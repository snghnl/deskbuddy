import XCTest
@testable import DeskBuddyCore

final class PluginSettingsTests: XCTestCase {
    func testEachPluginsKeysCarryItsID() {
        let calendar = PluginSettings(pluginID: "calendar", defaults: MemoryDefaults())

        XCTAssertEqual(calendar.key("eventAlerts"), "DeskBuddy.plugins.calendar.eventAlerts")
        XCTAssertEqual(PluginSettings.prefix(for: "todo"), "DeskBuddy.plugins.todo.")
    }

    func testAnUnchosenValueReadsAsTheDefaultUntilSet() {
        let defaults = MemoryDefaults()
        let settings = PluginSettings(pluginID: "calendar", defaults: defaults)

        XCTAssertTrue(settings.bool("eventAlerts", default: true))
        XCTAssertEqual(settings.integer("lead", default: 10), 10)
        XCTAssertEqual(settings.string("sound", default: "Glass"), "Glass")

        settings.set(false, for: "eventAlerts")
        settings.set(30, for: "lead")
        settings.set("Ping", for: "sound")

        XCTAssertFalse(settings.bool("eventAlerts", default: true))
        XCTAssertEqual(settings.integer("lead", default: 10), 30)
        XCTAssertEqual(settings.string("sound", default: "Glass"), "Ping")

        settings.set(nil, for: "lead")
        XCTAssertEqual(settings.integer("lead", default: 10), 10)
    }

    func testPluginsDoNotSeeEachOthersChoices() {
        let defaults = MemoryDefaults()
        let calendar = PluginSettings(pluginID: "calendar", defaults: defaults)
        let todo = PluginSettings(pluginID: "todo", defaults: defaults)

        calendar.set(false, for: "enabled")

        XCTAssertTrue(todo.bool("enabled", default: true))
    }
}

/// Preferences kept in memory only, so a test never writes a preferences file
private final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]

    init() {
        super.init(suiteName: nil)!
    }

    override func object(forKey key: String) -> Any? { values[key] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values[key] = nil }
}
