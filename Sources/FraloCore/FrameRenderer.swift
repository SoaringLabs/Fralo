import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct RenderedFrame {
    public let image: CGImage
    public let plan: RenderPlan
}

public enum FrameRenderer {
    public static func render(_ input: ImageInput, settings: RenderSettings, maxDimension: Int? = nil, containSource: Bool = false, canvasSize: CGSize? = nil) throws -> RenderedFrame {
        let plan = try RenderPlan(sourceSize: input.dimensions(), settings: settings, containSource: containSource, canvasSize: canvasSize)
        let reduction = maxDimension.map { min(1, CGFloat($0) / max(plan.pixelSize.width, plan.pixelSize.height)) } ?? 1
        let width = max(1, Int(ceil(plan.pixelSize.width * reduction)))
        let height = max(1, Int(ceil(plan.pixelSize.height * reduction)))
        let decodeLimit = canvasSize != nil ? max(1, Int(ceil(max(plan.screen.width, plan.screen.height) * reduction))) : maxDimension.map { _ in max(1, Int(ceil(max(plan.sourceSize.width, plan.sourceSize.height) * reduction))) }
        let source = try input.decode(maxDimension: decodeLimit)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw FraloError.message("无法分配图片内存。")
        }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: reduction, y: -reduction)
        context.translateBy(x: plan.origin.x, y: plan.origin.y)
        context.scaleBy(x: plan.scale, y: plan.scale)
        let geometry = plan.geometry

        context.saveGState()
        orient(context, geometry: geometry, direction: settings.orientation)
        drawBody(in: context, geometry: geometry)
        context.restoreGState()

        let screen = geometry.oriented(geometry.screen, settings.orientation)
        context.saveGState()
        context.addPath(rounded(screen, geometry.model.screenRadius)); context.clip()
        context.setFillColor(color(0x050607)); context.fill(screen)
        let factor = containSource ? min(screen.width / CGFloat(source.width), screen.height / CGFloat(source.height)) : max(screen.width / CGFloat(source.width), screen.height / CGFloat(source.height))
        let size = CGSize(width: CGFloat(source.width) * factor, height: CGFloat(source.height) * factor)
        let destination = CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
        drawUpright(source, in: destination, context: context)
        context.restoreGState()

        context.saveGState()
        orient(context, geometry: geometry, direction: settings.orientation)
        drawIsland(in: context, geometry: geometry)
        context.restoreGState()
        guard let image = context.makeImage() else { throw FraloError.message("合成图片失败。") }
        return RenderedFrame(image: image, plan: plan)
    }

    public static func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw FraloError.message("无法创建 PNG。")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw FraloError.message("PNG 编码失败。") }
        return data as Data
    }

    private static func orient(_ context: CGContext, geometry: FrameGeometry, direction: Orientation) {
        if direction == .landscape {
            context.translateBy(x: geometry.bounds.height, y: 0); context.rotate(by: .pi / 2)
        }
    }
    private static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }
    private static func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
    private static func fill(_ rect: CGRect, radius: CGFloat, color: CGColor, context: CGContext) {
        context.addPath(rounded(rect, radius)); context.setFillColor(color); context.fillPath()
    }
    private static func gradient(_ colors: [CGColor], locations: [CGFloat], rect: CGRect, horizontal: Bool, context: CGContext) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations) else { return }
        context.drawLinearGradient(gradient,
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: horizontal ? CGPoint(x: rect.maxX, y: rect.minY) : CGPoint(x: rect.minX, y: rect.maxY), options: [])
    }
    private static func drawBody(in context: CGContext, geometry g: FrameGeometry) {
        for button in g.buttons {
            context.saveGState(); context.addPath(rounded(button, button.width * 0.33)); context.clip()
            gradient([color(0x15181b), color(0x92999e), color(0x393f44), color(0x101214)], locations: [0, 0.26, 0.56, 1], rect: button, horizontal: true, context: context)
            context.restoreGState()
        }
        context.saveGState(); context.addPath(rounded(g.body, g.bodyRadius)); context.clip()
        gradient([0x17191c, 0x71767b, 0x24272b, 0xb5b7b7, 0x555b60, 0x292d31, 0x111315, 0x24282c, 0x444b51, 0xa6aaad, 0x42464a, 0x121416].map { color(UInt32($0)) },
                 locations: [0, 0.006, 0.015, 0.027, 0.045, 0.085, 0.45, 0.82, 0.952, 0.976, 0.988, 1], rect: g.body, horizontal: true, context: context)
        gradient([color(0xbec2c5, alpha: 0.64), color(0x343a40, alpha: 0.35), color(0x000000, alpha: 0.35), color(0x343a40, alpha: 0.05), color(0x000000, alpha: 0.4), color(0x9da3a7, alpha: 0.4), color(0x22262a, alpha: 0.85)],
                 locations: [0, 0.018, 0.1, 0.48, 0.87, 0.982, 1], rect: g.body, horizontal: false, context: context)
        context.restoreGState()
        let unit = g.model.screenWidth / 1290
        context.addPath(rounded(g.body.insetBy(dx: 6 * unit, dy: 6 * unit), g.bodyRadius - 6 * unit))
        context.setStrokeColor(color(0xaeb4b8, alpha: 0.55)); context.setLineWidth(2.2 * unit); context.strokePath()
        fill(g.body.insetBy(dx: 15 * unit, dy: 15 * unit), radius: g.bodyRadius - 15 * unit, color: color(0x060708), context: context)
        context.addPath(rounded(g.body.insetBy(dx: 15 * unit, dy: 15 * unit), g.bodyRadius - 15 * unit))
        context.setStrokeColor(color(0x92989b, alpha: 0.48)); context.setLineWidth(2.2 * unit); context.strokePath()
        fill(g.body.insetBy(dx: 22 * unit, dy: 22 * unit), radius: g.bodyRadius - 22 * unit, color: color(0x030405), context: context)
        fill(g.screen.insetBy(dx: -1, dy: -1), radius: g.model.screenRadius + 1, color: color(0x08090a), context: context)
    }
    private static func drawIsland(in context: CGContext, geometry g: FrameGeometry) {
        let r = g.island
        fill(r, radius: r.height / 2, color: color(0x020304), context: context)
        let cameraRadius = r.height * 0.21875
        let center = CGPoint(x: r.maxX - r.height * 0.52, y: r.midY)
        let camera = CGRect(x: center.x - cameraRadius, y: center.y - cameraRadius, width: cameraRadius * 2, height: cameraRadius * 2)
        context.setFillColor(color(0x06070b)); context.fillEllipse(in: camera)
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0x142341), color(0x13253a), color(0x070e19), color(0x1b1b2d), color(0x06080c), color(0x11151a)] as CFArray, locations: [0, 0.26, 0.49, 0.69, 0.83, 1]) else { return }
        context.saveGState(); context.addEllipse(in: camera.insetBy(dx: cameraRadius * 0.25, dy: cameraRadius * 0.25)); context.clip()
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: cameraRadius * 0.75, options: [])
        context.restoreGState()
        context.setFillColor(color(0x536c98, alpha: 0.45))
        context.fillEllipse(in: CGRect(x: center.x - cameraRadius * 0.36, y: center.y - cameraRadius * 0.44, width: cameraRadius * 0.36, height: cameraRadius * 0.36))
    }
    private static func drawUpright(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState(); context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
}
