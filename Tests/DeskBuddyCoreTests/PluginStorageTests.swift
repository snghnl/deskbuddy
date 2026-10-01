import XCTest
@testable import DeskBuddyCore

@MainActor
final class PluginStorageTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PluginStorageTests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    func testValuesComeBackAsTheyWereSet() throws {
        let storage = PluginStorage(directory: root)

        try storage.set(["a", "b"], forKey: "letters")
        try storage.set(Date(timeIntervalSinceReferenceDate: 42), forKey: "moment")

        XCTAssertEqual(try storage.get([String].self, forKey: "letters"), ["a", "b"])
        XCTAssertEqual(try storage.get(Date.self, forKey: "moment"), Date(timeIntervalSinceReferenceDate: 42))
    }

    func testAKeyNeverSetReadsAsNilAndRemovingItIsFine() throws {
        let storage = PluginStorage(directory: root)

        XCTAssertNil(try storage.get(Int.self, forKey: "missing"))
        XCTAssertNoThrow(try storage.remove(forKey: "missing"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path), "nothing is created until a write")
    }

    func testRemovedValuesAreGone() throws {
        let storage = PluginStorage(directory: root)
        try storage.set(1, forKey: "count")

        try storage.remove(forKey: "count")

        XCTAssertNil(try storage.get(Int.self, forKey: "count"))
    }

    func testEachKeyIsAJSONFileInThePluginsFolder() throws {
        try PluginStorage(directory: root).set([1, 2], forKey: "numbers")

        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("numbers.json"), encoding: .utf8), "[1,2]")
    }

    func testUnreadableValueThrowsAndCanBeSetAsideWithoutLosingIt() throws {
        let storage = PluginStorage(directory: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: root.appendingPathComponent("todos.json"))

        XCTAssertThrowsError(try storage.get([String].self, forKey: "todos"))
        let aside = try XCTUnwrap(try storage.setAside("todos"))

        XCTAssertNil(try storage.get([String].self, forKey: "todos"))
        XCTAssertEqual(try String(contentsOf: aside, encoding: .utf8), "not json")
        XCTAssertTrue(aside.lastPathComponent.hasPrefix("todos.unreadable-"))
        XCTAssertNil(try storage.setAside("todos"), "nothing left to move")
    }

    func testKeysThatCouldEscapeTheFolderAreRefused() {
        let storage = PluginStorage(directory: root)

        for key in ["", "../todo/todos", "a/b", "dot.ted", "space key", "ünïcode"] {
            XCTAssertThrowsError(try storage.set(1, forKey: key)) {
                XCTAssertEqual($0 as? PluginStorageError, .invalidKey(key))
            }
        }
    }

    func testEachPluginGetsAFolderNamedAfterItsID() throws {
        let manager = PluginManager(buddy: RecordingBuddy(), storageRoot: root)
        manager.register(Saver(id: "first"))
        manager.register(Saver(id: "second"))

        manager.activateAll()

        XCTAssertEqual(try PluginStorage(directory: root.appendingPathComponent("first")).get(String.self, forKey: "owner"), "first")
        XCTAssertEqual(try PluginStorage(directory: root.appendingPathComponent("second")).get(String.self, forKey: "owner"), "second")
    }
}

/// Writes its own id into its storage on activation
@MainActor
private final class Saver: DeskBuddyPlugin {
    let manifest: PluginManifest

    init(id: String) {
        manifest = PluginManifest(id: id, name: id, version: "1.0.0")
    }

    func activate(_ context: PluginContext) throws {
        try context.storage.set(manifest.id, forKey: "owner")
    }

    func deactivate() {}
}
