@testable import A2UIPlugin
import XCTest

final class A2UIDocumentTests: XCTestCase {
    private let parser = A2UIParser(allowedCommands: ["pomodoro.start", "todo.add"])

    /// The panel from the plan: pick a duration, Start runs pomodoro.start with it
    static let startPomodoro = """
        {"type": "column", "children": [
          {"type": "text", "text": "Start Pomodoro?", "style": "title"},
          {"type": "select", "id": "minutes", "label": "Duration",
           "options": [{"label": "25 minutes", "value": "25"}, {"label": "50 minutes", "value": "50"}]},
          {"type": "row", "align": "trailing", "children": [
            {"type": "button", "label": "Start", "style": "primary",
             "action": {"command": "pomodoro.start", "arguments": {"minutes": {"input": "minutes"}, "label": "Focus"}}}]}]}
        """

    func testReadsThePlansStartPomodoroPanel() throws {
        let node = try parser.parse(Data(Self.startPomodoro.utf8))

        XCTAssertEqual(node, .column([
            .text("Start Pomodoro?", style: .title),
            .select(id: "minutes", label: "Duration",
                    options: [A2UIOption(label: "25 minutes", value: "25"), A2UIOption(label: "50 minutes", value: "50")],
                    value: "25", style: .menu),
            .row([.button(label: "Start", style: .primary,
                          action: .command("pomodoro.start", arguments: ["minutes": .input("minutes"), "label": .literal("Focus")]))],
                 align: .trailing),
        ]))
        XCTAssertEqual(node.initialValues, ["minutes": "25"])
    }

    func testFillsInDefaultsAndAcceptsShorthands() throws {
        let node = try parse("""
            {"type": "card", "children": [
              {"type": "text", "text": "Which database?"},
              {"type": "select", "id": "db", "options": ["PostgreSQL", "SQLite"], "value": "SQLite", "style": "radio"},
              {"type": "textField", "id": "why", "placeholder": "Why?"},
              {"type": "divider"},
              {"type": "button", "label": "Continue", "action": {"name": "continue"}},
              {"type": "button", "label": "Add", "action": {"command": "todo.add", "arguments": {"title": "x", "count": 2, "urgent": true}}}]}
            """)

        guard case .card(let children) = node else { return XCTFail("expected a card") }
        XCTAssertEqual(children[0], .text("Which database?", style: .body))
        XCTAssertEqual(children[1], .select(id: "db", label: nil,
                                            options: [A2UIOption(label: "PostgreSQL", value: "PostgreSQL"), A2UIOption(label: "SQLite", value: "SQLite")],
                                            value: "SQLite", style: .radio))
        XCTAssertEqual(children[2], .textField(id: "why", label: nil, placeholder: "Why?", value: "", multiline: false))
        XCTAssertEqual(children[4], .button(label: "Continue", style: .secondary, action: .named("continue")))
        XCTAssertEqual(children[5], .button(label: "Add", style: .secondary,
                                            action: .command("todo.add", arguments: ["title": .literal("x"), "count": .literal("2"), "urgent": .literal("true")])))
        XCTAssertEqual(node.initialValues, ["db": "SQLite", "why": ""])
    }

    func testReadsEveryOtherComponent() throws {
        let node = try parse("""
            {"type": "column", "children": [
              {"type": "icon", "name": "star.fill", "size": 20, "color": "yellow"},
              {"type": "image", "url": "https://example.com/cat.png", "height": 80},
              {"type": "image", "url": "/tmp/cat.png"},
              {"type": "progress", "value": 0.4, "label": "Uploading"},
              {"type": "progress"},
              {"type": "list", "height": 100, "children": [{"type": "text", "text": "one"}]},
              {"type": "tabs", "id": "tab", "value": "Later", "tabs": [
                {"title": "Now", "children": [{"type": "checkbox", "id": "notify", "label": "Notify me", "value": true}]},
                {"title": "Later", "children": [{"type": "dateTime", "id": "when", "mode": "time", "value": "14:30"}]}]},
              {"type": "textField", "id": "note", "multiline": true},
              {"type": "slider", "id": "volume", "label": "Volume", "min": 0, "max": 1, "step": 0.1, "value": 0.3},
              {"type": "checkbox", "id": "dark", "label": "Dark mode", "style": "switch"}]}
            """)

        guard case .column(let children) = node else { return XCTFail("expected a column") }
        XCTAssertEqual(children[0], .icon(name: "star.fill", size: 20, color: .yellow))
        XCTAssertEqual(children[1], .image(source: .remote(URL(string: "https://example.com/cat.png")!), height: 80))
        XCTAssertEqual(children[2], .image(source: .file(URL(fileURLWithPath: "/tmp/cat.png")), height: 120))
        XCTAssertEqual(children[3], .progress(value: 0.4, label: "Uploading"))
        XCTAssertEqual(children[4], .progress(value: nil, label: nil))
        XCTAssertEqual(children[5], .list([.text("one", style: .body)], height: 100))
        XCTAssertEqual(children[6], .tabs(key: "root.children[6]", id: "tab", [
            A2UITab(title: "Now", children: [.checkbox(id: "notify", label: "Notify me", value: true, style: .checkbox)]),
            A2UITab(title: "Later", children: [.dateTime(id: "when", label: nil, mode: .time, value: "14:30")]),
        ], selected: 1))
        XCTAssertEqual(children[7], .textField(id: "note", label: nil, placeholder: nil, value: "", multiline: true))
        XCTAssertEqual(children[8], .slider(id: "volume", label: "Volume", range: 0...1, step: 0.1, value: 0.3))
        XCTAssertEqual(children[9], .checkbox(id: "dark", label: "Dark mode", value: false, style: .switch))

        // Inputs inside tabs count even while their tab is not showing
        XCTAssertEqual(node.initialValues, ["tab": "Later", "notify": "true", "when": "14:30", "note": "",
                                            "volume": "0.3", "dark": "false"])
    }

    func testFillsInSensibleDefaultsForTheNewInputs() throws {
        let node = try parse("""
            {"type": "column", "children": [
              {"type": "slider", "id": "s"},
              {"type": "dateTime", "id": "d", "mode": "date"},
              {"type": "tabs", "tabs": [{"title": "Only", "children": []}]}]}
            """)

        let values = node.initialValues
        XCTAssertEqual(values["s"], "0")
        XCTAssertEqual(values["d"], A2UINode.DateTimeMode.date.formatter().string(from: Date()), "today")
        XCTAssertEqual(values.count, 2, "tabs without an id are not an input")
    }

    func testNumbersAreReportedWithoutFloatingPointNoise() {
        XCTAssertEqual(A2UINode.format(3), "3")
        XCTAssertEqual(A2UINode.format(0.1 + 0.2), "0.3")
        XCTAssertEqual(A2UINode.format(-2.5), "-2.5")
    }

    func testRefusesWhatItCouldNotShowOrRunAndSaysWhere() {
        let cases: [(String, A2UIError)] = [
            ("[1, 2]", A2UIError(path: "root", reason: "expected a component object")),
            ("not json", A2UIError(path: "document", reason: "not JSON")),
            (#"{"type": "chart"}"#, A2UIError(path: "root", reason: "unknown component type \"chart\"")),
            (#"{"type": "column", "children": [{"type": "text"}]}"#,
             A2UIError(path: "root.children[0]", reason: "\"text\" is missing")),
            (#"{"type": "button", "label": "Delete", "action": {"command": "todo.remove", "arguments": {"id": "x"}}}"#,
             A2UIError(path: "root.action", reason: "the command \"todo.remove\" may not be run from a panel")),
            (#"{"type": "button", "label": "Go", "action": {"command": "todo.add", "name": "go"}}"#,
             A2UIError(path: "root.action", reason: "an action has either a \"command\" or a \"name\"")),
            (#"{"type": "button", "label": "Go", "action": {"command": "todo.add", "arguments": {"title": {"input": "nope"}}}}"#,
             A2UIError(path: "root.action.arguments.title", reason: "no input has the id \"nope\"")),
            (#"{"type": "row", "children": [{"type": "textField", "id": "a"}, {"type": "textField", "id": "a"}]}"#,
             A2UIError(path: "root.children[1]", reason: "the id \"a\" is used twice")),
            (#"{"type": "select", "id": "s", "options": []}"#,
             A2UIError(path: "root.options", reason: "a select needs at least one option")),
            (#"{"type": "select", "id": "s", "options": ["a"], "value": "b"}"#,
             A2UIError(path: "root", reason: "\"value\" is not one of the options")),
            (#"{"type": "text", "text": "hi", "style": "shouting"}"#,
             A2UIError(path: "root", reason: "\"style\" cannot be \"shouting\"")),
            (#"{"type": "icon", "name": "no.such.symbol"}"#,
             A2UIError(path: "root", reason: "no SF Symbol is called \"no.such.symbol\"")),
            (#"{"type": "image", "url": "http://example.com/a.png"}"#,
             A2UIError(path: "root", reason: "\"url\" must be https or a file")),
            (#"{"type": "image", "url": "https://example.com/a.png", "height": 900}"#,
             A2UIError(path: "root", reason: "\"height\" must be between 20 and 400")),
            (#"{"type": "progress", "value": 1.5}"#,
             A2UIError(path: "root", reason: "\"value\" must be between 0 and 1")),
            (#"{"type": "checkbox", "id": "c", "label": "x", "value": "yes"}"#,
             A2UIError(path: "root", reason: "\"value\" must be true or false")),
            (#"{"type": "slider", "id": "s", "min": 5, "max": 5}"#,
             A2UIError(path: "root", reason: "\"min\" must be less than \"max\"")),
            (#"{"type": "slider", "id": "s", "max": 10, "value": 11}"#,
             A2UIError(path: "root", reason: "\"value\" must be between 0 and 10")),
            (#"{"type": "slider", "id": "s", "step": 0}"#,
             A2UIError(path: "root", reason: "\"step\" must be more than 0")),
            (#"{"type": "dateTime", "id": "d", "mode": "date", "value": "tomorrow"}"#,
             A2UIError(path: "root", reason: "\"value\" must look like yyyy-MM-dd")),
            (#"{"type": "tabs", "tabs": []}"#,
             A2UIError(path: "root", reason: "\"tabs\" must be a list of at least one tab")),
            (#"{"type": "tabs", "tabs": [{"title": "A", "children": []}, {"title": "A", "children": []}]}"#,
             A2UIError(path: "root", reason: "two tabs have the same title")),
            (#"{"type": "tabs", "tabs": [{"title": "A"}]}"#,
             A2UIError(path: "root.tabs[0]", reason: "\"children\" must be a list")),
            (#"{"type": "column", "children": [{"type": "textField", "id": "x"}, {"type": "tabs", "id": "x", "tabs": [{"title": "A", "children": []}]}]}"#,
             A2UIError(path: "root.children[1]", reason: "the id \"x\" is used twice")),
        ]
        for (json, expected) in cases {
            XCTAssertThrowsError(try parse(json), json) { XCTAssertEqual($0 as? A2UIError, expected, json) }
        }
    }

    func testRefusesDocumentsNestedTooDeep() {
        var json = #"{"type": "divider"}"#
        for _ in 0..<20 { json = #"{"type": "column", "children": [\#(json)]}"# }

        XCTAssertThrowsError(try parse(json)) { XCTAssertEqual(($0 as? A2UIError)?.reason, "nested too deep") }
    }

    private func parse(_ json: String) throws -> A2UINode {
        try parser.parse(Data(json.utf8))
    }
}
