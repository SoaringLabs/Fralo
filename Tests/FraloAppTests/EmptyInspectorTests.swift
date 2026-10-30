import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class EmptyInspectorTests: XCTestCase {
    private var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/FraloApp/Development/Fixtures/03-journal.png")
    }

    @MainActor func testEmptyBatchCollapsesOnlyTheListAndKeepsTheInspector() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-empty-panels-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window)
        defer { window.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let list = try XCTUnwrap(root.left.body as? BatchList)
        let source = fixture
        XCTAssertTrue(root.collapsed); XCTAssertFalse(root.inspectorHidden); XCTAssertFalse(root.right.isHidden)
        XCTAssertFalse(defaults.bool(forKey: "sidebarCollapsed"), "Automatic collapse must not overwrite the user's preference")
        controller.importURLs([source]); XCTAssertFalse(root.collapsed); XCTAssertFalse(root.inspectorHidden)
        controller.newBatch(nil); XCTAssertTrue(list.entries.isEmpty); XCTAssertTrue(root.collapsed); XCTAssertFalse(root.inspectorHidden)
        XCTAssertFalse(defaults.bool(forKey: "sidebarCollapsed"))
        controller.undoChange(nil); XCTAssertEqual(list.entries.count, 1); XCTAssertFalse(root.collapsed)
        controller.redoChange(nil); XCTAssertTrue(list.entries.isEmpty); XCTAssertTrue(root.collapsed)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let second = directory.appendingPathComponent("second.png")
        try FileManager.default.copyItem(at: source, to: second)
        controller.importURLs([source, second]); XCTAssertFalse(root.collapsed)
        controller.removeSelected(nil); XCTAssertEqual(list.entries.count, 1); XCTAssertFalse(root.collapsed)
        controller.removeSelected(nil); XCTAssertTrue(list.entries.isEmpty); XCTAssertTrue(root.collapsed)
        XCTAssertTrue((window.firstResponder as? NSView)?.isHiddenOrHasHiddenAncestor == false)
        controller.undoChange(nil); XCTAssertFalse(root.collapsed)
        controller.toggleSidebar(nil); XCTAssertTrue(root.collapsed)
        XCTAssertTrue(defaults.bool(forKey: "sidebarCollapsed"))
        controller.newBatch(nil); controller.undoChange(nil)
        XCTAssertTrue(root.collapsed, "Restoring content must retain an explicitly hidden list")
    }

    @MainActor func testOpeningTheEmptyListShowsItsPlaceholderAndSurvivesImports() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-empty-placeholder-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window)
        defer { window.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let placeholder = try XCTUnwrap(descendants(root.left).compactMap { $0 as? SidebarEmptyPlaceholder }.first)
        controller.toggleSidebar(nil)
        XCTAssertFalse(root.collapsed); XCTAssertFalse(placeholder.isHidden); XCTAssertTrue(root.left.body.isHidden)
        controller.newBatch(nil)
        XCTAssertFalse(root.collapsed, "Repeated empty updates must not undo an explicit Show List command")
        controller.importURLs([fixture]); XCTAssertTrue(placeholder.isHidden); XCTAssertFalse(root.left.body.isHidden)
        controller.newBatch(nil); XCTAssertTrue(root.collapsed); XCTAssertFalse(placeholder.isHidden)
        XCTAssertEqual(window.subtitle, "iPhone 18 Pro Max · 竖屏 · 透明 PNG", "The empty subtitle names what the first import will be framed as")
    }

    @MainActor func testDropSummaryCountsFolderImagesAndDeclinesUnsupportedOrDuplicateFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appendingPathComponent("a.png"), other = directory.appendingPathComponent("b.jpg")
        let pdf = directory.appendingPathComponent("notes.pdf")
        for url in [image, other, pdf] { try Data([0]).write(to: url) }
        let folder = DropSummary(urls: [directory])
        XCTAssertEqual(folder.images, 2); XCTAssertEqual(folder.accepted, [directory]); XCTAssertTrue(folder.canDrop)
        XCTAssertEqual(folder.message(appending: false, device: "iPhone 18 Pro · 竖屏").title, "松开以添加 2 张图片")
        let mixed = DropSummary(urls: [image, pdf])
        XCTAssertEqual(mixed.accepted, [image]); XCTAssertEqual(mixed.message(appending: true, device: "").detail, "将添加 1 张 · 忽略 1 个文件")
        XCTAssertEqual(mixed.message(appending: true, device: "").title, "松开以追加 1 张图片到批次")
        let unsupported = DropSummary(urls: [pdf])
        XCTAssertFalse(unsupported.canDrop)
        XCTAssertEqual(unsupported.message(appending: false, device: "").title, "无法添加这个文件")
        XCTAssertEqual(unsupported.message(appending: false, device: "").detail, "仅支持 PNG / JPEG 图片")
        let duplicate = DropSummary(urls: [image], existing: [ImageInput(url: image).id])
        XCTAssertFalse(duplicate.canDrop); XCTAssertEqual(duplicate.message(appending: true, device: "").title, "这些图片已在批次中")
    }

    @MainActor func testEmptyStageDrawsTheSelectedFrameAndPlacesTheTargetOnItsScreen() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-empty-frame-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window)
        defer { window.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let stage = try XCTUnwrap(descendants(root.content).compactMap { $0 as? EmptyStageView }.first)
        let inspector = try XCTUnwrap(root.right.body as? CompositionInspector)
        for size in [NSSize(width: 1030, height: 640), NSSize(width: 1400, height: 950)] {
            window.setContentSize(size); root.layoutSubtreeIfNeeded()
            for _ in 0..<150 where stage.device == nil { try await Task.sleep(nanoseconds: 20_000_000) }
            stage.layoutSubtreeIfNeeded()
            let frame = try XCTUnwrap(stage.deviceRect), screen = try XCTUnwrap(stage.screenRect)
            XCTAssertTrue(frame.contains(screen)); XCTAssertTrue(screen.contains(stage.zone.frame))
            XCTAssertLessThanOrEqual(frame.maxX, stage.bounds.width - root.viewingInsets.right + 0.5, "The frame stays clear of the inspector")
            XCTAssertGreaterThanOrEqual(frame.minY, root.headerHeight, "The frame stays below the header")
            XCTAssertFalse(stage.zone.action.isHiddenOrHasHiddenAncestor)
            XCTAssertTrue(stage.zone.bounds.contains(stage.zone.convert(stage.zone.action.frame, from: stage.zone.action.superview)))
        }
        let portrait = try XCTUnwrap(stage.device?.image.size)
        var landscape = inspector.settings; landscape.orientation = .landscape
        inspector.restore(landscape); inspector.onChange?(landscape)
        for _ in 0..<150 where stage.device?.image.size == portrait { try await Task.sleep(nanoseconds: 20_000_000) }
        let turned = try XCTUnwrap(stage.device?.image.size)
        XCTAssertGreaterThan(turned.width, turned.height, "The empty frame follows the selected orientation")
    }
}
