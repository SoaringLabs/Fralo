import FraloLocalization
import AppKit
import XCTest
@testable import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class ExportCapsuleTests: XCTestCase {
    func testOutcomeMentionsOnlyWhatNeedsAttention() {
        let single = ExportOutcome(total: 1, succeeded: 1)
        XCTAssertEqual(single.tone, .success)
        XCTAssertEqual(single.title, L10n.tr("已导出图片"))
        XCTAssertEqual(single.counts, "")
        XCTAssertTrue(single.revealable)

        let batch = ExportOutcome(total: 8, succeeded: 8)
        XCTAssertEqual(batch.title, L10n.tr("已导出 \(8) 张图片"))
        XCTAssertEqual(batch.counts, "")

        let partial = ExportOutcome(total: 8, succeeded: 6, skipped: 1, failed: 1)
        XCTAssertEqual(partial.tone, .warning)
        XCTAssertEqual(partial.title, L10n.tr("已导出 \(6) 张，\(2) 张未导出"))
        XCTAssertEqual(partial.counts, [L10n.tr("\(1) 张失败"), L10n.tr("\(1) 张已跳过")].joined(separator: " · "))

        let stopped = ExportOutcome(total: 8, succeeded: 3, cancelled: true)
        XCTAssertEqual(stopped.tone, .cancelled)
        XCTAssertEqual(stopped.title, L10n.tr("导出已取消，已导出 \(3) 张图片"))
        XCTAssertEqual(stopped.counts, L10n.tr("\(5) 张未处理"))

        let nothing = ExportOutcome(total: 2, succeeded: 0, failed: 2)
        XCTAssertEqual(nothing.title, L10n.tr("未能导出图片"))
        XCTAssertFalse(nothing.revealable)
        XCTAssertEqual(ExportOutcome(total: 2, succeeded: 0, cancelled: true).title, L10n.tr("导出已取消"))
    }

    func testOutcomeKeepsEachIssueFromTheReport() {
        let report = ExportReport(settings: RenderSettings(), entries: [
            ExportEntry(input: "a.png", output: "/tmp/a.png", status: .success, reason: nil),
            ExportEntry(input: "b.png", output: "/tmp/b.png", status: .skipped, reason: "exists"),
            ExportEntry(input: "c.png", output: "/tmp/c.png", status: .failed, reason: nil)
        ], total: 4, cancelled: false, durationSeconds: 1)
        let outcome = ExportOutcome(report: report)
        XCTAssertEqual(outcome.succeeded, 1); XCTAssertEqual(outcome.unprocessed, 1)
        XCTAssertEqual(outcome.issues, [.init(name: "b.png", reason: "exists", failed: false), .init(name: "c.png", reason: "failed", failed: true)])
    }

    @MainActor func testRunReportsProgressStopsOnceAndSettlesBack() throws {
        let (capsule, window) = host()
        defer { window.close() }
        var cancels = 0, reveals = 0, hides = 0
        capsule.onCancel = { cancels += 1 }; capsule.onReveal = { reveals += 1 }; capsule.onReturn = { hides += 1 }

        XCTAssertNil(capsule.hitTest(NSPoint(x: 200, y: 200)), "A hidden capsule never takes clicks from the stage")
        capsule.begin(total: 4, thumbnail: nil)
        capsule.layoutSubtreeIfNeeded()
        XCTAssertEqual(capsule.phase, .running)
        XCTAssertFalse(capsule.surface.isHidden)
        XCTAssertEqual(capsule.title.stringValue, L10n.tr("正在导出 \(4) 张图片"))
        XCTAssertEqual(capsule.cancel.keyEquivalent, "\u{1b}", "Escape stops an export like the old sheet's Cancel")
        XCTAssertEqual(capsule.surface.frame.midX, capsule.anchor().midX, accuracy: 0.5, "The capsule sits where the viewing toolbar was")
        XCTAssertEqual(capsule.surface.frame.midY, capsule.anchor().midY, accuracy: 0.5)
        XCTAssertNil(capsule.hitTest(NSPoint(x: 20, y: 20)), "Outside the capsule the stage stays interactive")

        capsule.update(completed: 2)
        XCTAssertTrue(capsule.detail.stringValue.hasPrefix(L10n.tr("\(2) / \(4)")))
        XCTAssertEqual(capsule.progress.accessibilityRole(), .progressIndicator)
        XCTAssertEqual((capsule.progress.accessibilityValue() as? NSNumber)?.doubleValue, 0.5)

        capsule.setPendingUpdate(L10n.tr("导出结束后将安装更新并重启 Fralo"))
        XCTAssertTrue(capsule.detail.stringValue.contains(L10n.tr("导出结束后将安装更新并重启 Fralo")))

        capsule.cancel.performClick(nil); capsule.cancel.performClick(nil)
        XCTAssertEqual(cancels, 1)
        XCTAssertFalse(capsule.cancel.isEnabled)
        XCTAssertEqual(capsule.detail.stringValue, L10n.tr("正在停止…"))

        capsule.finish(ExportOutcome(total: 4, succeeded: 4), folderName: "Fralo 2026-11-04 00-30-00")
        capsule.layoutSubtreeIfNeeded()
        XCTAssertEqual(capsule.phase, .result(.success))
        XCTAssertTrue(capsule.cancel.isHidden)
        XCTAssertEqual(capsule.detail.stringValue, "Fralo 2026-11-04 00-30-00")
        let reveal = try XCTUnwrap(buttons(in: capsule).first { $0.title == L10n.tr("在 Finder 中显示") })
        reveal.performClick(nil)
        XCTAssertEqual(reveals, 1)
        XCTAssertEqual(capsule.phase, .hidden, "Revealing a clean run puts the capsule away")
        XCTAssertEqual(hides, 1)
        XCTAssertTrue(capsule.surface.isHidden)
    }

    @MainActor func testResultsThatNeedReadingStayAsACard() throws {
        let (capsule, window) = host()
        defer { window.close() }
        var hides = 0
        capsule.onReturn = { hides += 1 }
        capsule.begin(total: 3, thumbnail: nil)
        capsule.finish(ExportOutcome(total: 3, succeeded: 2, failed: 1, issues: [.init(name: "c.png", reason: "broken", failed: true)]),
                       folderName: "Fralo")
        capsule.layoutSubtreeIfNeeded()
        XCTAssertEqual(capsule.phase, .result(.warning))
        XCTAssertGreaterThan(capsule.surface.frame.height, ExportCapsule.height, "Issues open a card")
        XCTAssertEqual(capsule.surface.frame.maxY, capsule.anchor().midY + ExportCapsule.height / 2, accuracy: 0.5,
                       "The card grows upward from the toolbar line")
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let list = try XCTUnwrap(descendants(capsule).first { $0.accessibilityRole() == .list })
        XCTAssertEqual(list.accessibilityLabel(), L10n.tr("未导出的图片"))
        XCTAssertTrue(descendants(list).contains { $0.accessibilityLabel() == L10n.tr("\("c.png")：\("broken")") })
        let titles = buttons(in: capsule).map(\.title)
        XCTAssertEqual(Set(titles).intersection([L10n.tr("完成"), L10n.tr("在 Finder 中显示")]).count, 2)
        try XCTUnwrap(buttons(in: capsule).first { $0.title == L10n.tr("完成") }).performClick(nil)
        XCTAssertEqual(capsule.phase, .hidden); XCTAssertEqual(hides, 1)

        // Nothing exported: no Finder action, and Done is the only way out.
        capsule.begin(total: 1, thumbnail: nil)
        capsule.finish(ExportOutcome(total: 1, succeeded: 0, cancelled: true), folderName: "Fralo")
        XCTAssertEqual(capsule.phase, .result(.cancelled))
        XCTAssertFalse(buttons(in: capsule).contains { $0.title == L10n.tr("在 Finder 中显示") })
    }

    @MainActor func testWorkbenchHostsTheCapsuleOverTheViewingToolbar() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "fralo-export-capsule-\(UUID())", defaults = UserDefaults(suiteName: suite)!
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window)
        defer { window.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        window.layoutIfNeeded()
        let capsule = controller.exportCapsule
        XCTAssertNotNil(capsule.superview)
        XCTAssertTrue(capsule.surface.isHidden)
        XCTAssertEqual(capsule.phase, .hidden)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let toolbar = try XCTUnwrap(descendants(try XCTUnwrap(window.contentView)).first { $0 is ViewToolbar })
        XCTAssertEqual(capsule.anchor(), capsule.convert(toolbar.bounds, from: toolbar))
        XCTAssertFalse(controller.isExporting)
        XCTAssertFalse(toolbar.isHidden)
        // The toolbar (and the capsule it becomes) floats in a band raised off the window edge;
        // Fit keeps artwork above that whole band.
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let stage = try XCTUnwrap(capsule.superview)
        let band = stage.convert(toolbar.bounds, from: toolbar)
        let fromBottom = stage.isFlipped ? stage.bounds.maxY - band.midY : band.midY - stage.bounds.minY
        XCTAssertEqual(fromBottom, WorkbenchView.viewingControlsHeight / 2, accuracy: 0.5)
        XCTAssertEqual(root.viewingInsets.bottom, WorkbenchView.viewingControlsHeight)
        XCTAssertGreaterThan(root.viewingInsets.bottom, fromBottom + ExportCapsule.height / 2)
    }

    @MainActor func testThumbnailHoldsStillThenGivesWayToTheResult() throws {
        let (capsule, window) = host()
        defer { window.close() }
        let first = NSImage(size: NSSize(width: 10, height: 20))
        capsule.begin(total: 24, thumbnail: first)
        capsule.update(completed: 13)
        XCTAssertTrue(capsule.thumbnail.image === first, "Progress never swaps the image; the liquid and count carry the pace")
        XCTAssertFalse(capsule.thumbnail.isHidden)
        XCTAssertTrue(capsule.detail.stringValue.hasPrefix(L10n.tr("\(13) / \(24)")))
        capsule.finish(ExportOutcome(total: 24, succeeded: 24), folderName: "Fralo")
        XCTAssertTrue(capsule.thumbnail.isHidden, "The checkmark takes the thumbnail's place once the run is done")
    }

    @MainActor func testWorkWaitsForTheGrowAndIsNeverLost() throws {
        // Without animation (hidden window or Reduce Motion) work starts at once.
        let (capsule, window) = host()
        defer { window.close() }
        var started = 0
        capsule.begin(total: 3, thumbnail: nil) { started += 1 }
        XCTAssertEqual(started, 1)

        let (shown, visible) = host()
        visible.orderFrontRegardless()
        defer { visible.close() }
        // An interrupted grow still hands over, so an export can never hang unstarted.
        var interrupted = 0
        shown.begin(total: 3, thumbnail: nil) { interrupted += 1 }
        shown.hide(animated: true)
        XCTAssertEqual(interrupted, 1)

        // The deferral itself needs real motion: an on-screen window and Reduce Motion off.
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, visible.isVisible else {
            throw XCTSkip("System Reduce Motion or an off-screen test window disables the grow, so work starts at once")
        }
        var ready = 0
        shown.begin(total: 3, thumbnail: nil) { ready += 1 }
        XCTAssertEqual(ready, 0, "Export work must not start while the capsule is still reshaping")
        let deadline = Date().addingTimeInterval(2)
        while ready == 0, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        XCTAssertEqual(ready, 1, "It starts once the grow has finished")
    }

    @MainActor func testPreviewShimmerLoopsUntilTheRunEnds() throws {
        let canvas = CanvasSurface(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        canvas.wantsLayer = true
        canvas.image = NSImage(size: NSSize(width: 100, height: 200), flipped: false) { rect in NSColor.black.setFill(); rect.fill(); return true }
        let shimmer = PreviewShimmer()
        var reduced = DesignPreferences(); reduced.reduceMotion = true
        shimmer.start(on: canvas, preferences: reduced)
        XCTAssertFalse(shimmer.isRunning, "Reduce Motion keeps the preview still")

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            throw XCTSkip("System Reduce Motion intentionally disables the shimmer")
        }
        shimmer.start(on: canvas, preferences: DesignPreferences())
        let host = try XCTUnwrap(shimmer.host)
        XCTAssertTrue(shimmer.isRunning)
        XCTAssertEqual(host.frame, canvas.imageRect)
        let band = try XCTUnwrap(host.sublayers?.first)
        let pass = try XCTUnwrap(band.animation(forKey: "shimmer"))
        XCTAssertEqual(pass.repeatCount, .infinity, "One steady loop for the whole run, not a flash per image")
        XCTAssertEqual(pass.duration, PreviewShimmer.period)
        XCTAssertGreaterThanOrEqual(PreviewShimmer.period, 2)
        shimmer.stop()
        XCTAssertFalse(shimmer.isRunning)
        XCTAssertEqual(host.opacity, 0)
    }

    @MainActor private func host() -> (ExportCapsule, NSWindow) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let capsule = ExportCapsule(frame: window.contentView!.bounds)
        capsule.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(capsule)
        capsule.anchor = { NSRect(x: 250, y: 440, width: 200, height: 36) }
        return (capsule, window)
    }
    @MainActor private func buttons(in view: NSView) -> [NSButton] {
        view.subviews.flatMap { ($0 as? NSButton).map { [$0] } ?? [] } + view.subviews.flatMap { buttons(in: $0) }
    }
}
