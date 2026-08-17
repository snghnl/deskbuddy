import AppKit
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
            .background(BubbleShape(tail: tail, apex: apexInShape).fill(.ultraThinMaterial))
            .overlay(BubbleShape(tail: tail, apex: apexInShape).stroke(.white.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
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
    /// Called when the bubble is clicked (the controller handles dismissal; only extra behavior is delegated)
    var onTap: (() -> Void)?
    /// Called when visibility changes (used to sync the character's expression)
    var onVisibleChange: ((Bool) -> Void)?

    private let panel: NSPanel
    private let hosting: NSHostingView<BubbleView>
    private weak var characterPanel: NSPanel?
    private var autoHideTask: Task<Void, Never>?
    /// The message currently showing or suspended — kept until dismissed
    private var current: (message: String, autoHide: TimeInterval?)?

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
            self?.hide()
            self?.onTap?()
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

    /// Shows the bubble. With autoHide it closes itself after that interval (otherwise it stays until clicked).
    /// Placement is chosen from the screen space around the character, in the order above → below → left/right.
    func show(_ message: String, autoHide: TimeInterval? = nil) {
        guard let characterPanel else { return }
        current = (message, autoHide)

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

        autoHideTask?.cancel()
        if let autoHide {
            autoHideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(autoHide))
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    /// Fully dismiss (click or auto-hide) — discards any suspended message too
    func hide() {
        current = nil
        dismissPanel()
    }

    /// Fold away temporarily (e.g. while being thrown) — the message is kept and restored in resume
    func suspend() {
        guard panel.isVisible else { return }
        dismissPanel()
    }

    /// If there is a suspended message, shows it again relative to the character's current position
    func resume() {
        if let current {
            show(current.message, autoHide: current.autoHide)
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

// MARK: - Event Alert Watcher

/// Checks today's events every 30 seconds and notifies once per event at the configured lead time before it starts
@MainActor
final class EventNotifier {
    var onNotify: ((String) -> Void)?

    private let calendar: CalendarService
    private var task: Task<Void, Never>?
    private var notifiedIDs: Set<String> = []

    init(calendar: CalendarService) {
        self.calendar = calendar
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func tick() {
        let defaults = UserDefaults.standard
        guard calendar.access == .authorized,
              defaults.bool(forKey: SettingsKeys.eventAlerts) else { return }
        let leadMinutes = max(1, defaults.integer(forKey: SettingsKeys.eventAlertLead))

        let now = Date()
        for event in calendar.events(on: now) where !event.isAllDay {
            let seconds = event.start.timeIntervalSince(now)
            guard seconds > 0, seconds <= Double(leadMinutes) * 60,
                  !notifiedIDs.contains(event.id) else { continue }
            notifiedIDs.insert(event.id)
            let minutes = max(1, Int(seconds / 60))
            onNotify?(L.t("🕐 \(minutes)분 후 · \(event.title)", "🕐 In \(minutes) min · \(event.title)"))
        }
    }
}
