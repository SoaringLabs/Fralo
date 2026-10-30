import AppKit
import QuartzCore
import FraloDesignSystem

/// Native scrolling and hit testing with the reference's narrow, trackless artwork.
/// Customize individual parts so AppKit retains overlay fading and drag tracking.
/// Shared by the sidebar list and both canvas axes so the app has one scroller style.
@MainActor
final class ThinScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override var isOpaque: Bool { false }
    private var hoverArea: NSTrackingArea?
    private var isHovered = false { didSet { updateEmphasis() } }
    private var isDragging = false { didSet { updateEmphasis() } }
    var preferences = DesignPreferences() { didSet { updateEmphasis(force: true) } }
    @objc dynamic var hoverAmount: CGFloat = 0 { didSet { needsDisplay = true } }
    private var targetAmount: CGFloat = 0

    override class func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
        key == "hoverAmount" ? CABasicAnimation() : super.defaultAnimation(forKey: key)
    }

    private func updateEmphasis(force: Bool = false) {
        let target: CGFloat = isHovered || isDragging ? 1 : 0
        guard force || target != targetAmount else { return }
        targetAmount = target
        let duration = window == nil ? 0 : FraloMotion.duration(.selection, preferences: preferences)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            // AppKit retargets from the in-flight value instead of restarting.
            animator().hoverAmount = target
        }
        // Zero-duration proxies can defer their setter to the next run-loop turn.
        // Cancel through the proxy, then apply the accessible endpoint now.
        if duration == 0 { hoverAmount = target }
    }
    private var pointerMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor); self.pointerMonitor = nil }
        guard window != nil else { return }
        // Also observe location-bearing events: a click/scroll can relocate a
        // pointer without an intermediate mouseEntered/mouseExited event.
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.updateHover(for: event) }
            return event
        }
    }

    deinit { if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) } }

    private func updateHover(for event: NSEvent) {
        guard let window else { return }
        let sameWindow = event.window == nil || event.window === window
        let point = event.window == nil ? window.convertPoint(fromScreen: event.locationInWindow) : event.locationInWindow
        let inside = sameWindow && bounds.contains(convert(point, from: nil))
        if inside != isHovered { isHovered = inside; needsDisplay = true }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag], owner: self, userInfo: nil)
        addTrackingArea(area); hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event); isHovered = true; needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event); isHovered = false; needsDisplay = true
    }
    override func trackKnob(with event: NSEvent) {
        isHovered = true; isDragging = true; needsDisplay = true
        // Tracking areas keep isHovered current even if a drag ends outside.
        defer { isDragging = false; needsDisplay = true }
        super.trackKnob(with: event)
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // No slot, including legacy/Always mode and overlay hover/drag states.
    }

    private var isHorizontal: Bool { bounds.width > bounds.height }

    override func rect(for part: NSScroller.Part) -> NSRect {
        var rect = super.rect(for: part)
        if part == .knob, !rect.isEmpty {
            // Drawing six points thick must not make dragging six points precise.
            if isHorizontal { rect.origin.y = bounds.minY; rect.size.height = bounds.height }
            else { rect.origin.x = bounds.minX; rect.size.width = bounds.width }
        }
        return rect
    }

    override func drawKnob() {
        let native = rect(for: .knob)
        guard !native.isEmpty else { return }
        // Three points from the window-facing edge, matching across both axes.
        let knob = isHorizontal
            ? NSRect(x: native.minX, y: isFlipped ? floor(bounds.maxY - 9) : ceil(bounds.minY + 3), width: native.width, height: 6).intersection(bounds)
            : NSRect(x: floor(bounds.maxX - 9), y: native.minY, width: 6, height: native.height).intersection(bounds)
        let contrast = preferences.effectiveIncreaseContrast
        let idle: CGFloat = contrast ? 0.48 : 0.20
        let active: CGFloat = contrast ? 0.72 : 0.42
        let opacity = idle + (active - idle) * hoverAmount
        NSColor.labelColor.withAlphaComponent(opacity).setFill()
        NSBezierPath(roundedRect: knob, xRadius: 3, yRadius: 3).fill()
    }
}
