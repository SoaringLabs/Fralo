import AppKit
import XCTest
import FraloCore
@testable import FraloApp

final class PasteRoutingTests: XCTestCase {
    @MainActor private func withWorkbench(
        _ body: @MainActor (MainWindowController, NSMenuItem, NSPasteboard) async throws -> Void
    ) async throws {
        _ = NSApplication.shared
        let previousMenu = NSApp.mainMenu
        let previousWindowsMenu = NSApp.windowsMenu
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-paste-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let board = NSPasteboard.withUniqueName()
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/FraloApp/Development/Fixtures/03-journal.png")
        board.setData(try Data(contentsOf: fixture), forType: .png)
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")),
            preferences: defaults, pasteboard: board, restoreWindow: false)
        let delegate = AppDelegate()
        delegate.adoptForTesting(controller)
        defer {
            controller.settingsController?.window?.close(); controller.window?.close()
            NSApp.mainMenu = previousMenu; NSApp.windowsMenu = previousWindowsMenu
            board.releaseGlobally(); defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let paste = try XCTUnwrap(NSApp.mainMenu?.items.compactMap(\.submenu)
            .flatMap(\.items).first { $0.keyEquivalent == "v" })
        try await body(controller, paste, board)
    }

    @MainActor private func pasteText(_ text: String, using item: NSMenuItem, focusedWindow: NSWindow) throws {
        // Restore every clipboard representation after exercising native NSTextView paste.
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        defer {
            board.clearContents()
            board.writeObjects(saved.map { values in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            })
        }
        board.clearContents(); board.setString(text, forType: .string)
        let action = try XCTUnwrap(item.action)
        // XCTest does not run NSApplication's event loop/key-window bookkeeping.
        // Start the real responder chain at the supplied window's first responder.
        let handled = item.target.map { NSApp.sendAction(action, to: $0, from: item) }
            ?? focusedWindow.firstResponder?.tryToPerform(action, with: item) ?? false
        XCTAssertTrue(handled)
    }

    @MainActor func testSettingsSearchReceivesPasteInsteadOfImportingAnImage() async throws {
        try await withWorkbench { controller, item, _ in
            let settings = SettingsWindowController(selection: .system, updates: nil) { _ in }
            defer { settings.window?.close() }
            settings.focusSearch()
            let editor = try XCTUnwrap(settings.searchField.currentEditor())
            try pasteText("dark", using: item, focusedWindow: try XCTUnwrap(settings.window))
            XCTAssertEqual(editor.string, "dark")
            XCTAssertEqual(controller.batchCountForTesting, 0)
        }
    }

    @MainActor func testSettingsWithoutTextFocusCannotImportIntoBackgroundWorkbench() async throws {
        try await withWorkbench { controller, item, _ in
            // AppKit may fall back from a non-editing Settings window to the main
            // window's responder chain; that background controller must refuse paste.
            XCTAssertFalse(try XCTUnwrap(controller.window).isKeyWindow)
            XCTAssertFalse(controller.validateMenuItem(item))
            _ = controller.tryToPerform(try XCTUnwrap(item.action), with: item)
            XCTAssertEqual(controller.batchCountForTesting, 0)
        }
    }

    @MainActor func testWorkbenchTextEditorReceivesNativePaste() async throws {
        try await withWorkbench { controller, item, _ in
            let window = try XCTUnwrap(controller.window)
            let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
            window.contentView?.addSubview(editor); window.makeFirstResponder(editor)
            try pasteText("A text value", using: item, focusedWindow: window)
            XCTAssertEqual(editor.string, "A text value")
            XCTAssertEqual(controller.batchCountForTesting, 0)
        }
    }

    @MainActor func testWorkbenchStillPastesImagesIntoEmptyAndPopulatedBatches() async throws {
        try await withWorkbench { controller, item, _ in
            let window = try XCTUnwrap(controller.window)
            window.makeFirstResponder(window.contentView)
            for count in 1...2 {
                controller.pasteImage(item)
                XCTAssertEqual(controller.batchCountForTesting, count)
            }
        }
    }
}
