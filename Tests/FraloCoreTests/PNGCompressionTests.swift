import CoreGraphics
import XCTest
@testable import FraloCore

final class PNGCompressionTests: XCTestCase {
    private func fixture() throws -> CGImage {
        let w = 384, h = 256
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        var seed: UInt32 = 0x42714a39
        func next() -> Int { seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5; return Int(seed & 255) }
        for y in 0..<h { for x in 0..<w {
            let i = (y * w + x) * 4, a = x < 16 ? 0 : x < 48 ? 127 : 255
            bytes[i] = UInt8(next() * a / 255)
            bytes[i + 1] = UInt8(next() * a / 255)
            bytes[i + 2] = UInt8(next() * a / 255)
            bytes[i + 3] = UInt8(a)
        } }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let c = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: c.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }
    func testPNGQualityChangesEncodingWhileKeepingDimensionsAndTransparency() throws {
        let image = try fixture(), before = try pixels(image)
        var settings = CompositionSettings()
        let lossless = try CompositionRenderer.data(image, settings: settings)
        XCTAssertEqual(try pixels(ImageInput(data: lossless, name: "lossless.png").decode()), before)
        settings.pngLossless = false; settings.pngQuality = 0.2
        let low = try CompositionRenderer.data(image, settings: settings)
        settings.pngQuality = 0.95
        let high = try CompositionRenderer.data(image, settings: settings)
        XCTAssertNotEqual(low, high)
        XCTAssertLessThan(low.count, lossless.count)
        XCTAssertLessThan(high.count, lossless.count)
        for data in [low, high] {
            let decoded = try ImageInput(data: data, name: "compressed.png").decode(), after = try pixels(decoded)
            XCTAssertEqual(decoded.width, image.width); XCTAssertEqual(decoded.height, image.height)
            var error = 0.0
            for i in stride(from: 0, to: before.count, by: 4) {
                XCTAssertLessThanOrEqual(abs(Int(before[i + 3]) - Int(after[i + 3])), 1)
                for channel in 0..<3 { error += pow(Double(before[i + channel]) - Double(after[i + channel]), 2) }
            }
            XCTAssertLessThan(error / Double(image.width * image.height * 3), 5000, "Palette output must preserve the image, not collapse into one color")
        }
    }
    func testExistingCompositionSettingsKeepLosslessPNGOnMigration() throws {
        var original = CompositionSettings(); original.jpegQuality = 0.76
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "pngLossless"); object.removeValue(forKey: "pngQuality")
        let migrated = try JSONDecoder().decode(CompositionSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(migrated.pngLossless); XCTAssertEqual(migrated.pngQuality, 0.85)
        XCTAssertEqual(migrated.jpegQuality, original.jpegQuality)
        var invalid = migrated; invalid.pngQuality = .nan; XCTAssertThrowsError(try invalid.validated())
    }
}
