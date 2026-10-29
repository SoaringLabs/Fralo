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
                // Native buttons have different visual/alignment insets across SDKs.
                // Verify the row clears the visible header, not an exact gap.
                XCTAssertGreaterThanOrEqual(row.minY, heading.maxY)
                XCTAssertLessThanOrEqual(row.maxY, sidebar.bounds.maxY + 1)
            }
            XCTAssertEqual(list.verticalScroller?.scrollerStyle, style)
        }
        list.update([]); sidebar.layoutSubtreeIfNeeded(); XCTAssertNil(list.selectedIndex)
        list.update([BatchEntry(id: "short", title: "short.png")]); list.select(0); sidebar.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(table.convert(table.rect(ofRow: 0), to: sidebar).minY, header.convert(header.bounds, to: sidebar).maxY)
    }

    @MainActor func testSidebarScrollerPaintsASixPointKnobWithoutATrack() async throws {
        _ = NSApplication.shared
        let list = BatchList(entries: (0..<30).map { BatchEntry(id: String($0), title: "image-\($0).png") })
        let sidebar = DockedSidebar(header: NSTextField(labelWithString: "图片 30"), body: list, footer: NSView(), usesNativeHeader: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        window.contentView = sidebar; sidebar.layoutSubtreeIfNeeded()
        for style in [NSScroller.Style.legacy, .overlay] {
            list.scrollerStyle = style; list.tile(); sidebar.layoutSubtreeIfNeeded()
            let scroller = try XCTUnwrap(list.verticalScroller)
            scroller.knobProportion = 0.3; scroller.doubleValue = 0.4
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                scroller.appearance = NSAppearance(named: appearance)
                func paintedColumns(_ draw: () -> Void) throws -> Set<Int> {
                    let width = max(1, Int(scroller.bounds.width.rounded(.up)))
                    let height = max(1, Int(scroller.bounds.height.rounded(.up)))
                    let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                    memset(bitmap.bitmapData!, 0, bitmap.bytesPerRow * bitmap.pixelsHigh)
                    NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
                    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                    scroller.effectiveAppearance.performAsCurrentDrawingAppearance { draw() }
                    var columns = Set<Int>()
                    for x in 0..<width { for y in 0..<height {
                        if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 { columns.insert(x); break }
                    } }
                    return columns
                }
                XCTAssertTrue(try paintedColumns { scroller.drawKnobSlot(in: scroller.bounds, highlight: false) }.isEmpty,
                              "The background slot must stay transparent, including Always/legacy mode")
                let knobColumns = try paintedColumns { scroller.drawKnob() }
                XCTAssertFalse(knobColumns.isEmpty)
                XCTAssertLessThanOrEqual(knobColumns.count, 6, "Visible knob width must match the thin reference, independent of the larger hit target")
                XCTAssertGreaterThan(scroller.rect(for: .knob).width, 6, "Keep the native drag target wider than the artwork")
                let minX = try XCTUnwrap(knobColumns.min()), maxX = try XCTUnwrap(knobColumns.max())
                let point = NSPoint(x: CGFloat(minX + maxX + 1) / 2, y: scroller.rect(for: .knob).midY)
                XCTAssertEqual(scroller.testPart(scroller.convert(point, to: nil)), .knob,
                               "The pixels we draw must map to the native draggable knob in both modes")
            }
        }
    }

    @MainActor func testSidebarKnobHoverDarkensAndExitRestoresItsIdleColor() async throws {
        _ = NSApplication.shared
        let scroller = SidebarScroller(frame: NSRect(x: 0, y: 0, width: 17, height: 240))
        scroller.scrollerStyle = .legacy; scroller.knobProportion = 0.3; scroller.doubleValue = 0.4
        func maxAlpha() throws -> CGFloat {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 17, pixelsHigh: 240,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            memset(bitmap.bitmapData!, 0, bitmap.bytesPerRow * bitmap.pixelsHigh)
            NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            scroller.effectiveAppearance.performAsCurrentDrawingAppearance { scroller.drawKnob() }
            return (0..<17).flatMap { x in (0..<240).map { bitmap.colorAt(x: x, y: $0)?.alphaComponent ?? 0 } }.max() ?? 0
        }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            scroller.appearance = NSAppearance(named: appearance)
            let idle = try maxAlpha()
            let enter = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 1, trackingNumber: 1, userData: nil))
            scroller.mouseEntered(with: enter)
            XCTAssertGreaterThan(try maxAlpha(), idle + 0.1, "Hover must visibly darken the knob")
            let exit = try XCTUnwrap(NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 2, trackingNumber: 1, userData: nil))
            scroller.mouseExited(with: exit)
            XCTAssertEqual(try maxAlpha(), idle, accuracy: 0.01, "Pointer exit restores the pale idle color")
        }
    }

    @MainActor func testSidebarCardKeepsSevenPointGapToTheKnobInBothNativeStyles() async throws {
        _ = NSApplication.shared
        let list = BatchList(entries: (0..<30).map { BatchEntry(id: String($0), title: String(repeating: "long-screenshot-name-", count: 10) + "\($0).png") })
        let sidebar = DockedSidebar(header: NSTextField(labelWithString: "图片 30"), body: list, footer: NSView(), usesNativeHeader: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        window.contentView = sidebar
        let table = try XCTUnwrap(list.documentView as? NSTableView)
        for style in [NSScroller.Style.legacy, .overlay] {
            list.scrollerStyle = style; list.tile(); sidebar.layoutSubtreeIfNeeded(); list.select(10)
            let scroller = try XCTUnwrap(list.verticalScroller)
            let selection = table.convert(table.focusRingMaskBounds, to: sidebar)
            let knobLeft = scroller.convert(NSPoint(x: scroller.bounds.maxX - 9, y: scroller.bounds.midY), to: sidebar).x
            let gap = knobLeft - selection.maxX
            XCTAssertGreaterThanOrEqual(gap, 6)
            XCTAssertLessThanOrEqual(gap, 8, "The reserved gutter and card padding must not add two separate gaps")
            let cell = try XCTUnwrap(table.view(atColumn: 0, row: 10, makeIfNecessary: true) as? NSTableCellView)
            cell.layoutSubtreeIfNeeded()
            let name = try XCTUnwrap(cell.textField)
            XCTAssertLessThanOrEqual(name.convert(name.bounds, to: sidebar).maxX,
                                     scroller.convert(scroller.bounds, to: sidebar).minX - 4,
                                     "Long names stay clear of the broader native scroller hit target")
        }
    }

}
