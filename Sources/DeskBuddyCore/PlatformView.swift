/// A piece of UI in the host's own toolkit: on macOS a SwiftUI view, wrapped as
/// DeskBuddyMacUI's `MacView`. Core carries it from the plugin that made it to the host that
/// draws it without looking inside, so Core itself needs no UI framework.
public protocol PlatformView {}
