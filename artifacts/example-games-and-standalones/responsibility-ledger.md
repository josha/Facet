# Responsibility ledger — stage `example-games-and-standalones`

Written **before** editing, as the binding plan requires.

The line: **examples own game rules, content, deterministic fixtures, teaching copy,
and declared composition. Facet owns reusable layout, focus, input, adaptation,
accessibility, theme, motion, transition, resource, and lifecycle behavior.**

When a piece of work needs something Facet does not have, the fix goes into Facet
behind a public API and the example consumes it. It does not go into an example-only
tween, geometry loop, input branch, or raw GUI helper. This file records every such
call, with the evidence that decided it.

Step 13 has already reviewed the release candidate, so the default is example-only
change. The one declared exception is the `SurfaceGui` render-target seam, which the
plan authorizes by name.

---

## 1. Where each piece of this stage lands

| Work | Owner | Why | Public API it consumes |
|---|---|---|---|
| Five-letter dictionary data and its generator | **Example** | Word lists are content. A UI framework has no opinion about English. | — (data module) |
| Word validation (is this an accepted guess?) | **Example** | A game rule. | — |
| Two-pass duplicate letter scoring | **Example** | A game rule. | — |
| Board cell chrome, the active-row cue, the next-letter cue | **Example composition over Facet paint** | The *decision* to mark a cell is content; the *paint* is a theme role Facet already resolves. A tint that resolves to the surface's own value paints nothing, so the example must ask for a role that differs, not invent a colour. | `UI.Box` tint roles, `UI.ZStack`, theme roles |
| Crossword placement, connectivity, scoring, bag, turn budget | **Example** | Game rules. The plan says so explicitly: "do not put crossword rules in Facet". | — |
| Crossword board and rack navigation | **Facet** | Grid focus and directional navigation is framework behavior every consumer needs. | `NavigationGroup`, focus graph, `UI.Grid` |
| Match-3 board logic, seeds, legal-opening guarantee | **Example** | Game rules. | — |
| Match-3 tile identity across a move | **Example declares, Facet honors** | The example says which tile is which (a keyed collection); Facet decides what that means for reuse and motion. | keyed `UI.Grid`/`ForEach` identity |
| Match-3 movement, removal, insertion, cascade timing | **Facet** | This is the reusable motion authority. The plan forbids an example animation system by name. | `presenter.withAnimation`, the public structural-transition system, the framework clock / completion seam |
| Match-3 input lock while resolving | **Example state, Facet affordance** | Whether the board is busy is a game rule; showing a control as unavailable is framework behavior. | control `enabled` / disabled affordance |
| Haptics waveforms for press, release, selection | **Facet** | They ship as the library's documented defaults. The example must not re-implement them — re-implementing proves the example, not the framework. | `sensory_profile.DEFAULTS` via the adapter |
| One custom waveform | **Example content through Facet's seam** | The waveform data is content; the mechanism is `sensory_profile.resolve` over a partial profile. The example constructs no `HapticEffect` and reaches no adapter internal. | `haptics.new({ profile = … })`, `sensory_profile.resolve` |
| The demo's "start with haptics on" choice | **Example** | A demo choice. Facet's library-level contract stays game-opt-in and its separate tests stay untouched. | `haptics.new`, `adapter.setEnabled` |
| The visible event history and phase readout | **Example** | Teaching surface. | `presenter.onFeedback` |
| Outpost Power Terminal: power rules, budget, world fixture, copy | **Example** | Game rules and content. | — |
| Outpost Power Terminal: the `SurfaceGui` render target | **Facet** | A render target is a framework capability with a declared contract and a declared future entry. This is the plan's one authorized framework addition. | new `src/client/surface_target.luau` |
| Walk-up invitation | **Neither — the engine** | `ProximityPrompt` is the native, cross-input affordance. Facet does not wrap it and the example does not hand-roll it. | Roblox `ProximityPrompt` |
| Terminal input routing (keyboard, gamepad) | **Facet** | The semantic Input Action System is the one input authority. The example binds nothing through `ContextActionService` or `UserInputService`. | responder / focus scope, IAS actions |
| Server validation of a power change | **Example** | Game authority rules. | — |
| Theme picker and Full/Reduced control | **Example chrome, Facet mechanism** | The picker is showcase chrome — a shipping game chooses its theme rather than offering the player five reference packages. The *swap* is Facet's. | `theme_controller`, `env:set("reducedMotion", …)` |
| The place manifest | **Example/build infrastructure** | It describes examples, not framework behavior. | — |

---

## 2. Framework calls this stage makes (filled in as they are decided)

Each row records a need the examples could not meet from the public surface, what was
changed in Facet, and the evidence that the change is general rather than a game
policy in disguise.

| ID | The need | Decision | Public API added or changed | Rascal Rally impact | Evidence |
|---|---|---|---|---|---|
| FW-1 | Two-dimensional Facet UI must materialize on a world part players can walk up to and use. | **Change Facet.** `target_contract.FUTURE.surface` already declares this target and its open questions; the plan authorizes shipping it. | `src/client/surface_target.luau` — a thirteenth blessed client entry point, built on the existing root-factory seam the billboard target already uses. No second renderer, no `SurfaceGui` branch in any control. | None expected: the game mounts no world surface. The deliverable is an audited consumer-impact ledger plus game-side compatibility evidence, not a manufactured edit. | To be recorded: the Studio spike, the adapter spec, the capability ledger. |

| FW-2 | One control should be able to carry a different haptic waveform from its siblings — the plan asks the sensory demo for exactly that ("one control uses Facet's documented public override/profile seam"). | **Recorded, not fixed.** The override seam is real and public, but it is **adapter-wide**: `haptics.new({ profile })` resolves a partial profile over the defaults for all three phases at once, and there is no per-control route. So a demo that overrides on the installed adapter would move the very waveform the row beside it demonstrates. | None. The example composes around it with a **second adapter**, built through the same public `haptics.new({ profile })` and fed through `bind`'s own documented input shape — "something with an `onFeedback(fn) -> unsubscribe`". It is never bound to the presenter and never attached to a root, so nothing on the real bus can reach it and a duplicate pulse is impossible by construction rather than merely unobserved. The custom control declares `activation = "none"`, the documented silence. | None. | `tests/control_feedback.spec.luau` — the override adapter is proved unreachable from the presenter's bus, and the per-input-path pulse census shows exactly one release on each of pointer/touch/keyboard/gamepad. |

**Why FW-2 is recorded rather than fixed.** Two public calls to a public constructor
is composition, not a workaround: nothing reaches an adapter internal, nothing
re-implements a waveform, and on a device the override adapter genuinely plays — `bind`
is its documented input and the demo pushes a real cause onto it. What the example
cannot do is give one *button* a different feel through the property route, because
`attachButtons(root)` decorates every `GuiButton` under one Instance and an example is
given no Instance handle for a single control's subtree. That is the gap. It is worth a
per-control profile seam when a consumer needs one; the demo did not need the seam to
be honest, and this stage's instruction is to prefer example-only changes.

| FW-3 | A disclosure header should be able to follow a live locale change. Both apps' "What this shows" sections need one. | **Recorded, not fixed.** `Facet.Controls.DisclosureGroup` validates `label` as a plain `string` (`src/controls/disclosure_group.luau`), so it cannot take a reactive value and a locale flip leaves the header in the old language while everything under it changes. | None. Both apps hand-build the header from a `Button` and `UI.When` — public constructors doing exactly what the control would, one level down. | None. | Same class as the two findings these apps already record for `newLabel.title`; the pseudo-locale sweep is what makes it visible. |

**Why FW-3 is recorded rather than fixed.** It is a one-word type widening on a public
spec (`string` to a readable string), which is a public-contract change after Step 13's
release-candidate review, for a control neither game needs. It is also the *third*
recorded instance of one shape — a composite control accepting a plain string where the
rest of the surface accepts a readable — and three instances is a rule to change once,
deliberately, not three times in passing. Booked with its siblings.

*(Further rows are appended as the work finds them. A row is added the moment a need
is identified, not after the fix is written, so a workaround cannot quietly become the
answer.)*

---

## 3. Things deliberately NOT moved into Facet

| Temptation | Why it stays in the example |
|---|---|
| A "crossword" or "word game" module in `src/` | Game rules. The framework has no business knowing what a legal word placement is. |
| A per-example animation helper for the match-3 board | The plan forbids a second animation system by name. If `presenter.withAnimation` and the structural-transition system cannot express a step, that is a framework gap to fix in Facet — recorded in §2 — not a local helper. |
| A haptics waveform table inside the sensory demo | The defaults are the library's, and the demo exists to demonstrate *them*. Only the one deliberately-distinct custom waveform is example-owned, and it goes through the documented override seam. |
| A `SurfaceGui` branch inside a control, so the terminal's buttons behave differently on a part | A control that knows which target it is on is the failure the target contract exists to prevent. |
| Copying the showcase settings model into each standalone place | The plan requires reuse. A copy drifts, and the drift is invisible until two places disagree. |
