import SwiftUI

// MARK: - 캐릭터 종류

enum CharacterKind: String, CaseIterable, Identifiable {
    case slime, ghost, cat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .slime: "슬라임"
        case .ghost: "유령"
        case .cat: "고양이"
        }
    }
}

enum MouthState {
    case smile      // 평소
    case open       // 목록이 열려 신남
    case surprised  // 던져져서 날아가는 중
}

// MARK: - 플로팅 캐릭터

/// 화면에 떠 있는 캐릭터. 클릭/드래그 이벤트는 패널(윈도우)이 직접 처리하므로
/// 이 뷰는 순수하게 그리기만 한다.
struct CharacterView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var appState: AppState

    @AppStorage(SettingsKeys.character) private var characterRaw = CharacterKind.slime.rawValue
    @State private var blinking = false

    private var choice: CharacterChoice { .parse(characterRaw) }
    private var remaining: Int { store.todos.filter { !$0.isDone }.count }

    private var mouth: MouthState {
        if appState.flying { .surprised } else if appState.listVisible { .open } else { .smile }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 날 때는 빙글빙글 돌고, 걸을 때는 빠르게 통통 튀고, 쉴 때는 느리게 둥실거린다
            let animated = appState.walking || appState.flying
            TimelineView(.animation(minimumInterval: animated ? 1.0 / 60.0 : 1.0 / 20.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = sin(t * (appState.walking ? 7.0 : 1.9))
                let spin = (t * 620).truncatingRemainder(dividingBy: 360)
                CharacterBody(choice: choice, blinking: blinking, mouth: mouth)
                    .rotationEffect(.degrees(
                        appState.flying ? spin : (appState.walking ? phase * 7 : 0)
                    ))
                    .offset(y: appState.flying ? 0 : -phase * (appState.walking ? 5 : 3))
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

    private func blinkLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(.random(in: 2.0...4.5)))
            blinking = true
            try? await Task.sleep(for: .milliseconds(120))
            blinking = false
        }
    }
}

// MARK: - 캐릭터 몸통 (설정 미리보기에서도 재사용)

/// 76x84 캔버스 기준으로 그린다. 다른 크기가 필요하면 scaleEffect 로 줄인다.
struct CharacterBody: View {
    let choice: CharacterChoice
    var blinking = false
    var mouth: MouthState = .smile

    init(choice: CharacterChoice, blinking: Bool = false, mouth: MouthState = .smile) {
        self.choice = choice
        self.blinking = blinking
        self.mouth = mouth
    }

    init(kind: CharacterKind, blinking: Bool = false, mouth: MouthState = .smile) {
        self.init(choice: .builtin(kind), blinking: blinking, mouth: mouth)
    }

    var body: some View {
        ZStack {
            // 바닥 그림자
            Ellipse()
                .fill(.black.opacity(0.18))
                .frame(width: 44, height: 8)
                .offset(y: 30)
                .blur(radius: 2)

            switch choice {
            case .builtin(let kind):
                builtinBody(kind)
                face(kind)
            case .custom(let name):
                customBody(name)
            }
        }
    }

    @ViewBuilder
    private func builtinBody(_ kind: CharacterKind) -> some View {
        switch kind {
        case .slime: slimeBody
        case .ghost: ghostBody
        case .cat: catBody
        }
    }

    /// 사용자 이미지 — 표정 없이 몸통만. 파일이 사라졌으면 슬라임으로 대체한다.
    @ViewBuilder
    private func customBody(_ name: String) -> some View {
        if let image = CharacterImageCache.image(name) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 58, height: 58)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        } else {
            slimeBody
            face(.slime)
        }
    }

    // MARK: 몸통

    private var slimeBody: some View {
        SlimeShape()
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.55, green: 0.87, blue: 0.68),
                             Color(red: 0.28, green: 0.71, blue: 0.52)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(highlight)
            .frame(width: 58, height: 52)
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private var ghostBody: some View {
        GhostShape()
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.99, green: 0.99, blue: 1.0),
                             Color(red: 0.82, green: 0.82, blue: 0.95)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(highlight)
            .frame(width: 56, height: 58)
            .offset(y: -2)
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }

    private var catBody: some View {
        ZStack {
            // 귀 (머리 뒤에 깔린다)
            HStack(spacing: 26) {
                ear
                ear.scaleEffect(x: -1)
            }
            .offset(y: -24)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.98, green: 0.75, blue: 0.42),
                                 Color(red: 0.9, green: 0.58, blue: 0.25)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(highlight)
                .frame(width: 58, height: 50)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
    }

    private var ear: some View {
        ZStack {
            TriangleShape()
                .fill(Color(red: 0.88, green: 0.55, blue: 0.24))
                .frame(width: 17, height: 15)
            TriangleShape()
                .fill(Color(red: 0.98, green: 0.68, blue: 0.62))
                .frame(width: 8, height: 7)
                .offset(y: 4)
        }
    }

    private var highlight: some View {
        Ellipse()
            .fill(.white.opacity(0.45))
            .frame(width: 14, height: 8)
            .rotationEffect(.degrees(-20))
            .offset(x: -13, y: -16)
    }

    // MARK: 얼굴

    private func eyeColor(_ kind: CharacterKind) -> Color {
        switch kind {
        case .slime: Color(red: 0.13, green: 0.3, blue: 0.2)
        case .ghost: Color(red: 0.25, green: 0.25, blue: 0.38)
        case .cat: Color(red: 0.28, green: 0.17, blue: 0.1)
        }
    }

    private func mouthColor(_ kind: CharacterKind) -> Color {
        switch kind {
        case .slime: Color(red: 0.2, green: 0.42, blue: 0.3)
        case .ghost: Color(red: 0.35, green: 0.35, blue: 0.5)
        case .cat: Color(red: 0.4, green: 0.25, blue: 0.15)
        }
    }

    private func face(_ kind: CharacterKind) -> some View {
        ZStack {
            HStack(spacing: 14) {
                eye(kind)
                eye(kind)
            }
            .offset(y: -4)

            HStack(spacing: 34) {
                cheek
                cheek
            }
            .offset(y: 4)

            mouthView(kind)
        }
    }

    private func eye(_ kind: CharacterKind) -> some View {
        Capsule()
            .fill(eyeColor(kind))
            .frame(width: 6, height: blinking ? 1.5 : 9)
            .animation(.easeOut(duration: 0.08), value: blinking)
    }

    private var cheek: some View {
        Ellipse()
            .fill(.pink.opacity(0.45))
            .frame(width: 7, height: 4)
    }

    @ViewBuilder
    private func mouthView(_ kind: CharacterKind) -> some View {
        switch mouth {
        case .surprised:
            Ellipse()
                .fill(Color(red: 0.55, green: 0.28, blue: 0.25))
                .frame(width: 8, height: 10)
                .offset(y: 8)
        case .open:
            Ellipse()
                .fill(Color(red: 0.55, green: 0.28, blue: 0.25))
                .frame(width: 10, height: 7)
                .offset(y: 7)
        case .smile:
            if kind == .cat {
                CatMouthShape()
                    .stroke(mouthColor(kind), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: 14, height: 5)
                    .offset(y: 7)
            } else {
                SmileShape()
                    .stroke(mouthColor(kind), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: 12, height: 5)
                    .offset(y: 6)
            }
        }
    }
}

// MARK: - 도형

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

/// 밑단이 물결치는 유령 몸통
private struct GhostShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let hem = h * 0.82
        p.move(to: CGPoint(x: 0, y: h * 0.42))
        p.addCurve(to: CGPoint(x: w * 0.5, y: 0),
                   control1: CGPoint(x: 0, y: h * 0.12),
                   control2: CGPoint(x: w * 0.16, y: 0))
        p.addCurve(to: CGPoint(x: w, y: h * 0.42),
                   control1: CGPoint(x: w * 0.84, y: 0),
                   control2: CGPoint(x: w, y: h * 0.12))
        p.addLine(to: CGPoint(x: w, y: hem))
        // 아래로 늘어지는 물결 3개
        p.addQuadCurve(to: CGPoint(x: w * 0.67, y: hem),
                       control: CGPoint(x: w * 0.83, y: h * 1.06))
        p.addQuadCurve(to: CGPoint(x: w * 0.33, y: hem),
                       control: CGPoint(x: w * 0.5, y: h * 1.06))
        p.addQuadCurve(to: CGPoint(x: 0, y: hem),
                       control: CGPoint(x: w * 0.17, y: h * 1.06))
        p.closeSubpath()
        return p
    }
}

private struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.width * 0.5, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
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

/// 고양이 ω 입
private struct CatMouthShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: 0, y: h * 0.2))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.2),
                       control: CGPoint(x: w * 0.25, y: h * 1.4))
        p.addQuadCurve(to: CGPoint(x: w, y: h * 0.2),
                       control: CGPoint(x: w * 0.75, y: h * 1.4))
        return p
    }
}

// MARK: - 공유 상태

/// 패널 간 공유되는 UI 상태
@MainActor
final class AppState: ObservableObject {
    @Published var listVisible = false
    /// 자유 이동 중 걷고 있는지
    @Published var walking = false
    /// 바라보는 방향
    @Published var facingRight = true
    /// 던져져서 날아가는 중인지
    @Published var flying = false
}
