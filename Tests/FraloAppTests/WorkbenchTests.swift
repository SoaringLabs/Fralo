import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class WorkbenchTests: XCTestCase {
    @MainActor func testFloatingInspectorKeepsNavigationAboveFormAndActionsFullWidth() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(url: directory.appendingPathComponent("settings.json"))
        var settings = CompositionSettings(); settings.display = .browser; settings.mode = .background
        try CompositionStore(legacy: store).save(settings)
        let suite = "fralo-polish-\(UUID())"; let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MainWindowController(store: store, preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let inspector = try XCTUnwrap(root.right.body as? CompositionInspector)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let export = try XCTUnwrap(descendants(root.right).compactMap { $0 as? ExportAction }.first)
        let navigation = try XCTUnwrap(descendants(inspector).compactMap { $0 as? ValuePicker }.first { $0.accessibilityLabel() == "设置页面" })
        let device = try XCTUnwrap(descendants(inspector).compactMap { $0 as? ValuePicker }.first { $0.accessibilityLabel() == "展示类型" })
        for size in [NSSize(width: 1030, height: 640), NSSize(width: 1400, height: 838), NSSize(width: 1586, height: 945)] {
            window.setContentSize(size); root.layoutSubtreeIfNeeded()
            XCTAssertEqual(inspector.mode.bounds.width, root.right.bounds.width - 32, accuracy: 1)
            XCTAssertEqual(export.bounds.width, inspector.mode.bounds.width, accuracy: 1)
            let nav = navigation.convert(navigation.bounds, to: inspector)
            let form = device.convert(device.bounds, to: inspector)
            if inspector.isFlipped { XCTAssertLessThan(nav.maxY, form.minY) }
            else { XCTAssertGreaterThan(nav.minY, form.maxY) }
            XCTAssertEqual(root.left.frame.minY, root.right.frame.minY, accuracy: 1)
            XCTAssertEqual(root.left.frame.height, root.right.frame.height, accuracy: 1)
        }
        let tabs = try XCTUnwrap(descendants(inspector).compactMap { $0 as? InspectorTabs }.first)
        tabs.selectTabViewItem(at: 2)
        XCTAssertEqual(navigation.selectedIndex, 2, "Native page selection must update the visible navigation")
        navigation.choose(0)
        XCTAssertEqual(tabs.indexOfTabViewItem(try XCTUnwrap(tabs.selectedTabViewItem)), 0)
    }

    @MainActor func testWorkspaceWindowAllowsBehindWindowMaterial() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "fralo-material-\(UUID())"; let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); defer { window.close() }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        XCTAssertFalse(window.isOpaque, "An opaque window prevents the workspace from compositing with content behind it")
        XCTAssertEqual(window.backgroundColor.alphaComponent, 0, accuracy: 0.001,
                       "The default solid window background must not cover the behind-window material")
        XCTAssertEqual(root.workspace.effect.blendingMode, .behindWindow)
        XCTAssertEqual(root.workspace.effect.state, .followsWindowActiveState)
        XCTAssertEqual(window.alphaValue, 1, "Only the workspace material is translucent; artwork and controls must retain full opacity")
        var reduced = DesignPreferences(); reduced.reduceTransparency = true
        root.workspace.preferences = reduced
        XCTAssertTrue(root.workspace.isUsingOpaqueFallback, "System reduced-transparency behavior must remain available")
    }

    @MainActor func testRealBatchUsesSharedPanelsAndKeepsArtworkWhenCollapsed() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(url: directory.appendingPathComponent("settings.json"))
        let suite = "fralo-test-\(UUID())"; let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MainWindowController(store: store, preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let list = try XCTUnwrap(root.left.body as? BatchList)
        let screen = DeviceModel.iPhone18ProMax
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(screen.screenWidth), height: Int(screen.screenHeight), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.15, green: 0.4, blue: 0.35, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        let data = try FrameRenderer.pngData(XCTUnwrap(context.makeImage()))
        let first = directory.appendingPathComponent("one.png"), second = directory.appendingPathComponent("two.png")
        try data.write(to: first); try data.write(to: second)
        controller.importURLs([first, second, first])
        XCTAssertEqual(list.entries.count, 2, "Import must retain file identity deduplication")
        list.select(1)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let canvas = try XCTUnwrap(descendants(root).compactMap { $0 as? CanvasSurface }.first)
        for _ in 0..<150 where canvas.image == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        let image = try XCTUnwrap(canvas.image)
        controller.toggleSidebar(nil); root.layoutSubtreeIfNeeded()
        XCTAssertTrue(root.collapsed); XCTAssertEqual(canvas.image?.size, image.size)
        XCTAssertEqual(list.selectedIndex, 1)
        for size in [NSSize(width: 1030, height: 640), NSSize(width: 1400, height: 950)] {
            window.setContentSize(size); root.layoutSubtreeIfNeeded()
            XCTAssertEqual(root.left.frame.minY, root.right.frame.minY, accuracy: 1)
            XCTAssertEqual(root.left.frame.height, root.right.frame.height, accuracy: 1)
            XCTAssertGreaterThan(root.content.bounds.width, 300)
        }
        let inspector = try XCTUnwrap(root.right.body as? CompositionInspector)
        inspector.mode.choose(1)
        for _ in 0..<150 where canvas.image?.size != CanvasRatio.landscape.size { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(canvas.image?.size, CanvasRatio.landscape.size)
        let tabs = try XCTUnwrap(descendants(inspector).compactMap { $0 as? InspectorTabs }.first)
        tabs.selectTabViewItem(at: 1); inspector.dragBackground = true
        tabs.selectTabViewItem(at: 0)
        XCTAssertFalse(inspector.dragBackground, "Device page must not retain a hidden background-drag target")
        let point = canvas.convert(NSPoint(x: canvas.imageRect.midX, y: canvas.imageRect.midY), to: nil)
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        canvas.mouseDown(with: down)
        for step in 1...30 {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: point.x + CGFloat(step), y: point.y), modifierFlags: [], timestamp: Double(step) / 60, windowNumber: window.windowNumber, context: nil, eventNumber: step + 1, clickCount: 1, pressure: 1))
            canvas.mouseDragged(with: event)
        }
        canvas.mouseUp(with: down)
        XCTAssertGreaterThan(try CompositionStore(legacy: store).load().deviceX, 0.012, "Small pointer deltas must accumulate so a centered device can escape snapping")
        XCTAssertFalse(canvas.centerGuideX); XCTAssertFalse(canvas.centerGuideY)
        let beforeExportLabel = descendants(root).compactMap { $0 as? ExportAction }.first
        XCTAssertEqual(beforeExportLabel?.count, 2)
        // Background mode is a real saved composition, without rewriting the old CLI file.
        XCTAssertEqual(try CompositionStore(legacy: store).load().mode, .background)
        controller.removeSelected(nil); XCTAssertEqual(list.entries.count, 1)
        controller.newBatch(nil); XCTAssertTrue(list.entries.isEmpty); XCTAssertNil(canvas.image)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path), "GUI composition changes must not rewrite legacy CLI settings")
        XCTAssertEqual(try Data(contentsOf: first), data)
    }
    @MainActor func testJPEGPreviewCopiesUnflattenedPNGToIsolatedPasteboard() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = SettingsStore(url: root.appendingPathComponent("settings.json"))
        var settings = CompositionSettings(); settings.format = .jpeg; settings.deviceOpacity = 0.5
        try CompositionStore(legacy: store).save(settings)
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        let suite = "fralo-copy-\(UUID())"; let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MainWindowController(store: store, preferences: defaults, pasteboard: board, restoreWindow: false)
        defer { controller.window?.close() }
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.4, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 400, height: 100))
        let source = root.appendingPathComponent("wide.png")
        try FrameRenderer.pngData(XCTUnwrap(context.makeImage())).write(to: source)
        controller.importURLs([source])
        for _ in 0..<150 where board.data(forType: .png) == nil {
            controller.copyCurrent(nil); try await Task.sleep(nanoseconds: 20_000_000)
        }
        let data = try XCTUnwrap(board.data(forType: .png))
        let image = try ImageInput(data: data, name: "copied.png").decode()
        let expected = try CompositionRenderer.render(ImageInput(url: source), settings: settings)
        XCTAssertEqual(data, try FrameRenderer.pngData(expected.image), "Copy must use the raw composition even when the preview format is JPEG")
        XCTAssertEqual(image.width, expected.image.width)
    }

    @MainActor func testFailedPreviewCanRecoverWithoutStaleBatchError() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("recover.png"); try Data([0,1,2]).write(to: source)
        let suite = "fralo-recovery-\(UUID())"; let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MainWindowController(store: SettingsStore(url: root.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        defer { controller.window?.close() }
        let workbench = try XCTUnwrap(controller.window?.contentView as? WorkbenchView)
        let list = try XCTUnwrap(workbench.left.body as? BatchList)
        controller.importURLs([source])
        for _ in 0..<150 where list.entries.first?.failed != true { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(try XCTUnwrap(list.entries.first).failed)
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 400, height: 100))
        try FrameRenderer.pngData(XCTUnwrap(context.makeImage())).write(to: source)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let retry = try XCTUnwrap(descendants(workbench).compactMap { $0 as? ActionButton }.first { $0.title == "重试预览" })
        retry.performClick(nil)
        let canvas = try XCTUnwrap(descendants(workbench).compactMap { $0 as? CanvasSurface }.first)
        for _ in 0..<150 where canvas.image == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertNotNil(canvas.image); XCTAssertFalse(try XCTUnwrap(list.entries.first).failed)
    }

}
