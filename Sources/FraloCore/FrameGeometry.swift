import CoreGraphics
import Foundation

public struct FrameGeometry {
    public let model: DeviceModel
    public let body: CGRect
    public let screen: CGRect
    public let bounds: CGRect
    public let buttons: [CGRect]
    public let island: CGRect
    public var bodyRadius: CGFloat { model.screenRadius + model.bezel }

    public init(model: DeviceModel) {
        self.model = model
        let b = model.bezel.rounded(), w = model.screenWidth, h = model.screenHeight
        let bleed = ceil(w * 0.0106)
        body = CGRect(x: bleed, y: 0, width: w + b * 2, height: h + b * 2)
        screen = CGRect(x: bleed + b, y: b, width: w, height: h)
        let bw = bleed + 3
        buttons = [
            CGRect(x: 0, y: h * 0.114, width: bw, height: h * 0.033),
            CGRect(x: 0, y: h * 0.177, width: bw, height: h * 0.056),
            CGRect(x: 0, y: h * 0.249, width: bw, height: h * 0.056),
            CGRect(x: body.maxX - 3, y: h * 0.197, width: bw, height: h * 0.087),
            CGRect(x: body.maxX - 3, y: h * 0.402, width: bw - 3, height: h * 0.041)
        ]
        bounds = buttons.reduce(body) { $0.union($1) }.integral
        island = CGRect(x: screen.midX - w * 0.131, y: screen.minY + w * 0.020, width: w * 0.262, height: w * 0.0744)
    }
    public func oriented(_ rect: CGRect, _ direction: Orientation) -> CGRect {
        if direction == .portrait { return rect }
        return CGRect(x: bounds.height - rect.maxY, y: rect.minX, width: rect.height, height: rect.width)
    }
    public func orientedSize(_ direction: Orientation) -> CGSize {
        direction == .portrait ? bounds.size : CGSize(width: bounds.height, height: bounds.width)
    }
}

public struct RenderPlan {
    public let geometry: FrameGeometry
    public let settings: RenderSettings
    public let sourceSize: CGSize
    public let scale: CGFloat
    public let pixelSize: CGSize
    public let origin: CGPoint
    public var screen: CGRect {
        let r = geometry.oriented(geometry.screen, settings.orientation)
        return CGRect(x: r.minX * scale + origin.x, y: r.minY * scale + origin.y, width: r.width * scale, height: r.height * scale)
    }
    public init(sourceSize: CGSize, settings: RenderSettings, containSource: Bool = false, canvasSize: CGSize? = nil) throws {
        self.settings = try settings.validated(); self.sourceSize = sourceSize
        geometry = FrameGeometry(model: settings.model)
        let screen = geometry.oriented(geometry.screen, settings.orientation)
        let sourceRatio = sourceSize.width / sourceSize.height
        let screenRatio = screen.width / screen.height
        let cropFraction = 1 - min(sourceRatio, screenRatio) / max(sourceRatio, screenRatio)
        guard containSource || cropFraction <= 0.03 else {
            throw FraloError.message("截图比例与所选设备不匹配，裁切将超过 3%。请调整原图或设备设置。")
        }
        let size = geometry.orientedSize(settings.orientation)
        if let canvasSize {
            scale = min((canvasSize.width - CGFloat(settings.padding * 2)) / size.width,
                        (canvasSize.height - CGFloat(settings.padding * 2)) / size.height)
            pixelSize = canvasSize
            origin = CGPoint(x: (canvasSize.width - size.width * scale) / 2, y: (canvasSize.height - size.height * scale) / 2)
        } else {
            // Preserve the legacy CLI's source-density contract.
            scale = max(sourceSize.width / screen.width, sourceSize.height / screen.height)
            pixelSize = CGSize(width: ceil(size.width * scale) + CGFloat(settings.padding * 2), height: ceil(size.height * scale) + CGFloat(settings.padding * 2))
            origin = CGPoint(x: settings.padding, y: settings.padding)
        }
        guard scale.isFinite, scale > 0, pixelSize.width.isFinite, pixelSize.height.isFinite,
              pixelSize.width > 0, pixelSize.height > 0, pixelSize.width * pixelSize.height <= 100_000_000 else {
            throw FraloError.message("输出图片过大，请检查截图与所选设备方向或减少边距。")
        }
    }
}
