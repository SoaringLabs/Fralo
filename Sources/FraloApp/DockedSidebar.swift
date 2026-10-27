import AppKit
import FraloDesignSystem

/// A window region, with no floating-panel border, radius or shadow.
@MainActor
final class DockedSidebar: NSView {
    let surface = MaterialSurface(.workspace)
    let body: NSView

    init(header: NSView, body: NSView, footer: NSView) {
        self.body = body
        super.init(frame: .zero)
        surface.material = .sidebar
        for view in [surface, header, body, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor), surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor), surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            header.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            body.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12), body.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
        setAccessibilityElement(false)
        setAccessibilityLabel("图片列表")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}
