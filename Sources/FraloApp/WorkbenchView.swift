import AppKit
import FraloDesignSystem

@MainActor
private final class WorkspaceRegion: NSView {
    var onLayout: (() -> Void)?
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); onLayout?() }
}

/// AppKit drives one eased progress value for the panel and all viewing geometry.
@MainActor
private final class InspectorAnimation: NSAnimation {
    var onProgress: ((CGFloat) -> Void)?
    override var currentProgress: NSAnimation.Progress {
        didSet { onProgress?(CGFloat(currentValue)) }
    }
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
    let headerBackdrop = HeaderBackdrop(frame: .zero)
    /// Artwork currently extends under the header; keeps the backdrop up without hover.
    var contentUnderHeader = false { didSet { if oldValue != contentUnderHeader { updateHeaderBackdrop() } } }
    private var headerEngaged = false
    var headerHeight: CGFloat {
        // Accessories animate their safe-area contribution. Only the window toolbar
        // obstruction belongs in our fixed viewing budget; hover must not re-fit art.
        window.map { $0.frame.height - $0.contentLayoutRect.height } ?? region.safeAreaInsets.top
    }
    /// The viewport remains full width. These are document/viewing margins only;
    /// the inspector floats above the same scrolling canvas as the toolbar.
    var viewingInsets: NSEdgeInsets {
        NSEdgeInsets(top: headerHeight + 12, left: 24, bottom: 76,
                     right: 24 + (Self.inspectorWidth + Self.inspectorInset) * inspectorReveal)
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
    private var requestedInspectorHidden = false
    var inspectorHidden: Bool {
        get { requestedInspectorHidden }
        set { requestedInspectorHidden = newValue; settleInspector(); updateVisibility() }
    }
    var previewing = false { didSet { settleInspector(); applySidebar(animated: false); updateVisibility() } }
    var motionPreferences = DesignPreferences() {
        didSet { if motionPreferences.effectiveReduceMotion { settleInspector(); updateVisibility() } }
    }
    private var inspectorReveal: CGFloat = 1
    private var inspectorAnimation: InspectorAnimation?
    private var motionObservation: NSObjectProtocol?
    var onGeometryChange: (() -> Void)?
    var onPanelVisibilityChange: (() -> Void)?
    private var transition = 0
    override var isFlipped: Bool { true }
    static let inspectorWidth: CGFloat = 312
    /// Clears the six-point overlay knob at the window's trailing edge, with room to spare.
    static let inspectorInset: CGFloat = 16

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
        for view in [stage, content, headerBackdrop, toolbarBehavior, right] { region.addSubview(view) }
        toolbarBehavior.onVisibilityChange = { [weak self] visible in self?.headerEngaged = visible; self?.updateHeaderBackdrop() }
        region.onLayout = { [weak self] in
            guard let self else { return }
            self.arrangeWorkspace()
            self.onGeometryChange?()
        }
        motionObservation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.motionPreferences.effectiveReduceMotion else { return }
                self.settleInspector(); self.updateVisibility()
            }
        }
        arrangeWorkspace()
    }
    deinit {
        if let motionObservation { NSWorkspace.shared.notificationCenter.removeObserver(motionObservation) }
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
        arrangeWorkspace()
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
        guard inspectorHidden != value else {
            if !animated { settleInspector(); updateVisibility() }
            return
        }
        let duration = animated && window != nil && !previewing ? FraloMotion.duration(.structure, preferences: motionPreferences) : 0
        transition += 1; let currentTransition = transition
        inspectorAnimation?.stop(); inspectorAnimation = nil
        guard duration > 0 else { inspectorHidden = value; return }
        let start = inspectorReveal, target: CGFloat = value ? 0 : 1
        requestedInspectorHidden = value
        // Keep the panel visible until its slide finishes, including when reversing halfway.
        right.isHidden = false
        onPanelVisibilityChange?()
        let animation = InspectorAnimation(duration: duration, animationCurve: .easeInOut)
        animation.animationBlockingMode = .nonblocking
        animation.frameRate = 60
        animation.onProgress = { [weak self] progress in
            guard let self, self.transition == currentTransition else { return }
            self.inspectorReveal = start + (target - start) * progress
            self.arrangeWorkspace(); self.onGeometryChange?()
            if progress >= 1 {
                self.inspectorAnimation = nil
                self.updateVisibility()
            }
        }
        inspectorAnimation = animation; animation.start()
    }
    private func settleInspector() {
        transition += 1
        inspectorAnimation?.stop(); inspectorAnimation = nil
        inspectorReveal = inspectorHidden || previewing ? 0 : 1
        arrangeWorkspace(); onGeometryChange?()
    }
    private func updateVisibility() {
        right.isHidden = inspectorHidden || previewing
        needsLayout = true; onPanelVisibilityChange?()
    }
    private func updateHeaderBackdrop() {
        headerBackdrop.setShown(headerEngaged || contentUnderHeader)
    }
    private func arrangeWorkspace() {
        let area = region.bounds
        // The floating inspector stays clear of the full-height scroller at the window edge.
        let edge = Self.inspectorInset, width = Self.inspectorWidth
        let chrome = headerHeight
        let top: CGFloat = chrome + 8
        let height = max(0, area.height - top - edge)
        let rightRect = NSRect(x: area.width + edge - (width + 2 * edge) * inspectorReveal, y: top, width: width, height: height)
        toolbarBehavior.frame = NSRect(x: 0, y: 0, width: area.width, height: chrome)
        headerBackdrop.frame = toolbarBehavior.frame
        right.frame = rightRect
        content.frame = area
    }
}
