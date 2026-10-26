import AppKit
import QuartzCore

/// Parameter selection, with radio-group semantics. Navigation uses InspectorTabs instead.
@MainActor
public final class ValuePicker: NSControl {
    private let indicator = NSView()
    private var buttons: [NSButton] = []
    private var selection: Int
    public var preferences = DesignPreferences()
    public var onChange: ((Int) -> Void)?
    public var selectedIndex: Int {
        get { selection }
        set { select(newValue, animated: false, notify: false) }
    }
    public override var isEnabled: Bool {
        didSet { buttons.forEach { $0.isEnabled = isEnabled }; needsDisplay = true }
    }
    public override var acceptsFirstResponder: Bool { isEnabled }
    public override var wantsUpdateLayer: Bool { true }
    public override var intrinsicContentSize: NSSize {
        let widths = buttons.map { $0.intrinsicContentSize.width + 20 }
        return NSSize(width: (widths.max() ?? 50) * CGFloat(buttons.count), height: 30)
    }

    public init(_ titles: [String], label: String, selected: Int = 0, onChange: ((Int) -> Void)? = nil) {
        precondition(!titles.isEmpty)
        selection = min(max(selected, 0), titles.count - 1)
        self.onChange = onChange
        super.init(frame: .zero)
        wantsLayer = true; indicator.wantsLayer = true
        addSubview(indicator)
        for (index, title) in titles.enumerated() {
            let button = NSButton(title: title, target: self, action: #selector(chooseButton(_:)))
            button.tag = index; button.setButtonType(.pushOnPushOff)
            button.isBordered = false; button.refusesFirstResponder = true
            button.font = .systemFont(ofSize: 13, weight: .medium)
            button.setAccessibilityRole(.radioButton)
            button.setAccessibilityElement(true)
            buttons.append(button); addSubview(button)
        }
        setAccessibilityElement(true); setAccessibilityRole(.radioGroup)
        setAccessibilityLabel(label); setAccessibilityChildren(buttons)
        focusRingType = .exterior
        select(selection, animated: false, notify: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    public override func layout() {
        super.layout()
        let width = bounds.width / CGFloat(buttons.count)
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height)
        }
        indicator.frame = indicatorFrame
    }
    private var indicatorFrame: NSRect {
        let width = bounds.width / CGFloat(buttons.count)
        return NSRect(x: CGFloat(selection) * width + 2, y: 2, width: max(0, width - 4), height: max(0, bounds.height - 4))
    }
    public override func updateLayer() {
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.12).cgColor
        layer?.cornerRadius = bounds.height / 2
        indicator.layer?.backgroundColor = NSColor.controlColor.cgColor
        indicator.layer?.cornerRadius = max(0, bounds.height / 2 - 2)
        indicator.layer?.borderWidth = preferences.effectiveIncreaseContrast ? 1 : 0.5
        indicator.layer?.borderColor = NSColor.separatorColor.cgColor
        indicator.alphaValue = isEnabled ? 1 : 0.45
    }
    public override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    public override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 15, yRadius: 15).fill() }
    public override var focusRingMaskBounds: NSRect { bounds }

    @objc private func chooseButton(_ sender: NSButton) {
        window?.makeFirstResponder(self)
        select(sender.tag, animated: true, notify: true)
    }
    /// Same path as mouse/keyboard input; repeated or invalid values never emit edits.
    public func choose(_ index: Int) { select(index, animated: true, notify: true) }
    private func select(_ index: Int, animated: Bool, notify: Bool) {
        guard buttons.indices.contains(index), !notify || isEnabled else { return }
        let changed = index != selection; selection = index
        for (index, button) in buttons.enumerated() {
            button.state = index == selection ? .on : .off
            button.setAccessibilityValue(index == selection ? 1 : 0)
        }
        if animated && changed && window != nil {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = FraloMotion.duration(.selection, preferences: preferences)
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                indicator.animator().frame = indicatorFrame
            }
        } else { indicator.frame = indicatorFrame }
        if changed { NSAccessibility.post(element: self, notification: .valueChanged) }
        if changed && notify { onChange?(selection); sendAction(action, to: target) }
    }
    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 126: choose(max(0, selection - 1))
        case 124, 125: choose(min(buttons.count - 1, selection + 1))
        case 115: choose(0)
        case 119: choose(buttons.count - 1)
        case 49: choose((selection + 1) % buttons.count)
        default: super.keyDown(with: event)
        }
    }
}

/// Actual NSTabView retains system navigation semantics and keyboard behavior.
@MainActor
public final class InspectorTabs: NSTabView, NSTabViewDelegate {
    public var onSelection: ((Int) -> Void)?
    public init(_ pages: [(String, NSView)]) {
        // NSTabView lays out its chrome while adding items, before Auto Layout sizes it.
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        tabViewType = .topTabsBezelBorder; delegate = self
        for (index, page) in pages.enumerated() {
            let item = NSTabViewItem(identifier: index); item.label = page.0; item.view = page.1
            addTabViewItem(item)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    public func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        guard let tabViewItem else { return }; onSelection?(indexOfTabViewItem(tabViewItem))
    }
}
