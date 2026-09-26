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

    private static let ember     = Color(red: 0xE3 / 255, green: 0x6E / 255, blue: 0x43 / 255)
    private static let emberHot  = Color(red: 0xFF / 255, green: 0xB1 / 255, blue: 0x5E / 255)
    /// Gold used both as the lit flame's rim (behind the fill) and as the unlit
    /// "off" outline — a bright warm tone that glows on dark menu bars and still
    /// outlines the silhouette on light ones. Baked into the `.original` images, so
    /// it shows the same gold across light/dark instead of an adaptive tint.
    /// `fileprivate` so `StokerMenuBarIcon` (same file) can reuse it for the outline.
    fileprivate static let flameOutline = Color(red: 0xFF / 255, green: 0xC3 / 255, blue: 0x6E / 255)

    /// Per-frame breathing of the hot inner core, grown from the flame's base.
    /// Wide swing (±20%) so the flicker reads at menu-bar point sizes.
    private static let innerScale: [CGFloat] = [1.0, 1.22, 0.80]

    private var f: Int { ((frame % 3) + 3) % 3 }

    var body: some View {
        ZStack {
            if active {
                // Outline sits behind the fill so only its outer half shows as a rim.
                FlameShape(frame: f)
                    .stroke(Self.flameOutline,
                            style: StrokeStyle(lineWidth: size * 0.11, lineJoin: .round))
                FlameShape(frame: f)
                    .fill(Self.ember)
                FlameInnerShape()
                    .fill(Self.emberHot)
                    .scaleEffect(Self.innerScale[f], anchor: .bottom)
            } else {
                // Unlit / schedule off: a hollow gold outline echoing the lit rim.
                FlameShape(frame: 0)
                    .stroke(Self.flameOutline,
                            style: StrokeStyle(lineWidth: size * 0.085, lineJoin: .round))
            }
        }
        // Inset so the outline rim never clips the frame at the rounded base.
        .padding(size * 0.06)
        .frame(width: size, height: size)
    }
}

// MARK: - Geometry

/// The outer flame silhouette. `frame` (0–2) selects one of three distinct
/// poses (rest / lick-up-right / squat-left) so the active flame visibly
/// flickers by swapping discrete frames — the `MenuBarExtra` label snapshots its
/// content, so continuous interpolation is unreliable, but a state-driven frame
/// swap redraws cleanly.
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
        // frame 0 — rest: a plump teardrop, belly x≈13…51 (~56% wide vs the old 37%).
        [32, 7,  28, 16, 13, 30, 13, 42,  13, 53, 21, 61, 32, 61,  43, 61, 51, 53, 51, 42,  51, 28, 45, 21, 36, 15,  34, 17, 33, 21, 33, 19,  33, 13, 33, 10, 32, 7],
        // frame 1 — tall lick to the right: tip darts up-right, right belly pushes out.
        [35, 3,  30, 13, 15, 28, 15, 41,  14, 53, 22, 61, 32, 61,  44, 61, 53, 52, 53, 40,  53, 26, 46, 19, 38, 12,  36, 14, 34, 18, 34, 16,  35, 10, 35, 6, 35, 3],
        // frame 2 — squat & wide, leaning left: tip drops, belly fattens.
        [29, 10,  26, 19, 11, 33, 11, 45,  11, 55, 20, 62, 32, 62,  44, 62, 49, 55, 49, 44,  49, 30, 43, 22, 35, 18,  33, 20, 32, 24, 32, 22,  32, 16, 32, 13, 29, 10],
    ]

    static let inner: [CGFloat] =
        [32, 33,  28, 40, 25, 44, 25, 49,  25, 54, 28, 57, 32, 57,  36, 57, 39, 54, 39, 49,  39, 44, 36, 40, 32, 33]
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

    /// The unlit "off" outline: a hollow GOLD flame, kept ORIGINAL (not template) so
    /// the gold survives instead of being tinted to the menu bar's adaptive color —
    /// it echoes the lit flame's gold rim. Drawn at the same inset so the silhouette
    /// size stays put across on/off.
    static let cold: NSImage = render(
        FlameShape(frame: 0)
            .stroke(StokerFlameIcon.flameOutline, style: StrokeStyle(lineWidth: size * 0.085, lineJoin: .round))
            .padding(size * 0.06),
        template: false)

    /// Alert variants (any tool's activation is in `.alert`): the same images with a small red
    /// dot at the top-right, baked into the NSImage because `MenuBarExtra` labels only render
    /// images faithfully. Fixed `Color.red` like the fixed ember colours — a pre-rendered image
    /// has no theme environment.
    static let liveFramesAlert: [NSImage] = (0..<3).map { frame in
        render(withAlertDot(StokerFlameIcon(active: true, frame: frame, size: size)), template: false)
    }
    static let coldAlert: NSImage = render(
        withAlertDot(FlameShape(frame: 0)
            .stroke(StokerFlameIcon.flameOutline, style: StrokeStyle(lineWidth: size * 0.085, lineJoin: .round))
            .padding(size * 0.06)),
        template: false)

    private static func withAlertDot(_ view: some View) -> some View {
        ZStack(alignment: .topTrailing) {
            view
            Circle().fill(Color.red).frame(width: 5, height: 5)
        }
        .frame(width: size, height: size)
    }

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
