import DeskBuddyCore
import Foundation
import TodoAPI

/// Pomodoro-style countdown timers: starting them, keeping them across restarts, unlinking
/// deleted to-dos, and the bubble when one runs out. Works without the to-do feature, minus
/// linking. What the timers look like, and how a finished one sounds, come from `platform`.
@MainActor
public final class PomodoroPlugin: DeskBuddyPlugin {
    public let manifest = PluginManifest(id: "pomodoro", name: "Pomodoro", version: "1.0.0")

    private(set) var timers: TimerCenter?
    private let platform: any PomodoroPlatform

    package init(platform: any PomodoroPlatform) {
        self.platform = platform
    }

    public func activate(_ context: PluginContext) throws {
        let timers = TimerCenter(storage: context.storage, log: context.log)
        self.timers = timers
        let services = context.services
        let platform = platform

        // Finished timers announce themselves even if the character is hidden
        timers.onFire = { [buddy = context.buddy] timer in
            platform.playFinishedSound()
            // Announce with the linked to-do's title when there is one
            let title = timer.todoID.flatMap { services.resolve(TodoService.self)?.todo($0)?.title }
            buddy.say(strings.f("timer.done_bubble", title ?? timer.label))
        }

        // The Timer tab's buttons call TimerCenter.start directly; this is the same start for
        // callers outside the app, e.g. deskbuddy://pomodoro.start?minutes=25
        context.commands.register("pomodoro.start") { arguments in
            guard let minutes = arguments.int("minutes"), minutes > 0 else {
                throw CommandError.invalidArgument(name: "minutes", value: arguments["minutes"] ?? "")
            }
            timers.start(
                minutes: minutes,
                label: arguments["label"] ?? strings.f("timer.min_chip", minutes),
                todoID: arguments["todo"].flatMap(UUID.init(uuidString:))
            )
        }

        // A deleted to-do takes its links with it; the to-do feature does not know who linked to it
        context.events.subscribe(TodoDeleted.self) { event in
            timers.unlinkAll(from: event.id)
        }

        platform.show(timers, in: context)
    }

    public func deactivate() {
        // Every change is saved as it happens, so there is nothing to flush
    }
}

/// What a platform adds to the timers: how they look on the shared UI, and how a finished one
/// sounds. macOS's is PomodoroMac.
@MainActor
package protocol PomodoroPlatform {
    /// Puts the timers on screen, e.g. a Timer tab and an icon on the rows of linked to-dos
    func show(_ timers: TimerCenter, in context: PluginContext)

    func playFinishedSound()
}
