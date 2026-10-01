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
    public typealias Handler = @MainActor (CommandArguments) throws -> Void

    private var handlers: [String: Handler] = [:]

    public init() {}

    public func register(_ name: String, _ handler: @escaping Handler) {
        assert(handlers[name] == nil, "Command \(name) is registered twice")
        handlers[name] = handler
    }

    /// Runs the command. Throws `CommandError.unknownCommand` when nothing registered `name`,
    /// and passes on whatever the handler throws.
    public func execute(_ name: String, _ arguments: CommandArguments = CommandArguments()) throws {
        guard let handler = handlers[name] else { throw CommandError.unknownCommand(name) }
        try handler(arguments)
    }
}
