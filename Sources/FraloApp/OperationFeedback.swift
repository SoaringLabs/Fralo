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
        close.onPress = { [weak self] in self?.dismiss() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { dismissal?.cancel() }

    func show(_ kind: Kind, title: String, detail: String, duration: TimeInterval = 3) {
        dismiss()
        self.kind = kind
        self.title.stringValue = title; self.detail.stringValue = detail
        self.detail.toolTip = detail
        icon.image = NSImage(systemSymbolName: kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill", accessibilityDescription: nil)
        icon.contentTintColor = kind == .success ? .systemGreen : .systemOrange
        isHidden = false
        NSAccessibility.post(element: self, notification: .announcementRequested,
            userInfo: [.announcement: "\(title)。\(detail)", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        // Errors stay readable until dismissed or superseded. No animation or focus change.
        guard kind == .success else { return }
        let current = version
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.version == current else { return }
                self.dismiss()
            }
        }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func dismiss() {
        version += 1; dismissal?.cancel(); dismissal = nil
        kind = nil; isHidden = true
    }
}
