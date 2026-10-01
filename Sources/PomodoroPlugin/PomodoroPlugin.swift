import AppKit
import DeskBuddyCore
import TodoAPI

/// Pomodoro-style countdown timers: the Timer tab, the timer icon on to-do rows, and the
/// sound and bubble when one runs out. Works without the to-do feature, minus linking.
@MainActor
public final class PomodoroPlugin: DeskBuddyPlugin {
    public let manifest = PluginManifest(id: "pomodoro", name: "Pomodoro", version: "1.0.0")

    private(set) var timers: TimerCenter?
    private let defaults: UserDefaults

    public convenience init() {
        self.init(defaults: .standard)
    }

    /// Tests pass their own `defaults` so they never touch the user's timers
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func activate(_ context: PluginContext) throws {
        let timers = TimerCenter(defaults: defaults)
        self.timers = timers
        let services = context.services

        // Finished timers announce themselves even if the character is hidden
        timers.onFire = { [buddy = context.buddy] timer in
            NSSound(named: "Glass")?.play()
            // Announce with the linked to-do's title when there is one
            let title = timer.todoID.flatMap { services.resolve(TodoService.self)?.todo($0)?.title }
            buddy.say(L.f("timer.done_bubble", title ?? timer.label))
        }

        // The Timer tab's buttons call TimerCenter.start directly; this is the same start for
        // callers outside the app, e.g. deskbuddy://pomodoro.start?minutes=25
        context.commands.register("pomodoro.start") { arguments in
            guard let minutes = arguments.int("minutes"), minutes > 0 else {
                throw CommandError.invalidArgument(name: "minutes", value: arguments["minutes"] ?? "")
            }
            timers.start(
                minutes: minutes,
                label: arguments["label"] ?? L.f("timer.min_chip", minutes),
                todoID: arguments["todo"].flatMap(UUID.init(uuidString:))
            )
        }

        // A deleted to-do takes its links with it; the to-do feature does not know who linked to it
        context.events.subscribe(TodoDeleted.self) { event in
            timers.unlinkAll(from: event.id)
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
