import DeskBuddyCore
import SwiftUI
import TodoPlugin

/// What Calendar puts on the shared UI, until it becomes a plugin of its own (PR 10) and this
/// block moves into its `activate`. It still draws its day list with the to-do feature's rows,
/// so it gets the to-do store the plugin made.
@MainActor
enum FeatureContributions {
    static func register(plugins: PluginManager, todos store: TodoStore, calendar: CalendarService) {
        let slots = plugins.slots

        slots.contribute(CoreSlots.listTabs, ListTab(
            id: "calendar.month", order: 300,
            title: { L.s("list.calendar") }
        ) {
            CalendarTabView(store: store, calendar: calendar)
        })
        slots.contribute(CoreSlots.settingsSections, SettingsSection(
            id: "calendar.integration", order: 300,
            title: { L.s("settings.integrations") },
            footer: { L.s("settings.integrations_footer") }
        ) {
            CalendarSettingsRows(calendar: calendar)
        })
    }
}
