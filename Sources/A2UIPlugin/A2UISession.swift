import A2UIAPI
import DeskBuddyCore
import Foundation
import Observation

/// One panel's state: what is in its inputs, and what happens when a button is pressed
@MainActor
@Observable
final class A2UISession {
    let document: A2UINode
    /// The inputs' current values, by id
    var values: [String: String]
    /// Why the last command failed, shown at the bottom of the panel
    private(set) var error: String?
    /// The tab each set of tabs shows, by the tabs' key, once the user has picked one
    private(set) var selectedTabs: [String: Int] = [:]

    @ObservationIgnored private let commands: CommandRegistry
    @ObservationIgnored private let finish: (A2UIResponse) -> Void
    /// Called when the panel's content changes size, e.g. once an error shows
    @ObservationIgnored var resized: (() -> Void)?

    init(document: A2UINode, commands: CommandRegistry, finish: @escaping (A2UIResponse) -> Void) {
        self.document = document
        values = document.initialValues
        self.commands = commands
        self.finish = finish
    }

    /// Runs the button's action and finishes the panel. A command that fails leaves the
    /// panel open with the reason, so the user can fix the input or close it.
    func perform(_ action: A2UIAction) {
        if case .command(let command, let arguments) = action {
            do {
                try commands.execute(command, CommandArguments(arguments.mapValues(resolve)))
            } catch {
                self.error = String(describing: error)
                resized?()
                return
            }
        }
        finish(A2UIResponse(action: action.reportedName, values: values))
    }

    /// Shows another tab. Tabs differ in height, so the panel is measured again.
    func select(tab index: Int, of key: String, id: String?, title: String) {
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

