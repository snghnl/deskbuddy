import Foundation

/// Names something a plugin put on screen, so it can update or dismiss it later. Namespaced
/// by the plugin's id, like commands: "calendar.eventAlert".
public struct SurfaceID: Hashable, CustomStringConvertible {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }

    public var description: String { name }
}

/// UI a plugin puts up on its own, as opposed to a contribution to UI someone else owns (a slot)
public enum Surface {
    /// The buddy's speech bubble. It closes after the delay the user chose in Settings, or when
    /// clicked, and a later message — from anyone — takes its place.
    case bubble(String)
    /// A floating window next to the buddy, for something the user works with: a form, a
    /// choice. It takes keyboard focus and stays until dismissed or closed by the user.
    case panel(any PlatformView)

    var isBubble: Bool {
        if case .bubble = self { return true }
        return false
    }
}

/// How a surface left the screen, other than by being dismissed
public enum SurfaceEnd {
    /// The user closed it: clicked the bubble, or the panel's close button or Escape
    case closedByUser
    /// It left on its own: a bubble timed out or gave way to another message
    case wentAway
}

/// Draws surfaces with real windows. The app implements it; plugins go through SurfaceManager.
@MainActor
public protocol SurfacePresenter: AnyObject {
    /// Puts `surface` up, replacing what `id` showed. Calls `ended` once if it leaves the
    /// screen other than through `hide`.
    func show(_ surface: Surface, id: SurfaceID, ended: @escaping @MainActor (SurfaceEnd) -> Void)
    func update(_ surface: Surface, id: SurfaceID)
    func hide(_ id: SurfaceID)
}

/// Lets plugins put up a bubble or a panel without touching windows: where it goes, what stays
/// on top, how it follows the buddy and takes focus are the app's business.
@MainActor
public final class SurfaceManager {
    private let presenter: any SurfacePresenter
    /// Up surfaces, each with the presentation it belongs to — a close reported for an earlier
    /// presentation under the same id is ignored
    private var presented: [SurfaceID: UUID] = [:]

    public init(presenter: any SurfacePresenter) {
        self.presenter = presenter
    }

    /// Shows `surface` under `id`, replacing what that id showed. `onClose` runs if the user
    /// closes it, not when you call `dismiss`. A bubble that times out or gives way to another
    /// message is not reported either, but is no longer presented.
    public func present(_ surface: Surface, id: SurfaceID, onClose: (@MainActor () -> Void)? = nil) {
        let presentation = UUID()
        presented[id] = presentation
        presenter.show(surface, id: id) { [weak self] end in
            guard let self, presented[id] == presentation else { return }
            presented[id] = nil
            if case .closedByUser = end { onClose?() }
        }
    }

    /// Changes what `id` shows, e.g. a countdown ticking or a form after a submission. Does
    /// nothing once it is gone — dismissed, closed, or for a bubble, timed out or replaced.
    public func update(_ id: SurfaceID, to surface: Surface) {
        guard presented[id] != nil else { return }
        presenter.update(surface, id: id)
    }

    public func dismiss(_ id: SurfaceID) {
        guard presented.removeValue(forKey: id) != nil else { return }
        presenter.hide(id)
    }

    public func isPresented(_ id: SurfaceID) -> Bool {
        presented[id] != nil
    }
}
