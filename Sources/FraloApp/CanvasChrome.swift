import AppKit
import FraloDesignSystem
import QuartzCore

/// A decorative, event-transparent backdrop. Controls remain native siblings above the effect.
@MainActor
final class CanvasChrome: NSView {
    enum Placement { case top, floating }
    let placement: Placement
    let effect = NSVisualEffectView()
    private let opaqueBackdrop = NSView()
    private let fade = CAGradientLayer()
    private var tracking: NSTrackingArea?
    private var observers: [NSObjectProtocol] = []
    private var accessibilityObserver: NSObjectProtocol?
    private var eventMonitor: Any?
    private var trackingMenus: Set<ObjectIdentifier> = []
    private var presentation: [Bool] = []
    private(set) var isEngaged = false
    private(set) var isPointerInside = false
    private(set) var isUsingOpaqueFallback = false
    var preferences = DesignPreferences() { didSet { refresh(animated: false) } }
    var focusViews: () -> [NSView] = { [] }
    var menus: () -> [NSMenu] = { [] }
    /// Floating backdrops surround only the controls, never the entire bottom strip.
    weak var controls: NSView?

    init(_ placement: Placement) {
        self.placement = placement
        super.init(frame: .zero)
        wantsLayer = true
        effect.material = .headerView; effect.blendingMode = .withinWindow
        effect.state = .followsWindowActiveState
        effect.wantsLayer = true
        opaqueBackdrop.wantsLayer = true
        for view in [effect, opaqueBackdrop] { addSubview(view) }
        fade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        fade.locations = [0, 0.78, 1]
        // Layer coordinates are unflipped: dissolve the edge facing the artwork.
        fade.startPoint = CGPoint(x: 0.5, y: 1); fade.endPoint = CGPoint(x: 0.5, y: 0)
        if placement == .top { layer?.mask = fade }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh(animated: false) } }
        for name in [NSWindow.didUpdateNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, let window = notification.object as? NSWindow, window === self.window else { return }
                    if name == NSWindow.didResignKeyNotification { self.isPointerInside = false }
                    self.refresh()
                }
            })
        }
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self, let menu = notification.object as? NSMenu, self.owns(menu) else { return }
                    if name == NSMenu.didBeginTrackingNotification { self.trackingMenus.insert(ObjectIdentifier(menu)) }
                    else { self.trackingMenus.remove(ObjectIdentifier(menu)) }
                    self.refresh()
                }
            })
        }
        refresh(animated: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
        if window != nil {
            // Native titlebar controls sit outside the content hierarchy. Observe their pointer
            // events without replacing the toolbar or consuming any events.
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .keyUp]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, event.window === self.window else { return }
                    if event.type != .keyUp { self.updatePointer(locationInWindow: event.locationInWindow) }
                    self.refresh()
                }
                return event
            }
        }
        isPointerInside = window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        trackingMenus.removeAll(); refresh(animated: false)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        tracking = area; addTrackingArea(area)
    }
    override func mouseEntered(with event: NSEvent) { updatePointer(locationInWindow: event.locationInWindow); refresh() }
    override func mouseExited(with event: NSEvent) { updatePointer(locationInWindow: event.locationInWindow); refresh() }
    func updatePointer(locationInWindow: NSPoint) { isPointerInside = bounds.contains(convert(locationInWindow, from: nil)) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh(animated: false) }
    override func layout() {
        super.layout()
        let rect = controls.map { $0.frame.insetBy(dx: -8, dy: -7) } ?? bounds
        effect.frame = rect; opaqueBackdrop.frame = rect
        let radius = placement == .floating ? rect.height / 2 : 0
        effect.layer?.cornerRadius = radius; effect.layer?.masksToBounds = true
        opaqueBackdrop.layer?.cornerRadius = radius
        CATransaction.begin(); CATransaction.setDisableActions(true); fade.frame = bounds; CATransaction.commit()
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit === self || hit.isDescendant(of: effect) || hit.isDescendant(of: opaqueBackdrop) ? nil : hit
    }
    private func owns(_ menu: NSMenu) -> Bool {
        var current: NSMenu? = menu
        while let candidate = current {
            if menus().contains(where: { $0 === candidate }) { return true }
            current = candidate.supermenu
        }
        return false
    }
    func refresh(animated: Bool = true) {
        let active = window?.isKeyWindow == true
        let responder = window?.firstResponder as? NSView
        let focused = responder.map { responder in
            if focusViews().contains(where: { responder === $0 || responder.isDescendant(of: $0) }) { return true }
            // AppKit owns the views of standard toolbar items. Their focused view is
            // deliberately outside our content hierarchy, but has a public view rect.
            let rect = convert(responder.bounds, from: responder)
            return placement == .top && rect.height <= 80 && bounds.contains(NSPoint(x: rect.midX, y: rect.midY))
        } ?? false
        setEngaged(active && (isPointerInside || focused || !trackingMenus.isEmpty), animated: animated)
    }
    func setEngaged(_ engaged: Bool, animated: Bool = false) {
        isEngaged = engaged
        let reduced = preferences.effectiveReduceTransparency
        let contrast = preferences.effectiveIncreaseContrast
        isUsingOpaqueFallback = reduced
        let style = [reduced, contrast, effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua]
        if style != presentation {
            presentation = style
            effect.isHidden = reduced; opaqueBackdrop.isHidden = !reduced
            effectiveAppearance.performAsCurrentDrawingAppearance {
                opaqueBackdrop.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                opaqueBackdrop.layer?.borderColor = NSColor.labelColor.cgColor
                opaqueBackdrop.layer?.borderWidth = contrast ? 1 : 0
                effect.layer?.borderColor = NSColor.labelColor.cgColor
                effect.layer?.borderWidth = contrast ? 1 : 0
            }
        }
        // Accessibility settings protect labels even before pointer/focus engagement.
        let opacity: CGFloat = engaged || reduced || contrast ? 1 : 0
        for view in [effect, opaqueBackdrop] where view.alphaValue != opacity {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animated ? FraloMotion.duration(.preview, preferences: preferences) : 0
                if context.duration > 0 { view.animator().alphaValue = opacity }
                else { view.alphaValue = opacity }
            }
        }
    }
}
