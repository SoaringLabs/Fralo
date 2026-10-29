import AppKit
import FraloDesignSystem

/// The sidebar keeps the system split item's material. Only the fixed heading
/// overlays the list; the scroll view itself extends to the column's edges.
@MainActor
final class DockedSidebar: NSView {
    let body: NSView
    let heading: NSView
    private let headerContainer: SidebarHeading
    private let usesNativeHeader: Bool
    override var isFlipped: Bool { true }

    init(header: NSView, body: NSView, footer: NSView, usesNativeHeader: Bool = true) {
        self.body = body; heading = header
        if #available(macOS 26.0, *) { self.usesNativeHeader = usesNativeHeader }
        else { self.usesNativeHeader = false }
        headerContainer = SidebarHeading(header: header, usesMaterial: !self.usesNativeHeader)
        super.init(frame: .zero)
        for view in [body, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: topAnchor), body.bottomAnchor.constraint(equalTo: footer.topAnchor),
            body.leadingAnchor.constraint(equalTo: leadingAnchor), body.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
        let collapsedFooter = footer.heightAnchor.constraint(equalToConstant: 0)
        collapsedFooter.priority = .defaultLow; collapsedFooter.isActive = true
        if !self.usesNativeHeader {
            headerContainer.translatesAutoresizingMaskIntoConstraints = false; addSubview(headerContainer)
            NSLayoutConstraint.activate([
                headerContainer.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
                headerContainer.leadingAnchor.constraint(equalTo: leadingAnchor), headerContainer.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        }
        if let scroll = body as? NSScrollView {
            scroll.hasVerticalScroller = true
            scroll.verticalScroller = SidebarScroller()
            scroll.verticalScroller?.controlSize = .small
            // Keep native visibility preferences, but draw the same thin, trackless
            // knob in both legacy/Always and overlay presentation.
            scroll.scrollerStyle = NSScroller.preferredScrollerStyle
            scroll.scrollerKnobStyle = .default
            // One inset budget: 15pt to the right edge leaves a 7pt gap to the
            // six-point knob, in both native styles, without a second gutter.
            if let list = scroll as? BatchList {
                list.rowHorizontalInset = 10; list.rowTrailingMargin = 15
            }
        }
        setAccessibilityElement(false)
        setAccessibilityLabel("图片列表")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    /// Native split accessories live outside this view's descendant tree.
    func containsSidebarView(_ view: NSView) -> Bool {
        view.isDescendant(of: self) || view.isDescendant(of: headerContainer)
    }

    func configureHeader(for item: NSSplitViewItem) {
        if #available(macOS 26.0, *), usesNativeHeader {
            let accessory = NSSplitViewItemAccessoryViewController()
            accessory.automaticallyAppliesContentInsets = false
            accessory.view = headerContainer
            // Automatic draws a hard edge for this unboxed title. The native soft
            // edge matches the supplied reference; keep the heading legible in QA.
            if #available(macOS 26.1, *) { accessory.preferredScrollEdgeEffectStyle = .soft }
            item.addTopAlignedAccessoryViewController(accessory)
        }
    }

    override func layout() {
        super.layout()
        guard !usesNativeHeader, let scroll = body as? NSScrollView else { return }
        let top = headerContainer.convert(headerContainer.bounds, to: self).maxY
        scroll.automaticallyAdjustsContentInsets = false
        if abs(scroll.contentInsets.top - top) > 0.5 {
            let wasAtTop = abs(scroll.contentView.bounds.minY + scroll.contentInsets.top) < 1
            scroll.contentInsets = NSEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
            scroll.scrollerInsets = NSEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
            if wasAtTop {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: -top))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
    }
}

/// Receives clicks in the heading's blank space instead of the obscured rows.
@MainActor
private final class SidebarHeading: NSView {
    private let effect: NSVisualEffectView?
    private var observation: NSObjectProtocol?
    override var isFlipped: Bool { true }

    init(header: NSView, usesMaterial: Bool) {
        effect = usesMaterial ? NSVisualEffectView() : nil
        super.init(frame: .zero)
        if let effect {
            effect.material = .headerView; effect.blendingMode = .withinWindow
            effect.state = .followsWindowActiveState
            effect.translatesAutoresizingMaskIntoConstraints = false; addSubview(effect)
            NSLayoutConstraint.activate([effect.leadingAnchor.constraint(equalTo: leadingAnchor), effect.trailingAnchor.constraint(equalTo: trailingAnchor),
                                         effect.topAnchor.constraint(equalTo: topAnchor), effect.bottomAnchor.constraint(equalTo: bottomAnchor)])
            wantsLayer = true
            observation = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refreshMaterial() } }
            refreshMaterial()
        }
        header.translatesAutoresizingMaskIntoConstraints = false; addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 6), header.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18), header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { if let observation { NSWorkspace.shared.notificationCenter.removeObserver(observation) } }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshMaterial() }
    private func refreshMaterial() {
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        effect?.isHidden = opaque
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = opaque ? NSColor.windowBackgroundColor.cgColor : nil
        }
    }
}
