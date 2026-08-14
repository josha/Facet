# ADR-0026 — Authored opacity, scale and rotation: a composition rule, not a second writer

**Date:** 2026-08-14
**Status:** Accepted
**Commissioned by:** the game director, 2026-08-14. Verbatim: *"should opacity, transparency, and
scale get owned/influenced by luauui? it seems like we should be able to animate those."*
**Companions:** ADR-0022 Decision 2 (the presentation channel, and the `canvasGroup` fade rule),
ADR-0018 / ADR-0019 §4 (native stylesheet ownership and the five-name authority vocabulary),
ADR-0020 R8 (composition when a rule and a real child both paint),
`docs/reference/swiftui-parity.md` §6 (`opacity(_:)`), §8.1 (`withAnimation`).

## Context — the gap, and why two prior missions declined it

Two rounds looked at authored opacity and both deferred it, correctly, for the same reason. The
reason is worth restating exactly, because it is what this ADR has to answer:

- All three presentation-authority properties — `transform`, `transparency`, `dragHeld` — are
  **renderer-driven**, and **none of them appears in `src/blueprint_schema.luau`**. There is no
  authored value anywhere in that channel. So `withAnimation` cannot animate an opacity for the
  most basic possible reason: there is nothing authored to diff. (`withAnimation` interpolates the
  difference between two commits; before this ADR, the only values a commit produced were the
  solver's four rect numbers, all four of which it already animates.)
- `src/render/authority.luau:59` gives `transparency` to the **presentation** channel, and the
  manifest permits exactly **one authority per engine property per class**. That manifest exists
  because the engine will not police this: the Studio spike proved an explicit write silently
  defeats a `StyleRules` rule and fires no signal. A second writer is therefore not a style
  question, it is a defect class.
- So an authored opacity is either a second writer (refused) or a **composition rule** — the
  effective value as a function of the authored value and the live presentation value, resolved at
  the one write site — which then has to reconcile with `withAnimation`'s records and with the
  native sheet's ownership of `BackgroundTransparency` / `TextTransparency`.

Apple states the rule such a composition has to honour, and it is the only one of the three
properties for which Apple states it at all. Read from the JSON twin on 2026-08-14 (the §16 route
for a page that renders client-side) and quoted verbatim: applying `opacity(_:)` to a view *"that
has already had its opacity transformed, the modifier **multiplies** the effect of the underlying
opacity transformation"* ([SW-141]).

## Decision 1 — the authored value is an INPUT to the presentation authority, never a writer

**The manifest does not change. Not one line.** `transparency` and `transform` stay `presentation`,
and the presentation channel keeps being the only thing that writes them.

What is new is that the presentation channel's *value* now has two contributors instead of one:

```
engine write  =  compose( renderer-driven channel value , authored blueprint value )
```

`opacity`, `scale` and `rotation` are blueprint props declaring a new schema channel,
`channel = "presentation"`, whose meaning is precisely this and nothing else: **the renderer folds
this prop into the presentation channel's value; it never reaches an `adapter.setProp` call of its
own.** There is no `adapter.setProp(handle, "opacity", …)`. There is no
`authority.assertWrite(class, "opacity", …)`, because nothing writes an engine property called
opacity.

This is the difference between *another authority* and *another term*. The manifest asks "how many
functions may write this engine property?" — the answer stays one. It does not ask "how many facts
may that one function read?"

## Decision 2 — the composition rule, per property: each channel composes with its own group operation

| property | composition | identity | engine target |
|---|---|---|---|
| **opacity** | **multiply** | `1` | `CanvasGroup.GroupTransparency` |
| **scale** | **multiply** | `1` | `UIScale.Scale` (`LuauUIMotionScale`) |
| **rotation** | **add** (degrees) | `0` | `GuiObject.Rotation` |

This is one rule, not three: **compose in the transform's own group.** Two scalings compose by
multiplying their factors; two rotations compose by adding their angles; two alpha-over composites
compose by multiplying their alphas. Choosing anything else for any row would make nesting
non-associative — a subtree scaled 2× inside a container scaled 2× has to read 4×, or "scale" does
not mean scale.

Opacity is the one row where the answer is not merely geometric taste, and it is also the one row
Apple writes down: *"multiplies the effect of the underlying opacity transformation"* ([SW-141]).

**In engine units.** Roblox's channel is *transparency*, where `0` is opaque and `1` is invisible;
SwiftUI's authored value is *opacity*, where `1` is opaque. The renderer therefore composes:

```
T_effective  =  1 − (1 − T_presentation) × opacity_authored
```

which is exactly `opacity_effective = opacity_presentation × opacity_authored` written in the units
the engine takes. A framework fade to nothing (`T_presentation = 1`) stays invisible whatever the
author declared; an author's 50% stays 50% of whatever the framework is currently painting.

**What does NOT compose this way, and why.** The presentation channel also carries `x`, `y`, `w`,
`h` — a positional offset and a painted size delta. Those stay **additive** and stay
**renderer-only**: there is no authored counterpart to add, because the authored position and size
of a node is the solver's output, not a paint value. Smuggling an authored size through the
transform channel would be exactly the "size-shaped fade" the parity doc names as the failure mode.

## Decision 3 — one write site, and the composition happens there

`src/render/renderer.luau` gains **one** internal function, `pushPresentationPaint(path)`. It turns

- the channel value (`lastTransform[path]`, `lastTransparency[path]`),
- the authored value (`authoredPresentation[path]`),
- and this frame's `withAnimation` record and its progress `p`

into **at most two** `adapter.setProp` calls — `"transform"` and `"transparency"`, both on the
`presentation` authority, both still asserted through `authority.assertWrite`.

Every contributor routes through it: `controller.setPresentationTransform`,
`controller.setPresentationTransparency`, the animation writer, and the commit path that notices a
reactive `opacity`/`scale`/`rotation` changed. **No contributor calls `adapter.setProp` for these
two properties itself.** That is the invariant that makes "one authority" true in code rather than
in a comment, and `tests/authored_presentation.spec.luau` pins it by counting write sites in the
source.

The write is **memoized on the composed value**, not on any contributor's value. Recomposing when
nothing moved costs a comparison; it never costs an engine write. (The previous memo was on the
channel value alone, which would have gone stale the moment a second contributor existed.)

## Decision 4 — `opacity` implies the fade group, and lives exactly where `canvasGroup` lives

`opacity` is offered on **`Box` and `ZStack` only** — precisely the two classes that carry
`canvasGroup` — and **declaring it makes the node a fade group**, so an author does not write
`canvasGroup = true` beside it. The renderer passes the implied flag into `adapter.create` at
creation time and into the recycle key, exactly as the explicit prop already does.

**Why it is not offered on a leaf.** A leaf fade would have to write `BackgroundTransparency` or
`TextTransparency`. Both are in `NATIVE_SHEET_OWNED` (`src/render/authority.luau`). An explicit
write to a sheet-owned property does not "win this frame" — the spike (2026-07-19, reconfirmed
2026-07-24) proved it **permanently** defeats the rule, silently, with no signal. The concrete cost
is not hypothetical: `TextTransparency`'s rule is the disabled-state `:NonInteractable` one, so a
`UI.Text` that accepted an `opacity` would stop dimming when disabled, forever, from the first frame
it was faded. Refusing the leaf keeps the sheet whole.

The refusal is a **construction error** — `UI.Text { opacity = 0.4 }` reports an unknown property
with the class's valid list — and the spelling an author wants is one wrap:
`UI.ZStack { opacity = 0.4, children = { text } }`. That is SwiftUI's own answer too: without a
compositing group, ancestor opacity applies per-descendant, which is why `compositingGroup()` exists
and what its page describes it as buying ([SW-133]).

## Decision 5 — a `canvasGroup`'s `GroupTransparency` and an authored child opacity: the engine multiplies them, and that is correct

Two cases, and they have different answers because they are different questions.

**Same node.** The framework is fading a node (a transition, a toast retiring) *and* the author
declared an opacity on that same node. One engine property, two contributors, one write —
Decision 2's multiply, resolved by Decision 3's single site. A transition fading a 60%-opacity panel
out reaches zero, and on the way there paints `0.6 × p`; it never briefly brightens to full.

**Nested nodes.** An outer `canvasGroup` is fading, and a *descendant* declares its own opacity.
**The engine composes this one, and the framework must not.** A `canvasGroup` node is its subtree's
**real instance parent** — the single documented exception to LuauUI's flat instance tree
(ADR-0022 Decision 2) — so a nested fade group's `CanvasGroup` is genuinely inside the outer one's
render buffer. The inner group renders its subtree at its own `GroupTransparency`; the outer buffer
then composites that already-faded result at its own. The visible alpha is the product, which is
[SW-141]'s rule delivered by the renderer of record.

So the framework composes **within a node** and never **across nodes**. Doing both would multiply
the ancestor's alpha in twice — the descendant would fade faster than its parent, which is the
visible symptom, and the accumulate-down-the-subtree rule the *positional* half of the transform
needs would have been copied to a channel that must not have it. (Position accumulates because the
tree is flat and a container's move carries nothing inside it. Alpha does not accumulate, because a
fade group's children genuinely *are* inside it. Same fact, opposite conclusion — the same asymmetry
`withAnimation`'s size half already documents.)

## Decision 6 — the native sheet keeps everything it owned

None of the three engine targets is in `NATIVE_SHEET_OWNED`, and that is by construction rather
than by luck:

- **`GroupTransparency`** is owned by no rule at all — that is exactly why ADR-0022 chose it as the
  fade channel, and the sheet has no `CanvasGroup` class-default rule (`screen_target.luau`'s
  CanvasGroup note).
- **`UIScale.Scale`** lives on a **bespoke instance**, `LuauUIMotionScale`, already a declared
  member of `BESPOKE_INSTANCES`: no rule can express a motion scale, and being on that list is what
  buys the instance the right to exist.
- **`GuiObject.Rotation`** is written by no generated rule anywhere in `src/tokens/`, and is absent
  from `NATIVE_SHEET_OWNED`.

Therefore `BackgroundTransparency`, `TextTransparency`, `ImageTransparency` and
`StrokeTransparency` remain the sheet's, untouched. A disabled control still dims through its
`:NonInteractable` rule *underneath* an authored opacity, and the two compose visually — the group
buffer fades a picture that already has the disabled dimming painted into it — instead of contesting
one property. `assertBespokePaint` is not bypassed, weakened, or newly exempted by this ADR.

## Decision 7 — `withAnimation` animates all three, on the same spring, as three more terms in the record

A record grows from `{x, y, w, h}` to `{x, y, w, h, o, s, r}`, and the painted authored value is

```
authored_painted  =  authored_destination  +  delta × p
```

for the same single progress `p` that already drives position and size. That is what makes a panel
that slides, grows and fades arrive on one frame: three springs would drift, and no screenshot could
prove they had not.

- The deltas are diffed at the **armed commit** from the previous commit's authored values
  (`lastAuthored`), exactly as `x`/`y` are diffed from `lastRects`. An armed commit always solves,
  so the diff has one home; with incremental layout a solve that nothing dirtied is nearly free.
- They **do not accumulate down the subtree** — an authored opacity, scale or rotation is a per-node
  fact, like the size half. A `UI.Text` inside a fading card is *inside the group's buffer*
  (Decision 5) and must not also fade on its own.
- Interpolation is **linear in the authored value** (opacity `0 → 1` is linear alpha, scale
  `1 → 1.4` is linear scale) and never in the composed engine number, so a flight looks the same
  whether or not the framework happens to be fading the same node at the time.
- Interruption re-bases identically: a record claimed twice carries the value it is painted at right
  now, so a half-faded panel re-targeted mid-flight continues from the alpha on screen.

## Decision 8 — reduced motion: the flight is suppressed, the destination never is

`presenter.withAnimation` already installs **no records at all** under reduced motion — an explicit
branch, not "install and clear". All three properties inherit that untouched, and this is the
decision written down as the brief requires:

- **A fade** lands **instantly** at its destination alpha. The end state carries every fact; the
  travel was pure continuity, which is the `decorative` class (ADR-0022 Decision 1). Nothing is
  hidden, so information parity holds trivially.
- **A scale** lands **instantly**, and is deliberately **not substituted by a cross-fade**. The HIG
  reflex of preferring a cross-fade to a zoom exists because the zoom *is* the motion; deleting it
  outright is strictly less motion than replacing it with a different animation. A framework that
  answered a suppressed scale with a new fade would be adding motion in the name of reducing it.
- **A rotation** lands instantly, same reasoning.
- **An authored value that never changes is not motion**, and reduced motion does not touch it. A
  badge declared permanently at `rotation = 15` stays rotated; a watermark declared at
  `opacity = 0.3` stays at 0.3. Reduced motion is a policy about *travel*, and a constant does not
  travel.

The one thing this does not cover is the `informational` category — a spinner's rotation, a ring's
sweep. Those are controls that own their own motion through the motion clock (round 3's circular
`ProgressView` is the live example), they already keep advancing on the quantized tick under reduced
motion, and nothing here changes them: they never route through `withAnimation`.

## Decision 9 — the off-path cost is zero, and it is gated rather than asserted

The sensory-feedback mission found `mount` reading a channel unconditionally and gated it. Same
shape here:

- The renderer keeps an integer count of paths carrying an authored presentation value.
  `pushPresentationPaint` short-circuits on `authoredCount == 0` **before** any table lookup, and
  returns the channel value **by identity** — same table, no allocation, no comparison of fields
  that cannot have changed.
- A node that declares none of the three never enters the `authored` map and never enters that
  count. A surface that declares none of the three anywhere pays **one integer compare per
  presentation write**, and a frame with no presentation write pays nothing at all.
- Nothing new runs at mount, in the solver, or in the layout walk. The props are `paint`-class dirty
  and touch no measure or arrange path.

## Consequences

- **Three new blueprint props.** `scale` and `rotation` are shared box props on every rendered
  class; `opacity` is on `Box` and `ZStack`. All three are reactive, `dirty = { "paint" }`,
  `channel = "presentation"` — the first authored props in that channel, and the reason the schema's
  channel vocabulary grows by one name.
- **`withAnimation` now reaches an authored paint value**, which is the capability the director
  asked for and the thing §8.1 recorded as impossible until an authored prop existed.
- **A node carrying an authored `scale` or `rotation` writes a presentation transform, and
  `adapter.park` refuses to recycle a node with one.** So such a node opts out of instance
  recycling. Named here rather than discovered later: put an authored rotation on a virtualized
  list's rows and those rows stop being pooled.
- **Scale and rotation move no layout, no hit geometry and no focus.** LuauUI hit-tests solver
  rects, so a rotated button's tap target is its unrotated box. This matches Apple, who is explicit
  for both: `rotationEffect` *"has no effect on the view's frame"* ([SW-146]) and `scaleEffect`'s
  dimensions *"are considered to be unchanged by scaling the contents"* ([SW-147]).
- **OWED, and measured rather than suspected: an authored `scale` on a `Button` does not survive a
  press.** The engine honours exactly one `UIScale` per object, so the authored scale writes the
  same instance the press dip tweens. The dip tweens it to `style.extra.pressedScale` on
  `MouseButton1Down` and its recovery tweens it back to **`1`** on `MouseButton1Up` / `MouseLeave` —
  an absolute target, so the authored value is gone from that release onward and nothing re-asserts
  it (the renderer's write is memoized on the composed value, which has not changed).

  **This is a pre-existing hazard that an authored scale turns from rare into certain**, and the
  file already says so in its own words: the recovery deliberately reads only the dip's own
  `handle.uiScale` because *"a button released while a pop or an enter transition is live would have
  its presentation scale snapped to 1, and nothing re-asserts it"*. That mitigation is not enough
  once the scale is permanent rather than transient.

  **The fix is small and named**: record the composed resting scale on the handle when the
  presentation paint is applied, then make the dip's target `resting × pressedScale` and its
  recovery target `resting` instead of `1`. It is **not made here** because both call sites live in
  `src/client/screen_paint.luau`, which on 2026-08-14 is an uncommitted in-flight extraction owned
  by a concurrent agent — editing another agent's unstaged file is exactly how this session lost
  work four times. It is booked as a device-round item, and `api.md`'s `scale` row says so, so no
  author meets it without warning.
- **`opacity` is not offered on a leaf** (Decision 4). The spelling is one `UI.ZStack` wrap, and the
  parity doc, `api.md` and the guide all say so in the same words.
- **A HAND-OFF, not a decision here: an authored `opacity` is a fact any future
  cross-surface overlap diagnostic must read.** A separate question is open (2026-08-14) about
  detecting that two independently-mounted surfaces cover each other — a HUD under a debug
  overlay, which ADR-0025's collision alarm cannot see because it works *within* one
  composition. That is not this ADR's business and is not stretched to cover it. But whoever
  takes it inherits a new fact from this one: **a node or surface at `opacity = 0` occupies its
  box and covers nothing visible**, so a diagnostic that keys on geometry alone would report a
  collision a player cannot see. `opacity` belongs beside `hidden` in whatever "this is not
  covering anything" set that diagnostic ends up reading.
- **A `drawingGroup`-style rasterization is still not on offer.** Declaring an opacity buys grouped
  alpha and a render buffer, never a cached bitmap — the half of [SW-134] the `canvasGroup` row
  already records as missing.
