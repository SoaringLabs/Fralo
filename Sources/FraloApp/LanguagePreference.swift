import FraloLocalization
import Foundation

/// Fralo's interface language. It is the same per-app `AppleLanguages` value that
/// System Settings → General → Language & Region → Applications writes, so both places stay in agreement.
/// Settings applies a change immediately; the stored value also sets the language for the next launch.
struct LanguagePreference {
    static let key = "AppleLanguages"
    let defaults: UserDefaults
    /// The app's own defaults domain. `AppleLanguages` also exists in the global domain, which must not count as a choice.
    let domain: String

    init(defaults: UserDefaults = .standard, domain: String = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName) {
        self.defaults = defaults; self.domain = domain
    }

    /// A supported language code, or nil when Fralo follows the system.
    var choice: String? {
        guard let languages = defaults.persistentDomain(forName: domain)?[Self.key] as? [String], !languages.isEmpty else { return nil }
        return L10n.resolveLanguage(languages)
    }

    /// The language Fralo shows for the current choice: the choice itself, or the system's preferred languages.
    var effectiveLanguage: String {
        if let choice { return choice }
        let system = defaults.persistentDomain(forName: UserDefaults.globalDomain)?[Self.key] as? [String]
        return L10n.resolveLanguage(system ?? Locale.preferredLanguages)
    }

    func set(_ language: String?) {
        if let language { defaults.set([language], forKey: Self.key) } else { defaults.removeObject(forKey: Self.key) }
    }

    /// Each language names itself, so people can find theirs whatever the current interface language is.
    static func nativeName(_ language: String) -> String {
        let locale = Locale(identifier: language)
        return locale.localizedString(forIdentifier: language)?.capitalized(with: locale) ?? language
    }
}
