import FraloLocalization
import AppKit
import UniformTypeIdentifiers
import FraloCore
import FraloDesignSystem

@MainActor
final class MainWindowController: NSWindowController, NSMenuItemValidation {
    struct Item { let input: ImageInput; var thumbnail: NSImage?; var pixelSize: CGSize?; var error: String? }
    private var items: [Item] = []
    private var settings: CompositionSettings
    private let store: CompositionStore
    private var inspectorUI: CompositionInspector!
    private let preferences: UserDefaults
    private let pasteboard: NSPasteboard
    private let imageClipboard: any ImageClipboard
    private let inspectorUsesNativeGlass: Bool
    private(set) var appearanceChoice = AppAppearance.system
    private(set) var settingsController: SettingsWindowController?
    /// Set by the app delegate once Sparkle starts; nil in tests and previews, which Settings explains as unavailable.
    weak var updatePreferences: UpdatePreferences? { didSet { settingsController?.updates = updatePreferences } }
    let language: LanguagePreference
    /// Applies a language immediately (the app delegate rebuilds this window); false when it cannot right now.
    var onLanguageChange: ((String) -> Bool)?
    private var workbench: WorkbenchView!
    private var batchHadImages: Bool?
    private var sidebarCollapsedForEmptyBatch = false
    private let center = NSViewController()
    private let list = BatchList()
    private let viewing = ViewToolbar()
    private let exportAction = ExportAction(count: 0)
    private let batchCount = FraloStyle.text("0", role: .body)
    private let sidebarGuidance = FraloStyle.text(L10n.tr("↑ ↓ 切换图片"), role: .caption, secondary: true)
    private let addButton = SymbolButton("plus", label: L10n.tr("添加图片"))
    private let filename = FraloStyle.text("", role: .heading), position = FraloStyle.text("", role: .caption, secondary: true)
    private let previewScroll = PreviewScrollView()
    private let canvas = CanvasSurface(frame: .zero)
    private lazy var emptyStage = EmptyStageView(action: emptyAction)
    private let appendOverlay = AppendDropOverlay(frame: .zero)
    private let sidebarPlaceholder = SidebarEmptyPlaceholder(frame: .zero)
    private let dropRouter = FileDropRouter()
    private var emptyFrameKey: [String]?
    private var emptyFrameRequest = 0
    private let history = UndoManager()
    private var continuousSettingsStart: CompositionSettings?
    private var dragSettingsStart: CompositionSettings?
    let operationFeedback = OperationFeedback()
    private var feedbackTop: NSLayoutConstraint?
    private let emptyAction = ActionButton(L10n.tr("添加图片"), role: .primary, symbol: "plus")
    private let footer = CanvasControlsOverlay()
    private var footerTrailing: NSLayoutConstraint?
    private var fitMenu: NSPopUpButton { viewing.zoom }
    private let dimensions = FraloStyle.text(L10n.tr("尚无成品"), role: .detail, secondary: true)
    private let splitController = NSSplitViewController()
    private var header: WorkbenchHeader!
    private var rendered: RenderedComposition?
    private var renderedID: String?
    private(set) var previewRequest = 0
    private let thumbnails = ThumbnailPipeline()
    private var itemIndices: [String: Int] = [:]
    private var positioningLayers: CompositionPreviewLayers?
    private var renderWork: DispatchWorkItem?
    private var previewToken = CancellationToken()
    private let renderQueue = DispatchQueue(label: "app.fralo.preview", qos: .userInitiated)
    private let sizeQueue = DispatchQueue(label: "app.fralo.output-size", qos: .utility)
    private var zoom: CGFloat? = nil
    private var backgroundImageSize: CGSize?
    /// Set when a drag starts on the canvas outside the device over a pannable image background.
    private var dragsBackground = false
    private var dragDevicePosition: CGPoint?
    private var artworkDragChanged = false
    private weak var previewRestoreFocus: NSResponder?
    private var layingOutPreview = false
    private var pastedCount = 0
    private var cancellation: CancellationToken?
    private var progressPanel: NSPanel?
    private var updateNotice: NSTextField?
    /// Returns true when a pending update consumes successful export completion.
    var onExportFinished: (() -> Bool)?
    private var quitAfterExport = false
    private var initialWarning: String?
    var isExporting: Bool { cancellation != nil }
    private var selectedIndex: Int? { list.selectedIndex }

    init(store: SettingsStore = SettingsStore(), preferences: UserDefaults = .standard, pasteboard: NSPasteboard = .general, restoreWindow: Bool = true,
         inspectorUsesNativeGlass: Bool = false, imageClipboard: (any ImageClipboard)? = nil, language: LanguagePreference = LanguagePreference()) {
        self.store = CompositionStore(legacy: store); self.preferences = preferences; self.pasteboard = pasteboard
        self.language = language
        self.imageClipboard = imageClipboard ?? pasteboard
        self.inspectorUsesNativeGlass = inspectorUsesNativeGlass
        do { settings = try self.store.load() } catch { settings = CompositionSettings(); initialWarning = error.localizedDescription }
        let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 1000)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: min(1400, area.width - 80), height: min(950, area.height - 80)), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        history.groupsByEvent = false
        selectAppearance(preferences.string(forKey: "workbenchAppearance") ?? "system", persist: false)
        window.title = "Fralo"; window.titleVisibility = .hidden; window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true; window.titlebarSeparatorStyle = .none
        window.contentMinSize = NSSize(width: 1030, height: 640)
        buildInterface()
        if restoreWindow { window.setFrameAutosaveName("FraloMainWindow") }; window.center()
        if let warning = initialWarning { DispatchQueue.main.async { [weak self] in self?.showError(warning) } }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildInterface() {
        center.view = DropContainer()
        dropRouter.evaluate = { [weak self] urls in
            guard let self, !self.isExporting else { return DropSummary(urls: []) }
            return DropSummary(urls: urls, existing: Set(self.items.map(\.input.id)))
        }
        dropRouter.onChange = { [weak self] summary in self?.showDragFeedback(summary) }
        dropRouter.onDrop = { [weak self] in self?.importURLs($0) }
        (center.view as? DropContainer)?.router = dropRouter
        let title = FraloStyle.text(L10n.tr("图片")); title.font = .systemFont(ofSize: 13, weight: .semibold)
        batchCount.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium); batchCount.textColor = .labelColor
        addButton.onPress = { [weak self] in self?.addImages(nil) }
        let heading = FraloStyle.stack([title, batchCount, NSView(), addButton], axis: .horizontal, spacing: 6)
        sidebarGuidance.alignment = .center
        sidebarGuidance.textColor = NSColor(name: nil) { appearance in
            var color = NSColor.secondaryLabelColor
            appearance.performAsCurrentDrawingAppearance {
                color = NSColor.secondaryLabelColor.blended(withFraction: 0.12, of: .labelColor) ?? .secondaryLabelColor
            }
            return color
        }
        sidebarGuidance.identifier = .init("batch-keyboard-guidance")
        sidebarGuidance.setAccessibilityLabel(L10n.tr("使用向上和向下方向键切换图片"))
        let guidanceFooter = FraloStyle.stack([sidebarGuidance], spacing: 0, fillWidth: true)
        guidanceFooter.detachesHiddenViews = true
        let left = DockedSidebar(header: heading, body: list, footer: guidanceFooter)
        left.installPlaceholder(sidebarPlaceholder); left.dropRouter = dropRouter
        sidebarPlaceholder.addButton.onPress = { [weak self] in self?.addImages(nil) }
        list.onSelection = { [weak self] _ in self?.selectionChanged() }
        list.onDelete = { [weak self] in self?.removeSelected(nil) }
        list.documentView?.menu = batchItemsMenu()
        exportAction.onExportAll = { [weak self] in self?.exportAll(nil) }
        exportAction.onExportCurrent = { [weak self] in self?.exportCurrent(nil) }
        let inspectorBody = buildInspector()
        dimensions.alignment = .center
        inspectorUI.mode.setAccessibilityLabel(L10n.tr("成品背景"))
        let right = FloatingPanel(header: FraloStyle.stack([inspectorUI.mode], spacing: 8, fillWidth: true),
                                  body: inspectorBody, footer: inspectorUI.makeFooter(action: exportAction), bodySpacing: 16,
                                  useNativeGlass: inspectorUsesNativeGlass)
        workbench = WorkbenchView(left: left, right: right, content: center.view)
        workbench.configure(in: splitController, contentController: center)
        workbench.collapsed = preferences.bool(forKey: "sidebarCollapsed")
        workbench.inspectorHidden = preferences.bool(forKey: "inspectorHidden")
        workbench.onGeometryChange = { [weak self] in self?.layoutPreview() }
        workbench.onPanelVisibilityChange = { [weak self] in self?.updatePanelControls() }
        window?.contentViewController = splitController
        buildPreview()
        header = WorkbenchHeader(owner: self, splitView: workbench.splitView, menu: moreMenu(), sidebarHidden: workbench.collapsed)
        window?.toolbar = header.toolbar
        workbench.toolbarBehavior.focusViews = { [weak self] in self?.header.controlViews ?? [] }
        workbench.toolbarBehavior.menus = { [weak self] in self?.header.controlMenus ?? [] }
        window?.acceptsMouseMovedEvents = true
        updatePanelControls()
        requestPreview()
        updateActions(); window?.recalculateKeyViewLoop()
    }

    private func buildPreview() {
        previewScroll.documentView = canvas; previewScroll.hasVerticalScroller = true; previewScroll.hasHorizontalScroller = true
        // The same thin, trackless knob as the sidebar list, on both axes.
        previewScroll.verticalScroller = ThinScroller(); previewScroll.horizontalScroller = ThinScroller()
        previewScroll.verticalScroller?.controlSize = .small; previewScroll.horizontalScroller?.controlSize = .small
        previewScroll.autohidesScrollers = true; previewScroll.scrollerStyle = NSScroller.preferredScrollerStyle; previewScroll.drawsBackground = false
        previewScroll.automaticallyAdjustsContentInsets = false; previewScroll.contentInsets = NSEdgeInsetsZero
        previewScroll.translatesAutoresizingMaskIntoConstraints = false
        previewScroll.onResize = { [weak self] in self?.layoutPreview() }
        previewScroll.onScroll = { [weak self] in self?.updateCanvasOverlays() }
        center.view.addSubview(previewScroll)
        footer.translatesAutoresizingMaskIntoConstraints = false; center.view.addSubview(footer)
        fitMenu.removeAllItems(); fitMenu.addItems(withTitles: [L10n.tr("适应窗口"), "25%", "50%", "100%", "200%"])
        fitMenu.target = self; fitMenu.action = #selector(zoomMenuChanged(_:))
        viewing.composition.removeAllItems(); viewing.composition.addItems(withTitles: CanvasRatio.allCases.map(\.rawValue))
        viewing.composition.onChange = { [weak self] index in self?.inspectorUI.chooseCanvas(CanvasRatio.allCases[index]) }
        viewing.zoomOut.onPress = { [weak self] in self?.zoomOut(nil) }
        viewing.zoomIn.onPress = { [weak self] in self?.zoomIn(nil) }
        viewing.translatesAutoresizingMaskIntoConstraints = false; footer.addSubview(viewing)
        canvas.onPrevious = { [weak self] in self?.moveSelection(-1) }
        canvas.onNext = { [weak self] in self?.moveSelection(1) }
        canvas.onEscape = { [weak self] in if self?.workbench.previewing == true { self?.togglePreview() } }
        footerTrailing = footer.trailingAnchor.constraint(equalTo: center.view.trailingAnchor)
        NSLayoutConstraint.activate([
            previewScroll.topAnchor.constraint(equalTo: center.view.topAnchor), previewScroll.leadingAnchor.constraint(equalTo: center.view.leadingAnchor), previewScroll.trailingAnchor.constraint(equalTo: center.view.trailingAnchor), previewScroll.bottomAnchor.constraint(equalTo: center.view.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: center.view.leadingAnchor, constant: 24), footerTrailing!, footer.bottomAnchor.constraint(equalTo: center.view.bottomAnchor), footer.heightAnchor.constraint(equalToConstant: 76),
            viewing.centerXAnchor.constraint(equalTo: footer.centerXAnchor), viewing.centerYAnchor.constraint(equalTo: footer.centerYAnchor), viewing.widthAnchor.constraint(lessThanOrEqualTo: footer.widthAnchor), viewing.heightAnchor.constraint(equalToConstant: ViewToolbar.height)
        ])
        emptyAction.onPress = { [weak self] in self?.addImages(nil) }
        for view in [emptyStage, appendOverlay] {
            view.translatesAutoresizingMaskIntoConstraints = false; center.view.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: center.view.leadingAnchor), view.trailingAnchor.constraint(equalTo: center.view.trailingAnchor),
                view.topAnchor.constraint(equalTo: center.view.topAnchor), view.bottomAnchor.constraint(equalTo: center.view.bottomAnchor)
            ])
        }
        operationFeedback.translatesAutoresizingMaskIntoConstraints = false; center.view.addSubview(operationFeedback)
        feedbackTop = operationFeedback.topAnchor.constraint(equalTo: center.view.topAnchor)
        // The capsule hugs its message; long failure details truncate rather than widen past the stage.
        NSLayoutConstraint.activate([
            feedbackTop!, operationFeedback.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            operationFeedback.widthAnchor.constraint(lessThanOrEqualTo: footer.widthAnchor, constant: -24),
            operationFeedback.centerXAnchor.constraint(equalTo: footer.centerXAnchor)
        ])
    }

    private func buildInspector() -> NSView {
        inspectorUI = CompositionInspector(settings: settings)
        inspectorUI.onChange = { [weak self] value in
            guard let self, !self.isExporting, value != self.settings else { return }
            if self.continuousSettingsStart == nil { self.registerSettingsUndo(self.settings, name: L10n.tr("调整出图设置")) }
            let framing = Self.framing(self.settings) != Self.framing(value)
            self.settings = value
            if framing { self.scheduleThumbnails() }
            do { try self.store.save(value) } catch { self.showError(error.localizedDescription, title: L10n.tr("无法保存设置")) }
            self.requestPreview()
        }
        inspectorUI.onContinuousEditing = { [weak self] active in
            guard let self else { return }
            if active { self.continuousSettingsStart = self.settings }
            else if let initial = self.continuousSettingsStart {
                self.continuousSettingsStart = nil
                if initial != self.settings { self.registerSettingsUndo(initial, name: L10n.tr("调整出图设置")) }
            }
        }
        canvas.onDragStart = { [weak self] point in self?.beginArtworkDrag(at: point) }
        canvas.onDrag = { [weak self] delta in self?.dragArtwork(delta) }
        canvas.onDragEnd = { [weak self] in self?.finishArtworkDrag() }
        return inspectorUI
    }
    /// The device moves when the drag starts on it; empty canvas pans an image background that overflows the canvas.
    private func beginArtworkDrag(at fraction: CGPoint) {
        dragsBackground = false
        guard settings.mode == .background, Self.pansBackground(settings), backgroundImageSize != nil, let layers = positioningLayers else { return }
        let point = CGPoint(x: fraction.x * layers.canvasSize.width, y: fraction.y * layers.canvasSize.height)
        let background = layers.backgroundRect(settings: settings)
        let overflows = background.width > layers.canvasSize.width + 0.5 || background.height > layers.canvasSize.height + 0.5
        dragsBackground = overflows && !layers.deviceRect(settings: settings).contains(point)
    }
    private static func pansBackground(_ settings: CompositionSettings) -> Bool { settings.background != .solid && settings.background != .gradient }
    private func dragArtwork(_ delta: CGPoint, snapping: Bool = true) {
        guard settings.mode == .background, positioningLayers != nil, !isExporting else { return }
        if !artworkDragChanged {
            dragSettingsStart = settings
            // Invalidate any pending final image before the first live transform.
            previewRequest += 1; renderWork?.cancel(); previewToken.cancel()
            rendered = nil; renderedID = nil
            inspectorUI.showOutputSize(nil); viewing.finishPreviewUpdate(); updateActions()
        }
        artworkDragChanged = true
        if dragsBackground {
            if let backgroundImageSize { CompositionRenderer.panBackground(&settings, delta: delta, imageSize: backgroundImageSize) }
        } else {
            let previous = dragDevicePosition ?? CGPoint(x: settings.deviceX, y: settings.deviceY)
            let next = CGPoint(x: min(1, max(-1, previous.x + delta.x)), y: min(1, max(-1, previous.y + delta.y)))
            dragDevicePosition = next; settings.deviceX = next.x; settings.deviceY = next.y
            if snapping && abs(settings.deviceX) < 0.012 { settings.deviceX = 0 }
            if snapping && abs(settings.deviceY) < 0.012 { settings.deviceY = 0 }
            canvas.centerGuideX = settings.deviceX == 0; canvas.centerGuideY = settings.deviceY == 0
        }
        inspectorUI.set(settings)
        if let layers = positioningLayers {
            canvas.positionArtwork(deviceRect: layers.deviceRect(settings: settings), backgroundRect: layers.backgroundRect(settings: settings))
        }
    }

    private func finishArtworkDrag() {
        canvas.centerGuideX = false; canvas.centerGuideY = false; dragDevicePosition = nil
        let movedBackground = dragsBackground; dragsBackground = false
        guard artworkDragChanged else { return }; artworkDragChanged = false
        if let initial = dragSettingsStart, initial != settings {
            registerSettingsUndo(initial, name: movedBackground ? L10n.tr("移动背景") : L10n.tr("移动设备"))
        }
        dragSettingsStart = nil
        do { try store.save(settings) } catch { showError(error.localizedDescription, title: L10n.tr("无法保存设置")) }
        requestPreview(preservePositioning: true)
    }

    private func remember(_ name: String, restore: @escaping @MainActor (MainWindowController) -> Void) {
        let group = !history.isUndoing && !history.isRedoing && history.groupingLevel == 0
        if group { history.beginUndoGrouping() }
        history.registerUndo(withTarget: self) { target in MainActor.assumeIsolated { restore(target) } }
        history.setActionName(name)
        if group { history.endUndoGrouping() }
    }
    private func registerSettingsUndo(_ snapshot: CompositionSettings, name: String) {
        remember(name) { target in
            target.registerSettingsUndo(target.settings, name: name)
            let framingChanged = Self.framing(target.settings) != Self.framing(snapshot)
            target.settings = snapshot; target.inspectorUI.restore(snapshot)
            if framingChanged { target.scheduleThumbnails() }
            do { try target.store.save(snapshot) } catch { target.showError(error.localizedDescription, title: L10n.tr("无法保存设置")) }
            target.requestPreview()
        }
    }
    private func rememberBatch(_ name: String) {
        let snapshot = items, selected = selectedIndex
        remember(name) { target in
            target.rememberBatch(name)
            target.items = snapshot; target.refreshList()
            if !snapshot.isEmpty { target.list.select(min(selected ?? 0, snapshot.count - 1)) }
            target.scheduleThumbnails(); target.updateActions(); target.requestPreview()
            target.window?.makeFirstResponder(snapshot.isEmpty ? target.emptyAction : target.list.documentView)
        }
    }
    private var commandUndoManager: UndoManager {
        if let editor = window?.firstResponder as? NSTextView, editor.isEditable,
           let manager = editor.undoManager, manager.canUndo || manager.canRedo { return manager }
        return history
    }
    @objc func undoChange(_ sender: Any?) { guard !isExporting else { return }; commandUndoManager.undo() }
    @objc func redoChange(_ sender: Any?) { guard !isExporting else { return }; commandUndoManager.redo() }
    @objc func previousImage(_ sender: Any?) { moveSelection(-1) }
    @objc func nextImage(_ sender: Any?) { moveSelection(1) }
    @objc func nudgeArtwork(_ sender: NSMenuItem) {
        guard let point = (sender.representedObject as? NSValue)?.pointValue else { return }
        dragsBackground = false
        dragArtwork(CGPoint(x: point.x / settings.canvas.size.width, y: point.y / settings.canvas.size.height), snapping: false)
        finishArtworkDrag()
    }
    private func updateCanvasInteraction() {
        let enabled = settings.mode == .background && selectedIndex != nil && positioningLayers != nil && !isExporting
        canvas.allowsPositioning = enabled
        let help: String
        if enabled && Self.pansBackground(settings) {
            help = L10n.tr("拖动设备调整位置，拖动空白处调整背景；按 ⌥ 和方向键微调设备。上下键切换图片，Esc 返回编辑。")
        } else if enabled {
            help = L10n.tr("拖动设备调整位置；按 ⌥ 和方向键微调设备。上下键切换图片，Esc 返回编辑。")
        } else {
            help = L10n.tr("上下键切换图片，Tab 切换焦点，Esc 返回编辑。")
        }
        canvas.toolTip = help; canvas.setAccessibilityHelp(help)
    }

    private func moreMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(actionItem(L10n.tr("添加图片…"), #selector(addImages(_:)), symbol: "photo.badge.plus", key: "o"))
        menu.addItem(actionItem(L10n.tr("导入文件夹…"), #selector(addFolder(_:)), symbol: "folder.badge.plus", key: "o", modifiers: [.command, .shift]))
        menu.addItem(actionItem(L10n.tr("粘贴图片"), #selector(pasteImage(_:)), symbol: "doc.on.clipboard", key: "v"))
        menu.addItem(.separator())
        batchItemsMenu().items.forEach { $0.menu?.removeItem($0); menu.addItem($0) }
        menu.addItem(.separator())
        menu.addItem(actionItem(L10n.tr("设置…"), #selector(showSettings(_:)), symbol: "gearshape", key: ","))
        return menu
    }
    /// Shared by the more menu, the list's context menu and the batch button so their wording, icons and shortcuts agree.
    private func batchItemsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(actionItem(L10n.tr("删除"), #selector(removeSelected(_:)), symbol: "trash", key: "\u{8}", modifiers: []))
        menu.addItem(actionItem(L10n.tr("清空所有"), #selector(newBatch(_:)), symbol: "xmark.bin"))
        return menu
    }
    private func updatePanelControls() {
        guard header != nil else { return }
        header.update(name: selectedIndex.map { items[$0].input.name } ?? "Fralo", subtitle: headerSubtitle,
                      sidebarHidden: workbench.collapsed || workbench.previewing,
                      inspectorVisible: !workbench.inspectorHidden && !workbench.previewing,
                      canAdd: !isExporting, canCopy: rendered != nil && !isExporting, canExport: selectedIndex != nil && !isExporting)
        if workbench.collapsed, let focus = window?.firstResponder as? NSView, workbench.left.containsSidebarView(focus) {
            window?.makeFirstResponder(canvas)
        }
        // Opening the list by any route while it is collapsed for an empty batch is the user's choice.
        if sidebarCollapsedForEmptyBatch && !workbench.collapsed { sidebarCollapsedForEmptyBatch = false }
        if !sidebarCollapsedForEmptyBatch { preferences.set(workbench.collapsed, forKey: "sidebarCollapsed") }
        window?.recalculateKeyViewLoop()
    }

    /// Key equivalents mirror the main menu so pop-up menus teach the shortcut; the main menu still handles the keystroke.
    private func actionItem(_ title: String, _ action: Selector, symbol: String? = nil, key: String = "",
                            modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers; item.target = self
        item.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        // macOS 27 hides menu images by default; these icons are part of the confirmed FRALO-15 design.
        // Set by key so SDKs older than macOS 27 still build; 1 is NSMenuItemImageVisibilityVisible.
        if item.image != nil, item.responds(to: Selector(("setPreferredImageVisibility:"))) {
            item.setValue(1, forKey: "preferredImageVisibility")
        }
        return item
    }
    func selectAppearance(_ value: String, persist: Bool = true) {
        guard let choice = AppAppearance(rawValue: value) else { return }
        appearanceChoice = choice
        // App-wide, so About, Settings, alerts and update windows follow the workbench.
        NSApp.appearance = choice.appearance
        settingsController?.set(choice)
        if persist { preferences.set(value, forKey: "workbenchAppearance") }
    }
    /// Settings is the only place to edit app-level preferences; there is no duplicate View menu entry.
    @objc func showSettings(_ sender: Any?) {
        if settingsController == nil {
            settingsController = SettingsWindowController(selection: appearanceChoice, updates: updatePreferences, preferences: preferences,
                                                          language: language) { _ in }
            bindSettings()
        }
        settingsController?.set(appearanceChoice); settingsController?.present()
    }
    var batchCountForTesting: Int { items.count }
    private func bindSettings() {
        settingsController?.onAppearanceChange = { [weak self] value in self?.selectAppearance(value.rawValue) }
        settingsController?.onLanguageChange = { [weak self] language in self?.onLanguageChange?(language) ?? false }
    }
    /// Takes over the batch, selection and Settings window from the window being replaced after a language change.
    /// Undo history stays with the old window: its actions refer to that window's views.
    func adopt(from old: MainWindowController) {
        updatePreferences = old.updatePreferences
        pastedCount = old.pastedCount; zoom = old.zoom
        items = old.items; refreshList()
        if let selected = old.selectedIndex, items.indices.contains(selected) { list.select(selected) }
        else if !items.isEmpty { list.select(0) }
        settingsController = old.settingsController; old.settingsController = nil
        settingsController?.updates = updatePreferences
        bindSettings()
        updateActions(); requestPreview()
    }
    @objc func toggleSidebar(_ sender: Any?) {
        if workbench.previewing {
            togglePreview(); workbench.setCollapsed(false, animated: true)
            preferences.set(false, forKey: "sidebarCollapsed"); window?.makeFirstResponder(list.documentView); return
        }
        let focusWasInList = (window?.firstResponder as? NSView).map { workbench.left.containsSidebarView($0) } ?? false
        sidebarCollapsedForEmptyBatch = false
        workbench.setCollapsed(!workbench.collapsed, animated: true)
        preferences.set(workbench.collapsed, forKey: "sidebarCollapsed")
        if !workbench.previewing && (!workbench.collapsed || focusWasInList) {
            window?.makeFirstResponder(workbench.collapsed ? canvas : list.documentView)
        }
    }
    @objc func toggleInspector(_ sender: Any?) {
        if workbench.previewing {
            togglePreview()
            workbench.setInspectorHidden(false, animated: true)
        } else {
            let focusWasInInspector = (window?.firstResponder as? NSView).map { $0.isDescendant(of: workbench.right) } ?? false
            workbench.setInspectorHidden(!workbench.inspectorHidden, animated: true)
            if workbench.inspectorHidden && focusWasInInspector { window?.makeFirstResponder(canvas) }
        }
        preferences.set(workbench.inspectorHidden, forKey: "inspectorHidden")
    }
    @objc func togglePreview(_ sender: Any? = nil) {
        if !workbench.previewing { previewRestoreFocus = window?.firstResponder }
        workbench.previewing.toggle()
        let restore = previewRestoreFocus as? NSView
        let canRestore = restore.map { !$0.isHiddenOrHasHiddenAncestor } ?? false
        window?.makeFirstResponder(workbench.previewing || !canRestore ? canvas : restore); layoutPreview()
    }
    private func moveSelection(_ delta: Int) { list.moveSelection(by: delta) }
    private func selectionChanged() { updateActions(); requestPreview() }
    private func refreshList() {
        itemIndices = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.input.id, $0.offset) })
        list.update(items.map { batchEntry(for: $0) })
    }
    private func batchEntry(for item: Item) -> BatchEntry {
        let dimensions = item.pixelSize.map { "\(Int($0.width)) × \(Int($0.height))" }
        return BatchEntry(id: item.input.id, title: item.input.name, detail: dimensions ?? "",
                          detailToolTip: dimensions.map { L10n.tr("原图尺寸：\($0) 像素") },
                          image: item.thumbnail, failed: item.error != nil)
    }
    @objc private func batchMenu(_ sender: NSButton) {
        let menu = batchItemsMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 2), in: sender)
    }
    @objc func addImages(_ sender: Any?) {
        guard !isExporting else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg]; panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false; panel.message = L10n.tr("选择要套框的截图")
        panel.beginSheetModal(for: window!) { [weak self] response in if response == .OK { self?.importURLs(panel.urls) } }
    }
    @objc func addFolder(_ sender: Any?) {
        guard !isExporting else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = L10n.tr("导入文件夹当前层的 PNG / JPEG 图片")
        panel.beginSheetModal(for: window!) { [weak self] response in if response == .OK { self?.importURLs(panel.urls) } }
    }
    func importURLs(_ urls: [URL]) {
        guard !urls.isEmpty, !isExporting else { return }
        do {
            let inputs = try InputCollector.collect(urls)
            let existing = Set(items.map { $0.input.id })
            let accepted = inputs.filter { !existing.contains($0.id) }
            guard !accepted.isEmpty else { return }
            rememberBatch(L10n.tr("添加图片"))
            items += accepted.map { Item(input: $0) }
            refreshList(); updateActions()
            if selectedIndex == nil { list.select(0) }
            scheduleThumbnails(); requestPreview()
        } catch { showError(error.localizedDescription) }
    }
    /// AppKit can fall back from the key window to the main window's responders.
    /// Only a focused, unobstructed workbench may interpret standard paste as an image import.
    private var acceptsImagePaste: Bool {
        window?.isKeyWindow == true && window?.attachedSheet == nil && !isExporting
    }
    @objc func paste(_ sender: Any?) {
        guard acceptsImagePaste else { return }
        pasteImage(sender)
    }
    @objc func pasteImage(_ sender: Any?) {
        if let editor = window?.firstResponder as? NSTextView, editor.isEditable { editor.paste(sender); return }
        guard !isExporting else { return }
        let pasteboard = self.pasteboard
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty { importURLs(urls); return }
        let data: Data?
        if let png = pasteboard.data(forType: .png) { data = png }
        else if let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) { data = bitmap.representation(using: .png, properties: [:]) }
        else { data = nil }
        guard let data else { showError(L10n.tr("剪贴板中没有可导入的图片。")); return }
        rememberBatch(L10n.tr("粘贴图片"))
        pastedCount += 1
        items.append(Item(input: ImageInput(data: data, name: String(format: L10n.tr("粘贴图片-%03d.png"), pastedCount))))
        refreshList(); list.select(items.count - 1)
        updateActions(); scheduleThumbnails(); requestPreview()
    }
    @objc func removeSelected(_ sender: Any?) {
        guard !isExporting, let selectedIndex else { return }
        rememberBatch(L10n.tr("删除图片"))
        items.remove(at: selectedIndex); refreshList()
        if !items.isEmpty { list.select(min(selectedIndex, items.count - 1)) }
        updateActions(); scheduleThumbnails(); requestPreview()
        if items.isEmpty { window?.makeFirstResponder(emptyAction) }
    }
    @objc func newBatch(_ sender: Any?) {
        guard !isExporting else { return }
        if !items.isEmpty { rememberBatch(L10n.tr("清空所有")) }
        items.removeAll(); previewRequest += 1; thumbnails.cancel(); rendered = nil; renderedID = nil
        refreshList(); updateActions(); requestPreview()
        window?.makeFirstResponder(emptyAction)
    }

    /// Settings that change the framed thumbnail silhouette.
    private static func framing(_ s: CompositionSettings) -> [String] {
        [ThumbnailPipeline.styleKey(s)]
    }
    private func scheduleThumbnails() {
        var inputs = items.map(\.input)
        if let selectedIndex, selectedIndex > 0 { inputs.insert(inputs.remove(at: selectedIndex), at: 0) }
        thumbnails.request(inputs, settings: settings) { [weak self] id, result in
            guard let self, let index = self.itemIndices[id] else { return }
            switch result {
            case .success(let value):
                self.items[index].thumbnail = NSImage(cgImage: value.image, size: NSSize(width: value.image.width, height: value.image.height))
                self.items[index].pixelSize = value.pixelSize; self.items[index].error = nil
            case .failure(let error):
                self.items[index].thumbnail = nil; self.items[index].error = error.localizedDescription
            }
            let item = self.items[index]
            self.list.updateEntry(self.batchEntry(for: item), at: index)
        }
    }
    private func requestPreview(preservePositioning: Bool = false) {
        operationFeedback.dismiss()
        if !preservePositioning {
            dragSettingsStart = nil
            artworkDragChanged = false; dragDevicePosition = nil; positioningLayers = nil
            canvas.finishPositioningArtwork(discard: true)
            canvas.centerGuideX = false; canvas.centerGuideY = false
        }
        previewRequest += 1; renderWork?.cancel(); rendered = nil; renderedID = nil
        previewToken.cancel(); let token = CancellationToken(); previewToken = token
        inspectorUI.showOutputSize(nil, busy: selectedIndex != nil)
        guard let index = selectedIndex else {
            canvas.image = nil; showEmptyGuidance(); emptyStage.isHidden = false
            previewScroll.isHidden = true; footer.isHidden = true; filename.stringValue = ""; position.stringValue = ""
            window?.title = "Fralo"; dimensions.stringValue = L10n.tr("尚无成品"); inspectorUI.outputInfo.stringValue = "—"; viewing.finishPreviewUpdate(); updateActions(); return
        }
        let input = items[index].input, snapshot = settings, generation = previewRequest
        window?.title = input.name; filename.stringValue = input.name; position.stringValue = "\(index + 1) / \(items.count)"
        emptyStage.isHidden = true; previewScroll.isHidden = false; footer.isHidden = false
        viewing.beginPreviewUpdate(); updateActions()
        let work = DispatchWorkItem { [weak self] in
            guard !token.isCancelled else { return }
            let result = autoreleasepool { Result { () -> (RenderedComposition, CGImage, CGSize, CGSize?, Int?) in
                let backdrop = try CompositionRenderer.backgroundData(snapshot)
                let frame = try CompositionRenderer.render(input, settings: snapshot, backgroundData: backdrop, preparePreviewLayers: true)
                guard !token.isCancelled else { throw CancellationError() }
                let encoded = snapshot.outputFormat == .jpeg || !snapshot.pngLossless ? try CompositionRenderer.data(frame.image, settings: snapshot) : nil
                guard !token.isCancelled else { throw CancellationError() }
                let display = try encoded.map { try ImageInput(data: $0, name: "preview").decode() } ?? frame.image
                return (frame, display, try input.dimensions(), try backdrop.map { try ImageInput(data: $0, name: "background.png").dimensions() }, encoded?.count)
            } }
            // NSMenu runs a nested event-tracking loop, which does not drain main-queue work.
            RunLoop.main.perform(inModes: [.default, .eventTracking, .modalPanel]) {
                MainActor.assumeIsolated {
                    guard let self, self.previewRequest == generation else { return }
                    self.viewing.finishPreviewUpdate()
                    switch result {
                    case .success(let (frame, display, sourceSize, backgroundSize, byteCount)):
                        self.backgroundImageSize = backgroundSize
                        if let row = self.items.firstIndex(where: { $0.input.id == input.id }), self.items[row].error != nil { self.items[row].error = nil; self.refreshList() }
                        self.dimensions.toolTip = L10n.tr("原始图片：\(input.name) · \(Int(sourceSize.width)) × \(Int(sourceSize.height))")
                        self.inspectorUI.outputInfo.stringValue = "\(Int(frame.pixelSize.width)) × \(Int(frame.pixelSize.height))"
                        self.inspectorUI.showOutputSize(byteCount, busy: byteCount == nil && !self.isExporting)
                        self.positioningLayers = frame.previewLayers
                        self.canvas.finishPositioningArtwork(discard: true)
                        if let layers = frame.previewLayers {
                            self.canvas.prepareArtwork(background: layers.background, device: layers.device,
                                backgroundOpacity: layers.backgroundOpacity, canvasSize: layers.canvasSize)
                        }
                        self.rendered = frame; self.renderedID = input.id; self.canvas.image = NSImage(cgImage: display, size: frame.pixelSize)
                        self.canvas.setAccessibilityLabel(L10n.tr("成品画布，\(input.name)"))
                        self.canvas.showsElevation = snapshot.mode == .background
                        self.applyCanvasBacking()
                        self.dimensions.stringValue = "\(snapshot.outputFormat == .png ? "PNG" : "JPEG") · \(Int(frame.pixelSize.width)) × \(Int(frame.pixelSize.height))"
                        self.emptyStage.isHidden = true; self.layoutPreview()
                        if byteCount == nil { self.calculateCurrentSize() }
                    case .failure(let error):
                        self.inspectorUI.showOutputSize(nil)
                        self.positioningLayers = nil; self.canvas.finishPositioningArtwork(discard: true)
                        self.canvas.image = nil; self.emptyStage.isHidden = false
                        self.emptyAction.title = L10n.tr("重试预览"); self.emptyAction.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
                        self.emptyAction.setAccessibilityLabel(L10n.tr("重试预览"))
                        self.emptyAction.onPress = { [weak self] in self?.scheduleThumbnails(); self?.requestPreview() }
                        self.emptyStage.showError(error.localizedDescription)
                        self.previewScroll.isHidden = true; self.footer.isHidden = true; self.dimensions.stringValue = L10n.tr("无法确定")
                        if let i = self.items.firstIndex(where: { $0.input.id == input.id }) { self.items[i].error = error.localizedDescription; self.refreshList() }
                    }
                    self.updateActions()
                    self.window?.displayIfNeeded()
                }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
        renderWork = work; renderQueue.async(execute: work)
    }

    private func calculateCurrentSize() {
        guard let rendered, let index = selectedIndex, renderedID == items[index].input.id, !isExporting else { return }
        let generation = previewRequest, snapshot = settings
        inspectorUI.showOutputSize(nil, busy: true)
        sizeQueue.async { [weak self] in
            let result = autoreleasepool { Result { try CompositionRenderer.data(rendered.image, settings: snapshot).count } }
            DispatchQueue.main.async {
                guard let self, self.previewRequest == generation else { return }
                switch result {
                case .success(let count): self.inspectorUI.showOutputSize(count)
                case .failure: self.inspectorUI.showOutputSize(nil)
                }
            }
        }
    }

    private func layoutPreview() {
        guard !layingOutPreview else { return }
        layingOutPreview = true; defer { layingOutPreview = false }
        defer { updateCanvasOverlays() }
        let insets = workbench.viewingInsets
        footerTrailing?.constant = -insets.right
        feedbackTop?.constant = workbench.headerHeight + 12
        // The empty frame and append outline share the canvas' viewing margins; no floating bar while empty.
        emptyStage.viewingInsets = NSEdgeInsets(top: insets.top, left: insets.left, bottom: 24, right: insets.right)
        appendOverlay.viewingInsets = NSEdgeInsets(top: workbench.headerHeight + 8, left: 14, bottom: 14,
                                                   right: insets.right - 24 + (workbench.inspectorHidden || workbench.previewing ? 14 : 8))
        // Overlay scrollers start below the header instead of running under the toolbar.
        let scrollerInsets = NSEdgeInsets(top: workbench.headerHeight, left: 0, bottom: 0, right: 0)
        if previewScroll.scrollerInsets.top != scrollerInsets.top { previewScroll.scrollerInsets = scrollerInsets }
        viewing.fitControls(to: max(0, center.view.bounds.width - insets.left - insets.right))
        guard let rendered else { return }
        let pixels = rendered.pixelSize, backing = window?.backingScaleFactor ?? 2
        let reference = rendered.previewReferenceSize
        // Document gutters keep all image edges reachable without painting toolbar bars.
        let top = insets.top, bottom = insets.bottom
        canvas.viewingInsets = insets
        var factor: CGFloat = 0
        // Legacy scrollers consume viewport space; overlay scrollers do not. Settle native
        // tiling synchronously before publishing a fit scale or retaining a scroll position.
        for _ in 0..<4 {
            previewScroll.tile()
            let available = previewScroll.contentView.bounds.size
            guard available.width > 0, available.height > 0 else { return }
            factor = zoom.map { $0 / backing } ?? min(max(10, available.width - insets.left - insets.right - 8) / reference.width, max(10, available.height - top - bottom - 32) / reference.height)
            let size = NSSize(width: pixels.width * factor, height: pixels.height * factor)
            let document = NSSize(width: max(available.width, size.width + insets.left + insets.right + 8), height: max(available.height, size.height + top + bottom + 32))
            canvas.setFrameSize(document); canvas.zoom = factor
            previewScroll.tile()
            if zoom == nil {
                previewScroll.contentView.scroll(to: .zero)
                previewScroll.reflectScrolledClipView(previewScroll.contentView)
            }
            if previewScroll.contentView.bounds.size == available { break }
        }
        let percent = "\(Int((factor * backing * 100).rounded()))%"
        viewing.showStatus(percent, detail: "\(Int(pixels.width)) × \(Int(pixels.height)) px")
        // Presets keep their checkmark; a stepped zoom between presets selects none.
        let presets: [CGFloat?] = [nil, 0.25, 0.5, 1, 2]
        if let match = presets.firstIndex(where: { $0 == zoom }) { fitMenu.selectItem(at: match) } else { fitMenu.select(nil) }
        viewing.zoomOut.isEnabled = currentZoom > Self.zoomLevels.first! * 1.01
        viewing.zoomIn.isEnabled = currentZoom < Self.zoomLevels.last! * 0.99
        viewing.showsComposition = false
        viewing.composition.selectItem(at: CanvasRatio.allCases.firstIndex(of: settings.canvas) ?? 1)
        viewing.composition.displayTitle = "\(settings.canvas.rawValue) · \(Int(pixels.width)) × \(Int(pixels.height))"
    }
    /// Floating chrome reacts to the artwork actually beneath it.
    private func updateCanvasOverlays() { updateHeaderOverlap(); updateCapsuleBackdrop() }
    private func updateCapsuleBackdrop() {
        guard canvas.image != nil, !previewScroll.isHidden, !footer.isHidden, viewing.window != nil else { viewing.backdropLuminance = nil; return }
        viewing.backdropLuminance = canvas.artworkLuminance(under: canvas.convert(viewing.bounds, from: viewing))
    }
    /// The header backdrop also appears whenever artwork actually sits beneath it.
    private func updateHeaderOverlap() {
        guard let workbench else { return }
        let rect = canvas.image == nil || previewScroll.isHidden ? NSRect.zero : canvas.imageRect
        let band = workbench.headerBackdrop
        workbench.contentUnderHeader = !rect.isEmpty && band.convert(rect, from: canvas).intersects(band.bounds)
    }
    @objc func fitPreview(_ sender: Any?) { zoom = nil; layoutPreview() }
    @objc func actualPixels(_ sender: Any?) { zoom = 1; layoutPreview() }
    @objc func zoomIn(_ sender: Any?) { setZoom(by: 1.25) }
    @objc func zoomOut(_ sender: Any?) { setZoom(by: 0.8) }
    /// Standard magnifications, as in Preview: stepping lands on familiar percentages, never 27% or 34%.
    static let zoomLevels: [CGFloat] = [0.05, 0.1, 0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2, 3, 4, 6, 8]
    private var currentZoom: CGFloat { zoom ?? ((canvas.zoom ?? 0) * (window?.backingScaleFactor ?? 2)) }
    private func setZoom(by multiplier: CGFloat) {
        let current = currentZoom, levels = Self.zoomLevels
        let next = multiplier > 1 ? levels.first { $0 > current * 1.01 } : levels.last { $0 < current * 0.99 }
        guard let next else { return }
        zoom = next; layoutPreview()
    }
    @objc private func zoomMenuChanged(_ sender: Any?) {
        zoom = [nil, CGFloat(0.25), CGFloat(0.5), CGFloat(1), CGFloat(2)][fitMenu.indexOfSelectedItem]; layoutPreview()
    }

    @objc func copyCurrent(_ sender: Any?) {
        if sender is NSMenuItem, let editor = window?.firstResponder as? NSTextView, editor.isEditable { editor.copy(sender); return }
        guard let rendered, let index = selectedIndex, renderedID == items[index].input.id else { return }
        do {
            let data = settings.outputFormat == .png ? try CompositionRenderer.data(rendered.image, settings: settings) : try FrameRenderer.pngData(rendered.image)
            guard imageClipboard.writePNG(data) else {
                operationFeedback.show(.failure, title: L10n.tr("复制失败"), detail: L10n.tr("无法写入剪贴板，请重试"))
                return
            }
            operationFeedback.show(.success, title: L10n.tr("已复制到剪贴板"))
        } catch {
            operationFeedback.show(.failure, title: L10n.tr("复制失败"), detail: error.localizedDescription)
        }
    }
    @objc func exportAll(_ sender: Any?) {
        guard !items.isEmpty, !isExporting else { return }
        window?.makeFirstResponder(nil)
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = L10n.tr("导出"); panel.message = L10n.tr("选择输出文件夹")
        let overwrite = NSButton(checkboxWithTitle: L10n.tr("覆盖已有同名输出文件"), target: nil, action: nil); panel.accessoryView = overwrite
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let directory = panel.url, let self else { return }
            self.startExport(self.items.map(\.input), directory: directory, overwrite: overwrite.state == .on)
        }
    }
    @objc func exportCurrent(_ sender: Any?) {
        guard let index = selectedIndex, !isExporting else { return }
        window?.makeFirstResponder(nil)
        let input = items[index].input
        let panel = NSSavePanel(); panel.allowedContentTypes = [settings.outputFormat == .png ? .png : .jpeg]; panel.canCreateDirectories = true
        panel.nameFieldStringValue = BatchExporter.outputNames(for: [input], format: settings.outputFormat)[0]
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.startExport([input], directory: url.deletingLastPathComponent(), overwrite: true, names: [url.lastPathComponent])
        }
    }
    private func startExport(_ inputs: [ImageInput], directory: URL, overwrite: Bool, names: [String]? = nil) {
        let snapshot = settings, token = CancellationToken()
        let backdrop: Data?
        do { backdrop = try CompositionRenderer.backgroundData(snapshot) } catch { showError(error.localizedDescription); return }
        cancellation = token; updateActions()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 470, height: 240), styleMask: [.titled], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        let count = label(L10n.tr("已完成 0 / \(inputs.count)"))
        let current = label(L10n.tr("正在准备…"), size: 12, secondary: true); current.lineBreakMode = .byTruncatingMiddle
        let bar = NSProgressIndicator(); bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = Double(inputs.count); bar.style = .bar
        bar.widthAnchor.constraint(equalToConstant: 414).isActive = true
        let cancel = ActionButton(L10n.tr("取消"))
        cancel.target = self; cancel.action = #selector(cancelExportAction(_:)); cancel.keyEquivalent = "\u{1b}"
        let notice = label("", size: 12, secondary: true); updateNotice = notice
        let content = stack([label(L10n.tr("正在导出图片"), size: 16, weight: .semibold), count, bar, current, notice, cancel], spacing: 12)
        content.alignment = .centerX; content.translatesAutoresizingMaskIntoConstraints = false; panel.contentView?.addSubview(content)
        NSLayoutConstraint.activate([content.centerXAnchor.constraint(equalTo: panel.contentView!.centerXAnchor), content.centerYAnchor.constraint(equalTo: panel.contentView!.centerYAnchor)])
        progressPanel = panel; window?.beginSheet(panel)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try BatchExporter.run(inputs: inputs, settings: RenderSettings(model: snapshot.phoneModel, orientation: snapshot.orientation), directory: directory, overwrite: overwrite, cancellation: token, outputNames: names, composition: snapshot, backgroundData: backdrop) { progress in
                    DispatchQueue.main.async { count.stringValue = L10n.tr("已完成 \(progress.completed) / \(progress.total)"); current.stringValue = L10n.tr("正在处理：\(progress.currentName)"); bar.doubleValue = Double(progress.completed) }
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.window?.endSheet(panel); self.progressPanel = nil; self.cancellation = nil; self.updateActions()
                self.updateNotice = nil
                if self.quitAfterExport { NSApp.reply(toApplicationShouldTerminate: true); return }
                switch result {
                case .success(let report):
                    // Keep cancellation/failure/skip summaries visible before installing.
                    // A wholly successful export can hand off directly without a blocking sheet.
                    if report.failed == 0 && report.skipped == 0 && !report.cancelled,
                       self.onExportFinished?() == true { return }
                    self.showReport(report, directory: directory)
                case .failure(let error): self.showError(error.localizedDescription)
                }
            }
        }
    }
    @objc private func cancelExportAction(_ sender: NSButton) { cancelExport(); sender.isEnabled = false; sender.title = L10n.tr("正在停止…") }
    func cancelExport() { cancellation?.cancel() }
    func requestQuitAfterExport() { quitAfterExport = true; cancelExport() }
    func showPendingUpdate() { updateNotice?.stringValue = L10n.tr("导出结束后将安装更新并重启 Fralo") }
    func clearPendingUpdate() { updateNotice?.stringValue = "" }
    private func showReport(_ report: ExportReport, directory: URL) {
        let alert = NSAlert(); alert.messageText = report.cancelled ? L10n.tr("导出已取消") : L10n.tr("导出完成")
        alert.informativeText = L10n.tr("成功 \(report.succeeded) 张 · 跳过 \(report.skipped) 张 · 失败 \(report.failed) 张\n未处理 \(report.unprocessed) 张 · 用时 \(String(format: "%.2f", report.durationSeconds)) 秒")
        alert.addButton(withTitle: L10n.tr("完成")); alert.addButton(withTitle: L10n.tr("打开输出文件夹"))
        let issues = report.entries.filter { $0.status != .success }
        if !issues.isEmpty {
            let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 430, height: 140)); text.isEditable = false; text.isSelectable = true; text.font = .systemFont(ofSize: 12)
            text.string = issues.map { "\($0.input)：\($0.reason ?? $0.status.rawValue)" }.joined(separator: "\n")
            let scroll = NSScrollView(frame: text.frame); scroll.documentView = text; ScrollContent.configure(scroll); alert.accessoryView = scroll
        }
        alert.beginSheetModal(for: window!) { response in if response == .alertSecondButtonReturn { NSWorkspace.shared.open(directory) } }
    }
    /// Empty-batch transitions affect presentation, never the user's visibility preference:
    /// the list collapses while there is nothing to list, and the inspector stays available for presets.
    private func synchronizePanelsWithBatch() {
        let hasImages = !items.isEmpty
        sidebarPlaceholder.isHidden = hasImages; list.isHidden = !hasImages
        batchCount.isHidden = !hasImages
        guard batchHadImages != hasImages else { return }
        batchHadImages = hasImages
        if !hasImages {
            guard !workbench.collapsed, !workbench.previewing else { return }
            let focusWasInList = (window?.firstResponder as? NSView).map { workbench.left.containsSidebarView($0) } ?? false
            sidebarCollapsedForEmptyBatch = true
            workbench.setCollapsed(true, animated: window?.isVisible == true)
            if focusWasInList { window?.makeFirstResponder(emptyAction) }
        } else if sidebarCollapsedForEmptyBatch {
            sidebarCollapsedForEmptyBatch = false
            workbench.setCollapsed(false, animated: window?.isVisible == true)
        }
    }
    private func updateActions() {
        synchronizePanelsWithBatch()
        updateCanvasInteraction()
        inspectorUI?.setEditingEnabled(!isExporting)
        batchCount.stringValue = "\(items.count)"
        addButton.isEnabled = !isExporting
        workbench.left.showsFooter = items.count >= 2 && !isExporting
        window?.subtitle = headerSubtitle
        exportAction.count = items.count; exportAction.isEnabled = !isExporting
        updatePanelControls()
        if items.isEmpty { emptyStage.isHidden = false; footer.isHidden = true; previewScroll.isHidden = true }
        updateCanvasOverlays()
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let editingText = (window?.firstResponder as? NSTextView)?.isEditable == true
        switch menuItem.action {
        case #selector(paste(_:)): return acceptsImagePaste
        case #selector(undoChange(_:)):
            let manager = commandUndoManager
            menuItem.title = manager.canUndo ? L10n.tr("撤销「\(manager.undoActionName)」") : L10n.tr("撤销")
            return !isExporting && manager.canUndo
        case #selector(redoChange(_:)):
            let manager = commandUndoManager
            menuItem.title = manager.canRedo ? L10n.tr("重做「\(manager.redoActionName)」") : L10n.tr("重做")
            return !isExporting && manager.canRedo
        case #selector(toggleSidebar(_:)):
            menuItem.title = workbench.collapsed || workbench.previewing ? L10n.tr("显示图片列表") : L10n.tr("隐藏图片列表"); return true
        case #selector(toggleInspector(_:)):
            menuItem.title = workbench.inspectorHidden || workbench.previewing ? L10n.tr("显示出图设置") : L10n.tr("隐藏出图设置"); return true
        case #selector(togglePreview(_:)):
            menuItem.title = workbench.previewing ? L10n.tr("返回编辑") : L10n.tr("成品预览"); return !items.isEmpty
        case #selector(previousImage(_:)): return !isExporting && (selectedIndex ?? 0) > 0
        case #selector(nextImage(_:)): return !isExporting && selectedIndex.map { $0 + 1 < items.count } == true
        case #selector(nudgeArtwork(_:)): return canvas.allowsPositioning && !editingText
        default: break
        }
        if menuItem.action == #selector(showSettings(_:)) { return true }
        guard !isExporting else { return false }
        if menuItem.action == #selector(copyCurrent(_:)) { menuItem.title = editingText ? L10n.tr("复制") : L10n.tr("复制当前图片"); return rendered != nil || editingText }
        if menuItem.action == #selector(pasteImage(_:)) { menuItem.title = editingText ? L10n.tr("粘贴") : L10n.tr("粘贴图片"); return true }
        if menuItem.action == #selector(removeSelected(_:)) { return selectedIndex != nil && !editingText }
        if menuItem.action == #selector(exportCurrent(_:)) { return selectedIndex != nil }
        if menuItem.action == #selector(exportAll(_:)) || menuItem.action == #selector(newBatch(_:)) { return !items.isEmpty }
        if menuItem.action == #selector(zoomIn(_:)) { return canvas.image != nil && viewing.zoomIn.isEnabled }
        if menuItem.action == #selector(zoomOut(_:)) { return canvas.image != nil && viewing.zoomOut.isEnabled }
        if menuItem.action == #selector(fitPreview(_:)) || menuItem.action == #selector(actualPixels(_:)) { return canvas.image != nil }
        return true
    }
    /// “1 / 4 · iPhone 18 Pro · 竖屏”: position in the batch, then the device being framed.
    private var headerSubtitle: String {
        guard let index = selectedIndex else {
            // Empty: what the first import will be framed as, instead of repeating the stage's prompt.
            guard items.isEmpty else { return L10n.tr("\(items.count) 张图片") }
            let output = settings.mode == .transparent ? L10n.tr("透明 PNG") : L10n.tr("带背景 · \(settings.outputFormat == .png ? "PNG" : "JPEG")")
            return deviceDescription + " · " + output
        }
        return "\(index + 1) / \(items.count) · " + deviceDescription
    }
    private var deviceDescription: String {
        switch settings.display {
        case .phone: return settings.phoneModel.title + " · " + settings.orientation.title
        case .tablet: return "iPad · " + settings.orientation.title
        case .browser: return (settings.browser == .safari ? "Safari" : "Chrome") + " · " + settings.windowRatio.rawValue
        }
    }
    /// Transparent output sits on the stage with a viewing-only contact shadow; neither enters exported pixels.
    private func applyCanvasBacking() {
        let background = settings.mode == .background
        canvas.showsTransparencyGrid = background
        canvas.showsStageShadow = !background && settings.shadow == .none
    }
    private func showEmptyGuidance() {
        emptyAction.title = L10n.tr("添加图片…"); emptyAction.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        emptyAction.setAccessibilityLabel(L10n.tr("添加图片")); emptyAction.onPress = { [weak self] in self?.addImages(nil) }
        emptyStage.showEmpty(title: L10n.tr("拖入截图"), detail: L10n.tr("PNG / JPEG · 可多选或拖入文件夹"))
        refreshEmptyFrame()
    }
    /// Renders the selected device without a screenshot. Viewing only; cached per frame silhouette.
    private func refreshEmptyFrame() {
        let key = Self.framing(settings)
        guard key != emptyFrameKey else { return }
        emptyFrameKey = key; emptyFrameRequest += 1
        let generation = emptyFrameRequest
        var framing = settings; framing.mode = .transparent; framing.transparentShadow = .none; framing.deviceOpacity = 1
        renderQueue.async { [weak self, framing] in
            let result = autoreleasepool { Result { () -> (CGImage, CGRect, CGFloat) in
                let frame = try CompositionRenderer.render(ImageInput(data: Self.blankScreen, name: "empty.png"), settings: framing, maxDimension: 1600)
                let layout = try CompositionRenderer.screenLayout(framing)
                return (frame.image, layout.rect, layout.cornerRadius)
            } }
            DispatchQueue.main.async {
                guard let self, self.emptyFrameRequest == generation else { return }
                switch result {
                case .success(let (image, screen, radius)):
                    self.emptyStage.device = .init(image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)),
                                                   screen: screen, cornerRadius: radius, display: framing.display, orientation: framing.orientation,
                                                   browserAppearance: framing.browserAppearance)
                case .failure: self.emptyStage.device = nil; self.emptyFrameKey = nil
                }
            }
        }
    }
    /// A transparent pixel: the frame keeps its own dark screen fill.
    private static let blankScreen: Data = {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return (try? FrameRenderer.pngData(context.makeImage()!)) ?? Data()
    }()
    /// Drag feedback: the empty frame lights up or declines; a filled batch is outlined for appending.
    func showDragFeedback(_ summary: DropSummary?) {
        let appending = !items.isEmpty
        guard let summary, !isExporting else {
            appendOverlay.show(nil, title: "")
            if items.isEmpty && !emptyStage.isShowingError { showEmptyGuidance() }
            return
        }
        let message = summary.message(appending: appending, device: deviceDescription)
        if appending {
            appendOverlay.show(summary, title: summary.canDrop ? message.title : message.title + " · " + message.detail)
        } else {
            emptyStage.showDrag(summary.canDrop ? .accepting : .rejecting, title: message.title, detail: message.detail)
        }
    }
    private func showError(_ message: String, title: String = L10n.tr("无法完成操作")) {
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = title; alert.informativeText = message
        if let window, window.attachedSheet == nil { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}
