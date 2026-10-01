import A2UIAPI
import DeskBuddyCore
import Foundation
import SwiftUI

/// Shows UI described in DeskBuddy's A2UI subset (see A2UIDocument) as panels next to the
/// buddy: for other plugins through `A2UIService`, from outside through the a2ui.show
/// command. Knows nothing about who asks.
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

    public init() {}

    public func activate(_ context: PluginContext) throws {
        let panels = A2UIPanels(commands: context.commands, surfaces: context.surfaces,
                                parser: A2UIParser(allowedCommands: Self.allowedCommands))
        self.panels = panels
        context.services.provide(A2UIService.self, panels)

        // deskbuddy ui <file>: answers once the user is done with the panel
        context.commands.respondLater(to: "a2ui.show") { arguments in
            guard let payload = arguments["payload"], !payload.isEmpty else { throw CommandError.missingArgument("payload") }
            return try await panels.ask(Data(payload.utf8))
        }
    }

    public func deactivate() {}
}

/// The panels on screen, each waiting for its user
@MainActor
final class A2UIPanels: A2UIService {
    private let commands: CommandRegistry
    private let surfaces: SurfaceManager
    private let parser: A2UIParser
    private var shown = 0
    /// Each open panel's session and how to finish it, by surface
    private(set) var open: [SurfaceID: (session: A2UISession, finish: (Result<A2UIResponse, Error>) -> Void)] = [:]

    init(commands: CommandRegistry, surfaces: SurfaceManager, parser: A2UIParser) {
        self.commands = commands
        self.surfaces = surfaces
        self.parser = parser
    }

    func ask(_ document: Data) async throws -> A2UIResponse {
        let node = try parser.parse(document)
        try Task.checkCancellation()
        shown += 1
        let id = SurfaceID("a2ui.panel\(shown)")
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                present(node, id: id) { continuation.resume(with: $0) }
            }
        } onCancel: {
            Task { @MainActor in self.finish(id, with: .failure(CancellationError()), dismiss: true) }
        }
    }

    private func present(_ node: A2UINode, id: SurfaceID, finish: @escaping (Result<A2UIResponse, Error>) -> Void) {
        let session = A2UISession(document: node, commands: commands) { [weak self] response in
            self?.finish(id, with: .success(response), dismiss: true)
        }
        session.resized = { [weak self, weak session] in
            guard let self, let session else { return }
            surfaces.update(id, to: .panel(AnyView(A2UIPanelView(session: session))))
        }
        open[id] = (session, finish)
        surfaces.present(.panel(AnyView(A2UIPanelView(session: session))), id: id) { [weak self, weak session] in
            // Closed by the user: no action, but whatever they had entered
            self?.finish(id, with: .success(A2UIResponse(action: nil, values: session?.values ?? [:])), dismiss: false)
        }
    }

    /// Ends the panel's wait once, however it ends
    private func finish(_ id: SurfaceID, with result: Result<A2UIResponse, Error>, dismiss: Bool) {
        guard let panel = open.removeValue(forKey: id) else { return }
        if dismiss { surfaces.dismiss(id) }
        panel.finish(result)
    }
}
