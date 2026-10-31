import AppKit
import FraloCore
import FraloDesignSystem

/// What a drag would add, judged before it is dropped: supported files, folder contents,
/// and anything the batch already holds or cannot read.
struct DropSummary: Equatable {
    var accepted: [URL] = []
    var images = 0
    var duplicates = 0
    var unsupported = 0
    var canDrop: Bool { images > 0 }

    init(urls: [URL], existing: Set<String> = []) {
        for url in urls {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                let inputs = (try? InputCollector.collect([url])) ?? []
                let fresh = inputs.filter { !existing.contains($0.id) }.count
                images += fresh; duplicates += inputs.count - fresh
                if fresh > 0 { accepted.append(url) }
            } else if InputCollector.extensions.contains(url.pathExtension.lowercased()) {
                if existing.contains(ImageInput(url: url).id) { duplicates += 1 } else { images += 1; accepted.append(url) }
            } else { unsupported += 1 }
        }
    }

    /// The headline and supporting line shown while the drag is over the window.
    func message(appending: Bool, device: String) -> (title: String, detail: String) {
        guard canDrop else {
            if unsupported == 0 && duplicates > 0 { return ("这些图片已在批次中", "同一文件不会重复导入") }
            return (unsupported + duplicates > 1 ? "无法添加这些文件" : "无法添加这个文件", "仅支持 PNG / JPEG 图片")
        }
        let title = appending ? "松开以追加 \(images) 张图片到批次" : "松开以添加 \(images) 张图片"
        let skipped = unsupported + duplicates
        return (title, skipped > 0 ? "将添加 \(images) 张 · 忽略 \(skipped) 个文件" : "将按 \(device) 套框")
    }
}

/// Shared dragging-destination logic, so the stage and the sidebar react to the same drag identically.
@MainActor
final class FileDropRouter {
    var evaluate: ([URL]) -> DropSummary = { DropSummary(urls: $0) }
    var onChange: ((DropSummary?) -> Void)?
    var onDrop: (([URL]) -> Void)?
    /// Whether a drag can still be in progress. A drag ends on mouse-up, so this catches sessions
    /// that end without draggingExited or draggingEnded reaching us (e.g. a system shortcut taking over).
    var isDragging: () -> Bool = { NSEvent.pressedMouseButtons & 1 != 0 }
    private var cached: (changeCount: Int, summary: DropSummary)?
    private var active = false
    private var watchdog: Timer?

    private func summary(_ info: NSDraggingInfo) -> DropSummary {
        let board = info.draggingPasteboard
        if let cached, cached.changeCount == board.changeCount { return cached.summary }
        let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let result = evaluate(urls); cached = (board.changeCount, result)
        return result
    }
    func entered(_ info: NSDraggingInfo) -> NSDragOperation {
        let result = summary(info); begin(result)
        return result.canDrop ? .copy : []
    }
    func updated(_ info: NSDraggingInfo) -> NSDragOperation { summary(info).canDrop ? .copy : [] }
    func exited() { clear() }
    func ended() { clear() }
    func perform(_ info: NSDraggingInfo) -> Bool {
        let result = summary(info); clear()
        guard result.canDrop else { return false }
        onDrop?(result.accepted); return true
    }
    func begin(_ summary: DropSummary) {
        active = true; onChange?(summary)
        guard watchdog == nil else { return }
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if let self, !self.isDragging() { self.clear() } }
        }
        RunLoop.main.add(timer, forMode: .common); watchdog = timer
    }
    /// Idempotent: every end of a drag funnels here, and only the first one resets the feedback.
    private func clear() {
        cached = nil; watchdog?.invalidate(); watchdog = nil
        guard active else { return }
        active = false; onChange?(nil)
    }
}

/// The empty batch: the selected device's own frame, drawn without a screenshot,
/// with its screen as the drop target and the place to start.
@MainActor
final class EmptyStageView: NSView {
    struct Device {
        let image: NSImage
        /// Screen rectangle and corner radius as fractions of the image (top-left origin).
        let screen: CGRect
        let cornerRadius: CGFloat
        let display: DisplayKind
        let orientation: Orientation
        var browserAppearance: BrowserAppearance = .light
    }
    enum Feedback: Equatable { case idle, accepting, rejecting }

    let zone: DropZoneView
    var device: Device? { didSet { needsLayout = true; needsDisplay = true; refreshZoneAppearance() } }
    /// Keeps the frame clear of the header and the floating inspector.
    var viewingInsets = NSEdgeInsetsZero { didSet { needsLayout = true; needsDisplay = true } }
    private(set) var isShowingError = false
    private let tint = CALayer()
    override var isFlipped: Bool { true }

    init(action: ActionButton) {
        zone = DropZoneView(action: action)
        super.init(frame: .zero)
        wantsLayer = true
        tint.opacity = 0; layer?.addSublayer(tint)
        addSubview(zone)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func showEmpty(title: String, detail: String) {
        isShowingError = false
        zone.show(icon: "photo.badge.plus", title: title, detail: detail, hint: "或按 ⌘V 粘贴")
        zone.apply(.idle, animated: false); setFeedback(.idle, animated: false)
        needsLayout = true; needsDisplay = true; refreshZoneAppearance()
    }
    func showError(_ message: String) {
        isShowingError = true
        zone.show(icon: "exclamationmark.triangle", title: "无法生成成品", detail: message, hint: nil)
        zone.apply(.error, animated: false); setFeedback(.idle, animated: false)
        needsLayout = true; needsDisplay = true; refreshZoneAppearance()
    }
    func showDrag(_ feedback: Feedback, title: String, detail: String) {
        let icon = feedback == .accepting ? "arrow.down.circle" : "nosign"
        zone.show(icon: icon, title: title, detail: detail, hint: nil)
        zone.apply(feedback == .accepting ? .accepting : .rejecting, animated: true)
        setFeedback(feedback, animated: true)
    }
    private func setFeedback(_ feedback: Feedback, animated: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? FraloMotion.duration(.selection) : 0)
        CATransaction.setDisableActions(!animated || FraloMotion.duration(.selection) == 0)
        tint.opacity = feedback == .accepting ? 1 : 0
        CATransaction.commit()
    }

    /// Fits the frame within the viewing area, leaving a little air above and below.
    var deviceRect: NSRect? {
        guard let device, !isShowingError else { return nil }
        let area = NSRect(x: viewingInsets.left, y: viewingInsets.top, width: bounds.width - viewingInsets.left - viewingInsets.right,
                          height: bounds.height - viewingInsets.top - viewingInsets.bottom)
        let size = device.image.size
        guard area.width > 40, area.height > 40, size.width > 0, size.height > 0 else { return nil }
        let scale = min(area.width * 0.92 / size.width, area.height * 0.9 / size.height, 760 / size.height)
        let fitted = NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        return NSRect(x: (area.midX - fitted.width / 2).rounded(), y: (area.midY - fitted.height / 2).rounded(), width: fitted.width, height: fitted.height)
    }
    var screenRect: NSRect? {
        guard let device, let frame = deviceRect else { return nil }
        return NSRect(x: frame.minX + device.screen.minX * frame.width, y: frame.minY + device.screen.minY * frame.height,
                      width: device.screen.width * frame.width, height: device.screen.height * frame.height)
    }

    override func layout() {
        super.layout()
        tint.frame = bounds
        guard let device, let screen = screenRect, let frame = deviceRect else {
            // Without a frame (an error, or before the first render), the guidance sits in the viewing area.
            let area = NSRect(x: viewingInsets.left, y: viewingInsets.top, width: max(0, bounds.width - viewingInsets.left - viewingInsets.right),
                              height: max(0, bounds.height - viewingInsets.top - viewingInsets.bottom))
            zone.cornerRadius = 18
            zone.frame = NSRect(x: area.midX - min(area.width, 380) / 2, y: area.midY - min(area.height, 320) / 2, width: min(area.width, 380), height: min(area.height, 320)).integral
            return
        }
        let unit = max(10, min(18, screen.width / 22))
        var inset = NSEdgeInsets(top: unit, left: unit, bottom: unit, right: unit)
        if device.display == .phone {
            // Clear the Dynamic Island, which sits on the screen's top edge (trailing edge in landscape).
            let island = min(screen.width, screen.height) * 0.12 + unit * 0.5
            if device.orientation == .portrait { inset.top = island } else { inset.right = island }
        }
        zone.cornerRadius = max(8, device.cornerRadius * frame.width - unit)
        zone.frame = NSRect(x: screen.minX + inset.left, y: screen.minY + inset.top,
                            width: max(0, screen.width - inset.left - inset.right), height: max(0, screen.height - inset.top - inset.bottom)).integral
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let device, let frame = deviceRect else { return }
        NSGraphicsContext.saveGraphicsState()
        // A viewing-only contact shadow, as on the stage; never part of the export.
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.5 : 0.2)
        shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -16); shadow.set()
        device.image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
        if device.display == .browser, let screen = screenRect {
            // Viewing-only blank page follows the export shell, independently of the app.
            pageColor.setFill(); NSBezierPath(rect: screen).fill()
        }
    }
    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
    private var pageColor: NSColor { device?.browserAppearance == .dark ? NSColor(srgbRed: 0.125, green: 0.129, blue: 0.141, alpha: 1) : NSColor(srgbRed: 0.97, green: 0.97, blue: 0.975, alpha: 1) }

    /// Match the drop target's text and controls to the surface they're drawn over.
    private func refreshZoneAppearance() {
        if !isShowingError, let device {
            let darkGlass = device.display != .browser || device.browserAppearance == .dark
            zone.appearance = NSAppearance(named: darkGlass ? .darkAqua : .aqua)
        } else { zone.appearance = nil }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            tint.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.07).cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); refreshZoneAppearance(); needsDisplay = true
    }
}

/// The dashed target inside the screen. Its own appearance is dark on device glass,
/// so system label colors and the shared buttons stay legible on either window appearance.
@MainActor
final class DropZoneView: NSView {
    enum Style { case idle, accepting, rejecting, error }
    let action: ActionButton
    private let icon = NSImageView()
    private let title = FraloStyle.text("", role: .heading)
    private let detail = FraloStyle.text("", role: .detail, secondary: true)
    private let hint = FraloStyle.text("", role: .caption, secondary: true)
    private let content: NSStackView
    private let border = CAShapeLayer()
    private var style = Style.idle
    var cornerRadius: CGFloat = 18 { didSet { needsLayout = true } }
    override var isFlipped: Bool { true }

    init(action: ActionButton) {
        self.action = action
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.symbolConfiguration = .init(pointSize: 40, weight: .regular)
        // NSImageView accepts image drags by default; it would take over as the destination
        // under the pointer and end the zone's feedback mid-drag.
        icon.unregisterDraggedTypes()
        icon.widthAnchor.constraint(equalToConstant: 46).isActive = true; icon.heightAnchor.constraint(equalToConstant: 46).isActive = true
        title.font = .systemFont(ofSize: 19, weight: .semibold); title.alignment = .center
        detail.font = .systemFont(ofSize: 12.5); detail.alignment = .center
        detail.lineBreakMode = .byWordWrapping; detail.maximumNumberOfLines = 3; detail.usesSingleLineMode = false
        hint.font = .systemFont(ofSize: 12.5); hint.alignment = .center; hint.textColor = .secondaryLabelColor
        content = NSStackView(views: [icon, title, detail, action, hint])
        content.orientation = .vertical; content.alignment = .centerX; content.spacing = 8
        content.setCustomSpacing(14, after: icon); content.setCustomSpacing(20, after: detail); content.setCustomSpacing(12, after: action)
        super.init(frame: .zero)
        wantsLayer = true
        border.fillColor = nil; layer?.addSublayer(border)
        content.translatesAutoresizingMaskIntoConstraints = false; addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: centerXAnchor), content.centerYAnchor.constraint(equalTo: centerYAnchor),
            content.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24),
            detail.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            title.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor), detail.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor)
        ])
        setAccessibilityElement(true); setAccessibilityRole(.group); setAccessibilityLabel("图片拖放区域")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    private var detailText = ""
    func show(icon symbol: String, title: String, detail: String, hint: String?) {
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        self.title.stringValue = title; detailText = detail; self.detail.isHidden = detail.isEmpty; fitDetail()
        self.hint.attributedStringValue = Self.shortcutHint(hint ?? ""); self.hint.isHidden = hint == nil
        setAccessibilityHelp(title + "。" + detail)
    }
    /// Drag states replace the actions with feedback; the button returns once the drag ends.
    func apply(_ style: Style, animated: Bool) {
        self.style = style
        action.isHidden = style == .accepting || style == .rejecting
        let duration = animated ? FraloMotion.duration(.selection) : 0
        CATransaction.begin(); CATransaction.setAnimationDuration(duration); CATransaction.setDisableActions(duration == 0)
        refreshColors()
        CATransaction.commit()
    }
    /// Pasting is a quick way in, so the shortcut itself reads at full strength within the quieter hint.
    private static func shortcutHint(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let result = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph])
        let shortcut = (text as NSString).range(of: "⌘V")
        if shortcut.location != NSNotFound {
            result.addAttributes([.font: NSFont.systemFont(ofSize: 12.5, weight: .medium), .foregroundColor: NSColor.labelColor], range: shortcut)
        }
        return result
    }
    /// On a narrow screen the supporting line breaks between its phrases, never inside one.
    private func fitDetail() {
        let available = min(280, bounds.width - 24)
        let width = (detailText as NSString).size(withAttributes: [.font: detail.font ?? .systemFont(ofSize: 12.5)]).width
        let text = width > available ? detailText.replacingOccurrences(of: " · ", with: "\n") : detailText
        if detail.stringValue != text { detail.stringValue = text }
    }
    override func layout() {
        super.layout()
        fitDetail()
        border.frame = bounds
        let inset = border.lineWidth / 2
        border.path = CGPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), cornerWidth: max(0, cornerRadius - inset), cornerHeight: max(0, cornerRadius - inset), transform: nil)
        layer?.cornerRadius = cornerRadius
    }
    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let accent = NSColor.controlAccentColor
            let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            switch style {
            case .idle:
                border.strokeColor = NSColor.labelColor.withAlphaComponent(contrast ? 0.5 : 0.22).cgColor
                border.lineWidth = 1.5; border.lineDashPattern = [5, 4]; layer?.backgroundColor = nil
                icon.contentTintColor = .secondaryLabelColor
            case .accepting:
                border.strokeColor = accent.cgColor; border.lineWidth = 2; border.lineDashPattern = nil
                layer?.backgroundColor = accent.withAlphaComponent(0.16).cgColor
                icon.contentTintColor = .labelColor
            case .rejecting:
                border.strokeColor = NSColor.labelColor.withAlphaComponent(contrast ? 0.4 : 0.14).cgColor
                border.lineWidth = 1.5; border.lineDashPattern = [5, 4]; layer?.backgroundColor = nil
                icon.contentTintColor = .tertiaryLabelColor
            case .error:
                border.strokeColor = nil; layer?.backgroundColor = nil
                icon.contentTintColor = .secondaryLabelColor
            }
        }
        needsLayout = true
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshColors() }
}

/// With images already in the batch, a drag outlines the stage and names what will be appended.
@MainActor
final class AppendDropOverlay: NSView {
    private let border = CAShapeLayer()
    private let pill = NSView()
    private let icon = NSImageView()
    private let text = FraloStyle.text("", role: .body)
    /// Keeps the outline clear of the header and the floating inspector.
    var viewingInsets = NSEdgeInsetsZero { didSet { needsLayout = true } }
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; alphaValue = 0; isHidden = true
        border.fillColor = nil; border.lineWidth = 2; layer?.addSublayer(border)
        pill.wantsLayer = true; pill.layer?.cornerRadius = 18
        pill.layer?.shadowOpacity = 0.14; pill.layer?.shadowRadius = 12; pill.layer?.shadowOffset = NSSize(width: 0, height: -6)
        text.font = .systemFont(ofSize: 13, weight: .semibold); text.lineBreakMode = .byTruncatingTail
        icon.symbolConfiguration = .init(pointSize: 14, weight: .semibold); icon.unregisterDraggedTypes()
        let row = NSStackView(views: [icon, text]); row.spacing = 8; row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false; pill.addSubview(row)
        pill.translatesAutoresizingMaskIntoConstraints = false; addSubview(pill)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 16), row.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -16),
            row.centerYAnchor.constraint(equalTo: pill.centerYAnchor), pill.heightAnchor.constraint(equalToConstant: 36),
            pill.centerXAnchor.constraint(equalTo: centerXAnchor), pill.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -48)
        ])
        pillTop = pill.topAnchor.constraint(equalTo: topAnchor); pillTop?.isActive = true
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    private var pillTop: NSLayoutConstraint?
    private var accepting = true
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(_ summary: DropSummary?, title: String) {
        let visible = summary != nil
        if let summary {
            accepting = summary.canDrop
            text.stringValue = title
            icon.image = NSImage(systemSymbolName: accepting ? "plus" : "nosign", accessibilityDescription: nil)
            refreshColors()
        }
        if visible { isHidden = false }
        let duration = FraloMotion.duration(.selection)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            (duration > 0 ? animator() : self).alphaValue = visible ? 1 : 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { if let self, self.alphaValue == 0 { self.isHidden = true } }
        })
    }
    private var outline: NSRect {
        NSRect(x: viewingInsets.left, y: viewingInsets.top, width: max(0, bounds.width - viewingInsets.left - viewingInsets.right),
               height: max(0, bounds.height - viewingInsets.top - viewingInsets.bottom))
    }
    override func layout() {
        super.layout()
        border.frame = bounds
        border.path = CGPath(roundedRect: outline, cornerWidth: 22, cornerHeight: 22, transform: nil)
        pillTop?.constant = outline.minY + 14
    }
    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            border.strokeColor = accepting ? NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor : nil
            pill.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            pill.layer?.borderColor = NSColor.separatorColor.cgColor; pill.layer?.borderWidth = 0.5
            icon.contentTintColor = accepting ? .controlAccentColor : .secondaryLabelColor
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refreshColors() }
}

/// Placeholder A for the empty list: three fading slots in the shape of the real rows,
/// then what will appear here and how to add it.
@MainActor
final class SidebarEmptyPlaceholder: NSView {
    let addButton = ActionButton("添加图片…", role: .secondary, size: .compact, symbol: "plus")
    private let slots = SidebarSlots()
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        let heading = FraloStyle.text("还没有图片", role: .body, secondary: true)
        heading.font = .systemFont(ofSize: 12.5, weight: .semibold); heading.alignment = .center
        let detail = FraloStyle.text("导入的截图会按顺序排在这里\n也可以直接拖到这一栏", role: .caption, secondary: true)
        detail.textColor = .tertiaryLabelColor; detail.alignment = .center
        detail.maximumNumberOfLines = 3; detail.lineBreakMode = .byWordWrapping; detail.usesSingleLineMode = false
        let caption = NSStackView(views: [heading, detail, addButton])
        caption.orientation = .vertical; caption.alignment = .centerX; caption.spacing = 4; caption.setCustomSpacing(12, after: detail)
        for view in [slots, caption] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            slots.topAnchor.constraint(equalTo: topAnchor), slots.leadingAnchor.constraint(equalTo: leadingAnchor), slots.trailingAnchor.constraint(equalTo: trailingAnchor),
            slots.heightAnchor.constraint(equalToConstant: SidebarSlots.height),
            caption.topAnchor.constraint(equalTo: slots.bottomAnchor, constant: 18),
            caption.centerXAnchor.constraint(equalTo: centerXAnchor), caption.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24),
            caption.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
        setAccessibilityElement(false)
        slots.setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

/// Static dashed outlines matching the thumbnail rows. No shimmer: these are slots, not loading content.
@MainActor
private final class SidebarSlots: NSView {
    static let rows = 3
    static let height = CGFloat(rows) * FraloStyle.Workbench.rowHeight
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        for row in 0..<Self.rows {
            let alpha: CGFloat = [1, 0.6, 0.3][row]
            let top = CGFloat(row) * FraloStyle.Workbench.rowHeight
            let thumb = NSRect(x: 18, y: top + (FraloStyle.Workbench.rowHeight - 78) / 2, width: 40, height: 78)
            let lines = [NSRect(x: thumb.maxX + 14, y: thumb.midY - 11, width: (bounds.width - thumb.maxX - 40) * 0.82, height: 8),
                         NSRect(x: thumb.maxX + 14, y: thumb.midY + 5, width: (bounds.width - thumb.maxX - 40) * 0.5, height: 8)]
            let slot = NSBezierPath(roundedRect: thumb.insetBy(dx: 0.75, dy: 0.75), xRadius: 9, yRadius: 9)
            NSColor.labelColor.withAlphaComponent(0.025 * alpha).setFill(); slot.fill()
            slot.lineWidth = 1.5; slot.setLineDash([4, 3], count: 2, phase: 0)
            NSColor.labelColor.withAlphaComponent((contrast ? 0.36 : 0.15) * alpha).setStroke(); slot.stroke()
            // Where the name and size will sit: quiet bars, so only the thumbnail reads as a slot.
            NSColor.labelColor.withAlphaComponent((contrast ? 0.16 : 0.07) * alpha).setFill()
            for line in lines { NSBezierPath(roundedRect: line, xRadius: 4, yRadius: 4).fill() }
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
}
