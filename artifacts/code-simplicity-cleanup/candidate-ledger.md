# Simplicity-cleanup candidate ledger

**Stage:** roadmap Step 5.5, gate `code-simplicity-cleanup`
**Plan:** `docs/plans/code-simplicity-cleanup.md`
**Date opened:** 2026-07-28, before any source edit.

**Baseline frozen at:** library suite **2567** green; `check_registration`,
`check_boundary`, `check_docs`, `check_prop_parity` all exit 0; conformance
custom 41/41, fusion 34/41, imperative 36/41; public-surface dump 139 lines;
bench PASS; 14 of 16 prior gates exit zero. Raw baseline in `baseline/`.

**Rule of this ledger:** a candidate is only IMPLEMENTED when its waste or
duplication was established by tracing real call paths — never by a line count or
a bare grep miss — and when a runnable check would fail if the preserved behaviour
drifted. **RETAINED is a first-class outcome**: the plan says a small audit that
correctly keeps already-simple code beats a large refactor performed to justify the
pass. Roughly two thirds of what was examined was deliberately kept.

**How reachability was established** for every deletion below: read the module and
trace the call path, then grep the whole repo (`src`, `tests`, `examples`, `tools`,
`bench`, `docs`, `artifacts`, `assets`, `build`) for the name, **including**
string-keyed access, Rojo instance-path requires
(`require(ReplicatedStorage.LuauUI.client.x)`), `tools/lune/check_docs.luau` (which
asserts doc TERMS exist), `tools/lune/check_registration.luau` (which enforces the
control registry and api.md drift both directions), and
`tools/lune/gate_manifest.luau` — whose checks grep **source strings and test-case
names**, so a name mentioned there is load-bearing for a gate even with no Luau
caller.

---

## Status

| | Count |
|---|---|
| IMPLEMENTED | 10 |
| RETAINED (examined, deliberately kept) | 19 |
| ESCALATED (decision packet, not implemented) | 6 |

Net: 12 owned functions/fields/branches deleted, 9 duplicated decisions collapsed
to one owner, 2 stale documentation claims corrected, 1 prior gate repaired.
Public surface **byte-identical** (`public-surface.txt` vs
`baseline/public-surface-before.txt` — `diff` is empty). Suite **2567 → 2571**
(4 added pins, none removed, none weakened).

---

## IMPLEMENTED

### C-01 — one owner for what `enabled` means

- **Location:** `src/controls/contract.luau` (new owner); call sites in
  `slider.luau:133`, `slider.luau:248`, `stepper.luau:83`, `stepper.luau:118`,
  `stepper.luau:124`, `picker.luau:91`, `disclosure_group.luau:54`,
  `rating.luau:159`.
- **Evidence:** four byte-identical 9-line `isEnabled` bodies, a fifth with a
  `readOnly` prefix, and **three reactive re-spellings** of the same decision.
  Diffed all eight. The stepper's two memos had already drifted into a third
  spelling (`spec.enabled ~= nil and type(...) == "table" and use(...) == false`
  plus a separate `== false` guard) — same truth table, different shape. That drift
  is the argument: this is a policy, not arithmetic.
- **Behaviour preserved:** `nil` → enabled; a Readable is asked; anything else is
  enabled unless literally `false`. The one-shot form must **not** subscribe and
  the reactive form **must** — a bound `enabled` that flips has to move a control
  in and out of focus order with no remount. Rating's `readOnly` refusal stays
  Rating-local.
- **Proposal:** `contract.enabledNow(e)` and `contract.enabledIn(use, e)`; each
  control keeps a local named `isEnabled` delegating to it.
- **Risk:** low-medium — it is reached by every input class. Mitigated by the truth
  table being checked case by case (`nil`, `false`, `true`, a Readable yielding
  `false`/`true`/`nil`, a non-boolean) before the swap.
- **Check:** the suite's existing disabled-control cases, which assert refusal per
  input class — "an explicitly disabled Stepper refuses every input class",
  "a disabled Slider refuses drag AND Adjust", "navigation skips a disabled
  Slider's track", "a disabled Picker refuses selection", "a disabled group does
  not toggle", "a disabled rating refuses every input class, not just the pointer".
- **Constraint honoured:** `gate_manifest.luau` greps `isEnabled` in
  `stepper.luau`; the symbol is still there.
- **Benefit:** one place to change what `enabled` means across every value and
  selection control, instead of eight.

### C-02 — one mounted-node lookup in the renderer

- **Location:** `src/render/renderer.luau` — the walk formerly declared inside
  `controller.refresh`'s dirty loop, and the identical one declared later for the
  presentation channel.
- **Evidence:** two byte-equivalent depth-first `path → node` walks. The inner one
  was a **closure declared inside the `for _, entry in dirty` loop body**, so one
  closure was allocated per qualifying dirty prop per `refresh()`. They could not
  share only because of declaration order.
- **Behaviour preserved:** same first-match order over `root.node`; reactive prop
  writes land on the same node.
- **Proposal:** hoist the existing `findNode(path)` above `controller.refresh`
  (it closes over nothing but `root`) and call it from both.
- **Risk:** low — a lexical move with an identical traversal. Watched for this
  repo's own "later locals are not upvalues" lesson: the hoisted definition
  precedes its first consumer.
- **Check:** the renderer's reactive-prop re-apply cases and `mount.spec`; plus
  `check_flat_baseline`, which byte-compares every adapter prop write.
- **Benefit:** one tree-walk owner; a per-dirty-entry allocation removed from the
  refresh path.

### C-03 — one owner for "the nearest scroll ancestor"

- **Location:** `src/render/renderer.luau` — `scrollAncestorOf` (deleted) vs the
  `scrollHostOf` map built by `livePaths`.
- **Evidence:** `livePaths` threads the nearest scroll host down the recursion and
  records it per path; **its own comment says it exists precisely so this is not
  "computed on demand instead"** — while `scrollToVisible` computed it on demand
  with an 18-line full-tree walk. Verified the semantics match line by line: both
  exclude self (`nextHost`/`nextScroll` are passed to children only), and
  `scrollToVisible` reads only `host.path`.
- **Behaviour preserved:** the same host resolves, and `scrollToVisible` still
  returns `false` when there is none. The only state where the two spellings could
  differ is a mounted-but-not-yet-structurally-synced path — and such a path has no
  `lastRects` entry either, so both refuse it at the next guard.
- **Risk:** low-medium — keep-visible is a visible behaviour. `scrollHostOf` is
  `table.clear`ed and rebuilt inside `structuralSync`, which always precedes
  `solveAndApply`, and cleared on dispose.
- **Check:** the native-scroll keep-visible / scroll-to-visible cases and
  focus-into-scroller.
- **Benefit:** one owner for the ancestor decision, and a **full-tree walk removed
  from every keep-visible call** — which fires on every keyboard and gamepad focus
  move.

### C-04 — one grid column-count derivation

- **Location:** `src/layout/solver.luau` — `gridColumnCount`, called from both the
  measure pass and the arrange pass.
- **Evidence:** the derivation was written twice, identical apart from the measure
  copy's extra `innerMaxW ~= math.huge` guard. Measure/arrange disagreement on
  grids is this file's documented recurring defect class.
- **Behaviour preserved:** identical column counts on both passes. The `math.huge`
  guard moved **into** the helper; arrange's `innerW` derives from a concrete
  solved rect (`math.max(0, rect.w - pl - pr)`) and is never infinite, so the guard
  is inert there.
- **Risk:** low — a byte-identical extraction with the one asymmetry preserved.
- **Check:** the grid rows in `layout_vocabulary.spec` and `layout.spec`, plus the
  1 140-node `check_flat_baseline` byte comparison, in which **no rect changed**.
- **Benefit:** the two passes cannot drift.

### C-05 — one structural-region bookkeeping tail

- **Location:** `src/mount.luau` — the `ErrorBoundary` / `When` / `ForEach` blocks.
- **Evidence:** three consecutive 11-line blocks differing only in the builder
  called; the tail (`node.id`, two counter increments, `factoryRuns = 1`, the
  `scope:own` decrement) is character-identical in all three.
- **Behaviour preserved:** a structural region is exactly one mounted node with
  `factoryRuns == 1` and decrements the live count when its scope dies.
  `mountErrorBoundary` creates its own boundary and ignores the extra argument —
  stated in the comment so it is not read as a bug.
- **Risk:** low. The `mountWhen` / `mountForEach` **bodies** are untouched; only the
  dispatch and the shared tail changed, so the retiring/transition paths are not in
  this diff.
- **Check:** "50 mount/dispose cycles return mount and core registries to
  baseline", "mounts each node exactly once with stable paths", "dumps are
  deterministic and carry dirty flags".
- **Benefit:** a fourth structural region becomes one table entry rather than a
  fourth copied block.

### C-06 — `patternEscape` out of four `build()` closures

- **Location:** `popup_button.luau`, `table.luau`, `text_input.luau`,
  `virtual_list.luau`.
- **Evidence:** byte-identical, defined **inside `build()`** in all four, and
  called exactly once ≤3 lines later — so each control instantiation allocated a
  closure to make one call.
- **Behaviour preserved:** the escaped id pattern feeding `string.match` path
  routing.
- **Proposal:** hoist each to module scope. Deliberately **not** a shared owner —
  see RETAIN-06.
- **Risk:** ~zero (pure function, one call site each).
- **Check:** the gate-cited path-routing cases ("gamepad ButtonB while open closes
  the popup", "a tap on a rendered node OUTSIDE the open panel dismisses it").

### C-07 — scope diagnostics worded where the rule lives

- **Location:** `src/core/scope_impl.luau`; call sites in `custom.luau`,
  `fusion_adapter.luau`, `imperative.luau`.
- **Evidence:** all three cores passed **two** callbacks that formatted the **same
  two byte-identical strings** — three chances for a diagnostic to drift away from
  the mechanism it describes.
- **Behaviour preserved:** the exact substrings `double disposal` and
  `scope cleanup error in` reaching `core:lastError()`; the walk still continues
  past a throwing cleanup; counters return to baseline.
- **Proposal:** `scope_impl.factory(counts, report)` — one channel; the wording
  moves inside.
- **Risk:** low.
- **Check:** `lune run tests/conformance/cli <core>` on all three (which include
  `double-dispose-detected` and the new RR-7-R1 check) plus "siblings still
  release, counters stay exact, and no false double-dispose follows".
- **Benefit:** −12 lines, six fewer closures, and the RR-5-R1 reasoning now lives
  in one header instead of being implied by three call sites.

### C-08 — a prior gate's tautological check replaced with a real one

- **Location:** `tools/lune/gate_manifest.luau`, gate
  `theme-packages-and-skinning`, check `metric-snapshot-single-source`.
- **Evidence:** the check ended in `cmp -s baseline-neutral-dump.json
  final-neutral-dump.json` — **two stored files**. It could only ever prove they
  had not been touched, never anything about the current tree, which is precisely
  the failure `check_flat_baseline` was later built to replace ("the stored dump
  was no longer reproducible … the whole claim rested on a number nobody
  recomputed"). It had gone **red before this stage began** (see C-09).
- **Behaviour preserved:** the claim — flat/neutral rendering is unchanged against
  the Step 3.5 baseline.
- **Proposal:** run `check_flat_baseline`, which regenerates the neutral render
  from live source through the real mount → renderer → target stack and
  byte-compares 1 140 nodes with a named allow-list.
- **Risk:** low, and it **strengthens** the gate rather than weakening it.
- **Check:** the gate itself — `theme-packages-and-skinning` went FAIL → PASS.

### C-09 — a generator that defaulted to destroying its own comparison input

- **Location:** `tools/lune/_theme_baseline.luau`.
- **Evidence:** its target path **defaulted** to
  `artifacts/theme-packages-and-skinning/baseline-neutral-dump.json` — a stored
  comparison input. Running it bare overwrote the thing being compared against.
  That happened at 13:40 on 2026-07-28 (file mtime), before this stage's baseline
  freeze, and left the Step 3.5 gate red. The mitigation in place was a prose
  warning in `docs/handoff/SHOWCASE_DEVICE_PASS.md` — *"Do not regenerate … (I
  clobbered it once and restored it)"*.
- **Proposal:** require the target. Running it bare now exits 2 and says why.
- **Risk:** low — a development tool; the one programmatic caller
  (`check_flat_baseline`) already passes an explicit temp path.
- **Check:** `lune run tools/lune/_theme_baseline` → exit 2;
  `lune run tools/lune/check_flat_baseline` → PASS.
- **Benefit:** a required argument needs no prose warning. The handoff note was
  updated to record the change rather than repeat the warning.

### C-10 — the path↔attribute rename has one owner again

- **Location:** `src/themes/token_sync.luau`, `src/client/theme_controller.luau`.
- **Evidence:** `token_sync` exported `pathForAttribute` — **zero callers repo-wide**
  — while the controller hand-rolled the **opposite** direction as a local linear
  scan. `token_sync`'s own header declares it owns the path↔attribute namespace.
- **Behaviour preserved:** a rejected sheet edit is still named the way the
  designer sees it in the Style Editor, falling back to the raw path when no record
  claims it.
- **Proposal:** replace the dead export with `token_sync.attributeForPath(records,
  path)` (the controller's body, moved to its owner); the controller calls it.
- **Risk:** low — a pure lookup with one call site.
- **Check:** the theme-controller case asserting the dropped-edit warning names the
  attribute spelling, not the dotted path.

### C-11 — proved-dead owned code, deleted

Nine items, each with zero callers anywhere in the repo including every dynamic and
gate-string form. Grouped because the evidence and the check are the same shape.

| Deleted | Location | Note |
|---|---|---|
| `schema.isContainer` | `blueprint_schema.luau` | only its own definition line existed; `blueprint.luau` builds its own container set from `schema.all()` |
| `schema.TYPE_CHECKS` export | `blueprint_schema.luau` | the local is used internally; only the export assignment was unused |
| `schema.TRANSITION_FORMS` export | `blueprint_schema.luau` | same. The `table.freeze` moved onto the local so the table stays frozen |
| `transitions.activeCount` | `render/transitions.luau` | zero receivers; every `activeCount` hit in the repo resolves to `clock:` or `async/resources` |
| `transitions.isRunning` | `render/transitions.luau` | **one** line repo-wide — its own definition |
| `text_premeasure.isSettled` | `client/text_premeasure.luau` | no consumer; every other `isSettled` is motion's |
| `token_sync.weightNameOf` | `themes/token_sync.luau` | the unused half of a codec; `weightValueOf` stays (live via `fontRecord`) |
| `theme_controller.SUPPORTED_SCHEMA`, `standard_icons.SCHEMA`, `standard_icons.SOURCE_PX` | client/themes | absent from `gate_manifest.luau`, `check_docs.luau`, `api.md` and `artifacts/**`. `standard_icons.SCHEMA`'s *value* appears in `tools/upload_icons.py`, but as a literal in the manifest's `package` field — never read through the constant |
| dead `if compiled ~= nil or report.ok then` (comment-only body) + its unused local | `themes/package.luau` | the branch had no body; every failure is already emitted by the two loops above it |
| `graph.focused = graph.focused` | `present/presenter.luau` | a literal self-assignment; `graph.focused` is assigned once, in `focus_graph.luau` |
| `local Players = game:GetService("Players")` + `local _ = Players` | `client/roblox_env.luau` | a service handle whose only consumer was a no-op silencing its own unused-variable warning, "reserved for future locale facts" |

- **Check:** the full suite, all four checkers (`check_registration` in particular
  drift-checks `api.md` in **both** directions), and every prior gate.

### C-12 — two stale documentation claims corrected

1. **`host` is not a fifth live authority (closes ARCH-F8).**
   `src/render/authority.luau`'s header and `docs/guide/02-architecture.md` both
   presented `host` as an owner of real properties. It is declared in the type union
   and used by **nothing**: no `MANIFEST` entry carries it, no `assertWrite` call
   passes it, and the custom-control seam it was reserved for never shipped a
   blueprint class. The union member is **retained** (the theme linter's rejections
   and ADR-0019 §4 classify engine properties against this same five-name list);
   the false claim is gone.
2. **`adaptive.conditions` teaches its own leak.** `api.md`'s `AdaptiveStack`
   example passed no scope, and `opts` was named without its only field ever being
   documented — while the function builds **six memos** the caller owns. Measured:
   50 scope-less calls on one core leak `memos: 9 → 309`. The example now passes a
   scope and a new paragraph states the cost.

---

## RETAINED — examined, deliberately kept

| ID | What | Why it stays |
|---|---|---|
| RETAIN-01 | `isFinite` duplicated **15×** across `src/` (plus two under `isFiniteNumber`) | The strongest-looking candidate in the audit, and the right answer is no. It is a **zero-decision** predicate — one correct form, no policy content — unlike `enabled` (C-01), which encodes a policy that had already drifted. Consolidating buys ≈27 net lines and costs 15 new inter-module edges in a codebase with a gate-enforced require graph; the motion package's headers advertise "depends only on the contract types", and `motion/classes.luau` already records the opposite call in writing for its own Levenshtein ("kept local — motion owes nothing to the blueprint layer"). Decisive evidence that a shared owner would not have prevented drift: `table.luau` defines a *third* spelling, `finite(raw, fallback)`, which deliberately omits the `-math.huge` check and therefore could not have reused a shared one. |
| RETAIN-02 | `toColor3` defined 3× in `client/` (`Color3.new(c.r, c.g, c.b)`) | Genuine triplication, but `native_style` does not require `screen_chrome`, so consolidating means a new shared client module or a new cross-require for a three-line arithmetic-free conversion. Cheaper duplicated than seamed. |
| RETAIN-03 | `rgb()` 3× in `tokens/` | Same shape; two of the three are theme **data** files. |
| RETAIN-04 | `rectEq`/`rectsEqual` in slider, text_input, renderer | Three copies of a four-field comparison across three layers. Same reasoning as RETAIN-02. |
| RETAIN-05 | `authority.nativeSheetOwnedSet()` | No code consumer — but ADR-0018 names it "the probe list" and `artifacts/native-stylesheets/acceptance-ledger.md` cites it by name as NSS-I2's PASS evidence. Deleting it would silently invalidate a citation in a closed gate's evidence to save two lines. |
| RETAIN-06 | a shared `patternEscape` owner | C-06 hoisted four closures to module scope but did **not** create a shared owner: same reasoning as RETAIN-01, and these four live in four modules that otherwise have no reason to know about each other. |
| RETAIN-07 | `feedback.bus.lastError` + `lastEmitError` | Write-only: no consumer, and absent from the exported `Bus` type. But it is the named instrument of RR-12's fix in a closed gate's response ledger, and it is the third member of a consistent quarantine-diagnostic vocabulary (`core:lastError`, `clock:lastError`, `bus.lastError`). Deleting a 4-line diagnostic that a closed finding's response cites is not worth it. |
| RETAIN-08 | `presenter.onModalPresented` / `modalWatchers` | Superseded internally (the framework now drives `registry.surfacePresented(kind)` directly), so no `src/` subscriber remains — but it is documented in `api.md` and specced. Removing it is a public-export change, which ADR-0011 freezes for this stage. Recorded as a public seam whose framework consumer has moved on. |
| RETAIN-09 | `env.locale` | Zero `src/` readers, confirmed. A documented public environment fact, so removal is an API change. |
| RETAIN-10 | `core/fusion_adapter.luau` (227 lines), `core/imperative.luau` (273 lines) | The largest apparently-deletable blocks in the tree, and they are not dead: `gate_manifest.luau` defines `conformance-imperative-baseline`, the conformance CLI requires both, and `bench/scenarios.luau` benches both. They are the instruments that keep ADR-0002's core selection re-verifiable. |
| RETAIN-11 | `src/input/spatial.luau` | Looks like a contracts-only seam with no runtime consumer. It is `LuauUI.spatial` (public, registration-enforced), has a full spec, and `gate_manifest.luau` greps for the file and its spec by name. |
| RETAIN-12 | `render/target_contract.FUTURE` | Same shape: gate-grepped, spec-asserted, and its own evidence row exists. Frozen and invisible to `check()` by design. |
| RETAIN-13 | `resources.retryAttempts` legacy option | Documented, pinned, and exercised by the fuzz scenarios; its differing give-up semantics are the point. |
| RETAIN-14 | `scope_impl.Scope.use` (a one-line identity) | It is the contract's "borrowed, never disposed" verb; the no-op body **is** the semantics. |
| RETAIN-15 | `blueprint_schema`'s `local function p(spec) return spec end` (~200 call sites) | An identity function that looks like pure indirection; it is a Luau strict-mode annotation idiom. Removing it is a ~200-line diff for zero runtime effect and a non-obvious inference risk. |
| RETAIN-16 | `table.luau` `columnDim` vs `headerDim` | Both call `resolveDim`, deliberately differently: cells resolve non-reactively (they remount on width change) while headers are cached memos so the header re-solves in place. |
| RETAIN-17 | `table.luau` vs `virtual_list.luau` parallel structure | Not duplicates: Table does variable-height cumulative flow with a per-key memo cache; VirtualList does uniform-height canvas arithmetic with row-scope-owned memos. Unifying is a redesign. |
| RETAIN-18 | five one-line public fields on publicly exported module tables (`spring.MAX_SUBSTEP`, `value_model.defaultFormat`, `path_shapes.MAX_CONTROL_POINTS`, `rating.FILLED/EMPTY`) | Zero external references, but `LuauUI.valueModel` and `LuauUI.pathShapes` export whole module tables, so these are reachable public surface. An API change for one line each. |
| RETAIN-19 | the two scope-less `adaptive.conditions` calls in `tests/adaptive.spec.luau` | Each constructs its own core per case, so the six memos die with a core that lives one `it()`. The leak needs a long-lived core; the documentation was the live problem (C-12). |

---

## ESCALATED — decision packets, not implemented

Full packets in `decision-packets.md`.

| ID | What |
|---|---|
| DP-1 | RR-1-R1 — motion-clock quarantine granularity (an eviction-policy choice) |
| DP-2 | ESC-1 — interactive-state theme vocabulary (a feature) |
| DP-3 | ESC-2 — pointer-zone callbacks receive layout-space rects (a consumer sweep) |
| DP-4 | ARCH-F6 — two exemption mechanisms, and a record correction |
| DP-5 | the `imperative` conformance scorecard is nondeterministic |
| DP-6 | three consolidations found and evidenced but deliberately not taken: `presenter.autoGroups`/`layoutGroups`; `sheet_model`'s 8 twice-emitted state rules; the 16-entry `SLOT_FILL_TOKEN`/`chromeFillOf` mirror |

Two further **defects** were found while tracing and are reported, not fixed,
because fixing them is a behaviour change:

- `src/present/presenter.luau` answers "does surface H own path P?" at five sites
  with **two different rules** — one segment-aligned (`isPathPrefix`), four bare
  prefix. Two presented surfaces named `Settings` and `SettingsPanel` would
  cross-route focus visuals, tap dispatch and adjust-gating. (DP-6 context.)
- `src/client/roblox_env.luau`'s `keyboardOcclusionRect` listener is guarded by
  `UserInputService.OnScreenKeyboardVisible` evaluated **once, at bind time**, so
  on an ordinary client the soft keyboard is not up when `bind` runs and the
  listener is never connected for the session.
