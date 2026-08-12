# Hosted Row-Actions (VirtualList) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `newRowActions`-shaped swipe-actions capability hosted natively by `newVirtualList` whose CLOSED rows cost ≤5% time and ≤4 instances over unwrapped rows under `artifacts/row-actions/perf_workload.luau`.

**Architecture:** Per `docs/plans/row-actions-hosted-mode-design.md` (read it first, it is the spec): a shared per-list pointer dispatcher on VirtualList's existing per-row `Hit` Button; a lazily-built per-row gesture engine (row_actions core, no blueprint); slide via the presentation channel (`setPresentationOffset`); one shared tray overlay `When` per list; commit-height through the existing `rowHeightDim` memo. Standalone and Table row_actions modes stay byte-identical.

**Tech Stack:** Luau, Lune test runner (`./run-tests.sh`, `tools/test.sh N`), stylua, python gate checks.

## Global Constraints

- Working dir: `GameStudio/ui/LuauUI`, branch `row-actions-perf`. NO git worktree (gates cannot run in one — known trap).
- Full suite must stay green at every commit: `tools/test.sh 4049` (floor rises as tests are added; never falls).
- `stylua src tests` clean before each commit.
- NO behavior change to standalone/Table row_actions — `tests/row_actions*.spec.luau` and `tests/table.spec.luau` are the net; never edit an existing assertion to make it pass (adding the two `_open()` precursor lines in Task 1 is the only sanctioned existing-test edit).
- Perf claims: multi-run MEANS (≥3 runs), never single runs; the fling measure has ~2–5pp second-world bias until Task 7 de-biases it.
- `reorderable` + `rowActions` on one list = explicit `error()` (v1 unsupported).
- All new copy is theme/localization-neutral (no player-facing strings involved here).

---

### Task 1: Vacuous coordinator tests + duplicate comment cleanup (parked items, independent)

**Files:**
- Modify: `tests/row_actions_input.spec.luau:2723-2764` (two tests)
- Modify: `src/controls/row_actions.luau:1974-1989` and `:2020-2030` (duplicated comment blocks)

**Interfaces:** none (test hygiene only).

- [ ] **Step 1:** In the test `"a sibling row starting a gesture (coordinator claim) during A's commit..."` (line ~2723), insert before `w.rowA._commitFirst("trailing")`:

```lua
w.rowA._open("trailing") -- claims the coordinator (this IS what `claimed` tracks)
w.settle()
expect(w.rowA._isOpen()).toBe(true)
```

- [ ] **Step 2:** Same three lines at the top of `"scroll movement during A's commit..."` (line ~2742), before its `_commitFirst`.
- [ ] **Step 3:** Prove the precursor bites: temporarily comment out the `claimed._close()` call inside `bindScroll` (`src/controls/row_actions.luau:363-369`) and run the two tests — the scroll test MUST now fail (if it still passes, the test is still vacuous; stop and fix). Restore the line. Similarly verify the sibling-claim test exercises `newCoordinator.claim`'s `previous._close()` branch (`src/controls/row_actions.luau:333-344`) by temporarily breaking it. Restore.
  - NOTE the expected semantics: an OPEN row that then `_commitFirst`s is mid-commit while claimed; the guarded behavior is "commit completes exactly once despite the close request". If adding `_open` first makes a test genuinely fail against real behavior, that is a REAL finding — report it, do not paper over it.
- [ ] **Step 4:** Delete the verbatim duplicate comment copies at `src/controls/row_actions.luau:1982-1989` (keep 1974-1981) and `:2026-2030` (keep 2020-2024). Grep both spec files and `src/controls/row_actions.luau` for any OTHER immediately-repeated identical comment blocks (`awk` pairwise or manual scan); the prior sweep found exactly these 2 — if you find more, clean them; if not, note "2 found, not ~7" in the commit body.
- [ ] **Step 5:** `tools/test.sh 4049` green; stylua; commit `test(row-actions): de-vacuate coordinator commit tests + comment dedup`.

### Task 2: Engine core extraction inside row_actions.luau (`buildHosted`)

**Files:**
- Modify: `src/controls/row_actions.luau`
- Test: `tests/row_actions_hosted.spec.luau` (new)

**Interfaces:**
- Produces: `row_actions.buildHosted(LuauUI, core, spec) -> HostedEngine` where `spec` = the standard row-actions spec fields (`id`, `leading`, `trailing`, `fullSwipe`, callbacks) PLUS `paths: { content: string, trayLeading: string?, trayTrailing: string? }` (rect-lookup paths the host owns) and `onSlide: (px: number) -> ()` (host applies the visual slide), `onCommitHeight: ((px: number?) -> ())?`.
- `HostedEngine` = `{ pointerHandlers = {onPointerDown, onPointerMove, onPointerUp, onPointerCancel}, open, close, _open, _isOpen, _commitFirst, dump, trayState: Readable, dispose }` — `pointerHandlers` signature identical to the existing `_pointerHandlers` (`(path, pos, rectOf)` contract, `src/controls/row_actions.luau:1799+`).
- `trayState` (memo) = `nil | { edge: "leading"|"trailing", actions: {ActionSpec}, revealPx: Readable }` — what a host overlay needs to build/position trays.

**Approach constraint:** do NOT physically split the file. `buildHosted` is a sibling entry point that reuses the SAME internal closures `build()` uses (state signals, axis lock via `row_actions_state`, velocity, coordinator claim, commit ladder, `composeWithReorder`-compatible handler shape). Where a closure currently reads a blueprint-node rect by a hardcoded own-path (root/Content/tray ids derived from `spec.id`), thread the path through a small internal `pathsOf` indirection that `build()` fills with today's values (byte-identical behavior) and `buildHosted` fills from `spec.paths`. The slide: where `build()` writes the `contentOffsetX` signal, route through an internal `applySlide(px)` that `build()` keeps as the signal write and `buildHosted` forwards to `spec.onSlide`. Menu (`presentModal`) and keyboard-Delete logic come along unchanged.

- [ ] **Step 1:** Write failing tests in `tests/row_actions_hosted.spec.luau` driving `buildHosted` with a stub `rectOf`/paths (no mounted tree — precedent: the bare-path `composeWithReorder` unit tests at `tests/row_actions_input.spec.luau:2400-2511`): (a) horizontal drag past axis lock calls `onSlide` with monotonic px and `trayState` becomes `{edge="trailing"...}`; (b) release past open threshold → `_isOpen() == true`; (c) full-swipe past commit threshold fires the first trailing action exactly once; (d) `close()` → `onSlide(0)` and `trayState == nil` after settle; (e) coordinator: two engines, opening B closes A; (f) vertical drag never calls `onSlide` (axis lock).
- [ ] **Step 2:** Run: `lune run tests/run -- --filter row_actions_hosted` (check `tests/run` for the actual filter flag; else run full suite) — expect FAIL (buildHosted undefined).
- [ ] **Step 3:** Implement `buildHosted` per the approach constraint. Motion clock: reuse the same `bindMotion`/`nowFn` seam `_pointerHandlers` already asserts (`src/controls/row_actions.luau:1738-1745`); tests bind it the way existing `_pointerHandlers` unit tests do.
- [ ] **Step 4:** Tests pass; FULL suite `tools/test.sh 4049` green (the refactor's indirections must not shift standalone behavior).
- [ ] **Step 5:** stylua; commit `feat(row-actions): buildHosted engine entry (no blueprint) behind pathsOf/applySlide indirection`.

### Task 3: VirtualList seam — spec.rowActions, shared dispatcher, lazy engines

**Files:**
- Modify: `src/controls/virtual_list.luau` (row builder ~`:1275-1367`, spec table `~:120`, dispose path)
- Test: `tests/virtual_list_row_actions.spec.luau` (new)

**Interfaces:**
- Consumes: `row_actions.buildHosted` (Task 2 signature).
- Produces: `newVirtualList` spec field `rowActions: ((item: any) -> RowActionsSpecFields?)?` (nil per item = that row unwrapped); internal `list._hostedDebug()` (test-only accessor) returning `{ engineCount: number, engagedKey: string? }`.

Mechanics:
- If `spec.rowActions ~= nil and reorderable` → `error("newVirtualList: rowActions + reorderable is unsupported (v1)", 0)`.
- Build ONE shared handler table per list (four functions). Wire onto every row `Hit` Button (`virtual_list.luau:1322-1331`) ONLY when `spec.rowActions ~= nil` — a rowActions-less list must construct the byte-identical Hit it does today (mount-identity guarantee).
- Path→key: rows mount at `{path}/[{key}]` (ForEach, `src/mount.luau:287`); maintain `hitPathByKey`/`keyByHitPath` maps updated in the row factory (item scope own() removes on dispose) — do not parse paths.
- Lazy engine cache `enginesByKey: { [string]: HostedEngine }`, created on first `onPointerDown` for that key via `row_actions.buildHosted` with `paths.content` = the row's cell-content path and tray paths pointing into the Task 4 overlay; engines dispose with the LIST scope (a windowed-out row keeps its engine — scroll-close will have closed it anyway; note in a comment).
- `onSlide` v1 = write a per-list `engagedOffset` signal + `engagedKey` signal (Task 4 consumes both; presentation write lives there).
- ONE shared coordinator per list (reuse `row_actions.newCoordinator` + `bindScroll` against the list's own scroll observer so scroll closes the open row — find the existing scroll-position observable in `virtual_list.luau` (`scrollTop`) and adapt `bindScroll`'s controller contract (`src/controls/row_actions.luau:363-369`, stub example at `tests/row_actions_input.spec.luau:2747-2755`)).

- [ ] **Step 1:** Failing tests: (a) list with `rowActions` mounts and `_hostedDebug().engineCount == 0` after mount AND after steady scrolling (laziness); (b) pointer-down+horizontal-move on a row's Hit path (drive via the fake adapter the way `tests/virtual_list.spec.luau` drives pointer input — copy its idiom) creates exactly 1 engine and sets `engagedKey`; (c) `reorderable+rowActions` errors; (d) a `rowActions` list's row subtree paths are IDENTICAL to a plain list's except Hit props (compare `adapter.paths()` sets); (e) scroll while open → row closes (`engagedKey` nil after settle).
- [ ] **Step 2:** Run, expect FAIL. **Step 3:** Implement. **Step 4:** Suite green (floor +Task-2 count). **Step 5:** stylua; commit `feat(virtual-list): rowActions seam — shared dispatcher, lazy hosted engines`.

### Task 4: Shared tray overlay + presentation slide + commit height

**Files:**
- Modify: `src/controls/virtual_list.luau` (canvas children `~:1274`, `rowHeightDim` memo `~:1298`), `src/controls/row_actions.luau` (expose internal tray-builder for hosted reuse if not already reachable)
- Test: extend `tests/virtual_list_row_actions.spec.luau`

**Interfaces:**
- Consumes: `engagedKey`/`engagedOffset` signals, `trayState` from engines (Task 2/3).

Mechanics:
- Canvas gets ONE `UI.When({ id = "RowActionsOverlay", condition = engagedMemo, thenView = ... })` AFTER the rows ForEach (tray Buttons natively tappable in the revealed strip; design §4). `thenView` builds tray group(s) from the engaged engine's `trayState` via the same tray construction `build()` uses (`buildTray` internals — reuse, don't duplicate: same compactLabel degrade ladder, same roles/icons), positioned `anchor = "topLeft"`, `offsetY` = engaged row's canvas offset ((index-1)*pitch — same math as the row `offsetY` memo `virtual_list.luau:1288-1297`), height = row height, width sized to reveal.
- Slide: observe `engagedOffset` in the LIST's scope; apply `controller.setPresentationOffset(contentPath, px, 0)` to the engaged row's cell-content path; restore to nil/0 on disengage. Obtain the controller through the same contribution/bind walk row_actions uses for `bindMotion` (`renderer.luau:187` names the authority: `controller.setPresentationTransform / setPresentationOffset`); `tests/lib/fake_target` models `presentationOffset` (`fake_target.luau:255`).
- Commit height: inside the EXISTING `rowHeightDim` memo (`virtual_list.luau:1298-1300`), when `spec.rowActions ~= nil`, compose: engaged row + engine committing → engine's collapse height. Static branch on `spec.rowActions` presence so plain lists build the same memo body as today.
- Overlay z + interactivity: a tap on a revealed tray Button fires the action (assert engine fires exactly once); a tap on the slid content closes (tap-to-close rides the dispatcher).

- [ ] **Step 1:** Failing tests: (a) open a row → overlay mounts trays at the row's offsetY, `presentationOffset` on the content path equals the engine's reveal px; (b) tray Button tap fires `onAction` once and row closes/commits per role; (c) disengage → overlay unmounts, `presentationOffset` cleared, tree returns to closed shape; (d) commit on destructive → `rowHeightDim` collapses for that row only; (e) full-swipe commit works end-to-end on the mounted tree.
- [ ] **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** Suite green. **Step 5:** stylua; commit `feat(virtual-list): shared tray overlay + presentation slide + commit height`.

### Task 5: Behavior-parity + mount-identity differential proofs

**Files:**
- Test: extend `tests/virtual_list_row_actions.spec.luau`; new `tests/virtual_list_row_actions_identity.spec.luau`

**Interfaces:** consumes everything above; produces the shipping proof the charter requires.

- [ ] **Step 1 (parity):** Port the SEMANTICS (not paths) of the core standalone suite to hosted mode: leading & trailing reveal, open threshold vs snap-back, fullSwipe commit, irrevocable commit (sibling claim + scroll + outside tap during commit — mirror the three Task-1 tests), one-open across rows, keyboard Delete on focused Hit, `fullSwipe = false` variant. Each as its own `it(...)`.
- [ ] **Step 2 (identity):** Differential proof (incremental-layout precedent): build plain list world A and `rowActions` list world B with identical items; assert `adapter.paths()` of B == A ∪ {overlay When node} and every shared path's node class/rect identical; then engage+disengage a row in B and re-assert (tree returns to closed shape, zero leaks — engine count may stay 1, instances must not).
- [ ] **Step 3:** Suite green; update the row-actions gate's suite-check names if any new named ✓ lines are worth pinning (`tools/lune/gate_manifest.luau:2990-2995` pattern). stylua; commit `test(virtual-list): hosted parity + mount-identity differential proof`.

### Task 6: Docs + example

**Files:**
- Modify: `docs/reference/api.md` (newVirtualList section: `rowActions` field, v1 reorderable exclusion, hosted-vs-standalone cost note), `examples/gallery/scenarios/row_actions.luau` (add/adjust a VirtualList-hosted variant), `docs/plans/row-actions-perf-mission.md` (status → CLOSED BY docs/plans/row-actions-hosted-mode-design.md)
- Run `python3 tools/check_docs_cli.py` if that's the docs gate (check `tools/` listing; the 4c607a7 commit ran `check_docs_cli`).

- [ ] Steps: write docs; run docs check; suite green; stylua; commit `docs(virtual-list): rowActions hosted mode`.

### Task 7: Workload de-bias + hosted measurement

**Files:**
- Modify: `artifacts/row-actions/perf_workload.luau`
- Keep: `artifacts/row-actions/perf_floor_experiment.luau` (scoping evidence the design doc cites; add a header line marking it historical)

Mechanics (design §Measured floors):
- Keep drive shapes/constants byte-identical. Replace the one-pass measure with an interleaved schedule per shape: split `SAMPLES` into 4 blocks (base, wrapped, base, wrapped), concatenating each world's two blocks — kills the second-world GC bias the A/A control exposed (~2–5pp on fling). Print the A/A caveat in the header comment.
- Wrapped world's cell integration switches from manual `newRowActions` wrap to `rowActions = actionsFor` on the list spec (the blessed hosted integration). KEEP the old manual-wrap world as a third INFORMATIONAL measurement labeled `legacy-standalone-wrap` (transparency: the gate budget applies to the hosted numbers; legacy numbers show the old shape's cost).
- [ ] **Step 1:** Implement; run 3×; record means. Expected: hosted ≤5% steady AND fling, ≤4 (measured floor: ~0.08) — if not, STOP and profile before proceeding (scope totals, not step-p50).
- [ ] **Step 2:** Commit `perf(row-actions): de-biased interleaved workload + hosted-mode measurement`.

### Task 8: Gate ceilings 5/5/4 + mutation-bite proof + evidence regen

**Files:**
- Modify: `tools/check_row_actions_matrix.py:54-56`, `artifacts/row-actions/device-matrix.md` (perf section: new 3-run mean numbers, methodology note, legacy numbers), `tools/lune/gate_manifest.luau:2999-3012` (re-baseline note → restored-budget note)

- [ ] **Step 1:** `STEADY_CEILING_PCT = 5.0`, `FLING_CEILING_PCT = 5.0`, `INSTANCE_CEILING = 4.0`; update device-matrix.md numbers from Task 7's runs.
- [ ] **Step 2 (mutation bite):** (a) temporarily write `6.1%` into device-matrix.md's steady cell → `python3 tools/check_row_actions_matrix.py` must EXIT NONZERO; restore. (b) same for fling and instances cells. (c) temporarily loosen a ceiling constant to 60 → must pass → restore (proves the constant is live). Record all three in the commit body.
- [ ] **Step 3:** `python3 tools/check_row_actions_matrix.py` PASS; commit `gate(row-actions): budget restored to ≤5%/≤5%/≤4 with mutation-bite proof`.

### Task 9: Full gate + RascalRally suite

- [ ] **Step 1:** Stale lock check: `ls /tmp/luauui_prior_gates.lock 2>/dev/null && pgrep -f prior_gates.sh || true` — if lock exists with NO live prior_gates process: `rmdir /tmp/luauui_prior_gates.lock`.
- [ ] **Step 2:** `nohup tools/gate.sh row-actions > artifacts/row-actions/gate-run.log 2>&1 &` — DETACHED (the prior-gates sweep inside runs >1hr); poll the log; requirement: exit 0, all checks PASS, `prior-gates-rerun.txt` ends `DONE` with only allowlisted FAIL_RECOVERABLE lines.
- [ ] **Step 3:** RascalRally: run its suite per `games/RascalRally/code` convention (root CLAUDE.md: LuauUI and RascalRally move together; RR has zero rowActions call sites per `artifacts/row-actions/rr-compat.md`, so expectation = green with no changes; still update/extend the game-side compatibility evidence per the standing rule — at minimum re-run its suite against the new LuauUI src and record the count).
- [ ] **Step 4:** Final full LuauUI suite; stylua; final commit; update `docs/plans/row-actions-perf-mission.md` status if not already.

### Task 10: Icons — fresh Open Cloud key, upload, ids

**Files:** `GameStudio/tools/API_KEYS.txt` (ROBLOX_API_KEY), `src/themes/standard_icons.luau` (ids pushed by the tool), `assets/icons/provenance.md`, `assets/icons/upload-manifest.json`

- [ ] **Step 1:** Fresh key: create.roblox.com → Open Cloud → API keys — scope `assets` read+write (browser session; see `assets/icons/provenance.md:95-145` "Pending upload" for the exact failure being resumed).
- [ ] **Step 2:** From `GameStudio/ui/LuauUI/`: `/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/.venv/bin/python tools/upload_icons.py` then `--recheck` (expect Approved/Image).
- [ ] **Step 3:** Verify `standard_icons.luau` now carries non-nil `contentId` for `trash`/`flag`; run `tests/compact_label.spec.luau`'s resolve tests + full suite; update provenance.md's Pending section to CLOSED; commit `feat(icons): trash/flag uploaded — content ids live`.

## Execution notes

- Tasks 1 and 10 are independent of 2-9. Tasks 2→3→4→5 are strictly ordered. 6 after 4. 7 after 4 (needs hosted mode). 8 after 7. 9 last.
- Suite floor bookkeeping: after each task that adds tests, bump the `tools/test.sh` floor argument you verify with to the new pass count; Task 9 updates the gate manifest floor (`tools/lune/gate_manifest.luau:3019`) to the final count.
