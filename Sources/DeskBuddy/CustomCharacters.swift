import AppKit

/// The currently selected character — a built-in character or a user-added image
enum CharacterChoice: Equatable {
    case builtin(CharacterKind)
    case custom(String)   // File name inside the characters folder

    static func parse(_ raw: String) -> CharacterChoice {
        if raw.hasPrefix("custom:") {
            return .custom(String(raw.dropFirst("custom:".count)))
        }
        return .builtin(CharacterKind(rawValue: raw) ?? .slime)
    }

    var raw: String {
        switch self {
        case .builtin(let kind): kind.rawValue
        case .custom(let name): "custom:\(name)"
        }
    }
}

/// Manages user-added character images
/// (~/Library/Application Support/DeskBuddy/characters/)
@MainActor
enum CustomCharacters {
    static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeskBuddy/characters", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func list() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted()
    }

    /// Copies the source into the folder and returns the stored file name. The display name starts as the original file name.
    static func add(_ source: URL) throws -> String {
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
        let name = UUID().uuidString + "." + ext
        try FileManager.default.copyItem(at: source, to: url(name))
        setDisplayName(source.deletingPathExtension().lastPathComponent, for: name)
        return name
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(name))
        CharacterImageCache.evict(name)
        setDisplayName("", for: name)   // Clean up the name mapping too
    }

    // MARK: Display names (file name → user-assigned name)

    private static let namesKey = "DeskBuddy.customNames"

    static func displayName(_ name: String) -> String {
        let dict = UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String]
        return dict?[name] ?? L.s("character.custom")
    }

    static func setDisplayName(_ display: String, for name: String) {
        var dict = (UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String]) ?? [:]
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        dict[name] = trimmed.isEmpty ? nil : trimmed
        UserDefaults.standard.set(dict, forKey: namesKey)
    }
}

/// Custom character images are redrawn on every animation frame, so they must go through this cache
@MainActor
enum CharacterImageCache {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let loaded = NSImage(contentsOf: CustomCharacters.url(name)) else { return nil }
        cache[name] = loaded
        return loaded
    }

    static func evict(_ name: String) {
        cache[name] = nil
    }
}
