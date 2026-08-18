# ADR-0029 — The leaf fade: a composition needs a base term, and the engine takes it away

**Date:** 2026-08-15
**Status:** Accepted
**Supersedes:** nothing. **Amends:** [ADR-0026](ADR-0026-authored-presentation-composition.md)
Decision 4 (why a leaf is refused) and its Consequences (the asymmetry between the
three terms), replacing a predicted cost with a measured one and turning a silent
absence into a refusal that speaks.
**Commissioned by:** the game director, 2026-08-15 — close ADR-0026's deferral, or
say why it cannot close and make the refusal legible at the point of use.
**Companions:** ADR-0022 Decision 2 (the fade group and the presentation channel),
ADR-0018 / ADR-0019 §4 (native stylesheet ownership),
`docs/lessons/a-re-solve-does-not-repaint.md` (the theme-commit repaint sweep),
`docs/lessons/stylesheet-defeat-order-sensitive.md`,
`docs/lessons/the-base-term-is-destroyed-by-composing.md` (this round's lesson),
`artifacts/adr-0029-leaf-opacity/live-probes.md` (every number below).

## Context — the question ADR-0026 left open

ADR-0026 made `opacity`, `scale` and `rotation` authored props and folded them into
the presentation authority's own write as a second **term** rather than a second
writer. It offered `opacity` on `Box` and `ZStack` only, and gave a reason: a leaf
fade would write `TextTransparency` / `BackgroundTransparency`, both in
`NATIVE_SHEET_OWNED`, and an explicit write there *"permanently defeats the rule"* —
concretely, *"a `UI.Text` with an opacity would stop dimming when disabled, forever."*

The director's question is the right one, and it is not answered by that sentence.
ADR-0026's own rule for the group case is **compose, don't own**: the framework's
value and the author's value meet at one write site and multiply. Apple states the
same rule for nesting ([SW-141]). So: can `TextTransparency` carry an authored term
composed against the sheet's value at the one write site, exactly the way
`GroupTransparency` carries one composed against the channel value?

The two look symmetrical. They are not, and the reason is deeper than "the sheet
rewrites its property on state change and `GroupTransparency` has no state rules".

## Decision 1 — the leaf fade stays refused, because a composition has no base term to compose against

**A composition is `f(base, authored)`.** For the group case the base is the
framework's own channel value, which the framework holds in a table it owns. For a
leaf the base is the sheet's resolved value, and the engine offers exactly one way
to read it: `Instance:GetStyled(prop)`.

**Measured, 2026-08-15 (probe L1).** A `TextButton` under a `StyleLink` with a
`:NonInteractable` dimming rule reads `GetStyled("TextTransparency")` = `0` enabled
and `0.6` disabled — the rule working, the raw property `0` throughout, reads
blind. Then one explicit write of the composed value:

| step | `GetStyled` | raw |
|---|---|---|
| disabled, untouched | **0.6** | 0 |
| after the composed write (`opacity = 0.5` → `T = 0.5`) | **0.5** | 0.5 |
| disabled, after the write | **0.5** | 0.5 |
| unparented and re-parented | **0.5** | 0.5 |

`GetStyled` returns **the write**. So the base term is not merely stale after the
first composition — it has stopped existing, and nothing recovers it. The
order-sensitivity escape hatch does not apply: that lesson is about a write made
*before* an instance first joins the styled tree, and a tracked instance keeps its
defeat across leaving and re-joining.

**This is a stronger claim than ADR-0026's, and it is the one that closes the
question.** "The rule stops applying" invites a workaround — cache the base, watch
for changes, re-assert. "The base is unreadable from the first write" refuses all
of them at once, because every workaround needs to read it.

### The three workarounds, each closed by measurement rather than by argument

**Re-compose on `GetStyledPropertyChangedSignal`.** The signal exists and fires. It
fires *after* the write too — and by then `GetStyled` is our own value, so the
composition multiplies its own output back in. Built and watched (probe L4): a label
at `opacity = 0.5`, four disable/enable cycles, alphas written
`0.500 → 0.750 → 0.875 → 0.938 → 0.969 → 0.984 → 0.992 → 0.996 → 0.998`. **The label
is gone.** The failure is not silent, which is worse: the implementation looks alive
while reading its own tail.

**Animate the RULE instead of the instance.** A `StyleRule` property edit reaches
`GetStyled` after **3 frames** (probe L2b). A fade needs the value in the frame it
paints. It is also per-selector rather than per-node — a per-node fade would mean one
generated rule per faded node, mutating a sheet whose priorities are generator-owned
infrastructure, at 60 Hz.

**Write every transparency the leaf has.** A leaf's alpha is not one property. A
`Button` in native mode paints through chrome slots, an icon picture, a stroke and a
corner ladder, and the set is **open** — a theme package adds layers. Worse, some of
it has no instance at all: a `::UIStroke` rule renders a 3px ring with **zero child
instances** on the leaf (probe L2c). You cannot write a transparency onto something
that does not exist.

## Decision 2 — the offerable-term rule, which is what the asymmetry actually is

ADR-0026 shipped `scale` and `rotation` on every rendered class and `opacity` on two,
and never said why. It is one rule, and it is not about opacity being special:

> **An authored presentation term is offerable on a class when ONE engine property
> that no style rule owns expresses it for that class's entire painted output.**

| term | the one property | who owns it | offerable on |
|---|---|---|---|
| `scale` | `UIScale.Scale` on `FacetMotionScale` | nobody — a bespoke instance, no rule can express a motion scale | every rendered class |
| `rotation` | `GuiObject.Rotation` | nobody — written by no generated rule, absent from `NATIVE_SHEET_OWNED` | every rendered class |
| `opacity` | `CanvasGroup.GroupTransparency` | nobody — which is why ADR-0022 chose it | **only a node whose engine instance can BE a CanvasGroup** |

Both `UIScale` and `Rotation` apply to the instance *and its descendants*, so each
covers the node's whole painted output including phantom modifiers. Alpha has no such
property on a plain `GuiObject`; the only one is on `CanvasGroup`, and a `TextLabel`
cannot be a `CanvasGroup`. `Box` and `ZStack` are the two classes whose instance can
be one — which is why they are exactly the two that carry `canvasGroup`, and why
`opacity` was put there rather than somewhere convenient.

**Pinned as an invariant, not a spot check.** `tests/authored_presentation.spec.luau`
walks every class in the schema: `opacity` is offered on exactly `{Box, ZStack}` and
**refused by name** on every other rendered class, while `scale`/`rotation` are on all
21 and refused on none. Adding a class, or quietly widening either set, reddens it.

### Why the framework does not wrap the leaf for the author

The obvious alternative to refusing is materializing a leaf-with-opacity as a
`CanvasGroup` containing its `TextLabel` — the wrap, written by the framework. It is
refused on the first rung of the simplicity ladder: **it produces exactly the two
instances `UI.ZStack{ opacity }` already produces**, so it buys one line of author
text, and it costs a second exception to Facet's flat instance tree (ADR-0022
Decision 2's *"single documented exception"*), a hidden render buffer where ADR-0022
deliberately made the cost explicit, an extra ancestor that breaks any `>`
child-combinator rule reaching that node, and a recycle-key split. One line is not
worth an architecture exception that nothing in the blueprint declares.

## Decision 3 — the refusal is a construction error that names the fix

The refusal was already there; it just had nothing to say. `UI.Text{ opacity = 0.4 }`
reported *"unknown property 'opacity'. Valid properties: …"* — which reads as an
oversight in the schema, sends the author to a list that does not contain the answer,
and never mentions the one line that works. **A capability that is refused should say
so at the point of use.**

`schema.refusal(class, prop)` is one table and one lookup. It answers for `opacity`
**and** `canvasGroup` — one fact, both spellings — on every class that paints an
engine instance, and `blueprint.unknownPropError` prefers it to the suggester. The
message states the rule, the measured consequence, and the spelling:

> `Facet UI.Text: 'opacity' is REFUSED on UI.Text, not missing. A fade in Facet is
> one engine property no style rule owns — CanvasGroup.GroupTransparency — and only a
> node materialized as a CanvasGroup has one. UI.Box and UI.ZStack are the two classes
> that can BE one. Anywhere else the fade would have to write
> TextTransparency/BackgroundTransparency, which the native stylesheet owns, and one
> explicit write does not lose a frame: it makes the sheet's value unreadable for good
> (GetStyled returns the write from then on), so a control under it would stop dimming
> when disabled, forever. The spelling is one wrap: UI.ZStack{ opacity = 0.4, children
> = { … } }. `scale` and `rotation` need no wrap and are offered on every rendered
> class, because each of them IS one engine property no rule owns (UIScale.Scale,
> GuiObject.Rotation). See ADR-0029.`

**The five structural classes are deliberately excluded.** `When`, `ForEach`,
`Region`, `GridRow` and `ErrorBoundary` paint no instance, so `opacity` there is
genuinely unknown rather than refused, and the fade message would be a wrong answer to
a real question. The guard is `spec.props.scale == nil` — a class that offers `scale`
is a class that paints, which is exactly the set where "why not opacity too?" is worth
answering.

## Decision 4 — the wrap keeps the sheet whole, and that is measured too

The refusal is only honest if the spelling it offers does the job. `UI.ZStack{ opacity
= 0.5, children = { UI.Button{ enabled } } }`, live on a `nativeStyle` target
(probe W1):

```
1 DISABLED  GroupTransparency=0.5000  btn GetStyled(TextTransparency)=0.4000  raw=0.0000
2 ENABLED   GroupTransparency=0.5000  btn GetStyled(TextTransparency)=0.0000  raw=0.0000
3 DISABLED  GroupTransparency=0.5000  btn GetStyled(TextTransparency)=0.4000  raw=0.0000
```

The fade is one property no rule owns; the control's raw transparency is `0`
throughout, so the sheet's `:NonInteractable` rule is still its only writer and the
dimming moves with the state *underneath* the group fade. The two compose visually —
the buffer fades a picture that already has the dimming painted into it — which is
ADR-0026 Decision 6 confirmed from the other end.

## Decision 5 — an authored presentation term does not join `refreshThemedPaint`, and the entry condition is written down

The standing hazard: a theme commit re-derives everything the **solver** reads and
nothing the **adapter** paints, so every adapter-owned paint that resolves a palette
had to join `screen_paint.refreshThemedPaint` or go stale — the blue-spinner class
(`docs/lessons/a-re-solve-does-not-repaint.md`). An authored leaf opacity would have
been such a paint. Is the authored *group* opacity one?

**Measured (probe T1), with a positive control.** A node at `opacity = 0.4`,
`scale = 0.75`, `rotation = 20` under Studio Neutral, then a real
`theme_controller.install` of Fantasy Parchment: the caption's styled `TextColor3`
moves from `0.925, 0.937, 0.961` to `0.204, 0.157, 0.102` — the commit demonstrably
landed — and `GroupTransparency`, `UIScale` and `Rotation` are unchanged at
`0.6 / 0.75 / 20` across it and a second later.

**The rule, stated so the next authored paint knows which side it is on:**

> A paint joins `refreshThemedPaint` **iff its value resolves a palette.** The
> presentation composition resolves none — its terms are the framework's channel value
> and the author's number — so a theme commit cannot make it stale. A future term that
> reads a theme role, a token or `paletteTheme()` joins the sweep on the day it is
> written, not on the day a director notices it.

## Decision 6 — the refusal costs a valid surface nothing, and it is structural rather than measured

`schema.refusal` is reached from exactly **one** call site, and that site —
`unknownPropError` — only runs once a property is already absent from the class, i.e.
on a construction that is about to throw. A valid `UI.Text{ text = … }` never enters
it. This is pinned as a source contract (one caller, and it is inside
`unknownPropError`), because there is no runtime path to measure.

Measured anyway, ABBA-interleaved over 12 runs: **with** the branch, construct median
117.8 ms / mount median 79.0 ms; **without** it, 118.9 / 79.4. The "with" arm is
*faster* by less than its own control spread (construct 114.6–119.3 = 4.0%, mount
77.6–83.1 = 7.0%). A plain A-then-B ordering had first reported mount **+3.1%**, which
the interleave erased — recorded here because that number was on its way into this
document.

## Consequences

- **`opacity` and `canvasGroup` now refuse by name** on every rendered class that
  lacks them, and the message carries the rule, the consequence and the spelling. The
  suggester and the valid-property list are untouched for every other key.
- **The asymmetry between the three authored terms is documented and pinned.** It was
  undocumented from ADR-0026 until now.
- **ADR-0026 Decision 4's prediction is upgraded to a measurement**, and its wording
  understated the cost: the failure is not that the rule loses, it is that the base
  term becomes unreadable. The lesson
  `docs/lessons/the-base-term-is-destroyed-by-composing.md` carries the general shape.
- **The showcase teaches the wrap.** `examples/gallery/scenarios/with_animation.luau`
  gains a fade group holding a label and a *disabled* button, riding the badge's own
  `paintOpacity` memo — one authored term, one spring, two nodes that had to spell it
  differently. `tests/overflow_sweep.spec.luau` filed 16 findings on the first draft
  of that row (a fixed 60px lane, at 320×640 with the +14 text preference, under four
  `control`-chrome packages) and the row hugs and wraps because of it.
- **Nothing in the renderer, the adapter or the authority manifest changed.** No new
  engine property has a second writer; `NATIVE_SHEET_OWNED` is untouched. This ADR is
  a decision, a message and a set of pins.
- **What is still not on offer:** fading a leaf's own paint without a buffer, in any
  spelling. If Roblox ever ships a per-instance alpha that no rule owns — or a way to
  read a styled value *past* an explicit write — this decision is the one to revisit,
  and Decision 2's rule is the test to re-apply.
