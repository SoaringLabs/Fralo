import AppKit

/// Native scrolling and hit testing with the reference's narrow, trackless artwork.
/// Customize individual parts so AppKit retains overlay fading and drag tracking.
@MainActor
final class SidebarScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override var isOpaque: Bool { false }

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
        NSColor.labelColor.withAlphaComponent(contrast ? 0.7 : 0.35).setFill()
        NSBezierPath(roundedRect: knob, xRadius: 3, yRadius: 3).fill()
    }
}
