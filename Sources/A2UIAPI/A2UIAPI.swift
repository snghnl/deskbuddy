import Foundation

// What the A2UI feature offers other features: show a described UI and hear what the user did.
// The description is JSON in DeskBuddy's A2UI subset, documented in A2UIPlugin's A2UIDocument.

/// What the user did with an A2UI panel
public struct A2UIResponse: Codable, Equatable {
    /// The action they took: a button's `name`, or the command it ran. nil when they closed
    /// the panel without taking one.
    public let action: String?
    /// The panel's inputs at that moment, by id
    public let values: [String: String]

    public init(action: String?, values: [String: String]) {
        self.action = action
        self.values = values
    }
}

/// Shows A2UI documents as native panels next to the buddy. Look it up with
/// `services.resolve(A2UIService.self)`; nil means the A2UI feature is not there.
@MainActor
public protocol A2UIService: AnyObject {
    /// Shows `document` and waits until the user takes an action or closes the panel. Throws
    /// before showing anything if the document is not valid. Cancelling the calling task
    /// closes the panel and throws `CancellationError`.
    func ask(_ document: Data) async throws -> A2UIResponse
}
