import AppKit
import XCTest
import FraloDesignSystem
@testable import FraloApp

final class SidebarFooterTests: XCTestCase {
    @MainActor func testNativeBottomAccessoryOverlaysScrollingContentAndProtectsLastSelection() async throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("Native split accessories require macOS26") }
        _ = NSApplication.shared
        let list = BatchList(entries: (0..<30).map { BatchEntry(id: String($0), title: "image-\($0).png") })
        let caption = NSTextField(labelWithString: "↑ ↓ 切换图片"); caption.font = .systemFont(ofSize: 11)
        let heading = NSTextField(labelWithString: "图片30")
        let sidebar = DockedSidebar(header: heading, body: list, footer: caption)
        let split = NSSplitViewController(), sideController = NSViewController(), main = NSViewController()
        sideController.view = sidebar; main.view = NSView()
        let item = NSSplitViewItem(sidebarWithViewController: sideController)
        item.minimumThickness = 250; item.maximumThickness = 300; item.allowsFullHeightLayout = true
        split.addSplitViewItem(item); split.addSplitViewItem(NSSplitViewItem(viewController: main))
        sidebar.configureHeader(for: item); sidebar.showsFooter = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1030, height: 640), styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        window.contentViewController = split; window.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        let table = try XCTUnwrap(list.documentView as? NSTableView)
        let footer = try XCTUnwrap(caption.superview)
        for size in [NSSize(width: 1030, height: 640), NSSize(width: 1400, height: 900)] {
            window.setContentSize(size); sidebar.layoutSubtreeIfNeeded()
            let boundary = footer.convert(footer.bounds, to: sidebar)
            list.select(0); sidebar.layoutSubtreeIfNeeded()
            let header = try XCTUnwrap(heading.superview)
            XCTAssertGreaterThanOrEqual(table.convert(table.focusRingMaskBounds, to: sidebar).minY,
                                        header.convert(header.bounds, to: sidebar).maxY + 5, "First image keeps a small gap below the fixed heading")
            XCTAssertGreaterThan(list.convert(list.bounds, to: sidebar).maxY, boundary.minY + 10, "Content really scrolls under the footer")
            XCTAssertEqual(caption.convert(caption.bounds, to: footer).minY, 14, accuracy: 1)
            list.select(29); sidebar.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(table.convert(table.rect(ofRow: 29), to: sidebar).maxY, boundary.minY + 1, "The last selected image clears the caption overlay")
        }
        XCTAssertEqual(item.bottomAlignedAccessoryViewControllers.count, 1)
        sidebar.showsFooter = false; sidebar.layoutSubtreeIfNeeded()
        XCTAssertTrue(try XCTUnwrap(item.bottomAlignedAccessoryViewControllers.first).isHidden)
        XCTAssertTrue(footer.isHidden)
        sidebar.showsFooter = true; sidebar.layoutSubtreeIfNeeded()
        XCTAssertFalse(try XCTUnwrap(item.bottomAlignedAccessoryViewControllers.first).isHidden)
    }

    @MainActor func testCompatibilityFooterUsesOneInsetAndLeavesLastRowUncovered() async throws {
        _ = NSApplication.shared
        let list = BatchList(entries: (0..<30).map { BatchEntry(id: String($0), title: "image-\($0).png") })
        let caption = NSTextField(labelWithString: "↑ ↓ 切换图片"); caption.font = .systemFont(ofSize: 11)
        let sidebar = DockedSidebar(header: NSTextField(labelWithString: "图片30"), body: list, footer: caption, usesNativeHeader: false)
        sidebar.showsFooter = true
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        window.contentView = sidebar; window.makeKeyAndOrderFront(nil)
        let table = try XCTUnwrap(list.documentView as? NSTableView), footer = try XCTUnwrap(caption.superview)
        for style in [NSScroller.Style.overlay, .legacy] {
            list.scrollerStyle = style; sidebar.layoutSubtreeIfNeeded(); list.tile()
            XCTAssertEqual(list.contentInsets.bottom, footer.bounds.height, accuracy: 1)
            XCTAssertEqual(list.convert(list.bounds, to: sidebar).maxY, sidebar.bounds.maxY, accuracy: 1)
            list.select(29); sidebar.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(table.convert(table.rect(ofRow: 29), to: sidebar).maxY,
                                     footer.convert(footer.bounds, to: sidebar).minY + 1)
        }
        sidebar.showsFooter = false; sidebar.layoutSubtreeIfNeeded()
        XCTAssertEqual(list.contentInsets.bottom, 0)
        XCTAssertTrue(footer.isHidden)
    }
}
