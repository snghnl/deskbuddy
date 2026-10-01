import DeskBuddyCore
import Foundation

/// Stands in for the on-screen character in tests, keeping what it was asked to say
@MainActor
final class RecordingBuddy: Buddy {
    private(set) var said: [String] = []

    func say(_ message: String) {
        said.append(message)
    }

    func say(_ message: String, closingAfter seconds: TimeInterval) {
        said.append(message)
    }
}
