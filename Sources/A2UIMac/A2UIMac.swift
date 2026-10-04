import A2UIPlugin
import AppKit
import DeskBuddyCore
import DeskBuddyMacUI

/// A2UI panels on macOS: components as SwiftUI controls, icons as SF Symbols
package struct A2UIMac: A2UIPlatform {
    package init() {}

    package func panel(for session: A2UISession) -> any PlatformView {
        MacView(A2UIPanelView(session: session))
    }

    package nonisolated func iconExists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}
