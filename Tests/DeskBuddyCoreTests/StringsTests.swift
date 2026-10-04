import XCTest
@testable import DeskBuddyCore

final class StringsTests: XCTestCase {
    /// Fixture tables in this test target's Resources/Localizations
    private let strings = Strings(bundle: .module)

    func testReadsItsOwnTableInTheLanguageAsked() {
        XCTAssertEqual(strings.s("fixture.hello", korean: true), "안녕")
        XCTAssertEqual(strings.s("fixture.hello", korean: false), "Hello")
    }

    func testFallsBackToEnglishThenToCoresSharedStringsThenToTheKey() {
        XCTAssertEqual(strings.s("fixture.english_only", korean: true), "Only in English")
        XCTAssertEqual(strings.s("settings.cancel", korean: true), L.s("settings.cancel"))
        XCTAssertNotEqual(L.s("settings.cancel"), "settings.cancel")
        XCTAssertEqual(strings.s("fixture.missing", korean: true), "fixture.missing")
    }
}

/// Every key a target looks up exists in its own tables or Core's, in both languages. Reads
/// the sources, so a string moved or misspelled fails here rather than showing as its key.
final class LocalizationTablesTests: XCTestCase {
    private let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources")

    func testEveryKeyUsedIsTranslated() throws {
        let shared = try keys(in: "DeskBuddyCore")
        let targets = try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { $0 != "DeskBuddyCore" }
        var checked = 0
        for target in targets {
            let used = try usedKeys(in: target)
            guard !used.isEmpty else { continue }
            var own = try keys(in: target)
            // A feature's macOS layer (PomodoroMac) shows the strings its plugin target keeps
            if target.hasSuffix("Mac") {
                let plugin = try keys(in: target.dropLast(3) + "Plugin")
                for lang in ["en", "ko"] { own[lang, default: []].formUnion(plugin[lang] ?? []) }
            }
            for lang in ["en", "ko"] {
                let available = (own[lang] ?? []).union(shared[lang] ?? [])
                let missing = used.subtracting(available)
                XCTAssertTrue(missing.isEmpty, "\(target) \(lang).yml lacks \(missing.sorted())")
            }
            checked += used.count
        }
        XCTAssertGreaterThan(checked, 100, "found the keys in use")
    }

    /// Keys passed to strings.s/f in the target's Swift files
    private func usedKeys(in target: String) throws -> Set<String> {
        let folder = sources.appendingPathComponent(target)
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return [] }
        let pattern = try NSRegularExpression(pattern: #"strings\.[sf]\("([^"]+)""#)
        var used: Set<String> = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                used.insert(String(text[Range(match.range(at: 1), in: text)!]))
            }
        }
        return used
    }

    /// The keys in each of the target's tables, by language
    private func keys(in target: String) throws -> [String: Set<String>] {
        var tables: [String: Set<String>] = [:]
        for lang in ["en", "ko"] {
            let file = sources.appendingPathComponent("\(target)/Resources/Localizations/\(lang).yml")
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            tables[lang] = Set(text.split(separator: "\n").compactMap { line in
                line.split(separator: ":", maxSplits: 1).first.map(String.init)
            })
        }
        return tables
    }
}
