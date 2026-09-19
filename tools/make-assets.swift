// Renders DeskBuddy's image assets from the same shape the app draws, so the
// website and the app can never drift apart.
//
//   swift tools/make-assets.swift characters   # docs/assets/buddy-{light,dark}.png
//   swift tools/make-assets.swift og           # docs/assets/og.jpg (link previews)
//   swift tools/make-assets.swift icns         # assets/AppIcon.icns + docs/assets/favicon.png
//   swift tools/make-assets.swift all
//
// Keep EggShape and the two palettes in step with Sources/DeskBuddy/CharacterView.swift.
import SwiftUI
import AppKit

// MARK: - The character (mirrors CharacterView.swift)

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

struct Skin {
    let fill: Color
    let line: Color

    static let light = Skin(fill: Color(red: 0.99, green: 0.99, blue: 0.99),
                            line: Color(red: 0.16, green: 0.19, blue: 0.18))
    static let dark = Skin(fill: Color(red: 0.11, green: 0.12, blue: 0.12),
                           line: Color(red: 0.95, green: 0.96, blue: 0.95))
}

/// The buddy at an arbitrary scale. Proportions come from the app's 56x60 body.
struct Buddy: View {
    var skin: Skin
    var u: CGFloat

    var body: some View {
        let w = 56 * u, h = 60 * u
        let lw = 2.6 * u
        let d = lw * 1.6
        ZStack {
            EggShape()
                .fill(skin.fill)
                .overlay(EggShape().stroke(skin.line, lineWidth: lw))
                .frame(width: w, height: h)

            HStack(spacing: w * 0.23) {
                Circle().fill(skin.line).frame(width: d, height: d)
                Circle().fill(skin.line).frame(width: d, height: d)
            }
            .offset(y: -h * 0.02)
        }
        .frame(width: w, height: h)
    }
}

// MARK: - App icon
//
// Laid out on the macOS icon grid: a 824pt squircle centred on a 1024pt canvas.
// A pale paper plate: the body is separated from it by its outline rather than by
// a change in value, which is why the outline has to carry the icon at small sizes.

enum Brand {
    static let plateTop = Color(red: 0.99, green: 0.98, blue: 0.96)
    static let plateBottom = Color(red: 0.90, green: 0.89, blue: 0.86)
}

struct AppIcon: View {
    static let canvas: CGFloat = 1024
    static let plate: CGFloat = 824
    static let radius: CGFloat = 185

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .fill(LinearGradient(colors: [Brand.plateTop, Brand.plateBottom],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: Self.plate, height: Self.plate)
                .shadow(color: .black.opacity(0.25), radius: 24, y: 14)

            Buddy(skin: .light, u: 8.4)
        }
        .frame(width: Self.canvas, height: Self.canvas)
    }
}

// MARK: - Link preview card

struct OGCard: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.09, green: 0.11, blue: 0.11),
                                    Color(red: 0.05, green: 0.06, blue: 0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            HStack(spacing: 64) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("DeskBuddy")
                        .font(.system(size: 76, weight: .bold))
                        .foregroundStyle(.white)
                    Text("A desk buddy that keeps your to-dos.")
                        .font(.system(size: 34))
                        .foregroundStyle(Color(red: 0.72, green: 0.75, blue: 0.74))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("macOS · free & open source")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color(red: 0.55, green: 0.60, blue: 0.58))
                        .padding(.top, 8)
                }
                .frame(width: 600, alignment: .leading)

                Buddy(skin: .dark, u: 5.2)
                    .shadow(color: .black.opacity(0.5), radius: 34, y: 18)
            }
            .padding(.horizontal, 80)
        }
        .frame(width: 1200, height: 630)
    }
}

// MARK: - Render

@MainActor
func renderPNG(_ view: some View, to path: String, width: CGFloat, height: CGFloat, scale: CGFloat = 1) {
    write(view, path: path, width: width, height: height, scale: scale, jpeg: false)
}

@MainActor
func renderJPEG(_ view: some View, to path: String, width: CGFloat, height: CGFloat) {
    write(view, path: path, width: width, height: height, scale: 1, jpeg: true)
}

@MainActor
private func write(_ view: some View, path: String, width: CGFloat, height: CGFloat,
                   scale: CGFloat, jpeg: Bool) {
    let r = ImageRenderer(content: view.frame(width: width, height: height))
    r.scale = scale
    let props: [NSBitmapImageRep.PropertyKey: Any] = jpeg ? [.compressionFactor: 0.9] : [:]
    guard let img = r.nsImage, let tiff = img.tiffRepresentation,
          let bmp = NSBitmapImageRep(data: tiff),
          let data = bmp.representation(using: jpeg ? .jpeg : .png, properties: props) else {
        FileHandle.standardError.write("render failed: \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    try! data.write(to: url)
}

@MainActor
func characters() {
    // Transparent, generously sized; the page scales them down with CSS.
    //
    // The canvas is padded rather than matching the body exactly: the outline is
    // centred on the path, so half its width sits outside the body box and the
    // image bounds would otherwise slice it off on all four sides.
    let u: CGFloat = 6
    let pad = 2.6 * u
    for (name, skin) in [("light", Skin.light), ("dark", Skin.dark)] {
        renderPNG(Buddy(skin: skin, u: u).padding(pad),
                  to: "docs/assets/buddy-\(name).png",
                  width: 56 * u + pad * 2, height: 60 * u + pad * 2)
    }
    print("✅ docs/assets/buddy-{light,dark}.png")
}

/// Renders every size `iconutil` needs, then packs them into an .icns.
@MainActor
func icns() {
    let iconset = "build/AppIcon.iconset"
    try? FileManager.default.removeItem(atPath: iconset)
    for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                        (256, 1), (256, 2), (512, 1), (512, 2)] {
        let suffix = scale == 1 ? "" : "@2x"
        let px = CGFloat(pt * scale)
        renderPNG(AppIcon().scaleEffect(px / AppIcon.canvas),
                  to: "\(iconset)/icon_\(pt)x\(pt)\(suffix).png", width: px, height: px)
    }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    proc.arguments = ["-c", "icns", iconset, "-o", "assets/AppIcon.icns"]
    try? FileManager.default.createDirectory(atPath: "assets", withIntermediateDirectories: true)
    try! proc.run()
    proc.waitUntilExit()
    guard proc.terminationStatus == 0 else {
        FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
        exit(1)
    }

    renderPNG(AppIcon().scaleEffect(180 / AppIcon.canvas), to: "docs/assets/favicon.png",
              width: 180, height: 180)
    print("✅ assets/AppIcon.icns + docs/assets/favicon.png")
}

@MainActor
func main() {
    switch CommandLine.arguments.dropFirst().first ?? "all" {
    case "icns":
        icns()
    case "characters":
        characters()
    case "og":
        renderJPEG(OGCard(), to: "docs/assets/og.jpg", width: 1200, height: 630)
        print("✅ docs/assets/og.jpg")
    case "all":
        characters()
        renderJPEG(OGCard(), to: "docs/assets/og.jpg", width: 1200, height: 630)
        print("✅ docs/assets/og.jpg")
        icns()
    default:
        FileHandle.standardError.write("usage: make-assets.swift [characters|og|icns|all]\n".data(using: .utf8)!)
        exit(1)
    }
}
MainActor.assumeIsolated { main() }
