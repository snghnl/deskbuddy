import Foundation
import Yams

/// UI language preference. `.system` follows the user's macOS preferred language.
enum AppLanguage: String, CaseIterable {
    case system
    case korean
    case english
}

/// YAML-backed localization.
///
/// All user-visible strings live in `Resources/Localizations/<lang>.yml` as flat
/// `key: value` pairs. Look them up with `L.s("key")`, or `L.f("key", args...)`
/// for `String(format:)`-style entries. Missing keys fall back to English, and
/// ultimately to the key itself so a typo is visible instead of silent.
///
/// The language can be changed at runtime from Settings; views re-render via the
/// `settingsChanged` notification.
enum L {
    static var preference: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.language) ?? "") ?? .system
    }

    static var isKorean: Bool {
        switch preference {
        case .korean: true
        case .english: false
        case .system: Locale.preferredLanguages.first?.hasPrefix("ko") ?? false
        }
    }

    /// Locale for custom date formatters that should follow the app language.
    static var locale: Locale {
        Locale(identifier: isKorean ? "ko_KR" : "en_US")
    }

    /// Look up a localized string by key.
    static func s(_ key: String) -> String {
        let table = isKorean ? korean : english
        return table[key] ?? english[key] ?? key
    }

    /// Look up a `String(format:)` entry and apply the arguments.
    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: s(key), arguments: args)
    }

    // MARK: - Table loading

    private static let korean = loadTable("ko")
    private static let english = loadTable("en")

    private static func loadTable(_ lang: String) -> [String: String] {
        guard let url = Bundle.module.url(forResource: lang, withExtension: "yml", subdirectory: "Localizations"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let raw = try? Yams.load(yaml: text) as? [String: Any]
        else {
            assertionFailure("Failed to load localization table: \(lang).yml")
            return [:]
        }
        return raw.compactMapValues { $0 as? String }
    }
}
