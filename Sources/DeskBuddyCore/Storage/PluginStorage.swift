import Foundation

public enum PluginStorageError: Error, Equatable {
    /// Keys become file names, so they are limited to letters, digits, "-" and "_"
    case invalidKey(String)
}

/// A plugin's own data, kept on disk where no other plugin looks:
/// `Application Support/DeskBuddy/plugins/<plugin id>/<key>.json`, one JSON file per key.
///
/// Reading a key that was never written gives nil. Reading one whose file cannot be read
/// or decoded throws. Then the data is still on disk and must not be overwritten blindly:
/// `setAside(_:)` moves it out of the way so the plugin can start over without losing it.
@MainActor
public final class PluginStorage {
    /// The plugin's folder, created on the first write
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func get<Value: Decodable>(_ type: Value.Type, forKey key: String) throws -> Value? {
        let url = try file(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    /// Replaces the value atomically: a crash mid-write leaves the old file whole
    public func set<Value: Encodable>(_ value: Value, forKey key: String) throws {
        let url = try file(for: key)
        let data = try JSONEncoder().encode(value)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public func remove(forKey key: String) throws {
        let url = try file(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Moves the key's file to `<key>.unreadable-<time>.json` next to it, so a value that could
    /// not be read survives the plugin writing a fresh one. Returns where it went, or nil when
    /// there was nothing to move.
    @discardableResult
    public func setAside(_ key: String) throws -> URL? {
        let url = try file(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = directory.appendingPathComponent("\(key).unreadable-\(stamp).json")
        try FileManager.default.moveItem(at: url, to: aside)
        return aside
    }

    private func file(for key: String) throws -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !key.isEmpty, key.unicodeScalars.allSatisfy({ $0.isASCII && allowed.contains($0) }) else {
            throw PluginStorageError.invalidKey(key)
        }
        return directory.appendingPathComponent("\(key).json")
    }
}
