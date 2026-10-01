import Foundation

/// Something that has happened — "todo.deleted", not "delete the to-do". The type lives in the
/// emitting feature's API module, so subscribers depend on that module and not on the feature.
///
/// Carry only what a subscriber cannot look up through a service. To read another feature's
/// current state, resolve its service instead of keeping a copy built from events.
public protocol DeskBuddyEvent {
    /// Namespaced by the emitting plugin's id, past tense: "todo.deleted"
    static var name: String { get }
}

/// What `subscribe` hands back, for `unsubscribe`
public struct EventSubscription: Hashable {
    fileprivate let name: String
    fileprivate let id: UUID
}

/// Lets features announce what happened without knowing who listens — a deleted to-do, a
/// finished timer. The emitter does not wait for an answer and does not learn whether
/// anyone heard.
///
/// Delivery is synchronous, on the main actor, in subscription order. A handler that
/// subscribes or unsubscribes while an event is being delivered changes what the next
/// emit reaches, not the current one.
@MainActor
public final class EventBus {
    private typealias Handler = @MainActor (any DeskBuddyEvent) -> Void

    /// Per event name, in subscription order
    private var handlers: [String: [(id: UUID, handle: Handler)]] = [:]

    public init() {}

    @discardableResult
    public func subscribe<Event: DeskBuddyEvent>(
        _ type: Event.Type,
        _ handle: @escaping @MainActor (Event) -> Void
    ) -> EventSubscription {
        let subscription = EventSubscription(name: Event.name, id: UUID())
        handlers[Event.name, default: []].append((subscription.id, { event in
            if let event = event as? Event { handle(event) }
        }))
        return subscription
    }

    public func unsubscribe(_ subscription: EventSubscription) {
        handlers[subscription.name]?.removeAll { $0.id == subscription.id }
    }

    public func emit<Event: DeskBuddyEvent>(_ event: Event) {
        for handler in handlers[Event.name] ?? [] {
            handler.handle(event)
        }
    }
}
