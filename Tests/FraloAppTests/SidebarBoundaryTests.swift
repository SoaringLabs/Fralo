import AppKit
import XCTest
@testable import FraloApp
import FraloCore

final class SidebarBoundaryTests: XCTestCase {
    @MainActor func testSidebarUsesTheSystemSidebarItem() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-sidebar-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); defer { window.close() }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        XCTAssertEqual(root.sidebarItem.behavior, .sidebar, "The system sidebar owns material, edges and titlebar band")
        XCTAssertNil(root.left.layer?.backgroundColor, "The content stays clear so the system sidebar material shows")
        XCTAssertFalse(root.stage.isDescendant(of: root.left), "The stage material belongs to the content column only")
        let toggle = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "sidebar" })
        XCTAssertTrue(toggle.isBordered)
        controller.toggleSidebar(nil)
        XCTAssertTrue(toggle.isBordered, "The toggle keeps the same glass button whether the list is shown or hidden")
    }
}
