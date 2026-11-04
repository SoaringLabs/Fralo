import FraloLocalization
import AppKit
import QuartzCore
import FraloCore
import FraloDesignSystem

/// What an export run ended with, reduced to what people act on.
struct ExportOutcome: Equatable {
    struct Issue: Equatable {
        let name: String
        let reason: String
        let failed: Bool
    }
    enum Tone { case success, warning, cancelled }
    let total: Int
    let succeeded: Int
    let skipped: Int
    let failed: Int
    let cancelled: Bool
    let issues: [Issue]
    var unprocessed: Int { max(0, total - succeeded - skipped - failed) }

    init(total: Int, succeeded: Int, skipped: Int = 0, failed: Int = 0, cancelled: Bool = false, issues: [Issue] = []) {
        self.total = total; self.succeeded = succeeded; self.skipped = skipped; self.failed = failed
        self.cancelled = cancelled; self.issues = issues
    }
    init(report: ExportReport) {
        self.init(total: report.total, succeeded: report.succeeded, skipped: report.skipped, failed: report.failed,
                  cancelled: report.cancelled,
                  issues: report.entries.filter { $0.status != .success }.map {
                      Issue(name: $0.input, reason: $0.reason ?? $0.status.rawValue, failed: $0.status == .failed)
                  })
    }

    var tone: Tone { cancelled ? .cancelled : skipped + failed > 0 ? .warning : .success }
    var title: String {
        if cancelled { return succeeded == 0 ? L10n.tr("导出已取消") : L10n.tr("导出已取消，已导出 \(succeeded) 张图片") }
        if skipped + failed == 0 { return total == 1 ? L10n.tr("已导出图片") : L10n.tr("已导出 \(succeeded) 张图片") }
        return succeeded == 0 ? L10n.tr("未能导出图片") : L10n.tr("已导出 \(succeeded) 张，\(skipped + failed) 张未导出")
    }
    /// Only counts that need attention; a clean run says nothing about zero failures.
    var counts: String {
        var parts: [String] = []
        if failed > 0 { parts.append(L10n.tr("\(failed) 张失败")) }
        if skipped > 0 { parts.append(L10n.tr("\(skipped) 张已跳过")) }
        if unprocessed > 0 { parts.append(L10n.tr("\(unprocessed) 张未处理")) }
        return parts.joined(separator: " · ")
    }
    var revealable: Bool { succeeded > 0 }
}

/// Export progress and its result as one liquid-glass capsule on the stage. It grows out of the
/// viewing toolbar, fills with a neutral glass highlight while images export, and settles back
/// into the toolbar once a clean run has been seen. Results that need reading stay as a card.
@MainActor
final class ExportCapsule: NSView {
    enum Phase: Equatable { case hidden, running, result(ExportOutcome.Tone) }
    static let height: CGFloat = 48
    private(set) var phase = Phase.hidden
    var preferences = DesignPreferences() { didSet { surface.preferences = preferences; refreshFill() } }
    var onCancel: (() -> Void)?
    var onReveal: (() -> Void)?
    /// Called when the toolbar should start taking its place back, near the end of the collapse.
    var onReturn: (() -> Void)?
    /// The viewing toolbar the capsule grows from and returns to, in this view's coordinates.
    var anchor: () -> NSRect = { .zero }

    let surface = MaterialSurface(.panel, radius: ExportCapsule.height / 2)
    /// The glass clips its own shadow; this view behind it carries the toolbar's soft lift.
    private let lift = NSView()
    private let body = CapsuleBody()
    private let fill = CALayer()
    private let shimmer = CAGradientLayer()
    /// The batch's first image, held still for the whole run; per-image pace lives in the liquid and count.
    let thumbnail = NSImageView()
    /// One highlight across the whole capsule when a clean run completes.
    private let glint = CAGradientLayer()
    private let status = NSImageView()
    let title = FraloStyle.text("", role: .body)
    let detail = FraloStyle.text("", role: .caption, secondary: true)
    let cancel = IconButton("xmark", label: L10n.tr("取消导出"))
    let progress = NSView()
    private var reveal: ActionButton?
    private var done: ActionButton?
    private var issueList: IssueList?
    private var check: CAShapeLayer?
    private var total = 0
    private var completed = 0
    private var started = Date()
    private var stopping = false
    private var pendingUpdate = ""
    private var dismissal: DispatchWorkItem?
    private var tracking: NSTrackingArea?
    private var hovered = false
    private var generation = 0
    private var fraction: CGFloat = 0
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        surface.translatesAutoresizingMaskIntoConstraints = true
        // The same bare glass as the viewing toolbar, so the hand-off between them has no seam.
        surface.tintOpacity = ViewToolbar.tintOpacity; surface.darkTintOpacity = ViewToolbar.darkTintOpacity
        lift.wantsLayer = true; lift.isHidden = true
        lift.layer?.shadowColor = NSColor.black.cgColor; lift.layer?.shadowOpacity = 0.14
        lift.layer?.shadowRadius = 8; lift.layer?.shadowOffset = CGSize(width: 0, height: -2)
        addSubview(lift)
        surface.isHidden = true; addSubview(surface)
        body.frame = surface.contentView.bounds; body.autoresizingMask = [.width, .height]
        surface.contentView.addSubview(body)
        shimmer.startPoint = CGPoint(x: 0, y: 0.5); shimmer.endPoint = CGPoint(x: 1, y: 0.5)
        fill.addSublayer(shimmer); fill.masksToBounds = true
        glint.startPoint = CGPoint(x: 0, y: 0.5); glint.endPoint = CGPoint(x: 1, y: 0.5); glint.opacity = 0
        body.wantsLayer = true; body.layer?.addSublayer(fill)
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        for image in [thumbnail, status] { image.unregisterDraggedTypes(); image.setAccessibilityElement(false) }
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail; title.maximumNumberOfLines = 1
        detail.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        detail.lineBreakMode = .byTruncatingTail; detail.maximumNumberOfLines = 1
        cancel.keyEquivalent = "\u{1b}"
        cancel.onPress = { [weak self] in self?.requestStop() }
        progress.setAccessibilityElement(true); progress.setAccessibilityRole(.progressIndicator)
        progress.setAccessibilityLabel(L10n.tr("导出进度"))
        for view in [progress, thumbnail, status, title, detail, cancel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = true; body.addSubview(view)
        }
        // Above the content, so the completion highlight crosses the text and controls too.
        body.layer?.addSublayer(glint)
        refreshFill()
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { dismissal?.cancel() }

    /// Only the capsule takes clicks; the rest of the stage stays usable beneath it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !surface.isHidden, surface.frame.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshFill() }

    // MARK: Run

    /// `onReady` runs once the capsule has finished growing (at once when it does not animate), so heavy
    /// work started there never competes with the reshaping frames on the main thread.
    func begin(total: Int, thumbnail image: NSImage?, onReady: (() -> Void)? = nil) {
        dismissal?.cancel(); generation += 1
        clearResult()
        self.total = total; completed = 0; started = Date(); stopping = false; fraction = 0
        phase = .running
        thumbnail.image = image ?? NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        thumbnail.isHidden = false; status.isHidden = true; cancel.isHidden = false; cancel.isEnabled = true
        title.stringValue = total == 1 ? L10n.tr("正在导出图片") : L10n.tr("正在导出 \(total) 张图片")
        refreshFill(); refreshDetail()
        let start = anchor()
        surface.isHidden = false; surface.alphaValue = 1
        reshape(from: start, to: targetFrame, motion: .grow) { [weak self] in
            // The minimum display time counts from the real start of work, not from the grow.
            self?.started = Date()
            onReady?()
        }
        startShimmer()
        announce(title.stringValue)
    }

    func update(completed: Int) {
        guard phase == .running else { return }
        self.completed = completed
        setFraction(total == 0 ? 0 : CGFloat(completed) / CGFloat(total), animated: true)
        refreshDetail()
    }

    func setPendingUpdate(_ text: String) { pendingUpdate = text; refreshDetail() }

    private func requestStop() {
        guard phase == .running, !stopping else { return }
        stopping = true; cancel.isEnabled = false
        refreshDetail()
        onCancel?()
    }

    private func refreshDetail() {
        guard phase == .running else { return }
        let parts = stopping ? [L10n.tr("正在停止…")]
            : [L10n.tr("\(completed) / \(total)"), pendingUpdate.isEmpty ? remaining : pendingUpdate].filter { !$0.isEmpty }
        detail.stringValue = parts.joined(separator: " · ")
        detail.toolTip = pendingUpdate.isEmpty ? nil : pendingUpdate
        progress.setAccessibilityValue(NSNumber(value: total == 0 ? 0 : Double(completed) / Double(total)))
        progress.setAccessibilityValueDescription(L10n.tr("已完成 \(completed) / \(total)"))
    }

    /// Shown only once the run has some pace to go on and enough of it is left to matter.
    private var remaining: String {
        guard completed > 0, completed < total else { return "" }
        let left = Date().timeIntervalSince(started) / Double(completed) * Double(total - completed)
        guard left >= 3 else { return "" }
        return left < 60 ? L10n.tr("约剩 \(Int(left.rounded(.up))) 秒") : L10n.tr("约剩 \(Int((left / 60).rounded(.up))) 分钟")
    }

    // MARK: Result

    /// The running capsule stays at least this long, so a fast run reads as grow → fill → done, not a flicker.
    static let minimumRunDisplay: TimeInterval = 1.2

    func finish(_ outcome: ExportOutcome, folderName: String) {
        guard phase == .running else { return }
        let wait = Self.minimumRunDisplay - Date().timeIntervalSince(started)
        if wait > 0, canAnimate, !preferences.effectiveReduceMotion {
            setFraction(1, animated: true)
            let current = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                guard let self, self.generation == current else { return }
                self.settle(outcome, folderName: folderName)
            }
            return
        }
        settle(outcome, folderName: folderName)
    }

    private func settle(_ outcome: ExportOutcome, folderName: String) {
        guard phase == .running else { return }
        stopShimmer()
        let from = surface.frame
        phase = .result(outcome.tone)
        cancel.isHidden = true; thumbnail.isHidden = true
        title.stringValue = outcome.title
        if outcome.tone == .success {
            detail.stringValue = folderName
            fraction = 1
            let mark = checkmark(); body.layer?.addSublayer(mark); check = mark
        } else {
            fraction = 0
            status.isHidden = false
            // Monochrome like the rest of the glass; the symbol's shape carries the meaning.
            status.image = NSImage(systemSymbolName: outcome.tone == .warning ? "exclamationmark.triangle" : "stop.circle", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 19, weight: .medium).applying(.init(hierarchicalColor: .labelColor)))
            detail.stringValue = [outcome.counts, outcome.revealable ? L10n.tr("存放在“\(folderName)”") : ""].filter { !$0.isEmpty }.joined(separator: " · ")
            if !outcome.issues.isEmpty { let list = IssueList(outcome.issues); body.addSubview(list); issueList = list }
            let button = ActionButton(L10n.tr("完成"), size: .compact) { [weak self] in self?.hide(animated: true) }
            button.translatesAutoresizingMaskIntoConstraints = true; body.addSubview(button); done = button
        }
        detail.toolTip = detail.stringValue
        if outcome.revealable {
            let button = ActionButton(L10n.tr("在 Finder 中显示"), role: .primary, size: .compact) { [weak self] in
                self?.onReveal?(); if case .result(.success) = self?.phase { self?.hide(animated: true) }
            }
            button.translatesAutoresizingMaskIntoConstraints = true; body.addSubview(button); reveal = button
        }
        refreshFill()
        let to = targetFrame
        if abs(from.width - to.width) < 1, abs(from.height - to.height) < 1 {
            // Same shape (running → done): the glass stays put and only its content crossfades.
            if canAnimate, !preferences.effectiveReduceMotion {
                let fade = CATransition(); fade.type = .fade; fade.duration = 0.22
                body.layer?.add(fade, forKey: "content")
            }
            surface.frame = to; layoutBody()
        } else {
            reshape(from: from, to: to, motion: .grow)
        }
        if outcome.tone == .success, canAnimate, !preferences.effectiveReduceMotion {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            celebrate()
        }
        announce([outcome.title, outcome.counts].filter { !$0.isEmpty }.joined(separator: L10n.tr("，")))
        // A clean run passes by on its own; anything that needs reading stays until dismissed.
        if outcome.tone == .success { scheduleHide(after: 5) }
    }

    func hide(animated: Bool) {
        dismissal?.cancel(); dismissal = nil
        guard phase != .hidden else { return }
        stopShimmer()
        phase = .hidden; generation += 1
        let current = generation
        let finish: () -> Void = { [weak self] in
            guard let self, self.generation == current else { return }
            self.surface.isHidden = true; self.lift.isHidden = true; self.surface.alphaValue = 1; self.clearResult()
        }
        guard animated, canAnimate else { onReturn?(); finish(); return }
        if preferences.effectiveReduceMotion {
            onReturn?()
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; surface.animator().alphaValue = 0; lift.animator().alphaValue = 0 }, completionHandler: finish)
            return
        }
        // One continuous motion: content and liquid fade early while the glass contracts onto the
        // toolbar, which fades back in underneath for the last part.
        reshape(from: surface.frame, to: anchor(), motion: .collapse, completion: finish)
    }

    private func scheduleHide(after delay: TimeInterval) {
        dismissal?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.hovered else { return }
                self.hide(animated: true)
            }
        }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func clearResult() {
        for view in [reveal, done, issueList].compactMap({ $0 }) { view.removeFromSuperview() }
        reveal = nil; done = nil; issueList = nil
        check?.removeFromSuperlayer(); check = nil
        body.alphaValue = 1; fill.opacity = 1
    }

    // Pointing at a finished capsule holds it, so people can reach the Finder action.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: surface.frame, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; dismissal?.cancel() }
    override func mouseExited(with event: NSEvent) {
        hovered = false
        if case .result(.success) = phase { scheduleHide(after: 1.6) }
    }

    // MARK: Layout

    private var targetFrame: NSRect {
        let anchor = anchor()
        let side: CGFloat = 24, available = max(bounds.width - side * 2, 200)
        switch phase {
        case .hidden: return anchor
        case .running:
            let width = min(available, 380)
            return NSRect(x: anchor.midX - width / 2, y: anchor.midY - Self.height / 2, width: width, height: Self.height)
        case .result(.success):
            let width = min(available, max(380, contentWidth + 24))
            return NSRect(x: anchor.midX - width / 2, y: anchor.midY - Self.height / 2, width: width, height: Self.height)
        case .result:
            // A card grows upward from the toolbar's line, never over the window's bottom edge.
            let width = min(available, 440)
            let listHeight = issueList.map { IssueList.height(for: $0.count) + 12 } ?? 0
            let height = 16 + 40 + listHeight + 12 + 28 + 14
            return NSRect(x: anchor.midX - width / 2, y: anchor.midY + Self.height / 2 - height, width: width, height: height)
        }
    }
    private var contentWidth: CGFloat {
        let text = max(title.intrinsicContentSize.width, detail.intrinsicContentSize.width)
        return 52 + text + 16 + (reveal?.intrinsicContentSize.width ?? 0) + 8
    }
    private var card: Bool { if case .result(let tone) = phase { return tone != .success }; return false }
    private var cardRadius: CGFloat { 18 }

    override func layout() {
        super.layout()
        guard phase != .hidden, motion == nil else { return }
        surface.frame = targetFrame
        layoutBody()
    }

    /// Lays the content out for the glass's current size; called every frame while it reshapes.
    private func layoutBody() {
        let size = surface.frame.size
        surface.cornerRadius = min(card ? cardRadius : size.height / 2, size.height / 2)
        lift.frame = surface.frame; lift.isHidden = surface.isHidden; lift.alphaValue = surface.alphaValue
        lift.layer?.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: surface.cornerRadius,
                                        cornerHeight: surface.cornerRadius, transform: nil)
        body.frame = NSRect(origin: .zero, size: size)
        let width = size.width
        let top: CGFloat = card ? 16 : (size.height - 32) / 2
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // The liquid is a capsule of its own inside the glass, inset so its ends follow the outline.
        let inset: CGFloat = 3, height = max(0, size.height - inset * 2)
        let liquid = card ? 0 : max(fraction > 0 ? height : 0, (width - inset * 2) * fraction)
        fill.frame = CGRect(x: inset, y: inset, width: liquid, height: height)
        fill.cornerRadius = height / 2
        shimmer.frame = CGRect(x: -width * 0.4, y: 0, width: width * 0.4, height: height)
        CATransaction.commit()
        progress.frame = body.bounds
        thumbnail.frame = NSRect(x: 10, y: top, width: 32, height: 32)
        status.frame = NSRect(x: 12, y: top + 4, width: 26, height: 24)
        check?.frame = NSRect(x: 10, y: top, width: 32, height: 32)
        let trailing: CGFloat
        if card { trailing = 16 }
        else if let reveal { trailing = reveal.intrinsicContentSize.width + 20 }
        else { trailing = cancel.isHidden ? 16 : 42 }
        title.frame = NSRect(x: 52, y: top - 1, width: max(0, width - 52 - trailing), height: 17)
        detail.frame = NSRect(x: 52, y: top + 17, width: max(0, width - 52 - trailing), height: 15)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        glint.frame = CGRect(x: 0, y: 0, width: width * 0.35, height: size.height)
        CATransaction.commit()
        cancel.frame = NSRect(x: width - 38, y: (size.height - 28) / 2, width: 28, height: 28)
        if let issueList { issueList.frame = NSRect(x: 16, y: top + 44, width: width - 32, height: IssueList.height(for: issueList.count)) }
        var right = width - (card ? 16 : 10)
        for button in [reveal, card ? done : nil].compactMap({ $0 }) {
            let size = button.intrinsicContentSize
            let y = card ? body.bounds.height - 14 - size.height : (body.bounds.height - size.height) / 2
            button.frame = NSRect(x: right - size.width, y: y, width: size.width, height: size.height)
            right -= size.width + 8
        }
        if motion == nil { updateTrackingAreas() }
    }

    // MARK: Reshaping

    private enum Motion { case grow, collapse }
    private struct Reshape {
        let from: NSRect, to: NSRect, kind: Motion, start: CFTimeInterval, duration: CFTimeInterval
        let completion: (() -> Void)?
        var returned = false
    }
    private var motion: Reshape?
    private var link: CADisplayLink?

    /// Frame-driven, so size, corner radius, liquid and content stay in step on every display frame.
    private func reshape(from: NSRect, to: NSRect, motion kind: Motion, completion: (() -> Void)? = nil) {
        link?.invalidate(); link = nil
        // An interrupted motion still delivers its completion; a pending start must never be lost.
        if let pending = motion?.completion { motion = nil; pending() }
        guard canAnimate, !preferences.effectiveReduceMotion, !from.isEmpty else {
            motion = nil; surface.frame = to; body.alphaValue = 1; layoutBody()
            if kind == .collapse { onReturn?() }
            completion?(); return
        }
        motion = Reshape(from: from, to: to, kind: kind, start: CACurrentMediaTime(),
                         duration: kind == .grow ? 0.55 : 0.42, completion: completion)
        surface.frame = from; layoutBody()
        if kind == .grow { body.alphaValue = 0 }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common); self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        guard var motion else { link.invalidate(); return }
        let t = min(1, (link.targetTimestamp - motion.start) / motion.duration)
        // Growth springs slightly past its size; collapse settles without overshoot.
        let p = motion.kind == .grow ? Self.spring(t, damping: 0.72) : Self.spring(t, damping: 1)
        surface.frame = Self.interpolate(motion.from, motion.to, CGFloat(p))
        switch motion.kind {
        case .grow:
            body.alphaValue = CGFloat(max(0, min(1, (t - 0.45) / 0.35)))
        case .collapse:
            body.alphaValue = CGFloat(max(0, 1 - t / 0.3))
            fill.opacity = Float(max(0, 1 - t / 0.45))
            surface.alphaValue = CGFloat(max(0, min(1, (1 - t) / 0.25)))
            if t >= 0.65, !motion.returned { motion.returned = true; self.motion = motion; onReturn?() }
        }
        layoutBody()
        guard t >= 1 else { return }
        link.invalidate(); self.link = nil
        self.motion = nil
        surface.frame = motion.to; layoutBody()
        motion.completion?()
    }

    /// A unit step response; `damping` 1 is critical, below 1 overshoots once and settles by t = 1.
    static func spring(_ t: Double, damping: Double) -> Double {
        guard t < 1 else { return 1 }
        let omega = 9.0, time = t
        if damping >= 1 { return 1 - (1 + omega * time) * exp(-omega * time) }
        let damped = omega * sqrt(1 - damping * damping)
        return 1 - exp(-damping * omega * time) * (cos(damped * time) + damping * omega / damped * sin(damped * time))
    }
    static func interpolate(_ a: NSRect, _ b: NSRect, _ p: CGFloat) -> NSRect {
        NSRect(x: a.minX + (b.minX - a.minX) * p, y: a.minY + (b.minY - a.minY) * p,
               width: max(0, a.width + (b.width - a.width) * p), height: max(0, a.height + (b.height - a.height) * p))
    }
    private var canAnimate: Bool { window?.isVisible == true }

    // MARK: Liquid

    /// A neutral liquid in the label colour's own family: a soft grey on light glass, a faint mist on
    /// dark, so progress reads without bringing a new hue into the workbench.
    private func refreshFill() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let contrast = preferences.effectiveIncreaseContrast
        CATransaction.begin(); CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            fill.backgroundColor = NSColor.labelColor.withAlphaComponent(dark ? (contrast ? 0.24 : 0.14) : (contrast ? 0.16 : 0.08)).cgColor
        }
        shimmer.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(dark ? 0.16 : 0.5).cgColor,
                          NSColor.white.withAlphaComponent(0).cgColor]
        glint.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(dark ? 0.28 : 0.85).cgColor,
                        NSColor.white.withAlphaComponent(0).cgColor]
        CATransaction.commit()
    }
    private func setFraction(_ value: CGFloat, animated: Bool) {
        let old = fill.frame
        fraction = value
        guard motion == nil else { return }
        layoutBody()
        guard animated, canAnimate, !preferences.effectiveReduceMotion else { return }
        for (key, from, to) in [("bounds.size.width", old.width, fill.frame.width), ("position.x", old.midX, fill.frame.midX)] {
            let spring = CASpringAnimation(keyPath: key)
            spring.fromValue = from; spring.toValue = to
            spring.damping = 26; spring.stiffness = 300; spring.mass = 1; spring.duration = spring.settlingDuration
            fill.add(spring, forKey: key)
        }
    }
    private func startShimmer() {
        stopShimmer()
        guard canAnimate, !preferences.effectiveReduceMotion else { return }
        let slide = CABasicAnimation(keyPath: "position.x")
        slide.fromValue = -targetFrame.width * 0.2; slide.toValue = targetFrame.width * 1.2
        slide.duration = 1.8; slide.repeatCount = .infinity
        shimmer.add(slide, forKey: "shimmer")
    }
    private func stopShimmer() { shimmer.removeAnimation(forKey: "shimmer") }

    /// A clean finish: one highlight sweeps the capsule while the glass gives a small squash and settles.
    private func celebrate() {
        let width = surface.frame.width
        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = -width * 0.2; sweep.toValue = width * 1.2
        sweep.duration = 0.6; sweep.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
        let show = CAKeyframeAnimation(keyPath: "opacity"); show.values = [0, 1, 1, 0]; show.keyTimes = [0, 0.15, 0.75, 1]; show.duration = 0.6
        glint.add(sweep, forKey: "sweep"); glint.add(show, forKey: "show")
        // Scale about the glass's centre; AppKit keeps view layers anchored at their origin.
        for layer in [surface.layer, lift.layer].compactMap({ $0 }) {
            let center = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)
            func squash(_ x: CGFloat, _ y: CGFloat) -> NSValue {
                var t = CATransform3DMakeTranslation(center.x, center.y, 0)
                t = CATransform3DScale(t, x, y, 1)
                return NSValue(caTransform3D: CATransform3DTranslate(t, -center.x, -center.y, 0))
            }
            let bounce = CAKeyframeAnimation(keyPath: "transform")
            bounce.values = [squash(1, 1), squash(1.03, 0.92), squash(0.99, 1.03), squash(1, 1)]
            bounce.keyTimes = [0, 0.3, 0.65, 1]; bounce.duration = 0.36
            bounce.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeOut)]
            layer.add(bounce, forKey: "bounce")
        }
    }

    // MARK: Helpers


    /// Drawn in the body's y-down space, once, with Reduce Motion skipping the stroke.
    private func checkmark() -> CAShapeLayer {
        let rect = CGRect(x: 0, y: 0, width: 32, height: 32), path = CGMutablePath()
        path.move(to: CGPoint(x: rect.width * 0.24, y: rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.width * 0.43, y: rect.height * 0.7))
        path.addLine(to: CGPoint(x: rect.width * 0.77, y: rect.height * 0.32))
        let shape = CAShapeLayer(); shape.path = path; shape.fillColor = nil
        effectiveAppearance.performAsCurrentDrawingAppearance { shape.strokeColor = NSColor.labelColor.cgColor }
        shape.lineWidth = 2.4; shape.lineCap = .round; shape.lineJoin = .round
        if canAnimate, !preferences.effectiveReduceMotion {
            let draw = CABasicAnimation(keyPath: "strokeEnd"); draw.fromValue = 0; draw.toValue = 1
            draw.duration = 0.38; draw.beginTime = CACurrentMediaTime() + 0.12; draw.fillMode = .backwards
            draw.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1)
            shape.add(draw, forKey: "draw")
        }
        return shape
    }

    private func announce(_ text: String) {
        NSAccessibility.post(element: NSApp.mainWindow ?? self, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

/// The capsule's content plane: y-down, so its rows lay out from the top like the rest of the stage.
@MainActor
private final class CapsuleBody: NSView {
    override var isFlipped: Bool { true }
}

/// Images that did not export, each with its reason; scrolls past a handful.
@MainActor
private final class IssueList: NSView {
    static let rowHeight: CGFloat = 34
    static func height(for count: Int) -> CGFloat { min(CGFloat(count), 4) * rowHeight }
    let count: Int

    init(_ issues: [ExportOutcome.Issue]) {
        count = issues.count
        super.init(frame: .zero)
        let rows = issues.map { issue -> NSView in
            let icon = NSImageView(image: NSImage(systemSymbolName: issue.failed ? "exclamationmark.circle" : "minus.circle", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold).applying(.init(hierarchicalColor: .secondaryLabelColor))) ?? NSImage())
            icon.setAccessibilityElement(false); icon.unregisterDraggedTypes()
            let name = FraloStyle.text(issue.name, role: .detail)
            name.lineBreakMode = .byTruncatingMiddle; name.maximumNumberOfLines = 1
            name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let reason = FraloStyle.text(issue.reason, role: .caption, secondary: true)
            reason.lineBreakMode = .byTruncatingTail; reason.maximumNumberOfLines = 1; reason.toolTip = issue.reason
            reason.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let text = FraloStyle.stack([name, reason], spacing: 1)
            let row = FraloStyle.stack([icon, text], axis: .horizontal, spacing: 8); row.alignment = .firstBaseline
            row.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
            row.setAccessibilityElement(true); row.setAccessibilityRole(.staticText)
            row.setAccessibilityLabel(L10n.tr("\(issue.name)：\(issue.reason)"))
            return row
        }
        let list = FraloStyle.stack(rows, spacing: 0)
        let scroll = NSScrollView(); ScrollContent.install(list, in: scroll, inset: 0)
        scroll.translatesAutoresizingMaskIntoConstraints = false; addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        setAccessibilityElement(true); setAccessibilityRole(.list); setAccessibilityLabel(L10n.tr("未导出的图片"))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

/// A slow diagonal highlight that keeps crossing the preview while an export runs, clipped to the
/// artwork's own alpha. One unhurried pass, a rest, and again, rather than a flash per image.
@MainActor
final class PreviewShimmer {
    static let period: CFTimeInterval = 2.6
    /// Fraction of each period spent crossing; the rest is a pause.
    static let crossing = 0.62
    private(set) var host: CALayer?
    private let band = CAGradientLayer()
    private let mask = CALayer()
    private weak var canvas: CanvasSurface?

    var isRunning: Bool { host != nil }

    func start(on canvas: CanvasSurface, preferences: DesignPreferences) {
        remove()
        guard !preferences.effectiveReduceMotion, let layer = canvas.layer,
              let image = canvas.image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        self.canvas = canvas
        band.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(0.32).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        band.startPoint = CGPoint(x: 0, y: 0); band.endPoint = CGPoint(x: 1, y: 1)
        band.locations = [-0.3, -0.15, 0]
        mask.contents = image; mask.contentsGravity = .resize
        let host = CALayer(); host.mask = mask; host.addSublayer(band)
        host.compositingFilter = "screenBlendMode"
        layer.addSublayer(host); self.host = host
        relayout()
        let pass = CAKeyframeAnimation(keyPath: "locations")
        pass.values = [[-0.3, -0.15, 0], [1, 1.15, 1.3], [1, 1.15, 1.3]]
        pass.keyTimes = [0, NSNumber(value: Self.crossing), 1]
        pass.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .linear)]
        pass.duration = Self.period; pass.repeatCount = .infinity
        band.add(pass, forKey: "shimmer")
        let appear = CABasicAnimation(keyPath: "opacity"); appear.fromValue = 0; appear.toValue = 1; appear.duration = 0.3
        host.add(appear, forKey: "appear")
    }

    /// Keeps the highlight on the artwork when the preview resizes or zooms.
    func relayout() {
        guard let host, let canvas else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        host.frame = canvas.imageRect
        band.frame = host.bounds; mask.frame = host.bounds
        CATransaction.commit()
    }

    /// Ends with the run, whatever its outcome: the current pass fades rather than snapping off.
    func stop() {
        guard let host else { return }
        self.host = nil
        CATransaction.begin()
        CATransaction.setCompletionBlock { [band] in host.removeFromSuperlayer(); band.removeAllAnimations() }
        let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = host.presentation()?.opacity ?? 1; fade.toValue = 0; fade.duration = 0.25
        host.opacity = 0; host.add(fade, forKey: "fade")
        CATransaction.commit()
    }

    private func remove() {
        host?.removeFromSuperlayer(); host = nil; band.removeAllAnimations(); band.removeFromSuperlayer()
    }
}

/// Export progress on the Dock tile, for when Fralo is behind other windows.
@MainActor
final class DockProgress {
    static let shared = DockProgress()
    private let icon = NSImageView()
    private let bar = NSProgressIndicator()
    private init() {
        bar.style = .bar; bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = 1
        icon.addSubview(bar)
    }
    func show(_ fraction: Double) {
        let size = NSApp.dockTile.size
        icon.frame = NSRect(origin: .zero, size: size); icon.image = NSApp.applicationIconImage
        bar.frame = NSRect(x: size.width * 0.1, y: size.height * 0.06, width: size.width * 0.8, height: 14)
        bar.doubleValue = fraction
        NSApp.dockTile.contentView = icon; NSApp.dockTile.display()
    }
    func clear() {
        guard NSApp.dockTile.contentView === icon else { return }
        NSApp.dockTile.contentView = nil; NSApp.dockTile.display()
    }
}
