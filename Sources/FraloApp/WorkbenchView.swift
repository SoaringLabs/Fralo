import AppKit
import FraloDesignSystem

/// Production arrangement only. Shared surfaces and controls own their appearance.
@MainActor
final class WorkbenchView: NSView {
    let workspace = MaterialSurface(.workspace)
    let left: FloatingPanel
    let right: FloatingPanel
    let rail = CollapsedRail()
    let content: NSView
    var collapsed = false { didSet { updateVisibility() } }
    var previewing = false { didSet { updateVisibility() } }
    var onGeometryChange: (() -> Void)?
    override var isFlipped: Bool { true }

    init(left: FloatingPanel, right: FloatingPanel, content: NSView) {
        self.left = left; self.right = right; self.content = content
        super.init(frame: NSRect(x: 0, y: 0, width: 1200, height: 760))
        for view in [workspace, content, left, rail, right] { addSubview(view) }
        updateVisibility(); arrange()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func layout() { super.layout(); arrange(); onGeometryChange?() }
    func setCollapsed(_ value: Bool, animated: Bool) {
        guard collapsed != value else { return }
        let duration = animated ? FraloMotion.duration(.structure, preferences: DesignPreferences()) : 0
        left.isHidden = false; rail.isHidden = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            self.collapsed = value
            self.left.isHidden = false; self.rail.isHidden = false
            self.left.alphaValue = value ? 1 : 0; self.rail.alphaValue = value ? 0 : 1
            self.left.animator().alphaValue = value ? 0 : 1
            self.rail.animator().alphaValue = value ? 1 : 0
            self.arrange(animated: duration > 0)
        }, completionHandler: { [weak self] in MainActor.assumeIsolated { self?.updateVisibility() } })
    }
    private func updateVisibility() {
        left.isHidden = collapsed || previewing; rail.isHidden = !collapsed || previewing; right.isHidden = previewing
        left.alphaValue = collapsed ? 0 : 1; rail.alphaValue = collapsed ? 1 : 0
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
        let expandedWidth = min(268, max(206, bounds.width * 0.169))
        let leftWidth: CGFloat = collapsed ? 56 : expandedWidth
        let rightWidth = min(334, max(282, bounds.width * 0.211))
        let height = max(0, bounds.height - top - bottom)
        let leftRect = NSRect(x: margin, y: top, width: leftWidth, height: height)
        let rightRect = NSRect(x: bounds.width - margin - rightWidth, y: top, width: rightWidth, height: height)
        let start = previewing ? margin : leftRect.maxX + gap
        let end = previewing ? bounds.width - margin : rightRect.minX - gap
        let centerRect = NSRect(x: start, y: top, width: max(0, end - start), height: height + (compact ? 0 : 30))
        for (view, frame) in [(left as NSView, NSRect(x: margin, y: top, width: expandedWidth, height: height)),
                              (rail as NSView, NSRect(x: margin, y: top, width: 56, height: height)), (right, rightRect), (content, centerRect)] {
            if animated { view.animator().frame = frame } else { view.frame = frame }
        }
    }
}
