import Foundation
import CoreGraphics
import FraloCore

/// One serial renderer with cooperative cancellation between images. Only the current
/// request may publish; obsolete batches never have to drain before a new one starts.
@MainActor
final class ThumbnailPipeline {
    struct Thumbnail {
        let image: CGImage
        let pixelSize: CGSize
        var cost: Int { image.bytesPerRow * image.height }
    }
    typealias Render = (ImageInput, CompositionSettings) throws -> Thumbnail

    private let queue = DispatchQueue(label: "app.fralo.thumbnails", qos: .utility)
    private let worker: Worker
    private var token = CancellationToken()
    private var pending: DispatchWorkItem?

    init(costLimit: Int = 64 * 1024 * 1024, countLimit: Int = 1024,
         render: @escaping Render = { input, settings in
             Thumbnail(image: try CompositionRenderer.render(input, settings: settings, maxDimension: 180).image,
                       pixelSize: try input.dimensions())
         }) {
        worker = Worker(costLimit: costLimit, countLimit: countLimit, render: render)
    }

    static func styleKey(_ settings: CompositionSettings) -> String {
        switch settings.display {
        case .phone: return "phone/\(settings.phoneModel.rawValue)/\(settings.orientation.rawValue)"
        case .tablet: return "tablet/\(settings.orientation.rawValue)"
        case .browser: return "browser/\(settings.browser.rawValue)/\(settings.windowRatio.rawValue)/\(settings.browserAppearance.rawValue)"
        }
    }

    func cancel() { token.cancel(); pending?.cancel(); pending = nil }

    func request(_ inputs: [ImageInput], settings: CompositionSettings,
                 onResult: @escaping @MainActor (String, Result<Thumbnail, Error>) -> Void) {
        cancel()
        token = CancellationToken()
        let current = token, worker = worker, style = Self.styleKey(settings)
        // Keep only settings that affect the silhouette. Backgrounds, opacity and
        // export options must neither invalidate the cache nor change a thumbnail.
        var framing = CompositionSettings()
        framing.display = settings.display; framing.phoneModel = settings.phoneModel
        framing.orientation = settings.orientation; framing.browser = settings.browser
        framing.windowRatio = settings.windowRatio
        framing.browserAppearance = settings.browserAppearance
        let work = DispatchWorkItem {
            for input in inputs {
                guard !current.isCancelled else { return }
                let result = autoreleasepool { Result { try worker.thumbnail(input, settings: framing, style: style) } }
                guard !current.isCancelled else { return }
                DispatchQueue.main.async {
                    guard !current.isCancelled else { return }
                    onResult(input.id, result)
                }
            }
        }
        pending = work
        queue.async(execute: work)
    }

    deinit { token.cancel(); pending?.cancel() }

    /// Cache and render closure are confined to the serial worker queue.
    private final class Worker {
        struct Key: Hashable {
            let inputID: String
            let style: String
            let modified: Date?
            let fileSize: Int?
        }
        struct Entry { let value: Thumbnail; var used: UInt64 }
        private let render: Render
        private let costLimit: Int, countLimit: Int
        private var cache: [Key: Entry] = [:]
        private var cost = 0
        private var clock: UInt64 = 0
        init(costLimit: Int, countLimit: Int, render: @escaping Render) {
            self.costLimit = max(0, costLimit); self.countLimit = max(0, countLimit); self.render = render
        }
        func thumbnail(_ input: ImageInput, settings: CompositionSettings, style: String) throws -> Thumbnail {
            let attributes = try input.url?.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let key = Key(inputID: input.id, style: style, modified: attributes?.contentModificationDate, fileSize: attributes?.fileSize)
            clock &+= 1
            if var entry = cache[key] {
                entry.used = clock; cache[key] = entry; return entry.value
            }
            let value = try render(input, settings)
            guard countLimit > 0, value.cost <= costLimit else { return value }
            while cache.count >= countLimit || cost + value.cost > costLimit {
                guard let oldest = cache.min(by: { $0.value.used < $1.value.used }) else { break }
                cost -= oldest.value.value.cost; cache.removeValue(forKey: oldest.key)
            }
            cache[key] = Entry(value: value, used: clock); cost += value.cost
            return value
        }
    }
}
