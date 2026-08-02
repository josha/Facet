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

- Work from the library root: `GameStudio/ui/LuauUI` (all commands below
  assume it; use absolute paths in shell commands — relative paths against a
  wrong cwd are the #1 recorded time sink, `docs/lessons/absolute-paths-in-shell-commands.md`).
- The scaffold and deterministic conformance toolchain run in Lune
  (`lune run …`). A player-visible control is not production-proven by Lune alone:
  follow the required Studio and evidence loop in
  [`../plans/agent-execution-contract.md`](../plans/agent-execution-contract.md).
- Test-first is not optional: the scaffold stamps a FAILING spec on purpose.
  Never mark done while `./run-tests.sh` is red.
- Never edit `tools/lune/gate_manifest.luau` or `phases.json` for a control;
  the existing gate checks pick your work up through the suite and the
  registration checker.

## 1. Scaffold the skeleton

```
lune run tools/lune/scaffold_cli control <lower_snake_name>
```

This stamps and REGISTERS everything so nothing can be forgotten:

| File | What it is |
|---|---|
| `src/controls/<name>.luau` | the control source: `build(LuauUI, core, spec)` seam + `dump()` |
| `tests/<name>.spec.luau` | spec file with one deliberately-failing TODO test |
| `tests/run.luau` | your spec registered in the runner (edit applied) |
| `tests/conformance/controls_registry.luau` | your registry row (edit applied) |
| `src/init.luau` | `new<Name>` export (edit applied) |
| `docs/reference/api.md` | a TODO reference stub (edit applied) |

Verify the red state: `./run-tests.sh` must now FAIL with your TODO test.

## 2. Design the control's contract (in the spec, first)

Replace the TODO test with failing tests for the control's real behavior.
Cover, at minimum (this is the control contract the conformance culture
expects — see `tests/table.spec.luau` and `tests/virtualization.spec.luau`
for the house style):

1. **Build + render**: `build` returns `{ blueprint, dump, dispose }`; the
   blueprint mounts and renders headlessly (mount → `renderer.attach` over
   `tests/lib/fake_target` → `initialRender`), `core:lastError()` stays nil.
2. **Every input class**, end to end through the REAL paths — this is the
   review bar (`ui_todo.md` §0: *a control that only works with a mouse is an
   unfinished control*). A control must prove ALL FOUR of pointer, touch,
   keyboard, and gamepad: pointer/touch via `adapter.tap(path)` /
   `adapter.pointerDown(..., "touch")` / pointer handlers, keyboard/gamepad via
   a presenter + `system.deviceKey("Return"/"ButtonA"/...)` — never by calling
   callbacks directly. The scaffold stamps one failing case per class
   (`<Display> pointer:`/`touch:`/`keyboard:`/`gamepad:`); the registry row's
   `inputProofs` cites those exact names, and the registration checker fails a
   control that leaves any class unproven. If a class genuinely has no
   device-true case (its path is identical to a proven sibling), record it as a
   NAMED gap in `tools/lune/check_registration`'s `PROOF_GAPS` — never leave it
   silently empty. What mounting gives you for FREE (so you rarely hand-wire —
   ADR-0013): the presenter auto-composes navigation groups, per-node Activate
   dispatch, grab intercept, geometry feed, and keep-visible from the input
   contribution you attach in step 3 (below) — a composite attaches a
   contribution bundle to its root instead of asking consumers for `present()`
   opts.
3. **The paradigm axis** (UI-PARADIGM-001/002; the affordance matrix,
   `artifacts/input-paradigms/affordance-matrix.md`). Reachability (item 2) is
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
   never `preferredInput` alone (ADR-0015) — every live class gets its idiom at
   once. **Hot-switch (UI-PARADIGM-002):** if your control owns IN-FLIGHT state
   (a drag, a grab, an open edit), decide **CARRY** (survives a mid-gesture class
   flip; the new class's idiom becomes additionally available) or **CANCEL**
   (reverts to the pre-gesture snapshot — no data loss, never a wedge) and prove
   it; set `affordanceProofs.hotSwitch = false` (and delete the stub case) if the
   control holds none. See `tests/paradigm_table.spec.luau` (drag/grab/edit) and
   `tests/paradigm_textinput.spec.luau` (edit) for the house patterns.
4. **No factory reruns** for non-structural updates (compare
   `root.counters().factoryRuns` before/after a binding change).
5. **Dump determinism**: `dump()` twice → identical; it reflects the state a
   bug report needs.
6. **Registry neutrality**: build/mount/interact/dispose returns
   `core:counters()` to its baseline. Snapshot the baseline AFTER creating
   the long-lived harness singletons (environment, action system, presenter)
   — they intentionally allocate for the client's lifetime and have no
   dispose seam; only YOUR control must be neutral (see
   `tests/table.spec.luau` for the house pattern).

Run `./run-tests.sh` after writing them: they must fail for the RIGHT
reason (missing behavior, not typos).

**Authoring is strict.** Every `UI.*` spec is validated against
`src/blueprint_schema.luau` at construction: an unknown key, a wrongly typed
value, a bare number where a dimension belongs, a Signal on a prop read once at
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
- Own EVERY resource (signals, memos, observers) in the control's scope;
  `dispose()` = `scope:dispose()` and nothing else.
- State that must outlive the control belongs to the CALLER's data model,
  not inside the control.
- Focus: reachable ids via focusable primitives; if the control has inner
  navigation semantics, use `NavigationGroup`s (see
  `src/focus/focus_graph.luau`).
- **Attach your input contribution** (ui_todo §0; ADR-0013). Wrap the returned
  root with `LuauUI.contribution.attach(blueprint, bundle)` — a PUBLIC export,
  so a control built outside this repository uses the same seam (the scaffold
  stamps `local contribution = LuauUI.contribution` and a commented bundle
  skeleton). The bundle rides the blueprint's internal `meta` channel, never
  the public prop bag, so it is unaffected by strict prop validation. Fill only the fields your control needs
  (`focusGroups` for D-pad/arrow navigation, `handleActivate` for tap/A/Return,
  `navigateIntercept` for grab mode, `focusMoved`/`syncGeometry`/
  `keepVisibleOffset`/`bindActionSystem` as needed). The presenter discovers the
  bundle on mount and composes the four-input story with zero consumer opts;
  `tests/auto_input.spec.luau` is the pattern. (A composite that attaches NO
  contribution is treated as non-interactive by the checker — do not delete the
  attach for a control that a user can focus or activate.) The bundle also
  carries the **paradigm seams** (item 2.3): `adjustTargets`/`handleAdjust` for
  the Adjust verb (focus-gated so a bare screen never shadows gameplay keys),
  and `handleCancel`/`outsideDismiss`/`transientScope` for a control that opens a
  transient surface (the PopupButton is the worked example). Use these instead of
  asking consumers for `present()` opts.
- **Three load-bearing facts** (dry-run findings 2026-07-21 — previously only
  learnable from the exemplar sources):
  1. **One activation site.** When your bundle declares `handleActivate`, the
     inner focusable primitives must carry **no** `onActivate` prop — the
     presenter dispatches a tap/A/Return to the node's own `onActivate` FIRST
     and then to the longest-prefix contribution, so declaring both
     double-fires the verb.
  2. **The 44 px touch floor is a contract you must declare, not one the
     solver enforces.** A bare focusable primitive renders at its content
     height; give your control's hit surface an explicit
     `height = { type = "minMax", min = 44 }` (or equivalent) and assert the
     rendered rect in your touch-affordance case, or a sub-44px control will
     pass a careless test.
  3. **`pres.refresh()` before reading rendered props.** Binding writes flush
     to the adapter on refresh; a spec that asserts an adapter prop right
     after an interaction reads stale state without it.
- Async resources only via `LuauUI.newResourceProvider` handles owned by the
  right scope (item scopes for per-row resources).
- Keep `dump()` truthful as the state grows.

Loop `./run-tests.sh` until green. The suite total must be strictly larger
than before your work (`tools/test.sh <expected-min>` proves it; an
unregistered spec is a silent zero).

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

The registration checker now enforces the four-input bar: it **fails a
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
line, the gate output showing no regressed check + `artifacts/phase-4/gate.json`,
and the list of files you created/edited.

## 6. Live Roblox gate

Headless conformance proves deterministic control decisions. It does not prove that
Roblox created, laid out, styled, clipped, focused, or delivered input to the mounted
Instances correctly.

Before calling a player-visible control complete:

1. Add it to an instrumented gallery fixture with deterministic state and reset
   controls.
2. Pass the Studio preflight in the LuauUI execution contract, including a visible
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

## Common traps (from docs/lessons/)

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
