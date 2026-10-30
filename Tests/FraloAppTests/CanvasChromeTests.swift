import AppKit
import XCTest
import FraloCore
@testable import FraloDesignSystem
@testable import FraloApp

final class CanvasChromeTests: XCTestCase {
    @MainActor private final class KeyWindow: NSWindow {
        var simulatedKey = true
        override var isKeyWindow: Bool { simulatedKey }
    }
    @MainActor private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }

    @MainActor func testToolbarBehaviorOnlyRequestsNativeVisibilityAndKeepsMenuFocus() throws {
        _ = NSApplication.shared
        let window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400)); window.contentView = host
        let behavior = CanvasToolbarBehavior(frame: NSRect(x: 0, y: 340, width: 600, height: 60)); host.addSubview(behavior)
        XCTAssertTrue(behavior.subviews.isEmpty, "The tracking region must never paint a custom backdrop")
        XCTAssertNil(behavior.layer); XCTAssertNil(behavior.hitTest(NSPoint(x: 300, y: 370)))
        var requests: [Bool] = []; behavior.onVisibilityChange = { requests.append($0) }
        behavior.updatePointer(locationInWindow: NSPoint(x: 300, y: 370)); behavior.refresh()
        XCTAssertTrue(behavior.isEngaged); XCTAssertEqual(requests.last, true)
        behavior.updatePointer(locationInWindow: NSPoint(x: 300, y: 200)); behavior.refresh()
        let fallback = behavior.preferences.effectiveReduceTransparency || behavior.preferences.effectiveIncreaseContrast
        XCTAssertFalse(behavior.isEngaged); XCTAssertEqual(requests.last, fallback)
        let button = NSPopUpButton(frame: NSRect(x: 200, y: 350, width: 100, height: 30)); button.addItem(withTitle: "Zoom")
        host.addSubview(button); behavior.focusViews = { [button] }
        XCTAssertTrue(window.makeFirstResponder(button)); behavior.refresh()
        XCTAssertTrue(behavior.isEngaged, "Keyboard focus keeps the system background visible")
        window.makeFirstResponder(nil)
        let menu = NSMenu(), submenu = NSMenu(); let item = NSMenuItem(title: "Nested", action: nil, keyEquivalent: "")
        item.submenu = submenu; menu.addItem(item); behavior.menus = { [menu] }
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: submenu)
        XCTAssertTrue(behavior.isEngaged)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: submenu)
        XCTAssertFalse(behavior.isEngaged)
        behavior.updatePointer(locationInWindow: NSPoint(x: 300, y: 370)); behavior.refresh()
        window.simulatedKey = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertFalse(behavior.isEngaged); XCTAssertFalse(behavior.isPointerInside)
    }

    @MainActor func testFooterKeepsExistingCapsuleAndPassesCanvasInput() throws {
        _ = NSApplication.shared
        let overlay = CanvasControlsOverlay(frame: NSRect(x: 0, y: 0, width: 800, height: 76))
        let controls = ViewToolbar(); controls.frame = NSRect(x: 300, y: 20, width: 200, height: 36)
        overlay.addSubview(controls); overlay.layoutSubtreeIfNeeded()
        XCTAssertNil(overlay.hitTest(NSPoint(x: 100, y: 38)))
        XCTAssertNotNil(overlay.hitTest(NSPoint(x: 400, y: 38)))
        XCTAssertNil(overlay.layer?.mask, "No hand-made gradient or full-width backdrop")
        XCTAssertEqual(controls.surface.role, .panel, "Keep the existing legible FRALO-7 capsule")
        XCTAssertEqual(controls.surface.effect.blendingMode, .withinWindow)
        if #available(macOS 26.0, *) {
            let glass = try XCTUnwrap(descendants(controls).compactMap { $0 as? NSGlassEffectView }.first)
            XCTAssertNil(glass.tintColor)
            if #available(macOS 27.0, *) {
                XCTAssertEqual(glass.effectIsInteractive, !controls.surface.preferences.effectiveReduceMotion && !controls.surface.preferences.effectiveReduceTransparency)
                var reduced = DesignPreferences(); reduced.reduceMotion = true
                controls.surface.preferences = reduced
                XCTAssertFalse(glass.effectIsInteractive)
            }
        }
        var preferences = DesignPreferences(); preferences.reduceTransparency = true
        controls.surface.preferences = preferences
        XCTAssertTrue(controls.surface.isUsingOpaqueFallback)
    }

    @MainActor func testDocumentGuttersKeepFitAndZoomedEdgesReachable() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-chrome-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let canvas = try XCTUnwrap(descendants(root).compactMap { $0 as? CanvasSurface }.first)
        let scroll = try XCTUnwrap(canvas.enclosingScrollView)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FraloApp/Development/Fixtures/03-journal.png")
        controller.importURLs([fixture])
        for _ in 0..<1000 where canvas.image == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        _ = try XCTUnwrap(canvas.image)
        for size in [NSSize(width: 1030, height: 640), NSSize(width: 1400, height: 950)] {
            window.setContentSize(size); root.layoutSubtreeIfNeeded()
            controller.fitPreview(nil); root.layoutSubtreeIfNeeded()
            XCTAssertEqual(root.content.frame.minY, 0, accuracy: 0.1)
            XCTAssertEqual(scroll.frame.height, root.content.bounds.height, accuracy: 0.1)
            XCTAssertFalse(scroll.automaticallyAdjustsContentInsets)
            XCTAssertEqual(scroll.contentInsets.top, 0)
            XCTAssertEqual(scroll.contentInsets.bottom, 0)
            let rect = canvas.imageRect
            XCTAssertGreaterThanOrEqual(rect.minY, canvas.viewingInsets.top)
            XCTAssertLessThanOrEqual(rect.maxY, scroll.contentView.bounds.height - canvas.viewingInsets.bottom + 0.1)
            XCTAssertEqual(root.content.frame, root.content.superview!.bounds, "Floating inspector must not shrink the scrolling viewport")
            XCTAssertEqual(scroll.frame.width, root.content.bounds.width, accuracy: 0.1)
            XCTAssertGreaterThanOrEqual(rect.minX, canvas.viewingInsets.left)
            XCTAssertLessThanOrEqual(rect.maxX, scroll.contentView.bounds.width - canvas.viewingInsets.right + 0.1)
            let fittedZoom = canvas.zoom
            let fittedOrigin = scroll.contentView.bounds.origin
            window.makeFirstResponder(canvas)
            window.selectNextKeyView(nil)
            root.layoutSubtreeIfNeeded()
            XCTAssertEqual(scroll.contentView.bounds.origin, fittedOrigin, "Keyboard focus must not scroll a fitted image")
            for engaged in [false, true, false] {
                let document = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "document" }?.view)
                let documentFrame = document.frame
                root.toolbarBehavior.setEngaged(engaged); root.layoutSubtreeIfNeeded()
                XCTAssertEqual(canvas.zoom, fittedZoom); XCTAssertEqual(canvas.imageRect, rect)
                XCTAssertTrue(root.toolbarBehavior.subviews.isEmpty)
                XCTAssertEqual(document.frame, documentFrame, "Informational text must not move native toolbar actions")
                let title = try XCTUnwrap(descendants(document).compactMap { $0 as? NSTextField }.first)
                XCTAssertFalse(title.isHidden, "Filename remains visible independently of background interaction")
            }
            controller.actualPixels(nil); root.layoutSubtreeIfNeeded()
            XCTAssertGreaterThanOrEqual(canvas.imageRect.minY, canvas.viewingInsets.top)
            XCTAssertGreaterThanOrEqual(canvas.bounds.height - canvas.imageRect.maxY, canvas.viewingInsets.bottom)
            XCTAssertEqual(scroll.frame.height, root.content.bounds.height, accuracy: 0.1)
        }
        let document = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "document" }?.view)
        XCTAssertTrue(descendants(document).compactMap { $0 as? MaterialSurface }.isEmpty, "Filename has no custom white backing")
        for collapsed in [false, true] {
            root.collapsed = collapsed
            for hidden in [false, true] {
                root.inspectorHidden = hidden; root.layoutSubtreeIfNeeded(); controller.fitPreview(nil)
                XCTAssertEqual(root.content.frame, root.content.superview!.bounds)
                XCTAssertEqual(root.toolbarBehavior.frame.width, root.content.frame.width, accuracy: 0.1)
                XCTAssertEqual(canvas.viewingInsets.right, hidden ? 24 : WorkbenchView.inspectorWidth + 34)
                XCTAssertEqual(canvas.imageRect.midX, canvas.viewingInsets.left + (scroll.contentView.bounds.width - canvas.viewingInsets.left - canvas.viewingInsets.right) / 2, accuracy: 0.1)
            }
        }
        controller.newBatch(nil)
        let footer = try XCTUnwrap(descendants(root).compactMap { $0 as? CanvasControlsOverlay }.first)
        XCTAssertTrue(footer.isHidden)
    }

    @MainActor func testGutterCoordinateTransformPreservesAllDragDirections() throws {
        _ = NSApplication.shared
        let canvas = CanvasSurface(frame: NSRect(x: 0, y: 0, width: 900, height: 1000))
        canvas.image = NSImage(size: NSSize(width: 400, height: 800))
        canvas.viewingInsets = NSEdgeInsets(top: 70, left: 0, bottom: 76, right: 0)
        canvas.allowsPositioning = true
        let origin = NSPoint(x: canvas.imageRect.midX, y: canvas.imageRect.midY)
        for (x, y) in [(1.0, 0.0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)] {
            var delta = CGPoint.zero
            canvas.onDrag = { delta = $0 }
            func event(_ type: NSEvent.EventType, _ location: NSPoint) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(location, to: nil), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            }
            canvas.mouseDown(with: try event(.leftMouseDown, origin))
            let target = NSPoint(x: origin.x + x * 20, y: origin.y + y * 20)
            canvas.mouseDragged(with: try event(.leftMouseDragged, target))
            XCTAssertEqual(delta.x, x * 20 / canvas.imageRect.width, accuracy: 0.000001)
            XCTAssertEqual(delta.y, y * 20 / canvas.imageRect.height, accuracy: 0.000001)
            canvas.mouseUp(with: try event(.leftMouseUp, target))
        }
    }
}
