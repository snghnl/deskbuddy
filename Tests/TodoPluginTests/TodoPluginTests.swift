import DeskBuddyCore
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

    func testToDosAndHiddenHistorySurviveARestart() async throws {
        let directory = try scratchDirectory()
        let defaults = MemoryDefaults()
        let store = TodoStore(directory: directory, defaults: defaults, events: EventBus())
        store.add("finished")
        store.toggle(store.todos[0])
        store.clearCompletedFromList()

        // Saves follow changes after a short delay
        try await Task.sleep(for: .milliseconds(600))
        let reopened = TodoStore(directory: directory, defaults: defaults, events: EventBus())

        XCTAssertEqual(reopened.todos, store.todos)
        XCTAssertEqual(reopened.historyClearedAt, store.historyClearedAt)
        XCTAssertEqual(reopened.hiddenCompletedCount, 1)
    }

    func testKeepsToDosWhereTheCLIReadsThem() {
        // bin/deskbuddy reads $HOME/Library/Application Support/DeskBuddy/todos.json when the app is not running
        XCTAssertTrue(TodoStore.defaultDirectory.path.hasSuffix("/Library/Application Support/DeskBuddy"))
    }

    // MARK: - Helpers

    private func activatedManager() throws -> (manager: PluginManager, store: TodoStore) {
        let manager = PluginManager(buddy: QuietBuddy())
        let plugin = TodoPlugin(directory: try scratchDirectory(), defaults: MemoryDefaults())
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
private final class QuietBuddy: Buddy {
    func say(_ message: String) {}
    func say(_ message: String, closingAfter seconds: TimeInterval) {}
}

/// Settings kept in memory only, so a test never writes a preferences file
private final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]

    init() {
        super.init(suiteName: nil)!
    }

    override func object(forKey key: String) -> Any? { values[key] }
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func set(_ value: Double, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values[key] = nil }
}
