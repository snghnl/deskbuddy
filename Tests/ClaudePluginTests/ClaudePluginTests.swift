import A2UIAPI
import A2UIMac
@testable import A2UIPlugin
@testable import ClaudePlugin
import DeskBuddyCore
import SwiftUI
import XCTest

/// Claude's question goes through the real A2UI plugin, as in the app; the test plays the user
@MainActor
final class ClaudePluginTests: XCTestCase {
    private var manager: PluginManager!
    private var windows: RecordingWindows!
    private var panels: A2UIPanels!

    override func setUp() async throws {
        windows = RecordingWindows()
        manager = makeManager()
        let a2ui = A2UIPlugin(platform: A2UIMac())
        manager.register(a2ui)
        manager.register(ClaudePlugin())
        manager.activateAll()
        panels = try XCTUnwrap(a2ui.panels)
    }

    func testTheUsersPickGoesBackToClaude() async throws {
        let reply = ask(["question": "Which database should I use?", "options": "PostgreSQL\nSQLite\nMySQL", "project": "deskbuddy"])
        let session = try await openSession()
        XCTAssertEqual(session.values, ["choice": "PostgreSQL", "text": ""], "the first option is picked to start with")
        XCTAssertEqual(session.document.texts, [strings.s("claude.needs_input"), "deskbuddy", "Which database should I use?"])

        session.values["choice"] = "SQLite"
        session.perform(.named("answer"))

        let answer = try await reply.value
        XCTAssertEqual(answer, ["answer": "SQLite"])
        XCTAssertEqual(windows.log, ["show a2ui.panel1", "hide a2ui.panel1"])
    }

    func testTypedTextWinsOverThePickedOption() async throws {
        let reply = ask(["question": "Which database?", "options": "PostgreSQL\nSQLite"])
        let session = try await openSession()

        session.values["text"] = "  DuckDB, actually "
        session.perform(.named("answer"))

        let answer = try await reply.value
        XCTAssertEqual(answer, ["answer": "DuckDB, actually"])
    }

    func testAQuestionWithoutOptionsTakesFreeText() async throws {
        let reply = ask(["question": "What should the release be called?"])
        let session = try await openSession()
        XCTAssertEqual(session.values, ["text": ""])

        session.values["text"] = "Teddy"
        session.perform(.named("answer"))

        let answer = try await reply.value
        XCTAssertEqual(answer, ["answer": "Teddy"])
    }

    func testClosingThePanelTellsClaudeThereIsNoAnswer() async throws {
        let reply = ask(["question": "Proceed?", "options": "Yes\nNo"])
        _ = try await openSession()

        try XCTUnwrap(windows.closers[SurfaceID("a2ui.panel1")])()

        do {
            _ = try await reply.value
            XCTFail("expected no answer")
        } catch {
            XCTAssertEqual(String(describing: error), "closed without an answer")
        }
    }

    func testARunOfQuestionsSharesOnePanelUntilClosed() async throws {
        let first = ask(["question": "Is it an animal?", "options": "Yes\nNo", "panel": "twenty"])
        let session = try await openSession()
        let (action, keepOpen) = try continueButton(in: session.document)
        XCTAssertTrue(keepOpen, "a named run keeps the panel up between questions")

        session.values["choice"] = "Yes"
        session.perform(action, keepOpen: keepOpen)
        let firstAnswer = try await first.value
        XCTAssertEqual(firstAnswer, ["answer": "Yes"])

        let second = ask(["question": "Can it fly?", "options": "Yes\nNo", "panel": "twenty"])
        for _ in 0..<200 where !session.isListening { await Task.yield() }
        XCTAssertEqual(session.document.texts.last, "Can it fly?")
        session.values["choice"] = "No"
        session.perform(action, keepOpen: keepOpen)
        let secondAnswer = try await second.value
        XCTAssertEqual(secondAnswer, ["answer": "No"])
        XCTAssertEqual(windows.log, ["show a2ui.named.claude.twenty", "update a2ui.named.claude.twenty"])

        try manager.commands.execute("claude.close", CommandArguments(["panel": "twenty"]))
        XCTAssertEqual(windows.log.last, "hide a2ui.named.claude.twenty")
    }

    func testAQuestionWithoutAPanelNameClosesWhenAnswered() async throws {
        let reply = ask(["question": "Proceed?", "options": "Yes\nNo"])
        let session = try await openSession()
        let (action, keepOpen) = try continueButton(in: session.document)
        XCTAssertFalse(keepOpen)

        session.perform(action, keepOpen: keepOpen)

        _ = try await reply.value
        XCTAssertEqual(windows.log.last, "hide a2ui.panel1")
    }

    func testNeedsAQuestionAndAWayToShowIt() async throws {
        do {
            _ = try await manager.commands.perform("claude.ask", CommandArguments())
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? CommandError, .missingArgument("question"))
        }

        let withoutPanels = makeManager()
        withoutPanels.register(ClaudePlugin())
        withoutPanels.activateAll()
        do {
            _ = try await withoutPanels.commands.perform("claude.ask", CommandArguments(["question": "Hi?"]))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(String(describing: error), "this DeskBuddy cannot show panels")
        }
    }

    // MARK: - Helpers

    private func makeManager() -> PluginManager {
        PluginManager(buddy: QuietBuddy(), presenter: windows, storageRoot: FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudePluginTests-unused-\(UUID().uuidString)"))
    }

    private func ask(_ arguments: [String: String]) -> Task<[String: String]?, Error> {
        Task { try await manager.commands.perform("claude.ask", CommandArguments(arguments)) as? [String: String] }
    }

    private func openSession() async throws -> A2UISession {
        for _ in 0..<100 {
            if let session = panels.open.values.first?.session { return session }
            await Task.yield()
        }
        throw NoPanel()
    }

    private struct NoPanel: Error {}

    /// The Continue button's action, and whether it keeps the panel up
    private func continueButton(in node: A2UINode) throws -> (A2UIAction, Bool) {
        switch node {
        case .button(_, _, let action, let keepOpen):
            return (action, keepOpen)
        case .row(let children, _), .column(let children), .card(let children):
            for child in children {
                if let found = try? continueButton(in: child) { return found }
            }
        default:
            break
        }
        throw NoPanel()
    }
}

private extension A2UINode {
    /// Every text in the panel, in order
    var texts: [String] {
        switch self {
        case .text(let text, _): [text]
        case .row(let children, _), .column(let children), .card(let children): children.flatMap(\.texts)
        default: []
        }
    }
}

@MainActor
private final class RecordingWindows: SurfacePresenter {
    private(set) var log: [String] = []
    private(set) var closers: [SurfaceID: @MainActor () -> Void] = [:]

    func show(_ surface: Surface, id: SurfaceID, ended: @escaping @MainActor (SurfaceEnd) -> Void) {
        log.append("show \(id)")
        closers[id] = { ended(.closedByUser) }
    }

    func update(_ surface: Surface, id: SurfaceID) {
        log.append("update \(id)")
    }

    func hide(_ id: SurfaceID) {
        log.append("hide \(id)")
    }
}

@MainActor
private final class QuietBuddy: Buddy {
    let isVisible = true
    func say(_ message: String) {}
    func say(_ message: String, closingAfter seconds: TimeInterval) {}
    func openList(on page: any PlatformView) {}
}
