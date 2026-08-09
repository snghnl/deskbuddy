import AppKit
import QuartzCore

/// 캐릭터가 화면 안을 스스로 돌아다니게 한다.
/// 목표 지점을 무작위로 골라 걸어간 뒤 잠깐 쉬고, 다시 새 목표를 고르는 것을 반복한다.
@MainActor
final class WanderController {
    /// 걷는 속도 (pt/s)
    private let speed: CGFloat = 72

    private weak var panel: NSPanel?
    /// (걷는 중인지, 오른쪽을 향하는지) — 상태가 바뀔 때만 호출된다
    private let onWalk: (Bool, Bool) -> Void
    /// 목표 지점에 도착해 자리를 잡았을 때 (위치 저장용)
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
        resting = .random(in: 0.3...1.2)   // 시작하자마자 튀어나가지 않도록 잠깐 뜸을 들인다
        task = Task { [weak self] in
            var last = CACurrentMediaTime()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self else { return }
                let now = CACurrentMediaTime()
                self.step(dt: min(now - last, 0.1))   // 앱이 멈췄다 깨어나도 순간이동하지 않게 상한
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

    // MARK: - 한 프레임

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

    // MARK: - 목표 지점

    /// 패널이 화면 밖으로 나가지 않는 origin 의 유효 범위
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

    /// 현재 위치에서 너무 가깝지 않은 지점을 고른다
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
