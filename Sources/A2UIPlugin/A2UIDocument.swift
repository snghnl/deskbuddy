import Foundation

/// A UI described in DeskBuddy's A2UI subset: a tree of components, each a JSON object with a
/// `type`. Not the full A2UI specification — only what the first panels need, nested rather
/// than flattened, with actions that run DeskBuddy commands.
///
///     {"type": "column", "children": [
///       {"type": "text", "text": "Start Pomodoro?", "style": "title"},
///       {"type": "select", "id": "minutes", "label": "Duration",
///        "options": [{"label": "25 minutes", "value": "25"}, {"label": "50 minutes", "value": "50"}]},
///       {"type": "row", "align": "trailing", "children": [
///         {"type": "button", "label": "Start", "style": "primary",
///          "action": {"command": "pomodoro.start", "arguments": {"minutes": {"input": "minutes"}}}}]}]}
///
/// Components:
/// - `text`: `text`, `style` ("title", "body" — the default — or "caption")
/// - `button`: `label`, `action`, `style` ("primary" or "secondary", the default)
/// - `row`, `column`, `card`: `children`; a row may also have `align` ("leading", "center", "trailing")
/// - `divider`
/// - `textField`: `id`, `label`, `placeholder`, `value`
/// - `select`: `id`, `label`, `options` (strings, or objects with `label` and `value`), `value`
///   (the first option when left out), `style` ("menu", the default, or "radio")
///
/// An action either runs a command — `{"command": "todo.add", "arguments": {"title": "Milk"}}`,
/// where an argument may be `{"input": "<id>"}` to pass what the user entered — or names
/// itself, `{"name": "continue"}`, and leaves it to whoever showed the panel. Either way the
/// panel then closes. Only some commands may be run from a document.
indirect enum A2UINode: Equatable {
    case text(String, style: TextStyle)
    case button(label: String, style: ButtonStyle, action: A2UIAction)
    case row([A2UINode], align: RowAlignment)
    case column([A2UINode])
    case card([A2UINode])
    case divider
    case textField(id: String, label: String?, placeholder: String?, value: String)
    case select(id: String, label: String?, options: [A2UIOption], value: String, style: SelectStyle)

    enum TextStyle: String { case title, body, caption }
    enum ButtonStyle: String { case primary, secondary }
    enum RowAlignment: String { case leading, center, trailing }
    enum SelectStyle: String { case menu, radio }

    /// The inputs in this tree with their starting values, by id
    var initialValues: [String: String] {
        switch self {
        case .textField(let id, _, _, let value), .select(let id, _, _, let value, _):
            [id: value]
        case .row(let children, _), .column(let children), .card(let children):
            children.reduce(into: [:]) { $0.merge($1.initialValues) { first, _ in first } }
        case .text, .button, .divider:
            [:]
        }
    }
}

struct A2UIOption: Equatable {
    let label: String
    let value: String
}

enum A2UIAction: Equatable {
    case command(String, arguments: [String: A2UIArgument])
    case named(String)

    /// What the response reports as the action taken
    var reportedName: String {
        switch self {
        case .command(let command, _): command
        case .named(let name): name
        }
    }
}

enum A2UIArgument: Equatable {
    case literal(String)
    /// What the user entered in the input with this id
    case input(String)
}

struct A2UIError: Error, Equatable, CustomStringConvertible {
    let path: String
    let reason: String

    var description: String { "invalid A2UI at \(path): \(reason)" }
}

/// Reads a document, refusing anything it would not know how to show or run
struct A2UIParser {
    /// Commands a button may run
    let allowedCommands: Set<String>

    private static let maxDepth = 12

    func parse(_ data: Data) throws -> A2UINode {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw A2UIError(path: "document", reason: "not JSON")
        }
        var inputIDs: Set<String> = []
        var references: [(path: String, id: String)] = []
        let root = try node(json, at: "root", depth: 0, inputIDs: &inputIDs, references: &references)
        for reference in references where !inputIDs.contains(reference.id) {
            throw A2UIError(path: reference.path, reason: "no input has the id \"\(reference.id)\"")
        }
        return root
    }

    private func node(_ json: Any, at path: String, depth: Int,
                      inputIDs: inout Set<String>, references: inout [(path: String, id: String)]) throws -> A2UINode {
        guard depth <= Self.maxDepth else { throw A2UIError(path: path, reason: "nested too deep") }
        guard let object = json as? [String: Any] else { throw A2UIError(path: path, reason: "expected a component object") }
        let fields = Fields(object: object, path: path)
        let type = try fields.string("type")

        func children() throws -> [A2UINode] {
            guard let list = object["children"] as? [Any] else {
                throw A2UIError(path: path, reason: "\"children\" must be a list")
            }
            return try list.enumerated().map { index, child in
                try node(child, at: "\(path).children[\(index)]", depth: depth + 1, inputIDs: &inputIDs, references: &references)
            }
        }

        func inputID() throws -> String {
            let id = try fields.string("id")
            guard inputIDs.insert(id).inserted else { throw A2UIError(path: path, reason: "the id \"\(id)\" is used twice") }
            return id
        }

        switch type {
        case "text":
            return .text(try fields.string("text"), style: try fields.choice("style", default: .body))
        case "button":
            let action = try self.action(object["action"], at: "\(path).action", references: &references)
            return .button(label: try fields.string("label"), style: try fields.choice("style", default: .secondary), action: action)
        case "row":
            return .row(try children(), align: try fields.choice("align", default: .leading))
        case "column":
            return .column(try children())
        case "card":
            return .card(try children())
        case "divider":
            return .divider
        case "textField":
            return .textField(id: try inputID(), label: try fields.optionalString("label"),
                              placeholder: try fields.optionalString("placeholder"),
                              value: try fields.optionalString("value") ?? "")
        case "select":
            let id = try inputID()
            let options = try self.options(object["options"], at: "\(path).options")
            let value = try fields.optionalString("value") ?? options[0].value
            guard options.contains(where: { $0.value == value }) else {
                throw A2UIError(path: path, reason: "\"value\" is not one of the options")
            }
            return .select(id: id, label: try fields.optionalString("label"), options: options, value: value,
                           style: try fields.choice("style", default: .menu))
        default:
            throw A2UIError(path: path, reason: "unknown component type \"\(type)\"")
        }
    }

    private func action(_ json: Any?, at path: String, references: inout [(path: String, id: String)]) throws -> A2UIAction {
        guard let object = json as? [String: Any] else { throw A2UIError(path: path, reason: "a button needs an action object") }
        let fields = Fields(object: object, path: path)
        let command = try fields.optionalString("command")
        let name = try fields.optionalString("name")
        switch (command, name) {
        case (let command?, nil):
            guard allowedCommands.contains(command) else {
                throw A2UIError(path: path, reason: "the command \"\(command)\" may not be run from a panel")
            }
            let arguments: [String: Any]
            switch object["arguments"] {
            case nil:
                arguments = [:]
            case let given as [String: Any]:
                arguments = given
            default:
                throw A2UIError(path: "\(path).arguments", reason: "expected an object")
            }
            var resolved: [String: A2UIArgument] = [:]
            for (key, value) in arguments {
                resolved[key] = try argument(value, at: "\(path).arguments.\(key)", references: &references)
            }
            return .command(command, arguments: resolved)
        case (nil, let name?):
            return .named(name)
        default:
            throw A2UIError(path: path, reason: "an action has either a \"command\" or a \"name\"")
        }
    }

    private func argument(_ json: Any, at path: String, references: inout [(path: String, id: String)]) throws -> A2UIArgument {
        switch json {
        case let string as String:
            return .literal(string)
        case let number as NSNumber:
            // JSON true/false arrive as NSNumber too
            return .literal(CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue)
        case let object as [String: Any]:
            guard object.count == 1, let id = object["input"] as? String else {
                throw A2UIError(path: path, reason: "expected a string, a number, or {\"input\": \"<id>\"}")
            }
            references.append((path, id))
            return .input(id)
        default:
            throw A2UIError(path: path, reason: "expected a string, a number, or {\"input\": \"<id>\"}")
        }
    }

    private func options(_ json: Any?, at path: String) throws -> [A2UIOption] {
        guard let list = json as? [Any], !list.isEmpty else { throw A2UIError(path: path, reason: "a select needs at least one option") }
        return try list.enumerated().map { index, item in
            switch item {
            case let string as String:
                return A2UIOption(label: string, value: string)
            case let object as [String: Any]:
                let fields = Fields(object: object, path: "\(path)[\(index)]")
                let label = try fields.string("label")
                return A2UIOption(label: label, value: try fields.optionalString("value") ?? label)
            default:
                throw A2UIError(path: "\(path)[\(index)]", reason: "expected a string or {\"label\", \"value\"}")
            }
        }
    }
}

/// Typed reads from a component's JSON object, with errors that say where
private struct Fields {
    let object: [String: Any]
    let path: String

    func string(_ key: String) throws -> String {
        guard let value = try optionalString(key) else { throw A2UIError(path: path, reason: "\"\(key)\" is missing") }
        return value
    }

    func optionalString(_ key: String) throws -> String? {
        guard let value = object[key] else { return nil }
        guard let string = value as? String else { throw A2UIError(path: path, reason: "\"\(key)\" must be a string") }
        return string
    }

    func choice<Choice: RawRepresentable>(_ key: String, default fallback: Choice) throws -> Choice where Choice.RawValue == String {
        guard let raw = try optionalString(key) else { return fallback }
        guard let choice = Choice(rawValue: raw) else { throw A2UIError(path: path, reason: "\"\(key)\" cannot be \"\(raw)\"") }
        return choice
    }
}
