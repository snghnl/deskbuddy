import DeskBuddyCore
import SwiftUI
import TodoAPI

/// What the built-in features offer each other and put on the shared UI. A stand-in for the
/// feature plugins: each block moves into its plugin's `activate` once that feature moves out
/// of the app target.
@MainActor
enum FeatureContributions {
    static func register(
        services: ServiceRegistry,
        slots: SlotRegistry,
        store: TodoStore,
        timers: TimerCenter,
        calendar: CalendarService,
        appState: AppState
    ) {
        // MARK: To-dos

        services.provide(TodoService.self, store)

        let draft = TodoDraft()
        slots.contribute(CoreSlots.listTabs, ListTab(
            id: "todo.active", order: 100,
            title: { L.s("list.to_do") },
            count: { store.activeTodos.count },
            toolbar: { AnyView(TodoInputBar(store: store, appState: appState, draft: draft)) }
        ) {
            ActiveTodoList(store: store, slots: slots)
        })
        slots.contribute(CoreSlots.listTabs, ListTab(
            id: "todo.done", order: 200,
            title: { L.s("list.done") },
            count: { store.visibleCompleted.count }
        ) {
            CompletedTodoList(store: store)
        })
        // Hides rather than deletes, so no destructive styling and no second
        // confirmation — the permanent version lives in Settings.
        slots.contribute(CoreSlots.listMenu, ListMenuItem(
            id: "todo.clearCompleted", order: 100,
            title: { L.f("list.clear_from_list", store.visibleCompleted.count) },
            isEnabled: { !store.visibleCompleted.isEmpty },
            action: { store.clearCompletedFromList() }
        ))
        slots.contribute(CoreSlots.listMenu, ListMenuItem(
            id: "todo.restoreCompleted", order: 200,
            title: { L.f("list.restore_history", store.hiddenCompletedCount) },
            isVisible: { store.hiddenCompletedCount > 0 },
            action: { store.restoreClearedHistory() }
        ))
        slots.contribute(CoreSlots.settingsSections, SettingsSection(
            id: "todo.history", order: 500,
            title: { L.s("settings.history") },
            footer: { L.s("settings.history_footer") }
        ) {
            HistorySettingsRows(store: store)
        })
        slots.contribute(CoreSlots.buddyBadge, BuddyBadge(id: "todo.remaining", order: 100) {
            store.activeTodos.count
        })

        // MARK: Calendar

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

        // MARK: Timers

        slots.contribute(CoreSlots.listTabs, ListTab(
            id: "pomodoro.timers", order: 400,
            title: { L.s("timer.tab") },
            count: { timers.timers.count }
        ) {
            TimerTabView(timers: timers, todos: services.resolve(TodoService.self))
        })
        slots.contribute(TodoSlots.rowAccessory, TodoRowAccessory(id: "pomodoro.state", order: 100) { todoID in
            TimerStateIcon(timers: timers, todoID: todoID)
        })
    }
}
