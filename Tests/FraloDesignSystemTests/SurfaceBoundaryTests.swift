import AppKit
import XCTest
import QuartzCore
@testable import FraloDesignSystem

final class SurfaceBoundaryTests: XCTestCase {
    @MainActor func testPanelKeepsItsBackingAndDoesNotAnimateAsAnInteractiveControl() async throws {
        _ = NSApplication.shared
        let panel = MaterialSurface(.panel, radius: 24)
        let backing = panel.panelTint
        XCTAssertFalse(backing.isHidden)
        for name: NSAppearance.Name in [.aqua, .darkAqua] {
            panel.appearance = NSAppearance(named: name); panel.refresh()
            XCTAssertEqual(try XCTUnwrap(backing.layer?.backgroundColor).alpha, 0.55, accuracy: 0.01, "Panels stay translucent over the blurred stage")
        }
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) {
            let glass = try XCTUnwrap(panel.subviews.compactMap { $0 as? NSGlassEffectView }.first)
            XCTAssertFalse(glass.effectIsInteractive)
        }
        #endif
        var preferences = DesignPreferences(); preferences.reduceTransparency = true
        panel.preferences = preferences; XCTAssertTrue(panel.isUsingOpaqueFallback)
    }

    @MainActor func testNativeGlassCannotPaintAnUnroundedChildOutlineOutsideItsSurface() async throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native glass is unavailable") }
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 180), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let toolbar = ViewToolbar(); toolbar.frame = NSRect(x: 30, y: 50, width: 520, height: 48)
        window.contentView?.addSubview(toolbar)
        for appearance: NSAppearance.Name in [.aqua, .darkAqua, .aqua] {
            window.appearance = NSAppearance(named: appearance)
            window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            let surface = toolbar.surface; let layer = try XCTUnwrap(surface.layer)
            let glass = try XCTUnwrap(surface.subviews.compactMap { $0 as? NSGlassEffectView }.first)
            // Model the supplied photo's rectangular perimeter as an effect-child paint overrun.
            // This tests the component's clipping contract, not reproduction of a GPU/compositor fault.
            let perimeter = CALayer(); perimeter.frame = glass.bounds.insetBy(dx: -2, dy: -2)
            perimeter.borderColor = NSColor.black.cgColor; perimeter.borderWidth = 3
            let marker = CALayer(); marker.frame = NSRect(x: 35, y: 18, width: 8, height: 8)
            marker.backgroundColor = NSColor(calibratedRed: 0, green: 0.4, blue: 1, alpha: 1).cgColor
            let glassLayer = try XCTUnwrap(glass.layer)
            glassLayer.addSublayer(perimeter); glassLayer.addSublayer(marker)
            defer { perimeter.removeFromSuperlayer(); marker.removeFromSuperlayer() }
            let padding = 8, width = Int(layer.bounds.width) + padding * 2, height = Int(layer.bounds.height) + padding * 2
            let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.translateBy(x: CGFloat(padding), y: CGFloat(padding)); layer.render(in: context)
            let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            var leaked = 0
            for y in 0..<height { for x in 0..<width {
                if x < padding || x >= width - padding || y < padding || y >= height - padding {
                    if bytes[(y * width + x) * 4 + 3] > 0 { leaked += 1 }
                }
            } }
            XCTAssertEqual(leaked, 0, "\(appearance.rawValue): an unrounded child outline escaped the shared surface")
            for (x, y) in [(padding, padding), (width - padding - 1, padding),
                           (padding, height - padding - 1), (width - padding - 1, height - padding - 1)] {
                XCTAssertEqual(bytes[(y * width + x) * 4 + 3], 0, "The surface corners must remain rounded during child-layer redraw")
            }
            let foreground = ((padding + 22) * width + padding + 39) * 4
            XCTAssertGreaterThan(bytes[foreground + 2], 220, "Clipping must retain the blue foreground marker")
            XCTAssertLessThan(bytes[foreground], 30, "The foreground marker must not be replaced by surface backing")
        }
    }
}
