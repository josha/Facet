#!/usr/bin/env python3
"""Glossy Touch art generator (rich-skinning-v2 stage, ADR-0020 / charter cap 8).

Original, repository-owned art: every texture below is generated procedurally by
this script from the fixed seed `SEED` — no external imagery, no third-party
assets, and NO trade dress. The brief's reference ("glossy touch-era") names a
*category* of chrome — glossy skeuomorphic touch controls, vertical gradients,
gel highlights, 44px rows — not any vendor's pixels: the palette, geometry,
gradient stops and highlight construction below are all invented here.

Authored at TOUCH scale: a 44 px control row is the unit, so slice borders are
sized so that 2*border always fits inside 44 px.

Run with the repo-root shared venv python (any CWD works):
  <repo-root>/.venv/bin/python generate_art.py
"""

from __future__ import annotations

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.dirname(HERE)
PREVIEW_DIR = os.path.join(HERE, "preview")
SEED = 0x6E43  # fixed: determinism is the provenance claim ("gel"). Bumped twice:
# 0x6E11 -> 0x6E27 in the director art round 2026-07-25 (the bar trough, the bar
# fill and the stripe tile) and 0x6E27 -> 0x6E43 in the director round 2026-07-26
# (the ON toggle track, re-cut from green into the package's own blue). Every
# other texture is unchanged and re-generates byte-identically at either seed.

# ─────────────────────────────────────────────────────────────────────────────
# Tiny drawing toolkit. Duplicated verbatim in every theme generator on purpose:
# a theme folder must be copyable on its own, with no shared-module dependency.
# ─────────────────────────────────────────────────────────────────────────────
SS = 4


def _f(im):
    return np.clip(np.asarray(im, dtype=np.float64) / 255.0, 0.0, 1.0)


def _u8(a):
    return np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8)


def rgb(r, g, b):
    return np.array([r, g, b], dtype=np.float64) / 255.0


class Mask:
    def __init__(self, w, h, ss=SS):
        self.w, self.h, self.ss = w, h, ss
        self.im = Image.new("L", (w * ss, h * ss), 0)
        self.d = ImageDraw.Draw(self.im)

    def _s(self, box):
        return [v * self.ss for v in box]

    def rect(self, box, fill=255):
        self.d.rectangle(self._s(box), fill=fill)

    def rrect(self, box, radius, fill=255):
        self.d.rounded_rectangle(self._s(box), radius=radius * self.ss, fill=fill)

    def rring(self, box, radius, width, fill=255):
        self.d.rounded_rectangle(self._s(box), radius=radius * self.ss, outline=fill,
                                 width=max(1, int(round(width * self.ss))))

    def ellipse(self, box, fill=255):
        self.d.ellipse(self._s(box), fill=fill)

    def poly(self, pts, fill=255):
        self.d.polygon([(x * self.ss, y * self.ss) for x, y in pts], fill=fill)

    def stroke(self, pts, width, fill=255, caps=True):
        sp = [(x * self.ss, y * self.ss) for x, y in pts]
        w = max(1, int(round(width * self.ss)))
        if len(sp) > 1:
            self.d.line(sp, fill=fill, width=w, joint="curve")
        if caps:
            r = w / 2.0
            for x, y in (sp[0], sp[-1]):
                self.d.ellipse([x - r, y - r, x + r, y + r], fill=fill)

    def arr(self):
        return _f(self.im.resize((self.w, self.h), Image.LANCZOS))


def blur(a, r):
    if r <= 0:
        return a
    return _f(Image.fromarray(_u8(a), "L").filter(ImageFilter.GaussianBlur(r)))


def shift(a, dx, dy):
    out = np.zeros_like(a)
    h, w = a.shape[0], a.shape[1]
    ys0, ys1 = max(0, dy), min(h, h + dy)
    xs0, xs1 = max(0, dx), min(w, w + dx)
    if ys1 > ys0 and xs1 > xs0:
        out[ys0:ys1, xs0:xs1] = a[ys0 - dy:ys1 - dy, xs0 - dx:xs1 - dx]
    return out


def vgrad(w, h, stops):
    ys = np.linspace(0.0, 1.0, h)
    ts = np.array([s[0] for s in stops], dtype=np.float64)
    cs = np.array([np.asarray(s[1], dtype=np.float64) for s in stops])
    col = np.zeros((h, 3))
    for c in range(3):
        col[:, c] = np.interp(ys, ts, cs[:, c])
    return np.repeat(col[:, None, :], w, axis=1)


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.rgb = np.zeros((h, w, 3), dtype=np.float64)
        self.a = np.zeros((h, w), dtype=np.float64)

    def paint(self, color, alpha):
        col = np.asarray(color, dtype=np.float64)
        src = np.broadcast_to(col, (self.h, self.w, 3)) if col.ndim <= 1 else col
        sa = np.clip(np.broadcast_to(np.asarray(alpha, dtype=np.float64), (self.h, self.w)), 0, 1)[..., None]
        da = self.a[..., None]
        out_a = sa + da * (1 - sa)
        self.rgb = np.where(out_a > 1e-6, (src * sa + self.rgb * da * (1 - sa)) / np.maximum(out_a, 1e-6), 0.0)
        self.a = out_a[..., 0]

    def image(self):
        return Image.fromarray(np.dstack([_u8(self.rgb), _u8(self.a)]), "RGBA")


def nine_slice(img, border, w, h, resample=Image.BILINEAR):
    sw, sh = img.size
    b = border
    dst = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    cw, ch = w - 2 * b, h - 2 * b
    parts = [
        ((0, 0, b, b), (0, 0), (b, b)),
        ((sw - b, 0, sw, b), (w - b, 0), (b, b)),
        ((0, sh - b, b, sh), (0, h - b), (b, b)),
        ((sw - b, sh - b, sw, sh), (w - b, h - b), (b, b)),
        ((b, 0, sw - b, b), (b, 0), (cw, b)),
        ((b, sh - b, sw - b, sh), (b, h - b), (cw, b)),
        ((0, b, b, sh - b), (0, b), (b, ch)),
        ((sw - b, b, sw, sh - b), (w - b, b), (b, ch)),
        ((b, b, sw - b, sh - b), (b, b), (cw, ch)),
    ]
    for box, pos, size in parts:
        if size[0] <= 0 or size[1] <= 0:
            continue
        dst.alpha_composite(img.crop(box).resize(size, resample), pos)
    return dst


def checker(w, h, s=8, a=(56, 56, 62), b=(42, 42, 48)):
    im = Image.new("RGB", (w, h), a)
    d = ImageDraw.Draw(im)
    for y in range(0, h, s):
        for x in range(0, w, s):
            if ((x // s) + (y // s)) % 2:
                d.rectangle([x, y, x + s - 1, y + s - 1], fill=b)
    return im


class Sheet:
    def __init__(self, title, width=1500):
        self.title, self.width, self.rows = title, width, []

    def add(self, label, images, backdrop=None):
        self.rows.append((label, list(images), backdrop))

    def save(self, path):
        font = ImageFont.load_default(size=13)
        head = ImageFont.load_default(size=20)
        pad, gap, lab_h = 16, 18, 20
        total = 52 + sum(lab_h + max((i.height for i in ims), default=0) + gap
                         for _, ims, _ in self.rows) + pad
        im = Image.new("RGB", (self.width, total), (26, 26, 30))
        d = ImageDraw.Draw(im)
        d.text((pad, 16), self.title, font=head, fill=(236, 226, 200))
        y = 52
        for label, ims, backdrop in self.rows:
            d.text((pad, y), label, font=font, fill=(168, 172, 182))
            y += lab_h
            x = pad
            row_h = max((i.height for i in ims), default=0)
            for sub in ims:
                bg = (checker(sub.width, sub.height) if backdrop is None
                      else Image.new("RGB", (sub.width, sub.height), backdrop)).convert("RGBA")
                bg.alpha_composite(sub)
                im.paste(bg.convert("RGB"), (x, y))
                d.rectangle([x, y, x + sub.width - 1, y + sub.height - 1], outline=(90, 90, 98))
                x += sub.width + 12
            y += row_h + gap
        os.makedirs(os.path.dirname(path), exist_ok=True)
        im.save(path, optimize=True)
        print(f"wrote {path}  (contact sheet)")


# ─────────────────────────────────────────────────────────────────────────────
# Palette — cool neutral chrome with a saturated blue action colour.
# ─────────────────────────────────────────────────────────────────────────────
WHITE = rgb(255, 255, 255)
PANEL_TOP = rgb(250, 251, 253)
PANEL_BOT = rgb(222, 227, 236)
EDGE = rgb(132, 141, 158)
EDGE_SOFT = rgb(172, 180, 196)
SHADOW = rgb(52, 60, 76)
WELL_TOP = rgb(198, 205, 217)
WELL_BOT = rgb(252, 253, 255)

# Gel ramps: (top, mid) is the glossy upper segment, (low, bot) the matte lower
# segment. The hard VALUE STEP between mid and low is the whole look, and it is
# a function of y only — which is what keeps it nine-slice safe.
CHROME = (rgb(253, 253, 255), rgb(224, 230, 240), rgb(186, 195, 212), rgb(233, 237, 244))
CHROME_DOWN = (rgb(178, 187, 204), rgb(160, 170, 189), rgb(140, 151, 172), rgb(168, 178, 196))
BLUE = (rgb(146, 202, 255), rgb(56, 142, 242), rgb(20, 92, 206), rgb(66, 152, 240))
BLUE_DEEP = (rgb(66, 150, 238), rgb(32, 108, 216), rgb(14, 72, 172), rgb(34, 110, 208))
GREEN = (rgb(172, 238, 152), rgb(78, 194, 80), rgb(38, 144, 50), rgb(94, 202, 94))
KNOB = (rgb(255, 255, 255), rgb(246, 248, 252), rgb(206, 213, 226), rgb(238, 242, 248))
# the BAR's own gel ramp (director art round): deeper than the button BLUE so a
# 24px fill still reads domed at desktop scale
BLUE_GEL = (rgb(150, 208, 255), rgb(48, 136, 240), rgb(14, 78, 190), rgb(48, 132, 226))
BLUE_MID = rgb(46, 128, 232)
BLUE_BOT = rgb(20, 84, 188)
GREEN_BOT = rgb(34, 132, 44)


def gel(c: Canvas, mask, ramp, *, split=0.48, sheen=0.30, rim=True):
    """The house gel: a two-segment vertical gradient with a HARD value step at
    `split` (the gloss line) plus a white sheen over the upper segment."""
    top, mid, low, bot = ramp
    h, w = mask.shape
    e = 1.0 / max(2, h)
    c.paint(vgrad(w, h, [(0.0, top), (split - e, mid), (split, low), (1.0, bot)]), mask)
    if sheen > 0:
        k = max(1, int(round(h * split)))
        lens = np.zeros((h, w))
        lens[:k, :] = np.linspace(1.0, 0.12, k)[:, None]
        c.paint(WHITE, lens * mask * sheen)
    if rim:
        inner = np.clip(mask - shift(mask, 0, 1), 0, 1)
        c.paint(WHITE, inner * 0.7)


def panel(rng) -> Image.Image:
    """96x96, slice border 28 — rounded card, soft vertical gradient, hairline."""
    w = h = 96
    c = Canvas(w, h)
    body = Mask(w, h)
    body.rrect([2, 2, w - 3, h - 4], 14)
    bm = body.arr()
    c.paint(SHADOW, blur(shift(bm, 0, 2), 2.2) * 0.28)  # soft drop shadow
    c.paint(vgrad(w, h, [(0.0, PANEL_TOP), (1.0, PANEL_BOT)]), bm)
    ring = Mask(w, h)
    ring.rring([2, 2, w - 3, h - 4], 14, 1)
    c.paint(EDGE_SOFT, ring.arr() * 0.9)
    hi = Mask(w, h)
    hi.rring([3, 3, w - 4, h - 5], 13, 1)
    c.paint(WHITE, hi.arr() * 0.75)
    return c.image()


def button(rng, state: str) -> Image.Image:
    """64x44, slice border 16 — gel button.

    Authored AT the 44 px touch-row height so the gel's hard gloss step maps 1:1
    onto a real row (a 64x64 source would squeeze the step into the 12 px
    stretched centre band and the gloss would read as a soft gradient).
    """
    w, h = 64, 44
    c = Canvas(w, h)
    body = Mask(w, h)
    body.rrect([1, 1, w - 2, h - 3], 10)
    bm = body.arr()
    if state == "default":
        c.paint(SHADOW, blur(shift(bm, 0, 2), 1.8) * 0.30)
        gel(c, bm, CHROME, sheen=0.34)
    else:  # pressed — darker, gradient flipped, gloss killed, inner shade
        c.paint(SHADOW, blur(bm, 1.2) * 0.18)
        gel(c, bm, CHROME_DOWN, split=0.34, sheen=0.06, rim=False)
        inner = np.clip(bm - shift(bm, 0, 3), 0, 1)
        c.paint(SHADOW, blur(inner, 1.6) * 0.55)
    ring = Mask(w, h)
    ring.rring([1, 1, w - 2, h - 3], 10, 1)
    c.paint(EDGE, ring.arr() * (0.95 if state == "default" else 1.0))
    return c.image()


def field(rng) -> Image.Image:
    """64x44, slice border 16 — inset well with a top inner shadow."""
    w, h = 64, 44
    c = Canvas(w, h)
    body = Mask(w, h)
    body.rrect([1, 1, w - 2, h - 2], 10)
    bm = body.arr()
    c.paint(vgrad(w, h, [(0.0, WELL_TOP), (0.35, WELL_BOT), (1.0, WHITE)]), bm)
    inner = np.clip(bm - shift(bm, 0, 4), 0, 1)
    c.paint(SHADOW, blur(inner, 2.0) * 0.42)
    ring = Mask(w, h)
    ring.rring([1, 1, w - 2, h - 2], 10, 1)
    c.paint(EDGE, ring.arr() * 0.9)
    base = np.clip(bm - shift(bm, 0, -2), 0, 1)
    c.paint(WHITE, base * 0.6)
    return c.image()


def bar_track(rng) -> Image.Image:
    """96x24, slice border 10 — rounded inset trough.

    RE-CUT in the director art round (seed 0x6E27): the first cut read muddy at
    the 24 px desktop bar height. Three things were wrong and all three are
    geometry, not taste. (1) The well was drawn between y=2 and y=h-3, so only
    20 of the 24 authored pixels carried any art and the trough looked like a
    hairline on a light plate. It now uses the full height. (2) Its ramp ran
    196 -> 248 — a 52-level spread that is invisible next to a near-white page,
    so there was no WELL, only a pale band; the new ramp starts at 138 and the
    dark end is the TOP, which is what makes an inset read as inset. (3) There
    was no crisp boundary at all: one soft EDGE_SOFT ring at 0.95. It now carries
    a hard 1 px EDGE rim plus a 1 px white bevel on the bottom inside lip, which
    is the classic two-line inset and the thing that survives downscaling.
    """
    w, h = 96, 24
    c = Canvas(w, h)
    body = Mask(w, h)
    body.rrect([0, 0, w - 1, h - 1], 10)
    bm = body.arr()
    # a REAL well: dark at the top, opening to near-white at the bottom lip
    c.paint(vgrad(w, h, [
        (0.0, rgb(138, 148, 166)),
        (0.30, rgb(180, 189, 205)),
        (0.72, rgb(219, 225, 236)),
        (1.0, rgb(245, 248, 252)),
    ]), bm)
    # top inner shadow, deeper and tighter than the first cut
    inner = np.clip(bm - shift(bm, 0, 4), 0, 1)
    c.paint(SHADOW, blur(inner, 1.5) * 0.55)
    # the bottom inside lip catches light — the second line of the inset idiom
    lip = np.clip(bm - shift(bm, 0, -2), 0, 1)
    c.paint(WHITE, lip * 0.72)
    ring = Mask(w, h)
    ring.rring([0, 0, w - 1, h - 1], 10, 1)
    c.paint(EDGE, ring.arr() * 1.0)
    return c.image()


def bar_fill(rng) -> Image.Image:
    """96x24, slice border 8 — blue gel fill.

    The centre band is forced X-UNIFORM so a partially revealed fill and a
    stretched fill are the same picture.

    RE-CUT in the director art round (seed 0x6E27), and the height is the fix.
    The first cut was authored 20 px tall and DRAWN 24 (the package's
    `controls.progress.trackHeight`), so the middle 4 rows stretched to 8 and
    the gel's hard gloss step — the whole look — landed inside the stretched
    band and smeared into a soft gradient. This is provenance note 1 exactly, one
    control down from the button it was written for. Authored at 24 it is 1:1
    vertically at every width, so the step stays a step. The gloss is also
    deeper (a lower split, more sheen, a darker lower segment) because a 24 px
    bar shows a quarter of the pixels a 44 px button does.
    """
    w, h = 96, 24
    c = Canvas(w, h)
    body = Mask(w, h)
    body.rrect([0, 0, w - 1, h - 1], 9)
    bm = body.arr()
    gel(c, bm, BLUE_GEL, split=0.44, sheen=0.40)
    # a darker seat under the gloss so the fill reads domed rather than flat
    seat = np.clip(bm - shift(bm, 0, -3), 0, 1)
    c.paint(BLUE_BOT, seat * 0.45)
    ring = Mask(w, h)
    ring.rring([0, 0, w - 1, h - 1], 9, 1)
    c.paint(BLUE_BOT, ring.arr() * 0.85)
    b = 8
    c.rgb[:, b:w - b, :] = c.rgb[:, w // 2:w // 2 + 1, :]
    c.a[:, b:w - b] = c.a[:, w // 2:w // 2 + 1]
    return c.image()


def stripe_tile(rng) -> Image.Image:
    """24x24 SEAMLESS diagonal stripe tile (period 24 on both axes).

    White-on-transparency so it overlays any fill; this is the barber-pole /
    pinstripe demo asset for the `tile` layer kind (TileSize = 24,24).
    Diagonal art cannot live in a SLICED fill (the stretched centre would smear
    it), which is exactly why it ships as a tile.

    RE-CUT in the director art round (seed 0x6E27). The first cut ran a 12 px
    period at 0.55 white: over a 24 px bar that is ONE cycle of a low-contrast
    hatch, which is exactly the "muddy" read. The period is now 8 (three cycles
    per tile, still an exact divisor of the 24 px tile so both axes still seam),
    the white is brighter and narrower, and each stripe carries a thin dark
    leading edge — contrast between two marks survives downscaling in a way a
    single translucent mark does not.
    """
    s = 24
    c = Canvas(s, s)
    period = 8
    bright = Mask(s, s)
    shade = Mask(s, s)
    for k in range(-4, 7):
        off = k * period
        # the lit band: 3 of every 8 px
        bright.poly([(off, 0), (off + 3, 0), (off + 3 + s, s), (off + s, s)])
        # its 2 px leading edge, in shadow — the PAIR is what reads at 24 px, and
        # the shade half is what keeps the trough recessed instead of turning it
        # into a band brighter than the page behind it
        shade.poly([(off - 2, 0), (off, 0), (off + s, s), (off - 2 + s, s)])
    c.paint(SHADOW, shade.arr() * 0.30)
    c.paint(WHITE, bright.arr() * 0.55)
    return c.image()


def toggle_track(rng, state: str) -> Image.Image:
    """72x32, slice border 14 — capsule track.

    RE-CUT in the director round of 2026-07-26 (seed 0x6E43): the ON track was
    GREEN, and this package's action colour is BLUE. Every other "this is
    active" surface it paints — the selection plate, the pressed stepper plate,
    the progress fill — is the house blue, and the palette's `accent` is
    rgb(18, 92, 190); a green switch was the one piece of chrome that belonged
    to no theme. It now uses the same `BLUE` ramp and `BLUE_BOT` rim the
    selection plate does, so ON reads as "the accent colour" rather than as a
    borrowed traffic light. Geometry, slice border and the OFF state are
    untouched, and the knob is unchanged: a chrome gel knob reads on blue for
    the same reason it read on green.
    """
    w, h = 72, 32
    c = Canvas(w, h)
    body = Mask(w, h)
    body.rrect([0, 0, w - 1, h - 1], 15)
    bm = body.arr()
    if state == "on":
        gel(c, bm, BLUE, sheen=0.22)
        ring = Mask(w, h)
        ring.rring([0, 0, w - 1, h - 1], 15, 1)
        c.paint(BLUE_BOT, ring.arr() * 0.7)
    else:
        c.paint(vgrad(w, h, [(0.0, rgb(198, 204, 216)), (0.4, rgb(232, 236, 243)), (1.0, rgb(250, 251, 253))]), bm)
        inner = np.clip(bm - shift(bm, 0, 4), 0, 1)
        c.paint(SHADOW, blur(inner, 2.0) * 0.45)
        ring = Mask(w, h)
        ring.rring([0, 0, w - 1, h - 1], 15, 1)
        c.paint(EDGE_SOFT, ring.arr() * 0.95)
    return c.image()


def toggle_knob(rng) -> Image.Image:
    """30x30 whole image — chrome gel knob."""
    s = 30
    c = Canvas(s, s)
    body = Mask(s, s)
    body.ellipse([1, 0, s - 2, s - 3])
    bm = body.arr()
    c.paint(SHADOW, blur(shift(bm, 0, 2), 1.8) * 0.42)
    gel(c, bm, KNOB, sheen=0.30)
    ring = Mask(s, s)
    ring.ellipse([1, 0, s - 2, s - 3])
    r2 = Mask(s, s)
    r2.ellipse([2, 1, s - 3, s - 4])
    c.paint(EDGE, np.clip(ring.arr() - r2.arr(), 0, 1) * 0.85)
    return c.image()


def stepper_plate(rng, state: str) -> Image.Image:
    """44x44, slice border 14 — glyph plate."""
    w = h = 44
    c = Canvas(w, h)
    body = Mask(w, h)
    body.rrect([1, 1, w - 2, h - 3], 9)
    bm = body.arr()
    if state == "default":
        c.paint(SHADOW, blur(shift(bm, 0, 2), 1.6) * 0.26)
        gel(c, bm, CHROME, sheen=0.34)
    else:
        gel(c, bm, BLUE_DEEP, split=0.34, sheen=0.08, rim=False)
        inner = np.clip(bm - shift(bm, 0, 3), 0, 1)
        c.paint(SHADOW, blur(inner, 1.6) * 0.45)
    ring = Mask(w, h)
    ring.rring([1, 1, w - 2, h - 3], 9, 1)
    c.paint(EDGE if state == "default" else BLUE_BOT, ring.arr() * 0.95)
    return c.image()


def selection(rng, state: str) -> Image.Image:
    """72x44, slice border 18 — the selection plate (default vs selected glow)."""
    w, h = 72, 44
    c = Canvas(w, h)
    if state == "default":
        body = Mask(w, h)
        body.rrect([2, 2, w - 3, h - 3], 12)
        bm = body.arr()
        c.paint(vgrad(w, h, [(0.0, rgb(252, 253, 255)), (1.0, rgb(238, 241, 246))]), bm * 0.96)
        ring = Mask(w, h)
        ring.rring([2, 2, w - 3, h - 3], 12, 1)
        c.paint(EDGE_SOFT, ring.arr() * 0.8)
        return c.image()
    body = Mask(w, h)
    body.rrect([2, 2, w - 3, h - 3], 12)
    bm = body.arr()
    c.paint(BLUE_MID, blur(bm, 4.0) * 0.55)          # the glow, outside the plate
    gel(c, bm, BLUE, sheen=0.26)
    ring = Mask(w, h)
    ring.rring([2, 2, w - 3, h - 3], 12, 1)
    c.paint(BLUE_BOT, ring.arr() * 0.85)
    inner = Mask(w, h)
    inner.rring([4, 4, w - 5, h - 5], 10, 1)
    c.paint(WHITE, inner.arr() * 0.55)
    return c.image()


# ─────────────────────────────────────────────────────────────────────────────
def main() -> None:
    def r(k):
        return np.random.default_rng(SEED + k)

    items = []
    items.append(("glossy_panel.png", panel(r(1)), 28, [(220, 120), (360, 200), (520, 132)]))
    items.append(("glossy_button_default.png", button(r(2), "default"), 16, [(140, 44)]))
    items.append(("glossy_button_pressed.png", button(r(3), "pressed"), 16, [(140, 44)]))
    items.append(("glossy_field.png", field(r(4)), 16, [(180, 44), (300, 44), (140, 72)]))
    items.append(("glossy_bar_track.png", bar_track(r(5)), 10, [(120, 24), (260, 24), (400, 24)]))
    items.append(("glossy_bar_fill.png", bar_fill(r(6)), 8, [(60, 24), (180, 24), (340, 24)]))
    items.append(("glossy_stripe_tile.png", stripe_tile(r(7)), None, None))
    items.append(("glossy_toggle_track_off.png", toggle_track(r(8), "off"), 14, [(72, 32), (96, 32)]))
    items.append(("glossy_toggle_track_on.png", toggle_track(r(9), "on"), 14, [(72, 32), (96, 32)]))
    items.append(("glossy_toggle_knob.png", toggle_knob(r(10)), None, None))
    items.append(("glossy_stepper_plate_default.png", stepper_plate(r(11), "default"), 14, [(44, 44), (72, 44)]))
    items.append(("glossy_stepper_plate_pressed.png", stepper_plate(r(12), "pressed"), 14, [(44, 44), (72, 44)]))
    items.append(("glossy_selection_default.png", selection(r(13), "default"), 18, [(220, 44)]))
    items.append(("glossy_selection_selected.png", selection(r(14), "selected"), 18, [(220, 44)]))

    for name, img, border, _ in items:
        path = os.path.join(OUT_DIR, name)
        img.save(path, optimize=True)
        b = f"slice {border}" if border else "whole image"
        print(f"wrote {path}  ({img.width}x{img.height}, {b})")

    sheet = Sheet("glossy-touch — 44px touch scale, nine-slice stretch test")
    by = {n: (i, b, p) for n, i, b, p in items}

    def row(label, names, sizes=None, backdrop=None):
        imgs = []
        for n in names:
            img, border, prev = by[n]
            use = sizes or prev
            if border and use:
                imgs += [nine_slice(img, border, w, h) for w, h in use]
            else:
                imgs.append(img)
        sheet.add(label, imgs, backdrop)

    row("panel (96x96 b28) stretched", ["glossy_panel.png"])
    row("button default / pressed @140x44 (64x44 b16 — same insets, different art)",
        ["glossy_button_default.png", "glossy_button_pressed.png"])
    row("button default @ 88x44 / 300x44 / 140x88 — slice stress",
        ["glossy_button_default.png"], sizes=[(88, 44), (300, 44), (140, 88)])
    row("field (64x44 b16) stretched", ["glossy_field.png"])
    row("bar track (96x24 b10) stretched", ["glossy_bar_track.png"])
    row("bar fill (96x24 b8) stretched — X-uniform centre", ["glossy_bar_fill.png"])
    # STRIPED PROGRESS, composed exactly as the package composes it (director art
    # round 2026-07-25 — the first sheet put the stripe layer over the FILL,
    # while `glossy_touch.luau` declares it as `barTrack`'s second layer). So the
    # trough is striped, the gel fill draws OVER it, and the preview finally shows
    # what a player sees: a solid gel head against a hatched trough.
    trk = by["glossy_bar_track.png"][0]
    fil = by["glossy_bar_fill.png"][0]
    stripe = by["glossy_stripe_tile.png"][0]
    striped = []
    for pct in (0.2, 0.6, 1.0):
        bw, bh = 320, 24
        comp = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
        track = nine_slice(trk, 10, bw, bh)
        tile_layer = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
        for tx in range(0, bw, 24):
            for ty in range(0, bh, 24):
                tile_layer.alpha_composite(stripe.crop((0, 0, min(24, bw - tx), min(24, bh - ty))), (tx, ty))
        track = Image.alpha_composite(track, Image.composite(
            tile_layer, Image.new("RGBA", (bw, bh), (0, 0, 0, 0)), track.split()[3]))
        comp.alpha_composite(track)
        full = nine_slice(fil, 8, bw, bh)
        comp.alpha_composite(full.crop((0, 0, max(1, int(bw * pct)), bh)), (0, 0))
        striped.append(comp)
    sheet.add("striped progress AS SHIPPED: striped trough + gel fill over it, clipped 20/60/100%", striped)
    tiled = Image.new("RGBA", (240, 72), (0, 0, 0, 0))
    for yy in range(3):
        for xx in range(10):
            tiled.alpha_composite(stripe, (xx * 24, yy * 24))
    sheet.add("stripe tile 24x24 — TILED 10x3 on transparency (seam check)", [tiled], backdrop=(46, 128, 232))
    row("toggle track off / on (72x32 b14) + knob (30x30)",
        ["glossy_toggle_track_off.png", "glossy_toggle_track_on.png", "glossy_toggle_knob.png"])
    # assembled switch
    switches = []
    for st in ("off", "on"):
        comp = Image.new("RGBA", (84, 32), (0, 0, 0, 0))
        comp.alpha_composite(nine_slice(by[f"glossy_toggle_track_{st}.png"][0], 14, 84, 32))
        knob = by["glossy_toggle_knob.png"][0]
        comp.alpha_composite(knob, (1 if st == "off" else 84 - 31, 1))
        switches.append(comp)
    sheet.add("assembled switch off / on (knob travel is solver-owned)", switches)
    row("stepper plate default / pressed (44x44 b14)",
        ["glossy_stepper_plate_default.png", "glossy_stepper_plate_pressed.png"])
    row("selection default / selected @220x44 (72x44 b18) — glow plate",
        ["glossy_selection_default.png", "glossy_selection_selected.png"])
    sheet.save(os.path.join(PREVIEW_DIR, "contact-sheet.png"))


if __name__ == "__main__":
    main()
