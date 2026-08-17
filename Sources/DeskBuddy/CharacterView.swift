import SwiftUI

// MARK: - Character Kinds

enum CharacterKind: String, CaseIterable, Identifiable {
    case slime, ghost, cat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .slime: L.t("슬라임", "Slime")
        case .ghost: L.t("유령", "Ghost")
        case .cat: L.t("고양이", "Cat")
        }
    }
}

enum MouthState {
    case smile      // Default expression
    case open       // Excited because the list is open
    case surprised  // Thrown and flying through the air
}

// MARK: - Floating Character

/// The character floating on screen. Click/drag events are handled directly by the
/// panel (window), so this view does nothing but draw.
struct CharacterView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var appState: AppState

    @AppStorage(SettingsKeys.character) private var characterRaw = CharacterKind.slime.rawValue
    @State private var blinking = false

    private var choice: CharacterChoice { .parse(characterRaw) }
    private var remaining: Int { store.todos.filter { !$0.isDone }.count }

    private var mouth: MouthState {
        if appState.flying { .surprised }
        else if appState.listVisible || appState.talking { .open }
        else { .smile }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Spins while flying, bounces quickly while walking, bobs slowly while idle
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
                    .scaleEffect(x: appState.facingRight ? 1 : -1)   // Face the direction of travel
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

// MARK: - Character Body (also reused in the settings preview)

/// Drawn on a 76x84 canvas. Shrink with scaleEffect when another size is needed.
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
            // Ground shadow
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

    /// User-provided image — body only, no face. Falls back to the slime if the file is gone.
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

    // MARK: Body

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
            // Ears (layered behind the head)
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

    // MARK: Face

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

// MARK: - Shapes

/// Droplet-shaped slime body that spreads slightly at the bottom
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

/// Ghost body with a wavy hem
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
        // Three waves drooping downward
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

/// Cat ω mouth
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

// MARK: - Shared State

/// UI state shared across panels
@MainActor
final class AppState: ObservableObject {
    @Published var listVisible = false
    /// Current tab of the list panel (also switched with the ⌘1/2/3 shortcuts)
    @Published var tab: TodoTab = .active
    /// Whether the character is walking while roaming freely
    @Published var walking = false
    /// Facing direction
    @Published var facingRight = true
    /// Whether the character is flying after being thrown
    @Published var flying = false
    /// While a speech bubble is showing
    @Published var talking = false
}
