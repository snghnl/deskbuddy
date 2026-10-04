import A2UIAPI
import DeskBuddyCore
import Foundation
import Observation

/// One panel's state: what it shows, what is in its inputs, and what happens when a button is
/// pressed. A panel shown under a name keeps its session while its content changes.
@MainActor
@Observable
package final class A2UISession {
    package private(set) var document: A2UINode
    /// The inputs' current values, by id
    package var values: [String: String]
    /// Why the last command failed, shown at the bottom of the panel
    package private(set) var error: String?
    /// The tab each set of tabs shows, by the tabs' key, once the user has picked one
    package private(set) var selectedTabs: [String: Int] = [:]
    /// Whether someone waits for this panel's next action. Buttons that only name an action do
    /// nothing while nobody does, so they are disabled; command buttons act by themselves.
    package internal(set) var isListening = true

    @ObservationIgnored private let commands: CommandRegistry
    /// Called with the action taken, and whether the panel stays up after it
    @ObservationIgnored private let finish: (A2UIResponse, Bool) -> Void
    /// Called when the panel's content changes size, e.g. once an error shows
    @ObservationIgnored var resized: (() -> Void)?

    init(document: A2UINode, commands: CommandRegistry, finish: @escaping (A2UIResponse, Bool) -> Void) {
        self.document = document
        values = document.initialValues
        self.commands = commands
        self.finish = finish
    }

    /// Whether the button for `action` can be pressed now
    package func canPerform(_ action: A2UIAction) -> Bool {
        if case .command = action { return true }
        return isListening
    }

    /// Runs the button's action and hands it on, with whether the panel stays up after it. A
    /// command that fails leaves the panel open with the reason, so the user can fix the input
    /// or close it.
    package func perform(_ action: A2UIAction, keepOpen: Bool = false) {
        guard canPerform(action) else { return }
        if case .command(let command, let arguments) = action {
            do {
                try commands.execute(command, CommandArguments(arguments.mapValues(resolve)))
            } catch {
                self.error = String(describing: error)
                resized?()
                return
            }
        }
        finish(A2UIResponse(action: action.reportedName, values: values), keepOpen)
    }

    /// Shows a new document in the same panel: its inputs start over from the new values
    func update(_ document: A2UINode) {
        self.document = document
        values = document.initialValues
        error = nil
        selectedTabs = [:]
        resized?()
    }

    /// Shows another tab. Tabs differ in height, so the panel is measured again.
    package func select(tab index: Int, of key: String, id: String?, title: String) {
        selectedTabs[key] = index
        if let id { values[id] = title }
        resized?()
    }

    private func resolve(_ argument: A2UIArgument) -> String {
        switch argument {
        case .literal(let value): value
        case .input(let id): values[id] ?? ""
        }
    }
}
