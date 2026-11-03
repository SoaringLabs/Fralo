import FraloLocalization
import AppKit
import FraloCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var mainController: MainWindowController?
    private var updateController: UpdateController?
    private var pendingURLs: [URL] = []
    #if FRALO_DEV
    private let development = DevelopmentEntry()
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = makeMainController()
        mainController = controller
        #if FRALO_DEV
        if !DevelopmentEntry.labOnly && !CommandLine.arguments.contains("--workbench-preview") { updateController = UpdateController(mainController: controller) }
        #else
        updateController = UpdateController(mainController: controller)
        #endif
        controller.updatePreferences = updateController
        controller.onLanguageChange = { [weak self] in self?.applyLanguage($0) ?? false }
        installMenus(controller)
        #if FRALO_DEV
        if DevelopmentEntry.labOnly {
            development.showLab()
            development.runProbeIfRequested()
            return
        }
        #endif
        #if FRALO_DEV
        development.applyPreviewGeometry(to: controller.window)
        if CommandLine.arguments.contains("--workbench-preview"), let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--preview-appearance=") }) {
            controller.selectAppearance(String(arg.dropFirst("--preview-appearance=".count)), persist: false)
        }
        #endif
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        let paths = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        controller.importURLs(pendingURLs + paths.map { URL(fileURLWithPath: $0) })
        pendingURLs.removeAll()
        #if FRALO_DEV
        if CommandLine.arguments.contains("--design-lab") { development.showLab() }
        development.showRenderingProbesIfRequested(behind: controller.window)
        development.showSettingsPreviewIfRequested(controller)
        #endif
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        if let mainController { mainController.importURLs(urls) } else { pendingURLs += urls }
        sender.reply(toOpenOrPrint: .success)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if mainController?.isExporting == true {
            let alert = NSAlert(); alert.messageText = L10n.tr("正在导出图片")
            alert.informativeText = L10n.tr("退出将停止剩余导出，已经完成的文件会保留。")
            alert.addButton(withTitle: L10n.tr("继续导出")); alert.addButton(withTitle: L10n.tr("停止并退出"))
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
            mainController?.requestQuitAfterExport()
            return .terminateLater
        }
        return .terminateNow
    }

    /// Tests install a workbench without running the launch sequence.
    func adoptForTesting(_ controller: MainWindowController) {
        mainController = controller
        controller.onLanguageChange = { [weak self] in self?.applyLanguage($0) ?? false }
        installMenus(controller)
    }

    private func makeMainController() -> MainWindowController {
        #if FRALO_DEV
        return MainWindowController(inspectorUsesNativeGlass: CommandLine.arguments.contains("--panel-render-check"))
        #else
        return MainWindowController()
        #endif
    }

    /// Switches Fralo's own interface immediately: the workbench is rebuilt in the new language and takes over the
    /// batch, selection and Settings window, then the menu bar is rebuilt. Refused while exporting or showing a sheet,
    /// so no running operation or open dialog is torn down. Returns whether the language is now in effect.
    @discardableResult
    func applyLanguage(_ language: String) -> Bool {
        guard let old = mainController else { L10n.setLanguage(language); return true }
        guard L10n.resolveLanguage([language]) != L10n.language else { return true }
        guard !old.isExporting, old.window?.attachedSheet == nil else { return false }
        // Only one window may own the autosave name; hand it to the replacement.
        old.window?.setFrameAutosaveName("")
        L10n.setLanguage(language)
        let replacement = makeMainController()
        replacement.adopt(from: old)
        replacement.onLanguageChange = { [weak self] in self?.applyLanguage($0) ?? false }
        mainController = replacement
        updateController?.bind(to: replacement)
        installMenus(replacement)
        if let frame = old.window?.frame, old.window?.isVisible == true {
            replacement.window?.setFrame(frame, display: false)
            // Behind whatever is in front (normally Settings), in the old window's place, before the old one goes.
            if let number = old.window?.windowNumber { replacement.window?.order(.above, relativeTo: number) }
        }
        old.window?.close()
        replacement.settingsController?.reloadLocalizedContent()
        return true
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainController?.showWindow(nil); return true
    }

    func installMenus(_ controller: MainWindowController) {
        let bar = NSMenu()
        let app = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = app; bar.addItem(appItem)
        let about = app.addItem(withTitle: L10n.tr("关于 Fralo"), action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self
        let settings = app.addItem(withTitle: L10n.tr("设置…"), action: #selector(MainWindowController.showSettings(_:)), keyEquivalent: ",")
        settings.target = controller; settings.keyEquivalentModifierMask = .command
        app.addItem(.separator())
        let check = app.addItem(withTitle: L10n.tr("检查更新…"), action: #selector(UpdateController.checkForUpdates(_:)), keyEquivalent: "")
        check.target = updateController
        app.addItem(.separator())
        app.addItem(withTitle: L10n.tr("隐藏 Fralo"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: L10n.tr("退出 Fralo"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = NSMenu(title: L10n.tr("文件")); let fileItem = NSMenuItem(title: L10n.tr("文件"), action: nil, keyEquivalent: ""); fileItem.submenu = file; bar.addItem(fileItem)
        func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", modifiers: NSEvent.ModifierFlags = .command) {
            let value = NSMenuItem(title: title, action: action, keyEquivalent: key)
            value.target = controller; value.keyEquivalentModifierMask = modifiers; menu.addItem(value)
        }
        item(file, L10n.tr("添加图片…"), #selector(MainWindowController.addImages(_:)), "o")
        item(file, L10n.tr("从文件夹添加图片…"), #selector(MainWindowController.addFolder(_:)), "o", modifiers: [.command, .shift])
        item(file, L10n.tr("新批次"), #selector(MainWindowController.newBatch(_:)), "n")
        file.addItem(.separator())
        item(file, L10n.tr("导出全部…"), #selector(MainWindowController.exportAll(_:)), "e", modifiers: [.command, .shift])
        item(file, L10n.tr("导出当前图片…"), #selector(MainWindowController.exportCurrent(_:)), "e")
        file.addItem(.separator())
        file.addItem(withTitle: L10n.tr("关闭窗口"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let edit = NSMenu(title: L10n.tr("编辑")); let editItem = NSMenuItem(title: L10n.tr("编辑"), action: nil, keyEquivalent: ""); editItem.submenu = edit; bar.addItem(editItem)
        item(edit, L10n.tr("撤销"), #selector(MainWindowController.undoChange(_:)), "z")
        item(edit, L10n.tr("重做"), #selector(MainWindowController.redoChange(_:)), "z", modifiers: [.command, .shift])
        edit.addItem(.separator())
        edit.addItem(withTitle: L10n.tr("剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        item(edit, L10n.tr("复制当前图片"), #selector(MainWindowController.copyCurrent(_:)), "c")
        // Let the focused text editor handle standard paste before the workbench.
        edit.addItem(withTitle: L10n.tr("粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L10n.tr("全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        item(edit, L10n.tr("删除"), #selector(MainWindowController.removeSelected(_:)), "\u{8}", modifiers: [])
        item(edit, L10n.tr("清空所有"), #selector(MainWindowController.newBatch(_:)))

        let view = NSMenu(title: L10n.tr("显示")); let viewItem = NSMenuItem(title: L10n.tr("显示"), action: nil, keyEquivalent: ""); viewItem.submenu = view; bar.addItem(viewItem)
        item(view, L10n.tr("显示/隐藏侧边栏"), #selector(MainWindowController.toggleSidebar(_:)), "s", modifiers: [.command, .control])
        item(view, L10n.tr("显示/隐藏出图设置"), #selector(MainWindowController.toggleInspector(_:)), "i", modifiers: [.command, .option])
        item(view, L10n.tr("成品预览"), #selector(MainWindowController.togglePreview(_:)), "p", modifiers: [.command, .option])
        view.addItem(.separator())
        item(view, L10n.tr("上一张图片"), #selector(MainWindowController.previousImage(_:)), "[")
        item(view, L10n.tr("下一张图片"), #selector(MainWindowController.nextImage(_:)), "]")
        let position = NSMenuItem(title: L10n.tr("微调位置"), action: nil, keyEquivalent: "")
        let positionMenu = NSMenu(title: L10n.tr("微调位置")); position.submenu = positionMenu; view.addItem(position)
        for (title, key, delta) in [(L10n.tr("向左移动 1 px"), "\u{F702}", NSPoint(x: -1, y: 0)), (L10n.tr("向右移动 1 px"), "\u{F703}", NSPoint(x: 1, y: 0)),
                                    (L10n.tr("向上移动 1 px"), "\u{F700}", NSPoint(x: 0, y: -1)), (L10n.tr("向下移动 1 px"), "\u{F701}", NSPoint(x: 0, y: 1))] {
            item(positionMenu, title, #selector(MainWindowController.nudgeArtwork(_:)), key, modifiers: .option)
            positionMenu.items.last?.representedObject = NSValue(point: delta)
        }
        view.addItem(.separator())
        item(view, L10n.tr("适应窗口"), #selector(MainWindowController.fitPreview(_:)), "0")
        item(view, L10n.tr("实际像素"), #selector(MainWindowController.actualPixels(_:)), "1")
        item(view, L10n.tr("放大"), #selector(MainWindowController.zoomIn(_:)), "+")
        // ⌘= reaches “放大” without Shift on layouts where + is shifted.
        item(view, L10n.tr("放大"), #selector(MainWindowController.zoomIn(_:)), "=")
        view.items.last?.isHidden = true; view.items.last?.allowsKeyEquivalentWhenHidden = true
        item(view, L10n.tr("缩小"), #selector(MainWindowController.zoomOut(_:)), "-")

        let window = NSMenu(title: L10n.tr("窗口")); let windowItem = NSMenuItem(title: L10n.tr("窗口"), action: nil, keyEquivalent: ""); windowItem.submenu = window; bar.addItem(windowItem)
        window.addItem(withTitle: L10n.tr("最小化"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: L10n.tr("缩放"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        #if FRALO_DEV
        development.install(in: bar, mainWindow: controller.window)
        #endif
        NSApp.mainMenu = bar; NSApp.windowsMenu = window
    }

    @objc private func showAbout(_ sender: Any?) {
        let credits = NSMutableAttributedString(string: L10n.tr("开发者：\(FraloInfo.developer)\n维护者：Ethan (@Peek-A-Booo)\nMIT 开源许可\n"))
        let organization = NSAttributedString(string: "Soaring Labs on GitHub", attributes: [.link: URL(string: FraloInfo.homepage)!])
        credits.append(organization)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Fralo",
            .applicationVersion: FraloInfo.version,
            .version: FraloInfo.build,
            .credits: credits
        ])
    }
}
