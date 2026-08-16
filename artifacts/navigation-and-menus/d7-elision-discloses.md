# D7 — elision must DISCLOSE, not delete

**Principle.** Adaptation may change **how much** of something is shown, and may
change **what it costs** to reach it. It may not change **whether it can be
reached at all.**

The rank ladder was never missing and never broken. `layoutPriority`
(`src/layout/shrink.luau`) and the `UI.Region` rank ladder (ADR-0025) both ship,
and the HUD prints its own ladder on screen — it was doing exactly what it was
told. **What it lacked was any notion of where the elided content went**, so from
the player's side "step down" and "delete" were one operation.

## The red, before anything was built

The D7.6 sweep run against the unmodified fixture — nine swept viewports
(`tests/lib/device_views.VIEWS`) × two URL-bar states, under the showcase's own
chrome reservation:

```
TOTAL elided-or-dropped occurrences: 39; with a declared recovery route: 0; WITHOUT: 39
```

Every one a dead end. The live baseline that commissioned it is
[`d7-hud-baseline.md`](d7-hud-baseline.md).

## What shipped

### D7.1 — the `recover` contract, and the seam

`RegionDecl.recover` is a closed spec: `"none" | "self" | "overflow"`.

| | |
|---|---|
| **Required** | on a region with **more than one form** (`composition.normalize`) |
| **Refused** | on a region with **one** form (`blueprint.Region`) |
| `"none"` | every form below the richest still shows everything — a poorer *layout*, not less content. It has to be **written**: silence is not consent |
| `"self"` | the reduced form **is** the route; the player taps what is left |
| `"overflow"` | the screen's overflow surface is the route, and it reads `Resolution.unshown` |
| refused | `"none"` together with `mayDrop` — dropping shows nothing, so "nothing is lost" is not a claim available to it |

**Required, not defaulted, and the reason is the brief's own: silence is not
consent.** A defaulted `recover` would mean every existing declaration silently
claimed a route it had never thought about, which is the accepted-and-ignored
class the strict boundary exists to remove. It is required **where it means
something** and refused where it does not — a one-form region can only stop
showing content by being *dropped*, and a dropped region has no form left to be
its own route, so the sink is the only possible answer and a key with one legal
value is ceremony. `mayDrop` is already that declaration.

**The two halves live in different places, and that placement is a
measurement.** `forms` reaching the solver is the count of **mounted** forms, and
a form behind a `UI.When` is absent while its condition reads false — the
`composition` showcase declares two `When` forms per region and solves with one
of them for most of its states. So the *required* half is the pure normalizer's
(it must hold for a declaration driven straight from a test) and the *refused*
half is `UI.Region`'s, where the count is the DECLARED one. Putting both in the
normalizer rejected three good declarations on the frame a condition flipped.

Additive on the resolution:

```lua
RegionResolution.elided  -- a form below the richest was chosen; false when dropped
Resolution.unshown       -- { { id, reason = "dropped"|"elided", route = "overflow"|"self" } }
```

`unshown` is in **declaration order** (the same order as `regions`) and is **the
seam**. A DROPPED region's route is always `"overflow"` whatever its `recover`
said. Both appear in `composition.dump`, and both are empty/`false` on every
declaration that resolved cleanly before this shipped, which is what makes them
additive.

### D7.2 — a terminal form must be actionable

`recover = "self"` is checked at construction against **every form below the
richest**, not only the last one: the ladder can stop at any rung, so checking
only the terminal form leaves a dead end on exactly the middle-sized devices
nobody fixtures (mutation M10). In the fixture this turned **two** nodes into
Buttons — `TasksChip` (was `glass(…)` wrapping an `HStack` of `UI.Text`) and
`TasksOneBody`.

### D7.3 — the overflow sink, and the host finding

The baseline's finding 1: **the `…` button was itself dropped** — `@(8,138)
36×36 vis=false` in exactly the state that needs it. Measured cause, and it is
worse than "not rank-1": `R3c` lived in `RoundColumn`, a **form** of a two-form
region, and that form **was never chosen at any swept viewport**. The round strip
had been showing two of its three buttons for the fixture's whole life.

The repair is structural rather than a rank bump:

- `Rounds` is now **one form** — an `HStack{ wrap = true }` of three discs. One
  form means `recover` is refused on it, which means it **cannot elide**; it
  declares no `mayDrop`, so it cannot drop; it is rank 1. `wrap` is the
  framework's own answer to the measurement the old comment recorded (three
  compact discs plus gaps are 120px in a 119px lane at 359px): the row wraps to
  two lines where the lane is narrow and stays one line where it is not, at every
  width, with no ladder and no device branch.
- The third disc is the sink's trigger. Its 36px disc still delivers a **44px hit
  rect** — `Button` carries a `minHitSize` clamped up to `targetSizes.minimum` —
  which is the three-axes floor this affordance owes on touch.
- The sink is a **content panel on D1's `presenter.presentAnchored`**, not a D2
  menu: a menu item RUNS something, and "the score is 12–9" runs nothing. Tap-away
  rides the shipped `contribution.outsideDismiss` seam with `consume = false`.
- It costs **zero** while closed: the panel is a transient anchored surface with
  its own controller, so the HUD's own node count is unchanged by its existence.

### D7.4 — the re-rank, and the half a re-rank cannot fix

| | was | now |
|---|---|---|
| fps readout | 7 | **9** — first to give way |
| kill feed | 9 | **8** |
| tasks | 8 | **7** |

Measured live with the URL bar open at 749×380: `60 FPS · 42 ms` was on screen
while all three tasks, their rewards, the health figure and the kill feed were
gone.

**The scores are a case no re-rank could have fixed**, and this is the finding
worth keeping. `12`/`9` are lost when `Clock` steps down; `Clock` is in the
**centre** lane and the fps readout is in the **right** one, and rule 3 spends
only the currency of the lane that does not fit. No ranking makes the right lane
pay the centre lane's deficit. The scoreboard's recovery is the disclosure route
— `recover = "overflow"` — which is exactly what "tap for detail" is for.

### D7.5 — the URL-bar constant, split and re-measured

`URL_BAR_PX = 200` was commented as *"a fact about the SCREENSHOT"* — never
measured — and did two jobs: the height the chrome **steals** and the height the
pseudo bar is **drawn at**. An over-stated steal therefore also painted an absurd
box: measured at 749×380 the bar came out **733×158**, 42 % of the viewport, a
near-empty slab with one line of grey text adrift in it.

**How it was measured.** Chrome **151.0.0.0** on macOS (this machine), 2026-08-16.
A local HTTP server served a page that reported its own `window.outerHeight -
window.innerHeight` back over `fetch`, from two window kinds. (`outerHeight` reads
**0** in Chrome 151 until the window is focused — the first attempt returned
`-419` and was discarded; the measurement below is from a run that delays the
report until after focus.)

| window | outerHeight | innerHeight | chrome |
|---|---|---|---|
| normal window (tab strip + toolbar) | 1274 | 1131 | **143 px** |
| popup window (location bar, **no** tab strip) | 486 | 419 | **67 px** |

The fixture models the **67**, and that choice is the point: a tab strip does not
*appear* — it is always there. What appears and disappears, which is the whole
event this toggle exists to model, is the location-bar row. **200 was three times
it.**

The second job is now a **theme metric, not a constant**: the band is still drawn
at exactly the height it takes (the 2026-08-15 "the picture and the geometry are
one number" ruling, preserved and asserted), but the **field** inside it is a
control, so its box comes from the control-size ladder. That is what stops an
over-stated band from ever painting an empty slab again, at any band height.

> The live-browser probe was used because the round's reference media
> (`hud-a/b/c`) is **the fixture's own screenshot**, not a browser — measuring it
> would have re-derived the number it was supposed to replace. The
> `claude-in-chrome` MCP path was not used: it requires an interactive
> browser-selection prompt, and the execution contract's autonomy rule assumes the
> user is unavailable.

### D7.6 — the sweep

`tests/elision_recovery.spec.luau`, registered in `tests/run.luau`. At every
viewport in `tests/lib/device_views.VIEWS`, in **both** URL-bar states, every
entry in `resolution.unshown` must have a **live** route:

- `"overflow"` → the sink node is **`visibleOf` true**. Not "declared", not
  "present in the tree": a dropped region keeps its mount and the adapter writes
  `Visible = false` down the subtree, so "the node exists" is exactly the check
  that would have passed on the broken fixture.
- `"self"` → the region is standing and something focusable inside it is visible.

Plus a floor (`>= 20` occurrences swept, and at least one drop and one elision),
so a check that proves nothing can never pass — and `fallback = false` /
`collisions = 0` at every row.

## After

```
narrow-landscape 640x320 url:open   sink=true fallback=false
  Tasks:dropped->overflow, Feed:dropped->overflow, Clock:elided->overflow,
  Rail:elided->overflow, Actions:elided->overflow
...
TOTAL elided-or-dropped occurrences: 36; WITHOUT a route: 0
```

## The baseline's "fourth failure class" — refuted, with arithmetic

`Round 3 · Capture @(416,-37) 81x15`, read as a node painted entirely above the
top of the viewport. It is not.

A LuauUI ScreenGui renders `IgnoreGuiInset = true`, and `AbsolutePosition` on such
a tree is reported in the **inset-subtracted** space. The headless twin, driven at
the same 749×380 with the same chrome facts, puts the same node at **window y 21,
h 15** — inside the platform's 0..58 band, where ADR-0027 requires it. `21 − 58 =
−37`, against the session's own measured 58px inset.

Two independent corroborations, both from the baseline's own numbers:

1. **The x agrees exactly.** Live `x=416 w=81` → centre 456.5. Headless `x=393
   w=127` → centre 456.5. The free band is `x 164..749`, centre **456.5**. Both
   are perfectly centred in it; only the widths differ (text metrics).
2. **The baseline reports other nodes at `y = -58`** — `Tasks 1/3` `@(18,-54)`,
   health `84` `@(20,-54)`, the kill feed `@(8,-58)`. Those are hidden nodes
   parked at the composition's origin, i.e. **window y 0**. A capture in which
   window-space 0 reads back as −58 is a capture with a −58 offset.

**Disposition: not a defect, and not booked as one.** What is booked is the
reading trap, as an addendum to
`docs/lessons/injected-mouse-coords-are-gui-space.md`, and a durable regression
that pins the objective chip inside the band **at the baseline's own 749×380**
(the existing ADR-0027 case covers 735×413).

## GuiObject count — the A/B

The pre-D7 fixture was read out of `HEAD` and mounted with **only `recover` props
added** (a prop creates no node, so the tree is otherwise byte-identical), through
the same harness at the same viewports:

| | adapter nodes | elided | engine-backed | elision ratio |
|---|---|---|---|---|
| before | 144 | 56 | 88 | 38.9 % |
| after | **138** | 52 | **86** | 37.7 % |

**−6 nodes, −2 engine-backed**, identical at 749×380, 320×640 and 1232×1067. The
HUD got *smaller* while gaining a disclosure route: the never-chosen `RoundColumn`
form and its three discs left, the chip's four-node glass pill became one Button,
and the sink's own disc plus the URL field's plate are what came back. **The sink
adds nothing while closed** — it is a transient anchored surface with its own
controller.

## The Studio canary — real engine, 2026-08-16

**Preflight.** Studio instance `LuauUI-Showcase.rbxl`, Play (client DataModel),
viewport **749 × 380** — the baseline's own size. The place was **stale** (it still
held `pill("TasksChip", …)`) and the Rojo plugin was not connected, so the six
changed modules were pushed into the datamodel over a local HTTP fetch, the same
technique ADR-0025's own canary used, and each write was verified by byte count:
`hud 79365 · composition 90454 · blueprint 82034 · blueprint_schema 112046 ·
layout_node 49296 · solver 179858`. Source-state confirmed after the push
(`URL_BAR_STEAL_PX` present in the datamodel's copy). Fixture reached with
`LuauUIShowcaseAPI.showNext` until `{"mounted":"hud","current":"hud","ok":true}` —
**`mounted`**, not `current`. `HttpService.HttpEnabled` was restored to `false`
afterwards.

**Confirmed live, on the real engine:**

| | |
|---|---|
| the sink's disc | `…/Rounds/RoundStrip/R3` `[TextButton] 36×36` **`vis=true`** — with the URL bar **closed AND open**, which is exactly the state where the pre-D7 `…` was `vis=false` |
| its touch floor | three `LuauUIHitExpander` `[TextButton] 44×44` under the strip, one per disc — the three-axes floor, measured rather than argued |
| the dead form | `RoundColumn` and `R3c` are **absent from the tree**: the form the ladder never chose is gone, not hidden |
| the task chip | `…/Tasks/TasksChip` is a **`TextButton`** (it was a ZStack pill) |
| the URL bar | plate **733×67** — was 733×158 — with the field's own plate **713×36** inside it, the control-size ladder's box rather than a slab |
| Activate | one calibrated tap on `R3` routed to `Touch @110,72` (its own centre) and fired the engine's `Activated` **exactly once** — no double-dispatch between the host and its expander |

**...and the "fourth failure class" refutation, confirmed on the engine itself.**
`/HudScreen/UrlBarWhen` is a zero-size structural node at the Screen's own origin
— window y **0** — and it reports `AbsolutePosition = (0, **-58**)`. That is the
inset-subtracted space, live, with nothing to do with layout.

**Not closed: the panel's live mount.** No input class in this session reached
LuauUI's own Activate dispatch. The engine received the tap (routed `Touch` at the
button's own coordinates, `TextButton.Activated` fired once) and `Tab` produced no
focus ring at all — this is a touch-booted device-emulator session, whose injected
coordinates needed a **measured −62px x calibration** (`injected (300,200) → routed
(238,200)`, discovered rather than assumed, per
`docs/lessons/injected-mouse-coords-are-gui-space.md`). No anchored surface
appeared anywhere in the client DataModel, and the console carried no error.

The panel itself is proved headlessly through the real adapter — `the sink OPENS
and lists the content the screen is not showing` asserts the mounted panel carries
the task list and the kill-feed line, and the pseudo-localized case mounts it with
zero solver findings. **What remains open is one row: an anchored surface mounting
under a real engine tap.** It is booked rather than claimed, and it is not
attributed to the instrument: the evidence is equally consistent with the
emulator's input classification and with a defect on the live activation path, and
this session could not tell them apart.

**Procedure to close it:** connect the Rojo plugin (`rojo serve` is already
running on the showcase project) so the place is not stale, run Play on a
**desktop-booted** session rather than a device-emulator preset — where an injected
click arrives as `MouseButton1` and needs no offset — reach the `hud` fixture with
`showNext`, tap the third round disc, and assert a `LuauUI_HudOverflow` ScreenGui
appears carrying the `Hidden right now` title and one row per entry of
`resolution.unshown`.

## Mutation ledger — 14 run, 14 bite

Two of them did **not** bite on the first pass, and both were real holes in the
tests rather than in the code:

- **M6** — `elided` on a dropped region. The case ran at `h = 150`, where the only
  dropped region has ONE form, so `elided = false` was arithmetic rather than a
  decision. Moved to `h = 100`, where the ladder steps `C` down *and then* drops
  it: the only state in which the two flags can disagree.
- **M8** — the `"none"` region's absence from `unshown`. The case ran at `h = 300`,
  where the `"none"` region has not stepped down at all, so its absence was true
  for the wrong reason. Moved to `h = 200`, where all three have stepped.

| # | mutation | expected to break | result |
|---|---|---|---|
| M1 | `recover` defaults silently | `REQUIRES recover` | **RED** |
| M2 | a one-form region may declare `recover` | `REFUSES recover on a one-form region` | **RED** |
| M3 | an unknown route is a silent no-op | `refuses an unknown route` | **RED** |
| M4 | `"none"` together with `mayDrop` is accepted | `refuses "none" together with mayDrop` | **RED** |
| M5 | `elided` is never set | `a stepped-down region reports elided` | **RED** |
| M6 | a DROPPED region also reports `elided` | `a DROPPED region is elided = false` | **RED** |
| M7 | the unshown list omits a dropped region | `a dropped region's route is ALWAYS overflow` | **RED** |
| M8 | the list keeps a `"none"` region too | `the unshown list OMITS a recover = "none" region` | **RED** |
| M9 | a dropped region routes by its declared `recover` | `a dropped region's route is ALWAYS overflow` | **RED** |
| M10 | only the LAST form is checked for a `self` route | `...and a MIDDLE form too` | **RED** |
| M11 | a terminal form with nothing focusable is accepted | `refuses a LAST form with nothing focusable` | **RED** |
| M12 | the sink's host is droppable and low-ranked | `sweeps the device matrix` | **RED** |
| M13 | the task chip goes back to an untappable pill | `the sink OPENS` | **RED** |
| M14 | the URL bar keeps the screenshot's 200px | `the drawn bar is the height it steals` | **RED** |

## Migration — 51 declarations

`recover` is a **breaking change to every Region author with more than one form**.
Every one was migrated by reading its two forms and stating what is true of them,
never by defaulting:

| where | sites | notes |
|---|---|---|
| `examples/gallery/scenarios/hud.luau` | 5 | `Rounds` became one form; `Tasks` is the `"self"` route |
| `examples/gallery/scenarios/composition.luau` | 11 | four `"none"`, seven `"overflow"` |
| `examples/reference/p2_cartwheel` (shell, workbench) | 2 | the icon rail carries every destination the full list does → `"none"` |
| `tests/composition.spec.luau` | 17 | |
| `tests/hud_composition.spec.luau` | 9 | |
| `tests/hud_chrome_rotation.spec.luau` | 1 | |
| `tests/large_text_layout.spec.luau` | 2 | |
| **RascalRally** `ResultsScreen.luau` | 18 (9 × 2 blocks) | see below |

**RascalRally's two `"none"` declarations are the interesting ones**, because both
are true for a *measured* reason rather than by inspection:

- `Recap` — the reduced form carries LuauUI's `reveal = "auto"` (LTN-8), so the
  **whole** tally slides through the one line it rests on. The rich form wraps it
  to four; the short form scrolls it. Same sentence.
- `Ledger` — one `economyBody("Ledger", …)` builds both forms, a row and the same
  content stacked. No fact leaves the screen with the axis.

## Residual — booked, not closed

- **`recover = "overflow"` declares that the *screen* owes a route; it does not
  prove one exists.** The D7.6 sweep proves it for the HUD showcase. The
  `composition` scenario, `p2_cartwheel`'s workbench and **RascalRally's results
  screen** now declare `"overflow"` on regions whose surfaces build no disclosure
  plate. That is not a new defect — it is the *existing* one, made visible in
  `resolution.unshown` instead of silent. Building those sinks is a product change
  on a shipped game surface and nobody authorised one. The natural next step is to
  extend the D7.6 sweep to the whole showcase corpus and let it name them.
- **PENDING_PHYSICAL.** The sink's touch tap and its gamepad reach are headless
  and Studio-checkable only up to the point the execution contract allows; a real
  touch on a real device remains a physical row.
