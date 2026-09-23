#!/usr/bin/env python3


from __future__ import annotations

import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.dirname(HERE)
PREVIEW_DIR = os.path.join(HERE, "preview")
SEED = 0x9A17






SS = 4


def _f(im: Image.Image) -> np.ndarray:
    return np.clip(np.asarray(im, dtype=np.float64) / 255.0, 0.0, 1.0)


def _u8(a: np.ndarray) -> np.ndarray:
    return np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8)


def rgb(r: int, g: int, b: int) -> np.ndarray:
    return np.array([r, g, b], dtype=np.float64) / 255.0


class Mask:


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

    def ellipse(self, box, fill=255):
        self.d.ellipse(self._s(box), fill=fill)

    def poly(self, pts, fill=255):
        self.d.polygon([(x * self.ss, y * self.ss) for x, y in pts], fill=fill)

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


class Canvas:


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







IRON_D = rgb(0x14, 0x11, 0x0E)
IRON = rgb(0x2A, 0x24, 0x1D)
IRON_L = rgb(0x46, 0x3C, 0x2F)
BRASS_D = rgb(0x6B, 0x4E, 0x1C)
BRASS = rgb(0xC0, 0x94, 0x3A)
BRASS_L = rgb(0xF0, 0xD3, 0x8B)
RUBY_D = rgb(0x66, 0x14, 0x1C)
RUBY = rgb(0xC8, 0x2E, 0x3A)
RUBY_L = rgb(0xFF, 0x9A, 0x9A)

FACE_W, FACE_H = 64, 64
NEEDLE_W, NEEDLE_H = 24, 64
CAP_W, CAP_H = 28, 64


def face() -> Image.Image:

    w, h = FACE_W, FACE_H
    col = np.zeros((h, 3), dtype=np.float64)

    def band(y0: int, y1: int, top, bottom=None):
        bottom = top if bottom is None else bottom
        n = y1 - y0 + 1
        for i in range(n):
            t = 0.0 if n == 1 else i / (n - 1)
            col[y0 + i] = np.asarray(top) * (1 - t) + np.asarray(bottom) * t

    band(0, 1, IRON_D)
    band(2, 4, IRON_L, IRON)
    band(5, 8, BRASS_L, BRASS_D)
    band(9, 11, IRON, IRON_D * 0.9)
    band(12, 13, IRON_D * 0.45)
    band(14, h - 15, IRON_D * 0.55, IRON * 0.85)
    band(h - 14, h - 13, BRASS_D * 0.75)
    band(h - 12, h - 10, IRON_D * 0.9, IRON)
    band(h - 9, h - 6, BRASS, BRASS_D)
    band(h - 5, h - 3, IRON, IRON_L * 0.7)
    band(h - 2, h - 1, IRON_D)

    c = Canvas(w, h)
    c.paint(np.repeat(col[:, None, :], w, axis=1), np.ones((h, w)))
    return c.image()


def needle() -> Image.Image:

    w, h = NEEDLE_W, NEEDLE_H
    c = Canvas(w, h)
    cx = w / 2.0

    blade_pts = [(cx, 2), (cx + 6, h * 0.5), (cx, h - 3), (cx - 6, h * 0.5)]
    outline = Mask(w, h)
    outline.poly([(x, y) for x, y in [(cx, 0), (cx + 8, h * 0.5), (cx, h - 1), (cx - 8, h * 0.5)]])
    c.paint(IRON_D, outline.arr())

    blade = Mask(w, h)
    blade.poly(blade_pts)
    b = blade.arr()
    c.paint(vgrad(w, h, [(0.0, BRASS_L), (0.35, BRASS), (0.65, BRASS_D), (1.0, BRASS)]), b)
    bhi, blo = emboss(b, blur_r=0.8, dist=1)
    c.paint(BRASS_L, bhi * 0.7)
    c.paint(IRON_D, blo * 0.55)


    spine = Mask(w, h)
    spine.rect([cx - 1, 6, cx, h - 7])
    c.paint(BRASS_L, spine.arr() * 0.85)


    ring = Mask(w, h)
    ring.ellipse([cx - 7, h * 0.5 - 7, cx + 6, h * 0.5 + 6])
    c.paint(BRASS_D, ring.arr())
    jewel = Mask(w, h)
    jewel.ellipse([cx - 5, h * 0.5 - 5, cx + 4, h * 0.5 + 4])
    j = jewel.arr()
    c.paint(RUBY_D, j)
    inner = Mask(w, h)
    inner.ellipse([cx - 4, h * 0.5 - 4, cx + 3, h * 0.5 + 3])
    c.paint(RUBY, inner.arr())
    glint = Mask(w, h)
    glint.ellipse([cx - 3, h * 0.5 - 4, cx - 1, h * 0.5 - 2])
    c.paint(RUBY_L, glint.arr() * 0.9)

    return c.image()


def endcap() -> Image.Image:

    w, h = CAP_W, CAP_H
    c = Canvas(w, h)
    cx = w / 2.0

    body = Mask(w, h)
    body.rrect([1, 2, w - 2, h - 3], 6)
    bd = body.arr()
    c.paint(vgrad(w, h, [(0.0, BRASS_L), (0.22, BRASS), (0.6, BRASS_D), (1.0, BRASS * 0.8)]), bd)
    hi, lo = emboss(bd, blur_r=1.0, dist=2)
    c.paint(BRASS_L, hi * 0.75)
    c.paint(IRON_D, lo * 0.7)


    for dx in (-6, 6):
        flute = Mask(w, h)
        flute.rrect([cx + dx - 1, 10, cx + dx + 1, h - 11], 1)
        f = flute.arr()
        c.paint(IRON_D, f * 0.55)
        c.paint(BRASS_L, shift(f, 1, 0) * 0.35)


    boss = Mask(w, h)
    boss.ellipse([cx - 5, h * 0.5 - 5, cx + 4, h * 0.5 + 4])
    c.paint(IRON, boss.arr())
    boss_in = Mask(w, h)
    boss_in.ellipse([cx - 4, h * 0.5 - 4, cx + 3, h * 0.5 + 3])
    c.paint(BRASS, boss_in.arr())
    for y in (12, h - 13):
        rivet = Mask(w, h)
        rivet.ellipse([cx - 2, y - 2, cx + 1, y + 1])
        r = rivet.arr()
        c.paint(BRASS_L, r)
        c.paint(IRON_D, shift(r, 0, 1) * 0.5)

    return c.image()


def contact_sheet(images: dict) -> Image.Image:

    rows = [(320, 0.08), (520, 0.5), (760, 0.94)]
    pad, gap = 24, 20
    dial_h = 56
    w = pad * 2 + max(r[0] for r in rows)
    h = pad * 2 + len(rows) * (dial_h + gap)

    sheet = Image.new("RGB", (w, h), (34, 32, 38))
    d = ImageDraw.Draw(sheet)
    for y in range(0, h, 16):
        for x in range(0, w, 16):
            if ((x // 16) + (y // 16)) % 2:
                d.rectangle([x, y, x + 15, y + 15], fill=(41, 39, 46))

    face_im, needle_im, cap_im = images["face"], images["needle"], images["endcap"]
    y = pad
    for width, frac in rows:
        dial = Image.new("RGBA", (width, dial_h), (0, 0, 0, 0))
        dial.alpha_composite(face_im.resize((width, dial_h), Image.BILINEAR), (0, 0))
        cap = cap_im.resize((CAP_W, dial_h), Image.BILINEAR)
        dial.alpha_composite(cap, (0, 0))
        dial.alpha_composite(cap, (width - CAP_W, 0))
        nw = NEEDLE_W
        travel = width - 2 * CAP_W - nw
        nx = CAP_W + int(round(travel * frac))
        dial.alpha_composite(needle_im.resize((nw, dial_h), Image.BILINEAR), (nx, 0))
        sheet.paste(dial, (pad, y), dial)
        y += dial_h + gap
    return sheet


def main() -> None:
    np.random.default_rng(SEED)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    images = {"face": face(), "needle": needle(), "endcap": endcap()}
    for name, im in images.items():
        path = os.path.join(OUT_DIR, f"gauge_{name}.png")
        im.save(path, "PNG", optimize=True)
        print(f"wrote {path} ({im.size[0]}x{im.size[1]})")
    sheet = contact_sheet(images)
    sheet_path = os.path.join(PREVIEW_DIR, "contact-sheet.png")
    sheet.save(sheet_path, "PNG", optimize=True)
    print(f"wrote {sheet_path} ({sheet.size[0]}x{sheet.size[1]})")



    arr = np.asarray(images["face"])
    assert np.array_equal(arr[:, :1, :].repeat(arr.shape[1], axis=1), arr), (
        "gauge_face.png is not horizontally invariant — a stretch would distort it"
    )
    print("invariant: gauge_face.png is column-identical, so a horizontal stretch is lossless")


if __name__ == "__main__":
    main()
