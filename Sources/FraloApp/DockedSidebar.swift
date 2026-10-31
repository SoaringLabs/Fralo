import AppKit
import FraloDesignSystem

/// Fixed accessories overlay the list, which extends beneath both scroll edges.
@MainActor
final class DockedSidebar: NSView {
    let body: NSView
    let heading: NSView
    private let headerContainer: SidebarHeading
    private let footerContainer: SidebarFooter
    private let usesNativeHeader: Bool
    private var setNativeFooterVisible: ((Bool) -> Void)?
    private var bodyBottom: NSLayoutConstraint!
    var showsFooter = false {
        didSet {
            guard showsFooter != oldValue else { return }
            footerContainer.setVisible(showsFooter)
            setNativeFooterVisible?(showsFooter)
            // Preserve the existing legacy knob clearance when there is no footer.
            bodyBottom.constant = usesNativeHeader || showsFooter ? 0 : -10
            needsLayout = true
        }
    }
    override var isFlipped: Bool { true }

    init(header: NSView, body: NSView, footer: NSView, usesNativeHeader: Bool = true) {
        self.body = body; heading = header
        if #available(macOS 26.0, *) { self.usesNativeHeader = usesNativeHeader }
        else { self.usesNativeHeader = false }
        headerContainer = SidebarHeading(header: header, usesMaterial: !self.usesNativeHeader)
        footerContainer = SidebarFooter(content: footer, usesMaterial: !self.usesNativeHeader)
        super.init(frame: .zero)
        body.translatesAutoresizingMaskIntoConstraints = false; addSubview(body)
        bodyBottom = body.bottomAnchor.constraint(equalTo: bottomAnchor, constant: self.usesNativeHeader ? 0 : -10)
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: topAnchor), bodyBottom,
            body.leadingAnchor.constraint(equalTo: leadingAnchor), body.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        if !self.usesNativeHeader {
            headerContainer.translatesAutoresizingMaskIntoConstraints = false; addSubview(headerContainer)
            footerContainer.translatesAutoresizingMaskIntoConstraints = false; addSubview(footerContainer)
            NSLayoutConstraint.activate([
                headerContainer.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
                headerContainer.leadingAnchor.constraint(equalTo: leadingAnchor), headerContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
                footerContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
                footerContainer.leadingAnchor.constraint(equalTo: leadingAnchor), footerContainer.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        }
        if let scroll = body as? NSScrollView {
            scroll.hasVerticalScroller = true
            scroll.verticalScroller = ThinScroller()
            scroll.verticalScroller?.controlSize = .small
            // Keep native visibility preferences, but draw the same thin, trackless
            // knob in both legacy/Always and overlay presentation.
            scroll.scrollerStyle = NSScroller.preferredScrollerStyle
            scroll.scrollerKnobStyle = .default
            // One inset budget: 15pt to the right edge leaves a 7pt gap to the
            // six-point knob, in both native styles, without a second gutter.
            if let list = scroll as? BatchList {
                list.rowHorizontalInset = 10; list.rowTrailingMargin = 15
                list.contentTopPadding = 6
            }
        }
        setAccessibilityElement(false)
        setAccessibilityLabel("图片列表")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    /// Native split accessories live outside this view's descendant tree.
    func containsSidebarView(_ view: NSView) -> Bool {
        view.isDescendant(of: self) || view.isDescendant(of: headerContainer) || view.isDescendant(of: footerContainer)
    }

    /// Files dropped anywhere in the sidebar join the batch, as on the stage.
    var dropRouter: FileDropRouter? {
        didSet { if dropRouter != nil { registerForDraggedTypes([.fileURL]) } else { unregisterDraggedTypes() } }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dropRouter?.entered(sender) ?? [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dropRouter?.updated(sender) ?? [] }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropRouter?.exited() }
    override func draggingEnded(_ sender: NSDraggingInfo) { dropRouter?.ended() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { dropRouter?.updated(sender) == .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { dropRouter?.perform(sender) ?? false }

    /// Shown in place of the rows while the batch is empty, below the fixed heading.
    func installPlaceholder(_ placeholder: NSView) {
        placeholder.translatesAutoresizingMaskIntoConstraints = false; addSubview(placeholder)
        let top = usesNativeHeader ? placeholder.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 4)
            : placeholder.topAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: 4)
        NSLayoutConstraint.activate([top, placeholder.leadingAnchor.constraint(equalTo: leadingAnchor), placeholder.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     placeholder.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10)])
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
            let bottom = NSSplitViewItemAccessoryViewController()
            bottom.automaticallyAppliesContentInsets = false
            bottom.view = footerContainer
            bottom.isHidden = !showsFooter
            if #available(macOS 26.1, *) { bottom.preferredScrollEdgeEffectStyle = .soft }
            item.addBottomAlignedAccessoryViewController(bottom)
            setNativeFooterVisible = { [weak bottom] visible in bottom?.isHidden = !visible }
        }
    }

    override func layout() {
        super.layout()
        guard !usesNativeHeader, let scroll = body as? NSScrollView else { return }
        let top = headerContainer.convert(headerContainer.bounds, to: self).maxY
        let bottom = showsFooter ? footerContainer.bounds.height : 0
        scroll.automaticallyAdjustsContentInsets = false
        if abs(scroll.contentInsets.top - top) > 0.5 || abs(scroll.contentInsets.bottom - bottom) > 0.5 {
            let wasAtTop = abs(scroll.contentView.bounds.minY + scroll.contentInsets.top) < 1
            // AppKit also applies contentInsets to the scroller; a matching
            // scrollerInsets.top would add the fixed heading's height twice.
            scroll.contentInsets = NSEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
            if wasAtTop {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: -top))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
    }
}

/// Extra breathing room above the caption; no opaque strip on native scroll edges.
@MainActor
private final class SidebarFooter: NSView {
    private let content: NSView
    private let effect: NSVisualEffectView?
    private var observation: NSObjectProtocol?
    private var height: NSLayoutConstraint!
    override var isFlipped: Bool { true }

    init(content: NSView, usesMaterial: Bool) {
        self.content = content
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
        }
        content.translatesAutoresizingMaskIntoConstraints = false; addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            content.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1)
        ])
        height = heightAnchor.constraint(equalToConstant: 0); height.isActive = true
        isHidden = true; setAccessibilityElement(false)
        refreshMaterial()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { if let observation { NSWorkspace.shared.notificationCenter.removeObserver(observation) } }
    func setVisible(_ visible: Bool) {
        // 14pt above, 12pt below; hiding removes the native safe-area reservation too.
        height.constant = visible ? content.fittingSize.height + 26 : 0
        isHidden = !visible
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshMaterial() }
    private func refreshMaterial() {
        guard effect != nil else { return }
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        effect?.isHidden = opaque
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = opaque ? NSColor.windowBackgroundColor.cgColor : nil
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
