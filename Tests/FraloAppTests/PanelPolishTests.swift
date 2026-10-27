import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class PanelPolishTests: XCTestCase {
    @MainActor func testDockedSidebarUsesLeadingNativeToggleAndRestoresCollapsedState() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-docked-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(url: directory.appendingPathComponent("settings.json"))
        let controller = MainWindowController(store: store, preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); defer { window.close() }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let toggle = try XCTUnwrap(window.toolbar?.items.first)
        XCTAssertEqual(toggle.itemIdentifier, NSToolbarItem.Identifier("sidebar"))
        XCTAssertTrue(toggle.isNavigational, "AppKit must position the toggle with the leading window navigation controls")
        XCTAssertEqual(toggle.action, #selector(MainWindowController.toggleSidebar(_:)))
        toggle.validate()
        XCTAssertTrue(toggle.isEnabled, "The native navigation item must validate against the workbench controller")
        XCTAssertEqual(toggle.visibilityPriority, .user)
        for size in [NSSize(width: 1030, height: 640), NSSize(width: 1400, height: 1000)] {
            window.setContentSize(size); root.layoutSubtreeIfNeeded()
            XCTAssertEqual(root.left.frame.origin, .zero)
            XCTAssertEqual(root.left.frame.height, root.bounds.height)
            XCTAssertGreaterThanOrEqual(root.left.frame.width, 230)
            XCTAssertGreaterThan(root.content.frame.width, 300)
            XCTAssertEqual(root.left.surface.cornerRadius, 0)
            XCTAssertEqual(root.left.layer?.shadowOpacity ?? 0, 0)
            let header = root.left.subviews.compactMap { $0 as? NSStackView }.first!
            XCTAssertGreaterThanOrEqual(header.convert(header.bounds, to: root).minY, root.safeAreaInsets.top)
        }
        let inspector = try XCTUnwrap(root.right.body as? CompositionInspector)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let field = try XCTUnwrap(descendants(inspector).compactMap { $0 as? NSTextField }.first { $0.isEditable && !$0.isHiddenOrHasHiddenAncestor })
        XCTAssertTrue(window.makeFirstResponder(field))
        let responder = window.firstResponder
        controller.toggleSidebar(nil)
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertTrue(window.firstResponder === responder, "Hiding the list must not steal an inspector editing session")
        XCTAssertTrue(root.left.isHidden)
        let restored = MainWindowController(store: store, preferences: defaults, restoreWindow: false)
        defer { restored.window?.close() }
        XCTAssertTrue(try XCTUnwrap(restored.window?.contentView as? WorkbenchView).collapsed)
        controller.toggleSidebar(nil); controller.toggleSidebar(nil); controller.toggleSidebar(nil)
        try await Task.sleep(nanoseconds: 350_000_000); root.layoutSubtreeIfNeeded()
        XCTAssertFalse(root.collapsed); XCTAssertFalse(root.left.isHidden)
        XCTAssertEqual(root.left.frame.minX, 0)
    }


    @MainActor func testNativeHeaderAndShadowChangesKeepThePreviewScaleStable() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "fralo-header-shadow-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        defer { controller.window?.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(window.titleVisibility, .visible); XCTAssertFalse(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.toolbarStyle, .unified)
        window.setContentSize(NSSize(width: 1400, height: 1000))
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let shadow = try XCTUnwrap(descendants(root).compactMap { $0 as? ValuePicker }.first { $0.accessibilityLabel() == "阴影" })
        let canvas = try XCTUnwrap(descendants(root).compactMap { $0 as? CanvasSurface }.first)
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 800, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.4, blue: 0.3, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 400, height: 800))
        let file = directory.appendingPathComponent("shadow.png"); try FrameRenderer.pngData(XCTUnwrap(context.makeImage())).write(to: file)
        controller.importURLs([file])
        for _ in 0..<150 where canvas.image == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        root.layoutSubtreeIfNeeded()
        let initial = try XCTUnwrap(canvas.zoom)
        for index in [1, 2, 0] {
            let previous = canvas.image; shadow.choose(index)
            for _ in 0..<150 where canvas.image === previous { try await Task.sleep(nanoseconds: 20_000_000) }
            root.layoutSubtreeIfNeeded()
            XCTAssertEqual(try XCTUnwrap(canvas.zoom), initial, accuracy: 0.0001, "Shadow padding must not rescale the device in fit-to-window preview")
        }
    }

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
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertTrue(inspector.exportSettings.isDescendant(of: document), "Export format and JPEG parameters must scroll with the other settings")
        XCTAssertTrue(inspector.outputInfo.isDescendant(of: document), "The output summary belongs to the scrolling settings")
        XCTAssertFalse(inspector.mode.isDescendant(of: document), "The mode selector stays pinned above the scrolling form")
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
        let deadline = Date(timeIntervalSinceNow: 1.5)
        while canvas.image === first && Date() < deadline {
            RunLoop.current.run(mode: .eventTracking, before: Date(timeIntervalSinceNow: 0.02))
        }
        XCTAssertFalse(canvas.image === first, "The canvas must update while a contextual menu is tracking, before it closes")
        for _ in 0..<150 where canvas.image === first { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertFalse(canvas.image === first, "The real preview still follows the selected input")
        XCTAssertEqual(try illustration(), before, "The inspector demo must not follow the selected input")
        let inspector = try XCTUnwrap(root.right.body as? CompositionInspector)
        XCTAssertTrue(inspector.calculateSize.isEnabled)
        inspector.calculateSize.performClick(nil)
        for _ in 0..<150 where !inspector.outputSize.stringValue.hasPrefix("预计 ") { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(inspector.outputSize.stringValue.hasPrefix("预计 "))
        XCTAssertTrue(inspector.calculateSize.isHidden, "Retain the computed count until input or settings change")
        let compression = try XCTUnwrap(descendants(inspector).compactMap { $0 as? ValuePicker }.first { $0.accessibilityLabel() == "PNG 压缩" })
        let previous = canvas.image; compression.choose(1)
        for _ in 0..<250 where canvas.image === previous { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertFalse(inspector.settings.pngLossless)
        XCTAssertFalse(canvas.image === previous)
        XCTAssertTrue(inspector.outputSize.stringValue.hasPrefix("预计 "), "Reuse PNG preview encoding to report bytes without another render")
    }

}
