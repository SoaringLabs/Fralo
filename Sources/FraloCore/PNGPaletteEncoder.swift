import CoreGraphics
import CoreImage
import Foundation

/// Optional RGB palette reduction. Alpha and output dimensions remain intact.
/// Uses macOS Core Image; no imagequant/GPL dependency is linked or bundled.
enum PNGPaletteEncoder {
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false])
    // K-means stores cluster weights in alpha. Palette lookup requires opaque entries;
    // preserve the kernel's raw RGB instead of unpremultiplying by those weights.
    private static let opaquePalette = CIColorKernel(source: "kernel vec4 fraloPalette(__sample s) { return vec4(s.rgb, 1.0); }")

    static func data(_ image: CGImage, quality: Double) throws -> Data {
        guard quality.isFinite, (0.1...1).contains(quality) else { throw FraloError.message("PNG 品质须为 10–100%。") }
        let original = try FrameRenderer.pngData(image)
        let source = CIImage(cgImage: image, options: [.colorSpace: NSNull()])
        let opaque = source.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)]).cropped(to: source.extent)
        let scale = min(1, 384 / max(source.extent.width, source.extent.height))
        let sample = opaque.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let count = Int((16 + (quality - 0.1) / 0.9 * 112).rounded())
        guard let means = CIFilter(name: "CIKMeans", parameters: [kCIInputImageKey: sample,
            kCIInputExtentKey: CIVector(cgRect: sample.extent), "inputCount": count, "inputPasses": 5, "inputPerceptual": false])?.outputImage,
              let palette = opaquePalette?.apply(extent: means.extent, arguments: [means]) else {
            throw FraloError.message("无法创建 PNG 减色调色板。")
        }
        let reduced = opaque.applyingFilter("CIPalettize", parameters: ["inputPaletteImage": palette, "inputPerceptual": false])
        let clear = CIImage(color: .clear).cropped(to: source.extent)
        let restoredAlpha = reduced.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: source]).cropped(to: source.extent)
        guard let output = context.createCGImage(restoredAlpha, from: source.extent, format: .RGBA8, colorSpace: space) else {
            throw FraloError.message("PNG 减色压缩失败。")
        }
        let compressed = try FrameRenderer.pngData(output)
        // A tiny or already simple image can grow after remapping. Keep the better original.
        return compressed.count < original.count ? compressed : original
    }
}
