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
        let defaults = try scratchDefaults()
        let manager = PluginManager(buddy: QuietBuddy())
        let plugin = PomodoroPlugin(defaults: defaults)
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

    /// Empty defaults for timers the test starts, wiped afterwards along with the plist
    /// cfprefsd leaves behind, so the user's own timers are never touched
    private func scratchDefaults() throws -> UserDefaults {
        let suite = "com.snghnl.deskbuddy.PomodoroPluginTests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            try? FileManager.default.removeItem(at: library.appendingPathComponent("Preferences/\(suite).plist"))
        }
        return defaults
    }
}

@MainActor
private final class QuietBuddy: Buddy {
    func say(_ message: String) {}
    func say(_ message: String, closingAfter seconds: TimeInterval) {}
}
