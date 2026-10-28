import XCTest
import CoreGraphics
import ImageIO
@testable import FraloCore

final class CompositionTests: XCTestCase {
    func testPackagedResourcesResolveInsideAppBeforeBuildFallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let hostURL = directory.appendingPathComponent("Host.app")
        let resources = hostURL.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: String] = ["CFBundleIdentifier": "app.fralo.resource-test", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: hostURL.appendingPathComponent("Contents/Info.plist"))
        let copied = resources.appendingPathComponent("Fralo_FraloCore.bundle")
        try FileManager.default.copyItem(at: CompositionRenderer.resourceBundle().bundleURL, to: copied)
        let host = try XCTUnwrap(Bundle(url: hostURL))
        let resolved = CompositionRenderer.resourceBundle(in: host)
        XCTAssertEqual(resolved.bundleURL.standardizedFileURL, copied.standardizedFileURL)
        XCTAssertNotNil(resolved.url(forResource: "warm-gray", withExtension: "png", subdirectory: "Resources/Backgrounds"))
    }

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
        var bytes: [UInt8] = []; bytes.reserveCapacity(image.width * image.height * 4)
        for row in 0..<image.height {
            bytes.append(contentsOf: UnsafeBufferPointer(start: p + row * c.bytesPerRow, count: image.width * 4))
        }
        return bytes
    }
    private func solidInput(_ size: CGSize) throws -> ImageInput {
        let context = try XCTUnwrap(CompositionRenderer.bitmap(size))
        context.setFillColor(CGColor(srgbRed: 0.3, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        return ImageInput(data: try FrameRenderer.pngData(XCTUnwrap(context.makeImage())), name: "solid.png")
    }
    func testPreviewLayersKeepOffCanvasContentAndDoNotChangeFinalPixels() throws {
        let source = try input()
        for background in [BackgroundKind.solid, .gradient, .sage] {
            var settings = CompositionSettings(); settings.mode = .background; settings.background = background
            settings.deviceX = 0.9; settings.deviceY = -0.7; settings.backgroundScale = 2
            settings.deviceOpacity = 0.6; settings.backgroundOpacity = 0.5; settings.backgroundShadow = .strong
            let plain = try CompositionRenderer.render(source, settings: settings)
            let prepared = try CompositionRenderer.render(source, settings: settings, preparePreviewLayers: true)
            XCTAssertEqual(try FrameRenderer.pngData(plain.image), try FrameRenderer.pngData(prepared.image))
            let layers = try XCTUnwrap(prepared.previewLayers)
            let initial = layers.deviceRect(settings: settings)
            XCTAssertEqual(Int(initial.width), layers.device.width)
            XCTAssertEqual(Int(initial.height), layers.device.height)
            settings.deviceX = -0.2; settings.deviceY = 0.3; settings.backgroundX = 0.4
            let moved = layers.deviceRect(settings: settings)
            XCTAssertEqual(moved.minX - initial.minX, -1.1 * settings.canvas.size.width, accuracy: 0.0001)
            XCTAssertEqual(moved.minY - initial.minY, settings.canvas.size.height, accuracy: 0.0001)
            if background == .sage { XCTAssertGreaterThan(layers.backgroundRect(settings: settings).width, settings.canvas.size.width) }
        }
    }

    func testFixedDeviceSizesAndSilhouettesIgnoreSourceResolutionAndAspectRatio() throws {
        let sources = try [CGSize(width: 40, height: 10), CGSize(width: 1600, height: 400), CGSize(width: 100, height: 240), CGSize(width: 80, height: 80)].map(solidInput)
        for display in DisplayKind.allCases {
            for orientation in Orientation.allCases {
                for ratio in WindowRatio.allCases where display == .browser || ratio == .standard {
                    var settings = CompositionSettings(); settings.display = display; settings.orientation = orientation; settings.windowRatio = ratio
                    let portrait = display == .phone ? CGSize(width: 1530, height: 3036) : CGSize(width: 2400, height: 3200)
                    let browserSize: CGSize
                    switch ratio {
                    case .standard: browserSize = CGSize(width: 3000, height: 1875)
                    case .wide: browserSize = CGSize(width: 3000, height: 1688)
                    case .classic: browserSize = CGSize(width: 3000, height: 2250)
                    }
                    let base = display == .browser ? browserSize : orientation == .portrait ? portrait : CGSize(width: portrait.height, height: portrait.width)
                    for (shadow, margin): (ShadowStyle, CGFloat) in [(.none, 0), (.soft, 84), (.strong, 138)] {
                        settings.transparentShadow = shadow
                        var silhouette: [UInt8]?
                        for source in sources {
                            let result = try CompositionRenderer.render(source, settings: settings, maxDimension: 240)
                            XCTAssertEqual(result.pixelSize, CGSize(width: base.width + margin * 2, height: base.height + margin * 2))
                            XCTAssertEqual(result.previewReferenceSize, CGSize(width: base.width + 276, height: base.height + 276))
                            XCTAssertLessThanOrEqual(max(result.image.width, result.image.height), 240)
                            let bytes = try pixels(result.image)
                            let alpha = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
                            if let silhouette { XCTAssertEqual(alpha, silhouette, "Changing source pixels must not alter device or shadow geometry") }
                            silhouette = alpha
                        }
                    }
                }
            }
        }
    }
    func testShadowHasClearOuterEdgesAndDoesNotResizeDevice() throws {
        let source = try input()
        for display in DisplayKind.allCases {
            var settings = CompositionSettings(); settings.display = display
            let bare = try CompositionRenderer.render(source, settings: settings)
            let bareBytes = try pixels(bare.image)
            for (shadow, margin) in [(ShadowStyle.soft, 84), (.strong, 138)] {
                settings.transparentShadow = shadow
                let result = try CompositionRenderer.render(source, settings: settings)
                let bytes = try pixels(result.image), w = result.image.width, h = result.image.height
                var edgeAlpha: UInt8 = 0
                for x in 0..<w { edgeAlpha = max(edgeAlpha, bytes[x * 4 + 3], bytes[((h - 1) * w + x) * 4 + 3]) }
                for y in 0..<h { edgeAlpha = max(edgeAlpha, bytes[(y * w) * 4 + 3], bytes[(y * w + w - 1) * 4 + 3]) }
                XCTAssertEqual(edgeAlpha, 0, "Shadow must fade out on every outer edge")
                var visibleShadow = false
                var changedDevicePixels = 0
                for y in stride(from: 0, to: h, by: 8) {
                    for x in stride(from: 0, to: w, by: 8) {
                        let alpha = bytes[(y * w + x) * 4 + 3]
                        if x < margin || y < margin || x >= w - margin || y >= h - margin {
                            if alpha > 0 { visibleShadow = true }
                        } else {
                            let barePixel = ((y - margin) * bare.image.width + x - margin) * 4
                            if bareBytes[barePixel + 3] == 255 {
                                let pixel = (y * w + x) * 4
                                if (0..<4).contains(where: { bytes[pixel + $0] != bareBytes[barePixel + $0] }) { changedDevicePixels += 1 }
                            }
                        }
                    }
                }
                XCTAssertTrue(visibleShadow)
                XCTAssertEqual(changedDevicePixels, 0, "Shadow must preserve opaque device pixels at the same scale")
            }
        }
    }
    func testBackgroundCanvasAndDeviceSilhouetteStayFixedAcrossSources() throws {
        let sources = try [CGSize(width: 40, height: 10), CGSize(width: 1600, height: 400), CGSize(width: 100, height: 240)].map(solidInput)
        for display in DisplayKind.allCases {
            var settings = CompositionSettings(); settings.display = display; settings.mode = .background
            settings.background = .solid; settings.backgroundOpacity = 0
            for shadow in ShadowStyle.allCases {
                settings.backgroundShadow = shadow
                var silhouette: [UInt8]?
                for source in sources {
                    let result = try CompositionRenderer.render(source, settings: settings, maxDimension: 240)
                    XCTAssertEqual(result.pixelSize, CGSize(width: 2400, height: 1800))
                    XCTAssertEqual(result.previewReferenceSize, result.pixelSize)
                    let bytes = try pixels(result.image), alpha = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
                    if let silhouette { XCTAssertEqual(alpha, silhouette, "Background composition must use device geometry independently of source density") }
                    silhouette = alpha
                }
            }
        }
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
        XCTAssertEqual(try ImageInput(url: URL(fileURLWithPath: report.entries[0].output)).dimensions(), CGSize(width: 3000, height: 1875))
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
