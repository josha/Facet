#!/usr/bin/env python3
"""Generate Facet's own standard icon set.

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


def _ring(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float, w: float = STROKE) -> None:
    """A circular outline in 128-space, at the set's stroke weight.

    PIL draws an ellipse outline INWARD from the bounding box, so `r` is the
    outer radius and the ink occupies `r - w` to `r`. That is what keeps a ring
    the same optical size as the chevrons, which measure to their outer arms.
    """
    draw.ellipse(
        [(cx - r) * SS, (cy - r) * SS, (cx + r) * SS, (cy + r) * SS],
        outline=INK,
        width=int(w * SS),
    )


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


def chevron_up_down() -> Image.Image:
    """The pop-up button's stacked pair (Picker `style = "menu"`, 2026-09-11):
    a small up chevron over a small down one, each arm 28px out so the pair
    sits inside the same 96px content box at the set's stroke weight."""
    img, d = _canvas()
    _stroke(d, [(36, 52), (64, 26), (92, 52)])
    _stroke(d, [(36, 76), (64, 102), (92, 76)])
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


def trash() -> Image.Image:
    """A waste bin: a handle loop, a lid bar, and a tapered open container.

    Three independent strokes, the same budget as `menu`'s three bars. The lid
    (28-100) reads wider than the body's top corners (36-92) and the handle
    loop rides above the lid's centre -- the real object's own silhouette, not
    a modelling accident -- so the mark still reads as a bin rather than a
    generic box once it downsamples to 16px.
    """
    img, d = _canvas()
    _stroke(d, [(54, 40), (54, 28), (74, 28), (74, 40)])  # handle: a loop above the lid
    _stroke(d, [(28, 40), (100, 40)])  # lid
    _stroke(d, [(36, 44), (42, 100), (86, 100), (92, 44)])  # body: tapered open container
    return img


def flag() -> Image.Image:
    """A pole and a pennant: a vertical stroke with a filled triangular flag.

    The pole runs the full mark height so it sits at the same optical size as
    the taller chevrons and the plus/minus pair; the pennant is filled (like
    the pencil tip in `edit`) rather than stroked, so its point does not thin
    to nothing at 16px.
    """
    img, d = _canvas()
    _stroke(d, [(34, 26), (34, 102)])  # pole
    _poly(d, [(34, 30), (98, 46), (34, 62)])  # pennant
    return img


# ---- the selection marks (2026-09-11) ----------------------------------------
# A menu row and a radio group draw an indicator in a RESERVED slot: the resting
# shape is always there and the chosen state fills it. Both states therefore need
# art, or the row that is NOT chosen falls through to a character -- which is the
# `o`/`*`/`[]` this set exists to stop being visible. The ring and the box share
# one 80px outer box so a radio group and a checklist line up at the same optical
# size, and the "on" mark is the ring PLUS its dot rather than a separate glyph,
# so the two states are the same object in two conditions.


def radio_off() -> Image.Image:
    """A radio's resting ring."""
    img, d = _canvas()
    _ring(d, 64, 64, 40)
    return img


def radio_on() -> Image.Image:
    """A radio's chosen state: the same ring with its centre filled.

    The dot is r=15 against an inner edge at r=27, so twelve 128-space units of
    clear ground separate them -- 1.5px at the 16px rung, which survives the
    LANCZOS downsample instead of closing into a filled disc.
    """
    img, d = _canvas()
    _ring(d, 64, 64, 40)
    _dot(d, 64, 64, 15)
    return img


def check_off() -> Image.Image:
    """A checkbox's resting box: the radio's ring, squared off.

    Same 80px outer box and same stroke, with the set's corner softening, so a
    checklist and a radio group read as one family. The chosen state is the
    existing `check` tick, which the control draws over this slot.
    """
    img, d = _canvas()
    d.rounded_rectangle(
        [24 * SS, 24 * SS, 104 * SS, 104 * SS],
        radius=22 * SS,
        outline=INK,
        width=STROKE * SS,
    )
    return img


def search() -> Image.Image:
    """An open lens and a round handle, at the standard set's stroke weight."""
    img, d = _canvas()
    d.ellipse([22 * SS, 22 * SS, 88 * SS, 88 * SS], outline=INK, width=STROKE * SS)
    _stroke(d, [(81, 81), (103, 103)])
    return img


# ---- P1d: eleven common glyphs (2026-09-18) -----------------------------------
# Notice/Badge/Snackbar, DateTimePicker, Vote, Avatar and Pagination need a SMALL
# common set -- not parity with any reference catalog, just the marks those five
# controls actually ask for. Three families:
#
#   status badges (info/success/warning/error) -- a ring (the same r=40 outer
#   radius as radio/check/close so the family reads as one weight class) with a
#   small mark INSIDE it, kept within radius ~24-26 so its own ink never touches
#   the ring's inner edge (r - STROKE = 27). `error` is a small X in a ring,
#   deliberately smaller and enclosed rather than the bare full-box X `close`
#   draws, so the two are not the same shape at a glance. `warning` breaks the
#   ring pattern on purpose -- a hazard triangle is the one shape every reference
#   material actually uses for that meaning, and confusing it with a status
#   circle would be the worse defect.
#
#   calendar / clock -- a rounded rect with binding tabs, and a ring with two
#   unequal hands, both drawn from the same primitives as everything else here.
#
#   vote.up / vote.down / person / chevron.first / chevron.last -- a thumb is a
#   capsule (thick round-capped `_stroke`) merged into a rounded-rect fist so the
#   THUMB reads as a separate digit, not a blob; `vote.down` is the exact
#   vertical mirror. `person` is a head circle plus a shoulders trapezoid,
#   self-contained inside the content box like the status badges (not clipped by
#   the canvas edge). The chevron-first/last pair is the existing chevron plus a
#   bar, exactly as the ASCII floor `|<` / `>|` already say.


def status_info() -> Image.Image:
    """A ring holding a lowercase `i`: dot above, stem below -- the opposite
    order from `warning`'s `!`, which is the mark that keeps the two readable
    apart even before their shapes differ."""
    img, d = _canvas()
    _ring(d, 64, 64, 40)
    _dot(d, 64, 46, 7)
    _stroke(d, [(64, 62), (64, 82)], w=13)
    return img


def status_success() -> Image.Image:
    """A ring holding a SMALL tick -- deliberately not the bare `checkmark`
    glyph (which spans the whole 128px box), so a success badge and a plain
    tick are never the same silhouette at a glance."""
    img, d = _canvas()
    _ring(d, 64, 64, 40)
    _stroke(d, [(50, 66), (60, 76), (76, 52)], w=13)
    return img


def status_warning() -> Image.Image:
    """A hazard triangle (closed, round-jointed outline) holding a `!`: stem
    above, dot below. The one status mark that is NOT a ring -- a triangle is
    what every warning glyph anywhere actually is, and disguising it as a fourth
    circle would cost the one shape a player already knows."""
    img, d = _canvas()
    _stroke(d, [(64, 18), (108, 108), (20, 108), (64, 18)], w=13)
    _stroke(d, [(64, 56), (64, 80)], w=11)
    _dot(d, 64, 92, 5)
    return img


def status_error() -> Image.Image:
    """A ring holding a SMALL X -- enclosed and reduced, so it reads as its own
    mark rather than as `close` (a bare X filling the whole box) sitting on a
    ring by accident."""
    img, d = _canvas()
    _ring(d, 64, 64, 40)
    _stroke(d, [(52, 52), (76, 76)], w=13)
    _stroke(d, [(76, 52), (52, 76)], w=13)
    return img


def calendar() -> Image.Image:
    """A page with binding tabs: a rounded body, a header divider, and two
    short strokes standing proud of the top edge -- the rings a calendar hangs
    from, which is the one feature that keeps this from reading as a plain
    rounded rectangle."""
    img, d = _canvas()
    d.rounded_rectangle(
        [18 * SS, 40 * SS, 110 * SS, 108 * SS],
        radius=12 * SS,
        outline=INK,
        width=STROKE * SS,
    )
    _stroke(d, [(24, 60), (104, 60)], w=10)
    _stroke(d, [(40, 24), (40, 44)], w=11)
    _stroke(d, [(88, 24), (88, 44)], w=11)
    return img


def clock() -> Image.Image:
    """A ring with two unequal hands sharing a centre -- a short hour hand and
    a longer, angled minute hand, both short enough of the ring's inner edge
    that neither ever touches it."""
    img, d = _canvas()
    _ring(d, 64, 64, 40)
    _stroke(d, [(64, 64), (64, 44)], w=11)
    _stroke(d, [(64, 64), (76, 50)], w=11)
    return img


def thumb_up() -> Image.Image:
    """The conventional three-part hand silhouette: a cuff (wrist), a fist
    (with three finger-groove cutouts notched into its knuckle/right half),
    and a thumb capsule leaning up and to the right off the fist's top-left
    corner.

    FIX ROUND 1 (lead art check, 2026-09-18). Round zero's two-shape version
    (a plain block fist plus a straight vertical capsule) read as the letter
    "L"/a boot, not a thumb -- a gesture needs a wrist AND finger texture AND
    an ANGLED digit before it stops looking like two abstract rectangles. The
    grooves are cut by drawing background-transparent rectangles directly over
    the filled fist: `ImageDraw`'s basic shapes REPLACE pixels rather than
    alpha-composite them, so a `(0, 0, 0, 0)` fill genuinely punches a hole
    through already-opaque ink (verified: `img.getpixel` inside the cut reads
    back fully transparent) -- no new primitive, just the existing `fill=`
    parameter used to subtract instead of add.

    FIX ROUND 2 (owner feedback, 2026-09-18): "the thumbs are a bit comically
    long". The three-part shape is unchanged; only the thumb's own length and
    width move -- tip raised from y=16 to y=32 (a 24px rise above the fist's
    y=56 top edge, down from ~40px) and width from 22 to 26, same ~15-degree
    lean, same base overlapping the fist's top-left corner. Shortening the
    thumb also recentres the whole icon for free: the old top-heavy bbox
    (y~5-110, centre ~57.5) sat above the canvas's own y=64 centre, and the new
    one (y~19-110, centre ~64.5) lands on it without a separate shift.
    """
    img, d = _canvas()
    # cuff: the wrist, standing apart from the fist as its own short block
    d.rounded_rectangle([14 * SS, 58 * SS, 34 * SS, 110 * SS], radius=6 * SS, fill=INK)
    # fist: the folded fingers
    d.rounded_rectangle([40 * SS, 56 * SS, 112 * SS, 110 * SS], radius=14 * SS, fill=INK)
    # three knuckle grooves, right half only -- texture at 24px+, still reads
    # as a clean block at 16px once they disappear into the downsample
    for gy in (70, 83, 96):
        d.rectangle([80 * SS, (gy - 2.5) * SS, 112 * SS, (gy + 2.5) * SS], fill=(0, 0, 0, 0))
    # thumb: a capsule leaning ~15 degrees off vertical, based at the fist's
    # top-left corner and overlapping it (no gap), narrower than the fist and
    # taller than the fist's own base width -- so the silhouette reads "fist
    # with a raised thumb", not a letter
    _stroke(d, [(58, 64), (67, 32)], w=26)
    return img


def thumb_down() -> Image.Image:
    """The exact vertical mirror of `thumb_up` -- flips the FINISHED image
    top-to-bottom rather than redrawing a second hand, so the pair can never
    drift apart from each other."""
    return thumb_up().transpose(Image.FLIP_TOP_BOTTOM)


def person() -> Image.Image:
    """A head circle over rounded shoulders, both self-contained inside the
    content box -- a bust, not a clipped torso, so it sits on the same optical
    footing as every other icon in the set.

    FIX ROUND 1 (lead art check, 2026-09-18): the original trapezoid shoulders
    read as a chess pawn. Widening them to a half-ellipse (a dome: PIL's
    `pieslice` from 180 to 360 degrees on a bounding box gives a rounded top
    and a flat bottom, verified against `getpixel`) about 2.2x the head's own
    width, and opening a small 4px gap under the head instead of overlapping
    it, is what reads as shoulders rather than a pawn's base.
    """
    img, d = _canvas()
    _dot(d, 64, 44, 18)
    d.pieslice([24 * SS, 66 * SS, 104 * SS, 142 * SS], 180, 360, fill=INK)
    return img


def chevron_first() -> Image.Image:
    """A leading bar plus a FILLED arrowhead -- "skip to the first page", the
    same pairing the ASCII floor `|<` already spells out.

    FIRST DRAFT used the open `_stroke` chevron next to the bar and it read as
    the letter "K": two diagonal strokes meeting a vertical one at the same two
    points IS a K. A solid triangle reads as one mass next to the bar instead
    of two more strokes joining it, which is what breaks the illusion.
    """
    img, d = _canvas()
    _stroke(d, [(26, 24), (26, 104)], w=STROKE)
    _poly(d, [(90, 24), (90, 104), (42, 64)])
    return img


def chevron_last() -> Image.Image:
    """The mirror of `chevron_first`: a filled arrowhead plus a trailing bar,
    matching the ASCII floor `>|`."""
    img, d = _canvas()
    _poly(d, [(38, 24), (38, 104), (86, 64)])
    _stroke(d, [(102, 24), (102, 104)], w=STROKE)
    return img


ICONS = {
    "facet_icon_chevron_left": lambda: chevron("left"),
    "facet_icon_chevron_right": lambda: chevron("right"),
    "facet_icon_chevron_up": lambda: chevron("up"),
    "facet_icon_chevron_down": lambda: chevron("down"),
    "facet_icon_chevron_up_down": chevron_up_down,
    "facet_icon_check": check,
    "facet_icon_close": close,
    "facet_icon_plus": plus,
    "facet_icon_minus": minus,
    "facet_icon_menu": menu,
    "facet_icon_more": more,
    "facet_icon_edit": edit,
    "facet_icon_trash": trash,
    "facet_icon_flag": flag,
    "facet_icon_search": search,
    "facet_icon_radio_off": radio_off,
    "facet_icon_radio_on": radio_on,
    "facet_icon_check_off": check_off,
    "facet_icon_info": status_info,
    "facet_icon_success": status_success,
    "facet_icon_warning": status_warning,
    "facet_icon_error": status_error,
    "facet_icon_calendar": calendar,
    "facet_icon_clock": clock,
    "facet_icon_thumb_up": thumb_up,
    "facet_icon_thumb_down": thumb_down,
    "facet_icon_person": person,
    "facet_icon_chevron_first": chevron_first,
    "facet_icon_chevron_last": chevron_last,
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
