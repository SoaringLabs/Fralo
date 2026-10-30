import AppKit
import FraloDesignSystem

@MainActor
private final class WorkspaceRegion: NSView {
    var onLayout: (() -> Void)?
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); onLayout?() }
}

/// Native column ownership lets the toolbar and sidebar share the same boundary.
@MainActor
final class WorkbenchView: NSView {
    let splitView = NSSplitView()
    /// Native behind-window blur for the stage behind the content column, so artwork and the
    /// floating inspector sit on the desktop-tinted backdrop. The system sidebar keeps its own material.
    let stage = MaterialSurface(.workspace)
    let left: DockedSidebar
    let right: FloatingPanel
    let content: NSView
    let toolbarBehavior = CanvasToolbarBehavior(frame: .zero)
    private var workspaceItem: NSSplitViewItem?
    var headerHeight: CGFloat {
        // Accessories animate their safe-area contribution. Only the window toolbar
        // obstruction belongs in our fixed viewing budget; hover must not re-fit art.
        window.map { $0.frame.height - $0.contentLayoutRect.height } ?? region.safeAreaInsets.top
    }
    /// The viewport remains full width. These are document/viewing margins only;
    /// the inspector floats above the same scrolling canvas as the toolbar.
    var viewingInsets: NSEdgeInsets {
        NSEdgeInsets(top: headerHeight + 12, left: 24, bottom: 76,
                     right: inspectorHidden || previewing ? 24 : Self.inspectorWidth + 10 + 24)
    }
    private let region = WorkspaceRegion()
    private(set) var sidebarItem: NSSplitViewItem!
    private var sidebarObservation: NSKeyValueObservation?
    private var storedCollapsed = false
    private var movingSidebar = false
    private var sidebarTransition = 0
    var collapsed: Bool {
        get { storedCollapsed }
        set { setCollapsed(newValue, animated: false) }
    }
    var inspectorHidden = false { didSet { if !animatingInspector { updateVisibility() } } }
    var previewing = false { didSet { applySidebar(animated: false); updateVisibility() } }
    var onGeometryChange: (() -> Void)?
    var onPanelVisibilityChange: (() -> Void)?
    private var animatingInspector = false
    private var transition = 0
    override var isFlipped: Bool { true }
    static let inspectorWidth: CGFloat = 312

    init(left: DockedSidebar, right: FloatingPanel, content: NSView) {
        self.left = left; self.right = right; self.content = content
        super.init(frame: NSRect(x: 0, y: 0, width: 1200, height: 760))
        clipsToBounds = true; region.wantsLayer = true; region.clipsToBounds = true
        splitView.frame = bounds
        left.frame = NSRect(x: 0, y: 0, width: 230, height: bounds.height)
        region.frame = NSRect(x: 231, y: 0, width: bounds.width - 231, height: bounds.height)
        splitView.isVertical = true; splitView.dividerStyle = .thin
        for view in [splitView] {
            view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view)
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
                                         view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor)])
        }
        stage.autoresizingMask = [.width, .height]; stage.frame = region.bounds
        for view in [stage, content, toolbarBehavior, right] { region.addSubview(view) }
        toolbarBehavior.onVisibilityChange = { [weak self] visible in self?.setToolbarBackgroundVisible(visible) }
        region.onLayout = { [weak self] in
            guard let self else { return }
            if !self.animatingInspector { self.arrangeWorkspace() }
            self.onGeometryChange?()
        }
        arrangeWorkspace()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func configure(in controller: NSSplitViewController, contentController: NSViewController? = nil) {
        controller.splitView = splitView
        controller.view = self
        let sidebarController = NSViewController(); sidebarController.view = left
        // The system sidebar owns its material, edge and titlebar band, so the toggle matches other Mac apps.
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = 250; sidebarItem.maximumThickness = 300
        sidebarItem.preferredThicknessFraction = 0.18; sidebarItem.holdingPriority = .defaultHigh
        sidebarItem.canCollapse = true; sidebarItem.canCollapseFromWindowResize = false
        sidebarItem.allowsFullHeightLayout = true; sidebarItem.titlebarSeparatorStyle = .none
        let workspaceController = NSViewController(); workspaceController.view = region
        if let contentController { workspaceController.addChild(contentController) }
        let main = NSSplitViewItem(viewController: workspaceController)
        main.allowsFullHeightLayout = true
        main.minimumThickness = 740; main.titlebarSeparatorStyle = .none
        workspaceItem = main
        controller.addSplitViewItem(sidebarItem); controller.addSplitViewItem(main)
        left.configureHeader(for: sidebarItem)
        sidebarObservation = sidebarItem.observe(\.isCollapsed, options: [.new]) { [weak self] item, _ in
            MainActor.assumeIsolated {
                guard let self, !self.previewing, !self.movingSidebar, self.storedCollapsed != item.isCollapsed else { return }
                self.storedCollapsed = item.isCollapsed
                self.onPanelVisibilityChange?()
            }
        }
        applySidebar(animated: false); updateVisibility()
    }

    override func layout() {
        super.layout()
        if !animatingInspector { arrangeWorkspace() }
        onGeometryChange?()
    }
    func setCollapsed(_ value: Bool, animated: Bool) {
        guard storedCollapsed != value else { return }
        storedCollapsed = value; applySidebar(animated: animated)
        onPanelVisibilityChange?(); needsLayout = true
    }
    private func applySidebar(animated: Bool) {
        guard let sidebarItem else { return }
        let value = collapsed || previewing
        let duration = animated && window != nil ? FraloMotion.duration(.structure, preferences: DesignPreferences()) : 0
        sidebarTransition += 1; let currentTransition = sidebarTransition
        movingSidebar = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            if duration > 0 { sidebarItem.animator().isCollapsed = value }
            else { sidebarItem.isCollapsed = value }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.sidebarTransition == currentTransition else { return }
                // Earlier native animation callbacks must not overwrite the latest requested state.
                self.sidebarItem.isCollapsed = self.collapsed || self.previewing
                self.movingSidebar = false; self.needsLayout = true
                self.onPanelVisibilityChange?()
            }
        })
    }
    func setInspectorHidden(_ value: Bool, animated: Bool) {
        guard inspectorHidden != value else { return }
        let duration = animated && window != nil && !previewing ? FraloMotion.duration(.structure, preferences: DesignPreferences()) : 0
        transition += 1; let currentTransition = transition
        guard duration > 0 else { animatingInspector = false; inspectorHidden = value; arrangeWorkspace(); onGeometryChange?(); return }
        let wasVisible = !right.isHidden
        animatingInspector = true; inspectorHidden = value
        right.isHidden = previewing || (value && !wasVisible)
        onPanelVisibilityChange?()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration; self.arrangeWorkspace(animated: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.transition == currentTransition else { return }
                self.animatingInspector = false; self.updateVisibility(); self.arrangeWorkspace(); self.onGeometryChange?()
            }
        })
    }
    private func updateVisibility() {
        right.isHidden = inspectorHidden || previewing
        needsLayout = true; onPanelVisibilityChange?()
    }
    private func setToolbarBackgroundVisible(_ visible: Bool) {
        guard let window else { return }
        let style: NSTitlebarSeparatorStyle = visible ? .automatic : .none
        // Switching public system traits leaves all rendering to AppKit. Avoid repeated
        // writes during window updates so hover never becomes a layout/render loop.
        if window.titlebarAppearsTransparent == visible { window.titlebarAppearsTransparent = !visible }
        if window.titlebarSeparatorStyle != style { window.titlebarSeparatorStyle = style }
        if workspaceItem?.titlebarSeparatorStyle != style { workspaceItem?.titlebarSeparatorStyle = style }
    }
    private func arrangeWorkspace(animated: Bool = false) {
        let area = region.bounds
        // The floating inspector keeps a 10 pt inset from the window edge.
        let edge: CGFloat = 10, width = Self.inspectorWidth
        let chrome = headerHeight
        let top: CGFloat = chrome + 8
        let height = max(0, area.height - top - edge)
        let rightRect = NSRect(x: inspectorHidden || previewing ? area.width + edge : area.width - edge - width, y: top, width: width, height: height)
        toolbarBehavior.frame = NSRect(x: 0, y: 0, width: area.width, height: chrome)
        for (view, frame) in [(right as NSView, rightRect), (content, area)] {
            if animated { view.animator().frame = frame } else { view.frame = frame }
        }
    }
}
