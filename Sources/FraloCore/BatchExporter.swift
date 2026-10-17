import Foundation
import Darwin

public final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    public init() {}
    public func cancel() { lock.lock(); value = true; lock.unlock() }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

public struct ExportEntry: Codable, Sendable {
    public enum Status: String, Codable, Sendable { case success, skipped, failed }
    public let input: String
    public let output: String
    public let status: Status
    public let reason: String?
}

public struct ExportReport: Codable, Sendable {
    public let settings: RenderSettings
    public let entries: [ExportEntry]
    public let total: Int
    public let cancelled: Bool
    public let durationSeconds: Double
    public var succeeded: Int { entries.filter { $0.status == .success }.count }
    public var skipped: Int { entries.filter { $0.status == .skipped }.count }
    public var failed: Int { entries.filter { $0.status == .failed }.count }
    public var unprocessed: Int { total - entries.count }

    enum CodingKeys: String, CodingKey { case settings, entries, total, cancelled, durationSeconds, succeeded, skipped, failed, unprocessed }
    public init(settings: RenderSettings, entries: [ExportEntry], total: Int, cancelled: Bool, durationSeconds: Double) {
        self.settings = settings; self.entries = entries; self.total = total; self.cancelled = cancelled; self.durationSeconds = durationSeconds
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = try c.decode(RenderSettings.self, forKey: .settings); entries = try c.decode([ExportEntry].self, forKey: .entries)
        total = try c.decode(Int.self, forKey: .total); cancelled = try c.decode(Bool.self, forKey: .cancelled); durationSeconds = try c.decode(Double.self, forKey: .durationSeconds)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(settings, forKey: .settings); try c.encode(entries, forKey: .entries); try c.encode(total, forKey: .total)
        try c.encode(cancelled, forKey: .cancelled); try c.encode(durationSeconds, forKey: .durationSeconds)
        try c.encode(succeeded, forKey: .succeeded); try c.encode(skipped, forKey: .skipped); try c.encode(failed, forKey: .failed); try c.encode(unprocessed, forKey: .unprocessed)
    }
}

public struct ExportProgress: Sendable {
    public let completed: Int
    public let total: Int
    public let currentName: String
}

public enum BatchExporter {
    public static func outputNames(for inputs: [ImageInput]) -> [String] {
        var used = Set<String>()
        return inputs.map { input in
            let stem = input.stem.isEmpty ? "图片" : input.stem
            var candidate = "\(stem)-fralo.png", suffix = 2
            while !used.insert(candidate.lowercased()).inserted {
                candidate = "\(stem)-fralo-\(suffix).png"; suffix += 1
            }
            return candidate
        }
    }

    public static func run(inputs: [ImageInput], settings: RenderSettings, directory: URL, overwrite: Bool = false,
                           cancellation: CancellationToken = CancellationToken(),
                           outputNames explicitNames: [String]? = nil,
                           progress: (ExportProgress) -> Void = { _ in }) throws -> ExportReport {
        let settings = try settings.validated()
        guard !inputs.isEmpty else { throw FraloError.message("没有可导出的图片。") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let names = explicitNames ?? outputNames(for: inputs)
        guard names.count == inputs.count else { throw FraloError.message("导出文件名数量不匹配。") }
        let started = Date()
        var entries: [ExportEntry] = []
        let inputPaths = Set(inputs.compactMap { $0.url?.standardizedFileURL.resolvingSymlinksInPath().path })
        for (index, input) in inputs.enumerated() {
            if cancellation.isCancelled { break }
            let name = names[index]
            guard !name.isEmpty, (name as NSString).lastPathComponent == name, name != ".", name != ".." else {
                throw FraloError.message("输出文件名必须是文件名，不可包含目录。")
            }
            let output = directory.appendingPathComponent(name)
            progress(ExportProgress(completed: entries.count, total: inputs.count, currentName: input.name))
            let entry: ExportEntry = autoreleasepool {
                do {
                    guard !inputPaths.contains(output.standardizedFileURL.resolvingSymlinksInPath().path) else {
                        throw FraloError.message("不能覆盖任何原始截图。")
                    }
                    if !overwrite && FileManager.default.fileExists(atPath: output.path) {
                        return ExportEntry(input: input.name, output: output.path, status: .skipped, reason: "已有同名文件")
                    }
                    let frame = try FrameRenderer.render(input, settings: settings)
                    let data = try FrameRenderer.pngData(frame.image)
                    let written = try write(data, to: output, overwrite: overwrite)
                    return ExportEntry(input: input.name, output: output.path, status: written ? .success : .skipped, reason: written ? nil : "已有同名文件")
                } catch {
                    return ExportEntry(input: input.name, output: output.path, status: .failed, reason: error.localizedDescription)
                }
            }
            entries.append(entry)
            progress(ExportProgress(completed: entries.count, total: inputs.count, currentName: input.name))
        }
        return ExportReport(settings: settings, entries: entries, total: inputs.count, cancelled: cancellation.isCancelled, durationSeconds: Date().timeIntervalSince(started))
    }

    private static func write(_ data: Data, to destination: URL, overwrite: Bool) throws -> Bool {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".fralo-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        let result = temporary.withUnsafeFileSystemRepresentation { source in
            destination.withUnsafeFileSystemRepresentation { target in overwrite ? Darwin.rename(source!, target!) : Darwin.link(source!, target!) }
        }
        if result == 0 { return true }
        if !overwrite && errno == EEXIST { return false }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: destination.path])
    }
}
