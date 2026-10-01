@testable import DeskBuddy
import DeskBuddyCore
@testable import PomodoroPlugin
@testable import TodoPlugin
import XCTest

@MainActor
final class StorageMigrationTests: XCTestCase {
    private var support: URL!
    private var app: URL { support.appendingPathComponent("DeskBuddy") }
    private var plugins: URL { app.appendingPathComponent("plugins") }
    private let launch = Date(timeIntervalSince1970: 1_800_000_000)
    private let watermark: Double = 780_000_000

    override func setUpWithError() throws {
        // Stands in for Application Support
        support = FileManager.default.temporaryDirectory.appendingPathComponent("StorageMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: support)
    }

    func testEverythingReachesThePluginsAndTheirStoresReadIt() throws {
        let todos = [Todo(title: "Pack", memo: "socks"), Todo(title: "Done already", isDone: true, completedAt: launch)]
        let legacyTodos = try JSONEncoder().encode(todos)
        try legacyTodos.write(to: app.appendingPathComponent("todos.json"))
        let defaults = MemoryDefaults()
        let timers = [BuddyTimer(label: "25 min", todoID: todos[0].id, duration: 1500, pausedRemaining: 600)]
        defaults.set(try JSONEncoder().encode(timers), forKey: "DeskBuddy.timers")
        defaults.set(watermark, forKey: "DeskBuddy.historyClearedAt")

        StorageMigration.run(appFolder: app, defaults: defaults, now: launch)

        let store = TodoStore(storage: PluginStorage(directory: plugins.appendingPathComponent("todo")), events: EventBus())
        XCTAssertEqual(store.todos, todos)
        XCTAssertEqual(store.historyClearedAt, Date(timeIntervalSinceReferenceDate: watermark))
        XCTAssertEqual(TimerCenter(storage: PluginStorage(directory: plugins.appendingPathComponent("pomodoro"))).timers, timers)

        // Nothing is left where it would be read as stale
        XCTAssertFalse(exists(app.appendingPathComponent("todos.json")))
        XCTAssertNil(defaults.object(forKey: "DeskBuddy.timers"))
        XCTAssertNil(defaults.object(forKey: "DeskBuddy.historyClearedAt"))
    }

    func testOriginalsAreKeptInADatedBackupFolder() throws {
        let legacyTodos = Data(#"[{"id":"7D4C8A3E-0B1F-4E6A-9C2D-5F8E1A3B6C9D","title":"Old","isDone":false,"createdAt":700000000}]"#.utf8)
        try legacyTodos.write(to: app.appendingPathComponent("todos.json"))
        let defaults = MemoryDefaults()
        let timers = Data("[]".utf8)
        defaults.set(timers, forKey: "DeskBuddy.timers")
        defaults.set(watermark, forKey: "DeskBuddy.historyClearedAt")

        StorageMigration.run(appFolder: app, defaults: defaults, now: launch)

        let backup = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: app.appendingPathComponent("backups"),
                                                                                 includingPropertiesForKeys: nil).first)
        XCTAssertTrue(backup.lastPathComponent.hasSuffix("-before-plugin-storage"))
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("todos.json")), legacyTodos)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("timers.json")), timers)
        XCTAssertEqual(try JSONDecoder().decode(Date.self, from: Data(contentsOf: backup.appendingPathComponent("historyClearedAt.json"))),
                       Date(timeIntervalSinceReferenceDate: watermark))
    }

    func testRunningAgainChangesNothingAndNeverOverwritesPluginData() throws {
        try Data("[]".utf8).write(to: app.appendingPathComponent("todos.json"))
        StorageMigration.run(appFolder: app, defaults: MemoryDefaults(), now: launch)
        let migrated = try Data(contentsOf: plugins.appendingPathComponent("todo/todos.json"))

        // An older version, run in between, wrote a todos.json of its own
        let stray = Data(#"[{"id":"7D4C8A3E-0B1F-4E6A-9C2D-5F8E1A3B6C9D","title":"Stray","isDone":false,"createdAt":700000000}]"#.utf8)
        try stray.write(to: app.appendingPathComponent("todos.json"))
        StorageMigration.run(appFolder: app, defaults: MemoryDefaults(), now: launch.addingTimeInterval(60))

        XCTAssertEqual(try Data(contentsOf: plugins.appendingPathComponent("todo/todos.json")), migrated)
        XCTAssertEqual(try Data(contentsOf: app.appendingPathComponent("todos.json")), stray, "left for the user, not merged or lost")
    }

    func testToDosFromTheFloatingTodoDaysAreCopiedAndTheOriginalStays() throws {
        let floating = support.appendingPathComponent("FloatingTodo")
        try FileManager.default.createDirectory(at: floating, withIntermediateDirectories: true)
        let old = Data("[]".utf8)
        try old.write(to: floating.appendingPathComponent("todos.json"))

        StorageMigration.run(appFolder: app, defaults: MemoryDefaults(), now: launch)

        XCTAssertEqual(try Data(contentsOf: plugins.appendingPathComponent("todo/todos.json")), old)
        XCTAssertTrue(exists(floating.appendingPathComponent("todos.json")))
    }

    func testAFreshInstallGetsNoBackupFolder() {
        StorageMigration.run(appFolder: app, defaults: MemoryDefaults(), now: launch)

        XCTAssertFalse(exists(app.appendingPathComponent("backups")))
        XCTAssertFalse(exists(plugins))
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

/// Settings kept in memory only, so a test never writes a preferences file
private final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]

    init() {
        super.init(suiteName: nil)!
    }

    override func object(forKey key: String) -> Any? { values[key] }
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func set(_ value: Double, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values[key] = nil }
}
