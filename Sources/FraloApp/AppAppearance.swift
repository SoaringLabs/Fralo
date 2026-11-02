import FraloLocalization
import AppKit

enum AppAppearance: String, CaseIterable {
    case system, light, dark
    var title: String {
        switch self { case .system: return L10n.tr("跟随系统"); case .light: return L10n.tr("浅色"); case .dark: return L10n.tr("深色") }
    }
    var appearance: NSAppearance? {
        switch self { case .system: return nil; case .light: return NSAppearance(named: .aqua); case .dark: return NSAppearance(named: .darkAqua) }
    }
}
