import XCTest
import CoreGraphics
@testable import FraloCore

/// Runs against the actual CLI, comparing its exported bytes with the GUI's renderer.
/// CI supplies FRALO_CLI_BINARY after building Release; ordinary swift test skips it.
final class CLICompositionReferenceTests: XCTestCase {
    func testCLIAndGUIRendererAgreeForCompositionAndEveryMovementDirection() throws {
        guard let binary = ProcessInfo.processInfo.environment["FRALO_CLI_BINARY"] else {
            throw XCTSkip("Set FRALO_CLI_BINARY to exercise actual CLI/GUI output parity")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let context = try XCTUnwrap(CompositionRenderer.bitmap(CGSize(width: 64, height: 32)))
        context.setFillColor(CGColor(srgbRed: 1, green: 0.1, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        context.setFillColor(CGColor(srgbRed: 0.1, green: 1, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 32, y: 0, width: 32, height: 32))
        let inputURL = root.appendingPathComponent("source.png")
        try FrameRenderer.pngData(XCTUnwrap(context.makeImage())).write(to: inputURL)
        let input = ImageInput(url: inputURL), configURL = root.appendingPathComponent("recipe.json")
        var cases: [CompositionSettings] = []
        for display in DisplayKind.allCases {
            var settings = CompositionSettings(); settings.display = display; settings.transparentShadow = .soft
            cases.append(settings)
        }
        for (x, y) in [(-0.2, 0.0), (0.2, 0.0), (0.0, -0.2), (0.0, 0.2), (-0.2, -0.2), (-0.2, 0.2), (0.2, -0.2), (0.2, 0.2)] {
            var settings = CompositionSettings(); settings.display = .browser; settings.mode = .background
            settings.browser = .chrome; settings.browserAppearance = .dark; settings.background = .sage
            settings.deviceX = x; settings.deviceY = y; settings.deviceScale = 0.6; settings.deviceOpacity = 0.8
            settings.backgroundScale = 2; settings.backgroundX = x; settings.backgroundY = y; settings.backgroundOpacity = 0.7
            settings.backgroundShadow = .strong; cases.append(settings)
        }
        var jpeg = CompositionSettings(); jpeg.display = .tablet; jpeg.orientation = .landscape
        jpeg.mode = .background; jpeg.background = .gradient; jpeg.format = .jpeg; jpeg.jpegQuality = 0.5
        cases.append(jpeg)
        for (index, settings) in cases.enumerated() {
            try JSONEncoder().encode(settings).write(to: configURL)
            let process = Process(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = ["compose", inputURL.path, "--output", root.appendingPathComponent("out-\(index)").path,
                                 "--config", configURL.path, "--json"]
            process.standardOutput = output; process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, String(data: data, encoding: .utf8) ?? "No CLI response")
            let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let entries = try XCTUnwrap(report["entries"] as? [[String: Any]])
            let destination = try XCTUnwrap(entries.first?["output"] as? String)
            let frame = try CompositionRenderer.render(input, settings: settings)
            let expected = try CompositionRenderer.data(frame.image, settings: settings)
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: destination)), expected,
                           "Actual exported bytes differ for case \(index), \(settings.display)")
        }
    }
}
