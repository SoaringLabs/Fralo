import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class InspectorTransitionTests: XCTestCase {
    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    @MainActor func testInspectorAndViewingGeometryMoveTogetherAndReverseWithoutJumping() async throws {
        _ = NSApplication.shared
        let suite = "fralo-inspector-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(url: directory.appendingPathComponent("settings.json"))
        try CompositionStore(legacy: store).save(CompositionSettings())
        let controller = MainWindowController(store: store, preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let canvas = try XCTUnwrap(descendants(root).compactMap { $0 as? CanvasSurface }.first)
        let toolbar = try XCTUnwrap(descendants(root).compactMap { $0 as? ViewToolbar }.first)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("examples/01-today.png")
        let sourceBytes = try Data(contentsOf: fixture)
        controller.importURLs([fixture])
        for _ in 0..<1000 where canvas.image == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        let image = try XCTUnwrap(canvas.image)
        let storedSettings = try Data(contentsOf: directory.appendingPathComponent("settings.workbench.json"))
        for size in [NSSize(width: 1400, height: 850), NSSize(width: 1030, height: 640)] {
            window.setContentSize(size); root.layoutSubtreeIfNeeded(); controller.fitPreview(nil)
            let startInset = root.viewingInsets.right, startX = canvas.imageRect.midX
            controller.toggleInspector(nil)
            if !root.motionPreferences.effectiveReduceMotion {
                XCTAssertEqual(root.viewingInsets.right, startInset, accuracy: 0.01, "Starting a slide must not publish its final viewing margins")
                XCTAssertEqual(canvas.imageRect.midX, startX, accuracy: 0.1)
                var samples: [CGFloat] = []
                for _ in 0..<6 {
                    try await Task.sleep(nanoseconds: 20_000_000)
                    root.layoutSubtreeIfNeeded()
                    let inset = root.viewingInsets.right
                    samples.append(inset)
                    let reveal = (inset - 24) / (WorkbenchView.inspectorWidth + WorkbenchView.inspectorInset)
                    XCTAssertEqual(root.right.frame.minX, root.content.bounds.width + WorkbenchView.inspectorInset - (WorkbenchView.inspectorWidth + 2 * WorkbenchView.inspectorInset) * reveal, accuracy: 0.1)
                    XCTAssertEqual(canvas.viewingInsets.right, inset, accuracy: 0.1)
                    XCTAssertEqual(toolbar.convert(toolbar.bounds, to: root.content).midX, (24 + root.content.bounds.width - inset) / 2, accuracy: 1)
                }
                XCTAssertTrue(samples.contains { $0 > 24.1 && $0 < startInset - 0.1 }, "The actual artwork must receive intermediate viewing geometry")
                let currentInset = root.viewingInsets.right
                controller.toggleInspector(nil)
                XCTAssertEqual(root.viewingInsets.right, currentInset, accuracy: 0.01, "Reversal starts at the presented geometry")
            } else { controller.toggleInspector(nil) }
            try await Task.sleep(nanoseconds: 350_000_000)
            XCTAssertFalse(root.inspectorHidden); XCTAssertFalse(root.right.isHidden)
            XCTAssertEqual(root.viewingInsets.right, startInset, accuracy: 0.01)
            XCTAssertEqual(canvas.imageRect.midX, startX, accuracy: 0.1)
            controller.actualPixels(nil); let explicitZoom = canvas.zoom
            window.makeFirstResponder(canvas)
            controller.toggleInspector(nil)
            window.setContentSize(NSSize(width: size.width + 25, height: size.height))
            root.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 350_000_000)
            XCTAssertEqual(root.viewingInsets.right, 24, accuracy: 0.01); XCTAssertTrue(root.right.isHidden)
            XCTAssertEqual(canvas.zoom, explicitZoom); XCTAssertTrue(window.firstResponder === canvas)
            controller.toggleInspector(nil)
            try await Task.sleep(nanoseconds: 350_000_000)
            XCTAssertEqual(canvas.zoom, explicitZoom); XCTAssertTrue(canvas.image === image)
        }
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("settings.workbench.json")), storedSettings)
        XCTAssertEqual(try Data(contentsOf: fixture), sourceBytes)
    }

    @MainActor func testEmptyStatePreviewAndReducedMotionCancelPendingSlide() async throws {
        _ = NSApplication.shared
        let suite = "fralo-inspector-empty-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(url: directory.appendingPathComponent("settings.json"))
        try CompositionStore(legacy: store).save(CompositionSettings())
        let controller = MainWindowController(store: store, preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let empty = try XCTUnwrap(descendants(root).compactMap { $0 as? EmptyStageView }.first)
        root.layoutSubtreeIfNeeded()
        controller.toggleInspector(nil)
        try await Task.sleep(nanoseconds: 60_000_000)
        root.layoutSubtreeIfNeeded()
        XCTAssertEqual(empty.viewingInsets.right, root.viewingInsets.right, accuracy: 0.01)
        root.motionPreferences.reduceMotion = true
        XCTAssertEqual(root.viewingInsets.right, 24); XCTAssertTrue(root.right.isHidden)
        controller.toggleInspector(nil)
        XCTAssertEqual(root.viewingInsets.right, 352); XCTAssertFalse(root.right.isHidden)
        root.motionPreferences.reduceMotion = false
        controller.toggleInspector(nil)
        root.previewing = true
        XCTAssertEqual(root.viewingInsets.right, 24); XCTAssertTrue(root.right.isHidden)
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(root.viewingInsets.right, 24); XCTAssertTrue(root.right.isHidden)
        root.previewing = false; root.inspectorHidden = false
        controller.toggleInspector(nil)
        root.setInspectorHidden(true, animated: false)
        XCTAssertEqual(root.viewingInsets.right, 24); XCTAssertTrue(root.right.isHidden)
        root.inspectorHidden = false
        controller.toggleInspector(nil)
        try await Task.sleep(nanoseconds: 50_000_000)
        root.inspectorHidden = false // Direct nonanimated restoration cancels the old callback.
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertEqual(root.viewingInsets.right, 352); XCTAssertFalse(root.right.isHidden)
    }
}
