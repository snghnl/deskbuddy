import AppKit
import DeskBuddyCore
import TodoAPI

/// Pomodoro-style countdown timers: the Timer tab, the timer icon on to-do rows, and the
/// sound and bubble when one runs out. Works without the to-do feature, minus linking.
@MainActor
public final class PomodoroPlugin: DeskBuddyPlugin {
    public let manifest = PluginManifest(id: "pomodoro", name: "Pomodoro", version: "1.0.0")

    private var timers: TimerCenter?

    public init() {}

    public func activate(_ context: PluginContext) throws {
        let timers = TimerCenter()
        self.timers = timers
        let services = context.services

        // Finished timers announce themselves even if the character is hidden
        timers.onFire = { [buddy = context.buddy] timer in
            NSSound(named: "Glass")?.play()
            // Announce with the linked to-do's title when there is one
            let title = timer.todoID.flatMap { services.resolve(TodoService.self)?.todo($0)?.title }
            buddy.say(L.f("timer.done_bubble", title ?? timer.label))
        }

        context.slots.contribute(CoreSlots.listTabs, ListTab(
            id: "pomodoro.timers", order: 400,
            title: { L.s("timer.tab") },
            count: { timers.timers.count }
        ) {
            TimerTabView(timers: timers, todos: services.resolve(TodoService.self))
        })
        context.slots.contribute(TodoSlots.rowAccessory, TodoRowAccessory(id: "pomodoro.state", order: 100) { todoID in
            TimerStateIcon(timers: timers, todoID: todoID)
        })
    }

    public func deactivate() {
        // Every change is saved as it happens, so there is nothing to flush
    }
}
