import A2UIAPI
import DeskBuddyCore
import Foundation

/// Shows UI described in DeskBuddy's A2UI subset (see A2UIDocument) as panels next to the
/// buddy: for other plugins through `A2UIService`, from outside through the a2ui.show
/// command. Knows nothing about who asks. What a panel's components look like comes from
/// `platform`.
@MainActor
public final class A2UIPlugin: DeskBuddyPlugin {
    public let manifest = PluginManifest(id: "a2ui", name: "A2UI", version: "0.1.0")

    /// Commands a panel's buttons may run. Each is something the user could do in one click
    /// elsewhere anyway, and none destroys data — a document from outside cannot delete a to-do
    /// or open another panel.
    static let allowedCommands: Set<String> = [
        "buddy.say", "list.toggle", "todo.add", "todo.complete", "todo.show", "pomodoro.start",
    ]

    private(set) var panels: A2UIPanels?
    private let platform: any A2UIPlatform

    package init(platform: any A2UIPlatform) {
        self.platform = platform
    }

    public func activate(_ context: PluginContext) throws {
        let platform = platform
        let panels = A2UIPanels(commands: context.commands, surfaces: context.surfaces, platform: platform,
                                parser: A2UIParser(allowedCommands: Self.allowedCommands, iconExists: platform.iconExists))
        self.panels = panels
        context.services.provide(A2UIService.self, panels)

        // deskbuddy ui [--id name] [--no-wait] <file>: answers once the user acts on the panel.
        // With an id the panel can be changed in place by the next call; without waiting, the
        // call returns as soon as it shows.
        context.commands.respondLater(to: "a2ui.show") { arguments in
            guard let payload = arguments["payload"], !payload.isEmpty else { throw CommandError.missingArgument("payload") }
            let document = Data(payload.utf8)
            let name = arguments["id"].flatMap { $0.isEmpty ? nil : $0 }
            let wait = arguments["wait"] != "false"
            switch (name, wait) {
            case (nil, true):
                return try await panels.ask(document)
            case (let name?, true):
                return try await panels.ask(document, panel: name)
            case (let name?, false):
                try panels.show(document, panel: name)
                return ["panel": name]
            case (nil, false):
                // Nobody could ever change or close it
                throw CommandError.missingArgument("id")
            }
        }
        context.commands.register("a2ui.close") { arguments in
            guard let name = arguments["id"], !name.isEmpty else { throw CommandError.missingArgument("id") }
            panels.close(panel: name)
        }
    }

    public func deactivate() {}
}

/// The panels on screen. A panel without a name lives for one answer; a named one stays up
/// across calls while its actions say keepOpen.
@MainActor
final class A2UIPanels: A2UIService {
    private let commands: CommandRegistry
    private let surfaces: SurfaceManager
    private let platform: any A2UIPlatform
    private let parser: A2UIParser
    private var shown = 0
    /// The open panels, by surface
    private(set) var open: [SurfaceID: OpenPanel] = [:]

    final class OpenPanel {
        let session: A2UISession
        /// Whoever waits for the panel's next action
        var waiter: ((Result<A2UIResponse, Error>) -> Void)?

        init(session: A2UISession) {
            self.session = session
        }
    }

    init(commands: CommandRegistry, surfaces: SurfaceManager, platform: any A2UIPlatform, parser: A2UIParser) {
        self.commands = commands
        self.surfaces = surfaces
        self.platform = platform
        self.parser = parser
    }

    func ask(_ document: Data) async throws -> A2UIResponse {
        let node = try parser.parse(document)
        try Task.checkCancellation()
        shown += 1
        let id = SurfaceID("a2ui.panel\(shown)")
        present(node, id: id)
        return try await wait(for: id)
    }

    func ask(_ document: Data, panel name: String) async throws -> A2UIResponse {
        let id = try showOrUpdate(document, named: name)
        return try await wait(for: id)
    }

    func show(_ document: Data, panel name: String) throws {
        let id = try showOrUpdate(document, named: name)
        open[id]?.session.isListening = open[id]?.waiter != nil
    }

    func close(panel name: String) {
        let id = Self.surface(named: name)
        end(id, with: .success(A2UIResponse(action: nil, values: open[id]?.session.values ?? [:])), dismiss: true)
    }

    /// Named panels live under their own prefix, apart from the numbered one-answer panels
    private static func surface(named name: String) -> SurfaceID {
        SurfaceID("a2ui.named.\(name)")
    }

    private func showOrUpdate(_ document: Data, named name: String) throws -> SurfaceID {
        let node = try parser.parse(document)
        let id = Self.surface(named: name)
        if let panel = open[id] {
            panel.session.update(node)   // measures and redraws the same window
        } else {
            present(node, id: id)
        }
        return id
    }

    private func present(_ node: A2UINode, id: SurfaceID) {
        let session = A2UISession(document: node, commands: commands) { [weak self] response, keepOpen in
            self?.acted(id, response: response, keepOpen: keepOpen)
        }
        session.resized = { [weak self, weak session] in
            guard let self, let session else { return }
            surfaces.update(id, to: .panel(platform.panel(for: session)))
        }
        open[id] = OpenPanel(session: session)
        surfaces.present(.panel(platform.panel(for: session)), id: id) { [weak self, weak session] in
            // Closed by the user: no action, but whatever they had entered
            self?.end(id, with: .success(A2UIResponse(action: nil, values: session?.values ?? [:])), dismiss: false)
        }
    }

    /// Waits for the panel's next action. Cancelling — the CLI hanging up — closes the panel.
    private func wait(for id: SurfaceID) async throws -> A2UIResponse {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard let panel = open[id] else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                // Two callers on one panel: the newer one takes over
                panel.waiter?(.failure(CancellationError()))
                panel.waiter = { continuation.resume(with: $0) }
                panel.session.isListening = true
            }
        } onCancel: {
            Task { @MainActor in self.end(id, with: .failure(CancellationError()), dismiss: true) }
        }
    }

    private func acted(_ id: SurfaceID, response: A2UIResponse, keepOpen: Bool) {
        guard let panel = open[id] else { return }
        guard keepOpen else {
            end(id, with: .success(response), dismiss: true)
            return
        }
        // Stays up; its named actions wait for the next caller
        let waiter = panel.waiter
        panel.waiter = nil
        panel.session.isListening = false
        waiter?(.success(response))
    }

    /// Ends the panel and its wait once, however it ends
    private func end(_ id: SurfaceID, with result: Result<A2UIResponse, Error>, dismiss: Bool) {
        guard let panel = open.removeValue(forKey: id) else { return }
        if dismiss { surfaces.dismiss(id) }
        panel.waiter?(result)
    }
}

/// What a platform adds to A2UI panels: drawing their components, and knowing which icons
/// exist. macOS's is A2UIMac.
@MainActor
package protocol A2UIPlatform {
    /// The panel's content for `session`: its components as native controls
    func panel(for session: A2UISession) -> any PlatformView

    /// Whether an icon component may name `name`; checked before a panel is shown
    nonisolated func iconExists(_ name: String) -> Bool
}
