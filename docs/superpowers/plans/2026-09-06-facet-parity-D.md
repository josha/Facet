# Facet parity Plan D — the remaining per-class misses — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take the 17 of 29 FacetBench classes that still miss `≤ 0.5 ms live` (update) / `≤ 1 ms live` (structural) as far as measured levers can take them, profile-gated, with byte-identical observables, and close with a §after-2 table naming the mechanism of every remaining miss.

**Architecture:** Every task is a lever with its own counter (red-first), its own three-arm ABBA (A = parent SHA, B = mechanism, C = counter only), and an oracle that does not share the mechanism's switch. The first task is measurement, and it already happened in this session (§D1 below): the campaign's stated hypothesis ("seven flat commit walks") is REFUTED at HEAD, and the real O(tree) term on every tree-size-bound class is `measure_facts.memoPlan` recomputed over the whole tree per incremental solve. Levers are ranked by that measurement, not by the goal's order.

**Tech Stack:** Luau (Lune 0.10.4 headless, Roblox Studio live), FacetBench `tools/profile/attr`, Facet `tools/test.sh` / `tools/verify.sh`, RascalRally `./run-tests.sh`, Studio MCP for the live matrix.

**Spec:** `docs/plans/2026-09-06-facet-parity-D-goal.md` (the goal), with `GameStudio/ui/FacetBench/docs/studio-runs/2026-09-03-facet-parity.md` §after as the numeric authority.

## Global Constraints

- Facet repo `GameStudio/ui/Facet`, branch **`facet-parity-d`** off `main` `b315dc34` (created 2026-09-06 before any edit). FacetBench `GameStudio/ui/FacetBench` at `da1b433`. RascalRally `games/RascalRally/code` at `218aa83`. **Nothing merged or pushed.**
- Commits via `python3 tools/commit_isolated.py -m <MESSAGE FILE> <path[:marker]>` (`-m` takes a FILE PATH; `/dev/stdin` silently commits "placeholder"). Never amend. `.superpowers/` is in `.git/info/exclude`; never name it to `commit_isolated`.
- Gates on EVERY Facet commit, FOREGROUND, long timeouts, ONE lune process at a time (`pgrep -x lune`, never `pgrep -f`): `tools/test.sh <floor>` (floor **8,683**, ratchet only up), `tools/verify.sh affected --jobs 1` BEFORE the commit, `python3 tools/check_source_size.py`, `stylua --check src tests tools bench examples`. `tools/verify.sh full --jobs 1` before every close, then `git checkout -- examples/places/`. Commit BEFORE the long gate; write each gate's output to a named evidence file under `.superpowers/sdd/2026-09-06-facet-parity-D/`; append the ledger row as soon as the commit exists.
- **`renderer.luau` is at 197,472 of the 197,500 STOP** (28 chars). Any task that needs renderer characters takes a seam FIRST in its own commit. `solver.luau` 187,617.
- **No public API change. Observables byte-identical**: (1) `lune run tools/lune/text_reentry_differential <out>` in this tree vs a worktree at the parent commit, md5 `3db66551b80fe677d314f2092b0a0038` (144 blocks) or every differing block explained; (2) an oracle that does NOT share the mechanism's switch (§11 of the after-doc) — for each fast path, one spec drives a class the fast path does not serve and compares SLOW vs FAST on a byte-equal channel the fast path writes.
- **ABBA with a THIRD control arm**, interleaved A/B/B/A or B/A/A/B, medians of ≥ 2 runs each, paired worktrees (`git worktree add --detach <scratch>/dN/{A,B,C}/Facet <sha>` beside a FacetBench worktree so `../../../Facet/src` resolves per arm). Price the MARGINAL call, never calls × average.
- **RascalRally lockstep every task** that touches `src/`: a game-side contract test (or the compatibility evidence that proves the live consumer is current — do not manufacture churn), `./run-tests.sh` ≥ **3,599/0**, and a Studio canary (`rojo build default.project.json --output rr-canary.rbxl && RobloxStudio -localPlaceFile rr-canary.rbxl`; marker read back before any reading; one place open at a time; kill the pid after).
- **Measure the SETTLED session in a FRESH client VM per workload** (wait for `controller.textPending()` to fall, ~3.8 s, then sample; a prior workload in the same VM masks anything the process-global text store answers).
- **Register a FacetBench §Dn per task** in `docs/studio-runs/2026-09-03-facet-parity.md` (the convention: `# §Dn — <mechanism>`, provenance line with the three SHAs and the marker, numbered `## Dn.k` subsections, last one `## Dn.Provenance` with the gate results inline).
- **Owner rule:** a class still well over target after the planned tasks gets a deep attribution, an assessment and more levers BEFORE the close-out, never a named miss.
- Lessons binding (`tasks/lessons.md` 2026-09-05/06): a lever's first live drive happens BEFORE its task reports done; every reader a fix adds gets its own revert-and-redden check; a "kept null" mutation is a design fact to record; a divergence that moves with arm ORDER is shared state, not the arm; a spec fixture reproduces the PRODUCTION dirt shape.
- Counters, never wall-time, in specs: `expect(`name={actual}`).toBe(`name={expected}`)`, equalities read off the run, each task pins (a) an EXISTING counter that moves and (b) its NEW counter after the counter-only step.

---

## §D1 — Attribution at HEAD (done 2026-09-06 in the planning session; raw in `.superpowers/sdd/2026-09-06-facet-parity-D/attr-head/`)

Method: `lune run tools/profile/attr <wl> L 3` at `b315dc34`, `--noprof` control (0.954 vs 0.949 ms with hooks: the hooks are free on these classes), then a probe INSIDE `solver.measure` (uncommitted, diff kept as `attr-head/d1-probe-solver.diff`) because the wrapped children of `span:Facet/measure` summed to 0.06 ms of its 0.79.

**The finding.** On `battle_hud L updateItem-hp` (p50 0.949 ms, 36 `measure` calls, 6 uncached, 311 KB allocated) the root `measure` call took **0.658 ms of which `measureUncached` was 0.023 ms**. The remainder is ONE call: `measure_facts.memoPlan(ctx, root)`. It is memoised in `ctx.memoPlans` — PER SOLVE — and for a `vstack` whose children are height-free it recurses into every child, so on every incremental solve it re-derives the verdict of all 5,127 nodes and allocates a 5,127-entry map (the 300 KB). The wrap-based profiler could not see it because the solver binds `local memoPlan = measureFacts.memoPlan` at load; FacetBench `lib_attr` now shims it before the solver is required (`mf.memoPlan`).

| class (HEAD, Lune p50) | total | `mf.memoPlan` | `toLayoutNode` | `cw.harvest` | `arrange` | the rest |
|---|---:|---:|---:|---:|---:|---:|
| `battle_hud updateItem-hp` | 0.984 | **0.768 (78 %)** · 12 calls · 302.9 KB | 0.146 (`lastBuildChildVisits` 1,126) | 0.067 (`lastCommitScans` 1,137) | 0.066 (`lastPlaceSkipped` 1,124) | 0.06 |
| `battle_hud setState` | 1.100 | (same mechanism; measure 0.805 with 8 calls) | 0.142 | 0.059 | 0.049 | |
| `war_room setState` | 1.499 | (measure 1.157 with 8 calls) | 0.227 | 0.091 | 0.062 | |
| `damage_fountain updateItems-numbers` | 1.404 | measure 0.002 (anchor root, 199 skipped) | 0.387 (201 builds, 256 KB) | 0.045 | 0.218 (219 KB) | react 0.194 · rectPass 0.165 · dirtyScan+closure 0.204 |
| `war_room reorder` | 27.770 | — | 0.510 | 0.291 | 6.472 (6.3 MB) | rectPass.apply 10.487 (3.2 MB, INCLUDES the fake target's `setRect`) · `cw.hitRects` 2.818 (69 KB) · `ssZOrder` 3.241 · measure 2.247 |

**The seven `cw.*` walks are NOT flat 0.07 ms at HEAD**: six read 0.001–0.002 ms; only `cw.harvest` (0.066) still scans the dirty container's children. `rectPass.apply` is 0.007 on a leaf edit. The goal's step-1 hypothesis is refuted; step 1's real lever is `memoPlan`.

**Trial arm (uncommitted, reverted): cache the verdict on the node literal instead of `ctx.memoPlans`.** Lune p50, A = HEAD, B = trial, 2 passes each:

| class | A | B | Δ |
|---|---:|---:|---:|
| `battle_hud updateItem-hp` | 0.984 | **0.363** | −63 % |
| `battle_hud setState` | 1.105 | **0.405** | −63 % |
| `battle_hud updateItem-facing` | 0.955 | **0.341** | −64 % |
| `battle_hud addItem-damage` / `removeItem-damage` | 2.535 / 2.592 | **1.757 / 1.669** | −31 / −36 % |
| `war_room setState` | 1.471 | **0.451** | −69 % |
| `war_room updateItem-power` | 1.377 | **0.479** | −65 % |
| `war_room addItem-items` / `removeItem-items` / `reorder` | 5.071 / 13.827 / 27.664 | **3.348 / 11.461 / 25.951** | −34 / −17 / −6 % |
| `killfeed updateItem-hp` / `setState` | 0.296 / 0.285 | **0.195 / 0.200** | −34 / −30 % |
| `killfeed addItem-plates` / `removeItem-plates` | 0.738 / 1.065 | **0.643 / 0.928** | −13 % |

Live projection (`Lune × 1.37 + 0.129`): `battle_hud updateItem-hp` 0.363 → **0.63 live** (from 1.539), `war_room setState` 0.451 → **0.75 live**. Not yet under 0.5; the three remaining O(children) terms (build visits 0.146, harvest scans 0.067, place-skipped scan 0.066 ≈ 0.28 ms of the 0.363) are Task D2.

**Mount (battle_hud L, headless 105.9 ms, 5,109 creates):** `solver.solve` 37.1 (measure 13.1 + arrange 23.9; **`lastMeasured` 14,215 = 2.78 measures per node** because a cold solve has no memo and the arrange pass re-measures every node; `tm.measure` 6,012 calls / 8.1 ms, `tm.minWidth` 3,000 / 6.0 ms), `ssEnsureTree` 16.3, commit 17.2 (`rectPass.apply` 10.2 = 2 µs + 1.1 KB per rect; `cw.textScale` 2.3; `cw.visible` 1.3; `cw.textVerdicts` 1.1), `toLayoutNode` 11.9 (1.7 KB per node), unattributed ≈ 24 (the mount-tree build and adapter creates). Task D5.

**Lever ranking (counter moved × expected gain), which sets the task order:**

1. **D1 `memoPlan` on the node literal** — 0.6–1.0 ms on every tree-size-bound class, counter `lastPlanVisits` (new). Exact by construction: the verdict is a pure function of `node.width/height/kind/textFit/shrinkWeight` and the children's verdicts, none of which is written after `layout_node.build` constructs the literal (grepped: no post-build writer of `.width/.height/.kind/.textFit/.shrinkWeight/.children` in `src/`), and `layout_node.build` rebuilds a fresh literal for every node in `store.dirty`, which is ANCESTOR-CLOSED — so any node whose subtree's literals changed is itself a fresh literal. `tests/anchor_skip.spec.luau`'s header already states the verdict is "a PURE function of a built node".
2. **D2 the three O(children) scans on a leaf edit** — build child visits (ruling A-9's per-index rebuild, designed and deferred for scope in Plan C), the subtree-flag fold, harvest's descend list, the arrange replay's two sibling walks. ~0.28 ms on `battle_hud`, counters `lastBuildChildVisits`, `lastCommitScans`, `lastPlaceSkipped`.
3. **D3 the wide-key settle** — re-sweep the cutoff AFTER D1 (the push route paid `memoPlan`'s O(tree) too, so the crossover moves), then batch the boot-window drain's vocabulary. Counters `lastTextDirtyPaths`, `textMeasureBatches`, `drainDeferrals`.
4. **D4 the structural constant** — FIRST split the harness share of `rectPass.apply` on `reorder` (10.5 of 27.8 ms includes `fake_target.setRect`); then `authority.assertWrite` per rect, the nil `lastBarInsets` write, the unconditional `applyHitExpander`/`refitIconArt` calls, `cw.hitRects`' 69 KB (the doc's attribution is doubted by S3 — measure before believing), `ssZOrder`'s per-visit constant.
5. **D5 mount** — the cold solve's 2.78 measures per node (`lastMeasured` 14,215 → ~5,106 is the red-first pin).

Skipped, per the goal: the prefix rebase (§C12). Booked, not built: `SOLVE_FEEDBACK_ROUND_CAP` raising out of `refresh`.

---

### Task D0: the instruments, the ledger, and §D1 registered

**Files:**
- Modify (FacetBench): `tools/profile/lib_attr.luau` (the `mf.memoPlan` early shim + the named sub-measure wraps — ALREADY EDITED in the working tree by the planning session; review the diff, keep it)
- Create (FacetBench): `tools/profile/d1_uncached.luau`, `tools/profile/d1_mount.luau` (the two scratch probes, promoted with a header each), `docs/studio-runs/2026-09-03-facet-parity.md` gets `# §D1 — attribution at HEAD: the plan verdict was the walk`
- Modify (FacetBench): `tools/profile/README.md` (three lines: `mf.memoPlan` column, `d1_uncached`, `d1_mount`)
- Create (Facet, untracked): `.superpowers/sdd/2026-09-06-facet-parity-D/progress.md` + `attr-head/` (copy of the scratchpad run outputs)

**Interfaces:**
- Produces: the `attr` column `mf.memoPlan` (inclusive ms/kb/calls of the plan verdict), read by every later task's ABBA.

- [ ] **Step 1: ledger.** Write `progress.md` with the header block (plan path, base SHAs, floors 8,683 / 3,599, operating rules copied from Global Constraints) and the §D1 table above. Copy `<scratchpad>/attr-head/*` into `.superpowers/sdd/2026-09-06-facet-parity-D/attr-head/`.
- [ ] **Step 2: FacetBench instruments.** `cd GameStudio/ui/FacetBench && git diff tools/profile/lib_attr.luau` — confirm the shim block (`memoPlanSlot`) sits ABOVE `local layout_node = require(...)` and the named wraps sit below `solver.solve = wrap(...)`. Add a 6-line header to each `d1_*.luau` (usage + what it prints). Run `lune run tools/profile/attr battle_hud L 1 | grep mf.memoPlan` — expect a non-zero `mf.memoPlan` row. Run `tools/check.sh` (stylua excludes `tools/profile/`; the rest must be green).
- [ ] **Step 3: §D1 in the run doc.** Append the `# §D1` section: provenance (Facet `b315dc34`, FacetBench `da1b433`, RR `218aa83`, no Studio drive — headless only, stated), `## D1.1` the per-class span table above, `## D1.2` the probe method and why the wrap was blind, `## D1.3` the trial-arm table (labelled "uncommitted trial, reverted — the ranking evidence, not a result"), `## D1.4` the mount table, `## D1.5` the ranking, `## D1.Provenance`.
- [ ] **Step 4: commit FacetBench.** `git add tools/profile/lib_attr.luau tools/profile/d1_uncached.luau tools/profile/d1_mount.luau tools/profile/README.md docs/studio-runs/2026-09-03-facet-parity.md && git commit -m "Plan D §D1: attribution at HEAD — memoPlan is the walk; attr sees the load-bound seam"`. Ledger row.

---

### Task D1: the plan verdict lives on the node literal (the memoPlan lever)

**Files:**
- Modify: `src/layout/measure_facts.luau` (`memoPlan` — read/write `node.mPlan`; `MeasureCtx` loses `memoPlans`, gains `planVisits: number` (written); header sentence "it WRITES exactly four of them" → the new four: `fitCuts`, `planVisits`, `textFacts`, `textStates`)
- Modify: `src/layout/solve_ctx.luau` (`Ctx`: delete `memoPlans`, add `planVisits: number`; `new()`: delete `memoPlans = {}`, add `planVisits = 0` beside `measureServed = 0`)
- Modify: `src/layout/solver.luau` (the `work` literal near `:3435`: `planVisits = ctx.planVisits,`; the comment at `:1407` that names `ctx.memoPlans`; `Node` type gains `mPlan: number?` beside `mHeightFree`)
- Modify: `src/render/render_stats.luau` (`lastPlanVisits = 0` in `new()` beside `lastMeasureServed`; `stats.lastPlanVisits = work.planVisits or 0` beside `:298`)
- Modify: `tests/measure_facts_seam.spec.luau:205` (`{ "fitCuts", "planVisits", "textFacts", "textStates" }` and the prose block above it), `tests/measure_serve.spec.luau:102` (row 12 of the publish table: `ctx.memoPlans[node]` → `node.mPlan` — "WRITTEN BY THE SERVE — a pure function of the literal, cached for its life"), `tests/anchor_skip.spec.luau:50` (the sentence)
- Create: `tests/plan_cache.spec.luau`; register in `tests/run.luau` (append after the last Plan C spec line; a tree already carrying a later task's require is stale → STOP)
- Modify (FacetBench): `tools/profile/attr.luau` `statFields` gains `"lastPlanVisits"` after `"lastMeasureServed"`
- Modify (RR): `tests/facet_measure_fanout_contract.spec.luau` — beside `visits(warm)` add `plans(h)` = `` `plans={stats.lastPlanVisits} builds={stats.lastNodeBuilds}` `` pinned on the same `warm` surface, read off the run
- Modify: `tools/lune/verify/data/source-cap-ledger.md` (one row for `solver.luau` if its size moves ≥ 100 chars)

**Interfaces:**
- Produces: `ctx.planVisits` (bodies of `memoPlan` that ran, i.e. verdicts COMPUTED this solve), `work.planVisits`, `controller.stats().lastPlanVisits`; layout `Node.mPlan: number?`.
- Consumes: `layout_node.build`'s invariant that a dirty node and every ancestor is a FRESH literal (T6 pinned it: `store.byNode[node].built ~= previousBuilt` after a prop write).

- [ ] **Step 1: the red.** `tests/plan_cache.spec.luau` on `tests/lib/deep_stack_scene` (1,000 rows, 3,003 nodes): mount, one discarded warm tick (`scene.text(1, "w")`), then `scene.text(500, "x")` → pin `lastPlanVisits` and `lastMeasured` read off the run at HEAD with the counter only (expected shape: `plans=3003 measured=6`); target after: `plans=<depth + 1 ≈ 4>`; `solves=1` both. Plus a WIDTH write `scene.width(500, 40)` (measure-classed on the row): `plans` again ≤ 5 and `lastNodeBuilds` unchanged vs HEAD. Plus the exactness witness: a fixture `Screen > VStack > 20 × HStack{ Text, Box(width=signal) }` where row 5's Box `width` flips `{type="content"}` → `{type="fill"}` through a signal: assert the ROOT's verdict flips (read via `layout_node`'s built root → `solver` exposes nothing, so read the counter: after the flip the VStack must be `PLAN_KEYED`, which is observable as `lastMeasureCalls` moving because a keyed root's `maxH` re-enters the key — READ IT OFF THE RUN at HEAD and pin equality). Revert-and-redden: with `node.mPlan` cached but `layout_node.build` NOT rebuilding the parent (simulate by mutating `row.children[2].width` in place on the built tree in the spec — a `tests/`-only direct write), the root's verdict must be STALE and the case must go red; that is the case that proves the rebuild invariant is load-bearing, and it stays in the file as a NEGATIVE CONTROL (`it("...NEGATIVE CONTROL: an in-place dim write without a rebuild is exactly what the cache cannot see")`).
- [ ] **Step 2: run red.** `lune run tests/run_one tests/plan_cache.spec.luau` → the `plans=` pin fails with HEAD's 3,003.
- [ ] **Step 3: the mechanism.** In `measure_facts.luau`:

```luau
local function memoPlan(ctx: MeasureCtx, node: any): number
	--[[ CACHED ON THE LITERAL, FOR ITS LIFE (Plan D, D1). This was a per-solve memo in
		`ctx.memoPlans`, and on every incremental solve of a 5,127-node `battle_hud` it
		re-derived every node's verdict and allocated a 5,127-entry map: 0.768 ms and
		303 KB of a 0.949 ms one-leaf class, invisible to every wrap-based profile because
		the solver binds this function at load (FacetBench §D1). The verdict is a pure
		function of `width`/`height`/`kind`/`textFit`/`shrinkWeight` and the children's
		verdicts, none of which is written after `render/layout_node` builds the literal,
		and `layout_node.build` rebuilds a FRESH literal for every node in the ancestor-
		closed dirty set — so a node whose subtree changed is never the same table. The
		negative control in `tests/plan_cache.spec.luau` shows the one write this cannot
		see, and it is a write no production path makes. ]]
	local memo = node.mPlan
	if memo ~= nil then
		return memo
	end
	ctx.planVisits += 1
	... (body unchanged) ...
	node.mPlan = plan
	return plan
end
```

  `MeasureCtx`: replace `memoPlans: { [any]: number }` with `planVisits: number` (comment: "verdicts COMPUTED this solve — the counter that says the cache is serving; written"). `solve_ctx.new`: `planVisits = 0`. `solver.luau` `work`: `planVisits = ctx.planVisits`. `render_stats`: field + publish. `Node` type: `mPlan: number?`.
- [ ] **Step 4: run green** — `lune run tests/run_one tests/plan_cache.spec.luau`, then the three edited specs. Then `tools/test.sh 8683`.
- [ ] **Step 5: oracles.** All existing differential arms stay green (they compare `measureReuse=false` / `layoutNodeReuse=false` / `commitScope=false` arms — none toggles this cache, which is what makes them the switch-independent oracle): `text_settle_closure`, `measure_serve`, `host_space_oracle` (5 arms × 9 views), `commit_arrange_sibling`, `measure_memo` (800 seeded trees). Then the differential: `lune run tools/lune/text_reentry_differential <evidence>/d1-diff-after.txt`, and in a worktree at `b315dc34` the same → md5 both `3db66551b80fe677d314f2092b0a0038` or explain every block.
- [ ] **Step 6: the three-arm ABBA.** Worktrees A (`b315dc34`), C (HEAD with `ctx.planVisits += 1` and the counter plumbing but `node.mPlan` reads/writes removed — i.e. the per-solve memo restored), B (HEAD). `attr battle_hud L 3`, `war_room_inventory L 3`, `killfeed_nameplates L 3`, `damage_fountain L 3`, `nameplates L 3`, order B A A B then C once. Record per class p50 + `mf.memoPlan` + `lastPlanVisits` (expected: A 5,127 / C 5,127 / B ≤ 6 on `battle_hud updateItem-hp`; `lastMeasured`, `lastMeasureCalls`, `lastLayoutNodes`, `rectWrites` IDENTICAL on all three arms — the safety pair).
- [ ] **Step 7: RR lockstep.** `cd games/RascalRally/code && ./run-tests.sh` ≥ 3,599 (expect: no existing pin moves — this cache changes no measure count; if `facet_measure_fanout_contract` moves, STOP and attribute — that is a finding). Add the `plans(warm)` pin read off the run. Studio canary: build `rr-canary.rbxl`, `script_grep "CACHED ON THE LITERAL"` must hit `ReplicatedStorage.Facet.layout.measure_facts`, sponsor screen up, 45 frames of moving markers, 0 quarantines, `stats().lastPlanVisits` read live ≤ 6 on a dot tick.
- [ ] **Step 8: live drive (the lesson: measured LIVE before called a win).** FacetBench marker stamp, `rojo build runner/studio/place.project.json --output artifacts/studio-place-d1.rbxl`, fresh client VM per workload, settled-session probe for `battle_hud` (updateItem-hp / setState) and `war_room_inventory` (setState / updateItem-tier), `samples=100` loop mode + `frames` mode. Record beside vide.
- [ ] **Step 9: gates + commit.** `tools/verify.sh affected --jobs 1` (foreground), `check_source_size.py`, stylua. Message file `d1-commit-msg.txt`: `D1: the plan verdict is cached on the node literal, not re-derived over the tree per solve`. `commit_isolated.py -m ... src/layout/measure_facts.luau src/layout/solve_ctx.luau src/layout/solver.luau src/render/render_stats.luau tests/plan_cache.spec.luau tests/run.luau tests/measure_facts_seam.spec.luau tests/measure_serve.spec.luau tests/anchor_skip.spec.luau`. RR commit: `Facet lockstep D1: the racer list's plan verdicts are cached — plans=<n> pinned beside visits`. FacetBench: `attr.luau` statFields + `# §D2 — the plan verdict on the literal` with the ABBA + live rows. Ledger rows.

---

### Task D2: the three O(children) scans on a one-leaf edit

Profile-gated per sub-lever on `battle_hud L updateItem-hp` AFTER D1 (arm A = D1's commit). Expected before: `toLayoutNode` 0.146 / `cw.harvest` 0.067 / `arrange` 0.066 of ~0.36 ms.

**D2a — the per-index child rebuild (ruling A-9, deferred in Plan C for scope, not soundness).**

**Files:**
- Modify: `src/render/layout_node.luau` (`toLayoutNode`'s T15 arm — the `reusableKids` scan becomes a PATCH: when `prior.kids == node.children`, `prior.childArray ~= nil`, same axis/clip, copy `prior.childArray` and re-run `toLayoutNode` only at the indices whose child path is in `store.dirty`; the index comes from `prior.kidIndex` (`path -> index` over the SPLICED grandchildren, built once per full pass beside `childArray` and dropped when the array is rebuilt — the same lazy shape `stack_measure`'s `mIdx` uses). The `store.nodes` arithmetic: `nodesAtEntry + prior.n` minus the replaced children's `n` plus the rebuilt ones' — pin `lastLayoutNodes` UNMOVED.)
- Modify: the same function's post-children fold (S1 §2.B: `subtreeHasScroll` / `subtreeHasComposition` / `containerRelativeInside` over the layout children) — cache the three booleans on the store entry beside `n` (`entry.flagsScroll/flagsComposition/flagsInside`) and on the patch path recompute them only from the previous flags OR'd with the rebuilt children's (exact: the flags are ORs over the subtree).
- Create: `tests/build_index_patch.spec.luau` (register). Pins on `deep_stack_scene`: `lastBuildChildVisits` HEAD (read off the run, ~1,003) → after: `≤ dirty children + 1 per container` (expected 2); `lastNodeBuilds` UNMOVED; `lastLayoutNodes` UNMOVED; the `ForEach`-splice case (a `When`/`ForEach` region child whose grandchildren are the indexed ones: the index is over the SPLICED positions and a region toggling a child is a STRUCTURAL build, `collect == true`, which refuses the patch — pin `lastAggregateFallbacks`-style refusal count `lastBuildPatchRefused` read off the run).
- RR rider: `facet_measure_fanout_contract.spec.luau` `visits(warm)` moves from `visits=15 builds=9` WITH the mechanism (read off the run; the rider comment says why).

- [ ] Step 1 red (visits pin) → Step 2 run red → Step 3 mechanism → Step 4 green → Step 5 oracles (`node_reuse.spec`'s `layoutNodeReuse=false` arm + `host_space_oracle` arm c + the differential md5) → Step 6 ABBA A/B/C (`lastBuildChildVisits` 1,126 → ~3; `toLayoutNode` 0.146 → expected ≤ 0.03) → Step 7 RR + canary → Step 8 gates + commit `D2a: a rebuilt container patches its kept children array at the dirty indices`.

**D2b — `cw.harvest`'s descend list from the solver's walked set.** At HEAD the commit's ONE remaining per-child scan is `buildDescend` asking `entryVerdict` per child of the dirty container (1,137 scans, 4 probes). C4.2 proved a dirty-child INDEX is unsound (a clean child re-arranged gets a new entry). But T16 already exports `work.walkedIds` — the exact set of nodes the arrange pass WROTE an entry for this solve — and `rect_pass` already prunes by it. The lever: the descend list for a container with `n` children and `k` walked children is built from `walkedIds ∩ children` when `k < n // 8` (via the container's `kidIndex` from D2a), else by the scan. Exact because a child not in `walkedIds` has an entry IDENTICAL to the previous solve's (T16's invariant, pinned by `commit_probe_filter.spec`), which is `skip`'s "settled" verdict by definition. Counter: `lastCommitScans` 1,137 → ~10. Files: `src/render/commit_walks.luau` (`buildDescend`), `src/render/renderer.luau` — ZERO chars (the walked set already reaches `harvest` as an argument, T16). Spec `tests/commit_descend_walked.spec.luau` + the existing `commit_descend_predicate` (1,296 orderings) extended with a `walked` arm compared against the scan arm on every ordering. RR rider: `facet_commit_dirt_classes.spec.luau`'s `lastCommitVisits` aggregate pin re-read off the run (visits do not move; scans do — add `lastCommitScans` to the pin).
- [ ] Steps as D2a. ABBA gate: ship only if `cw.harvest` moves ≥ 0.03 ms on `battle_hud updateItem-hp` AND `reorder` does not regress (the class C4.6 bit).

**D2c — the arrange replay's two sibling walks** (S1 §3.3: `lastPlaceSkipped` 1,124 is the census). The replay compares each child's measured extent to `pMain[idx]` to find MOVED children; with D2a's `kidIndex` and `reuse.measureContains` it can enumerate the CANDIDATE movers (dirty children) and check only those — exact only if a clean child cannot move: it cannot on the MAIN axis without a dirty sibling before it (the prefix rebase §C12 is what handles the shifted run and it is SKIPPED by the goal), so this arm serves ONLY the case where no candidate moved (the `updateItem-hp` shape: a leaf whose box did not change) and falls to the scan otherwise. Counter `lastPlaceSkipped` → 0 on that shape with `lastArranged` UNMOVED. Files: `src/layout/stack.luau` (the replay's pass), `src/layout/solver.luau` ≤ +200 chars. Spec `tests/stack_replay_candidates.spec.luau` + `stack_replay.spec`'s `stackReplayAudit` arm ON over 9 views.
- [ ] Steps as D2a. Gate: ship only if `arrange` moves ≥ 0.03 ms on the class.

**D2 close:** re-run `attr` on all five workloads (A = D1 commit, B = D2 head); `battle_hud updateItem-hp` expected ≤ 0.10 ms Lune (live ≈ 0.27). §D3 registered.

---

### Task D3: the wide-key settle — right AND fast, and the boot-window drain batched

**D3a — re-sweep the cutoff after D1/D2.** `lune run tools/profile/t18_cutoff 1000 7` at the D2 head vs at `b315dc34` (worktree). The PUSH arm paid `memoPlan`'s whole-tree walk on every push solve; with D1 its per-node cost is the closure's alone. Read the new crossover band. If the push now wins at 33 % of the tree, the cap `max(64, lastLayoutNodes // 8)` in `renderer.luau`'s `textIndex.apply` call moves to the measured band (`// 3`? — READ IT OFF THE SWEEP; the constant is a measurement, never a guess) — renderer chars: the constant is the same length; if not, seam first. Then the wide-key classes live: `battle_hud updateItem-facing [S]`, `war_room updateItem-power [S]`, `war_room addItem-items [S]` in a fresh VM each (the §6 probe). Counter `lastTextDirtyPaths` (non-zero where it read 0 and `lastMeasured == lastMeasureCalls` at 14,263).

**D3b — the narrow route over the cap: re-measure the key's users, not the world.** If D3a's band still refuses `battle_hud`'s 1,000-label key (20 % of the tree): the cost of the push route is the CLOSURE (every ancestor of 1,000 labels is in `dirtyContains`, so every container on the way refuses its memo AND the aggregate's probe budget `n // 4` trips → full pass). The exact narrower form: a word's corrected width changes a label's MEASURED extent; if the label's new extent equals its previous one (`record`'s slot compare — the common case when the estimator was right to the pixel, and ALWAYS when the label's box is `fixed`), the label's ancestors need NO re-measure. So the push is spent in two rounds: round 1 re-measures ONLY the pushed text leaves (a `measureContains` of the leaves alone, no ancestor closure, `arrange` skipped — a MEASURE-ONLY probe solve that publishes nothing: `ctx.measureQuiet`, no rects written); the leaves whose `(w,h)` moved become round 2's dirt through the ordinary `dirty_closure.of` (ancestor-closed), which is the shipped narrow route on a set that is now the CHANGED labels, not the key's users. Byte-identical because round 2 is exactly the solve the closure route would have made for those labels, and a label whose extent did not move contributes nothing to any ancestor's answer (the container memo's `mMain[idx]` is the same number). The oracle that does not share the switch: `text_settle_closure.spec`'s forced-COLD arm over the 1,000-user key scene from `t18_cutoff`, every geometry channel byte-equal, `lastMeasured == lastMeasureCalls` asserted on the cold arm. Files: `src/render/text_index.luau` (`take` returns `{ full = false, probe = leaves }` over the cap instead of `full`; `apply` spends `probe` through a new `probeMeasures(paths) -> movedPaths` the renderer hands it — the renderer needs a seam FIRST: extract the settle-solve branch of `solveAndApply` into `src/render/settle_solve.luau`, own commit), `src/layout/solver.luau` (a `measureOnly` opt: run `measure` and return `work` without `arrange`; ≤ +600 chars). Counters: `lastTextProbeMeasures` (leaves probed), `lastTextDirtyPaths` (labels that MOVED → round 2), `lastMeasured` on the settle step (14,263 → probed + moved × depth).
- [ ] red-first on the `t18_cutoff` 1,000-user scene (`lastMeasured` at HEAD read off the run vs after), oracle, ABBA on `t18_settle battle_hud L 7` (SETTLE / UNUSED KEY / CONTROL rows), live fresh-VM probes of the three `[S]` classes, RR lockstep (`facet_text_settle_contract.spec` pins `solves=2 notifies=2` — re-read off the run; if it moves to 3 the rider says why), §D4 registered.

**D3c — the boot-window drain: the request budget, not the boxes (S2's finding, corrects §8b).** `text_metrics.luau`'s per-solve word collector has `COLLECT_CAP = 1024`, filled in document order by every `wordWidth` call whose word has no exact width yet — and a word that was REQUESTED but not yet ANSWERED is still `nil` in the store, so the in-flight backlog re-consumes the budget on every solve. Live, the first batch cannot answer inline (`warmFont`/`PreloadAsync` and `GetTextBoundsAsync` yield; loop mode never lets the spawn thread resume), so with a 1,023-word backlog every solve has room for exactly ONE new word — which is §8b's "744, 724, 725, …" walk to the digit. Headless the fake target answers inline, so the backlog never forms (2–3 rounds). `COLLECT_CAP` appears in no test, doc or bench. The lever: `text_metrics.beginCollect(skip)` takes `premeasure_round`'s `textInFlight` set (identical key format) so an in-flight word is neither re-requested nor charged to the budget; the final vocabulary is the same set learned in ~1 round instead of ~63. Files: `src/layout/text_metrics.luau` (`beginCollect(skip: { [string]: boolean }?)`, the `collecting` write guarded on `skip[key] == nil`; a `collectTruncated` counter when the cap trips), `src/render/premeasure_round.luau` (`request` passes its in-flight set through), `src/render/renderer.luau` (the `beginCollect` call at `:1899` gains one argument — ≤ +40 chars, inside the 28 available? NO: seam first — extract the settle-solve branch as D3b's seam, same commit precedes), `src/render/render_stats.luau` (`textCollectTruncated`). Red-first: a spec on a 1,200-word fresh mount with a fake adapter that DEFERS every batch by one frame (the fake target needs a `deferBatches` opt — `tests/lib/fake_target.luau`): `textMeasureBatches` HEAD read off the run (~1,200 − 1,024 + 1 rounds) → after ≤ 2; `textCollectTruncated` > 0 at HEAD → 0 after. Oracle: a third arm with the whole vocabulary `setMeasured` BEFORE mount (no batches at all) — rects byte-equal on all three; `text_round_reentry.spec`'s three observables; the differential md5 with every differing block explained (the batch count is a recorded observable and it MOVES by design). Live: `battle_hud` L fresh VM, `samples=100` loop mode — the `stepP95Ms` 890 ms row (§8b) is the number to move; `drainDeferrals` 0.
- [ ] Steps as D2a; RR: `facet_text_settle_contract.spec` (`solves=2 notifies=2` re-read off the run) + canary (results screen boot: batches counted live); §D5 registered, with §8b's diagnosis corrected in place ("Added 2026-09-06, Plan D").

---

### Task D4: the structural constant

**D4a — split the harness from the framework on `reorder` FIRST.** `attr war_room_inventory L 3` with `fake_target`'s `setRect` wrapped separately (lib_attr: wrap the adapter's `setRect` as `target.setRect`, the same way `cw.*` are) → `rectPass.apply` minus `target.setRect` is Facet's own share. §C10's rule: quote a Lune class only when the harness share is < 5 %; otherwise the number to carry is the LIVE one (36.5 ms) and the lever is judged live.

**D4b — the per-rect constant** (S3 §Q1), each its own ABBA on `reorder` + `removeItem-items` + `nameplates addItem-plates`, ship only if `rectPass.apply` moves ≥ 3 % on `reorder` with `rectWrites`/`engineWrites` IDENTICAL:
1. `authority.assertWrite("common", "size", "layout")` hoisted out of `applyOne` — asserted ONCE per `apply()` (the answer is a constant of the manifest). Files: `src/render/rect_pass.luau:100`.
2. `lastBarInsets[path] = entry.barInset` guarded on `entry.barInset ~= nil or lastBarInsets[path] ~= nil`. `rect_pass.luau:98`.
3. `screen_presentation.applyRect`: `applyHitExpander`/`refitIconArt` behind per-handle booleans set where `hitExpander`/icon art is assigned. Files: `src/client/screen_presentation.luau:445,462`; the fake target mirrors nothing (it has no expander path) — the live adapter is the only site, so the oracle is `host_move_write_cost.spec` × 9 views + `commit_arrange_sibling`'s adapter-write channel.
4. `cw.hitRects` 69 KB on `reorder`: MEASURE FIRST (S3 doubts §7.2's attribution to `authorPressableRects`, which is chrome-gated and war_room has no chrome): `controller.dump()` of one L mount to see whether `inputSinks` is non-empty; then wrap `authorPressableRects` in lib_attr. If the allocation is elsewhere in the walk's per-visited-node path, name it; the fix is a reused scratch table, not a fresh `{}` per call.
5. `ssZOrder` 3.24 ms on `reorder`: S3 §Q2 — the walk is O(n − insertion) by the monotone counter's design; attack the per-visit constant (`orderedChildren` sort + hit-lift touch per visited node): pin `zVisits` UNMOVED and time per visit. Ship only on a measured ≥ 5 % of `ssZOrder`.

**D4 close:** `attr` all five workloads; live `reorder`, `removeItem-items`, `addItem-items`, `killfeed addItem/removeItem-feed`, `battle_hud addItem/removeItem-damage` in a fresh VM each; §D6 registered with the harness split stated on every Lune number.

---

### Task D5: mount — the cold solve measures every node 2.78 times

**Mechanism.** On a cold solve `ctx.measures == nil` and `record` refuses (`ctx.reuse == nil`, the purity contract: a frozen hand-built tree may be solved), so the arrange pass re-measures every node the measure pass already answered at the same offer (14,215 measures on 5,106 nodes). The lever: let `record` write the two slots and the serve read them when `ctx.measureStamp ~= nil` (the renderer ALWAYS passes a stamp; `dump.fromSolve`, the fuzzer and a hand-built spec tree pass none — so the purity contract holds where it is exercised) — i.e. the node-resident serve becomes a WITHIN-solve memo on a cold solve, gated the same eleven-channel way it already is, with the reuse-set term replaced by "same solve token" (`node.mSolve == ctx.solveToken`: a node measured earlier in THIS solve at the same (offer, scope) has nothing dirty inside it by definition — the tree is immutable for the solve's life). Bonus: "the first reuse solve after a full one records and serves nothing" (T6's known cost) goes away, which is a structural-class win too (`addItem-damage`'s follow-on solve).

**Files:** `src/layout/solver.luau` (`measure`'s serve gate: `(reuse ~= nil and ... measureContains) or node.mSolve == ctx.solveToken`; `record`: refuse only when `ctx.measureStamp == nil`, stamp `node.mSolve = ctx.solveToken`), `tests/measure_serve.spec.luau` (the "FIRST reuse solve after a full one records and serves nothing" case is REWRITTEN to its new truth: it serves — read off the run; the frozen-tree case stays green because a frozen tree is solved with no stamp), `tests/mount_serve.spec.luau` (new: cold mount of `deep_stack_scene`: `lastMeasured` HEAD ~8,800 → after ~3,003, `lastMeasureCalls` unmoved, rects byte-equal to a `measureReuse=false` mount — and that arm ALSO takes this path, so the switch-independent oracle is `layout.spec`'s purity case + the 800-tree `measure_memo` fuzz whose per-solve memo is the SLOW arm here), FacetBench `d1_mount` A/B/C on all five workloads.

- [ ] red-first (`mount_serve.spec` `measured=` pin), mechanism, green, oracles + md5, ABBA (`mount:` line of `attr` + `d1_mount` spans: expect `solver.solve` 37 → ~22 ms of 106 on `battle_hud`; `tm.measure` calls 6,012 → ~2,000), live `mountMs` per workload in a fresh VM beside vide (213 → ?), RR (`facet_measure_fanout_contract`'s mount pin `arranged=37 measured=61` MOVES — re-read off the run, the rider says why), commit `D5: a cold solve serves a node's second question from its first answer`, §D7 registered. Then attribute what is left of mount (`ssEnsureTree` 16, `toLayoutNode` 12, `rectPass` 10, unattributed 24) in one `d1_mount` run and BOOK the per-node constants with their kb — no further mount lever in this plan unless one is ≥ 15 % and O(1)-shaped.

---

### Task D6: the assessment gate (owner rule)

- [ ] Run the full five-workload `attr` (A = `b315dc34`, B = D5 head) and the live matrix (loop + frames, fresh VM per row, settled probes for every `[S]` class). Build the §after-2 draft table (29 classes: Lune before / Lune after / live / vide / target / verdict).
- [ ] For EVERY class still > 1.5× its target: a deep attribution (`attr` + a `d1_uncached`-style probe if a span is unexplained), a one-paragraph assessment naming the mechanism and the next lever with its expected gain, and — if the lever is O(1)-shaped and ≤ 1 day — BUILD it here as D6.n with the same red/oracle/ABBA discipline. A class may be closed as a named miss ONLY with an assessment that names why the remaining lever is not exact or not bounded (e.g. `reorder`'s O(shifted) with vide at 5.3x).
- [ ] `SOLVE_FEEDBACK_ROUND_CAP` stays booked (not perf); state it.

---

### Task D7: close

- [ ] `tools/verify.sh full --jobs 1` (foreground, `timeout 900000`), `git checkout -- examples/places/`, `git worktree prune`. RR `./run-tests.sh` ≥ 3,599. FacetBench `tools/check.sh`.
- [ ] RED-TEAM: dispatch `code-reviewer` fresh-context over `main..facet-parity-d`; fix wave for every Critical/Important; scoped re-review. Every fix: revert-and-redden per reader.
- [ ] Final live matrix + RR canary on a moving field (§12's recipe), `§after-2` written into `docs/studio-runs/2026-09-03-facet-parity.md` (29 rows, every miss with its mechanism, the harness share stated where it is > 5 %, `mountMs` beside vide), chart SVG updated.
- [ ] Memory: update `memory/facet-parity-campaign.md` (Plan D landed, numbers, branch), write `facet-plan-d-memoplan-blind-spot.md`; `tasks/lessons.md` entry: "a wrap-based profiler is blind to a function the caller binds at load — when the sum of the wrapped children is far under the span, probe INSIDE the span before attributing to 'the walks'". Update `docs/plans/2026-09-06-facet-parity-landing.md` with a Plan D section.
- [ ] Branch menu for the owner (nothing merged/pushed): (1) merge `facet-parity-d` → main + graft to `public` (script handed over), RR + FacetBench pushed; (2) hold.

---

## Self-review (done while writing)

- **Spec coverage.** Goal step 1 (attribute, rank) → §D1 + D0. Step 2 (wide-key settle + batch drain) → D3a/b/c. Step 3 (tree-size residue in `layout_node.build`) → D1 (the real term, which was in `measure`) + D2a/b/c; `crossMax` left (1.9 %). Step 4 (structural constant, `ssZOrder`) → D4. Step 5 (mountMs) → D5. Rules → Global Constraints. Done criteria → D6/D7. Prefix rebase skipped; `SOLVE_FEEDBACK_ROUND_CAP` booked.
- **Placeholders.** D3b's cap constant and every "read off the run" pin are measurements by design, not TBDs; D3c's exact code lands after S2's brief is folded in (its mechanism, files and counters are named).
- **Type consistency.** `ctx.planVisits` / `work.planVisits` / `stats.lastPlanVisits` / `Node.mPlan` are the names used in D0, D1, RR rider and FacetBench `statFields`. D2a's `prior.kidIndex` is consumed by D2b and D2c under that name.
