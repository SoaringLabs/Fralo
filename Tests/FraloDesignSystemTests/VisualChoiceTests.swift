import AppKit
import XCTest
@testable import FraloDesignSystem

final class VisualChoiceTests: XCTestCase {
    @MainActor func testExportDisclosureStaysAtTrailingEdgeWhenPanelExpands() async {
        _ = NSApplication.shared
        let action = ExportAction(count: 3)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 60))
        action.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(action)
        NSLayoutConstraint.activate([action.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            action.trailingAnchor.constraint(equalTo: host.trailingAnchor), action.topAnchor.constraint(equalTo: host.topAnchor)])
        for width: CGFloat in [280, 360, 400] {
            host.setFrameSize(NSSize(width: width, height: 60)); host.layoutSubtreeIfNeeded()
            XCTAssertEqual(action.disclosure.frame.maxX, width, accuracy: 1)
            XCTAssertEqual(action.primary.frame.width, width - 35, accuracy: 1)
        }
    }

    @MainActor func testRestorationAndArtworkUpdatesDoNotEditAndDisabledChoicesStayPut() async throws {
        _ = NSApplication.shared
        var edits: [Int] = []
        let group = VisualChoiceGroup([VisualChoiceItem("A"), VisualChoiceItem("B")], label: "外框") { edits.append($0) }
        group.selectedIndex = 1
        group.setImages([NSImage(size: NSSize(width: 20, height: 40)), nil])
        group.choose(1); group.choose(99)
        XCTAssertTrue(edits.isEmpty)
        group.choose(0)
        XCTAssertEqual(edits, [0])
        let children = try XCTUnwrap(group.accessibilityChildren() as? [NSButton])
        XCTAssertEqual(group.accessibilityRole(), .radioGroup)
        XCTAssertEqual(children.map { $0.accessibilityRole() }, [.radioButton, .radioButton])
        XCTAssertEqual(children.map(\.state), [.on, .off])
        group.isEnabled = false; children[1].performClick(nil); group.choose(1)
        XCTAssertEqual(group.selectedIndex, 0)
        XCTAssertEqual(edits, [0])
        XCTAssertTrue(children.allSatisfy { !$0.isEnabled })
        group.selectedIndex = nil
        XCTAssertTrue(children.allSatisfy { $0.state == .off })
        let invalid = VisualChoiceGroup([VisualChoiceItem("A")], label: "空选择", selected: 9)
        XCTAssertNil(invalid.selectedIndex)
        XCTAssertEqual(invalid.focusRingMaskBounds, invalid.bounds)
    }

    @MainActor func testGridKeysEditOnlyTheFocusedParameterAndTabLeavesIt() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 360), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.autorecalculatesKeyViewLoop = false
        defer { window.close() }
        let group = VisualChoiceGroup((0..<4).map { VisualChoiceItem("\($0)") }, label: "方向")
        group.frame = NSRect(x: 0, y: 40, width: 300, height: 240)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        window.contentView?.addSubview(group); window.contentView?.addSubview(field)
        group.nextKeyView = field; field.nextKeyView = group
        window.makeFirstResponder(group)
        func key(_ code: UInt16, shift: Bool = false) {
            group.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? .shift : [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!)
        }
        key(125); XCTAssertEqual(group.selectedIndex, 2)
        key(124); XCTAssertEqual(group.selectedIndex, 3)
        key(126); XCTAssertEqual(group.selectedIndex, 1)
        key(123); XCTAssertEqual(group.selectedIndex, 0)
        for shift in [false, true] {
            window.makeFirstResponder(group); key(48, shift: shift)
            XCTAssertTrue(window.firstResponder === field.currentEditor())
        }
    }

    @MainActor func testGlassAndLegacyFallbackKeepForegroundInsideTheirContentHost() async {
        _ = NSApplication.shared
        for native in [false, true] {
            let panel = MaterialSurface(.panel, radius: 24, useNativeGlass: native)
            let button = ActionButton("前景"); panel.contentView.addSubview(button)
            if #available(macOS 26.0, *), native {
                let glass = panel.subviews.compactMap { $0 as? NSGlassEffectView }.first
                XCTAssertTrue(glass?.contentView === panel.contentView)
                XCTAssertTrue(panel.contentView.isDescendant(of: panel))
            } else { XCTAssertTrue(panel.contentView.superview === panel) }
            var preferences = DesignPreferences(); preferences.reduceTransparency = true
            panel.preferences = preferences
            XCTAssertTrue(panel.isUsingOpaqueFallback)
            XCTAssertTrue(button.superview === panel.contentView)
            XCTAssertFalse(button.isHidden)
            XCTAssertTrue(button.isEnabled)
        }
    }
}
