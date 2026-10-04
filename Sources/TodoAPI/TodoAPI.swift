import DeskBuddyCore
import Foundation

// What the to-do feature offers other features. Holds only types and protocols, so a
// feature can depend on it without depending on how to-dos are stored or shown.

/// What other features may know about a to-do
public struct TodoSummary: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let isDone: Bool
    public let createdAt: Date
    /// When it was completed; nil while open. To-dos completed before this was recorded
    /// report their creation time.
    public let completedAt: Date?
    public let hasMemo: Bool

    public init(id: UUID, title: String, isDone: Bool, createdAt: Date, completedAt: Date?, hasMemo: Bool) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.hasMemo = hasMemo
    }
}

/// For features that work with to-dos, such as a timer linked to one or the calendar's
/// completion history: reading them, and doing what a to-do row does. Look it up with
/// `services.resolve(TodoService.self)`; nil means the to-do feature is not there.
///
/// The actions take the id of a to-do and do nothing once it has been deleted. The
/// todo.toggle/remove/show commands do the same for callers outside the app.
@MainActor
public protocol TodoService: AnyObject {
    /// Open to-dos, in the user's order
    var active: [TodoSummary] { get }

    /// Any to-do, open or done — nil once it has been deleted
    func todo(_ id: UUID) -> TodoSummary?

    /// To-dos completed on the day `day` falls in, latest first. Includes those hidden from
    /// the Done tab: hiding them does not change the history.
    func completed(on day: Date) -> [TodoSummary]

    /// Marks an open to-do done, or a done one open again
    func toggle(_ id: UUID)

    /// Deletes the to-do for good; `TodoDeleted` follows
    func remove(_ id: UUID)

    /// Opens the list panel on the to-do's detail
    func show(_ id: UUID)
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
    public let content: @MainActor (UUID) -> any PlatformView

    public init(id: String, order: Int, content: @escaping @MainActor (UUID) -> any PlatformView) {
        self.id = id
        self.order = order
        self.content = content
    }
}
