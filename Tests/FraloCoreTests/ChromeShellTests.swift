import CoreGraphics
import XCTest
@testable import FraloCore

final class ChromeShellTests: XCTestCase {
    func testChromeHasTabAndToolbarControlsInPreviewAndExport() throws {
        let source = try CompositionRenderer.bitmap(CGSize(width: 40, height: 40))
        source.setFillColor(CGColor(gray: 1, alpha: 1))
        source.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        let input = ImageInput(data: try FrameRenderer.pngData(XCTUnwrap(source.makeImage())), name: "page.png")
        for ratio in WindowRatio.allCases {
            var settings = CompositionSettings(); settings.display = .browser
            settings.browser = .chrome; settings.windowRatio = ratio; settings.transparentShadow = .none
            for limit: Int? in [nil, 750] {
                let render = try CompositionRenderer.render(input, settings: settings, maxDimension: limit)
                let image = try ImageInput(data: CompositionRenderer.data(render.image, settings: settings), name: "export.png").decode()
                let bitmap = try CompositionRenderer.bitmap(CGSize(width: image.width, height: image.height))
                CompositionRenderer.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), context: bitmap)
                let bytes = try XCTUnwrap(bitmap.data).assumingMemoryBound(to: UInt8.self)
                let scale = CGFloat(image.width) / 1500
                // Each region was blank in the old shell. Inspect visible ink, not implementation geometry.
                for (name, rect) in [
                    ("close tab", CGRect(x: 357, y: 15, width: 18, height: 18)),
                    ("new tab", CGRect(x: 412, y: 15, width: 18, height: 18)),
                    ("reload", CGRect(x: 86, y: 55, width: 20, height: 20)),
                    ("profile", CGRect(x: 1420, y: 54, width: 24, height: 24)),
                    ("menu", CGRect(x: 1468, y: 55, width: 14, height: 20))
                ] {
                    var ink = 0
                    for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
                        for x in Int(rect.minX * scale)..<Int(rect.maxX * scale) {
                            let offset = y * bitmap.bytesPerRow + x * 4
                            if bytes[offset] < 180 && bytes[offset + 1] < 180 && bytes[offset + 2] < 180 && bytes[offset + 3] > 200 { ink += 1 }
                        }
                    }
                    XCTAssertGreaterThan(ink, 2, "Missing Chrome \(name), \(ratio), preview \(String(describing: limit))")
                }
            }
        }
    }
}
