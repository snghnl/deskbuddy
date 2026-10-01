import Observation

/// Something a feature puts on UI that another part of the app owns
public protocol SlotContribution {
    /// Unique within its slot
    var id: String { get }
    /// Position among the slot's contributions, ascending
    var order: Int { get }
}

/// Names a place on the UI that others can add to, and the kind of contribution it takes
public struct SlotID<Contribution: SlotContribution> {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }
}

/// Lets features put things on UI someone else owns — a tab in the list panel, a section in
/// Settings — without the owner knowing who they are.
///
/// The owner declares a `SlotID` and renders whatever `contributions(to:)` returns; features
/// call `contribute`. Observable, so the owner's view updates when something is added.
@MainActor
@Observable
public final class SlotRegistry {
    /// Per slot name, kept sorted by order
    private var bySlot: [String: [any SlotContribution]] = [:]

    public init() {}

    public func contribute<Contribution>(_ slot: SlotID<Contribution>, _ contribution: Contribution) {
        var list = bySlot[slot.name] ?? []
        assert(!list.contains { $0.id == contribution.id }, "\(slot.name) already has \(contribution.id)")
        // After any equal orders, so ties keep registration order
        let index = list.firstIndex { $0.order > contribution.order } ?? list.endIndex
        list.insert(contribution, at: index)
        bySlot[slot.name] = list
    }

    /// The slot's contributions, in order
    public func contributions<Contribution>(to slot: SlotID<Contribution>) -> [Contribution] {
        (bySlot[slot.name] ?? []).compactMap { $0 as? Contribution }
    }
}
