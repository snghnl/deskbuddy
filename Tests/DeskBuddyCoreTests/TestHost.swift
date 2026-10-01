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
    /// The close callback of each surface on screen, to play the user closing it
    private(set) var closers: [SurfaceID: @MainActor () -> Void] = [:]

    func show(_ surface: Surface, id: SurfaceID, closed: @escaping @MainActor () -> Void) {
        log.append("show \(id) \(Self.describe(surface))")
        closers[id] = closed
    }

    func update(_ surface: Surface, id: SurfaceID) {
        log.append("update \(id) \(Self.describe(surface))")
    }

    func hide(_ id: SurfaceID) {
        log.append("hide \(id)")
        closers[id] = nil
    }

    private static func describe(_ surface: Surface) -> String {
        switch surface {
        case .bubble(let message): "bubble \(message)"
        case .panel: "panel"
        }
    }
}
