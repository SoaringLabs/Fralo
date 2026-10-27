import AppKit
import FraloDesignSystem

/// Production arrangement only. Shared surfaces and controls own their appearance.
@MainActor
final class WorkbenchView: NSView {
    let workspace = MaterialSurface(.workspace)
    let left: DockedSidebar
    let right: FloatingPanel
    let content: NSView
    var collapsed = false { didSet { if !animatingSidebar { updateVisibility() } } }
    var previewing = false { didSet { updateVisibility() } }
    var onGeometryChange: (() -> Void)?
    private var animatingSidebar = false
    private var transition = 0
    override var isFlipped: Bool { true }

    init(left: DockedSidebar, right: FloatingPanel, content: NSView) {
        self.left = left; self.right = right; self.content = content
        super.init(frame: NSRect(x: 0, y: 0, width: 1200, height: 760))
        clipsToBounds = true
        for view in [workspace, content, left, right] { addSubview(view) }
        updateVisibility(); arrange()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func layout() { super.layout(); if !animatingSidebar { arrange() }; onGeometryChange?() }
    func setCollapsed(_ value: Bool, animated: Bool) {
        guard collapsed != value else { return }
        let duration = animated && window != nil && !previewing ? FraloMotion.duration(.structure, preferences: DesignPreferences()) : 0
        transition += 1
        let currentTransition = transition
        guard duration > 0 else {
            animatingSidebar = false; collapsed = value; arrange(); onGeometryChange?()
            return
        }
        layoutSubtreeIfNeeded()
        animatingSidebar = true
        collapsed = value
        left.isHidden = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            self.arrange(animated: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.transition == currentTransition else { return }
                self.animatingSidebar = false; self.updateVisibility(); self.arrange(); self.onGeometryChange?()
            }
        })
    }
    private func updateVisibility() {
        left.isHidden = collapsed || previewing; right.isHidden = previewing
        needsLayout = true
    }
    private func arrange(animated: Bool = false) {
        workspace.frame = bounds
        let margin = min(30, max(20, bounds.width * 0.0185))
        let gap = min(30, max(18, bounds.width * 0.019))
        let chrome = safeAreaInsets.top
        let compact = bounds.height - chrome < 720
        let top: CGFloat = chrome + (compact ? 22 : 36)
        let bottom: CGFloat = compact ? 22 : 62
        let expandedWidth = min(280, max(230, bounds.width * 0.18))
        let leftWidth: CGFloat = collapsed ? 0 : expandedWidth
        let rightWidth = min(400, max(316, bounds.width * 0.255))
        let height = max(0, bounds.height - top - bottom)
        let leftRect = NSRect(x: collapsed || previewing ? -expandedWidth : 0, y: 0, width: expandedWidth, height: bounds.height)
        let rightRect = NSRect(x: bounds.width - margin - rightWidth, y: top, width: rightWidth, height: height)
        let start = previewing || collapsed ? margin : leftWidth + gap
        let end = previewing ? bounds.width - margin : rightRect.minX - gap
        let centerRect = NSRect(x: start, y: top, width: max(0, end - start), height: height + (compact ? 0 : 30))
        for (view, frame) in [(left as NSView, leftRect), (right, rightRect), (content, centerRect)] {
            if animated { view.animator().frame = frame } else { view.frame = frame }
        }
    }
}
