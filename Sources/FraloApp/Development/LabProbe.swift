#if FRALO_DEV
import AppKit
import FraloDesignSystem
import CryptoKit

/// In-process acceptance probe. View-cache snapshots prove layout, not desktop compositing.
@MainActor
enum LabProbe {
    static func run(controller: DesignLabController, output: URL) {
        var checks: [String: Bool] = [:]
        var snapshots: [String] = []
        do {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            checks["developer_menu"] = NSApp.mainMenu?.items.contains { $0.title == "开发" } == true
            checks["lab_menu_has_no_product_import_or_export"] = !allMenuTitles(NSApp.mainMenu).contains("导出全部…") && !allMenuTitles(NSApp.mainMenu).contains("添加图片…")
            checks["fixtures_available"] = !controller.state.samples.missingFixtures
            checks["five_live_pages"] = controller.tabs.numberOfTabViewItems == 5
            for (index, page) in DesignLabState.Page.allCases.enumerated() {
                controller.selectPage(index)
                let name = "\(page.rawValue.lowercased())-light.png"
                try snapshot(controller.window!.contentView!, to: output.deletingLastPathComponent().appendingPathComponent(name))
                snapshots.append(name)
                if page == .components, let view = controller.tabs.selectedTabViewItem?.view {
                    let buttons = descendants(view).compactMap { $0 as? ActionButton }
                    checks["shared_action_controls"] = buttons.count >= 9
                    checks["soft_accessibility_roles"] = !buttons.isEmpty && buttons.allSatisfy { $0.accessibilityRole() == .button }
                    if let primary = buttons.first(where: { $0.role == .primary && $0.isEnabled }) {
                        let size = primary.intrinsicContentSize
                        primary.isBusy = true
                        checks["soft_busy_preserves_width"] = primary.intrinsicContentSize == size && !primary.isEnabled
                        primary.isBusy = false
                        for pressed in [false, true] {
                            primary.highlight(pressed)
                            let file = pressed ? "soft-button-pressed.png" : "soft-button-default.png"
                            try snapshot(primary, to: output.deletingLastPathComponent().appendingPathComponent(file))
                            snapshots.append(file)
                        }
                        primary.highlight(false)
                    }
                }
            }
            controller.selectPage(4)
            let scene = controller.scenarioView!
            controller.state.scenario.count = 100
            scene.list.update(controller.state.samples.entries(count: 100)); scene.refreshInspector(); scene.render()
            scene.layoutSubtreeIfNeeded()
            checks["large_batch_fills_panel"] = scene.list.bounds.height > scene.leftPanel.bounds.height - 160
            scene.list.select(99); scene.layoutSubtreeIfNeeded()
            if let table = scene.list.documentView as? NSTableView {
                checks["large_batch_end_reachable"] = scene.list.selectedIndex == 99 && table.visibleRect.intersects(table.rect(ofRow: 99))
            }
            try snapshot(controller.window!.contentView!, to: output.deletingLastPathComponent().appendingPathComponent("large-batch-scroll.png"))
            snapshots.append("large-batch-scroll.png")
            controller.state.scenario.count = 3
            scene.list.update(controller.state.samples.entries(count: 3)); scene.refreshInspector(); scene.render()
            let beforeSize = scene.canvas.image?.size
            scene.toggleSidebar(); scene.layoutSubtreeIfNeeded()
            checks["collapse_preserves_artwork_size"] = beforeSize == scene.canvas.image?.size
            checks["collapsed_panel_alignment"] = abs(scene.sidebarContainer.frame.minY - scene.rightPanel.frame.minY) < 1 && abs(scene.sidebarContainer.frame.maxY - scene.rightPanel.frame.maxY) < 1
            scene.togglePreview(); scene.layoutSubtreeIfNeeded()
            checks["preview_hides_tools"] = scene.sidebarContainer.isHidden && scene.rightPanel.isHidden
            checks["preview_focus"] = controller.window?.firstResponder === scene.canvas
            scene.canvas.keyDown(with: key(53, in: controller.window!))
            checks["escape_restores_editing"] = !controller.state.scenario.preview && !scene.sidebarContainer.isHidden
            controller.state.scenario.count = 3
            scene.list.select(0)
            scene.canvas.keyDown(with: key(125, in: controller.window!))
            checks["canvas_arrow_changes_selection"] = scene.list.selectedIndex == 1
            let picker = ValuePicker(["A", "B"], label: "键盘测试")
            picker.keyDown(with: key(124, in: controller.window!))
            checks["parameter_arrows_stay_in_control"] = picker.selectedIndex == 1 && scene.list.selectedIndex == 1
            controller.window?.recalculateKeyViewLoop()
            controller.window?.makeFirstResponder(scene.modePicker)
            scene.modePicker.keyDown(with: key(48, in: controller.window!))
            checks["tab_leaves_live_parameter"] = controller.window?.firstResponder !== scene.modePicker
            scene.modePicker.choose(0); scene.layoutSubtreeIfNeeded()
            checks["transparent_mode_has_image"] = scene.canvas.image != nil && controller.state.scenario.transparent
            for device in 0...2 {
                scene.devicePicker.choose(device); scene.layoutSubtreeIfNeeded()
                let name = "scenario-device-\(device).png"
                try snapshot(controller.window!.contentView!, to: output.deletingLastPathComponent().appendingPathComponent(name)); snapshots.append(name)
            }
            var preferences = DesignPreferences(); preferences.reduceMotion = true; preferences.reduceTransparency = true; preferences.increaseContrast = true
            controller.state.preferences = preferences; controller.state.appearance = 2; controller.rebuild(); controller.selectPage(2)
            checks["opaque_accessibility_fallback"] = controller.materialView.workspace.isUsingOpaqueFallback
            checks["reduced_motion"] = FraloMotion.duration(.selection, preferences: preferences) == 0
            try snapshot(controller.window!.contentView!, to: output.deletingLastPathComponent().appendingPathComponent("materials-dark-accessibility.png"))
            snapshots.append("materials-dark-accessibility.png")
            controller.state.preferences = .init(); controller.state.appearance = 1; controller.rebuild()
            controller.window?.setContentSize(NSSize(width: 1040, height: 680)); controller.selectPage(4)
            let compact = controller.scenarioView!
            compact.layoutSubtreeIfNeeded()
            checks["minimum_window_has_canvas"] = compact.canvas.bounds.width > 120 && compact.canvas.bounds.height > 120
            checks["minimum_window_panels_align"] = abs(compact.sidebarContainer.frame.height - compact.rightPanel.frame.height) < 1
            try snapshot(controller.window!.contentView!, to: output.deletingLastPathComponent().appendingPathComponent("minimum-window.png"))
            snapshots.append("minimum-window.png")
            let executable = Bundle.main.executableURL!
            let digest = SHA256.hash(data: try Data(contentsOf: executable)).map { String(format: "%02x", $0) }.joined()
            let report: [String: Any] = ["checks": checks, "passed": checks.values.allSatisfy { $0 }, "snapshots": snapshots, "binary_sha256": digest, "executable_path": executable.path,
                                       "pid": ProcessInfo.processInfo.processIdentifier, "window_number": controller.window?.windowNumber ?? 0,
                                       "limits": ["View-cache screenshots do not prove desktop compositing or VoiceOver speech.", "iPad/browser use explicit layout fixtures; product renderer is out of scope.", "OS accessibility settings are read; per-window previews only strengthen them."]]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        } catch {
            let report: [String: Any] = ["passed": false, "error": error.localizedDescription, "checks": checks]
            try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        }
        if !CommandLine.arguments.contains("--design-lab-keep-open") { NSApp.terminate(nil) }
        else {
            controller.state.preferences = .init(); controller.state.appearance = 0; controller.state.scenario = .init()
            controller.window?.setContentSize(NSSize(width: 1380, height: 900)); controller.rebuild(); controller.selectPage(1)
        }
    }
    private static func key(_ code: UInt16, in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                         context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }
    static func snapshot(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: .atomic)
    }
    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
    private static func allMenuTitles(_ menu: NSMenu?) -> [String] {
        menu?.items.flatMap { [$0.title] + allMenuTitles($0.submenu) } ?? []
    }
}
#endif
