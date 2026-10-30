import AppKit
import FraloDesignSystem

/// The workspace header's background. AppKit has no public hover reveal, and toggling
/// `titlebarAppearsTransparent` swaps instantly, so a native material fades here instead,
/// like Find My's own titlebar view. The window titlebar itself stays transparent.
@MainActor
final class HeaderBackdrop: NSView {
    static let fadeIn: TimeInterval = 0.2, fadeOut: TimeInterval = 0.25, hideDelay: TimeInterval = 0.3
    let effect = NSVisualEffectView()
    private let fallback = NSView()
    private let hairline = NSView()
    private var hideWork: DispatchWorkItem?
    private var observer: NSObjectProtocol?
    /// The requested state; alpha may still be fading toward it.
    private(set) var isShown = false
    var preferences = DesignPreferences() { didSet { refreshMaterial() } }
    var isUsingOpaqueFallback: Bool { !fallback.isHidden }
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; alphaValue = 0
        effect.material = .titlebar; effect.blendingMode = .withinWindow; effect.state = .followsWindowActiveState
        fallback.wantsLayer = true; hairline.wantsLayer = true
        for view in [effect, fallback] { view.frame = bounds; view.autoresizingMask = [.width, .height]; addSubview(view) }
        // Flipped: a flexible top margin pins the separator to the bottom edge.
        hairline.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        hairline.autoresizingMask = [.width, .minYMargin]; addSubview(hairline)
        setAccessibilityElement(false)
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refreshMaterial() } }
        refreshMaterial()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshMaterial() }

    /// Shows immediately; hides after a short delay so crossing between toolbar items never flickers.
    func setShown(_ shown: Bool) {
        if shown {
            hideWork?.cancel(); hideWork = nil
            guard !isShown else { return }
            isShown = true; fade(to: 1, duration: Self.fadeIn)
        } else {
            guard isShown, hideWork == nil else { return }
            guard window != nil, !preferences.effectiveReduceMotion else { isShown = false; fade(to: 0, duration: 0); return }
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.hideWork = nil; self.isShown = false; self.fade(to: 0, duration: Self.fadeOut)
                }
            }
            hideWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDelay, execute: work)
        }
    }
    private func fade(to value: CGFloat, duration: TimeInterval) {
        let duration = window == nil || preferences.effectiveReduceMotion ? 0 : duration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = value
        }
        // Zero-duration proxies can defer their setter; apply the endpoint now.
        if duration == 0 { alphaValue = value }
    }
    private func refreshMaterial() {
        let opaque = preferences.effectiveReduceTransparency
        effect.isHidden = opaque; fallback.isHidden = !opaque
        effectiveAppearance.performAsCurrentDrawingAppearance {
            fallback.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            hairline.layer?.backgroundColor = NSColor.separatorColor.cgColor
        }
    }
}

/// Tracks interaction only. `HeaderBackdrop` paints the background;
/// this view installs no material, tint, gradient, or opacity animation.
@MainActor
final class CanvasToolbarBehavior: NSView {
    var focusViews: () -> [NSView] = { [] }
    var menus: () -> [NSMenu] = { [] }
    var onVisibilityChange: ((Bool) -> Void)?
    var preferences = DesignPreferences() { didSet { refresh() } }
    private(set) var isPointerInside = false
    private(set) var isEngaged = false
    private var lastVisibility: Bool?
    private var tracking: NSTrackingArea?
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var accessibilityObserver: NSObjectProtocol?
    private var trackedMenus: Set<ObjectIdentifier> = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        for name in [NSWindow.didUpdateNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let window = note.object as? NSWindow, window === self.window else { return }
                    if name == NSWindow.didResignKeyNotification { self.isPointerInside = false }
                    self.refresh()
                }
            })
        }
        for name in [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let menu = note.object as? NSMenu, self.owns(menu) else { return }
                    if name == NSMenu.didBeginTrackingNotification { self.trackedMenus.insert(ObjectIdentifier(menu)) }
                    else { self.trackedMenus.remove(ObjectIdentifier(menu)) }
                    self.refresh()
                }
            })
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
        trackedMenus.removeAll(); lastVisibility = nil
        isPointerInside = window.map { bounds.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        if window != nil {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .keyUp]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard event.window === self.window else { return }
                    self.trace("event-\(event.type.rawValue)", point: event.locationInWindow, eventWindow: event.windowNumber)
                    if event.type != .keyUp { self.updatePointer(locationInWindow: event.locationInWindow) }
                    self.refresh()
                }
                return event
            }
        }
        refresh()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        tracking = area; addTrackingArea(area)
    }
    override func mouseEntered(with event: NSEvent) { updatePointer(locationInWindow: event.locationInWindow); refresh() }
    override func mouseExited(with event: NSEvent) { updatePointer(locationInWindow: event.locationInWindow); refresh() }
    func updatePointer(locationInWindow: NSPoint) {
        isPointerInside = bounds.contains(convert(locationInWindow, from: nil))
        trace("pointer", point: locationInWindow)
    }
    private func owns(_ menu: NSMenu) -> Bool {
        var current: NSMenu? = menu
        while let menu = current {
            if menus().contains(where: { $0 === menu }) { return true }
            current = menu.supermenu
        }
        return false
    }
    func refresh() {
        let focused = (window?.firstResponder as? NSView).map { responder in
            if focusViews().contains(where: { responder === $0 || responder.isDescendant(of: $0) }) { return true }
            let rect = convert(responder.bounds, from: responder)
            return rect.height <= 80 && bounds.contains(NSPoint(x: rect.midX, y: rect.midY))
        } ?? false
        setEngaged(window?.isKeyWindow == true && (isPointerInside || focused || !trackedMenus.isEmpty))
    }
    func setEngaged(_ value: Bool) {
        isEngaged = value
        let visible = value || preferences.effectiveReduceTransparency || preferences.effectiveIncreaseContrast
        guard lastVisibility != visible else { return }
        lastVisibility = visible; onVisibilityChange?(visible)
        trace("visibility")
    }
    private func trace(_ event: String, point: NSPoint? = nil, eventWindow: Int? = nil) {
        #if FRALO_DEV
        guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--preview-toolbar-trace=") }) else { return }
        let path = String(argument.dropFirst("--preview-toolbar-trace=".count))
        let payload: [String: Any] = ["event": event, "frame": NSStringFromRect(frame), "bounds": NSStringFromRect(bounds),
            "pointer": point.map(NSStringFromPoint) ?? "", "localPointer": point.map { NSStringFromPoint(convert($0, from: nil)) } ?? "",
            "inside": isPointerInside, "engaged": isEngaged, "key": window?.isKeyWindow ?? false,
            "window": window?.windowNumber ?? -1, "eventWindow": eventWindow ?? -1,
            "transparent": window?.titlebarAppearsTransparent ?? true, "separator": window?.titlebarSeparatorStyle.rawValue ?? 0]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) + Data([10]) else { return }
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        if let file = FileHandle(forWritingAtPath: path) { file.seekToEndOfFile(); file.write(data); try? file.close() }
        #endif
    }
}

/// Only the native control capsule receives input; empty footer space remains canvas.
@MainActor
final class CanvasControlsOverlay: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}
