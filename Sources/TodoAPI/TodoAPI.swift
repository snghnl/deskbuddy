import DeskBuddyCore
import Foundation
import SwiftUI

// What the to-do feature offers other features. Holds only types and protocols, so a
// feature can depend on it without depending on how to-dos are stored or shown.

/// What other features may know about a to-do
public struct TodoSummary: Identifiable, Equatable {
    public let id: UUID
    public let title: String

    public init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }
}

/// For features that work with to-dos, such as a timer linked to one. Look it up with
/// `services.resolve(TodoService.self)`; nil means the to-do feature is not there.
@MainActor
public protocol TodoService: AnyObject {
    /// Open to-dos, in the user's order
    var active: [TodoSummary] { get }

    /// Any to-do, open or done — nil once it has been deleted
    func todo(_ id: UUID) -> TodoSummary?
}

/// A to-do is gone for good — removed from the list, or wiped with the rest of the history.
/// Hiding completed to-dos from the Done tab is not a deletion.
public struct TodoDeleted: DeskBuddyEvent {
    public static let name = "todo.deleted"

    public let id: UUID

    public init(id: UUID) {
        self.id = id
    }
}

public enum TodoSlots {
    /// Small views after the title on the rows of the To Do tab, e.g. a timer icon
    public static let rowAccessory = SlotID<TodoRowAccessory>("todo.row.accessory")
}

public struct TodoRowAccessory: SlotContribution {
    public let id: String
    public let order: Int
    /// Given the row's to-do id. Render nothing when there is nothing to show for it.
    public let content: @MainActor (UUID) -> AnyView

    public init<Content: View>(
        id: String,
        order: Int,
        @ViewBuilder content: @escaping @MainActor (UUID) -> Content
    ) {
        self.id = id
        self.order = order
        self.content = { AnyView(content($0)) }
    }
}
