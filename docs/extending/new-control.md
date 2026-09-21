# Playbook: adding a new composite control

Audience: an agent (or developer) with NO prior context on this repository.
Follow the steps in order; every step has a command and a pass condition.
This playbook covers COMPOSITE controls — controls composed from the shipped
`UI.*` primitives (the way `Table` and `VirtualList` are built). A control
that needs a NEW engine instance class is an engine feature first: do
[new-engine-feature.md](new-engine-feature.md), then come back here.

Read [`../reference/constitution.md`](../reference/constitution.md) first — the
rules your addition must follow.

## 0. Ground rules

- Work from the library root: `GameStudio/ui/Facet` (all commands below
  assume it, and use absolute paths in shell commands — a relative path run
  against the wrong working directory is the single most expensive mistake
  recorded here).
- The scaffold and deterministic conformance toolchain run in Lune
  (`lune run …`). A player-visible control is not production-proven by Lune alone:
  follow §6 below, and read
  [`../guide/11-device-verification.md`](../guide/11-device-verification.md) for
  which instrument can close which kind of claim.
- Test-first is not optional: the scaffold stamps a FAILING spec on purpose.
  Never mark done while `./run-tests.sh` is red.
- **The fast loop is `lune run tests/run_one <spec-name>`** — one spec file,
  seconds instead of minutes. Use it while you write, and use it to watch a new
  case FAIL before you trust it. It cannot produce a suite verdict, so the full
  `./run-tests.sh` still decides green.
- Never edit `tools/lune/gate_manifest.luau` or `phases.json` for a control;
  the existing gate checks pick your work up through the suite and the
  registration checker. Gate rows derive their counts from the controls
  registry, so a control registered the way this playbook describes keeps them
  passing. **If you meet a gate row that a correctly registered control cannot
  satisfy, that is a defect in the row. Report it; do not edit it, and do not
  work around it.**

## 1. Scaffold the skeleton

```
lune run tools/lune/scaffold_cli control <lower_snake_name>
```

This stamps and REGISTERS everything, so that nothing can be forgotten. The plan reports the exact files it writes and edits:

| File | What the scaffold does |
|---|---|
| `src/controls/<name>.luau` | writes the control source: the `build(library, core, spec)` seam, an exported `Spec` type, the input-contribution skeleton, and `dump()` |
| `tests/<name>.spec.luau` | writes the spec: one failing TODO case, four failing input-class cases, four failing affordance cases, one hot-switch case |
| `examples/gallery/scenarios/<name>.luau` | writes the gallery scenario — the surface a person opens on a device |
| `tests/run.luau` | registers your spec in the runner |
| `tests/conformance/controls_registry.luau` | writes your registry row, with `inputProofs` and `affordanceProofs` citing the stamped case names |
| `src/render/compose_controls.luau` | the one public registration: `api.<Name> = composite("<Name>", require("../controls/<name>").build)` |
| `tests/lib/large_text_fixtures.luau` | registers a large-text fixture, so the accessibility sweep measures the control from its first commit |
| `docs/reference/api.md` | appends the reference stub, at the anchor the registration checker requires |
| `docs/guide/README.md` | adds the capability-catalog row, linked to that api.md anchor |
| `tests/controls_namespace.spec.luau` | adds your name to `POST_ADR_NAMES`, the namespace allowlist |
| `examples/gallery/scenarios/init.luau` | registers the scenario in `ORDER`, so the runner and the showcase can reach it |
| `tests/overflow_sweep.spec.luau` | adds the scenario to `SCENARIOS`, so it is swept at every viewport, text size, and theme |
| existing demo section | choose the appropriate visible home; the scaffold does not add a top-level demo or alter catalogue counts |

Every row is stamped from the one name you typed. Do not add a registration by
hand that the scaffold already writes.

Verify the red state: `./run-tests.sh` must now fail with the TEN stamped
cases and nothing else. Every other check in the suite was green before the
scaffold ran and must still be green after it. **If anything else is red, that
is a defect in the scaffold — report it rather than working around it.**

### What the scaffold cannot stamp, and what tells you so

Everything above is registered but STUBBED. These are yours, and each one has a
check that names it if you forget:

| Yours to write | What tells you |
|---|---|
| the ten stamped cases | `./run-tests.sh` — they `error("unimplemented")` on purpose |
| the real `docs/reference/api.md` entry | a human reviewer. The anchor satisfies `check_registration`; only a person can see that the entry is real |
| the catalog row's one-line description and the recipe's teaching copy | a human reviewer and the mounted scenario tests |
| the scenario's `steps` and `report` | a human reviewer, and §6 below: a fixture with no steps cannot be driven |
| a `PROOF_GAPS` or `AFFORDANCE_GAPS` entry, when a class genuinely has no device-true case | `lune run tools/lune/check_registration_cli`, which names the control and the class |
| a new public property on a primitive | `lune run tools/lune/check_prop_parity_cli`, which proves seven views of the property agree |
| a guide paragraph, when the control introduces a new CONCEPT | a human reviewer. The catalog row is mandatory; a concept paragraph is a judgement |

## 1.5 The shape of a control, and the one way it is registered

A control module exports one function and returns one record:

```lua
function gauge.build(library: any, core: any, spec: any)
    local UI = library.UI          -- the control-side node vocabulary
    -- …compose primitives, attach an input contribution…
    return {
        blueprint = blueprint,     -- required: the node the caller receives
        api = api,                 -- optional: the control's imperative verbs
        dump = dump,               -- optional: the deterministic diagnostic form
        dispose = dispose,         -- optional: teardown the wrapper registers
    }
end
```

Registration is one line in `src/render/compose_controls.luau`, beside the other
composites:

```lua
api.Gauge = composite("Gauge", require("../controls/gauge").build)
```

`composite(name, build)` is the whole public wrapper, and it is worth knowing
exactly what it does for you:

- It accepts both spellings: `UI.Gauge { ... }` and `UI.Gauge("Id") { ... }`.
  A constructor name becomes `spec.id`; without one the wrapper stamps a unique
  `Gauge#<n>`. Passing both is an error.
- It moves numeric children into `spec.children`, so a caller writes ordered
  children and your `build` reads one field. Writing both spellings is an error.
- It calls `build(library, core, spec)` under the caller's Compose owner.
- It registers your `dispose` with `Compose.cleanup`, so teardown follows the
  owner. Never ask a caller to call `dispose` by hand.
- It hands the frozen record `{ api, dump }` to the spec's `ref` callback, once,
  while the control is built. `ref` must be a function. A control that publishes
  its verbs on its own record is its own `api`.
- It returns your `blueprint` to the caller. The caller never sees the record
  except through `ref`.

So application code reads like every other control:

```luau
local gauge
UI.Gauge("Pressure")({
    value = pressure,
    ref = function(record) gauge = record.api end,
})
```

Do not add a second public spelling. `app.controls.<Name>` is the only one, and
`docs/reference/api.md` documents it under the heading `` `Controls.<Name>` ``
(`Controls.<Name>` reads as "the `<Name>` constructor on `app.controls`"; sample
code always spells it `UI.<Name>`).

A control takes its caller's state; it never invents it. State that must outlive
the control is a Compose cell the caller owns and passes in. Read
[component authoring](../guide/15-components.md) before writing the public usage
example, and write that example in the `UI.<Name>` form an application uses.

## 2. Design the control's contract (in the spec, first)

Replace the TODO test with failing tests for the control's real behavior.

**Build your world with `tests/lib/world.luau`, not by hand.** One call —
`local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })` — hands
back `app`, `UI` (`app.controls`), `Compose`, `core`, `env`, `adapter`, `system`
and `pres`, in one order. `tests/world_substrate.spec.luau` ratchets the number
of hand-rolled builders downward, and names the next spec file that adds one. A
new control's spec is a new spec file, so build it on the substrate.

Author your cases the way an application does: `w.UI.Gauge("Ctl")({ ... })`.
`w.record("Ctl")` answers the `{ blueprint, api, dump, dispose }` record that
control built, so a spec reaches the api and the dump without a second call
shape.

The house style for the control contract below is
[`tests/level_picker.spec.luau`](../../tests/level_picker.spec.luau) — a whole
composite control, every input class, registry neutrality — and
[`tests/paradigm_table.spec.luau`](../../tests/paradigm_table.spec.luau) for the
paradigm axis and the hot-switch transitions. Both are on the substrate.

Cover, at minimum (this is the control contract the conformance culture
expects):

1. **Build + render**: `build` returns `{ blueprint, api?, dump?, dispose? }`; the
   blueprint mounts and renders headlessly (mount → `renderer.attach` over
   `tests/lib/fake_target` → `initialRender`), `core.lastError()` stays nil.
2. **Every input class**, end to end through the REAL paths — this is the
   review bar: *a control that only works with a mouse is an unfinished control*.
   A control must prove ALL FOUR of pointer, touch,
   keyboard, and gamepad: pointer/touch via `adapter.tap(path)` /
   `adapter.pointerDown(..., "touch")` / pointer handlers, keyboard/gamepad via
   a presenter + `system.deviceKey("Return"/"ButtonA"/...)` — never by calling
   callbacks directly. The scaffold stamps one failing case per class
   (`<Display> pointer:`/`touch:`/`keyboard:`/`gamepad:`); the registry row's
   `inputProofs` cites those exact names, and the registration checker fails a
   control that leaves any class unproven. If a class genuinely has no
   device-true case (its path is identical to a proven sibling), record it as a
   NAMED gap in `tools/lune/check_registration`'s `PROOF_GAPS` — never leave it
   silently empty. What mounting gives you for FREE, so you rarely hand-wire:
   the presenter auto-composes navigation groups, per-node Activate
   dispatch, grab intercept, geometry feed, and keep-visible from the input
   contribution you attach in step 3 (below) — a composite attaches a
   contribution bundle to its root instead of asking consumers for `present()`
   opts.
3. **Every form you offer must be worth reading.** A control that offers a
   COMPACT representation — a `compactLabel`, a ViewThatFits ladder, or a form
   list a `UI.Region` collapses through — is making a promise about each rung of
   that ladder, and the framework cannot check it for you. The rule: **the
   minimum form must carry the control's essential value.** A round timer's
   smallest form may lose precision (`2m` for `2:14`) but not the fact that a
   round is running; a scoreboard's may lose the team names but not the score.
   Everything else — the detail, the history, the secondary figures — is what the
   `expand` discloses (`docs/guide/01-concepts.md`, "Adapting without dead ends"),
   and a disclosure cannot repair a missing headline: the player has to know there
   is something to ask for before they will ask for it. A ladder whose last rung
   drops the number the player needs has moved a defect behind a tap.
   The painted half of this is mechanical (`text_audit`'s value sweep refuses a
   truncated VALUE at any size); the authoring half is yours.
4. **The paradigm axis** — the affordance matrix. Reachability (item 2) is
   not enough — a control can be reachable on every class and still feel wrong.
   Prove the STRUCTURAL IDIOM each live class expects, as a *distinct* set of
   cases from the reachability ones. The scaffold stamps four failing
   `<Display> <class> affordance:` cases and one `<Display> hot-switch:` case;
   the registry row's `affordanceProofs` cites them. Decide, per class:
   - **pointer** — direct drag (no grip), a **hover** preview layer, wheel as a
     separate scroll channel.
   - **touch** — a 44 px hit floor; a naked pan scrolls, so any pan-to-reorder
     needs an edit-mode ≡ grip / long-press.
   - **keyboard** — a visible focus ring; Navigate → Activate; Adjust on a
     focused value.
   - **gamepad** — focus + A/B; reorder = grab mode; Adjust = focus-then-
     directional; a strengthened focus state at ten-foot.
   Read affordances from the **live class set** (`env` `interactionClasses`),
   never `preferredInput` alone — an affordance derives from the live capability
   set, so every live class gets its idiom at once. **Hot-switch (UI-PARADIGM-002):** if your control owns IN-FLIGHT state
   (a drag, a grab, an open edit), decide **CARRY** (survives a mid-gesture class
   flip; the new class's idiom becomes additionally available) or **CANCEL**
   (reverts to the pre-gesture snapshot — no data loss, never a wedge) and prove
   it; set `affordanceProofs.hotSwitch = false` (and delete the stub case) if the
   control holds none. See `tests/paradigm_table.spec.luau` (drag/grab/edit) and
   `tests/paradigm_textinput.spec.luau` (edit) for the house patterns.
5. **No factory reruns** for non-structural updates (compare
   `root.counters().factoryRuns` before/after a binding change).
6. **Dump determinism**: `dump()` twice → identical; it reflects the state a
   bug report needs.
7. **Registry neutrality**: build/mount/interact/dispose returns
   `core.owner.size()` to its baseline. Snapshot the baseline AFTER creating
   the long-lived harness singletons (environment, action system, presenter)
   — they intentionally allocate for the client's lifetime and have no
   dispose seam; only YOUR control must be neutral (see
   `tests/level_picker.spec.luau` for the house pattern).

Run `lune run tests/run_one <name>` after writing them — seconds, and it is the
only way to see each case fail for the RIGHT reason (missing behavior, not a
typo) while the file is still changing. Run `./run-tests.sh` before you believe
any of it.

**Your OWN spec is strict too, with the framework's own guard.** Schema
validation rules on `UI.*` primitive props. Your control's own spec table is
yours to close, and `Facet.specGuard` is the one implementation of that rule.

**Inside this repository — which is where you are — require the submodule
directly.** Every shipped control does exactly this, and so should yours:

```lua
local specGuard = require("../spec_guard")

-- CLOSED SPEC (constitution §4): exactly the fields this control reads.
local GAUGE_KEYS = specGuard.keySet({ "id", "value", "onChange" })

function gauge.build(library: any, core: any, spec: any)
    -- `where` is the PUBLIC name an author typed, so the error is greppable from
    -- the call site; `kind` is "spec" or "opts"
    specGuard.assertKnownKeys("Controls.Gauge", spec, GAUGE_KEYS, "spec")
```

Note the seam: `build(library, core, spec)`, three arguments, as
[§1.5](#15-the-shape-of-a-control-and-the-one-way-it-is-registered) describes and
as the scaffold stamps it. `src/controls/chip.luau` is the smallest worked
example.

> **Do NOT reach the guard through the library root from inside `src/controls/`.**
> `local Facet = require("../")` — or `require("@self")` — at module scope is a
> CIRCULAR REQUIRE: `src/init.luau` requires every control module near its top and
> assembles `Facet.specGuard` much later. Lune does not report the cycle. **It
> hangs** — no output, no stack, no timeout — so `lune run tests/run_one <name>`
> sits there forever with nothing to pull on. `lune run
> tools/lune/check_boundary` names the file and the rule
> (`src-module-requires-library-root`) in under a second, and 19 gate rows run it.

**Out of this repository** — a control shipped in a game, or in a package that
consumes Facet — there is no `../spec_guard` to require, so reach the same
implementation through the public surface instead. There is no cycle there,
because the library is fully loaded before your module runs:

```lua
local Facet = require(ReplicatedStorage.Facet)
local GAUGE_KEYS = Facet.specGuard.keySet({ "id", "value", "onChange" })
```

Either way a misspelled key gets the same sentence every Facet boundary
produces: the key that was wrong, a "Did you mean" when one is close, and the
whole legal set. See [api.md §`specGuard`](../reference/api.md#specguard).

**Authoring is strict.** Every `UI.*` spec is validated against
`src/blueprint_schema.luau` at construction: an unknown key, a wrongly typed
value, a bare number where a dimension belongs, a readable on a prop read once at
mount, a missing required prop, or children on a leaf is an immediate error
naming the control, the property, and the valid alternatives. If your control
needs a NEW public property on a primitive, add it to the schema FIRST, then
satisfy `lune run tools/lune/check_prop_parity_cli`, which proves the schema,
the dirty classification, `render/authority.luau`, the renderer's write sites,
the engine adapter's `setProp` switch, the exported spec type, and
`docs/reference/api.md` all describe the same property.

## 3. Implement

Rules the reviewers will hold you to:

- Compose shipped primitives (`UI.VStack/HStack/ZStack/Anchor/Text/Button/
  Toggle/Box/Grip/When/ForEach`, style modifiers `UI.shadow`/`UI.corners`).
  Structural changes go through `When`/`ForEach` only.
- Every reactive value you create belongs to a Compose owner. A
  `Compose.cell`/`formula`/`watch` made inside `build` belongs to the owner the
  control is built under. Register any other teardown with `Compose.cleanup`.
  Create a child owner only when the control must release a subtree earlier than
  its caller does; `src/controls/page_view.luau` is the worked example, and its
  `dispose` is `owner.dispose()` and nothing else.
- State that must outlive the control belongs to the CALLER's data model,
  not inside the control. A caller-owned writable cell arrives through the spec.
- Focus: reachable ids via focusable primitives; if the control has inner
  navigation semantics, use `NavigationGroup`s (see
  `src/focus/focus_graph.luau`).
- **Attach your input contribution.** Wrap the returned
  root with `Facet.contribution.attach(blueprint, bundle)` — a PUBLIC export,
  so a control built outside this repository uses the same seam. Inside the
  repository require `../input/contribution` directly, as the scaffold stamps
  it. The bundle rides the blueprint's internal `meta` channel, never
  the public prop bag, so it is unaffected by strict prop validation. Fill only the fields your control needs
  (`focusGroups` for D-pad/arrow navigation, `handleActivate` for tap/A/Return,
  `navigateIntercept` for grab mode, `focusMoved`/`syncGeometry`/
  `keepVisibleOffset`/`bindActionSystem` as needed, and `bindFocusGraph` for the
  rare control that must MOVE focus rather than follow it — `UI.VirtualList`'s
  index focus policy is the worked example; never ask a consumer for the graph).
  The presenter discovers the
  bundle on mount and composes the four-input story with zero consumer opts;
  `tests/auto_input.spec.luau` is the pattern. (A composite that attaches NO
  contribution is treated as non-interactive by the checker — do not delete the
  attach for a control that a user can focus or activate.) The bundle also
  carries the **paradigm seams** (item 2.3): `adjustTargets`/`handleAdjust` for
  the Adjust verb (focus-gated so a bare screen never shadows gameplay keys),
  and `handleCancel`/`outsideDismiss`/`transientScope` for a control that opens a
  transient surface (the Picker's menu, `picker_menu.luau`, is the worked example). Use these instead of
  asking consumers for `present()` opts.
- **Three load-bearing facts:**
  1. **One activation site.** When your bundle declares `handleActivate`, the
     inner focusable primitives must carry **no** `onActivate` prop. Activate
     dispatch is an ordered cascade with an early return
     (`activateEffect`, `src/present/presenter.luau`): a consumer's
     `opts.onActivate` override, then the node's own `onActivate`, then a
     `Toggle`'s auto-flip, then the longest-prefix contribution's
     `handleActivate`, then the drag verb's pickup. **The first one that answers
     ends the dispatch.**

     So declaring both does not double-fire the verb. It does something quieter
     and worse: **the node's `onActivate` wins and your bundle's
     `handleActivate` is never called at all, silently.** That holds on all four
     input classes.

     The silence is deliberate rather than an oversight, and it has to be: a
     composite may legitimately give ONE inner node its own `onActivate` while
     its bundle handles the rest, and the framework cannot tell that apart from a
     mistake without calling the handler it is trying not to call. The discipline
     is yours — **one activation site per path** — and the check is your own
     four-input cases, which fail if the wrong handler runs.
  2. **The 44 px touch floor is a contract you must declare, not one the
     solver enforces.** A bare focusable primitive renders at its content
     height; give your control's hit surface an explicit
     `height = { type = "minMax", min = "targetSizes.minimum" }` and assert the
     rendered rect in your touch-affordance case, or a sub-44px control will
     pass a careless test. **Name the token, never the number.** A bare `44`
     here is a theme-owned metric written into a control, and
     `tools/lune/check_theme_drift` rejects a numeric `min` anywhere under
     `src/controls/`. The token resolves to the same floor
     and moves with the theme package. `src/controls/chip.luau` and
     `src/controls/picker.luau` are the worked spellings.
  3. **`pres.refresh()` before reading rendered props.** Binding writes flush
     to the adapter on refresh; a spec that asserts an adapter prop right
     after an interaction reads stale state without it.
- Async resources only via `app.newResourceProvider` handles owned by the right
  owner (a row's own owner for a per-row resource).
- Keep `dump()` truthful as the state grows.

Loop `lune run tests/run_one <name>` while you implement, then `./run-tests.sh`
until green. The suite total must be strictly larger than before your work
(`tools/test.sh <expected-min>` proves it; an unregistered spec is a silent
zero).

## 4. Documentation

Replace the `docs/reference/api.md` TODO stub with the real entry. Note the
registration checker gates on EVERY undocumented public export, so if
someone else's export landed undocumented you may see unrelated drift — fix
or report it, don't ignore it. Your entry needs:
signature, spec-table fields, return surface, invariants, and a short
example — written for a developer who has never seen this repo (no internal
shorthand). If the control introduces a new concept, add a paragraph to the
relevant `docs/guide/` page.

[`../reference/constitution.md` §15](../reference/constitution.md#15-evidence)
is the evidence list your entry is part of: red-first specs, the registry row
with its proofs, this api.md entry plus a guide paragraph when it introduces a
concept, live Studio evidence for anything visible or interactive, and honest
PENDING rows for what only a device or a human can observe.

## 5. Gates and evidence

Run, in order, from the library root:

```
./run-tests.sh                                   # must exit 0: suite green, count grew
lune run tools/lune/check_registration_cli       # must exit 0: registration complete
lune run tools/lune/check_prop_parity_cli        # must exit 0: property views agree
lune run tools/lune/gate phase-4-hardening       # must not REGRESS (see below)
```

**"In order" is load-bearing — do not run the gate until the suite is green.**
Many gate rows prove themselves by grepping a passing line out of a full-suite
transcript (`tools/suite_transcript.sh`, which the rows shell into). A red suite
therefore has no such line for ANY of them, so every transcript-dependent row
flips at once, whatever its subject. A handful of unrelated rows going
FAIL_RECOVERABLE on a red suite is that cascade, not a regression you caused,
and it tells you nothing. Get `./run-tests.sh` to exit 0 first, then read the
gate.

The registration checker enforces the four-input bar: it **fails a
mouse-only control**. Every interactive control (a focusable leaf, or a
composite that attaches an input contribution) must declare `inputProofs` for
all four classes in `tests/conformance/controls_registry.luau`, and every cited
case name must exist verbatim in a spec `tests/run.luau` registers. A missing
class fails with a message naming the control and the class; a genuinely absent
device-true case must be a named `PROOF_GAPS` entry, never a silent omission.

It **also enforces the paradigm axis** (UI-PARADIGM-001/002). Every interactive
control must declare `affordanceProofs` — the four per-class structural-idiom
proofs plus a `hotSwitch` decision (a list of §C transition cases, or explicit
`false`). The checker refuses: a missing `affordanceProofs` (silent omission),
`affordanceProofs = false` on an interactive control, an uncited/unregistered
case name, a missing class idiom, or a missing `hotSwitch` decision. A genuinely
absent per-class idiom must be a named `AFFORDANCE_GAPS` entry (currently empty
— the matrix Amendments record every gap closed), never left silently empty. A
non-interactive control declares `inputProofs = false` **and**
`affordanceProofs = false`.

The gate's pass rule counts human-signoff placeholder checks (`PENDING`
states with no run command) as failures by design, so the gate command may
exit nonzero even when your work is perfect. Your bar: every check that was
PASS before your change is still PASS, and no check moved to
FAIL_RECOVERABLE. Never flip a PENDING state yourself.

Evidence to hand back: the green suite tail (`N passed`), the checker PASS
line, the `tools/verify.sh full` result showing no check that used to pass now
failing, and the list of files you created or edited.

## 6. Live Roblox gate

Headless conformance proves deterministic control decisions. It does not prove that
Roblox created, laid out, styled, clipped, focused, or delivered input to the mounted
Instances correctly.

Before calling a player-visible control complete:

1. Grow the gallery scenario the scaffold stamped
   (`examples/gallery/scenarios/<name>.luau`) into a real instrumented fixture:
   deterministic state, one named `step` per verb, and a `reset`. Its four
   registrations — the scenario `ORDER`, the overflow sweep, the demo picker,
   and standalone sweep registration — are already in place, and that is the whole of
   the repository's standing rule for a showcase surface: *registered in
   `scenarios/init.luau` ORDER, composed within an existing demo, swept by
   `tests/overflow_sweep.spec.luau` at all viewports, and verified across every
   shipped theme.* What is still yours is the part a tool cannot write: the
   state and the steps that let a person drive the control.
2. Pass the Studio preflight in the Facet execution contract, including a visible
   viewport, current source, working capture, and a raw-input canary.
3. Drive the mounted control through every Studio-observable native path. Pair the
   raw/native event with the semantic action, focus/value/command effect, actual hit
   geometry, and a capture.
4. Exercise the supported phone orientations, desktop, console/ten-foot emulation,
   preferred text, reduced motion, disabled state, and live input/layout changes that
   apply to the control.
5. Give a fresh-context verifier the contract, fixture, source change, and raw
   artifacts. Fix its correctness and evidence findings and rerun the affected
   fixture.
6. Keep true gamepad-class, physical touch/operating-system keyboard, device
   performance, and human-feel rows explicitly pending when the available Studio
   instrument cannot observe them.

Do not use a direct callback, a control method, a blueprint dump, or a screenshot by
itself as live-input proof. If Studio finds a defect that Lune missed, add both the
smallest deterministic regression and a durable Studio scenario for the engine-facing
part.

## Common traps

- **Suite "green" but truncated**: a main-thread yield truncates the Lune
  suite with exit 0 — `tools/test.sh` refuses a verdict without the
  `N passed` summary line. Never yield on the main thread in tests.
- **Unregistered spec**: `require` your spec in `tests/run.luau` (the
  scaffold did; don't remove it) — otherwise your green is a silent zero.
- **Driving callbacks directly**: tests must go through
  `system.deviceKey`/`adapter.tap`; direct callback invocation bypasses the
  context/sink/focus pipeline and proves nothing.
- **Absolute paths** in every shell command; Dropbox paths contain spaces —
  quote them.

## Controls inside navigation pages

A NavigationStack page runs under its own Compose owner. Build a composite
control there and keep caller data outside it. Declare Cancel through the normal
contribution so an editor or popup gets first refusal before the page pops. Do
not bind Back hardware or create a second focus order. Test a page switch while
your control owns focus and while its transient content is open.
