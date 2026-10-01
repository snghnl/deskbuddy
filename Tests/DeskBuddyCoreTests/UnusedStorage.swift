import DeskBuddyCore
import Foundation

extension PluginManager {
    /// For tests whose plugins keep nothing: their storage points at a folder that is never created
    convenience init(buddy: any Buddy) {
        self.init(buddy: buddy, storageRoot: FileManager.default.temporaryDirectory
            .appendingPathComponent("DeskBuddyCoreTests-unused-\(UUID().uuidString)", isDirectory: true))
    }
}
