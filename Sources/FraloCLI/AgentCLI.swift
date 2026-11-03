import Foundation
import FraloCore
import Darwin

/// A separate command boundary keeps legacy render's crop, models and naming contract intact.
enum AgentCLI {
    static let commands = ["compose", "capabilities", "schema", "config", "guide", "example"]
    struct Failure: Error {
        let code: String
        let message: String
    }

    static func writeJSON(_ object: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
    }

    static func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
    }

    static func fail(_ code: String, _ message: String) throws -> Never { throw Failure(code: code, message: message) }

    static func run(_ arguments: [String]) -> Int32 {
        do { return try execute(arguments) }
        catch {
            let failure = error as? Failure ?? Failure(code: "internal_error", message: error.localizedDescription)
            // New commands always have machine-readable startup errors, even before --json is parsed.
            try? writeJSON(["schemaVersion": 1, "version": FraloInfo.version, "status": "error",
                            "error": ["code": failure.code, "message": failure.message]])
            return 2
        }
    }

    private static func execute(_ arguments: [String]) throws -> Int32 {
        let command = arguments[0], args = Array(arguments.dropFirst())
        if args == ["--help"] || args == ["-h"] {
            let usage = [
                "compose": "fralo compose INPUT... --output DIR [--config FILE | --app-settings] [--dry-run] [--overwrite] [--json]\nAdditional inputs: --input/-i PATH (repeatable); -- ends option parsing. Default config: built-in defaults.",
                "config": "fralo config [--defaults | --app] [--json]\nPrint a versioned composition snapshot; never writes App preferences.",
                "schema": "fralo schema [--json]\nPrint the JSON Schema for composition configuration v1.",
                "capabilities": "fralo capabilities [--json]\nPrint the short versioned directory of implemented CLI capabilities.",
                "example": "fralo example \(AgentGuide.examples.keys.sorted().joined(separator: "|"))\nPrint a runnable JSON configuration example.",
                "guide": "fralo guide\nPrint the full offline CLI guide."
            ]
            print(usage[command]! + "\nFull workflow: fralo guide"); return 0
        }
        switch command {
        case "guide":
            guard args.isEmpty else { try fail("invalid_arguments", "Usage: fralo guide") }
            print(AgentGuide.text); return 0
        case "capabilities":
            try onlyJSONFlag(args)
            try writeJSON(["schemaVersion": 1, "version": FraloInfo.version, "platform": "macOS 14+",
                           "commands": commands, "configurationSchemaVersion": 1,
                           "displays": DisplayKind.allCases.map(\.rawValue),
                           "phoneModels": CompositionSettings.phoneModels.map(\.rawValue),
                           "inputFormats": ["png", "jpeg"], "outputFormats": ImageFormat.allCases.map(\.rawValue),
                           "configuration": "fralo schema", "defaults": "fralo config --defaults",
                           "guide": "fralo guide", "examples": AgentGuide.examples.keys.sorted(),
                           "preflight": "fralo compose INPUT --output DIR --config FILE --dry-run --json",
                           "exitCodes": ["0": "finished (may include skipped files)", "1": "one or more entries failed", "2": "arguments/configuration/startup error", "130": "cancelled"],
                           "legacy": ["command": "render", "phoneModels": DeviceModel.allCases.map(\.rawValue), "configuration": "legacy saved settings; not the workbench composition"],
                           "networkRequired": false] as [String: Any]); return 0
        case "schema":
            try onlyJSONFlag(args); try writeJSON(CompositionConfiguration.schema()); return 0
        case "example":
            guard args.count == 1, let document = AgentGuide.examples[args[0]] else {
                try fail("invalid_arguments", "Usage: fralo example \(AgentGuide.examples.keys.sorted().joined(separator: "|"))")
            }
            print(document); return 0
        case "config":
            guard args.filter({ $0 != "--json" }).count <= 1, Set(args).count == args.count,
                  args.allSatisfy({ ["--app", "--defaults", "--json"].contains($0) }) else {
                try fail("invalid_arguments", "Usage: fralo config [--defaults | --app] [--json]")
            }
            let settings: CompositionSettings
            do { settings = args.contains("--app") ? try CompositionStore().load() : CompositionSettings() }
            catch { try fail("config_invalid", error.localizedDescription) }
            try writeJSON(object(settings)); return 0
        case "compose": return try compose(args)
        default: try fail("invalid_arguments", "Unknown command.")
        }
    }

    private static func onlyJSONFlag(_ args: [String]) throws {
        guard args.isEmpty || args == ["--json"] else { try fail("invalid_arguments", "Only --json is accepted by this command.") }
    }

    private struct Options {
        var inputs: [URL] = []
        var output: URL?
        var config: URL?
        var app = false, overwrite = false, dryRun = false, json = false
    }

    private static func path(_ value: String) -> URL {
        URL(fileURLWithPath: (value as NSString).expandingTildeInPath).standardizedFileURL
    }

    private static func options(_ args: [String]) throws -> Options {
        var result = Options(), index = 0, positional = false, seen = Set<String>()
        while index < args.count {
            let argument = args[index]
            if positional { result.inputs.append(path(argument)); index += 1; continue }
            func value() throws -> String {
                index += 1
                guard index < args.count, !args[index].hasPrefix("-") else {
                    try fail("invalid_arguments", "Missing path for \(argument); prefix paths beginning with a dash with ./.")
                }
                return args[index]
            }
            let canonical = argument == "-o" ? "--output" : argument
            if ["--output", "--config", "--app-settings", "--overwrite", "--dry-run", "--json"].contains(canonical),
               !seen.insert(canonical).inserted { try fail("invalid_arguments", "Repeated option: \(argument).") }
            switch argument {
            case "--": positional = true
            case "--input", "-i": result.inputs.append(path(try value()))
            case "--output", "-o": result.output = path(try value())
            case "--config": result.config = path(try value())
            case "--app-settings": result.app = true
            case "--overwrite": result.overwrite = true
            case "--dry-run": result.dryRun = true
            case "--json": result.json = true
            default:
                guard !argument.hasPrefix("-") else { try fail("invalid_arguments", "Unknown option: \(argument).") }
                result.inputs.append(path(argument))
            }
            index += 1
        }
        guard result.output != nil, !result.inputs.isEmpty else { try fail("invalid_arguments", "Provide INPUT... and --output DIR.") }
        guard !(result.app && result.config != nil) else { try fail("invalid_arguments", "Choose --config or --app-settings, not both.") }
        return result
    }

    private static func configuration(_ options: Options) throws -> CompositionSettings {
        do {
            if let url = options.config {
                let data: Data
                do { data = try Data(contentsOf: url) }
                catch { try fail("config_unreadable", "Cannot read config: \(url.path)") }
                return try CompositionConfiguration.decode(data, relativeTo: url.deletingLastPathComponent())
            }
            return options.app ? try CompositionStore().load() : CompositionSettings()
        } catch let error as Failure { throw error }
        catch CompositionConfigurationIssue.unknownFields(let names) { try fail("config_unknown_field", "Unknown fields: \(names.joined(separator: ", "))") }
        catch CompositionConfigurationIssue.missingVersion { try fail("config_version_missing", "Provide schemaVersion: 1.") }
        catch CompositionConfigurationIssue.unsupportedVersion { try fail("config_version_unsupported", "Supported schemaVersion: 1.") }
        catch { try fail("config_invalid", error.localizedDescription) }
    }

    private static func checkDestination(_ directory: URL) throws {
        let manager = FileManager.default
        var current = directory
        var isDirectory: ObjCBool = false
        while !manager.fileExists(atPath: current.path, isDirectory: &isDirectory) {
            if (try? manager.destinationOfSymbolicLink(atPath: current.path)) != nil {
                try fail("output_unavailable", "Output path contains a dangling symlink: \(current.path)")
            }
            let parent = current.deletingLastPathComponent()
            guard parent != current else { try fail("output_unavailable", "No existing output ancestor.") }
            current = parent
        }
        guard isDirectory.boolValue, manager.isWritableFile(atPath: current.path) else {
            try fail("output_unavailable", "Output directory or its nearest existing ancestor is not a writable directory: \(current.path)")
        }
    }

    private static func compose(_ args: [String]) throws -> Int32 {
        let options = try options(args), settings = try configuration(options), directory = options.output!
        let inputs: [ImageInput]
        do {
            // Stable canonical order also makes duplicate-stem naming independent of system language.
            inputs = try InputCollector.collect(options.inputs).sorted { $0.id.utf8.lexicographicallyPrecedes($1.id.utf8) }
        } catch { try fail("input_unreadable", error.localizedDescription) }
        guard !inputs.isEmpty else { try fail("input_empty", "No PNG/JPEG inputs found; directories are not searched recursively.") }
        try checkDestination(directory)
        let background: Data?
        do {
            background = try CompositionRenderer.backgroundData(settings)
            if let background { _ = try ImageInput(data: background, name: "background.png").decode(maxDimension: 1) }
        } catch { try fail("background_invalid", error.localizedDescription) }
        let names = BatchExporter.outputNames(for: inputs, format: settings.outputFormat)
        let sourcePaths = Set(inputs.map(\.id))
        var result: [String: Any] = ["schemaVersion": 1, "version": FraloInfo.version,
            "command": "compose", "dryRun": options.dryRun, "outputDirectory": directory.path,
            "configurationSource": options.config?.path ?? (options.app ? "app" : "defaults"),
            "configuration": try object(settings), "outputFormat": settings.outputFormat.rawValue]
        if options.dryRun {
            var entries: [[String: Any]] = []
            for (input, name) in zip(inputs, names) {
                let output = directory.appendingPathComponent(name)
                var entry: [String: Any] = ["input": input.name, "inputPath": input.id, "output": output.path, "status": "ready"]
                if sourcePaths.contains(output.resolvingSymlinksInPath().path) {
                    entry["status"] = "failed"; entry["code"] = "source_protected"
                } else if (FileManager.default.fileExists(atPath: output.path)
                           || (try? FileManager.default.destinationOfSymbolicLink(atPath: output.path)) != nil), !options.overwrite {
                    entry["status"] = "skipped"; entry["code"] = "output_exists"
                } else {
                    let attributes = try? FileManager.default.attributesOfItem(atPath: output.path)
                    if attributes?[.type] as? FileAttributeType == .typeDirectory {
                        entry["status"] = "failed"; entry["code"] = "output_write_failed"
                    } else {
                        do { _ = try input.decode(maxDimension: 1) }
                        catch { entry["status"] = "failed"; entry["code"] = "input_invalid"; entry["reason"] = error.localizedDescription }
                    }
                }
                entries.append(entry)
            }
            let failed = entries.filter { $0["status"] as? String == "failed" }.count
            result["status"] = failed > 0 ? "failed" : "ready"
            result["entries"] = entries; result["total"] = entries.count; result["failed"] = failed
            try emit(result, json: options.json); return failed > 0 ? 1 : 0
        }
        let cancellation = CancellationToken()
        signal(SIGINT, SIG_IGN); signal(SIGTERM, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        interrupt.setEventHandler { cancellation.cancel() }; terminate.setEventHandler { cancellation.cancel() }
        interrupt.resume(); terminate.resume()
        defer { interrupt.cancel(); terminate.cancel() }
        let report: ExportReport
        do {
            report = try BatchExporter.run(inputs: inputs,
                settings: RenderSettings(model: settings.phoneModel, orientation: settings.orientation), directory: directory,
                collisionPolicy: options.overwrite ? .replace : .skip, cancellation: cancellation,
                composition: settings, backgroundData: background) { progress in
                    if progress.completed < progress.total {
                        FileHandle.standardError.write(Data("[\(progress.completed)/\(progress.total)] \(progress.currentName)\n".utf8))
                    }
                }
        } catch { try fail("output_unavailable", error.localizedDescription) }
        let encoded = try object(report)
        for key in ["total", "cancelled", "durationSeconds", "succeeded", "skipped", "failed", "unprocessed"] { result[key] = encoded[key] }
        var entries = encoded["entries"] as! [[String: Any]]
        for index in entries.indices { entries[index]["inputPath"] = inputs[index].id }
        result["entries"] = entries
        result["status"] = report.cancelled ? "cancelled" : report.failed > 0 ? (report.succeeded > 0 ? "partial_failure" : "failed") : "completed"
        try emit(result, json: options.json)
        return report.cancelled ? 130 : report.failed > 0 ? 1 : 0
    }

    private static func emit(_ result: [String: Any], json: Bool) throws {
        if json { try writeJSON(result) }
        else {
            for entry in result["entries"] as? [[String: Any]] ?? [] {
                print("\(entry["status"]!)\t\(entry["inputPath"]!)\t\(entry["output"]!)\t\(entry["code"] as? String ?? "")")
            }
            print("\(result["status"]!)\t\(result["outputDirectory"]!)")
        }
    }
}
