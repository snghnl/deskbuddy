import SwiftUI

// MARK: - Character Kinds

/// The built-in character. Collapsing the old slime/ghost/cat set to one case also
/// migrates existing installs for free: their stored raw value no longer matches,
/// so `init(rawValue:)` fails and `CharacterChoice.parse` falls back to `.buddy`.
enum CharacterKind: String, CaseIterable, Identifiable {
    case buddy

    var id: String { rawValue }

    var label: String { L.s("character.buddy") }
}

// MARK: - Palette

/// The body is opaque on purpose: a bare outline disappears against a dark
/// wallpaper, whereas a filled shape reads on any background without having to
/// work out what is behind it.
///
/// Body and outline invert together with the system appearance, which covers all
/// four combinations — in light mode the dark outline carries a white body over a
/// pale wallpaper, in dark mode the light outline does the same for a black body,
/// and when appearance and wallpaper disagree the body colour itself is the
/// contrast. Note this follows the *system appearance*, not the wallpaper: those
/// can disagree, but every resulting pairing still reads.
private enum Skin {
    static func fill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.11, green: 0.12, blue: 0.12)
                        : Color(red: 0.99, green: 0.99, blue: 0.99)
    }

    static func line(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.95, green: 0.96, blue: 0.95)
                        : Color(red: 0.16, green: 0.19, blue: 0.18)
    }

    /// A dark contact shadow only makes sense under a light body.
    static func shadow(_ scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.0 : 0.18
    }
}

// MARK: - Floating Character

/// The character floating on screen. Click/drag events are handled directly by the
/// panel (window), so this view does nothing but draw.
struct CharacterView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var appState: AppState

    @AppStorage(SettingsKeys.character) private var characterRaw = CharacterKind.buddy.rawValue
    @State private var blinking = false

    private var choice: CharacterChoice { .parse(characterRaw) }
    private var remaining: Int { store.todos.filter { !$0.isDone }.count }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Spins while flying, bounces quickly while walking, bobs slowly while idle
            let animated = appState.walking || appState.flying
            TimelineView(.animation(minimumInterval: animated ? 1.0 / 60.0 : 1.0 / 20.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = sin(t * (appState.walking ? 7.0 : 1.9))
                let spin = (t * 620).truncatingRemainder(dividingBy: 360)
                CharacterBody(choice: choice, blinking: blinking)
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
    static let bodySize = CGSize(width: 56, height: 60)
    static let lineWidth: CGFloat = 2.6

    @Environment(\.colorScheme) private var scheme

    let choice: CharacterChoice
    var blinking = false

    init(choice: CharacterChoice, blinking: Bool = false) {
        self.choice = choice
        self.blinking = blinking
    }

    var body: some View {
        ZStack {
            // Ground shadow
            Ellipse()
                .fill(.black.opacity(Skin.shadow(scheme)))
                .frame(width: 44, height: 8)
                .offset(y: 30)
                .blur(radius: 2)

            switch choice {
            case .builtin:
                buddyBody
                eyes
            case .custom(let name):
                customBody(name)
            }
        }
    }

    // MARK: Body

    private var buddyBody: some View {
        EggShape()
            .fill(Skin.fill(scheme))
            .overlay(EggShape().stroke(Skin.line(scheme), lineWidth: Self.lineWidth))
            .frame(width: Self.bodySize.width, height: Self.bodySize.height)
    }

    /// User-provided image — body only, no eyes. Falls back to the buddy if the file is gone.
    @ViewBuilder
    private func customBody(_ name: String) -> some View {
        if let image = CharacterImageCache.image(name) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 58, height: 58)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        } else {
            buddyBody
            eyes
        }
    }

    // MARK: Eyes
    //
    // Two dots, and that is the whole face — there are no expressions to switch
    // between. The blink squashes them rather than hiding them, so the character
    // never looks eyeless for a frame.

    private var eyes: some View {
        let w = Self.bodySize.width
        let d = Self.lineWidth * 1.6
        return HStack(spacing: w * 0.23) {
            eye(d)
            eye(d)
        }
        .offset(y: -Self.bodySize.height * 0.02)
    }

    private func eye(_ d: CGFloat) -> some View {
        Capsule()
            .fill(Skin.line(scheme))
            .frame(width: d, height: blinking ? d * 0.28 : d)
            .animation(.easeOut(duration: 0.08), value: blinking)
    }
}

// MARK: - Shapes

/// The body: a rounded form carrying slightly more weight low than high, so it
/// reads as sitting rather than floating.
struct EggShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.5, y: 0))
        p.addCurve(to: CGPoint(x: w, y: h * 0.62),
                   control1: CGPoint(x: w * 0.86, y: 0), control2: CGPoint(x: w, y: h * 0.30))
        p.addCurve(to: CGPoint(x: w * 0.5, y: h),
                   control1: CGPoint(x: w, y: h * 0.87), control2: CGPoint(x: w * 0.79, y: h))
        p.addCurve(to: CGPoint(x: 0, y: h * 0.62),
                   control1: CGPoint(x: w * 0.21, y: h), control2: CGPoint(x: 0, y: h * 0.87))
        p.addCurve(to: CGPoint(x: w * 0.5, y: 0),
                   control1: CGPoint(x: 0, y: h * 0.30), control2: CGPoint(x: w * 0.14, y: 0))
        p.closeSubpath()
        return p
    }
}

// MARK: - Menu bar glyph

/// The character as one even-odd path: a solid body with the eyes punched out.
///
/// The menu bar version is solid rather than outlined. At 18pt an outline reads as
/// an empty ring and the eyes disappear, and a filled glyph also sits better next
/// to the SF Symbols in the rest of the menu bar. The eyes are proportionally
/// larger than on the floating character for the same reason.
struct BuddyGlyph: Shape {
    var eye: CGFloat = 0.20     // diameter, as a fraction of body width
    var gap: CGFloat = 0.16     // space between the eyes, likewise

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = EggShape().path(in: rect)
        let d = w * eye
        let cy = h * 0.48
        let dx = (w * gap + d) / 2
        for sign in [-1.0, 1.0] as [CGFloat] {
            p.addEllipse(in: CGRect(x: w / 2 + sign * dx - d / 2, y: cy - d / 2, width: d, height: d))
        }
        return p
    }
}

extension NSImage {
    /// Status bar icon. Marked as a template so the system handles light and dark
    /// menu bars, the highlighted state and any accent tinting; drawn on demand
    /// rather than from a bitmap so it stays sharp at any scale.
    static func buddyStatusGlyph(height: CGFloat = 18) -> NSImage {
        let size = CGSize(width: (height * 56 / 60).rounded(), height: height)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(BuddyGlyph().path(in: rect).cgPath)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath(using: .evenOdd)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "DeskBuddy"
        return image
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
