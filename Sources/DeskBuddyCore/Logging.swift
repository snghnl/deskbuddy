import os

public extension Logger {
    /// A log under DeskBuddy's subsystem, so Console shows everything the app says in one place.
    /// Plugins get theirs as `context.log`, named after the plugin.
    static func deskBuddy(_ category: String) -> Logger {
        Logger(subsystem: "com.snghnl.deskbuddy", category: category)
    }
}
