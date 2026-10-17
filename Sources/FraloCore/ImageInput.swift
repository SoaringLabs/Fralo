import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct ImageInput: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let url: URL?
    public let data: Data?
    public init(url: URL) {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        self.id = canonical.path; self.name = url.lastPathComponent; self.url = canonical; self.data = nil
    }
    public init(data: Data, name: String, id: String = UUID().uuidString) {
        self.id = id; self.name = name; self.data = data; self.url = nil
    }
    public var stem: String { (name as NSString).deletingPathExtension }
    public func imageSource() throws -> CGImageSource {
        let source: CGImageSource?
        if let url { source = CGImageSourceCreateWithURL(url as CFURL, nil) }
        else if let data { source = CGImageSourceCreateWithData(data as CFData, nil) }
        else { source = nil }
        guard let source else { throw FraloError.message("无法读取图片：\(name)") }
        guard let type = CGImageSourceGetType(source) as String?, [UTType.png.identifier, UTType.jpeg.identifier].contains(type) else {
            throw FraloError.message("图片损坏或不是有效的 PNG / JPEG：\(name)")
        }
        return source
    }
    public func dimensions() throws -> CGSize {
        let source = try imageSource()
        guard let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? NSNumber,
              let h = p[kCGImagePropertyPixelHeight] as? NSNumber,
              w.intValue > 0, h.intValue > 0 else {
            throw FraloError.message("图片损坏或没有有效像素：\(name)")
        }
        let o = (p[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return o >= 5 && o <= 8 ? CGSize(width: h.doubleValue, height: w.doubleValue) : CGSize(width: w.doubleValue, height: h.doubleValue)
    }
    public func decode(maxDimension: Int? = nil) throws -> CGImage {
        let source = try imageSource()
        let size = try dimensions()
        let maxSize = maxDimension ?? Int(max(size.width, size.height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxSize),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw FraloError.message("图片解码失败：\(name)")
        }
        return image
    }
}

public enum InputCollector {
    public static let extensions: Set<String> = ["png", "jpg", "jpeg"]
    /// A folder means its immediate image files, never a recursive scan.
    public static func collect(_ urls: [URL]) throws -> [ImageInput] {
        var found: [ImageInput] = [], seen = Set<String>()
        for url in urls {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            let children: [URL]
            if exists && isDirectory.boolValue {
                children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
                    .filter { extensions.contains($0.pathExtension.lowercased()) && ((try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true) }
                    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            } else { children = [url] }
            for child in children {
                let input = ImageInput(url: child)
                if seen.insert(input.id).inserted { found.append(input) }
            }
        }
        return found
    }
}
