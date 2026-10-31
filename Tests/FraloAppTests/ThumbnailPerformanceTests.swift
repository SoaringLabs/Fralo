import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class ThumbnailPerformanceTests: XCTestCase {
    /// Opt-in end-to-end measurement; timings are observations, not CI deadlines.
    @MainActor func testLargeBatchDeviceSwitchBenchmark() async throws {
        guard ProcessInfo.processInfo.environment["FRALO_THUMBNAIL_BENCHMARK"] == "1" else {
            throw XCTSkip("Set FRALO_THUMBNAIL_BENCHMARK=1 to run the thumbnail benchmark")
        }
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "fralo-thumbnail-benchmark-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FraloApp/Development/Fixtures/03-journal.png")
        let count = Int(ProcessInfo.processInfo.environment["FRALO_THUMBNAIL_COUNT"] ?? "100") ?? 100
        let inputs = try (0..<count).map { index -> URL in
            let url = directory.appendingPathComponent("image-\(index).png")
            try FileManager.default.copyItem(at: fixture, to: url)
            return url
        }
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); window.isReleasedWhenClosed = false
        defer { controller.newBatch(nil); window.close() }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let list = try XCTUnwrap(root.left.body as? BatchList)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let inspector = try XCTUnwrap(descendants(root).compactMap { $0 as? CompositionInspector }.first)
        func wait(_ label: String, since start: Date, until ready: () -> Bool) async throws {
            var previous = Date(), maximumGap = 0.0
            while !ready(), Date().timeIntervalSince(start) < 60 {
                try await Task.sleep(nanoseconds: 5_000_000)
                let now = Date(); maximumGap = max(maximumGap, now.timeIntervalSince(previous)); previous = now
            }
            XCTAssertTrue(ready(), "\(label) did not finish")
            print("THUMBNAIL_BENCH count=\(count) phase=\(label) seconds=\(Date().timeIntervalSince(start)) maxMainGap=\(maximumGap)")
        }
        let initial = inspector.settings
        let start = Date(); controller.importURLs(inputs)
        try await wait("initial", since: start) { list.entries.allSatisfy { $0.image != nil } }
        var next = initial; next.orientation = .landscape
        let rapid = Date()
        inspector.onChange?(next)
        next.display = .tablet; inspector.onChange?(next)
        next.display = .browser; inspector.onChange?(next)
        try await wait("rapid-three-switches", since: rapid) {
            list.entries.allSatisfy { ($0.image?.size.width ?? 0) > ($0.image?.size.height ?? 0) }
        }
        // All browser thumbnails must finish, not just an intermediate landscape device.
        let expected = try CompositionRenderer.render(ImageInput(url: fixture), settings: {
            var s = next; s.mode = .transparent; s.transparentShadow = .none; s.deviceOpacity = 1; return s
        }(), maxDimension: 180).image
        try await wait("final-browser", since: rapid) {
            list.entries.allSatisfy { $0.image?.size == NSSize(width: expected.width, height: expected.height) }
        }
        let back = Date(); inspector.onChange?(initial)
        try await wait("return-phone", since: back) {
            list.entries.allSatisfy { ($0.image?.size.height ?? 0) > ($0.image?.size.width ?? 0) }
        }
    }
}
