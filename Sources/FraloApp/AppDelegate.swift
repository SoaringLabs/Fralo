import AppKit
import FraloCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainController: MainWindowController?
    private var updateController: UpdateController?
    private var pendingURLs: [URL] = []
    #if FRALO_DEV
    private let development = DevelopmentEntry()
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if FRALO_DEV
        let controller = MainWindowController(inspectorUsesNativeGlass: CommandLine.arguments.contains("--panel-render-check"))
        #else
        let controller = MainWindowController()
        #endif
        mainController = controller
        #if FRALO_DEV
        if !DevelopmentEntry.labOnly && !CommandLine.arguments.contains("--workbench-preview") { updateController = UpdateController(mainController: controller) }
        #else
        updateController = UpdateController(mainController: controller)
        #endif
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
            let alert = NSAlert(); alert.messageText = "正在导出图片"
            alert.informativeText = "退出将停止剩余导出，已经完成的文件会保留。"
            alert.addButton(withTitle: "继续导出"); alert.addButton(withTitle: "停止并退出")
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
            mainController?.requestQuitAfterExport()
            return .terminateLater
        }
        return .terminateNow
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainController?.showWindow(nil); return true
    }

    private func installMenus(_ controller: MainWindowController) {
        let bar = NSMenu()
        let app = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = app; bar.addItem(appItem)
        let about = app.addItem(withTitle: "关于 Fralo", action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self
        let settings = app.addItem(withTitle: "设置…", action: #selector(MainWindowController.showSettings(_:)), keyEquivalent: ",")
        settings.target = controller; settings.keyEquivalentModifierMask = .command
        app.addItem(.separator())
        let check = app.addItem(withTitle: "检查更新…", action: #selector(UpdateController.checkForUpdates(_:)), keyEquivalent: "")
        check.target = updateController
        let automatic = app.addItem(withTitle: "自动检查更新（每天）", action: #selector(UpdateController.toggleAutomaticChecks(_:)), keyEquivalent: "")
        automatic.target = updateController
        app.addItem(.separator())
        app.addItem(withTitle: "隐藏 Fralo", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: "退出 Fralo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = NSMenu(title: "文件"); let fileItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: ""); fileItem.submenu = file; bar.addItem(fileItem)
        func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "", modifiers: NSEvent.ModifierFlags = .command) {
            let value = NSMenuItem(title: title, action: action, keyEquivalent: key)
            value.target = controller; value.keyEquivalentModifierMask = modifiers; menu.addItem(value)
        }
        item(file, "添加图片…", #selector(MainWindowController.addImages(_:)), "o")
        item(file, "导入文件夹…", #selector(MainWindowController.addFolder(_:)), "o", modifiers: [.command, .shift])
        item(file, "新批次", #selector(MainWindowController.newBatch(_:)), "n")
        file.addItem(.separator())
        item(file, "导出全部…", #selector(MainWindowController.exportAll(_:)), "e", modifiers: [.command, .shift])
        item(file, "导出当前图片…", #selector(MainWindowController.exportCurrent(_:)), "e")
        file.addItem(.separator())
        file.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let edit = NSMenu(title: "编辑"); let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); editItem.submenu = edit; bar.addItem(editItem)
        item(edit, "撤销", #selector(MainWindowController.undoChange(_:)), "z")
        item(edit, "重做", #selector(MainWindowController.redoChange(_:)), "z", modifiers: [.command, .shift])
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        item(edit, "复制当前图片", #selector(MainWindowController.copyCurrent(_:)), "c")
        item(edit, "粘贴图片", #selector(MainWindowController.pasteImage(_:)), "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        item(edit, "删除", #selector(MainWindowController.removeSelected(_:)), "\u{8}", modifiers: [])
        item(edit, "清空所有", #selector(MainWindowController.newBatch(_:)))

        let view = NSMenu(title: "显示"); let viewItem = NSMenuItem(title: "显示", action: nil, keyEquivalent: ""); viewItem.submenu = view; bar.addItem(viewItem)
        item(view, "显示/隐藏侧边栏", #selector(MainWindowController.toggleSidebar(_:)), "s", modifiers: [.command, .control])
        item(view, "显示/隐藏出图设置", #selector(MainWindowController.toggleInspector(_:)), "i", modifiers: [.command, .option])
        item(view, "成品预览", #selector(MainWindowController.togglePreview(_:)), "p", modifiers: [.command, .option])
        view.addItem(.separator())
        item(view, "上一张图片", #selector(MainWindowController.previousImage(_:)), "[")
        item(view, "下一张图片", #selector(MainWindowController.nextImage(_:)), "]")
        let position = NSMenuItem(title: "微调位置", action: nil, keyEquivalent: "")
        let positionMenu = NSMenu(title: "微调位置"); position.submenu = positionMenu; view.addItem(position)
        for (title, key, delta) in [("向左移动 1 px", "\u{F702}", NSPoint(x: -1, y: 0)), ("向右移动 1 px", "\u{F703}", NSPoint(x: 1, y: 0)),
                                    ("向上移动 1 px", "\u{F700}", NSPoint(x: 0, y: -1)), ("向下移动 1 px", "\u{F701}", NSPoint(x: 0, y: 1))] {
            item(positionMenu, title, #selector(MainWindowController.nudgeArtwork(_:)), key, modifiers: .option)
            positionMenu.items.last?.representedObject = NSValue(point: delta)
        }
        view.addItem(.separator())
        item(view, "适应窗口", #selector(MainWindowController.fitPreview(_:)), "0")
        item(view, "实际像素", #selector(MainWindowController.actualPixels(_:)), "1")
        item(view, "放大", #selector(MainWindowController.zoomIn(_:)), "+")
        // ⌘= reaches “放大” without Shift on layouts where + is shifted.
        item(view, "放大", #selector(MainWindowController.zoomIn(_:)), "=")
        view.items.last?.isHidden = true; view.items.last?.allowsKeyEquivalentWhenHidden = true
        item(view, "缩小", #selector(MainWindowController.zoomOut(_:)), "-")
        item(view, "显示透明区域", #selector(MainWindowController.toggleTransparencyGrid(_:)))
        let appearance = NSMenuItem(title: "外观", action: nil, keyEquivalent: ""); appearance.submenu = controller.appearanceMenu(); view.addItem(appearance)

        let window = NSMenu(title: "窗口"); let windowItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: ""); windowItem.submenu = window; bar.addItem(windowItem)
        window.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        #if FRALO_DEV
        development.install(in: bar, mainWindow: controller.window)
        #endif
        NSApp.mainMenu = bar; NSApp.windowsMenu = window
    }

    @objc private func showAbout(_ sender: Any?) {
        let credits = NSMutableAttributedString(string: "开发者：\(FraloInfo.developer)\n维护者：Ethan (@Peek-A-Booo)\nMIT 开源许可\n")
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
