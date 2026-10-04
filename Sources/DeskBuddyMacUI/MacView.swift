import DeskBuddyCore
import SwiftUI

/// A SwiftUI view, as the macOS host takes UI from plugins. Core's slots, surfaces and
/// `Buddy.openList` carry it as a `PlatformView`; the host draws it with `swiftUI`.
public struct MacView: PlatformView {
    public let view: AnyView

    public init<Content: View>(_ view: Content) {
        self.view = AnyView(view)
    }
}

public extension PlatformView {
    /// What the macOS host draws for this: the SwiftUI view inside, or nothing for UI made
    /// for another platform
    var swiftUI: AnyView {
        guard let mac = self as? MacView else {
            assertionFailure("\(type(of: self)) is not a MacView, so macOS cannot draw it")
            return AnyView(EmptyView())
        }
        return mac.view
    }
}

// SwiftUI-friendly ways to fill Core's slots, wrapping the views as MacView

public extension ListTab {
    init<Content: View>(
        id: String,
        order: Int,
        title: @escaping @MainActor () -> String,
        count: @escaping @MainActor () -> Int = { 0 },
        toolbar: (@MainActor () -> AnyView)? = nil,
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) {
        var wrappedToolbar: (@MainActor () -> any PlatformView)?
        if let toolbar {
            wrappedToolbar = { MacView(toolbar()) }
        }
        self.init(id: id, order: order, title: title, count: count, toolbar: wrappedToolbar,
                  content: { MacView(content()) })
    }
}

public extension SettingsSection {
    init<Content: View>(
        id: String,
        order: Int,
        title: @escaping @MainActor () -> String,
        footer: (@MainActor () -> String)? = nil,
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) {
        self.init(id: id, order: order, title: title, footer: footer, content: { MacView(content()) })
    }
}
