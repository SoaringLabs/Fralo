import FraloLocalization
import AppKit
import FraloCore
import FraloDesignSystem

/// App-level preferences that live in Settings. Workbench output parameters stay in the inspector.
@MainActor
protocol UpdatePreferences: AnyObject {
    /// Non-nil when this build cannot check for updates; Settings explains it instead of silently dimming controls.
    var unavailableReason: String? { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var lastUpdateCheckDate: Date? { get }
    var canCheckForUpdates: Bool { get }
    func checkForUpdates(_ sender: Any?)
}

/// System Settings–style window: sidebar categories, inset grouped rows. Changes apply and save immediately.
@MainActor
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    enum Pane: String, CaseIterable {
        case appearance, updates
        var title: String { self == .appearance ? L10n.tr("外观") : L10n.tr("更新") }
        var symbol: String { self == .appearance ? "circle.lefthalf.filled" : "arrow.triangle.2.circlepath" }
        /// Badge tiles follow System Settings: a dark tile for appearance, neutral gray for software update.
        var badge: NSColor {
            self == .appearance ? NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 0.23, alpha: 1) : NSColor(white: 0.11, alpha: 1) } : .systemGray
        }
    }
    static let paneKey = "settingsPane"

    private(set) var selection: AppAppearance
    private(set) var pane: Pane
    var onAppearanceChange: ((AppAppearance) -> Void)?
    weak var updates: UpdatePreferences?
    let sidebar = NSTableView()
    let searchField = NSSearchField()
    private let noResults = NSTextField(labelWithString: "")
    /// Categories the sidebar lists: all of them, or those matching the search.
    private(set) var visiblePanes = Pane.allCases
    private(set) var searchResult = SettingsSearch.Result(panes: Pane.allCases)
    private(set) var picker: AppearanceThumbnailPicker?
    private(set) var automaticSwitch: NSSwitch?
    private(set) var checkButton: NSButton?
    private(set) var languagePopup: NSPopUpButton?
    let language: LanguagePreference
    /// Applies the effective language immediately; false when Fralo is busy and the choice must be reverted.
    var onLanguageChange: ((String) -> Bool)?
    private let detail = NSViewController()
    private let preferences: UserDefaults
    private var keyObserver: NSObjectProtocol?

    init(selection: AppAppearance, updates: UpdatePreferences?, preferences: UserDefaults = .standard,
         language: LanguagePreference = LanguagePreference(), onAppearanceChange: @escaping (AppAppearance) -> Void) {
        self.selection = selection; self.updates = updates; self.preferences = preferences; self.language = language
        self.onAppearanceChange = onAppearanceChange
        pane = preferences.string(forKey: Self.paneKey).flatMap(Pane.init(rawValue:)) ?? .appearance
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = L10n.tr("Fralo 设置"); window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false; window.identifier = .init("FraloSettings")
        window.contentMinSize = NSSize(width: 640, height: 400)
        super.init(window: window)
        window.onFind = { [weak self] in self?.focusSearch() }
        let split = NSSplitViewController()
        let side = NSViewController(); side.view = makeSidebar()
        let sideItem = NSSplitViewItem(sidebarWithViewController: side)
        sideItem.minimumThickness = 200; sideItem.maximumThickness = 240; sideItem.canCollapse = false
        detail.view = SettingsContentSurface()
        split.addSplitViewItem(sideItem); split.addSplitViewItem(NSSplitViewItem(viewController: detail))
        window.contentViewController = split
        window.setContentSize(NSSize(width: 760, height: 520))
        window.setFrameAutosaveName("FraloSettingsWindow")
        sidebar.selectRowIndexes([Pane.allCases.firstIndex(of: pane)!], byExtendingSelection: false)
        show(pane)
        if !window.setFrameUsingName("FraloSettingsWindow") { window.center() }
        // Sparkle can finish a check while Settings is behind its window; refresh when people come back.
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.pane == .updates { self?.show(.updates) } }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) } }

    func set(_ value: AppAppearance) { selection = value; picker?.select(value) }
    func present() {
        showWindow(nil); window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(sidebar)
        NSApp.activate(ignoringOtherApps: true)
    }

    func select(_ pane: Pane) {
        if !visiblePanes.contains(pane) { clearSearch() }
        sidebar.selectRowIndexes([visiblePanes.firstIndex(of: pane)!], byExtendingSelection: false)
        show(pane)
    }

    // MARK: Search

    func focusSearch() { window?.makeFirstResponder(searchField) }
    func clearSearch() { searchField.stringValue = ""; updateSearch() }
    @objc private func searchChanged(_ sender: NSSearchField) { updateSearch() }

    /// Filters the sidebar to matching categories, keeps the current one when it still matches,
    /// and highlights matching rows in the visible pane.
    func updateSearch() {
        let query = searchField.stringValue
        let result = SettingsSearch.search(query)
        searchResult = result; visiblePanes = result.panes
        sidebar.reloadData()
        noResults.isHidden = !result.isEmpty
        if let index = visiblePanes.firstIndex(of: pane) {
            sidebar.selectRowIndexes([index], byExtendingSelection: false)
            applyHighlights()
        } else if let first = visiblePanes.first {
            sidebar.selectRowIndexes([0], byExtendingSelection: false)
            if pane != first { show(first) }
        } else {
            applyHighlights()
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // VoiceOver hears how the filter changed without leaving the search field.
        let announcement = result.isEmpty ? L10n.tr("无结果") : L10n.tr("结果：\(result.panes.count)")
        NSAccessibility.post(element: searchField, notification: .announcementRequested,
                             userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    private func applyHighlights() {
        let searching = !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        func visit(_ view: NSView) {
            if let row = view as? SettingsRowView { row.isHighlighted = searching && row.searchID.map(searchResult.rows.contains) == true }
            view.subviews.forEach(visit)
        }
        visit(detail.view)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === searchField else { return false }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.moveDown(_:)):
            // Return or ↓ moves into the results, like System Settings; nothing to move to without results.
            guard !visiblePanes.isEmpty else { return true }
            if sidebar.selectedRow < 0 { sidebar.selectRowIndexes([0], byExtendingSelection: false) }
            window?.makeFirstResponder(sidebar)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if searchField.stringValue.isEmpty { return false }
            clearSearch(); return true
        default:
            return false
        }
    }

    private func makeSidebar() -> NSView {
        let column = NSTableColumn(identifier: .init("pane")); sidebar.addTableColumn(column)
        sidebar.headerView = nil; sidebar.style = .sourceList; sidebar.rowHeight = 30
        sidebar.dataSource = self; sidebar.delegate = self
        sidebar.setAccessibilityLabel(L10n.tr("设置分类"))
        let scroll = NSScrollView(); scroll.documentView = sidebar; scroll.drawsBackground = false
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 84, left: 0, bottom: 12, right: 0)
        searchField.delegate = self; searchField.target = self; searchField.action = #selector(searchChanged(_:))
        searchField.sendsSearchStringImmediately = true; searchField.sendsWholeSearchString = false
        localizeSearch()
        noResults.font = .systemFont(ofSize: 13); noResults.textColor = .secondaryLabelColor
        noResults.alignment = .center; noResults.isHidden = true
        let container = NSView()
        for view in [scroll, searchField, noResults] { view.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(view) }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor), scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            // Below the window controls, as in System Settings.
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 46),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            noResults.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 24),
            noResults.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            noResults.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12)
        ])
        return container
    }
    private func localizeSearch() {
        searchField.placeholderString = L10n.tr("搜索")
        searchField.setAccessibilityLabel(L10n.tr("搜索设置"))
        noResults.stringValue = L10n.tr("无结果")
    }

    private func show(_ pane: Pane) {
        guard let window else { return }
        self.pane = pane; preferences.set(pane.rawValue, forKey: Self.paneKey)
        window.subtitle = ""
        let root = NSView()
        let title = FraloStyle.text(pane.title); title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.setAccessibilityRole(.staticText); title.setAccessibilityLabel(pane.title)
        let separator = NSBox(); separator.boxType = .separator
        picker = nil; automaticSwitch = nil; checkButton = nil; languagePopup = nil
        let groups: [NSView]
        switch pane {
        case .appearance: groups = appearanceGroups()
        case .updates: groups = updateGroups()
        }
        let column = FraloStyle.stack(groups, spacing: 22, fillWidth: true)
        let scroll = NSScrollView(); ScrollContent.install(column, in: scroll, inset: 24)
        for view in [title, separator, scroll] { view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view) }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),
            title.centerYAnchor.constraint(equalTo: root.topAnchor, constant: 26),
            separator.topAnchor.constraint(equalTo: root.topAnchor, constant: 52),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor), separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: -4), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        // The split item owns the detail view; swap its contents rather than the view itself.
        detail.view.subviews.forEach { $0.removeFromSuperview() }
        root.translatesAutoresizingMaskIntoConstraints = false; detail.view.addSubview(root)
        NSLayoutConstraint.activate([root.topAnchor.constraint(equalTo: detail.view.topAnchor), root.bottomAnchor.constraint(equalTo: detail.view.bottomAnchor),
                                     root.leadingAnchor.constraint(equalTo: detail.view.leadingAnchor), root.trailingAnchor.constraint(equalTo: detail.view.trailingAnchor)])
        applyHighlights()
        window.recalculateKeyViewLoop()
    }

    private func appearanceGroups() -> [NSView] {
        let picker = AppearanceThumbnailPicker(selection: selection) { [weak self] value in
            guard let self else { return }
            self.selection = value; self.onAppearanceChange?(value)
        }
        self.picker = picker
        return [SettingsGroup(L10n.tr("界面"), rows: [
            SettingsGroup.row(L10n.tr("外观"), detail: L10n.tr("选择浅色、深色，或随系统自动切换。"), control: picker, searchID: SettingsSearch.Row.appearance)
        ], footer: L10n.tr("更改会自动保存，并即时应用到 Fralo 的所有窗口。")), languageGroup()]
    }

    private func languageGroup() -> NSView {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItem(withTitle: L10n.tr("跟随系统"))
        popup.menu?.addItem(.separator())
        for code in L10n.supportedLanguages {
            popup.addItem(withTitle: LanguagePreference.nativeName(code)); popup.lastItem?.representedObject = code
        }
        let current = language.choice
        popup.selectItem(at: current.flatMap { code in popup.itemArray.firstIndex { $0.representedObject as? String == code } } ?? 0)
        popup.target = self; popup.action = #selector(changeLanguage(_:))
        languagePopup = popup
        let rows = [SettingsGroup.row(L10n.tr("界面语言"), detail: nil, control: popup, searchID: SettingsSearch.Row.language)]
        return SettingsGroup(L10n.tr("语言"), rows: rows)
    }
    @objc private func changeLanguage(_ sender: NSPopUpButton) {
        let previous = language.choice
        language.set(sender.selectedItem?.representedObject as? String)
        guard onLanguageChange?(language.effectiveLanguage) ?? true else {
            // Busy (exporting or a dialog is open): keep the language that is actually showing.
            language.set(previous); show(.appearance)
            let alert = NSAlert(); alert.messageText = L10n.tr("暂时无法切换语言")
            alert.informativeText = L10n.tr("请在导出完成并关闭对话框后再切换语言。")
            alert.addButton(withTitle: L10n.tr("好"))
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return
        }
    }

    /// Rebuilds every string after a language change, keeping the current pane, selection and focus target.
    func reloadLocalizedContent() {
        window?.title = L10n.tr("Fralo 设置")
        sidebar.setAccessibilityLabel(L10n.tr("设置分类"))
        localizeSearch()
        show(pane)
        updateSearch()
        if pane == .appearance, let popup = languagePopup { window?.makeFirstResponder(popup) }
    }

    private func updateGroups() -> [NSView] {
        let reason = updates == nil ? L10n.tr("请打开完整的 Fralo.app 后检查更新。直接运行构建目录中的可执行文件不支持安装更新。") : updates?.unavailableReason
        let available = reason == nil
        let automatic = NSSwitch()
        automatic.state = available && updates?.automaticallyChecksForUpdates == true ? .on : .off
        automatic.isEnabled = available; automatic.target = self; automatic.action = #selector(toggleAutomatic(_:))
        automaticSwitch = automatic
        let check = NSButton(title: L10n.tr("立即检查…"), target: self, action: #selector(checkNow(_:)))
        check.bezelStyle = .push; check.isEnabled = available && updates?.canCheckForUpdates == true
        checkButton = check
        var automaticRows = [SettingsGroup.row(L10n.tr("每天自动检查更新"), detail: L10n.tr("发现新版本时会先询问你，不会自动下载或安装。"),
                                               control: automatic, enabled: available, searchID: SettingsSearch.Row.automatic)]
        if let reason {
            let icon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: L10n.tr("提示"))!)
            icon.symbolConfiguration = .init(paletteColors: [.black, .systemYellow])
            automaticRows.insert(SettingsGroup.row(L10n.tr("此构建无法检查更新"), detail: reason, leading: icon), at: 0)
        }
        let version = FraloStyle.text("\(FraloInfo.version) (\(FraloInfo.build))", secondary: true)
        version.isSelectable = true
        return [
            SettingsGroup(L10n.tr("自动更新"), rows: automaticRows),
            SettingsGroup(L10n.tr("版本"), rows: [
                SettingsGroup.row(L10n.tr("当前版本"), detail: nil, control: version, searchID: SettingsSearch.Row.version),
                SettingsGroup.row(L10n.tr("上次检查"), detail: Self.lastCheckText(available ? updates?.lastUpdateCheckDate : nil), control: check,
                                  searchID: SettingsSearch.Row.lastCheck)
            ])
        ]
    }

    static func lastCheckText(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return L10n.tr("从未检查") }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.language)
        formatter.dateStyle = .medium; formatter.timeStyle = .short; formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }

    @objc private func toggleAutomatic(_ sender: NSSwitch) { updates?.automaticallyChecksForUpdates = sender.state == .on }
    @objc private func checkNow(_ sender: Any?) { updates?.checkForUpdates(sender) }

    func numberOfRows(in tableView: NSTableView) -> Int { visiblePanes.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let pane = visiblePanes[row]
        let cell = NSTableCellView()
        let icon = NSImageView(image: Self.badge(pane))
        let label = FraloStyle.text(pane.title)
        // Not assigned to cell.imageView: the source list would dim it in inactive windows, unlike System Settings' colored tiles.
        cell.textField = label
        let stack = FraloStyle.stack([icon, label], axis: .horizontal, spacing: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                                     stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
                                     stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                                     icon.widthAnchor.constraint(equalToConstant: 20), icon.heightAnchor.constraint(equalToConstant: 20)])
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard visiblePanes.indices.contains(sidebar.selectedRow) else { return }
        let next = visiblePanes[sidebar.selectedRow]
        if next != pane || detail.view.subviews.isEmpty { show(next) }
    }

    /// A rounded colored tile with a white glyph; drawn per appearance so the dark tile lifts in Dark Mode.
    static func badge(_ pane: Pane) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { rect in
            pane.badge.setFill(); NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold).applying(.init(paletteColors: [.white]))
            if let glyph = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let size = glyph.size
                glyph.draw(in: NSRect(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2, width: size.width, height: size.height))
            }
            return true
        }
        image.accessibilityDescription = pane.title
        return image
    }
}

/// Settings window that answers ⌘F with its search field, even though the main menu targets the workbench.
@MainActor
final class SettingsWindow: NSWindow {
    var onFind: (() -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "f" {
            onFind?(); return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
