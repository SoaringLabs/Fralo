import AppKit
import XCTest
import FraloCore
@testable import FraloDesignSystem
import FraloLocalization
@testable import FraloApp

final class EstimatedSizeTests: XCTestCase {
    @MainActor private func scene() -> (NSWindow, EstimatedSizeView) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 80),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let value = EstimatedSizeView(); value.frame = NSRect(x: 20, y: 20, width: 200, height: 20)
        window.contentView?.addSubview(value); window.contentView?.layoutSubtreeIfNeeded()
        return (window, value)
    }

    @MainActor func testActivityReplacesOnlyTheEstimateAndStopsForResultEmptyAndDetachment() throws {
        let (window, value) = scene(); defer { window.close() }
        let frame = value.frame
        XCTAssertEqual(value.label.stringValue, "—"); XCTAssertFalse(value.isEstimating)
        XCTAssertTrue(value.indicator.isHidden)
        value.show(nil, busy: true)
        XCTAssertTrue(value.isEstimating); XCTAssertEqual(value.label.stringValue, L10n.tr("正在估算…"))
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            XCTAssertTrue(value.label.isHidden); XCTAssertFalse(value.indicator.isHidden)
            let rotation = try XCTUnwrap(value.indicator.arc.animation(forKey: "activity.rotation") as? CABasicAnimation)
            XCTAssertEqual(rotation.keyPath, "transform.rotation.z")
            XCTAssertEqual(rotation.duration, 0.8)
            XCTAssertEqual(rotation.repeatCount, .infinity)
            XCTAssertEqual(value.indicator.accessibilityRole(), .progressIndicator)
        }
        value.show(591_000)
        XCTAssertFalse(value.isEstimating); XCTAssertFalse(value.label.isHidden)
        XCTAssertTrue(value.indicator.isHidden); XCTAssertNil(value.indicator.arc.animation(forKey: "activity.rotation"))
        XCTAssertEqual(value.label.stringValue, L10n.tr("\(ByteCountFormatter.string(fromByteCount: 591_000, countStyle: .file)) / 张"))
        value.show(nil, busy: true); value.show(nil)
        XCTAssertEqual(value.label.stringValue, "—"); XCTAssertFalse(value.label.isHidden)
        XCTAssertNil(value.indicator.arc.animation(forKey: "activity.rotation"))
        value.show(nil, busy: true); value.removeFromSuperview()
        XCTAssertNil(value.indicator.arc.animation(forKey: "activity.rotation"))
        XCTAssertEqual(value.frame, frame, "Loading cannot move the row's value slot")
    }

    @MainActor func testReduceMotionProvidesLocalizedStatusWithoutRotationAndDoesNotRevealIdleActivity() {
        let (window, value) = scene(); defer { window.close() }
        value.show(nil, busy: true); value.preferences.reduceMotion = true
        XCTAssertFalse(value.label.isHidden); XCTAssertTrue(value.indicator.isHidden)
        XCTAssertEqual(value.label.stringValue, L10n.tr("正在估算…"))
        XCTAssertNil(value.indicator.arc.animation(forKey: "activity.rotation"))
        value.show(120_000)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        XCTAssertFalse(value.label.isHidden); XCTAssertTrue(value.indicator.isHidden)
        XCTAssertFalse(value.isEstimating)
    }

    @MainActor func testArcIsOpenRoundedUnclippedAndAdaptsToBothAppearances() throws {
        let (window, value) = scene(); defer { window.close() }
        let indicator = value.indicator
        var colors: [CGColor] = []
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            value.appearance = NSAppearance(named: appearance)
            value.show(nil, busy: true); value.layoutSubtreeIfNeeded()
            indicator.viewDidChangeEffectiveAppearance()
            let arc = indicator.arc
            XCTAssertEqual(arc.lineCap, .round); XCTAssertNil(arc.fillColor)
            let path = try XCTUnwrap(arc.path)
            let strokeBounds = path.boundingBoxOfPath.insetBy(dx: -arc.lineWidth / 2, dy: -arc.lineWidth / 2)
            XCTAssertTrue(indicator.bounds.contains(strokeBounds), "The stroke must fit inside its14pt slot")
            let stroke = path.copy(strokingWithWidth: arc.lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 1)
            XCTAssertFalse(stroke.contains(CGPoint(x: indicator.bounds.midX, y: indicator.bounds.midY)), "The painted stroke has an open center")
            colors.append(try XCTUnwrap(arc.strokeColor))
        }
        XCTAssertNotEqual(colors[0], colors[1], "The indicator must remain legible in light and dark appearances")
    }

    @MainActor func testPreviewStartsActivityImmediatelyAndCancellingBatchCannotRestoreStaleEstimate() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-estimate-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")),
                                              preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window)
        defer { window.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let inspector = try XCTUnwrap(root.right.body as? CompositionInspector)
        let list = try XCTUnwrap(root.left.body as? BatchList)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FraloApp/Development/Fixtures/01-today.png")
        controller.importURLs([source]); XCTAssertTrue(inspector.sizeEstimate.isEstimating)
        controller.newBatch(nil)
        XCTAssertFalse(inspector.sizeEstimate.isEstimating); XCTAssertEqual(inspector.outputSize.stringValue, "—")
        controller.importURLs([source]); XCTAssertTrue(inspector.sizeEstimate.isEstimating)
        try await waitForWorkbenchState("current image's estimate and source metadata") {
            !inspector.sizeEstimate.isEstimating && inspector.outputSize.stringValue != "—" && list.entries.first?.detail == "1320 × 2868"
        }
        XCTAssertEqual(list.entries.first?.detail, "1320 × 2868")
        XCTAssertEqual(list.entries.first?.detailToolTip, L10n.tr("原图尺寸：\("1320 × 2868") 像素"))
        XCTAssertNil(inspector.sizeEstimate.indicator.arc.animation(forKey: "activity.rotation"))
    }
}
