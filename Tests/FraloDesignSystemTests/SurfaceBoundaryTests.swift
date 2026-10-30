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

    @MainActor func testViewingCapsuleIsBareGlassInBothAppearances() throws {
        _ = NSApplication.shared
        let controls = ViewToolbar(); controls.frame = NSRect(x: 0, y: 0, width: 300, height: ViewToolbar.height)
        let surface = controls.surface
        for name: NSAppearance.Name in [.aqua, .darkAqua] {
            surface.appearance = NSAppearance(named: name); surface.refresh()
            XCTAssertTrue(surface.panelTint.isHidden, "\(name.rawValue): no overlay hides the glass rim or refraction")
            XCTAssertGreaterThan(surface.layer?.borderWidth ?? 0, 0, "\(name.rawValue): a hairline keeps the edge over same-tone art")
        }
        XCTAssertFalse(MaterialSurface(.panel).panelTint.isHidden, "Large panels keep their backing")
        XCTAssertTrue(surface.clipsToBounds, "The child-outline clipping contract still holds")
        controls.layout()
        XCTAssertGreaterThan(controls.layer?.shadowOpacity ?? 0, 0, "The host restores the lift the clip removes")
        XCTAssertNotNil(controls.layer?.shadowPath)

        var contrast = DesignPreferences(); contrast.increaseContrast = true
        surface.preferences = contrast
        XCTAssertEqual(surface.layer?.borderWidth, 1, "Increase Contrast widens the outline")
        var opaque = DesignPreferences(); opaque.reduceTransparency = true
        surface.preferences = opaque
        XCTAssertTrue(surface.isUsingOpaqueFallback)
    }

    @MainActor func testOutlineFollowsTheSurfaceAppearanceAndStrengthensWithoutGlass() throws {
        _ = NSApplication.shared
        let surface = MaterialSurface(.panel, radius: 18)
        func outline() throws -> (luma: CGFloat, alpha: CGFloat) {
            let color = try XCTUnwrap(surface.layer?.borderColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.sRGB) })
            return (0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent, color.alphaComponent)
        }
        surface.appearance = NSAppearance(named: .aqua); surface.refresh()
        let light = try outline()
        XCTAssertLessThan(light.luma, 0.3, "Dark hairline on light glass")
        surface.appearance = NSAppearance(named: .darkAqua); surface.refresh()
        let dark = try outline()
        XCTAssertGreaterThan(dark.luma, 0.7, "Light hairline on dark glass")
        var opaque = DesignPreferences(); opaque.reduceTransparency = true
        surface.preferences = opaque
        XCTAssertGreaterThan(try outline().alpha, dark.alpha, "With no glass rim, the outline carries the edge alone")
        var contrast = DesignPreferences(); contrast.increaseContrast = true
        surface.preferences = contrast
        XCTAssertGreaterThan(try outline().alpha, dark.alpha, "Increase Contrast is the strongest edge")
    }

    @MainActor func testCapsuleForegroundFlipsWithBackdropUsingHysteresis() throws {
        _ = NSApplication.shared
        let controls = ViewToolbar()
        func isLight() -> Bool { controls.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua }
        XCTAssertNil(controls.appearance, "Over the stage the capsule follows the window")
        controls.backdropLuminance = 0.92
        XCTAssertEqual(controls.usesLightAppearance, true); XCTAssertTrue(isLight(), "Bright art gets dark symbols")
        controls.backdropLuminance = 0.4
        XCTAssertEqual(controls.usesLightAppearance, true, "Mid tones keep the current choice")
        controls.backdropLuminance = 0.3
        XCTAssertEqual(controls.usesLightAppearance, false); XCTAssertFalse(isLight(), "Dark art gets light symbols")
        controls.backdropLuminance = 0.4
        XCTAssertEqual(controls.usesLightAppearance, false, "Mid tones keep the current choice")
        controls.backdropLuminance = ViewToolbar.lightBackdropThreshold
        XCTAssertEqual(controls.usesLightAppearance, true)
        controls.backdropLuminance = nil
        XCTAssertNil(controls.usesLightAppearance); XCTAssertNil(controls.appearance)
    }

    @MainActor func testCanvasReportsOpaqueArtworkLuminanceAndDefersToTheStage() throws {
        _ = NSApplication.shared
        // Top half white, bottom half black, right quarter transparent.
        let image = NSImage(size: NSSize(width: 400, height: 400), flipped: true) { _ in
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 300, height: 200).fill()
            NSColor.black.setFill(); NSRect(x: 0, y: 200, width: 300, height: 200).fill()
            return true
        }
        let canvas = CanvasSurface(frame: NSRect(x: 0, y: 0, width: 432, height: 432))
        canvas.image = image; canvas.zoom = 1
        let art = canvas.imageRect
        let top = try XCTUnwrap(canvas.artworkLuminance(under: NSRect(x: art.minX + 20, y: art.minY + 40, width: 200, height: 36)))
        XCTAssertGreaterThan(top, 0.9)
        let bottom = try XCTUnwrap(canvas.artworkLuminance(under: NSRect(x: art.minX + 20, y: art.minY + 320, width: 200, height: 36)))
        XCTAssertLessThan(bottom, 0.1)
        XCTAssertNil(canvas.artworkLuminance(under: NSRect(x: art.minX + 310, y: art.minY + 40, width: 80, height: 36)), "Transparent art shows the stage")
        XCTAssertNil(canvas.artworkLuminance(under: NSRect(x: art.minX - 180, y: art.minY + 40, width: 200, height: 36)), "Mostly over the stage")
        canvas.image = nil
        XCTAssertNil(canvas.artworkLuminance(under: NSRect(x: 0, y: 0, width: 100, height: 36)))
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
