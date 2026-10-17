import Foundation
import FraloCore
import Darwin

private let usage = """
Fralo \(FraloInfo.version) — 本地批量截图套框 · \(FraloInfo.developer)

用法：
  fralo render <图片或文件夹>... --output <目录> [选项]
  fralo models [--json]
  fralo settings

选项：
  --input, -i <路径>          追加输入，可重复；文件夹只读当前层
  --output, -o <目录>        输出目录（必填）
  --model <ID>               例如 iphone-18-pro-max，fralo models 查看全部
  --orientation <方向>       portrait 或 landscape（竖屏或横屏）
  --padding <像素>           四周透明边距，0–2048
  --overwrite                显式允许覆盖已有输出；始终保护原始输入
  --json                     标准输出为 JSON；进度写到标准错误
  --help, -h                 帮助
  --version                  版本

配置优先级：内置默认值 → App 已保存设置 → 本次明确参数。
CLI 参数不会改写 App 设置。按 Ctrl-C 取消，保留已完成文件。
退出码：0 完成（可含跳过），1 部分/全部失败，2 参数或启动失败，130 取消。
"""

private func stderr(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }
private func json<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    FileHandle.standardOutput.write(try encoder.encode(value)); print("")
}

private func run() throws -> Int32 {
    var args = Array(CommandLine.arguments.dropFirst())
    if args.isEmpty || args.contains("--help") || args.contains("-h") { print(usage); return 0 }
    if args == ["--version"] { print("fralo \(FraloInfo.version)"); return 0 }
    if args.first == "models" {
        struct ModelDescription: Encodable { let id: String; let name: String; let screenWidth: Int; let screenHeight: Int }
        let models = DeviceModel.allCases.map { ModelDescription(id: $0.rawValue, name: $0.title, screenWidth: Int($0.screenWidth), screenHeight: Int($0.screenHeight)) }
        if args.contains("--json") { try json(models) } else { models.forEach { print("\($0.id)\t\($0.name)") } }
        return 0
    }
    if args.first == "settings" {
        struct SettingsDescription: Encodable { let path: String; let settings: RenderSettings }
        let store = SettingsStore(); try json(SettingsDescription(path: store.url.path, settings: try store.load())); return 0
    }
    if args.first == "render" { args.removeFirst() }
    var paths: [URL] = [], directory: URL?, model: DeviceModel?, orientation: Orientation?, padding: Int?
    var overwrite = false, machineReadable = false, index = 0, positionalOnly = false
    func path(_ value: String) -> URL { URL(fileURLWithPath: (value as NSString).expandingTildeInPath) }
    func argument(_ flag: String) throws -> String {
        index += 1
        guard index < args.count else { throw FraloError.message("\(flag) 缺少参数。") }
        return args[index]
    }
    while index < args.count {
        let option = args[index]
        if positionalOnly { paths.append(path(option)); index += 1; continue }
        switch option {
        case "--": positionalOnly = true
        case "--input", "-i": paths.append(path(try argument(option)))
        case "--output", "-o": directory = path(try argument(option))
        case "--model":
            let value = try argument(option)
            guard let value = DeviceModel(rawValue: value) else { throw FraloError.message("未知设备：\(value)。使用 fralo models 查看设备 ID。") }
            model = value
        case "--orientation":
            let value = try argument(option)
            guard let value = Orientation(rawValue: value) else { throw FraloError.message("方向只能是 portrait 或 landscape。") }
            orientation = value
        case "--padding":
            let value = try argument(option)
            guard let value = Int(value) else { throw FraloError.message("边距必须为整数。") }
            padding = value
        case "--overwrite": overwrite = true
        case "--json": machineReadable = true
        default:
            guard !option.hasPrefix("-") else { throw FraloError.message("未知参数：\(option)") }
            paths.append(path(option))
        }
        index += 1
    }
    guard let directory else { throw FraloError.message("请用 --output 指定输出目录。") }
    guard !paths.isEmpty else { throw FraloError.message("请提供至少一个输入文件或文件夹。") }
    let inputs = try InputCollector.collect(paths)
    var settings = try SettingsStore().load()
    if let model { settings.model = model }
    if let orientation { settings.orientation = orientation }
    if let padding { settings.padding = padding }
    settings = try settings.validated()
    let cancellation = CancellationToken()
    signal(SIGINT, SIG_IGN); signal(SIGTERM, SIG_IGN)
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
    let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
    interrupt.setEventHandler { cancellation.cancel() }; terminate.setEventHandler { cancellation.cancel() }
    interrupt.resume(); terminate.resume()
    defer { interrupt.cancel(); terminate.cancel() }
    let report = try BatchExporter.run(inputs: inputs, settings: settings, directory: directory, overwrite: overwrite, cancellation: cancellation) { progress in
        if progress.completed < progress.total { stderr("[\(progress.completed)/\(progress.total)] \(progress.currentName)") }
    }
    if machineReadable { try json(report) } else {
        for entry in report.entries {
            print("\(entry.status.rawValue)\t\(entry.input)\t\(entry.output)\(entry.reason.map { "\t" + $0 } ?? "")")
        }
        print("成功 \(report.succeeded)，跳过 \(report.skipped)，失败 \(report.failed)，未处理 \(report.unprocessed)；\(String(format: "%.2f", report.durationSeconds)) 秒")
    }
    return report.cancelled ? 130 : report.failed > 0 ? 1 : 0
}

do { exit(try run()) }
catch { stderr("fralo: \(error.localizedDescription)"); exit(2) }
