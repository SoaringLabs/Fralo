import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class HIGWorkbenchTests: XCTestCase {
    @MainActor private func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap { descendants($0) } }
    @MainActor func testUndoRedoRestoresSettingsGesturesAndBatchSelection() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsStore(url: root.appendingPathComponent("settings.json"))
        var initial = CompositionSettings(); initial.mode = .background; initial.backgroundShadow = .none
        try CompositionStore(legacy: store).save(initial)
        let suite = "fralo-hig-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let controller = MainWindowController(store: store, preferences: defaults, pasteboard: board, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); window.isReleasedWhenClosed = false
        defer { window.close() }
        let views = descendants(try XCTUnwrap(window.contentView))
        let inspector = try XCTUnwrap(views.compactMap { $0 as? CompositionInspector }.first)
        let canvas = try XCTUnwrap(views.compactMap { $0 as? CanvasSurface }.first)
        let list = try XCTUnwrap(views.compactMap { $0 as? BatchList }.first)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/FraloApp/Development/Fixtures/03-journal.png")
        let second = root.appendingPathComponent("second.png"); try FileManager.default.copyItem(at: source, to: second)
        controller.importURLs([source, second]); list.select(1); window.makeFirstResponder(canvas)
        controller.removeSelected(nil); XCTAssertEqual(list.entries.count, 1)
        controller.undoChange(nil); XCTAssertEqual(list.entries.count, 2); XCTAssertEqual(list.selectedIndex, 1)
        controller.redoChange(nil); XCTAssertEqual(list.entries.count, 1)
        controller.newBatch(nil); XCTAssertTrue(list.entries.isEmpty)
        controller.undoChange(nil); XCTAssertEqual(list.entries.count, 1)
        controller.redoChange(nil); XCTAssertTrue(list.entries.isEmpty)
        controller.undoChange(nil); XCTAssertEqual(list.entries.count, 1)
        inspector.devicePicker.choose(1)
        XCTAssertEqual(try CompositionStore(legacy: store).load().display, .tablet)
        controller.undoChange(nil); XCTAssertEqual(inspector.devicePicker.selectedIndex, 0)
        XCTAssertEqual(try CompositionStore(legacy: store).load().display, .phone)
        controller.redoChange(nil); XCTAssertEqual(inspector.devicePicker.selectedIndex, 1)
        let opacity = try XCTUnwrap(descendants(inspector).compactMap { $0 as? SliderRow }.first { $0.slider.accessibilityLabel() == "设备透明度" })
        opacity.onEditingChanged?(true)
        opacity.setValue(90, notify: true); opacity.setValue(80, notify: true); opacity.setValue(60, notify: true)
        opacity.onEditingChanged?(false)
        controller.undoChange(nil); XCTAssertEqual(try CompositionStore(legacy: store).load().deviceOpacity, 1)
        controller.redoChange(nil); XCTAssertEqual(try CompositionStore(legacy: store).load().deviceOpacity, 0.6)
        window.makeFirstResponder(canvas)
        let command = NSMenuItem(title: "向右移动", action: #selector(MainWindowController.nudgeArtwork(_:)), keyEquivalent: "")
        command.representedObject = NSValue(point: CGPoint(x: 1, y: 0))
        XCTAssertTrue(controller.validateMenuItem(command)); controller.nudgeArtwork(command)
        XCTAssertEqual(try CompositionStore(legacy: store).load().deviceX, 1 / 2400, accuracy: 0.000001)
        controller.undoChange(nil); XCTAssertEqual(try CompositionStore(legacy: store).load().deviceX, 0)
        controller.redoChange(nil); XCTAssertEqual(try CompositionStore(legacy: store).load().deviceX, 1 / 2400, accuracy: 0.000001)
        for _ in 0..<1500 where canvas.image == nil { try await Task.sleep(nanoseconds: 5_000_000) }
        window.contentView?.layoutSubtreeIfNeeded()
        let p = canvas.convert(CGPoint(x: canvas.imageRect.midX, y: canvas.imageRect.midY), to: nil)
        func event(_ type: NSEvent.EventType, _ dx: CGFloat) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: p.x + dx, y: p.y), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, 0)); canvas.mouseDragged(with: try event(.leftMouseDragged, 40)); canvas.mouseUp(with: try event(.leftMouseUp, 40))
        let dragged = try CompositionStore(legacy: store).load().deviceX
        XCTAssertGreaterThan(dragged, 0.01)
        controller.undoChange(nil); XCTAssertEqual(try CompositionStore(legacy: store).load().deviceX, 1 / 2400, accuracy: 0.000001)
        controller.redoChange(nil); XCTAssertEqual(try CompositionStore(legacy: store).load().deviceX, dragged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path)); XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    @MainActor func testLongToolbarTitleKeepsActionsAndViewMenusRestorePanels() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "fralo-title-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); defer { window.close() }
        window.setContentSize(CGSize(width: 1030, height: 640))
        let title = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "document" }?.view)
        for text in descendants(title).compactMap({ $0 as? NSTextField }) { text.stringValue = String(repeating: "长文件名称", count: 30) }
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(title.bounds.width, 220)
        let sidebar = NSMenuItem(title: "", action: #selector(MainWindowController.toggleSidebar(_:)), keyEquivalent: "")
        let inspector = NSMenuItem(title: "", action: #selector(MainWindowController.toggleInspector(_:)), keyEquivalent: "")
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        controller.togglePreview()
        XCTAssertTrue(controller.validateMenuItem(sidebar)); XCTAssertEqual(sidebar.title, "显示图片列表")
        controller.toggleSidebar(nil); XCTAssertFalse(root.previewing); XCTAssertFalse(root.collapsed)
        controller.toggleInspector(nil) // Open the initially empty inspector before testing its hide command.
        controller.toggleInspector(nil)
        XCTAssertTrue(controller.validateMenuItem(inspector)); XCTAssertEqual(inspector.title, "显示出图设置")
        controller.toggleInspector(nil); XCTAssertFalse(root.inspectorHidden)
        let undo = NSMenuItem(title: "", action: #selector(MainWindowController.undoChange(_:)), keyEquivalent: "z")
        XCTAssertFalse(controller.validateMenuItem(undo)); XCTAssertEqual(undo.title, "撤销")
    }
    @MainActor func testTextEditingUsesNativeUndoWithoutUndoingTheComposition() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "fralo-native-text-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(url: root.appendingPathComponent("settings.json"))
        let controller = MainWindowController(store: store, preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); defer { window.close() }
        controller.toggleInspector(nil)
        let inspector = try XCTUnwrap(descendants(try XCTUnwrap(window.contentView)).compactMap { $0 as? CompositionInspector }.first)
        inspector.devicePicker.choose(1)
        let field = try XCTUnwrap(descendants(inspector).compactMap { $0 as? ValueField }.first)
        window.makeFirstResponder(field)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        XCTAssertTrue(editor.allowsUndo, "Native percentage editing should support text Undo")
        let original = editor.string
        editor.insertText("75.5", replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(try XCTUnwrap(editor.undoManager).canUndo)
        controller.undoChange(nil)
        XCTAssertEqual(editor.string, original)
        XCTAssertEqual(try CompositionStore(legacy: store).load().display, .tablet)
        controller.redoChange(nil); XCTAssertEqual(editor.string, "75.5")
        XCTAssertEqual(try CompositionStore(legacy: store).load().display, .tablet)
    }

}
