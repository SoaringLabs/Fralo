import AppKit
import QuartzCore
import XCTest
@testable import FraloDesignSystem

final class ArtworkDirectionTests: XCTestCase {
    @MainActor func testLiveLayerPixelsFollowPointerAndMatchFinalRasterInAllDirections() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 448, height: 448), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let canvas = CanvasSurface(frame: CGRect(x: 0, y: 0, width: 448, height: 448))
        canvas.showsTransparencyGrid = false; canvas.zoom = 1
        window.contentView = canvas
        let initial = CGRect(x: 180, y: 170, width: 40, height: 60)
        func image(_ size: CGSize, marker: CGRect?) throws -> CGImage {
            let c = try XCTUnwrap(CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            c.translateBy(x: 0, y: size.height); c.scaleBy(x: 1, y: -1)
            c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(origin: .zero, size: size))
            if let marker {
                c.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)); c.fill(marker)
                c.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)); c.fill(CGRect(x: marker.minX, y: marker.minY, width: marker.width, height: 8))
                c.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)); c.fill(CGRect(x: marker.minX, y: marker.maxY - 8, width: marker.width, height: 8))
            }
            return try XCTUnwrap(c.makeImage())
        }
        let size = CGSize(width: 400, height: 400)
        let background = try image(size, marker: nil)
        let device = try image(initial.size, marker: CGRect(origin: .zero, size: initial.size))
        func markers() throws -> [CGPoint] {
            canvas.layoutSubtreeIfNeeded(); canvas.displayIfNeeded(); canvas.layer?.displayIfNeeded()
            let layer = try XCTUnwrap(canvas.layer)
            let width = Int(canvas.bounds.width), height = Int(canvas.bounds.height)
            let c = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            layer.render(in: c)
            let p = try XCTUnwrap(c.data).assumingMemoryBound(to: UInt8.self)
            var xsum = [0, 0, 0], ysum = [0, 0, 0], count = [0, 0, 0]
            for y in 0..<height { for x in 0..<width {
                let i = (y * width + x) * 4
                let color: Int?
                if p[i] < 30 && p[i + 1] > 220 && p[i + 2] < 30 { color = 0 }
                else if p[i] > 220 && p[i + 1] < 30 && p[i + 2] < 30 { color = 1 }
                else if p[i] < 30 && p[i + 1] < 30 && p[i + 2] > 220 { color = 2 }
                else { color = nil }
                if let color { xsum[color] += x; ysum[color] += y; count[color] += 1 }
            } }
            for n in count { XCTAssertGreaterThan(n, 100, "Snapshot must contain the actual colored artwork pixels") }
            return (0..<3).map { CGPoint(x: Double(xsum[$0]) / Double(max(1, count[$0])), y: Double(ysum[$0]) / Double(max(1, count[$0]))) }
        }
        for target in ["device", "background"] {
            for delta in [CGPoint(x: -30, y: 0), CGPoint(x: 30, y: 0), CGPoint(x: 0, y: -50), CGPoint(x: 0, y: 50), CGPoint(x: -30, y: -50), CGPoint(x: 30, y: -50), CGPoint(x: -30, y: 50), CGPoint(x: 30, y: 50)] {
                canvas.image = NSImage(cgImage: background, size: size)
                let backdrop = target == "device" ? background : try image(CGSize(width: 800, height: 800), marker: initial.offsetBy(dx: 200, dy: 200))
                canvas.prepareArtwork(background: backdrop, device: device, backgroundOpacity: 1, canvasSize: size)
                var liveRect = initial
                var backgroundRect = CGRect(x: -200, y: -200, width: 800, height: 800)
                canvas.onDrag = { normalized in
                    liveRect = liveRect.offsetBy(dx: normalized.x * size.width, dy: normalized.y * size.height)
                    backgroundRect = backgroundRect.offsetBy(dx: normalized.x * size.width, dy: normalized.y * size.height)
                    canvas.positionArtwork(deviceRect: target == "device" ? liveRect : initial.offsetBy(dx: -1000, dy: -1000),
                                           backgroundRect: target == "device" ? CGRect(origin: .zero, size: size) : backgroundRect)
                }
                func event(_ type: NSEvent.EventType, _ local: CGPoint) throws -> NSEvent {
                    try XCTUnwrap(NSEvent.mouseEvent(with: type, location: canvas.convert(local, to: nil), modifierFlags: [], timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
                }
                let origin = CGPoint(x: canvas.imageRect.midX, y: canvas.imageRect.midY)
                canvas.mouseDown(with: try event(.leftMouseDown, origin))
                canvas.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: origin.x + delta.x, y: origin.y + delta.y)))
                let live = try markers()
                canvas.mouseUp(with: try event(.leftMouseUp, origin))
                canvas.finishPositioningArtwork()
                let finalImage = try image(size, marker: initial.offsetBy(dx: delta.x, dy: delta.y))
                canvas.image = NSImage(cgImage: finalImage, size: size)
                let final = try markers()
                print("[ArtworkDirection] target=\(target) delta=\(delta) livePixels=\(live) finalPixels=\(final)")
                for n in 0..<3 {
                    XCTAssertEqual(live[n].x, final[n].x, accuracy: 1, "Live X must match final pixels for \(target) \(delta)")
                    XCTAssertEqual(live[n].y, final[n].y, accuracy: 1, "Live Y and texture orientation must match final pixels for \(target) \(delta)")
                }
            }
        }
    }
}
