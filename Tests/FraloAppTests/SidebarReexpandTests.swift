import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class SidebarReexpandTests: XCTestCase {
    @MainActor func testListKeepsItsRowsAfterCollapseAndExpand() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "probe-\(UUID())"; let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("s.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let examples = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("examples")
        controller.importURLs(["01-today.png", "02-collection.png"].map { examples.appendingPathComponent($0) })
        try await Task.sleep(nanoseconds: 1_500_000_000)
        func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap { descendants($0) } }
        let list = try XCTUnwrap(descendants(root.left).compactMap { $0 as? BatchList }.first)
        let table = try XCTUnwrap(list.documentView as? NSTableView)
        let height = list.frame.height
        XCTAssertGreaterThan(height, 200)
        for _ in 0..<2 {
            controller.toggleSidebar(nil); try await Task.sleep(nanoseconds: 800_000_000)
            controller.toggleSidebar(nil); try await Task.sleep(nanoseconds: 800_000_000); root.layoutSubtreeIfNeeded()
            XCTAssertEqual(list.frame.height, height, accuracy: 1, "The list must regain its full height after the sidebar expands")
            XCTAssertEqual(table.rows(in: table.visibleRect).length, 2, "Both imported images stay visible")
        }
    }
}
