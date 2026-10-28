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
    let workspace = MaterialSurface(.workspace)
    let left: DockedSidebar
    let right: FloatingPanel
    let content: NSView
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

    init(left: DockedSidebar, right: FloatingPanel, content: NSView) {
        self.left = left; self.right = right; self.content = content
        super.init(frame: NSRect(x: 0, y: 0, width: 1200, height: 760))
        clipsToBounds = true; region.wantsLayer = true; region.clipsToBounds = true
        splitView.frame = bounds
        left.frame = NSRect(x: 0, y: 0, width: 230, height: bounds.height)
        region.frame = NSRect(x: 231, y: 0, width: bounds.width - 231, height: bounds.height)
        splitView.isVertical = true; splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false; addSubview(splitView)
        NSLayoutConstraint.activate([splitView.leadingAnchor.constraint(equalTo: leadingAnchor), splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
                                     splitView.topAnchor.constraint(equalTo: topAnchor), splitView.bottomAnchor.constraint(equalTo: bottomAnchor)])
        for view in [workspace, content, right] { region.addSubview(view) }
        region.onLayout = { [weak self] in
            guard let self else { return }
            if !self.animatingInspector { self.arrangeWorkspace() }
            self.onGeometryChange?()
        }
        arrangeWorkspace()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func configure(in controller: NSSplitViewController) {
        controller.splitView = splitView
        controller.view = self
        let sidebarController = NSViewController(); sidebarController.view = left
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = 230; sidebarItem.maximumThickness = 280
        sidebarItem.preferredThicknessFraction = 0.18; sidebarItem.holdingPriority = .defaultHigh
        sidebarItem.canCollapse = true; sidebarItem.canCollapseFromWindowResize = false
        sidebarItem.allowsFullHeightLayout = true; sidebarItem.titlebarSeparatorStyle = .none
        let workspaceController = NSViewController(); workspaceController.view = region
        let main = NSSplitViewItem(viewController: workspaceController)
        main.minimumThickness = 740; main.titlebarSeparatorStyle = .none
        controller.addSplitViewItem(sidebarItem); controller.addSplitViewItem(main)
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
    private func arrangeWorkspace(animated: Bool = false) {
        let area = region.bounds
        workspace.frame = area
        let margin: CGFloat = 24, gap: CGFloat = 24
        let chrome = region.safeAreaInsets.top
        let compact = area.height - chrome < 720
        let top: CGFloat = chrome + (compact ? 22 : 30)
        let bottom: CGFloat = compact ? 22 : 62
        let height = max(0, area.height - top - bottom)
        let rightRect = NSRect(x: inspectorHidden || previewing ? area.width + margin : area.width - margin - 360, y: top, width: 360, height: height)
        let end = inspectorHidden || previewing ? area.width - margin : rightRect.minX - gap
        let centerRect = NSRect(x: margin, y: top, width: max(0, end - margin), height: height + (compact ? 0 : 30))
        for (view, frame) in [(right as NSView, rightRect), (content, centerRect)] {
            if animated { view.animator().frame = frame } else { view.frame = frame }
        }
    }
}
