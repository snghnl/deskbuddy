import AppKit
import QuartzCore

/// Physics simulation for when the character is thrown.
/// Takes the velocity at the moment of release, drops it under gravity, bounces it off the screen edges, and stops it on the floor.
@MainActor
final class ThrowController {
    private let gravity: CGFloat = -1700        // pt/s²
    private let restitution: CGFloat = 0.62     // Bounce coefficient for walls, ceiling, and floor
    private let floorFriction: CGFloat = 0.82   // Horizontal velocity damping on each floor contact
    private let maxFlight: CFTimeInterval = 6   // Safety net — stops in place once this much time passes

    private weak var panel: NSPanel?
    private let onFlight: (Bool) -> Void
    private let onSettled: () -> Void

    private var task: Task<Void, Never>?
    private var velocity = CGVector.zero
    private var elapsed: CFTimeInterval = 0

    init(panel: NSPanel, onFlight: @escaping (Bool) -> Void, onSettled: @escaping () -> Void) {
        self.panel = panel
        self.onFlight = onFlight
        self.onSettled = onSettled
    }

    var isFlying: Bool { task != nil }

    func throwPanel(with velocity: CGVector) {
        self.velocity = velocity
        elapsed = 0
        guard task == nil else { return }   // Already flying — just update the velocity
        onFlight(true)
        task = Task { [weak self] in
            var last = CACurrentMediaTime()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(8))
                guard let self else { return }
                let now = CACurrentMediaTime()
                self.step(dt: min(now - last, 0.05))
                last = now
            }
        }
    }

    /// Stops in place when grabbed mid-flight (drag start) or when circumstances change
    func cancel() {
        guard task != nil else { return }
        task?.cancel()
        task = nil
        onFlight(false)
    }

    private func settle() {
        cancel()
        onSettled()
    }

    private func step(dt: CFTimeInterval) {
        guard let panel else { return }
        elapsed += dt
        if elapsed > maxFlight { settle(); return }

        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let size = panel.frame.size
        let minX = visible.minX
        let maxX = visible.maxX - size.width
        let minY = visible.minY
        let maxY = visible.maxY - size.height

        velocity.dy += gravity * CGFloat(dt)
        var p = panel.frame.origin
        p.x += velocity.dx * CGFloat(dt)
        p.y += velocity.dy * CGFloat(dt)

        // Side walls
        if p.x < minX { p.x = minX; velocity.dx = -velocity.dx * restitution }
        if p.x > maxX { p.x = maxX; velocity.dx = -velocity.dx * restitution }
        // Ceiling
        if p.y > maxY { p.y = maxY; velocity.dy = -velocity.dy * restitution }
        // Floor
        if p.y < minY {
            p.y = minY
            if abs(velocity.dy) < 90 {
                // Stop bouncing; slide to a halt instead
                velocity.dy = 0
                velocity.dx *= pow(0.02, CGFloat(dt))
                if abs(velocity.dx) < 12 {
                    panel.setFrameOrigin(p)
                    settle()
                    return
                }
            } else {
                velocity.dy = -velocity.dy * restitution
                velocity.dx *= floorFriction
            }
        }

        panel.setFrameOrigin(p)
    }
}
