import AppKit

@MainActor
public final class MaterialSurface: NSView {
    public enum Role: String, CaseIterable { case workspace, panel }
    public let role: Role
    public let effect = NSVisualEffectView()
    private let fallbackView = NSView()
    private var observer: NSObjectProtocol?
    public var preferences = DesignPreferences() { didSet { refresh() } }
    public var cornerRadius: CGFloat = 0 { didSet { refresh() } }
    public var material: NSVisualEffectView.Material { get { effect.material } set { effect.material = newValue } }
    public var isUsingOpaqueFallback: Bool { !fallbackView.isHidden }

    public init(_ role: Role, radius: CGFloat = 0) {
        self.role = role; cornerRadius = radius
        super.init(frame: .zero)
        wantsLayer = true; fallbackView.wantsLayer = true
        effect.material = role == .workspace ? .underWindowBackground : .sidebar
        effect.blendingMode = role == .workspace ? .behindWindow : .withinWindow
        effect.state = .followsWindowActiveState
        for view in [effect, fallbackView] {
            view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view)
            NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
                                         view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor)])
        }
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
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.cornerRadius = cornerRadius; layer?.masksToBounds = true
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.borderWidth = role == .panel ? (preferences.effectiveIncreaseContrast ? 1 : 0.5) : 0
            fallbackView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        fallbackView.isHidden = !preferences.effectiveReduceTransparency
        effect.isHidden = !fallbackView.isHidden
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
    public let surface = MaterialSurface(.panel, radius: 18)
    /// The supplied body owns scrolling; the panel only arranges its viewport.
    public let body: NSView
    public init(header: NSView, body: NSView, footer: NSView) {
        self.body = body
        super.init(frame: .zero)
        for view in [surface, header, body, footer] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor), surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor), surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 16), header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            body.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12), body.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

@MainActor
public final class CollapsedRail: NSView {
    public let surface = MaterialSurface(.panel, radius: 18)
    public let expand = IconButton("sidebar.left", label: "展开图片列表")
    public let add = IconButton("plus", label: "添加图片")
    public let previous = IconButton("chevron.up", label: "上一张图片")
    public let next = IconButton("chevron.down", label: "下一张图片")
    public let position = FraloStyle.text("0/0", role: .caption, secondary: true)
    public init() {
        super.init(frame: .zero)
        surface.translatesAutoresizingMaskIntoConstraints = false; addSubview(surface)
        let bottom = FraloStyle.stack([add, previous, next, position], spacing: 4); bottom.alignment = .centerX
        for view in [expand, bottom] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor), surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor), surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            expand.topAnchor.constraint(equalTo: topAnchor, constant: 12), expand.centerXAnchor.constraint(equalTo: centerXAnchor),
            bottom.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12), bottom.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    public func update(index: Int?, count: Int) {
        position.stringValue = "\(index.map { $0 + 1 } ?? 0)/\(count)"
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
    public init(entry: BatchEntry) {
        super.init(frame: .zero)
        let image = NSImageView(); image.image = entry.image ?? NSImage(systemSymbolName: entry.failed ? "exclamationmark.triangle" : "photo", accessibilityDescription: nil)
        image.imageScaling = .scaleProportionallyUpOrDown
        image.translatesAutoresizingMaskIntoConstraints = false
        let title = FraloStyle.text(entry.title)
        let detail = FraloStyle.text(entry.detail, role: .caption, secondary: true)
        if entry.failed { detail.textColor = .systemRed }
        let text = FraloStyle.stack([title, detail], spacing: 4); text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(image); addSubview(text)
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), image.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 48), image.heightAnchor.constraint(equalToConstant: 60),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 8), text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), text.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        textField = title; imageView = image
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
public final class BatchList: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = BatchNavigationTable()
    private var updating = false
    public var onDelete: (() -> Void)?
    public private(set) var entries: [BatchEntry] = []
    public var onSelection: ((Int) -> Void)?
    public var selectedIndex: Int? { entries.indices.contains(table.selectedRow) ? table.selectedRow : nil }
    public init(entries: [BatchEntry] = []) {
        super.init(frame: .zero)
        table.headerView = nil; table.style = .sourceList; table.rowHeight = 76; table.backgroundColor = .clear
        table.allowsMultipleSelection = false; table.allowsEmptySelection = false
        let column = NSTableColumn(identifier: .init("source")); table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self; table.delegate = self
        table.onDelete = { [weak self] in self?.onDelete?() }
        table.setAccessibilityLabel("原始图片列表")
        documentView = table; ScrollContent.configure(self)
        update(entries)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
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
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? { ThumbnailRow(entry: entries[row]) }
    public func tableViewSelectionDidChange(_ notification: Notification) { if !updating, let selectedIndex { onSelection?(selectedIndex) } }
}

@MainActor
public final class CanvasSurface: NSView {
    public var image: NSImage? {
        didSet {
            needsDisplay = true
            setAccessibilityValue(image.map { "\(Int($0.size.width)) × \(Int($0.size.height))" } ?? "暂无成品")
        }
    }
    public var zoom: CGFloat? { didSet { needsDisplay = true } }
    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
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
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        // Preview backing only. Its colors must never enter the exported image.
        NSColor(white: 0.96, alpha: 1).setFill(); rect.fill()
        NSColor(white: 0.90, alpha: 1).setFill()
        let tile: CGFloat = 10
        var y = rect.minY, row = 0
        while y < rect.maxY {
            var x = rect.minX + (row % 2 == 0 ? 0 : tile)
            while x < rect.maxX { NSRect(x: x, y: y, width: tile, height: tile).fill(); x += tile * 2 }
            y += tile; row += 1
        }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.restoreGraphicsState()
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
    public let preview = ActionButton("成品预览", role: .quiet, size: .compact)
    public init() {
        super.init(frame: .zero)
        surface.translatesAutoresizingMaskIntoConstraints = false; addSubview(surface)
        let row = FraloStyle.stack([zoom, FraloStyle.divider(), dimensions, preview], axis: .horizontal, spacing: 12)
        row.translatesAutoresizingMaskIntoConstraints = false; addSubview(row)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor), surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor), surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4), row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
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
