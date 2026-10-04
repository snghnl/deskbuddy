
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
    public let toolbar: (@MainActor () -> any PlatformView)?
    public let content: @MainActor () -> any PlatformView

    public init(
        id: String,
        order: Int,
        title: @escaping @MainActor () -> String,
        count: @escaping @MainActor () -> Int = { 0 },
        toolbar: (@MainActor () -> any PlatformView)? = nil,
        content: @escaping @MainActor () -> any PlatformView
    ) {
        self.id = id
        self.order = order
        self.title = title
        self.count = count
        self.toolbar = toolbar
        self.content = content
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
    public let content: @MainActor () -> any PlatformView

    public init(
        id: String,
        order: Int,
        title: @escaping @MainActor () -> String,
        footer: (@MainActor () -> String)? = nil,
        content: @escaping @MainActor () -> any PlatformView
    ) {
        self.id = id
        self.order = order
        self.title = title
        self.footer = footer
        self.content = content
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
