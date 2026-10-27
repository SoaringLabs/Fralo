import AppKit
import XCTest
@testable import FraloDesignSystem

final class DesignSystemTests: XCTestCase {
    @MainActor func testActionButtonBusyPreservesWidthAndRequestedAvailability() async {
        _ = NSApplication.shared
        var presses = 0
        let button = ActionButton("导出全部", role: .primary, symbol: "square.and.arrow.up") { presses += 1 }
        let size = button.intrinsicContentSize
        button.performClick(nil); XCTAssertEqual(presses, 1)
        button.isBusy = true; button.performClick(nil)
        XCTAssertEqual(presses, 1); XCTAssertFalse(button.isEnabled)
        XCTAssertEqual(button.intrinsicContentSize, size)
        XCTAssertEqual(button.accessibilityLabel(), "导出全部，正在处理")
        button.isEnabled = false; button.isBusy = false
        XCTAssertFalse(button.isEnabled)
        button.isEnabled = true; button.performClick(nil)
        XCTAssertEqual(presses, 2)
        XCTAssertEqual(button.accessibilityRole(), .button)
        XCTAssertEqual(button.accessibilityLabel(), "导出全部")
    }

    @MainActor func testActionButtonTabLeavesTheControlInBothDirections() async {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.autorecalculatesKeyViewLoop = false
        let button = ActionButton("添加图片", symbol: "plus")
        button.frame = NSRect(x: 0, y: 0, width: 120, height: 34)
        let field = NSTextField(frame: NSRect(x: 150, y: 0, width: 120, height: 24))
        window.contentView?.addSubview(button); window.contentView?.addSubview(field)
        button.nextKeyView = field; field.nextKeyView = button
        for modifiers: NSEvent.ModifierFlags in [[], .shift] {
            window.makeFirstResponder(button)
            button.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!)
            XCTAssertTrue(window.firstResponder === field.currentEditor())
        }
        window.close()
    }


    @MainActor func testPickerRestorationDoesNotEditAndKeyboardRespectsDisabledState() async {
        _ = NSApplication.shared
        var edits: [Int] = []
        let picker = ValuePicker(["竖屏", "横屏"], label: "方向") { edits.append($0) }
        picker.selectedIndex = 1
        picker.choose(1); picker.choose(9)
        XCTAssertTrue(edits.isEmpty)
        picker.choose(0)
        XCTAssertEqual(edits, [0])
        picker.isEnabled = false; picker.choose(1)
        XCTAssertEqual(picker.selectedIndex, 0)
        XCTAssertEqual(edits, [0])
        XCTAssertEqual(picker.accessibilityRole(), .radioGroup)
    }

    @MainActor func testSliderClampsRejectsNonfiniteAndRestoresWithoutEdits() async {
        var edits: [Double] = []
        let row = SliderRow("透明度", range: 0...100, value: 80) { edits.append($0) }
        row.value = 70; XCTAssertTrue(edits.isEmpty)
        row.setValue(140, notify: true)
        XCTAssertEqual(row.value, 100); XCTAssertEqual(edits, [100])
        row.setValue(.nan, notify: true)
        XCTAssertEqual(row.value, 100)
        row.isEnabled = false; row.setValue(20, notify: true)
        XCTAssertEqual(row.value, 100)
    }

    @MainActor func testPercentageInputUpdatesSliderAndRejectsInvalidOrDisabledEdits() async {
        var edits: [Double] = []
        let row = SliderRow("透明度", range: 0...100, value: 80) { edits.append($0) }
        row.valueField.stringValue = "37.5"; XCTAssertTrue(row.valueField.commit())
        XCTAssertEqual(row.value, 37.5); XCTAssertEqual(edits, [37.5])
        row.valueField.stringValue = "101"; XCTAssertFalse(row.valueField.commit())
        XCTAssertEqual(row.value, 37.5); XCTAssertEqual(edits, [37.5])
        row.value = 100
        row.valueField.stringValue = "37.5"; XCTAssertTrue(row.valueField.commit())
        XCTAssertEqual(row.value, 37.5, "Dragging the slider must also update the field's committed baseline")
        row.isEnabled = false; row.valueField.stringValue = "20"
        XCTAssertFalse(row.valueField.commit()); XCTAssertEqual(row.value, 37.5)
    }

    @MainActor func testCompactThumbnailColumnFitsTheRailViewport() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let list = BatchList(entries: [BatchEntry(id: "1", title: "sample.png")], compact: true)
        list.frame = NSRect(x: 6, y: 20, width: 68, height: 300); window.contentView?.addSubview(list)
        window.contentView?.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(list.documentView as? NSTableView)
        XCTAssertEqual(table.tableColumns[0].width, list.contentView.bounds.width, accuracy: 0.5)
        XCTAssertEqual(table.frame.width, list.contentView.bounds.width, accuracy: 0.5)
    }

    @MainActor func testThumbnailBatchRetainsLongNamesFailuresAndSelectionThroughRefresh() async {
        _ = NSApplication.shared
        let name = String(repeating: "超长截图名称", count: 30) + ".png"
        let entries = (0..<100).map { BatchEntry(id: String($0), title: name + String($0), failed: $0 == 40) }
        for compact in [false, true] {
            let list = BatchList(entries: entries, compact: compact)
            list.select(40); list.moveSelection(by: 1); list.update(entries)
            XCTAssertEqual(list.selectedIndex, 41)
            let failed = ThumbnailRow(entry: entries[40], compact: compact)
            XCTAssertTrue(failed.accessibilityLabel()?.contains("加载失败") == true)
            XCTAssertTrue(failed.toolTip?.contains(name) == true)
            let normal = ThumbnailRow(entry: entries[0], compact: compact)
            XCTAssertNil(normal.textField, "The filename must not compete with the thumbnail")
        }
    }

    @MainActor func testFormSlidersUseAvailableWidthRegardlessOfTheirValue() async {
        let first = SliderRow("设备缩放", range: 20...100, value: 74)
        let second = SliderRow("设备透明度", range: 0...100, value: 100)
        let form = FraloStyle.stack([first, second], fillWidth: true)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 180))
        form.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(form)
        NSLayoutConstraint.activate([form.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                                     form.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                                     form.topAnchor.constraint(equalTo: host.topAnchor)])
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(second.slider.frame.width, 150)
        XCTAssertEqual(first.slider.frame.width, second.slider.frame.width, accuracy: 1)
        XCTAssertGreaterThanOrEqual(second.valueLabel.frame.width, 48)
    }

    @MainActor func testClickingAParameterTakesFocusAwayFromTheCanvas() async {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let canvas = CanvasSurface(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let picker = ValuePicker(["A", "B"], label: "参数")
        picker.frame = NSRect(x: 0, y: 200, width: 200, height: 30)
        window.contentView?.addSubview(canvas); window.contentView?.addSubview(picker)
        window.makeFirstResponder(canvas)
        let button = picker.accessibilityChildren()?.last as? NSButton
        button?.performClick(nil)
        XCTAssertTrue(window.firstResponder === picker)
        XCTAssertEqual(picker.selectedIndex, 1)
        XCTAssertEqual(picker.focusRingType, .none, "Pointer selection should not add a second large selection outline")
        picker.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 123)!)
        XCTAssertEqual(picker.focusRingType, .exterior, "Keyboard use must expose a visible focus ring")
        window.close()
    }

    @MainActor func testTabAndBackTabLeaveCustomKeyboardControls() async {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.autorecalculatesKeyViewLoop = false
        let picker = ValuePicker(["A", "B"], label: "参数")
        picker.frame = NSRect(x: 0, y: 220, width: 200, height: 30)
        let field = NSTextField(frame: NSRect(x: 220, y: 220, width: 150, height: 24))
        let canvas = CanvasSurface(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        for view in [picker, field, canvas] { window.contentView?.addSubview(view) }
        picker.nextKeyView = field; field.nextKeyView = canvas; canvas.nextKeyView = picker
        func tab(_ view: NSView, shift: Bool = false) {
            window.makeFirstResponder(view)
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? .shift : [], timestamp: 0,
                                         windowNumber: window.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!
            view.keyDown(with: event)
        }
        tab(picker)
        XCTAssertTrue(window.firstResponder === field.currentEditor())
        tab(picker, shift: true); XCTAssertTrue(window.firstResponder === canvas)
        // AppKit may skip non-text controls when system keyboard navigation is off.
        tab(canvas); XCTAssertFalse(window.firstResponder === canvas)
        tab(canvas, shift: true); XCTAssertTrue(window.firstResponder === field.currentEditor())
        window.close()
    }

    @MainActor func testNumberFieldRejectsInvalidEditsAndPreservesLastValidValue() async {
        var edits: [Double] = []
        let field = ValueField(label: "质量", value: 90, range: 1...100) { edits.append($0) }
        for invalid in ["nan", "infinity", "0", "101", "not a number"] {
            field.stringValue = invalid; XCTAssertFalse(field.commit()); XCTAssertEqual(field.value, 90)
        }
        field.stringValue = "80"; XCTAssertTrue(field.commit()); XCTAssertEqual(edits, [80])
        field.isEnabled = false; field.stringValue = "70"; XCTAssertFalse(field.commit())
        XCTAssertEqual(field.value, 80)
    }

    @MainActor func testBusyButtonRestoresRequestedAvailabilityAndCurrentTitle() async {
        let button = ActionButton("导出")
        button.title = "导出全部 · 3 张"; button.isBusy = true
        XCTAssertFalse(button.isEnabled)
        button.isEnabled = false; button.isBusy = false
        XCTAssertFalse(button.isEnabled)
        XCTAssertEqual(button.title, "导出全部 · 3 张")
        button.isEnabled = true; XCTAssertTrue(button.isEnabled)
    }

    @MainActor func testExportCurrentNeverChangesPrimaryAction() async {
        var all = 0, current = 0
        let action = ExportAction(count: 3)
        action.onExportAll = { all += 1 }; action.onExportCurrent = { current += 1 }
        XCTAssertEqual(action.primary.accessibilityLabel(), "导出全部 · 3 张")
        XCTAssertEqual(action.primary.toolTip, "导出全部 · 3 张")
        action.exportCurrent(); action.primary.performClick(nil)
        XCTAssertEqual(current, 1); XCTAssertEqual(all, 1)
        action.count = 0; action.exportCurrent(); action.primary.performClick(nil)
        XCTAssertEqual(action.primary.accessibilityLabel(), "导出全部 · 0 张")
        XCTAssertEqual(action.primary.toolTip, "导出全部 · 0 张")
        XCTAssertEqual(current, 1); XCTAssertEqual(all, 1)
        XCTAssertFalse(action.disclosure.isEnabled)
    }

    @MainActor func testBatchSelectionClampsAndKeepsIdentityAcrossRefresh() async {
        let entries = (0..<3).map { BatchEntry(id: "\($0)", title: "\($0).png") }
        let list = BatchList(entries: entries)
        list.moveSelection(by: -1); XCTAssertEqual(list.selectedIndex, 0)
        list.moveSelection(by: 99); XCTAssertEqual(list.selectedIndex, 2)
        list.update([entries[2], entries[0], entries[1]])
        XCTAssertEqual(list.selectedIndex, 0)
        list.update([]); XCTAssertNil(list.selectedIndex)
    }

    @MainActor func testCanvasResizingOnlyChangesViewingGeometry() async {
        let image = NSImage(size: NSSize(width: 400, height: 300))
        let canvas = CanvasSurface(frame: NSRect(x: 0, y: 0, width: 832, height: 632))
        canvas.image = image
        XCTAssertEqual(canvas.imageRect.size, NSSize(width: 800, height: 600))
        canvas.setFrameSize(NSSize(width: 432, height: 332))
        XCTAssertEqual(canvas.imageRect.size, image.size)
        XCTAssertEqual(image.size, NSSize(width: 400, height: 300))
        canvas.zoom = 0.5
        XCTAssertEqual(canvas.imageRect.size, NSSize(width: 200, height: 150))
    }

    @MainActor func testAccessibilityRequestsCanOnlyStrengthenSystemPreferences() async {
        var preferences = DesignPreferences()
        preferences.reduceMotion = true; preferences.reduceTransparency = true; preferences.increaseContrast = true
        XCTAssertEqual(FraloMotion.duration(.structure, preferences: preferences), 0)
        let surface = MaterialSurface(.workspace)
        surface.preferences = preferences
        XCTAssertTrue(surface.isUsingOpaqueFallback)
        XCTAssertTrue(preferences.effectiveIncreaseContrast)
    }

    @MainActor func testSwatchesRemainSingleSelectedAndDoNotRetainTheirOwner() async {
        weak var released: SwatchPicker?
        autoreleasepool {
            let group = SwatchPicker([("A", nil), ("B", nil)])
            released = group
            group.buttons[1].performClick(nil)
            group.buttons[1].performClick(nil)
            XCTAssertFalse(group.buttons[0].isSelected)
            XCTAssertTrue(group.buttons[1].isSelected)
        }
        XCTAssertNil(released)
    }
}
