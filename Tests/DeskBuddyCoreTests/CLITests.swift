import XCTest
@testable import DeskBuddyCore

/// Runs the real bin/deskbuddy against a real CommandServer, so the CLI and the app cannot
/// drift apart on the wire. `open` is replaced on PATH: should the CLI fall back to the URL
/// scheme here, the test fails instead of launching the installed app.
@MainActor
final class CLITests: XCTestCase {
    private var socketPath = ""
    private var commands = CommandRegistry()
    private var server: CommandServer!
    private var sandbox: URL!

    override func setUpWithError() throws {
        socketPath = "/tmp/dbc-\(getpid())-\(UUID().uuidString.prefix(8)).sock"
        commands = CommandRegistry()
        server = CommandServer(path: socketPath, commands: commands)
        XCTAssertTrue(server.start())

        // Doubles as HOME, so a fallback to the data file would find nothing real either
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("deskbuddy-cli-\(UUID().uuidString)")
        let bin = sandbox.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let open = bin.appendingPathComponent("open")
        try "#!/bin/sh\necho \"$*\" >> \"$(dirname \"$0\")/opened\"\n".write(to: open, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: open.path)
        // Reports a running DeskBuddy only when a test has written its bundle path to bin/running,
        // so the real apps on this machine never leak in
        let lsappinfo = bin.appendingPathComponent("lsappinfo")
        try """
            #!/bin/sh
            running="$(dirname "$0")/running"
            [ -f "$running" ] || exit 0
            case "$1" in
              find) echo 'ASN:0x0-0x1-"DeskBuddy":' ;;
              info) printf '"LSBundlePath"="%s"\\n' "$(cat "$running")" ;;
            esac

            """.write(to: lsappinfo, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lsappinfo.path)
    }

    override func tearDownWithError() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.appendingPathComponent("bin/opened").path),
                       "the CLI fell back to opening a URL")
        server.stop()
        unlink(socketPath)
        try? FileManager.default.removeItem(at: sandbox)
    }

    func testNotifyReachesTheApp() {
        var said: (message: String?, autohide: String?)
        commands.register("buddy.say") { said = ($0["message"], $0["autohide"]) }

        let result = run("notify", "빌드 끝 ✅", "--autohide", "8")

        XCTAssertEqual(result.status, 0, result.err)
        XCTAssertEqual(said.message, "빌드 끝 ✅")
        XCTAssertEqual(said.autohide, "8")
    }

    func testAddSendsTitleAndMemo() {
        var added: (title: String?, memo: String?)
        commands.register("todo.add") { added = ($0["title"], $0["memo"]) }

        let result = run("add", "Review the PR", "--memo", "a=b, not urgent")

        XCTAssertEqual(result.status, 0, result.err)
        XCTAssertEqual(added.title, "Review the PR")
        XCTAssertEqual(added.memo, "a=b, not urgent")
    }

    func testListShowsWhatTheAppHas() {
        commands.respond(to: "todo.list") { _ in Self.todos }

        let plain = run("list")
        XCTAssertEqual(plain.status, 0, plain.err)
        XCTAssertEqual(plain.out, "[ ] a42620c8  Buy milk  📝\n")

        let all = run("list", "--all")
        XCTAssertEqual(all.out, "[ ] a42620c8  Buy milk  📝\n[x] 0b1c2d3e  Ship 0.16\n")

        let json = run("list", "--json")
        let decoded = try? JSONSerialization.jsonObject(with: Data(json.out.utf8)) as? [[String: Any]]
        XCTAssertEqual(decoded?.map { $0["title"] as? String }, ["Buy milk", "Ship 0.16"])
    }

    func testDoneResolvesAnIDPrefixAndCompletesIt() {
        commands.respond(to: "todo.list") { _ in Self.todos }
        var completed: String?
        commands.register("todo.complete") { completed = $0["id"] }

        let result = run("done", "a4262")

        XCTAssertEqual(result.status, 0, result.err)
        XCTAssertEqual(completed, "A42620C8-0000-4000-8000-000000000001")
        XCTAssertEqual(result.out, "Marked done: a4262\n")
    }

    func testToggle() {
        var toggled = false
        commands.register("list.toggle") { _ in toggled = true }

        XCTAssertEqual(run("toggle").status, 0)
        XCTAssertTrue(toggled)
    }

    func testTimerStartsAPomodoro() {
        var started: (minutes: String?, label: String?)
        commands.register("pomodoro.start") { started = ($0["minutes"], $0["label"]) }

        let result = run("timer", "25", "Focus")

        XCTAssertEqual(result.status, 0, result.err)
        XCTAssertEqual(started.minutes, "25")
        XCTAssertEqual(started.label, "Focus")
        XCTAssertEqual(result.out, "Started a 25-minute timer\n")
    }

    func testRunPrintsTheAnswerAndReportsErrors() {
        commands.respond(to: "greeter.hello") { ["greeting": "hello \($0["name"] ?? "")"] }

        let answered = run("run", "greeter.hello", "name=buddy")
        XCTAssertEqual(answered.status, 0, answered.err)
        XCTAssertEqual(answered.out, "{\"greeting\": \"hello buddy\"}\n")

        let unknown = run("run", "nope.nothing")
        XCTAssertEqual(unknown.status, 1)
        XCTAssertEqual(unknown.err, "deskbuddy: unknown command nope.nothing\n")

        let malformed = run("run", "greeter.hello", "name")
        XCTAssertEqual(malformed.status, 1)
        XCTAssertEqual(malformed.err, "deskbuddy: expected name=value, got name\n")
    }

    func testUIShowsTheFilesPanelAndPrintsWhatTheUserDid() throws {
        var shown: String?
        commands.respondLater(to: "a2ui.show") { arguments in
            shown = arguments["payload"]
            return Answer(action: "continue", values: ["db": "SQLite"])
        }
        let document = #"{"type": "button", "label": "Go", "action": {"name": "continue"}}"#
        let file = sandbox.appendingPathComponent("panel.json")
        try document.write(to: file, atomically: true, encoding: .utf8)

        let result = run("ui", file.path)

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(shown, document)
        XCTAssertEqual(try JSONDecoder().decode(Answer.self, from: Data(result.out.utf8)), Answer(action: "continue", values: ["db": "SQLite"]))
    }

    private struct Answer: Codable, Equatable {
        let action: String
        let values: [String: String]
    }

    func testAskPassesTheQuestionAndPrintsOnlyTheAnswer() throws {
        var asked: [String: String] = [:]
        commands.respondLater(to: "claude.ask") { arguments in
            asked = ["question": arguments["question"] ?? "", "options": arguments["options"] ?? "", "project": arguments["project"] ?? ""]
            return ["answer": "SQLite"]
        }

        let result = run("ask", "Which database?", "PostgreSQL", "SQLite")

        XCTAssertEqual(result.err, "")
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.out, "SQLite\n")
        XCTAssertEqual(asked, ["question": "Which database?", "options": "PostgreSQL\nSQLite",
                               "project": URL(fileURLWithPath: FileManager.default.currentDirectoryPath).lastPathComponent])
    }

    func testAskGivesUpAfterItsTimeoutAndTakesTheQuestionBack() throws {
        var cancelled = false
        commands.respondLater(to: "claude.ask") { _ in
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                cancelled = true
                throw error
            }
            return ["answer": "too late"]
        }

        let result = run("ask", "Proceed?", "--timeout", "1")

        XCTAssertEqual(result.status, 1)
        XCTAssertEqual(result.err, "deskbuddy: no answer within 1 seconds\n")
        let takenBack = expectation(description: "question taken back")
        Task { @MainActor in
            while !cancelled { try? await Task.sleep(for: .milliseconds(20)) }
            takenBack.fulfill()
        }
        wait(for: [takenBack], timeout: 5)
    }

    func testAskReportsAQuestionClosedWithoutAnAnswer() throws {
        commands.respondLater(to: "claude.ask") { _ in throw CommandError.invalidArgument(name: "answer", value: "none") }

        let result = run("ask", "Proceed?")

        XCTAssertEqual(result.status, 1)
        XCTAssertEqual(result.out, "")
        XCTAssertEqual(result.err, "deskbuddy: invalid answer: none\n")
    }

    // MARK: - Without the socket

    func testWithoutTheAppWritesFallBackToTheURLScheme() throws {
        server.stop()

        XCTAssertEqual(run("notify", "hi there", "--autohide", "3").status, 0)
        XCTAssertEqual(run("toggle").status, 0)

        XCTAssertEqual(try takeOpened(), [
            "-g deskbuddy://notify?message=hi%20there&autohide=3",
            "-g deskbuddy://toggle",
        ])
    }

    func testFallbackURLsGoToTheCopyThatIsRunning() throws {
        // A copy that is starting up and has not opened its socket yet
        server.stop()
        try "/Apps/Dev Build/DeskBuddy.app".write(to: sandbox.appendingPathComponent("bin/running"), atomically: true, encoding: .utf8)

        XCTAssertEqual(run("notify", "hi").status, 0)

        XCTAssertEqual(try takeOpened(), ["-g -a /Apps/Dev Build/DeskBuddy.app deskbuddy://notify?message=hi"])
    }

    func testTimerWaitsForTheRunningCopyInsteadOfLaunchingAnother() throws {
        server.stop()
        try "/Apps/Dev Build/DeskBuddy.app".write(to: sandbox.appendingPathComponent("bin/running"), atomically: true, encoding: .utf8)

        let result = run("timer", "25")

        // It waited, and it gave up, but it did not open anything
        XCTAssertEqual(result.status, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.appendingPathComponent("bin/opened").path))
    }

    func testWithoutTheAppListReadsTheToDoPluginsFile() throws {
        server.stop()
        try writeTodos(Self.todos, to: "Library/Application Support/DeskBuddy/plugins/todo")
        // Left behind by an older app; the plugin's file wins
        try writeTodos([], to: "Library/Application Support/DeskBuddy")

        XCTAssertEqual(run("list").out, "[ ] a42620c8  Buy milk  📝\n")
    }

    func testWithoutTheAppListReadsWhereOlderAppsKeptToDos() throws {
        server.stop()
        try writeTodos(Self.todos, to: "Library/Application Support/DeskBuddy")

        XCTAssertEqual(run("list").out, "[ ] a42620c8  Buy milk  📝\n")
    }

    private func writeTodos(_ todos: [TodoFixture], to folder: String) throws {
        let data = sandbox.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try JSONEncoder().encode(todos).write(to: data.appendingPathComponent("todos.json"))
    }

    func testWithoutAnAnsweringAppTimerGivesUpWithAReason() throws {
        server.stop()

        let result = run("timer", "25")

        XCTAssertEqual(result.status, 1)
        XCTAssertEqual(result.err, "deskbuddy: DeskBuddy is not answering — this needs DeskBuddy 0.16 or later\n")
        XCTAssertEqual(try takeOpened(), ["-g -b com.snghnl.deskbuddy"])
    }

    /// What the stand-in `open` was asked to open, clearing the record
    private func takeOpened() throws -> [String] {
        let record = sandbox.appendingPathComponent("bin/opened")
        let lines = try String(contentsOf: record, encoding: .utf8).split(separator: "\n").map(String.init)
        try FileManager.default.removeItem(at: record)
        return lines
    }

    // MARK: - Fixtures

    private struct TodoFixture: Encodable {
        let id: String
        let title: String
        let isDone: Bool
        let memo: String?
    }

    private static let todos = [
        TodoFixture(id: "A42620C8-0000-4000-8000-000000000001", title: "Buy milk", isDone: false, memo: "2%"),
        TodoFixture(id: "0B1C2D3E-0000-4000-8000-000000000002", title: "Ship 0.16", isDone: true, memo: nil),
    ]

    /// Runs bin/deskbuddy and waits for it. The app side needs the main actor to run each
    /// command, so this waits with an expectation rather than blocking.
    private func run(_ arguments: String...) -> (status: Int32, out: String, err: String) {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [repo.appendingPathComponent("bin/deskbuddy").path] + arguments
        process.environment = [
            "DESKBUDDY_SOCKET": socketPath,
            "HOME": sandbox.path,
            "PATH": "\(sandbox.appendingPathComponent("bin").path):/usr/bin:/bin",
            "LANG": "en_US.UTF-8",
        ]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let finished = expectation(description: "deskbuddy \(arguments.joined(separator: " "))")
        process.terminationHandler = { _ in finished.fulfill() }
        do {
            try process.run()
        } catch {
            XCTFail("could not run the CLI: \(error)")
            return (-1, "", "")
        }
        wait(for: [finished], timeout: 20)
        return (
            process.terminationStatus,
            String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }
}
