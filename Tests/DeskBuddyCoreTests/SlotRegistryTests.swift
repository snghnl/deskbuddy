import XCTest
@testable import DeskBuddyCore

@MainActor
final class SlotRegistryTests: XCTestCase {
    private let tabs = SlotID<Item>("test.tabs")
    private let badges = SlotID<Item>("test.badges")

    func testContributionsComeBackSortedByOrder() {
        let registry = SlotRegistry()
        registry.contribute(tabs, Item(id: "c", order: 300))
        registry.contribute(tabs, Item(id: "a", order: 100))
        registry.contribute(tabs, Item(id: "b", order: 200))

        XCTAssertEqual(registry.contributions(to: tabs).map(\.id), ["a", "b", "c"])
    }

    func testEqualOrdersKeepRegistrationOrder() {
        let registry = SlotRegistry()
        registry.contribute(tabs, Item(id: "first", order: 100))
        registry.contribute(tabs, Item(id: "second", order: 100))
        registry.contribute(tabs, Item(id: "before", order: 50))
        registry.contribute(tabs, Item(id: "third", order: 100))

        XCTAssertEqual(registry.contributions(to: tabs).map(\.id), ["before", "first", "second", "third"])
    }

    func testSlotsAreSeparate() {
        let registry = SlotRegistry()
        registry.contribute(tabs, Item(id: "tab", order: 0))
        registry.contribute(badges, Item(id: "badge", order: 0))

        XCTAssertEqual(registry.contributions(to: tabs).map(\.id), ["tab"])
        XCTAssertEqual(registry.contributions(to: badges).map(\.id), ["badge"])
    }

    func testEmptySlotHasNoContributions() {
        XCTAssertTrue(SlotRegistry().contributions(to: tabs).isEmpty)
    }

    func testPluginContributionReachesTheSharedRegistry() {
        let manager = PluginManager(buddy: RecordingBuddy())
        manager.register(TabPlugin(slot: tabs))

        manager.activateAll()

        XCTAssertEqual(manager.slots.contributions(to: tabs).map(\.id), ["tabplugin.tab"])
    }
}

private struct Item: SlotContribution {
    let id: String
    let order: Int
}

@MainActor
private final class TabPlugin: DeskBuddyPlugin {
    let manifest = PluginManifest(id: "tabplugin", name: "Tab", version: "0.0.0")
    let slot: SlotID<Item>

    init(slot: SlotID<Item>) {
        self.slot = slot
    }

    func activate(_ context: PluginContext) throws {
        context.slots.contribute(slot, Item(id: "tabplugin.tab", order: 500))
    }

    func deactivate() {}
}
