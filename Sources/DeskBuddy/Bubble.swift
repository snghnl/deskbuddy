import AppKit
import SwiftUI

// MARK: - 말풍선 모양/뷰

/// 꼬리가 붙는 변 — 캐릭터가 있는 방향
enum TailEdge {
    case top        // 말풍선이 캐릭터 아래에 있을 때
    case bottom     // 말풍선이 캐릭터 위에 있을 때
    case leading    // 말풍선이 캐릭터 오른쪽에 있을 때
    case trailing   // 말풍선이 캐릭터 왼쪽에 있을 때
}

/// 지정한 변 가운데에 꼬리가 달린 말풍선 — 몸통과 꼬리를 하나의 연속된 외곽선으로 그려서
/// 채움/테두리에 경계선이 생기지 않는다
private struct BubbleShape: Shape {
    let tail: TailEdge
    /// 꼬리 끝의 위치 (top/bottom 이면 x 좌표, leading/trailing 이면 y 좌표). nil 이면 가운데.
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
        // 꼬리가 몸통 모서리를 침범하지 않게 클램프
        let midX = min(max(apex ?? rect.midX, body.minX + r + half), body.maxX - r - half)
        let midY = min(max(apex ?? rect.midY, body.minY + r + half), body.maxY - r - half)

        var p = Path()
        p.move(to: CGPoint(x: body.minX + r, y: body.minY))
        // 윗변 (왼쪽 → 오른쪽)
        if tail == .top {
            p.addLine(to: CGPoint(x: midX - half, y: body.minY))
            p.addLine(to: CGPoint(x: midX, y: rect.minY))
            p.addLine(to: CGPoint(x: midX + half, y: body.minY))
        }
        p.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY),
                 tangent2End: CGPoint(x: body.maxX, y: body.minY + r), radius: r)
        // 오른쪽 변 (위 → 아래)
        if tail == .trailing {
            p.addLine(to: CGPoint(x: body.maxX, y: midY - half))
            p.addLine(to: CGPoint(x: rect.maxX, y: midY))
            p.addLine(to: CGPoint(x: body.maxX, y: midY + half))
        }
        p.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY),
                 tangent2End: CGPoint(x: body.maxX - r, y: body.maxY), radius: r)
        // 아랫변 (오른쪽 → 왼쪽)
        if tail == .bottom {
            p.addLine(to: CGPoint(x: midX + half, y: body.maxY))
            p.addLine(to: CGPoint(x: midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: midX - half, y: body.maxY))
        }
        p.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        p.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY),
                 tangent2End: CGPoint(x: body.minX, y: body.maxY - r), radius: r)
        // 왼쪽 변 (아래 → 위)
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
    /// 꼬리 끝 위치 — 패널 좌표가 아니라 뷰(그림자 패딩 10 포함) 좌표 기준
    var apex: CGFloat?

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)   // 줄임표 없이 전체 내용 표시
            .padding(.leading, 14 + (tail == .leading ? 8 : 0))
            .padding(.trailing, 14 + (tail == .trailing ? 8 : 0))
            .padding(.top, 9 + (tail == .top ? 8 : 0))
            .padding(.bottom, 9 + (tail == .bottom ? 8 : 0))
            .frame(maxWidth: 230)
            .background(BubbleShape(tail: tail, apex: apexInShape).fill(.ultraThinMaterial))
            .overlay(BubbleShape(tail: tail, apex: apexInShape).stroke(.white.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            .padding(10)   // 그림자가 잘리지 않게 패널 안쪽 여백
    }

    /// apex 는 패널 전체 좌표 기준으로 들어오므로, 바깥 패딩(10)을 빼서 shape 좌표로 변환
    private var apexInShape: CGFloat? {
        apex.map { $0 - 10 }
    }
}

/// 클릭만 받는 캐처 (ClickCatcherView 와 달리 드래그로 창이 움직이지 않는다)
private final class TapCatcherView: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }
}

// MARK: - 말풍선 패널

/// 캐릭터 머리 위에 말풍선을 띄운다. 캐릭터 패널의 child window 라서 캐릭터를 끌면 같이 움직인다.
@MainActor
final class BubbleController {
    /// 말풍선을 클릭했을 때 (닫기 처리는 컨트롤러가 하고, 추가 동작만 위임)
    var onTap: (() -> Void)?
    /// 표시 상태가 바뀔 때 (캐릭터 표정 연동용)
    var onVisibleChange: ((Bool) -> Void)?

    private let panel: NSPanel
    private let hosting: NSHostingView<BubbleView>
    private weak var characterPanel: NSPanel?
    private var autoHideTask: Task<Void, Never>?
    /// 지금 표시 중이거나 보류(suspend)된 메시지 — 닫기 전까지 유지
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
        panel.hasShadow = false   // 말풍선이 자체 그림자를 그린다
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        hosting = NSHostingView(rootView: BubbleView(message: ""))
        // 크기는 show() 에서 sizeThatFits 로 직접 측정한다 — intrinsic 은 긴 텍스트에서 부정확
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
            size = CGSize(width: 220, height: 64)   // 마지막 안전망
        }
        return size
    }

    /// 말풍선 표시. autoHide 를 주면 그 시간 후 스스로 닫힌다 (없으면 클릭할 때까지 유지).
    /// 위치는 캐릭터 주변의 화면 공간에 따라 위 → 아래 → 좌/우 순으로 고른다.
    func show(_ message: String, autoHide: TimeInterval? = nil) {
        guard let characterPanel else { return }
        current = (message, autoHide)

        let charFrame = characterPanel.frame
        let visible = (characterPanel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let overlap: CGFloat = 6   // 꼬리 끝이 캐릭터에 살짝 겹치게

        // 캐릭터 사방의 여유 공간
        let spaceAbove = visible.maxY - charFrame.maxY
        let spaceBelow = charFrame.minY - visible.minY
        let spaceLeft = charFrame.minX - visible.minX
        let spaceRight = visible.maxX - charFrame.maxX

        // 배치 결정 (위 → 아래 → 넓은 쪽 옆). 측정 크기는 꼬리 방향에 따라 8pt 차이라 근사로 충분.
        let probe = measure(message, tail: .bottom)
        let tail: TailEdge
        if spaceAbove + overlap >= probe.height {
            tail = .bottom       // 캐릭터 위
        } else if spaceBelow + overlap >= probe.height {
            tail = .top          // 캐릭터 아래
        } else if spaceRight >= spaceLeft {
            tail = .leading      // 캐릭터 오른쪽
        } else {
            tail = .trailing     // 캐릭터 왼쪽
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

        // 꼬리 끝이 캐릭터 중심을 가리키게 (클램핑으로 말풍선이 밀렸을 때도)
        let apex: CGFloat
        switch tail {
        case .top, .bottom:
            apex = charFrame.midX - origin.x
        case .leading, .trailing:
            // AppKit(y 위로) → SwiftUI(y 아래로) 좌표 변환
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

    /// 완전히 닫기 (클릭·자동 닫힘) — 보류 메시지도 버린다
    func hide() {
        current = nil
        dismissPanel()
    }

    /// 잠시 접기 (던져지는 동안 등) — 메시지는 유지했다가 resume 에서 되살린다
    func suspend() {
        guard panel.isVisible else { return }
        dismissPanel()
    }

    /// 보류된 메시지가 있으면 현재 캐릭터 위치 기준으로 다시 띄운다
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

// MARK: - 일정 알림 감시

/// 30초마다 오늘 일정을 검사해 시작 전 설정된 리드타임에 한 번씩 알린다
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
            onNotify?("🕐 \(minutes)분 후 · \(event.title)")
        }
    }
}
