import Foundation
import Yams

/// UI language preference. `.system` follows the user's macOS preferred language.
public enum AppLanguage: String, CaseIterable {
    case system
    case korean
    case english

    /// UserDefaults key holding the user's choice
    public static let defaultsKey = "DeskBuddy.language"
}

/// YAML-backed localization: the language choice, and the strings every target shares.
///
/// Each target keeps its own user-visible strings in `Resources/Localizations/<lang>.yml` as
/// flat `key: value` pairs and reads them through a `Strings` of its own bundle. Core's table
/// holds only the few strings more than one target uses; look those up with `L.s("key")`,
/// or `L.f("key", args...)` for `String(format:)`-style entries. Missing keys fall back to
/// English, and ultimately to the key itself so a typo is visible instead of silent.
///
/// The language can be changed at runtime from Settings; views re-render via the
/// `settingsChanged` notification.
public enum L {
    public static var preference: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: AppLanguage.defaultsKey) ?? "") ?? .system
    }

    public static var isKorean: Bool {
        switch preference {
        case .korean: true
        case .english: false
        case .system: Locale.preferredLanguages.first?.hasPrefix("ko") ?? false
        }
    }

    /// Locale for custom date formatters that should follow the app language.
    public static var locale: Locale {
        Locale(identifier: isKorean ? "ko_KR" : "en_US")
    }

    /// Look up a shared string by key.
    public static func s(_ key: String) -> String {
        shared.lookup(key, korean: isKorean) ?? key
    }

    /// Look up a shared `String(format:)` entry and apply the arguments.
    public static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: s(key), arguments: args)
    }

    private static let shared = Strings(bundle: .module)
}

/// One target's strings, from `Resources/Localizations/<lang>.yml` in its bundle. Keys it
/// lacks come from the shared strings in Core, so a target never needs to copy those.
///
///     let strings = Strings(bundle: .module)
///     strings.s("timer.tab")
public final class Strings: Sendable {
    private let korean: [String: String]
    private let english: [String: String]

    public init(bundle: Bundle) {
        korean = Self.loadTable("ko", from: bundle)
        english = Self.loadTable("en", from: bundle)
    }

    /// Look up a localized string by key.
    public func s(_ key: String) -> String {
        s(key, korean: L.isKorean)
    }

    /// Look up a `String(format:)` entry and apply the arguments.
    public func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: s(key), arguments: args)
    }

    /// In the given language, falling back to English, then to Core's shared strings, then to the key
    func s(_ key: String, korean: Bool) -> String {
        lookup(key, korean: korean) ?? L.s(key)
    }

    /// This table's own entry in the given language, or in English — nil when it has neither
    func lookup(_ key: String, korean: Bool) -> String? {
        (korean ? self.korean[key] : nil) ?? english[key]
    }

    private static func loadTable(_ lang: String, from bundle: Bundle) -> [String: String] {
        guard let url = bundle.url(forResource: lang, withExtension: "yml", subdirectory: "Localizations"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let raw = try? Yams.load(yaml: text) as? [String: Any]
        else {
            assertionFailure("Failed to load localization table \(lang).yml from \(bundle.bundlePath)")
            return [:]
        }
        return raw.compactMapValues { $0 as? String }
    }
}
