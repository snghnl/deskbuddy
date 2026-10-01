import DeskBuddyCore
import SwiftUI
import TodoAPI

/// What the built-in features offer each other and put on the shared UI. A stand-in for the
/// feature plugins: each block moves into its plugin's `activate` once that feature moves out
/// of the app target.
@MainActor
enum FeatureContributions {
    static func register(plugins: PluginManager, store: TodoStore, calendar: CalendarService, appState: AppState) {
        let services = plugins.services
        let slots = plugins.slots
        let buddy = plugins.buddy

        // MARK: To-dos

        services.provide(TodoService.self, store)
        store.events = plugins.events

        // The same shape as todos.json, so `deskbuddy list --json` reads the same either way
        plugins.commands.respond(to: "todo.list") { _ in store.todos }
        plugins.commands.register("todo.add") { arguments in
            guard let title = arguments["title"], !title.isEmpty else { throw CommandError.missingArgument("title") }
            store.add(title)
            if let memo = arguments["memo"], !memo.isEmpty,
               let added = store.todos.first(where: { $0.title == title.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                store.updateMemo(added.id, memo)
            }
            buddy.say(L.f("bubble.added", title), closingAfter: 5)
        }
        plugins.commands.register("todo.complete") { arguments in
            guard let id = arguments["id"] else { throw CommandError.missingArgument("id") }
            guard let todo = store.todos.first(where: { $0.id.uuidString.caseInsensitiveCompare(id) == .orderedSame }) else {
                throw CommandError.invalidArgument(name: "id", value: id)
            }
            if !todo.isDone { store.toggle(todo) }
            buddy.say(L.f("bubble.done", todo.title), closingAfter: 5)
        }

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
    }
}
