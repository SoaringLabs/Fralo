import AppKit

/// The sidebar column's content. The system sidebar split item supplies the material,
/// edges and collapse behavior, so this view stays transparent.
@MainActor
final class DockedSidebar: NSView {
    let body: NSView

    init(header: NSView, body: NSView, footer: NSView) {
        self.body = body
        super.init(frame: .zero)
        for view in [header, body, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            // The traffic lights and sidebar toggle own the titlebar band above the header.
            header.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18), header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            body.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10), body.bottomAnchor.constraint(equalTo: footer.topAnchor),
            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
        // An empty footer has no intrinsic height; without this the split view's collapse can hand it
        // all the space and leave the list at zero height after the sidebar expands again.
        let collapsedFooter = footer.heightAnchor.constraint(equalToConstant: 0)
        collapsedFooter.priority = .defaultLow; collapsedFooter.isActive = true
        setAccessibilityElement(false)
        setAccessibilityLabel("图片列表")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}
