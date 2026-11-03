import AppKit

public struct VisualChoiceItem {
    public let title: String
    public let detail: String
    public let symbol: String
    public var image: NSImage?
    /// Unavailable choices stay visible (e.g. “即将支持”) but cannot be selected.
    public var isAvailable: Bool
    public init(_ title: String, detail: String = "", symbol: String = "photo", image: NSImage? = nil, available: Bool = true) {
        self.title = title; self.detail = detail; self.symbol = symbol; self.image = image; self.isAvailable = available
    }
}

/// A real radio group: images explain choices; mouse, keyboard and accessibility share one edit path.
@MainActor
public final class VisualChoiceGroup: NSControl {
    /// `options`: compact one-line cards (symbol, title, check) for choices that need no artwork.
    public enum Layout { case row, tiles(columns: Int, height: CGFloat), options(columns: Int) }
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
    private var columns: Int {
        switch arrangement {
        case .tiles(let count, _):
            let available = bounds.width > 0 ? bounds.width : 280
            let needed = cards.map { card in
                let title = (card.item.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width
                let detail = (card.item.detail as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10)]).width
                return max(title, detail) + 16
            }.max() ?? 0
            var result = max(1, count)
            while result > 1 && ((available - CGFloat(result - 1) * 8) / CGFloat(result) < needed ||
                                  (result < count && cards.count % result != 0)) {
                result -= 1
            }
            return result
        case .options(let count):
            let available = bounds.width > 0 ? bounds.width : 280
            let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
            let labelWidth = cards.map { ($0.item.title as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
            // The symbol and selection mark need 76 pt in addition to the complete title.
            var result = max(1, count)
            while result > 1 && (available - CGFloat(result - 1) * 8) / CGFloat(result) < labelWidth + 76 {
                result -= 1
            }
            return result
        case .row: return 1
        }
    }
    private var rowHeight: CGFloat {
        switch arrangement { case .tiles(_, let height): return height; case .options: return 44; case .row: return 72 }
    }
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
            let style: VisualChoiceCard.Style = { switch layout { case .row: return .row; case .options: return .option; case .tiles: return .tile } }()
            let card = VisualChoiceCard(item: item, style: style, captionsBelow: captionsBelow)
            card.tag = index; card.target = self; card.action = #selector(pressed(_:))
            cards.append(card); addSubview(card)
        }
        setAccessibilityChildren(cards); focusRingType = .exterior
        select(selection, notify: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    public func setCardToolTip(_ text: String, at index: Int) {
        guard cards.indices.contains(index) else { return }; cards[index].toolTip = text; cards[index].setAccessibilityHelp(text)
    }
        public func setImages(_ images: [NSImage?]) {
        for (index, card) in cards.enumerated() where images.indices.contains(index) { card.artwork = images[index] }
    }
    public override func setFrameSize(_ newSize: NSSize) {
        let previousColumns = columns
        super.setFrameSize(newSize)
        if previousColumns != columns { invalidateIntrinsicContentSize(); needsLayout = true }
    }
    public override func layout() {
        super.layout()
        let width = max(0, (bounds.width - CGFloat(columns - 1) * 8) / CGFloat(columns))
        for (index, card) in cards.enumerated() {
            card.frame = NSRect(x: CGFloat(index % columns) * (width + 8), y: CGFloat(index / columns) * (rowHeight + 8), width: width, height: rowHeight)
        }
    }
    @objc private func pressed(_ sender: NSButton) { focusRingType = .none; window?.makeFirstResponder(self); choose(sender.tag) }
    public override func becomeFirstResponder() -> Bool {
        // Only keyboard focus draws a ring; focus restored after a click (e.g. a rebuilt group) stays quiet.
        focusRingType = NSApp.currentEvent?.type == .keyDown ? .exterior : .none
        return super.becomeFirstResponder()
    }
    public func choose(_ index: Int) {
        guard isEnabled, cards.indices.contains(index), cards[index].item.isAvailable else { return }; select(index, notify: true)
    }
    private func select(_ index: Int?, notify: Bool) {
        if let index, !cards.indices.contains(index) { return }
        let changed = index != selection; selection = index
        for (i, card) in cards.enumerated() {
            card.chosen = i == index; card.state = i == index ? .on : .off
            card.setAccessibilityValue(i == index ? 1 : 0)
        }
        needsDisplay = true; noteFocusRingMaskChanged()
        if changed { NSAccessibility.post(element: self, notification: .valueChanged) }
        if changed && notify, let index { onChange?(index); sendAction(action, to: target) }
    }
    public override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        focusRingType = .exterior
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
    /// Inset so the ring stays inside the group; edge-aligned cards would otherwise lose it to the parent's clip.
    public override func drawFocusRingMask() { NSBezierPath(roundedRect: focusRingMaskBounds.insetBy(dx: 4, dy: 4), xRadius: 10, yRadius: 10).fill() }
}

@MainActor
private final class VisualChoiceCard: NSButton {
    enum Style { case tile, row, option }
    let item: VisualChoiceItem
    private let style: Style
    private var horizontal: Bool { style != .tile }
    private let captionsBelow: Bool
    private lazy var hoverFeedback = HoverFeedback(view: self)
    var artwork: NSImage? { didSet { needsDisplay = true } }
    var chosen = false { didSet { needsDisplay = true } }
    var preferences = DesignPreferences() { didSet { refreshHover(); needsDisplay = true } }
    override var isEnabled: Bool { didSet { refreshHover(); needsDisplay = true } }
    override var isFlipped: Bool { true }
    var surfaceBounds: NSRect { NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - (captionsBelow ? 24 : 0)) }
    init(item: VisualChoiceItem, style: Style, captionsBelow: Bool) {
        self.item = item; self.style = style; self.captionsBelow = captionsBelow && style == .tile; artwork = item.image
        super.init(frame: .zero)
        title = item.title; setButtonType(.pushOnPushOff); isBordered = false; refusesFirstResponder = true
        setAccessibilityElement(true); setAccessibilityRole(.radioButton)
        setAccessibilityLabel(item.title + (item.detail.isEmpty ? "" : "，" + item.detail)); toolTip = item.title
        if !item.isAvailable { setAccessibilityEnabled(false) }
        refreshHover()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func highlight(_ flag: Bool) { super.highlight(flag); needsDisplay = true }
    private func refreshHover() { hoverFeedback.update(enabled: isEnabled && item.isAvailable, preferences: preferences) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); hoverFeedback.viewDidMoveToWindow() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); hoverFeedback.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hoverFeedback.enter() }
    override func mouseExited(with event: NSEvent) { hoverFeedback.exit() }
    override func draw(_ dirtyRect: NSRect) {
        if !item.isAvailable {
            // Dim the whole card, including its caption, like a disabled control.
            NSGraphicsContext.current?.cgContext.setAlpha(0.42)
        }
        if style == .option { drawOption(); return }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let rect = surfaceBounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        let pressed = cell?.isHighlighted == true && isEnabled && item.isAvailable
        let neutral = NSColor(white: dark ? 1 : 0, alpha: pressed ? 0.10 : 0.035 + (0.075 - 0.035) * hoverFeedback.amount)
        let accented = chosen && isEnabled && !horizontal
        // Selection keeps a neutral fill; the accent ring and check carry the state.
        (accented ? NSColor(white: dark ? 1 : 0, alpha: dark ? 0.09 : 0.06) : neutral).setFill(); path.fill()
        (accented ? NSColor.controlAccentColor.withAlphaComponent(0.90) : NSColor.labelColor.withAlphaComponent(preferences.effectiveIncreaseContrast ? 0.65 : 0.09)).setStroke()
        path.lineWidth = accented || preferences.effectiveIncreaseContrast ? 1.5 : 0.5; path.stroke()
        // A tile without a detail line centers image and title as one block instead of leaving the detail row empty.
        let tileImageHeight = max(20, bounds.height - 50)
        let titleOnlyTile = !horizontal && !captionsBelow && item.detail.isEmpty
        let tileTop = titleOnlyTile ? max(10, (bounds.height - tileImageHeight - 22) / 2) : 10
        let imageArea = horizontal ? NSRect(x: 14, y: 10, width: 56, height: bounds.height - 20)
            : captionsBelow ? surfaceBounds.insetBy(dx: 12, dy: 12)
            : NSRect(x: 12, y: tileTop, width: bounds.width - 24, height: tileImageHeight)
        if let artwork {
            draw(artwork, fitting: imageArea)
        } else if let symbol = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: horizontal ? 22 : 17, weight: .regular).applying(.init(paletteColors: [.secondaryLabelColor]))) {
            // A placeholder symbol keeps its text-like size instead of filling the artwork area.
            let size = symbol.size
            symbol.draw(in: NSRect(x: imageArea.midX - size.width / 2, y: imageArea.midY - size.height / 2, width: size.width, height: size.height),
                from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.35, respectFlipped: true, hints: nil)
        }
        let textX: CGFloat = horizontal ? 84 : 8
        let textWidth = bounds.width - textX - (horizontal ? 34 : 8)
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = horizontal ? .left : .center; paragraph.lineBreakMode = .byTruncatingTail
        let y = horizontal ? bounds.midY - 16 : captionsBelow ? surfaceBounds.maxY + 5 : titleOnlyTile ? imageArea.maxY + 4 : bounds.height - 36
        (item.title as NSString).draw(in: NSRect(x: textX, y: y, width: max(0, textWidth), height: 18),
            withAttributes: [.font: NSFont.systemFont(ofSize: horizontal ? 14 : 12, weight: chosen ? .semibold : .medium), .foregroundColor: isEnabled ? NSColor.labelColor : .disabledControlTextColor, .paragraphStyle: paragraph])
        (item.detail as NSString).draw(in: NSRect(x: textX, y: y + 18, width: max(0, textWidth), height: 15),
            withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph])
        if chosen && isEnabled, let mark = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [.white, .controlAccentColor])) {
            // Narrow tiles tuck a smaller check into the corner so it covers less of the thumbnail.
            let compact = bounds.width < 80
            mark.draw(in: compact ? NSRect(x: bounds.width - 19, y: 6, width: 12, height: 12) : NSRect(x: bounds.width - 24, y: 10, width: 14, height: 14),
                      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
    private func draw(_ image: NSImage, fitting area: NSRect) {
        let scale = min(area.width / max(1, image.size.width), area.height / max(1, image.size.height))
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height),
            from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.35, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
    /// One-line choice: symbol, title and a trailing check, e.g. 竖屏 / 横屏.
    private func drawOption() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        let pressed = cell?.isHighlighted == true && isEnabled && item.isAvailable
        let accented = chosen && isEnabled
        let resting: CGFloat = dark ? 0.06 : 0.045
        let fill = accented ? NSColor(white: dark ? 1 : 0, alpha: dark ? 0.09 : 0.06)
            : NSColor(white: dark ? 1 : 0, alpha: pressed ? 0.10 : resting + (0.075 - resting) * hoverFeedback.amount)
        fill.setFill(); path.fill()
        if accented || preferences.effectiveIncreaseContrast {
            (accented ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.65)).setStroke()
            path.lineWidth = 1.5; path.stroke()
        }
        if let symbol = NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 17, weight: .regular).applying(.init(paletteColors: [isEnabled ? .secondaryLabelColor : .disabledControlTextColor]))) {
            let size = symbol.size
            symbol.draw(in: NSRect(x: 12 + (22 - size.width) / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let title = NSAttributedString(string: item.title, attributes: [
            .font: NSFont.systemFont(ofSize: 12.5, weight: .semibold),
            .foregroundColor: isEnabled ? NSColor.labelColor : .disabledControlTextColor, .paragraphStyle: paragraph])
        // Center the native text line itself; a fixed 18pt box put its glyphs above the symbols.
        let titleHeight = title.size().height
        title.draw(in: NSRect(x: 44, y: bounds.midY - titleHeight / 2,
                              width: max(0, bounds.width - 44 - 32), height: titleHeight))
        if accented, let mark = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [.white, .controlAccentColor])) {
            mark.draw(in: NSRect(x: bounds.width - 26, y: bounds.midY - 8, width: 16, height: 16), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}
