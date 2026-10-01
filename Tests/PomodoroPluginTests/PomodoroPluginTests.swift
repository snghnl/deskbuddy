import DeskBuddyCore
import PomodoroPlugin
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

    func testActivatesWithoutTheToDoFeature() {
        let manager = PluginManager(buddy: QuietBuddy())
        manager.register(PomodoroPlugin())

        manager.activateAll()

        // Nothing provides TodoService here; the plugin still comes up, just without linking
        XCTAssertNil(manager.services.resolve(TodoService.self))
        XCTAssertFalse(manager.slots.contributions(to: CoreSlots.listTabs).isEmpty)
    }
}

@MainActor
private final class QuietBuddy: Buddy {
    func say(_ message: String) {}
}
