import AppKit
import XCTest
import FraloCore
import FraloDesignSystem
@testable import FraloApp

final class SidebarScrollingTests: XCTestCase {
    @MainActor func testSystemHeaderKeepsFirstAndKeyboardSelectedRowsUnobscured() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "fralo-scroll-\(UUID())"; let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let controller = MainWindowController(store: SettingsStore(url: directory.appendingPathComponent("s.json")), preferences: defaults, restoreWindow: false)
        let window = try XCTUnwrap(controller.window); defer { window.close() }
        let root = try XCTUnwrap(window.contentView as? WorkbenchView)
        let list = try XCTUnwrap(root.left.body as? BatchList)
        let table = try XCTUnwrap(list.documentView as? NSTableView)
        root.collapsed = false
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 64, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let urls = try (0..<30).map { index in
            let url = directory.appendingPathComponent("image-\(index).png"); try png.write(to: url); return url
        }
        controller.importURLs(urls)
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        for size in [NSSize(width: 1030, height: 640), NSSize(width: 1400, height: 900)] {
            window.setContentSize(size); root.layoutSubtreeIfNeeded()
            let heading = root.left.heading.convert(root.left.heading.bounds, to: root.left)
            XCTAssertLessThan(list.convert(list.bounds, to: root.left).minY, heading.maxY, "The list really extends under the fixed heading")
            XCTAssertTrue(list.hasVerticalScroller)
            let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
            let thumbnail = try XCTUnwrap(cell.imageView)
            XCTAssertEqual(thumbnail.convert(thumbnail.bounds, to: cell).minX, 18, accuracy: 1, "Rows retain their original 10pt outer margin plus 8pt cell padding")
            for index in [0, 29, 1, 0] {
                list.select(index); root.layoutSubtreeIfNeeded()
                let row = table.convert(table.rect(ofRow: index), to: root.left)
                XCTAssertGreaterThanOrEqual(row.minY, heading.maxY - 1, "Selection must not disappear underneath the heading")
                XCTAssertLessThanOrEqual(row.maxY, root.left.bounds.maxY + 1)
            }
            let headerHit = root.left.heading.hitTest(NSPoint(x: root.left.heading.bounds.midX, y: root.left.heading.bounds.midY))
            XCTAssertFalse(headerHit?.isDescendant(of: table) == true)
        }
        let add = try XCTUnwrap((root.left.heading as? NSStackView)?.arrangedSubviews.last as? NSButton)
        XCTAssertTrue(window.makeFirstResponder(add))
        controller.toggleSidebar(nil)
        XCTAssertFalse(window.firstResponder === add, "Collapsing must transfer focus out of the native accessory too")
        controller.toggleSidebar(nil)
        XCTAssertTrue(window.firstResponder === table)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        let inspectorScrollers = descendants(root.right).compactMap { $0 as? PanelScrollView }
        XCTAssertFalse(inspectorScrollers.isEmpty)
        XCTAssertTrue(inspectorScrollers.allSatisfy { !$0.hasVerticalScroller }, "Only the left column opts into scrollbars")
        if #available(macOS 26.0, *) { XCTAssertEqual(root.sidebarItem.topAlignedAccessoryViewControllers.count, 1) }
    }

    @MainActor func testCompatibilityHeadingAndSelectionAtBothEnds() async throws {
        _ = NSApplication.shared
        let list = BatchList(entries: (0..<30).map { BatchEntry(id: String($0), title: "image-\($0).png") })
        let header = NSButton(title: "图片 30", target: nil, action: nil)
        let sidebar = DockedSidebar(header: header, body: list, footer: NSView(), usesNativeHeader: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 640), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        window.contentView = sidebar; window.makeKeyAndOrderFront(nil)
        sidebar.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(list.documentView as? NSTableView)
        for style in [NSScroller.Style.overlay, .legacy] {
            list.scrollerStyle = style; sidebar.layoutSubtreeIfNeeded(); list.tile()
            for index in [0, 29, 1, 0] {
                list.select(index); sidebar.layoutSubtreeIfNeeded()
                let heading = header.convert(header.bounds, to: sidebar)
                let row = table.convert(table.rect(ofRow: index), to: sidebar)
                XCTAssertGreaterThanOrEqual(row.minY, heading.maxY + 9)
                XCTAssertLessThanOrEqual(row.maxY, sidebar.bounds.maxY + 1)
            }
            XCTAssertEqual(list.verticalScroller?.scrollerStyle, style)
        }
        list.update([]); sidebar.layoutSubtreeIfNeeded(); XCTAssertNil(list.selectedIndex)
        list.update([BatchEntry(id: "short", title: "short.png")]); list.select(0); sidebar.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(table.convert(table.rect(ofRow: 0), to: sidebar).minY, header.convert(header.bounds, to: sidebar).maxY + 9)
    }
}
