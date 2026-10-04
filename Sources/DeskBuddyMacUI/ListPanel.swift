import SwiftUI

/// Shows a page over the whole list panel, tab bar included — e.g. a to-do's detail.
/// List tabs read it from the environment: `@Environment(\.listPage) private var listPage`.
public struct ListPageAction {
    private let presentPage: @MainActor (AnyView) -> Void
    public let dismiss: @MainActor () -> Void

    public init(present: @escaping @MainActor (AnyView) -> Void, dismiss: @escaping @MainActor () -> Void) {
        presentPage = present
        self.dismiss = dismiss
    }

    @MainActor
    public func present<Page: View>(_ page: Page) {
        presentPage(AnyView(page))
    }
}

private struct ListPageKey: EnvironmentKey {
    static var defaultValue: ListPageAction { ListPageAction(present: { _ in }, dismiss: {}) }
}

public extension EnvironmentValues {
    var listPage: ListPageAction {
        get { self[ListPageKey.self] }
        set { self[ListPageKey.self] = newValue }
    }
}

private struct ListPanelVisibleKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Whether the list panel is on screen. The panel is hidden rather than torn down, so a
    /// tab that wants focus each time it opens (the to-do input) watches this.
    var listPanelVisible: Bool {
        get { self[ListPanelVisibleKey.self] }
        set { self[ListPanelVisibleKey.self] = newValue }
    }
}
