import SwiftUI

/// How DeskBuddy's own panels and bubbles look. The app decides from the user's setting and
/// passes it down through the environment, so plugins follow it without reading settings.
public enum Appearance {
    /// Liquid Glass needs macOS 26; before it, panels keep the frosted material
    public static var supportsGlass: Bool {
        if #available(macOS 26, *) { true } else { false }
    }
}

private struct GlassEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Whether panels, bubbles and their buttons use Liquid Glass. Only ever true on macOS 26
    /// and later, and only while the user leaves it on.
    var glassEnabled: Bool {
        get { self[GlassEnabledKey.self] }
        set { self[GlassEnabledKey.self] = newValue }
    }
}

public extension View {
    /// A panel's background in `shape`: Liquid Glass when `glassEnabled`, otherwise frosted
    /// material with a hairline edge
    func buddyBackground<S: InsettableShape>(in shape: S) -> some View {
        modifier(BuddyBackground(shape: shape))
    }

    /// A button on a panel. The prominent one is the main action.
    func buddyButtonStyle(prominent: Bool) -> some View {
        modifier(BuddyButtonStyle(prominent: prominent))
    }
}

private struct BuddyBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.glassEnabled) private var glass

    func body(content: Content) -> some View {
        if #available(macOS 26, *), glass {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.15), lineWidth: 1))
        }
    }
}

private struct BuddyButtonStyle: ViewModifier {
    let prominent: Bool
    @Environment(\.glassEnabled) private var glass

    func body(content: Content) -> some View {
        if #available(macOS 26, *), glass {
            if prominent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
        }
    }
}
