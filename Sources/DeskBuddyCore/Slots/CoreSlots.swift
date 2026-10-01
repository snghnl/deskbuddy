import SwiftUI

/// Slots on the UI DeskBuddy itself owns
public enum CoreSlots {
    /// Tabs of the list panel, left to right. ⌘1–⌘9 follow the same order.
    public static let listTabs = SlotID<ListTab>("list.tabs")
    /// Items in the list panel's ⋯ menu, above Quit
    public static let listMenu = SlotID<ListMenuItem>("list.menu")
    /// Sections of the Settings window, placed among the built-in ones by order
    public static let settingsSections = SlotID<SettingsSection>("settings.sections")
    /// The number on the buddy's badge. The first contribution with a count above zero is shown.
    public static let buddyBadge = SlotID<BuddyBadge>("buddy.badge")
}

public struct ListTab: SlotContribution {
    public let id: String
    public let order: Int
    public let title: @MainActor () -> String
    /// Shown next to the title when above zero
    public let count: @MainActor () -> Int
    /// Sits between the tab bar and the divider while the tab is selected, e.g. the to-do input
    public let toolbar: (@MainActor () -> AnyView)?
    public let content: @MainActor () -> AnyView

    public init<Content: View>(
        id: String,
        order: Int,
        title: @escaping @MainActor () -> String,
        count: @escaping @MainActor () -> Int = { 0 },
        toolbar: (@MainActor () -> AnyView)? = nil,
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) {
        self.id = id
        self.order = order
        self.title = title
        self.count = count
        self.toolbar = toolbar
        self.content = { AnyView(content()) }
    }
}

public struct ListMenuItem: SlotContribution {
    public let id: String
    public let order: Int
    public let title: @MainActor () -> String
    public let isEnabled: @MainActor () -> Bool
    public let isVisible: @MainActor () -> Bool
    public let action: @MainActor () -> Void

    public init(
        id: String,
        order: Int,
        title: @escaping @MainActor () -> String,
        isEnabled: @escaping @MainActor () -> Bool = { true },
        isVisible: @escaping @MainActor () -> Bool = { true },
        action: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.order = order
        self.title = title
        self.isEnabled = isEnabled
        self.isVisible = isVisible
        self.action = action
    }
}

public struct SettingsSection: SlotContribution {
    public let id: String
    public let order: Int
    public let title: @MainActor () -> String
    public let footer: (@MainActor () -> String)?
    /// The section's rows
    public let content: @MainActor () -> AnyView

    public init<Content: View>(
        id: String,
        order: Int,
        title: @escaping @MainActor () -> String,
        footer: (@MainActor () -> String)? = nil,
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) {
        self.id = id
        self.order = order
        self.title = title
        self.footer = footer
        self.content = { AnyView(content()) }
    }
}

public struct BuddyBadge: SlotContribution {
    public let id: String
    public let order: Int
    public let count: @MainActor () -> Int

    public init(id: String, order: Int, count: @escaping @MainActor () -> Int) {
        self.id = id
        self.order = order
        self.count = count
    }
}

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
