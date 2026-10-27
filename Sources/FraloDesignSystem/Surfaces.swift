import AppKit

@MainActor
public final class MaterialSurface: NSView {
    public enum Role: String, CaseIterable { case workspace, panel }
    public let role: Role
    public let effect = NSVisualEffectView()
    /// All foreground content belongs here, including when hosted inside native glass.
    public let contentView = NSView()
    private var nativeGlass: NSView?
    private let fallbackView = NSView()
    private let panelTint = NSView()
    private var observer: NSObjectProtocol?
    public var preferences = DesignPreferences() { didSet { refresh() } }
    public var cornerRadius: CGFloat = 0 { didSet { refresh() } }
    public var material: NSVisualEffectView.Material { get { effect.material } set { effect.material = newValue } }
    public var isUsingOpaqueFallback: Bool { !fallbackView.isHidden }
    public var isUsingNativeGlass: Bool { nativeGlass != nil && !isUsingOpaqueFallback }

    public init(_ role: Role, radius: CGFloat = 0, useNativeGlass: Bool = true) {
        self.role = role; cornerRadius = radius
        super.init(frame: .zero)
        wantsLayer = true; fallbackView.wantsLayer = true; panelTint.wantsLayer = true
        effect.material = role == .workspace ? .underWindowBackground : .sidebar
        effect.blendingMode = role == .workspace ? .behindWindow : .withinWindow
        effect.state = .followsWindowActiveState
        for view in [effect, panelTint] {
            view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view)
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
                                         view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor)])
        }
        contentView.wantsLayer = true
        contentView.translatesAutoresizingMaskIntoConstraints = false
        let host: NSView
        if role == .panel, useNativeGlass, #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(); glass.style = .regular
            glass.cornerRadius = radius; glass.contentView = contentView
            glass.translatesAutoresizingMaskIntoConstraints = false; addSubview(glass)
            NSLayoutConstraint.activate([glass.leadingAnchor.constraint(equalTo: leadingAnchor), glass.trailingAnchor.constraint(equalTo: trailingAnchor),
                glass.topAnchor.constraint(equalTo: topAnchor), glass.bottomAnchor.constraint(equalTo: bottomAnchor)])
            nativeGlass = glass
            host = glass
        } else { addSubview(contentView); host = self }
        NSLayoutConstraint.activate([contentView.leadingAnchor.constraint(equalTo: host.leadingAnchor), contentView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: host.topAnchor), contentView.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
        fallbackView.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(fallbackView)
        NSLayoutConstraint.activate([fallbackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), fallbackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            fallbackView.topAnchor.constraint(equalTo: contentView.topAnchor), fallbackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)])
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                                      object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
    public override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh() }
    public func refresh() {
        // The glass radius shapes the effect, but does not fence every descendant render layer.
        clipsToBounds = true
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.cornerRadius = cornerRadius; layer?.masksToBounds = true
            layer?.borderColor = (preferences.effectiveIncreaseContrast ? NSColor.separatorColor : NSColor.labelColor.withAlphaComponent(0.14)).cgColor
            layer?.borderWidth = role == .panel ? (preferences.effectiveIncreaseContrast ? 1 : 0.5) : 0
            fallbackView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            fallbackView.layer?.cornerRadius = cornerRadius
            panelTint.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.82).cgColor
        }
        if #available(macOS 26.0, *), let glass = nativeGlass as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
            if #available(macOS 27.0, *) { glass.effectIsInteractive = false }
        }
        panelTint.isHidden = role != .panel
        fallbackView.isHidden = !preferences.effectiveReduceTransparency
        effect.isHidden = !fallbackView.isHidden || nativeGlass != nil
    }
}

@MainActor
public final class FlippedDocument: NSView {
    public override var isFlipped: Bool { true }
}

@MainActor
public enum ScrollContent {
    public static func configure(_ scroll: NSScrollView) {
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
        scroll.scrollerKnobStyle = .default; scroll.borderType = .noBorder; scroll.drawsBackground = false
    }

    public static func make(_ content: NSView, inset: CGFloat = 16) -> NSScrollView {
        let scroll = NSScrollView(); install(content, in: scroll, inset: inset); return scroll
    }

    /// Pins width to the clip view; long settings remain vertically reachable.
    public static func install(_ content: NSView, in scroll: NSScrollView, inset: CGFloat = 16) {
        let document = FlippedDocument()
        document.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content); scroll.documentView = document
        configure(scroll)
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: inset),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -inset),
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: inset),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -inset)
        ])
    }
}

@MainActor
public final class FloatingPanel: NSView {
    public let surface = MaterialSurface(.panel, radius: FraloStyle.Workbench.panelRadius)
    /// The supplied body owns scrolling; the panel only arranges its viewport.
    public let body: NSView
    public init(header: NSView, body: NSView, footer: NSView, bodySpacing: CGFloat = 12) {
        self.body = body
        super.init(frame: .zero)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOpacity = 0.10
        layer?.shadowRadius = 16; layer?.shadowOffset = NSSize(width: 0, height: -6)
        surface.translatesAutoresizingMaskIntoConstraints = false; addSubview(surface)
        let host = surface.contentView
        for view in [header, body, footer] { view.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(view) }
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor), surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor), surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            header.topAnchor.constraint(equalTo: host.topAnchor, constant: 18), header.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -18),
            footer.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 18), footer.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -18),
            footer.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -18),
            body.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 18), body.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -18),
            body.topAnchor.constraint(equalTo: header.bottomAnchor, constant: bodySpacing), body.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    public override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: FraloStyle.Workbench.panelRadius, cornerHeight: FraloStyle.Workbench.panelRadius, transform: nil)
    }
}

@MainActor
public final class CollapsedRail: NSView {
    public let surface = MaterialSurface(.panel, radius: 18)
    public let expand = IconButton("chevron.right", label: "展开图片列表")
    public let list = BatchList(compact: true)
    public let add = IconButton("plus", label: "添加图片")
    public let previous = IconButton("chevron.up", label: "上一张图片")
    public let next = IconButton("chevron.down", label: "下一张图片")
    public let position = FraloStyle.text("0/0", role: .caption, secondary: true)
    public init() {
        super.init(frame: .zero)
        surface.translatesAutoresizingMaskIntoConstraints = false; addSubview(surface)
        let bottom = FraloStyle.stack([previous, next, position], spacing: 4); bottom.alignment = .centerX
        let top = FraloStyle.stack([expand, add], spacing: 8); top.alignment = .centerX
        let host = surface.contentView
        for view in [top, list, bottom] { view.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(view) }
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor), surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor), surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            top.topAnchor.constraint(equalTo: host.topAnchor, constant: 12), top.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            list.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 12), list.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -12),
            list.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 6), list.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -6),
            bottom.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -12), bottom.centerXAnchor.constraint(equalTo: host.centerXAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    public func update(index: Int?, count: Int) {
        position.stringValue = "\(index.map { $0 + 1 } ?? 0)/\(count)"
        if let index, list.selectedIndex != index { list.select(index) }
        previous.isEnabled = (index ?? 0) > 0
        next.isEnabled = index.map { $0 + 1 < count } ?? false
    }
}

public struct BatchEntry {
    public let id: String
    public let title: String
    public let detail: String
    public let image: NSImage?
    public let failed: Bool
    public init(id: String, title: String, detail: String = "", image: NSImage? = nil, failed: Bool = false) {
        self.id = id; self.title = title; self.detail = detail; self.image = image; self.failed = failed
    }
}

@MainActor
public final class ThumbnailRow: NSTableCellView {
    public init(entry: BatchEntry, compact: Bool = false) {
        super.init(frame: .zero)
        let image = NSImageView()
        image.image = entry.image ?? NSImage(systemSymbolName: entry.failed ? "exclamationmark.triangle" : "photo", accessibilityDescription: nil)
        image.imageScaling = .scaleProportionallyUpOrDown
        image.contentTintColor = entry.failed ? .systemRed : .secondaryLabelColor
        image.translatesAutoresizingMaskIntoConstraints = false
        addSubview(image)
        let inset: CGFloat = compact ? 7 : 12
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            image.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            image.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            image.bottomAnchor.constraint(equalTo: bottomAnchor, constant: entry.failed && !compact ? -28 : -inset)
        ])
        if entry.failed && !compact {
            let detail = FraloStyle.text("无法读取", role: .detail); detail.textColor = .systemRed
            detail.translatesAutoresizingMaskIntoConstraints = false; addSubview(detail)
            NSLayoutConstraint.activate([detail.centerXAnchor.constraint(equalTo: centerXAnchor), detail.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)])
            textField = detail
        }
        imageView = image
        toolTip = entry.title + (entry.failed ? " · 无法读取" : "")
        setAccessibilityLabel(entry.title + (entry.failed ? "，加载失败" : ""))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

@MainActor
private final class BatchNavigationTable: NSTableView {
    var onDelete: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 51 || event.keyCode == 117), let onDelete { onDelete() }
        else { super.keyDown(with: event) }
    }
}

@MainActor
private final class BatchSelectionRow: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 5), xRadius: 11, yRadius: 11).fill()
        NSColor.labelColor.withAlphaComponent(0.10).setStroke()
        let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 5), xRadius: 11, yRadius: 11)
        edge.lineWidth = 0.5; edge.stroke()
    }
    override var isEmphasized: Bool { get { true } set {} }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.17).setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 5), xRadius: 11, yRadius: 11)
        path.fill(); NSColor.controlAccentColor.setStroke(); path.lineWidth = 1.5; path.stroke()
    }
}

@MainActor
public final class BatchList: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = BatchNavigationTable()
    private var updating = false
    private let compact: Bool
    public var onDelete: (() -> Void)?
    public private(set) var entries: [BatchEntry] = []
    public var onSelection: ((Int) -> Void)?
    public var selectedIndex: Int? { entries.indices.contains(table.selectedRow) ? table.selectedRow : nil }
    public init(entries: [BatchEntry] = [], compact: Bool = false) {
        self.compact = compact
        super.init(frame: .zero)
        table.headerView = nil; table.style = .plain; table.rowHeight = compact ? 72 : FraloStyle.Workbench.rowHeight; table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 0, height: compact ? 6 : 10)
        table.allowsMultipleSelection = false; table.allowsEmptySelection = false
        let column = NSTableColumn(identifier: .init("source")); column.minWidth = 0; table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self; table.delegate = self
        table.onDelete = { [weak self] in self?.onDelete?() }
        table.setAccessibilityLabel("原始图片列表")
        documentView = table; ScrollContent.configure(self)
        update(entries)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    public override func layout() {
        super.layout()
        let width = max(1, contentView.bounds.width)
        if abs(table.frame.width - width) > 0.5 { table.setFrameSize(NSSize(width: width, height: table.frame.height)) }
        if let column = table.tableColumns.first, abs(column.width - width) > 0.5 { column.width = width }
    }
    public func update(_ entries: [BatchEntry]) {
        updating = true; defer { updating = false }
        let oldID = selectedIndex.map { self.entries[$0].id }
        self.entries = entries; table.reloadData()
        if !entries.isEmpty { select(entries.firstIndex { $0.id == oldID } ?? 0) }
    }
    public func select(_ index: Int) {
        guard entries.indices.contains(index) else { return }
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        table.scrollRowToVisible(index)
    }
    public func moveSelection(by delta: Int) {
        guard !entries.isEmpty else { return }
        select(min(entries.count - 1, max(0, (selectedIndex ?? 0) + delta)))
    }
    public func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? { ThumbnailRow(entry: entries[row], compact: compact) }
    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { BatchSelectionRow() }
    public func tableViewSelectionDidChange(_ notification: Notification) { if !updating, let selectedIndex { onSelection?(selectedIndex) } }
}

@MainActor
public final class CanvasSurface: NSView {
    public var showsTransparencyGrid = true { didSet { needsDisplay = true } }
    public var showsElevation = false { didSet { needsDisplay = true } }
    public var image: NSImage? {
        didSet {
            needsDisplay = true
            setAccessibilityValue(image.map { "\(Int($0.size.width)) × \(Int($0.size.height))" } ?? "暂无成品")
        }
    }
    public var zoom: CGFloat? { didSet { needsDisplay = true } }
    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public var onDrag: ((CGPoint) -> Void)?
    public var onDragEnd: (() -> Void)?
    public var centerGuideX = false { didSet { needsDisplay = true } }
    public var centerGuideY = false { didSet { needsDisplay = true } }
    private var dragPoint: CGPoint?
    public override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); dragPoint = convert(event.locationInWindow, from: nil) }
    public override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let previous = dragPoint, imageRect.width > 0, imageRect.height > 0 {
            onDrag?(CGPoint(x: (point.x - previous.x) / imageRect.width, y: (point.y - previous.y) / imageRect.height))
        }
        dragPoint = point
    }
    public override func mouseUp(with event: NSEvent) { dragPoint = nil; onDragEnd?() }
    public var onPrevious: (() -> Void)?
    public var onNext: (() -> Void)?
    public var onEscape: (() -> Void)?
    public override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true); setAccessibilityRole(.image); setAccessibilityLabel("成品画布")
        setAccessibilityHelp("上下键切换图片，Tab 切换焦点，Esc 返回编辑。")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    public var imageRect: NSRect {
        guard let image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let fit = max(0, min((bounds.width - 32) / image.size.width, (bounds.height - 32) / image.size.height))
        let factor = zoom ?? fit
        let size = NSSize(width: image.size.width * factor, height: image.size.height * factor)
        return NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }
    public override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        let rect = imageRect
        guard rect.width > 0, rect.height > 0 else { return }
        if showsElevation {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.17)
            shadow.shadowBlurRadius = 16; shadow.shadowOffset = NSSize(width: 0, height: -5); shadow.set()
            NSColor.black.withAlphaComponent(0.12).setFill(); rect.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        // Preview backing only. Its colors must never enter the exported image.
        if showsTransparencyGrid {
            NSColor(white: 0.96, alpha: 1).setFill(); rect.fill()
            NSColor(white: 0.90, alpha: 1).setFill()
            let tile: CGFloat = 10
            var y = rect.minY, row = 0
            while y < rect.maxY {
                var x = rect.minX + (row % 2 == 0 ? 0 : tile)
                while x < rect.maxX { NSRect(x: x, y: y, width: tile, height: tile).fill(); x += tile * 2 }
                y += tile; row += 1
            }
        }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
        if showsElevation {
            NSColor.black.withAlphaComponent(0.09).setStroke()
            let border = NSBezierPath(rect: rect); border.lineWidth = 0.5; border.stroke()
        }
        if centerGuideX || centerGuideY {
            NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke()
            let path = NSBezierPath(); path.lineWidth = 1
            if centerGuideX { path.move(to: NSPoint(x: rect.midX, y: rect.minY)); path.line(to: NSPoint(x: rect.midX, y: rect.maxY)) }
            if centerGuideY { path.move(to: NSPoint(x: rect.minX, y: rect.midY)); path.line(to: NSPoint(x: rect.maxX, y: rect.midY)) }
            path.stroke()
        }
    }
    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 48:
            if event.modifierFlags.contains(.shift) { window?.selectKeyView(preceding: self) }
            else { window?.selectKeyView(following: self) }
        case 126: onPrevious?()
        case 125: onNext?()
        case 53: onEscape?()
        default: super.keyDown(with: event)
        }
    }
}

@MainActor
public final class ViewToolbar: NSView {
    public let surface = MaterialSurface(.panel, radius: 18)
    public let zoom = ChoiceMenu(["适应窗口", "100%", "50%"], label: "查看倍率")
    public let dimensions = FraloStyle.text("2400 × 1800", role: .detail, secondary: true)
    public let composition = ChoiceMenu(["4:3"], label: "画布比例")
    public var showsComposition = false { didSet { composition.isHidden = !showsComposition; dimensions.isHidden = showsComposition } }
    public let preview = ActionButton("成品预览", role: .quiet, symbol: "photo")
    public init() {
        super.init(frame: .zero)
        surface.translatesAutoresizingMaskIntoConstraints = false; addSubview(surface)
        zoom.showsSurface = false; composition.showsSurface = false; composition.isHidden = true
        zoom.leadingSymbol = "display"
        func divider() -> NSView {
            let view = NSView(); view.wantsLayer = true; view.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
            view.widthAnchor.constraint(equalToConstant: 1).isActive = true; view.heightAnchor.constraint(equalToConstant: 22).isActive = true
            return view
        }
        let row = FraloStyle.stack([zoom, divider(), dimensions, composition, divider(), preview], axis: .horizontal, spacing: 10)
        row.translatesAutoresizingMaskIntoConstraints = false; surface.contentView.addSubview(row)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor), surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor), surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: surface.contentView.leadingAnchor, constant: 12), row.trailingAnchor.constraint(equalTo: surface.contentView.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: surface.contentView.topAnchor, constant: 4), row.bottomAnchor.constraint(equalTo: surface.contentView.bottomAnchor, constant: -4)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

@MainActor
public final class StateView: NSView {
    public enum State { case empty, loading, failure, progress }
    public let titleLabel: NSTextField
    public let detailLabel: NSTextField
    public let actionButton: ActionButton
    public let progress = NSProgressIndicator()
    public init(_ state: State, title: String, detail: String, action: (() -> Void)? = nil) {
        titleLabel = FraloStyle.text(title, role: .heading)
        detailLabel = FraloStyle.paragraph(detail)
        actionButton = ActionButton(state == .failure ? "重试" : state == .progress ? "取消" : "添加图片", onPress: action)
        super.init(frame: .zero)
        let iconName = state == .failure ? "exclamationmark.triangle" : "photo.badge.plus"
        let icon = NSImageView(image: NSImage(systemSymbolName: iconName, accessibilityDescription: nil)!)
        icon.contentTintColor = state == .failure ? .systemRed : .secondaryLabelColor
        var views: [NSView] = [icon, titleLabel, detailLabel]
        if state == .loading || state == .progress {
            progress.style = state == .loading ? .spinning : .bar
            progress.isIndeterminate = state == .loading; progress.minValue = 0; progress.maxValue = 100
            progress.doubleValue = 40; progress.startAnimation(nil); views.append(progress)
        }
        if action != nil { views.append(actionButton) }
        let column = FraloStyle.stack(views, spacing: 12); column.alignment = .centerX
        column.translatesAutoresizingMaskIntoConstraints = false; addSubview(column)
        detailLabel.alignment = .center; detailLabel.maximumNumberOfLines = 4
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            column.centerXAnchor.constraint(equalTo: centerXAnchor), column.centerYAnchor.constraint(equalTo: centerYAnchor),
            column.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 16),
            column.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16),
            detailLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 400)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}
