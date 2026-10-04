#if canImport(os)
import os
#endif

/// A log under DeskBuddy's name. On Apple platforms it goes to the unified log, so Console
/// shows everything the app says in one place. Plugins get theirs as `context.log`, its
/// category the plugin's id.
public struct Log: Sendable {
    public let category: String
    #if canImport(os)
    private let logger: Logger
    #endif

    public init(category: String) {
        self.category = category
        #if canImport(os)
        logger = Logger(subsystem: "com.snghnl.deskbuddy", category: category)
        #endif
    }

    /// Something failed
    public func error(_ message: String) {
        #if canImport(os)
        logger.error("\(message, privacy: .public)")
        #endif
    }

    /// Worth knowing, not a failure
    public func notice(_ message: String) {
        #if canImport(os)
        logger.notice("\(message, privacy: .public)")
        #endif
    }
}
