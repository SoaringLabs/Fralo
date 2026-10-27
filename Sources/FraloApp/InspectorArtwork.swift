import AppKit
import FraloCore

struct InspectorArtworkResult {
    let frames: [CGImage?]
    let backgrounds: [CGImage?]
}

/// Cached literal thumbnails, rendered off the main thread without recognizing or repairing content.
@MainActor
final class InspectorArtwork {
    private let queue = DispatchQueue(label: "app.fralo.inspector-artwork", qos: .userInitiated)
    private var pending: DispatchWorkItem?
    private var generation = 0
    private var cachedKey: String?
    private var cached: InspectorArtworkResult?
    func load(_ input: ImageInput?, display: DisplayKind, completion: @escaping (InspectorArtworkResult) -> Void) {
        var signature = (input?.id ?? "empty") + display.rawValue
        if let url = input?.url, let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
            signature += "\(attributes[.modificationDate] ?? "")-\(attributes[.size] ?? "")"
        }
        let key = signature
        generation += 1; let version = generation; pending?.cancel()
        if key == cachedKey, let cached { completion(cached); return }
        let work = DispatchWorkItem { [weak self] in
            let result = autoreleasepool { () -> InspectorArtworkResult in
                let source = input.flatMap { source -> ImageInput? in
                    guard let image = try? source.decode(maxDimension: 360), let data = try? FrameRenderer.pngData(image) else { return nil }
                    return ImageInput(data: data, name: "inspector-source.png")
                }
                let frames: [CGImage?] = (0..<2).map { index in
                    guard let source else { return nil }
                    var settings = CompositionSettings(); settings.display = display
                    settings.orientation = index == 0 ? .portrait : .landscape; settings.browser = index == 0 ? .safari : .chrome
                    return try? CompositionRenderer.render(source, settings: settings, maxDimension: 180).image
                }
                let backgrounds: [CGImage?] = [BackgroundKind.warm, .mist, .sage].map { background in
                    var settings = CompositionSettings(); settings.mode = .background; settings.background = background
                    guard let bytes = try? CompositionRenderer.backgroundData(settings) else { return nil }
                    return try? ImageInput(data: bytes, name: "background-preview.png").decode(maxDimension: 200)
                }
                return InspectorArtworkResult(frames: frames, backgrounds: backgrounds)
            }
            DispatchQueue.main.async {
                guard let self, self.generation == version else { return }
                self.cachedKey = key; self.cached = result; completion(result)
            }
        }
        pending = work; queue.async(execute: work)
    }
}
