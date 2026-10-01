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

    private nonisolated static func send(_ line: String, to path: String) -> String? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: Array(path.utf8) + [0])
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return nil }
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
