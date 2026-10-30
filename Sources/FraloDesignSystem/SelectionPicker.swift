import AppKit

/// Native capsule artwork with separate content-navigation and parameter-selection semantics.
@MainActor
public final class ValuePicker: NSSegmentedControl {
    public enum Purpose { case tabs, valueSelection }
    public let purpose: Purpose
    private var selection: Int
    private var accessibilityOptions: [SegmentAccessibility] = []
    private var optionFocus: Int?
    public var onChange: ((Int) -> Void)?
    public var selectedIndex: Int {
        get { selection }
        set {
            guard (0..<segmentCount).contains(newValue) else { return }
            let previous = selection
            selection = newValue; selectedSegment = newValue
            if previous != selection {
                optionFocus = selection
                notifySelection(from: previous)
            }
        }
    }
    public override var acceptsFirstResponder: Bool { isEnabled }
    /// The selector is one key view; its owned AX option objects are not NSViews.
    public override var canBecomeKeyView: Bool { isEnabled && !isHiddenOrHasHiddenAncestor && window != nil }
    public override var isEnabled: Bool {
        didSet {
            if oldValue != isEnabled {
                NSAccessibility.post(element: self, notification: .layoutChanged)
            }
        }
    }

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
        trackingMode = .selectOne; isContinuous = false
        segmentStyle = .automatic; segmentDistribution = .fillEqually
        controlSize = size
        if #available(macOS 26.0, *) { borderShape = .capsule }
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) { role = .tabs }
        #endif
        selectedSegment = selection
        setAccessibilityLabel(label)
        accessibilityOptions = titles.indices.map { SegmentAccessibility(owner: self, index: $0) }
        setAccessibilityElement(true); setAccessibilityOrientation(.horizontal)
        target = self; action = #selector(commitSelection(_:))
        focusRingType = .exterior
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    /// All native, keyboard and accessibility actions cross the same single-edit boundary.
    public override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        guard isEnabled, (0..<segmentCount).contains(selectedSegment),
              isEnabled(forSegment: selectedSegment), selectedSegment != selection else {
            selectedSegment = selection
            return false
        }
        let previous = selection
        selection = selectedSegment; optionFocus = selection
        notifySelection(from: previous)
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
        optionFocus = selection
        focusRingType = .none
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
    public override func becomeFirstResponder() -> Bool {
        if NSApp.currentEvent?.type == .keyDown { focusRingType = .exterior }
        let accepted = super.becomeFirstResponder()
        if accepted {
            scrollToVisible(optionRect(optionFocus ?? selection))
            notifyOptionFocus()
        }
        return accepted
    }
    public override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { optionFocus = nil }
        return accepted
    }
    public override func keyDown(with event: NSEvent) {
        focusRingType = .exterior
        if event.keyCode == 48 {
            if event.modifierFlags.contains(.shift) { window?.selectKeyView(preceding: self) }
            else { window?.selectKeyView(following: self) }
            return
        }
        guard isEnabled else { return }
        let current = optionFocus ?? selection
        switch event.keyCode {
        case 123, 126: move(from: current - 1, direction: -1)
        case 124, 125: move(from: current + 1, direction: 1)
        case 115: move(from: 0, direction: 1)
        case 119: move(from: segmentCount - 1, direction: -1)
        case 49: choose(current)
        default: super.keyDown(with: event)
        }
    }
    private func move(from start: Int, direction: Int) {
        var index = start
        while (0..<segmentCount).contains(index) {
            if isEnabled(forSegment: index) { choose(index); return }
            index += direction
        }
    }

    // Once AX is overridden, both purposes own their tree; NSView super getters do not expose cell AX.
    public override func accessibilityRole() -> NSAccessibility.Role? {
        purpose == .valueSelection ? .radioGroup : .tabGroup
    }
    public override func accessibilityRoleDescription() -> String? {
        accessibilityRole()?.description(with: nil)
    }
    public override func accessibilitySubrole() -> NSAccessibility.Subrole? {
        nil
    }
    public override func accessibilityChildren() -> [Any]? {
        accessibilityOptions
    }
    // Nil uses our owned child order instead of an inherited native cell navigation list.
    public override func accessibilityChildrenInNavigationOrder() -> [any NSAccessibilityElementProtocol]? {
        nil
    }
    public override func accessibilityVisibleChildren() -> [Any]? {
        accessibilityOptions.filter { optionRect($0.index).intersects(visibleRect) && !isHiddenOrHasHiddenAncestor }
    }
    public override func accessibilitySelectedChildren() -> [Any]? {
        accessibilityOptions.filter { $0.index == selection }
    }
    public override func accessibilityTabs() -> [Any]? {
        purpose == .tabs ? accessibilityOptions : nil
    }
    public override var accessibilityFocusedUIElement: Any? {
        return isEnabled && window?.firstResponder === self ? accessibilityOptions.first { $0.index == (optionFocus ?? selection) && isEnabled(forSegment: $0.index) } : nil
    }
    public override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        guard !isHiddenOrHasHiddenAncestor else { return nil }
        return accessibilityOptions.first { option in
            let visible = optionRect(option.index).intersection(visibleRect)
            return !visible.isEmpty && screenRect(visible).contains(point)
        } ?? self
    }
    fileprivate func optionRect(_ index: Int) -> NSRect {
        // All consumers use fillEqually; frames remain live across resizing and scrolling.
        let width = bounds.width / CGFloat(segmentCount)
        return NSRect(x: bounds.minX + CGFloat(index) * width, y: bounds.minY, width: width, height: bounds.height)
    }
    fileprivate func screenRect(_ rect: NSRect) -> NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(rect, to: nil))
    }
    fileprivate func isOptionFocused(_ index: Int) -> Bool {
        isEnabled && isEnabled(forSegment: index) && window?.firstResponder === self && (optionFocus ?? selection) == index
    }
    fileprivate func focusOption(_ index: Int) {
        guard isEnabled, (0..<segmentCount).contains(index), isEnabled(forSegment: index), let window else { return }
        optionFocus = index; focusRingType = .exterior
        scrollToVisible(optionRect(index))
        window.makeFirstResponder(self)
        notifyOptionFocus()
    }
    private func notifySelection(from previous: Int) {
        for option in accessibilityOptions where option.index == previous || option.index == selection {
            NSAccessibility.post(element: option, notification: .valueChanged)
        }
        NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
        notifyOptionFocus()
    }
    private func notifyOptionFocus() {
        guard isEnabled, let window, window.isKeyWindow, window.firstResponder === self,
              let option = accessibilityOptions.first(where: { $0.index == (optionFocus ?? selection) && isEnabled(forSegment: $0.index) }) else { return }
        NSAccessibility.post(element: option, notification: .focusedUIElementChanged)
    }
}

/// Stable elements provide either radio or tab semantics independently of native artwork.
@MainActor
private final class SegmentAccessibility: NSAccessibilityElement {
    weak var owner: ValuePicker?
    let index: Int
    init(owner: ValuePicker, index: Int) {
        self.owner = owner; self.index = index
        super.init(); setAccessibilityElement(true)
    }
    override func accessibilityRole() -> NSAccessibility.Role? { .radioButton }
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { owner?.purpose == .tabs ? .tabButtonSubrole : nil }
    override func accessibilityRoleDescription() -> String? { accessibilityRole()?.description(with: accessibilitySubrole()) }
    override func accessibilityLabel() -> String? { owner?.label(forSegment: index) }
    override func accessibilityHelp() -> String? { owner?.toolTip(forSegment: index) }
    override func accessibilityParent() -> Any? { owner }
    override func accessibilityWindow() -> Any? { owner?.window }
    override func accessibilityTopLevelUIElement() -> Any? { owner?.window }
    override func accessibilityFrame() -> NSRect { owner.map { $0.screenRect($0.optionRect(index)) } ?? .zero }
    override func accessibilityValue() -> Any? { NSNumber(value: owner?.selectedIndex == index) }
    override func isAccessibilitySelected() -> Bool { owner?.selectedIndex == index }
    override func isAccessibilityEnabled() -> Bool { owner.map { $0.isEnabled && $0.isEnabled(forSegment: index) } ?? false }
    override func isAccessibilityFocused() -> Bool { owner?.isOptionFocused(index) ?? false }
    override func setAccessibilityFocused(_ focused: Bool) { if focused { owner?.focusOption(index) } }
    override func accessibilityPerformPress() -> Bool {
        guard isAccessibilityEnabled(), let owner else { return false }
        owner.choose(index)
        return true
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
