import SwiftUI

/// 화면에 떠 있는 슬라임 캐릭터. 클릭/드래그 이벤트는 패널(윈도우)이 직접 처리하므로
/// 이 뷰는 순수하게 그리기만 한다.
struct CharacterView: View {
    @ObservedObject var store: TodoStore
    /// 리스트 패널이 열려있는지 — 열리면 캐릭터가 살짝 신난 표정이 된다
    @ObservedObject var appState: AppState

    @State private var blinking = false

    private var remaining: Int { store.todos.filter { !$0.isDone }.count }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 걸을 때는 빠르게 통통 튀고, 쉴 때는 느리게 둥실거린다
            TimelineView(.animation(minimumInterval: appState.walking ? 1.0 / 60.0 : 1.0 / 20.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = sin(t * (appState.walking ? 7.0 : 1.9))
                slime
                    .rotationEffect(.degrees(appState.walking ? phase * 7 : 0))
                    .offset(y: -phase * (appState.walking ? 5 : 3))
                    .scaleEffect(x: appState.facingRight ? 1 : -1)   // 진행 방향으로 몸을 돌린다
            }

            if remaining > 0 {
                Text("\(remaining)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.red.gradient))
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: 76, height: 84)
        .task { await blinkLoop() }
    }

    private var slime: some View {
        ZStack {
            // 바닥 그림자
            Ellipse()
                .fill(.black.opacity(0.18))
                .frame(width: 44, height: 8)
                .offset(y: 30)
                .blur(radius: 2)

            // 몸통
            SlimeShape()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.55, green: 0.87, blue: 0.68),
                                 Color(red: 0.28, green: 0.71, blue: 0.52)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    // 하이라이트
                    Ellipse()
                        .fill(.white.opacity(0.45))
                        .frame(width: 14, height: 8)
                        .rotationEffect(.degrees(-20))
                        .offset(x: -13, y: -16)
                )
                .frame(width: 58, height: 52)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

            // 눈
            HStack(spacing: 14) {
                eye
                eye
            }
            .offset(y: -4)

            // 볼터치
            HStack(spacing: 34) {
                cheek
                cheek
            }
            .offset(y: 4)

            // 입 — 리스트가 열려있으면 벌린 웃음, 평소엔 미소
            if appState.listVisible {
                Ellipse()
                    .fill(Color(red: 0.55, green: 0.28, blue: 0.25))
                    .frame(width: 10, height: 7)
                    .offset(y: 7)
            } else {
                SmileShape()
                    .stroke(Color(red: 0.2, green: 0.42, blue: 0.3), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: 12, height: 5)
                    .offset(y: 6)
            }
        }
    }

    private var eye: some View {
        Capsule()
            .fill(Color(red: 0.13, green: 0.3, blue: 0.2))
            .frame(width: 6, height: blinking ? 1.5 : 9)
            .animation(.easeOut(duration: 0.08), value: blinking)
    }

    private var cheek: some View {
        Ellipse()
            .fill(.pink.opacity(0.45))
            .frame(width: 7, height: 4)
    }

    private func blinkLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(.random(in: 2.0...4.5)))
            blinking = true
            try? await Task.sleep(for: .milliseconds(120))
            blinking = false
        }
    }
}

/// 아래가 살짝 퍼진 물방울형 슬라임 몸통
private struct SlimeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.5, y: 0))
        p.addCurve(to: CGPoint(x: w, y: h * 0.72),
                   control1: CGPoint(x: w * 0.92, y: 0),
                   control2: CGPoint(x: w, y: h * 0.38))
        p.addCurve(to: CGPoint(x: w * 0.5, y: h),
                   control1: CGPoint(x: w, y: h * 0.95),
                   control2: CGPoint(x: w * 0.78, y: h))
        p.addCurve(to: CGPoint(x: 0, y: h * 0.72),
                   control1: CGPoint(x: w * 0.22, y: h),
                   control2: CGPoint(x: 0, y: h * 0.95))
        p.addCurve(to: CGPoint(x: w * 0.5, y: 0),
                   control1: CGPoint(x: 0, y: h * 0.38),
                   control2: CGPoint(x: w * 0.08, y: 0))
        p.closeSubpath()
        return p
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: rect.width, y: 0),
                       control: CGPoint(x: rect.width / 2, y: rect.height * 2))
        return p
    }
}

/// 패널 간 공유되는 UI 상태
@MainActor
final class AppState: ObservableObject {
    @Published var listVisible = false
    /// 자유 이동 중 걷고 있는지
    @Published var walking = false
    /// 바라보는 방향
    @Published var facingRight = true
}
