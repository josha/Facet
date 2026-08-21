#!/usr/bin/env python3
"""Compact Pointer art generator (rich-skinning-v2 stage, ADR-0020 / charter cap 8).

Original, repository-owned art: every texture below is generated procedurally by
this script from the fixed seed `SEED` — no external imagery, no third-party
assets, and NO trade dress. The brief's reference ("desktop-pointer-class") names a
*category* of chrome — compact ~22 px pointer controls, near-flat surfaces,
hairline borders, subtle top-lit gradients, cool greys — not any vendor's
pixels: palette, geometry, gradient stops and border construction are invented
here.

This is the DESKTOP half of the platform pair; `glossy-touch` is the touch half.
Everything is authored AT the target control height so a 1 px hairline stays
exactly 1 px and the gradient maps 1:1 (nine-slice never re-scales it).

Run with the repo-root shared venv python (any CWD works):
  <repo-root>/.venv/bin/python generate_art.py
"""

from __future__ import annotations

import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.dirname(HERE)
PREVIEW_DIR = os.path.join(HERE, "preview")
SEED = 0xC0DE  # fixed: determinism is the provenance claim

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

    def rrect(self, box, radius, fill=255):
        self.d.rounded_rectangle(self._s(box), radius=radius * self.ss, fill=fill)

    def ellipse(self, box, fill=255):
        self.d.ellipse(self._s(box), fill=fill)

    def rect(self, box, fill=255):
        self.d.rectangle(self._s(box), fill=fill)

    def arr(self):
        return _f(self.im.resize((self.w, self.h), Image.LANCZOS))


def rrect_mask(w, h, box, radius):
    m = Mask(w, h)
    m.rrect(box, radius)
    return m.arr()


def hairline(w, h, box, radius, inset=1.0):
    """A crisp 1 px border band: outer shape minus the same shape inset by 1 px.
    Straight runs come out fully opaque (a true hairline); corners stay smooth."""
    x0, y0, x1, y1 = box
    outer = rrect_mask(w, h, box, radius)
    inner = rrect_mask(w, h, [x0 + inset, y0 + inset, x1 - inset, y1 - inset],
                       max(0.0, radius - inset))
    return np.clip(outer - inner, 0, 1)


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
# Palette — cool greys, one desaturated action blue. Near-flat by design.
# ─────────────────────────────────────────────────────────────────────────────
WHITE = rgb(255, 255, 255)
PANEL_TOP = rgb(252, 252, 253)
PANEL_BOT = rgb(242, 243, 246)
BTN_TOP = rgb(255, 255, 255)
BTN_BOT = rgb(236, 238, 243)
HOV_TOP = rgb(252, 253, 255)
HOV_BOT = rgb(228, 238, 252)
HOV_LINE = rgb(142, 170, 214)
PRS_TOP = rgb(210, 214, 222)
PRS_BOT = rgb(228, 231, 238)
LINE = rgb(178, 184, 195)
LINE_SOFT = rgb(202, 207, 216)
LINE_STRONG = rgb(150, 157, 171)
DROP = rgb(120, 128, 143)
WELL_TOP = rgb(238, 240, 245)
WELL_BOT = rgb(255, 255, 255)
TRACK_TOP = rgb(216, 220, 228)
TRACK_BOT = rgb(236, 238, 243)
ACCENT_TOP = rgb(90, 142, 226)
ACCENT_BOT = rgb(52, 104, 200)
ACCENT_LINE = rgb(40, 84, 168)


def panel(rng) -> Image.Image:
    """48x48, slice border 12 — flat card with a hairline and a soft top lift."""
    w = h = 48
    c = Canvas(w, h)
    box = [0, 0, w - 1, h - 1]
    bm = rrect_mask(w, h, box, 6)
    c.paint(vgrad(w, h, [(0.0, PANEL_TOP), (1.0, PANEL_BOT)]), bm)
    c.paint(LINE_SOFT, hairline(w, h, box, 6))
    c.paint(WHITE, hairline(w, h, [1, 1, w - 2, h - 2], 5) * 0.55)
    return c.image()


def button(rng, state: str) -> Image.Image:
    """32x22, slice border 8 — authored at the 22 px pointer-control height."""
    w, h = 32, 22
    c = Canvas(w, h)
    box = [0, 0, w - 1, h - 2]        # last row reserved for the 1 px drop line
    bm = rrect_mask(w, h, box, 4)
    if state == "default":
        top, bot, line = BTN_TOP, BTN_BOT, LINE
    elif state == "hover":
        top, bot, line = HOV_TOP, HOV_BOT, HOV_LINE
    else:
        top, bot, line = PRS_TOP, PRS_BOT, LINE_STRONG
    if state != "pressed":
        c.paint(DROP, shift(bm, 0, 1) * 0.16)  # 1 px shadow under the shape
    c.paint(vgrad(w, h, [(0.0, top), (1.0, bot)]), bm)
    if state == "pressed":
        inner = np.clip(bm - shift(bm, 0, 2), 0, 1)
        c.paint(DROP, blur(inner, 0.9) * 0.35)
    else:
        c.paint(WHITE, hairline(w, h, [1, 1, w - 2, h - 3], 3) * 0.55)
    c.paint(line, hairline(w, h, box, 4))
    return c.image()


def field(rng) -> Image.Image:
    """32x22, slice border 8 — inset well, hairline, 1 px top inner shadow."""
    w, h = 32, 22
    c = Canvas(w, h)
    box = [0, 0, w - 1, h - 1]
    bm = rrect_mask(w, h, box, 3)
    c.paint(vgrad(w, h, [(0.0, WELL_TOP), (0.30, WELL_BOT), (1.0, WHITE)]), bm)
    inner = np.clip(bm - shift(bm, 0, 2), 0, 1)
    c.paint(DROP, blur(inner, 0.8) * 0.30)
    c.paint(LINE, hairline(w, h, box, 3))
    return c.image()


def bar_track(rng) -> Image.Image:
    """48x10, slice border 4 — shallow trough. Minimum rendered height 10 px."""
    w, h = 48, 10
    c = Canvas(w, h)
    box = [0, 0, w - 1, h - 1]
    bm = rrect_mask(w, h, box, 4)
    c.paint(vgrad(w, h, [(0.0, TRACK_TOP), (1.0, TRACK_BOT)]), bm)
    c.paint(LINE_SOFT, hairline(w, h, box, 4))
    return c.image()


def bar_fill(rng) -> Image.Image:
    """48x8, slice border 3 — accent fill; centre band forced X-uniform."""
    w, h = 48, 8
    c = Canvas(w, h)
    box = [0, 0, w - 1, h - 1]
    bm = rrect_mask(w, h, box, 3)
    c.paint(vgrad(w, h, [(0.0, ACCENT_TOP), (1.0, ACCENT_BOT)]), bm)
    c.paint(WHITE, hairline(w, h, [0.5, 0.5, w - 1.5, h - 1.5], 2.5) * 0.22)
    c.paint(ACCENT_LINE, hairline(w, h, box, 3) * 0.55)
    b = 3
    c.rgb[:, b:w - b, :] = c.rgb[:, w // 2:w // 2 + 1, :]
    c.a[:, b:w - b] = c.a[:, w // 2:w // 2 + 1]
    return c.image()


def toggle_track(rng, state: str) -> Image.Image:
    """36x18, slice border 8 — small capsule."""
    w, h = 36, 18
    c = Canvas(w, h)
    box = [0, 0, w - 1, h - 1]
    bm = rrect_mask(w, h, box, 8)
    if state == "on":
        c.paint(vgrad(w, h, [(0.0, ACCENT_TOP), (1.0, ACCENT_BOT)]), bm)
        c.paint(WHITE, hairline(w, h, [1, 1, w - 2, h - 2], 7) * 0.22)
        c.paint(ACCENT_LINE, hairline(w, h, box, 8))
    else:
        c.paint(vgrad(w, h, [(0.0, TRACK_TOP), (1.0, rgb(246, 247, 250))]), bm)
        inner = np.clip(bm - shift(bm, 0, 2), 0, 1)
        c.paint(DROP, blur(inner, 0.8) * 0.28)
        c.paint(LINE, hairline(w, h, box, 8))
    return c.image()


def toggle_knob(rng) -> Image.Image:
    """16x16 whole image — small white knob."""
    s = 16
    c = Canvas(s, s)
    body = Mask(s, s)
    body.ellipse([0, 0, s - 2, s - 2])
    bm = body.arr()
    c.paint(DROP, blur(shift(bm, 0, 1), 0.9) * 0.34)
    c.paint(vgrad(s, s, [(0.0, WHITE), (1.0, rgb(238, 240, 245))]), bm)
    inner = Mask(s, s)
    inner.ellipse([1, 1, s - 3, s - 3])
    c.paint(LINE, np.clip(bm - inner.arr(), 0, 1) * 0.9)
    return c.image()


def stepper_plate(rng, state: str) -> Image.Image:
    """22x22, slice border 7 — glyph plate for stepper +/- halves."""
    w = h = 22
    c = Canvas(w, h)
    box = [0, 0, w - 1, h - 2]
    bm = rrect_mask(w, h, box, 4)
    if state == "default":
        c.paint(DROP, shift(bm, 0, 1) * 0.16)
        c.paint(vgrad(w, h, [(0.0, BTN_TOP), (1.0, BTN_BOT)]), bm)
        c.paint(WHITE, hairline(w, h, [1, 1, w - 2, h - 3], 3) * 0.55)
        c.paint(LINE, hairline(w, h, box, 4))
    else:
        c.paint(vgrad(w, h, [(0.0, PRS_TOP), (1.0, PRS_BOT)]), bm)
        inner = np.clip(bm - shift(bm, 0, 2), 0, 1)
        c.paint(DROP, blur(inner, 0.9) * 0.38)
        c.paint(LINE_STRONG, hairline(w, h, box, 4))
    return c.image()


# ─────────────────────────────────────────────────────────────────────────────
def main() -> None:
    def r(k):
        return np.random.default_rng(SEED + k)

    items = []
    items.append(("compact_panel.png", panel(r(1)), 12, [(180, 90), (300, 160), (420, 100)]))
    items.append(("compact_button_default.png", button(r(2), "default"), 8, [(90, 22)]))
    items.append(("compact_button_hover.png", button(r(3), "hover"), 8, [(90, 22)]))
    items.append(("compact_button_pressed.png", button(r(4), "pressed"), 8, [(90, 22)]))
    items.append(("compact_field.png", field(r(5)), 8, [(140, 22), (240, 22), (100, 44)]))
    items.append(("compact_bar_track.png", bar_track(r(6)), 4, [(90, 10), (200, 10), (320, 10)]))
    items.append(("compact_bar_fill.png", bar_fill(r(7)), 3, [(40, 8), (140, 8), (280, 8)]))
    items.append(("compact_toggle_track_off.png", toggle_track(r(8), "off"), 8, [(36, 18), (48, 18)]))
    items.append(("compact_toggle_track_on.png", toggle_track(r(9), "on"), 8, [(36, 18), (48, 18)]))
    items.append(("compact_toggle_knob.png", toggle_knob(r(10)), None, None))
    items.append(("compact_stepper_plate_default.png", stepper_plate(r(11), "default"), 7, [(22, 22), (34, 22)]))
    items.append(("compact_stepper_plate_pressed.png", stepper_plate(r(12), "pressed"), 7, [(22, 22), (34, 22)]))

    for name, img, border, _ in items:
        path = os.path.join(OUT_DIR, name)
        img.save(path, optimize=True)
        b = f"slice {border}" if border else "whole image"
        print(f"wrote {path}  ({img.width}x{img.height}, {b})")

    sheet = Sheet("compact-pointer — 22px pointer scale, hairline borders, nine-slice stretch test")
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

    # a light backdrop is the honest read for this package: it is designed for a
    # near-white desktop window, and hairlines vanish against the dark sheet.
    LIGHT = (223, 226, 233)
    row("panel (48x48 b12) stretched", ["compact_panel.png"], backdrop=LIGHT)
    row("button default / hover / pressed @90x22 (32x22 b8 — same insets)",
        ["compact_button_default.png", "compact_button_hover.png", "compact_button_pressed.png"],
        backdrop=LIGHT)
    row("button default @ 48x22 / 220x22 / 90x44 — slice stress",
        ["compact_button_default.png"], sizes=[(48, 22), (220, 22), (90, 44)], backdrop=LIGHT)
    row("field (32x22 b8) stretched", ["compact_field.png"], backdrop=LIGHT)
    row("bar track (48x10 b4) stretched", ["compact_bar_track.png"], backdrop=LIGHT)
    row("bar fill (48x8 b3) stretched — X-uniform centre", ["compact_bar_fill.png"], backdrop=LIGHT)
    trk = by["compact_bar_track.png"][0]
    fil = by["compact_bar_fill.png"][0]
    assembled = []
    for pct in (0.15, 0.55, 1.0):
        bw = 260
        comp = Image.new("RGBA", (bw, 10), (0, 0, 0, 0))
        comp.alpha_composite(nine_slice(trk, 4, bw, 10))
        inner = bw - 2
        full = nine_slice(fil, 3, inner, 8)
        comp.alpha_composite(full.crop((0, 0, max(1, int(inner * pct)), 8)), (1, 1))
        assembled.append(comp)
    sheet.add("assembled progress: track + window-clipped fill (15/55/100%)", assembled, LIGHT)
    row("toggle track off / on (36x18 b8) + knob (16x16)",
        ["compact_toggle_track_off.png", "compact_toggle_track_on.png", "compact_toggle_knob.png"],
        backdrop=LIGHT)
    switches = []
    for st in ("off", "on"):
        comp = Image.new("RGBA", (40, 18), (0, 0, 0, 0))
        comp.alpha_composite(nine_slice(by[f"compact_toggle_track_{st}.png"][0], 8, 40, 18))
        knob = by["compact_toggle_knob.png"][0]
        comp.alpha_composite(knob, (1 if st == "off" else 40 - 17, 1))
        switches.append(comp)
    sheet.add("assembled switch off / on (knob travel is solver-owned)", switches, LIGHT)
    row("stepper plate default / pressed (22x22 b7)",
        ["compact_stepper_plate_default.png", "compact_stepper_plate_pressed.png"], backdrop=LIGHT)
    # 3x zoom strip so a reviewer can judge the hairlines without a loupe
    zoom = []
    for n in ("compact_button_default.png", "compact_button_pressed.png", "compact_field.png"):
        img, border, _ = by[n]
        zoom.append(nine_slice(img, border, 90, 22).resize((270, 66), Image.NEAREST))
    sheet.add("3x nearest zoom — button default / pressed / field (hairline check)", zoom, LIGHT)
    sheet.save(os.path.join(PREVIEW_DIR, "contact-sheet.png"))


if __name__ == "__main__":
    main()
