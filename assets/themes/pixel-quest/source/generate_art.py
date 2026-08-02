#!/usr/bin/env python3
"""Pixel Quest art generator (rich-skinning-v2 stage, ADR-0020 R5 pixel mode).

Original, repository-owned art: every texture below is generated procedurally by
this script from the fixed seed `SEED` — no external imagery, no third-party
assets, no trade dress. Re-running reproduces the PNGs byte-for-byte.

PIXEL DISCIPLINE (the whole point of this set):
  * The art is authored on a hard grid of DESIGN PIXELS and saved at
    `PIXEL_UNIT` (= 4) image px per design pixel, upscaled with NEAREST.
    There is no anti-aliasing anywhere: every PNG contains only flat blocks of
    palette colours, so `ResampleMode = Pixelated` renders it exactly.
  * Every nine-slice source is `2*border + 1` DESIGN pixels on each sliced axis.
    That makes the stretched centre exactly ONE design pixel wide/tall, so any
    target size replicates a single uniform colour — a pixel nine-slice can
    never produce the "sharp but unevenly sized pixels" failure R5 warns about.
  * The slice borders below are therefore always `4 * border_dp`.

Palette: 6 chrome values + two 3-step accent ramps = 12 colours, NES-ish.

Run with the repo-root shared venv python (any CWD works):
  <repo-root>/.venv/bin/python generate_art.py
"""

from __future__ import annotations

import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.dirname(HERE)
PREVIEW_DIR = os.path.join(HERE, "preview")
SEED = 0x8B17  # fixed: determinism is the provenance claim ("8-bit")
PIXEL_UNIT = 4  # image px per design px == the package's identity.pixelUnit

# ── palette ──────────────────────────────────────────────────────────────────
INK = (0x16, 0x12, 0x1F)
SHADE = (0x3A, 0x2C, 0x4F)
WOOD_D = (0x6B, 0x43, 0x26)
WOOD = (0xA8, 0x72, 0x2F)
TAN = (0xD7, 0xA8, 0x60)
CREAM = (0xF4, 0xE6, 0xC0)
RED_D = (0x7A, 0x1F, 0x22)
RED = (0xC8, 0x40, 0x2F)
RED_L = (0xE8, 0x73, 0x5A)
GRN_D = (0x2F, 0x6B, 0x2A)
GRN = (0x4F, 0xA8, 0x3F)
GRN_L = (0x8E, 0xDE, 0x6A)
GLYPH = (0xF0, 0xF0, 0xF0)  # icons are near-white; the theme role supplies tint

PALETTE = {
    "INK": INK, "SHADE": SHADE, "WOOD_D": WOOD_D, "WOOD": WOOD, "TAN": TAN,
    "CREAM": CREAM, "RED_D": RED_D, "RED": RED, "RED_L": RED_L,
    "GRN_D": GRN_D, "GRN": GRN, "GRN_L": GRN_L,
}


# ─────────────────────────────────────────────────────────────────────────────
# Design-pixel canvas. Duplicated per theme on purpose (self-contained folder).
# ─────────────────────────────────────────────────────────────────────────────
class PC:
    """A grid of design pixels. Nothing here can produce a partial alpha."""

    def __init__(self, w: int, h: int):
        self.w, self.h = w, h
        self.px = np.zeros((h, w, 4), dtype=np.uint8)

    def set(self, x: int, y: int, col):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y, x] = (0, 0, 0, 0) if col is None else (*col, 255)

    def rect(self, x0, y0, x1, y1, col):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.set(x, y, col)

    def outline(self, x0, y0, x1, y1, col):
        for x in range(x0, x1 + 1):
            self.set(x, y0, col)
            self.set(x, y1, col)
        for y in range(y0, y1 + 1):
            self.set(x0, y, col)
            self.set(x1, y, col)

    def hline(self, x0, x1, y, col):
        for x in range(x0, x1 + 1):
            self.set(x, y, col)

    def vline(self, x, y0, y1, col):
        for y in range(y0, y1 + 1):
            self.set(x, y, col)

    def bitmap(self, rows, mapping, ox=0, oy=0):
        for y, line in enumerate(rows):
            for x, ch in enumerate(line):
                if ch in mapping:
                    self.set(ox + x, oy + y, mapping[ch])

    def image(self, unit: int = PIXEL_UNIT) -> Image.Image:
        im = Image.fromarray(self.px, "RGBA")
        return im.resize((self.w * unit, self.h * unit), Image.NEAREST)


def dilate(rows, ch="#"):
    """Return the 1-cell ring around the cells marked `ch` (for INK outlines)."""
    h, w = len(rows), len(rows[0])
    out = set()
    for y in range(h):
        for x in range(w):
            if rows[y][x] != ch:
                continue
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and rows[ny][nx] != ch:
                        out.add((nx, ny))
    return out


def nine_slice(img: Image.Image, border: int, w: int, h: int) -> Image.Image:
    """Reference nine-slice render, NEAREST (matches Pixelated + SliceScale 1)."""
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
        dst.alpha_composite(img.crop(box).resize(size, Image.NEAREST), pos)
    return dst


def checker(w, h, s=8, a=(56, 56, 62), b=(42, 42, 48)) -> Image.Image:
    im = Image.new("RGB", (w, h), a)
    d = ImageDraw.Draw(im)
    for y in range(0, h, s):
        for x in range(0, w, s):
            if ((x // s) + (y // s)) % 2:
                d.rectangle([x, y, x + s - 1, y + s - 1], fill=b)
    return im


class Sheet:
    def __init__(self, title: str, width: int = 1500):
        self.title, self.width, self.rows = title, width, []

    def add(self, label, images, backdrop=None):
        self.rows.append((label, list(images), backdrop))

    def save(self, path: str):
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
# Assets — every sliced source is 2*b+1 design px on each sliced axis.
# ─────────────────────────────────────────────────────────────────────────────
def plate(state: str) -> PC:
    """9x9 dp (36x36 px), slice border 4 dp (16 px). Menu/button plate."""
    p = PC(9, 9)
    if state == "default":
        p.rect(0, 0, 8, 8, WOOD)              # face
        p.outline(0, 0, 8, 8, INK)            # hard outline
        p.hline(1, 7, 1, TAN)                 # lit top / left bevel
        p.vline(1, 1, 7, TAN)
        p.hline(1, 7, 7, WOOD_D)              # shaded bottom / right bevel
        p.vline(7, 1, 7, WOOD_D)
        for rx, ry in ((2, 2), (6, 2), (2, 6), (6, 6)):
            p.set(rx, ry, TAN)                # corner rivets (inside the corners)
    else:  # selected — a DIFFERENT construction, not a tint
        p.rect(0, 0, 8, 8, TAN)               # light gilt face
        p.outline(0, 0, 8, 8, INK)
        p.outline(1, 1, 7, 7, CREAM)          # second, brighter frame ring
        p.hline(2, 6, 2, CREAM)
        p.vline(2, 2, 6, CREAM)
        p.hline(2, 6, 6, WOOD)
        p.vline(6, 2, 6, WOOD)
        for rx, ry in ((2, 2), (6, 2), (2, 6), (6, 6)):
            p.set(rx, ry, RED)                # ruby studs
        for cx, cy in ((0, 0), (8, 0), (0, 8), (8, 8)):
            p.set(cx, cy, None)               # chamfered (notched) corners
    return p


def plate_ornament() -> PC:
    """6x6 dp (24x24 px) whole image — the selected plate's side/corner jewel."""
    p = PC(6, 6)
    rows = [
        "..##..",
        ".#LL#.",
        "#LRRL#",
        "#RRRD#",
        ".#DD#.",
        "..##..",
    ]
    p.bitmap(rows, {"#": INK, "L": RED_L, "R": RED, "D": RED_D})
    return p


def blank() -> PC:
    """6x6 dp (24x24 px) of nothing at all — deliberately, entirely transparent.

    The per-state asset grammar requires a `default`, so a layer that must paint
    ONLY in one state (the selected plate's jewels) needs something to name in
    the others. This is that something: the package's explicit way of saying "no
    ornament here", rather than an ornament dimmed by a tint and hoped over.
    """
    return PC(6, 6)


def panel() -> PC:
    """13x13 dp (52x52 px), slice border 6 dp (24 px). Window chrome."""
    p = PC(13, 13)
    p.rect(0, 0, 12, 12, SHADE)
    p.outline(0, 0, 12, 12, INK)
    p.outline(1, 1, 11, 11, TAN)
    p.outline(2, 2, 10, 10, WOOD)
    p.outline(3, 3, 9, 9, WOOD_D)
    p.outline(4, 4, 8, 8, INK)
    p.rect(5, 5, 7, 7, SHADE)
    for rx, ry in ((2, 2), (10, 2), (2, 10), (10, 10)):
        p.set(rx, ry, CREAM)                  # corner rivets
    return p


def field() -> PC:
    """9x9 dp (36x36 px), slice border 4 dp (16 px). Inset text well."""
    p = PC(9, 9)
    p.rect(0, 0, 8, 8, SHADE)
    p.outline(0, 0, 8, 8, INK)
    p.hline(1, 7, 1, WOOD_D)                  # inset: dark on the lit side
    p.vline(1, 1, 7, WOOD_D)
    p.hline(1, 7, 7, TAN)
    p.vline(7, 1, 7, TAN)
    p.rect(2, 2, 6, 6, SHADE)
    return p


def bar_track() -> PC:
    """5x8 dp (20x32 px), slice border 2 dp (8 px). Carved HP rail."""
    p = PC(5, 8)
    rowcols = [INK, WOOD_D, SHADE, SHADE, SHADE, SHADE, TAN, INK]
    for y, col in enumerate(rowcols):
        p.hline(0, 4, y, col)
    p.vline(0, 0, 7, INK)
    p.vline(4, 0, 7, INK)
    return p


def bar_fill() -> PC:
    """3x4 dp (12x16 px), slice border 1 dp (4 px). Full-width HP fill.

    Uniform along X by construction, so any reveal percent looks identical.
    """
    p = PC(3, 4)
    for y, col in enumerate([RED_L, RED, RED, RED_D]):
        p.hline(0, 2, y, col)
    return p


def bar_cap_heart() -> PC:
    """10x10 dp (40x40 px) whole image — the HP bar's heart end-cap."""
    body = [
        "..........",
        "..##..##..",
        ".########.",
        ".########.",
        ".########.",
        "..######..",
        "...####...",
        "....##....",
        "..........",
        "..........",
    ]
    p = PC(10, 10)
    for x, y in dilate(body):
        p.set(x, y, INK)
    for y, line in enumerate(body):
        for x, ch in enumerate(line):
            if ch != "#":
                continue
            col = RED
            if y <= 2:
                col = RED_L
            elif y >= 6:
                col = RED_D
            p.set(x, y, col)
    p.set(2, 2, CREAM)                        # specular pip
    p.set(3, 2, CREAM)
    return p


def toggle_track(state: str) -> PC:
    """7x8 dp (28x32 px), slice border 3 dp (12 px)."""
    p = PC(7, 8)
    if state == "on":
        rows = [INK, GRN_L, GRN, GRN, GRN, GRN, GRN_D, INK]
    else:
        rows = [INK, INK, SHADE, SHADE, SHADE, SHADE, WOOD_D, INK]
    for y, col in enumerate(rows):
        p.hline(0, 6, y, col)
    p.vline(0, 0, 7, INK)
    p.vline(6, 0, 7, INK)
    for cx, cy in ((0, 0), (6, 0), (0, 7), (6, 7)):
        p.set(cx, cy, None)                   # chamfer
    return p


def toggle_knob() -> PC:
    """6x6 dp (24x24 px) whole image."""
    p = PC(6, 6)
    p.rect(0, 0, 5, 5, CREAM)
    p.outline(0, 0, 5, 5, INK)
    p.hline(1, 4, 4, TAN)
    p.vline(4, 1, 4, TAN)
    p.set(1, 1, CREAM)
    for cx, cy in ((0, 0), (5, 0), (0, 5), (5, 5)):
        p.set(cx, cy, None)
    return p


def stepper_plate(state: str) -> PC:
    """7x7 dp (28x28 px), slice border 3 dp (12 px)."""
    p = PC(7, 7)
    if state == "default":
        p.rect(0, 0, 6, 6, WOOD)
        p.outline(0, 0, 6, 6, INK)
        p.hline(1, 5, 1, TAN)
        p.vline(1, 1, 5, TAN)
        p.hline(1, 5, 5, WOOD_D)
        p.vline(5, 1, 5, WOOD_D)
        p.rect(2, 2, 4, 4, WOOD)
    else:
        p.rect(0, 0, 6, 6, WOOD_D)
        p.outline(0, 0, 6, 6, INK)
        p.hline(1, 5, 1, SHADE)               # inverted bevel = pressed
        p.vline(1, 1, 5, SHADE)
        p.hline(1, 5, 5, WOOD)
        p.vline(5, 1, 5, WOOD)
        p.rect(2, 2, 4, 4, WOOD_D)
    return p


ICON_BITMAPS = {
    "chevron_right": [
        ".##.....",
        "..##....",
        "...##...",
        "....##..",
        "....##..",
        "...##...",
        "..##....",
        ".##.....",
    ],
    "chevron_down": [
        "........",
        "#......#",
        "##....##",
        ".##..##.",
        "..####..",
        "...##...",
        "........",
        "........",
    ],
    "plus": [
        "........",
        "...##...",
        "...##...",
        ".######.",
        ".######.",
        "...##...",
        "...##...",
        "........",
    ],
    "minus": [
        "........",
        "........",
        "........",
        ".######.",
        ".######.",
        "........",
        "........",
        "........",
    ],
    "check": [
        "........",
        "......##",
        ".....##.",
        "#...##..",
        "##.##...",
        ".####...",
        "..##....",
        "........",
    ],
    "cross": [
        "##....##",
        ".##..##.",
        "..####..",
        "...##...",
        "...##...",
        "..####..",
        ".##..##.",
        "##....##",
    ],
}


def icon(name: str) -> PC:
    """8x8 dp (32x32 px) near-white glyph on transparency (R4 tints by role)."""
    p = PC(8, 8)
    p.bitmap(ICON_BITMAPS[name], {"#": GLYPH})
    return p


# ─────────────────────────────────────────────────────────────────────────────
def main() -> None:
    np.random.default_rng(SEED)  # seed is recorded even though the art is exact
    u = PIXEL_UNIT
    items = []  # (filename, PIL image, slice border px, preview sizes)

    items.append(("pixel_plate_default.png", plate("default").image(), 4 * u,
                  [(160, 48), (240, 48), (128, 96)]))
    items.append(("pixel_plate_selected.png", plate("selected").image(), 4 * u,
                  [(160, 48), (240, 48), (128, 96)]))
    items.append(("pixel_plate_ornament.png", plate_ornament().image(), None, None))
    items.append(("pixel_blank.png", blank().image(), None, None))
    items.append(("pixel_panel.png", panel().image(), 6 * u, [(160, 120), (280, 176), (400, 128)]))
    items.append(("pixel_field.png", field().image(), 4 * u, [(160, 48), (280, 48), (128, 96)]))
    items.append(("pixel_bar_track.png", bar_track().image(), 2 * u, [(120, 32), (240, 32), (360, 32)]))
    items.append(("pixel_bar_fill.png", bar_fill().image(), 1 * u, [(48, 16), (160, 16), (320, 16)]))
    items.append(("pixel_bar_cap_heart.png", bar_cap_heart().image(), None, None))
    items.append(("pixel_toggle_track_off.png", toggle_track("off").image(), 3 * u, [(64, 32), (96, 32)]))
    items.append(("pixel_toggle_track_on.png", toggle_track("on").image(), 3 * u, [(64, 32), (96, 32)]))
    items.append(("pixel_toggle_knob.png", toggle_knob().image(), None, None))
    items.append(("pixel_stepper_plate_default.png", stepper_plate("default").image(), 3 * u, [(32, 32), (48, 32)]))
    items.append(("pixel_stepper_plate_pressed.png", stepper_plate("pressed").image(), 3 * u, [(32, 32), (48, 32)]))
    for nm in ("chevron_right", "chevron_down", "plus", "minus", "check", "cross"):
        items.append((f"pixel_icon_{nm}.png", icon(nm).image(), None, None))

    for name, img, border, _ in items:
        path = os.path.join(OUT_DIR, name)
        img.save(path, optimize=True)
        b = f"slice {border}" if border else "whole image"
        print(f"wrote {path}  ({img.width}x{img.height}, {b})")

    # ── contact sheet ────────────────────────────────────────────────────────
    sheet = Sheet("pixel-quest — pixelUnit 4, nine-slice stretch test (NEAREST everywhere)")
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

    row("plate default @160x48 / 240x48 / 128x96 (36x36 b16)", ["pixel_plate_default.png"])
    row("plate SELECTED — different construction, same 4dp insets", ["pixel_plate_selected.png"])
    # selected plate with the ornament anchored at all four corners (a `corners` layer)
    orn = by["pixel_plate_ornament.png"][0]
    comp = Image.new("RGBA", (240, 48), (0, 0, 0, 0))
    comp.alpha_composite(nine_slice(by["pixel_plate_selected.png"][0], 16, 240, 48))
    for px, py in ((-4, -4), (240 - 20, -4), (-4, 48 - 20), (240 - 20, 48 - 20)):
        comp.alpha_composite(orn, (px, py))
    sheet.add("selected plate + ornament as a `corners` layer (240x48)", [comp])
    row("panel (52x52 b24) stretched", ["pixel_panel.png"])
    row("field (36x36 b16) stretched", ["pixel_field.png"])
    row("bar track (20x32 b8) stretched", ["pixel_bar_track.png"])
    row("bar fill (12x16 b4) stretched — uniform along X", ["pixel_bar_fill.png"])
    trk = by["pixel_bar_track.png"][0]
    fil = by["pixel_bar_fill.png"][0]
    heart = by["pixel_bar_cap_heart.png"][0]
    assembled = []
    for pct in (0.12, 0.5, 1.0):
        bw, bh = 320, 40
        c = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
        c.alpha_composite(nine_slice(trk, 8, bw - 40, 32), (36, 4))
        inner = bw - 40 - 16
        full = nine_slice(fil, 4, inner, 16)
        c.alpha_composite(full.crop((0, 0, max(4, int(inner * pct) // 4 * 4), 16)), (44, 12))
        c.alpha_composite(heart, (0, 0))
        assembled.append(c)
    sheet.add("assembled HP bar: heart cap + track + window-clipped fill (12/50/100%)", assembled)
    row("toggle track off / on (28x32 b12) + knob (24x24)",
        ["pixel_toggle_track_off.png", "pixel_toggle_track_on.png", "pixel_toggle_knob.png"])
    row("stepper plate default / pressed (28x28 b12)",
        ["pixel_stepper_plate_default.png", "pixel_stepper_plate_pressed.png"])
    sheet.add("icons 32x32 near-white (chevron_right/down, plus, minus, check, cross)",
              [by[f"pixel_icon_{n}.png"][0] for n in
               ("chevron_right", "chevron_down", "plus", "minus", "check", "cross")])
    # palette strip
    strip = Image.new("RGBA", (len(PALETTE) * 40, 40), (0, 0, 0, 255))
    dstrip = ImageDraw.Draw(strip)
    for i, (_, col) in enumerate(PALETTE.items()):
        dstrip.rectangle([i * 40, 0, i * 40 + 39, 39], fill=(*col, 255))
    sheet.add("palette: INK SHADE WOOD_D WOOD TAN CREAM | RED_D RED RED_L | GRN_D GRN GRN_L", [strip])
    sheet.save(os.path.join(PREVIEW_DIR, "contact-sheet.png"))


if __name__ == "__main__":
    main()
