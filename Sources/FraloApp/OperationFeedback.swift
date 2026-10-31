import AppKit
import FraloDesignSystem

/// One driver owns opacity and translation, including a reversal during dismissal.
@MainActor
final class FeedbackAnimation: NSAnimation {
    var onProgress: ((CGFloat) -> Void)?
    override var currentProgress: NSAnimation.Progress {
        didSet { onProgress?(CGFloat(currentValue)) }
    }
}

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
@MainActor
final class OperationFeedback: NSView {
    enum Kind { case success, failure }
    // A static status message uses the same AppKit material as the product inspector.
    // Native interactive glass can refract the text into a second lens at this small height.
    let surface = MaterialSurface(.panel, radius: 12, useNativeGlass: false)
    let title = FraloStyle.text("", role: .heading)
    let detail = FraloStyle.paragraph("")
    let close = SymbolButton("xmark", label: "关闭操作提示")
    private let icon = NSImageView()
    private(set) var kind: Kind?
    private var dismissal: DispatchWorkItem?
    private var version = 0
    private var transitionID = 0
    private(set) var animation: FeedbackAnimation?
    private(set) var verticalOffset: CGFloat = 0
    private var hiding = false
    private var motionObserver: NSObjectProtocol?

    init() {
        super.init(frame: .zero)
        isHidden = true
        surface.translatesAutoresizingMaskIntoConstraints = false; addSubview(surface)
        // Decorative image views must not intercept the workbench's file-drop routing.
        icon.unregisterDraggedTypes()
        icon.contentTintColor = .labelColor
        icon.setAccessibilityElement(false)
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 20).isActive = true
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.maximumNumberOfLines = 3
        for view in [icon, title, detail, close] {
            view.translatesAutoresizingMaskIntoConstraints = false; surface.contentView.addSubview(view)
        }
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor), surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor), surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.leadingAnchor.constraint(equalTo: surface.contentView.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -8),
            title.topAnchor.constraint(equalTo: surface.contentView.topAnchor, constant: 12),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor), detail.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            detail.bottomAnchor.constraint(equalTo: surface.contentView.bottomAnchor, constant: -12),
            close.trailingAnchor.constraint(equalTo: surface.contentView.trailingAnchor, constant: -10),
            close.topAnchor.constraint(equalTo: surface.contentView.topAnchor, constant: 8),
            close.bottomAnchor.constraint(lessThanOrEqualTo: surface.contentView.bottomAnchor, constant: -8)
        ])
        close.onPress = { [weak self] in self?.dismiss(animated: true) }
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.animation != nil, self.surface.preferences.effectiveReduceMotion else { return }
                self.transitionID += 1
                self.animation?.stop(); self.animation = nil
                self.finishTransition(hidden: self.hiding)
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit {
        dismissal?.cancel()
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
    }

    func show(_ kind: Kind, title: String, detail: String, duration: TimeInterval = 3) {
        let entering = isHidden
        cancelPending()
        self.kind = kind
        self.title.stringValue = title; self.detail.stringValue = detail
        self.detail.toolTip = detail
        icon.image = NSImage(systemSymbolName: kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill", accessibilityDescription: nil)
        icon.contentTintColor = kind == .success ? .systemGreen : .systemOrange
        if entering { applyPresentation(opacity: 0, offset: 6) }
        isHidden = false
        transition(hidden: false, animated: true)
        NSAccessibility.post(element: self, notification: .announcementRequested,
            userInfo: [.announcement: "\(title)。\(detail)", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        // Errors stay readable until dismissed or superseded; feedback never moves focus.
        guard kind == .success else { return }
        let current = version
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.version == current else { return }
                self.dismiss(animated: true)
            }
        }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    /// Context changes clear immediately; user dismissal and expiry animate out.
    func dismiss(animated: Bool = false) {
        cancelPending()
        transition(hidden: true, animated: animated)
    }

    private func cancelPending() {
        version += 1; dismissal?.cancel(); dismissal = nil
        transitionID += 1
        animation?.stop(); animation = nil
    }

    private func applyPresentation(opacity: CGFloat, offset: CGFloat) {
        surface.alphaValue = opacity; verticalOffset = offset
        surface.layer?.setAffineTransform(CGAffineTransform(translationX: 0, y: offset))
    }

    private func finishTransition(hidden: Bool) {
        applyPresentation(opacity: hidden ? 0 : 1, offset: 0)
        isHidden = hidden; hiding = hidden
        if hidden { kind = nil }
    }

    private func transition(hidden: Bool, animated: Bool) {
        hiding = hidden
        guard animated, !isHidden, window?.isVisible == true,
              !surface.preferences.effectiveReduceMotion else {
            finishTransition(hidden: hidden); return
        }
        let startOpacity = surface.alphaValue, startOffset = verticalOffset
        let endOpacity: CGFloat = hidden ? 0 : 1, endOffset: CGFloat = hidden ? 4 : 0
        guard abs(startOpacity - endOpacity) > 0.001 || abs(startOffset - endOffset) > 0.001 else {
            finishTransition(hidden: hidden); return
        }
        let current = transitionID
        let driver = FeedbackAnimation(duration: hidden ? 0.14 : 0.18, animationCurve: .easeInOut)
        driver.animationBlockingMode = .nonblocking; driver.frameRate = 60
        driver.onProgress = { [weak self] progress in
            guard let self, self.transitionID == current else { return }
            self.applyPresentation(opacity: startOpacity + (endOpacity - startOpacity) * progress,
                                   offset: startOffset + (endOffset - startOffset) * progress)
            if progress >= 1 {
                self.animation = nil; self.finishTransition(hidden: hidden)
            }
        }
        animation = driver; driver.start()
    }
}
