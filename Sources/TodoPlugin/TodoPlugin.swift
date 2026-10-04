import DeskBuddyCore
import Foundation
import SwiftUI
import TodoAPI

/// To-dos: the To Do and Done tabs, the detail page, the completion history in Settings, and
/// the count on the buddy. Other features reach to-dos through TodoAPI — `TodoService` to read
/// them, `TodoDeleted` to hear about deletions — never through this module.
@MainActor
public final class TodoPlugin: DeskBuddyPlugin {
    public let manifest = PluginManifest(id: "todo", name: "To-dos", version: "1.0.0")

    /// Set by `activate`
    private(set) var store: TodoStore?

    public init() {}

    public func activate(_ context: PluginContext) throws {
        let store = TodoStore(storage: context.storage, events: context.events)
        self.store = store
        let commands = context.commands
        let slots = context.slots
        let buddy = context.buddy
        let shared = TodoFeatureService(store: store, buddy: buddy)

        context.services.provide(TodoService.self, shared)

        // The same shape as todos.json, so `deskbuddy list --json` reads the same either way
        commands.respond(to: "todo.list") { _ in store.todos }
        commands.register("todo.add") { arguments in
            guard let title = arguments["title"], !title.isEmpty else { throw CommandError.missingArgument("title") }
            store.add(title)
            if let memo = arguments["memo"], !memo.isEmpty,
               let added = store.todos.first(where: { $0.title == title.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                store.updateMemo(added.id, memo)
            }
            buddy.say(L.f("bubble.added", title), closingAfter: 5)
        }
        commands.register("todo.complete") { arguments in
            let todo = try store.todo(for: arguments)
            if !todo.isDone { store.toggle(todo) }
            buddy.say(L.f("bubble.done", todo.title), closingAfter: 5)
        }
        // TodoService's actions, for callers outside the app. Quiet, like a row's buttons: no bubble.
        commands.register("todo.toggle") { arguments in
            shared.toggle(try store.todo(for: arguments).id)
        }
        commands.register("todo.remove") { arguments in
            shared.remove(try store.todo(for: arguments).id)
        }
        commands.register("todo.show") { arguments in
            shared.show(try store.todo(for: arguments).id)
        }

        let draft = TodoDraft()
        slots.contribute(CoreSlots.listTabs, ListTab(
            id: "todo.active", order: 100,
            title: { L.s("list.to_do") },
            count: { store.activeTodos.count },
            toolbar: { AnyView(TodoInputBar(store: store, draft: draft)) }
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
    }

    public func deactivate() {
        // Saves follow changes after a short delay; one may still be waiting
        store?.flush()
    }
}

private extension TodoStore {
    /// The to-do named by the `id` argument, a full UUID in any case
    func todo(for arguments: CommandArguments) throws -> Todo {
        guard let id = arguments["id"] else { throw CommandError.missingArgument("id") }
        guard let todo = todos.first(where: { $0.id.uuidString.caseInsensitiveCompare(id) == .orderedSame }) else {
            throw CommandError.invalidArgument(name: "id", value: id)
        }
        return todo
    }
}

/// What other features get as TodoService: reads straight from the store, which is
/// observable, so their views follow changes; actions as a to-do row performs them
@MainActor
final class TodoFeatureService: TodoService {
    private let store: TodoStore
    private let buddy: any Buddy

    init(store: TodoStore, buddy: any Buddy) {
        self.store = store
        self.buddy = buddy
    }

    var active: [TodoSummary] { store.active }

    func todo(_ id: UUID) -> TodoSummary? { store.todo(id) }

    func completed(on day: Date) -> [TodoSummary] { store.completed(on: day) }

    func toggle(_ id: UUID) {
        guard let todo = store.todos.first(where: { $0.id == id }) else { return }
        store.toggle(todo)
    }

    func remove(_ id: UUID) {
        guard let todo = store.todos.first(where: { $0.id == id }) else { return }
        store.remove(todo)
    }

    func show(_ id: UUID) {
        guard store.todos.contains(where: { $0.id == id }) else { return }
        buddy.openList(on: AnyView(TodoDetailPage(id: id, store: store)))
    }
}
