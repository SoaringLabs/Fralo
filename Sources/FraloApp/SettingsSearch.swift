import FraloLocalization
import FraloCore
import Foundation

/// What the Settings search field can find: category, group, setting and option names in the current
/// interface language, plus their English names so an English term works in any language.
/// Built on each query so a language change made in Settings is picked up immediately.
enum SettingsSearch {
    typealias Pane = SettingsWindowController.Pane

    /// `row` names a row Settings highlights; nil matches the category without singling out a row.
    struct Entry { let pane: Pane; let row: String?; let terms: [String] }
    struct Result: Equatable {
        var panes: [Pane] = []
        var rows: Set<String> = []
        var isEmpty: Bool { panes.isEmpty }
    }

    enum Row {
        static let appearance = "appearance.theme", language = "appearance.language"
        static let automatic = "updates.automatic", version = "updates.version", lastCheck = "updates.lastCheck"
    }

    static func entries() -> [Entry] {
        let en = ["en"]
        let languages = L10n.supportedLanguages.map(LanguagePreference.nativeName)
        return [
            Entry(pane: .appearance, row: nil, terms: L10n.tr("外观", alsoIn: en)),
            Entry(pane: .appearance, row: Row.appearance, terms: L10n.tr("界面", alsoIn: en) + L10n.tr("外观", alsoIn: en)
                  + L10n.tr("选择浅色、深色，或随系统自动切换。", alsoIn: en) + L10n.tr("跟随系统", alsoIn: en)
                  + L10n.tr("浅色", alsoIn: en) + L10n.tr("深色", alsoIn: en)),
            Entry(pane: .appearance, row: Row.language, terms: L10n.tr("语言", alsoIn: en) + L10n.tr("界面语言", alsoIn: en)
                  + L10n.tr("跟随系统", alsoIn: en) + languages),
            Entry(pane: .updates, row: nil, terms: L10n.tr("更新", alsoIn: en)),
            Entry(pane: .updates, row: Row.automatic, terms: L10n.tr("自动更新", alsoIn: en) + L10n.tr("每天自动检查更新", alsoIn: en)
                  + L10n.tr("发现新版本时会先询问你，不会自动下载或安装。", alsoIn: en)),
            Entry(pane: .updates, row: Row.version, terms: L10n.tr("版本", alsoIn: en) + L10n.tr("当前版本", alsoIn: en) + [FraloInfo.version]),
            Entry(pane: .updates, row: Row.lastCheck, terms: L10n.tr("上次检查", alsoIn: en) + L10n.tr("立即检查…", alsoIn: en)
                  + L10n.tr("检查更新…", alsoIn: en))
        ]
    }

    /// Case-, accent- and width-insensitive (so half- and full-width Japanese match); categories keep sidebar order.
    static func search(_ query: String, in entries: [Entry] = entries()) -> Result {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return Result(panes: Pane.allCases) }
        let matches = entries.filter { entry in
            entry.terms.contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil }
        }
        let panes = Set(matches.map(\.pane))
        return Result(panes: Pane.allCases.filter(panes.contains), rows: Set(matches.compactMap(\.row)))
    }
}
