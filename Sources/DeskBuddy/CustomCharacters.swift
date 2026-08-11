import AppKit

/// 현재 선택된 캐릭터 — 내장 캐릭터 또는 사용자가 추가한 이미지
enum CharacterChoice: Equatable {
    case builtin(CharacterKind)
    case custom(String)   // characters 폴더 안의 파일명

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

/// 사용자가 추가한 캐릭터 이미지 관리
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

    /// 원본을 폴더로 복사하고 저장된 파일명을 돌려준다. 표시 이름은 원본 파일명으로 시작한다.
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
        setDisplayName("", for: name)   // 이름 매핑도 정리
    }

    // MARK: 표시 이름 (파일명 → 사용자가 붙인 이름)

    private static let namesKey = "DeskBuddy.customNames"

    static func displayName(_ name: String) -> String {
        let dict = UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String]
        return dict?[name] ?? "커스텀"
    }

    static func setDisplayName(_ display: String, for name: String) {
        var dict = (UserDefaults.standard.dictionary(forKey: namesKey) as? [String: String]) ?? [:]
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        dict[name] = trimmed.isEmpty ? nil : trimmed
        UserDefaults.standard.set(dict, forKey: namesKey)
    }
}

/// 커스텀 캐릭터 이미지는 애니메이션 프레임마다 다시 그려지므로 반드시 캐시를 거친다
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
