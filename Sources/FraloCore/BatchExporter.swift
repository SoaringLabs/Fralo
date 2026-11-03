import FraloLocalization
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
    /// Stable machine code for composition exports; legacy render reports stay unchanged.
    public var code: String? = nil
}

public struct ExportReport: Codable, Sendable {
    public let settings: RenderSettings
    public var composition: CompositionSettings?
    public let entries: [ExportEntry]
    public let total: Int
    public let cancelled: Bool
    public let durationSeconds: Double
    public var succeeded: Int { entries.filter { $0.status == .success }.count }
    public var skipped: Int { entries.filter { $0.status == .skipped }.count }
    public var failed: Int { entries.filter { $0.status == .failed }.count }
    public var unprocessed: Int { total - entries.count }

    enum CodingKeys: String, CodingKey { case settings, composition, entries, total, cancelled, durationSeconds, succeeded, skipped, failed, unprocessed }
    public init(settings: RenderSettings, entries: [ExportEntry], total: Int, cancelled: Bool, durationSeconds: Double) {
        self.settings = settings; self.entries = entries; self.total = total; self.cancelled = cancelled; self.durationSeconds = durationSeconds
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        composition = try c.decodeIfPresent(CompositionSettings.self, forKey: .composition)
        settings = try c.decode(RenderSettings.self, forKey: .settings); entries = try c.decode([ExportEntry].self, forKey: .entries)
        total = try c.decode(Int.self, forKey: .total); cancelled = try c.decode(Bool.self, forKey: .cancelled); durationSeconds = try c.decode(Double.self, forKey: .durationSeconds)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(composition, forKey: .composition)
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
    public enum CollisionPolicy: Sendable { case skip, keepBoth, replace }

    private static func timestamp(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    public static func exportFolderName(for date: Date, timeZone: TimeZone = .current) -> String {
        "fralo-\(timestamp(for: date, timeZone: timeZone))"
    }

    /// A date opts into the app's versioned names. Nil preserves the CLI's stable names.
    public static func outputNames(for inputs: [ImageInput], format: ImageFormat = .png,
                                   date: Date? = nil, timeZone: TimeZone = .current) -> [String] {
        let suffixName = format == .png ? "png" : "jpg"
        let timestamp = date.map { Self.timestamp(for: $0, timeZone: timeZone) }
        var used = Set<String>()
        return inputs.map { input in
            let stem = input.stem.isEmpty ? L10n.tr("图片") : input.stem
            let base = timestamp.map { "fralo-\(stem)-\($0)" } ?? "\(stem)-fralo"
            var candidate = "\(base).\(suffixName)", suffix = 2
            while !used.insert(candidate.lowercased()).inserted {
                candidate = "\(base)-\(suffix).\(suffixName)"; suffix += 1
            }
            return candidate
        }
    }

    /// Also treats directories and dangling symlinks as occupied names.
    public static func availableOutputURL(for preferred: URL, reservingFileNames: Set<String> = []) -> URL {
        let stem = preferred.deletingPathExtension().lastPathComponent
        let ext = preferred.pathExtension
        var candidate = preferred, suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path)) != nil
            || reservingFileNames.contains(candidate.lastPathComponent.lowercased()) {
            let name = "\(stem)-\(suffix)" + (ext.isEmpty ? "" : ".\(ext)")
            candidate = preferred.deletingLastPathComponent().appendingPathComponent(name, isDirectory: preferred.hasDirectoryPath)
            suffix += 1
        }
        return candidate
    }

    /// App exports own a new directory; the CLI continues to use run's explicit destination.
    public static func runInNewDirectory(inputs: [ImageInput], settings: RenderSettings, parentDirectory: URL,
                                         date: Date = Date(), timeZone: TimeZone = .current,
                                         cancellation: CancellationToken = CancellationToken(),
                                         outputNames explicitNames: [String]? = nil,
                                         composition: CompositionSettings? = nil, backgroundData: Data? = nil,
                                         progress: (ExportProgress) -> Void = { _ in }) throws -> (directory: URL, report: ExportReport) {
        guard !inputs.isEmpty else { throw FraloError.message(L10n.tr("没有可导出的图片。")) }
        let settings = try settings.validated(), composition = try composition?.validated()
        let backdrop = try backgroundData ?? composition.flatMap { try CompositionRenderer.backgroundData($0) }
        let names = explicitNames ?? outputNames(for: inputs, format: composition?.outputFormat ?? .png, date: date, timeZone: timeZone)
        try validateOutputNames(names, count: inputs.count)
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        let preferred = parentDirectory.appendingPathComponent(exportFolderName(for: date, timeZone: timeZone), isDirectory: true)
        let directory: URL
        while true {
            let candidate = availableOutputURL(for: preferred)
            let result = candidate.withUnsafeFileSystemRepresentation { Darwin.mkdir($0!, 0o777) }
            if result == 0 { directory = candidate; break }
            let code = errno
            if code == EEXIST { continue }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: candidate.path])
        }
        do {
            let report = try run(inputs: inputs, settings: settings, directory: directory, collisionPolicy: .keepBoth,
                                 cancellation: cancellation, outputNames: names, composition: composition,
                                 backgroundData: backdrop, progress: progress)
            return (directory, report)
        } catch {
            // Remove only an empty directory we just created. Partial output must survive.
            _ = directory.withUnsafeFileSystemRepresentation { Darwin.rmdir($0!) }
            throw error
        }
    }

    private static func validateOutputNames(_ names: [String], count: Int) throws {
        guard names.count == count else { throw FraloError.message(L10n.tr("导出文件名数量不匹配。")) }
        guard names.allSatisfy({ !$0.isEmpty && ($0 as NSString).lastPathComponent == $0 && $0 != "." && $0 != ".." }) else {
            throw FraloError.message(L10n.tr("输出文件名必须是文件名，不可包含目录。"))
        }
    }

    public static func run(inputs: [ImageInput], settings: RenderSettings, directory: URL, collisionPolicy: CollisionPolicy = .skip,
                           cancellation: CancellationToken = CancellationToken(),
                           outputNames explicitNames: [String]? = nil, composition: CompositionSettings? = nil, backgroundData: Data? = nil,
                           progress: (ExportProgress) -> Void = { _ in }) throws -> ExportReport {
        let settings = try settings.validated()
        let composition = try composition?.validated()
        let backdrop = try backgroundData ?? composition.flatMap { try CompositionRenderer.backgroundData($0) }
        guard !inputs.isEmpty else { throw FraloError.message(L10n.tr("没有可导出的图片。")) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let names = explicitNames ?? outputNames(for: inputs, format: composition?.outputFormat ?? .png)
        try validateOutputNames(names, count: inputs.count)
        let started = Date()
        var entries: [ExportEntry] = []
        let inputPaths = Set(inputs.compactMap { $0.url?.standardizedFileURL.resolvingSymlinksInPath().path })
        let reservedNames = Set(names.map { $0.lowercased() })
        for (index, input) in inputs.enumerated() {
            if cancellation.isCancelled { break }
            let name = names[index]
            let preferred = directory.appendingPathComponent(name, isDirectory: false)
            let otherNames = reservedNames.subtracting([name.lowercased()])
            let output = collisionPolicy == .keepBoth
                ? availableOutputURL(for: preferred, reservingFileNames: otherNames) : preferred
            progress(ExportProgress(completed: entries.count, total: inputs.count, currentName: input.name))
            let entry: ExportEntry = autoreleasepool {
                var failureCode = "source_protected"
                do {
                    guard !inputPaths.contains(output.standardizedFileURL.resolvingSymlinksInPath().path) else {
                        throw FraloError.message(L10n.tr("不能覆盖任何原始截图。"))
                    }
                    let occupied = FileManager.default.fileExists(atPath: output.path)
                        || (composition != nil && (try? FileManager.default.destinationOfSymbolicLink(atPath: output.path)) != nil)
                    if collisionPolicy == .skip && occupied {
                        return ExportEntry(input: input.name, output: output.path, status: .skipped, reason: L10n.tr("已有同名文件"), code: composition == nil ? nil : "output_exists")
                    }
                    if composition != nil { failureCode = "input_invalid"; _ = try input.dimensions() }
                    failureCode = "render_failed"
                    let data: Data
                    if let composition {
                        let frame = try CompositionRenderer.render(input, settings: composition, backgroundData: backdrop)
                        data = try CompositionRenderer.data(frame.image, settings: composition)
                    } else {
                        let frame = try FrameRenderer.render(input, settings: settings)
                        data = try FrameRenderer.pngData(frame.image)
                    }
                    failureCode = "output_write_failed"
                    let written = try write(data, to: preferred, collisionPolicy: collisionPolicy, reservingFileNames: otherNames)
                    return ExportEntry(input: input.name, output: written?.path ?? output.path,
                                       status: written != nil ? .success : .skipped,
                                       reason: written != nil ? nil : L10n.tr("已有同名文件"),
                                       code: composition == nil || written != nil ? nil : "output_exists")
                } catch {
                    return ExportEntry(input: input.name, output: output.path, status: .failed, reason: error.localizedDescription,
                                       code: composition == nil ? nil : failureCode)
                }
            }
            entries.append(entry)
            progress(ExportProgress(completed: entries.count, total: inputs.count, currentName: input.name))
        }
        var report = ExportReport(settings: settings, entries: entries, total: inputs.count, cancelled: cancellation.isCancelled, durationSeconds: Date().timeIntervalSince(started))
        report.composition = composition; return report
    }

    private static func write(_ data: Data, to preferred: URL, collisionPolicy: CollisionPolicy,
                              reservingFileNames: Set<String>) throws -> URL? {
        let temporary = preferred.deletingLastPathComponent().appendingPathComponent(".fralo-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        while true {
            let destination = collisionPolicy == .keepBoth
                ? availableOutputURL(for: preferred, reservingFileNames: reservingFileNames) : preferred
            let result = temporary.withUnsafeFileSystemRepresentation { source in
                destination.withUnsafeFileSystemRepresentation { target in
                    collisionPolicy == .replace ? Darwin.rename(source!, target!)
                        : Darwin.renamex_np(source!, target!, UInt32(RENAME_EXCL))
                }
            }
            if result == 0 { return destination }
            let code = errno
            if code == EEXIST {
                if collisionPolicy == .keepBoth { continue }
                if collisionPolicy == .skip { return nil }
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: destination.path])
        }
    }
}
