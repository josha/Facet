# Files changed by the Step 5.5 cleanup

There is no git in this tree, so this is the hand-maintained list of every file the
stage touched. Nothing else under `src/`, `tests/`, `tools/`, `docs/` or
`examples/` was modified.

## Source (`src/`)

| File | What changed |
|---|---|
| `src/controls/contract.luau` | **added** `contract.enabledNow(e)` and `contract.enabledIn(use, e)` |
| `src/controls/slider.luau` | `isEnabled` body → `contract.enabledNow`; `focusableTrack` memo → `contract.enabledIn`; new `require("./contract")` |
| `src/controls/stepper.luau` | `isEnabled` body → `contract.enabledNow`; `decEnabled`/`incEnabled` guards → `contract.enabledIn`; new require |
| `src/controls/picker.luau` | `isEnabled` body → `contract.enabledNow`; new require |
| `src/controls/disclosure_group.luau` | `isEnabled` body → `contract.enabledNow`; new require |
| `src/controls/rating.luau` | `isEnabled` body → `not readOnly and contract.enabledNow(...)`; new require |
| `src/controls/popup_button.luau` | `patternEscape` hoisted out of `build()` to module scope |
| `src/controls/table.luau` | same hoist |
| `src/controls/text_input.luau` | same hoist |
| `src/controls/virtual_list.luau` | same hoist |
| `src/render/renderer.luau` | `findNode(path)` hoisted above `controller.refresh` and reused by the dirty loop (a per-dirty-entry closure deleted); `scrollAncestorOf` **deleted**, `scrollToVisible` now reads `scrollHostOf[path]`; `renderer.compactForm(node.props)` called once instead of twice |
| `src/layout/solver.luau` | **added** `gridColumnCount(node, inner, gap, minCol)`; measure and arrange both call it; two unused margin locals in `gridColumnMin` → `_` |
| `src/mount.luau` | three structural-region blocks → one `STRUCTURAL` dispatch table + one shared bookkeeping tail |
| `src/core/scope_impl.luau` | `factory(counts, onDoubleDispose, onCleanupError)` → `factory(counts, report)`; both diagnostic strings now formatted here; header documents the aliasing rule |
| `src/core/custom.luau` | passes `fail` as the single `report` channel |
| `src/core/fusion_adapter.luau` | passes one `report` closure |
| `src/core/imperative.luau` | passes one `report` closure |
| `src/motion/clock.luau` | `Stats.transactions` doc comment corrected (`transactions <= steps`, equality iff healthy) |
| `src/render/authority.luau` | header now states `host` is declared-but-unused; the union member is unchanged |
| `src/render/transitions.luau` | `self.activeCount` and `self.isRunning` **deleted** |
| `src/blueprint_schema.luau` | `schema.isContainer` **deleted**; `schema.TYPE_CHECKS` and `schema.TRANSITION_FORMS` export assignments **deleted** (`table.freeze` moved onto the `TRANSITION_FORMS` local) |
| `src/present/presenter.luau` | `graph.focused = graph.focused` self-assignment **deleted**; `isPathPrefix` hoisted above `filterHidden`, which now calls it instead of inlining the same expression |
| `src/themes/package.luau` | dead comment-only `if` branch and its unused local **deleted** |
| `src/themes/token_sync.luau` | `weightNameOf` and `pathForAttribute` **deleted**; `attributeForPath(records, path)` **added**; header list updated |
| `src/themes/standard_icons.luau` | `SCHEMA` and `SOURCE_PX` **deleted** |
| `src/client/theme_controller.luau` | `SUPPORTED_SCHEMA` **deleted**; local `attributeForPath` **deleted**, call site → `token_sync.attributeForPath` |
| `src/client/text_premeasure.luau` | `isSettled` **deleted** |
| `src/client/roblox_env.luau` | `local Players = game:GetService("Players")` and its `local _ = Players` no-op **deleted** |

## Tests (`tests/`) — additions only, nothing weakened or removed

| File | What changed |
|---|---|
| `tests/runtime_quarantine.spec.luau` | +2 cases: the RR-5-R1 double-dispose pin (both directions) and the RR-1-R2 stats pin (both directions) |
| `tests/presenter_drag_integration.spec.luau` | +1 case: RR-3-R1, two flights airborne, registry disposed mid-air, A/B against a control rig |
| `tests/conformance/suite.luau` | +1 check: `scope-cleanup-quarantined-and-early-child-is-not-a-double-dispose`, which therefore runs against all three cores |

## Tools

| File | What changed |
|---|---|
| `tools/lune/gate_manifest.luau` | new `code-simplicity-cleanup` gate; `theme-packages-and-skinning`'s `metric-snapshot-single-source` now runs `check_flat_baseline` instead of `cmp`-ing two stored files |
| `tools/lune/_theme_baseline.luau` | target path is now REQUIRED (was defaulting to a stored comparison input) |
| `tools/lune/_probe_public_surface.luau` | **new** — dumps the public export tree + DEPRECATIONS for the before/after byte comparison |
| `tools/lune/_probe_carryovers.luau` | **new** — runs each Step 5 residual's own reproduction verbatim |
| `phases.json` | registers the new gate; `sponsor-framework-gaps.next` → `code-simplicity-cleanup` |

## Docs

| File | What changed |
|---|---|
| `docs/reference/api.md` | `AdaptiveStack` example now passes `{ scope = … }`; new paragraph documenting `opts.scope` and the six-memo cost |
| `docs/guide/02-architecture.md` | the `host` authority bullet now says it is declared but unused |
| `docs/handoff/SHOWCASE_DEVICE_PASS.md` | the "do not run `_theme_baseline` bare" warning replaced with a note that it now refuses |
| `docs/plans/luauui-consolidated-roadmap.md` | Step 5.5 section. **Omitted from this list until verifier PG-4 caught it** — recorded now |

## Review response (2026-07-28, after the three fresh-context reviews)

Fixes for the three MAJOR findings. Full rationale and proofs in `review-response.md`.

| File | What changed |
|---|---|
| `tests/runtime_quarantine.spec.luau` | **PG-1** — the RR-1-R2 unhealthy branch asserted `transactions <= steps`, which any counting scheme satisfies; now asserts the exact measured `transactions == 0`. Mutation-proved: moving `transactions += 1` out of the commit phase left the old assertion green at 2571 and turns the new one red (1 failed / 2570 passed) |
| `tools/prior_gates.sh` | **PG-2 — new.** Re-runs every gate preceding a stage and writes the roll-up; the gate list is derived from `phases.json` rather than hard-coded, so a newly registered gate is covered when it lands. Waits for the load average to settle before each gate — without it, `phase-3-pilot`'s soak+bench check failed in-batch 2/2 and passed standalone 2/2 (mitigation only; see `review-response.md` and `perf-after.md`) |
| `artifacts/code-simplicity-cleanup/studio/*` | five-view matrix (all 5 rows, re-run at stamp `efbe185e-2570354`), the `scroll_host` keep-visible row for the changed `scrollToVisible` lookup, the full desktop scenario report, and a rewritten README |

## Bench normalization (2026-07-28, the follow-up to the flaky-gate finding)

Raw wall-clock was not a stable instrument: the same source measured 1.29× quiet,
1.40× mid-batch, 1.54× with Studio open. Full rationale, all four verification
results and the honest limits are in `perf-after.md`.

| File | What changed |
|---|---|
| `bench/scenarios.luau` | **added** `zz-yardstick-cpu` — a LuauUI-free, deterministic, allocation-free CPU workload (~0.23ms) used as the divisor. An allocation-heavy variant was trialled and rejected (11% vs 3% match to the median gated scene's load response); the rejection is recorded in the file so nobody re-runs the experiment |
| `tools/lune/bench.luau` | measures the yardstick **before and after** the scenes and averages it; every scene gets `p95_norm = p95_ms / yardstick`; the regression rule now compares **normalized ratios** against the baseline, with the raw `REGRESSION_FLOOR_MS` still exempting micro scenes. Falls back to the old raw rule with a printed NOTE if the baseline has no `p95_norm`. Reports yardstick **drift** and prints a loud UNTRUSTWORTHY RUN warning above 15% — which deliberately does **not** suppress the failure, since suppressing would let a real regression be laundered by running on a busy machine |
| `bench/baseline.json` | **re-frozen** from the median of 3 quiet runs, storing `p95_norm` as the gated value (`p95_ms` kept as descriptive only). Before re-freezing, the drift since 2026-07-25 was verified to be a uniform environment shift (4 gated scenes all 1.08–1.29×, no outlier) rather than a code regression |
| `tools/lune/gate_manifest.luau` | **PG-2** — `prior-gates-unregressed` regenerates its `after` operand through `tools/prior_gates.sh` instead of comparing two STORED files and executing nothing. **PG-3** — `performance-unregressed` now runs `tools/bench.sh` before reading `artifacts/bench.json`, so it cannot pass on a stale artifact written by a different gate. Both notes rewritten to record the defect they close |

No `src/` behaviour changed in the review response. Both files mutated as proof
(`src/motion/clock.luau`, `src/core/custom.luau`) were backed up and restored;
sha256 recorded in `review-response.md`, `stylua --check` exit 0, suite green.

## Formatting

`stylua src tests tools bench examples` was run once after the edits and
`stylua --check` exits 0. No file was reformatted beyond the lines the edits
touched (the two whitespace-only hunks stylua reported were orphan blank lines
left by deletions in `standard_icons.luau` and `theme_controller.luau`).
