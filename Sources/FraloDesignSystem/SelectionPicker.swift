import AppKit

/// System segmented selection. Content switches and parameter choices retain distinct semantics.
@MainActor
public final class ValuePicker: NSSegmentedControl {
    public enum Purpose { case tabs, valueSelection }
    public let purpose: Purpose
    private var selection: Int
    public var onChange: ((Int) -> Void)?
    public var selectedIndex: Int {
        get { selection }
        set {
            guard (0..<segmentCount).contains(newValue) else { return }
            selection = newValue
            selectedSegment = newValue
        }
    }
    public override var acceptsFirstResponder: Bool { isEnabled }

    public init(_ titles: [String], label: String, selected: Int = 0,
                purpose: Purpose = .valueSelection, size: NSControl.ControlSize = .regular,
                onChange: ((Int) -> Void)? = nil) {
        precondition(!titles.isEmpty)
        self.purpose = purpose
        selection = min(max(selected, 0), titles.count - 1)
        self.onChange = onChange
        super.init(frame: .zero)
        segmentCount = titles.count
        for (index, title) in titles.enumerated() {
            setLabel(title, forSegment: index)
            setToolTip(title, forSegment: index)
        }
        trackingMode = .selectOne
        isContinuous = false
        segmentStyle = .automatic
        segmentDistribution = .fillEqually
        controlSize = size
        if #available(macOS 26.0, *) { borderShape = .capsule }
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) {
            role = purpose == .tabs ? .tabs : .valueSelection
        }
        #endif
        selectedSegment = selection
        setAccessibilityLabel(label)
        target = self; action = #selector(commitSelection(_:))
        focusRingType = .exterior
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    /// The native cell, accessibility, keyboard and programmatic input share this edit boundary.
    /// Restoration is silent; repeated/disabled selections never emit business edits or actions.
    public override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        guard isEnabled, (0..<segmentCount).contains(selectedSegment),
              isEnabled(forSegment: selectedSegment), selectedSegment != selection else {
            selectedSegment = selection
            return false
        }
        selection = selectedSegment
        onChange?(selection)
        return super.sendAction(action, to: target)
    }
    @objc private func commitSelection(_ sender: Any?) {}

    public func choose(_ index: Int) {
        guard isEnabled, (0..<segmentCount).contains(index), isEnabled(forSegment: index), index != selection else { return }
        selectedSegment = index
        _ = sendAction(action, to: target)
    }
    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        focusRingType = .none
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
    public override func becomeFirstResponder() -> Bool {
        if NSApp.currentEvent?.type == .keyDown { focusRingType = .exterior }
        return super.becomeFirstResponder()
    }
    public override func keyDown(with event: NSEvent) {
        focusRingType = .exterior
        if event.keyCode == 48 {
            if event.modifierFlags.contains(.shift) { window?.selectKeyView(preceding: self) }
            else { window?.selectKeyView(following: self) }
            return
        }
        guard isEnabled else { return }
        switch event.keyCode {
        case 123, 126: choose(max(0, selection - 1))
        case 124, 125: choose(min(segmentCount - 1, selection + 1))
        case 115: choose(0)
        case 119: choose(segmentCount - 1)
        case 49: choose((selection + 1) % segmentCount)
        default: super.keyDown(with: event)
        }
    }
}

/// Actual NSTabView retains system navigation semantics and keyboard behavior.
@MainActor
public final class InspectorTabs: NSTabView, NSTabViewDelegate {
    public enum Style { case standard, floating }
    private var navigation: ValuePicker?
    public var onSelection: ((Int) -> Void)?
    public init(_ pages: [(String, NSView)], style: Style = .standard) {
        // NSTabView lays out its chrome while adding items, before Auto Layout sizes it.
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        tabViewType = .topTabsBezelBorder; delegate = self
        for (index, page) in pages.enumerated() {
            let item = NSTabViewItem(identifier: index); item.label = page.0; item.view = page.1
            addTabViewItem(item)
        }
        if style == .floating {
            tabViewType = .noTabsNoBorder; drawsBackground = false
            let bar = ValuePicker(pages.map(\.0), label: "设置页面", purpose: .tabs, size: .large)
            bar.onChange = { [weak self] in self?.selectTabViewItem(at: $0) }
            navigation = bar; addSubview(bar)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    public func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        guard let tabViewItem else { return }
        let index = indexOfTabViewItem(tabViewItem)
        navigation?.selectedIndex = index; needsLayout = true; onSelection?(index)
    }
    public override func layout() {
        super.layout()
        guard let navigation else { return }
        let height = navigation.intrinsicContentSize.height
        let contentInset = height + 14
        navigation.frame = NSRect(x: 0, y: isFlipped ? 0 : bounds.height - height, width: bounds.width, height: height)
        selectedTabViewItem?.view?.frame = NSRect(x: 0, y: isFlipped ? contentInset : 0, width: bounds.width, height: max(0, bounds.height - contentInset))
    }
}
