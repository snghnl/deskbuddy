/// A unit of functionality that DeskBuddy starts at launch and stops at quit.
///
/// Built-in plugins are compiled into the app and registered with `PluginManager`
/// by the app target. The lifecycle is synchronous on purpose: AppKit's
/// `applicationWillTerminate` cannot wait for async work, so an async `deactivate()`
/// would never get to finish.
@MainActor
public protocol DeskBuddyPlugin {
    var manifest: PluginManifest { get }

    /// Called once at launch. Throwing leaves the plugin inactive; the other plugins still start.
    func activate(_ context: PluginContext) throws

    /// Called once at quit, and only if `activate` succeeded.
    func deactivate()
}

public struct PluginManifest: Equatable {
    /// Unique across plugins, and the namespace for the plugin's commands, events and storage (e.g. "pomodoro")
    public let id: String
    public let name: String
    public let version: String

    public init(id: String, name: String, version: String) {
        self.id = id
        self.name = name
        self.version = version
    }
}

/// What a plugin gets to work with. Built per plugin, so later additions such as
/// plugin-scoped storage can be bound to the plugin they belong to.
public struct PluginContext {
    public let services: ServiceRegistry
}
