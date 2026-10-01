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
        XCTAssertEqual(children[2], .textField(id: "why", label: nil, placeholder: "Why?", value: ""))
        XCTAssertEqual(children[4], .button(label: "Continue", style: .secondary, action: .named("continue")))
        XCTAssertEqual(children[5], .button(label: "Add", style: .secondary,
                                            action: .command("todo.add", arguments: ["title": .literal("x"), "count": .literal("2"), "urgent": .literal("true")])))
        XCTAssertEqual(node.initialValues, ["db": "SQLite", "why": ""])
    }

    func testRefusesWhatItCouldNotShowOrRunAndSaysWhere() {
        let cases: [(String, A2UIError)] = [
            ("[1, 2]", A2UIError(path: "root", reason: "expected a component object")),
            ("not json", A2UIError(path: "document", reason: "not JSON")),
            (#"{"type": "slider"}"#, A2UIError(path: "root", reason: "unknown component type \"slider\"")),
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
