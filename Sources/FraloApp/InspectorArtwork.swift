import AppKit
import FraloCore

struct InspectorArtworkResult {
    let frames: [CGImage?]
    let backgrounds: [CGImage?]
}

/// Fixed explanatory assets, independent of the user's batch and preview renders.
@MainActor
final class InspectorArtwork {
    private static var cache: [String: InspectorArtworkResult] = [:]
    private static let backgrounds: [CGImage?] = [BackgroundKind.warm, .mist, .sage].map { background in
        var settings = CompositionSettings(); settings.mode = .background; settings.background = background
        guard let bytes = try? CompositionRenderer.backgroundData(settings) else { return nil }
        return try? ImageInput(data: bytes, name: "background-preview.png").decode(maxDimension: 200)
    }
    func load(display: DisplayKind, completion: (InspectorArtworkResult) -> Void) {
        if let cached = Self.cache[display.rawValue] { completion(cached); return }
        let suffixes = display == .browser ? ["safari", "chrome"] : ["portrait", "landscape"]
        let frames: [CGImage?] = suffixes.map { suffix in
            guard let url = Bundle.module.url(forResource: "\(display.rawValue)-\(suffix)", withExtension: "png", subdirectory: "Resources/InspectorDemos") else { return nil }
            return try? ImageInput(url: url).decode()
        }
        let result = InspectorArtworkResult(frames: frames, backgrounds: Self.backgrounds)
        Self.cache[display.rawValue] = result; completion(result)
    }
}
