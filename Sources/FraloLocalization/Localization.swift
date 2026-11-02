import Foundation

private final class LocalizationBundleToken: NSObject {}

/// Shared by the app, core errors, and design system. Language is selected at launch from macOS
/// language preferences (including the system's per-app language setting) and can change at runtime
/// from Fralo's Settings; interfaces rebuild on `languageDidChange`.
public enum L10n {
    public static let supportedLanguages = ["en", "zh-Hans", "zh-Hant", "ja"]
    /// Posted on the main thread after `setLanguage` changes the current language.
    public static let languageDidChange = Notification.Name("FraloLanguageDidChange")
    private static let languageLock = NSLock()
    nonisolated(unsafe) private static var current = launchLanguage
    /// Read from any thread: core errors may be formatted off the main thread.
    public static var language: String { languageLock.lock(); defer { languageLock.unlock() }; return current }

    /// Takes effect for text produced from now on. Returns false when the language is already current.
    @discardableResult
    public static func setLanguage(_ language: String) -> Bool {
        let resolved = resolveLanguage([language])
        languageLock.lock()
        let changed = resolved != current
        current = resolved
        languageLock.unlock()
        if changed { NotificationCenter.default.post(name: languageDidChange, object: nil) }
        return changed
    }

    static let launchLanguage: String = {
        #if DEBUG
        // Isolated preview override: never writes to the user's macOS language preferences.
        if CommandLine.arguments.contains("--workbench-preview"),
           let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--preview-language=") }) {
            return resolveLanguage([String(argument.dropFirst("--preview-language=".count))])
        }
        #endif
        return resolveLanguage(Locale.preferredLanguages)
    }()

    public static func resolveLanguage(_ preferences: [String]) -> String {
        Bundle.preferredLocalizations(from: supportedLanguages, forPreferences: preferences).first ?? "en"
    }

    /// Signed apps use Contents/Resources; SwiftPM tests and executables use a sibling bundle.
    /// A standalone copied CLI retains its original source-language errors if no bundle is present.
    static func resourceBundle(in host: Bundle = .main) -> Bundle {
        // xctest's main bundle belongs to Apple's test runner; the token locates our loaded test image.
        let owners = host == .main ? [host, Bundle(for: LocalizationBundleToken.self)] : [host]
        let directories = owners.flatMap { owner in
            [owner.resourceURL, owner.bundleURL, owner.bundleURL.deletingLastPathComponent(),
             owner.executableURL?.deletingLastPathComponent()].compactMap { $0 }
        }
        for directory in directories {
            if let bundle = Bundle(url: directory.appendingPathComponent("Fralo_FraloLocalization.bundle")) {
                return bundle
            }
        }
        // Bundle.module traps when its generated absolute build path no longer exists.
        // A missing optional CLI catalog must never turn a recoverable error into a crash.
        return host
    }

    private static let bundles: [String: Bundle] = {
        let resources = resourceBundle()
        return Dictionary(uniqueKeysWithValues: supportedLanguages.compactMap { language in
            guard let url = resources.url(forResource: language.lowercased(), withExtension: "lproj"),
                  let bundle = Bundle(url: url) else { return nil }
            return (language, bundle)
        })
    }()

    public static func tr(_ text: Text) -> String { translate(text, language: language) }
    /// The text in the current language followed by the same text in each of `languages`, for search terms
    /// that should also match a name people may know from another language.
    public static func tr(_ text: Text, alsoIn languages: [String]) -> [String] {
        [tr(text)] + languages.map { translate(text, language: $0) }
    }

    /// Explicit language keeps tests deterministic without mutating process-wide preferences.
    public static func translate(_ text: Text, language: String) -> String {
        let fallback = bundles["en"]?.localizedString(forKey: text.key, value: text.key, table: nil) ?? text.key
        let template = bundles[language]?.localizedString(forKey: text.key, value: fallback, table: nil) ?? fallback
        // Substitute in one pass: a filename containing "{1}" must stay a filename, not a token.
        var result = "", cursor = template.startIndex
        while cursor < template.endIndex {
            if template[cursor] == "{", let end = template[cursor...].firstIndex(of: "}"),
               let index = Int(template[template.index(after: cursor)..<end]), text.arguments.indices.contains(index) {
                result += text.arguments[index]; cursor = template.index(after: end)
            } else {
                result.append(template[cursor]); cursor = template.index(after: cursor)
            }
        }
        return result
    }

    /// A literal becomes a catalog key; interpolation becomes numbered, reorderable placeholders.
    /// Keep the full sentence inside tr rather than joining translated sentence fragments.
    public struct Text: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
        let key: String
        let arguments: [String]
        public init(stringLiteral value: String) { key = value; arguments = [] }
        public init(stringInterpolation: StringInterpolation) {
            key = stringInterpolation.key; arguments = stringInterpolation.arguments
        }
        public struct StringInterpolation: StringInterpolationProtocol {
            var key = ""
            var arguments: [String] = []
            public init(literalCapacity: Int, interpolationCount: Int) {
                key.reserveCapacity(literalCapacity); arguments.reserveCapacity(interpolationCount)
            }
            public mutating func appendLiteral(_ literal: String) { key += literal }
            public mutating func appendInterpolation<T>(_ value: T) {
                key += "{\(arguments.count)}"; arguments.append(String(describing: value))
            }
        }
    }
}
