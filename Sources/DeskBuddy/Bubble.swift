import AppKit
import DeskBuddyCore
import SwiftUI

// MARK: - Bubble Shape/View

/// The edge the tail attaches to — the side the character is on
enum TailEdge {
    case top        // Bubble is below the character
    case bottom     // Bubble is above the character
    case leading    // Bubble is to the right of the character
    case trailing   // Bubble is to the left of the character
}

/// Speech bubble with a tail at the middle of the given edge — body and tail are drawn
/// as one continuous outline so no seam appears in the fill/stroke
private struct BubbleShape: Shape {
    let tail: TailEdge
    /// Position of the tail tip (x coordinate for top/bottom, y coordinate for leading/trailing). nil means centered.
    var apex: CGFloat?

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 12
        let tailHeight: CGFloat = 8
        let half: CGFloat = 7

        var body = rect
        switch tail {
        case .bottom: body.size.height -= tailHeight
        case .top: body.origin.y += tailHeight; body.size.height -= tailHeight
        case .trailing: body.size.width -= tailHeight
        case .leading: body.origin.x += tailHeight; body.size.width -= tailHeight
        }
        // Clamp so the tail does not intrude into the body's rounded corners
        let midX = min(max(apex ?? rect.midX, body.minX + r + half), body.maxX - r - half)
        let midY = min(max(apex ?? rect.midY, body.minY + r + half), body.maxY - r - half)

        var p = Path()
        p.move(to: CGPoint(x: body.minX + r, y: body.minY))
        // Top edge (left → right)
        if tail == .top {
            p.addLine(to: CGPoint(x: midX - half, y: body.minY))
            p.addLine(to: CGPoint(x: midX, y: rect.minY))
            p.addLine(to: CGPoint(x: midX + half, y: body.minY))
        }
        p.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY),
                 tangent2End: CGPoint(x: body.maxX, y: body.minY + r), radius: r)
        // Right edge (top → bottom)
        if tail == .trailing {
            p.addLine(to: CGPoint(x: body.maxX, y: midY - half))
            p.addLine(to: CGPoint(x: rect.maxX, y: midY))
            p.addLine(to: CGPoint(x: body.maxX, y: midY + half))
        }
        p.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY),
                 tangent2End: CGPoint(x: body.maxX - r, y: body.maxY), radius: r)
        // Bottom edge (right → left)
        if tail == .bottom {
            p.addLine(to: CGPoint(x: midX + half, y: body.maxY))
            p.addLine(to: CGPoint(x: midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: midX - half, y: body.maxY))
        }
        p.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        p.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY),
                 tangent2End: CGPoint(x: body.minX, y: body.maxY - r), radius: r)
        // Left edge (bottom → top)
        if tail == .leading {
            p.addLine(to: CGPoint(x: body.minX, y: midY + half))
            p.addLine(to: CGPoint(x: rect.minX, y: midY))
            p.addLine(to: CGPoint(x: body.minX, y: midY - half))
        }
        p.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        p.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY),
                 tangent2End: CGPoint(x: body.minX + r, y: body.minY), radius: r)
        p.closeSubpath()
        return p
    }
}

struct BubbleView: View {
    let message: String
    var tail: TailEdge = .bottom
    /// Tail tip position — in view coordinates (including the 10pt shadow padding), not panel coordinates
    var apex: CGFloat?
    @AppStorage(SettingsKeys.liquidGlass) private var liquidGlass = false

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)   // Show the full content without truncation
            .padding(.leading, 14 + (tail == .leading ? 8 : 0))
            .padding(.trailing, 14 + (tail == .trailing ? 8 : 0))
            .padding(.top, 9 + (tail == .top ? 8 : 0))
            .padding(.bottom, 9 + (tail == .bottom ? 8 : 0))
            .frame(maxWidth: 230)
            .modifier(BubbleBackground(shape: BubbleShape(tail: tail, apex: apexInShape), glass: liquidGlass))
            .padding(10)   // Inner padding so the shadow is not clipped by the panel
    }

    /// apex comes in panel-wide coordinates, so subtract the outer padding (10) to convert to shape coordinates
    private var apexInShape: CGFloat? {
        apex.map { $0 - 10 }
    }
}

/// Catcher that only accepts clicks (unlike ClickCatcherView, dragging does not move the window)
private final class TapCatcherView: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }
}

// MARK: - Bubble Panel

/// Shows a speech bubble above the character's head. It is a child window of the character panel, so it moves along when the character is dragged.
@MainActor
final class BubbleController {
    /// Called when visibility changes (used to sync the character's expression)
    var onVisibleChange: ((Bool) -> Void)?

    private let panel: NSPanel
    private let hosting: NSHostingView<BubbleView>
    private weak var characterPanel: NSPanel?
    private var autoHideTask: Task<Void, Never>?
    /// The message currently showing or suspended — kept until dismissed
    private var current: Message?

    private struct Message {
        let id: UUID
        var text: String
        let autoHide: TimeInterval?
        let onTap: (() -> Void)?
        let onGone: (() -> Void)?
    }

    init(characterPanel: NSPanel) {
        self.characterPanel = characterPanel

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false   // The bubble draws its own shadow
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        hosting = NSHostingView(rootView: BubbleView(message: ""))
        // Size is measured directly with sizeThatFits in show() — intrinsic sizing is inaccurate for long text
        hosting.sizingOptions = []

        let container = NSView()
        let catcher = TapCatcherView()
        for view in [hosting, catcher] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        }
        catcher.onClick = { [weak self] in
            guard let self, let clicked = current else { return }
            current = nil
            dismissPanel()
            // The click is reported before the message is gone, so whoever showed it can tell
            // a click from a timeout
            clicked.onTap?()
            clicked.onGone?()
        }
        panel.contentView = container
    }

    var isVisible: Bool { panel.isVisible }

    private func measure(_ message: String, tail: TailEdge) -> CGSize {
        var size = NSHostingController(rootView: BubbleView(message: message, tail: tail))
            .sizeThatFits(in: CGSize(width: 280, height: 600))
        if size.width <= 1 || size.height <= 1 {
            size = CGSize(width: 220, height: 64)   // Last-resort fallback
        }
        return size
    }

    /// Shows the bubble, taking the place of whatever it said before. With autoHide it closes
    /// itself after that interval (otherwise it stays until clicked). `onTap` runs when this
    /// message is clicked; `onGone` once it leaves for any reason — clicked, timed out, hidden,
    /// or replaced by a newer message. Returns the message's id, to change or hide it later.
    @discardableResult
    func show(_ message: String, autoHide: TimeInterval? = nil,
              onTap: (() -> Void)? = nil, onGone: (() -> Void)? = nil) -> UUID {
        let shown = Message(id: UUID(), text: message, autoHide: autoHide, onTap: onTap, onGone: onGone)
        guard characterPanel != nil else { return shown.id }
        let replaced = current
        current = shown
        present(shown)
        replaced?.onGone?()
        return shown.id
    }

    /// Lays the message out and starts its auto-hide countdown afresh
    private func present(_ message: Message) {
        layout(message.text)
        autoHideTask?.cancel()
        if let autoHide = message.autoHide {
            autoHideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(autoHide))
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    /// Places and displays the message — leaves the auto-hide timer alone.
    /// Placement is chosen from the screen space around the character, in the order above → below → left/right.
    private func layout(_ message: String) {
        guard let characterPanel else { return }

        let charFrame = characterPanel.frame
        let visible = (characterPanel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let overlap: CGFloat = 6   // Let the tail tip slightly overlap the character

        // Free space on each side of the character
        let spaceAbove = visible.maxY - charFrame.maxY
        let spaceBelow = charFrame.minY - visible.minY
        let spaceLeft = charFrame.minX - visible.minX
        let spaceRight = visible.maxX - charFrame.maxX

        // Decide placement (above → below → whichever side is wider). Measured size only differs by 8pt across tail directions, so an approximation is enough.
        let probe = measure(message, tail: .bottom)
        let tail: TailEdge
        if spaceAbove + overlap >= probe.height {
            tail = .bottom       // Above the character
        } else if spaceBelow + overlap >= probe.height {
            tail = .top          // Below the character
        } else if spaceRight >= spaceLeft {
            tail = .leading      // To the right of the character
        } else {
            tail = .trailing     // To the left of the character
        }

        let size = tail == .bottom ? probe : measure(message, tail: tail)

        func clampX(_ x: CGFloat) -> CGFloat {
            max(visible.minX + 4, min(x, visible.maxX - size.width - 4))
        }
        func clampY(_ y: CGFloat) -> CGFloat {
            max(visible.minY + 4, min(y, visible.maxY - size.height - 4))
        }

        let origin: NSPoint
        switch tail {
        case .bottom:
            origin = NSPoint(x: clampX(charFrame.midX - size.width / 2),
                             y: charFrame.maxY - overlap)
        case .top:
            origin = NSPoint(x: clampX(charFrame.midX - size.width / 2),
                             y: charFrame.minY - size.height + overlap)
        case .leading:
            origin = NSPoint(x: charFrame.maxX - overlap,
                             y: clampY(charFrame.midY - size.height / 2))
        case .trailing:
            origin = NSPoint(x: charFrame.minX - size.width + overlap,
                             y: clampY(charFrame.midY - size.height / 2))
        }

        // Point the tail tip at the character's center (even when clamping shifted the bubble)
        let apex: CGFloat
        switch tail {
        case .top, .bottom:
            apex = charFrame.midX - origin.x
        case .leading, .trailing:
            // Convert AppKit (y up) → SwiftUI (y down) coordinates
            apex = (origin.y + size.height) - charFrame.midY
        }
        hosting.rootView = BubbleView(message: message, tail: tail, apex: apex)

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.parent == nil {
            characterPanel.addChildWindow(panel, ordered: .above)
        }
        panel.orderFrontRegardless()
        onVisibleChange?(true)
    }

    /// Changes the text of message `id` in place — no-op once it is gone. The auto-hide
    /// countdown keeps running, so a ticking message still closes on schedule.
    func replace(_ id: UUID, with text: String) {
        guard current?.id == id else { return }
        current?.text = text
        if panel.isVisible { layout(text) }
    }

    /// Hides message `id` if it is still the one showing (or suspended); a newer message stays
    func hide(_ id: UUID) {
        guard current?.id == id else { return }
        hide()
    }

    /// Fully dismiss (auto-hide, or someone hiding it) — discards any suspended message too
    func hide() {
        let gone = current
        current = nil
        dismissPanel()
        gone?.onGone?()
    }

    /// Fold away temporarily (e.g. while being thrown) — the message is kept and restored in resume
    func suspend() {
        guard panel.isVisible else { return }
        dismissPanel()
    }

    /// If there is a suspended message, shows it again relative to the character's current position
    func resume() {
        if let current {
            present(current)
        }
    }

    private func dismissPanel() {
        autoHideTask?.cancel()
        autoHideTask = nil
        guard panel.isVisible else { return }
        characterPanel?.removeChildWindow(panel)
        panel.orderOut(nil)
        onVisibleChange?(false)
    }
}

/// The bubble's fill: Liquid Glass in the bubble's own shape, tail included, or frosted
/// material with an edge and a drop shadow
private struct BubbleBackground: ViewModifier {
    let shape: BubbleShape
    let glass: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *), glass {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(shape.fill(.ultraThinMaterial))
                .overlay(shape.stroke(.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
    }
}
