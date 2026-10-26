#if FRALO_DEV
import AppKit
import FraloDesignSystem

/// A real NSButton with an experimental skin. Promote only after visual acceptance.
@MainActor
final class SoftButton: NSButton {
    let role: ActionButton.Role
    var onPress: (() -> Void)?
    var preferences = DesignPreferences() { didSet { refresh() } }
    private let symbol: NSImage?
    private let accessibleName: String
    private let activity = NSProgressIndicator()
    private var requestedEnabled = true
    private var tracking: NSTrackingArea?
    private var windowObservers: [NSObjectProtocol] = []
    private(set) var isHovered = false
    var isBusy = false { didSet { super.isEnabled = requestedEnabled && !isBusy; refresh() } }
    override var isEnabled: Bool {
        get { super.isEnabled }
        set { requestedEnabled = newValue; super.isEnabled = newValue && !isBusy; refresh() }
    }
    override var acceptsFirstResponder: Bool { isEnabled }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        if title.isEmpty { return NSSize(width: 34, height: 34) }
        let width = (title as NSString).size(withAttributes: [.font: font ?? .systemFont(ofSize: 13, weight: .medium)]).width
        return NSSize(width: ceil(width) + 32 + (symbol == nil ? 0 : 24), height: 34)
    }

    init(_ title: String, role: ActionButton.Role = .secondary, symbol: String? = nil,
         label: String? = nil, onPress: (() -> Void)? = nil) {
        self.role = role; self.onPress = onPress; accessibleName = label ?? title
        self.symbol = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        super.init(frame: .zero)
        self.title = title; font = .systemFont(ofSize: 13, weight: .medium)
        setButtonType(.momentaryPushIn); isBordered = false
        target = self; action = #selector(activate(_:)); focusRingType = .exterior
        hasDestructiveAction = role == .destructive; toolTip = accessibleName
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel(accessibleName)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        activity.style = .spinning; activity.controlSize = .small; activity.isDisplayedWhenStopped = false
        addSubview(activity); refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { windowObservers.forEach(NotificationCenter.default.removeObserver) }

    @objc private func activate(_ sender: Any?) { if isEnabled && !isBusy { onPress?() } }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 {
            if event.modifierFlags.contains(.shift) { window?.selectKeyView(preceding: self) }
            else { window?.selectKeyView(following: self) }
        } else { super.keyDown(with: event) }
    }
    override func highlight(_ flag: Bool) { super.highlight(flag); needsDisplay = true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach(NotificationCenter.default.removeObserver); windowObservers.removeAll()
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isHovered = false; self?.needsDisplay = true }
            })
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { isHovered = isEnabled; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
    override func layout() {
        super.layout()
        let x: CGFloat = title.isEmpty || symbol == nil ? bounds.midX - 7 : 16
        activity.frame = NSRect(x: x, y: bounds.midY - 7, width: 14, height: 14)
    }
    private func refresh() {
        if !isEnabled { isHovered = false }
        setAccessibilityLabel(accessibleName + (isBusy ? "，正在处理" : ""))
        if isBusy && !preferences.effectiveReduceMotion { activity.startAnimation(nil) }
        else { activity.stopAnimation(nil) }
        activity.isHidden = !isBusy || preferences.effectiveReduceMotion
        needsLayout = true; needsDisplay = true
    }
    private var surfaceRect: NSRect { bounds.insetBy(dx: 2, dy: 2) }
    override var focusRingMaskBounds: NSRect { surfaceRect }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: surfaceRect, xRadius: 9, yRadius: 9).fill() }

    override func draw(_ dirtyRect: NSRect) {
        let pressed = cell?.isHighlighted == true && isEnabled
        let contrast = preferences.effectiveIncreaseContrast
        let path = NSBezierPath(roundedRect: surfaceRect, xRadius: 9, yRadius: 9)
        let base = NSColor.controlBackgroundColor.blended(withFraction: 0.32, of: .windowBackgroundColor) ?? .controlBackgroundColor
        var fill = base, edge = NSColor.separatorColor, ink = NSColor.labelColor
        var hasSurface = true
        switch role {
        case .primary:
            fill = NSColor.controlAccentColor.blended(withFraction: 0.20, of: .black) ?? .controlAccentColor
            if isHovered { fill = fill.blended(withFraction: 0.04, of: .white) ?? fill }
            if pressed { fill = fill.blended(withFraction: 0.13, of: .black) ?? fill }
            edge = fill.blended(withFraction: 0.18, of: .black) ?? fill
            ink = Self.contrastingText(on: fill)
        case .secondary:
            if isHovered { fill = fill.blended(withFraction: 0.06, of: .labelColor) ?? fill }
            if pressed { fill = fill.blended(withFraction: 0.12, of: .labelColor) ?? fill }
        case .quiet:
            hasSurface = isHovered || pressed
            fill = base.blended(withFraction: pressed ? 0.15 : 0.07, of: .labelColor) ?? base
            edge = .clear
        case .destructive:
            ink = .systemRed
            edge = NSColor.systemRed.withAlphaComponent(contrast ? 0.8 : 0.24)
            if isHovered || pressed { fill = base.blended(withFraction: pressed ? 0.17 : 0.08, of: .systemRed) ?? base }
        }
        if !isEnabled {
            fill = base; edge = .separatorColor; ink = .disabledControlTextColor
            hasSurface = role != .quiet
        }
        if hasSurface {
            NSGraphicsContext.saveGraphicsState()
            if isEnabled && !pressed && !contrast && role != .quiet {
                let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
                shadow.shadowOffset = NSSize(width: 0, height: 1); shadow.shadowBlurRadius = 2; shadow.set()
            }
            fill.setFill(); path.fill(); NSGraphicsContext.restoreGraphicsState()
            if isEnabled && !pressed && !contrast && role != .quiet {
                let highlight = NSGradient(starting: NSColor.white.withAlphaComponent(role == .primary ? 0.06 : 0.08), ending: .clear)
                highlight?.draw(in: path, angle: -90)
            }
            edge.setStroke(); path.lineWidth = contrast ? 1.25 : 0.5; path.stroke()
        }
        let slot: CGFloat = symbol == nil ? 0 : 24
        let textRect = NSRect(x: 16 + slot, y: bounds.midY - 8, width: max(0, bounds.width - 32 - slot), height: 18)
        let centeredBusy = isBusy && symbol == nil
        if !title.isEmpty && !centeredBusy {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
            (title as NSString).draw(in: textRect, withAttributes: [.font: font!, .foregroundColor: ink, .paragraphStyle: paragraph])
        }
        if !isBusy || preferences.effectiveReduceMotion {
            let icon = isBusy ? NSImage(systemSymbolName: "hourglass", accessibilityDescription: nil) : symbol
            if let icon {
                let x: CGFloat = title.isEmpty || centeredBusy ? bounds.midX - 7 : 16
                let rect = NSRect(x: x, y: bounds.midY - 7, width: 14, height: 14)
                NSGraphicsContext.saveGraphicsState()
                let tinted = NSImage(size: rect.size, flipped: true) { target in
                    icon.draw(in: target); ink.setFill(); target.fill(using: .sourceIn); return true
                }
                tinted.draw(in: rect); NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
    private static func contrastingText(on background: NSColor) -> NSColor {
        guard let rgb = background.usingColorSpace(.sRGB) else { return .white }
        func linear(_ x: CGFloat) -> CGFloat { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        return (luminance + 0.05) / 0.05 > 1.05 / (luminance + 0.05) ? .black : .white
    }
}
#endif
