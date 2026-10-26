import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class WorkbenchTests: XCTestCase {
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
        controller.removeSelected(nil); XCTAssertEqual(list.entries.count, 1)
        controller.newBatch(nil); XCTAssertTrue(list.entries.isEmpty); XCTAssertNil(canvas.image)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path), "Viewing and batch operations must not rewrite render settings")
        XCTAssertEqual(try Data(contentsOf: first), data)
    }
}
