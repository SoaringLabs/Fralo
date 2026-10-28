import AppKit
import XCTest
@testable import FraloDesignSystem

final class HIGControlsTests: XCTestCase {
    @MainActor func testInvalidNumbersExplainRangeAndRecoverWithoutChangingValue() async {
        let row = SliderRow("设备缩放", range: 10...150, value: 74)
        var edits: [Double] = []; row.onChange = { edits.append($0) }
        for text in ["abc", "999", "74oops", "NaN", "1e2", ""] {
            row.valueField.stringValue = text
            XCTAssertFalse(row.valueField.commit())
            XCTAssertEqual(row.value, 74); XCTAssertTrue(edits.isEmpty)
            XCTAssertFalse(row.validationLabel.isHidden)
            XCTAssertTrue(row.validationLabel.stringValue.contains("10–150"))
            XCTAssertEqual(row.valueField.accessibilityHelp(), row.validationLabel.stringValue)
        }
        row.valueField.stringValue = "74.5"; XCTAssertTrue(row.valueField.commit())
        XCTAssertEqual(row.value, 74.5); XCTAssertEqual(edits, [74.5]); XCTAssertTrue(row.validationLabel.isHidden)
        row.valueField.stringValue = "bad"; _ = row.valueField.commit()
        row.setValue(82.504, notify: true)
        XCTAssertTrue(row.validationLabel.isHidden)
        XCTAssertTrue(row.valueField.commit()); XCTAssertEqual(row.value, 82.504, "Leaving rounded display must preserve slider precision")
    }
    @MainActor func testNumericInputUsesLocaleDecimalAndRejectsPartialParsing() async {
        let field = ValueField(label: "缩放", value: 74.5, range: 10...150, locale: Locale(identifier: "de_DE"))
        XCTAssertEqual(field.stringValue, "74,5")
        field.stringValue = "75,25"; XCTAssertTrue(field.commit()); XCTAssertEqual(field.value, 75.25)
        field.stringValue = "75.5"; XCTAssertFalse(field.commit()); XCTAssertEqual(field.value, 75.25)
        field.restore(100); XCTAssertEqual(field.stringValue, "100"); XCTAssertNil(field.validationMessage)
    }
}
