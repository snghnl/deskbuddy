import XCTest
@testable import DeskBuddyCore

@MainActor
final class EventBusTests: XCTestCase {
    func testDeliversToSubscribersInSubscriptionOrder() {
        let bus = EventBus()
        var heard: [String] = []
        bus.subscribe(Rang.self) { heard.append("first \($0.times)") }
        bus.subscribe(Rang.self) { heard.append("second \($0.times)") }

        bus.emit(Rang(times: 2))

        XCTAssertEqual(heard, ["first 2", "second 2"])
    }

    func testDeliversOnlyTheSubscribedEvent() {
        let bus = EventBus()
        var heard: [String] = []
        bus.subscribe(Rang.self) { _ in heard.append("rang") }
        bus.subscribe(Knocked.self) { _ in heard.append("knocked") }

        bus.emit(Knocked())

        XCTAssertEqual(heard, ["knocked"])
    }

    func testUnsubscribedHandlerHearsNothingMore() {
        let bus = EventBus()
        var heard: [String] = []
        let leaving = bus.subscribe(Rang.self) { _ in heard.append("leaving") }
        bus.subscribe(Rang.self) { _ in heard.append("staying") }

        bus.unsubscribe(leaving)
        bus.emit(Rang(times: 1))

        XCTAssertEqual(heard, ["staying"])
    }

    func testEmittingWithNoSubscribersDoesNothing() {
        EventBus().emit(Rang(times: 1))
    }

    func testChangesDuringDeliveryApplyFromTheNextEmit() {
        let bus = EventBus()
        var heard: [String] = []
        var later: EventSubscription?
        bus.subscribe(Rang.self) { _ in
            heard.append("first")
            if let later {
                bus.unsubscribe(later)
            } else {
                bus.subscribe(Rang.self) { _ in heard.append("joined") }
            }
        }
        later = bus.subscribe(Rang.self) { _ in heard.append("later") }

        bus.emit(Rang(times: 1))
        bus.emit(Rang(times: 1))

        // The first emit still reaches "later", though "first" unsubscribed it along the way
        XCTAssertEqual(heard, ["first", "later", "first"])
    }

    func testHandlerCanEmitAnotherEvent() {
        let bus = EventBus()
        var heard: [String] = []
        bus.subscribe(Knocked.self) { _ in
            heard.append("knocked")
            bus.emit(Rang(times: 1))
        }
        bus.subscribe(Rang.self) { _ in heard.append("rang") }

        bus.emit(Knocked())

        XCTAssertEqual(heard, ["knocked", "rang"])
    }

    func testEventReachesAPluginSubscribedFromAnother() {
        let manager = PluginManager(buddy: RecordingBuddy())
        var heard: Int?
        manager.register(TestPlugin(id: "listener") { context in
            context.events.subscribe(Rang.self) { heard = $0.times }
        })
        manager.register(TestPlugin(id: "ringer") { context in
            context.events.emit(Rang(times: 3))
        })

        manager.activateAll()

        XCTAssertEqual(heard, 3)
    }
}

private struct Rang: DeskBuddyEvent {
    static let name = "test.rang"
    let times: Int
}

private struct Knocked: DeskBuddyEvent {
    static let name = "test.knocked"
}

@MainActor
private final class TestPlugin: DeskBuddyPlugin {
    let manifest: PluginManifest
    private let onActivate: (PluginContext) -> Void

    init(id: String, onActivate: @escaping (PluginContext) -> Void) {
        manifest = PluginManifest(id: id, name: id, version: "1.0.0")
        self.onActivate = onActivate
    }

    func activate(_ context: PluginContext) throws {
        onActivate(context)
    }

    func deactivate() {}
}
