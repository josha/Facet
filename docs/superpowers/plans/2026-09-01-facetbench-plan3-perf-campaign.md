# FacetBench Plan 3 — Baselines + Facet Perf Campaign (Plan 3 of 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Commit drift-gated public baselines (Lune + Studio, all sizes), then land the profiling-ranked Facet fixes P1–P5 with red-first demonstrators until update-class steps cost ≤0.5 ms and structural steps ≤1 ms at size L, then re-baseline and publish the after-picture.

**Architecture:** Two repos. FacetBench (standalone) gets chores, baselines, chart page, and re-baselines. Facet (production, RascalRally lockstep) gets the five fixes, each an independent mission: counter-based demonstrator shown red → fix → Facet suite green → FacetBench before/after at S/M/L → RascalRally suite green. RED-TEAM + live canary close the campaign.

**Tech Stack:** As Plans 1–2. Facet repo toolchain: `tools/test.sh`, `tools/verify.sh {affected|fast|full}` (DAG gates; standing traps: the prior-gates lock refuses SILENTLY exit 2 and a backgrounded run ORPHANS it — never background verify.sh; >3 concurrent lune runs die silently). RascalRally suite per `games/RascalRally` tooling.

**Spec:** `GameStudio/ui/Facet/docs/superpowers/specs/2026-08-31-facetbench-and-perf-fixes-design.md` — Part 2 as revised by Addendum 2 (P1–P5, per-class targets). The profile evidence is FacetBench `artifacts/profile/PROFILE_REPORT.md` (gitignored scratch — Task 1 promotes the harnesses; the REPORT's numbers are quoted in each fix task below).

## Global Constraints

- FacetBench work: all Plan 1/2 constraints stand (stylua find-form, SPECS registration, cycle-safety, pristine vendor, check.sh green before commit).
- **Facet repo work (constitution-bound):** every Facet-source-touching task runs `tools/test.sh` (full suite green; count currently ~7875/0) AND `tools/verify.sh affected` (foreground only) before its commit, plus the RascalRally lune suite (both Rojo projects' relevant tests; ~3541/0) as lockstep evidence. NO public API changes; NO behavior changes — layout results must stay pixel-identical (each fix carries an invariant spec comparing against a forced full solve across the device matrix INCLUDING 320x640). `UseFacetSponsor` flags and legacy Sponsor modules untouched.
- **Demonstrators are counter-based, never wall-time asserts** (loop-shape bimodality + machine variance): solver/renderer expose cheap work counters (extending the existing `result.work.arranged/measured/skipped` and `controller.stats()` families); a demonstrator asserts a COUNT bound (O(touched)), is shown RED at pre-fix HEAD in the task report, and lands green in the same commit as its fix. Wall-time and gcinfo numbers are report evidence, not test asserts.
- **Before/after protocol per fix:** FacetBench facet-adapter step p50 at S/M/L via `run_one_lib` (samples 300) captured pre-fix and post-fix in the task report (the sibling checkout serves FacetBench live — no vendoring; FacetBench tests are NOT run against a broken Facet mid-task, only at task end when Facet suite is green).
- Fix order is dependency-ordered: P1 → P2 → P3 → P4 → P5 (P2 needs P1's cache semantics settled; P4 needs P2's changed-set; P5 needs P1+P2). P3 is independent and MAY be reordered earlier only by controller ruling.
- The target is aspirational-with-honesty (spec Addendum 1 rule 3): never met by weakening a workload, instrument, or demonstrator.
- Studio drives follow Plan 2's standing traps (marker discipline, console transport, CharacterAutoLoads=false, evidence rule: live claims ship dump fragments).

---

### Task 1: FacetBench opening chores + promote profiling harnesses

**Files:**
- Modify: `runner/studio/main.luau` (+snapshot-compare bite), `runner/lune/lib/schema.luau` + `runner/lune/run_matrix.luau` + `tools/studio_scrape.luau` (run.device), `workloads/war_room_inventory.luau` (sort tiebreak), `tests/matrix_util.spec.luau` ({} case), `tests/vendor_integrity.spec.luau` (scanner name classes), `runner/lune/lib/scene.luau` (_lastListStates → return value), `docs/studio-runs/2026-08-31-first-live-matrix.md` (0.1%→0.07%), `CONTRIBUTING.md` (live-only wording upgrade once the bite exists)
- Create: `tools/profile/` (the five attribution harnesses from artifacts/profile/, cleaned + committed with a README stating they are measurement scratch-lab tools, monkey-patch based, NOT part of check.sh), plus copy `artifacts/profile/PROFILE_REPORT.md` → `docs/profiling/2026-09-01-attribution.md` (public evidence)
- Test: extend `tests/run_one.spec.luau`/schema spec for run.device; a Lune-testable unit for the snapshot-compare helper

Batched dispatch (SDD batch rule): each item is small and independent.

- [ ] **Step 1: live-only behavioral bite** — `runCombo` takes `adapter.snapshot(handle)` once after mount and asserts it differs in `beforeUnmount` (both outside measured windows; skip when status ≠ ok). Extract the compare into a pure helper so a Lune spec can bite it (a stub adapter with constant snapshot must fail). Upgrade CONTRIBUTING's "review obligation" sentence to name the mechanical gate.
- [ ] **Step 2: run.device** — envelope `run.device` (string, required): Lune = `{process.os}-{process.arch}`; Studio scrape takes `--device` (required arg, recorded from the drive's environment). Schema requires non-empty string; biting cases; existing committed results get a one-time migration note in their doc (do NOT rewrite committed artifacts — schema accepts absent device for envelopes stamped before 2026-09-01 via an explicit dated grandfather clause with a comment).
- [ ] **Step 3: sortedOrder tiebreak on key** (war_room_inventory) — deterministic across runtimes; battle_hud/killfeed unaffected; spec determinism assertions still pass (counts unchanged).
- [ ] **Step 4: small test/robustness items** — acceptChild `{}` case; closure scanner accepts dot/dash in require names; `scene.validateSteps` returns the list-state set instead of `scene._lastListStates` (update the one consumer); doc digit 0.1%→0.07%.
- [ ] **Step 5: promote harnesses** — `tools/profile/{attribution,step_kinds,scaling,alloc,foreach_probe}.luau` (names per what exists in artifacts/profile), stylua'd, with `tools/profile/README.md`; public report copy under `docs/profiling/`. These are excluded from check.sh (they monkey-patch and take minutes) — README says so.
- [ ] **Step 6:** `tools/check.sh` green; `lune run tests/run` green; ONE commit: "feat: plan-3 chores (live bite, run.device, tiebreak, robustness) + promoted profiling harnesses"

### Task 2: Drift-gated Lune baselines (all sizes) + chart page

**Files:**
- Create: `tools/check_baselines.luau` (+spec), `tools/chart.luau` (+spec), `results/lune-<date>-<sha>.json` (committed), `results/chart.html` (generated, committed)
- Modify: `CONTRIBUTING.md` (baseline submission gains the drift gate + device row)

- [ ] **Step 1:** `check_baselines.luau`: validates every `results/*.json` row: schema-valid AND (for ok rows) `yardstickDriftPct ≤ 10` for mode=lune (studio rows exempt from the Norm/drift gate but must carry the device field per Task 1) — biting spec (a 12% drift row fails). Wire into check.sh.
- [ ] **Step 2:** Run the full Lune matrix at defaults (samples 1500) for ALL sizes: `lune run runner/lune/run_matrix --out results/lune-<date>-<sha>.json` (facet + _fixture produce ok rows; rivals live-only; flux unsupported — the HONEST headless baseline). Machine idle during the run (no concurrent suites). Gate passes; commit.
- [ ] **Step 3:** `tools/chart.luau`: reads every `results/*.json`, emits ONE self-contained `results/chart.html` (no external deps, inline JS/CSS): grouped bars per workload×size, loop stepP50Ms + frames frameP50Ms where present, per-framework columns in natural size order; unsupported/live-only rendered as labeled gaps, never zeros; a caveat footer (loop-mode Luau-side note + yardstick-Studio note, verbatim from CONTRIBUTING hazards). Spec: generated HTML contains the expected row labels and caveat strings for a fixture results dir. Commit: "feat: drift-gated baselines (lune, all sizes) + self-contained chart page"

### Task 3: Studio M/L sweep — the live before-picture

Live MCP task (Plan 2 Task 11 discipline: marker, transport, evidence rule, ≤300 loop samples).

- [ ] **Step 1:** Drive the full live matrix at **M and L** (loop mode samples 250; frames mode samples 300) for all frameworks + _fixture; battle_hud L frames-mode microprofiler captures for facet and vide (the before-picture that P1–P5 get judged against).
- [ ] **Step 2:** Scrape (with `--device`), validate, commit `results/studio-<date>-<sha>-ML.json`; regenerate chart.html; extend the evidence doc (or a new `docs/studio-runs/<date>-ML-sweep.md`) with the M/L tables — note where frameP*Ms stops being budget-bound and becomes a measurement (expected at L per the S-run's 44 ms figure).
- [ ] **Step 3:** Commit: "feat: live M/L baseline sweep (before-picture for the perf campaign)"

---

## The fix campaign (Tasks 4–8) — shared discipline

Every fix task works in the FACET repo (its own commits) and follows this exact loop; the task brief's specifics ride on top.

1. **Start green:** `tools/test.sh` full suite green at task start (first fix task records the count as the campaign baseline; later tasks confirm unchanged-or-explained).
2. **Demonstrator first, red:** a counter-based spec in Facet `tests/` asserting the O(touched) bound this fix creates. Counters extend the existing work/stats families (`result.work.*`, `controller.stats()`) — cheap increments, shippable, no timing asserts. Show it RED at pre-fix HEAD in the report (run output), commit it WITH the fix (never a red commit).
3. **Invariant spec:** layout output pixel-identical vs a forced full solve on representative trees across the device matrix incl. 320x640 (the solver-memo standing lesson: a memo needs a DIFFERENTIAL ORACLE — the forced-full-solve comparison is that oracle; run it inside the spec on every case the demonstrator exercises).
4. **Fix**, minimal and mechanism-true (each task names the mechanism + file:line from the profile).
5. **Gates:** `tools/test.sh` full green; `tools/verify.sh affected` foreground green; stylua per Facet conventions.
6. **Before/after:** FacetBench `run_one_lib` facet rows S/M/L (samples 300), pre-fix vs post-fix, in the report; plus the promoted `tools/profile/` harness slice relevant to this fix (e.g. measure-pass share for P1). No FacetBench commit needed (sibling serves live) unless a FacetBench harness needs a fix — separate commit there if so.
7. **RR lockstep:** run the RascalRally suite (both projects' lune tests; expect ~3541/0); no game-side source change expected (internal perf) — the suite run IS the compatibility evidence, recorded with counts. Any RR failure = STOP, report BLOCKED.
8. Commit(s) in Facet with clear messages; report with all numbers.

### Task 4: P1 — cross-solve measure cache (the keystone, HIGHEST RISK)

**Profile evidence:** solve = 63–74% of a step; a reuse solve with NOTHING dirty still measures exactly N nodes (16.1 ms at L) because `opts.reuse` is consulted only in arrange (`solver.luau:2169`) — `measure` (`:3656`) has no reuse arm; a 1-leaf-dirty solve measures 2N (root arrange re-measures the whole tree via stack distribution). Est. ≈1.6 ms S / 20.6 ms L (44%).

- [ ] **Mechanism:** give measure a reuse arm keyed by the same validity the arrange skip already trusts (clean subtree + identical offer ⇒ prior measurement), with the dirty path invalidating ancestors' cached measurements exactly as dirtiness propagates today. The cache lives with the solve-reuse state (`renderer.luau:1673` lastSolveInputs family), never global.
- [ ] **Demonstrator D-P1:** counter `work.measured`: after a 1-leaf update at N=1000, `measured ≤ C·depth` (C small, from the tree's branching — pin the exact bound from the fixture tree, not a fudge); RED today (measures 2N).
- [ ] **Oracle:** invariant spec per shared discipline — every demonstrator case ALSO solved with cache disabled (a test-only opt) and rect-for-rect compared. Plus the standing "differential oracle" cases: offer changes, viewport changes, text re-measure (the boot-window font flip class — `GetTextBoundsAsync` wrong-but-stable early; do not let the cache freeze a pre-flip measurement: text version must participate in the key).
- [ ] Risk note for the implementer: this memo has been wrong twice historically (solve-count coalescing round; incremental layout round). The invalidation axes are (structure, offer, viewport, theme/text metrics, explicit dirty). Every axis gets an oracle case.

### Task 5: P2 — copy-on-write rect map

**Profile evidence:** `replaySubtree` (`solver.luau:2081`) re-inserts every skipped node into a fresh `out` (`:3663`) — 8.77 ms at L for 5115 nodes, the only superlinear term. Est. ≈0.2 ms S / 12.3 ms L (26%). After P1.

- [ ] **Mechanism:** the solve result's rect map is copy-on-write against the previous solve: untouched subtrees share the prior entries (or the map is persistent/structurally shared); a skipped subtree costs one comparison, not N inserts. The renderer's consumers (commit walk, dump, boundary analysis) read through the same interface — audit every reader (`renderer.luau:1990-2102` and dump/diagnostics paths) for identity assumptions (a reader mutating the shared map is the failure mode: make the shared structure read-only by convention + a spec that mutation-detects via a canary entry).
- [ ] **Demonstrator D-P2:** counter on out-map insertions per solve: 1-leaf update at N=1000 ⇒ insertions ≤ touched-path size; RED today (N).
- [ ] **Oracle:** as shared discipline; plus an aliasing spec: two consecutive solves, mutate nothing, assert the maps share (identity) untouched entries AND a forced-full solve equals both.

### Task 6: P3 — cache the solver Node tree across solves

**Profile evidence:** `renderer.luau:1941` rebuilds the whole `solver.Node` tree every solve — one closure per node + 3.6 ms/step of theme-token re-resolution at L. Est. ≈0.54 ms S / 5.5 ms L (12%). Independent of P1/P2. This is also the main slice of the 3.4 KB/node/step allocation (with P2/P4 the rest) — the alloc number is report evidence.

- [ ] **Mechanism:** persistent Node tree owned by the renderer, patched on dirty (props/theme/structure) instead of rebuilt; theme-token resolution memoized per node and invalidated on theme changes (theme emission≠application standing lesson — invalidate on APPLICATION).
- [ ] **Demonstrator D-P3:** counter `toLayoutNode` (or node-construction) calls per refresh: clean refresh ⇒ 0; 1-leaf update ⇒ ≤ touched; RED today (N every solve).
- [ ] **Oracle:** shared discipline + a theme-change case (swap theme mid-run, rects AND resolved tokens equal a fresh build) + structure change (ForEach add/remove rebuilds exactly the region).

### Task 7: P4 — drive the commit from the changed-rect set

**Profile evidence:** commit = six full-tree walks + an N-entry rects loop + rectPass to make 4 writes (`renderer.luau:1990-2102`). Est. ≈0.42 ms S / 5.9 ms L (13%). Needs P2 (the changed set falls out of COW).

- [ ] **Mechanism:** P2's solve result carries the changed-entry set; commit iterates THAT (plus structurally-new/removed nodes), not the tree. The six walks collapse to per-changed-node work; ordering guarantees preserved (document-order lesson: apply in document order where the engine cares — cite the nested-tree round's ordered-application requirement).
- [ ] **Demonstrator D-P4:** counter on commit-visited nodes: 1-leaf update at N=1000 ⇒ visited ≤ touched + constant; RED today.
- [ ] **Oracle:** shared discipline + the adapter-op stream equivalence: fake_target op log for a step equals the full-walk implementation's op log (order-sensitive compare) on the demonstrator cases.

### Task 8: P5 — boundary-rooted partial solves for structural changes

**Profile evidence:** any structural change forces a full solve (`renderer.luau:2947`); worth 3.7 ms at L today but becomes the ENTIRE remaining ~30 ms on add/remove/reorder once P1+P2 land. Strictly after P1+P2 (P4 recommended first too).

- [ ] **Mechanism:** reuse the existing boundary analysis (`renderer.luau:3917` family) to re-root structural re-solves at the nearest enclosing boundary whose offer/rect provably cannot change (a fixed-size list viewport is such a boundary; an auto-sized ancestor is not — the boundary test must be conservative). Falls back to full solve when no boundary qualifies.
- [ ] **Demonstrator D-P5:** killfeed-style addItem at N=600 concurrent: `work.measured + work.arranged ≤ K·(list length)` — bounded by the list region, not the tree; RED today (full solve).
- [ ] **Oracle:** shared discipline + the retire/re-entry ForEach semantics untouched (existing suite covers; call out the re-entry specs in the report) + war_room reorder case (irreducible O(shifted) — assert the bound is the LIST region and record the honest floor).

### Task 9: Target checkpoint — re-baseline, judge, publish

- [ ] **Step 1 (Lune):** re-run the full Lune matrix (defaults) → `results/lune-<date>-<sha>-after.json`; drift gate green; chart regenerated.
- [ ] **Step 2 (Studio, live MCP):** re-drive S+M+L (loop 250 / frames 300); microprofiler battle_hud L facet (after-picture vs Task 3's before); scrape with device; commit results + evidence doc `docs/studio-runs/<date>-after-campaign.md` with the per-class target table: update/setState/noop at L vs ≤0.5 ms; add/remove/reorder at L vs ≤1 ms; war_room shift floor reported as O(shifted) with its number.
- [ ] **Step 3 (verdict):** if any class misses its target: NO instrument-weakening — the doc states achieved vs target, names the remaining bottleneck from the promoted harnesses' attribution, and books the next lever in the notes file. If met: state it with the receipts.
- [ ] **Step 4:** README + chart + docs/profiling updated to the after-picture (keep the before numbers — the delta IS the story). Commit(s).

### Task 10: RED-TEAM gate + RascalRally live canary + campaign close

- [ ] **Step 1:** RascalRally Studio canary (live MCP): boot RR per its dev-workflow (rojo double-sync trap; publish-before-TestTrack), drive a sponsor-mode session or the standard canary screen, confirm UI correct and no quarantines; evidence screenshots/dump fragment per the evidence rule. (This is the constitution's device/live canary for the whole campaign's Facet diff.)
- [ ] **Step 2:** RED-TEAM: dispatch the adversarial code-reviewer agent (fresh context) over the CAMPAIGN diff in Facet (campaign-start..HEAD): correctness, invalidation axes, cross-platform, regression risk in sibling callers, resource leaks. Findings triaged per SDD discipline (fix loop on Critical/Important).
- [ ] **Step 3:** `tools/verify.sh full` foreground green in Facet; FacetBench check.sh green; ledger/notes close-out.

---

## After this plan
Public-repo launch checklist (CI on PRs, repo split/publish mechanics) is deliberately OUT of scope — book in the notes file at close.
