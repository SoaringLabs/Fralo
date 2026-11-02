import AppKit
import XCTest
import FraloCore
import FraloLocalization
@testable import FraloApp

@MainActor
private final class FakeUpdates: UpdatePreferences {
    var unavailableReason: String?
    var automaticallyChecksForUpdates = true
    var lastUpdateCheckDate: Date?
    var canCheckForUpdates = true
    var checks = 0
    func checkForUpdates(_ sender: Any?) { checks += 1 }
}

final class SettingsWindowTests: XCTestCase {
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
    private func defaults() throws -> UserDefaults {
        let suite = "fralo-settings-\(UUID())"
        let value = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { value.removePersistentDomain(forName: suite) }
        return value
    }

    @MainActor func testUpdatePaneEditsSparklePreferenceAndChecksOnDemand() throws {
        _ = NSApplication.shared
        let updates = FakeUpdates(); updates.lastUpdateCheckDate = Date()
        let settings = SettingsWindowController(selection: .system, updates: updates, preferences: try defaults()) { _ in }
        defer { settings.window?.close() }
        settings.select(.updates)
        let toggle = try XCTUnwrap(settings.automaticSwitch)
        XCTAssertTrue(toggle.isEnabled); XCTAssertEqual(toggle.state, .on)
        toggle.performClick(nil)
        XCTAssertFalse(updates.automaticallyChecksForUpdates)
        try XCTUnwrap(settings.checkButton).performClick(nil)
        XCTAssertEqual(updates.checks, 1)
        let texts = descendants(settings.window!.contentView!).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertTrue(texts.contains("\(FraloInfo.version) (\(FraloInfo.build))"))
        XCTAssertFalse(texts.contains(L10n.tr("此构建无法检查更新")))
    }

    @MainActor func testUnavailableUpdatesExplainWhyAndDisableControls() throws {
        _ = NSApplication.shared
        for updates in [FakeUpdates(), nil] as [FakeUpdates?] {
            updates?.unavailableReason = "Service failed"
            let settings = SettingsWindowController(selection: .system, updates: updates, preferences: try defaults()) { _ in }
            defer { settings.window?.close() }
            settings.select(.updates)
            XCTAssertFalse(try XCTUnwrap(settings.automaticSwitch).isEnabled)
            XCTAssertEqual(settings.automaticSwitch?.state, .off)
            XCTAssertFalse(try XCTUnwrap(settings.checkButton).isEnabled)
            let texts = descendants(settings.window!.contentView!).compactMap { ($0 as? NSTextField)?.stringValue }
            XCTAssertTrue(texts.contains(L10n.tr("此构建无法检查更新")))
            XCTAssertTrue(texts.contains(updates == nil ? L10n.tr("请打开完整的 Fralo.app 后检查更新。直接运行构建目录中的可执行文件不支持安装更新。") : "Service failed"))
            XCTAssertTrue(texts.contains(L10n.tr("从未检查")))
        }
    }

    @MainActor func testSidebarSwitchesPanesAndReopensOnTheLastOne() throws {
        _ = NSApplication.shared
        let preferences = try defaults()
        let settings = SettingsWindowController(selection: .dark, updates: FakeUpdates(), preferences: preferences) { _ in }
        XCTAssertEqual(settings.pane, .appearance)
        XCTAssertEqual(settings.picker?.selection, .dark)
        XCTAssertEqual(settings.sidebar.accessibilityLabel(), L10n.tr("设置分类"))
        settings.sidebar.selectRowIndexes([1], byExtendingSelection: false)
        XCTAssertEqual(settings.pane, .updates)
        XCTAssertNil(settings.picker)
        XCTAssertNotNil(settings.automaticSwitch)
        settings.window?.close()
        let reopened = SettingsWindowController(selection: .dark, updates: nil, preferences: preferences) { _ in }
        defer { reopened.window?.close() }
        XCTAssertEqual(reopened.pane, .updates)
        XCTAssertEqual(reopened.sidebar.selectedRow, 1)
    }

    @MainActor func testThumbnailPickerIsARadioGroupWithArrowKeys() throws {
        _ = NSApplication.shared
        var changes: [AppAppearance] = []
        let settings = SettingsWindowController(selection: .system, updates: nil, preferences: try defaults()) { changes.append($0) }
        defer { settings.window?.close() }
        let picker = try XCTUnwrap(settings.picker)
        XCTAssertEqual(picker.accessibilityRole(), .radioGroup)
        XCTAssertTrue(picker.buttons.allSatisfy { $0.accessibilityRole() == .radioButton })
        XCTAssertEqual(picker.buttons[0].accessibilityValue() as? Int, 1)
        let window = try XCTUnwrap(settings.window); window.makeFirstResponder(picker.buttons[0])
        let right = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                   context: nil, characters: "\u{F703}", charactersIgnoringModifiers: "\u{F703}", isARepeat: false, keyCode: 124))
        picker.buttons[0].keyDown(with: right)
        XCTAssertEqual(picker.selection, .light); XCTAssertEqual(changes, [.light])
        picker.buttons[2].performClick(nil); picker.buttons[2].performClick(nil)
        XCTAssertEqual(changes, [.light, .dark], "Choosing the current option again is not a change")
    }

    @MainActor func testLastCheckUsesRelativeDatesAndNeverWhenMissing() {
        XCTAssertEqual(SettingsWindowController.lastCheckText(nil), L10n.tr("从未检查"))
        let now = Date()
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: L10n.language)
        formatter.dateStyle = .medium; formatter.timeStyle = .short; formatter.doesRelativeDateFormatting = true
        XCTAssertEqual(SettingsWindowController.lastCheckText(now, now: now), formatter.string(from: now))
    }

    @MainActor func testMenusOpenSettingsAndHaveNoDuplicatePreferenceEditors() throws {
        _ = NSApplication.shared
        let previous = NSApp.mainMenu; defer { NSApp.mainMenu = previous }
        let main = MainWindowController(store: SettingsStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")),
                                        preferences: try defaults(), restoreWindow: false)
        defer { main.settingsController?.window?.close(); main.window?.close() }
        AppDelegate().installMenus(main)
        let items = Self.items(NSApp.mainMenu)
        let settings = try XCTUnwrap(items.first { $0.action == #selector(MainWindowController.showSettings(_:)) })
        XCTAssertEqual(settings.keyEquivalent, ","); XCTAssertEqual(settings.keyEquivalentModifierMask, .command)
        XCTAssertFalse(items.contains { $0.title == L10n.tr("外观") }, "Appearance is edited only in Settings")
        XCTAssertFalse(items.contains { $0.action == NSSelectorFromString("toggleAutomaticChecks:") })
        XCTAssertTrue(items.contains { $0.action == #selector(UpdateController.checkForUpdates(_:)) }, "Check for Updates remains a menu command")
        _ = NSApp.sendAction(#selector(MainWindowController.showSettings(_:)), to: main, from: settings)
        let window = try XCTUnwrap(main.settingsController?.window)
        XCTAssertTrue(window.isVisible)
        main.showSettings(nil)
        XCTAssertTrue(main.settingsController?.window === window, "Reopening reuses the same window")
    }
    @MainActor func testLanguagePreferenceUsesOnlyTheAppDomain() throws {
        let suite = "fralo-language-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let language = LanguagePreference(defaults: defaults, domain: suite)
        XCTAssertNil(language.choice, "The global AppleLanguages list is not a Fralo choice")
        language.set("ja"); XCTAssertEqual(language.choice, "ja")
        XCTAssertEqual(defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String], ["ja"])
        defaults.set(["zh-Hant-TW"], forKey: "AppleLanguages"); XCTAssertEqual(language.choice, "zh-Hant", "System Settings writes region variants")
        language.set(nil); XCTAssertNil(language.choice)
        XCTAssertEqual(LanguagePreference.nativeName("ja"), "日本語")
        XCTAssertEqual(LanguagePreference.nativeName("en"), "English")
    }

    @MainActor func testLanguagePopupAppliesImmediatelyAndRevertsWhenBusy() throws {
        _ = NSApplication.shared
        let suite = "fralo-language-ui-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        var requests: [String] = [], accept = true
        let settings = SettingsWindowController(selection: .system, updates: nil, preferences: try self.defaults(),
                                                language: LanguagePreference(defaults: defaults, domain: suite)) { _ in }
        settings.onLanguageChange = { requests.append($0); return accept }
        defer { settings.window?.close() }
        let popup = try XCTUnwrap(settings.languagePopup)
        XCTAssertEqual(popup.indexOfSelectedItem, 0)
        XCTAssertEqual(popup.accessibilityLabel(), L10n.tr("界面语言"))
        XCTAssertEqual(popup.itemArray.compactMap { $0.representedObject as? String }, L10n.supportedLanguages)
        let texts = descendants(settings.window!.contentView!).compactMap { ($0 as? NSTextField)?.stringValue }
        XCTAssertFalse(texts.contains { $0.contains("›") }, "The language row has no explanation text")
        func choose(_ code: String?) throws {
            let popup = try XCTUnwrap(settings.languagePopup)
            popup.selectItem(at: code.flatMap { c in popup.itemArray.firstIndex { $0.representedObject as? String == c } } ?? 0)
            _ = popup.target?.perform(popup.action, with: popup)
        }
        try choose("ja")
        XCTAssertEqual(requests, ["ja"]); XCTAssertEqual(defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String], ["ja"])
        accept = false
        try choose("en")
        XCTAssertEqual(requests, ["ja", "en"])
        XCTAssertEqual(defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String], ["ja"], "A refused change keeps the language in effect")
        XCTAssertEqual(settings.languagePopup?.selectedItem?.representedObject as? String, "ja")
        settings.window?.attachedSheet.map { settings.window?.endSheet($0) }
        accept = true
        try choose(nil)
        XCTAssertNil(defaults.persistentDomain(forName: suite)?["AppleLanguages"])
        XCTAssertEqual(requests.last, LanguagePreference(defaults: defaults, domain: suite).effectiveLanguage)
    }

    private static func items(_ menu: NSMenu?) -> [NSMenuItem] {
        (menu?.items ?? []).flatMap { [$0] + items($0.submenu) }
    }
}
