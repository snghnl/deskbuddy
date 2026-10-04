import Foundation

/// Serves the command registry on a Unix domain socket, so the CLI can run a command and hear
/// back — its answer, or why it failed — which a deskbuddy:// URL cannot do. It also reaches
/// whichever copy of the app is actually running, where a URL goes to the default copy.
///
/// One request per connection, a line of JSON each way:
///
///     → {"command": "todo.list", "arguments": {"name": "value"}}
///     ← {"ok": true, "result": …}     or     ← {"ok": false, "error": "…"}
///
/// Only the user can connect (the socket is 0600). Commands run on the main actor like every
/// other way in; reading and writing the socket happen off it. A command may take its time to
/// answer (`CommandRegistry.respondLater`); other connections are served meanwhile, and a
/// client that hangs up before the answer cancels it.
public final class CommandServer: @unchecked Sendable {   // `source` is only touched on the main actor
    private let path: String
    private let commands: CommandRegistry
    private let acceptQueue = DispatchQueue(label: "com.snghnl.deskbuddy.command-socket")
    private var source: DispatchSourceRead?
    private let log = Log(category: "commands")

    /// A request is one short line; anything longer is not one of ours
    private static let maxRequestSize = 64 * 1024

    public init(path: String, commands: CommandRegistry) {
        self.path = path
        self.commands = commands
    }

    /// Starts listening. Returns false, serving nothing, when the path is too long for a socket
    /// or another DeskBuddy is already listening there — a development build running next to
    /// the installed app, say. A socket left behind by a crash is replaced.
    @MainActor
    @discardableResult
    public func start() -> Bool {
        guard source == nil else { return true }
        guard var address = Self.address(for: path) else {
            log.error("Command socket path is too long: \(self.path)")
            return false
        }
        if Self.someoneIsListening(at: &address) {
            log.notice("Another DeskBuddy already serves \(self.path)")
            return false
        }
        unlink(path)

        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { return false }
        let bound = Self.withSockaddr(&address) { bind(listener, $0, $1) } == 0
        guard bound, chmod(path, 0o600) == 0, listen(listener, 8) == 0 else {
            log.error("Could not open the command socket: \(String(cString: strerror(errno)))")
            close(listener)
            if bound { unlink(path) }
            return false
        }
        _ = fcntl(listener, F_SETFL, fcntl(listener, F_GETFL) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: acceptQueue)
        source.setEventHandler { [weak self] in self?.acceptPending(on: listener) }
        source.setCancelHandler { close(listener) }
        source.resume()
        self.source = source
        return true
    }

    /// Stops listening and removes the socket file
    @MainActor
    public func stop() {
        guard let source else { return }
        source.cancel()
        self.source = nil
        unlink(path)
    }

    // MARK: - Connections

    private func acceptPending(on listener: Int32) {
        while true {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }   // nothing more waiting
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    close(client)
                    return
                }
                serve(client)
            }
        }
    }

    private func serve(_ client: Int32) {
        Self.configure(client)
        guard let line = Self.readLine(from: client) else {
            close(client)
            return
        }
        let request = try? JSONDecoder().decode(Request.self, from: line)

        // This thread waits for the answer, which may take as long as the user does
        let answered = DispatchSemaphore(value: 0)
        let reply = ReplyBox()
        let task = Task { @MainActor [commands] in
            reply.data = await Self.reply(to: request, commands: commands)
            answered.signal()
        }

        // The client sends nothing after its request, so the socket turning readable means it
        // hung up. A command still waiting on the user is then cancelled.
        let hangup = DispatchSource.makeReadSource(fileDescriptor: client, queue: .global(qos: .utility))
        let watching = DispatchGroup()
        watching.enter()
        hangup.setEventHandler {
            task.cancel()
            hangup.cancel()
        }
        hangup.setCancelHandler { watching.leave() }
        hangup.resume()

        answered.wait()
        hangup.cancel()
        watching.wait()   // no more events will touch the socket once it is closed
        Self.write(reply.data ?? Self.encode(Reply(error: "no answer")), to: client)
        close(client)
    }

    @MainActor
    private static func reply(to request: Request?, commands: CommandRegistry) async -> Data {
        guard let request else {
            return encode(Reply(error: #"expected {"command": "...", "arguments": {...}}"#))
        }
        do {
            let answer = try await commands.perform(request.command, CommandArguments(request.arguments ?? [:]))
            return encode(Reply(result: answer))
        } catch is CancellationError {
            return encode(Reply(error: "cancelled"))
        } catch {
            return encode(Reply(error: String(describing: error)))
        }
    }

    private final class ReplyBox: @unchecked Sendable {   // written once before the semaphore, read after
        var data: Data?
    }

    // MARK: - Wire format

    private struct Request: Decodable {
        let command: String
        let arguments: [String: String]?
    }

    private struct Reply: Encodable {
        var ok: Bool
        var result: AnyEncodable?
        var error: String?

        init(result: (any Encodable)?) {
            ok = true
            self.result = result.map(AnyEncodable.init)
        }

        init(error: String) {
            ok = false
            self.error = error
        }
    }

    private struct AnyEncodable: Encodable {
        let value: any Encodable

        func encode(to encoder: Encoder) throws {
            try value.encode(to: encoder)
        }
    }

    private static func encode(_ reply: Reply) -> Data {
        var data = (try? JSONEncoder().encode(reply)) ?? Data(#"{"ok":false,"error":"could not encode the answer"}"#.utf8)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    // MARK: - Sockets

    private static func configure(_ client: Int32) {
        // Accepted sockets inherit the listener's non-blocking flag; reads here should wait
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        // A client that hangs up before the answer must not take the app down with SIGPIPE
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Up to the first newline. nil on a timeout, an error, an empty request or one too large.
    private static func readLine(from client: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= maxRequestSize {
            let count = read(client, &buffer, buffer.count)
            if count < 0 { return nil }
            if count == 0 { return data.isEmpty ? nil : data }   // closed without a newline
            data.append(contentsOf: buffer[0..<count])
            if let newline = data.firstIndex(of: UInt8(ascii: "\n")) {
                return Data(data[..<newline])
            }
        }
        return nil
    }

    private static func write(_ data: Data, to client: Int32) {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(client, base + offset, raw.count - offset)
                if written <= 0 { return }
                offset += written
            }
        }
    }

    private static func address(for path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        // Leave room for the terminating zero
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }

    private static func withSockaddr<T>(_ address: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    private static func someoneIsListening(at address: inout sockaddr_un) -> Bool {
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { return false }
        defer { close(probe) }
        return withSockaddr(&address) { connect(probe, $0, $1) } == 0
    }
}
