#!/usr/bin/env python3
"""Sample the PLATE COLOUR of the art that backs a theme package's SELECTED state.

Why this exists (director round 12, 2026-07-26). A theme declares
`extra.controlSelected` — the colour the framework paints for a selected row when
it has no art — and `sheet_model.selectedContentColor` resolves the SELECTED
LABEL's colour by contrast against exactly that number. When the package skins
selection with a picture, the declared colour stops being what a player sees and
the pairing is computed against a fiction: fantasy-ornate declared a burnished
gold `rgb(118, 90, 44)` while `ornate_selection_selected.png` paints a dark
emerald field. No runtime check can see a PNG, so the truth is sampled HERE, at
build time, and the headless sweep (`tests/theme_reference_packages.spec.luau`)
compares the declaration against it.

What is sampled: the alpha-weighted mean of the nine-slice CENTRE rect — the
region that stretches under a label, i.e. the pixels a lifted label is read
against. Whole-image art samples the whole image. The file's sha256 rides with
the sample so a re-cut of the art that was never re-sampled is a FAILING test
rather than a silently stale number.

Run from the Facet root with the repo-root shared venv python:
    ../../../.venv/bin/python tools/sample_plates.py            # write the file
    ../../../.venv/bin/python tools/sample_plates.py --check    # verify, exit 1 on drift
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "assets", "themes", "plate-samples.json")

# (package id, package module, asset directory, { slot -> art asset name }).
#
# `selected` is the asset the package's `chrome.selection` recipe names for its
# `selected` state — the plate a SELECTED label is read against, and the plate
# `extra.controlSelected` claims to be.
# `control` is the asset its `chrome.control` recipe names for `default` — the
# plate a PRIMARY (`surface = "accent"`) label is read against once the skin has
# replaced the accent fill, and the plate `extra.control` claims to be.
#
# The slice rect is parsed out of the module, so this table can never drift from
# the package's own geometry.
TARGETS = [
    (
        "fantasy-ornate",
        "fantasy_ornate",
        "fantasy-ornate",
        {"selected": "ornate_selection_selected", "control": "ornate_button_default"},
    ),
    (
        "glossy-touch",
        "glossy_touch",
        "glossy-touch",
        {"selected": "glossy_selection_selected", "control": "glossy_button_default"},
    ),
    (
        "pixel-quest",
        "pixel_quest",
        "pixel-quest",
        {"selected": "pixel_plate_selected", "control": "pixel_plate_default"},
    ),
    (
        "compact-pointer",
        "compact_pointer",
        "compact-pointer",
        {"selected": "compact_button_hover", "control": "compact_button_default"},
    ),
    (
        "fantasy-parchment",
        "fantasy_parchment",
        "fantasy-parchment",
        {"control": "parchment_button"},
    ),
]


def slice_center(module: str, asset: str):
    """Parse `<asset> = { ... sliceCenter = { x0 =, y0 =, x1 =, y1 = } ... }`."""
    path = os.path.join(ROOT, "examples", "themes", f"{module}.luau")
    with open(path, "r", encoding="utf-8") as fh:
        src = fh.read()
    at = src.find(f"\t{asset} = {{")
    if at < 0:
        raise SystemExit(f"sample_plates: {module}.luau declares no art entry '{asset}'")
    block = src[at : at + 600]
    m = re.search(
        r"sliceCenter = \{ x0 = (\d+), y0 = (\d+), x1 = (\d+), y1 = (\d+) \}", block
    )
    if m is None:
        return None
    return tuple(int(g) for g in m.groups())


def sample(path: str, rect):
    im = Image.open(path).convert("RGBA")
    a = np.asarray(im).astype(np.float64)
    h, w = a.shape[:2]
    if rect is None:
        x0, y0, x1, y1 = 0, 0, w, h
    else:
        x0, y0, x1, y1 = rect
    sub = a[y0:y1, x0:x1]
    if sub.size == 0:
        raise SystemExit(f"sample_plates: empty sample rect {rect} for {path}")
    alpha = sub[..., 3:4] / 255.0
    total = float(alpha.sum())
    if total <= 0:
        raise SystemExit(f"sample_plates: fully transparent sample rect for {path}")
    mean = (sub[..., :3] * alpha).sum(axis=(0, 1)) / total
    return {
        "r": int(round(mean[0])),
        "g": int(round(mean[1])),
        "b": int(round(mean[2])),
        "alpha": round(float(alpha.mean()), 4),
        "size": f"{w}x{h}",
    }


def build():
    out = {
        "schema": "facet-art-plate-samples/1",
        "note": (
            "Alpha-weighted mean of each asset's nine-slice CENTRE rect — the pixels a "
            "lifted label is read against. Regenerate with tools/sample_plates.py "
            "whenever the art is re-cut; tests/theme_reference_packages.spec.luau "
            "re-hashes every file and fails if a sample is stale."
        ),
        "samples": {},
    }
    for pkg, module, folder, slots in TARGETS:
        bySlot = {}
        for slot, asset in slots.items():
            rel = os.path.join("assets", "themes", folder, f"{asset}.png")
            path = os.path.join(ROOT, rel)
            if not os.path.isfile(path):
                raise SystemExit(f"sample_plates: missing {rel}")
            rect = slice_center(module, asset)
            with open(path, "rb") as fh:
                digest = hashlib.sha256(fh.read()).hexdigest()
            entry = sample(path, rect)
            entry["asset"] = asset
            entry["file"] = rel
            entry["sha256"] = digest
            entry["sliceCenter"] = (
                None
                if rect is None
                else {"x0": rect[0], "y0": rect[1], "x1": rect[2], "y1": rect[3]}
            )
            bySlot[slot] = entry
        out["samples"][pkg] = bySlot
    return out


def main():
    built = build()
    text = json.dumps(built, indent=2, sort_keys=True) + "\n"
    if "--check" in sys.argv:
        if not os.path.isfile(OUT):
            print("sample_plates: plate-samples.json is missing", file=sys.stderr)
            return 1
        with open(OUT, "r", encoding="utf-8") as fh:
            if fh.read() != text:
                print("sample_plates: plate-samples.json is STALE", file=sys.stderr)
                return 1
        print("sample_plates: up to date")
        return 0
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(text)
    for pkg, bySlot in sorted(built["samples"].items()):
        for slot, entry in sorted(bySlot.items()):
            print(
                f"{pkg:16s} {slot:9s} {entry['asset']:28s} "
                f"rgb({entry['r']}, {entry['g']}, {entry['b']})  alpha={entry['alpha']}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
