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
            // With a panel name, a run of questions shares one panel that changes in place
            let panel = arguments["panel"].flatMap { $0.isEmpty ? nil : $0 }
            let ask = ClaudeQuestion(
                question: question,
                options: (arguments["options"] ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty },
                project: arguments["project"].flatMap { $0.isEmpty ? nil : $0 },
                keepsPanel: panel != nil
            )
            let document = try ask.document()
            let response: A2UIResponse
            if let panel {
                response = try await a2ui.ask(document, panel: Self.a2uiPanel(panel))
            } else {
                response = try await a2ui.ask(document)
            }
            guard let answer = ask.answer(from: response) else { throw ClaudeAskError.closed }
            return ["answer": answer]
        }
        // Puts away the panel a run of questions shared, once the last answer is in
        context.commands.register("claude.close") { arguments in
            guard let panel = arguments["panel"], !panel.isEmpty else { throw CommandError.missingArgument("panel") }
            services.resolve(A2UIService.self)?.close(panel: Self.a2uiPanel(panel))
        }
    }

    /// Claude's panels among A2UI's named ones, apart from panels `deskbuddy ui` names
    private static func a2uiPanel(_ name: String) -> String {
        "claude.\(name)"
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
    /// Whether the panel stays up after the answer, for the next question in a run
    var keepsPanel = false

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
            ["type": "button", "label": strings.s("claude.continue"), "style": "primary",
             "action": ["name": Self.answerAction, "keepOpen": keepsPanel] as [String: Any]],
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
