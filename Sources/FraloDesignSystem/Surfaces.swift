import AppKit
import QuartzCore

@MainActor
public final class MaterialSurface: NSView {
    public enum Role: String, CaseIterable { case workspace, panel }
    public let role: Role
    public let effect = NSVisualEffectView()
    /// All foreground content belongs here, including when hosted inside native glass.
    public let contentView = NSView()
    private var nativeGlass: NSView?
    private let fallbackView = NSView()
    let panelTint = NSView()
    private var observer: NSObjectProtocol?
    public var preferences = DesignPreferences() { didSet { refresh() } }
    /// Opt in only for glass containing controls, not large decorative panels.
    public var isInteractive = false { didSet { refresh() } }
    public var cornerRadius: CGFloat = 0 { didSet { refresh() } }
    /// How much window background frosts a panel, per appearance. Zero leaves the native glass bare.
    public var tintOpacity: CGFloat = 0.55 { didSet { refresh() } }
    public var darkTintOpacity: CGFloat = 0.55 { didSet { refresh() } }
    /// A one-pixel outline in the label colour, so the surface keeps an edge over backdrops of its
    /// own tone. It resolves in the surface's effective appearance: dark on light glass, light on dark.
    /// Increase Contrast always shows it, at full point width.
    public var showsOutline = true { didSet { refresh() } }
    public var outlineOpacity: CGFloat = 0.14 { didSet { refresh() } }
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
        for view in [effect] {
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
        panelTint.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview(panelTint)
        NSLayoutConstraint.activate([panelTint.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), panelTint.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            panelTint.topAnchor.constraint(equalTo: contentView.topAnchor), panelTint.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)])
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
    public override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); refresh() }
    public func refresh() {
        // The glass radius shapes the effect, but does not fence every descendant render layer.
        clipsToBounds = true
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let tint = dark ? darkTintOpacity : tintOpacity
        let contrast = preferences.effectiveIncreaseContrast, opaque = preferences.effectiveReduceTransparency
        let outlined = showsOutline || contrast
        // Without glass the outline is the only edge left against a same-coloured backdrop.
        let outlineAlpha = opaque ? max(outlineOpacity, 0.24) : outlineOpacity
        let pixel = 1 / (window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.cornerRadius = cornerRadius; layer?.masksToBounds = true
            // Increase Contrast must be the strongest edge; the system separator is too pale over light art.
            layer?.borderColor = NSColor.labelColor.withAlphaComponent(contrast ? 0.5 : outlineAlpha).cgColor
            layer?.borderWidth = role == .panel && outlined ? (contrast ? 1 : pixel) : 0
            fallbackView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            fallbackView.layer?.cornerRadius = cornerRadius
            // Translucent enough for the blurred desktop behind the stage to read through, opaque enough to separate layers.
            panelTint.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(tint).cgColor
        }
        if #available(macOS 26.0, *), let glass = nativeGlass as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
            if #available(macOS 27.0, *) {
                glass.effectIsInteractive = isInteractive && !preferences.effectiveReduceMotion && !preferences.effectiveReduceTransparency
            }
        }
        panelTint.isHidden = role != .panel || tint == 0
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
        scroll.hasVerticalScroller = !(scroll is PanelScrollView); scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true; scroll.scrollerStyle = .overlay
        scroll.scrollerKnobStyle = .default; scroll.borderType = .noBorder; scroll.drawsBackground = false
    }

    public static func make(_ content: NSView, inset: CGFloat = 16) -> NSScrollView {
        let scroll = PanelScrollView(frame: .zero); install(content, in: scroll, inset: inset); return scroll
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
    public let surface: MaterialSurface
    /// The supplied body owns scrolling; the panel only arranges its viewport.
    public let body: NSView
    public init(header: NSView, body: NSView, footer: NSView, bodySpacing: CGFloat = 12, useNativeGlass: Bool = true) {
        self.body = body
        surface = MaterialSurface(.panel, radius: FraloStyle.Workbench.panelRadius, useNativeGlass: useNativeGlass)
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
    public init(entry: BatchEntry, compact: Bool = false, horizontalInset: CGFloat = 0, trailingInset: CGFloat? = nil) {
        super.init(frame: .zero)
        let image = NSImageView()
        image.image = entry.image ?? NSImage(systemSymbolName: entry.failed ? "exclamationmark.triangle" : "photo", accessibilityDescription: nil)
        image.imageScaling = .scaleProportionallyUpOrDown
        image.contentTintColor = entry.failed ? .systemRed : .secondaryLabelColor
        image.translatesAutoresizingMaskIntoConstraints = false
        addSubview(image)
        let inset: CGFloat = 7
        if compact { NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            image.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            image.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            image.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset)
        ]) }
        if !compact { layoutDetailed(entry, image: image, horizontalInset: horizontalInset, trailingInset: trailingInset ?? horizontalInset) }
        imageView = image
        toolTip = entry.title + (entry.failed ? " · 无法读取" : "")
        setAccessibilityLabel(entry.title + (entry.failed ? "，加载失败" : ""))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    /// Framed thumbnail, then file name and pixel size.
    private func layoutDetailed(_ entry: BatchEntry, image: NSImageView, horizontalInset: CGFloat, trailingInset: CGFloat) {
        let name = FraloStyle.text(entry.title); name.font = .systemFont(ofSize: 13, weight: .medium)
        let detail = FraloStyle.text(entry.failed ? "无法读取" : entry.detail, role: .caption)
        detail.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        detail.textColor = entry.failed ? .systemRed : .tertiaryLabelColor
        let text = FraloStyle.stack([name, detail], spacing: 3)
        text.translatesAutoresizingMaskIntoConstraints = false; addSubview(text)
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8 + horizontalInset), image.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 44), image.heightAnchor.constraint(equalToConstant: 78),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 12), text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8 - trailingInset),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            name.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -72)
        ])
        textField = name
    }
}

private func batchRowBounds(_ bounds: NSRect, leading: CGFloat, trailing: CGFloat, vertical: CGFloat) -> NSRect {
    NSRect(x: bounds.minX + 1 + leading, y: bounds.minY + vertical,
           width: max(0, bounds.width - 2 - leading - trailing), height: max(0, bounds.height - 2 * vertical))
}

@MainActor
private final class BatchNavigationTable: NSTableView {
    var onDelete: (() -> Void)?
    override func becomeFirstResponder() -> Bool {
        if NSApp.currentEvent?.type == .keyDown { focusRingType = .exterior }
        return super.becomeFirstResponder()
    }
    override func mouseDown(with event: NSEvent) { focusRingType = .none; super.mouseDown(with: event) }
    override func rightMouseDown(with event: NSEvent) {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0, let menu else { return }
        focusRingType = .none
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        window?.makeFirstResponder(self)
        // Avoid NSTableView's extra contextual-row highlight over the selected card.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
    var compact = false
    var rowHorizontalInset: CGFloat = 0
    var rowTrailingInset: CGFloat = 0
    override var focusRingMaskBounds: NSRect {
        selectedRow >= 0 ? batchRowBounds(rect(ofRow: selectedRow), leading: rowHorizontalInset, trailing: rowTrailingInset, vertical: compact ? 5 : 1) : .zero
    }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 12, yRadius: 12).fill() }
    override func keyDown(with event: NSEvent) {
        focusRingType = .exterior
        if (event.keyCode == 51 || event.keyCode == 117), let onDelete { onDelete() }
        else { super.keyDown(with: event) }
    }
}

@MainActor
private final class BatchSelectionRow: NSTableRowView {
    var compact = true
    var horizontalInset: CGFloat = 0
    var trailingInset: CGFloat = 0
    private var dark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
    override func drawBackground(in dirtyRect: NSRect) {
        guard compact else { return }
        NSColor.controlBackgroundColor.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 5), xRadius: 11, yRadius: 11).fill()
        NSColor.labelColor.withAlphaComponent(0.10).setStroke()
        let edge = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 5), xRadius: 11, yRadius: 11)
        edge.lineWidth = 0.5; edge.stroke()
    }
    override var isEmphasized: Bool { get { true } set {} }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
    override func drawSelection(in dirtyRect: NSRect) {
        guard compact else {
            // A neutral wash, not an accent block: the framed thumbnail stays the strongest element.
            (dark ? NSColor.white.withAlphaComponent(0.09) : NSColor.black.withAlphaComponent(0.06)).setFill()
            NSBezierPath(roundedRect: batchRowBounds(bounds, leading: horizontalInset, trailing: trailingInset, vertical: 1), xRadius: 12, yRadius: 12).fill(); return
        }
        NSColor.controlAccentColor.withAlphaComponent(0.17).setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 5), xRadius: 11, yRadius: 11)
        path.fill(); NSColor.controlAccentColor.setStroke(); path.lineWidth = 1.5; path.stroke()
    }
}

@MainActor
public final class BatchList: PanelScrollView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = BatchNavigationTable()
    private var updating = false
    private let compact: Bool
    /// Row content/selection inset, independent of the scroller at the viewport edge.
    public var rowHorizontalInset: CGFloat = 0 {
        didSet { updateRowInsets() }
    }
    /// Total trailing inset measured from the scroll view edge, including its gutter.
    public var rowTrailingMargin: CGFloat? { didSet { updateRowInsets() } }
    private func updateRowInsets() {
        let gutter = rowTrailingMargin == nil ? 0 : max(0, bounds.maxX - contentView.frame.maxX)
        let trailing = max(0, (rowTrailingMargin ?? rowHorizontalInset) - gutter)
        guard table.rowHorizontalInset != rowHorizontalInset || abs(table.rowTrailingInset - trailing) > 0.5 else { return }
        table.rowHorizontalInset = rowHorizontalInset; table.rowTrailingInset = trailing
        table.reloadData()
    }
    public var onDelete: (() -> Void)?
    public private(set) var entries: [BatchEntry] = []
    public var onSelection: ((Int) -> Void)?
    public var selectedIndex: Int? { entries.indices.contains(table.selectedRow) ? table.selectedRow : nil }
    public init(entries: [BatchEntry] = [], compact: Bool = false) {
        self.compact = compact
        super.init(frame: .zero)
        table.headerView = nil; table.style = .plain; table.rowHeight = compact ? 72 : FraloStyle.Workbench.rowHeight; table.backgroundColor = .clear
        table.intercellSpacing = NSSize(width: 0, height: compact ? 6 : 2); table.compact = compact
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
    public override func tile() {
        super.tile()
        if rowTrailingMargin != nil { updateRowInsets() }
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
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? { ThumbnailRow(entry: entries[row], compact: compact, horizontalInset: rowHorizontalInset, trailingInset: table.rowTrailingInset) }
    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { let view = BatchSelectionRow(); view.compact = compact; view.horizontalInset = rowHorizontalInset; view.trailingInset = table.rowTrailingInset; return view }
    public func tableViewSelectionDidChange(_ notification: Notification) { table.noteFocusRingMaskChanged(); if !updating, let selectedIndex { onSelection?(selectedIndex) } }
}

@MainActor
public final class CanvasSurface: NSView {
    public var showsTransparencyGrid = true { didSet { needsDisplay = true } }
    public var showsElevation = false { didSet { needsDisplay = true } }
    /// A soft contact shadow under transparent artwork on the stage. Viewing only.
    public var showsStageShadow = false { didSet { needsDisplay = true } }
    public var image: NSImage? {
        didSet {
            needsDisplay = true; luminanceMap = nil
            setAccessibilityValue(image.map { "\(Int($0.size.width)) × \(Int($0.size.height))" } ?? "暂无成品")
        }
    }
    public var zoom: CGFloat? { didSet { needsDisplay = true } }
    /// Viewing-only gutters keep Fit artwork and scroll limits clear of floating controls.
    public var viewingInsets = NSEdgeInsetsZero { didSet { needsDisplay = true } }
    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public var allowsPositioning = false {
        didSet {
            if !allowsPositioning {
                dragPoint = nil
                if positioningCursorPushed { NSCursor.pop(); positioningCursorPushed = false }
            }
            window?.invalidateCursorRects(for: self)
        }
    }
    public override func resetCursorRects() {
        super.resetCursorRects()
        if allowsPositioning { addCursorRect(imageRect, cursor: .openHand) }
    }
    public var onDrag: ((CGPoint) -> Void)?
    public var onDragEnd: (() -> Void)?
    public var centerGuideX = false { didSet { if oldValue != centerGuideX { updateGuides() } } }
    public var centerGuideY = false { didSet { if oldValue != centerGuideY { updateGuides() } } }
    public private(set) var isPositioningArtwork = false
    public private(set) var positionedDeviceRect = CGRect.zero
    private let artworkClip = CALayer(), backgroundArtwork = CALayer(), deviceArtwork = CALayer()
    private let artworkGuides = CAShapeLayer()
    private var artworkCanvasSize = CGSize.zero
    private var positionedBackgroundRect = CGRect.zero

    public func prepareArtwork(background: CGImage, device: CGImage, backgroundOpacity: CGFloat, canvasSize: CGSize) {
        wantsLayer = true
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if artworkClip.superlayer == nil {
            // The AppKit backing layer already carries this flipped NSView's geometry.
            // Flipping the standalone clip again mirrors live Y relative to the final raster.
            artworkClip.masksToBounds = true
            artworkClip.addSublayer(backgroundArtwork); artworkClip.addSublayer(deviceArtwork); artworkClip.addSublayer(artworkGuides)
            layer?.addSublayer(artworkClip)
            artworkGuides.fillColor = nil; artworkGuides.lineWidth = 1
        }
        artworkCanvasSize = canvasSize
        backgroundArtwork.contents = background; backgroundArtwork.opacity = Float(backgroundOpacity)
        deviceArtwork.contents = device
        artworkClip.isHidden = true
        CATransaction.commit()
    }
    /// Position existing textures. No decoding, drawing, encoding or implicit animation.
    public func positionArtwork(deviceRect: CGRect, backgroundRect: CGRect) {
        guard artworkCanvasSize.width > 0, deviceArtwork.contents != nil else { return }
        let starting = !isPositioningArtwork
        isPositioningArtwork = true; positionedDeviceRect = deviceRect; positionedBackgroundRect = backgroundRect
        CATransaction.begin(); CATransaction.setDisableActions(true)
        artworkClip.isHidden = false
        layoutArtwork()
        CATransaction.commit()
        if starting { needsDisplay = true }
    }
    public func finishPositioningArtwork(discard: Bool = false) {
        isPositioningArtwork = false
        CATransaction.begin(); CATransaction.setDisableActions(true)
        artworkClip.isHidden = true
        if discard { backgroundArtwork.contents = nil; deviceArtwork.contents = nil; artworkCanvasSize = .zero }
        CATransaction.commit()
        needsDisplay = true
    }
    public override func layout() {
        super.layout()
        if isPositioningArtwork {
            CATransaction.begin(); CATransaction.setDisableActions(true); layoutArtwork(); CATransaction.commit()
        }
    }
    private func layoutArtwork() {
        let rect = imageRect
        artworkClip.frame = rect
        let sx = rect.width / artworkCanvasSize.width, sy = rect.height / artworkCanvasSize.height
        func scaled(_ r: CGRect) -> CGRect { CGRect(x: r.minX * sx, y: r.minY * sy, width: r.width * sx, height: r.height * sy) }
        backgroundArtwork.frame = scaled(positionedBackgroundRect); deviceArtwork.frame = scaled(positionedDeviceRect)
        artworkGuides.frame = artworkClip.bounds
        updateGuides()
    }
    private func updateGuides() {
        guard isPositioningArtwork else { needsDisplay = true; return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let rect = artworkClip.bounds, path = CGMutablePath()
        if centerGuideX { path.move(to: CGPoint(x: rect.midX, y: 0)); path.addLine(to: CGPoint(x: rect.midX, y: rect.height)) }
        if centerGuideY { path.move(to: CGPoint(x: 0, y: rect.midY)); path.addLine(to: CGPoint(x: rect.width, y: rect.midY)) }
        artworkGuides.path = path; artworkGuides.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        CATransaction.commit()
    }
    private var dragPoint: CGPoint?
    private var positioningCursorPushed = false
    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self); dragPoint = allowsPositioning ? convert(event.locationInWindow, from: nil) : nil
        if allowsPositioning && !positioningCursorPushed { NSCursor.closedHand.push(); positioningCursorPushed = true }
    }
    public override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard allowsPositioning, let previous = dragPoint else { return }
        if imageRect.width > 0, imageRect.height > 0 {
            onDrag?(CGPoint(x: (point.x - previous.x) / imageRect.width, y: (point.y - previous.y) / imageRect.height))
        }
        dragPoint = point
    }
    public override func mouseUp(with event: NSEvent) {
        if positioningCursorPushed { NSCursor.pop(); positioningCursorPushed = false }
        dragPoint = nil; onDragEnd?()
    }
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
        let width = max(0, bounds.width - viewingInsets.left - viewingInsets.right)
        let height = max(0, bounds.height - viewingInsets.top - viewingInsets.bottom)
        let fit = max(0, min((width - 32) / image.size.width, (height - 32) / image.size.height))
        let factor = zoom ?? fit
        let size = NSSize(width: image.size.width * factor, height: image.size.height * factor)
        return NSRect(x: viewingInsets.left + (width - size.width) / 2, y: viewingInsets.top + (height - size.height) / 2, width: size.width, height: size.height)
    }
    /// Mean luminance (0–1) of the opaque artwork beneath `rect`, in this view's coordinates.
    /// Nil when the rect mostly covers the stage or transparent areas, which follow the window appearance.
    public func artworkLuminance(under rect: NSRect) -> CGFloat? {
        let art = imageRect
        guard rect.width > 0, rect.height > 0, art.width > 0, art.height > 0, let map = luminanceMap ?? makeLuminanceMap() else { return nil }
        let overlap = rect.intersection(art)
        guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return nil }
        let cellWidth = art.width / CGFloat(map.width), cellHeight = art.height / CGFloat(map.height)
        func column(_ x: CGFloat) -> Int { min(map.width - 1, max(0, Int((x - art.minX) / cellWidth))) }
        func row(_ y: CGFloat) -> Int { min(map.height - 1, max(0, Int((y - art.minY) / cellHeight))) }
        var total: CGFloat = 0, opaque = 0, samples = 0
        // Flipped view and bitmap rows both run top to bottom.
        for y in row(overlap.minY)...row(overlap.maxY - 0.01) {
            for x in column(overlap.minX)...column(overlap.maxX - 0.01) {
                samples += 1
                let value = map.values[y * map.width + x]
                if value >= 0 { total += CGFloat(value); opaque += 1 }
            }
        }
        // Coverage of the whole rect, so a capsule hanging mostly over the stage defers to it.
        let coverage = overlap.width * overlap.height / (rect.width * rect.height) * CGFloat(opaque) / CGFloat(max(1, samples))
        return coverage >= 0.5 && opaque > 0 ? total / CGFloat(opaque) : nil
    }
    private struct LuminanceMap { let width: Int, height: Int; let values: [Float] }
    private var luminanceMap: LuminanceMap?
    private func makeLuminanceMap() -> LuminanceMap? {
        guard let image, let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil), source.width > 0, source.height > 0 else { return nil }
        // A coarse map is plenty for a control-sized backdrop and keeps scrolling free of image work.
        let width = 64, height = max(1, min(512, Int((CGFloat(64) * CGFloat(source.height) / CGFloat(source.width)).rounded())))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let values = (0..<(width * height)).map { index -> Float in
            let alpha = Float(pixels[index * 4 + 3])
            guard alpha >= 128 else { return -1 }
            let r = Float(pixels[index * 4]), g = Float(pixels[index * 4 + 1]), b = Float(pixels[index * 4 + 2])
            return (0.2126 * r + 0.7152 * g + 0.0722 * b) / alpha
        }
        let map = LuminanceMap(width: width, height: height, values: values); luminanceMap = map
        return map
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
        if showsStageShadow && !isPositioningArtwork {
            let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowColor = NSColor(srgbRed: dark ? 0 : 0.27, green: dark ? 0 : 0.2, blue: dark ? 0 : 0.12, alpha: dark ? 0.55 : 0.28)
            shadow.shadowBlurRadius = 34; shadow.shadowOffset = NSSize(width: 0, height: -16); shadow.set()
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
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
        if !isPositioningArtwork {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
                       hints: [.interpolation: NSImageInterpolation.high])
        }
        NSGraphicsContext.restoreGraphicsState()
        if showsElevation {
            NSColor.black.withAlphaComponent(0.09).setStroke()
            let border = NSBezierPath(rect: rect); border.lineWidth = 0.5; border.stroke()
        }
        if !isPositioningArtwork && (centerGuideX || centerGuideY) {
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

/// Floating canvas controls: `[ − 59% ⌄ + ] | [▦]`. The zoom readout is itself the preset menu;
/// the steppers and the checkerboard toggle are native borderless symbol buttons.
@MainActor
public final class ViewToolbar: NSView {
    public static let height: CGFloat = 36
    /// Bare Liquid Glass in both appearances; legibility comes from `backdropLuminance`.
    public static let tintOpacity: CGFloat = 0, darkTintOpacity: CGFloat = 0
    /// Hysteresis band for flipping the capsule's foreground, so mid-tone artwork never flickers.
    /// Centred near 0.4 encoded luma, where dark symbols on the lightened glass start to out-contrast white.
    public static let lightBackdropThreshold: CGFloat = 0.45, darkBackdropThreshold: CGFloat = 0.35
    public let surface = MaterialSurface(.panel, radius: ViewToolbar.height / 2)
    public let zoom = ChoiceMenu(["适应窗口", "100%", "50%"], label: "缩放比例")
    public let zoomOut = SymbolButton("minus", label: "缩小")
    public let zoomIn = SymbolButton("plus", label: "放大")
    /// Status shown in the zoom readout: the current percentage or brief feedback such as “已复制”.
    public let dimensions = FraloStyle.text("—", role: .detail, secondary: true)
    public let composition = ChoiceMenu(["4:3"], label: "画布比例")
    private let progress = NSProgressIndicator()
    private var row: NSStackView!
    public private(set) var isCompact = false
    private var pendingActivity: DispatchWorkItem?
    private var activityVersion = 0
    public private(set) var isUpdatingPreview = false
    public var showsComposition = false { didSet { composition.isHidden = !showsComposition; zoom.isHidden = showsComposition } }
    public let preview = SymbolButton("checkerboard.rectangle", label: "显示透明区域", toggles: true)
    public init() {
        super.init(frame: .zero)
        surface.isInteractive = true
        surface.tintOpacity = Self.tintOpacity; surface.darkTintOpacity = Self.darkTintOpacity
        // The surface must clip (see the child-outline contract), which also clips the glass's own
        // shadow; this host layer restores a soft lift outside that clip.
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor; layer?.shadowOpacity = 0.14
        layer?.shadowRadius = 8; layer?.shadowOffset = CGSize(width: 0, height: -2)
        surface.translatesAutoresizingMaskIntoConstraints = false; addSubview(surface)
        zoom.showsSurface = false; composition.showsSurface = false; composition.isHidden = true
        zoom.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        zoom.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        progress.setAccessibilityLabel("正在更新预览"); progress.translatesAutoresizingMaskIntoConstraints = false
        let divider = NSBox(); divider.boxType = .separator
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true; divider.heightAnchor.constraint(equalToConstant: 16).isActive = true
        row = FraloStyle.stack([zoomOut, zoom, zoomIn, composition, divider, preview], axis: .horizontal, spacing: 2)
        row.setCustomSpacing(8, after: zoomIn); row.setCustomSpacing(8, after: composition); row.setCustomSpacing(8, after: divider)
        row.translatesAutoresizingMaskIntoConstraints = false; surface.contentView.addSubview(row)
        // The spinner takes the readout's place while a render is slow, so no action shifts.
        surface.contentView.addSubview(progress)
        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: leadingAnchor), surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.topAnchor.constraint(equalTo: topAnchor), surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: surface.contentView.leadingAnchor, constant: 6), row.trailingAnchor.constraint(equalTo: surface.contentView.trailingAnchor, constant: -6),
            row.centerYAnchor.constraint(equalTo: surface.contentView.centerYAnchor),
            progress.centerXAnchor.constraint(equalTo: zoom.centerXAnchor, constant: -6), progress.centerYAnchor.constraint(equalTo: zoom.centerYAnchor),
            progress.widthAnchor.constraint(equalToConstant: 14), progress.heightAnchor.constraint(equalToConstant: 14)
        ])
        showStatus("—")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { pendingActivity?.cancel() }
    public override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: Self.height / 2, cornerHeight: Self.height / 2, transform: nil)
    }
    /// Luminance of the artwork behind the capsule, or nil over the stage. Like system Liquid Glass,
    /// the capsule's foreground flips to stay legible: dark symbols over bright art, light over dark.
    public var backdropLuminance: CGFloat? { didSet { updateBackdropAppearance() } }
    /// Whether the backdrop chose the light appearance; nil inherits the window's.
    public private(set) var usesLightAppearance: Bool?
    private func updateBackdropAppearance() {
        guard let luminance = backdropLuminance else {
            guard usesLightAppearance != nil else { return }
            usesLightAppearance = nil; appearance = nil; return
        }
        let light: Bool
        switch usesLightAppearance {
        case true?: light = luminance > Self.darkBackdropThreshold
        case false?: light = luminance >= Self.lightBackdropThreshold
        case nil: light = luminance >= (Self.lightBackdropThreshold + Self.darkBackdropThreshold) / 2
        }
        guard light != usesLightAppearance else { return }
        usesLightAppearance = light
        let contrast = surface.preferences.effectiveIncreaseContrast
        appearance = NSAppearance(named: light ? (contrast ? .accessibilityHighContrastAqua : .aqua)
                                               : (contrast ? .accessibilityHighContrastDarkAqua : .darkAqua))
    }
    /// Shows `text` in the zoom readout; `detail` becomes its tooltip (e.g. the output pixel size).
    public func showStatus(_ text: String, detail: String? = nil) {
        dimensions.stringValue = text
        if let detail { dimensions.toolTip = detail; zoom.toolTip = "缩放比例 · " + detail }
        zoom.displayTitle = isUpdatingPreview ? "" : text
    }
    public func fitControls(to availableWidth: CGFloat) {
        let compact = availableWidth > 0 && availableWidth < 440
        if compact != isCompact {
            isCompact = compact
            row.spacing = compact ? 0 : 2
        }
    }
    public func beginPreviewUpdate() {
        pendingActivity?.cancel(); activityVersion += 1
        guard !isUpdatingPreview else { return }
        let version = activityVersion
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.activityVersion == version else { return }
                self.isUpdatingPreview = true; self.zoom.displayTitle = ""
                if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { self.progress.startAnimation(nil) }
                else { self.zoom.displayTitle = "…" }
            }
        }
        pendingActivity = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }
    public func finishPreviewUpdate() {
        pendingActivity?.cancel(); pendingActivity = nil; activityVersion += 1
        isUpdatingPreview = false; progress.stopAnimation(nil); zoom.displayTitle = dimensions.stringValue
    }
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
