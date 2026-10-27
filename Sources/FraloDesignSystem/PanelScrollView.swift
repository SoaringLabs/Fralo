import AppKit

/// Panel content scrolls through native wheel, trackpad, keyboard and accessibility
/// behavior without a visible scrollbar or a width-changing scrollbar gutter.
@MainActor
public class PanelScrollView: NSScrollView {
    public override init(frame: NSRect) {
        super.init(frame: frame)
        borderType = .noBorder; drawsBackground = false
        hasVerticalScroller = false; hasHorizontalScroller = false
        scrollerStyle = .overlay; autohidesScrollers = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}
