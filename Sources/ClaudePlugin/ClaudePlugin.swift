import A2UIAPI
import DeskBuddyCore
import Foundation

/// Lets Claude Code put a question in front of the user and wait for the answer: the
/// claude.ask command, run by `deskbuddy ask`. The question becomes an A2UI panel next to
/// the buddy; this plugin knows how Claude's questions look, the A2UI plugin knows how to
/// show them, and neither knows the other's code.
@MainActor
public final class ClaudePlugin: DeskBuddyPlugin {
    public let manifest = PluginManifest(id: "claude", name: "Claude Code", version: "0.1.0")

    public init() {}

    public func activate(_ context: PluginContext) throws {
        let services = context.services
        context.commands.respondLater(to: "claude.ask") { arguments in
            guard let question = arguments["question"], !question.isEmpty else {
                throw CommandError.missingArgument("question")
            }
            guard let a2ui = services.resolve(A2UIService.self) else { throw ClaudeAskError.noPanels }
            let ask = ClaudeQuestion(
                question: question,
                options: (arguments["options"] ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty },
                project: arguments["project"].flatMap { $0.isEmpty ? nil : $0 }
            )
            let response = try await a2ui.ask(try ask.document())
            guard let answer = ask.answer(from: response) else { throw ClaudeAskError.closed }
            return ["answer": answer]
        }
    }

    public func deactivate() {}
}

enum ClaudeAskError: Error, CustomStringConvertible {
    case closed
    case noPanels

    var description: String {
        switch self {
        case .closed: "closed without an answer"
        case .noPanels: "this DeskBuddy cannot show panels"
        }
    }
}

/// A question from Claude, as the panel shows it and the answer it gives back
struct ClaudeQuestion {
    let question: String
    /// Choices to pick from; empty for a free answer
    let options: [String]
    /// The folder Claude Code is working in, to tell sessions apart
    let project: String?

    private static let choiceID = "choice"
    private static let textID = "text"
    private static let answerAction = "answer"

    /// The panel in DeskBuddy's A2UI subset
    func document() throws -> Data {
        var children: [[String: Any]] = [
            ["type": "text", "text": strings.s("claude.needs_input"), "style": "title"],
        ]
        if let project {
            children.append(["type": "text", "text": project, "style": "caption"])
        }
        children.append(["type": "text", "text": question])
        if options.isEmpty {
            children.append(["type": "textField", "id": Self.textID, "placeholder": strings.s("claude.answer_placeholder")])
        } else {
            children.append(["type": "select", "id": Self.choiceID, "options": options, "style": "radio"])
            children.append(["type": "textField", "id": Self.textID, "placeholder": strings.s("claude.own_answer")])
        }
        children.append(["type": "row", "align": "trailing", "children": [
            ["type": "button", "label": strings.s("claude.continue"), "style": "primary", "action": ["name": Self.answerAction]],
        ]])
        return try JSONSerialization.data(withJSONObject: ["type": "column", "children": children])
    }

    /// What the user answered — typed text wins over the picked option. nil if they closed the panel.
    func answer(from response: A2UIResponse) -> String? {
        guard response.action == Self.answerAction else { return nil }
        let typed = (response.values[Self.textID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty || options.isEmpty { return typed }
        return response.values[Self.choiceID] ?? ""
    }
}
