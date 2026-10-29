import AppKit
import QuartzCore

/// Parameter selection, with radio-group semantics. Navigation uses InspectorTabs instead.
@MainActor
public final class ValuePicker: NSControl {
    private let indicator = NSView()
    private var buttons: [NSButton] = []
    private var symbols: [String] = []
    private var isAnimatingSelection = false
    private var animationGeneration = 0
    private var selection: Int
    public var controlHeight: CGFloat = FraloStyle.Workbench.controlHeight {
        didSet { invalidateIntrinsicContentSize(); select(selection, animated: false, notify: false); needsLayout = true; needsDisplay = true }
    }
    public var preferences = DesignPreferences()
    public var onChange: ((Int) -> Void)?
    public var selectedIndex: Int {
        get { selection }
        set { if newValue != selection { select(newValue, animated: false, notify: false) } }
    }
    public override var isEnabled: Bool {
        didSet { buttons.forEach { $0.isEnabled = isEnabled }; needsDisplay = true }
    }
    public override var acceptsFirstResponder: Bool { isEnabled }
    public override var wantsUpdateLayer: Bool { true }
    public override var intrinsicContentSize: NSSize {
        let widths = buttons.map { $0.intrinsicContentSize.width + 20 }
        return NSSize(width: (widths.max() ?? 50) * CGFloat(buttons.count), height: controlHeight)
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
    public func setSymbols(_ names: [String]) { symbols = names; select(selection, animated: false, notify: false) }

    public override func layout() {
        super.layout()
        let width = bounds.width / CGFloat(buttons.count)
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height)
        }
        if !isAnimatingSelection { indicator.frame = indicatorFrame }
    }
    private var indicatorFrame: NSRect {
        let width = bounds.width / CGFloat(buttons.count)
        return NSRect(x: CGFloat(selection) * width + 2, y: 2, width: max(0, width - 4), height: max(0, bounds.height - 4))
    }
    public override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.backgroundColor = NSColor.black.withAlphaComponent(dark ? 0.12 : 0.045).cgColor
        layer?.cornerRadius = 8
        indicator.layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.13) : NSColor.white.withAlphaComponent(0.80)).cgColor
        indicator.layer?.cornerRadius = 6
        indicator.layer?.shadowColor = NSColor.black.cgColor
        indicator.layer?.shadowOpacity = preferences.effectiveIncreaseContrast ? 0 : 0.10
        indicator.layer?.shadowRadius = 3; indicator.layer?.shadowOffset = NSSize(width: 0, height: -1)
        indicator.layer?.borderWidth = preferences.effectiveIncreaseContrast ? 1 : 0.5
        indicator.layer?.borderColor = NSColor.separatorColor.cgColor
        indicator.alphaValue = isEnabled ? 1 : 0.45
    }
    public override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    public override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 15, yRadius: 15).fill() }
    public override var focusRingMaskBounds: NSRect { bounds }

    public override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if NSApp.currentEvent?.type == .keyDown { focusRingType = .exterior }
        return accepted
    }
    @objc private func chooseButton(_ sender: NSButton) {
        focusRingType = .none
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
            button.font = .systemFont(ofSize: controlHeight >= 40 ? 14 : controlHeight < 28 ? 12 : 13, weight: index == selection ? .semibold : .medium)
            let title = NSAttributedString(string: button.title, attributes: [.font: button.font!,
                .foregroundColor: index == selection ? NSColor.labelColor : NSColor.secondaryLabelColor])
            button.attributedTitle = title; button.attributedAlternateTitle = title
            if symbols.indices.contains(index) {
                let image = NSImage(systemSymbolName: symbols[index], accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))?
                    .withSymbolConfiguration(.init(paletteColors: [index == selection ? .controlAccentColor : .labelColor]))
                button.image = image; button.imagePosition = .imageLeft; button.imageHugsTitle = true
            }
            button.setAccessibilityValue(index == selection ? 1 : 0)
        }
        animationGeneration += 1
        let generation = animationGeneration
        if animated && changed && window != nil {
            isAnimatingSelection = true
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = FraloMotion.duration(.selection, preferences: preferences)
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                indicator.animator().frame = indicatorFrame
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.animationGeneration == generation else { return }
                    self.isAnimatingSelection = false; self.needsLayout = true
                }
            })
        } else { isAnimatingSelection = false; indicator.frame = indicatorFrame }
        if changed { NSAccessibility.post(element: self, notification: .valueChanged) }
        if changed && notify { onChange?(selection); sendAction(action, to: target) }
    }
    public override func keyDown(with event: NSEvent) {
        focusRingType = .exterior
        switch event.keyCode {
        case 48:
            if event.modifierFlags.contains(.shift) { window?.selectKeyView(preceding: self) }
            else { window?.selectKeyView(following: self) }
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
            let bar = ValuePicker(pages.map(\.0), label: "设置页面")
            bar.controlHeight = 34
            bar.setSymbols(["iphone", "photo", "square.and.arrow.up"])
            bar.setAccessibilityRole(.tabGroup)
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
        navigation.frame = NSRect(x: 0, y: isFlipped ? 0 : bounds.height - 34, width: bounds.width, height: 34)
        selectedTabViewItem?.view?.frame = NSRect(x: 0, y: isFlipped ? 48 : 0, width: bounds.width, height: max(0, bounds.height - 48))
    }
}
