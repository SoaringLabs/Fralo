import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class PhoneModelZoomTests: XCTestCase {
    @MainActor func testSwitchingPhoneModelsKeepsFitStableAndActualPixelsNative() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "fralo-phone-zoom-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let inspector = try XCTUnwrap(root.right.body as? CompositionInspector)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let canvas = try XCTUnwrap(descendants(root).compactMap { $0 as? CanvasSurface }.first)
        let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 40))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("input.png")
        try FrameRenderer.pngData(XCTUnwrap(context.makeImage())).write(to: url)
        controller.importURLs([url])

        func choose(_ index: Int) async throws {
            let picker = try XCTUnwrap(descendants(inspector).compactMap { $0 as? VisualChoiceGroup }.first { $0.accessibilityLabel() == "机型" })
            let previous = canvas.image
            let changed = picker.selectedIndex != index
            picker.choose(index)
            for _ in 0..<200 where (changed && canvas.image === previous) || canvas.image == nil { try await Task.sleep(nanoseconds: 10_000_000) }
            XCTAssertNotNil(canvas.image)
            if changed { XCTAssertFalse(canvas.image === previous, "Wait for this model's actual preview, not the previous raster") }
            root.layoutSubtreeIfNeeded()
        }

        for orientation in Orientation.allCases {
            for shadow in ShadowStyle.allCases {
                var settings = inspector.settings
                settings.orientation = orientation; settings.transparentShadow = shadow; settings.phoneModel = .iPhone18ProMax
                inspector.restore(settings); inspector.onChange?(settings)
                for size in [NSSize(width: 1030, height: 640), NSSize(width: 1030, height: 1100), NSSize(width: 1586, height: 945)] {
                    window.setContentSize(size); root.layoutSubtreeIfNeeded(); controller.fitPreview(nil)
                    var lengths: [CGFloat] = []
                    for index in [0, 1, 0] {
                        try await choose(index)
                        let native = inspector.settings.deviceCanvasSize
                        let factor = try XCTUnwrap(canvas.zoom)
                        lengths.append(max(native.width, native.height) * factor)
                        let image = try XCTUnwrap(canvas.image)
                        XCTAssertEqual(canvas.imageRect.width / canvas.imageRect.height, image.size.width / image.size.height, accuracy: 0.0001)
                    }
                    XCTAssertEqual(try XCTUnwrap(lengths.min()), try XCTUnwrap(lengths.max()), accuracy: 1,
                                   "Fit should keep phone size stable for \(orientation), \(shadow), \(size)")
                }
                controller.actualPixels(nil)
                for index in [1, 0] {
                    try await choose(index)
                    let factor = try XCTUnwrap(canvas.zoom)
                    XCTAssertEqual(factor * window.backingScaleFactor, 1, accuracy: 0.0001)
                    let image = try XCTUnwrap(canvas.image)
                    let native = inspector.settings.deviceCanvasSize
                    let margin: CGFloat = shadow == .none ? 0 : shadow == .soft ? 84 : 138
                    XCTAssertEqual(image.size, CGSize(width: native.width + margin * 2, height: native.height + margin * 2))
                    XCTAssertEqual(canvas.imageRect.width * window.backingScaleFactor, image.size.width, accuracy: 0.001)
                    XCTAssertEqual(canvas.imageRect.height * window.backingScaleFactor, image.size.height, accuracy: 0.001)
                }
            }
        }
    }
}
