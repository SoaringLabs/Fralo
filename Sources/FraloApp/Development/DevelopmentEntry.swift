#if FRALO_DEV
import AppKit
import FraloDesignSystem

/// This entire type and its entry points are absent from a Release compilation.
@MainActor
final class DevelopmentEntry: NSObject {
    /// Deterministic content geometry for native reference-image comparisons.
    func applyPreviewGeometry(to window: NSWindow?) {
        guard CommandLine.arguments.contains("--workbench-preview"), let window,
              let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--preview-window=") }) else { return }
        let parts = argument.dropFirst("--preview-window=".count).split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts.allSatisfy(\.isFinite), parts[0] >= 1030, parts[1] >= 640 else { return }
        let visible = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        window.setContentSize(NSSize(width: min(parts[0], visible.width), height: min(parts[1], visible.height - 52)))
        if CommandLine.arguments.contains("--preview-collapsed"), let workbench = window.contentView as? WorkbenchView { workbench.collapsed = true }
        window.center()
        // Strengthen accessibility only in this preview; never change the user's OS settings.
        var preferences = DesignPreferences()
        preferences.reduceTransparency = CommandLine.arguments.contains("--preview-reduce-transparency")
        preferences.reduceMotion = CommandLine.arguments.contains("--preview-reduce-motion")
        preferences.increaseContrast = CommandLine.arguments.contains("--preview-increase-contrast")
        func apply(_ view: NSView) {
            (view as? CanvasToolbarBehavior)?.preferences = preferences
            (view as? MaterialSurface)?.preferences = preferences
            (view as? SymbolButton)?.preferences = preferences
            view.subviews.forEach(apply)
        }
        if let content = window.contentView { apply(content) }
    }
    static var labOnly: Bool { CommandLine.arguments.contains("--design-lab-only") }
    private(set) var controller: DesignLabController?
    private var productMenu: NSMenu?
    private var labMenu: NSMenu?
    private weak var mainWindow: NSWindow?
    private var panelProbe: PanelRenderingProbe?
    private var observer: NSObjectProtocol?
    func install(in menu: NSMenu, mainWindow: NSWindow? = nil) {
        self.mainWindow = mainWindow; productMenu = menu
        addDeveloperMenu(to: menu)
        let lab = NSMenu()
        let app = NSMenu(title: "Fralo")
        app.addItem(withTitle: "关于 Fralo", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(withTitle: "隐藏 Fralo", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "退出 Fralo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = app; lab.addItem(appItem)
        let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: NSSelectorFromString(selector), keyEquivalent: key)
        }
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); editItem.submenu = edit; lab.addItem(editItem)
        addDeveloperMenu(to: lab)
        let windows = NSMenu(title: "窗口")
        windows.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windows.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let windowItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: ""); windowItem.submenu = windows; lab.addItem(windowItem)
        labMenu = lab
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let window = notification.object as? NSWindow else { return }
                if window === self.controller?.window { NSApp.mainMenu = self.labMenu }
                else if window === self.mainWindow { NSApp.mainMenu = self.productMenu }
            }
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    private func addDeveloperMenu(to menu: NSMenu) {
        let submenu = NSMenu(title: "开发")
        let entry = NSMenuItem(title: "开发", action: nil, keyEquivalent: "")
        entry.submenu = submenu; menu.addItem(entry)
        let item = submenu.addItem(withTitle: "设计实验室…", action: #selector(openLab(_:)), keyEquivalent: "d")
        item.keyEquivalentModifierMask = [.command, .option, .shift]; item.target = self
    }
    @objc private func openLab(_ sender: Any?) { showLab() }
    func showLab() {
        if controller == nil { controller = DesignLabController() }
        controller?.showWindow(nil); controller?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func showRenderingProbesIfRequested(behind window: NSWindow?) {
        if CommandLine.arguments.contains("--panel-render-check"), let window {
            let report = CommandLine.arguments.first(where: { $0.hasPrefix("--panel-render-report=") }).map {
                URL(fileURLWithPath: String($0.dropFirst("--panel-render-report=".count)))
            }
            panelProbe = PanelRenderingProbe(window: window, initial: .staticGlass, report: report)
        }
    }
    func runProbeIfRequested() {
        guard let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--design-lab-probe=") }),
              let controller else { return }
        let path = String(argument.dropFirst("--design-lab-probe=".count))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            LabProbe.run(controller: controller, output: URL(fileURLWithPath: path))
        }
    }
}
#endif
