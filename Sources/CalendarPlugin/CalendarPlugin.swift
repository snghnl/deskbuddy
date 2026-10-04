import DeskBuddyCore
import DeskBuddyMacUI
import Foundation
import SwiftUI
import TodoAPI

/// The Calendar tab (completion history plus macOS calendar events), the calendar settings,
/// and the bubble before an event starts. Reads to-dos through TodoAPI and works without the
/// to-do feature, minus the history.
@MainActor
public final class CalendarPlugin: DeskBuddyPlugin {
    public let manifest = PluginManifest(id: "calendar", name: "Calendar", version: "1.0.0")

    private var notifier: EventNotifier?

    public init() {}

    public func activate(_ context: PluginContext) throws {
        let settings = context.settings
        let calendar = CalendarService()
        let notifier = EventNotifier(calendar: calendar, buddy: context.buddy, surfaces: context.surfaces, settings: settings)
        notifier.start()
        self.notifier = notifier

        let services = context.services
        context.slots.contribute(CoreSlots.listTabs, ListTab(
            id: "calendar.month", order: 300,
            title: { strings.s("list.calendar") }
        ) {
            CalendarTabView(calendar: calendar, todos: services.resolve(TodoService.self), settings: settings)
        })
        context.slots.contribute(CoreSlots.settingsSections, SettingsSection(
            id: "calendar.integration", order: 300,
            title: { strings.s("settings.integrations") },
            footer: { strings.s("settings.integrations_footer") }
        ) {
            CalendarSettingsRows(calendar: calendar, settings: settings)
        })
    }

    public func deactivate() {
        notifier?.stop()
    }
}

/// The calendar's preferences, by name in its PluginSettings, with their defaults
enum CalendarSettings {
    /// Show macOS calendar events on the Calendar tab
    static let showEvents = "showEvents"
    static let showEventsDefault = true
    /// Say when an event is about to start
    static let eventAlerts = "eventAlerts"
    static let eventAlertsDefault = true
    /// Minutes before the start to say it
    static let eventAlertLead = "eventAlertLead"
    static let eventAlertLeadDefault = 10
}
