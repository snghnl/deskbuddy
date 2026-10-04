import Foundation

/// A plugin's preferences: the small choices a Settings row binds to, kept in UserDefaults
/// under the plugin's own prefix, `DeskBuddy.plugins.<plugin id>.`. Data belongs in
/// PluginStorage; these are values the user picks.
///
/// Read them with a default rather than registering one, so a choice the user never made
/// stays unset. A SwiftUI row binds with `AppStorage(wrappedValue:_:store:)`, passing
/// `key(_:)` and `defaults`.
public struct PluginSettings {
    public let defaults: UserDefaults
    private let prefix: String

    public init(pluginID: String, defaults: UserDefaults) {
        self.defaults = defaults
        prefix = Self.prefix(for: pluginID)
    }

    /// Where every key of that plugin starts
    public static func prefix(for pluginID: String) -> String {
        "DeskBuddy.plugins.\(pluginID)."
    }

    /// The UserDefaults key `name` is kept under: "DeskBuddy.plugins.calendar.eventAlerts"
    public func key(_ name: String) -> String {
        prefix + name
    }

    public func bool(_ name: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key(name)) as? Bool ?? fallback
    }

    public func integer(_ name: String, default fallback: Int) -> Int {
        defaults.object(forKey: key(name)) as? Int ?? fallback
    }

    public func string(_ name: String, default fallback: String) -> String {
        defaults.object(forKey: key(name)) as? String ?? fallback
    }

    /// nil removes the choice, so reads fall back to their default again
    public func set(_ value: Any?, for name: String) {
        if let value {
            defaults.set(value, forKey: key(name))
        } else {
            defaults.removeObject(forKey: key(name))
        }
    }
}
