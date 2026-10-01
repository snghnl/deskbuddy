import DeskBuddyCore
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
        UserDefaults.standard.register(defaults: [
            CalendarSettings.showEvents: true,
            CalendarSettings.eventAlerts: true,
            CalendarSettings.eventAlertLead: 10,
        ])

        let calendar = CalendarService()
        let notifier = EventNotifier(calendar: calendar, buddy: context.buddy, surfaces: context.surfaces)
        notifier.start()
        self.notifier = notifier

        let services = context.services
        let commands = context.commands
        context.slots.contribute(CoreSlots.listTabs, ListTab(
            id: "calendar.month", order: 300,
            title: { L.s("list.calendar") }
        ) {
            CalendarTabView(calendar: calendar, todos: services.resolve(TodoService.self), commands: commands)
        })
        context.slots.contribute(CoreSlots.settingsSections, SettingsSection(
            id: "calendar.integration", order: 300,
            title: { L.s("settings.integrations") },
            footer: { L.s("settings.integrations_footer") }
        ) {
            CalendarSettingsRows(calendar: calendar)
        })
    }

    public func deactivate() {
        notifier?.stop()
    }
}

/// UserDefaults keys for the calendar settings. The names predate the plugin and stay as they are.
enum CalendarSettings {
    static let showEvents = "DeskBuddy.showCalendar"
    static let eventAlerts = "DeskBuddy.eventAlerts"
    static let eventAlertLead = "DeskBuddy.eventAlertLead"
}
