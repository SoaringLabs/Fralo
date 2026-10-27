import AppKit

/// A transparent, thin indicator with native scroller dragging and accessibility.
/// It is independent of NSScrollView's system-controlled reserved scrollbar width.
@MainActor
final class PanelScrollIndicator: NSScroller {
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) { drawKnob() }
    override func drawKnob() {
        let native = rect(for: .knob)
        guard native.height > 0 else { return }
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let width: CGFloat = contrast ? 6 : 4
        let knob = NSRect(x: (bounds.width - width) / 2, y: native.minY + 1, width: width, height: max(4, native.height - 2))
        NSColor.labelColor.withAlphaComponent(contrast ? 0.65 : 0.30).setFill()
        NSBezierPath(roundedRect: knob, xRadius: width / 2, yRadius: width / 2).fill()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}

/// The small trailing gutter is constant in both short and overflowing forms.
/// Native scrolling, keyboard navigation and magnification remain NSScrollView's responsibility.
@MainActor
public class PanelScrollView: NSScrollView {
    let positionIndicator = PanelScrollIndicator()
    private var observers: [NSObjectProtocol] = []
    private let gutter: CGFloat = 12

    public override init(frame: NSRect) {
        super.init(frame: frame)
        borderType = .noBorder; drawsBackground = false
        hasVerticalScroller = false; hasHorizontalScroller = false
        positionIndicator.scrollerStyle = .legacy
        positionIndicator.controlSize = .small
        positionIndicator.target = self; positionIndicator.action = #selector(scrollFromIndicator(_:))
        positionIndicator.setAccessibilityLabel("滚动内容")
        addSubview(positionIndicator)
        contentView.postsBoundsChangedNotifications = true
        observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateIndicator() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, (notification.object as? NSView) === self.documentView else { return }
                self.updateIndicator()
            }
        })
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    public override var documentView: NSView? {
        didSet { documentView?.postsFrameChangedNotifications = true; updateIndicator() }
    }
    public override func tile() {
        super.tile()
        var frame = contentView.frame
        frame.size.width = max(0, frame.width - gutter)
        contentView.frame = frame
        positionIndicator.frame = NSRect(x: frame.maxX, y: frame.minY + 2, width: gutter, height: max(0, frame.height - 4))
        updateIndicator()
    }
    public override func layout() { super.layout(); updateIndicator() }
    public override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView); updateIndicator()
    }
    private func updateIndicator() {
        guard let documentView else {
            positionIndicator.isHidden = true; positionIndicator.isEnabled = false; return
        }
        let height = documentView.frame.height, visible = contentView.bounds.height
        let overflow = height - visible
        positionIndicator.isHidden = overflow <= 1 || visible <= 0
        positionIndicator.isEnabled = overflow > 1 && visible > 0
        guard overflow > 1, visible > 0 else { return }
        positionIndicator.knobProportion = min(1, visible / height)
        let offset = (contentView.bounds.minY - documentView.frame.minY) / overflow
        positionIndicator.doubleValue = min(1, max(0, documentView.isFlipped ? offset : 1 - offset))
        positionIndicator.needsDisplay = true
    }
    @objc private func scrollFromIndicator(_ sender: NSScroller) {
        guard let documentView else { return }
        let overflow = max(0, documentView.frame.height - contentView.bounds.height)
        guard overflow > 0 else { return }
        var value = sender.doubleValue
        let page = contentView.bounds.height * 0.85 / overflow
        switch sender.hitPart {
        case .decrementPage: value -= page
        case .incrementPage: value += page
        case .decrementLine: value -= 24 / overflow
        case .incrementLine: value += 24 / overflow
        default: break
        }
        value = min(1, max(0, value))
        var origin = contentView.bounds.origin
        origin.y = documentView.frame.minY + (documentView.isFlipped ? value : 1 - value) * overflow
        contentView.scroll(to: contentView.constrainBoundsRect(NSRect(origin: origin, size: contentView.bounds.size)).origin)
        reflectScrolledClipView(contentView)
    }
}
