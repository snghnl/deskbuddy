import AppKit
import QuartzCore

/// Makes the character wander around the screen on its own.
/// Repeatedly picks a random target, walks there, rests briefly, then picks a new target.
@MainActor
final class WanderController {
    /// Walking speed (pt/s)
    private let speed: CGFloat = 72

    private weak var panel: NSPanel?
    /// (isWalking, isFacingRight) — called only when the state changes
    private let onWalk: (Bool, Bool) -> Void
    /// Called when the character reaches the target and settles (for saving the position)
    private let onSettled: () -> Void

    private var task: Task<Void, Never>?
    private var target: NSPoint?
    private var resting: CFTimeInterval = 0
    private var walking = false
    private var facingRight = true

    init(
        panel: NSPanel,
        onWalk: @escaping (Bool, Bool) -> Void,
        onSettled: @escaping () -> Void
    ) {
        self.panel = panel
        self.onWalk = onWalk
        self.onSettled = onSettled
    }

    var isRunning: Bool { task != nil }

    func start() {
        guard task == nil else { return }
        target = nil
        resting = .random(in: 0.3...1.2)   // Pause briefly so it doesn't dart off the moment it starts
        task = Task { [weak self] in
            var last = CACurrentMediaTime()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self else { return }
                let now = CACurrentMediaTime()
                self.step(dt: min(now - last, 0.1))   // Cap dt so the character doesn't teleport when the app stalls and wakes up
                last = now
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        target = nil
        setWalking(false)
    }

    // MARK: - Single Frame

    private func step(dt: CFTimeInterval) {
        guard let panel, panel.isVisible else { return }

        if resting > 0 {
            resting -= dt
            setWalking(false)
            return
        }

        let bounds = wanderBounds(for: panel)
        guard bounds.width > 0, bounds.height > 0 else { return }

        let origin = panel.frame.origin
        guard let target else {
            self.target = randomTarget(in: bounds, from: origin)
            return
        }

        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let distance = hypot(dx, dy)

        if distance < 1.5 {
            panel.setFrameOrigin(target)
            self.target = nil
            resting = .random(in: 0.9...3.5)
            setWalking(false)
            onSettled()
            return
        }

        let stride = min(speed * dt, distance)
        panel.setFrameOrigin(NSPoint(
            x: origin.x + dx / distance * stride,
            y: origin.y + dy / distance * stride
        ))
        if abs(dx) > 0.5 { facingRight = dx > 0 }
        setWalking(true)
    }

    private func setWalking(_ value: Bool) {
        guard walking != value else { return }
        walking = value
        onWalk(value, facingRight)
    }

    // MARK: - Target Point

    /// Valid range of origins that keep the panel from leaving the screen
    private func wanderBounds(for panel: NSPanel) -> CGRect {
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let size = panel.frame.size
        return CGRect(
            x: visible.minX,
            y: visible.minY,
            width: max(visible.width - size.width, 0),
            height: max(visible.height - size.height, 0)
        )
    }

    /// Picks a point that is not too close to the current position
    private func randomTarget(in bounds: CGRect, from current: NSPoint) -> NSPoint {
        var candidate = current
        for _ in 0..<8 {
            candidate = NSPoint(
                x: .random(in: bounds.minX...bounds.maxX),
                y: .random(in: bounds.minY...bounds.maxY)
            )
            if hypot(candidate.x - current.x, candidate.y - current.y) > 120 { break }
        }
        return candidate
    }
}
