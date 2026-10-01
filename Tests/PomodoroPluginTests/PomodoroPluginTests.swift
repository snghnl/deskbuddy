import DeskBuddyCore
@testable import PomodoroPlugin
import TodoAPI
import XCTest

@MainActor
final class PomodoroPluginTests: XCTestCase {
    func testActivationAddsTheTimerTabAndTheToDoRowIcon() {
        let manager = PluginManager(buddy: QuietBuddy())
        manager.register(PomodoroPlugin())

        manager.activateAll()

        XCTAssertEqual(manager.slots.contributions(to: CoreSlots.listTabs).map(\.id), ["pomodoro.timers"])
        XCTAssertEqual(manager.slots.contributions(to: TodoSlots.rowAccessory).map(\.id), ["pomodoro.state"])
    }

    func testStartCommandRejectsMinutesThatAreNotAPositiveNumber() {
        let manager = PluginManager(buddy: QuietBuddy())
        manager.register(PomodoroPlugin())
        manager.activateAll()

        for minutes in ["0", "-5", "soon"] {
            XCTAssertThrowsError(try manager.commands.execute("pomodoro.start", CommandArguments(["minutes": minutes]))) {
                XCTAssertEqual($0 as? CommandError, .invalidArgument(name: "minutes", value: minutes))
            }
        }
    }

    func testActivatesWithoutTheToDoFeature() {
        let manager = PluginManager(buddy: QuietBuddy())
        manager.register(PomodoroPlugin())

        manager.activateAll()

        // Nothing provides TodoService here; the plugin still comes up, just without linking
        XCTAssertNil(manager.services.resolve(TodoService.self))
        XCTAssertFalse(manager.slots.contributions(to: CoreSlots.listTabs).isEmpty)
    }

    func testDeletingAToDoUnlinksItsTimersAndKeepsThemRunning() throws {
        let manager = PluginManager(buddy: QuietBuddy())
        let plugin = PomodoroPlugin(defaults: MemoryDefaults())
        manager.register(plugin)
        manager.activateAll()
        let deleted = UUID(), kept = UUID()
        for todo in [deleted, deleted, kept] {
            try manager.commands.execute("pomodoro.start", CommandArguments(["minutes": "25", "todo": todo.uuidString]))
        }

        manager.events.emit(TodoDeleted(id: deleted))

        let timers = try XCTUnwrap(plugin.timers).timers
        XCTAssertEqual(timers.map(\.todoID), [nil, nil, kept])
        XCTAssertTrue(timers.allSatisfy(\.isRunning))
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
