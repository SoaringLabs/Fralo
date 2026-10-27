import AppKit
import UniformTypeIdentifiers
import FraloCore
import FraloDesignSystem

@MainActor
final class MainWindowController: NSWindowController, NSToolbarDelegate, NSMenuItemValidation {
    struct Item { let input: ImageInput; var thumbnail: NSImage?; var error: String? }
    private var items: [Item] = []
    private var settings: CompositionSettings
    private let store: CompositionStore
    private var inspectorUI: CompositionInspector!
    private let preferences: UserDefaults
    private let pasteboard: NSPasteboard
    private(set) var appearanceChoice = AppAppearance.system
    private(set) var settingsController: AppearanceSettingsWindowController?
    private var workbench: WorkbenchView!
    private let center = NSViewController()
    private let list = BatchList()
    private let viewing = ViewToolbar()
    private let batchScope = FraloStyle.text("样式应用于全部 0 张", role: .caption, secondary: true)
    private let exportAction = ExportAction(count: 0)
    private let batchCount = FraloStyle.text("图片 · 0", role: .heading)
    private let documentTitle = FraloStyle.text("Fralo", role: .body)
    private let filename = FraloStyle.text("", role: .heading), position = FraloStyle.text("", role: .caption, secondary: true)
    private let previewScroll = PreviewScrollView()
    private let canvas = CanvasSurface(frame: .zero)
    private let empty = NSView()
    private let emptyAction = ActionButton("添加图片", role: .primary, symbol: "plus")
    private let emptyMessage = label("拖入截图，开始套框", size: 22, weight: .semibold)
    private let emptyDetail = label("PNG / JPEG · 支持批量导入", secondary: true)
    private let previewSpinner = NSProgressIndicator()
    private let footer = NSView()
    private var fitMenu: NSPopUpButton { viewing.zoom }
    private let dimensions = FraloStyle.text("尚无成品", role: .detail, secondary: true)
    private let copyButton = ActionButton("", role: .quiet, size: .compact, symbol: "doc.on.doc", label: "复制当前图片")
    private var rendered: RenderedComposition?
    private var renderedID: String?
    private var previewRequest = 0, thumbnailRequest = 0
    private var renderWork: DispatchWorkItem?
    private let renderQueue = DispatchQueue(label: "app.fralo.preview", qos: .userInitiated)
    private let thumbnailQueue = DispatchQueue(label: "app.fralo.thumbnails", qos: .utility)
    private var zoom: CGFloat? = nil
    private var backgroundImageSize: CGSize?
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

    init(store: SettingsStore = SettingsStore(), preferences: UserDefaults = .standard, pasteboard: NSPasteboard = .general, restoreWindow: Bool = true) {
        self.store = CompositionStore(legacy: store); self.preferences = preferences; self.pasteboard = pasteboard
        do { settings = try self.store.load() } catch { settings = CompositionSettings(); initialWarning = error.localizedDescription }
        let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 1000)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: min(1400, area.width - 80), height: min(950, area.height - 80)), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        selectAppearance(preferences.string(forKey: "workbenchAppearance") ?? "system", persist: false)
        window.title = "Fralo"; window.titleVisibility = .hidden; window.toolbarStyle = .unifiedCompact
        window.titlebarAppearsTransparent = true; window.titlebarSeparatorStyle = .none
        // Let the behind-window workspace material composite with the desktop.
        // Keep window alpha at 1 so artwork and controls remain fully opaque.
        window.isOpaque = false; window.backgroundColor = .clear
        window.contentMinSize = NSSize(width: 1030, height: 640)
        buildInterface()
        if restoreWindow { window.setFrameAutosaveName("FraloMainWindow") }; window.center()
        if let warning = initialWarning { DispatchQueue.main.async { [weak self] in self?.showError(warning) } }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildInterface() {
        center.view = DropContainer()
        (center.view as? DropContainer)?.onDrop = { [weak self] in self?.importURLs($0) }
        let collapse = ActionButton("", size: .compact, symbol: "chevron.down", label: "收起图片列表") { [weak self] in self?.toggleSidebar(nil) }
        let heading = FraloStyle.stack([batchCount, NSView(), collapse], axis: .horizontal, spacing: 4)
        let add = ActionButton("添加图片", symbol: "plus.circle") { [weak self] in self?.addImages(nil) }
        let shortcut = FraloStyle.text("↑ ↓  切换图片", role: .caption, secondary: true); shortcut.alignment = .center
        let leftFooter = FraloStyle.stack([add, shortcut], spacing: 14, fillWidth: true)
        let left = FloatingPanel(header: heading, body: list, footer: leftFooter)
        list.onSelection = { [weak self] _ in self?.selectionChanged() }
        list.onDelete = { [weak self] in self?.removeSelected(nil) }
        let menu = NSMenu(); menu.addItem(actionItem("移除当前图片", #selector(removeSelected(_:))))
        menu.addItem(actionItem("清空批次", #selector(newBatch(_:)))); list.documentView?.menu = menu
        exportAction.onExportAll = { [weak self] in self?.exportAll(nil) }
        exportAction.onExportCurrent = { [weak self] in self?.exportCurrent(nil) }
        let inspectorBody = buildInspector()
        dimensions.alignment = .center
        let right = FloatingPanel(header: FraloStyle.stack([FraloStyle.text("检查器", role: .heading), inspectorUI.mode, batchScope], spacing: 8, fillWidth: true),
                                  body: inspectorBody,
                                  footer: FraloStyle.stack([FraloStyle.divider(), dimensions, exportAction], spacing: 12, fillWidth: true), bodySpacing: 18)
        workbench = WorkbenchView(left: left, right: right, content: center.view)
        workbench.collapsed = preferences.bool(forKey: "sidebarCollapsed")
        workbench.rail.expand.onPress = { [weak self] in self?.toggleSidebar(nil) }
        workbench.rail.add.onPress = { [weak self] in self?.addImages(nil) }
        workbench.rail.previous.onPress = { [weak self] in self?.moveSelection(-1) }
        workbench.rail.next.onPress = { [weak self] in self?.moveSelection(1) }
        workbench.onGeometryChange = { [weak self] in self?.layoutPreview() }
        window?.contentView = workbench
        buildPreview()
        let toolbar = NSToolbar(identifier: "FraloToolbar")
        toolbar.delegate = self; toolbar.displayMode = .iconOnly; toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = [.init("documentTitle")]
        window?.toolbar = toolbar
        updateActions(); window?.recalculateKeyViewLoop()
    }

    private func buildPreview() {
        previewScroll.documentView = canvas; previewScroll.hasVerticalScroller = true; previewScroll.hasHorizontalScroller = true
        previewScroll.autohidesScrollers = true; previewScroll.scrollerStyle = .overlay; previewScroll.drawsBackground = false
        previewScroll.translatesAutoresizingMaskIntoConstraints = false
        previewScroll.onResize = { [weak self] in self?.layoutPreview() }
        center.view.addSubview(previewScroll)
        footer.translatesAutoresizingMaskIntoConstraints = false; center.view.addSubview(footer)
        fitMenu.removeAllItems(); fitMenu.addItems(withTitles: ["适应窗口", "25%", "50%", "100%", "200%"])
        fitMenu.target = self; fitMenu.action = #selector(zoomMenuChanged(_:))
        viewing.composition.removeAllItems(); viewing.composition.addItems(withTitles: CanvasRatio.allCases.map(\.rawValue))
        viewing.composition.onChange = { [weak self] index in self?.inspectorUI.chooseCanvas(CanvasRatio.allCases[index]) }
        viewing.preview.onPress = { [weak self] in self?.togglePreview() }
        viewing.translatesAutoresizingMaskIntoConstraints = false; footer.addSubview(viewing)
        canvas.onPrevious = { [weak self] in self?.moveSelection(-1) }
        canvas.onNext = { [weak self] in self?.moveSelection(1) }
        canvas.onEscape = { [weak self] in if self?.workbench.previewing == true { self?.togglePreview() } }
        NSLayoutConstraint.activate([
            previewScroll.topAnchor.constraint(equalTo: center.view.topAnchor, constant: 16), previewScroll.leadingAnchor.constraint(equalTo: center.view.leadingAnchor), previewScroll.trailingAnchor.constraint(equalTo: center.view.trailingAnchor), previewScroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: center.view.leadingAnchor), footer.trailingAnchor.constraint(equalTo: center.view.trailingAnchor), footer.bottomAnchor.constraint(equalTo: center.view.bottomAnchor), footer.heightAnchor.constraint(equalToConstant: 76),
            viewing.centerXAnchor.constraint(equalTo: footer.centerXAnchor), viewing.centerYAnchor.constraint(equalTo: footer.centerYAnchor), viewing.widthAnchor.constraint(lessThanOrEqualTo: footer.widthAnchor), viewing.heightAnchor.constraint(equalToConstant: 48)
        ])
        empty.translatesAutoresizingMaskIntoConstraints = false; center.view.addSubview(empty)
        let icon = NSImageView(image: NSImage(systemSymbolName: "photo.badge.plus", accessibilityDescription: nil)!)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = .tertiaryLabelColor
        icon.widthAnchor.constraint(equalToConstant: 52).isActive = true; icon.heightAnchor.constraint(equalToConstant: 52).isActive = true
        let add = emptyAction; add.onPress = { [weak self] in self?.addImages(nil) }
        emptyDetail.lineBreakMode = .byWordWrapping; emptyDetail.maximumNumberOfLines = 3
        emptyDetail.alignment = .center
        emptyDetail.widthAnchor.constraint(lessThanOrEqualToConstant: 340).isActive = true
        let emptyContent = stack([icon, emptyMessage, emptyDetail, add, label("或按 ⌘V 粘贴图片", size: 12, secondary: true)], spacing: 16)
        emptyContent.alignment = .centerX; emptyContent.translatesAutoresizingMaskIntoConstraints = false; empty.addSubview(emptyContent)
        NSLayoutConstraint.activate([
            empty.leadingAnchor.constraint(equalTo: center.view.leadingAnchor), empty.trailingAnchor.constraint(equalTo: center.view.trailingAnchor), empty.topAnchor.constraint(equalTo: center.view.topAnchor), empty.bottomAnchor.constraint(equalTo: center.view.bottomAnchor),
            emptyContent.centerXAnchor.constraint(equalTo: empty.centerXAnchor), emptyContent.centerYAnchor.constraint(equalTo: empty.centerYAnchor)
        ])
        previewSpinner.style = .spinning; previewSpinner.controlSize = .small; previewSpinner.isDisplayedWhenStopped = false
        previewSpinner.translatesAutoresizingMaskIntoConstraints = false; center.view.addSubview(previewSpinner)
        NSLayoutConstraint.activate([previewSpinner.trailingAnchor.constraint(equalTo: center.view.trailingAnchor, constant: -22), previewSpinner.topAnchor.constraint(equalTo: center.view.topAnchor, constant: 18)])
    }

    private func buildInspector() -> NSView {
        inspectorUI = CompositionInspector(settings: settings)
        inspectorUI.onChange = { [weak self] value in
            guard let self, !self.isExporting else { return }
            self.settings = value
            do { try self.store.save(value) } catch { self.showError(error.localizedDescription) }
            self.requestPreview()
        }
        canvas.onDrag = { [weak self] delta in self?.dragArtwork(delta) }
        canvas.onDragEnd = { [weak self] in
            guard let self else { return }
            self.canvas.centerGuideX = false; self.canvas.centerGuideY = false; self.dragDevicePosition = nil
            guard self.artworkDragChanged else { return }; self.artworkDragChanged = false
            do { try self.store.save(self.settings) } catch { self.showError(error.localizedDescription) }
        }
        return inspectorUI
    }
    private func dragArtwork(_ delta: CGPoint) {
        guard settings.mode == .background, !isExporting else { return }
        artworkDragChanged = true
        if inspectorUI.dragBackground {
            if let backgroundImageSize { CompositionRenderer.panBackground(&settings, delta: delta, imageSize: backgroundImageSize) }
        } else {
            let previous = dragDevicePosition ?? CGPoint(x: settings.deviceX, y: settings.deviceY)
            let next = CGPoint(x: min(1, max(-1, previous.x + delta.x)), y: min(1, max(-1, previous.y + delta.y)))
            dragDevicePosition = next; settings.deviceX = next.x; settings.deviceY = next.y
            if abs(settings.deviceX) < 0.012 { settings.deviceX = 0 }
            if abs(settings.deviceY) < 0.012 { settings.deviceY = 0 }
            canvas.centerGuideX = settings.deviceX == 0; canvas.centerGuideY = settings.deviceY == 0
        }
        inspectorUI.set(settings)
        requestPreview()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("brand"), .flexibleSpace, .init("documentTitle"), .flexibleSpace, .init("copy"), .init("settings"), .init("more")]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier.rawValue {
        case "brand":
            let brand = FraloStyle.text("Fralo", role: .heading); item.view = brand; item.label = "Fralo"
        case "documentTitle":
            documentTitle.font = .systemFont(ofSize: 14, weight: .medium)
            item.view = documentTitle; item.label = "当前图片"
        case "more":
            let menu = NSMenu(); let title = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            title.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil); menu.addItem(title)
            menu.addItem(actionItem("添加图片…", #selector(addImages(_:))))
            menu.addItem(actionItem("导入文件夹…", #selector(addFolder(_:))))
            menu.addItem(actionItem("粘贴图片", #selector(pasteImage(_:))))
            menu.addItem(actionItem("设置…", #selector(showSettings(_:))))
            let appearance = NSMenuItem(title: "外观", action: nil, keyEquivalent: ""); appearance.submenu = appearanceMenu(); menu.addItem(appearance)
            menu.addItem(.separator()); menu.addItem(actionItem("移除当前图片", #selector(removeSelected(_:))))
            let button = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 24, height: 28), pullsDown: true)
            button.menu = menu; button.isBordered = false; button.imagePosition = .imageOnly
            (button.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
            button.setAccessibilityLabel("更多图片操作"); item.view = button; item.label = "更多图片操作"
        case "sidebar":
            let button = IconButton("sidebar.left", label: "显示或隐藏图片列表") { [weak self] in self?.toggleSidebar(nil) }
            item.view = button; item.label = "图片列表"
        case "add":
            let menu = NSMenu(); menu.addItem(actionItem("添加图片", #selector(addImages(_:))))
            menu.addItem(actionItem("选择图片…", #selector(addImages(_:))))
            menu.addItem(actionItem("导入文件夹…", #selector(addFolder(_:))))
            menu.addItem(actionItem("粘贴图片", #selector(pasteImage(_:))))
            let button = NSPopUpButton(frame: .zero, pullsDown: true); button.menu = menu; button.bezelStyle = .texturedRounded
            button.sizeToFit(); item.view = button; item.label = "添加图片"
        case "copy":
            copyButton.onPress = { [weak self] in self?.copyCurrent(nil) }
            item.view = copyButton; item.label = "复制当前图片"
        case "settings":
            item.view = IconButton("gearshape", label: "设置") { [weak self] in self?.showSettings(nil) }
            item.label = "设置"
        default: return nil
        }
        return item
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; return item
    }
    func selectAppearance(_ value: String, persist: Bool = true) {
        guard let choice = AppAppearance(rawValue: value) else { return }
        appearanceChoice = choice
        window?.appearance = choice.appearance
        settingsController?.set(choice)
        if persist { preferences.set(value, forKey: "workbenchAppearance") }
    }
    func appearanceMenu() -> NSMenu {
        let menu = NSMenu(title: "外观")
        for choice in AppAppearance.allCases {
            let item = actionItem(choice.title, #selector(changeAppearance(_:))); item.representedObject = choice.rawValue
            item.state = appearanceChoice == choice ? .on : .off; menu.addItem(item)
        }
        return menu
    }
    @objc private func changeAppearance(_ sender: NSMenuItem) { if let value = sender.representedObject as? String { selectAppearance(value) } }
    @objc func showSettings(_ sender: Any?) {
        if settingsController == nil {
            settingsController = AppearanceSettingsWindowController(selection: appearanceChoice) { [weak self] value in
                self?.selectAppearance(value.rawValue)
            }
        }
        settingsController?.set(appearanceChoice); settingsController?.present()
    }
    @objc func toggleSidebar(_ sender: Any?) {
        workbench.setCollapsed(!workbench.collapsed, animated: true)
        preferences.set(workbench.collapsed, forKey: "sidebarCollapsed")
    }
    private func togglePreview() {
        if !workbench.previewing { previewRestoreFocus = window?.firstResponder }
        workbench.previewing.toggle()
        viewing.preview.title = workbench.previewing ? "返回编辑 · Esc" : "成品预览"
        window?.makeFirstResponder(workbench.previewing ? canvas : previewRestoreFocus ?? canvas); layoutPreview()
    }
    private func moveSelection(_ delta: Int) { list.moveSelection(by: delta) }
    private func selectionChanged() { zoom = nil; fitMenu.selectItem(at: 0); updateActions(); requestPreview() }
    private func refreshList() {
        list.update(items.map { BatchEntry(id: $0.input.id, title: $0.input.name, detail: $0.error == nil ? "" : "无法读取", image: $0.thumbnail, failed: $0.error != nil) })
        workbench.rail.update(index: selectedIndex, count: items.count)
    }
    @objc private func batchMenu(_ sender: NSButton) {
        let menu = NSMenu(); menu.addItem(actionItem("移除当前图片", #selector(removeSelected(_:))))
        menu.addItem(actionItem("清空批次", #selector(newBatch(_:))))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 2), in: sender)
    }
    @objc func addImages(_ sender: Any?) {
        guard !isExporting else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg]; panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false; panel.message = "选择要套框的截图"
        panel.beginSheetModal(for: window!) { [weak self] response in if response == .OK { self?.importURLs(panel.urls) } }
    }
    @objc func addFolder(_ sender: Any?) {
        guard !isExporting else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "导入文件夹当前层的 PNG / JPEG 图片"
        panel.beginSheetModal(for: window!) { [weak self] response in if response == .OK { self?.importURLs(panel.urls) } }
    }
    func importURLs(_ urls: [URL]) {
        guard !urls.isEmpty, !isExporting else { return }
        do {
            let inputs = try InputCollector.collect(urls)
            let existing = Set(items.map { $0.input.id })
            let accepted = inputs.filter { !existing.contains($0.id) }
            guard !accepted.isEmpty else { return }
            items += accepted.map { Item(input: $0) }
            refreshList(); updateActions()
            if selectedIndex == nil { list.select(0) }
            scheduleThumbnails(); requestPreview()
        } catch { showError(error.localizedDescription) }
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
        guard let data else { showError("剪贴板中没有可导入的图片。"); return }
        pastedCount += 1
        items.append(Item(input: ImageInput(data: data, name: String(format: "粘贴图片-%03d.png", pastedCount))))
        refreshList(); list.select(items.count - 1)
        updateActions(); scheduleThumbnails(); requestPreview()
    }
    @objc func removeSelected(_ sender: Any?) {
        guard !isExporting, let selectedIndex else { return }
        items.remove(at: selectedIndex); refreshList()
        if !items.isEmpty { list.select(min(selectedIndex, items.count - 1)) }
        updateActions(); requestPreview()
    }
    @objc func newBatch(_ sender: Any?) {
        guard !isExporting else { return }
        items.removeAll(); previewRequest += 1; thumbnailRequest += 1; rendered = nil; renderedID = nil
        refreshList(); updateActions(); requestPreview()
    }

    private func scheduleThumbnails() {
        thumbnailRequest += 1
        let generation = thumbnailRequest, inputs = items.map(\.input)
        for input in inputs {
            thumbnailQueue.async { [weak self] in
                let result: Result<CGImage, Error> = autoreleasepool { Result { try input.decode(maxDimension: 180) } }
                DispatchQueue.main.async {
                    guard let self, self.thumbnailRequest == generation, let index = self.items.firstIndex(where: { $0.input.id == input.id }) else { return }
                    switch result {
                    case .success(let image): self.items[index].thumbnail = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)); self.items[index].error = nil
                    case .failure(let error): self.items[index].error = error.localizedDescription
                    }
                    self.refreshList()
                }
            }
        }
    }
    private func requestPreview() {
        previewRequest += 1; renderWork?.cancel(); rendered = nil; renderedID = nil
        guard let index = selectedIndex else {
            inspectorUI.setInput(nil)
            canvas.image = nil; empty.isHidden = false; emptyMessage.stringValue = "拖入截图，开始套框"
            emptyAction.title = "添加图片"; emptyAction.onPress = { [weak self] in self?.addImages(nil) }
            emptyDetail.stringValue = "PNG / JPEG · 支持批量导入"
            previewScroll.isHidden = true; footer.isHidden = true; filename.stringValue = ""; position.stringValue = ""
            window?.title = "Fralo"; documentTitle.stringValue = "Fralo"; dimensions.stringValue = "尚无成品"; inspectorUI.sourceInfo.stringValue = "尚未选择图片"; inspectorUI.outputInfo.stringValue = "—"; previewSpinner.stopAnimation(nil); updateActions(); return
        }
        let input = items[index].input, snapshot = settings, generation = previewRequest
        inspectorUI.setInput(input)
        window?.title = input.name; filename.stringValue = input.name; position.stringValue = "\(index + 1) / \(items.count)"
        documentTitle.stringValue = input.name
        empty.isHidden = true; previewScroll.isHidden = false; footer.isHidden = false
        previewSpinner.startAnimation(nil); updateActions()
        let work = DispatchWorkItem { [weak self] in
            let result = autoreleasepool { Result { () -> (RenderedComposition, CGImage, CGSize, CGSize?) in
                let backdrop = try CompositionRenderer.backgroundData(snapshot)
                let frame = try CompositionRenderer.render(input, settings: snapshot, backgroundData: backdrop)
                let display = snapshot.format == .jpeg ? try ImageInput(data: CompositionRenderer.data(frame.image, settings: snapshot), name: "preview.jpg").decode() : frame.image
                return (frame, display, try input.dimensions(), try backdrop.map { try ImageInput(data: $0, name: "background.png").dimensions() })
            } }
            DispatchQueue.main.async {
                guard let self, self.previewRequest == generation else { return }
                self.previewSpinner.stopAnimation(nil)
                switch result {
                case .success(let (frame, display, sourceSize, backgroundSize)):
                    self.backgroundImageSize = backgroundSize
                    if let row = self.items.firstIndex(where: { $0.input.id == input.id }), self.items[row].error != nil { self.items[row].error = nil; self.refreshList() }
                    self.inspectorUI.sourceInfo.stringValue = "\(input.name)\n\(Int(sourceSize.width)) × \(Int(sourceSize.height))"
                    self.inspectorUI.outputInfo.stringValue = "\(snapshot.format == .png ? "PNG" : "JPEG") · \(Int(frame.pixelSize.width)) × \(Int(frame.pixelSize.height))"
                    self.rendered = frame; self.renderedID = input.id; self.canvas.image = NSImage(cgImage: display, size: frame.pixelSize)
                    self.canvas.showsElevation = snapshot.mode == .background
                    self.canvas.showsTransparencyGrid = snapshot.mode == .background
                    self.dimensions.stringValue = "\(snapshot.format == .png ? "PNG" : "JPEG") · \(Int(frame.pixelSize.width)) × \(Int(frame.pixelSize.height))"
                    self.empty.isHidden = true; self.layoutPreview()
                case .failure(let error):
                    self.canvas.image = nil; self.empty.isHidden = false; self.emptyMessage.stringValue = "无法生成成品"
                    self.emptyAction.title = "重试预览"; self.emptyAction.onPress = { [weak self] in self?.scheduleThumbnails(); self?.requestPreview() }
                    self.emptyDetail.stringValue = error.localizedDescription
                    self.previewScroll.isHidden = true; self.footer.isHidden = true; self.dimensions.stringValue = "无法确定"
                    if let i = self.items.firstIndex(where: { $0.input.id == input.id }) { self.items[i].error = error.localizedDescription; self.refreshList() }
                }
                self.updateActions()
            }
        }
        renderWork = work; renderQueue.async(execute: work)
    }

    private func layoutPreview() {
        guard !layingOutPreview, let rendered else { return }
        layingOutPreview = true; defer { layingOutPreview = false }
        let available = previewScroll.contentView.bounds.size
        guard available.width > 0, available.height > 0 else { return }
        let pixels = rendered.pixelSize, backing = window?.backingScaleFactor ?? 2
        let factor = zoom.map { $0 / backing } ?? min(max(10, available.width - 8) / pixels.width, max(10, available.height - 32) / pixels.height)
        let size = NSSize(width: pixels.width * factor, height: pixels.height * factor)
        let document = NSSize(width: max(available.width, size.width + 8), height: max(available.height, size.height + 32))
        canvas.setFrameSize(document); canvas.zoom = factor
        viewing.dimensions.stringValue = "\(Int(pixels.width)) × \(Int(pixels.height))"
        viewing.showsComposition = settings.mode == .background
        viewing.composition.selectItem(at: CanvasRatio.allCases.firstIndex(of: settings.canvas) ?? 1)
        viewing.composition.displayTitle = "\(settings.canvas.rawValue) · \(Int(pixels.width)) × \(Int(pixels.height))"
    }
    @objc func fitPreview(_ sender: Any?) { zoom = nil; fitMenu.selectItem(at: 0); layoutPreview() }
    @objc func actualPixels(_ sender: Any?) { zoom = 1; fitMenu.selectItem(at: 3); layoutPreview() }
    @objc private func zoomIn(_ sender: Any?) { setZoom(by: 1.25) }
    @objc private func zoomOut(_ sender: Any?) { setZoom(by: 0.8) }
    private func setZoom(by multiplier: CGFloat) {
        let current = zoom ?? ((canvas.imageRect.width / max(1, rendered?.pixelSize.width ?? 1)) * (window?.backingScaleFactor ?? 2))
        zoom = min(8, max(0.05, current * multiplier)); layoutPreview()
    }
    @objc private func zoomMenuChanged(_ sender: Any?) {
        zoom = [nil, CGFloat(0.25), CGFloat(0.5), CGFloat(1), CGFloat(2)][fitMenu.indexOfSelectedItem]; layoutPreview()
    }

    @objc func copyCurrent(_ sender: Any?) {
        if sender is NSMenuItem, let editor = window?.firstResponder as? NSTextView, editor.isEditable { editor.copy(sender); return }
        guard let rendered, let index = selectedIndex, renderedID == items[index].input.id else { return }
        do {
            let data = try FrameRenderer.pngData(rendered.image)
            pasteboard.clearContents(); pasteboard.setData(data, forType: .png)
        } catch { showError(error.localizedDescription) }
    }
    @objc func exportAll(_ sender: Any?) {
        guard !items.isEmpty, !isExporting else { return }
        window?.makeFirstResponder(nil)
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "导出"; panel.message = "选择输出文件夹"
        let overwrite = NSButton(checkboxWithTitle: "覆盖已有同名输出文件", target: nil, action: nil); panel.accessoryView = overwrite
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let directory = panel.url, let self else { return }
            self.startExport(self.items.map(\.input), directory: directory, overwrite: overwrite.state == .on)
        }
    }
    @objc func exportCurrent(_ sender: Any?) {
        guard let index = selectedIndex, !isExporting else { return }
        window?.makeFirstResponder(nil)
        let input = items[index].input
        let panel = NSSavePanel(); panel.allowedContentTypes = [settings.format == .png ? .png : .jpeg]; panel.canCreateDirectories = true
        panel.nameFieldStringValue = BatchExporter.outputNames(for: [input], format: settings.format)[0]
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
        let count = label("已完成 0 / \(inputs.count)")
        let current = label("正在准备…", size: 12, secondary: true); current.lineBreakMode = .byTruncatingMiddle
        let bar = NSProgressIndicator(); bar.isIndeterminate = false; bar.minValue = 0; bar.maxValue = Double(inputs.count); bar.style = .bar
        bar.widthAnchor.constraint(equalToConstant: 414).isActive = true
        let cancel = ActionButton("取消")
        cancel.target = self; cancel.action = #selector(cancelExportAction(_:)); cancel.keyEquivalent = "\u{1b}"
        let notice = label("", size: 12, secondary: true); updateNotice = notice
        let content = stack([label("正在导出图片", size: 16, weight: .semibold), count, bar, current, notice, cancel], spacing: 12)
        content.alignment = .centerX; content.translatesAutoresizingMaskIntoConstraints = false; panel.contentView?.addSubview(content)
        NSLayoutConstraint.activate([content.centerXAnchor.constraint(equalTo: panel.contentView!.centerXAnchor), content.centerYAnchor.constraint(equalTo: panel.contentView!.centerYAnchor)])
        progressPanel = panel; window?.beginSheet(panel)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try BatchExporter.run(inputs: inputs, settings: RenderSettings(), directory: directory, overwrite: overwrite, cancellation: token, outputNames: names, composition: snapshot, backgroundData: backdrop) { progress in
                    DispatchQueue.main.async { count.stringValue = "已完成 \(progress.completed) / \(progress.total)"; current.stringValue = "正在处理：\(progress.currentName)"; bar.doubleValue = Double(progress.completed) }
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
    @objc private func cancelExportAction(_ sender: NSButton) { cancelExport(); sender.isEnabled = false; sender.title = "正在停止…" }
    func cancelExport() { cancellation?.cancel() }
    func requestQuitAfterExport() { quitAfterExport = true; cancelExport() }
    func showPendingUpdate() { updateNotice?.stringValue = "导出结束后将安装更新并重启 Fralo" }
    func clearPendingUpdate() { updateNotice?.stringValue = "" }
    private func showReport(_ report: ExportReport, directory: URL) {
        let alert = NSAlert(); alert.messageText = report.cancelled ? "导出已取消" : "导出完成"
        alert.informativeText = "成功 \(report.succeeded) 张 · 跳过 \(report.skipped) 张 · 失败 \(report.failed) 张\n未处理 \(report.unprocessed) 张 · 用时 \(String(format: "%.2f", report.durationSeconds)) 秒"
        alert.addButton(withTitle: "完成"); alert.addButton(withTitle: "打开输出文件夹")
        let issues = report.entries.filter { $0.status != .success }
        if !issues.isEmpty {
            let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 430, height: 140)); text.isEditable = false; text.isSelectable = true; text.font = .systemFont(ofSize: 12)
            text.string = issues.map { "\($0.input)：\($0.reason ?? $0.status.rawValue)" }.joined(separator: "\n")
            let scroll = NSScrollView(frame: text.frame); scroll.documentView = text; ScrollContent.configure(scroll); alert.accessoryView = scroll
        }
        alert.beginSheetModal(for: window!) { response in if response == .alertSecondButtonReturn { NSWorkspace.shared.open(directory) } }
    }
    private func updateActions() {
        inspectorUI?.setEditingEnabled(!isExporting)
        batchCount.stringValue = "图片 · \(items.count)"
        batchScope.stringValue = "样式应用于全部 \(items.count) 张"
        exportAction.count = items.count; exportAction.isEnabled = !isExporting
        workbench.rail.update(index: selectedIndex, count: items.count)
        copyButton.isEnabled = rendered != nil && !isExporting
        if items.isEmpty { empty.isHidden = false; footer.isHidden = true; previewScroll.isHidden = true }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(showSettings(_:)) { return true }
        if menuItem.action == #selector(changeAppearance(_:)) { menuItem.state = (menuItem.representedObject as? String) == appearanceChoice.rawValue ? .on : .off; return true }
        guard !isExporting else { return false }
        if menuItem.action == #selector(copyCurrent(_:)) { return rendered != nil || window?.firstResponder is NSTextView }
        if menuItem.action == #selector(exportCurrent(_:)) || menuItem.action == #selector(removeSelected(_:)) { return selectedIndex != nil }
        if menuItem.action == #selector(exportAll(_:)) || menuItem.action == #selector(newBatch(_:)) { return !items.isEmpty }
        return true
    }
    private func showError(_ message: String) {
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = "Fralo"; alert.informativeText = message
        if let window, window.attachedSheet == nil { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}
