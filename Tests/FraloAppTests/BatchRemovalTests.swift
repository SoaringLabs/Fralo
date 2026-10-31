import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class BatchRemovalTests: XCTestCase {
    @MainActor func testContextMenuDeleteAndClearKeepUndoAndOriginalFiles() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "fralo-row-removal-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FraloApp/Development/Fixtures/03-journal.png")
        let inputs = try (0..<3).map { index in
            let url = directory.appendingPathComponent("image-\(index).png")
            try FileManager.default.copyItem(at: source, to: url)
            return url
        }
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let list = try XCTUnwrap(root.left.body as? BatchList)
        controller.importURLs(inputs); list.select(1)
        let ids = list.entries.map(\.id)
        let menu = try XCTUnwrap(list.documentView?.menu)
        XCTAssertEqual(menu.items.map(\.title), ["删除", "清空所有"])
        menu.performActionForItem(at: 0)
        XCTAssertEqual(list.entries.map(\.id), [ids[0], ids[2]])
        XCTAssertEqual(list.selectedIndex, 1, "Deleting the selected middle image chooses the next image")
        controller.undoChange(nil)
        XCTAssertEqual(list.entries.map(\.id), ids)
        XCTAssertEqual(list.selectedIndex, 1)
        controller.redoChange(nil)
        XCTAssertEqual(list.entries.map(\.id), [ids[0], ids[2]])
        XCTAssertEqual(list.selectedIndex, 1)
        menu.performActionForItem(at: 0) // Selected last row falls back.
        XCTAssertEqual(list.entries.map(\.id), [ids[0]])
        XCTAssertEqual(list.selectedIndex, 0)
        list.onDelete?()
        XCTAssertTrue(list.entries.isEmpty)
        controller.undoChange(nil)
        XCTAssertEqual(list.entries.map(\.id), [ids[0]])
        XCTAssertEqual(list.selectedIndex, 0)
        menu.performActionForItem(at: 1)
        XCTAssertTrue(list.entries.isEmpty)
        controller.undoChange(nil)
        XCTAssertEqual(list.entries.map(\.id), [ids[0]])
        for input in inputs { XCTAssertTrue(FileManager.default.fileExists(atPath: input.path)) }
    }
}
