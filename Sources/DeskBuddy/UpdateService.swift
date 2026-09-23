import AppKit
import CryptoKit
import Foundation

/// Dotted release version ("0.13.0"), compared piece by piece so 0.9.0 < 0.10.0.
struct AppVersion: Comparable, CustomStringConvertible {
    let parts: [Int]

    init?(_ raw: String) {
        let trimmed = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        // A suffix like "-beta1" is dropped: 0.14.0-beta1 compares as 0.14.0
        let parts = trimmed.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? -1 }
        guard !parts.isEmpty, !parts.contains(-1) else { return nil }
        self.parts = parts
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    var description: String { parts.map(String.init).joined(separator: ".") }
}

/// A published release newer than the running build.
struct Update {
    let version: AppVersion
    let tag: String
    let zip: URL
    /// shasum -a 256 output listing the release assets, when the release has one
    let checksums: URL?
    let notes: URL
}

/// Checks GitHub releases for a newer build and installs it in place.
///
/// The app ships ad-hoc signed, so Sparkle's signing story buys us nothing — this
/// downloads the release zip over HTTPS, checks it against the release's
/// `checksums.txt`, swaps the bundle from a helper script once we have quit, and
/// relaunches.
@MainActor
final class UpdateService: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(tag: String)
        case downloading
        case installing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var lastChecked: Date?

    /// Called when an automatic check finds a version the user has not been told about yet
    var onUpdateFound: ((Update) -> Void)?

    private(set) var pending: Update?
    private var autoCheckTask: Task<Void, Never>?

    private let latestReleaseAPI = URL(string: "https://api.github.com/repos/snghnl/deskbuddy/releases/latest")!

    static let currentVersion: AppVersion = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return AppVersion(raw ?? "") ?? AppVersion("0.0.0")!
    }()

    // MARK: - Checking

    /// Checks once on launch and then daily, as long as the setting is on.
    func startAutoChecks() {
        guard autoCheckTask == nil else { return }
        autoCheckTask = Task { [weak self] in
            // Let the app settle before touching the network
            try? await Task.sleep(for: .seconds(8))
            while !Task.isCancelled {
                if UserDefaults.standard.bool(forKey: SettingsKeys.autoUpdateCheck) {
                    await self?.check(userInitiated: false)
                }
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
            }
        }
    }

    func check(userInitiated: Bool) async {
        switch phase {
        case .checking, .downloading, .installing: return   // already busy
        default: break
        }
        phase = .checking
        do {
            let update = try await fetchLatest()
            lastChecked = Date()
            pending = update
            guard let update else {
                phase = .upToDate
                return
            }
            phase = .available(tag: update.tag)
            // Only the automatic check speaks up, and only once per version
            let notifiedKey = SettingsKeys.lastNotifiedVersion
            if !userInitiated, UserDefaults.standard.string(forKey: notifiedKey) != update.tag {
                UserDefaults.standard.set(update.tag, forKey: notifiedKey)
                onUpdateFound?(update)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// The latest release, or nil when it is not newer than what is running
    private func fetchLatest() async throws -> Update? {
        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else { throw UpdateError.server(status) }

        let release = try JSONDecoder().decode(ReleaseJSON.self, from: data)
        guard !release.draft, !release.prerelease,
              let version = AppVersion(release.tagName), version > Self.currentVersion,
              let zip = release.assets.first(where: { $0.name.hasSuffix(".zip") })
        else { return nil }

        return Update(
            version: version,
            tag: release.tagName,
            zip: zip.browserDownloadURL,
            checksums: release.assets.first { $0.name == "checksums.txt" }?.browserDownloadURL,
            notes: release.htmlURL
        )
    }

    private struct ReleaseJSON: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let htmlURL: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft, prerelease, assets
        }
    }

    // MARK: - Installing

    func install(_ update: Update) async {
        do {
            // Fail before quitting rather than after, if we cannot write where we live
            let destination = Bundle.main.bundleURL.resolvingSymlinksInPath()
            let parent = destination.deletingLastPathComponent()
            guard FileManager.default.isWritableFile(atPath: parent.path) else {
                throw UpdateError.notWritable(parent.path)
            }

            phase = .downloading
            let zip = try await download(update.zip)
            if let checksums = update.checksums {
                try await verify(zip, named: update.zip.lastPathComponent, against: checksums)
            }

            phase = .installing
            let staged = try await Task.detached { try Self.unpack(zip) }.value
            guard Bundle(url: staged)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw UpdateError.badPackage
            }

            // The next launch announces the update — and that the code signature changed with it
            UserDefaults.standard.set(Self.currentVersion.description, forKey: SettingsKeys.updatedFrom)
            try swapAndRelaunch(staged, over: destination)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func download(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else { throw UpdateError.server(status) }
        return data
    }

    /// Matches the download against the release's checksum list. Releases published
    /// before that asset existed simply skip this — HTTPS to GitHub is the floor.
    private func verify(_ data: Data, named name: String, against url: URL) async throws {
        let (listData, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let list = String(data: listData, encoding: .utf8)
        else { throw UpdateError.checksumUnavailable }

        // shasum -a 256 prints "<hex>  <filename>"
        let expected = list.split(separator: "\n").first { line in
            line.split(separator: " ").last.map(String.init) == name
        }?.split(separator: " ").first.map(String.init)
        guard let expected else { throw UpdateError.checksumUnavailable }

        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw UpdateError.checksumMismatch }
    }

    /// Extracts the zip into a scratch directory and returns the .app inside it
    private nonisolated static func unpack(_ zip: Data) throws -> URL {
        let work = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DeskBuddyUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let archive = work.appendingPathComponent("update.zip")
        try zip.write(to: archive)
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, work.path])

        let app = work.appendingPathComponent("DeskBuddy.app")
        guard FileManager.default.fileExists(atPath: app.path) else { throw UpdateError.badPackage }
        // ditto carries the quarantine flag over from the archive when there is one
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return app
    }

    /// Hands the swap to a helper shell: it waits for us to exit, moves the new
    /// bundle into place and launches it. Replacing a running bundle from inside
    /// itself is not safe, hence the detour.
    private func swapAndRelaunch(_ staged: URL, over destination: URL) throws {
        func quoted(_ url: URL) -> String {
            "'" + url.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }

        let script = """
        #!/bin/sh
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        previous=\(quoted(destination)).previous
        rm -rf "$previous"
        mv \(quoted(destination)) "$previous" || exit 1
        if ! mv \(quoted(staged)) \(quoted(destination)); then
            mv "$previous" \(quoted(destination))   # put the old build back
            exit 1
        fi
        rm -rf "$previous"
        open \(quoted(destination))
        rm -rf \(quoted(staged.deletingLastPathComponent()))
        """

        // The script outlives its scratch directory, so it lives beside it rather than inside
        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("deskbuddy-update-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [scriptURL.path]
        try helper.run()

        NSApp.terminate(nil)
    }

    @discardableResult
    private nonisolated static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: output, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw UpdateError.tool((tool as NSString).lastPathComponent, text)
        }
        return text
    }
}

enum UpdateError: LocalizedError {
    case server(Int)
    case badPackage
    case checksumUnavailable
    case checksumMismatch
    case notWritable(String)
    case tool(String, String)

    var errorDescription: String? {
        switch self {
        case .server(let status): L.f("update.error_server", status)
        case .badPackage: L.s("update.error_package")
        case .checksumUnavailable: L.s("update.error_checksum_unavailable")
        case .checksumMismatch: L.s("update.error_checksum")
        case .notWritable(let path): L.f("update.error_not_writable", path)
        case .tool(let name, _): L.f("update.error_tool", name)
        }
    }
}
