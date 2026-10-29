import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class CanvasChromeTests: XCTestCase {
    @MainActor private final class KeyWindow: NSWindow { override var isKeyWindow: Bool { true } }
    @MainActor private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }

    @MainActor func testBackdropNeverInterceptsCanvasButFloatingControlsRemainClickable() throws {
        _ = NSApplication.shared
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let chrome = CanvasChrome(.floating); chrome.frame = NSRect(x: 0, y: 0, width: 800, height: 76)
        let button = NSButton(title: "Zoom", target: nil, action: nil)
        button.frame = NSRect(x: 320, y: 20, width: 160, height: 36)
        chrome.addSubview(button); chrome.controls = button; host.addSubview(chrome)
        chrome.layoutSubtreeIfNeeded()
        for engaged in [false, true] {
            chrome.setEngaged(engaged)
            XCTAssertNil(chrome.hitTest(NSPoint(x: 100, y: 38)))
            XCTAssertNil(chrome.hitTest(NSPoint(x: 315, y: 38)), "Decorative halo must not steal drag/scroll input")
            let hit = try XCTUnwrap(chrome.hitTest(NSPoint(x: 400, y: 38)))
            XCTAssertTrue(hit === button || hit.isDescendant(of: button))
        }
        XCTAssertLessThan(chrome.effect.frame.width, host.bounds.width / 2, "Bottom material stays local to the capsule")
        XCTAssertEqual(chrome.effect.blendingMode, .withinWindow)
    }

    @MainActor func testAccessibilityFallbackAndInteractionNeverChangeGeometry() {
        _ = NSApplication.shared
        let chrome = CanvasChrome(.top)
        chrome.frame = NSRect(x: 0, y: 0, width: 600, height: 70)
        var preferences = DesignPreferences(); preferences.reduceMotion = true
        chrome.preferences = preferences
        let original = chrome.frame
        for engaged in [true, false, true, false] {
            chrome.setEngaged(engaged, animated: true)
            XCTAssertEqual(chrome.frame, original)
            XCTAssertEqual(chrome.effect.alphaValue, engaged || preferences.effectiveReduceTransparency || preferences.effectiveIncreaseContrast ? 1 : 0)
        }
        preferences.reduceTransparency = true; chrome.preferences = preferences
        chrome.setEngaged(false)
        XCTAssertTrue(chrome.isUsingOpaqueFallback)
        XCTAssertTrue(chrome.effect.isHidden)
        preferences.increaseContrast = true; chrome.preferences = preferences
        XCTAssertEqual(chrome.frame, original)
    }

    @MainActor func testToolbarHoverUsesEventCoordinatesInsteadOfAnUnrelatedGlobalCursor() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        window.contentView = host
        let chrome = CanvasChrome(.top); chrome.frame = NSRect(x: 0, y: 340, width: 600, height: 60); host.addSubview(chrome)
        chrome.updatePointer(locationInWindow: chrome.convert(NSPoint(x: 300, y: 30), to: nil))
        XCTAssertTrue(chrome.isPointerInside)
        chrome.refresh(animated: false)
        XCTAssertTrue(chrome.isPointerInside, "A window update must not overwrite an actual pointer event with the global cursor")
        chrome.updatePointer(locationInWindow: chrome.convert(NSPoint(x: 300, y: -200), to: nil))
        XCTAssertFalse(chrome.isPointerInside)
    }

    @MainActor func testFocusAndNestedMenuKeepMaterialUntilBothAreDismissed() throws {
        _ = NSApplication.shared
        let window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400)); window.contentView = host
        let chrome = CanvasChrome(.floating); chrome.frame = NSRect(x: 0, y: 0, width: 600, height: 76); host.addSubview(chrome)
        let button = NSPopUpButton(frame: NSRect(x: 200, y: 20, width: 180, height: 30)); button.addItem(withTitle: "100%")
        chrome.addSubview(button); chrome.controls = button; chrome.focusViews = { [button] }
        var preferences = DesignPreferences(); preferences.reduceMotion = true; chrome.preferences = preferences
        chrome.updatePointer(locationInWindow: NSPoint(x: -1000, y: -1000))
        XCTAssertTrue(window.makeFirstResponder(button)); chrome.refresh(animated: false)
        XCTAssertTrue(chrome.isEngaged, "Keyboard focus protects controls without hover")
        let menu = NSMenu(), submenu = NSMenu()
        let item = NSMenuItem(title: "Nested", action: nil, keyEquivalent: ""); item.submenu = submenu; menu.addItem(item)
        chrome.menus = { [menu] }
        window.makeFirstResponder(nil)
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: submenu)
        XCTAssertTrue(chrome.isEngaged, "A nested menu belongs to its originating tool region")
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: submenu)
        XCTAssertFalse(chrome.isEngaged, "Dismissal restores transparency after focus and hover have left")
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
            XCTAssertLessThanOrEqual(rect.maxX, scroll.contentView.bounds.width + 0.1)
            let fittedZoom = canvas.zoom
            let fittedOrigin = scroll.contentView.bounds.origin
            window.makeFirstResponder(canvas)
            window.selectNextKeyView(nil)
            root.layoutSubtreeIfNeeded()
            XCTAssertEqual(scroll.contentView.bounds.origin, fittedOrigin, "Keyboard focus must not scroll a fitted image")
            for engaged in [true, false, true] {
                root.headerBackdrop.setEngaged(engaged)
                XCTAssertEqual(canvas.zoom, fittedZoom); XCTAssertEqual(canvas.imageRect, rect)
            }
            controller.actualPixels(nil); root.layoutSubtreeIfNeeded()
            XCTAssertGreaterThanOrEqual(canvas.imageRect.minY, canvas.viewingInsets.top)
            XCTAssertGreaterThanOrEqual(canvas.bounds.height - canvas.imageRect.maxY, canvas.viewingInsets.bottom)
            XCTAssertEqual(scroll.frame.height, root.content.bounds.height, accuracy: 0.1)
        }
        let document = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "document" }?.view)
        let localProtection = try XCTUnwrap(descendants(document).compactMap { $0 as? MaterialSurface }.first)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: canvas.imageRect.minY + 100))
        XCTAssertFalse(localProtection.isHidden, "Only overlapping artwork needs a local filename backing")
        controller.newBatch(nil)
        XCTAssertTrue(localProtection.isHidden, "Empty state must discard the previous artwork's overlap protection")
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
