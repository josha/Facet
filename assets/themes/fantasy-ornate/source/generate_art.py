#!/usr/bin/env python3
"""Fantasy Ornate art generator (rich-skinning-v2 stage, ADR-0020).

Original, repository-owned art: every texture below is generated procedurally by
this script from the fixed seed `SEED` — no external imagery, no third-party
assets, no trade dress. Re-running reproduces the PNGs byte-for-byte on the same
Pillow/numpy versions (recorded in ../provenance.md).

The look: rich metal-and-jewel over dark velvet — deliberately DISTINCT from the
sibling `fantasy-parchment` package, which is quiet paper-and-ink.

Outputs go to the parent directory (the theme asset folder); a contact sheet that
stretches every nine-slice to three sizes lands in ./preview/ so a lead can judge
slice quality without opening Studio.

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
SEED = 0x60D1  # fixed: determinism is the provenance claim

# ─────────────────────────────────────────────────────────────────────────────
# Tiny drawing toolkit. Duplicated verbatim in every theme generator on purpose:
# a theme folder must be copyable on its own, with no shared-module dependency.
# ─────────────────────────────────────────────────────────────────────────────
SS = 4  # supersample factor for anti-aliased shape masks


def _f(im: Image.Image) -> np.ndarray:
    return np.clip(np.asarray(im, dtype=np.float64) / 255.0, 0.0, 1.0)


def _u8(a: np.ndarray) -> np.ndarray:
    return np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8)


def rgb(r: int, g: int, b: int) -> np.ndarray:
    return np.array([r, g, b], dtype=np.float64) / 255.0


class Mask:
    """Supersampled single-channel shape accumulator -> float HxW in [0,1]."""

    def __init__(self, w: int, h: int, ss: int = SS):
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
        self.d.rounded_rectangle(
            self._s(box), radius=radius * self.ss, outline=fill,
            width=max(1, int(round(width * self.ss))),
        )

    def ellipse(self, box, fill=255):
        self.d.ellipse(self._s(box), fill=fill)

    def ering(self, box, width, fill=255):
        self.d.ellipse(self._s(box), outline=fill, width=max(1, int(round(width * self.ss))))

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

    def arr(self) -> np.ndarray:
        return _f(self.im.resize((self.w, self.h), Image.LANCZOS))


def blur(a: np.ndarray, r: float) -> np.ndarray:
    if r <= 0:
        return a
    return _f(Image.fromarray(_u8(a), "L").filter(ImageFilter.GaussianBlur(r)))


def shift(a: np.ndarray, dx: int, dy: int) -> np.ndarray:
    out = np.zeros_like(a)
    h, w = a.shape[0], a.shape[1]
    ys0, ys1 = max(0, dy), min(h, h + dy)
    xs0, xs1 = max(0, dx), min(w, w + dx)
    if ys1 > ys0 and xs1 > xs0:
        out[ys0:ys1, xs0:xs1] = a[ys0 - dy:ys1 - dy, xs0 - dx:xs1 - dx]
    return out


def emboss(mask: np.ndarray, blur_r: float = 1.0, dist: int = 1):
    """Top-left-lit emboss: returns (highlight, shadow) masks for a shape."""
    m = blur(mask, blur_r)
    hi = np.clip(m - shift(m, dist, dist), 0, 1)
    lo = np.clip(m - shift(m, -dist, -dist), 0, 1)
    return hi, lo


def vgrad(w: int, h: int, stops) -> np.ndarray:
    ys = np.linspace(0.0, 1.0, h)
    ts = np.array([s[0] for s in stops], dtype=np.float64)
    cs = np.array([np.asarray(s[1], dtype=np.float64) for s in stops])
    col = np.zeros((h, 3))
    for c in range(3):
        col[:, c] = np.interp(ys, ts, cs[:, c])
    return np.repeat(col[:, None, :], w, axis=1)


def fbm(rng: np.random.Generator, w: int, h: int, octaves: int = 4) -> np.ndarray:
    acc = np.zeros((h, w), dtype=np.float64)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        cells = max(2, 3 * (2 ** o))
        grid = rng.random((cells, cells))
        img = Image.fromarray((grid * 255).astype(np.uint8), "L").resize((w, h), Image.BICUBIC)
        acc += amp * _f(img)
        total += amp
        amp *= 0.55
    return acc / total


class Canvas:
    """Straight-alpha RGBA compositor in float space."""

    def __init__(self, w: int, h: int):
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

    def image(self) -> Image.Image:
        return Image.fromarray(np.dstack([_u8(self.rgb), _u8(self.a)]), "RGBA")


def nine_slice(img: Image.Image, border: int, w: int, h: int, resample=Image.BILINEAR) -> Image.Image:
    """Reference nine-slice render (matches Roblox SliceScale = 1)."""
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


def checker(w: int, h: int, s: int = 8, a=(56, 56, 62), b=(42, 42, 48)) -> Image.Image:
    im = Image.new("RGB", (w, h), a)
    d = ImageDraw.Draw(im)
    for y in range(0, h, s):
        for x in range(0, w, s):
            if ((x // s) + (y // s)) % 2:
                d.rectangle([x, y, x + s - 1, y + s - 1], fill=b)
    return im


class Sheet:
    """Vertical contact sheet: one labelled row per asset."""

    def __init__(self, title: str, width: int = 1500):
        self.title = title
        self.width = width
        self.rows = []  # (label, [PIL RGBA], backdrop)

    def add(self, label: str, images, backdrop=None):
        self.rows.append((label, list(images), backdrop))

    def save(self, path: str):
        font = ImageFont.load_default(size=13)
        head = ImageFont.load_default(size=20)
        pad, gap, lab_h = 16, 18, 20
        heights = [lab_h + max((im.height for im in ims), default=0) + gap for _, ims, _ in self.rows]
        total = 52 + sum(heights) + pad
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
                bg = checker(sub.width, sub.height) if backdrop is None else Image.new(
                    "RGB", (sub.width, sub.height), backdrop)
                bg = bg.convert("RGBA")
                bg.alpha_composite(sub)
                im.paste(bg.convert("RGB"), (x, y))
                d.rectangle([x, y, x + sub.width - 1, y + sub.height - 1], outline=(90, 90, 98))
                x += sub.width + 12
            y += row_h + gap
        os.makedirs(os.path.dirname(path), exist_ok=True)
        im.save(path, optimize=True)
        print(f"wrote {path}  (contact sheet)")


# ─────────────────────────────────────────────────────────────────────────────
# Palette — dark velvet field, gilt metal, cabochon jewels.
# ─────────────────────────────────────────────────────────────────────────────
VELVET_DEEP = rgb(26, 14, 24)
VELVET = rgb(56, 26, 44)
VELVET_HI = rgb(84, 40, 62)
LEATHER = rgb(38, 25, 24)
GOLD_SHADOW = rgb(70, 48, 16)
GOLD_DARK = rgb(120, 88, 30)
GOLD = rgb(178, 140, 60)
GOLD_LIGHT = rgb(226, 196, 116)
GOLD_HI = rgb(252, 240, 198)
RUBY = rgb(158, 30, 44)
RUBY_HI = rgb(238, 108, 108)
EMERALD = rgb(30, 118, 78)
EMERALD_HI = rgb(126, 216, 158)
AMBER = rgb(255, 176, 62)
AMBER_HI = rgb(255, 236, 176)
INK = rgb(16, 10, 14)


def gild(canvas: Canvas, mask: np.ndarray, *, blur_r=0.9, dist=1, base=GOLD, warm=0.0):
    """Paint `mask` as bevelled gold on `canvas`."""
    h, w = mask.shape
    body = np.broadcast_to(base, (h, w, 3)).copy()
    # subtle length-independent metal banding (uniform per axis, slice-safe on
    # the horizontal edge bands because it varies only with y)
    band = (np.cos(np.linspace(0, math.pi, h)) * 0.5 + 0.5)[:, None, None]
    body = body * (0.86 + 0.30 * band) + GOLD_LIGHT * (0.10 * band)
    if warm:
        body = body * (1 - warm) + GOLD_HI * warm
    canvas.paint(np.clip(body, 0, 1), mask)
    hi, lo = emboss(mask, blur_r, dist)
    canvas.paint(GOLD_HI, hi * 0.85)
    canvas.paint(GOLD_SHADOW, lo * 0.80)


def velvet_field(rng, w, h, *, tone=VELVET, deep=VELVET_DEEP) -> np.ndarray:
    n = fbm(rng, w, h, octaves=5)
    fine = fbm(rng, w, h, octaves=6)
    t = np.clip(0.42 * n + 0.28 * fine + 0.15, 0, 1)[..., None]
    return deep[None, None, :] * (1 - t) + tone[None, None, :] * t


def edge_vignette(w, h, border, strength=0.65, power=1.5) -> np.ndarray:
    yy, xx = np.mgrid[0:h, 0:w]
    dist = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy))
    return (np.clip(1.0 - dist / max(1.0, border), 0, 1) ** power) * strength


def scroll_pts(cx, cy, a, b, t0, t1, n=90, rot=0.0):
    ts = np.linspace(t0, t1, n)
    r = a + b * ts
    return [
        (cx + r[i] * math.cos(ts[i] + rot), cy + r[i] * math.sin(ts[i] + rot))
        for i in range(n)
    ]


# ─────────────────────────────────────────────────────────────────────────────
# Assets
# ─────────────────────────────────────────────────────────────────────────────
def panel_fill(rng) -> Image.Image:
    """128x128, slice border 32 — dark velvet content-back."""
    w = h = 128
    c = Canvas(w, h)
    field = velvet_field(rng, w, h)
    c.paint(field, np.ones((h, w)))
    # edge falloff is uniform along each edge, so the stretched bands stay clean
    c.paint(VELVET_DEEP, edge_vignette(w, h, 32, 0.72, 1.4))
    # a faint gold hairline just inside the rim so the fill still reads framed
    m = Mask(w, h)
    m.rring([9, 9, w - 10, h - 10], 4, 1)
    c.paint(GOLD_DARK, m.arr() * 0.55)
    return c.image()


def panel_frame(rng) -> Image.Image:
    """160x160, slice border 40 — gold filigree border, transparent centre.

    Edge bands are uniform along their stretch axis (a moulding profile), so the
    frame never smears; the flourishes live entirely inside the 40px corners.
    """
    w = h = 160
    c = Canvas(w, h)

    # 1) the moulding profile, drawn across the FULL width/height so corners and
    #    edges are continuous by construction.
    band = Mask(w, h)
    band.rring([2, 2, w - 3, h - 3], 8, 5)       # outer roll
    band.rring([10, 10, w - 11, h - 11], 5, 2)   # fillet
    band.rring([15, 15, w - 16, h - 16], 4, 7)   # broad ogee
    band.rring([26, 26, w - 27, h - 27], 3, 2)   # inner fillet
    band_m = band.arr()
    gild(c, band_m, blur_r=0.9, dist=1)

    # bead-and-reel on the broad ogee: dots repeat with an exact period so the
    # corner squares end on a whole bead and the edge bands stay uniform.
    beads = Mask(w, h)
    step, r = 10, 2.2
    for i in range(w // step):
        x = step / 2 + i * step
        beads.ellipse([x - r, 18.5 - r, x + r, 18.5 + r])
        beads.ellipse([x - r, h - 18.5 - r, x + r, h - 18.5 + r])
    for i in range(h // step):
        y = step / 2 + i * step
        beads.ellipse([18.5 - r, y - r, 18.5 + r, y + r])
        beads.ellipse([w - 18.5 - r, y - r, w - 18.5 + r, y + r])
    bm = beads.arr() * band_m
    hi, lo = emboss(bm, 0.7, 1)
    c.paint(GOLD_HI, hi * 0.9)
    c.paint(GOLD_SHADOW, lo * 0.7)

    # 2) corner flourishes — confined to the 40x40 slice corners.
    corner = Mask(40, 40)
    #    a diagonal acanthus spray sitting on the inner ogee
    corner.poly([(28, 39), (39, 28), (39, 39)])                       # solid quoin
    corner.stroke([(39, 24), (32, 28), (28, 32), (24, 39)], 3.4)      # spandrel band
    corner.stroke(scroll_pts(30.0, 30.0, 1.8, 1.75, 0.0, 5.9, rot=2.2), 3.0)   # volute
    for a, ln in ((0.60, 20.0), (1.06, 16.5), (0.14, 16.5)):          # leaf lobes
        x0, y0 = 30.0, 30.0
        pts = [(x0 - ln * math.cos(a) * t, y0 - ln * math.sin(a) * t) for t in (0.0, 0.55, 1.0)]
        corner.stroke(pts, 2.8)
        corner.ellipse([pts[-1][0] - 2.3, pts[-1][1] - 2.3, pts[-1][0] + 2.3, pts[-1][1] + 2.3])
    corner.ellipse([26.6, 26.6, 33.4, 33.4])                          # boss
    cm_tl = corner.arr()[::-1, ::-1]  # authored bottom-right, used as top-left
    seat = np.zeros((h, w))
    for sy, sx, mm in ((0, 0, cm_tl), (0, w - 40, cm_tl[:, ::-1]),
                       (h - 40, 0, cm_tl[::-1, :]), (h - 40, w - 40, cm_tl[::-1, ::-1])):
        seat[sy:sy + 40, sx:sx + 40] = np.maximum(seat[sy:sy + 40, sx:sx + 40], mm)
    c.paint(GOLD_SHADOW, blur(seat, 1.6) * 0.75)  # dark seat so the spray separates
    full = np.zeros((h, w))
    full[0:40, 0:40] = np.maximum(full[0:40, 0:40], cm_tl)
    full[0:40, w - 40:w] = np.maximum(full[0:40, w - 40:w], cm_tl[:, ::-1])
    full[h - 40:h, 0:40] = np.maximum(full[h - 40:h, 0:40], cm_tl[::-1, :])
    full[h - 40:h, w - 40:w] = np.maximum(full[h - 40:h, w - 40:w], cm_tl[::-1, ::-1])
    gild(c, full, blur_r=0.8, dist=1, warm=0.10)

    # 3) knock the centre out so the fill layer below shows through
    hole = Mask(w, h)
    hole.rrect([30, 30, w - 31, h - 31], 4)
    keep = 1.0 - hole.arr()
    c.a = c.a * keep
    return c.image()


def corner_ornament(rng) -> Image.Image:
    """48x48 top-left ornament (the other three orientations are saved beside it).

    Reads as a quarter-frame: an L-bracket hugging the two edges, a volute
    curling inward at the elbow, acanthus lobes on the diagonal, ruby boss.
    """
    s = 48
    c = Canvas(s, s)
    m = Mask(s, s)
    # L-bracket along the top and left edges, tapering away from the corner
    m.poly([(2, 2), (44, 2), (44, 7), (9, 7), (9, 44), (2, 44)])
    m.poly([(2, 2), (18, 2), (2, 18)])                       # solid quoin
    m.stroke([(44, 4.5), (46, 6.5)], 2.0)
    # inner secondary rule ending in scrolls
    m.stroke([(14, 12), (36, 12)], 2.2)
    m.stroke([(12, 14), (12, 36)], 2.2)
    m.stroke(scroll_pts(35.0, 15.0, 1.0, 1.05, 0.0, 4.6, rot=4.4), 2.0)
    m.stroke(scroll_pts(15.0, 35.0, 1.0, 1.05, 0.0, 4.6, rot=2.9), 2.0)
    # elbow volute + acanthus lobes on the diagonal
    m.stroke(scroll_pts(17.5, 17.5, 1.6, 1.9, 0.0, 5.8, rot=0.8), 3.0)
    for a, ln in ((0.30, 20.0), (0.78, 17.0), (1.26, 20.0)):
        x0, y0 = 17.0, 17.0
        pts = [(x0 + ln * math.cos(a) * t, y0 + ln * math.sin(a) * t) for t in (0.0, 0.55, 1.0)]
        m.stroke(pts, 2.4)
        m.ellipse([pts[-1][0] - 2.1, pts[-1][1] - 2.1, pts[-1][0] + 2.1, pts[-1][1] + 2.1])
    m.ellipse([13.0, 13.0, 22.0, 22.0])                      # boss seat
    mask = m.arr()
    c.paint(GOLD_SHADOW, blur(mask, 1.8) * 0.55)  # cast shade so it lifts off panels
    gild(c, mask, blur_r=0.8, dist=1, warm=0.12)
    # ruby cabochon at the elbow
    j = Mask(s, s)
    j.ellipse([14.4, 14.4, 20.6, 20.6])
    c.paint(RUBY, j.arr())
    jh = Mask(s, s)
    jh.ellipse([15.6, 15.4, 18.4, 18.0])
    c.paint(RUBY_HI, jh.arr() * 0.9)
    return c.image()


def edge_rail(rng) -> Image.Image:
    """64x24 horizontal rail — seamless at x=0/64 (tile period 64)."""
    w, h = 64, 24
    c = Canvas(w, h)
    body = Mask(w, h)
    body.rrect([0, 5, w - 1, h - 6], 3)
    bm = body.arr()
    gild(c, bm, blur_r=0.8, dist=1)
    # repeating guilloche: a sine ribbon whose period divides the tile exactly
    rib = Mask(w, h)
    period = 16
    for phase in (0.0, math.pi):
        pts = []
        for x in range(0, (w + 1) * 2):
            xx = x / 2.0
            pts.append((xx, h / 2 + 3.1 * math.sin(2 * math.pi * xx / period + phase)))
        rib.stroke(pts, 1.6, caps=False)
    rm = rib.arr() * bm
    rhi, rlo = emboss(rm, 0.6, 1)
    c.paint(GOLD_HI, rhi * 0.85)
    c.paint(GOLD_SHADOW, rlo * 0.75)
    # studs on the period, centred so x=0 and x=64 land identically
    studs = Mask(w, h)
    for i in range(w // period):
        x = period / 2 + i * period
        studs.ellipse([x - 2.6, h / 2 - 2.6, x + 2.6, h / 2 + 2.6])
    sm = studs.arr() * bm
    c.paint(RUBY, sm)
    sh = Mask(w, h)
    for i in range(w // period):
        x = period / 2 + i * period
        sh.ellipse([x - 1.5, h / 2 - 1.7, x + 0.2, h / 2 - 0.1])
    c.paint(RUBY_HI, sh.arr() * 0.9)
    return c.image()


def plaque(rng) -> Image.Image:
    """176x56, slice border 20 — blank title board (text is a live sub-slot)."""
    w, h = 176, 56
    c = Canvas(w, h)
    outer = Mask(w, h)
    outer.rrect([2, 4, w - 3, h - 5], 8)
    om = outer.arr()
    c.paint(GOLD_SHADOW, blur(om, 2.0) * 0.5)
    gild(c, om, blur_r=1.1, dist=1)
    # recessed velvet face
    face = Mask(w, h)
    face.rrect([9, 11, w - 10, h - 12], 5)
    fm = face.arr()
    field = velvet_field(rng, w, h, tone=rgb(64, 30, 50))
    c.paint(field, fm)
    fhi, flo = emboss(fm, 1.0, 1)
    c.paint(INK, fhi * 0.75)          # inset: shade on the lit side
    c.paint(GOLD_LIGHT, flo * 0.35)
    # gold bead run along the face rim — uniform along x on the stretched bands
    rim = Mask(w, h)
    rim.rring([9, 11, w - 10, h - 12], 5, 1)
    c.paint(GOLD_LIGHT, rim.arr() * 0.8)
    return c.image()


def _button_common(rng, size, border, *, face_lo, face_hi, gold_warm, inset, rim_gold):
    w = h = size
    c = Canvas(w, h)
    outer = Mask(w, h)
    outer.rrect([1, 1, w - 2, h - 2], 7)
    om = outer.arr()
    gild(c, om, blur_r=1.0, dist=1, warm=gold_warm)
    # inner bezel step
    step = Mask(w, h)
    step.rring([5, 5, w - 6, h - 6], 5, 2)
    c.paint(GOLD_SHADOW if not rim_gold else GOLD_HI, step.arr() * 0.6)
    # face
    face = Mask(w, h)
    face.rrect([8, 8, w - 9, h - 9], 4)
    fm = face.arr()
    grad = vgrad(w, h, [(0.0, face_hi), (0.55, face_lo), (1.0, face_lo * 0.82)])
    tex = velvet_field(rng, w, h, tone=rgb(70, 34, 54))
    c.paint(np.clip(grad * 0.72 + tex * 0.28, 0, 1), fm)
    fhi, flo = emboss(fm, 1.0, 1)
    if inset:
        c.paint(INK, fhi * 0.85)
        c.paint(GOLD_LIGHT, flo * 0.30)
    else:
        c.paint(GOLD_HI, fhi * 0.30)
        c.paint(INK, flo * 0.55)
    return c, w, h, om


def button(rng, state: str) -> Image.Image:
    """64x64, slice border 16 — three REAL images, identical content insets."""
    cfg = {
        "default": dict(face_lo=rgb(52, 26, 42), face_hi=rgb(86, 44, 66),
                        gold_warm=0.0, inset=False, rim_gold=False),
        "hover": dict(face_lo=rgb(78, 40, 60), face_hi=rgb(116, 62, 88),
                      gold_warm=0.26, inset=False, rim_gold=True),
        "pressed": dict(face_lo=rgb(30, 14, 25), face_hi=rgb(44, 22, 36),
                        gold_warm=-0.0, inset=True, rim_gold=False),
    }[state]
    c, w, h, om = _button_common(rng, 64, 16, **cfg)
    if state == "pressed":
        # darken the whole slab and drop a cast shadow inside the bezel
        c.rgb *= 0.72
        sh = Mask(w, h)
        sh.rrect([8, 8, w - 9, 20], 4)
        c.paint(INK, blur(sh.arr(), 2.2) * 0.45)
    if state == "hover":
        glow = Mask(w, h)
        glow.rring([1, 1, w - 2, h - 2], 7, 2)
        c.paint(GOLD_HI, blur(glow.arr(), 1.4) * 0.55)
    return c.image()


def selection(rng, state: str) -> Image.Image:
    """64x64, slice border 16 — 'selected' is a different construction, not a tint.

    Jewel studs live inside the 16px CORNER regions: the left/right slice bands
    stretch vertically, so a mid-edge gem would smear (see provenance note).
    """
    w = h = 64
    c = Canvas(w, h)
    if state == "default":
        plate = Mask(w, h)
        plate.rrect([2, 2, w - 3, h - 3], 6)
        pm = plate.arr()
        c.paint(velvet_field(rng, w, h, tone=rgb(48, 24, 38)) * 0.8, pm * 0.92)
        rim = Mask(w, h)
        rim.rring([2, 2, w - 3, h - 3], 6, 1)
        c.paint(GOLD_DARK, rim.arr() * 0.65)
        return c.image()

    # selected: raised gilt plate, double rule, emerald-lit field, corner rubies
    outer = Mask(w, h)
    outer.rrect([0, 0, w - 1, h - 1], 7)
    om = outer.arr()
    gild(c, om, blur_r=1.0, dist=1, warm=0.28)
    inner = Mask(w, h)
    inner.rring([4, 4, w - 5, h - 5], 5, 2)
    c.paint(GOLD_HI, inner.arr() * 0.8)
    face = Mask(w, h)
    face.rrect([8, 8, w - 9, h - 9], 4)
    fm = face.arr()
    grad = vgrad(w, h, [(0.0, rgb(24, 66, 52)), (0.5, rgb(16, 46, 38)), (1.0, rgb(10, 30, 26))])
    c.paint(grad, fm)
    glowm = blur(fm, 3.0) * fm
    c.paint(EMERALD_HI, glowm * 0.22)
    fhi, flo = emboss(fm, 1.0, 1)
    c.paint(INK, fhi * 0.6)
    c.paint(EMERALD_HI, flo * 0.35)
    # four ruby cabochons, one per slice corner
    for cx, cy in ((8, 8), (w - 9, 8), (8, h - 9), (w - 9, h - 9)):
        g = Mask(w, h)
        g.ellipse([cx - 4.2, cy - 4.2, cx + 4.2, cy + 4.2])
        gm = g.arr()
        gild(c, gm, blur_r=0.6, dist=1, warm=0.5)
        g2 = Mask(w, h)
        g2.ellipse([cx - 2.8, cy - 2.8, cx + 2.8, cy + 2.8])
        c.paint(RUBY, g2.arr())
        g3 = Mask(w, h)
        g3.ellipse([cx - 1.9, cy - 1.9, cx - 0.1, cy - 0.3])
        c.paint(RUBY_HI, g3.arr() * 0.95)
    return c.image()


def field(rng) -> Image.Image:
    """64x64, slice border 16 — dark inset writing surface."""
    w = h = 64
    c = Canvas(w, h)
    outer = Mask(w, h)
    outer.rrect([1, 1, w - 2, h - 2], 6)
    om = outer.arr()
    gild(c, om, blur_r=1.0, dist=1)
    well = Mask(w, h)
    well.rrect([6, 6, w - 7, h - 7], 4)
    wm = well.arr()
    grad = vgrad(w, h, [(0.0, rgb(18, 12, 16)), (0.45, rgb(30, 20, 28)), (1.0, rgb(38, 26, 34))])
    c.paint(grad, wm)
    whi, wlo = emboss(wm, 1.4, 2)
    c.paint(INK, whi * 0.95)                 # deep inner shadow at the top-left
    c.paint(GOLD_LIGHT, wlo * 0.28)
    rim = Mask(w, h)
    rim.rring([6, 6, w - 7, h - 7], 4, 1)
    c.paint(GOLD_DARK, rim.arr() * 0.7)
    return c.image()


def bar_track(rng) -> Image.Image:
    """96x28, slice border 12 — carved groove with a gold rim."""
    w, h = 96, 28
    c = Canvas(w, h)
    outer = Mask(w, h)
    outer.rrect([0, 1, w - 1, h - 2], 9)
    om = outer.arr()
    gild(c, om, blur_r=1.0, dist=1)
    groove = Mask(w, h)
    groove.rrect([5, 6, w - 6, h - 7], 5)
    gm = groove.arr()
    c.paint(vgrad(w, h, [(0.0, rgb(14, 8, 12)), (0.6, rgb(26, 16, 24)), (1.0, rgb(34, 22, 30))]), gm)
    ghi, glo = emboss(gm, 1.3, 2)
    c.paint(INK, ghi * 0.95)
    c.paint(GOLD_LIGHT, glo * 0.30)
    rim = Mask(w, h)
    rim.rring([5, 6, w - 6, h - 7], 5, 1)
    c.paint(GOLD_DARK, rim.arr() * 0.8)
    return c.image()


def bar_fill(rng) -> Image.Image:
    """96x20, slice border 8 — glowing liquid.

    The centre band is X-UNIFORM by construction (every pixel column between the
    slice borders is identical), which is what makes a stretched / partially
    revealed fill read correctly at any percent.
    """
    w, h = 96, 20
    c = Canvas(w, h)
    body = Mask(w, h)
    body.rrect([0, 0, w - 1, h - 1], 6)
    bm = body.arr()
    grad = vgrad(w, h, [
        (0.00, rgb(255, 226, 150)),
        (0.22, AMBER),
        (0.55, rgb(226, 122, 26)),
        (0.80, rgb(168, 66, 16)),
        (1.00, rgb(120, 40, 12)),
    ])
    c.paint(grad, bm)
    # gloss: a horizontal band, uniform along x
    gloss = Mask(w, h)
    gloss.rrect([0, 2, w - 1, 6], 2)
    c.paint(AMBER_HI, blur(gloss.arr(), 1.2) * bm * 0.55)
    # inner glow at the rim, uniform per axis
    ring = Mask(w, h)
    ring.rring([0, 0, w - 1, h - 1], 6, 1)
    c.paint(rgb(255, 246, 214), ring.arr() * 0.45)
    # force exact X-uniformity across the stretched centre: broadcast column w/2
    b = 8
    col_rgb = c.rgb[:, w // 2:w // 2 + 1, :]
    col_a = c.a[:, w // 2:w // 2 + 1]
    c.rgb[:, b:w - b, :] = col_rgb
    c.a[:, b:w - b] = col_a
    return c.image()


def bar_cap(rng, side: str) -> Image.Image:
    """28x36 gold finial; the end cap is the mirrored start cap."""
    w, h = 28, 36
    c = Canvas(w, h)
    m = Mask(w, h)
    m.poly([(3, 18), (11, 3), (24, 8), (24, 28), (11, 33)])
    m.ellipse([12, 11, 26, 25])
    m.stroke(scroll_pts(9, 18, 1.0, 1.1, 0.0, 4.2, rot=1.6), 2.4)
    mm = m.arr()
    c.paint(GOLD_SHADOW, blur(mm, 1.8) * 0.5)
    gild(c, mm, blur_r=0.9, dist=1, warm=0.2)
    j = Mask(w, h)
    j.ellipse([15, 14, 23, 22])
    c.paint(RUBY, j.arr())
    jh = Mask(w, h)
    jh.ellipse([16.2, 15.2, 19.4, 18.0])
    c.paint(RUBY_HI, jh.arr() * 0.9)
    img = c.image()
    return img if side == "start" else img.transpose(Image.FLIP_LEFT_RIGHT)


def bar_center(rng) -> Image.Image:
    """36x28 crown centrepiece (whole image)."""
    w, h = 36, 28
    c = Canvas(w, h)
    m = Mask(w, h)
    m.poly([(4, 22), (6, 8), (12, 15), (18, 4), (24, 15), (30, 8), (32, 22)])
    m.rect([4, 20, 32, 25])
    mm = m.arr()
    c.paint(GOLD_SHADOW, blur(mm, 1.8) * 0.5)
    gild(c, mm, blur_r=0.8, dist=1, warm=0.22)
    for cx, cy, col in ((6.5, 8.5, EMERALD), (18, 5.5, RUBY), (29.5, 8.5, EMERALD)):
        g = Mask(w, h)
        g.ellipse([cx - 2.3, cy - 2.3, cx + 2.3, cy + 2.3])
        c.paint(col, g.arr())
    band = Mask(w, h)
    band.rect([5, 21.5, 31, 23.5])
    c.paint(RUBY, band.arr() * 0.75)
    return c.image()


def toggle_track(rng, state: str) -> Image.Image:
    """72x32, slice border 14 — two-tone carved channel."""
    w, h = 72, 32
    c = Canvas(w, h)
    outer = Mask(w, h)
    outer.rrect([0, 1, w - 1, h - 2], 12)
    gild(c, outer.arr(), blur_r=1.0, dist=1, warm=0.25 if state == "on" else 0.0)
    ch = Mask(w, h)
    ch.rrect([4, 5, w - 5, h - 6], 9)
    cm = ch.arr()
    if state == "on":
        grad = vgrad(w, h, [(0.0, rgb(70, 178, 122)), (0.5, EMERALD), (1.0, rgb(14, 66, 46))])
        c.paint(grad, cm)
        c.paint(EMERALD_HI, blur(cm, 3.0) * cm * 0.25)
    else:
        grad = vgrad(w, h, [(0.0, rgb(20, 14, 20)), (0.5, rgb(34, 24, 32)), (1.0, rgb(46, 34, 42))])
        c.paint(grad, cm)
    chi, clo = emboss(cm, 1.3, 2)
    c.paint(INK, chi * (0.7 if state == "on" else 0.95))
    c.paint(GOLD_LIGHT, clo * 0.30)
    rim = Mask(w, h)
    rim.rring([4, 5, w - 5, h - 6], 9, 1)
    c.paint(GOLD_LIGHT if state == "on" else GOLD_DARK, rim.arr() * 0.75)
    return c.image()


def toggle_knob(rng, state: str) -> Image.Image:
    """28x28 jewelled disc (whole image)."""
    s = 28
    c = Canvas(s, s)
    ring = Mask(s, s)
    ring.ellipse([1, 1, s - 2, s - 2])
    rm = ring.arr()
    c.paint(GOLD_SHADOW, blur(rm, 1.8) * 0.55)
    gild(c, rm, blur_r=0.9, dist=1, warm=0.3 if state == "default" else 0.0)
    j = Mask(s, s)
    j.ellipse([6, 6, s - 7, s - 7])
    jm = j.arr()
    grad = vgrad(s, s, [(0.0, rgb(214, 74, 92)), (0.45, RUBY), (1.0, rgb(84, 14, 28))])
    c.paint(grad if state == "default" else grad * 0.62, jm)
    jh = Mask(s, s)
    jh.ellipse([9, 8.5, 14, 12.5])
    c.paint(RUBY_HI, jh.arr() * (0.95 if state == "default" else 0.45))
    if state == "pressed":
        c.rgb *= 0.78
        sh = Mask(s, s)
        sh.ellipse([5, 5, s - 6, s - 6])
        c.paint(INK, blur(sh.arr(), 1.6) * 0.28)
    return c.image()


def stepper_plate(rng, state: str) -> Image.Image:
    """40x40, slice border 12 — glyph plate behind a stepper icon."""
    w = h = 40
    c = Canvas(w, h)
    outer = Mask(w, h)
    outer.rrect([1, 1, w - 2, h - 2], 6)
    gild(c, outer.arr(), blur_r=0.9, dist=1, warm=0.15 if state == "default" else 0.0)
    face = Mask(w, h)
    face.rrect([6, 6, w - 7, h - 7], 3)
    fm = face.arr()
    if state == "default":
        c.paint(vgrad(w, h, [(0.0, rgb(84, 42, 64)), (1.0, rgb(46, 22, 38))]), fm)
        fhi, flo = emboss(fm, 1.0, 1)
        c.paint(GOLD_HI, fhi * 0.28)
        c.paint(INK, flo * 0.5)
    else:
        c.paint(vgrad(w, h, [(0.0, rgb(26, 12, 22)), (1.0, rgb(42, 20, 34))]), fm)
        fhi, flo = emboss(fm, 1.2, 2)
        c.paint(INK, fhi * 0.9)
        c.paint(GOLD_LIGHT, flo * 0.3)
        c.rgb *= 0.8
    return c.image()


ICON_WHITE = rgb(240, 240, 242)


def icon(name: str) -> Image.Image:
    """32x32 near-white glyph on transparency (R4: tint comes from the role)."""
    s = 32
    m = Mask(s, s)
    if name == "chevron_right":
        m.stroke([(12, 7), (21, 16), (12, 25)], 3.6)
    elif name == "chevron_down":
        m.stroke([(7, 12), (16, 21), (25, 12)], 3.6)
    elif name == "plus":
        m.rrect([14.2, 6, 17.8, 26], 1.6)
        m.rrect([6, 14.2, 26, 17.8], 1.6)
    elif name == "minus":
        m.rrect([6, 14.2, 26, 17.8], 1.6)
    elif name == "check":
        m.stroke([(7, 17), (13.5, 23.5), (25, 9)], 3.8)
    elif name == "cross":
        m.stroke([(9, 9), (23, 23)], 3.6)
        m.stroke([(23, 9), (9, 23)], 3.6)
    elif name == "gear":
        cx = cy = 16.0
        R, r = 14.2, 10.2
        n = 8
        pts = []
        span = 2 * math.pi / n
        for i in range(n):
            a0 = i * span - math.pi / 2
            pts += [
                (cx + R * math.cos(a0 - span * 0.20), cy + R * math.sin(a0 - span * 0.20)),
                (cx + R * math.cos(a0 + span * 0.20), cy + R * math.sin(a0 + span * 0.20)),
                (cx + r * math.cos(a0 + span * 0.30), cy + r * math.sin(a0 + span * 0.30)),
                (cx + r * math.cos(a0 + span * 0.70), cy + r * math.sin(a0 + span * 0.70)),
            ]
        m.poly(pts)
        m.ellipse([cx - 10.2, cy - 10.2, cx + 10.2, cy + 10.2])
        hole = Mask(s, s)
        hole.ellipse([cx - 4.6, cy - 4.6, cx + 4.6, cy + 4.6])
        arr = np.clip(m.arr() - hole.arr(), 0, 1)
        c = Canvas(s, s)
        c.paint(ICON_WHITE, arr)
        return c.image()
    else:
        raise ValueError(name)
    c = Canvas(s, s)
    c.paint(ICON_WHITE, m.arr())
    return c.image()


def velvet_tile(rng) -> Image.Image:
    """64x64 seamless damask tile for a `tile` layer (period 64x64)."""
    w = h = 64
    c = Canvas(w, h)
    base = velvet_field(rng, w, h)
    # make the base seamless by cross-fading with its own wrapped copy
    ax = (np.cos(np.linspace(0, 2 * math.pi, w, endpoint=False)) * 0.5 + 0.5)[None, :, None]
    ay = (np.cos(np.linspace(0, 2 * math.pi, h, endpoint=False)) * 0.5 + 0.5)[:, None, None]
    base = base * (ax * ay) + np.roll(np.roll(base, w // 2, 1), h // 2, 0) * (1 - ax * ay)
    c.paint(np.clip(base, 0, 1), np.ones((h, w)))
    motif = Mask(w, h)
    for ox, oy in ((0, 0), (w, 0), (0, h), (w, h), (w // 2, h // 2),
                   (-w // 2, h // 2), (w // 2, -h // 2), (3 * w // 2, h // 2), (w // 2, 3 * h // 2)):
        motif.poly([(ox, oy - 11), (ox + 7, oy), (ox, oy + 11), (ox - 7, oy)])
        motif.stroke(scroll_pts(ox, oy, 1.0, 1.0, 0.0, 3.4), 1.4)
    c.paint(VELVET_HI, motif.arr() * 0.42)
    return c.image()


# ─────────────────────────────────────────────────────────────────────────────
def main() -> None:
    def r(k):
        return np.random.default_rng(SEED + k)

    # (filename, image, slice border or None, preview sizes)
    items = []
    items.append(("ornate_panel_fill.png", panel_fill(r(1)), 32, [(180, 110), (320, 200), (460, 130)]))
    items.append(("ornate_panel_frame.png", panel_frame(r(2)), 40, [(180, 140), (330, 210), (470, 150)]))
    tl = corner_ornament(r(3))
    items.append(("ornate_corner_tl.png", tl, None, None))
    items.append(("ornate_corner_tr.png", tl.transpose(Image.FLIP_LEFT_RIGHT), None, None))
    items.append(("ornate_corner_bl.png", tl.transpose(Image.FLIP_TOP_BOTTOM), None, None))
    items.append(("ornate_corner_br.png", tl.transpose(Image.ROTATE_180), None, None))
    # rail is a TILE asset (period 64x24) — nine-slicing it stretches the studs,
    # so the package declares tileSize, never a slice border.
    items.append(("ornate_edge_rail.png", edge_rail(r(4)), None, None))
    items.append(("ornate_plaque.png", plaque(r(5)), 20, [(140, 56), (240, 56), (380, 56)]))
    for i, st in enumerate(("default", "hover", "pressed")):
        items.append((f"ornate_button_{st}.png", button(r(10 + i), st), 16, [(140, 44)]))
    for i, st in enumerate(("default", "selected")):
        items.append((f"ornate_selection_{st}.png", selection(r(20 + i), st), 16, [(200, 44)]))
    items.append(("ornate_field.png", field(r(30)), 16, [(160, 44), (280, 44), (160, 64)]))
    items.append(("ornate_bar_track.png", bar_track(r(40)), 12, [(120, 28), (240, 28), (360, 28)]))
    items.append(("ornate_bar_fill.png", bar_fill(r(41)), 8, [(40, 20), (140, 20), (300, 20)]))
    items.append(("ornate_bar_cap_start.png", bar_cap(r(42), "start"), None, None))
    items.append(("ornate_bar_cap_end.png", bar_cap(r(42), "end"), None, None))
    items.append(("ornate_bar_center.png", bar_center(r(43)), None, None))
    for i, st in enumerate(("off", "on")):
        items.append((f"ornate_toggle_track_{st}.png", toggle_track(r(50 + i), st), 14, [(72, 32), (96, 32)]))
    for i, st in enumerate(("default", "pressed")):
        items.append((f"ornate_toggle_knob_{st}.png", toggle_knob(r(55 + i), st), None, None))
    for i, st in enumerate(("default", "pressed")):
        items.append((f"ornate_stepper_plate_{st}.png", stepper_plate(r(60 + i), st), 12, [(40, 40), (64, 40)]))
    items.append(("ornate_velvet_tile.png", velvet_tile(r(70)), None, None))
    for nm in ("chevron_right", "chevron_down", "plus", "minus", "check", "cross", "gear"):
        items.append((f"ornate_icon_{nm}.png", icon(nm), None, None))

    for name, img, border, _ in items:
        path = os.path.join(OUT_DIR, name)
        img.save(path, optimize=True)
        b = f"slice {border}" if border else "whole image"
        print(f"wrote {path}  ({img.width}x{img.height}, {b})")

    # ── contact sheet ────────────────────────────────────────────────────────
    sheet = Sheet("fantasy-ornate — nine-slice stretch test + whole-image assets")
    by = {n: (i, b, p) for n, i, b, p in items}

    def row(label, names, sizes=None):
        imgs = []
        for n in names:
            img, border, prev = by[n]
            use = sizes or prev
            if border and use:
                imgs += [nine_slice(img, border, w, h) for w, h in use]
            else:
                imgs.append(img)
        sheet.add(label, imgs)

    row("panel fill  (128x128 b32) stretched 180x110 / 320x200 / 460x130", ["ornate_panel_fill.png"])
    row("panel frame (160x160 b40) stretched — corners must stay crisp", ["ornate_panel_frame.png"])
    row("corner ornaments tl / tr / bl / br (48x48 whole)",
        ["ornate_corner_tl.png", "ornate_corner_tr.png", "ornate_corner_bl.png", "ornate_corner_br.png"])
    # rail tiled, the way a package uses it
    rail = by["ornate_edge_rail.png"][0]
    tiled = Image.new("RGBA", (384, 24), (0, 0, 0, 0))
    for i in range(6):
        tiled.alpha_composite(rail, (i * 64, 0))
    sheet.add("edge rail 64x24 — TILED x6 (tile-only asset, period 64; seam must be invisible)", [tiled])
    row("plaque (176x56 b20) stretched — blank board, text is a live sub-slot", ["ornate_plaque.png"])
    row("button default / hover / pressed @140x44 (same insets, different art)",
        ["ornate_button_default.png", "ornate_button_hover.png", "ornate_button_pressed.png"])
    row("button default @ 80x44 / 240x44 / 140x88 — slice stress",
        ["ornate_button_default.png"], sizes=[(80, 44), (240, 44), (140, 88)])
    row("selection default / selected @200x44 — 'selected' is a new construction",
        ["ornate_selection_default.png", "ornate_selection_selected.png"])
    row("field (64x64 b16) stretched", ["ornate_field.png"])
    row("bar track (96x28 b12) stretched", ["ornate_bar_track.png"])
    row("bar fill (96x20 b8) stretched 40 / 140 / 300 px", ["ornate_bar_fill.png"])
    # an assembled bar at three percents
    trk = by["ornate_bar_track.png"][0]
    fil = by["ornate_bar_fill.png"][0]
    cap_s = by["ornate_bar_cap_start.png"][0]
    cap_e = by["ornate_bar_cap_end.png"][0]
    ctr = by["ornate_bar_center.png"][0]
    assembled = []
    for pct in (0.15, 0.55, 1.0):
        bw, bh = 300, 36
        comp = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
        comp.alpha_composite(nine_slice(trk, 12, bw - 24, 28), (12, 4))
        full = nine_slice(fil, 8, bw - 34, 20)
        comp.alpha_composite(full.crop((0, 0, max(1, int((bw - 34) * pct)), 20)), (17, 8))
        comp.alpha_composite(cap_s, (0, 0))
        comp.alpha_composite(cap_e, (bw - 28, 0))
        comp.alpha_composite(ctr, ((bw - 36) // 2, 4))
        assembled.append(comp)
    sheet.add("assembled bar: track + window-clipped fill (15/55/100%) + caps + crown", assembled)
    row("toggle track off / on (72x32 b14) + knob default / pressed (28x28)",
        ["ornate_toggle_track_off.png", "ornate_toggle_track_on.png",
         "ornate_toggle_knob_default.png", "ornate_toggle_knob_pressed.png"])
    row("stepper plate default / pressed (40x40 b12) at 40x40 and 64x40",
        ["ornate_stepper_plate_default.png", "ornate_stepper_plate_pressed.png"])
    tile = by["ornate_velvet_tile.png"][0]
    tiled2 = Image.new("RGBA", (256, 128), (0, 0, 0, 0))
    for yy in range(2):
        for xx in range(4):
            tiled2.alpha_composite(tile, (xx * 64, yy * 64))
    sheet.add("velvet damask tile 64x64 — TILED 4x2 (seam check)", [tiled2])
    icons = [by[f"ornate_icon_{n}.png"][0] for n in
             ("chevron_right", "chevron_down", "plus", "minus", "check", "cross", "gear")]
    sheet.add("icons 32x32 near-white on transparency (chevron_right/down, plus, minus, check, cross, gear)", icons)
    sheet.save(os.path.join(PREVIEW_DIR, "contact-sheet.png"))


if __name__ == "__main__":
    main()
