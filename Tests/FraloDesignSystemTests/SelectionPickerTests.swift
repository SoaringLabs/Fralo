import AppKit
import XCTest
@testable import FraloDesignSystem

final class SelectionPickerTests: XCTestCase {
    @MainActor private final class Receiver: NSObject {
        var values: [Int] = []
        @objc func changed(_ sender: ValuePicker) { values.append(sender.selectedIndex) }
    }

    @MainActor func testNativeCommitPreservesTargetActionAndEmitsOneBusinessEdit() async {
        _ = NSApplication.shared
        var edits: [Int] = []
        let picker = ValuePicker(["PNG", "JPEG"], label: "格式") { edits.append($0) }
        let receiver = Receiver()
        picker.target = receiver; picker.action = #selector(Receiver.changed(_:))
        // Exercise the same sendAction boundary as the native cell and accessibility segments.
        picker.selectedSegment = 1
        XCTAssertTrue(picker.sendAction(picker.action, to: picker.target))
        XCTAssertEqual(picker.selectedIndex, 1)
        XCTAssertEqual(edits, [1]); XCTAssertEqual(receiver.values, [1])
        XCTAssertFalse(picker.sendAction(picker.action, to: picker.target))
        picker.choose(1)
        XCTAssertEqual(edits, [1]); XCTAssertEqual(receiver.values, [1])
        picker.choose(0)
        XCTAssertEqual(edits, [1, 0]); XCTAssertEqual(receiver.values, [1, 0])
    }

    @MainActor func testRestoreInvalidAndDisabledSelectionsStaySilent() async {
        _ = NSApplication.shared
        var edits: [Int] = []
        let picker = ValuePicker(["无损", "均衡", "最小"], label: "体积") { edits.append($0) }
        picker.selectedIndex = 1
        picker.selectedIndex = -1; picker.selectedIndex = 9
        picker.choose(-1); picker.choose(9)
        XCTAssertEqual(picker.selectedSegment, 1); XCTAssertTrue(edits.isEmpty)
        picker.setEnabled(false, forSegment: 2); picker.choose(2)
        picker.selectedSegment = 2
        XCTAssertFalse(picker.sendAction(picker.action, to: picker.target))
        XCTAssertEqual(picker.selectedSegment, 1)
        picker.isEnabled = false
        picker.selectedSegment = 0
        XCTAssertFalse(picker.sendAction(picker.action, to: picker.target))
        picker.choose(0)
        XCTAssertEqual(picker.selectedIndex, 1); XCTAssertTrue(edits.isEmpty)
        picker.selectedIndex = 0
        XCTAssertEqual(picker.selectedSegment, 0); XCTAssertTrue(edits.isEmpty)
    }

    @MainActor func testNativeRolesAndSizesKeepContentDistinctFromParameters() async {
        _ = NSApplication.shared
        let navigation = ValuePicker(["设备", "背景", "导出"], label: "设置页面", purpose: .tabs, size: .large)
        let parameter = ValuePicker(["无", "柔和", "明显"], label: "阴影", size: .small)
        XCTAssertEqual(navigation.trackingMode, .selectOne)
        XCTAssertFalse(navigation.isContinuous)
        XCTAssertEqual(navigation.accessibilityRole(), .tabGroup)
        let tabs = navigation.accessibilityChildren() as? [NSAccessibilityElement]
        XCTAssertEqual(tabs?.map { $0.accessibilityRole() }, [.radioButton, .radioButton, .radioButton])
        XCTAssertEqual(tabs?.map { $0.accessibilitySubrole() }, [.tabButtonSubrole, .tabButtonSubrole, .tabButtonSubrole])
        XCTAssertEqual(navigation.accessibilityTabs()?.count, 3)
        XCTAssertEqual(navigation.accessibilityRoleDescription(), NSAccessibility.Role.tabGroup.description(with: nil))
        XCTAssertGreaterThan(navigation.intrinsicContentSize.height, parameter.intrinsicContentSize.height)
        if #available(macOS 26.0, *) {
            XCTAssertEqual(navigation.borderShape, .capsule)
            XCTAssertEqual(parameter.borderShape, .capsule)
        }
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) {
            XCTAssertEqual(navigation.role, .tabs)
            XCTAssertEqual(parameter.role, .tabs)
            XCTAssertEqual(parameter.accessibilityRole(), .radioGroup)
        }
        #endif
    }

    @MainActor func testParameterTreeHasStableRadioElementsAndSilentRestoration() async throws {
        _ = NSApplication.shared
        var edits: [Int] = []
        let picker = ValuePicker(["无", "柔和", "明显"], label: "阴影") { edits.append($0) }
        let options = try XCTUnwrap(picker.accessibilityChildren() as? [NSAccessibilityElement])
        XCTAssertEqual(picker.accessibilityRole(), .radioGroup)
        XCTAssertEqual(picker.accessibilityRoleDescription(), NSAccessibility.Role.radioGroup.description(with: nil))
        XCTAssertNil(picker.accessibilityTabs())
        XCTAssertNil(picker.accessibilityChildrenInNavigationOrder(), "Use the owned children for linear navigation, with no native tab list")
        XCTAssertEqual(options.map { $0.accessibilityRole() }, [.radioButton, .radioButton, .radioButton])
        XCTAssertTrue(options.allSatisfy { $0.accessibilitySubrole() == nil })
        XCTAssertTrue(options.allSatisfy { $0.accessibilityRoleDescription() == NSAccessibility.Role.radioButton.description(with: nil) })
        XCTAssertEqual(options.map { $0.accessibilityLabel() }, ["无", "柔和", "明显"])
        XCTAssertTrue(options.allSatisfy { ($0.accessibilityParent() as? ValuePicker) === picker })
        XCTAssertTrue(options[2].accessibilityPerformPress())
        XCTAssertEqual(edits, [2]); XCTAssertEqual(picker.selectedIndex, 2)
        XCTAssertEqual(options.compactMap { $0.accessibilityValue() as? NSNumber }, [0, 0, 1])
        XCTAssertTrue((picker.accessibilitySelectedChildren()?.first as? NSAccessibilityElement) === options[2])
        picker.selectedIndex = 1
        XCTAssertEqual(edits, [2], "Restoration updates AX state without emitting a business edit")
        XCTAssertEqual(options.compactMap { $0.accessibilityValue() as? NSNumber }, [0, 1, 0])
        XCTAssertTrue((picker.accessibilityChildren()?.last as? NSAccessibilityElement) === options[2])
        picker.setEnabled(false, forSegment: 2)
        XCTAssertFalse(options[2].isAccessibilityEnabled()); XCTAssertFalse(options[2].accessibilityPerformPress())
        picker.isEnabled = false
        XCTAssertTrue(options.allSatisfy { !$0.isAccessibilityEnabled() && !$0.accessibilityPerformPress() })
        XCTAssertEqual(edits, [2])
    }

    @MainActor func testParameterAXFocusSpaceArrowsAndTabShareARealKeyLoop() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 180), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.autorecalculatesKeyViewLoop = false
        defer { window.close() }
        let before = NSTextField(frame: NSRect(x: 10, y: 80, width: 90, height: 24))
        let after = NSTextField(frame: NSRect(x: 450, y: 80, width: 90, height: 24))
        var edits: [Int] = []
        let picker = ValuePicker(["无", "柔和", "明显"], label: "阴影") { edits.append($0) }
        picker.frame = NSRect(x: 120, y: 75, width: 300, height: 32)
        for view in [before, picker, after] { window.contentView?.addSubview(view) }
        before.nextKeyView = picker; picker.nextKeyView = after; after.nextKeyView = before
        let options = try XCTUnwrap(picker.accessibilityChildren() as? [NSAccessibilityElement])
        options[2].setAccessibilityFocused(true)
        XCTAssertTrue(window.firstResponder === picker)
        XCTAssertTrue(options[2].isAccessibilityFocused()); XCTAssertFalse(options[0].isAccessibilityFocused())
        XCTAssertTrue((picker.accessibilityFocusedUIElement as? NSAccessibilityElement) === options[2])
        XCTAssertEqual(picker.selectedIndex, 0, "Focusing an unselected radio must not edit its value")
        func key(_ code: UInt16, shift: Bool = false) {
            picker.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? .shift : [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!)
        }
        key(49); XCTAssertEqual(edits, [2])
        picker.setEnabled(false, forSegment: 1)
        key(123); XCTAssertEqual(edits, [2, 0], "Arrows skip a disabled option")
        XCTAssertTrue(options[0].isAccessibilityFocused())
        key(124); XCTAssertEqual(edits, [2, 0, 2])
        picker.selectedIndex = 0
        XCTAssertTrue(options[0].isAccessibilityFocused()); XCTAssertEqual(edits, [2, 0, 2])
        key(48); XCTAssertTrue(window.firstResponder === after.currentEditor())
        XCTAssertNil(picker.accessibilityFocusedUIElement)
        XCTAssertTrue(options.allSatisfy { !$0.isAccessibilityFocused() })
        window.makeFirstResponder(picker)
        key(48, shift: true); XCTAssertTrue(window.firstResponder === before.currentEditor())
    }

    @MainActor func testParameterHitFramesFollowWindowResizeAndScrolling() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 220), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 220))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 1000))
        let picker = ValuePicker(["无", "柔和", "明显"], label: "阴影")
        picker.frame = NSRect(x: 20, y: 750, width: 300, height: 32)
        document.addSubview(picker); scroll.documentView = document; window.contentView = scroll
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 700))
        let options = try XCTUnwrap(picker.accessibilityChildren() as? [NSAccessibilityElement])
        for option in options {
            let frame = option.accessibilityFrame()
            XCTAssertTrue((picker.accessibilityHitTest(NSPoint(x: frame.midX, y: frame.midY)) as? NSAccessibilityElement) === option)
        }
        let original = options[1].accessibilityFrame()
        window.setFrameOrigin(NSPoint(x: window.frame.minX + 80, y: window.frame.minY + 40))
        let moved = options[1].accessibilityFrame()
        XCTAssertEqual(moved.minX - original.minX, 80, accuracy: 0.1)
        XCTAssertEqual(moved.minY - original.minY, 40, accuracy: 0.1)
        picker.setFrameSize(NSSize(width: 360, height: 32))
        XCTAssertEqual(options[1].accessibilityFrame().width, 120, accuracy: 0.1)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 0))
        XCTAssertTrue(try XCTUnwrap(picker.accessibilityVisibleChildren()).isEmpty)
        XCTAssertFalse((picker.accessibilityHitTest(NSPoint(x: moved.midX, y: moved.midY)) as? NSAccessibilityElement) === options[1])
    }

    @MainActor func testAutomaticWindowKeyLoopIncludesVisibleEnabledSelectors() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let before = NSTextField(frame: NSRect(x: 10, y: 120, width: 90, height: 24))
        let parameter = ValuePicker(["PNG", "JPEG"], label: "格式")
        parameter.frame = NSRect(x: 120, y: 120, width: 180, height: 32)
        let tabs = ValuePicker(["设备", "背景"], label: "页面", purpose: .tabs)
        tabs.frame = NSRect(x: 320, y: 120, width: 180, height: 32)
        for view in [before, parameter, tabs] { window.contentView?.addSubview(view) }
        window.recalculateKeyViewLoop()
        var visited = Set<ObjectIdentifier>(); var current: NSView? = before
        while let view = current, visited.insert(ObjectIdentifier(view)).inserted { current = view.nextValidKeyView }
        XCTAssertTrue(visited.contains(ObjectIdentifier(parameter)))
        XCTAssertTrue(visited.contains(ObjectIdentifier(tabs)))
        parameter.isEnabled = false; XCTAssertFalse(parameter.canBecomeKeyView)
        tabs.isHidden = true; XCTAssertFalse(tabs.canBecomeKeyView)
    }
}
