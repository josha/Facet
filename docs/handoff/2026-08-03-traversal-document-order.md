# Handoff — Tab should traverse in document order, and the focus chain should be inspectable

**Date:** 2026-08-03
**Raised by:** the director, in a Studio playtest, after roadmap Step 8
(`desktop-keyboard-navigation`) had passed its gate and three fresh-context reviews.
**Status:** diagnosed with a measurement, **not started**.

Read this file plus `docs/plans/desktop-keyboard-navigation.md` and
`docs/plans/agent-execution-contract.md`. You should not need the Step 8 session.

---

## 1. The defect, in one line

**Tab reaches a `Slider` dead last, after every other control on the screen.**

Measured live in the gallery place (`studio/keyboard.json`, row `DK17-H-ring` in
`artifacts/desktop-keyboard-navigation/`), sixteen Tab presses from the top of the
fixture:

```
Actions/Reset → Count/Dec → Count/Inc → List/Row1 … List/Row12 → Volume/TrackHost/Track
```

The slider is on screen between the button row and the list. It traverses after
twelve list rows, so tabbing through the form reads as "Tab skips the slider".

This was recorded as an open observation in the acceptance ledger
(§"What this stage explicitly does not claim" → *Grip traversal position*) with
the note that it would be revisited if it proved to be a defect in use. It has.

## 2. Why it happens

A `Slider`'s focus stop is its track, which is a **`UI.Grip`**, and every
focusable Grip is **deferred to the end** of the focus order in three places:

| File | Line | What it does |
|---|---|---|
| `src/present/presenter.luau` | `focusWalk` ~319–331 | collects focusable Grips into a separate `deferred` list |
| `src/present/presenter.luau` | `focusOrder` ~413–416 | appends `deferred` after the ordinary walk |
| `src/present/presenter.luau` | `autoGroups` ~625 | emits a trailing `auto-grips` group |
| `src/present/presenter.luau` | `layoutGroups` ~705 | emits the same trailing `auto-grips` group |

The reason is real and is written at the call site: *"grips (opt-in focusable
pointer zones) sort AFTER the ordinary walk so list navigation lands on content
first; they stay reachable past the end (gamepad resize affordance)"*. That is
about **directional** navigation — arrowing down a table should land on rows, not
on column resize handles.

**It does not transfer to Tab.** Tab means document order, on every platform that
has ever had a Tab key. `graph.traverse` reads `allIds(scope)`, which is the
scope's own order — flat order, or every group's order concatenated in group order
— so it inherits the deferral wholesale.

## 3. What to build

### 3.1 Traversal follows document order

Tab and Shift+Tab should visit focusables in the order they are **mounted**, with
Grips in their natural position. The arrows must keep today's behavior exactly —
including the grip deferral, which exists for them.

Constraint from the Step 8 constitution rule (`docs/reference/constitution.md` §9):

> **One focus map, read two ways.** Directional Navigate and linear Traverse walk
> the *same* scope order. A second order, derived from Instances or maintained
> alongside, is the defect — the two would disagree the first time a node was
> hidden.

Document order is **the same set, sorted differently**, which does not break that
rule — but say so explicitly in whatever you write, because "traversal gets its
own ordering" reads like exactly the thing the rule forbids. The set must stay
identical: everything the arrows skip (hidden, disabled, non-focusable, retiring,
losing adaptive candidates, live focus-skip predicates) Tab must still skip, via
the same predicates.

Two shapes worth weighing before you pick:

- **(a) Carry a document index.** Have `focusWalk`/`autoGroups`/`layoutGroups`
  record each entry's document position alongside the path, and have
  `graph.traverse` sort by it. One order in the graph, two readings — closest to
  the constitution's wording. Costs a field on the order entry (which is already
  a union of `string | { id, focusable }`, so there is a shape to extend).
- **(b) Stop deferring, and defer in the arrows instead.** Emit grips in document
  position, and move the "content before handles" preference into
  `navigateDirection`. Cleaner data, but it moves a proven behavior into the
  directional path, so the arrow regressions carry the risk.

I lean **(a)**: it leaves every existing directional gate untouched and puts the
new behavior entirely inside the new verb.

### 3.2 The focus chain should be queryable and customizable

The director's framing: *"ideally the responder chain is auto-set but the user has
a way to query and customize if they want."*

Auto-derivation stays the default and must not regress — that is ADR-0013's whole
point and `tests/auto_input_screens.spec.luau` pins it. What is missing is that a
consumer cannot **see** the resulting order, and can only replace it wholesale
(`present({ navigationGroups = … })`), which means hand-maintaining the entire map
to move one control.

Suggested surface, to be designed against `docs/reference/constitution.md` (§3
constructors, §4 strict specs, §6 result objects) rather than bolted on:

- **Query.** Something like `handle.focusOrder()` returning the resolved traversal
  order as data — paths in order, each with whether it is currently eligible and
  why not. This is the debugging tool whose absence is why the defect above was
  found by a human rather than by an instrument. It also gives the Studio scenario
  something to assert beyond "focus moved".
- **Customize.** A per-node hint (a traversal index or an explicit before/after
  anchor) so an author can move one control without redeclaring the map. The Step 8
  plan's public-API rule applies: *"Add public options only for real author intent,
  such as a traversal exclusion or explicit order that the current graph cannot
  express."* An explicit order is named there as legitimate — an exclusion may
  already be expressible via `focusable`, so check before adding one.

Do **not** let this become a second focus system. If a custom order is supplied it
must flow into the same scope order everything else reads.

## 4. Where the code is

| Concern | Location |
|---|---|
| Traversal | `src/focus/focus_graph.luau` → `self.traverse(delta)` |
| Order production | `src/present/presenter.luau` → `focusWalk`, `focusOrder`, `autoGroups`, `layoutGroups` |
| Scope push/refresh | `src/present/presenter.luau` → `makeHandle` (~1590–1610) and `refresh` |
| Slider's focus stop | `src/controls/slider.luau` → the `Track` Grip (`focusable`, `focusVisual = "none"`) |
| Existing traversal tests | `tests/keyboard_navigation.spec.luau` |
| Directional tests that must not move | `tests/focus.spec.luau`, `tests/navigation_groups.spec.luau`, `tests/focus_structural.spec.luau`, `tests/focus_skip.spec.luau`, `tests/paradigm_table.spec.luau` |

## 5. How to verify

The headless suite **will not catch a regression here on its own** — that is the
lesson of this defect, so plan for both halves:

1. **Headless.** Add a fixture with a Grip-bearing control (a Slider) *between*
   ordinary controls and assert the traversal order interleaves correctly, and a
   companion asserting the arrows still defer. Every fixture in Step 8 put value
   controls on a screen alone or at the end, which is precisely why this shipped.
2. **Studio.** Scenario `keyboard_navigation` already mounts the exact shape
   (field → button row → slider → stepper → 12-row list). Drive it with
   `tools/studio/device_matrix.luau` mode `keyboard` and compare the focus log
   against document order. Recipe in `docs/guide/11-device-verification.md`.
   The gallery place already frees Tab (see §7).

## 6. Open, blocked, or unverified from Step 8

Inherit these; do not re-derive them.

- **Docs not yet written** for `PresenterOpts.keyboardNavigation`,
  `PresentOpts.keyboardNavigation`, and `Grip.focusVisual`. The gate is **stale**:
  `library-suite-green` pins 3070, the suite is at **3079**.
- **The gameplay-band number is wrong in the docs.** `docs/guide/07-input.md` and
  ADR-0014 say the avatar sits at priority **2000**. Measured on the real
  `PlayerModule`: **Camera 100, Character 150, Vehicle 200, Transformer 300**.
  Behavior is unaffected (Facet sits at 1500+); the number is simply false and
  someone will size against it.
- **Unverified live:** the end-to-end key drive *after* `keyboardNavigation` made
  surfaces sink. Three consecutive `execute_luau` timeouts on any call routed
  through the driver's `keyboard` mode. Needs a fresh Play session to separate
  "VirtualInput will not synthesize into a sinking context" from "the session
  wedged". Everything before the sink change is measured and stored.
- **`Tab` is the CoreGui players-list shortcut.** With the leaderboard enabled the
  engine will not deliver it — confirmed by the director on a physical keyboard.
  `decisions.md` DKN-1.
- **Keyboard IAS bindings are dead while a `TextBox` holds focus** (engine marks
  input `gameProcessed`), so `handleTraverse` is unreachable today. DKN-2. The
  director decided **not** to add a `UserInputService` listener to work around it.

## 7. Two traps that cost time in Step 8

- **The upvalue trap, twice.** A `local` declared *below* a closure that reads it
  resolves a nil **global** instead — silently, no error, the answer is just
  permanently wrong. It bit `newTextInput`'s `idPattern` and `newSlider`'s
  `trackPath` in the same stage. If a newly added fact is always false, check the
  declaration order first.
- **The gallery frees Tab for you**, in `examples/gallery/client/init.client.luau`
  (`SetCoreGuiEnabled(PlayerList, false)`, beside the existing
  `disableLegacyControls()`). That is a **UI-only-place** trade; Facet never makes
  it for a consumer. `gamepad_contention.traversalKeyContended()` reports the live
  answer.

## 8. The reason this file exists

The stage gate passed, and three independent fresh-context reviews accepted it.
The director then found two real defects in a ten-minute playtest: Space stealing
the avatar's jump key, and this one. Both were *recorded in the artifacts as
known caveats* rather than treated as defects — the instruments measured the right
things and nobody sat in front of it.

When you finish this, put a human in front of the fixture before calling it done.
