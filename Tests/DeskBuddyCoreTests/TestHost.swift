import DeskBuddyCore
import Foundation

extension PluginManager {
    /// For tests whose plugins keep nothing and show nothing: their storage points at a folder
    /// that is never created, and surfaces go nowhere
    convenience init(buddy: any Buddy) {
        self.init(buddy: buddy, presenter: RecordingPresenter(), storageRoot: FileManager.default.temporaryDirectory
            .appendingPathComponent("DeskBuddyCoreTests-unused-\(UUID().uuidString)", isDirectory: true))
    }
}

/// Stands in for the app's windows, keeping a log of what it was asked to do
@MainActor
final class RecordingPresenter: SurfacePresenter {
    private(set) var log: [String] = []
    /// How to end each surface on screen, to play the user closing it or a bubble going away
    private(set) var endings: [SurfaceID: @MainActor (SurfaceEnd) -> Void] = [:]

    func show(_ surface: Surface, id: SurfaceID, ended: @escaping @MainActor (SurfaceEnd) -> Void) {
        log.append("show \(id) \(Self.describe(surface))")
        endings[id] = ended
    }

    func update(_ surface: Surface, id: SurfaceID) {
        log.append("update \(id) \(Self.describe(surface))")
    }

    func hide(_ id: SurfaceID) {
        log.append("hide \(id)")
        endings[id] = nil
    }

    private static func describe(_ surface: Surface) -> String {
        switch surface {
        case .bubble(let message): "bubble \(message)"
        case .panel: "panel"
        }
    }
}
