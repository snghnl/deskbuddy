import XCTest
@testable import DeskBuddyCore

@MainActor
final class CommandServerTests: XCTestCase {
    private var path = ""
    private var commands = CommandRegistry()
    private var server: CommandServer!

    override func setUp() {
        // Socket paths are limited to ~100 bytes, so stay short and in /tmp
        path = "/tmp/dbt-\(getpid())-\(UUID().uuidString.prefix(8)).sock"
        commands = CommandRegistry()
        server = CommandServer(path: path, commands: commands)
    }

    override func tearDown() {
        server.stop()
        unlink(path)
    }

    func testAnswersWithTheCommandsResult() throws {
        commands.respond(to: "greeter.hello") { ["greeting": "hello \($0["name"] ?? "")"] }
        XCTAssertTrue(server.start())

        let reply = try exchange(#"{"command": "greeter.hello", "arguments": {"name": "buddy"}}"#)

        XCTAssertEqual(reply["ok"] as? Bool, true)
        XCTAssertEqual((reply["result"] as? [String: String])?["greeting"], "hello buddy")
    }

    func testCommandsWithoutAnAnswerJustSayOK() throws {
        var ran = false
        commands.register("list.toggle") { _ in ran = true }
        XCTAssertTrue(server.start())

        let reply = try exchange(#"{"command": "list.toggle"}"#)

        XCTAssertEqual(reply["ok"] as? Bool, true)
        XCTAssertNil(reply["result"])
        XCTAssertTrue(ran)
    }

    func testFailuresComeBackAsErrors() throws {
        commands.register("todo.add") { _ in throw CommandError.missingArgument("title") }
        XCTAssertTrue(server.start())

        let unknown = try exchange(#"{"command": "nope.nothing"}"#)
        XCTAssertEqual(unknown["ok"] as? Bool, false)
        XCTAssertEqual(unknown["error"] as? String, "unknown command nope.nothing")

        let failing = try exchange(#"{"command": "todo.add", "arguments": {}}"#)
        XCTAssertEqual(failing["error"] as? String, "missing argument title")

        let garbage = try exchange("not json")
        XCTAssertEqual(garbage["ok"] as? Bool, false)
    }

    func testWaitsForACommandThatAnswersLaterWhileServingOthers() throws {
        let pending = Pending()
        commands.respondLater(to: "ask.user") { _ in try await pending.answer() }
        commands.respond(to: "who") { _ in "still here" }
        XCTAssertTrue(server.start())

        let reply = ReplyBox()
        let answered = expectation(description: "answered")
        let path = self.path
        DispatchQueue.global().async {
            reply.text = Self.send(#"{"command": "ask.user"}"#, to: path)
            answered.fulfill()
        }
        wait(until: { pending.isWaiting })

        // Another connection gets through while the first waits on the user
        XCTAssertEqual(try exchange(#"{"command": "who"}"#)["result"] as? String, "still here")
        pending.resume(with: "SQLite")

        wait(for: [answered], timeout: 5)
        // Key order in the reply is not fixed, so compare what it says
        let answer = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(reply.text).utf8)) as? [String: Any])
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual(answer["result"] as? String, "SQLite")
    }

    func testAClientThatHangsUpCancelsTheCommandItWaitedFor() throws {
        let pending = Pending()
        commands.respondLater(to: "ask.user") { _ in try await pending.answer() }
        XCTAssertTrue(server.start())

        let fd = try XCTUnwrap(Self.connect(to: path))
        let request = Array(#"{"command": "ask.user"}"#.utf8 + [UInt8(ascii: "\n")])
        XCTAssertEqual(write(fd, request, request.count), request.count)
        wait(until: { pending.isWaiting })

        close(fd)

        wait(until: { pending.wasCancelled })
    }

    func testLeavesASocketAnotherServerIsListeningOnAlone() throws {
        commands.respond(to: "who") { _ in "first" }
        XCTAssertTrue(server.start())

        let second = CommandServer(path: path, commands: CommandRegistry())
        XCTAssertFalse(second.start())

        XCTAssertEqual(try exchange(#"{"command": "who"}"#)["result"] as? String, "first")
    }

    func testReplacesASocketLeftBehindByACrash() throws {
        // A bound socket whose owner went away without removing it
        let stale = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: Array(path.utf8) + [0])
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(stale, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        XCTAssertEqual(bound, 0)
        close(stale)

        commands.respond(to: "who") { _ in "new" }
        XCTAssertTrue(server.start())
        XCTAssertEqual(try exchange(#"{"command": "who"}"#)["result"] as? String, "new")
    }

    func testOnlyTheUserCanUseTheSocketAndStopRemovesIt() throws {
        XCTAssertTrue(server.start())
        let permissions = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)

        server.stop()

        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    // MARK: - Client

    /// Sends one line and returns the parsed reply. The client blocks, so it runs off the main
    /// actor while this waits — the server needs the main actor to run the command.
    private func exchange(_ line: String) throws -> [String: Any] {
        let reply = ReplyBox()
        let done = expectation(description: "reply")
        let path = self.path
        DispatchQueue.global().async {
            reply.text = Self.send(line, to: path)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        let text = try XCTUnwrap(reply.text, "no reply")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed) as? [String: Any])
    }

    /// Lets the main actor run until `condition` holds, failing after a few seconds
    private func wait(until condition: @escaping @MainActor () -> Bool) {
        let met = expectation(description: "condition")
        Task { @MainActor in
            while !condition() { try? await Task.sleep(for: .milliseconds(10)) }
            met.fulfill()
        }
        wait(for: [met], timeout: 5)
    }

    private nonisolated static func connect(to path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: Array(path.utf8) + [0])
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    private nonisolated static func send(_ line: String, to path: String) -> String? {
        guard let fd = connect(to: path) else { return nil }
        defer { close(fd) }
        let request = Array((line + "\n").utf8)
        guard write(fd, request, request.count) == request.count else { return nil }
        var received = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            received += buffer[0..<count]
        }
        return String(decoding: received, as: UTF8.self)
    }
}

private final class ReplyBox: @unchecked Sendable {
    var text: String?
}

/// An answer the test hands over when it chooses, standing in for the user
@MainActor
private final class Pending {
    private var continuation: CheckedContinuation<String, Error>?
    private(set) var isWaiting = false
    private(set) var wasCancelled = false

    func answer() async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                isWaiting = true
            }
        } onCancel: {
            Task { @MainActor in
                self.wasCancelled = true
                self.continuation?.resume(throwing: CancellationError())
                self.continuation = nil
            }
        }
    }

    func resume(with answer: String) {
        continuation?.resume(returning: answer)
        continuation = nil
    }
}
