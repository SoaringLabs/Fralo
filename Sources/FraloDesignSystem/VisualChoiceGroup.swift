import AppKit

public struct VisualChoiceItem {
    public let title: String
    public let detail: String
    public let symbol: String
    public var image: NSImage?
    public init(_ title: String, detail: String = "", symbol: String = "photo", image: NSImage? = nil) {
        self.title = title; self.detail = detail; self.symbol = symbol; self.image = image
    }
}

/// A real radio group: images explain choices; mouse, keyboard and accessibility share one edit path.
@MainActor
public final class VisualChoiceGroup: NSControl {
    public enum Layout { case row, tiles(columns: Int, height: CGFloat) }
    private let arrangement: Layout
    private var cards: [VisualChoiceCard] = []
    private var selection: Int?
    public var onChange: ((Int) -> Void)?
    public var selectedIndex: Int? {
        get { selection }
        set { select(newValue, notify: false) }
    }
    public var preferences = DesignPreferences() { didSet { cards.forEach { $0.preferences = preferences } } }
    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { isEnabled }
    public override var isEnabled: Bool { didSet { cards.forEach { $0.isEnabled = isEnabled } } }
    private var columns: Int { if case .tiles(let count, _) = arrangement { return max(1, count) }; return 1 }
    private var rowHeight: CGFloat { if case .tiles(_, let height) = arrangement { return height }; return 72 }
    public override var intrinsicContentSize: NSSize {
        let rows = (cards.count + columns - 1) / columns
        return NSSize(width: 280, height: CGFloat(rows) * rowHeight + CGFloat(max(0, rows - 1)) * 8)
    }
    public init(_ items: [VisualChoiceItem], label: String, selected: Int? = 0,
                layout: Layout = .tiles(columns: 2, height: 112), captionsBelow: Bool = false, onChange: ((Int) -> Void)? = nil) {
        precondition(!items.isEmpty)
        arrangement = layout; selection = selected.flatMap { items.indices.contains($0) ? $0 : nil }; self.onChange = onChange
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.radioGroup); setAccessibilityLabel(label)
        for (index, item) in items.enumerated() {
            let card = VisualChoiceCard(item: item, horizontal: { if case .row = layout { return true }; return false }(), captionsBelow: captionsBelow)
            card.tag = index; card.target = self; card.action = #selector(pressed(_:))
            cards.append(card); addSubview(card)
        }
        setAccessibilityChildren(cards); focusRingType = .exterior
        select(selection, notify: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    public func setImages(_ images: [NSImage?]) {
        for (index, card) in cards.enumerated() where images.indices.contains(index) { card.artwork = images[index] }
    }
    public override func layout() {
        super.layout()
        let width = max(0, (bounds.width - CGFloat(columns - 1) * 8) / CGFloat(columns))
        for (index, card) in cards.enumerated() {
            card.frame = NSRect(x: CGFloat(index % columns) * (width + 8), y: CGFloat(index / columns) * (rowHeight + 8), width: width, height: rowHeight)
        }
    }
    @objc private func pressed(_ sender: NSButton) { window?.makeFirstResponder(self); choose(sender.tag) }
    public func choose(_ index: Int) { guard isEnabled else { return }; select(index, notify: true) }
    private func select(_ index: Int?, notify: Bool) {
        if let index, !cards.indices.contains(index) { return }
        let changed = index != selection; selection = index
        for (i, card) in cards.enumerated() {
            card.chosen = i == index; card.state = i == index ? .on : .off
            card.setAccessibilityValue(i == index ? 1 : 0)
        }
        needsDisplay = true
        if changed { NSAccessibility.post(element: self, notification: .valueChanged) }
        if changed && notify, let index { onChange?(index); sendAction(action, to: target) }
    }
    public override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        let current = selection ?? 0
        switch event.keyCode {
        case 48:
            if event.modifierFlags.contains(.shift) { window?.selectKeyView(preceding: self) }
            else { window?.selectKeyView(following: self) }
        case 123: choose(max(0, current - 1))
        case 124: choose(min(cards.count - 1, current + 1))
        case 126: choose(max(0, current - columns))
        case 125: choose(min(cards.count - 1, current + columns))
        case 49: choose((current + 1) % cards.count)
        default: super.keyDown(with: event)
        }
    }
    public override var focusRingMaskBounds: NSRect { selection.map { cards[$0].convert(cards[$0].surfaceBounds, to: self) } ?? bounds }
    public override func drawFocusRingMask() { NSBezierPath(roundedRect: focusRingMaskBounds.insetBy(dx: 2, dy: 2), xRadius: 12, yRadius: 12).fill() }
}

@MainActor
private final class VisualChoiceCard: NSButton {
    private let item: VisualChoiceItem
    private let horizontal: Bool
    private let captionsBelow: Bool
    private var hovered = false
    private var tracking: NSTrackingArea?
    var artwork: NSImage? { didSet { needsDisplay = true } }
    var chosen = false { didSet { needsDisplay = true } }
    var preferences = DesignPreferences() { didSet { needsDisplay = true } }
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    var surfaceBounds: NSRect { NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - (captionsBelow ? 24 : 0)) }
    init(item: VisualChoiceItem, horizontal: Bool, captionsBelow: Bool) {
        self.item = item; self.horizontal = horizontal; self.captionsBelow = captionsBelow && !horizontal; artwork = item.image
        super.init(frame: .zero)
        title = item.title; setButtonType(.pushOnPushOff); isBordered = false; refusesFirstResponder = true
        setAccessibilityElement(true); setAccessibilityRole(.radioButton)
        setAccessibilityLabel(item.title + (item.detail.isEmpty ? "" : "，" + item.detail)); toolTip = item.title
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func highlight(_ flag: Bool) { super.highlight(flag); needsDisplay = true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let rect = surfaceBounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        let pressed = cell?.isHighlighted == true && isEnabled
        let neutral = NSColor(white: dark ? 1 : 0, alpha: pressed ? 0.10 : hovered && isEnabled ? 0.075 : 0.035)
        let accented = chosen && isEnabled && !horizontal
        (accented ? NSColor.controlAccentColor.withAlphaComponent(dark ? 0.14 : 0.08) : neutral).setFill(); path.fill()
        (accented ? NSColor.controlAccentColor.withAlphaComponent(0.90) : NSColor.labelColor.withAlphaComponent(preferences.effectiveIncreaseContrast ? 0.65 : 0.09)).setStroke()
        path.lineWidth = accented || preferences.effectiveIncreaseContrast ? 1.5 : 0.5; path.stroke()
        let imageArea = horizontal ? NSRect(x: 14, y: 10, width: 56, height: bounds.height - 20)
            : captionsBelow ? surfaceBounds.insetBy(dx: 12, dy: 12)
            : NSRect(x: 12, y: 10, width: bounds.width - 24, height: max(20, bounds.height - 50))
        if let image = artwork ?? NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [.secondaryLabelColor])) {
            let scale = min(imageArea.width / max(1, image.size.width), imageArea.height / max(1, image.size.height))
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: NSRect(x: imageArea.midX - size.width / 2, y: imageArea.midY - size.height / 2, width: size.width, height: size.height),
                from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.35, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        }
        let textX: CGFloat = horizontal ? 84 : 8
        let textWidth = bounds.width - textX - (horizontal ? 34 : 8)
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = horizontal ? .left : .center; paragraph.lineBreakMode = .byTruncatingTail
        let y = horizontal ? bounds.midY - 16 : captionsBelow ? surfaceBounds.maxY + 5 : bounds.height - 36
        (item.title as NSString).draw(in: NSRect(x: textX, y: y, width: max(0, textWidth), height: 18),
            withAttributes: [.font: NSFont.systemFont(ofSize: horizontal ? 14 : 12, weight: chosen ? .semibold : .medium), .foregroundColor: isEnabled ? NSColor.labelColor : .disabledControlTextColor, .paragraphStyle: paragraph])
        (item.detail as NSString).draw(in: NSRect(x: textX, y: y + 18, width: max(0, textWidth), height: 15),
            withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph])
        if chosen && isEnabled, let mark = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [.white, .controlAccentColor])) {
            mark.draw(in: NSRect(x: bounds.width - 24, y: 10, width: 14, height: 14), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}
