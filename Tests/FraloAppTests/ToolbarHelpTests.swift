import AppKit
import XCTest
import FraloCore
import FraloLocalization
@testable import FraloApp

final class ToolbarHelpTests: XCTestCase {
    @MainActor func testNativeHeaderIconsResolveAndKeepActionsAndAccessibility() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-toolbar-help-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window)
        defer { window.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        let header = try XCTUnwrap(window.toolbar?.delegate as? WorkbenchHeader)
        header.help.resolveViews()
        XCTAssertEqual(Set(header.help.targets.map { $0.item.itemIdentifier.rawValue }), Set(["add", "sidebar", "copyCurrent", "exportCurrent", "inspector", "more"]))
        for target in header.help.targets {
            let view = try XCTUnwrap(target.view, target.item.itemIdentifier.rawValue)
            XCTAssertNil(view.toolTip, "Native popup must not duplicate fast help")
            XCTAssertEqual(view.accessibilityHelp(), target.text)
            XCTAssertTrue(view.window === window)
        }
        let more = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "more" } as? NSMenuToolbarItem)
        XCTAssertFalse(more.menu.items.isEmpty)
        let inspector = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "inspector" })
        XCTAssertEqual(inspector.action, #selector(MainWindowController.toggleInspector(_:)))
        controller.toggleInspector(nil)
        XCTAssertEqual(header.help.targets.first { $0.item === inspector }?.text, L10n.tr("显示出图设置"))
        XCTAssertEqual(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "copyCurrent" }?.action, #selector(MainWindowController.copyCurrent(_:)))
    }

    @MainActor func testDelayCancellationWarmSwitchingAndDismissalDoNotTakeFocus() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let a = NSToolbarItem(itemIdentifier: .init("a")), b = NSToolbarItem(itemIdentifier: .init("b"))
        for (index, item) in [a, b].enumerated() {
            let button = NSButton(title: item.itemIdentifier.rawValue, target: nil, action: nil)
            button.frame = NSRect(x: 100 + index * 50, y: 240, width: 44, height: 36)
            item.view = button; window.contentView!.addSubview(button)
        }
        let help = ToolbarHelp(window: window); help.preferences.reduceMotion = true
        help.configure([(a, "First"), (b, "Second")])
        defer { help.dismiss(resetWarmth: true); window.close() }
        let focus = window.firstResponder
        help.hover(a)
        try await Task.sleep(nanoseconds: 160_000_000)
        XCTAssertNil(help.visibleText, "Passing over a button must not flash help")
        help.dismiss(resetWarmth: true)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(help.visibleText, "Cancelled delay must not show late")
        help.hover(a)
        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertEqual(help.visibleText, "First")
        XCTAssertEqual(help.panel.alphaValue, 1, "Reduce Motion skips the fade")
        XCTAssertFalse(help.panel.canBecomeKey); XCTAssertFalse(help.panel.canBecomeMain)
        XCTAssertTrue(help.panel.ignoresMouseEvents)
        XCTAssertTrue(window.firstResponder === focus)
        help.hover(b)
        XCTAssertEqual(help.visibleText, "Second", "Neighbor help switches without another full delay")
        help.dismiss()
        help.hover(a)
        try await Task.sleep(nanoseconds: 90_000_000)
        XCTAssertEqual(help.visibleText, "First", "A brief gap between icons keeps the toolbar warm")
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
        XCTAssertNil(help.visibleText); XCTAssertFalse(help.panel.isVisible)
        help.hover(a)
        try await Task.sleep(nanoseconds: 90_000_000)
        XCTAssertNil(help.visibleText, "Menu dismissal resets the fast-switch session")
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        try await Task.sleep(nanoseconds: 450_000_000)
        XCTAssertNil(help.visibleText)
    }
}
