#!/usr/bin/env python3
"""Fantasy Parchment nine-slice art generator (theme-packages-and-skinning stage).

Original, repository-owned art: every texture is generated procedurally by this
script from a fixed seed — no external imagery, no third-party assets, no trade
dress. Re-running the script reproduces the PNGs byte-for-byte on the same
Pillow/numpy versions (recorded in provenance.md), which is the package's
source-art provenance story.

Outputs (into the parent directory):
  parchment_panel.png   144x144, nine-slice borders 40px  — raised panels/modals
  parchment_button.png   72x72,  nine-slice borders 24px  — control chrome
  parchment_field.png    72x72,  nine-slice borders 24px  — text-field chrome (inset look)

Slice geometry is part of the theme package (SliceCenter = Rect(border, border,
size-border, size-border)); keep these numbers in sync with the package data.

Run with the repo-root shared venv python (any CWD works):
  <repo-root>/.venv/bin/python generate_art.py
"""

from __future__ import annotations

import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED = 0x5EED  # fixed: determinism is the provenance claim

# Palette (0..255 RGB) — warm aged paper over iron-gall ink.
PARCHMENT_LIGHT = np.array([233, 218, 183], dtype=np.float64)
PARCHMENT_DARK = np.array([196, 172, 128], dtype=np.float64)
EDGE_BROWN = np.array([124, 96, 58], dtype=np.float64)
INK = np.array([62, 48, 34], dtype=np.float64)


def _fbm_noise(rng: np.random.Generator, size: int, octaves: int = 4) -> np.ndarray:
    """Fractal value noise in [0,1]: upsampled random grids summed by octave."""
    acc = np.zeros((size, size), dtype=np.float64)
    amp, total = 1.0, 0.0
    for octave in range(octaves):
        cells = 4 * (2**octave)
        grid = rng.random((cells, cells))
        img = Image.fromarray((grid * 255).astype(np.uint8), "L").resize(
            (size, size), Image.BICUBIC
        )
        acc += amp * (np.asarray(img, dtype=np.float64) / 255.0)
        total += amp
        amp *= 0.55
    return acc / total


def _parchment_base(rng: np.random.Generator, size: int) -> np.ndarray:
    """Mottled parchment sheet with fibers and faint stains. Returns HxWx3 float."""
    noise = _fbm_noise(rng, size, octaves=5)
    sheet = PARCHMENT_LIGHT[None, None, :] * (1 - noise[..., None]) + PARCHMENT_DARK[
        None, None, :
    ] * noise[..., None]

    # horizontal fiber streaks: low-frequency per-row wobble
    rows = _fbm_noise(rng, size, octaves=2)[:, : size // 8].mean(axis=1)
    sheet += (rows[:, None, None] - 0.5) * 14.0

    # a few translucent stains
    stain_layer = Image.new("L", (size, size), 0)
    sd = ImageDraw.Draw(stain_layer)
    for _ in range(4):
        cx, cy = rng.integers(0, size, 2)
        r = int(size * (0.10 + 0.12 * rng.random()))
        sd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=int(28 + 30 * rng.random()))
    stain = np.asarray(
        stain_layer.filter(ImageFilter.GaussianBlur(size * 0.06)), dtype=np.float64
    )[..., None] / 255.0
    sheet = sheet * (1 - stain) + (sheet * 0.82 + EDGE_BROWN * 0.18) * stain
    return sheet


def _deckle_mask(rng: np.random.Generator, size: int, margin: float) -> np.ndarray:
    """Alpha mask with a slightly irregular (deckled) edge inside `margin` px."""
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    steps = 64
    pts = []
    for i in range(steps * 4):
        t = i / (steps * 4)
        # walk the rectangle perimeter, jittering inward
        per = t * 4
        jitter = margin * (0.25 + 0.75 * rng.random())
        if per < 1:
            x, y = per * size, jitter
        elif per < 2:
            x, y = size - jitter, (per - 1) * size
        elif per < 3:
            x, y = size - (per - 2) * size, size - jitter
        else:
            x, y = jitter, size - (per - 3) * size
        pts.append((x, y))
    d.polygon(pts, fill=255)
    return np.asarray(
        mask.filter(ImageFilter.GaussianBlur(margin * 0.35)), dtype=np.float64
    ) / 255.0


def _edge_shade(size: int, border: int, strength: float) -> np.ndarray:
    """Darkening ramp toward the edges (0 center .. 1 at rim), border-band only."""
    yy, xx = np.mgrid[0:size, 0:size]
    dist = np.minimum(np.minimum(xx, size - 1 - xx), np.minimum(yy, size - 1 - yy))
    ramp = np.clip(1.0 - dist / border, 0.0, 1.0) ** 1.6
    return ramp * strength


def _compose(
    seed_key: int,
    size: int,
    border: int,
    deckle_px: float,
    kind: str,  # "panel" | "button" | "field"
) -> Image.Image:
    rng = np.random.default_rng(SEED + seed_key)
    sheet = _parchment_base(rng, size)

    if kind == "button":
        # a pressable slab: warm the paper toward tanned leather so a 46px-tall
        # button reads as a control, not a scrap of the panel behind it
        sheet = sheet * 0.86 + np.array([172, 132, 82], dtype=np.float64)[None, None, :] * 0.14
    elif kind == "field":
        # writing surface: lighter interior with a letterpress well
        sheet = np.minimum(sheet * 1.06 + 8.0, 255.0)
        yy, xx = np.mgrid[0:size, 0:size]
        dist = np.minimum(np.minimum(xx, size - 1 - xx), np.minimum(yy, size - 1 - yy))
        well = np.clip(1.0 - dist / border, 0.0, 1.0) ** 1.2 * 0.16
        sheet = sheet * (1 - well[..., None]) + PARCHMENT_DARK[None, None, :] * well[..., None]

    shade = _edge_shade(size, border, strength=0.55 if kind == "panel" else 0.30)
    sheet = sheet * (1 - shade[..., None]) + EDGE_BROWN[None, None, :] * shade[..., None]

    # ink border: double rule on panels (a framed page), single heavier rule on
    # controls (read at 46px), thin rule on fields
    line = Image.new("L", (size, size), 0)
    ld = ImageDraw.Draw(line)
    off = int(deckle_px + border * 0.28)
    if kind == "button":
        w = max(3, size // 20)
        ld.rectangle([off, off, size - 1 - off, size - 1 - off], outline=255, width=w)
    elif kind == "field":
        w = max(1, size // 40)
        ld.rectangle([off, off, size - 1 - off, size - 1 - off], outline=210, width=w)
    else:
        w = max(2, size // 48)
        ld.rectangle([off, off, size - 1 - off, size - 1 - off], outline=255, width=w)
        off2 = off + w + max(1, w // 2)
        ld.rectangle(
            [off2, off2, size - 1 - off2, size - 1 - off2], outline=140, width=max(1, w // 2)
        )
    line_arr = np.asarray(line.filter(ImageFilter.GaussianBlur(0.7)), dtype=np.float64)[..., None] / 255.0
    # ink sits unevenly: modulate by noise so the rule looks drawn, not vector
    line_arr *= (0.65 + 0.35 * _fbm_noise(rng, size, octaves=3))[..., None]
    sheet = sheet * (1 - 0.85 * line_arr) + INK[None, None, :] * (0.85 * line_arr)

    alpha = _deckle_mask(rng, size, deckle_px) * 255.0
    rgba = np.dstack([np.clip(sheet, 0, 255), alpha]).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def _slider_track(rng: np.random.Generator) -> Image.Image:
    """A thin parchment rail with a carved groove line. 96x20, nine-slice
    border 8 — sliced horizontally along the track length."""
    w, h = 96, 20
    sheet = _parchment_base(rng, 96)[:h, :, :]
    shade = np.clip(1.0 - np.minimum(np.mgrid[0:h, 0:w][0], h - 1 - np.mgrid[0:h, 0:w][0]) / 7.0, 0, 1) ** 1.4
    sheet = sheet * (1 - (shade * 0.5)[..., None]) + EDGE_BROWN[None, None, :] * (shade * 0.5)[..., None]
    # the groove: a dark carved line along the middle
    groove = Image.new("L", (w, h), 0)
    gd = ImageDraw.Draw(groove)
    gd.line([(4, h // 2), (w - 4, h // 2)], fill=230, width=3)
    g = np.asarray(groove.filter(ImageFilter.GaussianBlur(0.8)), dtype=np.float64)[..., None] / 255.0
    sheet = sheet * (1 - 0.8 * g) + INK[None, None, :] * (0.8 * g)
    alpha = np.full((h, w), 255.0)
    # soften the rail's end caps slightly
    for x in range(3):
        alpha[:, x] *= (x + 1) / 4
        alpha[:, w - 1 - x] *= (x + 1) / 4
    return Image.fromarray(np.dstack([np.clip(sheet, 0, 255), alpha]).astype(np.uint8), "RGBA")


def _slider_thumb(rng: np.random.Generator) -> Image.Image:
    """A round wax-seal thumb, 28x28, drawn whole (no nine-slice)."""
    s = 28
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # wax body: deep red-brown with an irregular rim
    d.ellipse([1, 1, s - 2, s - 2], fill=(126, 42, 34, 255))
    d.ellipse([3, 3, s - 4, s - 4], fill=(150, 52, 40, 255))
    # pressed-seal ring + highlight
    d.ellipse([7, 7, s - 8, s - 8], outline=(96, 30, 24, 255), width=2)
    d.ellipse([9, 8, 15, 12], fill=(196, 96, 80, 190))
    noise = _fbm_noise(rng, s, octaves=3)
    arr = np.asarray(img, dtype=np.float64)
    arr[..., :3] *= (0.9 + 0.2 * noise)[..., None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def _badge_seal(rng: np.random.Generator) -> Image.Image:
    """A small round parchment seal for badges/counters, 28x28, drawn whole."""
    s = 28
    sheet = _parchment_base(rng, 32)[:s, :s, :]
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, s - 1, s - 1], fill=255)
    ring = Image.new("L", (s, s), 0)
    ImageDraw.Draw(ring).ellipse([1, 1, s - 2, s - 2], outline=255, width=2)
    r = np.asarray(ring.filter(ImageFilter.GaussianBlur(0.5)), dtype=np.float64)[..., None] / 255.0
    sheet = sheet * (1 - 0.85 * r) + INK[None, None, :] * (0.85 * r)
    alpha = np.asarray(mask, dtype=np.float64)
    return Image.fromarray(np.dstack([np.clip(sheet, 0, 255), alpha]).astype(np.uint8), "RGBA")


def main() -> None:
    # Control borders are 16px so both borders (32px) fit inside a 46px-tall
    # button/field without slice overlap at SliceScale 1.
    specs = [
        ("parchment_panel.png", 1, 144, 40, 7.0, "panel"),
        ("parchment_button.png", 2, 64, 16, 2.5, "button"),
        ("parchment_field.png", 3, 64, 16, 2.0, "field"),
    ]
    for name, key, size, border, deckle, kind in specs:
        img = _compose(key, size, border, deckle, kind)
        path = os.path.join(OUT_DIR, name)
        img.save(path, optimize=True)
        print(f"wrote {path}  ({size}x{size}, slice border {border}px)")
    # value-control chrome (director review 2026-07-25: "just changing the
    # color isn't enough" — the slider rail and thumb are art, like the RPG
    # reference kits). The badge seal keeps counters readable ON the art.
    extras = [
        ("parchment_slider_track.png", 4, _slider_track, "96x20, slice border 8 (horizontal rail)"),
        ("parchment_slider_thumb.png", 5, _slider_thumb, "28x28 whole image (wax-seal knob)"),
        ("parchment_badge.png", 6, _badge_seal, "28x28 whole image (counter seal)"),
    ]
    for name, key, fn, desc in extras:
        rng = np.random.default_rng(SEED + key)
        path = os.path.join(OUT_DIR, name)
        fn(rng).save(path, optimize=True)
        print(f"wrote {path}  ({desc})")


if __name__ == "__main__":
    main()
