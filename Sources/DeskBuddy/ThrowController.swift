import AppKit
import QuartzCore

/// 캐릭터를 던졌을 때의 물리 시뮬레이션.
/// 놓는 순간의 속도를 받아 중력으로 떨어뜨리고, 화면 가장자리에 튕기다가 바닥에서 멈춘다.
@MainActor
final class ThrowController {
    private let gravity: CGFloat = -1700        // pt/s²
    private let restitution: CGFloat = 0.62     // 벽·천장·바닥 반발 계수
    private let floorFriction: CGFloat = 0.82   // 바닥에 닿을 때마다 수평 속도 감쇠
    private let maxFlight: CFTimeInterval = 6   // 안전장치 — 이 시간이 지나면 그 자리에서 멈춘다

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
        guard task == nil else { return }   // 이미 날고 있으면 속도만 갱신
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

    /// 날아가는 도중 잡아채거나(드래그 시작) 상황이 바뀌면 그 자리에서 멈춘다
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

        // 좌우 벽
        if p.x < minX { p.x = minX; velocity.dx = -velocity.dx * restitution }
        if p.x > maxX { p.x = maxX; velocity.dx = -velocity.dx * restitution }
        // 천장
        if p.y > maxY { p.y = maxY; velocity.dy = -velocity.dy * restitution }
        // 바닥
        if p.y < minY {
            p.y = minY
            if abs(velocity.dy) < 90 {
                // 더 튀지 않고 미끄러지다 멈춘다
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
