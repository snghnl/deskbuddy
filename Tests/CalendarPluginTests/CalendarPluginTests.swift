@testable import CalendarPlugin
import DeskBuddyCore
import SwiftUI
import TodoAPI
import XCTest

@MainActor
final class CalendarPluginTests: XCTestCase {
    func testActivationAddsTheCalendarTabAndItsSettings() {
        let manager = PluginManager(buddy: QuietBuddy(), presenter: NoWindows(), storageRoot: unusedStorageRoot())
        manager.register(CalendarPlugin())

        manager.activateAll()
        defer { manager.deactivateAll() }

        XCTAssertEqual(manager.slots.contributions(to: CoreSlots.listTabs).map(\.id), ["calendar.month"])
        XCTAssertEqual(manager.slots.contributions(to: CoreSlots.settingsSections).map(\.id), ["calendar.integration"])
    }

    func testActivatesWithoutTheToDoFeature() {
        let manager = PluginManager(buddy: QuietBuddy(), presenter: NoWindows(), storageRoot: unusedStorageRoot())
        manager.register(CalendarPlugin())

        manager.activateAll()
        defer { manager.deactivateAll() }

        // Nothing provides TodoService here; the tab still comes up, showing events only
        XCTAssertNil(manager.services.resolve(TodoService.self))
        XCTAssertFalse(manager.slots.contributions(to: CoreSlots.listTabs).isEmpty)
    }

    func testStartingUpLeavesThePreferencesUnchosen() {
        let defaults = MemoryDefaults()
        let manager = PluginManager(buddy: QuietBuddy(), presenter: NoWindows(), storageRoot: unusedStorageRoot(), defaults: defaults)
        manager.register(CalendarPlugin())

        manager.activateAll()
        defer { manager.deactivateAll() }

        // Defaults are read, not registered or written, so a later default change reaches everyone
        XCTAssertTrue(defaults.isEmpty)
        let settings = PluginSettings(pluginID: "calendar", defaults: defaults)
        XCTAssertTrue(settings.bool(CalendarSettings.eventAlerts, default: CalendarSettings.eventAlertsDefault))
        XCTAssertEqual(settings.integer(CalendarSettings.eventAlertLead, default: CalendarSettings.eventAlertLeadDefault), 10)
    }
}

@MainActor
private final class QuietBuddy: Buddy {
    let isVisible = true
    func say(_ message: String) {}
    func say(_ message: String, closingAfter seconds: TimeInterval) {}
    func openList(on page: any PlatformView) {}
}

/// Calendar keeps nothing in plugin storage; this folder is never created
private func unusedStorageRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("CalendarPluginTests-unused-\(UUID().uuidString)")
}

/// Surfaces go nowhere
@MainActor
private final class NoWindows: SurfacePresenter {
    func show(_ surface: Surface, id: SurfaceID, ended: @escaping @MainActor (SurfaceEnd) -> Void) {}
    func update(_ surface: Surface, id: SurfaceID) {}
    func hide(_ id: SurfaceID) {}
}

/// Preferences kept in memory only, so a test never writes a preferences file
private final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]
    var isEmpty: Bool { values.isEmpty }

    init() {
        super.init(suiteName: nil)!
    }

    override func object(forKey key: String) -> Any? { values[key] }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func removeObject(forKey key: String) { values[key] = nil }
}
