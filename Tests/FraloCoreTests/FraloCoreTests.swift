import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import FraloCore

final class FraloCoreTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("fralo-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    private func source(width: Int = 132, height: Int = 286, name: String = "screen.png") throws -> ImageInput {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let i = (y * width + x) * 4
            pixels[i] = y < height / 2 ? 240 : 20
            pixels[i + 1] = x < width / 2 ? 40 : 180
            pixels[i + 2] = y < height / 2 ? 20 : 240
        } }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return ImageInput(data: try FrameRenderer.pngData(image), name: name)
    }
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        let bytes = CFDataGetBytePtr(image.dataProvider!.data!)!
        let i = y * image.bytesPerRow + x * 4
        return Array(UnsafeBufferPointer(start: bytes + i, count: 4))
    }

    func testSourceIsUprightAndUndistortedInBothDirections() throws {
        for direction in Orientation.allCases {
            let input = try source(width: direction == .portrait ? 132 : 286, height: direction == .portrait ? 286 : 132)
            let result = try FrameRenderer.render(input, settings: RenderSettings(orientation: direction))
            let screen = result.plan.screen
            let upper = pixel(result.image, Int(screen.minX + screen.width * 0.3), Int(screen.minY + screen.height * 0.3))
            let lower = pixel(result.image, Int(screen.minX + screen.width * 0.3), Int(screen.minY + screen.height * 0.75))
            XCTAssertGreaterThan(upper[0], upper[2], "top half should remain red in \(direction)")
            XCTAssertGreaterThan(lower[2], lower[0], "bottom half should remain blue in \(direction)")
            XCTAssertEqual(upper[3], 255)
        }
    }
    func testAllTwelveModelDirectionCombinationsHaveTightTransparentBounds() throws {
        for model in DeviceModel.allCases { for direction in Orientation.allCases {
            let size = direction == .portrait ? CGSize(width: model.screenWidth, height: model.screenHeight) : CGSize(width: model.screenHeight, height: model.screenWidth)
            let input = try source(width: Int(size.width / 10), height: Int(size.height / 10))
            let result = try FrameRenderer.render(input, settings: RenderSettings(model: model, orientation: direction))
            XCTAssertEqual(pixel(result.image, 0, 0)[3], 0)
            XCTAssertEqual(pixel(result.image, result.image.width - 1, result.image.height - 1)[3], 0)
            var minX = result.image.width, minY = result.image.height, maxX = 0, maxY = 0
            for y in 0..<result.image.height { for x in 0..<result.image.width {
                if pixel(result.image, x, y)[3] > 0 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
            } }
            XCTAssertLessThanOrEqual(minX, 1); XCTAssertLessThanOrEqual(minY, 1)
            XCTAssertLessThanOrEqual(result.image.width - 1 - maxX, 1); XCTAssertLessThanOrEqual(result.image.height - 1 - maxY, 1)
        } }
    }
    func testPaddingAddsExactlyTransparentPixelsAndPreservesContent() throws {
        let input = try source()
        let zero = try FrameRenderer.render(input, settings: RenderSettings())
        let padded = try FrameRenderer.render(input, settings: RenderSettings(padding: 17))
        XCTAssertEqual(padded.image.width, zero.image.width + 34); XCTAssertEqual(padded.image.height, zero.image.height + 34)
        for y in 0..<padded.image.height {
            XCTAssertEqual(pixel(padded.image, 0, y)[3], 0); XCTAssertEqual(pixel(padded.image, 16, y)[3], 0)
        }
        let x = zero.image.width / 2, y = zero.image.height / 2
        XCTAssertEqual(pixel(zero.image, x, y), pixel(padded.image, x + 17, y + 17))
    }
    func testOriginalResolutionIsNotReducedToFrameTemplate() throws {
        let sourceSize = CGSize(width: 2640, height: 5736)
        let plan = try RenderPlan(sourceSize: sourceSize, settings: RenderSettings())
        XCTAssertEqual(plan.screen.width, sourceSize.width, accuracy: 0.001)
        XCTAssertEqual(plan.screen.height, sourceSize.height, accuracy: 0.001)
        XCTAssertGreaterThan(plan.pixelSize.width, sourceSize.width)
    }
    func testLargeAspectMismatchRequiresAdjustmentButMinorCropWorks() throws {
        XCTAssertThrowsError(try RenderPlan(sourceSize: CGSize(width: 1000, height: 1000), settings: RenderSettings()))
        XCTAssertNoThrow(try RenderPlan(sourceSize: CGSize(width: 1320, height: 2850), settings: RenderSettings()))
    }
    func testJPEGImportHonorsExifOrientation() throws {
        let png = try source(width: 286, height: 132)
        let raw = try png.decode()
        let jpeg = NSMutableData()
        let destination = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, raw, [kCGImagePropertyOrientation: 6, kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFOrientation: 6], kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let input = ImageInput(data: jpeg as Data, name: "oriented.jpg")
        XCTAssertEqual(try input.dimensions(), CGSize(width: 132, height: 286))
        let decoded = try input.decode()
        XCTAssertEqual(decoded.width, 132); XCTAssertEqual(decoded.height, 286)
        XCTAssertNoThrow(try FrameRenderer.render(input, settings: RenderSettings()))
    }
    func testPreviewAndFullRenderUseSamePlan() throws {
        let input = try source(width: 264, height: 573)
        let full = try FrameRenderer.render(input, settings: RenderSettings(padding: 6))
        let preview = try FrameRenderer.render(input, settings: RenderSettings(padding: 6), maxDimension: 120)
        XCTAssertEqual(full.plan.pixelSize, preview.plan.pixelSize)
        XCTAssertLessThanOrEqual(max(preview.image.width, preview.image.height), 121)
    }
    func testSettingsRoundTripDefaultsAndValidation() throws {
        let store = SettingsStore(url: folder.appendingPathComponent("settings.json"))
        XCTAssertEqual(try store.load(), RenderSettings())
        let saved = RenderSettings(model: .iPhone16Pro, orientation: .landscape, padding: 24)
        try store.save(saved); XCTAssertEqual(try store.load(), saved)
        XCTAssertThrowsError(try store.save(RenderSettings(padding: -1)))
        try Data("broken".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load())
    }
    func testBatchContinuesPastBadInputAndDefaultsToSkippingCollisions() throws {
        let good = try source(), bad = ImageInput(data: Data("broken".utf8), name: "broken.png")
        let report = try BatchExporter.run(inputs: [good, bad], settings: RenderSettings(), directory: folder)
        XCTAssertEqual(report.succeeded, 1); XCTAssertEqual(report.failed, 1)
        let before = try Data(contentsOf: folder.appendingPathComponent("screen-fralo.png"))
        let repeatReport = try BatchExporter.run(inputs: [good], settings: RenderSettings(padding: 20), directory: folder)
        XCTAssertEqual(repeatReport.skipped, 1)
        XCTAssertEqual(before, try Data(contentsOf: folder.appendingPathComponent("screen-fralo.png")))
        let replaced = try BatchExporter.run(inputs: [good], settings: RenderSettings(padding: 20), directory: folder, overwrite: true)
        XCTAssertEqual(replaced.succeeded, 1); XCTAssertNotEqual(before, try Data(contentsOf: folder.appendingPathComponent("screen-fralo.png")))
        let decoded = try JSONDecoder().decode(ExportReport.self, from: JSONEncoder().encode(report))
        XCTAssertEqual(decoded.failed, 1)
    }
    func testCancellationKeepsCompletedOutputAndReportsUnprocessed() throws {
        let inputs = try (0..<10).map { try source(name: "screen-\($0).png") }
        let token = CancellationToken()
        let result = try BatchExporter.run(inputs: inputs, settings: RenderSettings(), directory: folder, cancellation: token) {
            if $0.completed == 1 { token.cancel() }
        }
        XCTAssertTrue(result.cancelled); XCTAssertEqual(result.succeeded, 1); XCTAssertEqual(result.unprocessed, 9)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.entries[0].output))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 1)
    }
    func testNamesDisambiguateDifferentInputsAndCollectorIsShallow() throws {
        let first = try source(name: "same.png"), second = try source(name: "same.jpg")
        XCTAssertEqual(BatchExporter.outputNames(for: [first, second]), ["same-fralo.png", "same-fralo-2.png"])
        let root = folder.appendingPathComponent("root"), nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try first.data!.write(to: root.appendingPathComponent("one.png"))
        try first.data!.write(to: nested.appendingPathComponent("two.png"))
        let collected = try InputCollector.collect([root, root.appendingPathComponent("one.png")])
        XCTAssertEqual(collected.count, 1)
    }
    func testExplicitOverwriteStillProtectsOriginalInput() throws {
        let input = try source(), url = folder.appendingPathComponent("original.png")
        try input.data!.write(to: url)
        let before = try Data(contentsOf: url)
        let report = try BatchExporter.run(inputs: [ImageInput(url: url)], settings: RenderSettings(), directory: folder, overwrite: true, outputNames: ["original.png"])
        XCTAssertEqual(report.failed, 1); XCTAssertEqual(before, try Data(contentsOf: url))
    }
}
