# The node that must spend the reservation lives outside the subtree

**Found:** 2026-08-14, desktop, `Facet-Showcase` / `table-columns`.
**Reported as:** *"on desktop, the scroll bar is persistent (correct) but it
always overlaps content"* — and, once the first diagnosis came back
vertical-only, *"the scroll bar issue should apply to both horizontal and
vertical ones."*

## The symptom, measured live

```
Body: Abs=883  Win=875   bar occupies 887..895
  header 'name': 12..277    ok
  header 'team': 277..630   ok
  header 'best': 630..895   <-- 8px UNDER THE BAR
```

Every column boundary drifts, worsening left to right. A headless A/B at all
eight swept viewports: reserve 8 → 8px of worst-case drift; reserve 0 → 0px.
**The drift IS the reserve.**

## The cause

The solver reserves the engine scrollbar off a scroll host's cross axis whenever
its content overflows, and the reservation is spent *inside* the host's content
box. Everything **under** the host is therefore correct for free — the rows stop
short of the bar without knowing the bar exists.

A Table's **header is a SIBLING of its scrolling body**, not a node inside it.
It laid its columns across the full frame while the rows laid theirs across the
frame minus 8, and three `fill` columns divided a difference of 8 into a
cumulative 2 / 5 / 8 px of drift.

This is [`a-fixed-box-cannot-hold-a-themes-frame.md`](a-fixed-box-cannot-hold-a-themes-frame.md)'s
closing line exactly — *reserving room is only half of it, something has to
spend it* — with the twist that **the node which must spend it sits outside the
subtree that made the reservation**, so nothing in the normal flow of insets can
reach it.

## Why nothing caught it

`tests/scroll_window_clip.spec.luau` is the instrument for "content laid out
past the window the player can see", and it walks a scroll host's
**descendants**. A sibling is structurally invisible to it at every viewport and
under every package — not a gap in the sweep, but the shape of its question. The
theme sweep could not see it either, for the same reason: it asks the solver for
findings, and a header laid out inside its own box files none.

The class needs a different sentence: **a Table's header column boundaries equal
its body's**, on whichever axis scrolls. That is the check, and it lives beside
the fixture in `tests/playlist_columns.spec.luau`.

## The fix

One number feeding both halves:

1. the solver **publishes the gutter each scroll host actually spent** —
   `out[id].barInset`, keyed by the side it came off (`right` for a Y scroller,
   `bottom` for an X one), and **nil** when it reserved nothing;
2. the renderer hands it back through `controller.scrollBarInsetOf(path)`;
3. `newTable`'s header pays the same number on the same side, as a third term of
   the multi-metric trailing padding it already carries
   (`chromeInsets.selection.right` + `chromeBleed` + the gutter).

Three things this deliberately is **not**:

- **Not derived from `adapter.scrollBarThickness`.** That is what a bar *would*
  take. The gutter is what *this* body took, and the two differ for every table
  whose rows fit. The conditionality is the reason it has to be published rather
  than re-derived: a sibling cannot know whether the content overflowed.
- **Not a trailing `Spacer` child.** A `percent` or `fill` column resolves
  against its container's inner extent, not against what its siblings left — so
  a spacer moves a `fixed` column's edge and leaves a `percent` one exactly
  where it was. Padding narrows the extent itself, which is the only spelling
  that moves every dim kind identically.
- **Not hard-coded to width.** A horizontally scrolling region reserves off its
  **bottom**, and any sibling that must align across *that* boundary drifts
  identically. Measured live: the shipped card rail reads `Abs=871x852` against
  `Win=871x844`. No horizontal surface has an aligned sibling *today* — the rail's
  neighbours stack above and below it — which is exactly why the axis half has
  its own case in `tests/scroll_bar_measure.spec.luau` rather than shipping on
  the strength of a `then`/`else` nobody ran.

## The cost, stated — and then paid off (2026-08-15)

The gutter is a **measurement**, so it arrives through `syncGeometry` and a prop
write made there was drained by the next `controller.refresh()`. `present`'s own
solve therefore laid the header out un-guttered and the first refresh corrected
it. Taking the root path from the node the presenter hands `syncGeometry` —
rather than from `mountedRoot`, which `buildFocusGroups` only writes *during*
that first refresh — is what took this from two frames to one.

Convergence is one step and the argument is structural, not hopeful: the gutter
narrows only the header's **inner** width, and a `lineLimit = 1` title in a
`minMax`-floored band cannot answer that with a taller header — so the body's
rect, its overflow verdict and the gutter are all fixed points after the first
solve. Pinned by "converges in one refresh and then holds still".

**The last frame is closed.** It was flagged here rather than smuggled into a bug
fix, and it was then done as its own change: the renderer now re-drains the prop
dirties a solve's own consumers published, inside that solve — the same settle
phase L-31 gave env writes (optimization log **L-34**). `present` returns with
the grids already together, pinned by *"PRESENT ALONE lands the grids together —
the gutter costs no frame at all"* in `tests/playlist_columns.spec.luau`, and the
general shape by *"a measure→publish cycle whose publication is a PROP settles in
the same solve"* in `tests/measure_publish_settle.spec.luau`.

## The rule

**Ask of every reservation: who spends it, and are they inside the box that made
it?** When the answer is "a sibling", the reservation has to become a published
fact rather than an inset, and the check that guards it is an equality between
two subtrees — never a containment test inside one.

## See also

- [`a-fixed-box-cannot-hold-a-themes-frame.md`](a-fixed-box-cannot-hold-a-themes-frame.md)
  — the same rule one level in: a control that reserves room its own content
  cannot spend.
- `docs/plans/device-bug-round-2026-08-12.md` B7(a) — FIXED 2026-08-12
  (director ruling REVERSED): why the reserve was made policy-blind, from
  2026-08-12 until 2026-08-28. Director ruling 2026-08-28 (task SCROLL2,
  fa7233a, ADR-0040 row B-35) PARTIALLY RE-REVERSED it: "always" still
  reserves unconditionally — this entry's own reasoning (Roblox has no overlay
  scrollbar; the engine charges the window for the bar instance whatever the
  policy paints) is still exactly why a BARE zero reserve is wrong — but
  "auto" reserves nothing again, paired with a compensating frame-widen
  (`src/client/screen_scroll_indicators.luau`'s file header) so the zero
  reserve does not reproduce the clip this entry describes.
