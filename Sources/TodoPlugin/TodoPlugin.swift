import DeskBuddyCore
import Foundation
import TodoAPI

/// To-dos: keeping them, the commands, the count on the buddy and the Done-tab menu items.
/// Other features reach to-dos through TodoAPI — `TodoService` to read and act on them,
/// `TodoDeleted` to hear about deletions — never through this module. How to-dos look, in
/// tabs, a detail page and Settings, comes from `platform`.
@MainActor
public final class TodoPlugin: DeskBuddyPlugin {
    public let manifest = PluginManifest(id: "todo", name: "To-dos", version: "1.0.0")

    /// Set by `activate`
    private(set) var store: TodoStore?
    private let platform: any TodoPlatform

    package init(platform: any TodoPlatform) {
        self.platform = platform
    }

    public func activate(_ context: PluginContext) throws {
        let store = TodoStore(storage: context.storage, events: context.events, log: context.log)
        self.store = store
        let commands = context.commands
        let slots = context.slots
        let buddy = context.buddy
        let shared = TodoFeatureService(store: store, buddy: buddy, platform: platform)

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
            buddy.say(strings.f("bubble.added", title), closingAfter: 5)
        }
        commands.register("todo.complete") { arguments in
            let todo = try store.todo(for: arguments)
            if !todo.isDone { store.toggle(todo) }
            buddy.say(strings.f("bubble.done", todo.title), closingAfter: 5)
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

        platform.show(store, in: context)

        // Hides rather than deletes, so no destructive styling and no second
        // confirmation — the permanent version lives in Settings.
        slots.contribute(CoreSlots.listMenu, ListMenuItem(
            id: "todo.clearCompleted", order: 100,
            title: { strings.f("list.clear_from_list", store.visibleCompleted.count) },
            isEnabled: { !store.visibleCompleted.isEmpty },
            action: { store.clearCompletedFromList() }
        ))
        slots.contribute(CoreSlots.listMenu, ListMenuItem(
            id: "todo.restoreCompleted", order: 200,
            title: { strings.f("list.restore_history", store.hiddenCompletedCount) },
            isVisible: { store.hiddenCompletedCount > 0 },
            action: { store.restoreClearedHistory() }
        ))
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
    private let platform: any TodoPlatform

    init(store: TodoStore, buddy: any Buddy, platform: any TodoPlatform) {
        self.store = store
        self.buddy = buddy
        self.platform = platform
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
        platform.showDetail(of: id, in: store, buddy: buddy)
    }
}

/// What a platform adds to to-dos: how they look on the shared UI. macOS's is TodoMac.
@MainActor
package protocol TodoPlatform {
    /// Puts to-dos on screen, e.g. To Do and Done tabs and the history rows in Settings
    func show(_ store: TodoStore, in context: PluginContext)

    /// Brings up one to-do's detail, e.g. over the list panel
    func showDetail(of id: UUID, in store: TodoStore, buddy: any Buddy)
}
