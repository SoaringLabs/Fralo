import AppKit

/// Shared, surface-free activity glyph for preview rendering and file-size calculation.
@MainActor
public final class ArcActivityIndicator: NSView {
    let arc = CAShapeLayer()
    public var isRunning = false { didSet { updateRotation() } }
    public var increaseContrast = false { didSet { updateTint() } }
    public override var isHidden: Bool { didSet { updateRotation() } }
    public init(label: String) {
        super.init(frame: .zero)
        wantsLayer = true; layer?.addSublayer(arc)
        arc.fillColor = nil; arc.lineWidth = 1.75; arc.lineCap = .round
        setAccessibilityElement(true); setAccessibilityRole(.progressIndicator)
        setAccessibilityLabel(label)
        updateTint()
    }
    required public init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    public override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        arc.frame = bounds
        arc.contentsScale = window?.backingScaleFactor ?? 1
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY),
                    radius: max(0, min(bounds.width, bounds.height) / 2 - 1.5),
                    startAngle: -.pi / 2, endAngle: .pi, clockwise: false)
        arc.path = path; CATransaction.commit()
    }
    public override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateRotation() }
    public override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); needsLayout = true }
    public override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateTint() }
    private func updateTint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            arc.strokeColor = (increaseContrast ? NSColor.labelColor : .secondaryLabelColor).cgColor
            CATransaction.commit()
        }
    }
    private func updateRotation() {
        guard isRunning, window != nil, !isHiddenOrHasHiddenAncestor else { arc.removeAnimation(forKey: "activity.rotation"); return }
        guard arc.animation(forKey: "activity.rotation") == nil else { return }
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0; rotation.toValue = -2 * Double.pi
        rotation.duration = 0.8; rotation.repeatCount = .infinity
        rotation.timingFunction = CAMediaTimingFunction(name: .linear)
        arc.add(rotation, forKey: "activity.rotation")
    }
}
