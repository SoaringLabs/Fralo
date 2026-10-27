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
            NSColor.controlBackgroundColor.withAlphaComponent(isEnabled ? 0.92 : 0.5).setFill(); path.fill()
            NSColor.separatorColor.withAlphaComponent(0.20).setStroke(); path.lineWidth = 0.5; path.stroke()
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
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: NSRect(x: leading, y: bounds.midY - 8, width: max(0, bounds.width - leading - 24), height: 19),
                               withAttributes: [.font: font ?? FraloStyle.TextRole.body.font, .foregroundColor: ink, .paragraphStyle: paragraph])
        if let arrow = NSImage(systemSymbolName: showsSurface ? "chevron.up.chevron.down" : "chevron.down", accessibilityDescription: nil) {
            let tinted = NSImage(size: NSSize(width: 10, height: 12), flipped: false) { target in
                let scale = min(target.width / max(1, arrow.size.width), target.height / max(1, arrow.size.height))
                let size = NSSize(width: arrow.size.width * scale, height: arrow.size.height * scale)
                arrow.draw(in: NSRect(x: (target.width - size.width) / 2, y: (target.height - size.height) / 2, width: size.width, height: size.height))
                (self.showsSurface ? NSColor.controlAccentColor : ink).setFill(); target.fill(using: .sourceIn); return true
            }
            tinted.draw(in: NSRect(x: bounds.maxX - 17, y: bounds.midY - 6, width: 10, height: 12))
        }
    }
    public override var focusRingMaskBounds: NSRect { bounds.insetBy(dx: 1, dy: 1) }
    public override func drawFocusRingMask() { NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 8, yRadius: 8).fill() }
}

@MainActor
public final class SliderRow: NSStackView {
    public let slider: NSSlider
    public let valueLabel = FraloStyle.text("")
    public var onChange: ((Double) -> Void)?
    private let format: (Double) -> String = { "\(Int($0.rounded()))%" }
    public var isEnabled: Bool {
        get { slider.isEnabled }
        set { slider.isEnabled = newValue; valueLabel.textColor = newValue ? .labelColor : .disabledControlTextColor }
    }
    public var value: Double {
        get { slider.doubleValue }
        set { setValue(newValue, notify: false) }
    }
    public init(_ title: String, range: ClosedRange<Double>, value: Double, onChange: ((Double) -> Void)? = nil) {
        precondition(range.lowerBound.isFinite && range.upperBound.isFinite)
        slider = NSSlider(value: range.lowerBound, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        self.onChange = onChange
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 6
        let label = FraloStyle.text(title); label.font = .systemFont(ofSize: 13, weight: .medium)
        addArrangedSubview(label)
        let row = FraloStyle.stack([slider, valueLabel], axis: .horizontal, spacing: 8)
        addArrangedSubview(row); row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        valueLabel.alignment = .right; valueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
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
        slider.doubleValue = next; valueLabel.stringValue = format(next)
        if notify && changed { onChange?(next) }
    }
    @objc private func changed(_ sender: Any?) { valueLabel.stringValue = format(value); if isEnabled { onChange?(value) } }
}

@MainActor
public final class ValueField: NSTextField, NSTextFieldDelegate {
    public var onCommit: ((Double) -> Void)?
    public private(set) var value: Double
    private let range: ClosedRange<Double>
    public init(label: String, value: Double, range: ClosedRange<Double>, onCommit: ((Double) -> Void)? = nil) {
        self.range = range; self.value = min(range.upperBound, max(range.lowerBound, value)); self.onCommit = onCommit
        super.init(frame: .zero)
        stringValue = String(self.value); delegate = self; setAccessibilityLabel(label)
        FraloStyle.configure(self)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @discardableResult public func commit() -> Bool {
        guard isEnabled, let parsed = Double(stringValue), parsed.isFinite, range.contains(parsed) else {
            stringValue = String(value); NSAccessibility.post(element: self, notification: .valueChanged); return false
        }
        let changed = parsed != value; value = parsed
        if changed { onCommit?(parsed) }; return true
    }
    public func controlTextDidEndEditing(_ obj: Notification) { _ = commit() }
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
    public init(count: Int) {
        super.init(frame: .zero)
        orientation = .horizontal; alignment = .centerY; spacing = 0
        wantsLayer = true; layer?.cornerRadius = 11
        primary.drawsSurface = false; disclosure.drawsSurface = false
        let divider = NSView(); divider.wantsLayer = true; divider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
        addArrangedSubview(primary); addArrangedSubview(divider); addArrangedSubview(disclosure)
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: 46), primary.heightAnchor.constraint(equalTo: heightAnchor),
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
        let accent = NSColor.controlAccentColor.blended(withFraction: 0.10, of: .black) ?? .controlAccentColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (primary.isEnabled ? accent : NSColor.quaternaryLabelColor).cgColor
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
