import AppKit
import XCTest
@testable import FraloApp

final class SidebarBoundaryTests: XCTestCase {
    @MainActor func testSidebarTintResolvesAgainWhenAppearanceChangesAndBoundarySpansPane() async throws {
        _ = NSApplication.shared
        let sidebar = DockedSidebar(header: NSView(), body: NSView(), footer: NSView())
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 240, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        window.contentView = sidebar
        var channels: [CGFloat] = []
        for appearance: NSAppearance.Name in [.aqua, .darkAqua, .aqua] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(nanoseconds: 20_000_000)
            sidebar.needsLayout = true; sidebar.layoutSubtreeIfNeeded()
            let color = try XCTUnwrap(sidebar.hierarchyTint.fillColor.usingColorSpace(.sRGB))
            channels.append(color.redComponent)
            XCTAssertEqual(color.alphaComponent, 0.32, accuracy: 0.001)
            // NSBox reserves drawing outsets around its one-point separator alignment rect.
            let edge = sidebar.boundarySeparator.alignmentRect(forFrame: sidebar.boundarySeparator.frame)
            XCTAssertEqual(edge.width, 1, accuracy: 0.001)
            XCTAssertEqual(edge.maxX, sidebar.bounds.maxX, accuracy: 0.001)
            XCTAssertEqual(edge.height, sidebar.bounds.height, accuracy: 0.001)
            XCTAssertTrue(sidebar.clipsToBounds, "The boundary must stay inside the pane while it collapses")
        }
        XCTAssertLessThan(channels[1], channels[0] - 0.2, "Dark mode must not keep the light tint resolved during initialization")
        XCTAssertEqual(channels[0], channels[2], accuracy: 0.001)
    }
}
