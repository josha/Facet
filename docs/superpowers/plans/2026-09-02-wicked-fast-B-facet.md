# Wicked Fast — Plan B: the Facet fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a nameplates tick stop re-deriving a layout that did not change shape. The arena measured the tick at **8.578 ms headless at L** (build 0.400 / solve 2.707 / commit 4.139 / react 0.518 / residual 0.814; 4,048 KB garbage; arranged 1,489, measured 1,241, rectWrites 1,488, ~1,500 visits per commit walk × 8). This plan implements the profile's ranked levers — a **translate class** that the solver, the commit walks and the rect pass all understand — plus the single-update floor (anchor arrange), the structural-churn walk, and one correctness fix. The honest landing is **≈ 4.5 ms headless**, not the spec's ≤0.5 ms target; the miss is stated with its bottleneck in Task 9, it is not engineered away.

**Architecture:** One new dirty *tier*, not one new dirty *class*. `dirtyContains` splits into a measure half and an arrange half (T3) so an offset-only step never re-measures; `arrange` gains a third arm that re-bases a whole subtree's rects by (dx, dy) instead of re-entering it (T4); the commit's eight walks learn to honour a `moveOnly` entry so the six position-independent ones stop at a moved subtree's root and `rect_pass` emits the subtree's writes from a flat run instead of walking and comparing the tree (T5). The anchor branch then stops paying a `measure()` per non-dirty child (T6), `structuralSync`'s three re-derivable phases go incremental (T7), and the recycler's stale property signature is fixed (T8).

**Tech Stack:** Luau under Lune 0.10.4 (`lune run …`), stylua, `tools/test.sh` / `tools/verify.sh`, `python3 tools/check_source_size.py`, `python3 tools/commit_isolated.py`. The fake adapter (`tests/lib/fake_target.luau`) is the headless render target; FacetBench (`../FacetBench`, branch **`main`** at **`f1e8ba4`** — the arena branch `wicked-fast-arena` was merged and deleted when Plan A landed) is the measurement arena; Rascal Rally (`../../../games/RascalRally/code`) is the production consumer and its own git repo.

**Spec:** `docs/superpowers/specs/2026-09-02-facet-wicked-fast-design.md` Part 2 + Risks + Success criteria (lines 134-235).
**Profile that re-ranks it:** `FacetBench/docs/profiling/2026-09-02-nameplates-attribution.md` at FacetBench `7a7422a` (§6 ranked levers, §8 projection, §9 order).

### The ranking this plan implements (do not re-rank)

T1 extract → T2 counters + red baseline → T3 measure/arrange split → T4 translate arm → T5 commit under a translate (+N1 rect pass, +O5 folded in) → **T5b class-aware commit dirt (conditional, gated by its own 5 % drop test)** → T6 anchor arrange O(dirty children) + string allocation → T7 structural sync incremental → T8 propSigCache → T9 closing.

T5b is *inserted*, not a renumber: T6–T9 keep the numbers they have everywhere in this document, in their commit messages, and in the ledger rows they write.

### Dropped, with the reason (profile §6)

- **O1 (`memoPlan` cross-solve store)** — the 0.959 ms "measure nothing" floor it targets reads **0.004 ms** at `2d9f90cf` (probe arm B). P1–P5 already removed it. Re-evaluate only if T3 leaves > 0.4 ms of measure on ancestors (Task 9 states the number).
- **O5 as its own task** — `probeEntry`'s sibling scan is not separately visible; it sits inside the walks T5 prunes. Folded into T5's per-walk counters.
- **`layout_node.build`** — 0.400 ms, 4.7 % of the tick. Under the 5 % bar.
- **`hitRects` + `scrollRegions`** — 0.327 ms, 3.8 %, and `hitRects` genuinely must see a move (`r.x`/`r.y` centre the hit expander, `commit_walks.luau:1043-1050`). Not attacked; `scrollRegions` still gets the prune for free in T5 because it is position-independent.
- **`Facet/react`** (0.518 ms, 537 signal writes at ~1 µs) — the model layer, a non-goal of the spec. It is the floor Task 9 reports against.

### MIXED DIRT — the fact every task carries

**A nameplates tick is not 250 pure translates.** ~20 % of the plates are `caster`s (41–43 live at L in the arena) whose Cast bar width is `{ type = "fixed", px = cast * 100 }` and changes every tick — a **measure-class** change on the bar, so the bar and its ancestors up to the plate root re-measure and re-arrange while the other ~208 plates only move. The 537 signal writes are 250 × 2 + ~42.

Consequences, carried into every task below:

1. The fixture (`tests/lib/nameplates_scene.luau`, Task 2) exposes **two** update steps: `tick(dx, dy)` — pure translate, every plate — and `tickWithCasts(dx, dy)` — the same translate plus a cast-bar width write on a deterministic 1-in-5 subset (50 casters at N = 250).
2. T3's red pin on the **pure** `tick` is `lastMeasured == PLATES * 2 == 500`, **not** 0 — the fixture's `Hp`/`Cast` are fixed × fixed, which `measure_facts.memoPlan` classifies `PLAN_SKIP` (`measure_facts.luau:409-412`) and `solver.luau:1720-1722` sends straight to `measureUncached`, counted on every touch. Until T4 stops re-entering the plate subtree, the plate's own arrange measures both of them, every plate, every tick. The `== 0` pin belongs to T4's spec, where the translate arm makes it true. Derivation and the caster-tick number in Task 3 Step 1.
3. T4's red `lastArranged == 252 / lastTranslated == 1250` is the pure tick. On `tickWithCasts` the pin is `arranged == 302 / translated == 1200` — a caster plate's root is in `dirtyContains` (its own offset dirt *and* the bar's measure dirt closing over ancestors), so the root takes the arrange path; it does **not** resize (the fixture's plate root is `width = px(180)`, `height = content`, and the bar's height is fixed), so only Cast is arranged below it. **Task 4 Step 1 carries the competing derivation and the rule that settles it from the run** — under `translatable` as written, a caster plate's `Row` and `Hp` are themselves clean, same-size and moved, so they become their own translate roots and the split is `402 / 1,100` instead. Whichever the run reports is the mechanism; the EXPRESSION is corrected, never the assertion.
4. T5's per-walk visit pins are given per step kind (Task 5 Step 1's table): `253` on a pure tick, `303` on a caster tick — the visited-node closure, not the 503 *path strings* `markNodeDirty` writes (250 of those are `…/[pN]` item prefixes with no mounted node behind them; see Task 5 Step 1).
5. T9 reports every per-class number for **both** steps, and the FacetBench workload's real tick — the caster mix — is the headline.
6. Every differential oracle drives **both** steps at every device view.

The §8 projection at these ceilings is **≈ 4.5 ms headless** (≈ 5.1 ms live at the 1.14× VM ratio), not 3.8: the ~42 casters' measure + arrange is ~0.5 ms of floor the pure-translate ceiling does not remove.

## Global Constraints

- Facet repo `/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet`, HEAD `2d9f90cf`; commits via `python3 tools/commit_isolated.py -m <msgfile> <path[:marker]>` (usage in commit-seams §4.4); FacetBench repo `/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/FacetBench` (branch **`main`**, HEAD `f1e8ba4`, plain git — Plan A's `wicked-fast-arena` was merged and the branch deleted; `git branch -a` shows `main` only); RascalRally `/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/games/RascalRally`.
- Gates on EVERY Facet commit: `tools/test.sh` (full, ~85 s cold); `tools/verify.sh affected --jobs 1` FOREGROUND (never background, never `--jobs>1`); `python3 tools/check_source_size.py`; `stylua --check src tests tools bench examples`. RR: `games/RascalRally/code/run-tests.sh` green + a contract spec named for the fix.
- Solver headroom 861 chars until T1 lands: no solver edit before T1.
- Never a wall-time assertion; counters + `collectgarbage("count")` deltas only; median-of-K for ratios.
- No public API or behavior change (rects byte-equal to a full solve is the definition of "no behavior change" for T3–T7).
- Differential oracle across every `device_views` row incl. 320×640 for every solver/commit task.
- `skip` in commit_walks compares TABLE IDENTITY; rects are `table.freeze`d — never mutate a rect in place.
- Fresh-context adversarial review per task (the SDD task review) + RED-TEAM at T9.
- Coding style: match the surrounding file (`--!strict`, comment density, template strings); comment codes per `tools/check_comment_codes.py` if the file uses them (check).

### Standing notes for every task

- **Suite floor.** `tools/test.sh 8006` — 8,006 passing / 0 failing at `2d9f90cf` (`artifacts/test.json`). The floor only ratchets up; never pass a lower N to make a run green.
- **The two dirty sets are different** (commit-seams §7.1). `dirtyContains` = LAYOUT ids, `measure`/`arrange` entries only, handed to the solver. `nodeDirty` → `builtDirty` = MOUNTED paths, **every** class, handed to the commit prune. A translate tier must satisfy both, and the commit's set is the wider one. Every visit pin in this plan is expressed against `|nodeDirty|` **restricted to paths a node is actually mounted at**, which is why the six pruned walks land on 253 and not 0. `markNodeDirty` (`renderer.luau:2735-2746`) marks *path strings* by prefix, and a `UI.ForEach` row's `…/[pN]` prefix has no mounted node behind it (`mount.luau:357` uses `rowPath` as a PARENT path; `mountNode` at `:595-596` mounts the row's own root at `…/[pN]/Plate`). `skip` is only ever asked about real nodes, so those 250 phantom strings can never become visits.
- **RR characterization pins move.** `games/RascalRally/code/tests/facet_measure_fanout_contract.spec.luau:605-608` pins `measured=/arranged=/skipped=` and `lastCommitVisits == 256` on shipped surfaces. T3–T7 may move them. That file's own rule applies: *"If a Facet change moves them, move them WITH the measurement that licenses it and say so here."* Update the table in its header, never loosen the assertion.
- **Source cap.** After every solver or renderer edit run `python3 tools/check_source_size.py`. If a module's headroom falls under 1,000 characters, STOP and take the seam its `tools/lune/verify/data/source-cap-ledger.md` row names before writing more. A row whose size drifts more than 2,000 characters from the file must be re-recorded in the same commit (ledger rules, lines 26-40).
- **`src/render/renderer.luau` is the second cap risk, and it has a named seam.** 192,657 today, **7,343 to the cap** (`source-cap-ledger.md:59`). This round adds to it in six tasks — T2 (+~1,000), T3 (+~1,600), T4 (+~400), T5 (+~200), T5b (+~600), T7 (+2,500–4,000) − T8 (−250) ≈ **5,600–7,100** — which lands inside, or through, the 1,000-character stop above. The seam that row names is the **text-measurement round**: `textInFlight`, `textMeasureCancels` and the collect/deliver/`learned` block inside `solveAndApply` (~4 KB), which reads `adapter`, `env`, `stats` and `solveAndApply` and therefore costs one record. **T7 MUST take that seam as its FIRST, SEPARATE commit if `check_source_size` reports renderer headroom under 1,000 after T6** — the same standing obligation T1 discharges for the solver, not a judgement call at the time.

---

### Task 1 (T1): extract `chosenCandidate` — the headroom that licenses every later solver edit

**Files:**
- Create: `src/layout/candidate.luau`
- Modify: `src/layout/solver.luau:793-941` (delete the body, keep a one-line call), plus the Deps bind at **`solver.luau:578-595`** — where `GRID_DEPS` (`:578-584`), `FLOW_DEPS` (`:591`) and `COMPOSITION_DEPS` (`:595`) are built, which is near the **TOP** of the file, above `chosenCandidate` (`:814`), not near the bottom
- Modify: `tools/lune/verify/data/source-cap-ledger.md:72` (the `src/layout/solver.luau` row)
- Modify: `docs/superpowers/specs/2026-09-02-facet-wicked-fast-design.md:49` (the §1.1 float amendment, final review Minor 13)

**Interfaces:**
- Consumes: `solver.luau`'s forward locals `measure` (`:547`) and `setFitProbe` (`:551`, body `:1024-1030`), and the exported types `solver.Node` / `Ctx`.
- Produces: `candidate.choose(deps: Deps, ctx: any, node: any, availW: number, availH: number): number` where `export type Deps = { measure: (any, any, number, number) -> (number, number), setFitProbe: (any, boolean) -> () }`. `solver.luau` keeps a module-level `CANDIDATE_DEPS: candidate.Deps` built at bind time and calls `candidate.choose(CANDIDATE_DEPS, ctx, node, availW, availH)` at BOTH existing call sites — `contentSize` (`:1432`, the measure path) and `arrange` (`:2638`, the arrange path).

- [ ] **Step 1: Create `src/layout/candidate.luau`** — move `solver.luau:793-941` verbatim (header doc-comment 793-813 included), changing only: the `local function chosenCandidate(ctx, node, availW, availH)` header becomes `function candidate.choose(deps: Deps, ctx: any, node: any, availW: number, availH: number): number`; the two free calls become `deps.measure(...)` and `deps.setFitProbe(...)`. `math.huge` stays (a global). Nothing else in the body reads an upvalue — the complete free-variable list is `measure`, `setFitProbe`, `math` (solver-seams §5). File preamble:

```luau
--!strict
--[[ FIT-CANDIDATE SELECTION, lifted out of `layout/solver.luau` on 2026-09-02
	because the solver had 861 characters of Source-write headroom and the
	wicked-fast round needs several hundred of them (`source-cap-ledger.md`'s
	trigger for that row named this function by name).

	IT IS A ONE-WAY SPLIT. The only things it needed from the host were the
	mutually-recursive `measure` and `setFitProbe` — both forward locals there,
	both handed in as a bind-time `Deps` record exactly as `GRID_DEPS` /
	`FLOW_DEPS` / `COMPOSITION_DEPS` already are. Everything else it reads is a
	field of the `ctx` or `node` it is given (`ctx.fitProbe`, `ctx.fitCuts`),
	so no mutable upvalue of the solver crosses this boundary and no behavior
	changes: `tests/view_that_fits.spec.luau` and the three reuse oracles are
	the proof, not this comment. ]]
local candidate = {}

export type Deps = {
	measure: (any, any, number, number) -> (number, number),
	setFitProbe: (any, boolean) -> (),
}
```

- [ ] **Step 2: Rewire `solver.luau`** — delete `:793-941`; at BOTH call sites (`contentSize` `:1432` and `arrange` `:2638`) call `candidate.choose(CANDIDATE_DEPS, ctx, node, availW, availH)`; add `local candidate = require("./candidate")` beside the other `layout/` requires; build the record **beside the other three Deps records at `:578-595`**, so every statement this file makes about what a helper module reads lives in one place.

  **BOTH fields are forwarders, and neither may be by value.** `measure` is assigned at `solver.luau:1675` and `setFitProbe` at `:1024-1030` — both far below `:595`, so a by-value record built there captures `nil` for both; and a record built after `:1030` (the shape an earlier draft of this plan proposed) still captures `measure = nil`, because `:1030 < :1675`. The file already states the rule and the remedy for exactly this, one comment above the bind site (`solver.luau:569-577`): *"it cannot go into a load-time record BY VALUE: the record would capture nil. The forwarder below reads the local at call time instead."* `measure` therefore comes through `GRID_DEPS.measure` — the file's existing call-time forwarder, the same one `COMPOSITION_DEPS` (`:595`) borrows — and `setFitProbe` gets a forwarder of its own:

```luau
-- ...AND WHAT `src/layout/candidate.luau` NEEDS, which is the pair the extraction
-- found and no more. BOTH are forward locals assigned far below this line —
-- `measure` at ~1,675, `setFitProbe` at ~1,024 — so both are read AT CALL TIME,
-- for the reason `GRID_DEPS` above states: a by-value record here captures nil.
-- `measure` borrows `GRID_DEPS`'s forwarder rather than building a second one, so
-- the two records cannot end up reading a different `measure` after an edit.
local CANDIDATE_DEPS: candidate.Deps = {
	measure = GRID_DEPS.measure,
	setFitProbe = function(ctx: Ctx, on: boolean)
		setFitProbe(ctx, on)
	end,
}
```

- [ ] **Step 3: Prove no behavior change and bank the headroom**

```bash
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet
stylua src/layout/candidate.luau src/layout/solver.luau
python3 tools/check_source_size.py
lune run tests/run_one view_that_fits
lune run tests/run_one measure_reuse
```
Expected: `check_source_size` PASS with `src/layout/solver.luau` about **7.7 KB smaller**. Measured, not estimated: `sed -n '793,941p' src/layout/solver.luau | wc -c` is **7,708** characters, so 199,139 → **≈ 191,600** once the one-line call, the `require` and the eleven-line `CANDIDATE_DEPS` record are added back — **headroom ≈ 8,400**, not ~4,900. That is what the ledger row in Step 4 records, and it is the number the rest of the round spends: estimating from the code this plan shows, T3 ≈ +1,700 (solver + renderer), T4 ≈ +3,200 solver, T6 ≈ +1,200 solver, so the headroom T1 frees is sufficient with ~3.5 KB to spare. Both specs green. If the solver's new size is not at least 3,500 characters below the old one, the extraction did not take the whole body — do not proceed.

- [ ] **Step 4: Re-record the ledger row** — `tools/lune/verify/data/source-cap-ledger.md:72`, the `src/layout/solver.luau` row. Set the size cell to the number `check_source_size` just printed, and replace the trigger with one that is *actually in the file* and is a CONDITION:

> **TAKEN 2026-09-02: `chosenCandidate` went to `src/layout/candidate.luau` (7,708 characters measured at `2d9f90cf`) behind a two-field `Deps` record — `measure` + `setFitProbe`, the exact pair the previous trigger predicted — and the wicked-fast round then spent part of what it bought (the translate arm, the measure/arrange split and the anchor-arrange skip all live in `arrange`). TRIGGER: the next round that adds a branch to `arrange`'s container dispatch takes the STACK branch (`solver.luau` `local isH = node.kind == "hstack"` through the `distribute`/`shrunk` tail, ~6 KB) — it reads only `ctx.containerW/H` plus node fields and calls `measure` back, i.e. the same one-way Deps shape `candidate.luau` has now proven, and it is the largest single block left that is not the recursion itself.**

- [ ] **Step 5: The spec's float amendment** (final review Minor 13) — `docs/superpowers/specs/2026-09-02-facet-wicked-fast-design.md:49` reads `**`x` / `y` props** (px from the canvas's top-left, integers).` The arena's projector returns raw floats on purpose (two ticks that round to the same px would be an equal write, which every framework skips, so the workload would measure nothing). Replace `integers` with `numeric px, floats allowed` and leave the rest of the line untouched.

- [ ] **Step 6: Gates**

```bash
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet
tools/test.sh 8006
tools/verify.sh affected --jobs 1
python3 tools/check_source_size.py
stylua --check src tests tools bench examples
```
All four green, foreground, in that order.

- [ ] **Step 7: RascalRally lockstep — compatibility evidence, no new spec.** T1 is a pure code move with no contract, default or behavior change, so the game needs no edit; the lockstep clause (`games/RascalRally/CLAUDE.md:34`) is satisfied by proving the live consumer is current:

```bash
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/games/RascalRally/code
./run-tests.sh
```
Expected: green, and the **55** `facet_*.spec.luau` contracts among them (`ls games/RascalRally/code/tests/facet_*.spec.luau | wc -l` = 55 at `2d9f90cf`). Record the pass count in the task report.

- [ ] **Step 8: Fresh-context review** — dispatch the code-reviewer agent over the diff with the questions: *"is any upvalue of `solver.luau` read by the moved body?"*, *"are BOTH `Deps` fields call-time forwarders — i.e. does the record hold no forward local by value?"*, and *"are both call sites (`:1432` measure, `:2638` arrange) converted, and does either pass a different argument list?"* Fix findings before committing.

- [ ] **Step 9: Commit**

```bash
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet
cat > /tmp/facet-b-t1.msg <<'MSG'
refactor(layout): extract chosenCandidate to layout/candidate.luau

The source-cap ledger's own trigger for the solver row, taken before the
wicked-fast round opens `arrange`: 199,139 -> ~191,600 chars (the moved body is
7,708 measured). Two-field Deps record (measure + setFitProbe), BOTH call-time
forwarders beside GRID_DEPS because both are forward locals; both call sites
(contentSize, arrange) converted. No behavior change. Ledger row re-recorded
with the stack-branch trigger. Also amends the wicked-fast spec 1.1 to say canvas
coordinates are numeric px (floats allowed) — the arena's projector returns
raw floats on purpose.
MSG
python3 tools/commit_isolated.py -m /tmp/facet-b-t1.msg \
  src/layout/candidate.luau \
  src/layout/solver.luau \
  tools/lune/verify/data/source-cap-ledger.md:"chosenCandidate" \
  docs/superpowers/specs/2026-09-02-facet-wicked-fast-design.md:"floats allowed"
```

---

### Task 2 (T2): counters, the nameplates fixture, and the RED numbers on disk

Nothing is optimised in this task. It creates the instrument every later demonstrator reads, and it writes the *before* numbers down so a later "improvement" cannot be a moved goalpost.

**Files:**
- Create: `tests/lib/nameplates_scene.luau` (the fixture)
- Create: `tests/nameplates_baseline.spec.luau` (the pinned before)
- Modify: `src/render/commit_walks.luau` — the seven `stats.lastCommitVisits += 1` sites (`:465`, `:595`, `:689`, `:758`, `:850`, `:1027`, `:1090`) and the constructor return (`:1195-1210`)
- Modify: `src/render/rect_pass.luau:112` (the eighth site)
- Modify: `src/render/renderer.luau:621` (stats table — `lastCommitVisitsByWalk` and `lastLayoutNodes`), `:1969-1971` (publish `lastLayoutNodes` beside the `work.skipped` repair), `:2004` (the per-commit reset), `:2873-2894` + `:2747-2789` (two `profile.span` labels)
- Modify (FacetBench): `tools/profile/attr.luau` (`statFields` + the per-walk block)
- Create (FacetBench): `docs/profiling/2026-09-02-wicked-ledger.md`

**Interfaces:**
- Produces (Facet): `stats.lastCommitVisitsByWalk: { harvest: number, textScale: number, padding: number, textVerdicts: number, visible: number, hitRects: number, scrollRegions: number, rectPass: number }` — a FRESH table per commit span, so a `controller.stats()` snapshot (a shallow `table.clone`) is not mutated by the next commit. `stats.lastCommitVisits` keeps its meaning (the sum) exactly.
- Produces (Facet): `stats.lastLayoutNodes: number` — `nodeStore.nodes`, the count the renderer already computes to repair `work.skipped` (`renderer.luau:1969-1971`) and then throws away. Additive; it is what makes `census().layout` a layout-node count instead of a build count, and it is the denominator T4's work invariant needs.
- Produces (Facet): `tests/lib/nameplates_scene.luau` — `scene.PLATES = 250`, `scene.NODES_PER_PLATE = 6`, `scene.CASTER_EVERY = 5`, `scene.new(opts: Opts): Scene`, and on the scene `tick(dx, dy)`, `tickWithCasts(dx, dy)`, `hp(i, fraction)`, `add(i)`, `remove(i)`, `census(): Census`, `snapshot(): string`, `stats(): any`, `dispose()`.
- Produces (Facet): two profile spans, `"dirtyScan"` (the classification loop) and `"dirtyClosure"` (the ancestor-closure builder), inside `controller.refresh`.
- Produces (FacetBench): `attr.luau` prints `st.lastRectInserts`, `st.lastTranslated`, `st.lastCommitVisits`, `st.lastSsVisited`, `st.lastLayoutNodes`, `st.lastSolveSkipped` and one `cv.<walk>` count per commit walk, plus (free, via `lib_attr`'s existing `profile.setHooks`) the `span:dirtyScan` / `span:dirtyClosure` rows.
- Consumes: `tests/lib/device_views.luau` (`VIEWS`), `tests/lib/fake_target.luau` (`new`, `liveNodes`, `ops`), `src/render/renderer.luau` (`attach`), `src/mount.luau` (`mount`), `src/core/custom.luau` (`new`).

- [ ] **Step 1: Per-walk visit counters.** Each of the eight walks currently pays `stats.lastCommitVisits += 1` — a table-field increment — per node. Replace it with a per-walk local and one publish, which is strictly *fewer* per-node operations than today. In `commit_walks.luau`, for each of the seven walks (pattern shown for `harvest`, `:461-478`):

```luau
		local visits = 0
		local function walk(node: any)
			if skip(node) then
				return
			end
			visits += 1
			-- … unchanged body …
		end
		walk(rootNode)
		publishVisits("harvest", visits)
```
with one shared helper next to the prune state (`commit_walks.luau:305-321`):

```luau
	-- P4's visit counter, per walk (wicked-fast T2). `lastCommitVisits` keeps its
	-- meaning — it is the SUM — but a single number cannot say which walk stopped
	-- at a moved subtree and which had to descend it, and that is the whole
	-- question T5 asks. The per-node cost went DOWN: a local increment instead of
	-- a table-field one, published once per walk.
	local function publishVisits(name: string, n: number)
		stats.lastCommitVisits += n
		local byWalk = stats.lastCommitVisitsByWalk
		if byWalk ~= nil then
			byWalk[name] = (byWalk[name] or 0) + n
		end
	end
```
`visible` and `hitRects` use recursive inner functions (`pushVisible`, `pushHitRects`); the counter is an upvalue of the same shape. `rect_pass.luau` does the same with `publishVisits` handed in through its ctx: add `visits` to `rect_pass.new`'s ctx contract (`rect_pass.luau:60-77`) as `scope.publishVisits` — it already receives `scope = { skip, note, armed }` from `commit_walks`, so export `publishVisits` from the constructor return (`commit_walks.luau:1195-1210`) inside that same `scope` table and call `scope.publishVisits("rectPass", visits)` at the end of `apply`.

- [ ] **Step 2: The stats field.** `renderer.luau:621`, beside `lastCommitVisits = 0`:

```luau
		-- ...and the same number split by walk (wicked-fast T2). A FRESH table per
		-- commit: `controller.stats()` is a shallow clone, so a shared table would
		-- let the next commit rewrite a snapshot the caller already took.
		lastCommitVisitsByWalk = {} :: { [string]: number },
```
and at the reset site (`renderer.luau:2004`), beside `stats.lastCommitVisits = 0`:

```luau
			stats.lastCommitVisitsByWalk = {}
```
...and the layout-node count, at the site that already computes it (`renderer.luau:1969-1971`, the `work.skipped` repair) — one line, so `census()` and T4's invariant read a real number instead of `lastNodeBuilds`:

```luau
		if result.work ~= nil then
			-- HOW MANY LAYOUT NODES THIS SOLVE HAD. The repair below already reads
			-- it; publishing it costs nothing and is the only honest denominator for
			-- `arranged + translated + skipped` (`stats.lastSkipped` is written ONLY
			-- when skipped > 0 at `:1972-1975`, so it is stale by design).
			stats.lastLayoutNodes = nodeStore.nodes
			result.work.skipped = math.max(0, nodeStore.nodes - (result.work.arranged or 0))
		end
```
with `lastLayoutNodes = 0` declared beside `lastCommitVisits = 0` at `:621`.

- [ ] **Step 3: The two residual spans.** The tick's 0.814 ms unattributed (profile §7) is mostly the dirty-closure build and the classification loop, and T3 rewrites the first of them — so it is measured *before* it is changed. In `renderer.luau`, wrap the classification loop (`:2747-2789`) as `profile.span("dirtyScan", function() … end)` and the ancestor-closure builder (`:2873-2894`, the `else` arm that builds `contains`) as `profile.span("dirtyClosure", function() … end)`. `profile` is already required in the file (`profile.span("commit", …)` at `:1998`). Both spans are inert unless `profile.setEnabled(true)` — which only the FacetBench harnesses do.

  **One note for the reviewer, so the wrap is not misread as a scoping bug:** the classification loop writes six *enclosing* locals — `needsSolve`, `needsStructure`, `hiddenTouched`, `presentationTouched`, `nodeDirtySeen`, `structureEpoch`. Putting it inside a closure keeps every one of those an UPVALUE write, which is legal Luau and changes nothing about where they land; it is not a new scope for them. Say so in the commit message too — a `profile.span` that quietly shadowed one of those would be a silent correctness change and the next reader should not have to re-derive that it does not.

- [ ] **Step 4: The fixture — `tests/lib/nameplates_scene.luau`.** This is the shape the arena actually drives (solver-seams §0: `ForEach` splices into its parent, so the canvas is ONE `anchor` layout node with 250 direct plate children).

```luau
--!strict
--[[ THE NAMEPLATES SCENE — the arena's workload, headless, as a Facet fixture.

	`FacetBench/frameworks/facet/adapter.luau:48-90` maps the bench's `canvas` to
	`UI.Anchor` and its `list` to `UI.ForEach` with the placement props on the
	TEMPLATE ROOT, and `layout_node.luau:1263-1275` splices a ForEach's children
	into the enclosing flow — so the layout tree is one `anchor` with 250 direct
	plate roots, each an `hstack`/`vstack` carrying `anchor = "topLeft"` plus a
	reactive `offsetX`/`offsetY`. That is the tree every demonstrator in the
	wicked-fast round pins, so it lives here rather than in one spec.

	THE MOUNTED SHAPE, WHICH IS NOT THE LAYOUT SHAPE, AND THE COUNTS DEPEND ON IT.
	`mount.luau:273-281` builds ONE region node for the ForEach (`class="ForEach"`,
	`path` = the ForEach's own path) whose `children` array (assigned at `:452`) is
	the rows' own roots. `mount.luau:357` builds `rowPath = `{path}/[{key}]`` and
	passes it to `mountNode` as a PARENT path, and `mountNode` computes
	`path = parentPath .. "/" .. id` (`:595-596`) — so **there is no per-item
	wrapper node**: the row's `Plate` sits directly in the region's children at
	`…/[p1]/Plate`, and `…/[p1]` is a path string with nothing mounted at it.
	MOUNTED is therefore LAYOUT + 1 (the region), and the 250 `…/[pN]` strings
	`markNodeDirty` writes can never become commit visits.

	AND THERE IS A `UI.Screen` ROOT, because `mountLib.mount(core, bp)` mounts the
	blueprint it is handed at `"" .. "/" .. id` (`mount.luau:713-714`, `:596`) —
	the root node IS whatever it is given. Every sibling perf spec wraps in a
	Screen (`tests/commit_scope.spec.luau:739`, RR
	`facet_measure_fanout_contract.spec.luau:110`), so this one does too rather
	than being the only fixture whose root is an Anchor.

	TWO UPDATE STEPS, BECAUSE A TICK IS NOT 250 PURE TRANSLATES (profile §1/§6).
	`tick` moves every plate and touches nothing else. `tickWithCasts` moves every
	plate AND advances the Cast bar of a deterministic one-in-five subset — a
	MEASURE-class write (`{ type = "fixed", px = cast * 100 }`) whose dirt closes
	over the bar's ancestors up to the plate root. Roughly 20 % of the arena's
	plates are casters (41-43 live at L, seeded); here the set is exact — 50 —
	because a pinned count is worth more to a demonstrator than a matched sample.

	NO FIXED x FIXED ANCESTOR ABOVE A PLATE, ON PURPOSE — AND THE TWO FIXED x FIXED
	LEAVES STILL COUNT UNTIL T4. `measure_facts.luau:409-412` classifies a
	fixed-width AND fixed-height non-text node `PLAN_SKIP`, and
	`solver.luau:1720-1722` sends a PLAN_SKIP node straight to `measureUncached`,
	which increments `ctx.measured` EVERY time it is touched — no memo, no slate,
	no dirty test. The anchor branch measures all 250 children on every arrange, so
	a fixed x fixed Canvas or plate root would make a small `lastMeasured` pin
	unreachable by construction and the T3 demonstrator would be measuring the
	fixture. The Canvas fills and the plate root is fixed-width + content-height,
	which is what that constraint buys.

	`Hp` and `Cast` ARE fixed x fixed, and the earlier claim that they "sit at the
	LEAVES where nothing re-enters them" is FALSE UNTIL T4 LANDS: a moved plate
	root fails the arrange skip, takes the vstack arrange branch, and that branch
	measures each non-hug child (`solver.luau:3290-3340`). So both are touched, per
	plate, per tick — `lastMeasured == PLATES * 2` on a pure tick after T3, and
	only T4's translate arm (which stops re-entering the subtree at all) takes it
	to 0. T3's spec pins the 500; T4's pins the 0. ]]
local UI = require("../../src/blueprint")
local mountLib = require("../../src/mount")
local environment = require("../../src/env/environment")
local renderer = require("../../src/render/renderer")
local customFactory = require("../../src/core/custom")
local path_shapes = require("../../src/controls/path_shapes")
local fake_target = require("./fake_target")

local nameplates_scene = {}

nameplates_scene.PLATES = 250
nameplates_scene.NODES_PER_PLATE = 6 -- Plate, Row, Name, Lvl, Hp, Cast
nameplates_scene.CASTER_EVERY = 5 -- every 5th plate advances its cast bar

local function px(n: number): any
	return { type = "fixed", px = n }
end
local function fill(): any
	return { type = "fill", weight = 1 }
end

export type Opts = {
	viewport: { x: number, y: number, w: number, h: number }?,
	plates: number?,
	incremental: boolean?, -- renderer.attach `incrementalLayout` (default true)
	measureReuse: boolean?, -- default true
	commitScope: boolean?, -- default true
	fractional: boolean?, -- offsets as { scale, offset } instead of plain px
	overflow: boolean?, -- plate 1 is 2,000 px wide: its subtree leaves the anchor
	withPath: boolean?, -- add one UI.Path leaf: the `visible` prune latch closes
}

-- `layout` is the LAYOUT-NODE count (`stats().lastLayoutNodes`, i.e. the solver's
-- `nodeStore.nodes`); `nodeBuilds` is what `stats().lastNodeBuilds` reports — the
-- number of node tables CONSTRUCTED on the last build, which is near zero on a
-- steady tick with a warm P3 store and is not a tree size at all. They had the
-- same name in an earlier draft of this fixture, which is exactly how a census
-- stops being a census.
export type Census = { mounted: number, layout: number, nodeBuilds: number, plates: number, casters: number }

function nameplates_scene.new(opts: Opts?)
	local o: Opts = opts or {}
	local n = o.plates or nameplates_scene.PLATES
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", o.viewport or { x = 0, y = 0, w = 1280, h = 720 })

	local items = {}
	for i = 1, n do
		local caster = i % nameplates_scene.CASTER_EVERY == 0
		items[i] = {
			key = `p{i}`,
			caster = caster,
			x = core:signal((i * 37) % 1200),
			y = core:signal((i * 53) % 680),
			hp = core:signal(0.5 + ((i % 7) / 14)),
			cast = core:signal(if caster then 0.25 else 0),
			name = `Racer {i}`,
			lvl = tostring(10 + (i % 30)),
		}
	end
	local rows = core:signal(items)

	local function offsetOf(item: any, axis: "x" | "y"): any
		local sig = if axis == "x" then item.x else item.y
		if not o.fractional then
			return sig
		end
		-- the RascalRally minimap idiom (`FacetSponsor/MapCanvas.luau:230-236`):
		-- a scaleOffset metric, so `offsetPx` resolves it against the anchor's
		-- inner extent and the answer is viewport-dependent
		return core:memo(function(use: any)
			local v = use(sig) :: number
			return { scale = v / 1280, offset = -9 }
		end)
	end

	local plateWidth = if o.overflow then 2000 else 180
	local children: { any } = {
		UI.ForEach({
				id = "Plates",
				items = rows,
				key = function(item: any)
					return item.key
				end,
				row = function(item: any)
					return UI.VStack({
						id = "Plate",
						anchor = "topLeft",
						offsetX = offsetOf(item, "x"),
						offsetY = offsetOf(item, "y"),
						padding = 0,
						gap = 2,
						width = px(if item.key == "p1" then plateWidth else 180),
						height = { type = "content" },
						children = {
							UI.HStack({
								id = "Row",
								padding = 0,
								gap = 4,
								width = fill(),
								height = px(16),
								children = {
									UI.Text({ id = "Name", textSize = 14, text = item.name }),
									UI.Text({ id = "Lvl", textSize = 12, text = item.lvl }),
								},
							}),
							UI.Box({
								id = "Hp",
								height = px(6),
								width = core:memo(function(use: any)
									return px(100 * (use(item.hp) :: number))
								end),
							}),
							UI.Box({
								id = "Cast",
								height = px(4),
								width = core:memo(function(use: any)
									return px(100 * (use(item.cast) :: number))
								end),
							}),
						},
					})
				end,
		}),
	}
	if o.withPath then
		-- one stroked path anywhere on the surface shuts `visible`'s prune for the
		-- life of the surface (`commit_walks.luau:842`, `local prunable = next(pathNodes) == nil`).
		-- The points come from `src/controls/path_shapes` rather than two literals:
		-- `UI.Path`'s own doc says `points` are normalized Path2D control points from
		-- `Facet.pathShapes` (`blueprint_schema.luau:2615-2621`), and it is the idiom
		-- `tests/commit_scope.spec.luau:759` already uses for exactly this latch.
		table.insert(children, UI.Path({ id = "Spark", points = path_shapes.ring(), thickness = 2 }))
	end
	local bp = UI.Screen({
		id = "S",
		children = { UI.Anchor({ id = "Canvas", width = fill(), height = fill(), children = children }) },
	})

	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {
		rootPolicy = "edgeToEdge",
		incrementalLayout = o.incremental ~= false,
		measureReuse = o.measureReuse ~= false,
		layoutNodeReuse = true,
		commitScope = o.commitScope ~= false,
	})
	controller.initialRender()

	local scene: any = {
		core = core,
		env = env,
		adapter = adapter,
		controller = controller,
		items = items,
		rows = rows,
	}

	function scene.tick(dx: number, dy: number)
		for _, item in items do
			item.x:set((item.x:get() :: number) + dx)
			item.y:set((item.y:get() :: number) + dy)
		end
		controller.refresh()
	end

	function scene.tickWithCasts(dx: number, dy: number)
		for _, item in items do
			item.x:set((item.x:get() :: number) + dx)
			item.y:set((item.y:get() :: number) + dy)
			if item.caster then
				-- 0.05 per tick, wrapping: never an equal write (an equal write is
				-- skipped by the signal and the caster would silently stop being one)
				local next_ = (item.cast:get() :: number) + 0.05
				item.cast:set(if next_ > 1 then 0.05 else next_)
			end
		end
		controller.refresh()
	end

	function scene.hp(i: number, fraction: number)
		items[i].hp:set(fraction)
		controller.refresh()
	end

	function scene.add(i: number)
		local caster = i % nameplates_scene.CASTER_EVERY == 0
		local item = {
			key = `add{i}`,
			caster = caster,
			x = core:signal((i * 11) % 1200),
			y = core:signal((i * 17) % 680),
			hp = core:signal(0.5),
			cast = core:signal(if caster then 0.25 else 0),
			name = `Added {i}`,
			lvl = "1",
		}
		local next_ = table.clone(rows:get() :: any)
		table.insert(next_, item)
		rows:set(next_)
		controller.refresh()
	end

	function scene.remove(i: number)
		local next_ = table.clone(rows:get() :: any)
		table.remove(next_, i)
		rows:set(next_)
		controller.refresh()
	end

	function scene.census(): Census
		local mounted = 0
		local function walk(node: any)
			mounted += 1
			for _, child in node.children do
				walk(child)
			end
		end
		walk(root.node)
		local casters = 0
		for _, item in items do
			if item.caster then
				casters += 1
			end
		end
		local st = controller.stats() :: any
		return {
			mounted = mounted,
			layout = st.lastLayoutNodes,
			nodeBuilds = st.lastNodeBuilds,
			plates = #items,
			casters = casters,
		}
	end

	function scene.stats(): any
		return controller.stats()
	end

	-- every live node's rect and every per-path fact the eight walks own — the
	-- COMMIT oracle, not just the solver's (copied from `commit_scope.spec`'s
	-- `painted` so the two read the same channels)
	function scene.snapshot(): string
		local out = {}
		for path, node in adapter.liveNodes() do
			local props = {}
			for k, v in node.props or {} do
				if type(v) == "table" then
					local inner = {}
					for k2, v2 in v do
						table.insert(inner, `{tostring(k2)}={tostring(v2)}`)
					end
					table.sort(inner)
					table.insert(props, `{k}=\{{table.concat(inner, ",")}\}`)
				else
					table.insert(props, `{k}={tostring(v)}`)
				end
			end
			table.sort(props)
			local r, hit, region = node.rect, node.hitRect, node.scrollRegion
			table.insert(
				out,
				`{path}|{if r then `{r.x},{r.y},{r.w},{r.h}` else "-"}|{table.concat(props, ",")}`
					.. `|vis={tostring(node.visible)}`
					.. `|hit={if hit then `{hit.x},{hit.y},{hit.w},{hit.h}` else "-"}`
					.. `|canvas={if region then `{region.contentW},{region.contentH}` else "-"}`
			)
		end
		table.sort(out)
		return table.concat(out, "\n")
	end

	function scene.dispose()
		controller.dispose()
		root.dispose()
	end

	return scene
end

return nameplates_scene
```

- [ ] **Step 5: The RED baseline spec — `tests/nameplates_baseline.spec.luau`.** It records the before numbers and, from this commit on, fails if any of them moves for a reason nobody wrote down. The counts are stated as EXPRESSIONS over the census; the literals beside them are what the expressions evaluate to at `PLATES = 250` with a `UI.Screen` root, one `ForEach` region node, and **no per-item wrapper** (the mounted shape derived in the fixture header from `mount.luau:273-281`, `:357`, `:452`, `:595-596`).

```luau
--!strict
--[[ THE BEFORE NUMBERS, ON DISK (wicked-fast T2). Every later demonstrator in
	this round reads a "currently N" from here rather than from a memory of a
	profiling run, so an improvement cannot be a moved goalpost. The arena's own
	numbers (1,489 arranged / 1,241 measured / 1,488 writes on a 1,465-layout-node
	tree) are the WORKLOAD's; these are this FIXTURE's, and they are not the same
	tree — `FacetBench/docs/profiling/2026-09-02-nameplates-attribution.md` is the
	workload's record.

	THESE PINS MOVE, AND THE TASK THAT MOVES ONE UPDATES IT WITH THE MEASUREMENT
	THAT LICENSED IT — never by loosening the assertion (ENGINEERING.md: "pin
	every human-locked baseline and fail on drift"). The schedule is known in
	advance, so an unexpected move is a finding:

	  | pin | moved by | to |
	  |---|---|---|
	  | `lastMeasured` on a tick   | T3 | 500 = PLATES x 2 (pure) / read off the run (casters) |
	  | `lastMeasured` on a tick   | T4 | 0 (pure) — the translate arm stops re-entering the subtree |
	  | `lastArranged`             | T4 | 252 (pure) / 302 (casters, see T4 Step 1's competing derivation) |
	  | `lastRectInserts`          | T4 | arranged + translated = 1,502 |
	  | every per-walk visit count | T5 | 253 (pure) / 303 (casters); hitRects stays 1,503 |
	  | the four hidden-blind walks | T5b (if built) | 3 on a pure tick |
	  | the census, `rectWrites`   | never | 1,503 mounted / 1,502 layout / 1,500 writes |

	253 is Screen + Canvas + the ForEach region + one root per plate. The 250
	`…/[pN]` strings `markNodeDirty` also writes have NO mounted node behind them
	(`mount.luau:357` uses `rowPath` as a parent path), and `skip` is only ever
	asked about real nodes — so they are dirty PATHS and never commit VISITS. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")

local PLATES = scene.PLATES
-- + the Canvas anchor + the Screen root. The ForEach region is NOT a layout node:
-- `layout_node.luau:1263-1275` splices its children into the enclosing flow.
local LAYOUT = PLATES * scene.NODES_PER_PLATE + 2 -- 1502
-- ...+ the ForEach REGION, and nothing else. There is no per-item wrapper node
-- (`mount.luau:357` uses `rowPath` as a parent path; the row's own root is mounted
-- at `…/[pN]/Plate` by `:595-596`), so this is LAYOUT + 1, not LAYOUT + PLATES + 1.
local MOUNTED = LAYOUT + 1 -- 1503
local CASTERS = PLATES // scene.CASTER_EVERY -- 50
local MEASURED_TICK = -1 -- Step 6 writes the measured before here, with its mechanism

describe("nameplates baseline — the numbers the wicked-fast round starts from", function()
	it("the fixture is the tree the plan says it is", function()
		local s = scene.new()
		local c = s.census()
		expect(`plates={c.plates} casters={c.casters} mounted={c.mounted} layout={c.layout}`)
			.toBe(`plates={PLATES} casters={CASTERS} mounted={MOUNTED} layout={LAYOUT}`)
		s.dispose()
	end)

	it("a pure tick: a full arrange, a full re-measure, eight whole-tree walks", function()
		local s = scene.new()
		s.tick(3, 2)
		local st = s.stats()
		-- MEASURED_TICK is the number Step 6 of this task READS OFF THE RUN and
		-- writes in as a literal, with the plan-verdict breakdown that explains it
		-- in a comment beside it. It is the "currently N" every later demonstrator
		-- quotes, so it is on disk rather than in a memory of a profiling session.
		expect(st.lastMeasured).toBe(MEASURED_TICK)
		expect(st.lastArranged).toBe(LAYOUT)
		expect(st.lastRectInserts).toBe(LAYOUT)
		expect(st.rectWrites > 0 and st.lastCommitVisits >= MOUNTED * 7).toBe(true)
		-- the per-walk breakdown this task exists to publish
		local byWalk = st.lastCommitVisitsByWalk
		for _, name in { "harvest", "textScale", "padding", "textVerdicts", "visible", "hitRects", "scrollRegions", "rectPass" } do
			expect(`{name}={byWalk[name]}`).toBe(`{name}={MOUNTED}`)
		end
		s.dispose()
	end)

	it("...and a caster tick moves the same numbers (the mixed-dirt step exists and bites)", function()
		local s = scene.new()
		s.tick(3, 2)
		local pure = s.stats().lastMeasured
		s.tickWithCasts(3, 2)
		local mixed = s.stats().lastMeasured
		expect(mixed >= pure).toBe(true)
		expect(s.stats().lastArranged).toBe(LAYOUT)
		s.dispose()
	end)
end)
```

- [ ] **Step 6: Run it and WRITE THE NUMBERS DOWN.** `lune run tests/run_one nameplates_baseline`. Two outcomes are legitimate:
  - it passes → the census matches the expressions (1,503 mounted / 1,502 layout).
  - `mounted` or `layout` differs → **do not change the assertion to match.** Update the EXPRESSION and its comment to what the census actually shows, and record the discovered shape in the fixture header. The expressions, not the literals, are the contract; every later task's pins are the same expressions. (The shape is now derived from `mount.luau` rather than guessed — `mount.luau:273-281`/`:357`/`:452`/`:595-596`/`:713-714` — so a mismatch here is a finding about the *mount*, not a chore.)

  Then record, in the task report and in the new ledger (Step 8), the measured `lastMeasured` for `tick` and for `tickWithCasts`, and the p50 of `lune run tools/profile/attr nameplates L 3` — the arena's tick is the number T9 reports against.

- [ ] **Step 7: FacetBench — `attr.luau` prints the two counters the profile could not.** In `tools/profile/attr.luau`, add to `statFields` (the list ending `"textMeasureBatches"` at `:130-131`): `"lastRectInserts"`, `"lastTranslated"`, `"lastCommitVisits"`, `"lastSsVisited"`, `"lastLayoutNodes"`, `"lastSolveSkipped"`. Immediately after the `for _, f in statFields do … end` loop (`:163-174`) add:

```luau
	local byWalk = (st :: any).lastCommitVisitsByWalk
	if type(byWalk) == "table" then
		for walk, n in byWalk do
			local key = "cv." .. walk
			b.cnt[key] = b.cnt[key] or {}
			table.insert(b.cnt[key], n)
		end
	end
```
`lib_attr.luau` needs no edit for the two new spans: it already installs `profile.setHooks` (`lib_attr.luau:112-133`) and `attr.luau` prints every accumulator key it finds (`:210-240`), so `span:dirtyScan` and `span:dirtyClosure` appear on their own. `lastTranslated` / `lastSolveSkipped` / `lastSsVisited` read `nil` until T4 / T4 / T7 land — guard the `statFields` loop with `st[f] or 0` so a missing field prints 0 instead of erroring.

Verify: `cd ../FacetBench && lune run tools/profile/attr nameplates S 1` prints `cv.harvest=… cv.rectPass=…` in the `updateItems-plates` count line and a `span:dirtyClosure` row.

- [ ] **Step 8: Create the running ledger** — `FacetBench/docs/profiling/2026-09-02-wicked-ledger.md`:

```markdown
# Wicked-fast — running ABBA ledger

One row per landed Facet fix. Command, every row: `lune run tools/profile/attr nameplates L 3`
(median of the three tick p50s), from the FacetBench root with the sibling Facet checkout at
the stated commit. `_fixture` must read 1.00x on the matrix row that accompanies it.

| date | Facet commit | task | tick p50 (ms) | tick gcKb | hp p50 (ms) | add/remove p50 (ms) | note |
|---|---|---|---:|---:|---:|---|---|
| 2026-09-02 | 2d9f90cf | before | 8.578 | 4048 | 0.539 | 1.332 / 1.281 | profile §1 |
```

- [ ] **Step 9: Gates + RR.** Facet: `tools/test.sh 8006`, `tools/verify.sh affected --jobs 1`, `python3 tools/check_source_size.py`, `stylua --check src tests tools bench examples`. FacetBench: `tools/check.sh` (stylua excludes `tools/profile`, so also run `stylua tools/profile/attr.luau` by hand). RR: `stats()` gains a key, which `games/RascalRally/code/tests/facet_measure_fanout_contract.spec.luau:440` reads by name — check it still reads `lastCommitVisits` (unchanged meaning) and run `./run-tests.sh`. No RR source change; the compatibility evidence is the green suite plus the `lastCommitVisits == 256` pin at `:608` still holding (it must — this task changes where the number is accumulated, not what it counts). If it moves, the accumulation is wrong: fix the counter, not the pin.

- [ ] **Step 10: Fresh-context review**, then commit — two repos, two commits:

```bash
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet
cat > /tmp/facet-b-t2.msg <<'MSG'
test(perf): nameplates fixture + per-walk commit visit counters

`stats().lastCommitVisitsByWalk` (a fresh table per commit; the per-node cost
goes DOWN — a local increment, published once a walk), two profile spans over
the refresh's dirty scan and closure build, and `tests/lib/nameplates_scene.luau`
— the arena's tick as a headless fixture, with the mixed-dirt `tickWithCasts`
step. `tests/nameplates_baseline.spec.luau` pins the BEFORE numbers.
MSG
python3 tools/commit_isolated.py -m /tmp/facet-b-t2.msg \
  tests/lib/nameplates_scene.luau \
  tests/nameplates_baseline.spec.luau \
  src/render/commit_walks.luau:"publishVisits" \
  src/render/rect_pass.luau:"publishVisits" \
  src/render/renderer.luau:"lastCommitVisitsByWalk","dirtyClosure","dirtyScan"

cd ../FacetBench
git add tools/profile/attr.luau docs/profiling/2026-09-02-wicked-ledger.md
git commit -m "profile: per-walk commit visits, rectInserts/translated/ssVisited, running ledger"
```

---

### Task 3 (T3): O2 — split `dirtyContains` into a measure half and an arrange half

**Files:**
- Modify: `src/render/renderer.luau:2873-2894` (the closure builder's `else` arm), `:1945-1951` (`solveOpts.reuse`), and the file-local beside `dirtyContains`
- Modify: `src/layout/solver.luau:1792-1814` (the adopt gate). **No `Ctx` type edit:** `Ctx.reuse` is declared `reuse: any` at `solver.luau:525` — there is no `dirtyContains`-typed record to add a field to, so "add `measureContains` to the `reuse` record's type" would be a no-op. Introducing a real `Reuse` record type and changing `reuse: any` to `reuse: Reuse?` is a separate, separately-reviewable change and is NOT in this round.
- Create: `tests/measure_split.spec.luau`
- Modify: `tests/layout_prop_dirt.spec.luau` (the positive per-prop proof)
- Create: `games/RascalRally/code/tests/facet_measure_split.spec.luau`

**Interfaces:**
- Consumes: `dirty` entries `{ path: string, class: string, prop: string? }` (`mount.luau:91-103`); `measure_reuse.adopt(store, node, reusable, containerW, containerH)` (`measure_reuse.luau:174-204`).
- Produces: `solveOpts.reuse = { previous = lastResult, dirtyContains = <set>, measureContains = <set> }`. `measureContains ⊆ dirtyContains` always; on the structural path both are `structuralPlan.contains` (conservative — a structural change can change a measure).
- Produces: the adopt gate's third argument becomes `ctx.reuse ~= nil and ctx.reuse.measureContains[node.id] ~= true`.

- [ ] **Step 1: Write the failing demonstrator — `tests/measure_split.spec.luau`.** It must state the pins for BOTH step kinds, and it must explain *why* the before number is what it is before changing it.

```luau
--!strict
--[[ O2 — MEASURE DIRT AND ARRANGE DIRT ARE NOT THE SAME SET.

	`renderer.luau:2873-2894` closes the dirty set over ancestors for `measure`
	AND `arrange` entries together, and hands the union to the solver as one
	`dirtyContains`. The solver reads it twice for two different questions: the
	arrange skip (`solver.luau:2222-2266`) asks "did anything inside move?", and
	the ADOPT GATE (`:1792-1814`) asks "can this node keep the measure slate it
	filled last solve?". `offsetX`/`offsetY`/`anchor` are `dirty = { "arrange" }`
	(`blueprint_schema.luau:754-780`) and measure provably never reads them
	(`solver.luau:1448-1457` — the anchor/zstack/region measure branch has no
	offset in it), so every offset-only step throws away a measure slate it
	could have kept.

	WHY THE BEFORE NUMBER IS AS BIG AS IT IS, and the demonstrator says it out
	loud rather than assuming it: a refused slate is REPLACED, not just missed
	(`measure_reuse.luau:138-144` writes a fresh table into `store.byId[id]`), so
	the plate root re-measures; and the plate's own fixed x fixed leaves are
	`PLAN_SKIP` (`measure_facts.luau:409-412`), which `solver.luau:1720-1722`
	sends straight to `measureUncached` — no memo, counted every time. The
	arena's 1,241 is those two mechanisms on a 1,465-node tree. If THIS fixture's
	before number is not explained by that arithmetic, add a temporary counter
	next to `ctx.measured += 1` that buckets by plan verdict and report the real
	mechanism BEFORE fixing anything.

	AND THE AFTER NUMBER IS NOT ZERO AT THIS TASK — IT CANNOT BE, BY CONSTRUCTION.
	The split fixes the ADOPT gate; it does not stop the plate's own arrange from
	descending. At T3 there is no translate arm yet, so a moved plate root is in
	`dirtyContains`, fails the arrange skip, and takes the vstack arrange branch,
	which measures each non-hug child (`solver.luau:3290-3340`,
	`local w, h = measure(ctx, child, innerW, innerH)`). `Row` (height px(16))
	hits its slate and costs nothing; `Hp` and `Cast` are fixed x fixed, hence
	`PLAN_SKIP`, hence counted on EVERY touch — two per plate, every plate, every
	tick. So the pure-tick pin here is `PLATES * 2`, and the `== 0` pin belongs to
	`tests/translate_arm.spec.luau` (T4), where the translate arm stops re-entering
	the subtree at all. A demonstrator that pinned 0 here would be red for the
	whole of T3 with no fix available, which is the "unreachable green" class.

	THE CASTER NUMBER IS READ OFF THE RUN, and this header says why it is not
	knowable on paper. It is the sum of three things the source does not let you
	count without running it: how many ancestors lose their slate when a Cast
	box's measure dirt closes over them (the Canvas's own child list is
	re-measured, and whether the Screen is depends on the root policy's chrome
	facts); how many of those ancestors are themselves PLAN_SKIP or PLAN_KEYED;
	and how many times the vstack branch touches the two PLAN_SKIP leaves under a
	caster (its own measure pass AND its arrange pass are two separate touches of
	the same node, and only the second is guaranteed). Step 2 runs it, and the
	number goes in as a literal WITH the plan-verdict bucket breakdown that
	explains it. THE PROTOCOL: update the EXPRESSION and its comment, never the
	assertion. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")
local device_views = require("./lib/device_views")

local PLATES = scene.PLATES
-- Hp and Cast are fixed x fixed => PLAN_SKIP => `measureUncached` counts them on
-- every touch, and the plate's own arrange touches both. See the header: this is
-- the T3 floor, and T4 takes it to 0.
local MEASURED_TICK = PLATES * 2 -- 500
-- READ OFF THE RUN in Step 2, with the plan-verdict breakdown beside it. Do not
-- guess it: the ancestor-slate arithmetic is not decidable from the source alone.
local MEASURED_WITH_CASTS = -1

describe("O2: an arrange-only step does not re-measure MORE THAN ITS PLAN_SKIP LEAVES", function()
	it("a pure tick measures only the two PLAN_SKIP leaves per plate", function()
		local s = scene.new()
		s.tick(3, 2) -- warm: the first tick after initialRender is not the steady state
		s.tick(3, 2)
		expect(s.stats().lastMeasured).toBe(MEASURED_TICK)
		s.dispose()
	end)

	it("a caster tick measures the cast bars and their ancestors' slates, and nothing else", function()
		local s = scene.new()
		s.tickWithCasts(3, 2)
		s.tickWithCasts(3, 2)
		expect(s.stats().lastMeasured).toBe(MEASURED_WITH_CASTS)
		s.dispose()
	end)

	it("...at every device view, including 320x640", function()
		for _, view in device_views.VIEWS do
			local s = scene.new({ viewport = { x = 0, y = 0, w = view.w, h = view.h } })
			s.tick(3, 2)
			s.tick(3, 2)
			expect(`{view.id}:{s.stats().lastMeasured}`).toBe(`{view.id}:{MEASURED_TICK}`)
			s.dispose()
		end
	end)
end)
```

- [ ] **Step 2: Run to verify it fails, and READ THE TWO NUMBERS OFF THE RUN** — `lune run tests/run_one measure_split`. Expected: FAIL on the pure-tick pin with a large number (the fixture's before, recorded in T2), and FAIL on the caster pin against the `-1` placeholder. Record the actual before and the plan-verdict breakdown in the task report; if the before is not explained by "fresh slate for every `dirtyContains` id + PLAN_SKIP leaves under them", instrument (a temporary bucket beside `ctx.measured += 1`) and report the real mechanism before Step 3.

  After Step 3 lands, re-run and write `MEASURED_WITH_CASTS`'s EXPRESSION — not a bare literal: `CASTERS * <touches per caster>` plus the named ancestor term, with a one-line comment saying which nodes each term is. If the pure-tick pin does not land on exactly `PLATES * 2`, that is a finding about the fixture's plan verdicts, not a number to relax: bucket `ctx.measured` by `memoPlan` verdict, report which nodes are being counted, and correct the EXPRESSION with the mechanism written into the spec header.

- [ ] **Step 3: Implement the split.** `renderer.luau:2873-2894` (the `else` arm that builds `contains`) — build both sets in the one pass, with the prefix walk terminating **per set** (an arrange entry that already filled a prefix chain must not stop a later measure entry from filling the measure chain):

```luau
				--[[ TWO CLOSURES, NOT ONE (wicked-fast O2). The arrange half is what
					it always was: every dirty node plus every ancestor, and the solver
					skips exactly what is absent. The MEASURE half carries only
					`measure` dirt and its prefixes, because that is the only question
					the adopt gate (`solver.luau:1801`) is asking — "can this node keep
					the slate it filled?" — and an offset-only change cannot answer it
					with "no". The prefix walk terminates PER SET: an arrange entry that
					has already filled a chain must not cut a later measure entry's. ]]
				local contains: { [string]: boolean } = {}
				local measures: { [string]: boolean } = {}
				for _, entry in dirty do
					local path = entry.path
					local isMeasure = entry.class == "measure"
					if (isMeasure or entry.class == "arrange") and path ~= nil then
						contains[path] = true
						if isMeasure then
							measures[path] = true
						end
						local at = path
						while true do
							local cut = string.match(at, "^(.*)/[^/]*$")
							if cut == nil or cut == "" then
								break
							end
							local seenArrange = contains[cut]
							contains[cut] = true
							if isMeasure then
								if measures[cut] then
									break
								end
								measures[cut] = true
							elseif seenArrange then
								break
							end
							at = cut
						end
					end
				end
				dirtyContains = contains
				measureContains = measures
```
The structural arm above it sets both to `structuralPlan.contains` (`dirtyContains = if structuralPlan ~= nil then structuralPlan.contains else nil; measureContains = dirtyContains`). Reset both to `nil` where `dirtyContains` is reset after the `pcall`. Declare `measureContains` beside the existing `dirtyContains` file-local.

`renderer.luau:1945-1951`:
```luau
		if incrementalEnabled and lastResult ~= nil and dirtyContains ~= nil then
			solveOpts.reuse = {
				previous = lastResult,
				dirtyContains = dirtyContains,
				-- a solve with no measure half is a solve that cannot prove a slate
				-- is stale, so it falls back to the arrange half — never to `nil`
				measureContains = measureContains or dirtyContains,
			}
```
`solver.luau:1801-1806` — the adopt gate's `reusable` argument becomes `ctx.reuse ~= nil and ctx.reuse.measureContains[node.id] ~= true`. **No type edit accompanies it:** `Ctx.reuse` is `reuse: any` (`solver.luau:525`), so there is no record to widen — adding a field to a `dirtyContains`-typed record would be editing a type that does not exist. **The arrange skip at `:2222-2266` keeps reading `dirtyContains` — unchanged.**

- [ ] **Step 4: The three-arm differential oracle** — append to `tests/measure_split.spec.luau`, the `measure_reuse.spec.luau:492-501` shape, over the fixture and every device view, both step kinds, plus the two Risk fixtures the spec demands:

```luau
local function arms(view: any, opts: any): (any, any, any)
	local base = table.clone(opts or {})
	base.viewport = { x = 0, y = 0, w = view.w, h = view.h }
	local a = table.clone(base) -- cache ON, incremental ON
	local b = table.clone(base)
	b.measureReuse = false -- cache OFF, incremental ON
	local c = table.clone(base)
	c.measureReuse = false
	c.incremental = false -- BOTH OFF: a forced full solve, the ground truth
	return scene.new(a), scene.new(b), scene.new(c)
end

describe("O2 oracle: byte-equal to a full solve, every view, every step kind", function()
	for _, fixture in { { name = "plain" }, { name = "overflow", overflow = true }, { name = "fractional", fractional = true } } do
		it(`{fixture.name}: rects, visibility, hit rects and text verdicts survive the split`, function()
			for _, view in device_views.VIEWS do
				local a, b, c = arms(view, fixture)
				local label = `{fixture.name}/{view.id}`
				-- (no `expect(label).toBe(label)` line here: an assertion whose two
				-- sides are the same expression proves nothing — the repo's own
				-- "check that proves nothing" class. The mount check is the
				-- snapshot comparison immediately below.)
				if a.snapshot() ~= c.snapshot() then
					error(`{label}: diverged from a FULL solve at mount`, 0)
				end
				for step = 1, 4 do
					local dx, dy = step * 3, step * 2
					a.tick(dx, dy)
					b.tick(dx, dy)
					c.tick(dx, dy)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: tick {step} diverged from a FULL solve`, 0)
					end
					if a.snapshot() ~= b.snapshot() then
						error(`{label}: tick {step} diverged from the memo-less solve`, 0)
					end
					a.tickWithCasts(dx, dy)
					b.tickWithCasts(dx, dy)
					c.tickWithCasts(dx, dy)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: caster tick {step} diverged from a FULL solve`, 0)
					end
					a.hp(7, 0.1 * step)
					b.hp(7, 0.1 * step)
					c.hp(7, 0.1 * step)
					if a.snapshot() ~= c.snapshot() then
						error(`{label}: hp {step} diverged from a FULL solve`, 0)
					end
				end
				a.dispose()
				b.dispose()
				c.dispose()
			end
		end)
	end
end)
```

- [ ] **Step 5: The prop-dirt audit becomes a positive proof.** `tests/layout_prop_dirt.spec.luau` today derives prop→class pairs from `layout_node.luau`'s reads and fails on drift; the split needs the stronger statement *"a prop declared arrange-only is provably unread by measure"*. Append a driver that MOUNTS each such prop and measures — not a grep:

```luau
--[[ THE SPLIT'S OWN AUDIT (wicked-fast O2). `renderer.luau`'s closure now trusts
	the declared class to decide whether a node keeps its measure slate, so
	"declared arrange-only" has to be a FACT about the solver, not a claim in the
	schema. For every (class, prop) whose declared classes are exactly
	{ "arrange" }, mount it, change it, and assert the solve measured NOTHING.
	The values come from the schema itself (`enum[1]` and `enum[#enum]`, or 0 and
	7 for a number), so the audit cannot drift out of date when an enum grows.
	A prop that fails here is a REAL finding — either its declared class is wrong
	or measure reads it. Do not weaken the assertion to make it pass.

	THE PARENT MATTERS, AND A WRONG ONE MAKES THE AUDIT VACUOUS. `alignH`/`alignV`
	under a stack are INERT — `placement_audit.luau:92-99` gives them to `zstack`,
	`grid` and `gridrow` only, and `:183-189` files an inert-placement diagnostic
	for exactly the stack pairing — so an audit that drove `alignH` on a vstack
	child would drive a prop nothing consumes and pass while measuring nothing.
	Each parent below is the kind `placement_audit.luau:89-117` says READS that
	prop.

	THE SET IS EIGHT, NOT NINE. `grep -n 'dirty = { "arrange" }' src/blueprint_schema.luau`
	returns nine hits and one of them (`:1174`) is inside a comment. The eight real
	arrange-only specs are `anchor` (`:754`), `offsetX` (`:763`), `offsetY` (`:772`),
	`lineAlign` (`:801`), `alignH` (`:876`), `alignV` (`:885`), `hidden` (`:967`)
	and `distribute` (`DISTRIBUTE`, `:1176`). `layoutPriority` (`:828`),
	`shrinkWeight` (`:837`) and `gridSpan` (`:866`) are `dirty = { "measure" }` and
	are NOT audited here — they are already covered by the existing measure-class
	rows of this spec, and putting them in this table would assert the opposite of
	what the schema declares.

	AND THE AUDIT'S OWN FIXTURE INHERITS THE PLAN_SKIP HAZARD (T3 Step 1's
	header): if both children it mounts are fixed x fixed, they are `PLAN_SKIP`,
	`measureUncached` counts them on every touch, and `lastMeasured == 0` is
	unreachable no matter how correct the split is. The children below are
	`width = px(20), height = { type = "content" }` with a text leaf inside —
	content on one axis is enough to leave PLAN_SKIP. ]]
-- solver KIND -> the blueprint class that mounts it. Two of the kinds are not
-- classes at all: `hwrap`/`vwrap` are `UI.HStack`/`UI.VStack` with `wrap = true`
-- (`layout_node.luau:474`), and `gridrow` is `UI.GridRow` inside a `UI.Grid`.
local CLASS_FOR_KIND: { [string]: (children: { any }) -> any } = {
	anchor = function(children)
		return UI.Anchor({ id = "P", width = px(200), height = px(200), children = children })
	end,
	zstack = function(children)
		return UI.ZStack({ id = "P", width = px(200), height = px(200), children = children })
	end,
	hstack = function(children)
		return UI.HStack({ id = "P", padding = 0, gap = 0, width = px(200), height = px(200), children = children })
	end,
	vstack = function(children)
		return UI.VStack({ id = "P", padding = 0, gap = 0, width = px(200), height = px(200), children = children })
	end,
	hwrap = function(children)
		return UI.HStack({
			id = "P",
			wrap = true,
			padding = 0,
			gap = 0,
			width = px(200),
			height = px(200),
			children = children,
		})
	end,
	gridrow = function(children)
		return UI.Grid({
			id = "P",
			width = px(200),
			height = px(200),
			children = { UI.GridRow({ id = "R", children = children }) },
		})
	end,
}

-- prop -> the parent KIND that reads it (`src/layout/placement_audit.luau:89-117`).
-- `hidden` has no parent requirement (it is read on the node itself, wherever it
-- sits), and `distribute` is a CONTAINER prop — it is driven on the mounted parent,
-- not on a child — so it carries the `SELF` marker the driver branches on.
local PARENT_FOR: { [string]: string } = {
	anchor = "anchor",
	offsetX = "anchor",
	offsetY = "anchor",
	alignH = "zstack",
	alignV = "zstack",
	lineAlign = "hstack",
	hidden = "vstack",
	distribute = "SELF",
}
```
For each arrange-only prop the driver builds the parent `CLASS_FOR_KIND[PARENT_FOR[prop]]` with two children (each `width = px(20)`, `height = { type = "content" }`, one text leaf inside — never fixed × fixed, see the header), drives the prop from value A to value B through a signal, refreshes, and expects `stats().lastMeasured == 0` — at all nine `device_views.VIEWS`. For `distribute` the signal is bound on the PARENT instead of a child; everything else is identical. `PARENT_FOR` must cover every arrange-only prop the schema reports, and only those; the driver asserts both directions (`expect(PARENT_FOR[prop] ~= nil).toBe(true)` with the prop name in the message, and the reverse — every key of `PARENT_FOR` is still `dirty = { "arrange" }` in the schema), so a schema that gains a ninth arrange-only prop, or reclassifies one of these to `measure`, fails here instead of silently escaping the audit.

- [ ] **Step 6: Run everything**

```bash
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet
lune run tests/run_one measure_split
lune run tests/run_one layout_prop_dirt
lune run tests/run_one measure_reuse
lune run tests/run_one rect_cow
lune run tests/run_one incremental_layout
lune run tests/run_one container_relative_incremental
lune run tests/run_one nameplates_baseline
```
`nameplates_baseline` goes red on its `lastMeasured` comparison — that is this task's whole point. Update that pin to `PLATES * 2` (pure) and the caster number read off the run, in the baseline spec's schedule table row, with this commit's sha beside it, in the same commit. Do not delete the assertion.

- [ ] **Step 7: Prove the demonstrator bites.** Revert the adopt gate's argument to `dirtyContains` (one word) and re-run `measure_split` — it must go red on the pure-tick pin with the T2 before number. Restore. A demonstrator that passes both ways is measuring nothing (`docs/lessons/`, the gate-integrity rule).

- [ ] **Step 8: Gates** — `tools/test.sh 8006`; `tools/verify.sh affected --jobs 1`; `python3 tools/check_source_size.py` (solver + renderer both inside the warning band: if either row's size drifts > 2,000 chars from its ledger cell, re-record the row in this commit); `stylua --check src tests tools bench examples`.

- [ ] **Step 9: RascalRally lockstep — `tests/facet_measure_split.spec.luau`.** The game's own moving-anchor surface is the sponsor minimap: `src/client/FacetSponsor/MapCanvas.luau:230-236` builds each dot's `offsetX`/`offsetY` as memos over the racer's `u`/`v`, and `MapCanvas.build` is mounted headless by `tests/facet_sponsor_omen.spec.luau:527-577` (`mapWorld`) — copy that mount. The spec drives a position-only change and asserts the framework did not re-measure:

```luau
-- drive u/v only: every dot moves, nothing resizes
map.setDots({ { key = "Kart1", u = 0.30, v = 0.40, name = "R1", color = …, family = "help" }, … })
local st = map.controller.stats()
expect(`measured={st.lastMeasured}`).toBe("measured=0")
```
plus the game-side differential: the same drive against a controller attached with `incrementalLayout = false, measureReuse = false` must produce a byte-equal `adapter.liveNodes()` rect dump. Header per the exemplar (`facet_nested_tree_consumer_contract.spec.luau:1-40`): name the Facet mechanism with file:line, name the game call sites the re-audit found (`MapCanvas.luau:230-236`, and the fact that no other game surface animates a placement prop — state the grep that found it), and say why the game needs no source edit. Then `./run-tests.sh`. If `facet_measure_fanout_contract.spec.luau:605-608`'s pins move, update them with the measurement in that file's own table and say what licensed it.

- [ ] **Step 10: Fresh-context review** — dispatch code-reviewer over the diff + the demonstrator. The questions to put in the prompt: *"can a `measure`-class entry's prefix chain be cut short by an earlier `arrange` entry?"*, *"what happens on the structural path where `measureContains` is the plan's `contains`?"*, *"is there any solver read of `dirtyContains` that meant the measure question?"*

- [ ] **Step 11: ABBA re-measure + ledger row**

```bash
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/FacetBench
lune run tools/profile/attr nameplates L 3
```
Append the median tick p50 / gcKb / hp p50 to `docs/profiling/2026-09-02-wicked-ledger.md` as a row named `T3 O2 measure split` with the Facet commit sha, then `git add docs/profiling/2026-09-02-wicked-ledger.md && git commit -m "ledger: T3 (O2 measure/arrange split) re-measure"`.

- [ ] **Step 12: Commit (Facet, then RR)**

```bash
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet
cat > /tmp/facet-b-t3.msg <<'MSG'
perf(layout): split dirtyContains into measure and arrange halves

An offset-only step re-measured 1,241 nodes because one closure answered two
questions. The adopt gate now reads a `measureContains` built from `measure`
dirt only; the arrange skip still reads the full set. A pure nameplates tick
measures PLATES*2 = 500 (was: the fixture's baseline number) — the floor is the
plate's two fixed x fixed leaves, which are PLAN_SKIP and are counted on every
touch until T4 stops re-entering the subtree; a caster tick measures <read off
the run>. Oracle: byte-equal to a forced full solve across all nine device views
incl. 320x640, plus overflow and fractional-offset fixtures. `layout_prop_dirt`
now PROVES each of the EIGHT arrange-only props is unread by measure by mounting
it under the parent kind `placement_audit` says reads it, not by grepping.
MSG
python3 tools/commit_isolated.py -m /tmp/facet-b-t3.msg \
  src/render/renderer.luau:"measureContains" \
  src/layout/solver.luau:"measureContains" \
  tests/measure_split.spec.luau \
  tests/layout_prop_dirt.spec.luau:"arrange-only" \
  tools/lune/verify/data/source-cap-ledger.md:"solver.luau"

cd ../../../games/RascalRally/code
git add tests/facet_measure_split.spec.luau tests/run.luau tests/facet_measure_fanout_contract.spec.luau
git commit -m "test(facet): consumer rider for the measure/arrange dirt split (minimap dots)"
```
(`tests/run.luau` gets the new spec's name — every RR task below does the same.)

---

### Task 4 (T4): O3 — the translate arm

**Files:**
- Modify: `src/layout/solver.luau:2222-2266` (the skip site, gaining a third arm), `:2265-2271` (the counters + the `walkedIds` write, which MOVES below the entry write), `:2273-2302` (the ordinary entry write — the translate root takes it), `:3709-3722` (ctx init), `:3761-3765` (the `skipped` subtraction), `:3801-3812` (`result.work`)
- Modify: `src/render/renderer.luau:1969-1971` (the `work.skipped` rewrite — **`:1969-1971`, not `:1957-1959`**; `:1957-1959` is inside the `solveOpts.measures` block), `:1986-1991` (`lastArranged`/`lastMeasured`/`lastRectInserts`, where `lastTranslated` and `lastSolveSkipped` join them), `:621` (stats fields)
- Modify: `tests/rect_cow.spec.luau:495-497` (the two invariant pins)
- Create: `tests/translate_arm.spec.luau`
- Create: `games/RascalRally/code/tests/facet_translate.spec.luau`

**Interfaces:**
- Consumes: `ctx.reuse.dirtyContains`, `reuse.previous.rects[id]` entries `{ rect, containerW, containerH, offerW, offerH, kind, overflow, textState, compact, textFacts, hitFloor, barInset? }` (`solver.luau:2273-2302`, `:2602`).
- Produces: `ctx.translated`, `ctx.translatedRoots: { [string]: { dx: number, dy: number, from: number, to: number } }`, `ctx.translatedPaths: { string }`, `ctx.translatedEntries: { any }` — the last two are parallel flat arrays in document order (T5 reads them; nothing else may).
- Produces: `result.work.translated`, `result.work.translatedRoots`, `result.work.translatedPaths`, `result.work.translatedEntries`; `stats().lastTranslated`; `stats().lastSolveSkipped` (`result.work.skipped` published UNCONDITIONALLY — the existing `stats.lastSkipped` is written only when `skipped > 0` (`renderer.luau:1972-1975`) and is therefore stale by design, which no invariant may read).
- Produces: on every translated DESCENDANT entry, `entry.moveOnly = true` and `entry.prev = <the entry it superseded>`; and the same pair on the translate ROOT's ordinary entry, which is inert until T5b (the root is in `nodeDirty`, so `skip` refuses it before it ever looks at `moveOnly`). Invariant maintained: `arranged + translated + skipped == layoutNodes`, and `rectInserts == arranged + translated`.

- [ ] **Step 1: Write the failing demonstrator — `tests/translate_arm.spec.luau`**

```luau
--!strict
--[[ O3 — A SUBTREE THAT ONLY MOVED IS RE-BASED, NOT RE-ENTERED.

	The arrange skip (`solver.luau:2222-2266`) is on ABSOLUTE-rect identity: a
	moved plate fails `pr.x == rect.x` at its root and at every descendant, so
	250 moves arrange 1,489 nodes. But an unchanged subtree that moved is its old
	rects plus one delta, known without walking it — and the rect map is
	copy-on-write (`solver.luau:3752`), so writing it is a delta write per
	descendant with no re-entry.

	THE PINS AND THEIR ARITHMETIC (fixture: 250 plates x 6 nodes + the Canvas
	anchor + the Screen root = 1,502 layout nodes; the ForEach region is NOT a
	layout node — `layout_node.luau:1263-1275` splices its children into the
	enclosing flow):
	  pure tick        arranged 252 = Screen + Canvas + 250 plate roots (each is
	                   in `dirtyContains` — its own offsetX wrote the dirt — so it
	                   takes the ORDINARY entry write, and its 5 descendants are
	                   re-based by `translateDescendants`)
	                   translated 1,250 = 250 x 5
	  caster tick      arranged 302 / translated 1,200 — SEE THE NEXT PARAGRAPH,
	                   WHICH IS THE ONE THING IN THIS SPEC THAT IS NOT SETTLED ON
	                   PAPER.

	THE CASTER SPLIT HAS TWO CANDIDATE DERIVATIONS AND STEP 2 DECIDES IT.
	(a) 302 / 1,200 — 2 ancestors + 250 plate roots + 50 Cast boxes arranged; a
	caster's Row/Name/Lvl/Hp translate under its root.
	(b) 402 / 1,100 — because `translatable` as written does NOT require the node
	to be dirty. On a caster tick the plate root has a dirty child (Cast), so it
	takes the ordinary arrange and descends; its `Row` is then clean, the same
	size (`width = fill()` inside a `px(180)` plate) and moved, so `Row` is
	ITSELF a translate root (arranged 1, translating Name + Lvl = 2), and `Hp` is
	a childless translate root (arranged 1, translating 0). Per caster:
	arranged 4 (Plate, Row, Hp, Cast) + translated 2 = 6 nodes. Totals
	2 + 200 + 50*4 = 402 arranged and 200*5 + 50*2 = 1,100 translated.
	Both sum to 1,502, so the invariant cannot tell them apart. (b) is what the
	code in Step 3 does as written; (a) is what an earlier draft of this plan
	assumed. **Step 2 reads the run.** Whichever it reports IS the mechanism:
	correct the EXPRESSIONS below and this paragraph, never the assertion, and
	say in the task report which derivation held and why.

	The caster plate root does NOT resize under either derivation — the fixture's
	plate is `width = px(180)`, `height = content`, and the cast bar's height is
	fixed — so no plate hugs its bar. If the implementer measures a resize
	instead, the plate hugs the bar somewhere and the pin is the measured shape
	WITH the mechanism written down here. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")
local device_views = require("./lib/device_views")

local PLATES = scene.PLATES
local CASTERS = PLATES // scene.CASTER_EVERY
local LAYOUT = PLATES * scene.NODES_PER_PLATE + 2 -- 1502
local ARRANGED_TICK = PLATES + 2 -- 252
local TRANSLATED_TICK = PLATES * (scene.NODES_PER_PLATE - 1) -- 1250
-- derivation (a); if Step 2 reports derivation (b) these become
--   ARRANGED_CASTS  = PLATES + 2 + CASTERS * 3        -- 402 (Plate, Row, Hp, Cast)
--   TRANSLATED_CASTS = (PLATES - CASTERS) * 5 + CASTERS * 2 -- 1100 (Name + Lvl)
-- and the header's caster paragraph is rewritten to say which one held.
local ARRANGED_CASTS = PLATES + 2 + CASTERS -- 302
local TRANSLATED_CASTS = (PLATES - CASTERS) * 5 + CASTERS * 4 -- 1200

describe("O3: a moved-not-resized subtree translates", function()
	it("a pure tick arranges the roots and translates the rest", function()
		local s = scene.new()
		s.tick(3, 2)
		s.tick(3, 2)
		local st = s.stats()
		expect(`arranged={st.lastArranged} translated={st.lastTranslated}`)
			.toBe(`arranged={ARRANGED_TICK} translated={TRANSLATED_TICK}`)
		s.dispose()
	end)

	it("a caster tick arranges the bars too", function()
		local s = scene.new()
		s.tickWithCasts(3, 2)
		s.tickWithCasts(3, 2)
		local st = s.stats()
		expect(`arranged={st.lastArranged} translated={st.lastTranslated}`)
			.toBe(`arranged={ARRANGED_CASTS} translated={TRANSLATED_CASTS}`)
		s.dispose()
	end)

	it("a pure tick now measures NOTHING (the pin T3 could not reach)", function()
		-- T3's floor was `PLATES * 2`: the plate's own arrange descended into two
		-- fixed x fixed, PLAN_SKIP leaves that `measureUncached` counts on every
		-- touch. The translate arm does not descend at all, so the touches stop.
		local s = scene.new()
		s.tick(3, 2)
		s.tick(3, 2)
		expect(s.stats().lastMeasured).toBe(0)
		s.dispose()
	end)

	it("the work invariant holds and every translated node is a rect insert", function()
		local s = scene.new()
		s.tick(3, 2)
		s.tick(3, 2)
		local st = s.stats()
		-- `lastSolveSkipped`, NOT `lastSkipped`: `renderer.luau:1972-1975` writes
		-- `lastSkipped` only when skipped > 0, so on a step that skipped nothing it
		-- still holds the PREVIOUS step's number and an invariant reading it would
		-- pass or fail on history. The sum is `nodeStore.nodes` by construction
		-- (`:1969-1971` derives `skipped` from it), so what this line actually pins
		-- is that the fixture really has LAYOUT layout nodes — and
		-- `lastLayoutNodes` says so directly, which is why both are asserted.
		expect(st.lastLayoutNodes).toBe(LAYOUT)
		expect(st.lastArranged + st.lastTranslated + st.lastSolveSkipped).toBe(LAYOUT)
		-- ...and THIS one is the independent pin: nothing derives `rectInserts`
		-- from `arranged`, so an arm that counted a write it did not make shows up
		-- here and nowhere else.
		expect(st.lastRectInserts).toBe(st.lastArranged + st.lastTranslated)
		s.dispose()
	end)

	it("THE TRANSLATE ROOT'S OWN RECT MOVES (the pin no counter can make)", function()
		-- The counter pins above all pass on a translate arm that returns from the
		-- skip site without writing `out[node.id]` — `arranged`, `translated` and
		-- `rectInserts` are all incremented, and the plate simply never moves on
		-- screen. This is the assertion that catches it: the ADAPTER's rect for a
		-- plate root, before and after, differs by exactly the delta.
		local s = scene.new()
		s.tick(3, 2)
		local path = "/S/Canvas/Plates/[p7]/Plate"
		local before = s.adapter.liveNodes()[path].rect
		s.tick(3, 2)
		local after = s.adapter.liveNodes()[path].rect
		expect(`dx={after.x - before.x} dy={after.y - before.y}`).toBe("dx=3 dy=2")
		-- ...and a descendant of it moved by the same delta, from the re-based run
		local kidPath = "/S/Canvas/Plates/[p7]/Plate/Hp"
		local kidAfter = s.adapter.liveNodes()[kidPath].rect
		s.tick(3, 2)
		local kidNext = s.adapter.liveNodes()[kidPath].rect
		expect(`dx={kidNext.x - kidAfter.x} dy={kidNext.y - kidAfter.y}`).toBe("dx=3 dy=2")
		s.dispose()
	end)

	it("the writes are REAL and they all still happen (the flat tree, profile §1)", function()
		local s = scene.new()
		s.tick(3, 2)
		local before = s.stats().rectWrites
		s.tick(3, 2)
		expect(s.stats().rectWrites - before).toBe(PLATES * scene.NODES_PER_PLATE) -- 1500
		s.dispose()
	end)

	it("...at every device view, including 320x640", function()
		for _, view in device_views.VIEWS do
			local s = scene.new({ viewport = { x = 0, y = 0, w = view.w, h = view.h } })
			s.tick(3, 2)
			s.tick(3, 2)
			local st = s.stats()
			expect(`{view.id}:{st.lastArranged}/{st.lastTranslated}`)
				.toBe(`{view.id}:{ARRANGED_TICK}/{TRANSLATED_TICK}`)
			s.dispose()
		end
	end)
end)
```

- [ ] **Step 2: Run to verify it fails** — `lune run tests/run_one translate_arm`. Expected: FAIL immediately, `lastTranslated` is `nil` (the counter does not exist) and `lastArranged` reads 1502. **Read the caster step's `arranged`/`translated` off this run too** — it is what settles derivation (a) vs (b) in the spec header, and it can be read before the arm exists only as `arranged == 1502`; the settling run is the one after Step 3.

- [ ] **Step 3: Implement the arm.** `solver.luau:2222-2266`, restructured so the *size* test is shared and the two arms differ only in what they do about position. **The translate root does NOT return early: it falls through to the ordinary entry write at `:2273-2302` and re-bases its descendants afterwards.** An earlier draft returned from inside the skip site, which meant `out[node.id]` was never updated — the plate root kept its old frozen rect, `rect_pass.applyOne` compared equal and wrote nothing, the 250 plates never moved on screen, and `rectInserts` counted a rect that was not inserted. Every counter pin in this spec would still have passed. Hence: one arm, one entry write, honest counters.

```luau
local function arrange(ctx: Ctx, node: Node, rect: Rect, out: { [string]: any })
	local reuse = ctx.reuse
	-- set by the translate arm below and consumed after the entry write; nil on
	-- every ordinary arrange, which is nearly all of them
	local tdx: number?, tdy: number? = nil, nil
	if reuse ~= nil then
		local prev = reuse.previous.rects[node.id]
		local pr = if prev ~= nil then prev.rect else nil
		local containerOk = node.containerRelativeInside ~= true
			or (prev ~= nil and prev.containerW == ctx.containerW and prev.containerH == ctx.containerH)
		if pr ~= nil and containerOk and pr.w == rect.w and pr.h == rect.h then
			local clean = reuse.dirtyContains[node.id] ~= true
			if clean and pr.x == rect.x and pr.y == rect.y then
				-- THE SKIP, unchanged (P2): `out` IS the previous map, so the subtree
				-- is already right, table for table.
				return
			end
			--[[ THE TRANSLATE (wicked-fast O3). Same size, different origin, and
				NOTHING INSIDE IS DIRTY — which `dirtyContains` proves in one test
				per child rather than per descendant, because it is closed over
				ancestors: a dirty descendant would have put its parent in the set.
				So this subtree's rects are its old rects plus one delta, and it is
				written without measuring, arranging or re-entering anything. A node
				that is itself dirty still qualifies (its own offset moved it) as
				long as no CHILD is — that is what makes the plate root, not its
				children, the translate root the commit can then act on.

				IT DOES NOT RETURN HERE. The root's own rect is this solve's, and
				only the ordinary write below records it — with this solve's offers,
				text verdicts and container, exactly as any other arranged node. ]]
			if translatable(reuse, node) then
				tdx, tdy = rect.x - pr.x, rect.y - pr.y
			end
		end
	end
	ctx.arranged += 1
	ctx.rectInserts += 1
	local gap = node.gap or 0
	out[node.id] = {
		-- … the ordinary entry literal, UNCHANGED (`solver.luau:2273-2302`) …
	}
	if tdx ~= nil then
		local entry = out[node.id]
		--[[ THE ROOT IS A MOVE TOO, AND SAYS SO. Its size is unchanged (proved
			above), none of its children is dirty (proved above), and the only
			reason it is not clean is its own placement prop — so `moveOnly` is a
			true statement about it. It is INERT until T5b: `skip` refuses any path
			in `nodeDirty` before it looks at `moveOnly`, and a translate root that
			got here because of its own dirt is in `nodeDirty` by construction. T5b
			is what removes it from the COMMIT-side set and cashes this line in. ]]
		local prevEntry = (ctx.reuse :: any).previous.rects[node.id]
		entry.moveOnly = true
		entry.prev = prevEntry
		prevEntry.prev = nil
		local from = #ctx.translatedPaths + 1
		if translateDescendants(ctx, node, tdx, tdy :: number, out) then
			ctx.translatedRoots[node.id] = { dx = tdx, dy = tdy :: number, from = from, to = #ctx.translatedPaths }
			-- WHO WALKED: NOT THIS NODE. Its body did not run, so it filed no
			-- findings this solve, and `solve`'s replay (`:3795-3799`) must replay
			-- its previous ones exactly as it does for a skipped subtree. Being
			-- `arranged` and absent from `walkedIds` is a NEW class — before this
			-- task the two were the same set — and the replay's invariant is
			-- "`walkedIds` answers for whether this node's body ran", which still
			-- holds. Marking it walked here would silently delete the diagnostics
			-- of every node that only moved.
			return
		end
		--[[ REFUSED, AND ROLLED BACK. A descendant with no `previous.rects` entry
			cannot be re-based (see `translateDescendants`), so this node takes the
			ordinary container dispatch below, which recomputes every descendant and
			overwrites whatever the partial run wrote. What must NOT survive is the
			partial run's BOOKKEEPING, or `rectInserts == arranged + translated`
			would count the same nodes twice. ]]
		local wrote = #ctx.translatedPaths - from + 1
		if wrote > 0 then
			for i = #ctx.translatedPaths, from, -1 do
				ctx.translatedPaths[i] = nil
				ctx.translatedEntries[i] = nil
			end
			ctx.translated -= wrote
			ctx.rectInserts -= wrote
		end
		entry.moveOnly = nil
		entry.prev = nil
	end
	-- WHO WALKED, for the diagnostic replay in `solve`; on a reuse solve this set is
	-- the touched path, not the tree. MOVED BELOW THE ENTRY WRITE by this task so
	-- that a translate root — which returns above without running its body — is not
	-- in it, while a REFUSED translate (which does run its body) is.
	if reuse ~= nil then
		ctx.walkedIds[node.id] = true
	end
```
with the two helpers above `arrange` (`local function`, so `translateDescendants` can recurse into itself; neither calls `arrange`, so no forward declaration is needed):

```luau
	-- no child in the dirty set => no DESCENDANT in it (the set is prefix-closed),
	-- so one pass over the children answers for the whole subtree. The same pass
	-- refuses a child the previous solve never recorded — a partial previous solve
	-- (`solver.luau:3752`: a throw mid-solve tears `lastResult`) is the only way to
	-- reach that, and it is cheaper to refuse it here than to unwind it below.
	local function translatable(reuse: any, node: Node): boolean
		local rects = reuse.previous.rects
		for _, child in node.children or {} do
			if reuse.dirtyContains[child.id] == true or rects[child.id] == nil then
				return false
			end
		end
		return true
	end

	--[[ RE-BASE EVERY DESCENDANT BY (dx, dy). Returns false — having written some
		of them — if any node below has no previous entry; the caller rolls the
		partial run back and takes the ordinary arrange, which rewrites all of it.

		WHY THE GUARD IS NOT DEAD CODE EVEN THOUGH IT SHOULD NEVER FIRE: `translatable`
		only inspects DIRECT children, so a newly built GRANDCHILD is not covered by
		it. The argument that it cannot happen is real but indirect — a new grandchild
		means its parent's `children` array changed, which means `layout_node.build`
		rebuilt the parent, which puts the parent in `nodeStore.builtIds`, which
		`structural_scope.widen` (`renderer.luau:1917`) unions into
		`structuralPlan.contains`, which IS `dirtyContains` on the structural path —
		so the parent is dirty and `translatable` already refused. That is four
		inferences across three files to justify an unguarded `prevEntry.rect`, and
		the failure mode if any link breaks is an indexing error inside a protected
		solve boundary. The guard costs one nil test per node. ]]
	local function translateDescendants(ctx: Ctx, node: Node, dx: number, dy: number, out: { [string]: any }): boolean
		local rects = (ctx.reuse :: any).previous.rects
		for _, child in node.children or {} do
			local prevEntry = rects[child.id]
			if prevEntry == nil or prevEntry.rect == nil then
				return false
			end
			local old = prevEntry.rect
			local entry = table.clone(prevEntry)
			entry.rect = table.freeze({ x = old.x + dx, y = old.y + dy, w = old.w, h = old.h })
			entry.moveOnly = true
			entry.prev = prevEntry
			--[[ THE CHAIN BREAK. `prev` exists for exactly one reader — the NEXT
				commit's `skip`, comparing table identity — and the entry we are
				superseding on this very line does not need its own any more. Leaving
				it makes every tick retain the whole history of the plate: tick N's
				entry holds N-1, which holds N-2, forever. `tests/translate_arm.spec`
				pins a flat heap over 200 ticks and goes red if this line is removed. ]]
			prevEntry.prev = nil
			out[child.id] = entry
			ctx.translated += 1
			ctx.rectInserts += 1
			table.insert(ctx.translatedPaths, child.id)
			table.insert(ctx.translatedEntries, entry)
			if not translateDescendants(ctx, child, dx, dy, out) then
				return false
			end
		end
		return true
	end
```
Note what the arm deliberately does **not** touch: `ctx.walkedIds` for the translate root or any translated descendant (see the comment above — the new arranged-but-not-walked class, and why `solver.luau:3795-3799`'s replay is correct for it), and `ctx.offers` (the descendants' offers are unchanged — the clone carries `offerW`/`offerH` forward; the ROOT's offers are this solve's, written by whatever measured it). Container-relative descendants are safe because the root's `containerOk` held and no ancestor between the root and them changed size.

**One interaction to carry into T6.** `ctx.offers` is written ONLY in `measureUncached` (`solver.luau:1962-1963`) and is fresh per solve, so a node measured through a memo hit already records `offerW = nil` in its entry today — the offer channel is best-effort and T6's third arm degrades to a `measure()` call when it is absent, never to a wrong answer. T6 Step 5 nevertheless writes the offers it serves from cache, so a translate root's ordinary entry write does not record a `nil` offer that costs the NEXT tick a measure.

ctx init (`solver.luau:3709-3722`): `translated = 0`, `translatedRoots = {}`, `translatedPaths = {}`, `translatedEntries = {}`. The subtraction (`:3761-3765`):

```luau
	if ctx.reuse ~= nil then
		local pw = ctx.reuse.previous.work
		local total = if pw ~= nil then (pw.arranged or 0) + (pw.translated or 0) + (pw.skipped or 0) else 0
		ctx.skipped = math.max(0, total - ctx.arranged - ctx.translated)
	end
```
`result.work` (`:3801-3812`) gains `translated = ctx.translated`, `translatedRoots = ctx.translatedRoots`, `translatedPaths = ctx.translatedPaths`, `translatedEntries = ctx.translatedEntries`.

`renderer.luau:1969-1971` — the renderer's own rewrite of `skipped` must subtract the new class too (this is the block T2 already touched to publish `lastLayoutNodes`; **`:1957-1959` is not it** — that is inside the `solveOpts.measures` assignment):

```luau
		if result.work ~= nil then
			stats.lastLayoutNodes = nodeStore.nodes
			result.work.skipped =
				math.max(0, nodeStore.nodes - (result.work.arranged or 0) - (result.work.translated or 0))
		end
```
`renderer.luau:1986-1991` publishes `stats.lastTranslated = result.work.translated or 0` and, beside it, `stats.lastSolveSkipped = result.work.skipped or 0` — **unconditionally**, unlike `stats.lastSkipped` at `:1972-1975`, which is written only when `skipped > 0` and is therefore stale by design on any step that skipped nothing. `lastSkipped`'s existing meaning is untouched (four specs assert it). Declare `lastTranslated = 0` and `lastSolveSkipped = 0` in the stats table (`:621`).

- [ ] **Step 4: Fix the invariant pins that were true only because the class did not exist.** `tests/rect_cow.spec.luau:497` asserts `lastRectInserts == lastArranged`; it becomes `lastRectInserts == lastArranged + lastTranslated`. `:495` asserts `lastRectInserts + lastSkipped == total`; it becomes `lastArranged + lastTranslated + lastSolveSkipped == total` — note `lastSolveSkipped`, the unconditional publish this task adds, not the stale-by-design `lastSkipped` (`renderer.luau:1972-1975`). If `rect_cow`'s existing steps all skip something, the two are equal there and the change is invisible in that file; take it anyway, because the pin's next reader will not know which fixtures skip. Add a one-paragraph comment at each site naming the new class and this task, so the next reader knows the pin was widened deliberately.

`tests/nameplates_baseline.spec.luau` goes red on `lastMeasured` (T3's `PLATES * 2` → 0), on `lastArranged` (1,502 → 252) and on `lastRectInserts`: update those three rows of its schedule table to the T4 column with this commit's sha, in this commit. `lune run tests/run_one nameplates_baseline` and `lune run tests/run_one measure_split` green afterwards — `measure_split`'s pure-tick pin also moves to 0 here, which is the one pin in this round that TWO tasks touch, and T4 is the task that writes the mechanism into both headers.

- [ ] **Step 5: The heap pin (the chain break)** — append to `tests/translate_arm.spec.luau`:

```luau
	it("200 ticks do not retain the history of a plate", function()
		local s = scene.new()
		for _ = 1, 20 do
			s.tick(1, 1)
		end
		collectgarbage("collect")
		local before = collectgarbage("count") :: number
		for _ = 1, 200 do
			s.tick(1, 1)
		end
		collectgarbage("collect")
		local after = collectgarbage("count") :: number
		-- 200 ticks x 1,250 retained entries would be tens of MB; the pin is
		-- deliberately loose in absolute terms and lethal to a chain leak
		expect(`grewKb<1024={tostring(after - before < 1024)}`).toBe("grewKb<1024=true")
		s.dispose()
	end)
```

- [ ] **Step 6: The differential oracle** — the same three-arm block as T3 Step 4 (plain / overflow / fractional, all nine views, `tick` + `tickWithCasts` + `hp`), added to this spec against the translate arm. It is the definition of "no behavior change" for this task: the fake adapter's rects, visibility, hit rects and scroll regions byte-equal to the forced full solve at every step.

- [ ] **Step 7: Prop-dirt: nothing moves.** State it in the spec header, do not edit the audit: **the translate class is derived from rect deltas, not from a prop class.** No `dirty = { … }` entry changes, `LAYOUT_CLASSES` in `layout_prop_dirt.spec.luau:54` is untouched, and `renderer.luau:2765-2785`'s dispatch is untouched. The audit T3 added still holds because it asserts `lastMeasured`, which this task does not touch.

- [ ] **Step 8: Prove it bites** — change `translatable` to `return false` and re-run: `translate_arm` must go red with `translated=0 arranged=1502`. Then a second mutation, because the first cannot see the defect this step's design exists to prevent: delete the `if tdx ~= nil then … end` block's `translateDescendants` call but keep the `return`, i.e. re-create the early-return draft — the counter pins all still pass and only the new root-rect pin and the differential oracle go red. Restore both.

- [ ] **Step 9: Gates** — `tools/test.sh 8006`; `tools/verify.sh affected --jobs 1`; `python3 tools/check_source_size.py` (the solver grew: if headroom < 1,000, take the ledger's stack-branch seam now); `stylua --check src tests tools bench examples`.

- [ ] **Step 10: RascalRally — `tests/facet_translate.spec.luau`.** Same minimap mount as T3 (`facet_sponsor_omen.spec.luau:527-577`). Assertions: after a `setDots` that only moves the dots, `stats().lastTranslated > 0` and `lastArranged` is bounded by (dots + the canvas chain) — state the exact number the shipped surface produces, measured, in the header table; and the rect dump equals a full-solve arm's. The header must also record the re-audit: the game reaches into a rendered instance in exactly one place (`FacetSettingsGui.luau:103-104`, `adapter.getInstance(path)` — a flat path lookup, `screen_target.luau:1503-1525`), and a translated node's handle is written through the same `adapter.setRect`, so nothing in the game observes the difference. Then `./run-tests.sh`.

- [ ] **Step 11: Fresh-context review.** Prompt questions: *"can `translatable` return true while a descendant is dirty?"*, *"what happens when a translated subtree contains a scroll host with `barInset`?"*, *"is `prevEntry.prev = nil` safe given `lastCommitEntry` holds that table?"*, *"does anything read `previous.rects[id]` after `out[id]` is overwritten in the same solve?"*, *"does the translate root write its OWN entry into `out`, and is `rectInserts` counting exactly the entries that were inserted?"*, *"a translate root is `arranged` and absent from `walkedIds` — does `solve`'s diagnostic replay (`:3795-3799`) then do the right thing for it, and does the REFUSED path put it back in?"*, *"after a refusal, are `ctx.translated`, `ctx.rectInserts`, `ctx.translatedPaths` and `ctx.translatedEntries` exactly what they were before the attempt?"*

- [ ] **Step 12: ABBA + ledger row** (`T4 O3 translate arm`), as T3 Step 11.

- [ ] **Step 13: Commit**

```bash
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet
cat > /tmp/facet-b-t4.msg <<'MSG'
perf(layout): arrange gains a translate arm

A subtree whose size is unchanged, whose origin moved and none of whose children
are in the dirty set is re-based by (dx, dy) into the COW rect map instead of
being re-entered: the ROOT takes the ordinary entry write (so `rectInserts` is
honest and the plate actually moves), then `translateDescendants` re-bases the
rest — new frozen rect, cloned entry, `moveOnly` + `prev` for the commit, no
measure and no arrange. A descendant with no previous entry refuses the whole
run, rolls the bookkeeping back and takes the ordinary arrange. A translate root
is arranged and deliberately NOT in `walkedIds`: its body did not run, so its
diagnostics replay. A nameplates tick at 250 plates goes 1,502
arranged -> 252 arranged + 1,250 translated; a caster tick <302+1,200 or
402+1,100, read off the run — see the spec header>. The
1,500 rect WRITES are unchanged — they are real in a flat engine tree. Invariant
`arranged + translated + skipped == layoutNodes` and `rectInserts == arranged +
translated`, both re-pinned in rect_cow.spec. Oracle byte-equal to a forced full
solve across nine device views incl. 320x640, overflow and fractional fixtures.
MSG
python3 tools/commit_isolated.py -m /tmp/facet-b-t4.msg \
  src/layout/solver.luau:"translateDescendants","translatable","translated" \
  src/render/renderer.luau:"lastTranslated","lastSolveSkipped" \
  tests/translate_arm.spec.luau \
  tests/rect_cow.spec.luau:"lastTranslated"

cd ../../../games/RascalRally/code
git add tests/facet_translate.spec.luau tests/run.luau
git commit -m "test(facet): consumer rider for the solver's translate arm (minimap dots move, nothing re-arranges)"
```

---

### Task 5 (T5): O4 + N1 — the commit under a translate

**Files:**
- Modify: `src/render/commit_walks.luau:351-377` — `probeEntry` `:351-361`, `skip` `:363-369` (its dirty refuse is `:364`), `note` `:375-377`; `skip` gains `moveBlind`, `scope` gains `noteEntry` — plus the six position-independent walks' `skip` call sites (`:465`, `:595`, `:689`, `:758`, `:850`, `:1090` regions) and the constructor return (`:1195-1210`)
- Modify: `src/render/rect_pass.luau:97-142` (`apply` gains the translated-run arm and a third parameter)
- Modify: `src/render/renderer.luau:2103` (`rectPass.apply(root.node, result.rects, result.work)`) — **`:2103`, not `:2013`**; `:2013` is inside the `harvest` call block
- Create: `tests/commit_translate.spec.luau`
- Create: `games/RascalRally/code/tests/facet_commit_translate.spec.luau`

**Interfaces:**
- Consumes: `result.work.translatedRoots / translatedPaths / translatedEntries` (T4), `entry.moveOnly`, `entry.prev`.
- Produces: `skip(node: any, moveBlind: boolean?): boolean` — the second argument means *"this walk's output cannot depend on position, so a `moveOnly` entry whose `prev` is what I last committed is as good as no change at all"*. `scope.noteEntry(path: string, entry: any)` — writes `lastCommitEntry[path]`, for the rect pass's fast arm which applies descendants it never visits as nodes.
- Produces: `rect_pass.apply(rootNode: any, rects: { [string]: any }, work: any?)` — `work` nil (initialRender, or any solve with no translate) falls back to today's walk exactly.

- [ ] **Step 1: Write the failing demonstrator — `tests/commit_translate.spec.luau`.** The pin table, derived (fixture: **1,503 mounted nodes** — 1,502 layout nodes plus the ForEach region, and no per-item wrapper; the VISITED dirty closure on a pure tick is Screen + Canvas + the region + one root per plate = **253**, plus the 50 Cast paths = **303** on a caster tick. `markNodeDirty` also writes 250 `…/[pN]` path strings with no mounted node behind them — dirty PATHS, never commit VISITS):

| walk | before | pure tick | caster tick | why |
|---|---:|---:|---:|---|
| harvest | 1503 | 253 | 303 | hidden/composition/textFacts: no rect, no position |
| textScale | 1503 | 253 | 303 | textSize/theme only |
| padding | 1503 | 253 | 303 | class + `props.padding` only |
| textVerdicts | 1503 | 253 | 303 | size-derived verdicts only |
| visible | 1503 | 253 | 303 | position-independent while `prunable` (no `UI.Path`) |
| scrollRegions | 1503 | 253 | 303 | reads `rect.w`/`rect.h`, never x/y |
| hitRects | 1503 | 1503 | 1503 | **must** see a move: `r.x`/`r.y` centre the expander |
| rect_pass | 1503 | 253 | 303 | stops at each translate root, applies its run |
| `rectWrites` | 1500 | 1500 | 1500 | real engine writes in a flat tree |

The caster column reads 303 under **either** of T4's two candidate derivations, which is why it is stated flatly here while T4's arranged/translated split is not: under derivation (b) a caster's `Row` and `Hp` are themselves translate roots whose entries carry `moveOnly`, so the six walks skip them exactly as they skip a descendant — the visited set is still Plate + Cast per caster.

**The floor is `|nodeDirty|`, not zero, and the plan says so rather than promising 0**: `skip` refuses for any path in `nodeDirty` (`commit_walks.luau:364`), and every plate root wrote a prop this tick, so the six pruned walks visit exactly the dirty closure and stop at its edge. **Getting below that needs a class-aware `nodeDirty` — an arrange-class prop write that does not mark the COMMIT's set — and that is Task 5b, immediately after this one, gated by its own 5 % drop test.** It is not a T9 ledger line: at the plan's own projected 4.5 ms landing the six pruned walks still cost ≈ 0.27 ms at 253 visits (0.758 + 0.249 + 0.186 + 0.175 + 0.136 + 0.118 = 1.622 ms over ~1,500 visits each today, i.e. ≈ 0.18 µs a visit; 253 x 6 = 1,518 visits), which is **6.1 %** — over the same 5 % bar this plan uses to drop O1, the build and hitRects.

```luau
--!strict
--[[ O4 + N1 — THE COMMIT UNDER A TRANSLATE.

	Of the eight walks, five are provably position-independent, `visible` is too
	on any surface without a stroked `UI.Path`, and only `hitRects` and
	`rect_pass` genuinely need to see a move (commit-seams 1.11). They all
	descend anyway, because `skip` compares ENTRY TABLE IDENTITY
	(`commit_walks.luau:363-369`) and a moved node has a new entry table.

	So a translated entry carries `moveOnly` and a `prev` pointer at the table it
	superseded, and a walk that cannot depend on position asks `skip(node, true)`
	— which accepts "same entry as last commit" OR "a move away from the entry I
	last committed". `visible` passes `true` only when its existing whole-surface
	`prunable` latch is open, so one `UI.Path` still closes it, exactly as today.

	And `rect_pass` stops at a translate root: the 1,500 writes are real (flat
	engine tree, profile §1) but the WALK and the `rectsEqual` compare are not —
	the run the solver recorded is the subtree in document order, and every rect
	in it provably differs from what was last written, so the compare is dead
	work. `lastCommitEntry` is still maintained for every applied path
	(`scope.noteEntry`), or the next commit's prune would compare against a
	two-ticks-old table and descend everything. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")
local device_views = require("./lib/device_views")

local PLATES = scene.PLATES
local CASTERS = PLATES // scene.CASTER_EVERY
-- layout nodes + the ForEach REGION. There is no per-item wrapper node
-- (`mount.luau:357` uses `rowPath` as a parent path; `:595-596` mounts the row's
-- own root at `…/[pN]/Plate`), so this is LAYOUT + 1.
local MOUNTED = PLATES * scene.NODES_PER_PLATE + 2 + 1 -- 1503
-- the VISITED closure: Screen, Canvas, the region, one root per plate. The 250
-- `…/[pN]` strings `markNodeDirty` also writes have no node behind them and `skip`
-- is never asked about them.
local DIRTY_TICK = 3 + PLATES -- 253
local DIRTY_CASTS = DIRTY_TICK + CASTERS -- 303
local PRUNED = { "harvest", "textScale", "padding", "textVerdicts", "visible", "scrollRegions", "rectPass" }

describe("O4/N1: six walks stop at a moved subtree, two do not", function()
	it("a pure tick", function()
		local s = scene.new()
		s.tick(3, 2)
		s.tick(3, 2)
		local by = s.stats().lastCommitVisitsByWalk
		for _, name in PRUNED do
			expect(`{name}={by[name]}`).toBe(`{name}={DIRTY_TICK}`)
		end
		expect(`hitRects={by.hitRects}`).toBe(`hitRects={MOUNTED}`)
		s.dispose()
	end)

	it("a caster tick pays for the cast bars and nothing else", function()
		local s = scene.new()
		s.tickWithCasts(3, 2)
		s.tickWithCasts(3, 2)
		local by = s.stats().lastCommitVisitsByWalk
		for _, name in PRUNED do
			expect(`{name}={by[name]}`).toBe(`{name}={DIRTY_CASTS}`)
		end
		s.dispose()
	end)

	it("the writes are all still there", function()
		local s = scene.new()
		s.tick(3, 2)
		local before = s.stats().rectWrites
		s.tick(3, 2)
		expect(s.stats().rectWrites - before).toBe(PLATES * scene.NODES_PER_PLATE)
		s.dispose()
	end)

	it("ONE UI.Path closes the visible prune, and only that one", function()
		local s = scene.new({ withPath = true })
		s.tick(3, 2)
		s.tick(3, 2)
		local by = s.stats().lastCommitVisitsByWalk
		expect(`visible={by.visible > DIRTY_TICK}`).toBe("visible=true")
		-- ...and `harvest` is UNCHANGED at DIRTY_TICK, not DIRTY_TICK + 1. The Spark
		-- Path leaf is never dirty (nothing writes it) and its rect never moves, so
		-- its entry keeps identity and `skip` prunes it like any other clean node.
		-- The `visible` half above is the real assertion of this test: one stroked
		-- path opens the whole-surface latch and nothing else changes.
		expect(`harvest={by.harvest}`).toBe(`harvest={DIRTY_TICK}`)
		s.dispose()
	end)
end)
```

- [ ] **Step 2: Run to verify it fails** — `lune run tests/run_one commit_translate`. Expected: every pruned walk reads `1503`.

- [ ] **Step 3: Implement `skip`'s second question** — `commit_walks.luau:363-369`:

```luau
	local function skip(node: any, moveBlind: boolean?): boolean
		if not pruning or nodeDirty[node.path] == true then
			return false
		end
		local probe = probeEntry(node)
		if probe == nil then
			return false
		end
		local last = lastCommitEntry[node.path]
		if last == probe then
			return true
		end
		-- ...OR the only thing that happened to it is a move, and this walk's
		-- output does not read a position (wicked-fast O4). `prev` is the entry
		-- the solver superseded, by identity — so this is still the
		-- table-identity test, one link further back.
		return moveBlind == true and probe.moveOnly == true and last == probe.prev
	end
	local function noteEntry(path: string, entry: any)
		lastCommitEntry[path] = entry
	end
```
Call sites: `harvest` (`:462`), `textScale` (`:592`), `padding` (`:686`), `textVerdicts` (`:755`), `scrollRegions` (`:1086`) become `skip(node, true)`. `visible` (`:850` region) becomes `if prunable and not flipped and skip(node, true) then` — `prunable` already gates it, so the `UI.Path` latch is untouched. `hitRects` (`:1027` region) stays `skip(node)`. Export `noteEntry` in the constructor's `scope` table (`:1195-1210`) beside `skip`/`note`/`armed`/`records`/`publishVisits`.

- [ ] **Step 4: Implement the rect pass's run arm** — `rect_pass.luau:97-142`:

```luau
	local function apply(rootNode: any, rects: { [string]: any }, work: any?)
		local pruning = scope.armed()
		local recording = scope.records()
		local applied: { [string]: boolean }? = if pruning then nil else {}
		local roots = if work ~= nil then work.translatedRoots else nil
		local paths = if work ~= nil then work.translatedPaths else nil
		local entries = if work ~= nil then work.translatedEntries else nil
		local visits = 0
		local function walk(node: any)
			if pruning and scope.skip(node) then
				return
			end
			visits += 1
			local entry = rects[node.path]
			if entry ~= nil then
				if applied ~= nil then
					applied[node.path] = true
				end
				applyOne(node.path, entry)
			end
			if recording and handles[node.path] ~= nil then
				scope.note(node)
			end
			--[[ THE RUN (wicked-fast N1). This node's subtree only moved, and the
				solver already wrote every descendant's rect into a flat, document
				ordered run when it re-based them. Walking the live tree to find
				them again — a hash lookup, a `rectsEqual` and a recursive call per
				node — is the 1.2 ms of `rect_pass` that is not the adapter calls.
				Every rect in the run provably differs from what was last written
				(the arm fires only when x or y moved), so the compare is dead. ]]
			local run = if roots ~= nil then roots[node.path] else nil
			if run ~= nil then
				for i = run.from, run.to do
					local path = (paths :: any)[i]
					local entryAt = (entries :: any)[i]
					lastBarInsets[path] = entryAt.barInset
					local handle = handles[path]
					if handle ~= nil then
						authority.assertWrite("common", "size", "layout")
						adapter.setRect(handle, entryAt.rect)
						lastRects[path] = entryAt.rect
						stats.rectWrites += 1
					end
					if applied ~= nil then
						applied[path] = true
					end
					if recording then
						scope.noteEntry(path, entryAt)
					end
				end
				return
			end
			for _, child in node.children do
				walk(child)
			end
		end
		walk(rootNode)
		-- … unchanged tail (the `applied` sweep and `settleRects`) …
		scope.publishVisits("rectPass", visits)
	end
```
`renderer.luau:2103` becomes `rectPass.apply(root.node, result.rects, result.work)`. `apply` with `work == nil` (initialRender, and any solve whose work has no `translatedRoots`) behaves exactly as before.

One honest consequence to write into the module header: a structural WRAPPER path inside a translated subtree (a `ForEach` item wrapper, which owns no rect) is not re-noted by the run, so the next commit's `probeEntry` on that wrapper answers with its child's entry and the wrapper is visited once more than strictly needed. In this fixture the wrappers sit *above* the plate roots, so the count is zero; the bound is "one extra visit per structural wrapper inside a translated subtree", not a correctness issue.

- [ ] **Step 5: The commit oracle — FOUR arms, not three.** Append it to this spec, comparing `scene.snapshot()` (rects **and** visibility **and** hit rects **and** scroll regions **and** every prop the fake adapter holds) against the full-solve arm, at every device view, for `tick`, `tickWithCasts`, `hp`, `add`, `remove`, and with `withPath = true` as a sixth fixture variant. This is the commit oracle the solver's own oracle cannot stand in for: T4 proved the rect map, T5 must prove what the adapter was told.

  T3's `arms()` varies `measureReuse` and `incremental` only — which is the right control for a *solver* task and the wrong one for this one. The whole subject here is the COMMIT prune, and `Opts` already exposes `commitScope`; an oracle that never turns it off is comparing this task's fix against itself. So this spec's `arms()` returns four:

```luau
local function arms(view: any, opts: any): (any, any, any, any)
	local base = table.clone(opts or {})
	base.viewport = { x = 0, y = 0, w = view.w, h = view.h }
	local a = table.clone(base) -- everything ON: the shipped configuration
	local b = table.clone(base)
	b.measureReuse = false -- memo OFF, incremental + commit prune ON
	local c = table.clone(base)
	c.measureReuse = false
	c.incremental = false -- BOTH solver halves OFF: a forced full solve
	--[[ THE FOURTH ARM, AND WHY IT IS THIS TASK'S REAL CONTROL. `commitScope` is
		the P4 prune; with it off, every walk descends the whole tree and writes
		what it finds, which is the pre-P4 build. If the pruned commit and the
		unpruned one ever tell the adapter different things, THIS is the arm that
		says so — `c` cannot, because it still runs the prune. `commit_scope.spec`'s
		own header makes the same argument for the same reason. ]]
	local d = table.clone(base)
	d.commitScope = false
	return scene.new(a), scene.new(b), scene.new(c), scene.new(d)
end
```
  and every `if a.snapshot() ~= c.snapshot()` comparison in the block gains its twin, `if a.snapshot() ~= d.snapshot() then error(`{label}: … diverged from an UNPRUNED commit`, 0) end`. All four are disposed at the end of each view.

- [ ] **Step 6: Prove it bites** — three separate mutations, each re-running the spec: (a) `moveBlind` ignored in `skip` → the six walks read 1503; (b) `scope.noteEntry` call removed from the run → the SECOND tick after a translate reads 1503 for the pruned walks (the stale-`lastCommitEntry` defect, which a single-tick test would never see — this is why the demonstrator ticks twice); (c) the `run` arm removed → `rectPass` reads 1503 with `rectWrites` unchanged. All three must go red.

- [ ] **Step 7: Gates** — as T4 Step 9, plus: `renderer.luau` and `commit_walks.luau` both grew; run `python3 tools/check_source_size.py` and re-record any warning-band row whose size drifted > 2,000 characters. `tests/nameplates_baseline.spec.luau` goes red on all eight per-walk counts: update that row of its schedule table to the T5 column (253 / 303, `hitRects` 1,503) with this commit's sha, in this commit.

- [ ] **Step 8: RascalRally — `tests/facet_commit_translate.spec.luau`.** The minimap mount again, and this time the game's own shape makes the honest point: `MapCanvas` mounts `UI.Path` (the tick ring and the trace), so `visible`'s whole-surface `prunable` latch is CLOSED there. The spec asserts, on a dots-only move: `harvest`/`textScale`/`padding`/`textVerdicts`/`scrollRegions`/`rectPass` visits bounded by the dirty closure (state the measured number), `visible` and `hitRects` at the full mounted count, and the adapter dump byte-equal to a full-solve arm. Write that asymmetry into the header as the finding it is — the game gets six of the eight walks pruned, not seven, and the reason is a spinner-shaped one. Then `./run-tests.sh`.

- [ ] **Step 9: Fresh-context review.** Prompt: *"can a `moveOnly` skip hide a change to `entry.textFacts`/`entry.composition`/`entry.compact`?"* (it cannot — the clone carries them and any change to them comes from a measure, which makes the node dirty), *"what happens when a translated subtree's root is `hiddenFlips`-forced?"*, *"is `lastCommitEntry` complete after a run?"*, *"does the run arm run when `pruning == false`?"*

- [ ] **Step 10: ABBA + ledger row** (`T5 O4+N1 commit under a translate`).

- [ ] **Step 11: Commit**

```bash
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet
cat > /tmp/facet-b-t5.msg <<'MSG'
perf(render): the commit under a translate

`skip(node, moveBlind)` — a walk whose output cannot read a position accepts a
`moveOnly` entry whose `prev` is what it last committed. Six walks pass true;
`hitRects` does not (it centres expanders on x/y) and `visible` passes it only
behind its existing UI.Path latch. `rect_pass` stops at a translate root and
emits the subtree from the solver's flat run — no walk, no `rectsEqual`, same
1,500 adapter writes — and re-notes every applied path so the NEXT commit can
still prune. Nameplates tick at 250 plates: seven walks 1,503 -> 253 visits.
MSG
python3 tools/commit_isolated.py -m /tmp/facet-b-t5.msg \
  src/render/commit_walks.luau:"moveBlind","noteEntry" \
  src/render/rect_pass.luau:"translatedRoots","noteEntry" \
  src/render/renderer.luau:"result.work)" \
  tests/commit_translate.spec.luau

cd ../../../games/RascalRally/code
git add tests/facet_commit_translate.spec.luau tests/run.luau
git commit -m "test(facet): consumer rider for the pruned commit under a translate (minimap keeps visible unpruned — UI.Path)"
```

---

### Task 5b (T5b): the commit's dirty set stops carrying pure-arrange dirt

**This task begins with the condition that may delete it**, in the shape T7 Step 1 uses. After T5 lands:

```bash
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/FacetBench
lune run tools/profile/attr nameplates L 3
```

Read `cv.harvest`, `cv.textScale`, `cv.padding`, `cv.textVerdicts`, `cv.visible`, `cv.scrollRegions` and the per-walk `attr` span accumulators on the `updateItems-plates` bucket. **If the six pruned walks sum to under 5 % of the tick, DROP the task** with a ledger line in `docs/profiling/2026-09-02-wicked-ledger.md` — *"T5b DROPPED: the six position-independent walks are X ms of a Y ms tick at L after T3-T5, under the 5 % bar"* — commit it, and skip to Task 6.

The estimate that says it will build: those six walks cost 0.758 + 0.249 + 0.186 + 0.175 + 0.136 + 0.118 = **1.622 ms** today over ~1,500 visits each (profile §1), i.e. ≈ 0.18 µs a visit. At T5's floor of 253 visits × 6 walks ≈ 1,518 visits ≈ **0.27 ms**, and the plan's own projected landing is ≈ 4.5 ms — **6.1 %**. That is over the same 5 % bar this plan uses to drop O1, `layout_node.build` and `hitRects`, which is why this is a task and not a T9 ledger line.

**Files:**
- Modify: `src/render/renderer.luau:1592` (the `nodeDirty` file-local gains a sibling), `:2735-2746` (`markNodeDirty` gains `markCommitDirty`), `:2747-2789` (the classification loop), `:1920-1923` (`builtDirty` / the reset), `:2026` (what the commit is handed)
- Modify: `src/render/commit_walks.luau:305-321` (the prune state takes two sets), `:363-369` (`skip` selects one)
- Create: `tests/commit_dirt_classes.spec.luau`
- Modify: `tests/nameplates_baseline.spec.luau` (the schedule table's T5b row)
- Create: `games/RascalRally/code/tests/facet_commit_dirt_classes.spec.luau`

**Interfaces:**
- Produces (renderer): `commitDirty: { [string]: boolean }?` — the same shape and lifecycle as `nodeDirty`, built in the same loop, omitting entries whose `class == "arrange"` and whose `prop` is one of `anchor`, `offsetX`, `offsetY`, `alignH`, `alignV`, `lineAlign`, `distribute`. **`hidden` is kept** (it is `dirty = { "arrange" }` at `blueprint_schema.luau:967` and three walks read it).
- Produces (commit_walks): the ctx gains `commitDirty` beside `nodeDirty`; `skip(node, moveBlind)` consults `commitDirty` when `moveBlind == true` and `nodeDirty` otherwise.
- Consumes: `layout_node.build(..., nodeDirty, ...)` (`renderer.luau:1911`) — **unchanged**, still the all-classes set. The P3 store genuinely needs arrange dirt: a node whose `offsetX` changed must be rebuilt.

- [ ] **Step 1: The drop test** — above. Record X and Y as this task's before, or write the ledger line and stop.

- [ ] **Step 2: The prop→walk read audit, IN THE SPEC, as the source of truth.** This is the table that licenses the whole task; it lives in `tests/commit_dirt_classes.spec.luau`'s header and is re-derived from the walk bodies (`commit_walks.luau:405-1195`), not from memory:

```
	| walk           | reads an arrange-class prop? | which                                                          |
	|----------------|------------------------------|----------------------------------------------------------------|
	| harvest        | YES                          | `authoredHidden[path]` / `entry.hidden` -> `hidden` (:427-470)  |
	| textScale      | no                           | `props.textSize` (measure), `class`, `metrics`, `entry.textFacts.size` |
	| padding        | no                           | `class`, `props.padding` (measure), `metrics`                   |
	| textVerdicts   | no                           | `class`, `#children`, the compact form, `entry.compact`, `entry.textFacts.wraps` |
	| visible        | YES                          | `hiddenRoots` (derived from `hidden`), `paintHeld`, `pathNodes` |
	| scrollRegions  | no                           | `class == "ScrollView"`, `props.axis/padding/indicators/autoscroll`, `entry.*` |
	| hitRects       | YES                          | `hiddenRoots`, plus `entry.rect` (it must see a move anyway)     |
	| rect_pass      | n/a — it IS the position pass | `entry.rect`                                                    |
```

- [ ] **Step 3: Write the failing demonstrator — `tests/commit_dirt_classes.spec.luau`**

```luau
--!strict
--[[ THE COMMIT'S DIRTY SET IS NOT THE BUILD'S (wicked-fast T5b).

	After T5 the six position-independent walks stop at a moved subtree's root —
	but not at the root itself, because `skip` refuses ANY path in `nodeDirty`
	(`commit_walks.luau:364`) and a plate root wrote `offsetX` this tick. So the
	floor is 253 visits x 6 walks, ~0.27 ms, and every one of those visits is a
	walk re-deriving an answer from inputs that did not change.

	`nodeDirty` is the right set for `layout_node.build` (`renderer.luau:1911`):
	a node whose `offsetX` changed must be rebuilt, and the P3 store's `dirty`
	argument is what makes that happen. It is the WRONG set for four of the eight
	commit walks, and the audit above is the proof: `textScale`, `padding`,
	`textVerdicts` and `scrollRegions` read no arrange-class prop at all.

	SO THERE ARE TWO SETS, NOT ONE NARROWED ONE. Build-side: every class, as
	today. Commit-side: everything except the SEVEN pure-arrange props
	(`anchor`, `offsetX`, `offsetY`, `alignH`, `alignV`, `lineAlign`,
	`distribute`), keeping `hidden` — which is arrange-class but is read by
	`harvest`, `visible` and `hitRects`.

	AND THE THREE HIDDEN-READING WALKS KEEP THE ALL-CLASSES SET. Not because
	their answer depends on a position — it does not — but because narrowing a
	walk's set is only sound if the walk cannot read anything the narrowing threw
	away, and `hiddenRoots` is DERIVED state that `harvest` itself maintains
	(`commit_walks.luau:442-470`). Keeping those three on `nodeDirty` costs 253
	visits and removes a whole class of question about ordering between the walks.
	`hitRects` is unchanged for the separate reason that it must see the move.

	WHAT MAKES THE FOUR REACH 3 AND NOT 253: T4 stamps `moveOnly`/`prev` on the
	translate ROOT's entry as well as its descendants. That stamp is inert until
	this task, because `skip` tests `nodeDirty` first; once the plate roots leave
	the commit-side set, `skip(root, true)` sees a `moveOnly` entry whose `prev`
	is what it last committed and stops there. If the four walks read 253 after
	this task, the root stamp is missing — fix T4's arm, not this pin. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")
local device_views = require("./lib/device_views")

local PLATES = scene.PLATES
local CASTERS = PLATES // scene.CASTER_EVERY
local MOUNTED = PLATES * scene.NODES_PER_PLATE + 2 + 1 -- 1503
local DIRTY_TICK = 3 + PLATES -- 253, the all-classes closure T5 left them at
local ARRANGE_BLIND = { "textScale", "padding", "textVerdicts", "scrollRegions" }
-- Screen, Canvas, the ForEach region: the three nodes whose entries this solve
-- rewrote for a reason that is not a pure-arrange prop write
local CLEAN_FLOOR = 3

describe("T5b: a pure-arrange write does not dirty the commit", function()
	it("the four hidden-blind walks stop at the top of the surface", function()
		local s = scene.new()
		s.tick(3, 2)
		s.tick(3, 2)
		local by = s.stats().lastCommitVisitsByWalk
		for _, name in ARRANGE_BLIND do
			expect(`{name}={by[name]}`).toBe(`{name}={CLEAN_FLOOR}`)
		end
		s.dispose()
	end)

	it("...and the three that read `hidden` are UNCHANGED", function()
		local s = scene.new()
		s.tick(3, 2)
		s.tick(3, 2)
		local by = s.stats().lastCommitVisitsByWalk
		expect(`harvest={by.harvest} visible={by.visible}`).toBe(`harvest={DIRTY_TICK} visible={DIRTY_TICK}`)
		expect(`hitRects={by.hitRects}`).toBe(`hitRects={MOUNTED}`)
		s.dispose()
	end)

	it("a MEASURE-class write still dirties the commit (the narrowing is not a hole)", function()
		local s = scene.new()
		s.tickWithCasts(3, 2)
		s.tickWithCasts(3, 2)
		local by = s.stats().lastCommitVisitsByWalk
		-- the 50 Cast boxes and their plate roots are back in the set: a width
		-- write is `dirty = { "measure" }` and is never dropped
		for _, name in ARRANGE_BLIND do
			expect(`{name}={by[name] >= CASTERS}`).toBe(`{name}=true`)
		end
		s.dispose()
	end)

	it("a `hidden` flip is seen by every walk that reads it, at every device view", function()
		for _, view in device_views.VIEWS do
			local s = scene.new({ viewport = { x = 0, y = 0, w = view.w, h = view.h } })
			s.tick(3, 2)
			s.hide(11, true)
			local by = s.stats().lastCommitVisitsByWalk
			-- `hidden` is arrange-class and is KEPT: harvest and visible must both
			-- have descended to the hidden node, so neither can be at CLEAN_FLOOR
			expect(`{view.id}:harvest={by.harvest > CLEAN_FLOOR} visible={by.visible > CLEAN_FLOOR}`)
				.toBe(`{view.id}:harvest=true visible=true`)
			expect(`{view.id}:{s.adapter.liveNodes()["/S/Canvas/Plates/[p11]/Plate"].visible}`)
				.toBe(`{view.id}:false`)
			s.hide(11, false)
			s.dispose()
		end
	end)
end)
```
  The fixture gains one step for this task — `scene.hide(i, on)`, the same shape as `scene.hp`:

```luau
	function scene.hide(i: number, on: boolean)
		items[i].hidden:set(on)
		controller.refresh()
	end
```
  with `hidden = core:signal(false)` added to each item in `nameplates_scene.new` and `hidden = item.hidden` on the plate's `UI.VStack`. Add it in THIS task's commit, and note in the fixture header that the pure `tick` never writes it, so no earlier pin moves.

- [ ] **Step 4: Run to verify it fails** — `lune run tests/run_one commit_dirt_classes`. Expected: the four hidden-blind walks read `253`, not `3`. Record the number.

- [ ] **Step 5: Implement the second set.** `renderer.luau`, beside the existing `nodeDirty` file-local (`:1592`):

```luau
	--[[ THE COMMIT'S OWN DIRTY SET (wicked-fast T5b). Same shape and lifecycle as
		`nodeDirty`, built in the same loop, minus the SEVEN prop writes that move a
		node and change nothing a commit walk reads. `hidden` is arrange-class and
		is KEPT — `harvest`, `visible` and `hitRects` all read it.

		WHY TWO SETS RATHER THAN ONE NARROWED ONE: `nodeDirty` is also the P3 node
		store's `dirty` argument (`renderer.luau:1911`), and the store genuinely
		needs arrange dirt — a node whose `offsetX` changed must be rebuilt or the
		solver arranges it at the old offset. Narrowing the one set would trade a
		commit win for a layout defect. ]]
	local commitDirty: { [string]: boolean }? = nil
	-- the seven props that move a node and change nothing a commit walk reads.
	-- Derived from `blueprint_schema.luau`'s eight `dirty = { "arrange" }` specs
	-- MINUS `hidden`; the per-walk read audit that licenses each omission is in
	-- `tests/commit_dirt_classes.spec.luau`'s header.
	local PURE_ARRANGE_PROPS: { [string]: boolean } = {
		anchor = true,
		offsetX = true,
		offsetY = true,
		alignH = true,
		alignV = true,
		lineAlign = true,
		distribute = true,
	}
```
  `markNodeDirty` (`:2735-2746`) is duplicated once, parameterised on the set, and the classification loop (`:2747-2789`) calls both:

```luau
		local function markDirtyIn(set: { [string]: boolean }?, path: string?)
			if set == nil or path == nil then
				return
			end
			local at: string? = path
			while at ~= nil and at ~= "" and not set[at] do
				set[at] = true
				at = string.match(at, "^(.*)/[^/]*$")
			end
		end
		local function markNodeDirty(path: string?)
			markDirtyIn(nodeDirty, path)
		end
```
  and inside the loop, immediately after `markNodeDirty(entry.path)`:

```luau
			-- ...AND THE COMMIT'S SET, WHICH A PURE PLACEMENT WRITE DOES NOT ENTER.
			-- A nil `prop` (a structural entry, a whole-node invalidation) is never
			-- dropped: the omission is decided by a NAME being in the table, never
			-- by one being absent.
			if not (entry.class == "arrange" and entry.prop ~= nil and PURE_ARRANGE_PROPS[entry.prop]) then
				markDirtyIn(commitDirty, entry.path)
			end
```
  `commitDirty` is reset to `{}` wherever `nodeDirty` is (`:1923`) and set to `nil` wherever `nodeDirty` is (`:1880`); `builtDirty`'s twin is held at `:1920` (`local builtCommitDirty = commitDirty`) and both are handed to the commit at `:2026`.

  `commit_walks.luau`: the ctx gains `commitDirty: any` beside `nodeDirty` (`:305-321`), and `skip` (`:363-369`) selects:

```luau
	local function skip(node: any, moveBlind: boolean?): boolean
		if not pruning then
			return false
		end
		-- THE SET DEPENDS ON THE QUESTION. A walk that told us its output cannot
		-- read a position is also telling us it cannot read a pure PLACEMENT prop,
		-- so it is answered against the commit-side set. Every other walk — and
		-- every walk at all when `commitDirty` was not supplied — keeps the
		-- all-classes set it has always had.
		local set = if moveBlind == true and commitDirty ~= nil then commitDirty else nodeDirty
		if set[node.path] == true then
			return false
		end
		local probe = probeEntry(node)
		if probe == nil then
			return false
		end
		local last = lastCommitEntry[node.path]
		if last == probe then
			return true
		end
		return moveBlind == true and probe.moveOnly == true and last == probe.prev
	end
```
  and the two `hidden`-reading walks that T5 gave `moveBlind` give it back: `harvest` (`:462`) and `visible` (`:850` region) revert to `skip(node)`. `textScale` (`:592`), `padding` (`:686`), `textVerdicts` (`:755`) and `scrollRegions` (`:1086`) keep `skip(node, true)`; `rect_pass` and `hitRects` were never `moveBlind`.

  **`harvest` and `visible` therefore do not improve in this task, and the commit message says so** rather than reporting a seven-walk win. They stay at T5's 253 — the all-classes set still holds every plate root — and what this task buys is the four hidden-blind walks going to 3. Reverting them is not a regression against T5 either: `skip(node, true)` and `skip(node)` give the same answer for a node that is in `nodeDirty`, which every plate root is.

- [ ] **Step 6: Extend the prop→dirty-class audit, and make it bite.** The table in Step 2 is a comment, and a comment cannot be executed — so the audit's SOURCE OF TRUTH is a real table in `tests/commit_dirt_classes.spec.luau`, asserted by a driver in the same file. T3's `layout_prop_dirt` audit answers "is this prop unread by MEASURE?"; this one answers "is this walk unread BY an arrange-class prop?", which is the different question the commit-side set depends on:

```luau
-- THE AUDIT'S SOURCE OF TRUTH. One row per walk; `true` means "this walk reads a
-- prop whose declared class is `arrange`", which is what disqualifies it from the
-- commit-side set. It is asserted against the SET, not against a grep, by the
-- driver below: for each walk marked `false`, drive each of the seven pure-arrange
-- props on a mounted fixture and assert that walk's visit count does not move.
local WALK_READS_ARRANGE: { [string]: boolean } = {
	harvest = true,
	textScale = false,
	padding = false,
	textVerdicts = false,
	visible = true,
	hitRects = true,
	scrollRegions = false,
	rectPass = true,
}
```
  and the driver: for every walk with `false`, for every prop in `PURE_ARRANGE_PROPS`, mount the T3 audit's parent for that prop (`CLASS_FOR_KIND[PARENT_FOR[prop]]`), drive the prop through a signal, refresh, and assert that walk's `lastCommitVisitsByWalk` entry is at the clean floor. **The mutation that proves it bites (Step 8):** make `padding`'s walk body read `authoredHidden[path]` — one line — and this audit must go red for `padding`, because `padding` is marked `false` and the driver now finds it descending into a `hidden`-flipped subtree. If it does not go red, the audit is a grep with extra steps and must be fixed before the task lands.

- [ ] **Step 7: Oracle** — the SAME four-arm oracle T5 Step 5 builds (plain / overflow / fractional / `withPath`, all nine views, `tick` + `tickWithCasts` + `hp` + `add` + `remove`, compared against both the forced full solve and the `commitScope = false` unpruned commit), plus one step this task adds at every view: **`hide(i, true)` then `hide(i, false)`**. A narrowing that dropped `hidden` would be invisible to every other step and lethal here.

- [ ] **Step 8: Prove it bites** — three mutations, each re-running `commit_dirt_classes`: (a) drop the `PURE_ARRANGE_PROPS` test so `commitDirty` is `nodeDirty` → the four walks read 253; (b) add `hidden` to `PURE_ARRANGE_PROPS` → the `hidden`-flip test goes red and the adapter reports the plate still visible; (c) the Step 6 audit mutation above. All three must go red.

- [ ] **Step 9: Gates** — `tools/test.sh <ratcheted>`; `tools/verify.sh affected --jobs 1`; `python3 tools/check_source_size.py` (renderer grew again — if headroom is under 1,000, the standing note's renderer seam is owed BEFORE this commit, not after); `stylua --check src tests tools bench examples`. `tests/nameplates_baseline.spec.luau` gains its T5b row (the four hidden-blind walks → 3) with this commit's sha.

- [ ] **Step 10: RascalRally — `tests/facet_commit_dirt_classes.spec.luau`.** The minimap again (`facet_sponsor_omen.spec.luau:527-577`'s `mapWorld` mount): a dots-only `setDots` writes `offsetX`/`offsetY` memos and nothing else, so it is the game's own pure-arrange step. Assert `textScale`/`padding`/`textVerdicts`/`scrollRegions` at the surface's clean floor (state the measured number), `harvest`/`visible`/`hitRects` unchanged from their T5 numbers, and the adapter dump byte-equal to a `commitScope = false` arm. Then a `hidden` flip on one dot, asserting the adapter saw it. `./run-tests.sh`; if `facet_measure_fanout_contract.spec.luau:605-608`'s `lastCommitVisits == 256` moves, move it WITH the measurement in that file's own table.

- [ ] **Step 11: Fresh-context review** — *"is there any walk marked `false` in `WALK_READS_ARRANGE` that reads state another walk derived from an arrange-class prop?"*, *"what happens on the structural path, where a `structure` entry has no `prop`?"*, *"can `commitDirty` be non-nil while `nodeDirty` is nil, or vice versa?"*, *"does `layout_node.build` still receive the all-classes set?"*

- [ ] **Step 12: ABBA + ledger row** (`T5b class-aware commit dirt`), as T5 Step 10.

- [ ] **Step 13: Commit**

```bash
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet
cat > /tmp/facet-b-t5b.msg <<'MSG'
perf(render): the commit's dirty set stops carrying pure-arrange dirt

`skip` refused any path in `nodeDirty`, and a plate root wrote `offsetX` — so
after the translate prune the six position-independent walks still paid 253
visits each, ~0.27 ms of a ~4.5 ms tick. There are now TWO sets built in the same
loop: the build-side one (all classes, still what `layout_node.build` gets — the
P3 store needs arrange dirt) and a commit-side one that omits the seven pure
placement props (anchor, offsetX, offsetY, alignH, alignV, lineAlign, distribute)
and KEEPS `hidden`. `skip` picks by the walk's own `moveBlind` claim: textScale,
padding, textVerdicts and scrollRegions go 253 -> 3 on a pure tick; harvest,
visible and hitRects keep the all-classes set and are unchanged. The per-walk
prop-read audit is a driver in commit_dirt_classes.spec, not a comment: a walk
that starts reading `hidden` turns it red.
MSG
python3 tools/commit_isolated.py -m /tmp/facet-b-t5b.msg \
  src/render/renderer.luau:"commitDirty","PURE_ARRANGE_PROPS" \
  src/render/commit_walks.luau:"commitDirty" \
  tests/commit_dirt_classes.spec.luau \
  tests/lib/nameplates_scene.luau:"scene.hide" \
  tests/nameplates_baseline.spec.luau:"T5b"

cd ../../../games/RascalRally/code
git add tests/facet_commit_dirt_classes.spec.luau tests/run.luau
git commit -m "test(facet): consumer rider for the class-aware commit dirty set (minimap dots-only move)"
```

---

### Task 6 (T6): N2 + A1 — anchor arrange O(dirty children), and the string allocations

**Files:**
- Modify: `src/render/layout_node.luau:534-616` (the node literal — `local layoutNode: any = {` at `:534`, `id = node.path` at `:537`; the `anchor`/`offsetX`/`offsetY` block is `:558-562`), which gains `wKey`/`hKey`
- Modify: `src/layout/solver.luau:1962-1963` (`ctx.offers` writes, in `measureUncached`), `:2285-2286` (`ctx.offers` reads, in the entry literal), `:1765` (`dropH`) + `:1790` (the `cacheKey` interpolation) + `:1817` (the memo READ) + `:1928` (the `note` gate) + `:1934` (the packed WRITE) + `:1938` (the published WRITE) for arm B, `:3063-3108` (the anchor branch)
- Create: `tests/anchor_arrange.spec.luau`
- Create: `games/RascalRally/code/tests/facet_anchor_arrange.spec.luau`

**Interfaces:**
- Produces: `node.wKey: string` and `node.hKey: string` on every layout node (`node.path .. "|w"` / `"|h"` — inside the literal there is no local `id`, only the field `id = node.path` at `:537`), built once where the node is built and carried across solves by the P3 node store (a reused node table keeps them; a rebuilt node rebuilds them — its path is its mounted path, so the value is a pure function of identity). **Every read is guarded** (`node.wKey or (node.id .. "|w")`) because `layout_node.luau:315-324` returns a warm `hit.built` WITHOUT re-running the literal.
- Produces: in the anchor branch, a non-dirty child whose recorded `prev.offerW`/`prev.offerH` equal this solve's offer takes `w, h` from `previous.rects[child.id].rect` instead of calling `measure`.
- Consumes: `reuse.previous.rects[id].offerW/offerH` (recorded at `solver.luau:2285-2286` and, until now, read by nothing).

- [ ] **Step 1: Write the failing demonstrator — `tests/anchor_arrange.spec.luau`.** The single-update floor is the target: arranging the 250-child anchor to settle ONE child costs 0.31 ms and 125 KB in the arena (profile §3.2), because the loop measures and allocates for all 250.

```luau
--!strict
--[[ N2 — THE SINGLE-UPDATE FLOOR IS THE CONTAINER, NOT THE CHANGE.

	There is no "list" layout node: `ForEach` splices its children into the
	parent (`layout_node.luau:1263-1275`), so the canvas is ONE `anchor` with 250
	direct children and `solver.luau:3063-3108` re-offers and re-places every one
	of them to settle a single dirty child. Per child, unconditionally: one
	`measure()` (a memo HIT still allocates the interpolated `{maxW}|{maxH}|
	{scopeKey}` cacheKey at `:1790`), one rect table, two `dim()` and two
	`offsetPx()` calls. That is the 0.31 ms / 125 KB the arena measures for a
	3-node change — and the same floor sits under every add and every remove.

	WHY A PER-CHILD SKIP IS SOUND HERE AND NOWHERE ELSE: an anchor child's rect
	is a pure function of (innerX, innerY, innerW, innerH, child.anchor,
	child.offsetX/Y, measure(child, innerW, innerH)) — NO SIBLING APPEARS IN IT.
	A stack's does (`solver.luau:3290-3340`: every child feeds `fixedMain` /
	`fillWeightSum` and then the cursor), which is why this task touches the
	anchor branch only. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")
local device_views = require("./lib/device_views")

-- READ OFF THE RUN in Step 2, both of them, and written in as expressions with the
-- node names beside them. They are NOT knowable on paper, and the two ways they
-- were guessed in earlier drafts were both wrong:
--   * `arranged` — the dirty chain is Screen + Canvas + Plate + Hp = 4 only if the
--     Canvas arranges. It is in `dirtyContains` (a prefix of the Hp write), so it
--     does; but whether the PLATE also translates its unchanged Row/Cast or
--     arranges them depends on whether the plate's content height moved when Hp's
--     width changed, which it does not — so 3 (Canvas, Plate, Hp) plus the Screen
--     is the expectation, and the run says whether the Screen arranges under
--     `rootPolicy = "edgeToEdge"`.
--   * `measured` — `Hp` and `Cast` are PLAN_SKIP (`measure_facts.luau:409-412`),
--     counted on EVERY touch by `measureUncached` with no memo, and the plate's
--     arrange touches them separately from its own measure. So `measured` is at
--     least 5 and the exact number is a property of how many times the vstack
--     branch re-enters them, which only the run reports.
-- THE PROTOCOL, as everywhere else in this round: correct the EXPRESSION and this
-- comment, never the assertion.
local ARRANGED_HP = -1
local MEASURED_HP = -1

describe("N2: one changed plate does not re-offer 250 siblings", function()
	it("an hp step arranges and measures the changed plate's chain only", function()
		local s = scene.new()
		s.tick(3, 2)
		s.hp(7, 0.9)
		local st = s.stats()
		-- the dirty chain, and nothing else. What makes this a real assertion is
		-- the number's SIZE, not its exact value: 250 re-offered siblings cannot
		-- fit in it under any reading.
		expect(`arranged={st.lastArranged} measured={st.lastMeasured}`)
			.toBe(`arranged={ARRANGED_HP} measured={MEASURED_HP}`)
		expect(`arrangedUnder10={st.lastArranged < 10} measuredUnder10={st.lastMeasured < 10}`)
			.toBe("arrangedUnder10=true measuredUnder10=true")
		s.dispose()
	end)

	it("...and it does not allocate a kilobyte per sibling", function()
		local s = scene.new()
		s.tick(3, 2)
		s.hp(7, 0.9)
		collectgarbage("collect")
		local k0 = collectgarbage("count") :: number
		for i = 1, 10 do
			s.hp(7, 0.5 + i * 0.01)
		end
		local k1 = collectgarbage("count") :: number
		--[[ 125 KB a step in the arena; the pin is per-step and deliberately
			generous, and a re-offer of 250 siblings cannot fit under it.

			IT PRINTS THE NUMBER, NOT A BOOLEAN. Step 4 has to compare two
			implementations of the memo key on this exact measurement, and
			`kbPerStep<20=true` compares equal to `kbPerStep<20=true` no matter how
			far apart the two arms are. The rounded KB is in the message so the
			run's transcript carries it; the ASSERTION is still the threshold. ]]
		local kbPerStep = (k1 - k0) / 10
		print(`anchor_arrange hp kbPerStep={string.format("%.2f", kbPerStep)}`)
		expect(`kbPerStep<20={tostring(kbPerStep < 20)}`).toBe("kbPerStep<20=true")
		s.dispose()
	end)

	it("...at every device view", function()
		for _, view in device_views.VIEWS do
			local s = scene.new({ viewport = { x = 0, y = 0, w = view.w, h = view.h } })
			s.tick(3, 2)
			s.hp(7, 0.9)
			expect(`{view.id}:{s.stats().lastArranged}`).toBe(`{view.id}:{ARRANGED_HP}`)
			s.dispose()
		end
	end)
end)
```

- [ ] **Step 2: Run to verify it fails, and READ THE TWO PINS OFF THE RUN** — `lune run tests/run_one anchor_arrange`. Expected: `arranged` is already small after T4 (the sibling skip arm takes each unchanged child), but `measured` and the KB are not: the loop still calls `measure` for all 250. Write `ARRANGED_HP` and `MEASURED_HP` in as expressions with the node names beside them, per the header's protocol — `measured` is expected to be at least 5 (the two PLAN_SKIP leaves are touched by both the plate's measure and its arrange), and if it is not, bucket `ctx.measured` by plan verdict and report the mechanism before Step 5. Record the before KB per step from the `kbPerStep=` line; that number is what Step 4 must beat.

- [ ] **Step 3: The two `|w`/`|h` concatenations.** In `layout_node.luau`'s node literal (`:534-616`; the placement block that sets `anchor = props.anchor` / `offsetX = resolveOffset(...)` is `:558-562`), add beside them:

```luau
		-- the two keys `ctx.offers` is indexed by, built once per node instead of
		-- twice per measure AND twice per arrange (`solver.luau:1962-1963`,
		-- `:2285-2286`). `node.path` is the mounted path — the same expression the
		-- `id` field two dozen lines up uses (`:537`) — so this is a pure function
		-- of identity and the P3 store carries it across solves for free.
		wKey = node.path .. "|w",
		hKey = node.path .. "|h",
```
  **`node.path`, not `id`.** `toLayoutNode`'s parameters are `(node, metrics, textScale, prefOffset, parentAxis, insideClipper, store)` (`:252-266`) and there is no local `id` anywhere in the function — `id` is a FIELD of the literal (`id = node.path`, `:537`), not a name in scope. `wKey = id .. "|w"` would be an unknown global under `--!strict` and `nil` at runtime.

  Then `solver.luau:1962-1963` becomes `ctx.offers[node.wKey or (node.id .. "|w")] = maxW` / `ctx.offers[node.hKey or (node.id .. "|h")] = maxH`, and `:2285-2286` reads the same two guarded expressions. Grep for every other `.. "|w"` / `.. "|h"` in `src/` and convert them all — a mixed scheme would silently miss keys.

  **The `or` fallback is not defensive clutter; it is required, and it is CODE rather than a review question.** `layout_node.luau:315-324` returns a warm store hit WITHOUT re-running the literal:

```luau
		if store.reuse then
			local hit = store.byNode[node]
			if hit ~= nil and not store.dirty[node.path] and hit.axis == parentAxis and hit.clip == (insideClipper == true) then
				store.nodes += hit.n
				return hit.built
			end
		end
```
  so a node table built before this commit and still in a live `store.byNode` is served without the two fields, and `ctx.offers[node.wKey] = maxW` with `wKey == nil` raises `table index is nil` — a hard crash inside a protected solve boundary, not a missed optimisation. The store is per-attach and is invalidated only on a `metrics`/`textScale`/`prefOffset` change (`layout_node.luau:1560-1576`), so a Studio module reload that leaves the controller alive is a real path to it. Two guarded reads cost one `or` per node on the uncached path; a proof that the store cannot survive a reload would cost a day and could still be wrong after the next Studio release.

- [ ] **Step 4: The `cacheKey` string — measure, then decide.** `solver.luau:1790` allocates `{maxW}|{maxH}|{scopeKey}` (or `{maxW}|*|{scopeKey}`) per memoised measure. Two arms; the demonstrator decides, and the decision is written into the commit message with its number:
  - **A (keep the string):** leave `:1790` alone. A no-op, and the honest default.
  - **B (three-level numeric table):** `perNode[maxW]` → `[if dropH then DROP_H else maxH]` → `[scopeKey]` → the memoised value. **Four sites read or write that key and B must change all four**, not "the memo key":

    | site | today | under B |
    |---|---|---|
    | `:1817` | `local hit = perNode[cacheKey]` | three nested lookups, `nil` at any level = miss |
    | `:1928` | `if perNode[cacheKey] == nil then … note …` | the same three-level probe |
    | `:1934` | `perNode[cacheKey] = { mw, mh … }` (packed array) | write at the third level, creating levels 1-2 on demand |
    | `:1938` | `perNode[cacheKey] = { w = …, h = … }` (published record) | same, and the `hit` shape stays polymorphic — the reader must still tell a packed array from a published record |

    **The sentinel is selected by `dropH`, not by `maxH`.** `maxH` is always a number; the height-free case is signalled by the separate boolean `local dropH = plan == PLAN_HEIGHT_FREE` at `solver.luau:1765`. `perNode[maxW][maxH or DROP_H]` — the shape an earlier draft of this plan proposed — never selects the sentinel at all and would silently merge every height-free answer with a real height's.

    **And the `KEY_CAP` accounting must keep its meaning.** `KEY_CAP = 12` is `measure_reuse.luau:101`; `store.n[id]` is bumped once per NEW LEAF entry by `measure_reuse.note` (`:209`), reset by `:198`, and tested at `adopt` (`:190`). Under a nested table the INTERIOR tables are unbounded and nothing prunes them, so B must state — and the spec must assert — that `note` is still called exactly once per new *leaf*, i.e. that the cap still counts "distinct memo answers held" and not "distinct `maxW` values", and that the interior tables die with the slate.

  Method: implement A-vs-B behind nothing — measure both by running the KB pin from Step 1 twice, once per arm, on the hp step at L, median of 5, **reading the printed `kbPerStep=` number** (the assertion is a boolean and cannot express a 15 % comparison; that is why Step 1's pin prints the value). Take the cheaper. If B is not at least 15 % better on solve KB, take A and say so: a three-level table is three allocations where the string was one, and the win is not free.

- [ ] **Step 5: The anchor branch's third arm** — `solver.luau:3063-3108`, at the top of the loop body:

```luau
		if node.kind == "anchor" then
			local reuse = ctx.reuse
			local prevOf = if reuse ~= nil then reuse.previous.rects else nil
			for _, child in node.children or {} do
				local w: number, h: number
				--[[ THE THIRD ARM (wicked-fast N2). `prev.offerW/offerH` have been
					RECORDED at every rect write since P2 (`solver.luau:2285-2286`)
					so that a later solve could ask "is this the same question I
					already answered?" — and until now nothing asked. A child with
					no dirt inside it, offered exactly what it was offered last
					time, has the answer already: its own rect's w/h. That is the
					whole of the anchor's per-child cost apart from the placement
					arithmetic, and no sibling is involved (see the header). ]]
				local prev = if prevOf ~= nil and reuse.dirtyContains[child.id] ~= true then prevOf[child.id] else nil
				if prev ~= nil and prev.offerW == innerW and prev.offerH == innerH then
					w, h = prev.rect.w, prev.rect.h
					--[[ ...AND RECORD THE OFFER WE JUST SERVED. `ctx.offers` is written
						in `measureUncached` and NOWHERE else (`solver.luau:1962-1963`),
						and it is fresh per solve — so a child served from here has no
						offer recorded, and the entry write below it (`:2285-2286`) would
						record `offerW = nil`. That is not a correctness bug (a nil offer
						fails this arm's test next solve and falls back to `measure`, the
						conservative direction), but it is a SELF-DISARMING cache: the
						arm would fire at most every other tick. Two writes keep the
						channel honest. It matters most for a TRANSLATE ROOT, whose
						ordinary entry write (T4 Step 3) records this solve's offers. ]]
					ctx.offers[child.wKey or (child.id .. "|w")] = innerW
					ctx.offers[child.hKey or (child.id .. "|h")] = innerH
				else
					w, h = measure(ctx, child, innerW, innerH)
				end
				-- … unchanged: ANCHOR_FACTORS, the fill give-back, offsetPx, arrange …
```
Note the arm reuses the child's PAINTED size only when the offer matches exactly, so a viewport change (which changes `innerW`/`innerH`) falls through to `measure` for every child — which is what makes the 320×640 oracle row meaningful rather than vacuous.

- [ ] **Step 6: Oracle** — the same three-arm block (plain / overflow / fractional, nine views, `tick` + `tickWithCasts` + `hp` + `add` + `remove`). The overflow fixture matters most here: a plate 2,000 px wide changes what the anchor's own hug path would compute, and the arm must not serve a stale size to it.

- [ ] **Step 7: Prove it bites** — force `prev = nil` in the third arm: the KB pin must go red. Then revert `wKey`/`hKey` to the concatenations: the KB pin must move measurably (record how much; if it does not move at all, say so in the commit message rather than claiming a win).

- [ ] **Step 8: Gates + RR.** Gates as T4 Step 9. RR spec `tests/facet_anchor_arrange.spec.luau`: the minimap again (a 6-to-12-dot anchor, not 250 — state that the game's own canvas is small and this is a currency-and-direction check, not a claim that the game got 56 % faster, exactly as `facet_measure_fanout_contract.spec.luau`'s header does for L-37). Assert: moving ONE dot arranges the dot's chain only, and the rect dump matches the full-solve arm. `./run-tests.sh`.

- [ ] **Step 9: Fresh-context review** — *"can `prev.offerW == innerW` be true while the child's own content changed?"* (only if the child is dirty, which the arm tests), *"is EVERY `ctx.offers` index guarded with `node.wKey or (node.id .. \"|w\")`, including any site the grep in Step 3 turned up?"* (the guard is code in Step 3, not a question to be answered here — the reviewer's job is to find the site that was missed, because a warm `store.byNode` hit serves a node table with no `wKey` and an unguarded index raises `table index is nil`), *"does the anchor arm's offer write use the same guarded expression?"*, *"under arm B, is `measure_reuse.note` still called exactly once per new leaf, and does anything now hold an unbounded interior table past the slate's life?"*

- [ ] **Step 10: ABBA + ledger row** (`T6 N2+A1 anchor arrange`), reporting the hp p50 and the tick gcKb (the allocation half is the point).

- [ ] **Step 11: Commit**

```bash
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet
cat > /tmp/facet-b-t6.msg <<'MSG'
perf(layout): anchor arrange is O(dirty children), and two strings a node stop

The anchor branch re-offered and re-measured all 250 children to settle one; a
child with nothing dirty inside it, offered exactly what `prev.offerW/offerH`
recorded, takes w/h from its own previous rect instead — and records the offer it
served, or the arm would disarm itself every other tick. `node.wKey`/`node.hKey`
are built once in `layout_node.build` (from `node.path`; there is no local `id`
in that function) instead of twice per measure and twice per arrange, and every
read is guarded because a warm P3 store serves node tables built before this
commit. hp step at 250 plates: arranged/measured <read off the run>, solve KB
<20 (was 125 in the arena). cacheKey: <A kept / B nested table>, decided by
measurement, see the ledger row.
MSG
python3 tools/commit_isolated.py -m /tmp/facet-b-t6.msg \
  src/render/layout_node.luau:"wKey" \
  src/layout/solver.luau:"wKey","offerW == innerW" \
  tests/anchor_arrange.spec.luau

cd ../../../games/RascalRally/code
git add tests/facet_anchor_arrange.spec.luau tests/run.luau
git commit -m "test(facet): consumer rider for the anchor arrange skip (one dot moves, siblings are not re-offered)"
```

---

### Task 7 (T7): O6 — `structuralSync` incremental, scoped

**This task begins with the condition that may delete it.** The profile puts `structuralSync` at ~0.6 ms of a 1.33 ms nameplates add/remove (four whole-tree walks on a 1,503-node tree) and 0.06–0.12 ms of a 0.40 ms fountain add/remove. T3–T6 change the *other* halves of those steps. **Step 1 re-measures; if `ssTotal` is under 5 % of the add step after T3–T6 land, the task is DROPPED with a ledger line and the plan moves to T8.**

On today's numbers this condition almost certainly does not fire — `ss` is already ~45 % of the add step, and T3–T6 shrink the halves it is measured against, so its SHARE rises. **The step reads as a coin flip and is not one; it is the discipline, run because a rule applied only when it is expected to bite is not a rule.** Budget for the task building.

`ssZOrder` is **not** in scope and cannot be: it is a document-order running counter with a reserved slot per hit-floor class (`renderer.luau:2367-2372`), so inserting one node renumbers everything after it, and NM-H4a forbids making the reservation a function of current state. So the ceiling here is **~0.3 ms of the 0.6** on a nameplates churn step and **~0.05 of the 0.1** on a fountain one — `ssLivePaths` + `ssSweep` + `ssEnsureTree` only. The plan says that up front so the after-doc cannot be surprised by it.

**Files:**
- Modify: `src/render/renderer.luau:2413-2435` (`structuralSync`'s head takes the delta), `:2422-2432` (the six whole-tree `table.clear`s and `pathNodeCount = 0` — the block Step 3 must answer for, per map), `:934-940` (`ensureTree`), `:1402-1441` (`livePaths`), `:2436-2576` (the sweep), `:2350-2382` (`syncZOrder`, called unchanged), `:621` (stats fields)
- Create: `tests/structural_incremental.spec.luau`
- Create: `games/RascalRally/code/tests/facet_structural_incremental.spec.luau`

**Interfaces:**
- Produces: `stats.lastSsVisited` — nodes visited by `ensureTree` + `livePaths` + the sweep in the most recent `structuralSync` pass, reset at the top of that function. (Named `last*`, not `ssVisited`: the whole `ss*` family is cumulative ms and must stay that way; a per-pass count that a single `stats()` snapshot can read is a `last*`, exactly like `lastCommitVisits`.)
- Produces: `structuralSync(dirty: { { path: string, class: string, prop: string? } }?)` — `nil` means "no delta available", which takes today's whole-tree path verbatim (`controller.initialRender()` passes nil).
- Produces: `childPathsOf: { [string]: { [string]: boolean } }` — the per-parent live-path index `livePaths` maintains, which is what lets the sweep enumerate a departed subtree without iterating `handles`.

- [ ] **Step 1: The drop test.** With T3–T6 landed:

```bash
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/FacetBench
lune run tools/profile/attr nameplates L 3
```
Read the `addItem-plates` and `removeItem-plates` buckets' p50 and their `mount (ss)` column. If `ss` is under 5 % of the step, write a ledger line in `docs/profiling/2026-09-02-wicked-ledger.md` — *"T7 O6 DROPPED: ssTotal is X ms of a Y ms add at L after T3-T6, under the 5 % bar (spec Part 2's own rule: a lever the profile says is <5 % is dropped, not built)"* — commit it, and skip to Task 8. Otherwise continue, recording X and Y as this task's before.

- [ ] **Step 2: Write the failing demonstrator — `tests/structural_incremental.spec.luau`**

```luau
--!strict
--[[ O6 — THE STRUCTURAL SYNC IS O(TREE) FOR AN O(1) CHANGE.

	Adding one plate re-walks the whole mounted tree three times and iterates the
	whole handle map once: `ensureTree` (`renderer.luau:934-940`: a hash lookup
	and a recursive call per node, discovering newness one node at a time),
	`livePaths` (`:1402-1441`: six whole-tree maps rebuilt from scratch after the
	`table.clear` block at `:2422-2432`), and the sweep (`:2436-2576`: `for path, handle in handles`,
	testing `alive[path]`). Only `ssZOrder` is inherently whole-tree, and it stays
	that way — NM-H4a (`:2364-2372`) forbids a state-dependent reservation, so a
	document-order counter renumbers everything after an insert BY DESIGN.

	The delta is available and simply is not handed down: `refresh` has the
	`dirty` array with its `structure` entries before it calls `structuralSync`
	(`renderer.luau:2793`). ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")

local PLATES = scene.PLATES
local MOUNTED = PLATES * scene.NODES_PER_PLATE + 2 + 1 -- 1503 (no per-item wrapper)

describe("O6: a structural sync visits the delta", function()
	it("adding one plate does not walk 1,753 nodes three times", function()
		local s = scene.new()
		s.tick(3, 2)
		s.add(1)
		local visited = s.stats().lastSsVisited
		-- the added subtree (6 nodes + its wrapper) and its ancestor chain, times
		-- the three phases — an order of magnitude under the whole tree
		expect(`ssVisited<{MOUNTED // 4}={tostring(visited < MOUNTED // 4)}`)
			.toBe(`ssVisited<{MOUNTED // 4}=true`)
		s.dispose()
	end)

	it("removing one plate is the same", function()
		local s = scene.new()
		s.tick(3, 2)
		s.remove(3)
		expect(s.stats().lastSsVisited < MOUNTED // 4).toBe(true)
		s.dispose()
	end)

	it("ORACLE: 30 random adds and removes leave the tree a from-scratch sync would build", function()
		local a = scene.new()
		local b = scene.new()
		local seed = 20260902
		local function rnd(n: number): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return (seed % n) + 1
		end
		for step = 1, 30 do
			local i = rnd(20)
			if step % 3 == 0 then
				a.remove(i)
				b.remove(i)
			else
				a.add(i)
				b.add(i)
			end
			-- b is forced through the whole-tree path by a full structural sync
			b.controller.initialRender()
			if a.snapshot() ~= b.snapshot() then
				error(`structural step {step} diverged from a from-scratch sync`, 0)
			end
		end
		a.dispose()
		b.dispose()
	end)
end)
```

- [ ] **Step 3: Implement.** Thread the delta: `renderer.luau:2793` becomes `profile.span("mount", function() structuralSync(dirty) end)`, and `structuralSync(delta)` computes its roots once:

```luau
	local function structuralSync(delta: { any }?)
		structureEpoch += 1
		stats.lastSsVisited = 0
		--[[ THE ROOTS OF THIS SYNC (wicked-fast O6). A `structure` entry names the
			mounted path whose CHILDREN moved; everything outside those subtrees is
			unchanged by construction, and the six maps `livePaths` builds are all
			inherited-from-the-parent facts (`scrollHostOf`, `clipHostOf`,
			`parentNodeOf`, `pathNodes`, `inputSinks`, `alive`) so a subtree can be
			re-derived from its parent's recorded values alone. A `nil` delta — the
			initial render, or any pass we cannot prove is bounded — takes the whole
			tree exactly as before. ]]
		local roots = structuralRootsOf(delta)
```
`ensureTree` and `livePaths` gain a starting node + inherited `(host, clip)` read from `scrollHostOf[parentPath]` / `clipHostOf[parentPath]`, and both `+= 1` into `stats.lastSsVisited` per visited node. `livePaths` additionally maintains `childPathsOf[parentPath]`, and — before re-deriving a root's subtree — snapshots the OLD membership from `childPathsOf` into a `departedCandidates` list. The sweep then iterates that list instead of `handles`, testing `alive[path]` exactly as today, with the identical per-path teardown body (park/remove + the ~20 record clears + `measure_reuse.forget` + `lastResult.rects[path] = nil`). `syncZOrder()` is called unchanged, whole tree, and the header comment says why.

  **THE SIX WHOLE-TREE CLEARS ARE THE HARD PART, AND EACH ONE IS DECIDED BY NAME.** `structuralSync` today does, at `renderer.luau:2422-2432`:

```luau
		local alive: { [string]: boolean } = {}
		table.clear(scrollHostOf); table.clear(clipHostOf); table.clear(pathNodes)
		table.clear(parentNodeOf); table.clear(inputSinks); pathNodeCount = 0
```
  A `livePaths` bounded to the delta with those clears still in place erases every UNVISITED node's entry — and one of them is worse than an erasure. This step is not done until each of the six has an answer in the code:

| state | today | bounded |
|---|---|---|
| `scrollHostOf` | whole-tree clear, refilled by `livePaths` | **per-subtree clear-then-refill.** Snapshot the root's old membership from `childPathsOf[root]` FIRST, clear only those paths, then refill from the walk. It is an inherited-from-the-parent fact, so the subtree's seed is `scrollHostOf[parentPath]`. |
| `clipHostOf` | same | **same**, seeded from `clipHostOf[parentPath]`. |
| `parentNodeOf` | same | **same.** A path is REUSED across a remount, so a stale link must be cleared for the departed set specifically — not left, and not cleared globally. |
| `inputSinks` | same | **same**; membership is per-node, so the departed snapshot is exactly what to remove. |
| `pathNodes` | same | **per-subtree, AND IT IS THE DANGEROUS ONE.** `commit_walks.luau:842` reads `local prunable = next(pathNodes) == nil`, so a `pathNodes` that is empty at the moment the commit runs **OPENS** `visible`'s whole-surface prune on a surface that has a stroked `UI.Path` — the exact opposite of the latch T5 promises to preserve, and silent. Clear only the departed subtree's paths and refill from the walk; never `table.clear`. |
| `pathNodeCount` | `= 0`, then re-incremented | **decremented per departed Path**, never zeroed. It is the count behind `pathNodes` and the same argument applies. |
| `alive` | the sweep's only liveness oracle, built over the whole tree | **scoped to `departedCandidates`.** Bounded, it stops answering for the untouched tree, so the sweep must not ask it about anything outside that set — which is exactly what iterating `departedCandidates` instead of `handles` achieves. Keep it a fresh local per sync. |

  On the `roots = nil` fallback path every one of these reverts to the verbatim whole-tree behaviour above, unchanged — that is what makes the fallback a correctness story rather than a second implementation.

Anything that cannot be bounded — a delta entry whose path has no live parent, a root whose parent is itself being replaced, a `stampMoved` restamp — sets `roots = nil` and takes the whole-tree path. **The fallback is the correctness story: it must be cheap to reach and impossible to reach silently** (bump a `stats.ssFullPasses` counter and pin it in the spec, so a fixture that always falls back cannot pass the visit assertions).

- [ ] **Step 4: Prove it bites — five arms, and the fifth is the one no existing oracle can see.**
  1. Force `roots = nil` unconditionally: the two visit assertions go red, the oracle stays green (that is the point of a fallback).
  2. Break the sweep's `departedCandidates` enumeration to only look at direct children: the 30-step oracle must go red on a nested removal.
  3. Restore the whole-tree `table.clear(scrollHostOf)`: a fixture with a ScrollView above the churn must go red on its scroll-region facts.
  4. Zero `pathNodeCount` instead of decrementing it: the `withPath` fixture's count assertion goes red.
  5. **The `pathNodes` arm.** Restore `table.clear(pathNodes)` and add this test, which is the only thing in the round that can see it:

```luau
	it("a UI.Path SURVIVES a structural churn (the visible latch stays closed)", function()
		--[[ `commit_walks.luau:842` reads `local prunable = next(pathNodes) == nil`.
			A partially rebuilt `pathNodes` breaks no rect and no visibility VALUE —
			it OPENS the whole-surface prune on a surface that has a stroked path,
			which is invisible to every rect oracle and to every visit count except
			this one. It is the exact opposite of the latch T5 preserves.

			ASSERTED THROUGH THE OBSERVABLE, never through a `pathNodes` accessor:
			with the latch closed, `visible` cannot prune, so its visit count stays
			ABOVE the dirty closure across an add and across a remove. Adding a
			getter for a private renderer table to test this would make the test
			pass and the surface worse. ]]
		local s = scene.new({ withPath = true })
		s.tick(3, 2)
		s.add(1)
		local addVisible = s.stats().lastCommitVisitsByWalk.visible
		s.remove(2)
		local removeVisible = s.stats().lastCommitVisitsByWalk.visible
		local floor = 3 + PLATES -- the dirty closure a PRUNING `visible` would stop at
		expect(`add={addVisible > floor} remove={removeVisible > floor}`).toBe("add=true remove=true")
		s.dispose()
	end)
```

- [ ] **Step 5: Gates + RR.** Gates as T4 Step 9. **`renderer.luau` is the file with the least headroom of the three, and the standing note's rule applies BEFORE this task's code, not after it:** run `python3 tools/check_source_size.py` at the end of T6 and, if the renderer row is under 1,000 characters of headroom, take the seam its ledger row names (`tools/lune/verify/data/source-cap-ledger.md:59` — the text-measurement round: `textInFlight`, `textMeasureCancels`, the collect/deliver/`learned` block inside `solveAndApply`, ~4 KB, costing one record) as this task's FIRST, SEPARATE commit. T7 adds 2,500–4,000 characters to that file; discovering the cap halfway through it is how a round loses a day. RR spec `tests/facet_structural_incremental.spec.luau`: the racer list is the game's real structural churn (`FacetRacerListScreen` + `SponsorListModel.rows`, mounted exactly as `facet_measure_fanout_contract.spec.luau:96-108` does). Add and remove a racer, assert `lastSsVisited` is bounded and the adapter dump matches a from-scratch render. `./run-tests.sh`.

- [ ] **Step 6: Fresh-context review** — *"which of the six maps is NOT a pure function of the parent's value plus the node?"*, *"can a parked handle's path be missed by the bounded sweep?"*, *"what happens when two structural roots are ancestor and descendant of each other?"*, *"is any `table.clear` at `:2422-2432` still unconditional on the bounded path, and does `pathNodeCount` still equal the size of `pathNodes` afterwards?"*, *"is `alive` ever asked about a path outside `departedCandidates`?"*

- [ ] **Step 7: ABBA + ledger row** (`T7 O6 structural sync`) — report the add/remove p50 for nameplates AND fountain.

- [ ] **Step 8: Commit**

```bash
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet
cat > /tmp/facet-b-t7.msg <<'MSG'
perf(render): structuralSync takes the delta (ensureTree, livePaths, sweep)

Three of the five phases are re-derivations of inherited facts and are now
bounded by the structure delta `refresh` already holds; the sweep enumerates a
departed subtree from the per-parent index instead of iterating every handle.
The six whole-tree `table.clear`s go per-subtree with the old membership
snapshotted from `childPathsOf` first, `pathNodeCount` is decremented rather than
zeroed, and `alive` is scoped to the departed candidates. `pathNodes` is the one
that mattered: an emptied `pathNodes` OPENS `visible`'s whole-surface prune on a
surface with a stroked UI.Path, which no rect oracle can see — there is a
mutation arm for exactly that.
`ssZOrder` stays a full renumber and always will — NM-H4a forbids a
state-dependent reservation in a document-order counter — so the ceiling here
was ~0.3 ms of the 0.6, and that is what it claims. New `stats.lastSsVisited`;
an unbounded delta falls back to the whole-tree path and says so via
`ssFullPasses`.
MSG
python3 tools/commit_isolated.py -m /tmp/facet-b-t7.msg \
  src/render/renderer.luau:"lastSsVisited","structuralRootsOf","childPathsOf" \
  tests/structural_incremental.spec.luau

cd ../../../games/RascalRally/code
git add tests/facet_structural_incremental.spec.luau tests/run.luau
git commit -m "test(facet): consumer rider for the incremental structural sync (racer list add/remove)"
```

---

### Task 8 (T8): W1 — `propSigCache` lets a recycled instance keep an undeclared style prop

Correctness only. **No perf claim in this task's commit message or in the after-doc.**

**Files:**
- Modify: `src/render/renderer.luau:866-905` — the safety-argument comment is `:866-884` and the cache itself `:885-905` (`propSignature` / `propSigCache`)
- Create: `tests/recycle_prop_signature.spec.luau`
- Create: `games/RascalRally/code/tests/facet_recycle_props.spec.luau`

**Interfaces:**
- Consumes: `recycleKey(class, hint, createKind, propSig)` (`renderer.luau:911-913`), `recycleKeyOf[path]` (`:1042-1043`), `captureParkedProps`/`restoreParkedProps` (`:1485-1507`).
- Produces: `propSignature(node)` returns the sorted, comma-joined key set of `node.props` **computed at every call**; `propSigCache` is deleted.

- [ ] **Step 1: Write the red spec — `tests/recycle_prop_signature.spec.luau`**, the `tests/instance_recycling.spec.luau:77-140` shape:

```luau
--!strict
--[[ W1 — A RECYCLED INSTANCE KEEPS A STYLE PROP IT NEVER DECLARED.

	`propSigCache` (`renderer.luau:885-905`) is keyed on the props TABLE identity
	and is never invalidated, while `mount.luau:637` mutates that same table in
	place on every reactive write. A reactive prop whose value crosses nil
	therefore ADDS or REMOVES a key after the signature was cached:

	  reactive `shadow` starts nil -> no `shadow` key -> sig "…,color", cached,
	  and `recycleKeyOf[path]` frozen from it (`:1042-1043`);
	  the signal fires a shadow table -> the key appears -> `applyStyleProp`
	  materialises a real `UIShadow` (`screen_paint.luau:554-573`);
	  at park the handle goes into the bucket for the STALE "…,color" key;
	  a fresh node declaring only `color` adopts it, adoption writes only the
	  properties that DIFFER (`:1377-1391` — an ABSENT prop raises no write at
	  all), and the `UIShadow` survives onto a node that never asked for one.

	The whole safety argument for carrying property caches across an adoption is
	that "every property on the instance is one the new node also declares"
	(`renderer.luau:866-884`), and a stale signature is exactly the case where
	that is false. ]]
```
The spec builds the `ragged` virtual-list world with `shadow` supplied as a `core:signal(nil)` on the odd rows, flips the signal to a real shadow table, `pres.refresh()`, scrolls far enough to park those rows, scrolls back so a row that never declared a shadow adopts the pooled instance, and asserts `adapter.liveNodes()[path].props.shadow == nil`. Second case, the nil-crossing in the other direction: a node that declares `shadow` reactively and currently resolves it to nil must not adopt an instance carrying a live shadow.

- [ ] **Step 2: Run to verify it fails** — `lune run tests/run_one recycle_prop_signature`. Expected: the adopted row reports a `shadow` prop. Record the exact failure text in the task report; it is the reconstruction of the RED-TEAM report that is not on disk.

- [ ] **Step 3: Implement — delete the cache.**

```luau
	--[[ NO CACHE (wicked-fast W1). It was keyed on the props TABLE and
		`mount.luau:637` mutates that table in place, so a reactive prop crossing
		nil changed the key SET behind the cached answer and a pooled instance kept
		a style prop its adopter never declared. The cache was also a strong,
		never-cleared table holding one entry per mounted node's props for the life
		of the controller.

		It is not replaced by a cleverer key. `propSignature` is asked exactly
		twice per node CREATE (`renderer.luau:998` and `:1042`) and never per
		frame, so the sort it does is a create-path cost, not a commit-path one.

		The alternative considered and rejected: sign the DECLARED set
		(`keys(node.props) ∪ keys(node.dynamicProps)`), which is stable across a
		nil crossing. It is correct only with an explicit "declared but currently
		nil => tear the modifier down" write, and no such write exists —
		`applyShadow` (`screen_paint.luau:554-573`) has no nil branch at all and
		would index nil if it were called with one. That fix is a bigger, separate
		change to four style-prop appliers; this one is the seam that removes the
		defect. ]]
	local function propSignature(node: any): string
		local props = node.props
		if props == nil then
			return ""
		end
		local names = {}
		for name in props do
			table.insert(names, name)
		end
		table.sort(names)
		return table.concat(names, ",")
	end
```

- [ ] **Step 4: Prove it bites** — restore the cache: the spec goes red again. Restore the fix.

- [ ] **Step 5: Gates** — as T4 Step 9, plus `lune run tests/run_one instance_recycling`, `instance_recycling_themed`, `instance_park_corpse` (the three siblings that own this behaviour).

- [ ] **Step 6: RascalRally — `tests/facet_recycle_props.spec.luau`.** The game's recycled surface is the sponsor racer list (`FacetRacerListScreen` over `SponsorListModel.rows`), whose rows carry conditional decoration. Mount it, drive the roster through enough churn to park and adopt rows, and assert no row's instance carries a style prop its blueprint did not declare — enumerate the adapter's props per row against the blueprint's declared set. `./run-tests.sh`.

- [ ] **Step 7: Fresh-context review** — *"is `propSignature` on any per-frame path?"* (prove it with a call-count instrument, not by reading), *"does dropping the cache change any recycle key for a node whose props never cross nil?"* (it must not — same input, same sorted output).

- [ ] **Step 8: Commit**

```bash
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet
cat > /tmp/facet-b-t8.msg <<'MSG'
fix(render): a recycled instance can no longer keep an undeclared style prop

`propSigCache` was keyed on the props table identity while `mount.luau:637`
mutates that table in place, so a reactive prop crossing nil changed the key set
behind the cached signature: the handle parked into a stale bucket and a node
that never declared `shadow` adopted an instance carrying a UIShadow. The cache
is deleted — `propSignature` is asked twice per node create and never per frame
— which also removes a strong, never-cleared table that held one entry per
mounted node for the life of the controller. Red-then-green spec included.
MSG
python3 tools/commit_isolated.py -m /tmp/facet-b-t8.msg \
  src/render/renderer.luau:"propSignature" \
  tests/recycle_prop_signature.spec.luau

cd ../../../games/RascalRally/code
git add tests/facet_recycle_props.spec.luau tests/run.luau
git commit -m "test(facet): consumer rider for the recycle property-signature fix (racer list churn)"
```

---

### Task 9 (T9): closing — the matrices, the honest after-doc, RED-TEAM, the canary

**Files:**
- Create (FacetBench): `docs/studio-runs/2026-09-02-wicked-fast.md`, `results/lune-<date>-<facet sha>-wicked-after.json`, `results/studio-<date>-<facet sha>-wicked-after.json`
- Modify (FacetBench): `results/chart.html` (regenerated), `README.md` (numbers section), `docs/profiling/2026-09-02-wicked-ledger.md` (the final row)
- Modify (Facet): `docs/superpowers/plans/2026-08-31-facetbench-plan2-3-notes.md` (charter notes); the studio-root `tasks/lessons.md` (outside the Facet repo, only if a correction occurred)

**Interfaces:**
- Consumes: `docs/profiling/2026-09-02-wicked-ledger.md` (one row per landed task, from T2–T8, including T5b's row or its DROPPED line); `results/lune-2026-09-02-2d9f90cf-wicked-before.json` and `results/studio-2026-09-02-8827a87-wicked-before.json` (Plan A Tasks 11-12, on FacetBench `main`) as the ABBA A-arms; `stats()`'s full counter set incl. `lastTranslated`, `lastSolveSkipped`, `lastLayoutNodes`, `lastSsVisited`, `lastCommitVisitsByWalk`; `tools/profile/attr`'s per-step buckets.
- Produces: `results/lune-<date>-<sha>-wicked-after.json` and `results/studio-<date>-<sha>-wicked-after.json` (schema- and drift-valid per `lune run tools/check_schema` / `check_baselines`); `results/chart.html`; `docs/studio-runs/2026-09-02-wicked-fast.md` — per-class numbers for BOTH tick kinds against the ≤0.5 ms update / ≤1 ms structural targets, the miss with its bottleneck, and the host-per-plate next lever stated with counts and not built; the charter notes' carry list.

- [ ] **Step 1: The final Lune matrix** (foreground; check `uptime` first, pause CrashPlan if running):

```bash
cd /Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/FacetBench
lune run runner/lune/run_matrix --frameworks facet,_fixture --workloads nameplates,damage_fountain \
  --sizes S,M,L --samples 750 --warmup 50 --retry-drift 2 \
  --out results/lune-$(date +%F)-$(git -C ../Facet rev-parse --short HEAD)-wicked-after.json
lune run tools/check_schema results/lune-*-wicked-after.json && lune run tools/check_baselines
```
Expected: 12 rows `ok`, drift ≤ 10 %, `_fixture` 1.00× against the before envelope (if `_fixture` moved, the lab moved and no facet row is comparable — re-run).

- [ ] **Step 2: The Studio matrix** (orchestrator-driven, needs the MCP bridge). Follow `runner/studio/DRIVING.md` exactly: stamp `FACETBENCH_MARKER`, `rojo build` → `artifacts/studio-place.rbxl`, open, Play, `FacetBenchRun:FireAllClients(json)` for `--workloads nameplates,damage_fountain --sizes S,M,L`, loop + frames, all six frameworks; scrape `LogService:GetLogHistory()` → `lune run tools/studio_scrape` → the after envelope. **Probe the commit marker before trusting any reading** (`docs/plans/2026-09-02-facet-wicked-fast-reference.md:39`).

- [ ] **Step 3: Regenerate the chart + README** — `lune run tools/chart`; README's "Numbers" gains a *Wicked-fast campaign — after (Facet `<sha>`)* block beside the before block.

- [ ] **Step 4: Write the after-doc** — `FacetBench/docs/studio-runs/2026-09-02-wicked-fast.md`. It must contain, and must not soften:
  - Per-class numbers at L against the targets (**≤0.5 ms update / ≤1 ms structural**), for BOTH `tick` (pure) and `tickWithCasts` (the arena's real mix — the caster tick is the headline, not the pure one).
  - **THE HEADLINE COMES FROM `attr` ON THE ARENA, NOT FROM THIS ROUND'S SPEC PINS, and the after-doc says so in its own words rather than assuming the reader remembers.** The fixture is deliberately not the workload: the arena's canvas takes fixed px `width`/`height` when the scene declares them (`FacetBench/frameworks/facet/adapter.luau:78-86`), which makes it `PLAN_SKIP`, and `tests/lib/nameplates_scene.luau` uses `fill()` precisely to avoid that. That is a defensible fixture choice — a fixed × fixed canvas would have made T3's and T6's demonstrators measure the fixture — but it means the fixture's counts are not the arena's, and a number quoted from a spec pin as if it were a workload number is the kind of claim this round exists not to make. T2's baseline header states this once; the after-doc restates it beside the headline.
  - The stage table rebuilt from `attr` after the round, beside the before table from profile §1, with every counter: arranged / translated / measured / rectInserts / rectWrites / per-walk visits / gcKb.
  - **The miss, stated plainly with its bottleneck.** The projection was ≈ 4.5 ms headless and the target was 0.5. What is left after this round: the react layer (0.52 ms, 537 signal writes at ~1 µs — the model, a non-goal), the build (0.40), the two must-visit walks (0.33), the ~1,500 real rect writes (~1.0), the ~42 casters' measure + arrange (~0.5), the residual. Name the react layer's 1 µs per write as the number that decides whether the campaign can get closer, and vide's whole tick (0.29 ms live) as the yardstick.
  - **The next lever, with counts and no build:** one Frame per plate (`instance_boundary.createOptsFor` is the single predicate) makes 250 engine writes carry 1,488 descendants instead of 1,488 writes carrying themselves. State it as **the user's decision**, with the measured counts and the risk (`screen_target.setRect` is the only writer of `handle.windowRect`, and `applyRect` recomputes `px = rect.x - ox` from it, so a host-relative tree changes what "skip a write" means — solver-seams §7). Do not build it.
  - O1's re-evaluation: how much measure remains on ancestors after T3 (if > 0.4 ms, say so and book it; if not, record O1 as closed).
- [ ] **Step 5: RED-TEAM** — dispatch the code-reviewer agent (fresh context) over the WHOLE Facet diff `2d9f90cf..HEAD`: the translate arm's soundness, the `moveOnly`/`prev` identity protocol, the chain break, the commit prune's new second question, the structural fallback, the recycle-key change. Every HIGH and MEDIUM finding is fixed (or refused in writing with a reason) before Step 6.

- [ ] **Step 6: RascalRally milestone Studio canary** (live MCP, per commit-seams §5.4): boot RR per its dev workflow (rojo double-sync trap, publish-before-TestTrack), **probe a commit marker before trusting any reading**, drive a sponsor-mode session (`SponsorCmd:FireServer("role", "sponsor")`, then the results payload from the Server VM per `HANDOFF_2026-08-04_black_screen.md:108-130`), and confirm: UI correct in `screen_capture`, **60 fps sustained**, `clock:lastError() == nil`, partials firing at pinned counts. The minimap is the surface to watch — it is the one this round changed most.

- [ ] **Step 7: Full gates, both repos** — Facet `tools/test.sh <the ratcheted count>`, `tools/verify.sh affected --jobs 1`, `python3 tools/check_source_size.py`, `stylua --check src tests tools bench examples`; FacetBench `tools/check.sh`; RR `./run-tests.sh`.

- [ ] **Step 8: Charter notes + memory** — update `Facet/docs/superpowers/plans/2026-08-31-facetbench-plan2-3-notes.md` with the round's outcome and its carry list. Append to the studio-root `tasks/lessons.md` (`/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/tasks/lessons.md` — it is OUTSIDE the Facet repo, so it is edited in place and never staged by `commit_isolated.py`) ONLY if a correction occurred during the round: write the rule that prevents the repeat, not a diary entry.

- [ ] **Step 9: Commit** — FacetBench: `git add results/ docs/ README.md && git commit -m "results: wicked-fast after — Lune + Studio matrices, per-class numbers, the stated miss"`. Facet: `python3 tools/commit_isolated.py -m /tmp/facet-b-t9.msg docs/superpowers/plans/2026-08-31-facetbench-plan2-3-notes.md`.

---

## Self-review

*Re-run after the adversarial-review amendment pass (9 blocking + 15 non-blocking findings, the line-ref table, and the controller's rulings). Task 5b is new; T6–T9 keep their numbers.*

- **Spec coverage.** Part 2 O2 → T3; O3 → T4; O4 + O5 → T5 (O5 folded, per the profile's rank 8); O6 → T7 (scoped, with its own drop condition); W1 → T8; O1 → dropped in the header with the 0.004 ms measurement and re-evaluated in T9 Step 4. The profile's two levers the spec did not have: N1 → T5 (the rect-pass run), N2 → T6. **New since the review: T5b** — the class-aware commit dirty set, which the plan's own 5 % rule demanded (the six pruned walks are ≈ 0.27 ms of a projected 4.5 ms tick, 6.1 %) and which an earlier draft booked as a T9 ledger line. Per-fix discipline (spec lines 190-200): extraction first → T1; red-first counters → every task's Step 1; differential oracle across the device matrix → T3/T4/T5/T5b/T6 Step "oracle"; prop-dirt audit extended when a class boundary moves → T3 Step 5 (measure-side) and T5b Step 6 (commit-side), with T4 Step 7 stating why nothing moves there; gates → every task; RR lockstep → every task; fresh-context review → every task; ABBA re-measure → every task's ledger step. Risks (lines 208-218): O2/O3 correctness → the overflow-sized anchor and the fractional-offset fixtures, at 320×640, in every oracle; O1 memo identity → moot (dropped); source cap → T1 for the solver plus a NAMED renderer seam owed at T7 (standing notes); measurement → `_fixture` 1.00× in T9 Step 1. Success criteria (lines 226-235) → T9.
- **Mixed dirt.** Present in the header as its own section and carried into T2 (`tickWithCasts` in the fixture), T3 (the caster pin, read off the run), T4 (302/1,200 vs 402/1,100, with the run deciding), T5 (303), T5b (the measure-class arm that proves the narrowing is not a hole), T9 (both steps reported, the caster tick as the headline). Every oracle drives both steps.
- **Constants, re-derived from `mount.luau` rather than assumed.** `UI.ForEach` mounts ONE region node (`:273-281`) whose children are the row roots directly (`:357` uses `rowPath` as a PARENT path; `:595-596` mounts the row's own root under it), so there is no per-item wrapper; and the fixture now has a `UI.Screen` root because `mountLib.mount` mounts whatever blueprint it is handed (`:713-714`). LAYOUT 1,502 / MOUNTED 1,503 / visited dirty closure 253 (pure) and 303 (casters) / ARRANGED_TICK 252 / TRANSLATED_TICK 1,250 / rectWrites 1,500. The 503 an earlier draft used counted PATH STRINGS, 250 of which have no mounted node behind them and can therefore never become commit visits — that distinction is now stated in the Global Constraints, in T2's fixture header, and in T5's pin table.
- **Type consistency.** `translatedRoots[id] = { dx, dy, from, to }` with parallel `translatedPaths` / `translatedEntries` — produced in T4, consumed only in T5, same field names in both. `entry.moveOnly: boolean` + `entry.prev: <entry>` — written in T4 on the translate root AND on every translated descendant, read only by `skip` in T5/T5b. `skip(node, moveBlind?)` — one signature; at T5 six walks pass `true`, at T5b `harvest` and `visible` give it back and four keep it, `hitRects` and `rect_pass` never had it. `commitDirty` — produced in T5b's renderer, consumed only by `skip`; `nodeDirty` keeps every existing consumer including `layout_node.build` (`renderer.luau:1911`). `stats.lastCommitVisitsByWalk` keys — the same eight strings in T2's counter, T2's baseline spec, T5's and T5b's demonstrators, and T2's `attr.luau` block. `stats.lastTranslated` / `lastSolveSkipped` / `lastLayoutNodes` / `lastSsVisited` — declared where they are produced, read only in their own demonstrators and `attr.luau`'s `statFields`. **No type edit is claimed where no type exists:** `Ctx.reuse` is `reuse: any` (`solver.luau:525`), so T3 adds `measureContains` to a table, not to a record, and says so.
- **Placeholder scan.** No "TBD", no "add tests", no "similar to Task N", no step without code. Three decisions are deliberately left to a measurement, and each carries both arms in full plus the rule that picks: T6 Step 4 (`cacheKey` string vs three-level table — decided by the PRINTED solve KB on the hp step, 15 % bar, with all four read/write sites enumerated and the `dropH` sentinel corrected), T7 Step 1 (build or drop — the 5 % bar, with the ledger line to write either way, and an explicit note that it almost certainly builds), and T5b Step 1 (the same shape). **Five numbers are read off a run rather than guessed**, each with the correction protocol *update the EXPRESSION, never the assertion*: T2's `MEASURED_TICK`, T3's `MEASURED_WITH_CASTS`, T4's caster arranged/translated split, and T6's `ARRANGED_HP`/`MEASURED_HP`. Each says in its own header WHY it is not knowable on paper.
- **Every red demonstrator asserts a counter, a rect, or a `collectgarbage("count")` delta.** No wall-time assertion anywhere. One tautology (`expect(label).toBe(label)`) has been deleted from T3's oracle with a comment naming the class so it is not reintroduced. One pin that could not happen (`harvest == DIRTY_TICK + 1` for a Path leaf that `skip` prunes) has been corrected to `DIRTY_TICK`, with the mechanism written beside it. One invariant that read a stale-by-design field (`stats.lastSkipped`, written only when `skipped > 0` at `renderer.luau:1972-1975`) now reads the unconditional `lastSolveSkipped`, and the plan states which half of that assertion is a tautology and which is the real pin.
- **Moving pins are scheduled, not discovered.** `tests/nameplates_baseline.spec.luau` carries a table of which task moves which pin and to what (T3 `lastMeasured` → `PLATES * 2` / the caster number; T4 the same pin → 0 and `lastArranged` → 252/302-or-402 and `lastRectInserts` → 1,502; T5 the eight walk counts → 253/303 with `hitRects` at 1,503; T5b the four hidden-blind walks → 3); T3 Step 6, T4 Step 4, T5 Step 7 and T5b Step 9 each update their own row in their own commit. `tests/rect_cow.spec.luau`'s two invariant pins are widened in T4 Step 4. RR's `facet_measure_fanout_contract.spec.luau:605-608` is named in the standing notes with the same rule. A pin that moves off-schedule is a finding, not a chore.
- **Corrections carried from the review's own verification, so the plan does not re-make them.** The Deps bind is `solver.luau:578-595` (top of file) with BOTH fields as call-time forwarders, and `chosenCandidate` has TWO call sites (`:1432`, `:2638`). The translate root takes the ordinary entry write — an early return left `out[node.id]` stale, and every counter pin still passed. `wKey`/`hKey` read `node.path` (there is no local `id` in `toLayoutNode`) and every `ctx.offers` index is guarded, because `layout_node.luau:315-324` serves warm store hits without re-running the literal. The eight arrange-only props are the schema's real eight, mounted under the parent kind `placement_audit.luau:89-117` says reads them. The four line refs a code step actually edits are corrected: `renderer.luau:2103` (`rectPass.apply`), `renderer.luau:1969-1971` (`work.skipped`), `solver.luau:1790` (`cacheKey`), `measure_reuse.luau:101`/`:190`/`:198`/`:209` (`KEY_CAP` and the key accounting). FacetBench is `main` at `f1e8ba4`; RR has 55 `facet_*.spec.luau` contracts; `adapter.getInstance` is `FacetSettingsGui.luau:103-104`; T1 frees 7,708 characters, not ~4,000.
- **Known open seams** (the implementer opens these ranges; the excerpts stopped short): `solver.luau:1817`/`:1928`/`:1934`/`:1938` — the memo read/write sites T6 arm B must convert together, and the polymorphic `hit` shape (packed array vs published record) they share; `renderer.luau`'s `structuralRootsOf` insertion point and the per-map clear-then-refill in `structuralSync` for T7; `commit_walks.luau:405-1195` — the walk bodies T5b's `WALK_READS_ARRANGE` table is derived from, which must be re-read at implementation time rather than trusted from this plan. Each is named in its task's Files block.
