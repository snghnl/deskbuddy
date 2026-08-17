import AppKit
import SwiftUI

// MARK: - 말풍선 모양/뷰

/// 아래 가운데에 꼬리가 달린 말풍선 — 몸통과 꼬리를 하나의 연속된 외곽선으로 그려서
/// 채움/테두리에 경계선이 생기지 않는다
private struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 12
        let tailHeight: CGFloat = 8
        let tailHalf: CGFloat = 7
        let body = CGRect(x: rect.minX, y: rect.minY,
                          width: rect.width, height: rect.height - tailHeight)
        let mid = rect.midX

        var p = Path()
        p.move(to: CGPoint(x: body.minX + r, y: body.minY))
        p.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY),
                 tangent2End: CGPoint(x: body.maxX, y: body.minY + r), radius: r)
        p.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY),
                 tangent2End: CGPoint(x: body.maxX - r, y: body.maxY), radius: r)
        // 꼬리 (오른쪽 → 끝점 → 왼쪽)
        p.addLine(to: CGPoint(x: mid + tailHalf, y: body.maxY))
        p.addLine(to: CGPoint(x: mid, y: rect.maxY))
        p.addLine(to: CGPoint(x: mid - tailHalf, y: body.maxY))
        p.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        p.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY),
                 tangent2End: CGPoint(x: body.minX, y: body.maxY - r), radius: r)
        p.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        p.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY),
                 tangent2End: CGPoint(x: body.minX + r, y: body.minY), radius: r)
        p.closeSubpath()
        return p
    }
}

struct BubbleView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)   // 줄임표 없이 전체 내용 표시
            .padding(.horizontal, 14)
            .padding(.top, 9)
            .padding(.bottom, 9 + 8)   // 꼬리 높이만큼 여유
            .frame(maxWidth: 230)
            .background(BubbleShape().fill(.ultraThinMaterial))
            .overlay(BubbleShape().stroke(.white.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            .padding(10)   // 그림자가 잘리지 않게 패널 안쪽 여백
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
        // 말풍선 크기는 SwiftUI 콘텐츠의 intrinsic size 로 정한다
        hosting.sizingOptions = [.intrinsicContentSize]

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

    /// 말풍선 표시. autoHide 를 주면 그 시간 후 스스로 닫힌다 (없으면 클릭할 때까지 유지).
    func show(_ message: String, autoHide: TimeInterval? = nil) {
        guard let characterPanel else { return }

        hosting.rootView = BubbleView(message: message)
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.intrinsicContentSize
        if size.width <= 1 || size.height <= 1 {
            size = hosting.fittingSize
        }
        if size.width <= 1 || size.height <= 1 {
            size = CGSize(width: 220, height: 64)   // 마지막 안전망
        }
        let charFrame = characterPanel.frame
        let visible = (characterPanel.screen ?? NSScreen.main)?.visibleFrame ?? .zero

        // 캐릭터 머리 위, 꼬리가 캐릭터 중심을 향하도록 가운데 정렬 (화면 밖으로는 안 나가게)
        var x = charFrame.midX - size.width / 2
        x = max(visible.minX + 4, min(x, visible.maxX - size.width - 4))
        let y = min(charFrame.maxY - 6, visible.maxY - size.height)

        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
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

    func hide() {
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
