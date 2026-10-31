import AppKit
import XCTest
@testable import FraloDesignSystem

final class BatchThumbnailTests: XCTestCase {
    @MainActor func testContentUpdateKeepsUnrelatedRowsSelectionAndScroll() throws {
        _ = NSApplication.shared
        let list = BatchList(entries: (0..<100).map { BatchEntry(id: "\($0)", title: "Image \($0)") })
        list.frame = NSRect(x: 0, y: 0, width: 260, height: 400); list.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(list.documentView as? NSTableView)
        list.select(0); table.scrollRowToVisible(99)
        let origin = list.contentView.bounds.origin
        var selections = 0; list.onSelection = { _ in selections += 1 }
        let visibleRow = try XCTUnwrap(table.view(atColumn: 0, row: 99, makeIfNecessary: true))
        list.updateEntry(BatchEntry(id: "0", title: "Image 0", detail: "1200 × 2400", failed: true), at: 0)
        XCTAssertEqual(list.entries[0].detail, "1200 × 2400"); XCTAssertTrue(list.entries[0].failed)
        XCTAssertEqual(list.contentView.bounds.origin, origin); XCTAssertEqual(list.selectedIndex, 0)
        XCTAssertEqual(selections, 0)
        XCTAssertTrue(table.view(atColumn: 0, row: 99, makeIfNecessary: true) === visibleRow)
        list.updateEntry(BatchEntry(id: "deleted", title: "wrong"), at: 0)
        list.updateEntry(BatchEntry(id: "1000", title: "wrong"), at: 1000)
        XCTAssertEqual(list.entries[0].id, "0"); XCTAssertEqual(list.entries.count, 100)
    }
}
