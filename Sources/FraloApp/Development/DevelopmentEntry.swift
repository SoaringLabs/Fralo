#if FRALO_DEV
import AppKit

/// This entire type and its entry points are absent from a Release compilation.
@MainActor
final class DevelopmentEntry: NSObject {
    static var labOnly: Bool { CommandLine.arguments.contains("--design-lab-only") }
    private(set) var controller: DesignLabController?
    private var productMenu: NSMenu?
    private var labMenu: NSMenu?
    private weak var mainWindow: NSWindow?
    private var materialProbe: WorkspaceMaterialProbe?
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
        if CommandLine.arguments.contains("--workspace-material-check") {
            submenu.addItem(.separator())
            let reference = submenu.addItem(withTitle: "不透明窗口参考（仅验证）", action: #selector(toggleMaterialReference(_:)), keyEquivalent: "")
            reference.target = self
            let stop = submenu.addItem(withTitle: "结束材质底板验证", action: #selector(stopMaterialProbe(_:)), keyEquivalent: "")
            stop.target = self
        }
    }
    @objc private func openLab(_ sender: Any?) { showLab() }
    func showLab() {
        if controller == nil { controller = DesignLabController() }
        controller?.showWindow(nil); controller?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func showMaterialProbeIfRequested(behind window: NSWindow?) {
        guard CommandLine.arguments.contains("--workspace-material-check"), let window else { return }
        materialProbe = WorkspaceMaterialProbe(window: window)
        window.makeKeyAndOrderFront(nil)
    }
    @objc private func toggleMaterialReference(_ sender: NSMenuItem) {
        materialProbe?.toggleOpaqueReference()
        sender.state = materialProbe?.isOpaqueReference == true ? .on : .off
    }
    @objc private func stopMaterialProbe(_ sender: NSMenuItem) { materialProbe?.stop(); materialProbe = nil }
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
