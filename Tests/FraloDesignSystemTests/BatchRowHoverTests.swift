import AppKit
import XCTest
@testable import FraloDesignSystem

final class BatchRowHoverTests: XCTestCase {
    // A command-line XCTest process must finish AppKit launch before testing
    // animation frames in a hidden window, including when this suite runs first.
    @MainActor private static let app: NSApplication = {
        let app = NSApplication.shared
        app.finishLaunching()
        return app
    }()

    @MainActor private final class KeyWindow: NSWindow {
        var simulatedKey = true
        var simulatedPointer = NSPoint(x: -100, y: -100)
        override var isKeyWindow: Bool { simulatedKey }
        override var mouseLocationOutsideOfEventStream: NSPoint { simulatedPointer }
    }

    @MainActor private func scene(compact: Bool = false) throws -> (KeyWindow, BatchList, NSTableView, BatchSelectionRow) {
        _ = Self.app
        let window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 400),
                               styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let list = BatchList(entries: (0..<8).map { BatchEntry(id: "\($0)", title: "image\($0).png") }, compact: compact)
        list.preferences.reduceMotion = true
        window.contentView = list; list.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(list.documentView as? NSTableView)
        let row = try XCTUnwrap(table.rowView(atRow: 1, makeIfNecessary: true) as? BatchSelectionRow)
        return (window, list, table, row)
    }

    @MainActor private func event(_ type: NSEvent.EventType, window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                                            windowNumber: window.windowNumber, context: nil,
                                            eventNumber: 0, trackingNumber: 0, userData: nil))
    }

    @MainActor func testHoverDoesNotSelectOrMoveFocusAndSelectedStateWins() throws {
        let (window, list, table, row) = try scene(); defer { window.close() }
        XCTAssertTrue(window.makeFirstResponder(table))
        var selections = 0; list.onSelection = { _ in selections += 1 }
        row.mouseEntered(with: try event(.mouseEntered, window: window))
        XCTAssertEqual(row.hoverAmount, 1, "Reduced motion applies pointer feedback immediately")
        XCTAssertEqual(list.selectedIndex, 0); XCTAssertEqual(selections, 0)
        XCTAssertTrue(window.firstResponder === table)
        list.moveSelection(by: 1)
        XCTAssertEqual(list.selectedIndex, 1)
        XCTAssertTrue(row.isSelected); XCTAssertEqual(row.hoverAmount, 0, "Hover cannot stack over selection")
        row.mouseExited(with: try event(.mouseExited, window: window))
        XCTAssertEqual(list.selectedIndex, 1); XCTAssertEqual(row.hoverAmount, 0)
    }

    @MainActor func testWindowDeactivationAndDetachingClearHover() throws {
        let (window, list, _, row) = try scene(); defer { window.close() }
        row.mouseEntered(with: try event(.mouseEntered, window: window)); XCTAssertEqual(row.hoverAmount, 1)
        window.simulatedKey = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertEqual(row.hoverAmount, 0); XCTAssertEqual(list.selectedIndex, 0)
        row.mouseEntered(with: try event(.mouseEntered, window: window))
        XCTAssertEqual(row.hoverAmount, 0, "Inactive windows must not show pointer hover")
        window.simulatedKey = true
        row.mouseEntered(with: try event(.mouseEntered, window: window)); XCTAssertEqual(row.hoverAmount, 1)
        window.contentView = nil
        XCTAssertEqual(row.hoverAmount, 0, "Detached/recycled rows cannot retain hover")
    }

    @MainActor func testCompactRailKeepsItsExistingAppearance() throws {
        let (window, _, _, row) = try scene(compact: true); defer { window.close() }
        row.mouseEntered(with: try event(.mouseEntered, window: window))
        XCTAssertEqual(row.hoverAmount, 0)
    }

    @MainActor func testHoverFadeHasIntermediateFramesAndCanReverse() throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            throw XCTSkip("System Reduce Motion intentionally disables the fade")
        }
        let (window, list, _, row) = try scene(); defer { window.close() }
        list.preferences.reduceMotion = false
        window.simulatedPointer = row.convert(NSPoint(x: row.bounds.midX, y: row.bounds.midY), to: nil)
        row.mouseEntered(with: try event(.mouseEntered, window: window))
        row.updateTrackingAreas()
        RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        XCTAssertGreaterThan(row.hoverAmount, 0)
        XCTAssertLessThan(row.hoverAmount, 1, "Pointer entry must fade rather than jump to its final shade")
        window.simulatedPointer = NSPoint(x: -100, y: -100)
        row.mouseExited(with: try event(.mouseExited, window: window))
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(row.hoverAmount, 0, accuracy: 0.001)
        XCTAssertEqual(list.selectedIndex, 0)
    }

    @MainActor func testPaintedSelectionIsStrongerThanHoverInBothAppearances() throws {
        let row = BatchSelectionRow(); row.compact = false
        row.frame = NSRect(x: 0, y: 0, width: 240, height: 94)
        func paintedAlpha(selection: Bool) throws -> CGFloat {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 240, pixelsHigh: 94,
                                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
            NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current = context; context.cgContext.clear(row.bounds)
            row.effectiveAppearance.performAsCurrentDrawingAppearance {
                if selection { row.drawSelection(in: row.bounds) } else { row.drawBackground(in: row.bounds) }
            }
            context.flushGraphics()
            return try XCTUnwrap(bitmap.colorAt(x: 120, y: 47)).alphaComponent
        }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            row.appearance = NSAppearance(named: appearance)
            row.isSelected = false; row.hoverAmount = 1
            let hover = try paintedAlpha(selection: false)
            row.isSelected = true
            let selected = try paintedAlpha(selection: true)
            XCTAssertGreaterThan(hover, 0); XCTAssertGreaterThan(selected, hover * 1.5)
            row.hoverAmount = 1
            XCTAssertEqual(try paintedAlpha(selection: false), 0, "No hover wash behind a selected row")
            row.preferences.increaseContrast = true
            XCTAssertGreaterThan(try paintedAlpha(selection: true), selected)
            row.preferences.increaseContrast = false
        }
    }
}
