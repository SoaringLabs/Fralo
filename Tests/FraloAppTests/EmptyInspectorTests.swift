import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class EmptyInspectorTests: XCTestCase {
    @MainActor func testEmptyTransitionsRestoreOnlyAutomaticallyHiddenInspector() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-empty-inspector-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window)
        defer { window.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let list = try XCTUnwrap(root.left.body as? BatchList)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/FraloApp/Development/Fixtures/03-journal.png")
        XCTAssertTrue(root.inspectorHidden); XCTAssertTrue(root.right.isHidden)
        XCTAssertNil(defaults.object(forKey: "inspectorHidden"), "Automatic collapse must not overwrite the user's preference")
        controller.importURLs([source]); XCTAssertFalse(root.inspectorHidden)
        controller.newBatch(nil); XCTAssertTrue(list.entries.isEmpty); XCTAssertTrue(root.inspectorHidden)
        XCTAssertFalse(defaults.bool(forKey: "inspectorHidden"))
        controller.undoChange(nil); XCTAssertEqual(list.entries.count, 1); XCTAssertFalse(root.inspectorHidden)
        controller.redoChange(nil); XCTAssertTrue(list.entries.isEmpty); XCTAssertTrue(root.inspectorHidden)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let second = directory.appendingPathComponent("second.png")
        try FileManager.default.copyItem(at: source, to: second)
        controller.importURLs([source, second]); XCTAssertFalse(root.inspectorHidden)
        controller.removeSelected(nil); XCTAssertEqual(list.entries.count, 1); XCTAssertFalse(root.inspectorHidden)
        controller.removeSelected(nil); XCTAssertTrue(list.entries.isEmpty); XCTAssertTrue(root.inspectorHidden)
        XCTAssertTrue((window.firstResponder as? NSView)?.isHiddenOrHasHiddenAncestor == false)
        controller.undoChange(nil); XCTAssertFalse(root.inspectorHidden)
        controller.toggleInspector(nil); XCTAssertTrue(root.inspectorHidden)
        XCTAssertTrue(defaults.bool(forKey: "inspectorHidden"))
        controller.newBatch(nil); controller.undoChange(nil)
        XCTAssertTrue(root.inspectorHidden, "Restoring content must retain an explicitly hidden inspector")
        controller.newBatch(nil); controller.importURLs([source])
        XCTAssertTrue(root.inspectorHidden)
    }

    @MainActor func testManualEmptyInspectorOverrideAndStoredPreferenceSurviveImports() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-empty-preference-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: "inspectorHidden")
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window)
        defer { window.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/FraloApp/Development/Fixtures/03-journal.png")
        controller.importURLs([source]); XCTAssertTrue(root.inspectorHidden)
        controller.newBatch(nil); controller.toggleInspector(nil)
        XCTAssertFalse(root.inspectorHidden)
        controller.newBatch(nil)
        XCTAssertFalse(root.inspectorHidden, "Repeated empty updates must not undo an explicit Show Inspector command")
        controller.importURLs([source]); XCTAssertFalse(root.inspectorHidden)
        controller.newBatch(nil); XCTAssertTrue(root.inspectorHidden)
    }
}
