import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class DropFeedbackTests: XCTestCase {
    private var fixture: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/FraloApp/Development/Fixtures/01-today.png")
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
