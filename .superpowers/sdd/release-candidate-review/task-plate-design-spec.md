# Region-expand plate — visual redesign spec (UI-SPEC gate, round 3)

**Role:** UI Designer.  **Scope:** the expanded plate of Facet's region-expand feature
(`src/region_expand.luau` + the panel built in `src/blueprint.luau` `panelOf`/`sheetOf`).
**Status:** three options for director choice.  **Settled mid-flight (director ruling
2026-08-21): the close position is upper-right** — no left-vs-right choice is presented;
options differ only on how the close *integrates* so the plate carries no dead band.

Mockups (phone 360x691 @2x, dark theme, live scrim):
- `plate_design_A.png`, `plate_design_B.png`, `plate_design_C.png`, side-by-side
  `plate_design_options.png` (includes the current rejected state for contrast) — all in
  the session scratchpad
  (`/private/tmp/claude-501/-Users-josha-Library-CloudStorage-Dropbox-Documents-UntitledRacingGame/813f367f-0195-4e4c-a4d1-207eca0ad07b/scratchpad/`).

---

## Why the current plate reads unbalanced (the defect, stated once)

The shipped panel reserves the close disc's own metric (`controlSizes.compact.height`,
36) as the plate's **right padding** while the left padding is `space.s` (8), and then
pushes the disc 16px (`space.m`) outside the plate on both axes.  Measured live (phone
360x691): content x157..300, panel edge 336 — a 36px dead band trails the content, and
the disc floats above-right of the box it is supposed to belong to.  The eye reads three
chips hugging one corner of a panel that is bigger than its content, plus a satellite.
Two structural causes: (1) the close's *reservation* participates in content flow;
(2) the straddle margin (16) is unrelated to the disc's size (36), so the disc is
neither on the corner nor in the panel.

**Balance invariant for every option below:** the plate's padding is uniform (one token
on all four sides), and the close either joins the content flow as a peer or sits on
padding/margin that is *derived from the close's own size* — never a hand-picked
reservation.

---

## Shared contract (all options — unchanged from shipped behavior)

These do not move; they are the feature's contract, verified in
`src/region_expand.luau` and `src/present/catchers.luau`:

- **Dismissal routes:** tap outside dismisses (`outsideTapCancel = true` — verified: the
  scrim catcher routes to `presenter.dismiss`); gamepad **Cancel** (B) dismisses
  (default `cancelPolicy`); a second press on the pill toggles closed; the epoch check
  closes on any anchor-rect change.  The visible close is the **keyboard** route out
  (Escape is platform-reserved, ADR-0013) and is therefore mandatory in every option —
  "no visible close" was evaluated and rejected at spec time against ADR-0013's
  standing rule ("screens that present a modal should always include a visible close
  affordance").
- **Close affordance contract:** `icon = "close"` (ASCII-safe glyph; packages may paint
  art over it), `label = "Close"` for the screen reader — icon-only, localization-free;
  a focus stop with a ring; effective target = `targetSizes.minimum` (44) via the
  renderer's hit floor (the visible control may be smaller); `surface = "chip"`.
- **Focus:** the plate is modal (traps the ring).  Initial focus = the presenter's
  shipped rule (first focusable — the content's own control when form 1 has one, else
  the close).  The close is the **last** stop in traversal order in every option.
  Cancel = dismiss.  No new focus API.
- **Scrim:** `scrim = "scrim"` → theme `scrimOpacity` (0.45), composed with
  `PreferredTransparency`.
- **Motion:** no `transition` declared — the plate places rather than travels (the
  reduced-motion answer by construction).  Sound hooks unchanged: the presenter's
  feedback `dismiss` event is the close sound's trigger point.
- **Anchoring:** `presentAnchored`, edge `bottom`, align `start`, gap `s`, no tail;
  edge flip + safe-area clamp are the placement's (D1).  The design must not assume
  which side of the screen the pill is on — every option below is side-agnostic.
- **Ten-foot:** every metric below is a token or a token derivation, so the ×1.5
  ladder resolves it with no per-option branch.  Focus strengthening
  (`tenFootFocusRingThickness` 4 + `tenFootFocusScale`) applies to the close as to any
  control.
- **Sheet fallback** (`sheetOf`): each option states its sheet form; the sheet keeps
  the same dismissal contract.

Token values referenced (from `tokens/default_style.luau` /
`themes/snapshot.luau`): `space` xs 4 / s 8 / m 16 / l 24; `radii.control` 8,
`radii.panel` 12; `controlSizes.compact` height 36, iconSize 16;
`targetSizes.minimum` 44; `focusRingThickness` 2 (ten-foot 4); `scrimOpacity` 0.45.

---

## Option A — inline trailing close (RECOMMENDED)

*The close is the last element of the plate's own row: a compact circular chip in
flow, uniform padding all around.  No straddle, no reservation, nothing outside the
box.*

**Mockup:** `plate_design_A.png`.

### Structure (Facet primitives)

```
ExpandPanel = HStack {
  gap     = "space.m",          -- the separator between content and chrome
  padding = uniform "space.s",  -- one token, all four sides
  children = {
    [form 1]                    -- the author's content, unchanged
    CloseDisc                   -- Button, shape=circle,
                                --   height = controlSizes.compact.height,
                                --   alignV = "start"
  }
}
```

### Geometry (every value a token or derivation)

| Metric | Derivation | Near px | Ten-foot px |
|---|---|---|---|
| Plate padding (all 4 sides) | `space.s` | 8 | 12 |
| Content ↔ close gap | `space.m` | 16 | 24 |
| Close disc | `controlSizes.compact.height`, circle | 36 | 54 |
| Close glyph | `controlSizes.compact.iconSize` | 16 | 24 |
| Corner radius | `radii.panel` | 12 | ladder |
| Plate width | hug: s + content + m + disc + s | content+68 | derives |
| Plate height (1-row content) | s + max(content, disc) + s | 52 | derives |

- **Separation invariant:** the content↔close gap (`space.m`) is strictly larger than
  any gap inside the content row (`xs`/`s`), so proximity alone says "this is the
  plate's chrome, not a fourth chip"; the disc additionally wears the interactive chip
  surface + hairline, which no content chip does.
- **Tall content:** `alignV = "start"` — the disc top-aligns beside the first row
  (standard card idiom).  For a one-row compact plate the disc and row are the same
  36, so it reads centered with zero special-casing.
- **`fill` correction:** unchanged mechanism; the fixed width (`plate.max`) lands on
  the HStack, the content column takes the remainder (`plate.max − space.m − disc −
  2·space.s`).  This *shrinks* the shipped chrome-overflow caveat's error band — the
  chrome is now visible control, not dead reservation.
- **Focus ring room:** disc inset `space.s` (8) from every plate edge ≥ ring 2
  (ten-foot: 12 ≥ 4).  Ring draws fully inside the plate.
- **Edge clamp:** trivial — the surface box IS the visual box (no margins), the
  shipped clamp needs no knowledge.  Hit expander exceeds the disc by (44−36)/2 = 4px
  per side; the plate's own padding (8) contains it, so the effective target never
  hangs off-plate or off-screen.
- **R18:** satisfied by construction — the close is *in flow*; it cannot cover
  content.
- **Sheet:** the same rule, one idiom both presentations: `HStack { content (fill),
  gap m, disc }`, padding `space.m`, disc top-trailing.  Replaces the shipped
  right-padding-as-reservation on the sheet too.

**Focus order:** content stops (document order) → CloseDisc.  Pointer/touch may still
prefer scrim-tap; pad prefers B; keyboard tabs to the disc.

**Balance rationale (one line):** the close joins the content's own flow, so the plate
hugs [content + close] under uniform `space.s` padding — no reserved corner, no dead
band, nothing floating outside the box to balance.

**Honest cons:** the plate is ~8px wider than the current ZStack box for the same
content (width spent on a visible control instead of a dead band); the close shares
the row's visual plane, so it has less "chrome" separation than a corner disc.

---

## Option B — corner disc on symmetric padding (the reference-image look, fixed)

*Keeps the straddling top-right disc the director's reference showed, but removes the
reservation from content flow: the plate's padding is uniform `space.m`, and the disc's
center sits exactly on the plate's corner — its incursion lands on padding only,
proven, never on content.*

**Mockup:** `plate_design_B.png`.  Position: **upper-right — settled, director ruling
2026-08-21.**  (Specified as "top-trailing" so a future RTL mirror follows locale.)

### Structure

```
ExpandPanel = ZStack {
  children = {
    ExpandPlate = VStack {
      surface = "raised",
      padding = uniform "space.m",                       -- symmetric; NO disc metric
      margin  = { top = "space.xs" + DISC/2,             -- = 4 + 18 = 22 near
                  trailing = "space.xs" + DISC/2 },      -- the straddle, derived
      children = { [form 1] }
    },
    CloseDisc = Button { shape = circle, height = controlSizes.compact.height,
                         alignH = "end", alignV = "start",
                         margin = { top = "space.xs", trailing = "space.xs" } }
  }
}
```

### The construction (why the numbers cannot go wrong)

- **Disc center lands exactly on the plate corner:** disc center offset from the
  ZStack's top-trailing corner = `xs + DISC/2`; the plate's corner offset = its margin
  = `xs + DISC/2`.  Equal by construction, for any theme ladder.
- **R18 proof (padding-only incursion):** the disc reaches `DISC/2` inward from the
  corner; the content box's nearest point is the padded corner at distance
  `space.m·√2`.  Near: 16√2 ≈ 22.6 > 18.  Ten-foot: 24√2 ≈ 33.9 > 27.  The guarantee
  is the inequality `controlSizes.compact.height ≤ 2√2 · space.m` (36 ≤ 45 near) — the
  build asserts it, so a theme that breaks it fails loudly at compile, not visually.
- **Focus ring room:** the disc is inset `space.xs` (4) from the surface box ≥ ring 2;
  ten-foot 6 ≥ 4.  (The shipped design had zero ring room outside the disc.)
- **Edge clamp:** the shipped mechanism unchanged — the straddle is *plate margin*, so
  the surface box contains the disc and the clamp already clamps a box that contains
  it.  At the reference layout (pill at x130) the box's trailing edge lands exactly on
  the `space.m` gutter.
- **Hit-target honesty (the one real con):** the 44 floor reaches 22px inward from the
  corner; padding is 16, so the invisible expander can contest ~6px of a content
  control's corner if the author puts one exactly in the top-trailing corner (topmost
  wins → the close).  A and C have zero incursion.
  **CORRECTED IN BUILD (fix round 1, 2026-08-21): the ten-foot line here was wrong and
  the incursion is WORSE at distance, not absent.**  This spec said "Ten-foot: 22 < 24 →
  no incursion", comparing the NEAR floor's half (44/2 = 22) against the TEN-FOOT
  padding (24).  The floor scales too: 66/2 = 33, minus 24, so the incursion is **9px at
  ten-foot** against 6px near — measured 6×6 = 36 px² and 9×9 = 81 px² over an author
  Button in the plate's top-trailing corner.  It is answered in the build rather than
  accepted: the close now carries `expandTarget = { role = "close" }` and the renderer's
  grow-until-pressable floor (`render/commit_walks.growWithin`, ADR-0041) bounds it, so
  the floor grants nothing over an author control.  What remains is the disc's own
  bounding BOX at the corner — 2px near, 3px at ten-foot — which is a rectangle-vs-circle
  fact about engine hit rects, not about this design.
- **Sheet:** a sheet is edge-to-edge — no corner to straddle — so the disc sits
  *inside* the sheet's top-trailing padding, and its trailing reserve is the disc's own
  metric.  B is the only option whose plate and sheet wear two different silhouettes.
  **CORRECTED IN BUILD (fix round 1, 2026-08-21): "as shipped today" was not enough of a
  ruling.**  The close affordance is ONE node shared by both presentations, so the
  `space.xs` margin that centres the disc on the *plate's* corner also moves it inward on
  the *sheet*, where there is no straddle to absorb it — straight into a reserve that was
  exactly `controlSizes.compact.height` and no more.  Measured: the painted circle 4px
  (near) / 6px (ten-foot) over the author's own words.  The sheet's trailing reserve is
  therefore `space.xs + controlSizes.compact.height` — the disc PLUS the inset it is
  given — which restores the tangency this bullet has always described.

### Geometry table

| Metric | Derivation | Near px | Ten-foot px |
|---|---|---|---|
| Plate padding (all 4) | `space.m` | 16 | 24 |
| Disc | `controlSizes.compact.height` | 36 | 54 |
| Straddle margin (top+trailing) | `space.xs + disc/2` | 22 | 33 |
| Disc inset from box | `space.xs` | 4 | 6 |
| Plate width | hug: m + content + m | content+32 | derives |
| Plate height (1-row) | m + content + m | 68 | derives |

**Focus order:** content stops → CloseDisc (last child of the ZStack — unchanged).

**Balance rationale (one line):** the content sits dead-center in a symmetric
`space.m` frame, and the disc is a true corner ornament — half in, half out, centered
on the corner it decorates instead of hovering near it.

**Honest cons:** on a one-row plate the 36 disc is more than half the 68 plate height,
so over the rounded corner it still reads slightly satellite (visible in the mockup —
inherent to the treatment at this content size; on taller plates, e.g. the task list,
it reads like the director's reference); the corner hit-expander incursion above; two
silhouettes across plate vs sheet.

---

## Option C — footer collapse bar

*No corner chrome at all: a slim full-width dismiss bar under the content, inside the
same uniform padding.  The dismiss reads as "collapse" — the mirror of the expand that
opened it.*

**Mockup:** `plate_design_C.png`.

### Structure

```
ExpandPanel = VStack {
  padding = uniform "space.s",
  gap     = "space.s",
  children = {
    [form 1],
    CollapseBar = Button { width = fill, height = "space.l",
                           radius = "radii.control", surface = "chip",
                           icon = "close", label = "Close" }
  }
}
```

### Geometry

| Metric | Derivation | Near px | Ten-foot px |
|---|---|---|---|
| Plate padding (all 4) | `space.s` | 8 | 12 |
| Content ↔ bar gap | `space.s` | 8 | 12 |
| Bar visible height | `space.l` | 24 | 36 |
| Bar radius | `radii.control` | 8 | ladder |
| Bar glyph | `controlSizes.compact.iconSize` | 16 | 24 |
| Plate width | hug: s + content + s | content+16 | derives |
| Plate height (1-row) | s + content + s + bar + s | 84 | derives |

- **Glyph is the static `close`, never a directional chevron:** the placement flips
  the plate above/below the pill near screen edges, so a direction-implying glyph
  would lie half the time.
- **Hit floor:** 44 − 24 = 20 → the expander reaches 10px above/below the bar.  Above:
  the `space.s` gap absorbs 8, leaving a 2px contest band at the content's bottom edge
  (topmost wins → the bar).  If form 1's *last row* is interactive, the spec's
  variance is gap = `space.m` (kills the band).  Ten-foot: bar 36 → expander 4 ≤ gap
  12 — no band.  Below: 10 − 8 = 2px past the plate edge, contained by the placement
  gutter.
- **Edge clamp:** trivial (no margins, box = visual box), same as A.
- **R18:** satisfied by construction (in flow).
- **Sheet:** the same bar as the sheet's last row — the natural bottom-sheet dismiss
  idiom; one silhouette across both presentations (same virtue as A).
- **Ten-foot virtue:** a full-width final focus stop is the easiest possible target to
  see and land on from the couch; the ring wraps the whole bar.

**Focus order:** content stops → CollapseBar.

**Balance rationale (one line):** zero horizontal chrome — both side paddings are the
same token and the dismiss spans the full content width as plate furniture, so nothing
pulls the composition left, right, or out of the box.

**Honest cons:** +32px height (bar + gap) on *every* plate — a 62% height increase on
a one-row plate, the tallest option; a bottom bar is a less conventional close than a
top-right disc (novelty cost the director should weigh); the 2px contest band at near
density unless the gap variance is applied.

---

## Comparison and recommendation

| | A inline trailing | B corner disc | C footer bar |
|---|---|---|---|
| Dead band removed | yes (in flow) | yes (symmetric m) | yes (in flow) |
| Uniform padding | s | m | s |
| Anything outside the box | no | disc (contained margin) | no |
| Hit-expander over content | none | ~6px corner (near only) | 2px band (variance kills it) |
| Same silhouette plate & sheet | yes | no | yes |
| Height (1-row, near) | 52 | 68 | 84 |
| Convention match (upper-right settled) | high | highest (literal reference) | low-mid |
| Engineering delta | small (ZStack→HStack, drop reservations) | small (padding+margins only) | small (VStack, drop straddle) |

All three are zero-new-API: they reshape `panelOf`/`sheetOf` blueprints and token
references only; `region_expand.luau` (dismissal, epoch, focus) is untouched.

**Recommendation: Option A.**  Strongest reason: it is the only treatment where the
close and the content are one composed unit — the plate hugs [content + close] under
one uniform padding token, so there is no reserved corner, no dead band, and nothing
floating outside the box for the eye to balance; the corner-disc look that produced
both rejected rounds is retired rather than re-tuned.  (B is the closest to the
director's original reference if he wants to keep that look; C is the strongest
ten-foot/touch target if he'll trade height for it.)

### Decision needed (plain language)

The pop-open panel needs its close button placed so the panel looks tidy.  Today the
panel saves an empty strip for the button and then floats the button outside its
corner, which looks lopsided.  Three fixes, pick one:

- **A (recommended):** put the round close button *inside* the panel, at the end of
  the row of numbers, with even padding all around.  Tidiest and simplest; the button
  becomes part of the row.
- **B:** keep the "button pinned on the corner" look from the reference picture, but
  center it exactly on the corner and give the panel even padding so the content sits
  centered.  Closest to the picture; on a small one-row panel the button still looks a
  bit like it's hovering.
- **C:** a slim full-width "close" bar along the panel's bottom, like the pull-bar on
  a phone sheet.  Perfectly symmetric and easiest to hit, but it makes every panel
  taller.
