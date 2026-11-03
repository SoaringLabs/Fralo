import AppKit
import XCTest
@testable import FraloDesignSystem

final class ControlHoverTests: XCTestCase {
    @MainActor private final class KeyWindow: NSWindow {
        var simulatedKey = true
        var simulatedPointer = NSPoint(x: -100, y: -100)
        override var isKeyWindow: Bool { simulatedKey }
        override var mouseLocationOutsideOfEventStream: NSPoint { simulatedPointer }
    }
    @MainActor private func window() -> KeyWindow {
        _ = NSApplication.shared
        let window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
                               styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }
    @MainActor private func event(_ type: NSEvent.EventType, _ window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.enterExitEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
    }
    @MainActor private func alpha(_ view: NSView) throws -> CGFloat {
        let w = Int(view.bounds.width), h = Int(view.bounds.height)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context; context.cgContext.clear(view.bounds)
        view.effectiveAppearance.performAsCurrentDrawingAppearance { view.draw(view.bounds) }
        context.flushGraphics()
        return try XCTUnwrap(bitmap.colorAt(x: 6, y: h / 2)).alphaComponent
    }

    @MainActor func testSharedFadeReversesFromCurrentShadeAndReduceMotionFinishesIt() throws {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { throw XCTSkip("System Reduce Motion disables fades") }
        let window = window(); defer { window.close() }
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        window.contentView?.addSubview(view)
        let hover = HoverFeedback(view: view); hover.viewDidMoveToWindow()
        hover.enter()
        let entry = try XCTUnwrap(hover.animation)
        XCTAssertEqual(entry.duration, FraloMotion.duration(.hover))
        XCTAssertEqual(entry.animationCurve, .easeOut)
        // Advance AppKit's eased progress deterministically; wall-clock sleeps can skip short fades under load.
        entry.currentProgress = 0.4
        let intermediate = hover.amount
        XCTAssertGreaterThan(intermediate, 0); XCTAssertLessThan(intermediate, 1)
        hover.exit()
        XCTAssertEqual(hover.amount, intermediate, accuracy: 0.001)
        let exit = try XCTUnwrap(hover.animation); exit.currentProgress = 0.4
        XCTAssertGreaterThan(hover.amount, 0); XCTAssertLessThan(hover.amount, intermediate)
        let reverseStart = hover.amount
        hover.enter(); XCTAssertEqual(hover.amount, reverseStart, accuracy: 0.001)
        var preferences = DesignPreferences(); preferences.reduceMotion = true
        hover.update(enabled: true, preferences: preferences)
        // The simulated pointer is outside: refreshing preferences must clear synthetic hover.
        XCTAssertNil(hover.animation); XCTAssertEqual(hover.amount, 0)
        hover.enter(); XCTAssertEqual(hover.amount, 1); XCTAssertNil(hover.animation)
        hover.exit(); XCTAssertEqual(hover.amount, 0)
    }

    @MainActor func testCardsFadeExistingShadesWithoutChangingSelectionOrHoveringUnavailableItems() throws {
        let window = window(); defer { window.close() }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for layout in [VisualChoiceGroup.Layout.tiles(columns: 2, height: 112), .options(columns: 2), .row] {
                let group = VisualChoiceGroup([.init("Selected"), .init("Available"), .init("Soon", available: false)],
                                              label: "Choices", layout: layout)
                group.frame = NSRect(x: 0, y: 0, width: 500, height: 300)
                group.appearance = NSAppearance(named: appearance); group.preferences.reduceMotion = true
                window.contentView?.addSubview(group); group.layoutSubtreeIfNeeded()
                defer { group.removeFromSuperview() }
                var changes = 0; group.onChange = { _ in changes += 1 }
                window.makeFirstResponder(group)
                let card = try XCTUnwrap(group.subviews[1] as? NSButton)
                let resting = try alpha(card)
                card.mouseEntered(with: try event(.mouseEntered, window))
                XCTAssertGreaterThan(try alpha(card), resting)
                XCTAssertEqual(group.selectedIndex, 0); XCTAssertEqual(changes, 0)
                XCTAssertTrue(window.firstResponder === group)
                card.mouseExited(with: try event(.mouseExited, window))
                XCTAssertEqual(try alpha(card), resting, accuracy: 0.005)
                let unavailable = try XCTUnwrap(group.subviews[2] as? NSButton)
                let unavailableShade = try alpha(unavailable)
                unavailable.mouseEntered(with: try event(.mouseEntered, window)); unavailable.highlight(true)
                XCTAssertEqual(try alpha(unavailable), unavailableShade, accuracy: 0.005)
                unavailable.performClick(nil); XCTAssertEqual(group.selectedIndex, 0)
                switch layout {
                case .row: break // This legacy style has no selected surface.
                default:
                    let selected = try XCTUnwrap(group.subviews[0] as? NSButton)
                    let shade = try alpha(selected)
                    selected.mouseEntered(with: try event(.mouseEntered, window))
                    XCTAssertEqual(try alpha(selected), shade, accuracy: 0.005)
                }
                group.isEnabled = false
                let disabledShade = try alpha(card)
                card.mouseEntered(with: try event(.mouseEntered, window))
                XCTAssertEqual(try alpha(card), disabledShade, accuracy: 0.005)
            }
        }
    }

    @MainActor func testActionHoverClearsOnBusyDisableWindowDeactivationAndDetachment() throws {
        let window = window(); defer { window.close() }
        for role in [ActionButton.Role.primary, .secondary, .quiet, .destructive] {
            var presses = 0
            let button = ActionButton("Action", role: role) { presses += 1 }
            button.frame = NSRect(x: 0, y: 0, width: 160, height: 40)
            button.preferences.reduceMotion = true; window.contentView?.addSubview(button)
            let initialSize = button.intrinsicContentSize
            button.mouseEntered(with: try event(.mouseEntered, window)); XCTAssertTrue(button.isHovered)
            XCTAssertEqual(presses, 0); XCTAssertEqual(button.intrinsicContentSize, initialSize)
            button.isBusy = true; XCTAssertFalse(button.isHovered)
            button.isBusy = false
            button.mouseEntered(with: try event(.mouseEntered, window)); XCTAssertTrue(button.isHovered)
            button.isEnabled = false; XCTAssertFalse(button.isHovered)
            button.isEnabled = true
            button.mouseEntered(with: try event(.mouseEntered, window))
            window.simulatedKey = false
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
            XCTAssertFalse(button.isHovered)
            button.mouseEntered(with: try event(.mouseEntered, window)); XCTAssertFalse(button.isHovered)
            window.simulatedKey = true
            button.mouseEntered(with: try event(.mouseEntered, window)); XCTAssertTrue(button.isHovered)
            button.removeFromSuperview(); XCTAssertFalse(button.isHovered)
            XCTAssertEqual(presses, 0)
        }
    }

    @MainActor func testStationaryPointerTrackingRefreshHandlesScrollAndRebuiltControls() {
        let window = window(); defer { window.close() }
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        window.contentView?.addSubview(view)
        let hover = HoverFeedback(view: view); hover.viewDidMoveToWindow()
        window.simulatedPointer = view.convert(NSPoint(x: 50, y: 20), to: nil)
        hover.updateTrackingAreas(); XCTAssertEqual(hover.amount, 1)
        view.setFrameOrigin(NSPoint(x: 200, y: 0))
        hover.updateTrackingAreas()
        XCTAssertEqual(hover.amount, 0, "frame=\(view.frame), bounds=\(view.bounds), pointer=\(view.convert(window.simulatedPointer, from: nil)), hovered=\(hover.isHovered)")
        XCTAssertEqual(view.trackingAreas.count, 1)
    }
}
