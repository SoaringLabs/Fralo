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
        let full = try FrameRenderer.render(input, settings: RenderSettings())
        let preview = try FrameRenderer.render(input, settings: RenderSettings(), maxDimension: 120)
        XCTAssertEqual(full.plan.pixelSize, preview.plan.pixelSize)
        XCTAssertLessThanOrEqual(max(preview.image.width, preview.image.height), 121)
    }
    func testSettingsRoundTripDefaultsAndValidation() throws {
        let store = SettingsStore(url: folder.appendingPathComponent("settings.json"))
        XCTAssertEqual(try store.load(), RenderSettings())
        let saved = RenderSettings(model: .iPhone16Pro, orientation: .landscape)
        try store.save(saved); XCTAssertEqual(try store.load(), saved)
        var unsupported = RenderSettings(); unsupported.schemaVersion = 2
        XCTAssertThrowsError(try store.save(unsupported))
        // Files written before transparent padding was removed still load.
        try Data(#"{"schemaVersion":1,"model":"iphone-16-pro","orientation":"landscape","padding":24}"#.utf8).write(to: store.url)
        XCTAssertEqual(try store.load(), saved)
        try Data("broken".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load())
    }
    func testBatchContinuesPastBadInputAndDefaultsToSkippingCollisions() throws {
        let good = try source(), bad = ImageInput(data: Data("broken".utf8), name: "broken.png")
        let report = try BatchExporter.run(inputs: [good, bad], settings: RenderSettings(), directory: folder)
        XCTAssertEqual(report.succeeded, 1); XCTAssertEqual(report.failed, 1)
        let before = try Data(contentsOf: folder.appendingPathComponent("screen-fralo.png"))
        let repeatReport = try BatchExporter.run(inputs: [good], settings: RenderSettings(model: .iPhone16Pro), directory: folder)
        XCTAssertEqual(repeatReport.skipped, 1)
        XCTAssertEqual(before, try Data(contentsOf: folder.appendingPathComponent("screen-fralo.png")))
        let replaced = try BatchExporter.run(inputs: [good], settings: RenderSettings(model: .iPhone16Pro), directory: folder, collisionPolicy: .replace)
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
        let report = try BatchExporter.run(inputs: [ImageInput(url: url)], settings: RenderSettings(), directory: folder, collisionPolicy: .replace, outputNames: ["original.png"])
        XCTAssertEqual(report.failed, 1); XCTAssertEqual(before, try Data(contentsOf: url))
    }

    func testTimestampedNamesShareLocalTimeAndPreserveSourceStems() throws {
        let inputs = try [source(name: "首页 v2.png"), source(name: "首页 v2.jpg"), source(name: "settings.jpeg")]
        let date = Date(timeIntervalSince1970: 0), zone = try XCTUnwrap(TimeZone(secondsFromGMT: 8 * 3600))
        let png = BatchExporter.outputNames(for: inputs, date: date, timeZone: zone)
        XCTAssertEqual(png, ["fralo-首页 v2-19700101-080000.png", "fralo-首页 v2-19700101-080000-2.png", "fralo-settings-19700101-080000.png"])
        XCTAssertEqual(BatchExporter.outputNames(for: [inputs[0]], date: date, timeZone: zone)[0], png[0])
        XCTAssertEqual(BatchExporter.outputNames(for: inputs, format: .jpeg, date: date, timeZone: zone),
                       png.map { ($0 as NSString).deletingPathExtension + ".jpg" })
    }

    func testKeepBothNumbersRepeatedExportsAndPreservesExistingBytes() throws {
        let preferred = folder.appendingPathComponent("fralo-screen-19700101-080000.png")
        let existing = Data("existing file".utf8); try existing.write(to: preferred)
        let input = try source()
        for suffix in [2, 3] {
            let report = try BatchExporter.run(inputs: [input], settings: .init(), directory: folder,
                                              collisionPolicy: .keepBoth, outputNames: [preferred.lastPathComponent])
            XCTAssertEqual(report.succeeded, 1); XCTAssertEqual(report.skipped, 0)
            XCTAssertEqual(URL(fileURLWithPath: report.entries[0].output).lastPathComponent, "fralo-screen-19700101-080000-\(suffix).png")
            XCTAssertEqual(try Data(contentsOf: preferred), existing)
            XCTAssertNoThrow(try ImageInput(url: URL(fileURLWithPath: report.entries[0].output)).decode())
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 3, "No temporary files remain")
    }

    func testKeepBothPreservesSourceWhenItsNameIsChosenForOutput() throws {
        let input = try source(), url = folder.appendingPathComponent("original.png")
        try input.data!.write(to: url)
        let before = try Data(contentsOf: url)
        let report = try BatchExporter.run(inputs: [ImageInput(url: url)], settings: .init(), directory: folder,
                                          collisionPolicy: .keepBoth, outputNames: ["original.png"])
        XCTAssertEqual(report.succeeded, 1)
        XCTAssertEqual(URL(fileURLWithPath: report.entries[0].output).lastPathComponent, "original-2.png")
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testKeepBothTreatsExistingDirectoryAsOccupiedFileName() throws {
        let occupied = folder.appendingPathComponent("image.png", isDirectory: true)
        try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: false)
        let result = try BatchExporter.run(inputs: [source()], settings: .init(), directory: folder,
                                          collisionPolicy: .keepBoth, outputNames: ["image.png"])
        XCTAssertEqual(result.succeeded, 1)
        XCTAssertEqual(URL(fileURLWithPath: result.entries[0].output).lastPathComponent, "image-2.png")
        XCTAssertNoThrow(try ImageInput(url: URL(fileURLWithPath: result.entries[0].output)).decode())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: occupied.path), [])
    }

    func testAvailableNameSkipsDirectoriesDanglingSymlinksAndReservedBatchNames() throws {
        let target = folder.appendingPathComponent("image.png")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let link = folder.appendingPathComponent("image-2.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder.appendingPathComponent("missing"))
        XCTAssertEqual(BatchExporter.availableOutputURL(for: target, reservingFileNames: ["image-3.png"]).lastPathComponent, "image-4.png")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), folder.appendingPathComponent("missing").path)
    }

    func testKeepBothReservesOtherBatchNamesAndRetainsFailedInputReporting() throws {
        try Data("existing".utf8).write(to: folder.appendingPathComponent("same.png"))
        let input = try source(), bad = ImageInput(data: Data("bad".utf8), name: "broken.png")
        let report = try BatchExporter.run(inputs: [input, input, bad], settings: .init(), directory: folder,
                                          collisionPolicy: .keepBoth, outputNames: ["same.png", "same-2.png", "bad.png"])
        XCTAssertEqual(report.succeeded, 2); XCTAssertEqual(report.failed, 1)
        XCTAssertEqual(report.entries.prefix(2).map { URL(fileURLWithPath: $0.output).lastPathComponent }, ["same-3.png", "same-2.png"])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("same.png")), Data("existing".utf8))
    }

    func testConcurrentKeepBothExportsNeverReplaceEachOther() async throws {
        let input = try source(), directory = try XCTUnwrap(folder)
        let reports = try await withThrowingTaskGroup(of: ExportReport.self, returning: [ExportReport].self) { group in
            for _ in 0..<2 {
                group.addTask {
                    try BatchExporter.run(inputs: [input], settings: .init(), directory: directory,
                                          collisionPolicy: .keepBoth, outputNames: ["same.png"])
                }
            }
            var reports: [ExportReport] = []
            for try await report in group { reports.append(report) }
            return reports
        }
        XCTAssertTrue(reports.allSatisfy { $0.succeeded == 1 })
        XCTAssertEqual(Set(reports.flatMap { $0.entries.map(\.output) }).count, 2)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), ["same.png", "same-2.png"])
    }

    func testSingleExportCreatesFolderWithMatchingImageTimestamp() throws {
        let result = try BatchExporter.runInNewDirectory(inputs: [source()], settings: .init(), parentDirectory: folder,
                                                        date: Date(timeIntervalSince1970: 0), timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 28800)))
        XCTAssertEqual(result.directory.lastPathComponent, "fralo-19700101-080000")
        XCTAssertEqual(result.directory.deletingLastPathComponent().standardizedFileURL, folder.standardizedFileURL)
        XCTAssertEqual(result.report.succeeded, 1)
        XCTAssertEqual(URL(fileURLWithPath: result.report.entries[0].output).deletingLastPathComponent(), result.directory)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: result.directory.path), ["fralo-screen-19700101-080000.png"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["fralo-19700101-080000"])
    }

    func testEveryExportCreatesAnotherFolderAndPreservesEarlierContents() throws {
        let date = Date(timeIntervalSince1970: 0), zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let existing = folder.appendingPathComponent("fralo-19700101-000000")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
        let sentinel = existing.appendingPathComponent("keep.txt"), bytes = Data("preserve this export".utf8)
        try bytes.write(to: sentinel)
        for suffix in [2, 3] {
            let result = try BatchExporter.runInNewDirectory(inputs: [source()], settings: .init(), parentDirectory: folder, date: date, timeZone: zone)
            XCTAssertEqual(result.directory.lastPathComponent, "fralo-19700101-000000-\(suffix)")
            XCTAssertEqual(result.report.succeeded, 1)
            XCTAssertEqual(try Data(contentsOf: sentinel), bytes)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: existing.path), ["keep.txt"])
        }
    }

    func testExportFolderSkipsExistingFilesAndDanglingSymlinks() throws {
        let bytes = Data("keep".utf8), path = folder.appendingPathComponent("fralo-19700101-000000")
        try bytes.write(to: path)
        let link = folder.appendingPathComponent("fralo-19700101-000000-2")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder.appendingPathComponent("missing"))
        let result = try BatchExporter.runInNewDirectory(inputs: [source()], settings: .init(), parentDirectory: folder,
                                                        date: Date(timeIntervalSince1970: 0), timeZone: try XCTUnwrap(TimeZone(secondsFromGMT: 0)))
        XCTAssertEqual(result.directory.lastPathComponent, "fralo-19700101-000000-3")
        XCTAssertEqual(try Data(contentsOf: path), bytes)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), folder.appendingPathComponent("missing").path)
    }

    func testConcurrentExportsReceiveSeparateFolders() async throws {
        let input = try source(), parent = try XCTUnwrap(folder), zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let directories = try await withThrowingTaskGroup(of: URL.self, returning: [URL].self) { group in
            for _ in 0..<2 {
                group.addTask {
                    try BatchExporter.runInNewDirectory(inputs: [input], settings: .init(), parentDirectory: parent,
                                                        date: Date(timeIntervalSince1970: 0), timeZone: zone).directory
                }
            }
            var paths: [URL] = []
            for try await path in group { paths.append(path) }
            return paths
        }
        XCTAssertEqual(Set(directories.map(\.lastPathComponent)), ["fralo-19700101-000000", "fralo-19700101-000000-2"])
        for path in directories { XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: path.path).count, 1) }
    }

    func testNewFolderKeepsPartialSuccessAndCancelledOutputTogether() throws {
        let good = try source(), bad = ImageInput(data: Data("bad".utf8), name: "broken.png")
        let partial = try BatchExporter.runInNewDirectory(inputs: [good, bad], settings: .init(), parentDirectory: folder)
        XCTAssertEqual(partial.report.succeeded, 1); XCTAssertEqual(partial.report.failed, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: partial.directory.path).count, 1)
        let token = CancellationToken()
        let cancelled = try BatchExporter.runInNewDirectory(inputs: [good, good], settings: .init(), parentDirectory: folder, cancellation: token) {
            if $0.completed == 1 { token.cancel() }
        }
        XCTAssertTrue(cancelled.report.cancelled); XCTAssertEqual(cancelled.report.succeeded, 1); XCTAssertEqual(cancelled.report.unprocessed, 1)
        XCTAssertNotEqual(cancelled.directory, partial.directory)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cancelled.directory.path).count, 1)
        XCTAssertEqual(URL(fileURLWithPath: cancelled.report.entries[0].output).deletingLastPathComponent(), cancelled.directory)
    }

    func testInvalidExportDoesNotCreateAFolder() throws {
        XCTAssertThrowsError(try BatchExporter.runInNewDirectory(inputs: [], settings: .init(), parentDirectory: folder))
        XCTAssertThrowsError(try BatchExporter.runInNewDirectory(inputs: [source()], settings: .init(), parentDirectory: folder, outputNames: ["../escape.png"]))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [])
        let file = folder.appendingPathComponent("file"), bytes = Data("not a directory".utf8)
        try bytes.write(to: file)
        XCTAssertThrowsError(try BatchExporter.runInNewDirectory(inputs: [source()], settings: .init(), parentDirectory: file))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
}
