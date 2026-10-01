import Foundation

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
    private typealias Handler = @MainActor (CommandArguments) throws -> (any Encodable)?

    private var handlers: [String: Handler] = [:]

    public init() {}

    /// For commands that do something and have nothing to say back
    public func register(_ name: String, _ perform: @escaping @MainActor (CommandArguments) throws -> Void) {
        add(name) { arguments in
            try perform(arguments)
            return nil
        }
    }

    /// For commands that answer with a value, such as a list. Only callers that can take an
    /// answer — the CLI over the command socket — see it; a URL drops it.
    public func respond(to name: String, _ answer: @escaping @MainActor (CommandArguments) throws -> any Encodable) {
        add(name) { try answer($0) }
    }

    /// Runs the command and returns its answer, if it gives one. Throws
    /// `CommandError.unknownCommand` when nothing registered `name`, and passes on whatever
    /// the handler throws.
    @discardableResult
    public func execute(_ name: String, _ arguments: CommandArguments = CommandArguments()) throws -> (any Encodable)? {
        guard let handler = handlers[name] else { throw CommandError.unknownCommand(name) }
        return try handler(arguments)
    }

    private func add(_ name: String, _ handler: @escaping Handler) {
        assert(handlers[name] == nil, "Command \(name) is registered twice")
        handlers[name] = handler
    }
}
