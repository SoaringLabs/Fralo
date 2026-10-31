import AppKit
import FraloDesignSystem

/// The write result is separate from clipboard reading so a rejected write can be verified.
@MainActor
protocol ImageClipboard {
    func writePNG(_ data: Data) -> Bool
}

extension NSPasteboard: ImageClipboard {
    func writePNG(_ data: Data) -> Bool {
        clearContents()
        return setData(data, forType: .png)
    }
}

/// Window-local feedback that leaves the canvas, zoom readout and keyboard focus alone.
/// A single-line glass capsule in the same family as the floating view controls: success
/// passes by on its own, a failure stays until dismissed or superseded.
@MainActor
final class OperationFeedback: NSView {
    enum Kind { case success, failure }
    enum Phase { case hidden, entering, shown, exiting }
    static let height: CGFloat = 36
    /// Static text on bare glass: never interactive, so the lens cannot refract the label.
    let surface = MaterialSurface(.panel, radius: OperationFeedback.height / 2)
    let title = FraloStyle.text("", role: .body)
    let detail = FraloStyle.text("", role: .body, secondary: true)
    let close = NSButton()
    private let icon = NSImageView()
    private var row: NSStackView!
    private var rowTrailing: NSLayoutConstraint!
    private(set) var kind: Kind?
    private(set) var phase = Phase.hidden
    private var dismissal: DispatchWorkItem?
    private var generation = 0
    private var tracking: NSTrackingArea?
    private var isHovered = false

    init() {
        super.init(frame: .zero)
        isHidden = true; alphaValue = 0
        wantsLayer = true
        // The surface clips its glass; this host layer carries the lift so it reads above the artwork.
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 12; layer?.shadowOffset = CGSize(width: 0, height: -3)
        surface.tintOpacity = 0.3; surface.darkTintOpacity = 0.3
        surface.translatesAutoresizingMaskIntoConstraints = false; addSubview(surface)
        // Decorative image views must not intercept the workbench's file-drop routing.
        icon.unregisterDraggedTypes()
        icon.setAccessibilityElement(false)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.setContentHuggingPriority(.required, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        detail.lineBreakMode = .byTruncatingTail; detail.maximumNumberOfLines = 1
        // Below the title, above every hugging preference: the detail truncates only at the stage's width limit.
        detail.setContentCompressionResistancePriority(.defaultHigh - 1, for: .horizontal)
        close.isBordered = false; close.bezelStyle = .regularSquare; close.imagePosition = .imageOnly
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭操作提示")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        close.contentTintColor = .secondaryLabelColor
        close.toolTip = "关闭"; close.setAccessibilityLabel("关闭操作提示")
        close.target = self; close.action = #selector(closePressed(_:))
        close.widthAnchor.constraint(equalToConstant: 24).isActive = true
        close.heightAnchor.constraint(equalToConstant: 24).isActive = true
        row = FraloStyle.stack([icon, title, detail, close], axis: .horizontal, spacing: 6)
        row.setCustomSpacing(8, after: icon); row.setCustomSpacing(2, after: detail)
        row.alignment = .centerY; row.wantsLayer = true
        row.translatesAutoresizingMaskIntoConstraints = false; surface.contentView.addSubview(row)
        rowTrailing = row.trailingAnchor.constraint(equalTo: surface.contentView.trailingAnchor, constant: -16)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor), surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor), surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: surface.contentView.leadingAnchor, constant: 12), rowTrailing,
            row.centerYAnchor.constraint(equalTo: surface.contentView.centerYAnchor)
        ])
        setAccessibilityElement(true); setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { dismissal?.cancel() }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: Self.height / 2, cornerHeight: Self.height / 2, transform: nil)
    }

    // Pointing at a success message holds it, so people can finish reading it.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        dismissal?.cancel(); dismissal = nil
    }
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if kind == .success, phase == .entering || phase == .shown { scheduleDismissal(after: 1.2) }
    }

    func show(_ kind: Kind, title: String, detail: String = "", duration: TimeInterval = 2.4) {
        let replacing = phase == .entering || phase == .shown
        dismissal?.cancel(); dismissal = nil
        if replacing, !reduceMotion, canAnimate {
            // A repeat keeps the capsule in place; only its content crossfades.
            let fade = CATransition(); fade.type = .fade; fade.duration = 0.16
            row.layer?.add(fade, forKey: "content")
        }
        self.kind = kind
        self.title.stringValue = title
        self.detail.stringValue = detail; self.detail.isHidden = detail.isEmpty
        self.detail.toolTip = detail.isEmpty ? nil : detail
        let success = kind == .success
        let symbol = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            .applying(success ? .init(paletteColors: [.white, .systemGreen]) : .preferringMulticolor())
        icon.image = NSImage(systemSymbolName: success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                             accessibilityDescription: nil)?.withSymbolConfiguration(symbol)
        close.isHidden = success
        rowTrailing.constant = success ? -16 : -6
        let announcement = detail.isEmpty ? title : "\(title)，\(detail)"
        setAccessibilityLabel(announcement)
        superview?.layoutSubtreeIfNeeded()
        if replacing { phase = .shown } else { present() }
        if !reduceMotion, canAnimate { icon.addSymbolEffect(.bounce, options: .nonRepeating) }
        NSAccessibility.post(element: self, notification: .announcementRequested,
            userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        // Errors stay readable until dismissed or superseded; feedback never moves focus.
        if success, !isHovered { scheduleDismissal(after: duration) }
    }

    /// Context changes clear immediately; user dismissal and expiry animate out.
    func dismiss(animated: Bool = false) {
        dismissal?.cancel(); dismissal = nil
        guard phase != .hidden else { return }
        guard animated, canAnimate, let layer else { finish(hidden: true); return }
        generation += 1; let current = generation
        phase = .exiting
        let from = presented(layer)
        layer.removeAllAnimations()
        let end = reduceMotion ? CATransform3DIdentity : transform(scale: 0.96, lift: 4)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.finish(hidden: true)
            }
        }
        alphaValue = 0; layer.transform = end
        let accelerate = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
        layer.add(basic("opacity", from: from.opacity, to: Float(0), duration: 0.18, timing: accelerate), forKey: "feedback.opacity")
        if !reduceMotion {
            layer.add(basic("transform", from: NSValue(caTransform3D: from.transform), to: NSValue(caTransform3D: end),
                            duration: 0.18, timing: accelerate), forKey: "feedback.transform")
        }
        CATransaction.commit()
    }

    @objc private func closePressed(_ sender: Any?) { dismiss(animated: true) }

    private var reduceMotion: Bool { surface.preferences.effectiveReduceMotion }
    private var canAnimate: Bool { window?.isVisible == true }

    private func scheduleDismissal(after delay: TimeInterval) {
        dismissal?.cancel()
        let current = generation
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current, !self.isHovered else { return }
                self.dismiss(animated: true)
            }
        }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Drops in from under the header on a lightly damped spring; Reduce Motion keeps only the fade.
    private func present() {
        let wasExiting = phase == .exiting
        isHidden = false
        guard canAnimate, let layer else { finish(hidden: false); return }
        generation += 1; let current = generation
        phase = .entering
        // Reversing an exit starts from what is on screen, so the capsule never jumps.
        let from = wasExiting ? presented(layer)
            : (opacity: Float(0), transform: reduceMotion ? CATransform3DIdentity : transform(scale: 0.9, lift: 10))
        layer.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.phase = .shown
            }
        }
        alphaValue = 1; layer.transform = CATransform3DIdentity
        layer.add(basic("opacity", from: from.opacity, to: Float(1), duration: reduceMotion ? 0.2 : 0.16,
                        timing: CAMediaTimingFunction(name: .easeOut)), forKey: "feedback.opacity")
        if !reduceMotion {
            let spring = CASpringAnimation(keyPath: "transform")
            spring.mass = 1; spring.stiffness = 420; spring.damping = 30
            spring.fromValue = NSValue(caTransform3D: from.transform); spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            spring.duration = spring.settlingDuration
            layer.add(spring, forKey: "feedback.transform")
        }
        CATransaction.commit()
    }

    private func finish(hidden: Bool) {
        generation += 1
        layer?.removeAllAnimations()
        layer?.transform = CATransform3DIdentity
        alphaValue = hidden ? 0 : 1; isHidden = hidden
        phase = hidden ? .hidden : .shown
        if hidden { kind = nil }
    }

    private func presented(_ layer: CALayer) -> (opacity: Float, transform: CATransform3D) {
        let shown = layer.presentation() ?? layer
        return (shown.opacity, shown.transform)
    }

    /// Scales about the capsule's centre, whatever anchor AppKit gave its backing layer, and
    /// raises it toward the header by `lift` points.
    private func transform(scale: CGFloat, lift: CGFloat) -> CATransform3D {
        let anchor = layer?.anchorPoint ?? .zero
        let dx = bounds.width * (0.5 - anchor.x), dy = bounds.height * (0.5 - anchor.y)
        let up: CGFloat = superview?.isFlipped == true ? -lift : lift
        var result = CATransform3DMakeTranslation(-dx, -dy, 0)
        result = CATransform3DConcat(result, CATransform3DMakeScale(scale, scale, 1))
        return CATransform3DConcat(result, CATransform3DMakeTranslation(dx, dy + up, 0))
    }

    private func basic(_ keyPath: String, from: Any, to: Any, duration: CFTimeInterval, timing: CAMediaTimingFunction) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from; animation.toValue = to
        animation.duration = duration; animation.timingFunction = timing
        return animation
    }
}
