import XCTest
import CoreGraphics
import ImageIO
@testable import FraloCore

final class CompositionTests: XCTestCase {
    private func input() throws -> ImageInput {
        let c = try XCTUnwrap(CompositionRenderer.bitmap(CGSize(width: 400, height: 100)))
        c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 400, height: 100))
        c.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 15, height: 100))
        c.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)); c.fill(CGRect(x: 385, y: 0, width: 15, height: 100))
        return ImageInput(data: try FrameRenderer.pngData(XCTUnwrap(c.makeImage())), name: "wide.png")
    }
    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let c = try XCTUnwrap(CompositionRenderer.bitmap(CGSize(width: image.width, height: image.height)))
        CompositionRenderer.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), context: c)
        let p = try XCTUnwrap(c.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: p, count: c.bytesPerRow * c.height))
    }
    func testAllShellsContainMismatchedSourceAndKeepBothEdges() throws {
        let source = try input()
        XCTAssertThrowsError(try FrameRenderer.render(source, settings: .init()), "Legacy CLI mismatch behavior stays explicit")
        for display in DisplayKind.allCases {
            for orientation in Orientation.allCases {
                for browser in BrowserStyle.allCases {
                    var s = CompositionSettings(); s.display = display; s.orientation = orientation; s.browser = browser
                    let result = try CompositionRenderer.render(source, settings: s)
                    let bytes = try pixels(result.image)
                    var red = 0, green = 0
                    for p in stride(from: 0, to: bytes.count - 3, by: 4) {
                        if bytes[p] > 220 && bytes[p+1] < 40 && bytes[p+2] < 40 { red += 1 }
                        if bytes[p+1] > 220 && bytes[p] < 40 && bytes[p+2] < 40 { green += 1 }
                    }
                    XCTAssertGreaterThan(red, 200, "\(display)/\(orientation)/\(browser) left edge cropped")
                    XCTAssertGreaterThan(green, 200, "\(display)/\(orientation)/\(browser) right edge cropped")
                }
            }
        }
    }
    func testOpacityBackgroundResourcesAndJPEGFill() throws {
        let source = try input(); var s = CompositionSettings(); s.deviceOpacity = 0.5
        var image = try CompositionRenderer.render(source, settings: s).image
        var bytes = try pixels(image)
        XCTAssertLessThanOrEqual(stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }.max()!, 129)
        s.mode = .background; s.deviceOpacity = 0; s.backgroundOpacity = 0.3
        for background: BackgroundKind in [.warm, .mist, .sage] {
            s.background = background
            let result = try CompositionRenderer.render(source, settings: s)
            XCTAssertEqual(result.pixelSize, s.canvas.size)
            bytes = try pixels(result.image); XCTAssertEqual(Int(bytes[3]), 77, accuracy: 2)
        }
        s.mode = .transparent; s.format = .jpeg; s.jpegFill = ArtworkColor(1, 0, 0)
        image = try CompositionRenderer.render(source, settings: s).image
        let data = try CompositionRenderer.data(image, settings: s)
        let decoded = try ImageInput(data: data, name: "test.jpg").decode()
        bytes = try pixels(decoded)
        XCTAssertEqual(bytes[3], 255); XCTAssertGreaterThan(bytes[0], 245); XCTAssertLessThan(bytes[1], 10)
        let png = try FrameRenderer.pngData(image)
        XCTAssertEqual(try pixels(ImageInput(data: png, name: "copy.png").decode())[3], 0, "PNG copy retains transparency independently of JPEG")
    }
    func testCompositionExportKeepsFailureSkipCancelAndSourceProtection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = try input(), bad = ImageInput(data: Data([0,1,2]), name: "bad.png")
        var s = CompositionSettings(); s.display = .browser; s.format = .jpeg
        let report = try BatchExporter.run(inputs: [source, bad], settings: .init(), directory: root, composition: s)
        XCTAssertEqual(report.succeeded, 1); XCTAssertEqual(report.failed, 1); XCTAssertEqual(report.composition, s)
        XCTAssertTrue(report.entries[0].output.hasSuffix(".jpg"))
        let roundtrip = try JSONDecoder().decode(ExportReport.self, from: JSONEncoder().encode(report)); XCTAssertEqual(roundtrip.composition, s)
        let again = try BatchExporter.run(inputs: [source], settings: .init(), directory: root, composition: s); XCTAssertEqual(again.skipped, 1)
        let token = CancellationToken(); token.cancel()
        let cancelled = try BatchExporter.run(inputs: [source], settings: .init(), directory: root, cancellation: token, composition: s)
        XCTAssertTrue(cancelled.cancelled); XCTAssertEqual(cancelled.unprocessed, 1)
        let file = root.appendingPathComponent("source.png"), original = try FrameRenderer.pngData(source.decode())
        try original.write(to: file)
        let protected = try BatchExporter.run(inputs: [ImageInput(url: file)], settings: .init(), directory: root, overwrite: true, outputNames: [file.lastPathComponent], composition: s)
        XCTAssertEqual(protected.failed, 1); XCTAssertEqual(try Data(contentsOf: file), original)
    }
    func testOutputRatiosAndTransparentShadowExtent() throws {
        let source = try input()
        var s = CompositionSettings(); s.display = .browser
        for ratio in WindowRatio.allCases {
            s.windowRatio = ratio
            let image = try CompositionRenderer.render(source, settings: s).image
            XCTAssertEqual(Double(image.width) / Double(image.height), ratio.ratio, accuracy: 0.01)
        }
        s.mode = .background; s.background = .solid
        for ratio in CanvasRatio.allCases {
            s.canvas = ratio
            let image = try CompositionRenderer.render(source, settings: s).image
            XCTAssertEqual(image.width, Int(ratio.size.width)); XCTAssertEqual(image.height, Int(ratio.size.height))
        }
        s.mode = .transparent; s.transparentShadow = .none
        let tight = try CompositionRenderer.render(source, settings: s).image
        s.transparentShadow = .strong
        let shadow = try CompositionRenderer.render(source, settings: s).image
        XCTAssertGreaterThan(shadow.width, tight.width); XCTAssertGreaterThan(shadow.height, tight.height)
        XCTAssertEqual(try pixels(shadow)[3], 0, "Shadow needs a transparent outer edge rather than a clipped crop")
    }
    func testPreviewReductionKeepsRealOutputSizeAndBackgroundPanBounds() throws {
        for display in DisplayKind.allCases {
            var s = CompositionSettings(); s.display = display; s.transparentShadow = .soft
            let full = try CompositionRenderer.render(input(), settings: s)
            let preview = try CompositionRenderer.render(input(), settings: s, maxDimension: 120)
            XCTAssertEqual(preview.pixelSize, full.pixelSize)
            XCTAssertLessThanOrEqual(max(preview.image.width, preview.image.height), 120)
        }
        var s = CompositionSettings(); s.mode = .background; s.backgroundScale = 2
        CompositionRenderer.panBackground(&s, delta: CGPoint(x: 0.1, y: 0.1), imageSize: s.canvas.size)
        XCTAssertEqual(s.backgroundX, 0.2, accuracy: 0.001); XCTAssertEqual(s.backgroundY, 0.2, accuracy: 0.001)
        CompositionRenderer.panBackground(&s, delta: CGPoint(x: 10, y: -10), imageSize: s.canvas.size)
        XCTAssertEqual(s.backgroundX, 1); XCTAssertEqual(s.backgroundY, -1)
    }
    func testCompositionSettingsMigrateWithoutChangingLegacyCLIFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = SettingsStore(url: root.appendingPathComponent("settings.json"))
        let old = RenderSettings(model: .iPhone16Pro, orientation: .landscape, padding: 42)
        try legacy.save(old); let bytes = try Data(contentsOf: legacy.url)
        let store = CompositionStore(legacy: legacy); var s = try store.load()
        XCTAssertEqual(s.orientation, .landscape); s.mode = .background; try store.save(s)
        XCTAssertEqual(try store.load(), s); XCTAssertEqual(try Data(contentsOf: legacy.url), bytes); XCTAssertEqual(try legacy.load(), old)
        s.deviceOpacity = .nan; XCTAssertThrowsError(try store.save(s))
    }
}
