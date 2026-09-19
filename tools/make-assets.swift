// Renders DeskBuddy's image assets from the same SwiftUI shapes the app draws on
// screen, so the website and the icon can never drift from the real character.
//
//   swift tools/make-assets.swift characters     # docs/assets/{slime,ghost,cat}.png
//   swift tools/make-assets.swift og             # docs/assets/og.jpg (link previews)
//   swift tools/make-assets.swift candidates     # app icon drafts in build/icon-candidates/
//   swift tools/make-assets.swift icns <design>  # build/AppIcon.iconset + favicons
//
// Icon designs: cat, ghost, bubble, card
import SwiftUI
import AppKit

// MARK: - Shapes (kept in sync with Sources/DeskBuddy/CharacterView.swift)

struct SlimeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.5, y: 0))
        p.addCurve(to: CGPoint(x: w, y: h * 0.72),
                   control1: CGPoint(x: w * 0.92, y: 0), control2: CGPoint(x: w, y: h * 0.38))
        p.addCurve(to: CGPoint(x: w * 0.5, y: h),
                   control1: CGPoint(x: w, y: h * 0.95), control2: CGPoint(x: w * 0.78, y: h))
        p.addCurve(to: CGPoint(x: 0, y: h * 0.72),
                   control1: CGPoint(x: w * 0.22, y: h), control2: CGPoint(x: 0, y: h * 0.95))
        p.addCurve(to: CGPoint(x: w * 0.5, y: 0),
                   control1: CGPoint(x: 0, y: h * 0.38), control2: CGPoint(x: w * 0.08, y: 0))
        p.closeSubpath()
        return p
    }
}

struct GhostShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        let hem = h * 0.82
        p.move(to: CGPoint(x: 0, y: h * 0.42))
        p.addCurve(to: CGPoint(x: w * 0.5, y: 0),
                   control1: CGPoint(x: 0, y: h * 0.12), control2: CGPoint(x: w * 0.16, y: 0))
        p.addCurve(to: CGPoint(x: w, y: h * 0.42),
                   control1: CGPoint(x: w * 0.84, y: 0), control2: CGPoint(x: w, y: h * 0.12))
        p.addLine(to: CGPoint(x: w, y: hem))
        p.addQuadCurve(to: CGPoint(x: w * 0.67, y: hem), control: CGPoint(x: w * 0.83, y: h * 1.06))
        p.addQuadCurve(to: CGPoint(x: w * 0.33, y: hem), control: CGPoint(x: w * 0.5, y: h * 1.06))
        p.addQuadCurve(to: CGPoint(x: 0, y: hem), control: CGPoint(x: w * 0.17, y: h * 1.06))
        p.closeSubpath()
        return p
    }
}

struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.width * 0.5, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(to: CGPoint(x: rect.width, y: 0),
                       control: CGPoint(x: rect.width / 2, y: rect.height * 2))
        return p
    }
}

struct CatMouthShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: 0, y: h * 0.2))
        p.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.2), control: CGPoint(x: w * 0.25, y: h * 1.4))
        p.addQuadCurve(to: CGPoint(x: w, y: h * 0.2), control: CGPoint(x: w * 0.75, y: h * 1.4))
        return p
    }
}

/// Speech bubble with a tail on the bottom-left, matching Bubble.swift's silhouette.
struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let body = CGRect(x: 0, y: 0, width: w, height: h * 0.84)
        var p = Path(roundedRect: body, cornerRadius: h * 0.24, style: .continuous)
        p.move(to: CGPoint(x: w * 0.22, y: h * 0.80))
        p.addLine(to: CGPoint(x: w * 0.20, y: h))
        p.addLine(to: CGPoint(x: w * 0.42, y: h * 0.80))
        p.closeSubpath()
        return p
    }
}

// MARK: - Palette (from CharacterView.swift)

enum Pal {
    static let slimeTop = Color(red: 0.55, green: 0.87, blue: 0.68)
    static let slimeBot = Color(red: 0.28, green: 0.71, blue: 0.52)
    static let slimeEye = Color(red: 0.13, green: 0.30, blue: 0.20)
    static let slimeMouth = Color(red: 0.20, green: 0.42, blue: 0.30)

    static let ghostTop = Color(red: 0.99, green: 0.99, blue: 1.00)
    static let ghostBot = Color(red: 0.82, green: 0.82, blue: 0.95)
    static let ghostEye = Color(red: 0.25, green: 0.25, blue: 0.38)
    static let ghostMouth = Color(red: 0.35, green: 0.35, blue: 0.50)

    static let catTop = Color(red: 0.98, green: 0.75, blue: 0.42)
    static let catBot = Color(red: 0.90, green: 0.58, blue: 0.25)
    static let catEar = Color(red: 0.88, green: 0.55, blue: 0.24)
    static let catInner = Color(red: 0.98, green: 0.68, blue: 0.62)
    static let catEye = Color(red: 0.28, green: 0.17, blue: 0.10)
    static let catMouth = Color(red: 0.40, green: 0.25, blue: 0.15)
}

// MARK: - Faces
// Geometry mirrors CharacterView at its native 58pt body width; `u` scales it up.

struct Face: View {
    let eye: Color
    let mouth: Color
    let u: CGFloat
    var catMouth = false

    var body: some View {
        ZStack {
            HStack(spacing: 14 * u) {
                Capsule().fill(eye).frame(width: 6 * u, height: 9 * u)
                Capsule().fill(eye).frame(width: 6 * u, height: 9 * u)
            }
            .offset(y: -4 * u)

            HStack(spacing: 34 * u) {
                Ellipse().fill(.pink.opacity(0.45)).frame(width: 7 * u, height: 4 * u)
                Ellipse().fill(.pink.opacity(0.45)).frame(width: 7 * u, height: 4 * u)
            }
            .offset(y: 4 * u)

            if catMouth {
                CatMouthShape()
                    .stroke(mouth, style: StrokeStyle(lineWidth: 1.4 * u, lineCap: .round))
                    .frame(width: 14 * u, height: 5 * u)
                    .offset(y: 7 * u)
            } else {
                SmileShape()
                    .stroke(mouth, style: StrokeStyle(lineWidth: 1.6 * u, lineCap: .round))
                    .frame(width: 12 * u, height: 5 * u)
                    .offset(y: 6 * u)
            }
        }
    }
}

struct Highlight: View {
    let u: CGFloat
    var body: some View {
        Ellipse()
            .fill(.white.opacity(0.45))
            .frame(width: 14 * u, height: 8 * u)
            .rotationEffect(.degrees(-20))
            .offset(x: -13 * u, y: -16 * u)
    }
}

struct CatBody: View {
    let u: CGFloat
    var body: some View {
        ZStack {
            HStack(spacing: 16 * u) {
                ear.rotationEffect(.degrees(-16))
                ear.rotationEffect(.degrees(16))
            }
            .offset(y: -23 * u)

            Ellipse()
                .fill(LinearGradient(colors: [Pal.catTop, Pal.catBot], startPoint: .top, endPoint: .bottom))
                .overlay(Highlight(u: u))
                .frame(width: 58 * u, height: 50 * u)

            Face(eye: Pal.catEye, mouth: Pal.catMouth, u: u, catMouth: true)
        }
    }

    private var ear: some View {
        ZStack {
            TriangleShape().fill(Pal.catEar).frame(width: 18 * u, height: 16 * u)
            TriangleShape().fill(Pal.catInner).frame(width: 7 * u, height: 7 * u).offset(y: -2 * u)
        }
    }
}

struct GhostBody: View {
    let u: CGFloat
    var body: some View {
        ZStack {
            GhostShape()
                .fill(LinearGradient(colors: [Pal.ghostTop, Pal.ghostBot], startPoint: .top, endPoint: .bottom))
                .overlay(Highlight(u: u))
                .frame(width: 56 * u, height: 58 * u)
            Face(eye: Pal.ghostEye, mouth: Pal.ghostMouth, u: u).offset(y: -2 * u)
        }
    }
}

struct SlimeBody: View {
    let u: CGFloat
    var body: some View {
        ZStack {
            SlimeShape()
                .fill(LinearGradient(colors: [Pal.slimeTop, Pal.slimeBot], startPoint: .top, endPoint: .bottom))
                .overlay(Highlight(u: u))
                .frame(width: 58 * u, height: 52 * u)
            Face(eye: Pal.slimeEye, mouth: Pal.slimeMouth, u: u).offset(y: 2 * u)
        }
    }
}

// MARK: - Icon designs
// Rendered on the macOS icon grid: 1024pt canvas, 824pt squircle, 185pt corner radius.

let canvas: CGFloat = 1024
let plate: CGFloat = 824
let plateRadius: CGFloat = 185

struct Plate<Content: View>: View {
    let colors: [Color]
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: plateRadius, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: plateRadius, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 3)
                )
                .frame(width: plate, height: plate)
                .shadow(color: .black.opacity(0.28), radius: 26, y: 16)
            content
        }
        .frame(width: canvas, height: canvas)
    }
}

/// Cat face, centred on a warm cream plate.
struct CatIcon: View {
    var body: some View {
        Plate(colors: [Color(red: 1.0, green: 0.96, blue: 0.90), Color(red: 0.99, green: 0.89, blue: 0.76)]) {
            CatBody(u: 8.6).offset(y: 30)
        }
    }
}

/// Ghost on a deep indigo plate — highest contrast of the four.
struct GhostIcon: View {
    var body: some View {
        Plate(colors: [Color(red: 0.36, green: 0.36, blue: 0.58), Color(red: 0.20, green: 0.20, blue: 0.36)]) {
            GhostBody(u: 8.4)
        }
    }
}

/// Cat peeking over a speech bubble — reads as "desk buddy that talks to you".
struct BubbleIcon: View {
    var body: some View {
        Plate(colors: [Color(red: 0.42, green: 0.78, blue: 0.62), Color(red: 0.22, green: 0.60, blue: 0.46)]) {
            ZStack {
                BubbleShape()
                    .fill(.white)
                    .frame(width: 470, height: 360)
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
                    .offset(y: 150)

                // Three list lines inside the bubble
                VStack(alignment: .leading, spacing: 34) {
                    ForEach([250.0, 200.0, 150.0], id: \.self) { w in
                        Capsule().fill(Color(red: 0.80, green: 0.84, blue: 0.82)).frame(width: w, height: 26)
                    }
                }
                .offset(x: -14, y: 118)

                CatBody(u: 5.0).offset(y: -128)
            }
        }
    }
}

/// Character sitting on a to-do card — the app's actual job, stated literally.
struct CardIcon: View {
    var body: some View {
        Plate(colors: [Color(red: 0.98, green: 0.97, blue: 0.95), Color(red: 0.91, green: 0.90, blue: 0.88)]) {
            ZStack {
                RoundedRectangle(cornerRadius: 56, style: .continuous)
                    .fill(.white)
                    .frame(width: 540, height: 330)
                    .shadow(color: .black.opacity(0.16), radius: 20, y: 12)
                    .offset(y: 170)

                VStack(alignment: .leading, spacing: 40) {
                    ForEach(0..<3, id: \.self) { i in
                        HStack(spacing: 26) {
                            if i == 0 {
                                ZStack {
                                    Circle().fill(Pal.slimeBot).frame(width: 40, height: 40)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            } else {
                                Circle().strokeBorder(Color(red: 0.78, green: 0.78, blue: 0.76), lineWidth: 4)
                                    .frame(width: 40, height: 40)
                            }
                            Capsule().fill(Color(red: 0.85, green: 0.85, blue: 0.83))
                                .frame(width: i == 0 ? 250 : 290, height: 24)
                        }
                    }
                }
                .offset(y: 170)

                SlimeBody(u: 5.2).offset(x: 150, y: -60)
            }
        }
    }
}

// MARK: - Rendering

@MainActor
func render(_ view: some View, to path: String, size: CGFloat) {
    let r = ImageRenderer(content: view.frame(width: canvas, height: canvas))
    r.scale = size / canvas
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let bmp = NSBitmapImageRep(data: tiff),
          let png = bmp.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("render failed: \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    try! png.write(to: url)
}

@MainActor
func renderJPEG(_ view: some View, to path: String, width: CGFloat, height: CGFloat) {
    let r = ImageRenderer(content: view.frame(width: width, height: height))
    r.scale = 1
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let bmp = NSBitmapImageRep(data: tiff),
          let jpeg = bmp.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
        FileHandle.standardError.write("render failed: \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    try! jpeg.write(to: url)
}

@MainActor
func design(_ name: String) -> AnyView {
    switch name {
    case "cat": return AnyView(CatIcon())
    case "ghost": return AnyView(GhostIcon())
    case "bubble": return AnyView(BubbleIcon())
    case "card": return AnyView(CardIcon())
    default:
        FileHandle.standardError.write("unknown design: \(name)\n".data(using: .utf8)!)
        exit(1)
    }
}

/// A character on its own, no plate — what the website puts in the hero.
@MainActor
func portrait(_ name: String) -> AnyView {
    let u: CGFloat = 8.0
    switch name {
    case "slime": return AnyView(SlimeBody(u: u).frame(width: canvas, height: canvas))
    case "ghost": return AnyView(GhostBody(u: u).frame(width: canvas, height: canvas))
    case "cat": return AnyView(CatBody(u: u).frame(width: canvas, height: canvas))
    default:
        FileHandle.standardError.write("unknown character: \(name)\n".data(using: .utf8)!)
        exit(1)
    }
}

/// 1200x630 link-preview card.
struct OGCard: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.09, green: 0.16, blue: 0.13),
                                    Color(red: 0.05, green: 0.10, blue: 0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            HStack(spacing: 56) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("DeskBuddy")
                        .font(.system(size: 76, weight: .bold, design: .default))
                        .foregroundStyle(.white)
                    Text("A desk buddy that keeps your to-dos.")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(Color(red: 0.62, green: 0.82, blue: 0.73))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("macOS · free & open source")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color(red: 0.35, green: 0.81, blue: 0.59))
                        .padding(.top, 8)
                }
                .frame(width: 600, alignment: .leading)

                SlimeBody(u: 4.6)
                    .shadow(color: .black.opacity(0.35), radius: 30, y: 16)
            }
            .padding(.horizontal, 80)
        }
        .frame(width: 1200, height: 630)
    }
}

let names = ["cat", "ghost", "bubble", "card"]
let characters = ["slime", "ghost", "cat"]
let args = Array(CommandLine.arguments.dropFirst())

@MainActor
func main() {
    switch args.first ?? "characters" {
    case "characters":
        for c in characters { render(portrait(c), to: "docs/assets/\(c).png", size: 640) }
        print("✅ docs/assets/{\(characters.joined(separator: ","))}.png")

    case "og":
        renderJPEG(OGCard(), to: "docs/assets/og.jpg", width: 1200, height: 630)
        print("✅ docs/assets/og.jpg")

    case "candidates":
        for n in names { render(design(n), to: "build/icon-candidates/\(n).png", size: 512) }
        print("✅ build/icon-candidates/{\(names.joined(separator: ","))}.png")

    case "icns":
        let name = args.count > 1 ? args[1] : "cat"
        let view = design(name)
        let iconset = "build/AppIcon.iconset"
        try? FileManager.default.removeItem(atPath: iconset)
        // The sizes `iconutil` expects for a complete .icns
        let specs: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                                   (256, 1), (256, 2), (512, 1), (512, 2)]
        for (pt, scale) in specs {
            let suffix = scale == 1 ? "" : "@2x"
            render(view, to: "\(iconset)/icon_\(pt)x\(pt)\(suffix).png", size: CGFloat(pt * scale))
        }
        // Web assets come off the same source so the site and the app never drift
        render(view, to: "docs/assets/icon-512.png", size: 512)
        render(view, to: "docs/assets/icon-256.png", size: 256)
        render(view, to: "docs/assets/favicon-64.png", size: 64)
        print("✅ \(iconset) + docs/assets (design: \(name))")

    default:
        FileHandle.standardError.write("usage: make-assets.swift [characters|og|candidates|icns <design>]\n".data(using: .utf8)!)
        exit(1)
    }
}
MainActor.assumeIsolated { main() }
