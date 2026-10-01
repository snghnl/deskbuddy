import DeskBuddyCore
@testable import PomodoroPlugin
import SwiftUI
import TodoAPI
import XCTest

@MainActor
final class PomodoroPluginTests: XCTestCase {
    func testActivationAddsTheTimerTabAndTheToDoRowIcon() throws {
        let manager = PluginManager(buddy: QuietBuddy(), storageRoot: try scratchDirectory())
        manager.register(PomodoroPlugin())

        manager.activateAll()

        XCTAssertEqual(manager.slots.contributions(to: CoreSlots.listTabs).map(\.id), ["pomodoro.timers"])
        XCTAssertEqual(manager.slots.contributions(to: TodoSlots.rowAccessory).map(\.id), ["pomodoro.state"])
    }

    func testStartCommandRejectsMinutesThatAreNotAPositiveNumber() throws {
        let manager = PluginManager(buddy: QuietBuddy(), storageRoot: try scratchDirectory())
        manager.register(PomodoroPlugin())
        manager.activateAll()

        for minutes in ["0", "-5", "soon"] {
            XCTAssertThrowsError(try manager.commands.execute("pomodoro.start", CommandArguments(["minutes": minutes]))) {
                XCTAssertEqual($0 as? CommandError, .invalidArgument(name: "minutes", value: minutes))
            }
        }
    }

    func testActivatesWithoutTheToDoFeature() throws {
        let manager = PluginManager(buddy: QuietBuddy(), storageRoot: try scratchDirectory())
        manager.register(PomodoroPlugin())

        manager.activateAll()

        // Nothing provides TodoService here; the plugin still comes up, just without linking
        XCTAssertNil(manager.services.resolve(TodoService.self))
        XCTAssertFalse(manager.slots.contributions(to: CoreSlots.listTabs).isEmpty)
    }

    func testDeletingAToDoUnlinksItsTimersAndKeepsThemRunning() throws {
        let manager = PluginManager(buddy: QuietBuddy(), storageRoot: try scratchDirectory())
        let plugin = PomodoroPlugin()
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

    func testTimersSurviveARestart() throws {
        let storage = PluginStorage(directory: try scratchDirectory())
        let timers = TimerCenter(storage: storage)
        timers.start(minutes: 25, label: "Focus")
        timers.pause(try XCTUnwrap(timers.timers.first).id)

        let reopened = TimerCenter(storage: storage)

        XCTAssertEqual(reopened.timers, timers.timers)
    }

    /// An empty folder for the plugin's storage, removed afterwards
    private func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PomodoroPluginTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

@MainActor
private final class QuietBuddy: Buddy {
    let isVisible = true
    func say(_ message: String) {}
    func say(_ message: String, closingAfter seconds: TimeInterval) {}
    func replace(_ old: String, with new: String) {}
    func openList(on page: AnyView) {}
}

