import AppKit
import XCTest
import FraloLocalization
@testable import FraloApp

final class SettingsSearchTests: XCTestCase {
    private var original = ""
    override func setUp() { super.setUp(); original = L10n.language; L10n.setLanguage("zh-Hans") }
    override func tearDown() { L10n.setLanguage(original); super.tearDown() }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
    private func defaults() throws -> UserDefaults {
        let suite = "fralo-search-\(UUID())"
        let value = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { value.removePersistentDomain(forName: suite) }
        return value
    }

    @MainActor func testMatchesCurrentLanguageEnglishOptionsAndFullWidthText() {
        XCTAssertEqual(SettingsSearch.search("深色"), .init(panes: [.appearance], rows: [SettingsSearch.Row.appearance]))
        XCTAssertEqual(SettingsSearch.search("dark").rows, [SettingsSearch.Row.appearance], "English names work in any language")
        XCTAssertEqual(SettingsSearch.search("ＤＡＲＫ").rows, [SettingsSearch.Row.appearance])
        XCTAssertEqual(SettingsSearch.search("日本語").rows, [SettingsSearch.Row.language])
        XCTAssertEqual(SettingsSearch.search("跟随系统").rows, [SettingsSearch.Row.appearance, SettingsSearch.Row.language])
        XCTAssertEqual(SettingsSearch.search(" Version ").panes, [.updates])
        XCTAssertEqual(SettingsSearch.search("更新").panes, [.updates], "A category name matches without singling out rows")
        XCTAssertTrue(SettingsSearch.search("zzz").isEmpty)
        XCTAssertEqual(SettingsSearch.search(""), .init(panes: SettingsWindowController.Pane.allCases))
        L10n.setLanguage("ja")
        XCTAssertEqual(SettingsSearch.search("表示言語").rows, [SettingsSearch.Row.language], "Terms follow a language change")
    }

    @MainActor func testSearchFiltersSidebarHighlightsRowsAndShowsNoResults() throws {
        _ = NSApplication.shared
        let settings = SettingsWindowController(selection: .system, updates: nil, preferences: try defaults()) { _ in }
        defer { settings.window?.close() }
        XCTAssertEqual(settings.searchField.placeholderString, L10n.tr("搜索"))
        XCTAssertEqual(settings.searchField.accessibilityLabel(), L10n.tr("搜索设置"))
        func search(_ text: String) { settings.searchField.stringValue = text; settings.updateSearch() }
        func rows() -> [SettingsRowView] { descendants(settings.window!.contentView!).compactMap { $0 as? SettingsRowView } }
        func noResultsVisible() -> Bool {
            descendants(settings.window!.contentView!).contains { ($0 as? NSTextField)?.stringValue == L10n.tr("无结果") && !$0.isHiddenOrHasHiddenAncestor }
        }

        search("上次检查")
        XCTAssertEqual(settings.visiblePanes, [.updates]); XCTAssertEqual(settings.sidebar.numberOfRows, 1)
        XCTAssertEqual(settings.pane, .updates, "The only match opens")
        XCTAssertEqual(rows().filter(\.isHighlighted).map(\.searchID), [SettingsSearch.Row.lastCheck])
        XCTAssertEqual(rows().first { $0.isHighlighted }?.accessibilityValueDescription(), L10n.tr("与搜索匹配"))
        XCTAssertFalse(noResultsVisible())

        search("zzz")
        XCTAssertEqual(settings.sidebar.numberOfRows, 0); XCTAssertTrue(noResultsVisible())
        XCTAssertTrue(rows().allSatisfy { !$0.isHighlighted })

        search("语言")
        XCTAssertEqual(settings.pane, .appearance)
        XCTAssertEqual(rows().filter(\.isHighlighted).map(\.searchID), [SettingsSearch.Row.language])

        settings.select(.updates)
        XCTAssertEqual(settings.searchField.stringValue, "", "Choosing a category outside the results clears the search")
        XCTAssertEqual(settings.visiblePanes, SettingsWindowController.Pane.allCases)
        XCTAssertTrue(rows().allSatisfy { !$0.isHighlighted })
    }

    @MainActor func testKeyboardFindReturnAndEscape() throws {
        _ = NSApplication.shared
        let settings = SettingsWindowController(selection: .system, updates: nil, preferences: try defaults()) { _ in }
        defer { settings.window?.close() }
        let window = try XCTUnwrap(settings.window)
        let find = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber,
                                                  context: nil, characters: "f", charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3))
        XCTAssertTrue(window.performKeyEquivalent(with: find))
        XCTAssertTrue(window.firstResponder === settings.searchField.currentEditor() || window.firstResponder === settings.searchField)
        let editor = NSTextView()
        settings.searchField.stringValue = "版本"; settings.updateSearch()
        XCTAssertTrue(settings.control(settings.searchField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertTrue(window.firstResponder === settings.sidebar, "Return moves into the results")
        XCTAssertEqual(settings.sidebar.selectedRow, 0)
        XCTAssertTrue(settings.control(settings.searchField, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(settings.searchField.stringValue, ""); XCTAssertEqual(settings.visiblePanes.count, 2)
        XCTAssertFalse(settings.control(settings.searchField, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))),
                       "Escape with an empty field falls through to the system")
        settings.focusSearch(); settings.searchField.stringValue = "zzz"; settings.updateSearch()
        XCTAssertTrue(settings.control(settings.searchField, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        XCTAssertFalse(window.firstResponder === settings.sidebar, "Nothing to move into without results")
    }
}
