import CalendarPlugin
import DeskBuddyCore
import DeskBuddyMacUI
import TodoAPI

/// The calendar on macOS: events from EventKit, the Calendar tab (completion history plus
/// events) and the calendar rows in Settings
package struct CalendarMac: CalendarPlatform {
    package init() {}

    package func show(settings: PluginSettings, in context: PluginContext) -> any CalendarSource {
        let calendar = CalendarService()
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
        return calendar
    }
}
