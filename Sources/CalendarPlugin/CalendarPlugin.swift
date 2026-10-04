import DeskBuddyCore
import Foundation

/// The calendar: the bubble before an event starts, and the calendar's preferences. Where
/// events come from and how the calendar looks — the Calendar tab with the completion history,
/// the Settings rows — come from `platform`. Reads to-dos only there, through TodoAPI.
@MainActor
public final class CalendarPlugin: DeskBuddyPlugin {
    public let manifest = PluginManifest(id: "calendar", name: "Calendar", version: "1.0.0")

    private var notifier: EventNotifier?
    private let platform: any CalendarPlatform

    package init(platform: any CalendarPlatform) {
        self.platform = platform
    }

    public func activate(_ context: PluginContext) throws {
        let source = platform.show(settings: context.settings, in: context)
        let notifier = EventNotifier(calendar: source, buddy: context.buddy, surfaces: context.surfaces,
                                     settings: context.settings)
        notifier.start()
        self.notifier = notifier
    }

    public func deactivate() {
        notifier?.stop()
    }
}

/// What a platform adds to the calendar: where events come from, and how it looks. macOS's is
/// CalendarMac.
@MainActor
package protocol CalendarPlatform {
    /// Puts the calendar on screen, e.g. a Calendar tab and Settings rows, and returns where its
    /// events come from
    func show(settings: PluginSettings, in context: PluginContext) -> any CalendarSource
}

/// The calendar's preferences, by name in its PluginSettings, with their defaults
package enum CalendarSettings {
    /// Show macOS calendar events on the Calendar tab
    package static let showEvents = "showEvents"
    package static let showEventsDefault = true
    /// Say when an event is about to start
    package static let eventAlerts = "eventAlerts"
    package static let eventAlertsDefault = true
    /// Minutes before the start to say it
    package static let eventAlertLead = "eventAlertLead"
    package static let eventAlertLeadDefault = 10
}
