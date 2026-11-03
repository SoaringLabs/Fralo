import AppKit

/// Shared pointer feedback for custom controls. Only the shade animates; actions stay immediate.
@MainActor
final class HoverFeedback {
    @MainActor final class Fade: NSAnimation {
        var onProgress: ((CGFloat) -> Void)?
        override var currentProgress: NSAnimation.Progress {
            didSet { onProgress?(CGFloat(currentValue)) }
        }
        override var runLoopModesForAnimating: [RunLoop.Mode]? { [.common, .eventTracking] }
    }

    private weak var view: NSView?
    private var tracking: NSTrackingArea?
    private var observers: [NSObjectProtocol] = []
    private var displayObserver: NSObjectProtocol?
    private var enabled = true
    private var preferences = DesignPreferences()
    private var target: CGFloat = 0
    private(set) var isHovered = false
    private(set) var amount: CGFloat = 0
    private(set) var animation: Fade?

    init(view: NSView) { self.view = view }
    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        if let displayObserver { NSWorkspace.shared.notificationCenter.removeObserver(displayObserver) }
    }

    func update(enabled: Bool, preferences: DesignPreferences) {
        guard self.enabled != enabled || self.preferences != preferences else { return }
        self.enabled = enabled; self.preferences = preferences
        syncPointer()
        refresh(animated: false)
    }
    func viewDidMoveToWindow() {
        observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        if let displayObserver { NSWorkspace.shared.notificationCenter.removeObserver(displayObserver); self.displayObserver = nil }
        isHovered = false; refresh(animated: false)
        guard let window = view?.window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncPointer(); self?.refresh(animated: false) }
            })
        }
        displayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh(animated: false); self?.view?.needsDisplay = true } }
        syncPointer()
    }
    func updateTrackingAreas() {
        guard let view else { return }
        if let tracking { view.removeTrackingArea(tracking) }
        let visible = view.bounds.intersection(view.visibleRect)
        let area = NSTrackingArea(rect: visible.isEmpty ? .zero : visible,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: view)
        view.addTrackingArea(area); tracking = area
        // Rebuilt cards and scrolling can move beneath a stationary pointer.
        syncPointer()
    }
    func enter() { isHovered = enabled && view?.window?.isKeyWindow == true; refresh() }
    func exit() { isHovered = false; refresh() }
    private func syncPointer() {
        let inside = enabled && view.map { view in
            view.window.map { $0.isKeyWindow && !view.isHiddenOrHasHiddenAncestor &&
                view.bounds.intersection(view.visibleRect).contains(view.convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        } ?? false
        guard inside != isHovered else { return }
        isHovered = inside; refresh(animated: false)
    }
    private func refresh(animated: Bool = true) {
        let value: CGFloat = enabled && isHovered && view?.window?.isKeyWindow == true ? 1 : 0
        guard value != target || !animated else { return }
        target = value
        animation?.stop(); animation = nil
        let duration = animated ? FraloMotion.duration(.hover, preferences: preferences) : 0
        guard duration > 0, amount != value else { setAmount(value); return }
        let start = amount
        let fade = Fade(duration: duration, animationCurve: .easeOut)
        fade.animationBlockingMode = .nonblocking; fade.frameRate = 60
        fade.onProgress = { [weak self] progress in
            guard let self else { return }
            self.setAmount(start + (value - start) * progress)
            if progress >= 1 { self.animation = nil }
        }
        animation = fade; fade.start()
    }
    private func setAmount(_ value: CGFloat) {
        amount = min(1, max(0, value)); view?.needsDisplay = true
    }
}
