import AppKit
import XCTest
@testable import FraloDesignSystem

final class BatchRowLayoutTests: XCTestCase {
    @MainActor func testFirstRowPaddingKeepsThumbnailCenteredWithoutInlineActions() throws {
        _ = NSApplication.shared
        let document = FlippedDocument(frame: NSRect(x: 0, y: 0, width: 250, height: 110))
        let row = ThumbnailRow(entry: BatchEntry(id: "a", title: "a.png"), topPadding: 6)
        row.frame = document.bounds; document.addSubview(row); row.layoutSubtreeIfNeeded()
        let image = try XCTUnwrap(row.imageView)
        XCTAssertEqual(image.convert(image.bounds, to: document).midY, 58, accuracy: 1,
                       "The thumbnail stays centered below the six-point gap in visual coordinates")
        XCTAssertTrue(row.subviews.compactMap { $0 as? NSButton }.isEmpty, "Rows expose actions through the context menu")
    }
}
