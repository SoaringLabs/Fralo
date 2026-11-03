import FraloLocalization
import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class PhoneModelZoomTests: XCTestCase {
    @MainActor func testEmptyPhoneLongestEdgeIsCappedAndStillFitsSmallerWindows() throws {
        _ = NSApplication.shared
        let stage = EmptyStageView(action: ActionButton("Add", role: .primary))
        stage.viewingInsets = NSEdgeInsets(top: 64, left: 24, bottom: 24, right: 368)
        for orientation in Orientation.allCases {
            let size = FrameGeometry(model: .iPhone18Pro).orientedSize(orientation)
            stage.device = .init(image: NSImage(size: size), screen: CGRect(x: 0.03, y: 0.03, width: 0.94, height: 0.94),
                                 cornerRadius: 0.05, display: .phone, orientation: orientation)
            var largeSize: NSSize?
            for viewport in [NSSize(width: 2400, height: 2000), NSSize(width: 4000, height: 2000)] {
                stage.setFrameSize(viewport)
                let rect = try XCTUnwrap(stage.deviceRect)
                XCTAssertEqual(max(rect.width, rect.height), 760, accuracy: 0.5,
                               "A wider window must not keep enlarging the \(orientation) phone")
                if let largeSize { XCTAssertEqual(rect.size, largeSize) }
                else { largeSize = rect.size }
            }
            for viewport in [NSSize(width: 1030, height: 640), NSSize(width: 1030, height: 400)] {
                stage.setFrameSize(viewport)
                let rect = try XCTUnwrap(stage.deviceRect)
                XCTAssertLessThan(max(rect.width, rect.height), 760, "Limited space must still shrink the phone")
                if size.width >= size.height {
                    XCTAssertEqual(rect.height, rect.width * size.height / size.width, accuracy: 1)
                } else {
                    XCTAssertEqual(rect.width, rect.height * size.width / size.height, accuracy: 1)
                }
                XCTAssertGreaterThanOrEqual(rect.minX, stage.viewingInsets.left)
                XCTAssertLessThanOrEqual(rect.maxX, viewport.width - stage.viewingInsets.right)
                XCTAssertGreaterThanOrEqual(rect.minY, stage.viewingInsets.top)
                XCTAssertLessThanOrEqual(rect.maxY, viewport.height - stage.viewingInsets.bottom)
            }
        }
        for display in [DisplayKind.tablet, .browser] {
            stage.device = .init(image: NSImage(size: NSSize(width: 800, height: 400)),
                                 screen: CGRect(x: 0.03, y: 0.03, width: 0.94, height: 0.94),
                                 cornerRadius: 0.05, display: display, orientation: .landscape)
            stage.setFrameSize(NSSize(width: 4000, height: 2000))
            XCTAssertEqual(try XCTUnwrap(stage.deviceRect).size, NSSize(width: 1520, height: 760),
                           "The phone cap must not change existing tablet/browser fit")
        }
    }

    @MainActor func testEmptyPhoneModelSwitchKeepsTheDrawnDeviceRectangleStable() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-empty-model-fit-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")),
                                              preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window)
        window.isReleasedWhenClosed = false
        defer { window.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let inspector = try XCTUnwrap(root.right.body as? CompositionInspector)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let stage = try XCTUnwrap(descendants(root).compactMap { $0 as? EmptyStageView }.first)
        let guidance = try XCTUnwrap(stage.zone.subviews.compactMap { $0 as? NSStackView }.first)
        for orientation in Orientation.allCases {
            var settings = inspector.settings; settings.orientation = orientation
            inspector.restore(settings); inspector.onChange?(settings)
            for _ in 0..<200 where stage.device?.orientation != orientation || stage.device == nil {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            for size in [NSSize(width: 1030, height: 640), NSSize(width: 1030, height: 1100), NSSize(width: 1586, height: 945)] {
                window.setContentSize(size); root.layoutSubtreeIfNeeded()
                var baseline: NSRect?
                for index in [0, 1, 0] {
                    let picker = try XCTUnwrap(descendants(inspector).compactMap { $0 as? VisualChoiceGroup }.first {
                        $0.accessibilityLabel() == L10n.tr("机型")
                    })
                    let previous = stage.device?.image, changed = picker.selectedIndex != index
                    picker.choose(index)
                    for _ in 0..<200 where stage.device == nil || (changed && stage.device?.image === previous) {
                        try await Task.sleep(nanoseconds: 10_000_000)
                    }
                    if changed { XCTAssertFalse(stage.device?.image === previous, "Wait for the newly selected model raster") }
                    root.layoutSubtreeIfNeeded(); stage.layoutSubtreeIfNeeded()
                    let frame = try XCTUnwrap(stage.deviceRect), screen = try XCTUnwrap(stage.screenRect)
                    if let baseline {
                        XCTAssertEqual(frame, baseline, "Empty phone bounds must stay fixed for \(orientation), \(size)")
                    } else { baseline = frame }
                    let content = stage.convert(guidance.bounds, from: guidance)
                    XCTAssertEqual(content.midX, screen.midX, accuracy: 1)
                    XCTAssertEqual(content.midY, screen.midY, accuracy: 1)
                }
            }
        }
    }

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
            let picker = try XCTUnwrap(descendants(inspector).compactMap { $0 as? VisualChoiceGroup }.first { $0.accessibilityLabel() == L10n.tr("机型") })
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
