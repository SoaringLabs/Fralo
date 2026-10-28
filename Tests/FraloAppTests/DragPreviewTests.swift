import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class DragPreviewTests: XCTestCase {
    @MainActor func testDraggingTransformsCachedLayersAndOnlyRendersOnMouseUp() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 400, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.6, blue: 0.4, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 400, height: 800))
        let source = directory.appendingPathComponent("source.png")
        try FrameRenderer.pngData(XCTUnwrap(context.makeImage())).write(to: source)
        for (format, pan) in [(ImageFormat.png, false), (.jpeg, false), (.png, true)] {
            let store = SettingsStore(url: directory.appendingPathComponent(UUID().uuidString + ".json"))
            var settings = CompositionSettings(); settings.mode = .background; settings.background = .sage
            settings.pngLossless = false; settings.pngQuality = 0.345; settings.format = format
            settings.deviceX = 0.2; settings.backgroundScale = 2; settings.deviceOpacity = 0.6; settings.backgroundShadow = .strong
            try CompositionStore(legacy: store).save(settings)
            let suite = "fralo-drag-\(UUID())", board = NSPasteboard.withUniqueName()
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite); board.releaseGlobally() }
            let controller = MainWindowController(store: store, preferences: defaults, pasteboard: board, restoreWindow: false)
            let window = try XCTUnwrap(controller.window); window.isReleasedWhenClosed = false
            defer { window.close() }
            func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap { descendants($0) } }
            let root = try XCTUnwrap(window.contentView)
            let canvas = try XCTUnwrap(descendants(root).compactMap { $0 as? CanvasSurface }.first)
            let inspector = try XCTUnwrap(descendants(root).compactMap { $0 as? CompositionInspector }.first)
            controller.importURLs([source])
            for _ in 0..<2000 where canvas.image == nil { try await Task.sleep(nanoseconds: 5_000_000) }
            root.layoutSubtreeIfNeeded()
            let initialImage = try XCTUnwrap(canvas.image)
            inspector.dragBackground = pan
            let origin = canvas.convert(CGPoint(x: canvas.imageRect.midX, y: canvas.imageRect.midY), to: nil)
            func event(_ type: NSEvent.EventType, _ fraction: CGFloat) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: origin.x + fraction * canvas.imageRect.width, y: origin.y),
                    modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            }
            canvas.mouseDown(with: try event(.leftMouseDown, 0))
            let generation = controller.previewRequest, start = ProcessInfo.processInfo.systemUptime
            for step in 1...120 {
                canvas.mouseDragged(with: try event(.leftMouseDragged, CGFloat(step) / 1000))
                XCTAssertTrue(canvas.isPositioningArtwork, "The texture transform must update synchronously with every pointer event")
                XCTAssertEqual(controller.previewRequest, generation + 1, "Only invalidate stale work once; never enqueue work during the drag")
                XCTAssertTrue(canvas.image === initialImage, "The cached bitmap must remain unchanged during the gesture")
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            print("[DragPreview] format=\(format) backgroundPan=\(pan) 120-events-ms=\(elapsed * 1000)")
            XCTAssertLessThan(elapsed, 0.1, "120 transforms should cost less than 100ms total")
            var finalRect = canvas.positionedDeviceRect
            canvas.mouseUp(with: try event(.leftMouseUp, 0.12))
            XCTAssertEqual(controller.previewRequest, generation + 2, "Mouse-up enqueues one final render")
            XCTAssertTrue(canvas.isPositioningArtwork, "Keep the final layer position visible while encoding")
            // A second gesture can begin before the previous final encode completes.
            canvas.mouseDown(with: try event(.leftMouseDown, 0.12))
            canvas.mouseDragged(with: try event(.leftMouseDragged, 0.14))
            XCTAssertEqual(controller.previewRequest, generation + 3)
            finalRect = canvas.positionedDeviceRect
            try await Task.sleep(nanoseconds: 80_000_000)
            XCTAssertTrue(canvas.image === initialImage, "An obsolete completion must not replace live layers during the next gesture")
            XCTAssertTrue(canvas.isPositioningArtwork)
            canvas.mouseUp(with: try event(.leftMouseUp, 0.14))
            XCTAssertEqual(controller.previewRequest, generation + 4)
            for _ in 0..<2000 where canvas.image === initialImage { try await Task.sleep(nanoseconds: 5_000_000) }
            XCTAssertFalse(canvas.isPositioningArtwork)
            XCTAssertFalse(canvas.image === initialImage)
            let saved = try CompositionStore(legacy: store).load()
            if pan { XCTAssertNotEqual(saved.backgroundX, settings.backgroundX) }
            else { XCTAssertEqual(saved.deviceX, settings.deviceX + 0.14, accuracy: 0.00001) }
            let expected = try CompositionRenderer.render(ImageInput(url: source), settings: saved, preparePreviewLayers: true)
            XCTAssertEqual(finalRect, try XCTUnwrap(expected.previewLayers).deviceRect(settings: saved))
            controller.copyCurrent(nil)
            XCTAssertEqual(board.data(forType: .png), try (format == .png ? CompositionRenderer.data(expected.image, settings: saved) : FrameRenderer.pngData(expected.image)), "Copy must contain the final composition with the existing PNG/JPEG contract")
        }
    }
    @MainActor func testPendingReplacementCannotBeCancelledByDraggingStaleArtwork() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-pending-drag-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = SettingsStore(url: directory.appendingPathComponent("settings.json"))
        var settings = CompositionSettings(); settings.mode = .background; settings.background = .solid
        try CompositionStore(legacy: store).save(settings)
        let controller = MainWindowController(store: store, preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window)
        defer { window.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap { descendants($0) } }
        let root = try XCTUnwrap(window.contentView)
        let canvas = try XCTUnwrap(descendants(root).compactMap { $0 as? CanvasSurface }.first)
        let inspector = try XCTUnwrap(descendants(root).compactMap { $0 as? CompositionInspector }.first)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FraloApp/Development/Fixtures/03-journal.png")
        controller.importURLs([source])
        for _ in 0..<500 where canvas.image == nil { try await Task.sleep(nanoseconds: 10_000_000) }
        let initial = try XCTUnwrap(canvas.image)
        inspector.devicePicker.choose(1)
        let generation = controller.previewRequest
        XCTAssertFalse(canvas.allowsPositioning, "Old pixels are not a prepared layer set for the new device")
        let point = canvas.convert(CGPoint(x: canvas.imageRect.midX, y: canvas.imageRect.midY), to: nil)
        func event(_ type: NSEvent.EventType, _ offset: CGFloat) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: point.x + offset, y: point.y), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, 0))
        canvas.mouseDragged(with: try event(.leftMouseDragged, 80))
        canvas.onDrag?(CGPoint(x: 0.1, y: 0)) // A stale callback must be rejected by the owner too.
        canvas.mouseUp(with: try event(.leftMouseUp, 80))
        XCTAssertEqual(controller.previewRequest, generation, "Dragging old pixels must not cancel the pending replacement")
        XCTAssertEqual(try CompositionStore(legacy: store).load().deviceX, 0)
        for _ in 0..<500 where canvas.image === initial { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(canvas.image === initial); XCTAssertTrue(canvas.allowsPositioning)
        XCTAssertFalse(canvas.isPositioningArtwork)
    }

    /// Opt-in visible-window cadence probe. Run separately from the test suite and UI QA.
    @MainActor func testVisibleDragCadence() async throws {
        guard let reportPath = ProcessInfo.processInfo.environment["FRALO_LIVE_DRAG_REPORT"] else {
            throw XCTSkip("Opt-in desktop performance probe")
        }
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SettingsStore(url: root.appendingPathComponent("settings.json"))
        var settings = CompositionSettings(); settings.mode = .background; settings.background = .sage
        settings.pngLossless = false; settings.pngQuality = 0.345; settings.backgroundShadow = .strong
        try CompositionStore(legacy: store).save(settings)
        let suite = "fralo-cadence-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MainWindowController(store: store, preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); window.isReleasedWhenClosed = false
        defer { window.close() }
        window.title = "Fralo Drag Cadence QA"; controller.showWindow(nil); app.activate(ignoringOtherApps: true)
        func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap { descendants($0) } }
        let canvas = try XCTUnwrap(descendants(try XCTUnwrap(window.contentView)).compactMap { $0 as? CanvasSurface }.first)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FraloApp/Development/Fixtures/03-journal.png")
        controller.importURLs([fixture])
        for _ in 0..<2000 where canvas.image == nil { try await Task.sleep(nanoseconds: 5_000_000) }
        _ = try XCTUnwrap(canvas.image)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let origin = canvas.convert(CGPoint(x: canvas.imageRect.midX, y: canvas.imageRect.midY), to: nil)
        func event(_ type: NSEvent.EventType, _ fraction: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: origin.x + fraction * canvas.imageRect.width, y: origin.y), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: event(.leftMouseDown, 0))
        let generation = controller.previewRequest
        var ticks: [Double] = [], presentedX: [CGFloat] = [], step = 0
        let finished = expectation(description: "Visible six-second drag")
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { timer in
            MainActor.assumeIsolated {
                step += 1
                ticks.append(ProcessInfo.processInfo.systemUptime)
                // Three round trips, ending at the initial position. No complete render until mouse-up.
                let fraction = CGFloat(sin(Double(step) * .pi / 60)) * 0.18
                canvas.mouseDragged(with: event(.leftMouseDragged, fraction))
                if let clip = canvas.layer?.sublayers?.last, let device = clip.sublayers?.dropFirst().first,
                   let presentation = device.presentation() { presentedX.append(presentation.frame.minX) }
                if step == 360 { timer.invalidate(); finished.fulfill() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        await fulfillment(of: [finished], timeout: 15)
        timer.invalidate()
        let renders = controller.previewRequest - generation - 1
        canvas.mouseUp(with: event(.leftMouseUp, 0))
        let intervals = zip(ticks.dropFirst(11), ticks.dropFirst(10)).map { ($0 - $1) * 1000 }.sorted()
        guard let maximum = intervals.last else { XCTFail("No frame samples recorded"); return }
        let allIntervals = zip(ticks.dropFirst(), ticks).map { ($0 - $1) * 1000 }
        let payload: [String: Any] = ["callbacks": ticks.count, "includingWarmupMaxMs": allIntervals.max() ?? 0, "medianMs": intervals[intervals.count / 2],
            "p95Ms": intervals[Int(Double(intervals.count - 1) * 0.95)], "maxMs": maximum,
            "intervalsOver50Ms": intervals.filter { $0 > 50 }.count,
            "presentationSamples": presentedX.count, "distinctPresentationPositions": Set(presentedX.map { Int($0.rounded()) }).count,
            "rendersDuringGesture": renders, "limits": "Visible AppKit timer/event/presentation-layer cadence, not physical display scanout or hardware FPS measurement."]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: reportPath))
        print("[VisibleDragCadence] \(payload)")
        XCTAssertEqual(ticks.count, 360); XCTAssertEqual(renders, 0)
        XCTAssertGreaterThan(Set(presentedX.map { Int($0.rounded()) }).count, 50, "The presentation layer must move throughout the held gesture")
        XCTAssertLessThan(intervals[Int(Double(intervals.count - 1) * 0.95)], 35)
        XCTAssertLessThan(maximum, 100, "No 1–2 second pauses during a held drag")
        try await Task.sleep(nanoseconds: 2_000_000_000)
    }

}
