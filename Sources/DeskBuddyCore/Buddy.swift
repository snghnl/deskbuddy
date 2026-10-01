import Foundation
import SwiftUI

/// The character on screen, as plugins get to use it
@MainActor
public protocol Buddy: AnyObject {
    /// Whether the character is on screen. Ambient news, such as an upcoming event, is only
    /// worth saying while it is out; `say` would bring it out.
    var isVisible: Bool { get }

    /// Shows `message` in a speech bubble, bringing the buddy out first if it is hidden.
    /// The bubble closes after the delay the user chose in Settings, or when clicked.
    func say(_ message: String)

    /// Like `say(_:)`, but the bubble closes after `seconds` whatever the user chose —
    /// for short confirmations that should not linger.
    func say(_ message: String, closingAfter seconds: TimeInterval)

    /// Changes the text of the bubble showing `old` to `new`, e.g. a countdown ticking down.
    /// Does nothing once that bubble has closed or another message has replaced it.
    func replace(_ old: String, with new: String)

    /// Opens the list panel under the buddy, covered by `page` — e.g. a to-do's detail when
    /// the todo.show command runs. Views already inside the panel use the `listPage`
    /// environment action instead.
    func openList(on page: AnyView)
}
