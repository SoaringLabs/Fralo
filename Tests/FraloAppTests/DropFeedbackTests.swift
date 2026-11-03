import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class DropFeedbackTests: XCTestCase {
    private var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/FraloApp/Development/Fixtures/01-today.png")
    }

    @MainActor func testEmptyTargetCrossfadesOnDragEntryExitAndRapidReentry() throws {
        _ = NSApplication.shared
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            throw XCTSkip("The system disables animation")
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let stage = EmptyStageView(action: ActionButton("Add", role: .primary))
        window.contentView = stage
        stage.showEmpty(title: "Drop screenshots", detail: "PNG / JPEG")
        stage.layoutSubtreeIfNeeded()
        XCTAssertNil(stage.zone.layer?.animation(forKey: kCATransition))

        stage.showDrag(.accepting, title: "Release to add", detail: "4 images")
        XCTAssertNotNil(stage.zone.layer?.animation(forKey: kCATransition) as? CATransition,
                        "The entire guidance must transition, including its icon, text and button")
        XCTAssertTrue(stage.zone.action.isHidden, "The logical drag state applies without waiting for the fade")

        stage.showEmpty(title: "Drop screenshots", detail: "PNG / JPEG")
        XCTAssertNotNil(stage.zone.layer?.animation(forKey: kCATransition) as? CATransition,
                        "Leaving a drag must also transition back to the normal guidance")
        XCTAssertFalse(stage.zone.action.isHidden)

        stage.showDrag(.accepting, title: "Release to add", detail: "4 images")
        XCTAssertTrue(stage.zone.action.isHidden, "A rapid re-entry must keep the latest drag state")
        XCTAssertNotNil(stage.zone.layer?.animation(forKey: kCATransition))
        stage.showError("Cannot render")
        XCTAssertNil(stage.zone.layer?.animation(forKey: kCATransition), "An error replaces any outgoing drag animation")
        XCTAssertFalse(stage.zone.action.isHidden)
    }

    @MainActor func testReducedMotionKeepsDragFeedbackImmediateInBothDirections() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let stage = EmptyStageView(action: ActionButton("Add", role: .primary))
        window.contentView = stage
        stage.showEmpty(title: "Drop screenshots", detail: "PNG / JPEG")
        stage.showDrag(.accepting, title: "Release to add", detail: "4 images")
        stage.zone.preferences.reduceMotion = true
        XCTAssertNil(stage.zone.layer?.animation(forKey: kCATransition), "Reduce Motion cancels the current transition")
        stage.showEmpty(title: "Drop screenshots", detail: "PNG / JPEG")
        XCTAssertNil(stage.zone.layer?.animation(forKey: kCATransition))
        XCTAssertFalse(stage.zone.action.isHidden)
        stage.showDrag(.rejecting, title: "Cannot add", detail: "PNG / JPEG only")
        XCTAssertNil(stage.zone.layer?.animation(forKey: kCATransition))
        XCTAssertTrue(stage.zone.action.isHidden)
    }

    /// A descendant registered for drags becomes the destination under the pointer, so the container
    /// receives draggingExited mid-drag and its feedback flickers (NSImageView registers image types by default).
    @MainActor func testOnlyTheDropContainersRegisterForDrags() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-drop-targets-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("settings.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window)
        defer { window.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        func registered(below container: NSView) -> [String] {
            func walk(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(walk) }
            return walk(container).filter { !$0.registeredDraggedTypes.isEmpty }.map { String(describing: type(of: $0)) }
        }
        XCTAssertEqual(registered(below: root.content), [], "Empty stage")
        XCTAssertEqual(registered(below: root.left), [], "Empty sidebar")
        controller.importURLs([fixture]); root.layoutSubtreeIfNeeded()
        XCTAssertEqual(registered(below: root.content), [], "Filled stage")
        XCTAssertEqual(registered(below: root.left), [], "Filled sidebar rows")
    }

    /// The feedback must not outlive the drag when AppKit never sends draggingExited,
    /// e.g. when a system shortcut interrupts the session.
    @MainActor func testFeedbackClearsWhenTheDragEndsWithoutAnExit() async throws {
        let router = FileDropRouter()
        var states: [DropSummary?] = []
        router.onChange = { states.append($0) }
        var dragging = true
        router.isDragging = { dragging }
        router.begin(DropSummary(urls: [fixture]))
        XCTAssertEqual(states.count, 1); XCTAssertTrue(states[0]?.canDrop == true)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(states.count, 1, "An ongoing drag keeps its feedback")
        dragging = false
        for _ in 0..<50 where states.count == 1 { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(states.count, 2, "Releasing the mouse ends the feedback")
        XCTAssertNil(states.last ?? nil)
        router.begin(DropSummary(urls: [fixture])); router.ended()
        XCTAssertNil(states.last ?? nil, "draggingEnded clears the feedback")
        let count = states.count; router.ended(); router.exited()
        XCTAssertEqual(states.count, count, "Clearing twice does not repeat the reset")
    }
}
