import CoreGraphics
import XCTest
@testable import FraloCore

final class BrowserAppearanceTests: XCTestCase {
    private func input() throws -> ImageInput {
        let context = try CompositionRenderer.bitmap(CGSize(width: 40, height: 40))
        context.setFillColor(CGColor(srgbRed: 0.3, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        return ImageInput(data: try FrameRenderer.pngData(XCTUnwrap(context.makeImage())), name: "source.png")
    }

    private func pixel(_ image: CGImage, x: CGFloat, y: CGFloat) throws -> [UInt8] {
        let context = try CompositionRenderer.bitmap(CGSize(width: image.width, height: image.height))
        CompositionRenderer.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), context: context)
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = Int(y) * context.bytesPerRow + Int(x) * 4
        return (0..<4).map { bytes[offset + $0] }
    }

    func testOldConfigurationsDefaultToLightAndDarkPersists() throws {
        var settings = CompositionSettings(); settings.display = .browser; settings.browserAppearance = .dark
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CompositionStore(legacy: SettingsStore(url: root.appendingPathComponent("settings.json")))
        try store.save(settings)
        XCTAssertEqual(try store.load(), settings)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        legacy.removeValue(forKey: "browserAppearance")
        let decoded = try JSONDecoder().decode(CompositionSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded.browserAppearance, .light)
        XCTAssertEqual(decoded.browser, settings.browser)
        legacy["browserAppearance"] = "unsupported"
        XCTAssertThrowsError(try JSONDecoder().decode(CompositionSettings.self, from: JSONSerialization.data(withJSONObject: legacy)))
    }

    func testSafariAndChromePreviewAndExportsChangeShellWithoutRecoloringSource() throws {
        let source = try input()
        for browser in BrowserStyle.allCases {
            for ratio in WindowRatio.allCases {
                for limit: Int? in [nil, 750] {
                    var settings = CompositionSettings(); settings.display = .browser
                    settings.browser = browser; settings.windowRatio = ratio
                    let light = try CompositionRenderer.render(source, settings: settings, maxDimension: limit)
                    settings.browserAppearance = .dark
                    let dark = try CompositionRenderer.render(source, settings: settings, maxDimension: limit)
                    XCTAssertEqual(dark.pixelSize, light.pixelSize)
                    XCTAssertEqual(dark.previewReferenceSize, light.previewReferenceSize)
                    let scale = CGFloat(dark.image.width) / 1500
                    let lightBar = try pixel(light.image, x: 500 * scale, y: 32 * scale)
                    let darkBar = try pixel(dark.image, x: 500 * scale, y: 32 * scale)
                    XCTAssertGreaterThan(lightBar[0], 210); XCTAssertLessThan(darkBar[0], 100)
                    let centerX = CGFloat(dark.image.width) / 2, centerY = CGFloat(dark.image.height) / 2
                    let original = try pixel(light.image, x: centerX, y: centerY)
                    XCTAssertEqual(try pixel(dark.image, x: centerX, y: centerY), original)
                    XCTAssertEqual(Int(original[0]), 77, accuracy: 2)
                    for format in ImageFormat.allCases {
                        settings.format = format
                        let exported = try ImageInput(data: CompositionRenderer.data(dark.image, settings: settings), name: "export").decode()
                        XCTAssertLessThan(try pixel(exported, x: 500 * scale, y: 32 * scale)[0], 100)
                        let sample = try pixel(exported, x: centerX, y: centerY)
                        for index in 0..<3 { XCTAssertEqual(Int(sample[index]), Int(original[index]), accuracy: format == .jpeg ? 4 : 0) }
                    }
                }
            }
        }
    }

    func testDarkArtworkAlsoEntersBackgroundCompositionAndLeavesHardwareUnchanged() throws {
        let source = try input()
        for display in DisplayKind.allCases {
            var settings = CompositionSettings(); settings.display = display
            settings.mode = .background; settings.background = .solid
            let light = try CompositionRenderer.render(source, settings: settings, maxDimension: 500, preparePreviewLayers: true)
            settings.browserAppearance = .dark
            let dark = try CompositionRenderer.render(source, settings: settings, maxDimension: 500, preparePreviewLayers: true)
            let lightData = try FrameRenderer.pngData(light.image), darkData = try FrameRenderer.pngData(dark.image)
            if display == .browser {
                XCTAssertNotEqual(lightData, darkData)
                XCTAssertNotEqual(try FrameRenderer.pngData(XCTUnwrap(light.previewLayers).device), try FrameRenderer.pngData(XCTUnwrap(dark.previewLayers).device))
            } else { XCTAssertEqual(lightData, darkData, "Hardware and screenshot pixels do not have an app appearance") }
        }
    }
}
