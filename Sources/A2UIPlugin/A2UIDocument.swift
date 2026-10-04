import Foundation

/// A UI described in DeskBuddy's A2UI subset: a tree of components, each a JSON object with a
/// `type`. Not the full A2UI specification — only what panels need so far, nested rather than
/// flattened, with actions that run DeskBuddy commands.
///
///     {"type": "column", "children": [
///       {"type": "text", "text": "Start Pomodoro?", "style": "title"},
///       {"type": "select", "id": "minutes", "label": "Duration",
///        "options": [{"label": "25 minutes", "value": "25"}, {"label": "50 minutes", "value": "50"}]},
///       {"type": "row", "align": "trailing", "children": [
///         {"type": "button", "label": "Start", "style": "primary",
///          "action": {"command": "pomodoro.start", "arguments": {"minutes": {"input": "minutes"}}}}]}]}
///
/// Showing things:
/// - `text`: `text`, `style` ("title", "body" — the default — or "caption")
/// - `icon`: `name` (on macOS, an SF Symbol), `size` (8–64, default 16), `color` ("primary", the default,
///   "secondary", "accent", "red", "orange", "yellow", "green", "blue", "purple", "pink")
/// - `image`: `url` (https, or a file path), `height` (20–400, default 120)
/// - `progress`: `value` (0–1; left out, a spinner), `label`
/// - `divider`
///
/// Arranging them:
/// - `row`, `column`, `card`: `children`; a row may also have `align` ("leading", "center", "trailing")
/// - `list`: `children` in a scrolling area `height` tall (60–400, default 160)
/// - `tabs`: `tabs`, each `{"title", "children"}`; with an `id`, the chosen tab's title is an input
///
/// Asking the user — every input has an `id`, and its value is reported as a string:
/// - `textField`: `label`, `placeholder`, `value`, `multiline` (four lines tall)
/// - `select`: `label`, `options` (strings, or objects with `label` and `value`), `value` (the
///   first option when left out), `style` ("menu", the default, or "radio")
/// - `checkbox`: `label`, `value` (true or false, default false), `style` ("checkbox", the
///   default, or "switch"); reported as "true" or "false"
/// - `slider`: `label`, `min` (default 0), `max` (default 100), `step`, `value` (default `min`)
/// - `dateTime`: `label`, `mode` ("date", "time" or "dateTime", the default), `value` — reported
///   and given as 2026-10-02, 14:30 or 2026-10-02T14:30 in local time; now when left out
///
/// Acting — `button`: `label`, `action`, `style` ("primary" or "secondary", the default). An
/// action either runs a command — `{"command": "todo.add", "arguments": {"title": "Milk"}}`,
/// where an argument may be `{"input": "<id>"}` to pass what the user entered — or names
/// itself, `{"name": "continue"}`, and leaves it to whoever showed the panel. Either way the
/// panel then closes, unless the action says `"keepOpen": true`: then it stays up for whoever
/// showed it to change in place (a panel shown under a name). Only some commands may be run
/// from a document.
// `package` is for A2UIMac, which draws these

package indirect enum A2UINode: Equatable {
    case text(String, style: TextStyle)
    case icon(name: String, size: Double, color: IconColor)
    case image(source: ImageSource, height: Double)
    case progress(value: Double?, label: String?)
    case divider

    case row([A2UINode], align: RowAlignment)
    case column([A2UINode])
    case card([A2UINode])
    case list([A2UINode], height: Double)
    /// `key` tells this set of tabs apart from others in the panel; `id`, if any, is its input
    case tabs(key: String, id: String?, [A2UITab], selected: Int)

    case textField(id: String, label: String?, placeholder: String?, value: String, multiline: Bool)
    case select(id: String, label: String?, options: [A2UIOption], value: String, style: SelectStyle)
    case checkbox(id: String, label: String, value: Bool, style: CheckboxStyle)
    case slider(id: String, label: String?, range: ClosedRange<Double>, step: Double?, value: Double)
    case dateTime(id: String, label: String?, mode: DateTimeMode, value: String)

    /// `keepOpen`: the panel stays up after the action, to be changed in place
    case button(label: String, style: ButtonStyle, action: A2UIAction, keepOpen: Bool)

    package enum TextStyle: String { case title, body, caption }
    package enum ButtonStyle: String { case primary, secondary }
    package enum RowAlignment: String { case leading, center, trailing }
    package enum SelectStyle: String { case menu, radio }
    package enum CheckboxStyle: String { case checkbox, `switch` }
    package enum IconColor: String { case primary, secondary, accent, red, orange, yellow, green, blue, purple, pink }

    package enum ImageSource: Equatable {
        case remote(URL)
        case file(URL)
    }

    package enum DateTimeMode: String {
        case date, time, dateTime

        /// How values of this mode are written, in local time
        package var format: String {
            switch self {
            case .date: "yyyy-MM-dd"
            case .time: "HH:mm"
            case .dateTime: "yyyy-MM-dd'T'HH:mm"
            }
        }

        package func formatter() -> DateFormatter {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            return f
        }
    }

    /// The inputs in this tree with their starting values, by id
    var initialValues: [String: String] {
        switch self {
        case .textField(let id, _, _, let value, _), .select(let id, _, _, let value, _), .dateTime(let id, _, _, let value):
            return [id: value]
        case .checkbox(let id, _, let value, _):
            return [id: value ? "true" : "false"]
        case .slider(let id, _, _, _, let value):
            return [id: Self.format(value)]
        case .tabs(_, let id, let tabs, let selected):
            var values = tabs.reduce(into: [String: String]()) { all, tab in
                all.merge(tab.children.reduce(into: [:]) { $0.merge($1.initialValues) { first, _ in first } }) { first, _ in first }
            }
            if let id { values[id] = tabs[selected].title }
            return values
        case .row(let children, _), .column(let children), .card(let children), .list(let children, _):
            return children.reduce(into: [:]) { $0.merge($1.initialValues) { first, _ in first } }
        case .text, .icon, .image, .progress, .divider, .button:
            return [:]
        }
    }

    /// A number as reported: no decimals when it is whole, otherwise at most six, so steps of
    /// 0.1 read 0.3 and not 0.30000000000000004
    package static func format(_ number: Double) -> String {
        if number.rounded() == number && abs(number) < 1e15 { return String(Int64(number)) }
        var text = String(format: "%.6f", number)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

package struct A2UITab: Equatable {
    package let title: String
    package let children: [A2UINode]
}

package struct A2UIOption: Equatable {
    package let label: String
    package let value: String
}

package enum A2UIAction: Equatable {
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

package enum A2UIArgument: Equatable {
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
    /// Whether an icon of that name exists where the panel is drawn
    let iconExists: (String) -> Bool

    private static let maxDepth = 12

    func parse(_ data: Data) throws -> A2UINode {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw A2UIError(path: "document", reason: "not JSON")
        }
        var context = Context()
        let root = try node(json, at: "root", depth: 0, context: &context)
        for reference in context.references where !context.inputIDs.contains(reference.id) {
            throw A2UIError(path: reference.path, reason: "no input has the id \"\(reference.id)\"")
        }
        return root
    }

    /// What parsing has seen so far across the whole document
    private struct Context {
        var inputIDs: Set<String> = []
        var references: [(path: String, id: String)] = []
    }

    private func node(_ json: Any, at path: String, depth: Int, context: inout Context) throws -> A2UINode {
        guard depth <= Self.maxDepth else { throw A2UIError(path: path, reason: "nested too deep") }
        guard let object = json as? [String: Any] else { throw A2UIError(path: path, reason: "expected a component object") }
        let fields = Fields(object: object, path: path)
        let type = try fields.string("type")

        func children(of object: [String: Any], at path: String) throws -> [A2UINode] {
            guard let list = object["children"] as? [Any] else {
                throw A2UIError(path: path, reason: "\"children\" must be a list")
            }
            return try list.enumerated().map { index, child in
                try node(child, at: "\(path).children[\(index)]", depth: depth + 1, context: &context)
            }
        }

        func claim(_ id: String) throws -> String {
            guard context.inputIDs.insert(id).inserted else { throw A2UIError(path: path, reason: "the id \"\(id)\" is used twice") }
            return id
        }

        switch type {
        case "text":
            return .text(try fields.string("text"), style: try fields.choice("style", default: .body))

        case "icon":
            let name = try fields.string("name")
            guard iconExists(name) else {
                throw A2UIError(path: path, reason: "no icon is called \"\(name)\"")
            }
            return .icon(name: name, size: try fields.number("size", default: 16, in: 8...64),
                         color: try fields.choice("color", default: .primary))

        case "image":
            return .image(source: try imageSource(try fields.string("url"), at: path),
                          height: try fields.number("height", default: 120, in: 20...400))

        case "progress":
            return .progress(value: try fields.optionalNumber("value", in: 0...1), label: try fields.optionalString("label"))

        case "divider":
            return .divider

        case "row":
            return .row(try children(of: object, at: path), align: try fields.choice("align", default: .leading))
        case "column":
            return .column(try children(of: object, at: path))
        case "card":
            return .card(try children(of: object, at: path))
        case "list":
            return .list(try children(of: object, at: path), height: try fields.number("height", default: 160, in: 60...400))

        case "tabs":
            let id = try fields.optionalString("id").map(claim)
            guard let list = object["tabs"] as? [Any], !list.isEmpty else {
                throw A2UIError(path: path, reason: "\"tabs\" must be a list of at least one tab")
            }
            let tabs = try list.enumerated().map { index, item in
                let tabPath = "\(path).tabs[\(index)]"
                guard let tab = item as? [String: Any] else { throw A2UIError(path: tabPath, reason: "expected {\"title\", \"children\"}") }
                return A2UITab(title: try Fields(object: tab, path: tabPath).string("title"),
                               children: try children(of: tab, at: tabPath))
            }
            guard Set(tabs.map(\.title)).count == tabs.count else { throw A2UIError(path: path, reason: "two tabs have the same title") }
            var selected = 0
            if let value = try fields.optionalString("value") {
                guard let index = tabs.firstIndex(where: { $0.title == value }) else {
                    throw A2UIError(path: path, reason: "\"value\" is not one of the tab titles")
                }
                selected = index
            }
            return .tabs(key: path, id: id, tabs, selected: selected)

        case "textField":
            return .textField(id: try claim(try fields.string("id")), label: try fields.optionalString("label"),
                              placeholder: try fields.optionalString("placeholder"),
                              value: try fields.optionalString("value") ?? "",
                              multiline: try fields.bool("multiline", default: false))

        case "select":
            let id = try claim(try fields.string("id"))
            let options = try self.options(object["options"], at: "\(path).options")
            let value = try fields.optionalString("value") ?? options[0].value
            guard options.contains(where: { $0.value == value }) else {
                throw A2UIError(path: path, reason: "\"value\" is not one of the options")
            }
            return .select(id: id, label: try fields.optionalString("label"), options: options, value: value,
                           style: try fields.choice("style", default: .menu))

        case "checkbox":
            return .checkbox(id: try claim(try fields.string("id")), label: try fields.string("label"),
                             value: try fields.bool("value", default: false), style: try fields.choice("style", default: .checkbox))

        case "slider":
            let id = try claim(try fields.string("id"))
            let min = try fields.number("min", default: 0)
            let max = try fields.number("max", default: 100)
            guard min < max else { throw A2UIError(path: path, reason: "\"min\" must be less than \"max\"") }
            let step = try fields.optionalNumber("step", in: 0...(max - min))
            guard step != 0 else { throw A2UIError(path: path, reason: "\"step\" must be more than 0") }
            return .slider(id: id, label: try fields.optionalString("label"), range: min...max, step: step,
                           value: try fields.number("value", default: min, in: min...max))

        case "dateTime":
            let id = try claim(try fields.string("id"))
            let mode: A2UINode.DateTimeMode = try fields.choice("mode", default: .dateTime)
            let formatter = mode.formatter()
            let value: String
            if let given = try fields.optionalString("value") {
                guard formatter.date(from: given) != nil else {
                    throw A2UIError(path: path, reason: "\"value\" must look like \(mode.format.replacingOccurrences(of: "'", with: ""))")
                }
                value = given
            } else {
                value = formatter.string(from: Date())
            }
            return .dateTime(id: id, label: try fields.optionalString("label"), mode: mode, value: value)

        case "button":
            let action = try self.action(object["action"], at: "\(path).action", context: &context)
            let keepOpen = try Fields(object: object["action"] as? [String: Any] ?? [:], path: "\(path).action")
                .bool("keepOpen", default: false)
            return .button(label: try fields.string("label"), style: try fields.choice("style", default: .secondary),
                           action: action, keepOpen: keepOpen)

        default:
            throw A2UIError(path: path, reason: "unknown component type \"\(type)\"")
        }
    }

    /// https only on the network; a local file by path or file:// URL
    private func imageSource(_ url: String, at path: String) throws -> A2UINode.ImageSource {
        if url.hasPrefix("/") { return .file(URL(fileURLWithPath: url)) }
        guard let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased() else {
            throw A2UIError(path: path, reason: "\"url\" is not a URL or a file path")
        }
        switch scheme {
        case "https": return .remote(parsed)
        case "file": return .file(parsed)
        default: throw A2UIError(path: path, reason: "\"url\" must be https or a file")
        }
    }

    private func action(_ json: Any?, at path: String, context: inout Context) throws -> A2UIAction {
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
                resolved[key] = try argument(value, at: "\(path).arguments.\(key)", context: &context)
            }
            return .command(command, arguments: resolved)
        case (nil, let name?):
            return .named(name)
        default:
            throw A2UIError(path: path, reason: "an action has either a \"command\" or a \"name\"")
        }
    }

    private func argument(_ json: Any, at path: String, context: inout Context) throws -> A2UIArgument {
        switch json {
        case let string as String:
            return .literal(string)
        case let number as NSNumber:
            return .literal(isBool(number) ? (number.boolValue ? "true" : "false") : number.stringValue)
        case let object as [String: Any]:
            guard object.count == 1, let id = object["input"] as? String else {
                throw A2UIError(path: path, reason: "expected a string, a number, or {\"input\": \"<id>\"}")
            }
            context.references.append((path, id))
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

/// JSON true and false arrive as NSNumber too
private func isBool(_ number: NSNumber) -> Bool {
    CFGetTypeID(number) == CFBooleanGetTypeID()
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

    func bool(_ key: String, default fallback: Bool) throws -> Bool {
        guard let value = object[key] else { return fallback }
        guard let number = value as? NSNumber, isBool(number) else { throw A2UIError(path: path, reason: "\"\(key)\" must be true or false") }
        return number.boolValue
    }

    func optionalNumber(_ key: String, in range: ClosedRange<Double>? = nil) throws -> Double? {
        guard let value = object[key] else { return nil }
        guard let number = value as? NSNumber, !isBool(number), number.doubleValue.isFinite else {
            throw A2UIError(path: path, reason: "\"\(key)\" must be a number")
        }
        if let range, !range.contains(number.doubleValue) {
            throw A2UIError(path: path, reason: "\"\(key)\" must be between \(A2UINode.format(range.lowerBound)) and \(A2UINode.format(range.upperBound))")
        }
        return number.doubleValue
    }

    func number(_ key: String, default fallback: Double, in range: ClosedRange<Double>? = nil) throws -> Double {
        try optionalNumber(key, in: range) ?? fallback
    }

    func choice<Choice: RawRepresentable>(_ key: String, default fallback: Choice) throws -> Choice where Choice.RawValue == String {
        guard let raw = try optionalString(key) else { return fallback }
        guard let choice = Choice(rawValue: raw) else { throw A2UIError(path: path, reason: "\"\(key)\" cannot be \"\(raw)\"") }
        return choice
    }
}
