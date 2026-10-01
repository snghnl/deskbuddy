import os

/// Owns the built-in plugins: registered by the app at startup, activated at launch, deactivated at quit.
@MainActor
public final class PluginManager {
    public let services = ServiceRegistry()

    private var registered: [any DeskBuddyPlugin] = []
    /// In activation order — deactivated in reverse
    private var active: [any DeskBuddyPlugin] = []
    private let log = Logger(subsystem: "com.snghnl.deskbuddy", category: "plugins")

    public init() {}

    public func register(_ plugin: any DeskBuddyPlugin) {
        precondition(!registered.contains { $0.manifest.id == plugin.manifest.id },
                     "Plugin id \(plugin.manifest.id) is registered twice")
        registered.append(plugin)
    }

    /// Activates the registered plugins in registration order. A plugin that throws is
    /// logged and left inactive; the rest still start.
    public func activateAll() {
        for plugin in registered where !active.contains(where: { $0.manifest.id == plugin.manifest.id }) {
            do {
                try plugin.activate(PluginContext(services: services))
                active.append(plugin)
            } catch {
                log.error("\(plugin.manifest.id, privacy: .public) failed to activate: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Deactivates in reverse activation order, so a plugin stops before the ones it was started after
    public func deactivateAll() {
        for plugin in active.reversed() {
            plugin.deactivate()
        }
        active.removeAll()
    }
}
