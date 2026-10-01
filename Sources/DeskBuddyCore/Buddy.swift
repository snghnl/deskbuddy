/// The character on screen, as plugins get to use it
@MainActor
public protocol Buddy: AnyObject {
    /// Shows `message` in a speech bubble, bringing the buddy out first if it is hidden.
    /// The bubble closes after the delay the user chose in Settings, or when clicked.
    func say(_ message: String)
}
