import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class ThumbnailPipelineTests: XCTestCase {
    private func image() -> CGImage {
        CGContext(data: nil, width: 8, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }

    @MainActor private func request(_ pipeline: ThumbnailPipeline, _ inputs: [ImageInput], _ settings: CompositionSettings = CompositionSettings()) async -> [Result<ThumbnailPipeline.Thumbnail, Error>] {
        let done = expectation(description: "thumbnail request")
        var results: [Result<ThumbnailPipeline.Thumbnail, Error>] = []
        pipeline.request(inputs, settings: settings) { _, result in
            results.append(result)
            if results.count == inputs.count { done.fulfill() }
        }
        await fulfillment(of: [done], timeout: 5)
        return results
    }

    @MainActor func testRapidSwitchSkipsObsoleteBatchAndSuppressesItsCallbacks() async throws {
        let started = expectation(description: "first render started"), done = expectation(description: "latest render finished")
        let release = DispatchSemaphore(value: 0), image = image()
        let lock = NSLock(); var renders = 0
        let pipeline = ThumbnailPipeline { _, _ in
            lock.lock(); renders += 1; let count = renders; lock.unlock()
            if count == 1 { started.fulfill(); _ = release.wait(timeout: .now() + 5) }
            return .init(image: image, pixelSize: CGSize(width: 8, height: 16))
        }
        let old = (0..<500).map { ImageInput(data: Data(), name: "\($0).png") }
        pipeline.request(old, settings: CompositionSettings()) { _, _ in XCTFail("An obsolete result reached the UI") }
        await fulfillment(of: [started], timeout: 5)
        var settings = CompositionSettings(); settings.display = .tablet
        pipeline.request(old, settings: settings) { _, _ in XCTFail("The intermediate batch should never render") }
        settings.display = .browser
        pipeline.request([old[499]], settings: settings) { id, result in
            XCTAssertEqual(id, old[499].id)
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            done.fulfill()
        }
        release.signal()
        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(renders, 2, "At most the in-flight old image and the latest image should render, not 1001 images")
    }

    @MainActor func testCacheReusesShapesAndAppendButIgnoresBackgroundSettings() async throws {
        let image = image(); var renders = 0
        let pipeline = ThumbnailPipeline { _, settings in
            renders += 1
            XCTAssertEqual(settings.mode, .transparent); XCTAssertEqual(settings.transparentShadow, .none)
            XCTAssertEqual(settings.deviceOpacity, 1)
            return .init(image: image, pixelSize: CGSize(width: 8, height: 16))
        }
        let a = ImageInput(data: Data(), name: "a.png"), b = ImageInput(data: Data(), name: "b.png")
        let initial = CompositionSettings()
        _ = await request(pipeline, [a], initial)
        var landscape = initial; landscape.orientation = .landscape
        _ = await request(pipeline, [a], landscape)
        _ = await request(pipeline, [a, b], initial)
        XCTAssertEqual(renders, 3, "Returning to phone and appending must reuse existing images")
        var background = initial; background.mode = .background; background.deviceOpacity = 0.2
        background.transparentShadow = .strong; background.browser = .chrome; background.windowRatio = .wide
        _ = await request(pipeline, [a, b], background)
        XCTAssertEqual(renders, 3, "Inactive browser and background options do not change phone thumbnails")
    }

    @MainActor func testCacheHonorsCountAndByteLimitsAndDoesNotCacheFailures() async throws {
        let image = image(), cost = image.bytesPerRow * image.height
        let a = ImageInput(data: Data(), name: "a.png"), b = ImageInput(data: Data(), name: "b.png")
        for (costLimit, countLimit) in [(cost * 10, 1), (cost, 10), (0, 10)] {
            var renders = 0
            let pipeline = ThumbnailPipeline(costLimit: costLimit, countLimit: countLimit) { _, _ in
                renders += 1; return .init(image: image, pixelSize: CGSize(width: 8, height: 16))
            }
            _ = await request(pipeline, [a]); _ = await request(pipeline, [b]); _ = await request(pipeline, [a])
            XCTAssertEqual(renders, 3)
        }
        var attempts = 0
        let pipeline = ThumbnailPipeline { _, _ in
            attempts += 1
            if attempts == 1 { throw FraloError.message("invalid image") }
            return .init(image: image, pixelSize: CGSize(width: 8, height: 16))
        }
        let failed = await request(pipeline, [a]); XCTAssertThrowsError(try failed[0].get())
        let recovered = await request(pipeline, [a]); XCTAssertNoThrow(try recovered[0].get())
        _ = await request(pipeline, [a]); XCTAssertEqual(attempts, 2)
    }

    @MainActor func testChangedFileInvalidatesCachedThumbnail() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fralo-thumbnail-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1]).write(to: url)
        let image = image(); var renders = 0
        let pipeline = ThumbnailPipeline { _, _ in
            renders += 1; return .init(image: image, pixelSize: CGSize(width: 8, height: 16))
        }
        _ = await request(pipeline, [ImageInput(url: url)])
        try Data([1, 2]).write(to: url)
        _ = await request(pipeline, [ImageInput(url: url)])
        XCTAssertEqual(renders, 2)
    }

    @MainActor func testRealThumbnailsMatchExistingRendererAcrossDeviceShapes() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FraloApp/Development/Fixtures/03-journal.png")
        let input = ImageInput(url: fixture), pipeline = ThumbnailPipeline()
        var styles: [CompositionSettings] = []
        for model in CompositionSettings.phoneModels {
            for orientation in Orientation.allCases {
                var s = CompositionSettings(); s.phoneModel = model; s.orientation = orientation; styles.append(s)
            }
        }
        for orientation in Orientation.allCases {
            var s = CompositionSettings(); s.display = .tablet; s.orientation = orientation; styles.append(s)
        }
        for browser in BrowserStyle.allCases {
            for ratio in WindowRatio.allCases {
                var s = CompositionSettings(); s.display = .browser; s.browser = browser; s.windowRatio = ratio; styles.append(s)
            }
        }
        for style in styles {
            let values = await request(pipeline, [input], style), value = try XCTUnwrap(values.first).get()
            let expected = try CompositionRenderer.render(input, settings: style, maxDimension: 180).image
            XCTAssertEqual(value.image.width, expected.width); XCTAssertEqual(value.image.height, expected.height)
            XCTAssertEqual(value.image.dataProvider?.data as Data?, expected.dataProvider?.data as Data?, "\(ThumbnailPipeline.styleKey(style)) must preserve the previous raster output")
        }
    }

    @MainActor func testCancelSuppressesInFlightResult() async throws {
        let started = expectation(description: "render started"), released = expectation(description: "render released")
        let release = DispatchSemaphore(value: 0), image = image()
        let pipeline = ThumbnailPipeline { _, _ in
            started.fulfill(); _ = release.wait(timeout: .now() + 5); released.fulfill()
            return .init(image: image, pixelSize: CGSize(width: 8, height: 16))
        }
        pipeline.request([ImageInput(data: Data(), name: "a.png")], settings: CompositionSettings()) { _, _ in XCTFail("Cancelled batch published") }
        await fulfillment(of: [started], timeout: 5)
        pipeline.cancel(); release.signal()
        await fulfillment(of: [released], timeout: 5)
        // Drain the main queue after the worker's publication point.
        try await Task.sleep(nanoseconds: 20_000_000)
    }

    @MainActor func testUndoRedoAndBatchUndoRestoreCurrentThumbnailStyle() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-thumbnail-undo-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); window.isReleasedWhenClosed = false
        defer { controller.newBatch(nil); window.close() }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView), list = try XCTUnwrap(root.left.body as? BatchList)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let inspector = try XCTUnwrap(descendants(root).compactMap { $0 as? CompositionInspector }.first)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FraloApp/Development/Fixtures/03-journal.png")
        func waitForImage(landscape: Bool) async throws {
            for _ in 0..<1000 {
                if let size = list.entries.first?.image?.size, (size.width > size.height) == landscape { return }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            XCTFail("Thumbnail did not adopt the current orientation")
        }
        controller.importURLs([fixture]); try await waitForImage(landscape: false)
        var settings = inspector.settings; settings.orientation = .landscape
        inspector.onChange?(settings); try await waitForImage(landscape: true)
        controller.undoChange(nil); try await waitForImage(landscape: false)
        controller.redoChange(nil); try await waitForImage(landscape: true)
        controller.newBatch(nil); XCTAssertTrue(list.entries.isEmpty)
        controller.undoChange(nil); try await waitForImage(landscape: true)
        controller.removeSelected(nil); XCTAssertTrue(list.entries.isEmpty)
        try await Task.sleep(nanoseconds: 20_000_000); XCTAssertTrue(list.entries.isEmpty)
    }

    @MainActor func testThumbnailArrivalPreservesScrollPositionAndSelection() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "fralo-thumbnails-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FraloApp/Development/Fixtures/03-journal.png")
        let inputs = try (0..<40).map { index -> URL in
            let url = directory.appendingPathComponent("image-\(index).png")
            try FileManager.default.copyItem(at: fixture, to: url); return url
        }
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); window.isReleasedWhenClosed = false
        defer { controller.newBatch(nil); window.close() }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let list = try XCTUnwrap(root.left.body as? BatchList)
        controller.importURLs(inputs); root.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(list.documentView as? NSTableView)
        table.scrollRowToVisible(39)
        let origin = list.contentView.bounds.origin
        XCTAssertGreaterThan(origin.y, 0)
        for _ in 0..<1000 where list.entries.contains(where: { $0.image == nil }) { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(list.entries.allSatisfy { $0.image != nil })
        XCTAssertEqual(list.contentView.bounds.origin.y, origin.y, accuracy: 1, "Background thumbnails must not scroll back to the selected row")
        XCTAssertEqual(list.selectedIndex, 0)
    }
}
