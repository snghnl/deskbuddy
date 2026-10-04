import AppKit
import DeskBuddyCore
import DeskBuddyMacUI
import PomodoroPlugin
import TodoAPI

/// The timers on macOS: the Timer tab, the timer icon on to-do rows, and the Glass sound
package struct PomodoroMac: PomodoroPlatform {
    package init() {}

    package func show(_ timers: TimerCenter, in context: PluginContext) {
        let services = context.services
        context.slots.contribute(CoreSlots.listTabs, ListTab(
            id: "pomodoro.timers", order: 400,
            title: { strings.s("timer.tab") },
            count: { timers.timers.count }
        ) {
            TimerTabView(timers: timers, todos: services.resolve(TodoService.self))
        })
        context.slots.contribute(TodoSlots.rowAccessory, TodoRowAccessory(id: "pomodoro.state", order: 100) { todoID in
            MacView(TimerStateIcon(timers: timers, todoID: todoID))
        })
    }

    package func playFinishedSound() {
        NSSound(named: "Glass")?.play()
    }
}
