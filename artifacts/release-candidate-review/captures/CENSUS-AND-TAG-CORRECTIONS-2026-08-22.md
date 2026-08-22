# Correction — the ten-foot captures were taken with the sticky-tag defect live

**Written:** 2026-08-22, SCREEN-X fix round. **Applies to:**
`tv_corners_rounded.png`, `tv_corners_zoom_compare.png`,
`tv-paint-final-2026-08-21.png`, `console-tenfoot-2026-08-21.png`.

## What is wrong in the pictures

Every one of these was taken between 2026-08-18 and 2026-08-22, the window in
which `syncTags`' tag-REMOVAL half was dead code (ADR-0038 renamed the tags
`luau-*` -> `facet-*`, the sweep left every hand-counted length behind, and a
five-character `string.sub` against a six-character literal is a constant). A
sliding `Picker` declares every segment `surface = "plain"` so nothing paints
over the indicator behind them — and because a `Button` takes
`facet-surface-control` as its CLASS DEFAULT at create, that declaration is a
tag REMOVAL, which is precisely what could not happen.

So in these captures:

* the **Quality** segmented picker shows three identical opaque plates and **no
  pill**;
* the **icon-segment row** and the **vertical rail** show the same, even though
  `tv-paint-final`'s own caption reads *"Selected: browse — the pill and the rail
  share this one signal"*;
* the **All controls / Settings** tab strip shows two plates and **no
  underline**.

None of that is a ten-foot fact. It is the same defect the `tab-view` demo was
reported for (`artifacts/framework-gaps-phase2/bugAB-red-tabview.png`), showing
up in a frame nobody was looking at it in.

## What is NOT wrong, and why the decision stands

**ADR-0040 row B-17 is unaffected.** Its claim is that the paint family scales at
ten-foot — corner radii 12→18 on `panel` and 8→12 on `control`, hairline strokes
1→1.5 — and the surfaces those numbers are read off (the settings PANEL and the
`–`/`+` stepper CONTROLS) are legitimately `panel`/`control`: their tags are
class defaults that were never asked to be removed, so the additive-only bug
could not touch them. `tv_corners_zoom_compare.png` annotates exactly those two
numbers and both are honest. The row needs no revision.

What the pictures can no longer be used for is **"this is what the ten-foot
screen looks like."** Once the fix lands the pills and the underline appear, so
the frames will differ from what is on disk here.

## What is owed

A re-capture of the console ten-foot view, booked as item 4 of
`docs/handoff/SCREEN-X-OWED-LIVE-WORK.md`. Until then these four images stay as
they are — they are dated evidence and are not edited — and this note travels
beside them.

## The other captures added in the same window are UNAFFECTED

Surveyed one family at a time, against the one question that decides it: *does
the frame contain a node whose classification tag should have been REMOVED?*

| capture(s) | verdict |
|---|---|
| `bugAB-red-tabview.png`, `bugAB-green-tags-removed.png` | **Keep exactly as they are.** They ARE the defect's RED/GREEN evidence pair; the red one is supposed to show it. |
| `bugC-live-closed.png`, `bugC-live-editing.png` | Dated evidence for the table heading-band gutter (a geometry measurement in pixels). Selection and edit-mode chrome sit in frame, so tags may be stale in them, but nothing about the measured 68px gutter is decided by a tag. Not re-captured. |
| `plate_design_A/B/C.png`, `plate_design_options.png`, `plate-b-live-2026-08-21.png` | Expand-plate design options: chips, a plate and a close disc. **No picker, tab strip or selection indicator in frame** — the only visible consequence of a failed removal is a surface plate left under an indicator, and there is no indicator here to hide. The close disc paints its plate and its circle correctly, which is the positive control. Unaffected. |
| `rr-canary-2026-08-22.png` | Rascal Rally results canary, taken for zero-box TEXT nodes — a geometry claim the tag path cannot reach. No indicator chrome in frame and no unexplained plate. Unaffected. |

**The reasoning that decides all of the above, stated once:** the defect was
purely ADDITIVE. The ADD half of `syncTags` always worked, so anything that
should be painted is painted correctly in every capture. Only a node that asked
for a tag to come OFF can be wrong — which is a state change after create, OR a
first mount whose AUTHORED classification differs from the class default
(`surface = "plain"` on a `Button` is the second kind, and is why "static
first-mount capture" is not by itself an argument for safety).
