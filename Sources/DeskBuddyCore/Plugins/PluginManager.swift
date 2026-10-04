import Foundation
import os

/// Owns the built-in plugins: registered by the app at startup, activated at launch, deactivated at quit.
@MainActor
public final class PluginManager {
    public let buddy: any Buddy
    public let commands = CommandRegistry()
    public let events = EventBus()
    public let services = ServiceRegistry()
    public let slots = SlotRegistry()
    public let surfaces: SurfaceManager

    private var registered: [any DeskBuddyPlugin] = []
    /// In activation order — deactivated in reverse
    private var active: [any DeskBuddyPlugin] = []
    private let log = Logger.deskBuddy("plugins")

    /// Each plugin's storage is the folder named after its id in here
    private let storageRoot: URL

    /// `presenter` draws the surfaces plugins put up. `storageRoot` is where plugins keep their
    /// data — the app's `Application Support/DeskBuddy/plugins`, a temporary folder in tests.
    public init(buddy: any Buddy, presenter: any SurfacePresenter, storageRoot: URL) {
        self.buddy = buddy
        surfaces = SurfaceManager(presenter: presenter)
        self.storageRoot = storageRoot
    }

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
                let storage = PluginStorage(directory: storageRoot.appendingPathComponent(plugin.manifest.id, isDirectory: true))
                try plugin.activate(PluginContext(buddy: buddy, commands: commands, events: events, services: services,
                                                  slots: slots, surfaces: surfaces, storage: storage,
                                                  log: .deskBuddy(plugin.manifest.id)))
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
