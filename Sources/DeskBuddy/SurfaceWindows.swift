import AppKit
import DeskBuddyCore
import SwiftUI

/// Puts plugins' surfaces on screen. A bubble goes through the buddy's speech bubble. A panel
/// gets a floating window beside the character that follows it when dragged, shows on every
/// Space and over full-screen apps, and takes keyboard focus without activating the app.
@MainActor
final class SurfaceWindows: SurfacePresenter {
    private let characterPanel: NSPanel
    private let bubble: BubbleController
    /// The user's bubble delay at the moment of showing — nil keeps a bubble until clicked
    private let bubbleAutoHide: () -> TimeInterval?

    /// Each bubble surface's message in the shared bubble. May outlive the message, which is
    /// harmless: the bubble ignores ids it no longer shows.
    private var bubbleMessages: [SurfaceID: UUID] = [:]
    private var panels: [SurfaceID: SurfacePanel] = [:]

    init(characterPanel: NSPanel, bubble: BubbleController, bubbleAutoHide: @escaping () -> TimeInterval?) {
        self.characterPanel = characterPanel
        self.bubble = bubble
        self.bubbleAutoHide = bubbleAutoHide
    }

    func show(_ surface: Surface, id: SurfaceID, ended: @escaping @MainActor (SurfaceEnd) -> Void) {
        closePanel(id)
        switch surface {
        case .bubble(let message):
            // The new message takes the bubble from the old one; hiding it first would flicker
            if !characterPanel.isVisible { characterPanel.orderFrontRegardless() }
            bubbleMessages[id] = bubble.show(message, autoHide: bubbleAutoHide(),
                                             onTap: { ended(.closedByUser) },
                                             onGone: { ended(.wentAway) })
        case .panel(let content):
            if let message = bubbleMessages.removeValue(forKey: id) { bubble.hide(message) }
            let panel = SurfacePanel()
            panel.onClose = { [weak self] in
                self?.closePanel(id)
                ended(.closedByUser)
            }
            panels[id] = panel
            panel.setContent(content)
            // A child of a hidden window would not show
            if !characterPanel.isVisible { characterPanel.orderFrontRegardless() }
            place(panel)
            characterPanel.addChildWindow(panel, ordered: .above)
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }

    func update(_ surface: Surface, id: SurfaceID) {
        switch surface {
        case .bubble(let text):
            guard let message = bubbleMessages[id] else { return }
            bubble.replace(message, with: text)
        case .panel(let content):
            guard let panel = panels[id] else { return }
            panel.setContent(content)
            place(panel)
        }
    }

    func hide(_ id: SurfaceID) {
        if let message = bubbleMessages.removeValue(forKey: id) {
            bubble.hide(message)
        }
        closePanel(id)
    }

    private func closePanel(_ id: SurfaceID) {
        guard let panel = panels.removeValue(forKey: id) else { return }
        characterPanel.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// Beside the character, on whichever side has room, vertically centered on it
    private func place(_ panel: SurfacePanel) {
        let size = panel.frame.size
        let character = characterPanel.frame
        let visible = (characterPanel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let gap: CGFloat = 6
        let x = visible.maxX - character.maxX >= size.width + gap
            ? character.maxX + gap
            : character.minX - size.width - gap
        let y = character.midY - size.height / 2
        panel.setFrameOrigin(NSPoint(
            x: max(visible.minX + 4, min(x, visible.maxX - size.width - 4)),
            y: max(visible.minY + 4, min(y, visible.maxY - size.height - 4))
        ))
    }
}

/// A plugin's panel: borderless like the list panel, with a close button and Escape to close
private final class SurfacePanel: NSPanel {
    var onClose: (() -> Void)?
    private let hosting = NSHostingView(rootView: AnyView(EmptyView()))

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        hosting.sizingOptions = []
        contentView = hosting
    }

    // Borderless panels cannot become key by default, and then text fields cannot take input
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    /// Wraps the plugin's view in the panel's chrome and sizes the window to fit it
    func setContent(_ content: AnyView) {
        let view = AnyView(SurfacePanelChrome(content: content) { [weak self] in self?.onClose?() })
        hosting.rootView = view
        var size = NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: SurfacePanelChrome.maxWidth, height: 700))
        if size.width <= 1 || size.height <= 1 {
            size = CGSize(width: 300, height: 120)   // Last-resort fallback
        }
        setContentSize(size)
    }
}

struct SurfacePanelChrome: View {
    static let maxWidth: CGFloat = 360

    let content: AnyView
    let close: () -> Void
    @AppStorage(SettingsKeys.liquidGlass) private var liquidGlass = false

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .frame(minWidth: 240, maxWidth: Self.maxWidth, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .buddyBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(strings.s("surface.close"))
            }
            // Also reaches the plugin's content, e.g. A2UI buttons
            .environment(\.glassEnabled, liquidGlass && Appearance.supportsGlass)
    }
}
