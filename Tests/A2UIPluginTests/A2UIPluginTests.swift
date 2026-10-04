import A2UIAPI
import A2UIMac
@testable import A2UIPlugin
import DeskBuddyCore
import SwiftUI
import XCTest

@MainActor
final class A2UIPluginTests: XCTestCase {
    private var manager: PluginManager!
    private var windows: RecordingWindows!
    private var panels: A2UIPanels!
    private var started: [[String: String]] = []

    override func setUp() async throws {
        windows = RecordingWindows()
        manager = PluginManager(buddy: QuietBuddy(), presenter: windows, storageRoot: FileManager.default.temporaryDirectory
            .appendingPathComponent("A2UIPluginTests-unused-\(UUID().uuidString)"))
        // Stands in for the timer plugin
        manager.commands.register("pomodoro.start") { [unowned self] in
            guard $0["minutes"] != "0" else { throw CommandError.invalidArgument(name: "minutes", value: "0") }
            started.append(["minutes": $0["minutes"] ?? "", "label": $0["label"] ?? ""])
        }
        let plugin = A2UIPlugin(platform: A2UIMac())
        manager.register(plugin)
        manager.activateAll()
        panels = try XCTUnwrap(plugin.panels)
    }

    func testOffersTheServiceAndTheShowCommand() async {
        XCTAssertTrue(manager.services.resolve(A2UIService.self) === panels)
        do {
            _ = try await manager.commands.perform("a2ui.show", CommandArguments())
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? CommandError, .missingArgument("payload"))
        }
    }

    func testStartRunsPomodoroStartWithThePickedDurationAndClosesThePanel() async throws {
        let answer = Task { try await panels.ask(Data(A2UIDocumentTests.startPomodoro.utf8)) }
        let session = try await openSession()
        session.values["minutes"] = "50"

        session.perform(startAction(in: session.document))

        let response = try await answer.value
        XCTAssertEqual(response, A2UIResponse(action: "pomodoro.start", values: ["minutes": "50"]))
        XCTAssertEqual(started, [["minutes": "50", "label": "Focus"]])
        XCTAssertEqual(windows.log.last, "hide a2ui.panel1")
        XCTAssertTrue(panels.open.isEmpty)
    }

    func testAFailingCommandKeepsThePanelOpenWithTheReason() async throws {
        let answer = Task { try await panels.ask(Data(A2UIDocumentTests.startPomodoro.utf8)) }
        let session = try await openSession()
        session.values["minutes"] = "0"

        session.perform(startAction(in: session.document))

        XCTAssertEqual(session.error, "invalid minutes: 0")
        XCTAssertEqual(windows.log.last, "update a2ui.panel1 panel", "resized to fit the message")
        XCTAssertFalse(panels.open.isEmpty)
        answer.cancel()
    }

    func testSwitchingTabsReportsTheTabAndMeasuresThePanelAgain() async throws {
        let answer = Task {
            try await panels.ask(Data(#"""
                {"type": "column", "children": [
                  {"type": "tabs", "id": "when", "tabs": [
                    {"title": "Now", "children": [{"type": "text", "text": "short"}]},
                    {"title": "Later", "children": [{"type": "dateTime", "id": "at", "mode": "time", "value": "09:00"}]}]},
                  {"type": "button", "label": "OK", "action": {"name": "ok"}}]}
                """#.utf8))
        }
        let session = try await openSession()

        session.select(tab: 1, of: "root.children[0]", id: "when", title: "Later")
        XCTAssertEqual(session.selectedTabs, ["root.children[0]": 1])
        XCTAssertEqual(windows.log.last, "update a2ui.panel1 panel")
        session.perform(.named("ok"))

        let response = try await answer.value
        XCTAssertEqual(response, A2UIResponse(action: "ok", values: ["when": "Later", "at": "09:00"]))
    }

    func testANamedActionAnswersWithTheInputs() async throws {
        let answer = Task {
            try await panels.ask(Data(#"""
                {"type": "column", "children": [
                  {"type": "select", "id": "db", "options": ["PostgreSQL", "SQLite"], "style": "radio"},
                  {"type": "button", "label": "Continue", "action": {"name": "continue"}}]}
                """#.utf8))
        }
        let session = try await openSession()
        session.values["db"] = "SQLite"

        session.perform(.named("continue"))

        let response = try await answer.value
        XCTAssertEqual(response, A2UIResponse(action: "continue", values: ["db": "SQLite"]))
    }

    func testClosingThePanelAnswersWithNoAction() async throws {
        let answer = Task { try await panels.ask(Data(A2UIDocumentTests.startPomodoro.utf8)) }
        _ = try await openSession()

        try XCTUnwrap(windows.closers[SurfaceID("a2ui.panel1")])()

        let response = try await answer.value
        XCTAssertEqual(response, A2UIResponse(action: nil, values: ["minutes": "25"]))
        XCTAssertEqual(started, [])
    }

    func testCancellingTheAskClosesThePanel() async throws {
        let answer = Task { try await panels.ask(Data(A2UIDocumentTests.startPomodoro.utf8)) }
        _ = try await openSession()

        answer.cancel()

        do {
            _ = try await answer.value
            XCTFail("expected a cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(windows.log.last, "hide a2ui.panel1")
    }

    func testAnInvalidDocumentShowsNothing() async {
        do {
            _ = try await panels.ask(Data(#"{"type": "button", "label": "x", "action": {"command": "todo.remove"}}"#.utf8))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual((error as? A2UIError)?.reason, "the command \"todo.remove\" may not be run from a panel")
        }
        XCTAssertEqual(windows.log, [])
    }

    func testTheShowCommandAnswersWithWhatTheUserDid() async throws {
        let answer = Task { try await manager.commands.perform("a2ui.show", CommandArguments(["payload": A2UIDocumentTests.startPomodoro])) }
        let session = try await openSession()

        session.perform(startAction(in: session.document))

        let response = try await answer.value as? A2UIResponse
        XCTAssertEqual(response, A2UIResponse(action: "pomodoro.start", values: ["minutes": "25"]))
    }

    // MARK: - Named panels

    func testANamedPanelStaysUpAfterAKeepOpenActionAndChangesInPlace() async throws {
        let first = Task { try await panels.ask(question("Is it an animal?", keepOpen: true), panel: "twenty") }
        let session = try await openSession()

        session.perform(.named("yes"), keepOpen: true)

        let firstAnswer = try await first.value
        XCTAssertEqual(firstAnswer.action, "yes")
        XCTAssertFalse(session.isListening, "nobody waits until the next question")
        XCTAssertFalse(session.canPerform(.named("yes")))
        XCTAssertEqual(windows.log, ["show a2ui.named.twenty"], "still up")

        let second = Task { try await panels.ask(question("Can it fly?", keepOpen: false), panel: "twenty") }
        try await until { session.isListening }
        XCTAssertEqual(session.document.texts, ["Can it fly?"])
        XCTAssertEqual(windows.log, ["show a2ui.named.twenty", "update a2ui.named.twenty panel"], "the same window, redrawn")

        session.perform(.named("no"))

        let secondAnswer = try await second.value
        XCTAssertEqual(secondAnswer.action, "no")
        XCTAssertEqual(windows.log.last, "hide a2ui.named.twenty", "an action without keepOpen ends it")
    }

    func testShowingWithoutWaitingKeepsNamedActionsOffUntilSomeoneAsks() async throws {
        try panels.show(question("Uploading… 40%", keepOpen: true), panel: "progress")
        let session = try XCTUnwrap(panels.open.values.first?.session)

        XCTAssertFalse(session.isListening)
        XCTAssertFalse(session.canPerform(.named("yes")))
        XCTAssertTrue(session.canPerform(.command("pomodoro.start", arguments: [:])), "commands act by themselves")

        try panels.show(question("Uploading… 80%", keepOpen: true), panel: "progress")
        XCTAssertEqual(session.document.texts, ["Uploading… 80%"])
        XCTAssertEqual(windows.log, ["show a2ui.named.progress", "update a2ui.named.progress panel"])

        let answer = Task { try await panels.ask(question("Done. Open it?", keepOpen: false), panel: "progress") }
        try await until { session.isListening }
        panels.close(panel: "progress")
        let closed = try await answer.value
        XCTAssertNil(closed.action, "closing ends the wait without an action")
        XCTAssertEqual(windows.log.last, "hide a2ui.named.progress")
    }

    func testTheShowCommandNamesPanelsAndCanSkipWaiting() async throws {
        let document = String(decoding: question("Hi", keepOpen: true), as: UTF8.self)

        let shown = try await manager.commands.perform("a2ui.show", CommandArguments(["payload": document, "id": "p", "wait": "false"]))
        XCTAssertEqual(shown as? [String: String], ["panel": "p"])
        XCTAssertEqual(windows.log, ["show a2ui.named.p"])

        try manager.commands.execute("a2ui.close", CommandArguments(["id": "p"]))
        XCTAssertEqual(windows.log.last, "hide a2ui.named.p")

        do {
            _ = try await manager.commands.perform("a2ui.show", CommandArguments(["payload": document, "wait": "false"]))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? CommandError, .missingArgument("id"), "a panel nobody waits on needs a name to be closed by")
        }
    }

    // MARK: - Helpers

    /// A yes/no panel whose buttons may keep it up
    private func question(_ text: String, keepOpen: Bool) -> Data {
        Data(#"""
            {"type": "column", "children": [
              {"type": "text", "text": "\#(text)"},
              {"type": "row", "children": [
                {"type": "button", "label": "No", "action": {"name": "no", "keepOpen": \#(keepOpen)}},
                {"type": "button", "label": "Yes", "action": {"name": "yes", "keepOpen": \#(keepOpen)}}]}]}
            """#.utf8)
    }

    /// Lets the panel's tasks run until `condition` holds
    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
        throw NoPanel()
    }

    /// The session of the panel that just opened, once the ask has put it up
    private func openSession() async throws -> A2UISession {
        for _ in 0..<100 {
            if let session = panels.open.values.first?.session { return session }
            await Task.yield()
        }
        throw NoPanel()
    }

    private struct NoPanel: Error {}

    private func startAction(in node: A2UINode) -> A2UIAction {
        guard case .column(let children) = node, case .row(let buttons, _) = children[2],
              case .button(_, _, let action, _) = buttons[0] else { fatalError("not the Start Pomodoro panel") }
        return action
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
        log.append("update \(id) panel")
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
