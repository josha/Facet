# A re-solve does not repaint

**Found:** 2026-08-14, from a director report — *"when i changed to the parchment
theme, the spinner stayed blue. i'd expect to make it a similar color?"*

**Cost:** every stroked `UI.Path` in the framework had never worn a theme
package's palette, in any package, since `UI.Path` shipped. Every static `tint`
kept the outgoing package's colour for the rest of its life. Two shipped
controls' whole visual identity — the circular ProgressView's arc, the dot
spinner's pulse — plus the showcase HUD's task marks.

## The mechanism

A theme commit is a **re-solve, never a rebuild** (ADR-0019 §2). That is a
feature: mount identity, focus, scroll position and text entry all survive a
swap because nothing is torn down. The commit publishes `themeMetrics`, which is
one of the renderer's coalesced **geometry** keys, and the renderer re-derives
everything downstream of it.

```
themeMetrics  ->  geometry  ->  re-solve  ->  new rects  ->  the adapter is told
tint / role   ->  paint     ->  (nothing)
```

So the commit re-derives everything the **solver** reads and nothing the
**adapter** paints. A node whose layout did not change is never re-visited, and a
colour is not a layout.

Most paint survives that anyway, because a StyleSheet rule owns it and the sheet
is swapped wholesale. The exceptions are exactly the paints **no rule can
express**:

| paint | why no rule can carry it |
|---|---|
| the focus ring's colour | a ring is a bespoke child, not a selectable state |
| the toggle's palette | a rule cannot see a **value** |
| the `tint` channel | same: a blend driven by a signal is not a selector |
| a `UI.Path`'s stroke role | a `Path2D` **is not a GuiObject** — no selector can reach one at all |

The first two each grew their own refresh **at the moment a director noticed
them blue** (`screen_target.luau`'s focus-treatment block still records the
2026-07-25 round: *"the ring painted itself from a STATIC accent constant
captured at construction, so it stayed Studio-Neutral blue no matter which
package was installed"*). The other two were the same bug, in the same file, and
were never looked for.

## The two shapes are not the same bug

Worth separating, because they fail differently:

* **Stale** — `tint` resolved against the live palette but was only written when
  its VALUE changed. A reactive tint therefore self-heals on its next write (the
  dot spinner recolours on the next animation tick); a static one never does.
  This is what made the report read as "only some things are stale".
* **Blind** — a Path's `role` resolved against `COLOR`, the palette captured at
  the target's construction. No amount of re-writing helps: there is no path
  through the code where a package's colour could ever reach it.

Measured before the fix: under Fantasy Parchment (accent rgb(122, 72, 26)) a
tinted Box and both of a circular ProgressView's paths read rgb(44, 98, 210)
after the commit, after a refresh, and after a frame.

## Why the suite could not see it

`tests/lib/fake_target` resolved **every** tint against a hard-coded
`NEUTRAL_THEME`, and modelled a Path's stroke colour not at all. A test double
that cannot tell a themed colour from a stale one cannot fail this test — the
5,184 green cases were, on this axis, all asserting the same constant. The double
now tracks the package pushed through `setThemePackage`, which is what its own
header always claimed ("the fake and the live target agree about the colour").

## Rules

1. **Ask what a re-solve does NOT do.** "The swap re-solves" is a statement about
   geometry. Every commit-time refresh in this adapter exists because somebody
   discovered, visually, that paint was not included. When a fact reaches the
   framework through one channel, enumerate the channels it does not reach.
2. **A construction-time palette is a bug waiting for a package.** `COLOR.*` in
   `screen_target` is the style the target was *built* with. Any read of it that
   is not explicitly "the no-package fallback" is theme-blindness. `paletteTheme()`
   is the live answer; there is now one sweep
   (`screen_paint.refreshThemedPaint`) and the next palette consumer joins it
   rather than becoming a fourth seam a director finds.
3. **The thing that self-heals hides the class.** The spinner's dots recover on
   the next tick, so the visible symptom was intermittent and control-shaped —
   which is exactly what makes it read as "the spinner is broken" rather than
   "nothing repaints". Ask whether the surface you are looking at is being
   re-written for some *other* reason before concluding the channel works.
4. **A mirror that resolves against a constant is not a mirror.** Before trusting
   "headless proves the adapter", check what the double resolves against. This is
   the same family as
   [`fake-adapter-records-what-live-adapter-ignores.md`](fake-adapter-records-what-live-adapter-ignores.md),
   read from the other end: there the fake recorded more than the live adapter
   applied; here it applied less than the live adapter resolved.
5. **A source-contract check on a concatenated source can match the wrong file.**
   The first version of this fix's check searched the whole live-adapter text for
   `refreshThemedPaint()` — which is *defined* in `screen_paint`, one of the
   concatenated parts, so it passed however the commit was mutated. Mutation
   testing caught it; a whole-text `find` for a name that also appears in a
   definition proves nothing. Extract the function's own body and search that.
