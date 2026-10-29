import AppKit

/// Native scrolling and hit testing with the reference's narrow, trackless artwork.
/// Customize individual parts so AppKit retains overlay fading and drag tracking.
@MainActor
final class SidebarScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override var isOpaque: Bool { false }
    private var hoverArea: NSTrackingArea?
    private var isHovered = false
    private var isDragging = false
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

    override func rect(for part: NSScroller.Part) -> NSRect {
        var rect = super.rect(for: part)
        if part == .knob, !rect.isEmpty {
            // Drawing six points wide must not make dragging six points precise.
            rect.origin.x = bounds.minX; rect.size.width = bounds.width
        }
        return rect
    }

    override func drawKnob() {
        let native = rect(for: .knob)
        guard !native.isEmpty else { return }
        let knob = NSRect(x: floor(bounds.maxX - 9), y: native.minY, width: 6, height: native.height).intersection(bounds)
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let active = isHovered || isDragging
        let opacity: CGFloat = contrast ? (active ? 0.72 : 0.48) : (active ? 0.42 : 0.20)
        NSColor.labelColor.withAlphaComponent(opacity).setFill()
        NSBezierPath(roundedRect: knob, xRadius: 3, yRadius: 3).fill()
    }
}
