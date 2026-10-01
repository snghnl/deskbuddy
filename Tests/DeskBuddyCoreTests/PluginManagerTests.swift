import XCTest
@testable import DeskBuddyCore

@MainActor
final class PluginManagerTests: XCTestCase {
    private var journal: [String] = []

    override func setUp() {
        journal = []
    }

    func testActivatesInRegistrationOrderAndDeactivatesInReverse() {
        let manager = PluginManager()
        manager.register(plugin("a"))
        manager.register(plugin("b"))
        manager.register(plugin("c"))

        manager.activateAll()
        manager.deactivateAll()

        XCTAssertEqual(journal, ["a.activate", "b.activate", "c.activate",
                                 "c.deactivate", "b.deactivate", "a.deactivate"])
    }

    func testPluginThatFailsToActivateIsNotDeactivatedAndOthersStillStart() {
        let manager = PluginManager()
        manager.register(plugin("a"))
        manager.register(plugin("broken", fails: true))
        manager.register(plugin("c"))

        manager.activateAll()
        manager.deactivateAll()

        XCTAssertEqual(journal, ["a.activate", "broken.activate", "c.activate",
                                 "c.deactivate", "a.deactivate"])
    }

    func testActivatingTwiceDoesNotRestartPlugins() {
        let manager = PluginManager()
        manager.register(plugin("a"))

        manager.activateAll()
        manager.activateAll()
        manager.deactivateAll()
        manager.deactivateAll()

        XCTAssertEqual(journal, ["a.activate", "a.deactivate"])
    }

    func testServiceProvidedByOnePluginResolvesInAnother() {
        let manager = PluginManager()
        var greeting: String?
        manager.register(plugin("provider") { context in
            context.services.provide(Greeter.self, EnglishGreeter())
        })
        manager.register(plugin("consumer") { context in
            greeting = context.services.resolve(Greeter.self)?.greet()
        })

        manager.activateAll()

        XCTAssertEqual(greeting, "hello")
    }

    func testResolvingAServiceNobodyProvidesGivesNil() {
        XCTAssertNil(ServiceRegistry().resolve(Greeter.self))
    }

    func testServicesAreKeyedByTheTypeTheyWereProvidedUnder() {
        let registry = ServiceRegistry()
        registry.provide(Greeter.self, EnglishGreeter())

        // The concrete type was never registered, only the protocol
        XCTAssertNil(registry.resolve(EnglishGreeter.self))
        XCTAssertNotNil(registry.resolve(Greeter.self))
    }

    // MARK: - Fixtures

    private func plugin(_ id: String, fails: Bool = false, onActivate: ((PluginContext) -> Void)? = nil) -> RecordingPlugin {
        RecordingPlugin(id: id, fails: fails, onActivate: onActivate) { [unowned self] in journal.append($0) }
    }
}

@MainActor
private protocol Greeter {
    func greet() -> String
}

private struct EnglishGreeter: Greeter {
    func greet() -> String { "hello" }
}

private struct ActivationFailed: Error {}

@MainActor
private final class RecordingPlugin: DeskBuddyPlugin {
    let manifest: PluginManifest
    private let fails: Bool
    private let onActivate: ((PluginContext) -> Void)?
    private let record: (String) -> Void

    init(id: String, fails: Bool, onActivate: ((PluginContext) -> Void)?, record: @escaping (String) -> Void) {
        manifest = PluginManifest(id: id, name: id, version: "0.0.0")
        self.fails = fails
        self.onActivate = onActivate
        self.record = record
    }

    func activate(_ context: PluginContext) throws {
        record("\(manifest.id).activate")
        if fails { throw ActivationFailed() }
        onActivate?(context)
    }

    func deactivate() {
        record("\(manifest.id).deactivate")
    }
}
