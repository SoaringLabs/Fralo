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
        XCTAssertGreaterThan(navigation.intrinsicContentSize.height, parameter.intrinsicContentSize.height)
        if #available(macOS 26.0, *) {
            XCTAssertEqual(navigation.borderShape, .capsule)
            XCTAssertEqual(parameter.borderShape, .capsule)
        }
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) {
            XCTAssertEqual(navigation.role, .tabs)
            XCTAssertEqual(parameter.role, .valueSelection)
        }
        #endif
    }
}
