import Foundation
import CoreGraphics

public enum DisplayKind: String, Codable, CaseIterable, Sendable { case phone, tablet, browser }
public enum CompositionMode: String, Codable, CaseIterable, Sendable { case transparent, background }
public enum BrowserStyle: String, Codable, CaseIterable, Sendable { case safari, chrome }
public enum WindowRatio: String, Codable, CaseIterable, Sendable {
    case standard = "16:10", wide = "16:9", classic = "4:3"
    public var ratio: Double { self == .standard ? 1.6 : self == .wide ? 16.0 / 9 : 4.0 / 3 }
}
public enum CanvasRatio: String, Codable, CaseIterable, Sendable {
    case square = "1:1", landscape = "4:3", wide = "16:9", portrait = "3:4", story = "9:16"
    public var size: CGSize {
        switch self {
        case .square: return .init(width: 2400, height: 2400)
        case .landscape: return .init(width: 2400, height: 1800)
        case .wide: return .init(width: 2400, height: 1350)
        case .portrait: return .init(width: 1800, height: 2400)
        case .story: return .init(width: 1350, height: 2400)
        }
    }
}
public enum BackgroundKind: String, Codable, CaseIterable, Sendable { case solid, gradient, warm, mist, sage, local }
public enum ShadowStyle: String, Codable, CaseIterable, Sendable { case none, soft, strong }
public enum ImageFormat: String, Codable, CaseIterable, Sendable { case png, jpeg }
public struct ArtworkColor: Codable, Equatable, Sendable {
    public var red: Double, green: Double, blue: Double
    public init(_ red: Double, _ green: Double, _ blue: Double) { self.red = red; self.green = green; self.blue = blue }
    public var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    var isValid: Bool { [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) } }
}

/// GUI composition preferences are separate from the legacy CLI render contract.
public struct CompositionSettings: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var display: DisplayKind = .phone
    public var orientation: Orientation = .portrait
    public var browser: BrowserStyle = .safari
    public var windowRatio: WindowRatio = .standard
    public var mode: CompositionMode = .transparent
    public var canvas: CanvasRatio = .landscape
    public var deviceScale = 0.74
    public var deviceX = 0.0, deviceY = 0.0
    public var deviceOpacity = 1.0
    public var background: BackgroundKind = .warm
    public var backgroundColor = ArtworkColor(0.88, 0.87, 0.84)
    public var localBackgroundPath: String?
    public var backgroundScale = 1.0
    public var backgroundX = 0.0, backgroundY = 0.0
    public var backgroundOpacity = 1.0
    public var transparentShadow: ShadowStyle = .none
    public var backgroundShadow: ShadowStyle = .soft
    public var format: ImageFormat = .png
    public var jpegQuality = 0.9
    public var jpegFill = ArtworkColor(1, 1, 1)
    public var shadow: ShadowStyle { mode == .transparent ? transparentShadow : backgroundShadow }
    public init() {}
    public func validated() throws -> Self {
        let values: [(Double, ClosedRange<Double>)] = [(deviceScale, 0.1...1.5), (deviceX, -1...1), (deviceY, -1...1),
            (deviceOpacity, 0...1), (backgroundScale, 1...4), (backgroundX, -1...1), (backgroundY, -1...1),
            (backgroundOpacity, 0...1), (jpegQuality, 0.1...1)]
        guard schemaVersion == 1, values.allSatisfy({ $0.0.isFinite && $0.1.contains($0.0) }), backgroundColor.isValid, jpegFill.isValid else {
            throw FraloError.message("成图配置包含不支持的版本或无效数值。")
        }
        return self
    }
}

public struct CompositionStore: Sendable {
    public let url: URL
    public let legacy: SettingsStore
    public init(legacy: SettingsStore = SettingsStore()) {
        self.legacy = legacy
        url = legacy.url.deletingPathExtension().appendingPathExtension("workbench.json")
    }
    public func load() throws -> CompositionSettings {
        if FileManager.default.fileExists(atPath: url.path) {
            return try JSONDecoder().decode(CompositionSettings.self, from: Data(contentsOf: url)).validated()
        }
        var settings = CompositionSettings()
        settings.orientation = try legacy.load().orientation
        return settings
    }
    public func save(_ settings: CompositionSettings) throws {
        let settings = try settings.validated()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url, options: .atomic)
    }
}
