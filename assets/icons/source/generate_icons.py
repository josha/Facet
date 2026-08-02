#!/usr/bin/env python3
"""Generate LuauUI's own standard icon set.

THE FRAMEWORK'S FIRST ART. Everything else in this repo is per-PACKAGE
(assets/themes/<pkg>/); this set is owned by the library itself and fills in
below a package's own art, above the ASCII fallback glyph.

WHY A SCRIPT AND NOT A GENERATOR MODEL. A 16-24px UI glyph has to be crisp and
pixel-aligned, which is exactly what AI raster generation is worst at. These are
flat geometry: a chevron, a tick, a plus and a bar are strokes, and a pencil is
three polygons. Drawing them at 8x and downsampling with LANCZOS gives clean
antialiased edges, and re-running this script reproduces every PNG byte for byte
-- the same convention every assets/themes/<pkg>/source/generate_art.py follows.

WHY NEAR-WHITE ON TRANSPARENCY, AND WHY ONLY ONE VERSION. `ImageColor3`
MULTIPLIES, so a white source reaches any colour a theme names while a black one
can only ever get darker. Measured across all 11 theme variants of the eight
reference packages, `tintRole = "content"` contrasts 3.31:1 to 15.62:1 against
the `control` plate these sit on -- dark in every light package, light in every
dark one. So one silhouette is correct everywhere and a light/dark pair would be
strictly worse. Nothing is baked in: the tint owns the colour completely.

Regenerate:  python3 assets/icons/source/generate_icons.py
"""

from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw

# ---------------------------------------------------------------- constants --
SIZE = 128  # the source-pixel size every icon is authored and uploaded at
SS = 8  # supersample factor; 128 * 8 = 1024
INK = (240, 240, 242, 255)  # #F0F0F2 -- near-white, so tintRole owns the colour
STROKE = 13  # stroke weight in 128-space; reads at 16px and holds at 24px

OUT = pathlib.Path(__file__).resolve().parent.parent


def _canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (SIZE * SS, SIZE * SS), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def _dot(draw: ImageDraw.ImageDraw, x: float, y: float, r: float) -> None:
    """A filled circle in 128-space, used for round caps, joins and the `more` dots."""
    cx, cy, cr = x * SS, y * SS, r * SS
    draw.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=INK)


def _stroke(draw: ImageDraw.ImageDraw, pts: list[tuple[float, float]], w: float = STROKE) -> None:
    """A round-capped, round-joined polyline in 128-space.

    PIL has no round cap, so the caps and joins are drawn as circles of the same
    radius. Doing it explicitly (rather than with `joint="curve"`, which only
    handles joins) is what keeps a chevron's tip from looking chipped at 16px.
    """
    scaled = [(x * SS, y * SS) for x, y in pts]
    draw.line(scaled, fill=INK, width=int(w * SS))
    for x, y in pts:
        _dot(draw, x, y, w / 2)


def _poly(draw: ImageDraw.ImageDraw, pts: list[tuple[float, float]]) -> None:
    draw.polygon([(x * SS, y * SS) for x, y in pts], fill=INK)


def _save(img: Image.Image, name: str) -> pathlib.Path:
    out = img.resize((SIZE, SIZE), Image.LANCZOS)
    path = OUT / f"{name}.png"
    out.save(path, "PNG", optimize=True)
    return path


# -------------------------------------------------------------------- icons --
# Every icon is drawn inside a 96px content area centred in the 128px box, so the
# whole set shares one optical weight and one margin. A control anchors these at
# the theme's `iconSizes` rung, so the margin is what keeps a 20px icon from
# touching a 20px plate's edge.


def chevron(direction: str) -> Image.Image:
    img, d = _canvas()
    # the tip sits ON centre and the arms open 40px out, so all four rotations
    # occupy the same optical box
    pts = {
        "left": [(80, 26), (46, 64), (80, 102)],
        "right": [(48, 26), (82, 64), (48, 102)],
        "up": [(26, 80), (64, 46), (102, 80)],
        "down": [(26, 48), (64, 82), (102, 48)],
    }[direction]
    _stroke(d, pts)
    return img


def check() -> Image.Image:
    img, d = _canvas()
    # a tick is a chevron with unequal arms; the long arm rises to the same
    # height the chevrons reach so the set stays optically level
    _stroke(d, [(28, 68), (52, 92), (100, 38)])
    return img


def close() -> Image.Image:
    img, d = _canvas()
    _stroke(d, [(34, 34), (94, 94)])
    _stroke(d, [(94, 34), (34, 94)])
    return img


def plus() -> Image.Image:
    img, d = _canvas()
    _stroke(d, [(64, 28), (64, 100)])
    _stroke(d, [(28, 64), (100, 64)])
    return img


def minus() -> Image.Image:
    img, d = _canvas()
    _stroke(d, [(28, 64), (100, 64)])
    return img


def menu() -> Image.Image:
    img, d = _canvas()
    for y in (40, 64, 88):
        _stroke(d, [(28, y), (100, y)])
    return img


def more() -> Image.Image:
    img, d = _canvas()
    # three dots, same weight as a stroke so `more` does not read lighter than
    # its neighbours in a toolbar
    for x in (34, 64, 94):
        _dot(d, x, 64, STROKE / 2 + 1)
    return img


def edit() -> Image.Image:
    """A pencil on the standard 45-degree diagonal, tip at lower-left.

    Filled rather than stroked: an outlined pencil loses its tip at 16px, and
    this is the one mark in the set that is a THING rather than a gesture. The
    three parts (tip, body, cap) are separated by the same 4px gap so the seams
    survive the downsample instead of merging into a bar.
    """
    img, d = _canvas()
    # tip: an isoceles triangle pointing down-left
    _poly(d, [(26, 102), (34, 74), (54, 94)])
    # body: the long shaft, parallel to the tip's axis
    _poly(d, [(38, 70), (82, 26), (102, 46), (58, 90)])
    # cap (the ferrule end), set off by a gap so it reads as a separate band
    _poly(d, [(86, 22), (96, 12), (116, 32), (106, 42)])
    return img


ICONS = {
    "luauui_icon_chevron_left": lambda: chevron("left"),
    "luauui_icon_chevron_right": lambda: chevron("right"),
    "luauui_icon_chevron_up": lambda: chevron("up"),
    "luauui_icon_chevron_down": lambda: chevron("down"),
    "luauui_icon_check": check,
    "luauui_icon_close": close,
    "luauui_icon_plus": plus,
    "luauui_icon_minus": minus,
    "luauui_icon_menu": menu,
    "luauui_icon_more": more,
    "luauui_icon_edit": edit,
}


def contact_sheet(images: dict[str, Image.Image]) -> None:
    """A no-Studio preview at the sizes these are actually drawn at.

    The whole point of the set is that it reads at 16-24px; a contact sheet at
    128px would prove nothing. Every icon appears at each `iconSizes` rung on a
    mid-grey so a near-white silhouette is visible without a tint.
    """
    rungs = [16, 20, 24, 48]
    pad, label_w = 12, 0
    cell_h = max(rungs) + pad
    sheet = Image.new(
        "RGBA",
        (label_w + sum(r + pad for r in rungs) + pad, cell_h * len(images) + pad),
        (96, 100, 108, 255),
    )
    for row, (name, img) in enumerate(sorted(images.items())):
        x = label_w + pad
        y = row * cell_h + pad
        for r in rungs:
            sheet.alpha_composite(img.resize((r, r), Image.LANCZOS), (x, y + (max(rungs) - r) // 2))
            x += r + pad
    preview = OUT / "source" / "preview"
    preview.mkdir(parents=True, exist_ok=True)
    sheet.save(preview / "contact-sheet.png", "PNG")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    built = {}
    for name, fn in ICONS.items():
        img = fn()
        path = _save(img, name)
        built[name] = Image.open(path).convert("RGBA")
        print(f"  {path.name}  {SIZE}x{SIZE}")
    contact_sheet(built)
    print(f"{len(built)} icons + contact sheet -> {OUT}")


if __name__ == "__main__":
    main()
