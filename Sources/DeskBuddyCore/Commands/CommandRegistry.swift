import Foundation
import os

/// The arguments a command runs with. Every way in — a deskbuddy:// URL, the CLI — hands
/// over text, so values are strings, with typed readers on top.
public struct CommandArguments {
    private let values: [String: String]

    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    public subscript(_ name: String) -> String? {
        values[name]
    }

    public func int(_ name: String) -> Int? {
        values[name].flatMap { Int($0) }
    }

    public func double(_ name: String) -> Double? {
        values[name].flatMap { Double($0) }
    }
}

public enum CommandError: Error, Equatable, CustomStringConvertible {
    case unknownCommand(String)
    case missingArgument(String)
    case invalidArgument(name: String, value: String)

    public var description: String {
        switch self {
        case .unknownCommand(let name): "unknown command \(name)"
        case .missingArgument(let name): "missing argument \(name)"
        case .invalidArgument(let name, let value): "invalid \(name): \(value)"
        }
    }
}

/// Things that can be done from outside the app, by name — "todo.add", "pomodoro.start".
/// Whoever owns the action registers it; the URL scheme and the CLI run it by name, so a new
/// command needs no new routing. Names are namespaced by the owning plugin's id.
@MainActor
public final class CommandRegistry {
    private enum Handler {
        case now(@MainActor (CommandArguments) throws -> (any Encodable)?)
        case later(@MainActor (CommandArguments) async throws -> any Encodable)
    }

    private var handlers: [String: Handler] = [:]
    private let log = Logger.deskBuddy("commands")

    public init() {}

    /// For commands that do something and have nothing to say back
    public func register(_ name: String, _ perform: @escaping @MainActor (CommandArguments) throws -> Void) {
        add(name, .now { arguments in
            try perform(arguments)
            return nil
        })
    }

    /// For commands that answer with a value, such as a list. Only callers that can take an
    /// answer — the CLI over the command socket — see it; a URL drops it.
    public func respond(to name: String, _ answer: @escaping @MainActor (CommandArguments) throws -> any Encodable) {
        add(name, .now { try answer($0) })
    }

    /// For commands whose answer comes later, such as what the user picked in a panel. The CLI
    /// waits on the socket meanwhile; if it hangs up first, the task running `answer` is
    /// cancelled.
    public func respondLater(to name: String, _ answer: @escaping @MainActor (CommandArguments) async throws -> any Encodable) {
        add(name, .later(answer))
    }

    /// Runs the command and returns its answer, if it gives one. Throws
    /// `CommandError.unknownCommand` when nothing registered `name`, and passes on whatever
    /// the handler throws. A command that answers later is started and not waited for, as
    /// for a URL, which has no one to answer to; its failure is logged.
    @discardableResult
    public func execute(_ name: String, _ arguments: CommandArguments = CommandArguments()) throws -> (any Encodable)? {
        switch try handler(for: name) {
        case .now(let handle):
            return try handle(arguments)
        case .later(let handle):
            Task {
                do {
                    _ = try await handle(arguments)
                } catch {
                    log.error("\(name, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
            return nil
        }
    }

    /// Runs the command and waits for its answer, however long a command that answers later
    /// takes. Cancelling the calling task cancels such a command.
    public func perform(_ name: String, _ arguments: CommandArguments = CommandArguments()) async throws -> (any Encodable)? {
        switch try handler(for: name) {
        case .now(let handle):
            return try handle(arguments)
        case .later(let handle):
            return try await handle(arguments)
        }
    }

    private func handler(for name: String) throws -> Handler {
        guard let handler = handlers[name] else { throw CommandError.unknownCommand(name) }
        return handler
    }

    private func add(_ name: String, _ handler: Handler) {
        assert(handlers[name] == nil, "Command \(name) is registered twice")
        handlers[name] = handler
    }
}
