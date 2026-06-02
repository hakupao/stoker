import SwiftUI
import AppKit

// MARK: - Flame mark

/// Stoker's menu-bar mark, drawn in SwiftUI (no bundled asset) so it can switch
/// on schedule state, recolor itself, flicker frame-by-frame, and adapt to the
/// menu bar's light/dark appearance.
///
/// - `active`  → schedule lit: a warm two-tone flame (ember body + hotter core).
/// - inactive  → schedule off: the same silhouette as a cold hollow outline in
///   the adaptive secondary label color ("unlit").
///
/// The brand embers match the Forge app icon (`ForgeBadgeMark`). Drawing in a
/// fixed 64×64 design space and scaling to the view's frame keeps the geometry
/// resolution-independent for any menu-bar point size.
struct StokerFlameIcon: View {
    /// Schedule on → lit/colored/flickering. Off → cold outline.
    var active: Bool
    /// Free-running frame counter (reduced mod 3). Ignored when inactive.
    var frame: Int = 0
    var size: CGFloat = 18

    private static let ember    = Color(red: 0xE3 / 255, green: 0x6E / 255, blue: 0x43 / 255)
    private static let emberHot = Color(red: 0xFF / 255, green: 0xB1 / 255, blue: 0x5E / 255)

    /// Per-frame breathing of the hot inner core, grown from the flame's base.
    private static let innerScale: [CGFloat] = [1.0, 1.08, 0.92]

    private var f: Int { ((frame % 3) + 3) % 3 }

    var body: some View {
        ZStack {
            if active {
                FlameShape(frame: f)
                    .fill(Self.ember)
                FlameInnerShape()
                    .fill(Self.emberHot)
                    .scaleEffect(Self.innerScale[f], anchor: .bottom)
            } else {
                FlameShape(frame: 0)
                    .stroke(Color(nsColor: .secondaryLabelColor),
                            style: StrokeStyle(lineWidth: size * 0.075, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Geometry

/// The outer flame silhouette. `frame` (0–2) selects one of three subtly
/// different shapes so the active flame flickers by swapping discrete frames —
/// the `MenuBarExtra` label snapshots its content, so continuous interpolation
/// is unreliable, but a state-driven frame swap redraws cleanly.
struct FlameShape: Shape {
    var frame: Int = 0

    func path(in rect: CGRect) -> Path {
        FlameGeometry.build(FlameGeometry.outer[((frame % 3) + 3) % 3], in: rect)
    }
}

/// The hotter inner core, layered over `FlameShape` in the lit state.
struct FlameInnerShape: Shape {
    func path(in rect: CGRect) -> Path {
        FlameGeometry.build(FlameGeometry.inner, in: rect)
    }
}

/// Cubic-Bézier path data in a 64×64 design space. Each array is
/// `[startX, startY, (c1x, c1y, c2x, c2y, endX, endY)…]` — one 6-tuple per curve.
private enum FlameGeometry {
    static func build(_ d: [CGFloat], in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 64 * rect.width,
                    y: rect.minY + y / 64 * rect.height)
        }
        var path = Path()
        path.move(to: pt(d[0], d[1]))
        var i = 2
        while i + 5 < d.count {
            path.addCurve(to: pt(d[i + 4], d[i + 5]),
                          control1: pt(d[i], d[i + 1]),
                          control2: pt(d[i + 2], d[i + 3]))
            i += 6
        }
        path.closeSubpath()
        return path
    }

    static let outer: [[CGFloat]] = [
        [32, 4,  28, 16, 20, 22, 20, 34,  20, 47, 25, 60, 32, 60,  39, 60, 44, 47, 44, 34,  44, 26, 39, 22, 37, 15,  36, 20, 33, 21, 33, 16,  33, 11, 33, 7, 32, 4],
        [32, 6,  27, 17, 20, 22, 20, 34,  20, 47, 25, 60, 32, 60,  39, 60, 44, 47, 44, 33,  44, 25, 38, 22, 36, 14,  35, 20, 32, 21, 32, 16,  32, 11, 33, 8, 32, 6],
        [32, 3,  29, 15, 21, 23, 21, 35,  21, 48, 26, 60, 32, 60,  38, 60, 44, 48, 44, 35,  44, 27, 40, 21, 38, 16,  37, 21, 34, 22, 34, 17,  34, 12, 33, 7, 32, 3],
    ]

    static let inner: [CGFloat] =
        [32, 31,  29, 38, 27, 41, 27, 46,  27, 51, 29, 54, 32, 54,  35, 54, 37, 51, 37, 46,  37, 41, 35, 38, 32, 31]
}

// MARK: - Menu-bar NSImages

/// Pre-rendered `NSImage`s for the `MenuBarExtra` label.
///
/// `MenuBarExtra` does NOT reliably render a raw filled SwiftUI `Shape` as its
/// label (the status item comes up blank), but it renders `Image(nsImage:)`
/// faithfully — and `.renderingMode(.original)` keeps the flame's color instead
/// of letting the menu bar flatten it to a monochrome tint. So we rasterize the
/// flame view once with `ImageRenderer` and hand the menu bar plain images.
@MainActor
enum StokerMenuBarIcon {
    static let size: CGFloat = 18

    /// The three lit-flame frames, kept ORIGINAL (not template) so the ember/gold
    /// color survives. Cycle through these to animate the flicker.
    static let liveFrames: [NSImage] = (0..<3).map { frame in
        render(StokerFlameIcon(active: true, frame: frame, size: size), template: false)
    }

    /// The unlit outline, rendered as a TEMPLATE (black mask) so macOS tints it to
    /// the menu bar's adaptive light/dark color — the natural "cold / off" look.
    static let cold: NSImage = render(
        FlameShape(frame: 0)
            .stroke(Color.black, style: StrokeStyle(lineWidth: size * 0.075, lineJoin: .round)),
        template: true)

    private static func render(_ view: some View, template: Bool) -> NSImage {
        let renderer = ImageRenderer(content: view.frame(width: size, height: size))
        renderer.scale = 2   // crisp on Retina; downsamples cleanly on 1× displays
        let pointSize = NSSize(width: size, height: size)
        guard let cg = renderer.cgImage else { return NSImage(size: pointSize) }
        let image = NSImage(cgImage: cg, size: pointSize)
        image.isTemplate = template
        return image
    }
}
