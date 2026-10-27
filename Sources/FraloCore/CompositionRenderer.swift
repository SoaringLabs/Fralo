import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct RenderedComposition {
    public let image: CGImage
    public let pixelSize: CGSize
    /// A stable fit-to-window envelope, independent of the selected shadow's export padding.
    public let previewReferenceSize: CGSize
    init(image: CGImage, pixelSize: CGSize, previewReferenceSize: CGSize? = nil) {
        self.image = image; self.pixelSize = pixelSize; self.previewReferenceSize = previewReferenceSize ?? pixelSize
    }
}

/// Deterministic image assembly. Never inspects screenshot content or changes its crop.
public enum CompositionRenderer {
    private static let strongestShadowBlur: CGFloat = 42
    private static let shadowOffsetY: CGFloat = 12
    public static func backgroundData(_ settings: CompositionSettings) throws -> Data? {
        guard settings.mode == .background else { return nil }
        let name: String
        switch settings.background {
        case .warm: name = "warm-gray"
        case .mist: name = "mist-blue"
        case .sage: name = "sage-gray"
        case .local:
            guard let path = settings.localBackgroundPath else { throw FraloError.message("请先选择本地背景图片。") }
            return try Data(contentsOf: URL(fileURLWithPath: path))
        default: return nil
        }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Resources/Backgrounds") else {
            throw FraloError.message("找不到内置背景素材：\(name)")
        }
        return try Data(contentsOf: url)
    }

    public static func render(_ input: ImageInput, settings: CompositionSettings, backgroundData: Data? = nil, maxDimension: Int? = nil) throws -> RenderedComposition {
        let settings = try settings.validated()
        let limit = settings.mode == .background ? min(maxDimension ?? 2400, 2400) : maxDimension
        let device: CGImage
        let nativeSize: CGSize
        switch settings.display {
        case .phone:
            let frame = try FrameRenderer.render(input, settings: RenderSettings(orientation: settings.orientation), maxDimension: limit, containSource: true)
            device = frame.image; nativeSize = frame.plan.pixelSize
        case .tablet, .browser:
            let frame = try shell(input, settings: settings, maxDimension: limit); device = frame.image; nativeSize = frame.pixelSize
        }
        let blur: CGFloat = settings.shadow == .none ? 0 : settings.shadow == .soft ? 24 : strongestShadowBlur
        let shadowOffset: CGFloat = settings.shadow == .none ? 0 : shadowOffsetY
        let margin = ceil(blur * 3 + shadowOffset)
        let size = settings.mode == .background ? settings.canvas.size : CGSize(width: nativeSize.width + margin * 2, height: nativeSize.height + margin * 2)
        let reduction = maxDimension.map { min(1, CGFloat($0) / max(size.width, size.height)) } ?? 1
        let context = try bitmap(CGSize(width: ceil(size.width * reduction), height: ceil(size.height * reduction)))
        context.scaleBy(x: reduction, y: reduction)
        if settings.mode == .background {
            context.saveGState(); context.setAlpha(settings.backgroundOpacity)
            switch settings.background {
            case .solid: context.setFillColor(settings.backgroundColor.cgColor); context.fill(CGRect(origin: .zero, size: size))
            case .gradient:
                let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [settings.backgroundColor.cgColor, CGColor(srgbRed: 0.55, green: 0.62, blue: 0.65, alpha: 1)] as CFArray, locations: [0, 1])!
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            default:
                let bytes = try backgroundData ?? Self.backgroundData(settings)
                guard let bytes else { throw FraloError.message("背景图片不可用。") }
                let image = try ImageInput(data: bytes, name: "background.png").decode(maxDimension: 4800)
                let scale = max(size.width / CGFloat(image.width), size.height / CGFloat(image.height)) * settings.backgroundScale
                let imageSize = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                let rect = CGRect(x: (size.width - imageSize.width) / 2 + CGFloat(settings.backgroundX) * (imageSize.width - size.width) / 2,
                                  y: (size.height - imageSize.height) / 2 + CGFloat(settings.backgroundY) * (imageSize.height - size.height) / 2,
                                  width: imageSize.width, height: imageSize.height)
                draw(image, in: rect, context: context)
            }
            context.restoreGState()
        }
        let rect: CGRect
        if settings.mode == .background {
            let fit = min(size.width / CGFloat(device.width), size.height / CGFloat(device.height)) * settings.deviceScale
            let w = CGFloat(device.width) * fit, h = CGFloat(device.height) * fit
            rect = CGRect(x: (size.width - w) / 2 + CGFloat(settings.deviceX) * size.width, y: (size.height - h) / 2 + CGFloat(settings.deviceY) * size.height, width: w, height: h)
        } else { rect = CGRect(x: margin, y: margin, width: nativeSize.width, height: nativeSize.height) }
        context.saveGState(); context.setAlpha(settings.deviceOpacity)
        if blur > 0 { context.setShadow(offset: CGSize(width: 0, height: shadowOffset), blur: blur, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: settings.shadow == .strong ? 0.4 : 0.23)) }
        draw(device, in: rect, context: context); context.restoreGState()
        guard let image = context.makeImage() else { throw FraloError.message("无法合成成品。") }
        let maximumMargin = ceil(strongestShadowBlur * 3 + shadowOffsetY)
        let reference = settings.mode == .background ? size : CGSize(width: nativeSize.width + maximumMargin * 2, height: nativeSize.height + maximumMargin * 2)
        return RenderedComposition(image: image, pixelSize: size, previewReferenceSize: reference)
    }

    public static func panBackground(_ settings: inout CompositionSettings, delta: CGPoint, imageSize: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let size = settings.canvas.size
        let cover = max(size.width / imageSize.width, size.height / imageSize.height) * settings.backgroundScale
        let overflowX = imageSize.width * cover - size.width, overflowY = imageSize.height * cover - size.height
        settings.backgroundX = overflowX > 0 ? min(1, max(-1, settings.backgroundX + delta.x * size.width * 2 / overflowX)) : 0
        settings.backgroundY = overflowY > 0 ? min(1, max(-1, settings.backgroundY + delta.y * size.height * 2 / overflowY)) : 0
    }

    public static func flattened(_ image: CGImage, color: ArtworkColor) throws -> CGImage {
        let context = try bitmap(CGSize(width: image.width, height: image.height))
        context.setFillColor(color.cgColor); context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), context: context)
        return context.makeImage()!
    }
    public static func data(_ image: CGImage, settings: CompositionSettings) throws -> Data {
        if settings.format == .png {
            return try settings.pngLossless ? FrameRenderer.pngData(image) : PNGPaletteEncoder.data(image, quality: settings.pngQuality)
        }
        let flattened = try Self.flattened(image, color: settings.jpegFill)
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else { throw FraloError.message("无法创建 JPEG。") }
        CGImageDestinationAddImage(destination, flattened, [kCGImageDestinationLossyCompressionQuality: settings.jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FraloError.message("JPEG 编码失败。") }
        return bytes as Data
    }
    static func bitmap(_ size: CGSize) throws -> CGContext {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0, size.width * size.height <= 100_000_000,
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw FraloError.message("成品尺寸过大，无法分配图片内存。")
        }
        context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
        return context
    }
    static func draw(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState(); context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high; context.draw(image, in: CGRect(origin: .zero, size: rect.size)); context.restoreGState()
    }
    private static func fill(_ rect: CGRect, radius: CGFloat, color: CGColor, context: CGContext) {
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)); context.setFillColor(color); context.fillPath()
    }
    private static func shell(_ input: ImageInput, settings: CompositionSettings, maxDimension: Int?) throws -> RenderedComposition {
        let tablet = settings.display == .tablet
        let size = tablet ? (settings.orientation == .portrait ? CGSize(width: 1100, height: 1442) : CGSize(width: 1442, height: 1100)) : CGSize(width: 1500, height: (1500 / settings.windowRatio.ratio).rounded())
        let sourceSize = try input.dimensions()
        let screen = tablet ? CGRect(origin: .zero, size: size).insetBy(dx: 38, dy: 38) : CGRect(x: 2, y: settings.browser == .chrome ? 86 : 64, width: size.width - 4, height: size.height - (settings.browser == .chrome ? 88 : 66))
        let density = max(sourceSize.width / screen.width, sourceSize.height / screen.height)
        let requested = maxDimension.map { min(density, CGFloat($0) / max(size.width, size.height)) } ?? density
        let output = CGSize(width: ceil(size.width * requested), height: ceil(size.height * requested))
        let context = try bitmap(output); context.scaleBy(x: requested, y: requested)
        let bodyColor = tablet ? CGColor(srgbRed: 0.12, green: 0.13, blue: 0.14, alpha: 1) : CGColor(srgbRed: 0.92, green: 0.92, blue: 0.93, alpha: 1)
        fill(CGRect(origin: .zero, size: size), radius: tablet ? 62 : 16, color: bodyColor, context: context)
        if tablet {
            context.setStrokeColor(CGColor(gray: 0.55, alpha: 1)); context.setLineWidth(3)
            context.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3), cornerWidth: 60, cornerHeight: 60, transform: nil)); context.strokePath()
            context.setFillColor(CGColor(gray: 0.02, alpha: 1)); context.fillEllipse(in: CGRect(x: size.width / 2 - 5, y: 13, width: 10, height: 10))
        } else {
            for (i, color) in [ArtworkColor(1, 0.36, 0.33), ArtworkColor(1, 0.75, 0.24), ArtworkColor(0.18, 0.8, 0.3)].enumerated() {
                context.setFillColor(color.cgColor); context.fillEllipse(in: CGRect(x: 22 + i * 25, y: 24, width: 15, height: 15))
            }
            let barY: CGFloat = settings.browser == .chrome ? 48 : 14
            fill(CGRect(x: 230, y: barY, width: size.width - 460, height: 36), radius: 9, color: CGColor(gray: 0.98, alpha: 1), context: context)
            if settings.browser == .chrome { fill(CGRect(x: 130, y: 7, width: 260, height: 34), radius: 8, color: CGColor(gray: 0.99, alpha: 1), context: context) }
            context.setStrokeColor(CGColor(gray: 0.45, alpha: 1)); context.setLineWidth(2)
            for (index, x) in [CGFloat(125), CGFloat(166)].enumerated() {
                let edge: CGFloat = index == 0 ? 6 : -6
                context.move(to: CGPoint(x: x + edge, y: barY + 11)); context.addLine(to: CGPoint(x: x, y: barY + 18)); context.addLine(to: CGPoint(x: x + edge, y: barY + 25)); context.strokePath()
            }
        }
        context.saveGState(); context.addPath(CGPath(roundedRect: screen, cornerWidth: tablet ? 30 : 4, cornerHeight: tablet ? 30 : 4, transform: nil)); context.clip()
        context.setFillColor(CGColor(gray: 0.04, alpha: 1)); context.fill(screen)
        let image = try input.decode(maxDimension: maxDimension)
        let fit = min(screen.width / CGFloat(image.width), screen.height / CGFloat(image.height))
        let rect = CGRect(x: screen.midX - CGFloat(image.width) * fit / 2, y: screen.midY - CGFloat(image.height) * fit / 2, width: CGFloat(image.width) * fit, height: CGFloat(image.height) * fit)
        draw(image, in: rect, context: context); context.restoreGState()
        return RenderedComposition(image: context.makeImage()!, pixelSize: CGSize(width: ceil(size.width * density), height: ceil(size.height * density)))
    }
}
