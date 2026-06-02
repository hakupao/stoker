#!/usr/bin/env python3
from __future__ import annotations

import json
import math
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
LOGO = ASSETS / "logo"
ICONS = ASSETS / "icons"
PNG = ASSETS / "png"
MOCKUPS = ASSETS / "mockups"
PREVIEW = ROOT / "preview"

COLORS = {
    "graphite": "#171716",
    "graphite_2": "#232323",
    "ink": "#0E0F0D",
    "ember": "#E36E43",
    "ember_hot": "#FFB15E",
    "copper": "#B97A54",
    "ivory": "#F3EEE6",
    "ash": "#D6D0C7",
    "sage": "#9EB392",
    "sage_deep": "#64755F",
    "mist": "#EAF0E9",
    "ok": "#43B86C",
    "warn": "#D89D38",
    "danger": "#DC5B54",
}


def ensure_dirs() -> None:
    for path in [
        LOGO,
        ICONS / "cue",
        ICONS / "status",
        ICONS / "menubar",
        PNG / "app-icon",
        PNG / "cue",
        PNG / "status",
        PNG / "menubar",
        PNG / "scene",
    ]:
        path.mkdir(parents=True, exist_ok=True)


def hex_to_rgba(value: str, alpha: int = 255) -> tuple[int, int, int, int]:
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), alpha)


def mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    t = max(0.0, min(1.0, t))
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rounded_linear_gradient(
    size: int,
    rect: tuple[int, int, int, int],
    radius: int,
    stops: list[str],
) -> Image.Image:
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    x0, y0, x1, y1 = rect
    w = x1 - x0
    h = y1 - y0
    colors = [hex_to_rgba(stop)[:3] for stop in stops]
    for y in range(y0, y1):
        for x in range(x0, x1):
            pos = ((x - x0) / max(1, w) * 0.68) + ((y - y0) / max(1, h) * 0.32)
            if pos < 0.58:
                c = mix(colors[0], colors[1], pos / 0.58)
            else:
                c = mix(colors[1], colors[2], (pos - 0.58) / 0.42)
            layer.putpixel((x, y), (*c, 255))

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(rect, radius=radius, fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.alpha_composite(layer)
    out.putalpha(mask)
    return out


def radial_glow(
    size: int,
    center: tuple[float, float],
    radius: float,
    inner: str,
    outer: str,
    alpha: int = 255,
) -> Image.Image:
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ci = hex_to_rgba(inner)[:3]
    co = hex_to_rgba(outer)[:3]
    cx, cy = center
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - cx, y - cy) / radius
            if d <= 1:
                t = d * d
                c = mix(ci, co, t)
                a = int(alpha * (1 - d) ** 1.7)
                layer.putpixel((x, y), (*c, a))
    return layer


def draw_arc(draw: ImageDraw.ImageDraw, bbox: tuple[int, int, int, int], start: int, end: int, fill: str, width: int) -> None:
    draw.arc(bbox, start=start, end=end, fill=fill, width=width)


def draw_app_icon(size: int) -> Image.Image:
    s = size / 1024
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rect = tuple(int(v * s) for v in (46, 46, 978, 978))
    image.alpha_composite(
        rounded_linear_gradient(
            size,
            rect,
            int(218 * s),
            ["#121211", "#242522", "#374033"],
        )
    )
    draw = ImageDraw.Draw(image)

    # Outer polish.
    draw.rounded_rectangle(rect, radius=int(218 * s), outline=hex_to_rgba("#F3EEE6", 38), width=max(1, int(5 * s)))
    draw.rounded_rectangle(
        tuple(int(v * s) for v in (67, 67, 957, 957)),
        radius=int(198 * s),
        outline=hex_to_rgba("#000000", 70),
        width=max(1, int(6 * s)),
    )

    image.alpha_composite(radial_glow(size, (512 * s, 548 * s), 360 * s, COLORS["ember_hot"], COLORS["ember"], 178))
    image.alpha_composite(radial_glow(size, (728 * s, 342 * s), 315 * s, COLORS["sage"], COLORS["sage_deep"], 92))
    draw = ImageDraw.Draw(image)

    ring = tuple(int(v * s) for v in (226, 218, 798, 790))
    draw_arc(draw, ring, 200, 494, hex_to_rgba("#0B0C0A", 210), int(54 * s))
    draw_arc(draw, ring, 205, 365, hex_to_rgba(COLORS["copper"], 230), int(7 * s))
    draw_arc(draw, ring, -46, 84, hex_to_rgba(COLORS["sage"], 235), int(42 * s))
    draw_arc(draw, ring, -46, 84, hex_to_rgba("#F3EEE6", 55), int(5 * s))

    cx, cy = 512 * s, 512 * s
    for idx in range(12):
        angle = math.radians(idx * 30 - 90)
        length = 34 if idx % 3 == 0 else 22
        r1 = 279 * s
        r2 = (279 + length) * s
        p1 = (cx + math.cos(angle) * r1, cy + math.sin(angle) * r1)
        p2 = (cx + math.cos(angle) * r2, cy + math.sin(angle) * r2)
        draw.line([p1, p2], fill=hex_to_rgba(COLORS["copper"], 230), width=max(2, int(8 * s)))

    # Central aperture, intentionally simple at small sizes.
    aperture = tuple(int(v * s) for v in (332, 328, 692, 688))
    for offset, (start, end) in enumerate([(18, 132), (138, 252), (258, 372)]):
        draw_arc(draw, aperture, start, end, hex_to_rgba("#111210", 248), int(84 * s))
        draw_arc(draw, aperture, start + 2, end - 3, hex_to_rgba("#F3EEE6", 38), int(5 * s))
        draw_arc(draw, aperture, start + 78, end + 12, hex_to_rgba(COLORS["ember"], 150), int(5 * s))

    ember_box = tuple(int(v * s) for v in (420, 418, 604, 602))
    image.alpha_composite(radial_glow(size, (512 * s, 512 * s), 122 * s, COLORS["ember_hot"], COLORS["ember"], 250))
    draw = ImageDraw.Draw(image)
    draw.ellipse(ember_box, fill=hex_to_rgba("#F07845", 242))
    draw.ellipse(tuple(int(v * s) for v in (458, 452, 566, 582)), fill=hex_to_rgba("#FFC36E", 196))

    # Quota bead.
    bead = tuple(int(v * s) for v in (724, 463, 806, 545))
    draw.ellipse(bead, fill=hex_to_rgba("#AFC29E", 232), outline=hex_to_rgba("#EAF0E9", 90), width=max(1, int(4 * s)))
    draw.ellipse(tuple(int(v * s) for v in (749, 488, 781, 520)), fill=hex_to_rgba(COLORS["mist"], 235))
    return image


# macOS .iconset slots mapped to (pixel size, detail-tier SVG basename).
# Apple .iconset supports per-size art; small slots use simplified variants so they
# stay legible instead of turning to mud when single-downscaled. See THEME.md §11.
#   16px  -> body + ember disc + one sage arc stub (no ring/ticks/aperture)
#   32px  -> + a single thin ring
#   64px  -> + the 6-blade aperture (still no ticks)
#   128px+ -> full detail incl. ticks + copper hairline (the canonical master)
ICONSET_SLOTS = [
    ("icon_16x16.png", 16, "stoker-app-icon-16.svg"),
    ("icon_16x16@2x.png", 32, "stoker-app-icon-32.svg"),
    ("icon_32x32.png", 32, "stoker-app-icon-32.svg"),
    ("icon_32x32@2x.png", 64, "stoker-app-icon-64.svg"),
    ("icon_128x128.png", 128, "stoker-app-icon-source.svg"),
    ("icon_128x128@2x.png", 256, "stoker-app-icon-source.svg"),
    ("icon_256x256.png", 256, "stoker-app-icon-source.svg"),
    ("icon_256x256@2x.png", 512, "stoker-app-icon-source.svg"),
    ("icon_512x512.png", 512, "stoker-app-icon-source.svg"),
    ("icon_512x512@2x.png", 1024, "stoker-app-icon-source.svg"),
]


def _find_svg_renderer() -> list[str] | None:
    """Return an argv-prefix command that rasterizes an SVG to a PNG at a fixed size.

    Tries rsvg-convert, then resvg, then cairosvg (python module). Returns None when no
    real renderer is available so callers can degrade gracefully instead of faking it.
    """
    if shutil.which("rsvg-convert"):
        return ["rsvg-convert"]
    if shutil.which("resvg"):
        return ["resvg"]
    try:
        import cairosvg  # noqa: F401

        return ["__cairosvg__"]
    except ImportError:
        return None


def _render_svg_to_png(renderer: list[str], svg: Path, out: Path, px: int) -> None:
    if renderer[0] == "rsvg-convert":
        subprocess.run(
            ["rsvg-convert", "-w", str(px), "-h", str(px), str(svg), "-o", str(out)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    elif renderer[0] == "resvg":
        subprocess.run(
            ["resvg", "-w", str(px), "-h", str(px), str(svg), str(out)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    else:  # cairosvg python module
        import cairosvg

        cairosvg.svg2png(
            url=str(svg), write_to=str(out), output_width=px, output_height=px
        )


def save_app_icons() -> None:
    """Render the macOS iconset deterministically from the hand-authored SVG sources.

    Each slot is rasterized at its exact pixel size from the appropriate detail-tier SVG,
    then assembled into Stoker.icns via iconutil. Falls back to the legacy PIL drawing only
    if no real SVG renderer is installed (so the pack still builds), printing a warning.
    """
    iconset = PNG / "app-icon" / "AppIcon.iconset"
    iconset.mkdir(parents=True, exist_ok=True)

    renderer = _find_svg_renderer()
    master_svg = LOGO / "stoker-app-icon-source.svg"

    if renderer is None or not master_svg.exists():
        print(
            "WARNING: no SVG renderer (rsvg-convert/resvg/cairosvg) found; "
            "falling back to legacy PIL app-icon drawing.",
        )
        master = draw_app_icon(1024)
        master.save(PNG / "app-icon" / "stoker-app-icon-1024.png")
        for name, px, _svg in ICONSET_SLOTS:
            master.resize((px, px), Image.Resampling.LANCZOS).save(iconset / name)
    else:
        for name, px, svg_name in ICONSET_SLOTS:
            _render_svg_to_png(renderer, LOGO / svg_name, iconset / name, px)
        # 1024 master preview alongside the iconset.
        _render_svg_to_png(
            renderer, master_svg, PNG / "app-icon" / "stoker-app-icon-1024.png", 1024
        )

    try:
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset), "-o", str(PNG / "app-icon" / "Stoker.icns")],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass


def glyph_canvas(size: int = 128) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image)


def draw_clock(draw: ImageDraw.ImageDraw, color: str, accent: str) -> None:
    draw.arc((24, 20, 104, 100), 210, 500, fill=hex_to_rgba(color), width=8)
    draw.line((64, 60, 64, 34), fill=hex_to_rgba(color), width=7)
    draw.line((64, 60, 86, 60), fill=hex_to_rgba(color), width=7)
    draw.ellipse((55, 51, 73, 69), fill=hex_to_rgba(accent))


def draw_quota(draw: ImageDraw.ImageDraw, color: str, accent: str) -> None:
    draw.arc((22, 24, 106, 108), 190, 350, fill=hex_to_rgba("#3A3A36", 170), width=10)
    draw.arc((22, 24, 106, 108), 190, 298, fill=hex_to_rgba(color), width=10)
    draw.ellipse((78, 77, 96, 95), fill=hex_to_rgba(accent))
    draw.rounded_rectangle((45, 54, 83, 76), radius=10, outline=hex_to_rgba(color), width=6)


def draw_tools(draw: ImageDraw.ImageDraw, color: str, accent: str) -> None:
    draw.rounded_rectangle((24, 34, 68, 78), radius=16, outline=hex_to_rgba(color), width=7)
    draw.rounded_rectangle((60, 50, 104, 94), radius=16, outline=hex_to_rgba(accent), width=7)
    draw.line((55, 64, 73, 64), fill=hex_to_rgba(COLORS["ivory"]), width=5)


def draw_awake(draw: ImageDraw.ImageDraw, color: str, accent: str) -> None:
    draw.ellipse((31, 24, 93, 86), fill=hex_to_rgba(color, 80))
    draw.pieslice((45, 16, 109, 92), 90, 270, fill=(0, 0, 0, 0))
    draw.arc((31, 24, 93, 86), 80, 315, fill=hex_to_rgba(color), width=8)
    draw.ellipse((82, 76, 98, 92), fill=hex_to_rgba(accent))


def draw_run(draw: ImageDraw.ImageDraw, color: str, accent: str) -> None:
    draw.polygon([(43, 30), (43, 98), (96, 64)], fill=hex_to_rgba(color))
    draw.ellipse((22, 51, 38, 67), fill=hex_to_rgba(accent))
    draw.arc((19, 18, 110, 110), 218, 322, fill=hex_to_rgba(accent), width=5)


def draw_logs(draw: ImageDraw.ImageDraw, color: str, accent: str) -> None:
    for idx, y in enumerate([30, 50, 70, 90]):
        draw.rounded_rectangle((28, y, 100, y + 10), radius=5, fill=hex_to_rgba(color if idx != 1 else accent))
        draw.ellipse((16, y, 26, y + 10), fill=hex_to_rgba(accent if idx != 1 else color))


def draw_export(draw: ImageDraw.ImageDraw, color: str, accent: str) -> None:
    draw.rounded_rectangle((27, 52, 101, 100), radius=12, outline=hex_to_rgba(color), width=7)
    draw.line((64, 26, 64, 73), fill=hex_to_rgba(accent), width=7)
    draw.line((44, 46, 64, 26, 84, 46), fill=hex_to_rgba(accent), width=7)


def draw_settings(draw: ImageDraw.ImageDraw, color: str, accent: str) -> None:
    for x, y in [(36, 38), (64, 64), (92, 90)]:
        draw.line((x, 24, x, 104), fill=hex_to_rgba(color), width=6)
        draw.ellipse((x - 10, y - 10, x + 10, y + 10), fill=hex_to_rgba(accent))


def draw_language(draw: ImageDraw.ImageDraw, color: str, accent: str) -> None:
    draw.ellipse((20, 24, 88, 92), outline=hex_to_rgba(color), width=7)
    draw.arc((34, 24, 74, 92), 80, 280, fill=hex_to_rgba(color), width=5)
    draw.line((22, 58, 86, 58), fill=hex_to_rgba(color), width=5)
    draw.rounded_rectangle((72, 70, 108, 100), radius=8, fill=hex_to_rgba(accent))


def draw_status(draw: ImageDraw.ImageDraw, color: str, accent: str, mode: str) -> None:
    draw.ellipse((24, 24, 104, 104), fill=hex_to_rgba(color, 42), outline=hex_to_rgba(color), width=8)
    if mode == "active":
        draw.line((45, 67, 58, 80, 85, 49), fill=hex_to_rgba(accent), width=9)
    elif mode == "paused":
        draw.rounded_rectangle((46, 43, 57, 85), radius=5, fill=hex_to_rgba(accent))
        draw.rounded_rectangle((71, 43, 82, 85), radius=5, fill=hex_to_rgba(accent))
    elif mode == "warning":
        draw.polygon([(64, 38), (92, 86), (36, 86)], outline=hex_to_rgba(accent))
        draw.line((64, 54, 64, 72), fill=hex_to_rgba(accent), width=7)
        draw.ellipse((60, 77, 68, 85), fill=hex_to_rgba(accent))
    else:
        draw.line((48, 48, 80, 80), fill=hex_to_rgba(accent), width=8)
        draw.line((80, 48, 48, 80), fill=hex_to_rgba(accent), width=8)


GLYPHS = {
    "cue-schedule": draw_clock,
    "cue-quota": draw_quota,
    "cue-tools": draw_tools,
    "cue-keep-awake": draw_awake,
    "cue-run-now": draw_run,
    "cue-logs": draw_logs,
    "cue-export": draw_export,
    "cue-settings": draw_settings,
    "cue-language": draw_language,
}


def save_glyph_pngs() -> None:
    for name, fn in GLYPHS.items():
        image, draw = glyph_canvas()
        fn(draw, COLORS["ivory"], COLORS["ember"])
        image.save(PNG / "cue" / f"{name}.png")

    for mode, color in [
        ("active", COLORS["ok"]),
        ("paused", COLORS["sage"]),
        ("warning", COLORS["warn"]),
        ("error", COLORS["danger"]),
    ]:
        image, draw = glyph_canvas()
        draw_status(draw, color, COLORS["ivory"], mode)
        image.save(PNG / "status" / f"status-{mode}.png")

    # Menu bar template raster: a SINGLE pure-black-on-alpha image (macOS tints templates
    # itself, so no white sibling). Rendered straight from the canonical SVG when a real
    # renderer is available so the bundle art matches the vector exactly, at 18px (@1x) and
    # 36px (@2x) for a ~18pt menu bar slot. Falls back to PIL drawing the simplified
    # single-arc + centered-dot mark if no renderer is present.
    menubar_svg = ICONS / "menubar" / "stoker-menubar-template-black.svg"
    renderer = _find_svg_renderer()
    if renderer is not None and menubar_svg.exists():
        _render_svg_to_png(renderer, menubar_svg, PNG / "menubar" / "stoker-menubar-template-black.png", 18)
        _render_svg_to_png(renderer, menubar_svg, PNG / "menubar" / "stoker-menubar-template-black@2x.png", 36)
    else:
        for px, suffix in [(18, ""), (36, "@2x")]:
            image = Image.new("RGBA", (px, px), (0, 0, 0, 0))
            draw = ImageDraw.Draw(image)
            s = px / 64
            ring = (10 * s, 10 * s, 54 * s, 54 * s)  # ring bbox centered on (32,32)
            draw.arc(ring, start=10, end=350, fill=(0, 0, 0, 255), width=max(1, round(5 * s)))
            r = 7 * s
            draw.ellipse((32 * s - r, 32 * s - r, 32 * s + r, 32 * s + r), fill=(0, 0, 0, 255))
            image.save(PNG / "menubar" / f"stoker-menubar-template-black{suffix}.png")


def save_scene_pngs() -> None:
    image = Image.new("RGBA", (1200, 760), hex_to_rgba("#F8F5EF"))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((70, 70, 1130, 690), radius=36, fill=hex_to_rgba("#FFFFFF"), outline=hex_to_rgba("#DDD5C8"), width=2)
    draw.rounded_rectangle((110, 114, 1090, 180), radius=24, fill=hex_to_rgba("#191917"))
    draw.text((150, 133), "Stoker", fill=hex_to_rgba(COLORS["ivory"]), font=ImageFont.load_default())
    for x in [150, 310, 470, 630]:
        draw.rounded_rectangle((x, 238, x + 110, 282), radius=22, fill=hex_to_rgba("#F3EEE6"))
    draw.line((160, 440, 1040, 440), fill=hex_to_rgba("#D9D2C8"), width=3)
    pts = [(160, 500), (300, 456), (460, 474), (610, 390), (760, 418), (900, 360), (1040, 376)]
    draw.line(pts, fill=hex_to_rgba(COLORS["sage_deep"]), width=8, joint="curve")
    draw.line([(x, y + 58) for x, y in pts], fill=hex_to_rgba(COLORS["ember"]), width=8, joint="curve")
    image.alpha_composite(draw_app_icon(180), (510, 248))
    image.save(MOCKUPS / "stoker-main-window-concept.png")

    empty = Image.new("RGBA", (880, 520), hex_to_rgba("#F8F5EF"))
    draw = ImageDraw.Draw(empty)
    draw.rounded_rectangle((80, 70, 800, 450), radius=34, fill=hex_to_rgba("#FFFFFF"), outline=hex_to_rgba("#E0D8CD"), width=2)
    draw.arc((292, 140, 588, 436), 205, 493, fill=hex_to_rgba(COLORS["graphite"]), width=20)
    draw.arc((292, 140, 588, 436), -40, 78, fill=hex_to_rgba(COLORS["sage"]), width=18)
    draw.ellipse((400, 250, 480, 330), fill=hex_to_rgba(COLORS["ember"]))
    draw.line((346, 380, 534, 380), fill=hex_to_rgba("#D8D0C4"), width=8)
    empty.save(PNG / "scene" / "empty-state-ember.png")


def write_svg_files() -> None:
    mark = f"""<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128" role="img" aria-label="Stoker mark">
  <defs>
    <linearGradient id="ember" x1="36" y1="30" x2="92" y2="98" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="{COLORS['ember_hot']}"/>
      <stop offset="1" stop-color="{COLORS['ember']}"/>
    </linearGradient>
  </defs>
  <rect x="10" y="10" width="108" height="108" rx="30" fill="{COLORS['graphite']}"/>
  <path d="M31 76a38 38 0 0 1 55-45" fill="none" stroke="{COLORS['copper']}" stroke-width="7" stroke-linecap="round"/>
  <path d="M87 33a38 38 0 0 1 15 43" fill="none" stroke="{COLORS['sage']}" stroke-width="9" stroke-linecap="round"/>
  <path d="M42 71c14-4 19-14 22-28 9 14 22 22 39 22-12 10-20 18-24 35-9-14-20-22-37-29z" fill="{COLORS['ink']}" stroke="{COLORS['ember']}" stroke-width="2" stroke-linejoin="round"/>
  <circle cx="64" cy="70" r="16" fill="url(#ember)"/>
  <circle cx="93" cy="72" r="5" fill="{COLORS['mist']}"/>
</svg>
"""
    (LOGO / "stoker-mark.svg").write_text(mark, encoding="utf-8")

    wordmark = f"""<svg xmlns="http://www.w3.org/2000/svg" width="320" height="92" viewBox="0 0 320 92" role="img" aria-label="Stoker wordmark">
  <rect width="320" height="92" rx="18" fill="none"/>
  <text x="0" y="66" fill="{COLORS['graphite']}" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', Inter, Helvetica, Arial, sans-serif" font-size="72" font-weight="650" letter-spacing="0">Stoker</text>
</svg>
"""
    (LOGO / "stoker-wordmark.svg").write_text(wordmark, encoding="utf-8")

    lockup = f"""<svg xmlns="http://www.w3.org/2000/svg" width="520" height="140" viewBox="0 0 520 140" role="img" aria-label="Stoker logo lockup">
  <rect width="520" height="140" rx="28" fill="{COLORS['ivory']}"/>
  <g transform="translate(26 6)">{mark.split('<svg', 1)[1].split('>', 1)[1].rsplit('</svg>', 1)[0]}</g>
  <text x="168" y="87" fill="{COLORS['graphite']}" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', Inter, Helvetica, Arial, sans-serif" font-size="70" font-weight="650" letter-spacing="0">Stoker</text>
  <circle cx="468" cy="72" r="7" fill="{COLORS['ember']}"/>
</svg>
"""
    (LOGO / "stoker-lockup-horizontal.svg").write_text(lockup, encoding="utf-8")

    # The app-icon SVGs (stoker-app-icon-source.svg + the 16/32/64 detail-tier variants)
    # are now HAND-AUTHORED canonical vector sources and the single source of truth for the
    # iconset; this generator renders them but must NOT overwrite them. See save_app_icons().

    # Menu bar mark: a single template image only. macOS auto-tints template images for
    # light/dark menu bars and the highlighted state, so we ship ONE pure-black-on-alpha
    # variant (no white sibling). Simplified single schedule-sweep arc + centered ember dot,
    # optically centered on (32,32) so it stays crisp at 16-18px instead of mudding.
    (ICONS / "menubar" / "stoker-menubar-template-black.svg").write_text(
        """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" role="img" aria-label="Stoker menu bar template icon">
  <path d="M45.789 43.57A18 18 0 1 0 18.211 43.57" fill="none" stroke="#000000" stroke-width="5" stroke-linecap="round"/>
  <circle cx="32" cy="32" r="7" fill="#000000"/>
</svg>
""",
        encoding="utf-8",
    )

    icon_svgs = {
        "cue-schedule.svg": "<path d='M18 39a22 22 0 0 1 33-26' fill='none' stroke='{ivory}' stroke-width='4' stroke-linecap='round'/><path d='M32 31V17M32 31h14' stroke='{ivory}' stroke-width='4' stroke-linecap='round'/><circle cx='32' cy='31' r='5' fill='{ember}'/>",
        "cue-quota.svg": "<path d='M16 43a24 24 0 0 1 48 0' fill='none' stroke='#4a4a45' stroke-width='5' stroke-linecap='round'/><path d='M16 43a24 24 0 0 1 35-21' fill='none' stroke='{sage}' stroke-width='5' stroke-linecap='round'/><circle cx='52' cy='42' r='5' fill='{ember}'/>",
        "cue-tools.svg": "<rect x='12' y='19' width='28' height='28' rx='10' fill='none' stroke='{ivory}' stroke-width='4'/><rect x='30' y='27' width='28' height='28' rx='10' fill='none' stroke='{ember}' stroke-width='4'/>",
        "cue-keep-awake.svg": "<path d='M42 12a23 23 0 1 0 10 43 20 20 0 0 1-10-43z' fill='none' stroke='{ivory}' stroke-width='4' stroke-linejoin='round'/><circle cx='50' cy='49' r='5' fill='{ember}'/>",
        "cue-run-now.svg": "<path d='M22 15v34l28-17z' fill='{ivory}'/><path d='M11 32h8' stroke='{ember}' stroke-width='4' stroke-linecap='round'/>",
        "cue-logs.svg": "<path d='M18 20h34M18 32h34M18 44h34' stroke='{ivory}' stroke-width='5' stroke-linecap='round'/><circle cx='11' cy='20' r='3' fill='{ember}'/><circle cx='11' cy='32' r='3' fill='{ember}'/><circle cx='11' cy='44' r='3' fill='{ember}'/>",
        "cue-export.svg": "<rect x='15' y='30' width='34' height='22' rx='6' fill='none' stroke='{ivory}' stroke-width='4'/><path d='M32 12v28M21 24l11-12 11 12' stroke='{ember}' stroke-width='4' stroke-linecap='round' stroke-linejoin='round'/>",
        "cue-settings.svg": "<path d='M20 14v36M32 14v36M44 14v36' stroke='{ivory}' stroke-width='4' stroke-linecap='round'/><circle cx='20' cy='25' r='5' fill='{ember}'/><circle cx='32' cy='37' r='5' fill='{ember}'/><circle cx='44' cy='29' r='5' fill='{ember}'/>",
        "cue-language.svg": "<circle cx='28' cy='30' r='20' fill='none' stroke='{ivory}' stroke-width='4'/><path d='M9 30h38M28 10c7 10 7 30 0 40' stroke='{ivory}' stroke-width='3' fill='none'/><rect x='41' y='38' width='15' height='13' rx='4' fill='{ember}'/>",
    }
    for filename, body in icon_svgs.items():
        svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" role="img" aria-label="{filename[:-4]}">
  {body.format(ivory=COLORS['ivory'], ember=COLORS['ember'], sage=COLORS['sage'])}
</svg>
"""
        (ICONS / "cue" / filename).write_text(svg, encoding="utf-8")

    status_svg = {
        "status-active.svg": (COLORS["ok"], "<path d='M20 33l8 8 17-20' stroke='{accent}' stroke-width='5' fill='none' stroke-linecap='round' stroke-linejoin='round'/>"),
        "status-paused.svg": (COLORS["sage"], "<rect x='24' y='21' width='6' height='24' rx='3' fill='{accent}'/><rect x='36' y='21' width='6' height='24' rx='3' fill='{accent}'/>"),
        "status-warning.svg": (COLORS["warn"], "<path d='M32 18l18 31H14z' fill='none' stroke='{accent}' stroke-width='4' stroke-linejoin='round'/><path d='M32 29v10' stroke='{accent}' stroke-width='4' stroke-linecap='round'/><circle cx='32' cy='44' r='2.5' fill='{accent}'/>"),
        "status-error.svg": (COLORS["danger"], "<path d='M23 23l18 18M41 23L23 41' stroke='{accent}' stroke-width='5' stroke-linecap='round'/>"),
    }
    for filename, (color, body) in status_svg.items():
        (ICONS / "status" / filename).write_text(
            f"""<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" role="img" aria-label="{filename[:-4]}">
  <circle cx="32" cy="32" r="25" fill="{color}" opacity=".16"/>
  <circle cx="32" cy="32" r="25" fill="none" stroke="{color}" stroke-width="4"/>
  {body.format(accent=COLORS['ivory'])}
</svg>
""",
            encoding="utf-8",
        )


def write_docs() -> None:
    tokens = {
        "name": "Stoker",
        "positioning": "A quiet macOS utility that tends AI usage windows and quota signals on schedule.",
        "palette": COLORS,
        "typography": {
            "display": "SF Pro Display Semibold or system equivalent",
            "ui": "SF Pro Text / system",
            "mono": "SF Mono for log and JSON surfaces",
        },
        "icon_principles": [
            "No literal flame as the primary shape.",
            "Use ember, aperture, time arc, and quota bead as the recurring motif.",
            "Keep menu bar assets monochrome and template-friendly.",
            "Use warm ember sparingly against graphite and ivory surfaces.",
        ],
    }
    (ROOT / "brand-tokens.json").write_text(json.dumps(tokens, indent=2) + "\n", encoding="utf-8")


def write_preview() -> None:
    css = f"""html {{
  color-scheme: light;
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", Inter, Helvetica, Arial, sans-serif;
  background: #f7f3ec;
  color: {COLORS['graphite']};
}}
body {{
  margin: 0;
  padding: 48px;
}}
.shell {{
  max-width: 1120px;
  margin: 0 auto;
}}
.hero {{
  display: grid;
  grid-template-columns: 210px 1fr;
  align-items: center;
  gap: 34px;
  padding: 36px;
  border: 1px solid #ded7cd;
  border-radius: 28px;
  background: #fffaf2;
}}
.hero img {{
  width: 180px;
  height: 180px;
}}
h1 {{
  font-size: 64px;
  line-height: 1;
  margin: 0 0 12px;
  letter-spacing: 0;
}}
p {{
  color: #5f5b54;
  font-size: 18px;
  line-height: 1.5;
  margin: 0;
}}
.grid {{
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 18px;
  margin-top: 24px;
}}
.card {{
  border: 1px solid #ded7cd;
  border-radius: 18px;
  background: #fffaf2;
  padding: 20px;
}}
.card h2 {{
  margin: 0 0 14px;
  font-size: 17px;
}}
.swatches {{
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: 10px;
}}
.swatch {{
  height: 54px;
  border-radius: 14px;
  border: 1px solid rgba(0,0,0,.08);
}}
.icons {{
  display: grid;
  grid-template-columns: repeat(4, 48px);
  gap: 12px;
}}
.icons img {{
  width: 48px;
  height: 48px;
  object-fit: contain;
  background: #171716;
  border-radius: 12px;
  padding: 6px;
  box-sizing: border-box;
}}
.wide {{
  grid-column: span 3;
}}
.mockup {{
  width: 100%;
  border-radius: 16px;
  border: 1px solid #ded7cd;
}}
"""
    (PREVIEW / "styles.css").write_text(css, encoding="utf-8")

    icon_list = "\n".join(
        f'<img src="../assets/png/cue/{name}.png" alt="{name}">' for name in GLYPHS.keys()
    )
    status_list = "\n".join(
        f'<img src="../assets/png/status/status-{name}.png" alt="{name}">' for name in ["active", "paused", "warning", "error"]
    )
    swatches = "\n".join(
        f'<div class="swatch" title="{key}" style="background:{value}"></div>'
        for key, value in COLORS.items()
        if key in ["graphite", "ember", "copper", "ivory", "sage", "mist", "ok", "warn", "danger", "ash"]
    )
    html = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Stoker UI Pack Preview</title>
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <main class="shell">
    <section class="hero">
      <img src="../assets/png/app-icon/stoker-app-icon-1024.png" alt="Stoker app icon">
      <div>
        <h1>Stoker</h1>
        <p>A quiet macOS utility that tends AI usage windows, quota signals, and scheduled READY check-ins.</p>
      </div>
    </section>
    <section class="grid">
      <div class="card">
        <h2>Palette</h2>
        <div class="swatches">{swatches}</div>
      </div>
      <div class="card">
        <h2>Option Cues</h2>
        <div class="icons">{icon_list}</div>
      </div>
      <div class="card">
        <h2>Status</h2>
        <div class="icons">{status_list}</div>
      </div>
      <div class="card wide">
        <h2>Main Window Direction</h2>
        <img class="mockup" src="../assets/mockups/stoker-main-window-concept.png" alt="Stoker main window concept">
      </div>
    </section>
  </main>
</body>
</html>
"""
    (PREVIEW / "index.html").write_text(html, encoding="utf-8")


def save_preview_sheet() -> None:
    sheet = Image.new("RGBA", (1600, 1100), hex_to_rgba("#F7F3EC"))
    draw = ImageDraw.Draw(sheet)
    title_font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 56)
    body_font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 24)
    draw.text((80, 62), "Stoker UI Pack", fill=hex_to_rgba(COLORS["graphite"]), font=title_font)
    draw.text((82, 130), "Candidate art only. Nothing has been replaced.", fill=hex_to_rgba("#69635B"), font=body_font)
    sheet.alpha_composite(draw_app_icon(280), (80, 210))
    draw.text((420, 236), "Quiet ember + schedule arc + quota bead", fill=hex_to_rgba(COLORS["graphite"]), font=body_font)
    for idx, key in enumerate(["graphite", "ember", "copper", "ivory", "sage", "mist", "ok", "warn", "danger"]):
        x = 420 + (idx % 5) * 140
        y = 300 + (idx // 5) * 92
        draw.rounded_rectangle((x, y, x + 110, y + 50), radius=14, fill=hex_to_rgba(COLORS[key]), outline=hex_to_rgba("#CFC7BA"))
        draw.text((x, y + 58), key, fill=hex_to_rgba("#69635B"), font=body_font)

    x0, y0 = 80, 560
    draw.text((x0, y0 - 55), "Option cues", fill=hex_to_rgba(COLORS["graphite"]), font=body_font)
    for idx, name in enumerate(GLYPHS.keys()):
        icon = Image.open(PNG / "cue" / f"{name}.png").resize((72, 72), Image.Resampling.LANCZOS)
        x = x0 + idx * 116
        y = y0
        draw.rounded_rectangle((x - 10, y - 10, x + 82, y + 82), radius=18, fill=hex_to_rgba(COLORS["graphite"]))
        sheet.alpha_composite(icon, (x, y))

    draw.text((80, 760), "Main window direction", fill=hex_to_rgba(COLORS["graphite"]), font=body_font)
    mockup = Image.open(MOCKUPS / "stoker-main-window-concept.png").resize((680, 431), Image.Resampling.LANCZOS)
    sheet.alpha_composite(mockup, (80, 810))
    scene = Image.open(PNG / "scene" / "empty-state-ember.png").resize((520, 307), Image.Resampling.LANCZOS)
    sheet.alpha_composite(scene, (820, 835))
    sheet.convert("RGB").save(PREVIEW / "stoker-ui-pack-preview.png", quality=95)


def main() -> None:
    ensure_dirs()
    save_app_icons()
    # write_svg_files() before save_glyph_pngs(): the menu bar template PNGs are rendered
    # straight from the menu bar template SVG, so the vector must exist on disk first.
    write_svg_files()
    save_glyph_pngs()
    save_scene_pngs()
    write_docs()
    # Candidate-only docs (README/preview/research-notes/prompts) and the preview sheet are no
    # longer generated: the pack ships committed assets and a hand-maintained README, so a build
    # no longer overwrites the README or recreates retired concept files.
    print(f"Generated Stoker UI pack at {ROOT}")


if __name__ == "__main__":
    main()
