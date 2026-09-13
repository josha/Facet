# Facet transitions round — design (2026-09-12)

Status: DRAFT for owner review. Nothing built yet.

Source of the catalog: transitions.dev (32 free transitions + its `_root.css`
tokens). Source of the inventory: an audit of `src/motion`, `src/present`,
`src/render/transitions.luau`, `src/render/presentation_channel.luau`, and every
control under `src/controls`.

## 1. What Facet already has (do not rebuild)

| transitions.dev item | Facet today | Verdict |
|---|---|---|
| Modal open (scale .96 + fade) | `transition = "materialize"` exists (`render/transitions.luau:46-52`) but **Alert never passes it** (`controls/alert.luau:613-616`) | wire it |
| Menu dropdown scale-from-anchor | `materialize` + `pivot` exist; **plain Menu never passes a transition** (`controls/menu.luau:844-858`) | wire it |
| Panel reveal (slide + fade) | `slide-up/down/left/right` + `fade` on `When`/`ForEach`/`present*` | have |
| Tabs sliding pill | `SelectionIndicator` four-spring slide via `Picker`/`TabView` | have |
| Page side-by-side | `NavigationStack.spec.transition` push/pop | have |
| Toast rise + fade | `presentToast` default slide-from-edge + fade | have |
| Card resize | `presenter.withAnimation` (paint-only rect travel) | have |
| Counter / number change | `clock:counter`, `motion.newValueReveal` | have |
| Loader | `ProgressView` indeterminate glide | have |
| Button hover lift / press dip | native-sheet `transitions` + bespoke `screen_paint` tween, `pressedScale 0.985` | have |
| Enter slower than exit | **not a default** — one `class` drives both directions | add |
| Accordion | `DisclosureGroup` has zero motion | add |
| Toggle thumb overshoot | `Toggle` has zero motion | add |
| Error shake | nothing | add |
| List stagger | `transition` has no `stagger` field (`blueprint_schema.luau:173-181`) | add |
| Icon swap cross-fade | nothing; achievable as a keyed `When` recipe | recipe first |
| Text-state swap | achievable as a keyed `ForEach` + `slide-up` recipe | recipe only |
| Skeleton pulse | `AsyncImage` has no placeholder motion | Tier 3 |
| Blur on any transition | impossible: Roblox has no per-GuiObject blur | never |
| Card tilt, particles, digit reels, morph, streaming/AI text | pointer-3D, extra Instances, or AI-specific | never |

Existing timing scale to reuse: spring classes `container` (0.35s), `object`
(0.28s), `reward` (ζ0.7, 0.18s), `decay` (0.5s) in `motion/classes.luau:67-72`;
theme durations `motion.fast = 0.12`, `motion.normal = 0.2` in
`tokens/default_style.luau:100`. transitions.dev's scale (150/250/350ms, exits
faster) maps onto these without new tokens except one (see 2C).

## 2. What to add

Everything below is **paint-only**: it moves through the presentation channel
(`offset`/`scale`/`rotation`/`opacity`, `render/presentation_channel.luau:292`)
and never touches the solver. Every item is decorative under reduce-motion
(invariants I-1..I-4 in `motion/motion.luau:31-46`): instant placement, same
settle event, same frame.

### Tier 1 — wiring only, no new machinery (sonnet)

- **1A Alert entrance/exit.** `presentModal` opts gain
  `transition = { enter = "materialize", exit = "materialize", class = "object", exitClass = "dismiss" }`.
  Scale 0.96→1 + fade in; faster dip out. Spec field `transition?` added to
  `AlertSpec` so a caller can override, or pass `{ enter = "instant" }` to opt
  out. (A bare `"instant"` is not a transition declaration; `Alert.build`
  refuses it by name — task 7 item 5.)
- **1B Menu dropdown.** `presentAnchored` in `controls/menu.luau` passes
  `materialize` with `pivot` set from the resolved anchor side (top-left for a
  menu that opens downward, etc.). Same asymmetric exit.
- **1C Enter/exit asymmetry.** Register a built-in spring class `dismiss`
  (ζ1.0, ~0.15s). `transition` gains an optional `exitClass`; when unset the exit
  uses `dismiss`. **This is the one deliberately visible change** to existing
  callers: every `When`/`ForEach`/toast/surface exit gets ~40% faster. Owner
  call: default-on (recommended) or opt-in.
- **1D Ten-foot focus lift springs.** `screen_target.luau:3076,3261` writes the
  `UIScale` 1.05 focus lift instantly. Drive it with an `object` spring so pad
  focus travel breathes. One spring alive only while focus is moving.
- **1E Toggle.** Thumb travel becomes a spring (`reward`, small overshoot,
  matches the site's `(.34,1.35,.64,1)` feel) on the thumb's presentation
  offset; layout lands instantly underneath. Track colour already crossfades
  through the native sheet `fast` transition.

### Tier 2 — small new primitives (opus for F/G/H, sonnet for I/J)

- **2F `stagger` on list transitions.** `transition.stagger?: number` (seconds
  per item, default 0) on `ForEach`/`When` groups. Item *i* starts its enter
  after `min(i, 8) × stagger`. Cost is delayed starts, not more springs; the
  cap keeps a 600-row list from queueing 600 timers. Exit never staggers.
- **2G Radial + button pops.** RadialMenu: wedges bloom on open (scale
  0.92→1 with `stagger = 0.02`, total ≤120ms — the radial design doc forbids
  long staggers), the wedge under the pointer lifts 1.04 (one spring, moves
  with the pointer), and a selected wedge pops 1→1.08→1 via `reward` before
  the menu closes. Button: a `pop = true` spec option adds the same release
  overshoot for reward-role buttons (the press dip already exists).
- **2H `presenter.shake(path)`.** A four-leg timeline on presentation offset x
  (±8px, 80/60/60/40ms). `TextInput` gains `invalid: Signal<boolean>?`; a
  false→true edge shakes and the existing error tint is the informational
  channel, so reduce-motion drops the shake and keeps the tint.
- **2I DisclosureGroup.** Chevron rotates 0→90° via a `rotation` spring;
  content enters with `slide-up` + fade; the toggle runs inside
  `withAnimation("container")` so siblings below glide instead of jumping.
- **2J Icon swap.** Document the keyed-`When` cross-fade recipe. Only if the
  recipe reads badly in the showcase, add `Button.iconTransition = "fade"`.

### Tier 3 — booked, not built this round

AsyncImage skeleton pulse; banner stacking (toast queue recede); success-check
bob. Each needs its own perf row; none is asked for by a shipped Rascal Rally
screen.

### Recipes (docs only)

`docs/guide/15-adaptive-recipes.md` gains: text-state swap (keyed `ForEach` +
`slide-up`), card resize (`withAnimation`), icon swap (keyed `When` + `fade`).

## 3. Performance guardrails (the part that is not optional)

1. **Paint-only law, pinned.** A new spec `motion_paint_only.spec.luau` runs a
   toggle flip, a shake, a wedge pop, a disclosure open, and a 30-row staggered
   mount, and asserts the solver's solve count is unchanged by the motion and
   that no `Size` write occurs — only `offset`/`scale`/`rotation`/`opacity`.
2. **Zero new Instances.** No item above materializes an Instance for motion.
   Icon swap (2J) may stack two images for one transition; that is the only
   allowed exception and it is bounded at one.
3. **Idle is free.** After settle, `clock.steps` stops advancing `writes` for
   every new value. Pinned in the same spec (`writes` delta = 0 across 60 idle
   steps).
4. **Bench.** Before each tier lands:
   - `tools/perf.sh` must pass, **and** no existing scene's `observed_p95_ms`
     may move more than +10% (the gate's 4× trend budget is too loose to catch
     a real regression). `picker-menu-open-close` and `radial-menu-open-close`
     are the sensitive rows: they price a transition's first ticks.
   - New scene `control-motion` in `bench/perf_scenes.luau`: 40 toggles
     flipping, 8 wedge pops, 1 shake, one 30-row staggered list, one scripted
     clock step per iteration. Baselined with
     `lune run tools/lune/perf_baseline_scene control-motion`, and the
     `motionSteps == motionTransactions` invariant added to
     `tools/check_perf_scenes.py` for it (one commit per stepped frame).
   - `tools/verify.sh full` green (perf is a producer node in `full`, not
     `--fast`).
5. **Rascal Rally moves with Facet.** Per the root constitution: run the RR
   suite, add or update an RR contract test for 1C (exit timing) and 1A
   (Alert transition), and run one Studio canary on a screen that opens an
   Alert and a Menu. FacetBench does not see motion (no workload exercises it);
   no FacetBench change this round.
6. **Renderer cap.** `render/renderer.luau` sits at 196,755 chars of the 200k
   write cap. No change lands in it. `render/transitions.luau` (28.5k) is the
   only render file 2F touches.
7. **Exit cap.** The 500ms disposal cap on structural exits stays.

## 4. Order and routing

| Step | Items | Model | Gate |
|---|---|---|---|
| 1 | 1A 1B 1C 1E | sonnet, one subagent per item | suite + `tools/perf.sh` + ±10% check |
| 2 | 1D | sonnet | Studio pad canary (ten-foot) |
| 3 | RED-TEAM Tier 1 | code-reviewer (opus) | findings fixed |
| 4 | 2F 2H | opus | `control-motion` scene baselined |
| 5 | 2G 2I 2J | opus (2G), sonnet (2I, 2J) | showcase capture review |
| 6 | RED-TEAM Tier 2 + RR canary + recipes | code-reviewer (opus), sonnet for docs | `tools/verify.sh full`, RR suite |

Each step is one worktree commit; captures for the showcase go through the
creative-director review as usual.

## 5. Owner decisions (ruled 2026-09-12)

1. **1C default.** Faster exits everywhere by default. `exitClass` defaults to
   `dismiss`; a caller opts out per call.
2. **Scope.** Tier 1 + Tier 2 this round. Tier 3 stays booked.
