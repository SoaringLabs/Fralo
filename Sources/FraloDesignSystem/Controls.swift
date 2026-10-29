import AppKit

@MainActor
public class NativeActionButton: NSButton {
    public typealias Role = ActionButton.Role
    public var onPress: (() -> Void)?
    private var available = true
    private var normalTitle: String
    public var isBusy = false {
        willSet { if newValue && !isBusy { normalTitle = title } }
        didSet { title = isBusy ? "处理中…" : normalTitle; super.isEnabled = available && !isBusy }
    }
    public override var isEnabled: Bool {
        get { super.isEnabled }
        set { available = newValue; super.isEnabled = newValue && !isBusy }
    }
    public init(_ title: String, role: Role = .secondary, onPress: (() -> Void)? = nil) {
        normalTitle = title; self.onPress = onPress
        super.init(frame: .zero)
        self.title = title; target = self; action = #selector(performAction(_:))
        bezelStyle = role == .quiet ? .inline : .rounded
        if role == .primary { bezelColor = .controlAccentColor; contentTintColor = .white }
        if role == .destructive { hasDestructiveAction = true }
        FraloStyle.configure(self)
    }
    required public init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func performAction(_ sender: Any?) { if isEnabled { onPress?() } }
}

@MainActor
public final class IconButton: ActionButton {
    public init(_ symbol: String, label: String, onPress: (() -> Void)? = nil) {
        super.init("", role: .quiet, size: .compact, symbol: symbol, label: label, onPress: onPress)
        toolTip = label
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

/// Circular symbol button for canvas and sidebar chrome. Every state reads at a glance: a soft circle
/// on hover (key window only), a deeper inset circle while pressed, and the accent tint when a toggle
/// is on. The owner sets a toggle's state; a click never leaves a stale “on” behind.
@MainActor
public final class SymbolButton: NSButton {
    public var onPress: (() -> Void)?
    public var preferences = DesignPreferences() { didSet { needsDisplay = true } }
    private let toggles: Bool
    private let symbol: NSImage?
    private var assignedState: NSControl.StateValue = .off
    private var tracking: NSTrackingArea?
    private var windowObservers: [NSObjectProtocol] = []
    var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    public init(_ symbol: String, label: String, toggles: Bool = false, onPress: (() -> Void)? = nil) {
        self.toggles = toggles; self.onPress = onPress
        self.symbol = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        super.init(frame: .zero)
        title = ""; image = nil; isBordered = false; focusRingType = .exterior
        setButtonType(toggles ? .pushOnPushOff : .momentaryPushIn)
        target = self; action = #selector(activate(_:))
        toolTip = label; setAccessibilityLabel(label)
        setAccessibilityElement(true); setAccessibilityRole(toggles ? .checkBox : .button)
        if toggles { setAccessibilityValue(false) }
        let side = FraloStyle.Button.compactHeight
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: side), heightAnchor.constraint(equalToConstant: side)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { windowObservers.forEach(NotificationCenter.default.removeObserver) }
    public override var alignmentRectInsets: NSEdgeInsets { .init(top: 0, left: 0, bottom: 0, right: 0) }
    public override var intrinsicContentSize: NSSize { NSSize(width: FraloStyle.Button.compactHeight, height: FraloStyle.Button.compactHeight) }
    public override var isEnabled: Bool { didSet { if !isEnabled { isHovered = false }; needsDisplay = true } }
    public override var state: NSControl.StateValue {
        didSet {
            assignedState = state; needsDisplay = true
            if toggles { setAccessibilityValue(state == .on) }
        }
    }
    @objc private func activate(_ sender: Any?) {
        if super.state != assignedState { super.state = assignedState; needsDisplay = true }
        if isEnabled { onPress?() }
    }
    /// Like native buttons, a mouse click acts without pulling keyboard focus off the canvas or a field.
    public override func becomeFirstResponder() -> Bool {
        if NSApp.currentEvent?.type == .leftMouseDown && !NSApp.isFullKeyboardAccessEnabled { return false }
        return super.becomeFirstResponder()
    }
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    public override func mouseEntered(with event: NSEvent) { isHovered = isEnabled }
    public override func mouseExited(with event: NSEvent) { isHovered = false }
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach(NotificationCenter.default.removeObserver); windowObservers.removeAll()
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isHovered = false }
            })
        }
    }
    public override func highlight(_ flag: Bool) { super.highlight(flag); needsDisplay = true }
    public override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    private var circle: NSRect {
        let side = min(bounds.width, bounds.height)
        return NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
    }
    public override var focusRingMaskBounds: NSRect { circle }
    public override func drawFocusRingMask() { NSBezierPath(ovalIn: circle).fill() }
    public override func draw(_ dirtyRect: NSRect) {
        let pressed = cell?.isHighlighted == true && isEnabled
        let on = toggles && state == .on, contrast = preferences.effectiveIncreaseContrast
        let accent = NSColor.controlAccentColor
        var fill: NSColor? = nil, edge: NSColor? = nil
        if isEnabled {
            if on { fill = accent.withAlphaComponent(pressed ? 0.30 : isHovered ? 0.22 : 0.15); edge = contrast ? accent : nil }
            else if pressed { fill = NSColor.labelColor.withAlphaComponent(0.16) }
            else if isHovered { fill = NSColor.labelColor.withAlphaComponent(0.08); edge = contrast ? NSColor.labelColor.withAlphaComponent(0.5) : nil }
        }
        // Pressing tucks the circle in by a point, so the click lands as a physical press.
        let surface = NSBezierPath(ovalIn: circle.insetBy(dx: pressed ? 1.5 : 0.5, dy: pressed ? 1.5 : 0.5))
        if let fill { fill.setFill(); surface.fill() }
        if let edge { edge.setStroke(); surface.lineWidth = 1; surface.stroke() }
        guard let symbol else { return }
        let ink: NSColor = !isEnabled ? .tertiaryLabelColor : on ? accent : pressed ? .labelColor : NSColor.labelColor.withAlphaComponent(0.82)
        let size = symbol.size, rect = NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        let tinted = NSImage(size: size, flipped: false) { target in
            symbol.draw(in: target); ink.setFill(); target.fill(using: .sourceIn); return true
        }
        tinted.draw(in: rect.integral)
    }
}

@MainActor
public final class ChoiceMenu: NSPopUpButton {
    public var onChange: ((Int) -> Void)?
    public var showsSurface = true { didSet { needsDisplay = true } }
    public var displayTitle: String? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    public var leadingSymbol: String? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    public init(_ titles: [String], label: String, selected: Int = 0, onChange: ((Int) -> Void)? = nil) {
        self.onChange = onChange
        super.init(frame: .zero, pullsDown: false)
        addItems(withTitles: titles)
        if titles.indices.contains(selected) { selectItem(at: selected) }
        target = self; action = #selector(changed(_:)); setAccessibilityLabel(label)
        isBordered = false; font = .systemFont(ofSize: 14, weight: .medium)
        focusRingType = .exterior
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func changed(_ sender: Any?) { needsDisplay = true; if isEnabled { onChange?(indexOfSelectedItem) } }
    public override var intrinsicContentSize: NSSize {
        let text = displayTitle ?? titleOfSelectedItem ?? ""
        return NSSize(width: ceil((text as NSString).size(withAttributes: [.font: font ?? FraloStyle.TextRole.body.font]).width) + (leadingSymbol == nil && image == nil ? 38 : 62), height: 32)
    }
    public override var alignmentRectInsets: NSEdgeInsets { .init(top: 0, left: 0, bottom: 0, right: 0) }
    public override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    public override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        if showsSurface {
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            NSColor.white.withAlphaComponent(isEnabled ? (dark ? 0.055 : 0.72) : 0.025).setFill(); path.fill()
            NSColor.labelColor.withAlphaComponent(0.09).setStroke(); path.lineWidth = 0.5; path.stroke()
        }
        let ink: NSColor = isEnabled ? .labelColor : .disabledControlTextColor
        var leading: CGFloat = 11
        if let image = leadingSymbol.flatMap({ NSImage(systemSymbolName: $0, accessibilityDescription: nil) }) ?? image {
            let target = NSRect(x: 10, y: bounds.midY - 9, width: 18, height: 18)
            let tinted = NSImage(size: target.size, flipped: false) { rect in
                let scale = min(rect.width / max(1, image.size.width), rect.height / max(1, image.size.height))
                let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: NSRect(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2, width: size.width, height: size.height))
                ink.setFill(); rect.fill(using: .sourceIn); return true
            }
            tinted.draw(in: target); leading = 36
        }
        let text = displayTitle ?? titleOfSelectedItem ?? ""
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? FraloStyle.TextRole.body.font, .foregroundColor: ink]
        var arrowX = bounds.maxX - 17
        if !showsSurface && leading == 11 {
            // A bare readout keeps its value and chevron together as one centered label.
            let width = min(ceil((text as NSString).size(withAttributes: attributes).width), bounds.width - 38)
            leading = max(11, (bounds.width - width - 16) / 2); arrowX = leading + width + 6
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        var textAttributes = attributes; textAttributes[.paragraphStyle] = paragraph
        (text as NSString).draw(in: NSRect(x: leading, y: bounds.midY - 8, width: max(0, arrowX - leading - 4), height: 19), withAttributes: textAttributes)
        if let arrow = NSImage(systemSymbolName: showsSurface ? "chevron.up.chevron.down" : "chevron.down", accessibilityDescription: nil) {
            let tinted = NSImage(size: NSSize(width: 10, height: 12), flipped: false) { target in
                let scale = min(target.width / max(1, arrow.size.width), target.height / max(1, arrow.size.height))
                let size = NSSize(width: arrow.size.width * scale, height: arrow.size.height * scale)
                arrow.draw(in: NSRect(x: (target.width - size.width) / 2, y: (target.height - size.height) / 2, width: size.width, height: size.height))
                (self.showsSurface ? NSColor.controlAccentColor : ink).setFill(); target.fill(using: .sourceIn); return true
            }
            tinted.draw(in: NSRect(x: arrowX, y: bounds.midY - 6, width: 10, height: 12))
        }
    }
    public override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }
    public override func drawFocusRingMask() { NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 8, yRadius: 8).fill() }
}

@MainActor
private final class TrackingSlider: NSSlider {
    var onEditingChanged: ((Bool) -> Void)?
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        onEditingChanged?(true)
        defer { onEditingChanged?(false) }
        super.mouseDown(with: event)
    }
}

@MainActor
public final class SliderRow: NSStackView {
    public let slider: NSSlider
    public let valueField: ValueField
    public let validationLabel = FraloStyle.paragraph("")
    public var onEditingChanged: ((Bool) -> Void)?
    public var valueLabel: NSTextField { valueField }
    public var onChange: ((Double) -> Void)?
    public var isEnabled: Bool {
        get { slider.isEnabled }
        set { slider.isEnabled = newValue; valueField.isEnabled = newValue; valueLabel.textColor = newValue ? .labelColor : .disabledControlTextColor }
    }
    public var value: Double {
        get { slider.doubleValue }
        set { setValue(newValue, notify: false) }
    }
    public init(_ title: String, range: ClosedRange<Double>, value: Double, onChange: ((Double) -> Void)? = nil) {
        precondition(range.lowerBound.isFinite && range.upperBound.isFinite)
        slider = TrackingSlider(value: range.lowerBound, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        self.onChange = onChange
        valueField = ValueField(label: title + "百分比", value: value, range: range)
        super.init(frame: .zero)
        valueField.onCommit = { [weak self] in self?.setValue($0, notify: true) }
        (slider as? TrackingSlider)?.onEditingChanged = { [weak self] in self?.onEditingChanged?($0) }
        validationLabel.textColor = .systemRed; validationLabel.isHidden = true
        valueField.onValidationChange = { [weak self] message in
            self?.validationLabel.stringValue = message ?? ""; self?.validationLabel.isHidden = message == nil
        }
        orientation = .vertical; alignment = .leading; spacing = 6
        let label = FraloStyle.text(title); label.font = .systemFont(ofSize: 13, weight: .medium)
        addArrangedSubview(label)
        let suffix = FraloStyle.text("%", role: .detail, secondary: true)
        let row = FraloStyle.stack([slider, valueField, suffix], axis: .horizontal, spacing: 5)
        addArrangedSubview(row); row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        addArrangedSubview(validationLabel); validationLabel.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        valueLabel.alignment = .right; valueLabel.widthAnchor.constraint(equalToConstant: 56).isActive = true
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.target = self; slider.action = #selector(changed(_:)); slider.isContinuous = true
        slider.setAccessibilityLabel(title)
        setValue(value, notify: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    public func setValue(_ value: Double, notify: Bool) {
        guard value.isFinite, !notify || isEnabled else { return }
        let next = min(slider.maxValue, max(slider.minValue, value)); let changed = next != slider.doubleValue
        slider.doubleValue = next; valueField.restore(next)
        if notify && changed { onChange?(next) }
    }
    @objc private func changed(_ sender: Any?) { valueField.restore(value); if isEnabled { onChange?(value) } }
}

@MainActor
public final class ValueField: NSTextField, NSTextFieldDelegate {
    public var onCommit: ((Double) -> Void)?
    public var onValidationChange: ((String?) -> Void)?
    public private(set) var validationMessage: String?
    public private(set) var value: Double
    private let range: ClosedRange<Double>
    private let numbers: NumberFormatter
    private let rangeHelp: String
    public init(label: String, value: Double, range: ClosedRange<Double>, locale: Locale = .current, onCommit: ((Double) -> Void)? = nil) {
        self.range = range; self.value = min(range.upperBound, max(range.lowerBound, value)); self.onCommit = onCommit
        numbers = NumberFormatter(); numbers.locale = locale; numbers.numberStyle = .decimal
        numbers.usesGroupingSeparator = false; numbers.minimumFractionDigits = 0; numbers.maximumFractionDigits = 1
        rangeHelp = "请输入 " + (numbers.string(from: NSNumber(value: range.lowerBound)) ?? "") + "–" + (numbers.string(from: NSNumber(value: range.upperBound)) ?? "") + " 之间的数值。"
        super.init(frame: .zero)
        stringValue = display(self.value); delegate = self; setAccessibilityLabel(label)
        toolTip = rangeHelp; setAccessibilityHelp(rangeHelp)
        FraloStyle.configure(self); font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular); bezelStyle = .roundedBezel
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    public func restore(_ next: Double) {
        guard next.isFinite else { return }; value = min(range.upperBound, max(range.lowerBound, next))
        stringValue = display(value); showValidation(nil)
    }
    @discardableResult public func commit() -> Bool {
        guard isEnabled else { return false }
        let text = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        // Parse the whole input: NumberFormatter alone can accept a valid prefix of invalid text.
        let separator = NSRegularExpression.escapedPattern(for: numbers.decimalSeparator ?? ".")
        let pattern = "^[+-]?(?:[0-9]+(?:" + separator + "[0-9]*)?|" + separator + "[0-9]+)$"
        guard text.range(of: pattern, options: .regularExpression) != nil,
              let parsed = numbers.number(from: text)?.doubleValue, parsed.isFinite, range.contains(parsed) else {
            stringValue = display(value); showValidation(rangeHelp)
            NSAccessibility.post(element: self, notification: .announcementRequested,
                                 userInfo: [.announcement: rangeHelp, .priority: NSAccessibilityPriorityLevel.high.rawValue])
            return false
        }
        // Leaving the rounded display must not quantize an untouched continuous slider value.
        if text == display(value) { showValidation(nil); return true }
        let changed = parsed != value; restore(parsed)
        if changed { onCommit?(parsed) }; return true
    }
    public func controlTextDidEndEditing(_ obj: Notification) { _ = commit() }
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { restore(value); return true }
        return false
    }
    private func display(_ value: Double) -> String { numbers.string(from: NSNumber(value: value)) ?? String(value) }
    private func showValidation(_ message: String?) {
        validationMessage = message; toolTip = message ?? rangeHelp; setAccessibilityHelp(message ?? rangeHelp)
        onValidationChange?(message)
    }
}

@MainActor
public final class ColorChoice: NSColorWell {
    public var onChange: ((NSColor) -> Void)?
    public init(label: String, color: NSColor, onChange: ((NSColor) -> Void)? = nil) {
        self.onChange = onChange
        super.init(frame: .zero)
        self.color = color; target = self; action = #selector(changed(_:)); setAccessibilityLabel(label)
        widthAnchor.constraint(equalToConstant: 64).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func changed(_ sender: Any?) { onChange?(color) }
}

@MainActor
public final class BackgroundSwatch: NativeActionButton {
    public var isSelected = false { didSet { state = isSelected ? .on : .off; setAccessibilityValue(isSelected ? 1 : 0) } }
    public init(_ title: String, image: NSImage? = nil, onSelect: (() -> Void)? = nil) {
        super.init(title, onPress: onSelect)
        self.image = image; imagePosition = .imageAbove; imageScaling = .scaleProportionallyDown
        setButtonType(.pushOnPushOff); setAccessibilityRole(.radioButton)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

@MainActor
public final class SwatchPicker: NSStackView {
    public let buttons: [BackgroundSwatch]
    public var onSelection: ((Int) -> Void)?
    public private(set) var selectedIndex = 0
    public init(_ choices: [(String, NSImage?)]) {
        buttons = choices.map { BackgroundSwatch($0.0, image: $0.1) }
        super.init(frame: .zero)
        orientation = .horizontal; alignment = .centerY; spacing = 12
        setAccessibilityElement(true); setAccessibilityRole(.radioGroup); setAccessibilityLabel("背景选择")
        for (index, button) in buttons.enumerated() {
            addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: 100).isActive = true
            button.heightAnchor.constraint(equalToConstant: 85).isActive = true
            button.onPress = { [weak self] in self?.select(index, notify: true) }
        }
        select(0, notify: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    public func select(_ index: Int, notify: Bool = false) {
        guard buttons.indices.contains(index), !notify || buttons[index].isEnabled else { return }
        let changed = index != selectedIndex; selectedIndex = index
        buttons.enumerated().forEach { $0.element.isSelected = $0.offset == index }
        if notify && changed { onSelection?(index) }
    }
}

@MainActor
public final class ToggleControl: NSButton {
    public var onChange: ((Bool) -> Void)?
    public var value: Bool { get { state == .on } set { state = newValue ? .on : .off } }
    public init(_ title: String, value: Bool, onChange: ((Bool) -> Void)? = nil) {
        self.onChange = onChange; super.init(frame: .zero)
        self.title = title; setButtonType(.switch); self.value = value
        target = self; action = #selector(changed(_:)); FraloStyle.configure(self)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func changed(_ sender: Any?) { if isEnabled { onChange?(value) } }
}

@MainActor
public final class ExportAction: NSStackView {
    public let primary = ActionButton("导出全部 · 0 张", role: .primary, symbol: "square.and.arrow.up")
    public let disclosure = ActionButton("", role: .primary, symbol: "chevron.down", label: "更多导出操作")
    public var onExportAll: (() -> Void)?
    public var onExportCurrent: (() -> Void)?
    public var count = 0 { didSet { primary.title = "导出全部 · \(count) 张"; refresh() } }
    public var isEnabled = true { didSet { refresh() } }
    private let divider = NSView()
    public init(count: Int) {
        super.init(frame: .zero)
        orientation = .horizontal; alignment = .centerY; spacing = 0; distribution = .fill
        wantsLayer = true; layer?.cornerRadius = 20
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOffset = NSSize(width: 0, height: -4); layer?.shadowRadius = 7
        // Keep custom-drawn button content in its own backing when the window loses focus.
        primary.wantsLayer = true; disclosure.wantsLayer = true
        primary.drawsSurface = false; disclosure.drawsSurface = false
        divider.wantsLayer = true
        primary.font = .systemFont(ofSize: 13.5, weight: .semibold)
        addArrangedSubview(primary); addArrangedSubview(divider); addArrangedSubview(disclosure)
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: 40), primary.heightAnchor.constraint(equalTo: heightAnchor),
            disclosure.heightAnchor.constraint(equalTo: heightAnchor), disclosure.widthAnchor.constraint(equalToConstant: 34),
            divider.widthAnchor.constraint(equalToConstant: 1), divider.heightAnchor.constraint(equalToConstant: 24)])
        primary.setContentHuggingPriority(.defaultLow, for: .horizontal)
        primary.onPress = { [weak self] in self?.onExportAll?() }
        disclosure.onPress = { [weak self] in self?.showMenu() }
        self.count = count; primary.title = "导出全部 · \(count) 张"; refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    private func refresh() {
        primary.isEnabled = isEnabled && count > 0; disclosure.isEnabled = primary.isEnabled
        // A neutral capsule: near-black in light appearance, near-white in dark appearance.
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let tint = dark ? NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1) : NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        primary.primaryTint = tint; disclosure.primaryTint = tint
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let fill = ActionButton.primaryColors(accent: tint).background
            layer?.backgroundColor = (primary.isEnabled ? fill : NSColor.quaternaryLabelColor).cgColor
            layer?.shadowOpacity = primary.isEnabled ? 0.14 : 0
            divider.layer?.backgroundColor = (dark ? NSColor.black.withAlphaComponent(0.14) : NSColor.white.withAlphaComponent(0.18)).cgColor
        }
    }
    public override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh() }
    public func exportCurrent() { if isEnabled && count > 0 { onExportCurrent?() } }
    private func showMenu() {
        let menu = NSMenu()
        let current = NSMenuItem(title: "导出当前图片…", action: #selector(current(_:)), keyEquivalent: "")
        current.target = self; menu.addItem(current)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: disclosure.bounds.minY), in: disclosure)
    }
    @objc private func current(_ sender: Any?) { exportCurrent() }
}
