import DeskBuddyCore
import SwiftUI
import TodoAPI
@testable import TodoPlugin
import XCTest

@MainActor
final class TodoPluginTests: XCTestCase {
    func testActivationProvidesTheServiceAndPutsItsUIOnTheSharedSlots() throws {
        let manager = try activatedManager().manager

        XCTAssertNotNil(manager.services.resolve(TodoService.self))
        XCTAssertEqual(manager.slots.contributions(to: CoreSlots.listTabs).map(\.id), ["todo.active", "todo.done"])
        XCTAssertEqual(manager.slots.contributions(to: CoreSlots.listMenu).map(\.id), ["todo.clearCompleted", "todo.restoreCompleted"])
        XCTAssertEqual(manager.slots.contributions(to: CoreSlots.settingsSections).map(\.id), ["todo.history"])
        XCTAssertEqual(manager.slots.contributions(to: CoreSlots.buddyBadge).map(\.id), ["todo.remaining"])
    }

    func testDeletingAToDoAnnouncesIt() throws {
        let (manager, store) = try activatedManager()
        store.add("keep")
        store.add("delete")
        let doomed = try XCTUnwrap(store.todos.first { $0.title == "delete" })
        var deleted: [UUID] = []
        manager.events.subscribe(TodoDeleted.self) { deleted.append($0.id) }

        store.remove(doomed)
        store.remove(doomed)   // already gone: nothing more to announce

        XCTAssertEqual(deleted, [doomed.id])
        XCTAssertEqual(store.todos.map(\.title), ["keep"])
    }

    func testWipingHistoryAnnouncesEachCompletedToDoButHidingItDoesNot() throws {
        let (manager, store) = try activatedManager()
        for title in ["open", "done 1", "done 2"] { store.add(title) }
        let done = store.todos.filter { $0.title.hasPrefix("done") }
        done.forEach(store.toggle)
        var deleted: [UUID] = []
        manager.events.subscribe(TodoDeleted.self) { deleted.append($0.id) }

        store.clearCompletedFromList()
        XCTAssertEqual(deleted, [])

        store.deleteCompleted()
        XCTAssertEqual(Set(deleted), Set(done.map(\.id)))
        XCTAssertEqual(store.todos.map(\.title), ["open"])
    }

    func testAddAndCompleteCommands() throws {
        let (manager, store) = try activatedManager()

        try manager.commands.execute("todo.add", CommandArguments(["title": "  Write tests ", "memo": "for PR 9"]))
        let added = try XCTUnwrap(store.todos.first)
        XCTAssertEqual(added.title, "Write tests")
        XCTAssertEqual(added.memo, "for PR 9")

        try manager.commands.execute("todo.complete", CommandArguments(["id": added.id.uuidString.lowercased()]))
        XCTAssertEqual(store.todos.first?.isDone, true)

        XCTAssertThrowsError(try manager.commands.execute("todo.add", CommandArguments())) {
            XCTAssertEqual($0 as? CommandError, .missingArgument("title"))
        }
        XCTAssertThrowsError(try manager.commands.execute("todo.complete", CommandArguments(["id": "nope"]))) {
            XCTAssertEqual($0 as? CommandError, .invalidArgument(name: "id", value: "nope"))
        }
    }

    func testToggleRemoveAndShowCommandsActOnTheNamedToDo() throws {
        let buddy = RecordingBuddy()
        let (manager, store) = try activatedManager(buddy: buddy)
        store.add("Water plants")
        let id = try XCTUnwrap(store.todos.first).id.uuidString
        var deleted: [String] = []
        manager.events.subscribe(TodoDeleted.self) { deleted.append($0.id.uuidString) }

        try manager.commands.execute("todo.toggle", CommandArguments(["id": id]))
        XCTAssertEqual(store.todos.first?.isDone, true)
        try manager.commands.execute("todo.toggle", CommandArguments(["id": id]))
        XCTAssertEqual(store.todos.first?.isDone, false)

        try manager.commands.execute("todo.show", CommandArguments(["id": id]))
        XCTAssertEqual(buddy.openedPages, 1)

        try manager.commands.execute("todo.remove", CommandArguments(["id": id]))
        XCTAssertTrue(store.todos.isEmpty)
        XCTAssertEqual(deleted, [id])
        XCTAssertTrue(buddy.said.isEmpty, "row actions stay quiet")

        for command in ["todo.toggle", "todo.remove", "todo.show"] {
            XCTAssertThrowsError(try manager.commands.execute(command, CommandArguments(["id": id]))) {
                XCTAssertEqual($0 as? CommandError, .invalidArgument(name: "id", value: id))
            }
        }
    }

    func testOtherFeaturesActOnToDosThroughTheService() throws {
        let buddy = RecordingBuddy()
        let (manager, store) = try activatedManager(buddy: buddy)
        let todos = try XCTUnwrap(manager.services.resolve(TodoService.self))
        store.add("Water plants")
        let id = try XCTUnwrap(store.todos.first).id
        var deleted: [UUID] = []
        manager.events.subscribe(TodoDeleted.self) { deleted.append($0.id) }

        todos.toggle(id)
        XCTAssertEqual(todos.todo(id)?.isDone, true)
        XCTAssertEqual(todos.completed(on: Date()).map(\.id), [id])
        todos.toggle(id)
        XCTAssertEqual(todos.active.map(\.id), [id])

        todos.show(id)
        XCTAssertEqual(buddy.openedPages, 1)

        todos.remove(id)
        XCTAssertNil(todos.todo(id))
        XCTAssertEqual(deleted, [id])

        // Gone now: the actions quietly do nothing
        todos.toggle(id)
        todos.remove(id)
        todos.show(id)
        XCTAssertEqual(deleted, [id])
        XCTAssertEqual(buddy.openedPages, 1)
        XCTAssertTrue(buddy.said.isEmpty)
    }

    func testCompletedOnADayListsThatDaysCompletionsLatestFirstHiddenOnesIncluded() throws {
        let (manager, store) = try activatedManager()
        let todos = try XCTUnwrap(manager.services.resolve(TodoService.self))
        let today = Date()
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: today))
        store.todos = [
            Todo(title: "open"),
            Todo(title: "earlier today", isDone: true, completedAt: today.addingTimeInterval(-60)),
            Todo(title: "yesterday", isDone: true, completedAt: yesterday),
            Todo(title: "later today", isDone: true, memo: "note", completedAt: today),
        ]
        store.clearCompletedFromList()

        let done = todos.completed(on: today)

        XCTAssertEqual(done.map(\.title), ["later today", "earlier today"])
        XCTAssertEqual(done.map(\.hasMemo), [true, false])
        XCTAssertTrue(done.allSatisfy { $0.isDone && $0.completedAt != nil })
        XCTAssertEqual(todos.completed(on: yesterday).map(\.title), ["yesterday"])
        XCTAssertNil(todos.active.first?.completedAt)
    }

    func testToDosAndHiddenHistorySurviveARestart() throws {
        let storage = PluginStorage(directory: try scratchDirectory())
        let store = TodoStore(storage: storage, events: EventBus(), log: Log(category: "test"))
        store.add("finished")
        store.toggle(store.todos[0])
        store.clearCompletedFromList()

        store.flush()
        let reopened = TodoStore(storage: storage, events: EventBus(), log: Log(category: "test"))

        XCTAssertEqual(reopened.todos, store.todos)
        XCTAssertEqual(reopened.historyClearedAt, store.historyClearedAt)
        XCTAssertEqual(reopened.hiddenCompletedCount, 1)
    }

    func testQuittingWritesTheSaveThatWasStillWaitingWhereTheCLIReadsIt() throws {
        let root = try scratchDirectory()
        let manager = PluginManager(buddy: RecordingBuddy(), presenter: NoWindows(), storageRoot: root)
        let plugin = TodoPlugin()
        manager.register(plugin)
        manager.activateAll()
        try XCTUnwrap(plugin.store).add("Ship 0.18")

        manager.deactivateAll()

        // bin/deskbuddy reads plugins/todo/todos.json when the app is not running
        let saved = try JSONDecoder().decode([Todo].self, from: Data(contentsOf: root.appendingPathComponent("todo/todos.json")))
        XCTAssertEqual(saved.map(\.title), ["Ship 0.18"])
    }

    func testUnreadableToDosAreSetAsideNotOverwritten() throws {
        let directory = try scratchDirectory()
        let garbage = Data("{ not the to-do list".utf8)
        try garbage.write(to: directory.appendingPathComponent("todos.json"))

        let store = TodoStore(storage: PluginStorage(directory: directory), events: EventBus(), log: Log(category: "test"))
        store.add("fresh start")
        store.flush()

        XCTAssertEqual(store.todos.map(\.title), ["fresh start"])
        let kept = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("todos.unreadable-") }
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(kept[0])), garbage)
    }

    // MARK: - Helpers

    private func activatedManager(buddy: (any Buddy)? = nil) throws -> (manager: PluginManager, store: TodoStore) {
        let manager = PluginManager(buddy: buddy ?? RecordingBuddy(), presenter: NoWindows(), storageRoot: try scratchDirectory())
        let plugin = TodoPlugin()
        manager.register(plugin)
        manager.activateAll()
        return (manager, try XCTUnwrap(plugin.store))
    }

    /// An empty folder for todos.json, removed afterwards
    private func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TodoPluginTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

}

@MainActor
private final class RecordingBuddy: Buddy {
    private(set) var said: [String] = []
    private(set) var openedPages = 0
    let isVisible = true
    func say(_ message: String) { said.append(message) }
    func say(_ message: String, closingAfter seconds: TimeInterval) { said.append(message) }
    func openList(on page: any PlatformView) { openedPages += 1 }
}

/// Surfaces go nowhere
@MainActor
private final class NoWindows: SurfacePresenter {
    func show(_ surface: Surface, id: SurfaceID, ended: @escaping @MainActor (SurfaceEnd) -> Void) {}
    func update(_ surface: Surface, id: SurfaceID) {}
    func hide(_ id: SurfaceID) {}
}
