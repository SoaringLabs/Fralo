import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class OperationFeedbackTests: XCTestCase {
    @MainActor private final class RejectingClipboard: ImageClipboard {
        var writes = 0
        func writePNG(_ data: Data) -> Bool { writes += 1; return false }
    }

    @MainActor func testCopySuccessPreservesZoomAndFocusAndClearsWhenContextChanges() async throws {
        try await withController { controller, board in
            let feedback = controller.operationFeedback
            controller.copyCurrent(nil)
            XCTAssertTrue(feedback.isHidden, "An empty batch cannot report copy success")
            try await self.waitForCopy(controller, board: board)
            let window = try XCTUnwrap(controller.window)
            let toolbar = try XCTUnwrap(self.descendants(try XCTUnwrap(window.contentView)).compactMap { $0 as? ViewToolbar }.first)
            let readout = toolbar.dimensions.stringValue
            let focus = window.firstResponder
            controller.copyCurrent(nil)
            XCTAssertEqual(feedback.kind, .success)
            XCTAssertFalse(feedback.isHidden)
            XCTAssertEqual(feedback.title.stringValue, "已复制当前图片")
            XCTAssertEqual(toolbar.dimensions.stringValue, readout)
            XCTAssertTrue(window.firstResponder === focus)
            XCTAssertNotNil(board.data(forType: .png))
            controller.zoomIn(nil)
            XCTAssertTrue(toolbar.dimensions.stringValue.hasSuffix("%"))
            XCTAssertFalse(feedback.isHidden, "Viewing changes must not dismiss the copy result")
            controller.newBatch(nil)
            XCTAssertTrue(feedback.isHidden)
        }
    }

    @MainActor func testRejectedClipboardWriteShowsPersistentFailureInsteadOfSuccess() async throws {
        let rejecting = RejectingClipboard()
        try await withController(imageClipboard: rejecting) { controller, board in
            self.importFixture(controller)
            for _ in 0..<200 where rejecting.writes == 0 {
                controller.copyCurrent(nil)
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertGreaterThan(rejecting.writes, 0)
            XCTAssertEqual(controller.operationFeedback.kind, .failure)
            XCTAssertEqual(controller.operationFeedback.title.stringValue, "复制失败")
            XCTAssertTrue(controller.operationFeedback.detail.stringValue.contains("重试"))
            XCTAssertNil(board.data(forType: .png))
            controller.operationFeedback.close.performClick(nil)
            XCTAssertTrue(controller.operationFeedback.isHidden)
        }
    }

    @MainActor func testExpiryCannotDismissNewerFeedbackAndFailureDoesNotExpire() async throws {
        _ = NSApplication.shared
        let feedback = OperationFeedback()
        feedback.show(.success, title: "first", detail: "", duration: 0.05)
        feedback.show(.success, title: "second", detail: "", duration: 0.3)
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertFalse(feedback.isHidden)
        XCTAssertEqual(feedback.title.stringValue, "second")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(feedback.isHidden)
        feedback.show(.success, title: "old", detail: "", duration: 0.05)
        feedback.show(.failure, title: "failed", detail: "retry", duration: 0.01)
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertFalse(feedback.isHidden)
        XCTAssertEqual(feedback.kind, .failure)
    }

    @MainActor func testMessageFitsCanvasInLightDarkAndAccessibilityFallback() async throws {
        try await withController { controller, _ in
            let window = try XCTUnwrap(controller.window)
            let root = try XCTUnwrap(window.contentView as? WorkbenchView)
            let feedback = controller.operationFeedback
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                window.appearance = NSAppearance(named: appearance)
                for size in [NSSize(width: 1030, height: 640), NSSize(width: 1400, height: 900)] {
                    window.setContentSize(size)
                    var preferences = DesignPreferences()
                    preferences.reduceMotion = true; preferences.reduceTransparency = true; preferences.increaseContrast = true
                    feedback.surface.preferences = preferences
                    feedback.show(.failure, title: "复制失败", detail: "无法写入剪贴板，请重试复制。")
                    window.contentView?.layoutSubtreeIfNeeded()
                    XCTAssertTrue(feedback.surface.isUsingOpaqueFallback)
                    XCTAssertGreaterThan(feedback.bounds.height, 40)
                    XCTAssertGreaterThanOrEqual(feedback.title.bounds.width, feedback.title.intrinsicContentSize.width)
                    XCTAssertGreaterThan(feedback.detail.bounds.width, 140)
                    let close = feedback.close.convert(feedback.close.bounds, to: feedback)
                    XCTAssertEqual(feedback.bounds.maxX - close.maxX, 10, accuracy: 1)
                    XCTAssertGreaterThanOrEqual(feedback.frame.minY, root.headerHeight)
                    XCTAssertTrue(feedback.superview!.bounds.contains(feedback.frame))
                    let panel = root.right.convert(root.right.bounds, to: feedback.superview)
                    XCTAssertFalse(feedback.frame.intersects(panel))
                }
            }
        }
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }

    @MainActor private func importFixture(_ controller: MainWindowController) {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        controller.importURLs([root.appendingPathComponent("Sources/FraloApp/Development/Fixtures/03-journal.png")])
    }

    @MainActor private func waitForCopy(_ controller: MainWindowController, board: NSPasteboard) async throws {
        importFixture(controller)
        for _ in 0..<200 where board.data(forType: .png) == nil {
            controller.copyCurrent(nil)
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(board.data(forType: .png))
    }

    @MainActor private func withController(imageClipboard: (any ImageClipboard)? = nil,
        body: @MainActor (MainWindowController, NSPasteboard) async throws -> Void) async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-feedback-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let board = NSPasteboard.withUniqueName()
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")),
            preferences: defaults, pasteboard: board, restoreWindow: false, imageClipboard: imageClipboard)
        defer {
            controller.window?.close(); board.releaseGlobally(); defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try await body(controller, board)
    }
}
