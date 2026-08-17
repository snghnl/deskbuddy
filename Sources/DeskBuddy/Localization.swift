import Foundation

/// UI language preference. `.system` follows the user's macOS preferred language.
enum AppLanguage: String, CaseIterable {
    case system
    case korean
    case english
}

/// Minimal localization layer.
///
/// Every user-visible string in the app is written as `L.t("한국어", "English")` inline,
/// so the source stays readable and adding a language setting required no string catalogs.
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

    /// Pick the Korean or English variant of a string.
    static func t(_ korean: String, _ english: String) -> String {
        isKorean ? korean : english
    }

    /// Locale for custom date formatters that should follow the app language.
    static var locale: Locale {
        Locale(identifier: isKorean ? "ko_KR" : "en_US")
    }
}
