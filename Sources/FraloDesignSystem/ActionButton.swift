import AppKit

/// Default Fralo action style; native button events with the selected soft appearance.
@MainActor
public class ActionButton: NSButton {
    public enum Role { case primary, secondary, quiet, destructive }
    public enum Size { case regular, compact }
    public let size: Size
    public let role: Role
    public var onPress: (() -> Void)?
    public var preferences = DesignPreferences() { didSet { refresh() } }
    private let explicitLabel: String?
    private var accessibleName: String { explicitLabel ?? title }
    private var accessibilityObserver: NSObjectProtocol?
    private let activity = NSProgressIndicator()
    private var requestedEnabled = true
    private var tracking: NSTrackingArea?
    private var windowObservers: [NSObjectProtocol] = []
    private(set) var isHovered = false
    public var isBusy = false { didSet { super.isEnabled = requestedEnabled && !isBusy; refresh() } }
    public override var isEnabled: Bool {
        get { super.isEnabled }
        set { requestedEnabled = newValue; super.isEnabled = newValue && !isBusy; refresh() }
    }
    public override var acceptsFirstResponder: Bool { isEnabled }
    public override var isFlipped: Bool { true }
    public override var intrinsicContentSize: NSSize {
        if title.isEmpty { return NSSize(width: buttonHeight, height: buttonHeight) }
        let width = (title as NSString).size(withAttributes: [.font: font ?? .systemFont(ofSize: 13, weight: .medium)]).width
        return NSSize(width: ceil(width) + inset * 2 + iconSlot, height: buttonHeight)
    }

    public init(_ title: String, role: Role = .secondary, size: Size = .regular, symbol: String? = nil,
         label: String? = nil, onPress: (() -> Void)? = nil) {
        self.role = role; self.size = size; self.onPress = onPress; explicitLabel = label
        super.init(frame: .zero)
        self.title = title; self.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        font = .systemFont(ofSize: size == .regular ? 13 : 12, weight: .medium)
        setButtonType(.momentaryPushIn); isBordered = false
        target = self; action = #selector(activate(_:)); focusRingType = .exterior
        hasDestructiveAction = role == .destructive; toolTip = label ?? title
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel(accessibleName)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        activity.style = .spinning; activity.controlSize = .small; activity.isDisplayedWhenStopped = false
        addSubview(activity); refresh()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
    required public init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }

    @objc private func activate(_ sender: Any?) { if isEnabled && !isBusy { onPress?() } }
    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 {
            if event.modifierFlags.contains(.shift) { window?.selectKeyView(preceding: self) }
            else { window?.selectKeyView(following: self) }
        } else { super.keyDown(with: event) }
    }
    public override func highlight(_ flag: Bool) { super.highlight(flag); needsDisplay = true }
    public override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach(NotificationCenter.default.removeObserver); windowObservers.removeAll()
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isHovered = false; self?.needsDisplay = true }
            })
        }
    }
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    public override func mouseEntered(with event: NSEvent) { isHovered = isEnabled; needsDisplay = true }
    public override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
    public override func layout() {
        super.layout()
        let x: CGFloat = title.isEmpty || image == nil ? bounds.midX - iconSide / 2 : inset
        activity.frame = NSRect(x: x, y: bounds.midY - iconSide / 2, width: iconSide, height: iconSide)
    }
    private func refresh() {
        if !isEnabled { isHovered = false }
        setAccessibilityLabel(accessibleName + (isBusy ? "，正在处理" : ""))
        if isBusy && !preferences.effectiveReduceMotion { activity.startAnimation(nil) }
        else { activity.stopAnimation(nil) }
        activity.isHidden = !isBusy || preferences.effectiveReduceMotion
        needsLayout = true; needsDisplay = true
    }
    public override var title: String {
        didSet {
            if explicitLabel == nil && (toolTip == oldValue || toolTip == nil) { toolTip = title }
            invalidateIntrinsicContentSize(); refresh()
        }
    }
    public override var image: NSImage? { didSet { invalidateIntrinsicContentSize(); needsLayout = true; needsDisplay = true } }
    private var buttonHeight: CGFloat { size == .regular ? FraloStyle.Button.height : FraloStyle.Button.compactHeight }
    private var inset: CGFloat { size == .regular ? FraloStyle.Button.inset : FraloStyle.Button.compactInset }
    private var radius: CGFloat { size == .regular ? FraloStyle.Button.radius : FraloStyle.Button.compactRadius }
    private var iconSide: CGFloat { size == .regular ? FraloStyle.Button.icon : FraloStyle.Button.compactIcon }
    private var iconSlot: CGFloat { image == nil ? 0 : iconSide + (size == .regular ? 10 : 8) }
    private var surfaceRect: NSRect { bounds.insetBy(dx: 2, dy: 2) }
    public override var focusRingMaskBounds: NSRect { surfaceRect }
    public override func drawFocusRingMask() { NSBezierPath(roundedRect: surfaceRect, xRadius: radius, yRadius: radius).fill() }

    public override func draw(_ dirtyRect: NSRect) {
        let pressed = cell?.isHighlighted == true && isEnabled
        let contrast = preferences.effectiveIncreaseContrast
        let path = NSBezierPath(roundedRect: surfaceRect, xRadius: radius, yRadius: radius)
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
        let slot = iconSlot
        let textRect = NSRect(x: inset + slot, y: bounds.midY - 8, width: max(0, bounds.width - inset * 2 - slot), height: 18)
        let centeredBusy = isBusy && image == nil
        if !title.isEmpty && !centeredBusy {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
            (title as NSString).draw(in: textRect, withAttributes: [.font: font ?? FraloStyle.TextRole.body.font, .foregroundColor: ink, .paragraphStyle: paragraph])
        }
        if !isBusy || preferences.effectiveReduceMotion {
            let icon = isBusy ? NSImage(systemSymbolName: "hourglass", accessibilityDescription: nil) : image
            if let icon {
                let x: CGFloat = title.isEmpty || centeredBusy ? bounds.midX - iconSide / 2 : inset
                let rect = NSRect(x: x, y: bounds.midY - iconSide / 2, width: iconSide, height: iconSide)
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
