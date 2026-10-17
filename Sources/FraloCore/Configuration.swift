import Foundation

public enum Orientation: String, Codable, CaseIterable, Sendable {
    case portrait, landscape
    public var title: String { self == .portrait ? "竖屏" : "横屏" }
}

public enum DeviceModel: String, Codable, CaseIterable, Sendable {
    case iPhone16Pro = "iphone-16-pro"
    case iPhone16ProMax = "iphone-16-pro-max"
    case iPhone17Pro = "iphone-17-pro"
    case iPhone17ProMax = "iphone-17-pro-max"
    case iPhone18Pro = "iphone-18-pro"
    case iPhone18ProMax = "iphone-18-pro-max"

    public var title: String {
        rawValue.replacingOccurrences(of: "iphone-", with: "iPhone ")
            .replacingOccurrences(of: "-pro-max", with: " Pro Max")
            .replacingOccurrences(of: "-pro", with: " Pro")
    }
    public var isMax: Bool { rawValue.hasSuffix("max") }
    public var generation: Int { rawValue.contains("16") ? 16 : rawValue.contains("17") ? 17 : 18 }
    public var screenWidth: Double { isMax ? 1320 : 1206 }
    public var screenHeight: Double { isMax ? 2868 : 2622 }
    // Original artwork parameters, calibrated to Simulator screen sizes and the accepted frame study.
    public var bezel: Double { screenWidth * (generation == 16 ? 0.040 : generation == 17 ? 0.038 : 0.036) }
    public var screenRadius: Double { screenWidth * 0.1194 }
}

public struct RenderSettings: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var model: DeviceModel
    public var orientation: Orientation
    public var padding: Int

    public init(model: DeviceModel = .iPhone18ProMax, orientation: Orientation = .portrait, padding: Int = 0) {
        self.model = model; self.orientation = orientation; self.padding = padding
    }
    public func validated() throws -> Self {
        guard schemaVersion == 1 else { throw FraloError.message("配置版本不受支持：\(schemaVersion)") }
        guard (0...2048).contains(padding) else { throw FraloError.message("透明边距须为 0–2048 px 的整数。") }
        return self
    }
}

public enum FraloError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

public struct SettingsStore: Sendable {
    public let url: URL
    public init(url: URL? = nil) {
        if let url { self.url = url }
        else if let path = ProcessInfo.processInfo.environment["FRALO_SETTINGS_PATH"] {
            self.url = URL(fileURLWithPath: path)
        } else {
            self.url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Fralo/settings.json")
        }
    }
    public func load() throws -> RenderSettings {
        guard FileManager.default.fileExists(atPath: url.path) else { return RenderSettings() }
        do { return try JSONDecoder().decode(RenderSettings.self, from: Data(contentsOf: url)).validated() }
        catch { throw FraloError.message("无法读取配置 \(url.path)：\(error.localizedDescription)") }
    }
    public func save(_ settings: RenderSettings) throws {
        let settings = try settings.validated()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: url, options: .atomic)
    }
}
