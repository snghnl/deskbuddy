import DeskBuddyCore
import Foundation
import SwiftUI

/// Stands in for the on-screen character in tests, keeping what it was asked to say
@MainActor
final class RecordingBuddy: Buddy {
    private(set) var said: [String] = []

    var isVisible = true

    func say(_ message: String) {
        said.append(message)
    }

    func say(_ message: String, closingAfter seconds: TimeInterval) {
        said.append(message)
    }

    func replace(_ old: String, with new: String) {
        if let i = said.lastIndex(of: old) { said[i] = new }
    }

    func openList(on page: AnyView) {}
}
