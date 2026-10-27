import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class PanelPolishTests: XCTestCase {
    @MainActor func testInspectorWidthStaysFixedWhenLongSettingsNeedScrolling() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-scroll-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        defer { controller.window?.close(); try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        let window = try XCTUnwrap(controller.window), root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let inspector = try XCTUnwrap(root.right.body as? CompositionInspector)
        let scroll = try XCTUnwrap(inspector.subviews.first as? NSScrollView)
        // Reproduce the user's always-visible native scrollbar preference without changing the OS.
        scroll.scrollerStyle = .legacy
        window.setContentSize(NSSize(width: 1400, height: 1000)); root.layoutSubtreeIfNeeded()
        let before = inspector.devicePicker.convert(inspector.devicePicker.bounds, to: root.right)
        let clipWidth = scroll.contentView.bounds.width
        inspector.mode.choose(1); root.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 60_000_000); root.layoutSubtreeIfNeeded()
        let after = inspector.devicePicker.convert(inspector.devicePicker.bounds, to: root.right)
        XCTAssertEqual(after.width, before.width, accuracy: 0.5, "Overflow must not squeeze the settings")
        XCTAssertEqual(after.midX, before.midX, accuracy: 0.5, "Switching mode must not shift controls sideways")
        XCTAssertEqual(scroll.contentView.bounds.width, clipWidth, accuracy: 0.5)
    }

    @MainActor func testPreviewActivityBelongsToTheViewingToolbar() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-preview-activity-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        defer { controller.window?.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let root = try XCTUnwrap(controller.window?.contentView)
        let toolbar = try XCTUnwrap(descendants(root).compactMap { $0 as? ViewToolbar }.first)
        let activity = descendants(root).compactMap { $0 as? NSProgressIndicator }.filter { !($0.superview is ActionButton) }
        XCTAssertEqual(activity.count, 1)
        for spinner in activity { XCTAssertTrue(spinner.isDescendant(of: toolbar), "Preview activity needs a stable place beside preview controls") }
    }
    @MainActor func testSwitchingBatchInputKeepsTheFixedOrientationIllustration() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "fralo-fixed-demo-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        defer { controller.window?.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let root = try XCTUnwrap(controller.window?.contentView as? WorkbenchView)
        let list = try XCTUnwrap(root.left.body as? BatchList)
        let choice = try XCTUnwrap(descendants(root.right.body).compactMap { $0 as? VisualChoiceGroup }.first { $0.accessibilityLabel() == "方向" })
        let canvas = try XCTUnwrap(descendants(root.content).compactMap { $0 as? CanvasSurface }.first)
        for (name, red, green) in [("green.png", 0.1, 0.8), ("red.png", 0.9, 0.1)] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 100, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(srgbRed: red, green: green, blue: 0.1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
            try FrameRenderer.pngData(XCTUnwrap(context.makeImage())).write(to: directory.appendingPathComponent(name))
        }
        controller.importURLs([directory.appendingPathComponent("green.png"), directory.appendingPathComponent("red.png")])
        for _ in 0..<150 where canvas.image == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        let first = try XCTUnwrap(canvas.image)
        root.layoutSubtreeIfNeeded()
        func illustration() throws -> Data {
            let bitmap = try XCTUnwrap(choice.bitmapImageRepForCachingDisplay(in: choice.bounds))
            choice.cacheDisplay(in: choice.bounds, to: bitmap)
            return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        }
        let before = try illustration()
        list.select(1)
        for _ in 0..<150 where canvas.image === first { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertFalse(canvas.image === first, "The real preview still follows the selected input")
        XCTAssertEqual(try illustration(), before, "The inspector demo must not follow the selected input")
    }

}
