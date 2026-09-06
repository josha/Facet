# Facet Parity — Plan C: per-host rect space, the translate lane, and the update-class walks — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a nameplate move cost one rect write and one engine write per plate instead of six, make an all-placement tick solve nothing, and make a 1-leaf update on a big HUD cost O(dirty × depth) instead of O(nodes) — with `rectOf`/`screenRectOf`/hit/focus/engine `Position` byte-identical to today on every path, both adapters, the whole device matrix.

**Architecture:** (1) A container whose `offsetX`/`offsetY`/`anchor` is REACTIVE and that has children becomes an instance host that is also a **coordinate space** (`createOpts.hostSpace`): the solver arranges its subtree from (0,0), every rect beneath it is stored host-relative, and the two public readers compose the host chain on read exactly the way `screenRectOf` already composes `scrollShift`. (2) A **translate lane** in `controller.refresh` consumes every layout-class dirty entry that is a placement prop on such a host — it re-places the host with the SAME pure function the solver uses, writes the solver's own entry in place, and calls `adapter.setRect` once — and hands only the remainder to the solve; an all-placement tick therefore has `stats.solves = 0`. (3) Then the walks the profile ranks: a node-resident last-measure serve inside `measure` (C2), stack pass-1 serving + anchor clean-child skip (C3), a per-node dirty-child index for the commit walks (C4), and a bounded z walk (C5) — each built only if C0's spans put it at ≥5 % of the class it targets.

**Tech Stack:** Luau under Lune 0.10.4 (`lune run …`), stylua, `tools/test.sh`, `tools/verify.sh affected --jobs 1`, `python3 tools/check_source_size.py`, `python3 tools/commit_isolated.py`; the fake adapter `tests/lib/fake_target.luau` is the headless render target; FacetBench (`../FacetBench`, branch `main` at `1ead3b3`) is the arena; RascalRally (`../../../games/RascalRally/code`, `main` at `07d1a18`) is the production consumer (its own git repo).

**Spec:** `docs/superpowers/specs/2026-09-03-facet-parity-design.md` (the authority). Task plan it argues from: `docs/plans/2026-09-03-facet-parity-plan.md`. Method + traps, still binding: `docs/plans/2026-09-02-facet-wicked-fast-reference.md`. The campaign's "before" is Plan B's after-picture `../FacetBench/docs/studio-runs/2026-09-02-wicked-fast.md`.

**Scouting that this plan is written from** (read-only, 2026-09-03, at Facet `a46f84c4`): five briefs in the session scratchpad `briefs/S1-solver.md`, `S2-renderer.md`, `S3-boundary-adapters.md`, `S4-tests-oracle.md`, `S5-bench-rr.md`. Every line number below is at `a46f84c4` and DRIFTS as tasks land — locate by the quoted symbol/comment, never by line.

## Global Constraints

- Facet repo `/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet`, branch **`facet-parity`** (created off `main` `a46f84c4`, Plan B merged). Commits via `python3 tools/commit_isolated.py -m <msgfile> <path[:marker]>` (`--dry-run` first); **never amend; nothing merged or pushed** (finish with the branch menu).
- Gates on EVERY Facet commit, FOREGROUND, one lune process at a time: `tools/test.sh` (full); `tools/verify.sh affected --jobs 1` BEFORE committing (it diffs the working tree vs HEAD; on a clean tree it selects nothing — then `tools/verify.sh fast --jobs 1` is the HEAD attestation); `python3 tools/check_source_size.py`; `stylua --check src tests tools bench examples`. After any file EXTRACTION also run `python3 tools/check_brand_drift.py` by hand.
- **T0 landed at `0e69ceb1` (Facet) / `f446078` (FacetBench) before the plan was committed; later tasks start from there.** The base sentence above records where the BRANCH was cut (`a46f84c4`); Task 0's own work — `engineWrites` on both adapters, the fake's host `rect` field and write mirror, FacetBench's per-kind buckets — is already in the tree, so a line number cited "at `a46f84c4`" is located by its quoted symbol, never by number.
- **The floors are READ, not quoted (MI-2).** `8250/0` (Facet) and `3575/0` (RR) are the LAST OBSERVED counts from a transcript, not floors: the tracked Facet ledger floor is 8193 → 8222, and no RR run has ever recorded 3575 (the suite-cache max is 3574). **T0 step 7 runs both suites at the branch base, writes the true counts into the ledger, and every later `tools/test.sh <floor>` in this plan uses THAT number.** Until then the counts below are labelled "last observed".
- **RascalRally lockstep on every Facet `src/` change:** `cd games/RascalRally/code && ./run-tests.sh 2>&1 | tee <transcript>` green (at or above the T0-recorded base count), plus the rider spec the task names; milestone canary at T4 (C1 close), T5 (C6 close) and T10.
- **Source cap + the per-task character budget (ruling R-14).** `renderer.luau` 196,147 (3,853 headroom; its ledger row's trigger is the size line **198,000**); `solver.luau` 195,168 (4,832); `row_actions.luau` 195,894 is the third banded file (`source-cap-ledger.md:58`) and this plan does not touch it. **The STOP line for this campaign is 197,500** (500 under the trigger, so a stylua re-wrap cannot cross it unseen). Budget, measured AFTER stylua and recorded in the ledger at each task's gate: T1 **−2,100** (net), T3 **≤ +1,400**, T5 **≤ +900**, T8 and T9 **≤ +600 each**. A task that would blow its budget or cross 197,500 STOPS and takes the fallback seam planned up front — **T3 step 0b: `src/render/dirty_closure.luau`**, the pure `dirtyClosure(dirty) -> (contains, measures)` block at `renderer.luau:2988-3025` (~2 KB; a function of its argument alone, so it passes `tests/stack_seam.spec.luau`'s one-way test — unlike `livePaths`, which reassigns the scalar upvalue `pathNodeCount` and can NEVER be that seam). New code goes in new modules wherever the one-way test allows.
- **No public API or behaviour change.** `rectOf`/`screenRectOf`/`hitRectOf`/focus/engine `Position` return today's numbers BY CONSTRUCTION (composition on read) and the extended oracle proves it on every path. Diagnostics (`controller.diagnostics()`) are advisory but the oracle compares them too.
- **Counters, never wall-time.** Every demonstrator pins a counter AND `solves=N` for its drive (0 stated when the drive caused none); `scene.new()` → ONE discarded warm-up tick → the measured tick; pin idiom `` expect(`name={actual}`).toBe(`name={expected}`) ``; a "currently N" number is READ OFF THE RUN at HEAD with a throwaway probe before it is written into a spec (the T2 lesson).
- **Three oracles, each over the thing it can actually see (IM-2 — "both adapters" was an overclaim and is reworded here).** (1) The FAKE adapter carries the SOLVER-DRIVEN differential oracle: every arm, every drive, all 9 views. (2) The LIVE `screen_presentation` carries the ADAPTER-MATHS oracle on hand-fed rects — `tests/host_move_write_cost.spec.luau`, which is the only spec that drives the real `applyRect` (its header says why), extended in T3 step 9 into a 9-view loop over three fixtures. (3) STUDIO carries the end-to-end canary (T4/T5/T10). No claim in this plan says "proved on both adapters" unless it names which of the three saw it.
- **Differential oracle** after every driver step, on the fake adapter, all 9 `device_views.VIEWS` incl. `narrow-portrait` 320x640: `scene.snapshot()` — extended in T3 with engine `presentedPosition`/`presentedSize`, focus triple, and per-path `controller.rectOf`/`screenRectOf` — byte-equal to the full-solve arm `c` (`{ measureReuse = false, incremental = false }`; **there is no `controller.refresh({ full = true })` and this plan adds none**). Copy the non-vacuity guard and the "`b`/`d` DRIVEN every step, COMPARED selectively" rule verbatim.
- **A fast path that skips a function owes a LIST of everything that function published** (the T9 lesson). Every task that skips work (T3's arm skip, T5's lane, T6's serve, T7's serve) writes that list into its spec header and into the ledger BEFORE code, with a per-channel verdict: served / gated.
- Spec discovery is the hand-kept require list in `tests/run.luau` — **every new spec is added there** (and considered for `tests/lib/tiers.luau`'s exclusions if it is a device-matrix oracle).
- `commit_walks.skip` compares ENTRY TABLE IDENTITY; rects are `table.freeze`d — never mutate a rect in place; an entry table may be mutated (T5 does, deliberately, and says why).
- Fresh-context adversarial review per task (the SDD task review), ≤5 fix rounds, rulings in the ledger `.superpowers/sdd/2026-09-03-facet-parity-C/progress.md`; RED-TEAM at T10. Implementers: opus for T3/T5/T6/T7, sonnet for the rest; haiku only for scouting.

## Rulings made while writing this plan (recorded here so the ledger starts from them)

| # | Ruling | Why |
|---|---|---|
| R-1 | The pure placement function lives in **`src/layout/placement.luau`** as `placement.anchorPlace(...)`, NOT in a new `anchor_place.luau`. | `src/layout/anchor_placement.luau` already exists and is the presented-surface edge/flip/tail module; a fourth file one word away is a legibility hazard, and `placement.luau` already owns `ANCHOR_FACTORS`/`offsetPx`/`offsetFill` with zero Deps. |
| R-2 | **Coordinate-space hosts are exactly the translate trigger** (`createOpts.hostSpace = true`); canvasGroup/opacity/scale/rotation hosts and the adapter-registered scroll/clip hosts keep today's absolute-rect scheme and `settleRects`. The spec's "unify all host kinds" is **T4 step 3's measured decision**, not the default. **R-2 is IMPLEMENTED, not merely argued: `createOptsFor` returns `nil` for a `ScrollView` or a `clipChildren` container outright (T3 step 3), and `registerHost`'s reuse path ORs `hostSpace` so a double registration cannot lose it.** | The adapter's `px = rect.x - host.rect.x` re-base is space-invariant whenever host and child share a space, so mixed schemes compose exactly (T3 §"the adapter rule"); making scroll children host-relative would change the meaning of every raw-rect reader inside every RR list (scroll_into_view subtracts host from target). Smallest change first; unify only on a number. |
| R-3 | **The lane consumes its qualifying entries and hands the REMAINDER to the solve** (validate-then-apply, so it never half-applies). A pure tick has `solves=0`; a caster tick has `solves=1` with 208 hosts lane-translated and only the casters solved. | The FacetBench `nameplates` tick is `tickWithCasts` BY CONSTRUCTION (~42 casters resize their Cast bar every tick — `S5 §A4`), and RR's minimap dot move re-runs a PAINT memo beside the placement write. A lane that refuses on ANY other dirt never fires on either shipped surface. The spec's "never partially applies" is kept in its intended sense: all-or-nothing per candidate SET, validated before any write. Deviation from spec §5.4 wording — recorded; the owner sees it in the closing report. |
| R-4 | **Paint/semantics dirt never blocks the lane**; only measure/structure/navigation-affecting entries (the ones that set `needsSolve`) do. | `paint`/`semantics` entries are applied by the prop-write loop that runs BEFORE the solve gate whether or not a solve happens. |
| R-5 | The solver learns a host from a **build-time `Node.hostSpace` flag** copied by `layout_node` from the MOUNT node's `hostSpace` field, which `ensureTree` stamps from `createOpts` on the line that already computes it. | The solver has zero host knowledge today (`ctx.boundary` is the Stage-1 analysis map — a trap); `createOptsFor` runs once per node lifetime in `ensureTree`, which precedes the first solve of any node. |
| R-6 | `rectOf` composes `hostOriginOf` but **returns the STORED TABLE unchanged when the origin is (0,0)** — every node on a host-free tree, so a tree with no hosts is byte-identical at the ALLOCATION level and `slider.luau:183-185`'s identity assumption survives everywhere it is used today. | `screenRectOf` already solves the same problem with its `dx==0 and dy==0…` early-out. |
| R-7 | `stats.engineWrites` is **adapter-owned** (`adapter.engineWrites()` reader on both adapters, an OPTIONAL `target_contract` entry) and `controller.stats()` copies it into the clone. | There is no seam that hands the renderer's `stats` table into an adapter; the fake's precedent is a zero-arg reader (`hostCount`, `liveCount`). |
| R-8 | ~~A container becomes a `hostSpace` host only if its subtree (at create time) contains no `Composition`.~~ **REPLACED BY R-13 (review IM-7).** There is NO create-time Composition scan and no `instance_boundary.hasComposition`. Compositions under a space host are exact by the origin-carry R-13 installs. | The scan was a one-shot snapshot: `createOptsFor` runs once from `ensureTree` and mount nodes start with `children = {}` (`mount.luau:624`), so a `Composition` arriving later under a `When`/`ForEach` region would never be seen — a gate that silently stops holding is worse than no gate. R-13 makes the absolute origin available where the window-space decision is made, so nothing needs excluding. |
| R-9 | C2 is the **node-resident last-measure serve** inside `measure` (T6): `(lastOfferW, lastOfferH, lastW, lastH[, lastCtrW/H, lastCuts])` on the layout `Node`. **Amended by R-11: the serve is GATED, not "republishes the same three channels"** — it republishes **the three it can carry** and REFUSES whenever a channel it cannot carry is live. `memoPlans` persistence is NOT built. | Profile (S5 §A2): `Facet/measure` on the nameplates tick is 0.001 ms — the measure WALK is not the cost; `battle_hud` hp measure is 1.2 ms because clean siblings on the dirty path each pay a memo lookup (a `{maxW}|{maxH}|{scopeKey}` string + slate adopt + map probe). Serving from a few numbers on the node removes the whole lookup, for every container kind at once. |
| R-10 | **The lane serves `layout_node.build`'s placement fields through the build's OWN code, and never marks `nodeDirty`.** `layout_node.luau` extracts the four placement assignments of its node literal (`anchor`, `offsetX`, `offsetY`, `placementProps`) into `layout_node.applyPlacement(layoutNode, props, metrics)`. **The four assignments LEAVE the literal** — a Luau table constructor cannot call a function that mutates the table it is building — and `applyPlacement` is called on the CONSTRUCTED table immediately after the literal, before the `store.byNode[node]` write (`layout_node.luau:1416+`). The lane's `apply` calls the same function, so there is ONE copy. `applyPlacement` reads **all NINE** placement props (`anchor`, `offsetX`, `offsetY`, `alignH`, `alignV`, `lineAlign`, `gridSpan`, `layoutPriority`, `shrinkWeight`), because `placementProps` ORs all nine; the lane is safe calling it only because it refuses presence flips. **The nil-flip gate:** a placement entry whose OLD or NEW value is `nil` (a presence flip) is REFUSED and stays in the remainder. | The lane replaces `dirty` with the remainder, which removes the consumed entries from the classifier loop whose first act is the unconditional `markDirtyIn(nodeDirty, entry.path)` (`renderer.luau:2849`) — and the `nodeDirty = nil` safety valve cannot fire, because `refresh` advances `nodeDirtySeen = root.dirtySeq()` BEFORE the loop. The warm store hit (`layout_node.luau:315-326`) would then return a layout node carrying the stale `resolveOffset`. Marking `nodeDirty` anyway would cost the lane nothing but reintroduces a build; serving through the build's own function is exact and is the T9 lesson's rule (1) — publish the LIST, not "the ones we found". The nil flip is the only thing that moves `placementProps` (`layout_node.luau:605-615`) and the parent's `inertPlacement` audit, so it is gated instead of served (review MI-8). |
| R-11 | **T6's serve is gated, never republishing what a tuple cannot carry.** `layout_node.build` computes two bottom-up booleans on every node — `subtreeHasScroll`, `subtreeHasComposition` — in the same post-children pass that computes `containerRelativeInside`, and **both are SELF-INCLUSIVE** (`node.kind == "scroll" or any child.subtreeHasScroll`; `node.kind == "composition" or any child.subtreeHasComposition`), the shape `containerRelativeInside` already has where it ORs `selfRelative` — because `ctx.hasScroll` is set for the node ITSELF and `ctx.compositions[node.id]` is written for the composition node itself, so a child-only OR would leave the owner of each channel ungated. The serve refuses when `node.subtreeHasScroll`, `node.subtreeHasComposition`, `node.containerRelativeInside == true`, `ctx.analyze`, or `not ctx.measureQuiet`. It SERVES offers (2), `textStates`/`compact`/`textFacts` (3) and `ctx.fitCuts += node.lastCuts`. The record happens through ONE **module-level** `record(ctx, node, maxW, maxH, cutsAtEntry, w, h)` — `cutsAtEntry` BEFORE the values, so the two `return measureUncached(…)` returns stay one-liners instead of needing a temp that an implementer can get wrong — — module-level because it reads `ctx` and `cutsAtEntry`, and a `local function` inside `measure` would allocate a closure on every one of the 2,000+ calls T6 exists to make cheaper — called at EVERY `return` of `measure`, **the serve's own return included** (`return record(ctx, node, maxW, maxH, cutsAtEntry, node.lastW, node.lastH)`, which is idempotent: it rewrites the same tuple, and `lastCuts = ctx.fitCuts - cutsAtEntry` reproduces the `node.lastCuts` the serve just added). | `measure`'s memo-hit path publishes ten channels (T6's spec-header table), not three: `ctx.compositions[node.id]` alone feeds the public `controller.compositionAt`, and `ctx.hasScroll`/`armContainer`'s `ctx.scopeKey`/`ctx.boundary` cannot be carried by four numbers. T9 rule (2): gate on the channel you cannot serve. And `measure` has SIX returns, four of them early — a `local w, h = measureBody(...)` wrapper is the exact shape T9 rule (4) names as the trap, so the recorder goes at every return and a source scan pins `#returns == #record( calls`. |
| R-12 | **The lane SERVES `hit_lift` instead of counting sinks and expanders.** After applying, `if adapter.setHitRect ~= nil and next(lastHitRects) ~= nil and hitLift.refresh(lastResult.rects, lastHitRects, inputSinks, parentNodeOf, solverHidden, geometry.hostOriginOf) then syncZOrder() end` — the same call the commit makes, **carrying the commit's own feature guard `adapter.setHitRect ~= nil`** (`renderer.luau:2181-2183`). It reads `lastHitRects`, not the tree. **The origin it is handed is `geometry.hostOriginOf`, NOT the commit's fresh-map `originOf`** (review I-1): the same map-decides-the-function rule — a lane frame runs no solve, so the per-commit closure over `result.rects` does not exist, and the lane's own `apply` has already written `lastRects[path]` and bumped the epoch, so `hostOriginOf` IS this frame's origin there. `hostHitCount` and `hostSinkCount` DO NOT EXIST. The host's OWN expander gate stays (`lastHitRects[path] ~= nil` → refuse), and the Path gate stays (`spaceHostHasPath`, the only thing `noteUnder`/`noteFromHost` serve — a COUNT whose key they DELETE at zero, cleared by `clearHosts`/`dropPath` with the other maps). **Every ±1 on that count RIDES A LATCH THE SOURCE ALREADY KEEPS, never an unconditional per-walk `+1`** (settled at review D-0, T5 step 3 has the code): the `+1` rides `livePaths`' existing transition at `renderer.luau:1459-1463` (`local isPath = node.class == "Path"; if isPath ~= (pathNodes[node.path] ~= nil) then …`) and fires only on `isPath and pathNodes[node.path] == nil`, with `pathNodes[node.path] = isPath or nil` left AFTER the note; a REPARENT is a second, exclusive branch, ordered BEFORE `hostSpaceOf[node.path]` is rewritten for the walk, that notes the OLD chain −1 and the NEW chain +1 through `geometry.noteFromHost` (`noteUnder` would skip the old host itself and would read the stale chain) and then rewrites `geometry.pathHostOf[node.path]`; the `−1` rides `sweepDeparted`'s existing `if pathNodes[path] ~= nil then` guard (`renderer.luau:2584` — which is also how `sweepDeparted` knows the departed node was a Path), inside that guard and BEFORE `geometry.dropPath(path)` clears `hostSpaceOf`. An unconditional `+1` ratchets forever, because the bounded structural arm re-walks live nodes and never calls `clearHosts()`. | RascalRally's minimap `Dot` (`MapCanvas.luau:267-307`) is a `UI.Anchor` with reactive offsets and children — a space host by construction — whose subtree holds a `DotHit` `UI.Button` (a sink) and, mid-omen, a `UI.Path`. The two counters would have refused the lane on the ONLY surface it was built for, while an isolated-fixture pin passed and proved nothing. Serving the real function costs one `hit_lift.refresh` on a frame that has any expander at all and is exact by construction. |
| R-13 | **The solver carries the absolute origin down `arrange`** as `ctx.spaceOX`/`ctx.spaceOY`, pushed and popped in a four-line WRAPPER around the renamed `arrangeBody` (a hand-placed pop before each of `arrangeBody`'s several returns is one `return` away from leaking a host's origin into its parent's siblings for the rest of the solve; a wrapper cannot be skipped by a branch, and all twelve recursive call sites AND `solve`'s root call at `solver.luau:3585` keep calling `arrange` — the root call included, which is what makes a hostSpace ROOT push its own origin too). **There is no `ctx.spaceOrigin` map** — no reader can reach one. **`compositionResolve.resolve` takes ORIGIN NUMBERS, not a rect** (`resolve(deps, ctx, node, innerW, innerH, originX?, originY?)`) — so the ARRANGE-time call becomes `compositionResolve.resolve(COMPOSITION_DEPS, ctx, node, innerW, innerH, innerX + ctx.spaceOX, innerY + ctx.spaceOY)` and the MEASURE-time call is unchanged. **The absolute-rect audit is fixed at its PRODUCER, `tests/lib/large_text.auditRects`** — one line, `rect = w.controller.rectOf(path)` in place of `rect = node.rect`. `text_audit.luau` is NOT modified. **No create-time scan (R-8 is dead).** **`ctx.spaceOrigin` does not exist** — see the decision recorded in T3's Files list. | The **three** absolute readers are real, and what gates on them is a shipped spec suite: (1) `composition_resolve.luau:187-197` decides `atRoot` by `placedY == ctx.rootRect.y` and keys its cache on `{placedX},{placedY}` — served by the `ctx.spaceOX`/`spaceOY` carry at its arrange-time call site; (2) `tests/lib/large_text.auditRects` (`:220-244`) builds its map from `w.adapter.node(path).rect` — the ADAPTER's STORED rect, which is exactly what T3 makes host-relative — and feeds `audit.overlaps`, `audit.clippedEssential` and `audit.hitFloor` (`:258-260`); (3) `src/layout/dump.luau`'s `nodeDump` (`:11-51`) emits `rect = entry and entry.rect`, the solver's own entry rect, and is composed at its producer with a two-number accumulator down the recursion it already does. Under T3 reader (2) is a screenful of false findings in the **large-text device-matrix specs** (`tests/large_text_*.spec.luau`), which is what gates on it — the arm-`c` oracle CANNOT see it (both arms host). (`text_audit.outOfBounds`/`focusVisibility` have NO live producer: they are called only from `tests/text_audit.spec.luau` on hand-built literal rect maps, so nobody should go hunting for one.) Carrying two numbers down the walk the solver is already doing is O(1) per node and exact for a Composition that appears at any time. The measure-time `resolve` needs nothing: measure runs before any position is known, so its origin-less fallback to `ctx.rootRect` was ALREADY position-blind, and the arrange-time re-resolve is what lands — the file's own `:174-181` argument already relies on exactly that. |
| R-14 | **A per-task character budget, and a fallback seam planned up front** (see Global Constraints): STOP line 197,500; T1 −2,100 / T3 ≤ +1,400 / T5 ≤ +900 / T8, T9 ≤ +600; the fallback is `src/render/dirty_closure.luau`, taken as T3 step 0b. | T1 nets ~−2,100 while T3 and T5 together add host maps, three composition sites, a `livePaths` parameter, ctx fields on `rect_pass`/`commit_walks`, two adapter arguments, the lane hook and two `stats` fields — at this repo's comment density that plausibly returns the renderer to within ~1,000 of the trigger. The plan's old escape hatch (`livePaths`) FAILS the one-way test: it writes `stats.lastSsVisited`, four maps, and reassigns the scalar upvalue `pathNodeCount` (`renderer.luau:1462`). A budget measured per task is how the STOP is seen coming instead of hit. |
| R-15 | **T4 step 1 is T3 step 0 and T4 step 2 is T3's acceptance gate (step 10).** T4 keeps the rest, renumbered 1-5. | The RR literals are read AT HEAD, and a HEAD literal cannot be read after HEAD moved: that makes them unconditionally a T3 prerequisite, not the "do T4 steps 1-3 before committing T3 if needed" parenthetical the plan had. And "the same literals unchanged" IS T3's acceptance test — the one sentence that says the public numbers did not move on the production consumer. |

---

### Task 0 (C0): the "before", the instruments, and the lever verdicts

**Files:**
- Modify: `src/client/screen_presentation.luau` (`applyRect` write-skip `:401-408`, `applyHitExpander` `:296-315`) — count engine writes
- Modify: `src/client/screen_target.luau` (export the counter reader beside `census`)
- Modify: `tests/lib/fake_target.luau` (`setRect` `:524-553`: per-node `lastWriteX/Y/W/H` mirror + counter; new `adapter.engineWrites()` beside `hostCount` `:873`)
- Modify: `src/render/target_contract.luau` (`OPTIONAL` `:37-…`: add `"engineWrites"`; fix the stale `:20` prose)
- Modify: `src/render/renderer.luau` (`controller.stats()` `:3806-3808`)
- Modify: `tests/commit_dirt_classes.spec.luau:876`, `tests/commit_translate.spec.luau:217` (the hand-rolled `stats` literals gain nothing — the field is adapter-side, so these do NOT change; verify by running them)
- Modify: `tests/render_target_contract.spec.luau` (pins both adapters against `OPTIONAL` — confirm it accepts an entry one adapter lacks, else add the reader to both)
- Modify (FacetBench): `runner/lune/run_one_lib.luau` (`:168-230`), `runner/lune/lib/schema.luau` (`METRIC_FIELDS`), `tools/profile/attr.luau:113` (`statFields`)
- Create (FacetBench): `docs/studio-runs/2026-09-03-facet-parity.md` (§before only)
- Test: `tests/engine_writes.spec.luau` (new; register in `tests/run.luau`)

**Interfaces:**
- Produces: `adapter.engineWrites(): number` on both adapters (cumulative engine `Position`/`Size` writes made by the node's own `applyRect`/`setRect` path — NOT hit expanders, NOT decorations); `controller.stats().engineWrites` (nil when the adapter has no reader); FacetBench row `metrics.byKind = { [bucket] = { n, p50, p95 } }` (optional, loop rows only).
- Later tasks read `engineWrites` in every demonstrator.

- [ ] **Step 1: the fake target's engine-write mirror (red first).** Write `tests/engine_writes.spec.luau`:

```luau
--!strict
--[[ ENGINE WRITES ARE COUNTED AT THE WRITE, ON BOTH ADAPTERS (Plan C, T0).
	`stats.rectWrites` counts `adapter.setRect` CALLS; the engine's own bill is two
	levels down — the `Position`/`Size` assignment `applyRect` makes after its
	write-skip compare. Under a real instance parent the two diverge by design
	(a host move: N setRect calls, 1 Position write), so a counter that can only
	see the call proves nothing about the collapse this campaign is for. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")

describe("engineWrites: the adapter counts what the engine was told", function()
	it("the fake target counts one Position/Size write per changed rect, none for an equal one", function()
		local s = scene.new()
		s.tick(3, 2) -- warm: the first refresh is the cold solve
		local before = s.adapter.engineWrites()
		s.tick(3, 2)
		local st = s.stats()
		-- READ OFF THE RUN at HEAD before T3: every one of the 1,500 rect writes is a
		-- real engine write today, because the plate tree is FLAT.
		expect(`engineWrites delta={s.adapter.engineWrites() - before} solves={st.solves}`).toBe(
			`engineWrites delta={scene.PLATES * scene.NODES_PER_PLATE} solves={st.solves}`
		)
		expect(`stats.engineWrites={st.engineWrites}`).toBe(`stats.engineWrites={s.adapter.engineWrites()}`)
		-- an A/A re-apply costs nothing: the mirror compares before it writes
		local again = s.adapter.engineWrites()
		s.controller.refresh()
		expect(`A/A delta={s.adapter.engineWrites() - again}`).toBe("A/A delta=0")
		s.dispose()
	end)
end)
```

Register it in `tests/run.luau` (beside `require("./commit_translate.spec")`). Run `lune run tests/run_one engine_writes` — expected FAIL: `attempt to call a nil value (field 'engineWrites')`.

- [ ] **Step 2: the fake target.** In `tests/lib/fake_target.luau` `adapter.setRect` (`:524`), add the mirror BEFORE the `ops` insert, and the reader beside `hostCount`:

```luau
	-- THE ENGINE-WRITE MIRROR (Plan C, T0): the live `applyRect` compares the pair
	-- it is about to write against the pair it wrote last (`handle.lastWriteX/Y`,
	-- `lastWriteW/H`) and skips an equal one. Mirrored here at the same
	-- granularity — Position and Size counted separately — so a headless
	-- demonstrator can pin the collapse a real parent buys instead of inferring it.
	local engineWriteCount = 0
	function adapter.engineWrites(): number
		return engineWriteCount
	end
```

and inside `setRect`, after `handle.rect = rect`:

```luau
		-- see `engineWrites`: the position the engine would be handed is the
		-- host-relative pair (`presentedPosition` is the WINDOW pair; both are kept)
		local hostOx, hostOy = 0, 0
		local host = handle.instanceHost
		if host ~= nil and host.rect ~= nil then
			hostOx, hostOy = host.rect.x, host.rect.y
		end
		local px, py = rect.x - hostOx, rect.y - hostOy
		if handle.lastWriteX ~= px or handle.lastWriteY ~= py then
			handle.lastWriteX, handle.lastWriteY = px, py
			engineWriteCount += 1
		end
		if handle.lastWriteW ~= rect.w or handle.lastWriteH ~= rect.h then
			handle.lastWriteW, handle.lastWriteH = rect.w, rect.h
			engineWriteCount += 1
		end
```

NOTE the fake's host entry has NO `rect` today (`{ path, crops, children }` at `:209`); in this task make `registerFakeHost` entries gain `rect = nil` and have `setRect` write `entry.rect = rect` when `instanceHosts[handle.path] ~= nil` (mirroring `screen_target.setRect:2098-2100`). That is the live shape and T3 needs it.

- [ ] **Step 3: the live adapter.** `screen_presentation.luau` `applyRect`: add a module-closure counter and increment inside BOTH `if handle.lastWriteX ~= px …` and `if handle.lastWriteW ~= pw …` branches (`:401-408`); export `engineWrites = function() return engineWriteCount end` in the return table (`:576-595`). `screen_target.luau`: `adapter.engineWrites = region.engineWrites` next to its other presentation re-exports (grep `region.applyRect` to find where the region's functions are bound). `target_contract.OPTIONAL` gains `"engineWrites", -- () -> number  [diagnostic: engine Position/Size writes]` with a two-line note; rewrite `:20`'s "today `{ canvasGroup }`" to "today `{ canvasGroup?, instanceHost?, hostSpace? }`" (T3 adds the third). Run `lune run tests/run_one render_target_contract`.

- [ ] **Step 4: `controller.stats()`.** `renderer.luau:3806-3808`:

```luau
	function controller.stats()
		local out = table.clone(stats)
		-- adapter-owned (Plan C, T0): the engine's own write count lives where the
		-- write is made; nil on an adapter without the reader
		if adapter.engineWrites ~= nil then
			out.engineWrites = adapter.engineWrites()
		end
		return out
	end
```

Run `lune run tests/run_one engine_writes` → PASS. Run `python3 tools/check_source_size.py` (renderer +~250).

- [ ] **Step 5: FacetBench per-step-kind buckets.** In `runner/lune/run_one_lib.luau`'s sample loop (`:173-178`), accumulate per bucket using the SAME bucket rule `tools/profile/lib_attr.luau`'s `bucketName` uses (copy it into a small local: `updateItem-<field>`, `updateItems-<listState>`, `addItem-<listState>`, `removeItem-<listState>`, else `step.kind`):

```luau
		local byKind: { [string]: { number } } = {}
		…
			samples[i] = (os.clock() - s0) * 1000
			local bucket = bucketName(step)
			local list = byKind[bucket]
			if list == nil then
				list = {}
				byKind[bucket] = list
			end
			table.insert(list, samples[i])
```

and after `row.metrics = { … }`:

```luau
		-- PER-CLASS ON BOTH RUNNERS (Plan C, T0 — the wicked-fast after-doc §4.4's
		-- booked instrument): one distribution per step-kind bucket, so a live vide
		-- cell stops being a whole-workload p50 wearing a per-class label. Loop rows
		-- only; a frames row is paced per frame and its per-step split means nothing.
		if frameWait == nil then
			local buckets: { [string]: any } = {}
			for bucket, list in byKind do
				local bs = stats.summarize(list)
				buckets[bucket] = { n = #list, p50 = bs.p50, p95 = bs.p95 }
			end
			row.metrics.byKind = buckets
		end
```

`schema.luau`: `byKind` is OPTIONAL on a loop row (validate shape: table of `{ n: number, p50: number, p95: number }`), FORBIDDEN on a frames row. `tools/check_schema` + `lune run tests/run` (FacetBench) + `tools/check.sh` green. `attr.luau:113` `statFields`: append `"engineWrites"`.

- [ ] **Step 6: the before.** From FacetBench root, with the sibling Facet at the T0 commit: `lune run tools/profile/attr <w> L 3` for `nameplates`, `damage_fountain`, `battle_hud`, `war_room_inventory`, `killfeed_nameplates`; and `lune run runner/lune/run_matrix --frameworks facet --sizes L --out artifacts/parity-before-lune.json`. Write `docs/studio-runs/2026-09-03-facet-parity.md` §before: (a) the 29-row per-class table (Lune, this run, HEAD) with the after-doc's live column beside it (`285b8ce6`, labelled as such), vide's live `stepP50Ms` per workload labelled "whole-workload" — and, from `byKind`, nothing yet (vide is live-only: the Studio drive at T10 fills the per-class vide rows for the first time); (b) the per-span table for `battle_hud updateItem-hp`, `war_room setState`, `killfeed updateItem-hp` (measure / arrange / each `cw.*` / `rectPass` / `dirtyScan`+`dirtyClosure` / build / react) and for `nameplates` add/remove `ssZOrder` etc.; (c) **the lever verdict paragraph**: for C2 (measure), C3 (arrange), C4 (commit walks), C5 (`ssZOrder`) state the span's share of its class — ≥5 % is a lever, else it is BOOKED with the number and its task is skipped at T10's discretion. Commit (FacetBench) — `docs/` + `runner/` + `tools/`.

- [ ] **Step 7: the true floors, gates + commit (Facet).** FIRST, before any of this task's edits are staged: check out the branch base and run `tools/test.sh` and RR `./run-tests.sh` clean, and write **the two counts they actually print** into the ledger as `BASE FACET <n>/0` and `BASE RR <n>/0` (MI-2: the plan's `8250`/`3575` are last-observed transcript numbers — the tracked Facet ledger floor is 8193 → 8222 and RR has never recorded above 3574). Every later `tools/test.sh <floor>` in this plan means THAT number. Then: `tools/verify.sh affected --jobs 1`; `tools/test.sh <BASE FACET>`; `check_source_size.py`; stylua; RR `./run-tests.sh` (fake_target changed shape: `engineWrites` reader + host `rect`) → record counts in the ledger. Commit message: `T0: engineWrites on both adapters, FacetBench per-kind buckets, the Plan C before`.

---
### Task 1 (C1 step 1a): the renderer's geometry-read seam — `src/render/rect_reads.luau`

The renderer is 1,853 characters from its size line and T3 must add a host map, a composed reader and three composition sites to it. The ledger row says "no clean small seam is left" — but the four geometry READS are one-way by the file's own test (they read `lastRects`, `handles`, `scrollHostOf` — tables the renderer mutates IN PLACE and never rebinds, see `dispose`'s own comment at `:3993-3996` — and `adapter`, plus one function `presentationShift`), and T3's whole change lives in exactly those reads. This is the LIVE seam, taken first, in its own commit.

**Files:**
- Create: `src/render/rect_reads.luau`
- Modify: `src/render/renderer.luau` (delete `rectOf` `:323-326`, `scrollShift` `:389-406`, `screenRectOf` — declared `:472`, body to `:493` — and `paintedRectIn` — declared `:498`, body to `:509`; bind the four names from the module at the same place)
- Modify: `tools/lune/verify/data/source-cap-ledger.md:59` (the RENDERER row — `:72` is the solver, `:58` is `row_actions.luau`: re-record size + name the seam as taken)
- Modify: `tests/lib/renderer_source.luau` (`PARTS` gains `rect_reads`)
- Test: `tests/rect_reads_seam.spec.luau` (new; copy the shape of `tests/stack_seam.spec.luau`)

**Interfaces:**
- Produces: `rect_reads.new(deps: Deps) -> { rectOf, scrollShift, screenRectOf, paintedRectIn, hostSpaceOf, spaceHosts, spaceHostHasPath, pathHostOf, hostOriginOf, originIn, noteUnder, noteFromHost, invalidateOrigins, clearHosts, dropPath }` where
  ```luau
  export type Deps = {
  	adapter: any,                              -- `getScrollPosition` (optional on the target)
  	handles: { [string]: any },                -- by reference
  	lastRects: { [string]: any },              -- by reference
  	scrollHostOf: { [string]: string },        -- by reference (cleared in place at structuralSync/dispose)
  	presentationShift: (path: string) -> (number, number),
  }
  ```
  `hostSpaceOf`/`spaceHosts`/`spaceHostHasPath`/`pathHostOf`/`hostOriginOf`/`originIn`/`noteUnder`/`noteFromHost`/`invalidateOrigins`/`clearHosts`/`dropPath` are created here EMPTY-BEHAVIOURED (T3 fills the first two, T5 fills `spaceHostHasPath` and `pathHostOf`; every map is declared and CLEARED here so no later task can add a map that `clearHosts`/`dropPath` forget — review N-8): in T1 `hostOriginOf` and `originIn` return `0, 0` and `rectOf` is the bare read. Declaring the names now is what keeps T3's renderer diff to the bindings.
  **`noteUnder` and `noteFromHost` are TWO ENTRY POINTS onto one loop (review D-0):** `noteUnder(map, path, d)` starts at `hostSpaceOf[path]` — the caller has a node and wants the hosts ABOVE it; `noteFromHost(map, hostPath, d)` starts AT `hostPath` and walks its own `hostSpaceOf` chain — the caller already HAS the host. T5's reparent branch needs the second (`noteUnder(map, oldHost, -1)` would skip `oldHost` itself, the one host whose count actually changed), and it needs it on BOTH sides because the branch runs BEFORE `hostSpaceOf[path]` is rewritten for the walk, so `noteUnder` would read the stale chain. `noteUnder` is one line: `noteFromHost(map, hostSpaceOf[path], delta)`. Delete-at-zero lives in the shared loop, so neither entry point can forget it.
  **`originIn(rects, path)` is NOT `hostOriginOf` (ruling from review BL-5):** `hostOriginOf` walks `lastRects`, which is LAST frame's geometry, and `paintedRectIn` deliberately reads the CURRENT solve's `rects` map — its own comment says why ("culling this frame's paths against last frame's geometry is exactly the one-frame lag that makes a re-sorted row flash its ring outside the list"). Composing a fresh child rect against a stale host origin would re-create that lag for every node under a moving host, on the cull pass. So `originIn` takes the same `rects` argument `paintedRectIn` was handed and walks `hostSpaceOf` reading `rects[host].rect`; `paintedRectIn` uses `originIn`, and only `rectOf`/`screenRectOf` use `hostOriginOf`.
- T3 consumes every one of these.

- [ ] **Step 1: the seam spec, red.** Create `tests/rect_reads_seam.spec.luau` from `tests/stack_seam.spec.luau`'s skeleton (its `stripComments`, `fieldsRead`, `sorted`, the Deps-set assertion `:73-85`, the READ-vs-WRITE scan `:150-188`, and the negative controls `:130-147`, `:190-224`), asserting:
  - `require("../src/render/rect_reads")` loads and `rect_reads.new` is a function;
  - declared `Deps` fields == fields read off `deps` == `{ "adapter", "handles", "lastRects", "presentationShift", "scrollHostOf" }`;
  - it assigns NO field of `deps` (`expect(assigned).toEqual({})`), and the only `table.insert` targets are none;
  - `renderer.luau` contains the char-for-char bind line `local geometry = rect_reads.new({ adapter = adapter, handles = handles, lastRects = lastRects, scrollHostOf = scrollHostOf, presentationShift = presentationShift })` and NO remaining `local function screenRectOf`/`local function scrollShift`/`local function paintedRectIn`/`local function rectOf` definitions (`string.find(src, "local function screenRectOf", 1, true) == nil`);
  - behavioural: on a hand-built world with a ScrollView (the `customFactory.new()`/`environment.new`/`mountLib.mount`/`fake_target.new()`/`renderer.attach` world every spec builds by hand — e.g. `tests/layout_prop_dirt.spec.luau:395-422`), `controller.screenRectOf(path)` minus `controller.rectOf(path)` equals minus the scroll position after `controller.scrollTo(host, { x = 0, y = 40 })` — the same number the pre-seam build returns (pin it as a literal read at HEAD first).
  Run `lune run tests/run_one rect_reads_seam` → FAIL (module missing).

- [ ] **Step 2: create `src/render/rect_reads.luau`** — move the four bodies VERBATIM (comments included), with `lastRects`, `handles`, `scrollHostOf`, `adapter` unpacked from `deps` at `new` and `presentationShift` called as `deps.presentationShift`. Preamble:

```luau
--!strict
--[[ THE FOUR GEOMETRY READS, lifted out of `render/renderer.luau` on 2026-09-03
	(Plan C, T1) because the renderer stood 1,853 characters from the size line
	its own ledger row names, and the campaign's change is a change to exactly
	these reads: rects beneath an instance host that is a COORDINATE SPACE are
	stored host-relative, and `rectOf`/`screenRectOf` compose the host chain on
	read the way `screenRectOf` already composes the scroll and presentation
	shifts (T3 fills `hostOriginOf`; here it is the identity).

	ONE-WAY BY THE FILE'S OWN TEST. Everything this reads is a table the renderer
	mutates IN PLACE and never rebinds — `handles`, `lastRects`, `scrollHostOf`
	(`dispose` clears them with `table.clear` for exactly this reason) — plus the
	adapter and one function. No reassigned upvalue of the host crosses this
	boundary; `tests/rect_reads_seam.spec.luau` is the proof. ]]
local rect_reads = {}

export type Deps = {
	adapter: any,
	handles: { [string]: any },
	lastRects: { [string]: any },
	scrollHostOf: { [string]: string },
	presentationShift: (path: string) -> (number, number),
}

function rect_reads.new(deps: Deps)
	local adapter = deps.adapter
	local handles = deps.handles
	local lastRects = deps.lastRects
	local scrollHostOf = deps.scrollHostOf
	local presentationShift = deps.presentationShift

	-- path -> nearest COORDINATE-SPACE host ancestor (T3 fills it on the live-path
	-- walk; empty here). Cleared in place with the renderer's other per-path maps.
	local hostSpaceOf: { [string]: string } = {}
	-- the set of paths that ARE coordinate-space hosts (T3 fills it on the same walk)
	local spaceHosts: { [string]: true } = {}
	-- space host -> how many `Path` nodes live under it (T5's `visible` gate fills it
	-- on the same walk). A COUNT, so `noteUnder` DELETES the key at zero: `0` is
	-- truthy in Luau, and a gate written `if spaceHostHasPath[path] then` would
	-- otherwise refuse forever once a Path had ever been under that host.
	local spaceHostHasPath: { [string]: number } = {}
	-- which space host a PATH node was last counted under, so a reparented Path can
	-- note the OLD host −1 and the NEW host +1 (review B-2). Keyed by the Path's own
	-- path; nil for a Path with no space host above it. WHO FILLS IT: `livePaths`
	-- (T5 step 3), on the same latch edge that fills `spaceHostHasPath`. WHO READS
	-- IT: exactly one site — that walk's reparent branch, which compares it against
	-- the nearest space host the walk has just computed, BEFORE `hostSpaceOf[path]`
	-- is rewritten for this walk. Nothing else reads it.
	local pathHostOf: { [string]: string } = {}
	-- absolute origin of a host, cached; invalidated wholesale by an epoch bump
	local originCache: { [string]: { x: number, y: number, epoch: number } } = {}
	-- the COMPOSED rect of a path, cached against the same epoch (Plan C ruling from
	-- review IM-9): inside a space host `rectOf` would otherwise allocate a fresh
	-- table per call, and ~30 sites compare what it returns BY IDENTITY —
	-- `slider.luau:183-185` skips a signal write on identity, and the pointer
	-- contract `(path, pos, rectOf)` is called per pointer MOVE by `table_rows`,
	-- `level_picker`, `virtual_list_hosted`, `region_expand`. Memoised per
	-- (path, epoch), identity is stable between host moves; the cost is one table
	-- per path under a host per host move, on demand.
	local composedCache: { [string]: { epoch: number, src: any, rect: any } } = {}
	local originEpoch = 0

	local function invalidateOrigins()
		originEpoch += 1
	end
	local function clearHosts()
		table.clear(hostSpaceOf)
		table.clear(spaceHosts)
		table.clear(originCache)
		table.clear(composedCache)
		table.clear(spaceHostHasPath)
		table.clear(pathHostOf)
		originEpoch += 1
	end
	-- ±1 on `hostPath` ITSELF and every space host above it. This is the entry point
	-- for a caller that already HAS the host rather than a path under it — T5's
	-- reparent branch knows the OLD host and the NEW host, and `noteUnder(map,
	-- oldHost, -1)` would start at `hostSpaceOf[oldHost]` and SKIP `oldHost`, which
	-- is the one host whose count actually changed. `nil` is a legal argument and a
	-- no-op (a Path with no space host above it). The key is DELETED at zero.
	local function noteFromHost(map: { [string]: number }, hostPath: string?, delta: number)
		local host = hostPath
		while host ~= nil do
			local n = (map[host] or 0) + delta
			map[host] = if n > 0 then n else nil
			host = hostSpaceOf[host]
		end
	end
	-- ±1 on every space-host ancestor of `path`; the key is DELETED at zero
	local function noteUnder(map: { [string]: number }, path: string, delta: number)
		noteFromHost(map, hostSpaceOf[path], delta)
	end
	-- one departed path (called from `sweepDeparted`): the bounded structural arm
	-- does not clear the whole map, and a stale entry keyed by a removed host is a
	-- wrong origin, not a slow one (review IM-8)
	local function dropPath(path: string)
		hostSpaceOf[path] = nil
		spaceHosts[path] = nil
		originCache[path] = nil
		composedCache[path] = nil
		spaceHostHasPath[path] = nil
		pathHostOf[path] = nil
	end
	-- the sum of the host chain above `path` — (0, 0) on every path with no
	-- coordinate-space host above it, which is every path on a host-free tree
	local function hostOriginOf(path: string): (number, number)
		local host = hostSpaceOf[path]
		if host == nil then
			return 0, 0
		end
		local cached = originCache[host]
		if cached ~= nil and cached.epoch == originEpoch then
			return cached.x, cached.y
		end
		local r = lastRects[host]
		local hx, hy = hostOriginOf(host)
		local x = hx + (if r ~= nil then r.x else 0)
		local y = hy + (if r ~= nil then r.y else 0)
		originCache[host] = { x = x, y = y, epoch = originEpoch }
		return x, y
	end
	-- THE SAME WALK OVER A CALLER-SUPPLIED MAP (review BL-5). `paintedRectIn` reads
	-- the CURRENT solve's `rects`, on purpose; `hostOriginOf` reads `lastRects`,
	-- which on the cull pass is last frame's. Uncached by construction — the map is
	-- the argument, so there is nothing stable to key on.
	local function originIn(rects: { [string]: any }, path: string): (number, number)
		local ox, oy = 0, 0
		local host = hostSpaceOf[path]
		while host ~= nil do
			local e = rects[host]
			local r = if e ~= nil then (e.rect or e) else nil
			if r ~= nil then
				ox += r.x
				oy += r.y
			end
			host = hostSpaceOf[host]
		end
		return ox, oy
	end

	-- drag math reads solved rects through this lookup. THE STORED TABLE, UNCHANGED,
	-- whenever the origin is (0, 0): `slider.luau` compares what this returns by
	-- identity to skip a signal write, and a host-free tree must stay byte-identical
	-- at the allocation level too (Plan C ruling R-6). INSIDE a host the composed
	-- table is memoised against the origin epoch (review IM-9) so identity is stable
	-- between host moves and no per-read allocation happens.
	local function rectOf(path: string): any
		local rect = lastRects[path]
		if rect == nil then
			return nil
		end
		local ox, oy = hostOriginOf(path)
		if ox == 0 and oy == 0 then
			return rect
		end
		local cached = composedCache[path]
		-- `src` is compared BY IDENTITY: a stored rect is `table.freeze`d and replaced
		-- wholesale when it changes (Global Constraints), so a different table is the
		-- exact test for "this path's own rect moved", and the epoch is the test for
		-- "a host above it moved".
		if cached ~= nil and cached.epoch == originEpoch and cached.src == rect then
			return cached.rect
		end
		local out = { x = rect.x + ox, y = rect.y + oy, w = rect.w, h = rect.h }
		composedCache[path] = { epoch = originEpoch, src = rect, rect = out }
		return out
	end
	… (scrollShift verbatim) …
	local function screenRectOf(path: string, relativeTo: string?): any
		local rect = lastRects[path]
		if rect == nil then
			return nil
		end
		local dx, dy = scrollShift(path)
		local px, py = presentationShift(path)
		local hx, hy = hostOriginOf(path)
		local out = if dx == 0 and dy == 0 and px == 0 and py == 0 and hx == 0 and hy == 0
			then rect
			else { x = rect.x - dx + px + hx, y = rect.y - dy + py + hy, w = rect.w, h = rect.h }
		… (relativeTo tail verbatim) …
	end
	… (paintedRectIn verbatim, plus `local hx, hy = originIn(rects, path)` — `originIn`, NOT
	   `hostOriginOf`: the argument map is the fresh one this function exists to read) …
	return {
		rectOf = rectOf, scrollShift = scrollShift, screenRectOf = screenRectOf, paintedRectIn = paintedRectIn,
		hostSpaceOf = hostSpaceOf, spaceHosts = spaceHosts, spaceHostHasPath = spaceHostHasPath,
		pathHostOf = pathHostOf, hostOriginOf = hostOriginOf, originIn = originIn, noteUnder = noteUnder,
		noteFromHost = noteFromHost,
		invalidateOrigins = invalidateOrigins, clearHosts = clearHosts, dropPath = dropPath,
	}
end

return rect_reads
```

(`hostOriginOf`/`originIn` ARE included in T1 — with `hostSpaceOf` empty they are one table read and return `0, 0` on every path, so T1's behaviour is today's byte-for-byte; T3 only populates the maps. `originCache`'s `epoch` field makes invalidation O(1) per host move instead of O(hosts), and `composedCache` hangs off the same epoch.)

- [ ] **Step 3: rewire the renderer.** Delete the four bodies; at the position of the old `rectOf` add `local geometry = rect_reads.new({ … })` (the char-for-char line from Step 1) and `local rectOf, scrollShift, screenRectOf, paintedRectIn = geometry.rectOf, geometry.scrollShift, geometry.screenRectOf, geometry.paintedRectIn`. `presentationShift` is `channel.presentationShift` (`presentation_channel.new` is CALLED at `:448` — `:453` is a field inside that call). Verify order: `scrollShift` at `:389` precedes `channel` at `:448`, and `screenRectOf` is declared at `:472`; move the bind line to just after `channel` is built so the closure captures a live function (or forward it call-time: `presentationShift = function(p) return channel.presentationShift(p) end`). `scrollHostOf` is declared at `:335` (`:327-334` is its comment block) above both — fine. Every existing caller keeps its name. Add `require("./rect_reads")` beside `rect_pass`.

- [ ] **Step 4: gates.** `lune run tests/run_one rect_reads_seam` PASS; `tests/lib/renderer_source.luau` `PARTS` += `"rect_reads"` (the source-scan specs read the renderer as parts); `python3 tools/check_source_size.py` (renderer should drop ~2,400; **record the NET delta after stylua in the ledger against R-14's T1 budget of −2,100** — a smaller drop than that is the first signal that T3 needs step 0b); `python3 tools/check_brand_drift.py`; re-record the renderer row in `source-cap-ledger.md` (size, "THE GEOMETRY-READ SEAM IS OUT, 2026-09-03 (Plan C T1)…", next candidate unchanged: the size line); `tools/verify.sh affected --jobs 1`; `tools/test.sh <BASE FACET>`; stylua; RR suite (src changed) + note "no RR rider: pure extraction, byte-identical reads" in the ledger. Commit: `T1: extract the four geometry reads into render/rect_reads (the live seam Plan C changes)`.

---

### Task 2 (C1 step 1b): the solver's translate-arm seam + the pure placement function

**Files:**
- Create: `src/layout/translate_arm.luau`
- Modify: `src/layout/solver.luau` (`translatable` `:2231-2246`, `translateDescendants` `:2248-2301` → deleted; the gate at `:2369` and the call at `:2419` become `translateArm.*` calls; the anchor branch placement `:3226-3234` becomes `placementLib.anchorPlace(...)`; the padding/inner-box block `:2459-2462` becomes `placementLib.innerBox(...)`)
- Modify: `src/layout/placement.luau` (add `anchorPlace`, `innerBox`)
- Modify: `tools/lune/verify/data/source-cap-ledger.md:72` (the SOLVER row — `:59` is the renderer — re-record)
- Test: `tests/translate_arm_seam.spec.luau` (new), `tests/placement_anchor_place.spec.luau` (new); both registered in `tests/run.luau`

**Interfaces:**
- Produces:
  ```luau
  -- src/layout/translate_arm.luau  (NO Deps record: `translatable` is pure over its two
  -- arguments and `translateDescendants` touches only ctx/node/base/was/out — the
  -- `placement.luau`/`recycle_key.luau` precedent, the strongest one-way claim)
  translate_arm.translatable(reuse: any, node: any): boolean
  translate_arm.translateDescendants(ctx: any, node: any, base: Rect, was: Rect, out: { [string]: any }): boolean
  -- src/layout/placement.luau
  placement.anchorPlace(innerX, innerY, innerW, innerH, w, h, wFill: boolean, hFill: boolean, anchor: string?, offsetX: any, offsetY: any)
      -> (x: number, y: number, w: number, h: number, unknownAnchor: boolean)
  placement.innerBox(x: number, y: number, w: number, h: number, pt: number, pr: number, pb: number, pl: number)
      -> (innerX: number, innerY: number, innerW: number, innerH: number)
  ```
  `innerBox` is the second half of the same anti-divergence ruling (review IM-3): the lane needs `innerX/innerY/innerW/innerH` exactly as the solver derives them at `solver.luau:2459-2462`, and a hand-written second copy is where the `math.max(0, …)` clamp drifts. It is the solver's own four lines, verbatim, called by the solver's padding block AND by the lane's `innerBoxOf`. Zero Deps, like everything else in `placement.luau`.
  `anchorPlace` is the ONE copy of the corner-anchor maths (`ox = offsetPx(offsetX, innerW)`, `oy = offsetPx(offsetY, innerH)`, `offsetFill` on a fill axis, `x = innerX + roundPx((innerW - w) * f[1]) + ox`, `y = …`); the solver's anchor branch and T5's lane both call it. `unknownAnchor` is true when `anchor` names no factor (the solver files its diagnostic and falls back to topLeft exactly as `:3197-3201` does today).
- T3 changes the arm inside `translate_arm.luau`; T5 calls `anchorPlace`.

- [ ] **Step 1: red.** `tests/placement_anchor_place.spec.luau`: pins for each of the nine anchors on a 100x50 child in a (10,20,300,200) inner box with `offsetX = 5, offsetY = -3`, computed by hand (e.g. `center` → `x = 10 + roundPx((300-100)*0.5) + 5 = 115`, `y = 20 + roundPx((200-50)*0.5) - 3 = 92`); a fill-width child with `offsetX = 30` under `topLeft` → `w = offsetFill(300, 30, 0) = 270`; a `{ scale = 0.5, offset = -9 }` offset → `offsetPx` → `roundPx(150 - 9) = 141`; an unknown anchor → `unknownAnchor = true`, placed as `topLeft`. **`innerBox` (IM-3):** pins for a padded box (`innerBox(10, 20, 300, 200, 4, 6, 8, 12)` → `22, 24, 282, 188`) and the clamp case (`innerBox(0, 0, 10, 10, 20, 20, 20, 20)` → `20, 20, 0, 0`, not a negative), PLUS the anti-divergence pin the ruling asks for: drive a padded Anchor, a `{ scale, offset }` offset and a fill-parent child through the SOLVER (a hand-built world, reading `controller.rectOf` of the child) and through `anchorPlace(placement.innerBox(...))` called directly, and assert the two agree — that pin is what keeps R-1's "one copy" true after the lane starts calling both. `tests/translate_arm_seam.spec.luau` from `stack_seam.spec.luau`'s skeleton: the module has NO `Deps` (`rawget(mod, "Deps") == nil` and the source declares no `export type Deps`), reads `reuse.dirtyContains`, `reuse.previous`, `node.children`, `child.id`/`child.kind` (closed sets via `fieldsRead`), and WRITES exactly `{ "ctx.rectInserts", "ctx.translated" }` (the widened assertion the S1 brief names — NOT stack's empty set) with index writes only into `out[...]`, `paths[...]`, `entries[...]`; solver contains the char-for-char lines `translateArm.translatable(reuse, node)` and `translateArm.translateDescendants(ctx, node, rect, tprev.rect, out)` and NO remaining `local function translatable`/`local function translateDescendants`; negative controls for each scan. Both red.

- [ ] **Step 2: `placement.innerBox` + `placement.anchorPlace`.** Append to `placement.luau`:

```luau
-- THE INNER (CONTENT) BOX, ONE COPY (Plan C, T2 — review IM-3). `arrange` derives
-- it at the padding block and the translate lane needs the identical four numbers
-- to place a host the way the solver would have; the `math.max(0, …)` clamp is
-- exactly the kind of detail a second hand-written copy loses.
function placement.innerBox(
	x: number, y: number, w: number, h: number,
	pt: number, pr: number, pb: number, pl: number
): (number, number, number, number)
	return x + pl, y + pt, math.max(0, w - pl - pr), math.max(0, h - pt - pb)
end

```

and, in the solver's padding block, `local innerX, innerY, innerW, innerH = placementLib.innerBox(rect.x, rect.y, rect.w, rect.h, pt, pr, pb, pl)` in place of the three derivation lines (the long "THE PADDING FACTS ARE COMPUTED BEFORE THE LEAF RETURN" comment stays where it is — it explains the POSITION of the block, not the arithmetic). Then:

```luau
-- THE CORNER-ANCHOR PLACEMENT, ONE COPY (Plan C, T2). The solver's anchor branch
-- and the translate lane (`render/translate_lane`) both place a child from the same
-- eleven inputs, and a second hand-written copy is how the two would start
-- disagreeing by a rounding. `unknownAnchor` reports a factor lookup miss so the
-- caller files the diagnostic the solver always filed; the placement falls back to
-- `topLeft` exactly as it did.
function placement.anchorPlace(
	innerX: number, innerY: number, innerW: number, innerH: number,
	w: number, h: number, wFill: boolean, hFill: boolean,
	anchor: string?, offsetX: any, offsetY: any
): (number, number, number, number, boolean)
	local f = placement.ANCHOR_FACTORS[anchor or "topLeft"]
	local unknown = f == nil
	if unknown then
		f = placement.ANCHOR_FACTORS.topLeft
	end
	local ox = placement.offsetPx(offsetX, innerW)
	local oy = placement.offsetPx(offsetY, innerH)
	if wFill then
		w = placement.offsetFill(innerW, ox, f[1])
	end
	if hFill then
		h = placement.offsetFill(innerH, oy, f[2])
	end
	local x = innerX + roundPx((innerW - w) * f[1]) + ox
	local y = innerY + roundPx((innerH - h) * f[2]) + oy
	return x, y, w, h, unknown
end
```

Rewire the solver's anchor branch (`:3197-3201` + `:3226-3234`):

```luau
			local x, y, pw, ph, unknownAnchor = anchorPlace(
				innerX, innerY, innerW, innerH, w, h,
				dim(child, "w").type == "fill", dim(child, "h").type == "fill",
				child.anchor, child.offsetX, child.offsetY
			)
			if unknownAnchor then
				table.insert(ctx.diagnostics, { node = child.id, issue = `unknown anchor '{child.anchor}'` })
			end
			arrange(ctx, child, { x = x, y = y, w = pw, h = ph }, out)
```

with `local anchorPlace = placementLib.anchorPlace` beside `:2070-2072`. Keep the two long comment blocks (`offsetFill` give-back, "resolved ONCE") — move them onto `anchorPlace` in `placement.luau`, not deleted.

- [ ] **Step 3: `translate_arm.luau`.** Move `translatable` + `translateDescendants` verbatim (comments included) into the module with `ctx: any, node: any` parameter types (stack's precedent; the solver's `Ctx`/`Node`/`Rect` types are erased at runtime and importing them would name a solver symbol). Preamble states the NO-Deps claim and the two ctx counter writes. Solver: `local translateArm = require("./translate_arm")`; `:2369` → `… and translateArm.translatable(reuse, node) then`; `:2419` → `if translateArm.translateDescendants(ctx, node, rect, tprev.rect, out) then`. `literalIsWholeEntry`/`selfPlaces` stay in the solver (they are the ROOT's gate, not the subtree's).

- [ ] **Step 4: gates.** Both new specs PASS; `lune run tests/run_one translate_arm` (the 1,529-line O3 spec) PASS unchanged — it is the byte-identical proof; `check_source_size.py` (solver −~3,000); `check_brand_drift.py`; ledger solver row re-record ("THE TRANSLATE ARM IS OUT, 2026-09-03 (Plan C T2)…; next candidate still the SCROLL arrange branch"); `verify.sh affected --jobs 1`; `test.sh <BASE FACET>`; stylua; RR suite. Commit: `T2: extract the translate arm (layout/translate_arm) and the corner-anchor placement (placement.anchorPlace)`.

---
### Task 3 (C1 steps 2-5): the per-host rect space

The mechanism, end to end, so every site edit below is one sentence:

- **Who is a space.** `instance_boundary.createOptsFor(node, opts)` gains a third branch, and an explicit REFUSAL above it. Refuse (`return nil`, no host at all from this branch) when `node.class == "ScrollView"` or `props.clipChildren == true` — the two adapter-side host triggers (`screen_target.luau:1484-1487`) — or when `opts.translateHosts == false`. Otherwise: `node.dynamicProps` carries `offsetX`, `offsetY` or `anchor` (the REACTIVE fact — `node.props` already holds the resolved value by the time this runs, S3 §2) AND `#node.children > 0` → `{ instanceHost = true, hostSpace = true }`. There is **no Composition scan** (R-8 is dead; R-13 makes compositions exact under a host by carrying the origin). The scale/rotation branch stays ABOVE it and unchanged (R-2: a rotated container with a reactive offset is a plain host; it moves through the ordinary arrange path, stated in the ledger).
  - The ScrollView/clipChildren refusal is R-2's IMPLEMENTATION, not a restatement of it (review BL-1): `offsetX`/`offsetY`/`anchor` are `shared = true` props (`src/blueprint_schema.luau:763-780`), so `UI.ScrollView({ offsetX = signal, children = … })` and `UI.VStack({ clipChildren = true, offsetY = signal, children = … })` both reach this branch today. If a ScrollView became a space host, `scroll_into_view.luau:104-117`'s `targetRect.y - hostRect.y` would subtract a parent-relative host from a host-relative target and mean nothing — the exact reader R-2 says must not move.
  - **KNOWN LIMIT, shared with the scale/rotation trigger (review IM-7):** `#node.children > 0` is read once, from `ensureTree`, and mount nodes start with `children = {}` (`mount.luau:624`) with regions mounting children later — so a container that is EMPTY at create time and gains children through a `When` never becomes a host. It stays correct (it is simply not a host); it is stated here so nobody reads a missing host as a bug.
  - `opts.translateHosts` comes from `RendererAttachOpts.translateHosts: boolean?` (default true; an internal flag beside `commitScope`), threaded to `createOptsFor`. It exists for the oracle's arm `e` (review IM-1) and is the only supported way to turn the fifth trigger off.
- **How the solver learns it.** `ensureTree` (`renderer.luau:1007`) stamps `node.hostSpace = createOpts ~= nil and createOpts.hostSpace == true or nil` on the MOUNT node right after computing `createOpts`; `layout_node.toLayoutNode`'s literal (`:548-612`) copies `hostSpace = node.hostSpace` (a warm store hit returns `hit.built` without re-running the literal — fine, the flag is fixed for the node's lifetime; a REMOUNT gets a fresh mount node, a fresh createOpts and a fresh layout node).
- **What the solver does with it** (`arrange`): the node's OWN entry keeps the rect it was handed (parent-space); its BODY runs against `{ x = 0, y = 0, w = rect.w, h = rect.h }` — one `if node.hostSpace then rect = ORIGIN_OF(rect) end` before the per-kind branches read `rect.x/rect.y` (the padding block's `placementLib.innerBox(rect.x, rect.y, …)` is the first read; put the rebind immediately above it — no read of `rect.x`/`rect.y` survives past that block, only `rect.w`/`rect.h`). The translate arm: `tdx, tdy` are still computed against the parent-space rect; on a `hostSpace` root the arm records the root as a move (`entry.moveOnly`, `entry.prev`, `translatedRoots[node.id] = { dx, dy, from, to = from - 1 }` — an EMPTY run) and does NOT call `translateDescendants` — the descendants' rects are relative and unchanged. Rollback bookkeeping is untouched (nothing was written). One comment on the empty-run write (review MI-6): **`translatedRoots` is KEYED by `node.id` (`solver.luau:2420`) and LOOKED UP by `node.path` (`rect_pass.luau:198`)** — they coincide today, and the empty run inherits that coupling; say so at the write so the next reader does not have to re-derive it.
- **The absolute origin travels with the walk (ruling R-13).** `arrange` carries `ctx.spaceOX`/`ctx.spaceOY`, pushed and popped in a four-line WRAPPER around the renamed `arrangeBody` so no branch's early `return` can skip the pop (T3 step 5 has the code). There is no per-node `spaceOrigin` map. One consumer inside the solver, and two absolute-rect producers outside it:
  - **`composition_resolve` takes ORIGIN NUMBERS, not a rect.** Its signature is `resolve(deps, ctx, node, innerW, innerH, originX?, originY?)` (`composition_resolve.luau:153-161`) and it falls back to `ctx.rootRect` when they are absent (`:187-188`, which is also where `atRoot` is decided and the cache keyed on `{placedX},{placedY}`). It has TWO callers: `solver.luau:2702` — the ARRANGE-time one, today `resolve(COMPOSITION_DEPS, ctx, node, innerW, innerH, innerX, innerY)` — which becomes `resolve(COMPOSITION_DEPS, ctx, node, innerW, innerH, innerX + ctx.spaceOX, innerY + ctx.spaceOY)`; and `solver.luau:1386` in `measure`, which passes NO origin and is **UNCHANGED** — measure runs before any position is known, so its fallback was already position-blind, and the arrange-time re-resolve with the shifted origin is what lands, exactly as the file's own `:174-181` argument relies on. The T3 implementer still reads `composition_resolve.luau` and LISTS in the ledger any window-space read that does not go through those two origin numbers (a further `ctx.rootRect` read or an absolute map is a finding, not a detail).
  - **The absolute-rect audit: ONE named producer, ONE line — `tests/lib/large_text.auditRects`.** `text_audit.luau` is NOT modified and has no `originOf` in its `opts`. The reason is measured, not guessed: **`text_audit` is never required from `src/` or `tools/`** (every hit there is prose in a comment), and the two functions this plan previously named — `outOfBounds(rects, bounds, opts)` `:583` and `focusVisibility(focus, viewports)` `:517` — are called ONLY from `tests/text_audit.spec.luau` on hand-built literal rect maps that never see a solve. **They have no live producer; do not go looking for one.** The RR canary's "0 Facet quarantines / diagnostics racing 0" comes from `controller.diagnostics()`, the solver channel, not from `text_audit` at all.
    The real exposure is `tests/lib/large_text.auditRects` (`tests/lib/large_text.luau:220-244`), which builds `out[path] = { rect = node.rect, … }` from `w.adapter.node(path).rect` — the adapter's STORED rect, precisely what T3 makes host-relative — and hands it to `audit.overlaps`, `audit.clippedEssential` and `audit.hitFloor` through `large_text.sweep` (`:253-266`). The edit is one line:

```luau
		out[path] = {
			-- COMPOSED, NOT STORED (Plan C, T3). `node.rect` is the adapter's stored
			-- rect, which beneath a coordinate-space host is host-relative; every
			-- check below (`overlaps`, `clippedEssential`, `hitFloor`) compares rects
			-- of nodes that may sit in DIFFERENT spaces, so it reads the composed one.
			-- `rectOf`, NOT `screenRectOf`: `rectOf` is the solver-space composition
			-- and returns today's exact number, while `screenRectOf` would add the
			-- scroll and presentation shifts this audit never had.
			rect = w.controller.rectOf(path),
```

    What gates on it is the **large-text device-matrix specs** (`tests/large_text_*.spec.luau`), which is where a regression would surface; arm `e` (IM-1) is the framework-side proof, comparing `diagKey` after every step so the no-host world files the same findings.
- **What the renderer stores.** `lastRects[path]` is whatever the solver emitted — host-relative beneath a space host. `rect_reads.hostSpaceOf[path]` = nearest `hostSpace` ancestor, threaded on `livePaths` exactly like `scrollHostOf` (`:1449-…`: a sixth parameter `space: string?`, `nextSpace = if node.hostSpace then node.path else space`), cleared at `structuralSync`'s whole-tree arm and at `dispose` via `geometry.clearHosts()`, and re-threaded per root as `geometry.hostSpaceOf[r.path]`. `spaceHosts` is the `{ [path]: true }` set the same walk fills. `restoreParkedProps` (`:1581`) carries `rect` ONLY when `hostSpaceOf[old] == hostSpaceOf[new]` — else `lastRects[new] = nil` (one spare `setRect` on a cross-space recycle, stated).
- **Origin-cache invalidation is hooked at EVERY writer, not one (review IM-8).** `lastRects` has three writers, and the epoch is one integer, so the rule is blunt on purpose: `geometry.invalidateOrigins()` is called (a) once per commit **unconditionally**, at the top of `rectPass.apply` — not per-path inside `applyOne`, which is both the hot loop and only one of the writers; (b) from the translate lane's `apply` (T5); (c) from `restoreParkedProps`, which writes `lastRects[path] = carried.rect` directly (`renderer.luau:1580-1581`). And **`geometry.dropPath(path)` is called from `sweepDeparted`** for every departed path (clearing `hostSpaceOf`, `spaceHosts`, `originCache`, `composedCache`), because the BOUNDED structural arm never calls `clearHosts()` — without it the caches keep entries keyed by paths whose hosts were removed or re-created. The bounded arm calls `geometry.invalidateOrigins()` as well.
- **The adapter rule.** `applyRect`'s `ox, oy = handle.instanceHost.rect.x/y` is space-invariant when host and child share a space, so the ONLY change is: a space host's children are ALREADY relative → `ox, oy = 0, 0` when `handle.instanceHost.hostSpace == true`. Three sites (`applyRect:338-341`, `applyHitExpander:302-305`, the focus-ring float `:416-417`) — factor ONE local `hostOriginOf(handle): (number, number)` in `screen_presentation.luau` and call it at all three. `registerHost(path, instance, rect, crops)` gains a fifth arg `hostSpace: boolean?` stored on the entry; `screen_target.luau:1252` passes `createOpts.hostSpace == true`. **`registerHost` is create-OR-REUSE and the reuse path returns early** (`screen_presentation.luau:153-162`: `existing.crops = existing.crops or crops; return existing`) — so the reuse path must OR the new flag the way it ORs `crops`: `existing.hostSpace = existing.hostSpace or hostSpace` (review BL-1). A path can be registered twice (the adapter's own ScrollView/clipChildren registration, then `createOpts.instanceHost` at `screen_target.luau:1252`), and if the flag were lost on the second call `applyRect` would subtract the host rect from children whose rects are ALREADY relative — every child landing at `rect − host`. `registerFakeHost` gets the identical OR. `screen_target.setRect:2098-2105`: a space host does NOT join `movedHosts` (its children need no re-base — `settleRects` would re-apply O(children) `applyRect`s per moved host per tick for nothing). Fake target: `registerFakeHost(path, crops, hostSpace)`; `_composePresentation` computes `presentedPosition = rect + Σ(space-host ancestors' rects) + transforms` — walk `hostFor` chain: `local h = node.instanceHost; while h ~= nil do if h.hostSpace then ox += h.rect.x; oy += h.rect.y end; h = hostFor(h.path) end` (a non-space host contributes nothing: its children's rects are absolute in ITS space, which is the same space its own rect is in); the T0 engine-write mirror uses `hostOx = 0` for a space host.
- **The fake must RECOMPOSE the subtree on a space-host `setRect` (review BL-4).** `_composePresentation` is called from `create`, `setRect`, `adopt` and the `transform` prop branch — and only the `transform` branch recomposes the whole subtree (`fake_target.luau:716-721`: `for path, node in nodes do if prefix match then recompose`). Under Plan C a host move produces exactly ONE `setRect` (the host) and zero for its descendants — that is the point — so every descendant's `presentedPosition`/`presentedSize` would keep its pre-move value **forever**, and arm `a` and arm `c` would go stale identically (arm `c` also skips the writes: `rect_pass.applyOne` compares by value). The `pos=` column would then be GREEN while the fake diverged from an engine that reparents for free. So: in `adapter.setRect`, when `instanceHosts[handle.path]` exists and is a `hostSpace` host, mirror the `transform` branch's loop and recompose every node whose path has `handle.path .. "/"` as a prefix. Two instruments guard it: the T3 step 8 oracle asserts **`pos == sro` as an IDENTITY inside `snapshot()`** (the line carries `POSMISMATCH` otherwise) — an instrument that cannot go stale in step with itself — and the negative control below.
- **Composers — and WHICH origin function each one gets.** Everything that compares rects of nodes that may sit in DIFFERENT spaces composes an origin, and **the choice between `hostOriginOf` and `originIn` is decided by WHICH MAP the composer is reading, not by taste** (the BL-5 lesson, which applies at three sites, not one): `hostOriginOf` walks `lastRects` — LAST frame — so it is correct only where the composer's own map is `lastRects`.
  - **FRESH-MAP composers get `originIn`, through one per-commit closure.** Build it once at the top of the commit span: `local originOf = function(p) return geometry.originIn(result.rects, p) end`, and hand `originOf` to (a) `hit_lift.refresh` (defined at `:138`; the two overlap tests are `:141-150` — compose `hit`, `hostEntry.rect`, `entry.rect`; the module "depends on nothing" and stays that way: a function argument) — its rect argument is `result.rects`, the solve's own map (`renderer.luau:2183`); and (b) `commitWalks`' ctx, for `authorPressableRects` (`:1099-1112`, which reads `local other = rects[path]` off the COMMIT walk's map at `commit_walks.luau:1104-1106`) and the `growWithin` call site at `:1170`, which passes the entry's path. **The `r` in `growWithin` is NOT composed** (review MI-3): it is already the entry's own rect, in the entry's space, and B-3 below composes INTO that space — the composition is on the sink rects alone.
    **Composed into the ENTRY's space, NOT window space (review B-3) — so `want` and the stored rect never leave it.** `growWithin(r, want, authorPressableRects())` RETURNS `want` (`commit_walks.luau:1160-1169`), and `want` is what goes to `setHitRect` and into `lastHitRects`, which the hitRects bullet below requires to be in the entry's space (`applyHitExpander` subtracts the host origin, → 0 under a space host). Composing the sinks to window space while leaving `want` raw compares mismatched spaces; composing `want` too makes `growWithin` hand back a window-space rect that the adapter then re-bases a SECOND time. Either way a space host's chrome expander is wrong by the host origin. So `authorPressableRects` takes the entry's path and offsets each sink rect by `originOf(sinkPath) − originOf(entryPath)`: `r`, `want`, `growWithin`'s output and the stored entry all stay in the entry's space, and `setHitRect`'s contract is untouched. Both run INSIDE the commit walks — before `lastRects` is rewritten, as the renderer's own comment at `:2186-2190` says of `installAnimationRecords` — so handing them `hostOriginOf` would compose this solve's expanders and sinks against last frame's host origin: the exact one-frame lag BL-5 forbids, at a second and third site.
  - **`lastRects` composers keep `hostOriginOf`:** `controller.coverRect` (`renderer.luau:3856` — its map really is `lastRects`) and `scroll_into_view.luau:104-117` (compose `hostRect` and `targetRect` before subtracting).
  - **`surface_overlap.coverRect` takes the FOUR-ARGUMENT form, settled** (review N-16 — the plan had said "build the union over `rectOf(path)` **or** pass `originOf`", and an either/or is not a plan): `coverRect(rootPath, lastRects, paintsNothing, originOf)` where `originOf` is `geometry.hostOriginOf`. No union-over-`rectOf` variant, and no "computed on demand" variant either — T5's channel table says the same thing.
  - No change, stated: `presentation_channel.luau:78,587` (same node, same space). `selection_indicator.luau:73/679-690` — raw `rectOf` on nodes that share a parent: composition cancels; the comment's reasoning is re-derived in one added sentence and PINNED (below).
- **hitRects walk** (`commit_walks:996-1193`): `want` is computed in the entry's space and handed to `setHitRect`; `applyHitExpander` subtracts the host origin → 0 under a space host → consistent. No change but the pin.

**Files:**
- Modify: `src/render/instance_boundary.luau` (`createOptsFor` `:72-103` gains the ScrollView/`clipChildren`/`translateHosts` refusal + the third branch, `CreateOpts` `:65`; NO `hasComposition` — R-8 is dead)
- Modify: `src/render/renderer.luau` (`RendererAttachOpts.translateHosts` beside `commitScope`, threaded into `createOptsFor`; `ensureTree` `:1007` stamp; `livePaths` `:1449` thread; `structuralSync` clears `:2622-2643`, thread `:2639-2643`; `dispose` `:3996`; `restoreParkedProps` `:1581` (guard + `invalidateOrigins`); `sweepDeparted` calls `geometry.dropPath`; `rect_pass.new` ctx `:1632-1640` gains `invalidateOrigins`; **the per-commit `local originOf = function(p) return geometry.originIn(result.rects, p) end` built once at the top of the commit span and handed to BOTH `hitLift.refresh` (`:2183`) and `commitWalks`' ctx** — fresh map, review N-3; `controller.coverRect` (`:3856`) keeps `geometry.hostOriginOf`, whose map really is `lastRects`)
- Modify: `src/render/layout_node.luau` (node literal `:548-612`: `hostSpace = node.hostSpace`)
- Modify: `src/layout/solver.luau` (`arrange` `:2329` renamed `arrangeBody` with an ANNOTATED forward local `local arrange: (Ctx, Node, Rect, { [string]: any }) -> ()` — `--!strict`, review MI-4 — plus the four-line push/pop wrapper; **its twelve recursive call sites AND `solve`'s root call at `solver.luau:3585` all keep the name `arrange`, which is what makes a hostSpace ROOT push its own origin too** (review MI-5); the origin rebind inside `arrangeBody`; the ARRANGE-time `compositionResolve.resolve` call at `:2702` gaining the shifted ORIGIN NUMBERS — the `measure`-time call at `:1386` is UNCHANGED — and the arm's host-root branch; `Ctx` gains `spaceOX`, `spaceOY` and NOT `spaceOrigin`; `Node` type `:146` gains `hostSpace: boolean?`)
- Modify: `tests/lib/large_text.luau` (`auditRects` `:220-244`: `rect = w.controller.rectOf(path)` replaces `rect = node.rect` — the ONE line, review B-1). **`src/layout/text_audit.luau` is NOT modified** and gains no `opts.originOf`: it is never required from `src/` or `tools/`, and `outOfBounds`/`focusVisibility` are called only from `tests/text_audit.spec.luau` on hand-built literal maps.
- Modify: `src/layout/dump.luau` (`nodeDump` `:11-51`: it emits `rect = entry and entry.rect` — the SOLVER's entry rect, host-relative under a space host — and it already RECURSES over the `solver.Node` tree, so it composes with its own two-number accumulator: `nodeDump(node, rects, ox, oy)`, `if node.hostSpace then ox, oy = ox + r.x, oy + r.y end` computed from the node's own entry BEFORE descending, and `rect = if ox == 0 and oy == 0 then entry.rect else { x = entry.rect.x + ox, … }`. `dump.fromSolve` passes `0, 0`.)
  **DECISION, from the source (the question B-1's ruling left open): `ctx.spaceOrigin` is DELETED from this plan — it has no reader.** `dump` receives `result.rects` from `solver.solve` and never sees a `ctx`, so it could not read the map even if it existed; it recurses over the Node tree and already has `node.hostSpace`, so a two-number accumulator is both cheaper and self-contained — the same shape `arrange` uses. `ctx.spaceOX`/`ctx.spaceOY` REMAIN (the `composition_resolve` call site reads them); the per-node `spaceOrigin` map does not.
- Read (no edit unless the audit finds one): `src/layout/composition_resolve.luau` — confirm every window-space read goes through the two origin numbers `resolve` is handed (`:187-188`), and list any that does not in the ledger. The CALLER is what changes (`solver.luau:2702`), not this file — R-13.
- Modify: `src/layout/translate_arm.luau` (no change — the skip is at the CALL in `arrange`; state it)
- Modify: `src/render/rect_pass.luau` (`apply`: `ctx.invalidateOrigins()` once at the top, unconditionally — review IM-8; `applyOne` `:83-96` unchanged)
- Modify: `src/render/hit_lift.luau` (`refresh` — defined at `:138` — gains the `originOf` argument; the two overlap tests are at `:141-150`)
- Modify: `src/render/commit_walks.luau` (`authorPressableRects` `:1099-1112` — it reads `local other = rects[path]` off the COMMIT walk's own map at `:1104-1106` — and the `growWithin` call `:1170`; ctx gains `originOf`, the FRESH-map closure, not `hostOriginOf`; `authorPressableRects` gains the ENTRY's path and offsets each sink by `originOf(sink) − originOf(entry)`, so `want` and the stored rect stay in the entry's space — review B-3)
- Modify: `src/render/surface_overlap.luau` (`coverRect` `:145` → `coverRect(rootPath, rects, excluded, originOf)`, the settled four-argument form; its caller's map is `lastRects`, so it is handed `geometry.hostOriginOf`)
- Modify: `src/render/scroll_into_view.luau` (`:104-117`; `Deps` gains `hostOriginOf` — its map is `lastRects`)
- Modify: `src/client/screen_presentation.luau` (`registerHost` `:153-162` — the fifth arg AND the reuse-path OR; `applyRect` — declared `:333`, body to ~`:429`, the re-base at `:338-341`, the focus-ring float at `:416-417`; `applyHitExpander` `:302-305`; the "THE INSTANCE TREE IS FLAT" prose `:220-228`)
- Modify: `src/client/screen_target.luau` (`:1252` registerHost arg; `setRect` `:2098-2105`; the `elided` comment `:2079-2082`; the FOUR-triggers prose `:1484-1487` → five)
- Modify: `tests/lib/fake_target.luau` (`registerFakeHost` `:199-212` — the `hostSpace` arg AND the reuse OR; create `:405-409`; `_composePresentation` `:466-522`; **`setRect`'s subtree recompose for a space host, mirroring the `transform` branch at `:716-721`** — review BL-4; T0's mirror)
- Modify: `tests/lib/nameplates_scene.luau` (`snapshot()` `:442-461` — `:427-440` is `ser` — the new channels, the `diagKey` column, and the `pos == sro` identity assertion; **`Opts.hosts` (default true) threading `RendererAttachOpts.translateHosts` into `renderer.attach`** — the arm-`e` flag, review IM-1)
- Modify: `tests/host_move_write_cost.spec.luau` (its own header is stale: it is **six** cases, not four. Fixture: a SPACE host's kids carry host-relative rects; keep the six control cases; T3 step 9 rebuilds it as a 9-view loop over three fixtures — review IM-2)
- Modify: `tests/instance_hosts.spec.luau` (`:274` `hostCount() == 3` — unchanged: static blueprints; **`:273`'s `expect(adapter.isHost("/S/Plain")).toBe(false)` is THE elision tripwire** — its own comment at `:269-272` says "THE ONE THAT KEEPS ELISION ALIVE" — and the fifth trigger is precisely "a plain container becomes a host", so that pin is the one to watch and to name in the ledger (review MI-4). ADD cases: "a reactive placement on a container with children is the fifth trigger; on a LEAF it is not"; "a `ScrollView` with a reactive `offsetX` is NOT a space host"; "a `VStack{ clipChildren = true, offsetY = signal }` is NOT a space host"; "a double `registerHost` keeps `hostSpace`" — driving `screen_presentation.registerHost` twice for the same path, once with the flag and once without, in either order)
- Modify: `tests/translate_arm.spec.luau` — **TWO edits, and the second is a LOAD-TIME breakage the rename causes (review D-1):**
  1. **The `ARRANGE_SOURCE` scan at `:227` must be renamed with the function.** It reads `local from = body:find("local function arrange%(ctx", 1)` at MODULE scope; after `arrange` becomes `arrangeBody` the pattern misses, `from` is `nil`, and `string.sub(body, nil, to)` ERRORS — the whole spec fails to LOAD, taking `stampsAfterLiteral`, `LITERAL_AT` and both prop audits with it. Change the pattern to `"local function arrangeBody%(ctx"`, and the header prose at `:923` ("from `local function arrange` to `function solver.solve`") to `arrangeBody`. The scanned span now also contains the four-line `arrange` wrapper, which is **harmless**: `stampsAfterLiteral` matches only `out[node.id].<field> =` and `^\t\tentry.<field> =`, and the wrapper has neither. Do NOT "fix" it by narrowing the scan — that spec's own header (`:227-240`) is a warning about exactly that failure mode. T2 step 4 calls this spec the byte-identical proof and T3 step 11 runs the full gate set, so without this edit the breakage surfaces in T3.
  2. `:157` `rectWrites == 1500` → `PLATES`; `:148` child adapter delta → `dx=0 dy=0` at the adapter (host-relative) while `presentedPosition` delta stays `3,2` — the header gains the new arithmetic paragraph.
  **NOT affected, checked:** the spec's two other solver reads — `:466` (`selfArrangeKey`) and `:975` (`literalIsWholeEntry`) — match different symbols; and `tests/commit_scope.spec.luau:1276` matches the CALL text `arrange(`, which every one of the twelve recursive sites and `solve`'s root call still keep., `tests/nameplates_baseline.spec.luau:172` (`rectWrites` 4502 → `1502 + 250 + 250`), `tests/commit_translate.spec.luau:123-125`
- Modify: `tools/lune/check_elision_census.luau` (add `TRANSLATED` fixture beside `ROTATED` `:116`, exact pin read off the run)
- Create: `tests/translate_host.spec.luau` (the C1 demonstrator + the reader-audit pins), `tests/host_space_oracle.spec.luau` (the extended oracle)
- Register both in `tests/run.luau`; `tests/lib/tiers.luau`: the oracle joins the fast-tier exclusions if `lune run tools/lune/time_specs` puts it over `THRESHOLD_MS`.

**Interfaces:**
- Consumes: T1's `geometry.*`, T2's `translateArm.*`, T0's `engineWrites`.
- Produces: `CreateOpts = { canvasGroup: boolean?, instanceHost: boolean?, hostSpace: boolean? }`; `RendererAttachOpts.translateHosts: boolean?` (default true); `instance_boundary.createOptsFor(node, opts)`; mount node field `hostSpace: boolean?`; layout `Node.hostSpace: boolean?`; `ctx.spaceOX`/`ctx.spaceOY` on the solver ctx (no `spaceOrigin`); `arrangeBody` + the `arrange` wrapper; host registry entries carry `hostSpace: boolean?`; `geometry.hostSpaceOf`/`geometry.spaceHosts` populated; `geometry.dropPath(path)` wired to `sweepDeparted`; the per-commit `originOf(path)` closure over `geometry.originIn(result.rects, …)`; `hit_lift.refresh(rects, hitRects, sinks, parentNodeOf, hidden, originOf)` (fresh-map `originOf`); `commit_walks` ctx `originOf` (fresh-map) with `authorPressableRects(entryPath)` composing into the ENTRY's space; `surface_overlap.coverRect(rootPath, rects, excluded, originOf)` (handed `hostOriginOf`, map = `lastRects`); `scene.snapshot()` lines carry `|pos=x,y|psize=w,h|focus=<focused>,<profile>,<lift>|ro=x,y,w,h|sro=x,y,w,h` (with `pos == sro` asserted as an identity).

- [ ] **Step 0 (ruling R-15 — BEFORE anything in this task touches `src/`): the RR literals at HEAD.** A HEAD literal cannot be read after HEAD has moved, so this is a T3 prerequisite, not a T4 step. Create RR `tests/facet_translate_host_contract.spec.luau` (register it in RR `tests/run.luau`), mount `MapCanvas` at 8 dots exactly as `tests/facet_commit_translate.spec.luau:132-162` does, drive `dotsAt(n, phase)` twice, and pin as literals READ OFF THE RUN at RR `07d1a18` + Facet `a46f84c4`: `controller.screenRectOf` and `rectOf` of `…/Markers/Dots/[<key3>]/Dot`, `…/Dot/DotHit`, and the name tag `…/Dot/NameTagRegion/then/NameTag` (with `showNameTags` on); `adapter.hostCount()` (today: the ScrollViews/clip hosts on that surface — read it); `adapter.node(dot).presentedPosition`; and a dots-only frame's `rectWrites` delta. Also the `Ticker` compact strip (`stripOffsetY` memo) and `StartCountdown` — one `screenRectOf` pin each, mounted the way their existing specs mount them (grep RR tests for `Ticker` and `StartCountdown`). Commit the RR spec on its own (it is green at HEAD by construction).

- [ ] **Step 0b (ONLY if R-14's budget says so): `src/render/dirty_closure.luau`.** Run `check_source_size.py` before starting step 1. If the renderer is above 196,100 after T1 — i.e. T1 did not net its −2,100 — extract the pure `dirtyClosure(dirty) -> (contains, measures)` block (`renderer.luau:2988-3025`) into `src/render/dirty_closure.luau` in its OWN commit, with a seam spec copied from `tests/rect_reads_seam.spec.luau` (it is a function of its argument alone: no `deps`, no upvalue). ~2 KB of headroom, bought before it is needed rather than in an emergency.

- [ ] **Step 1: the reader-audit table in the ledger, BEFORE code.** Write to `.superpowers/sdd/2026-09-03-facet-parity-C/progress.md` a table with one row per reader in S2 §8 (all of §8.1 and §8.2, incl. `drag_registry`'s aliased `rectOf`, `surface_lifecycle:573`, `slider:530-558`, `table*`, `level_picker`, `text_input`, `virtual_*`, `region_expand`, `modal_zones`, `catchers`, `presentation_channel:78,587`, `restoreParkedProps`, `hit_lift`, `authorPressableRects`, `coverRect`, `scroll_into_view`) **plus the three ABSOLUTE readers ruling R-13 exists for — `composition_resolve`'s `atRoot`/cache key (served by the `ctx.spaceOX/spaceOY` carry at its arrange-time call site), `tests/lib/large_text.auditRects` and `layout/dump.luau`'s `nodeDump` (each composed at the producer, one line)**: verdict `composes via rectOf/screenRectOf (no edit)` / `same space by construction (no edit, pinned)` / `must compose (edited in this task)` / `absolute reader: origin carry` / `absolute reader: composed at its producer`. Every row that is not "no edit" names its pin in `tests/translate_host.spec.luau` (or, for the absolute readers, the arm-`e` `diagKey` comparison in `tests/host_space_oracle.spec.luau` and the large-text device-matrix specs). **`text_audit.outOfBounds`/`focusVisibility` get no row: they have no live producer — review B-1.**

- [ ] **Step 2: the red demonstrator.** Create `tests/translate_host.spec.luau`:

```luau
--!strict
--[[ A HOST IS A COORDINATE SPACE (Plan C, C1). A container whose placement is
	REACTIVE and that has children is a real engine parent AND the origin its
	subtree's rects are stored against. A nameplate move is then ONE stored rect
	and ONE engine write; its five descendants' rects do not change in their own
	space, so `rect_pass.applyOne` finds them equal and writes nothing.

	THE PINS AND THEIR ARITHMETIC (fixture: 250 plates x 6 nodes):
	  pure tick      rectWrites 250 (was 1,500) · engineWrites 250 (was 1,500)
	                 solves 1 (the lane, T5, makes it 0)
	  caster tick    rectWrites 250 + 50 (the Cast bar resized) · engineWrites 250 + 50
	                 (a Size write, not a Position write — READ OFF THE RUN)
	PUBLIC NUMBERS DO NOT MOVE: `rectOf`/`screenRectOf` for plate 7's Name leaf at
	tick 2 are the literals below, READ OFF THE RUN AT HEAD `a46f84c4` BEFORE this
	task and kept by construction (composition on read). ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")

local PLATES, CASTERS = scene.PLATES, scene.PLATES // scene.CASTER_EVERY
-- READ OFF THE RUN AT HEAD (probe: mount, tick(3,2) twice, print both reads) —
-- the implementer replaces these four literals with the probe's output BEFORE
-- touching src/, and never after.
local NAME_RECT_AT_HEAD = "x=?,y=?,w=?,h=?"
local NAME_SCREEN_RECT_AT_HEAD = "x=?,y=?,w=?,h=?"

local function fmt(r: any): string
	return if r == nil then "nil" else `x={r.x},y={r.y},w={r.w},h={r.h}`
end

describe("translate host: one write per plate, today's numbers on every read", function()
	it("a pure tick writes one rect and one engine Position per plate", function()
		local s = scene.new()
		s.tick(3, 2) -- warm
		local rw, ew, solves = s.stats().rectWrites, s.adapter.engineWrites(), s.stats().solves
		s.tick(3, 2)
		local st = s.stats()
		expect(`rectWrites={st.rectWrites - rw} engineWrites={s.adapter.engineWrites() - ew} solves={st.solves - solves}`).toBe(
			`rectWrites={PLATES} engineWrites={PLATES} solves=1`
		)
		local name = "/S/Canvas/Plates/[p7]/Plate/Row/Name"
		expect(fmt(s.controller.rectOf(name))).toBe(NAME_RECT_AT_HEAD)
		expect(fmt(s.controller.screenRectOf(name))).toBe(NAME_SCREEN_RECT_AT_HEAD)
		-- THE STORED RECT IS HOST-RELATIVE, pinned as the IDENTITY it actually is
		-- (review MI-3): `stored + the host chain's origin == screenRectOf`. A
		-- threshold ("stored.x < 180") passes on a coincidence and would still pass
		-- if the rect were absolute on a plate that happens to sit near the left edge.
		local stored = s.adapter.node(name).rect
		local hx, hy = 0, 0
		local h = s.adapter.hostOf(name)
		while h ~= nil do
			if h.hostSpace then
				hx, hy = hx + h.rect.x, hy + h.rect.y
			end
			h = s.adapter.hostOf(h.path)
		end
		local sr = s.controller.screenRectOf(name)
		expect(`composed={stored.x + hx},{stored.y + hy}`).toBe(`composed={sr.x},{sr.y}`)
		-- ...and the engine window position is the public one
		local pos = s.adapter.node(name).presentedPosition
		local sro = s.controller.screenRectOf(name)
		expect(`pos={pos.x},{pos.y}`).toBe(`pos={sro.x},{sro.y}`)
		expect(`hosts={s.adapter.hostCount()}`).toBe(`hosts={PLATES}`)
		s.dispose()
	end)

	it("a caster tick adds exactly the Cast bars' writes", function()
		local s = scene.new()
		s.tickWithCasts(3, 2) -- warm
		local rw, ew = s.stats().rectWrites, s.adapter.engineWrites()
		s.tickWithCasts(3, 2)
		local st = s.stats()
		expect(`rectWrites={st.rectWrites - rw} engineWrites={s.adapter.engineWrites() - ew} solves=1`).toBe(
			`rectWrites={PLATES + CASTERS} engineWrites={PLATES + CASTERS} solves=1`
		)
		s.dispose()
	end)
end)
```

plus, in the same file, the reader-audit pins (each one a small hand-built world — the `customFactory.new()`/`environment.new`/`mountLib.mount`/`fake_target.new()`/`renderer.attach` idiom every spec uses, e.g. `tests/layout_prop_dirt.spec.luau:395-422`): (a) **hit expander under a moved host vs a sibling outside it**: an `Anchor` canvas with a reactive-offset `VStack` host holding a 20x20 `Button` (below the 44 floor → an expander) next to a static 60x60 `Button` outside the host; move the host so the expander OVERHANGS the static button; assert `hitLift`'s effect through `adapter.zOrderOf(...)`/the `ops` log the same way `tests/hit_expander_overhang.spec.luau` does, and that the expander's `hitRectOf` is host-relative while its window rect (`hitRect + hostOriginOf`) is where the full-solve arm puts it; (b) **`scrollToVisible` through a space host**: a `ScrollView` inside a moved host with a target row below the fold → `controller.scrollToVisible(row)` returns true and `scrollPosition` equals the pre-Plan-C number (read at HEAD); (c) **`coverRect()`** on a surface whose only painted box is inside a moved host equals `screenRectOf(thatBox)`; (d) **`selection_indicator`** inside a moved host: build via `UI.Picker`/`SegmentedControl` (whichever mounts the indicator — grep `selection_indicator` callers) under a reactive-offset host, move it, assert the indicator's rect tracks the selected segment (delta between them unchanged); (e) **recycle across spaces**: `remove` a plate then `add` one, with recycling armed, assert `stats.recycled > 0` OR `parkRefused` accounts for the host (see T4 step 2), and the re-adopted node's `rectOf` equals the full-solve arm's; (f) a **focused** node inside a moved host: `controller.setFocusPath(name)`, move, `adapter.node(name).focused == true` and `focusLift` equals the full arm's; (g) **a `ScrollView` with a reactive `offsetX` is NOT a space host** (review BL-1): `adapter.isHost(sv) == true` (the adapter registers it as it always did) but `adapter.hostOf(child).hostSpace ~= true`, and the child's stored rect is still absolute; (h) **the same for `UI.VStack({ clipChildren = true, offsetY = signal, children = … })`**; (i) **the fake's `presentedPosition` does not go stale** (review BL-4): move a host, then read `adapter.node(descendant).presentedPosition` — it equals `controller.screenRectOf(descendant)`, and the Step-7 mutation "delete the subtree recompose in `fake_target.setRect`" reddens it on the FIRST tick (record the bite in the ledger); (j) **the cull composes against THIS solve's origin** (review BL-5): a `clipChildren` Canvas holding a reactive-offset host with a `UI.Path` inside it — move the host far enough that the path leaves the Canvas' clip box, and the `visible` verdict flips on the SAME solve (with `paintedRectIn` reverted to `hostOriginOf` it flips one frame late — the Step-7 mutation for this pin); (k) **the hit lift composes against THIS solve's origin too** (review N-3, the same lesson at the second and third site): a `Button` sink that only overlaps a neighbouring expander AFTER this solve's host move is lifted on the SAME solve — assert it through `adapter.zOrderOf(...)`/the `ops` log the way (a) does, with the mutation "hand `hitLift.refresh`/`commitWalks` `hostOriginOf` instead of `originOf`" reddening it by one frame — **AND, per review B-3, assert the STORED rect too: `adapter.hitRectOf(chrome)` under a moved host is byte-equal to arm `c`'s stored rect (both arms host, so equality is the pin), which the z-order assertion alone cannot see.** Each pin is stated against the arm-`c` world where a number is not known at HEAD. Run → FAIL on the first `expect` (rectWrites 1500).

- [ ] **Step 3: `instance_boundary.createOptsFor`** — third branch after the scale/rotation one:

```luau
	--[[ A REACTIVE PLACEMENT ON A CONTAINER IS A COORDINATE-SPACE DECLARATION
		(Plan C, C1). A node whose `offsetX`/`offsetY`/`anchor` is a signal or memo
		will MOVE, per frame, as a unit — and under a flat tree every move rewrote
		every descendant's `Position` (1,488 engine writes for 250 nameplates,
		measured in `FacetBench/docs/profiling/2026-09-02-nameplates-attribution.md`).
		Given a real parent AND rects stored relative to it, a move is one rect and
		one write; the public readers compose the origin back on read.

		`dynamicProps`, NOT `props`: by the time this runs, `mount` has resolved the
		signal into `props` and the reactive FACT survives only there.

		AN ADAPTER-REGISTERED HOST KEEPS THE ABSOLUTE SCHEME (ruling R-2, made real
		here). `offsetX`/`offsetY`/`anchor` are `shared = true` props, so a
		`ScrollView` or a `clipChildren` container reaches this branch — and a
		ScrollView also READS `offsetX/Y` for its own axis, while
		`scroll_into_view` subtracts a raw host rect from a raw target rect. Making
		either a coordinate space would change the meaning of every raw-rect reader
		inside every list Facet ships. Refused outright, above the trigger.

		THERE IS NO COMPOSITION SCAN (ruling R-8 is REPLACED by R-13): a create-time
		scan is a one-shot snapshot — mount nodes start with `children = {}` and a
		`When`/`ForEach` can mount a `Composition` under an already-registered host
		later, at which point the gate silently stops holding. The solver instead
		carries the absolute origin (`ctx.spaceOX/spaceOY`) and hands
		`composition_resolve` a window-space rect, which is exact at any time. ]]
	-- `props` is ALREADY bound above (`local props = node.props` at `:73`, with the
	-- nil early-return at `:74-76`), so this branch neither re-declares it nor
	-- re-guards it.
	if node.class == "ScrollView" or props.clipChildren == true then
		return nil
	end
	if opts ~= nil and opts.translateHosts == false then
		return nil
	end
	local dyn = node.dynamicProps
	if
		dyn ~= nil
		and (dyn.offsetX ~= nil or dyn.offsetY ~= nil or dyn.anchor ~= nil)
		and node.children ~= nil
		and #node.children > 0
	then
		return { instanceHost = true, hostSpace = true }
	end
	return nil
```

`createOptsFor` gains the second parameter `opts` (the renderer's attach opts; `nil` is "defaults"), and `renderer.attach` threads `RendererAttachOpts.translateHosts` into every call. `CreateOpts` type gains `hostSpace: boolean?`. `kindOf` unchanged (`"host"`). There is NO `instance_boundary.hasComposition`.

- [ ] **Step 4: the stamp and the layout node.** `renderer.luau:1007`: `node.hostSpace = if createOpts ~= nil and createOpts.hostSpace == true then true else nil` (one line + a two-line comment pointing at `instance_boundary`). `layout_node.luau` literal: `hostSpace = node.hostSpace,` beside `placementProps`. Solver `Node` type: `hostSpace: boolean?`.

- [ ] **Step 5: the solver.** In `arrange`, immediately before the padding block (`local pt, pr, pb, pl = sides(node.padding)`), after the entry write and the arm:

```luau
	--[[ A COORDINATE-SPACE HOST'S BODY RUNS AT THE ORIGIN (Plan C, C1). Its own
		entry above keeps the rect its parent placed it at; everything beneath it
		is placed against (0, 0, w, h) and stored that way. `render/rect_reads`
		composes the chain back on read, so no public number moves — and a
		host that only MOVED re-bases nothing below it, which is the whole point. ]]
	if node.hostSpace == true then
		rect = { x = 0, y = 0, w = rect.w, h = rect.h }
	end
```

**The push/pop is a WRAPPER, and that is the only shape** (the plan previously offered two and asked the implementer to pick — settled here). `local function arrange(...)` at `solver.luau:2329` is renamed `arrangeBody`; an ANNOTATED forward local `local arrange: (Ctx, Node, Rect, { [string]: any }) -> ()` is declared above it — annotated because `solver.luau` is `--!strict`, where a bare `local arrange` takes type `nil` and the assignment below fails to convert; the repo's own idiom for this is exactly that (`src/present/surface_lifecycle.luau:547 local refreshBody: () -> ()`, `presenter.luau:3670`/`:3865`, `custom.luau:445`) and `solver.luau` has none today (review MI-4). **Its twelve recursive call sites AND `solve`'s root call at `solver.luau:3585` all keep the name `arrange`** — measured: `:2661, 2675, 2686, 2789, 2803, 2867, 2870, 2881, 2889, 3090, 3236, 3409` inside `arrangeBody`, plus `:3585` in `solver.solve` — and routing the ROOT call through the wrapper too is what makes a `hostSpace` ROOT push its own origin (review MI-5). Then `arrange` is assigned after the body:

```luau
	local arrange: (Ctx, Node, Rect, { [string]: any }) -> ()
	-- …`local function arrangeBody(ctx: Ctx, node: Node, rect: Rect, out: { [string]: any })`
	--   (the renamed `:2329`, its body verbatim) …
	--[[ THE ORIGIN PUSH LIVES IN A WRAPPER, NOT IN THE BODY (Plan C, ruling R-13).
		`arrangeBody` returns from several branches — the leaf return among them —
		and a hand-placed pop before each is one `return` away from leaking a host's
		origin into its parent's siblings for the rest of the solve. A wrapper cannot
		be skipped by a branch. Two numbers, four lines, O(1) per node; all twelve
		recursive call sites AND `solver.solve`'s root call at `:3585` still call
		`arrange`, so the push nests by construction AND a hostSpace ROOT pushes too.
		The rect handed down is still the PARENT-space rect — the rebind to (0, 0)
		stays inside `arrangeBody`, after the entry write. ]]
	arrange = function(ctx: Ctx, node: Node, rect: Rect, out: { [string]: any })
		if node.hostSpace == true then
			local ox, oy = ctx.spaceOX, ctx.spaceOY
			ctx.spaceOX += rect.x
			ctx.spaceOY += rect.y
			arrangeBody(ctx, node, rect, out)
			ctx.spaceOX, ctx.spaceOY = ox, oy
			return
		end
		return arrangeBody(ctx, node, rect, out)
	end
```

`Ctx` gains `spaceOX = 0`, `spaceOY = 0` in its literal — **and nothing else: there is no `ctx.spaceOrigin`** (T3's Files list records why: its only candidate reader, `layout/dump.luau`, never sees a `ctx` and composes with its own accumulator instead). Solver budget: +~350 chars, inside T3's.

In the composition branch, shift the **origin numbers** `resolve` already takes — it has no rect parameter (review N-1). The ARRANGE-time call at `solver.luau:2702` is today `resolve(COMPOSITION_DEPS, ctx, node, innerW, innerH, innerX, innerY)` and becomes:

```luau
			-- WINDOW SPACE FOR THE DECISIONS, THIS SPACE FOR THE PLACEMENT (R-13).
			-- `composition_resolve` takes ORIGIN NUMBERS (`originX, originY`), not a
			-- rect, and falls back to `ctx.rootRect` when they are absent — which is
			-- where it decides `atRoot` and keys its cache. Shifting them by the host
			-- origin is the whole change; the children are still placed against this
			-- space's `innerX/innerY`.
			compositionResolve.resolve(COMPOSITION_DEPS, ctx, node, innerW, innerH, innerX + ctx.spaceOX, innerY + ctx.spaceOY)
```

**The MEASURE-time call (`solver.luau:1386`) is UNCHANGED, and the reason goes in a comment beside it:** it passes no origin at all, because measure runs before any position is known — its fallback to `ctx.rootRect` was ALREADY position-blind, and the arrange-time re-resolve above is what lands. That is exactly the argument `composition_resolve.luau:174-181` already makes for the fallback existing.

**The pin:** grep `tests/` for `UI.Composition(`. If a `Composition` CAN be authored under an ordinary container, add a hand-built world to `tests/translate_host.spec.luau` — a reactive-offset VStack holding one — and assert arm `a` and arm `e` agree on `snapshot()` and `diagKey` after a move. If it cannot (the presenter builds compositions at surface roots), state "unreachable by authoring — the presenter builds compositions at surface roots" in the spec header and keep `translate_arm`'s existing refusal note as the standing evidence.

and in the arm block (`if tdx ~= nil then …`), before `translateArm.translateDescendants`:

```luau
		if node.hostSpace == true then
			-- the subtree is stored in THIS node's space: a move of the node moves
			-- nothing in it. Recorded as an EMPTY run so `rect_pass` stops here.
			-- KEY/LOOKUP ASYMMETRY, inherited deliberately (review MI-6): this map is
			-- keyed by `node.id` and `rect_pass.luau:198` looks it up by `node.path`.
			-- They coincide today; if they ever stop coinciding, this write and that
			-- read are the pair to fix together.
			ctx.translatedRoots[node.id] = { dx = dx, dy = dy, from = from, to = from - 1 }
			return
		end
```

(`walkedIds` semantics unchanged: the host is a translate root, not walked.) NOTE `contentRect`/`ctx.containerW/H` are unaffected; `noteContainment` compares child vs inner box — same space, and translation-invariant. Audit `src/layout/*.luau` for any comparison of a rect against `contentRect`/the viewport/`ctx.root` (grep `contentRect\.` and `viewport` in `arrange_reports.luau`, `text_audit.luau`, `boundary_report.luau`): list each in the ledger with "same space / composes / served by the `ctx.spaceOX/spaceOY` carry / composed at its producer / not reachable under a host". The three already known — `composition_resolve` (served by the carry, at its arrange-time call site), `tests/lib/large_text.auditRects` and `layout/dump.luau` (each composed at the producer, one line) — are handled, not booked; anything else the grep finds is a new finding and gets a pin, because an "off-screen" style finding computed from a relative rect is a diagnostics difference the oracle's arm-`c` cannot see (both arms host). Arm `e` (step 8) is what turns that into evidence: it compares `diagKey` after every step.

**There are THREE absolute readers in total (the count R-13, T3 step 1 and the mechanism bullet all use).** The one INSIDE the solver — `composition_resolve`'s `atRoot`/cache key — is served by the `ctx.spaceOX`/`spaceOY` carry at its arrange-time call site, above. The other two get their changes at their own producers, each one line and each NAMED (review B-1): `tests/lib/large_text.auditRects` reads `w.controller.rectOf(path)` instead of `node.rect`, and `src/layout/dump.luau`'s `nodeDump` carries a two-number accumulator down the recursion it already does. Neither `text_audit.luau` nor `composition_resolve.luau` is edited, and **`ctx.spaceOrigin` is not built at all** — no reader can reach it (see T3's Files list for the decision and its evidence).

- [ ] **Step 6: the renderer's map + composers.** `livePaths` sixth param `space`, writes `geometry.hostSpaceOf[node.path] = space` (nil when none) and `geometry.spaceHosts[node.path] = node.hostSpace or nil`; `nextSpace = if node.hostSpace then node.path else space`; the whole-tree arm calls `geometry.clearHosts()` beside `table.clear(scrollHostOf)`; the BOUNDED arm calls `geometry.invalidateOrigins()`; per-root thread `geometry.hostSpaceOf[r.path]`; `dispose` calls `geometry.clearHosts()`; **`sweepDeparted` calls `geometry.dropPath(path)` per departed path** (review IM-8 — the bounded arm never clears the maps, and a cache entry keyed by a removed host is a WRONG origin, not a slow one). `rect_pass.new` ctx gains `invalidateOrigins = geometry.invalidateOrigins`, and **`rect_pass.apply` calls it ONCE at the top, unconditionally** — not per-path inside `applyOne`: `lastRects` has three writers (`applyOne`, `restoreParkedProps`, and T5's lane) and the epoch is one integer, so a blunt per-commit bump is both cheaper than a hot-loop branch and impossible to hook incompletely. `restoreParkedProps` and the lane call it too. **Then the origin split (review N-3):** build `local originOf = function(p) return geometry.originIn(result.rects, p) end` ONCE at the top of the commit span and hand it to `hitLift.refresh(..., originOf)` and to `commit_walks.new`'s ctx — where `authorPressableRects(entryPath)` offsets each sink rect by `originOf(sinkPath) − originOf(entryPath)`, i.e. **composes into the ENTRY's space so `want` and the stored `lastHitRects` entry never leave it** (review B-3); `growWithin` returns `want`, and `want` is what `setHitRect` stores — both read THIS solve's map and run before `lastRects` is rewritten, so `hostOriginOf` there would be last frame's origin. `hostOriginOf` stays where the map really is `lastRects`: `surface_overlap.coverRect(root.node.path, lastRects, paintsNothing, geometry.hostOriginOf)` and `scroll_into_view`'s Deps. `restoreParkedProps`: guard as stated. Renderer size after: run `check_source_size.py` — **against R-14's T3 budget (≤ +1,400) and the 197,500 STOP line**; if either is breached, take step 0b (`src/render/dirty_closure.luau`) in its own commit before continuing. `livePaths` is NOT a candidate seam — it reassigns the scalar upvalue `pathNodeCount` and fails the one-way test.

- [ ] **Step 7: both adapters** as the mechanism section states (registry `hostSpace` **including the reuse-path OR on BOTH adapters**, `hostOriginOf(handle)` local at the three live sites, `setRect`'s `movedHosts` guard, fake `_composePresentation` chain, **the fake's subtree recompose on a space-host `setRect`**, T0 mirror `hostOx = 0` for a space host). Rewrite the "THE INSTANCE TREE IS FLAT" and "FOUR triggers" prose to the five-trigger, mixed-space truth (3-6 lines each; the doc is the code's contract) — and say in the FLAT prose that a space host is the one kind whose children's rects are NOT window-space.

- [ ] **Step 8: the oracle.** `nameplates_scene.snapshot()` line gains `|pos={pp.x},{pp.y}|psize={ps.w},{ps.h}|focus={tostring(node.focused)},{tostring(node.focusProfile)},{tostring(node.focusLift)}|ro={fmt(controller.rectOf(path))}|sro={fmt(controller.screenRectOf(path))}|diagKey={…}` (nil → `-`), **and asserts `pos == sro` as an identity per line, emitting `POSMISMATCH` into the line when it does not hold** (review BL-4: arms `a` and `c` can go stale in step with each other, so the only honest instrument is one that checks the fake's composed position against the public reader rather than against another arm). Create `tests/host_space_oracle.spec.luau` = `commit_translate.spec.luau:287-401`'s four-arm loop (arms a/b/c/d, 4 fixtures incl. `withPath`, 9 views, 4 rounds × the six step kinds + `hide(i, on)` and `nudgeLabel`), `ORACLE_PLATES = 20`, non-vacuity guard, comparing the extended snapshot.
  **Arm `e` is a THREAD, not a second world (review IM-1).** `nameplates_scene.Opts.hosts` (default true) threads `RendererAttachOpts.translateHosts` to `renderer.attach`, so arm `e` is the SAME reactive fixture, mounted with `hosts = false`, driven through the IDENTICAL step list, and compared to arm `a` after EVERY step — `ro=`, `sro=`, `pos=` and `diagKey=`. Its raw stored-rect column is EXPECTED to differ (that is the change), so the compare for `e` strips that one field. A mount-only comparison of a different world (static offsets) would prove nothing about the only thing that changed — a MOVE — which is why the fixture flag replaces it. Arm `e` is simultaneously the "a tree with no hosts is byte-identical" proof, the "public numbers do not move" proof, and (via `diagKey`) R-13's proof that the absolute readers still file the same findings. Run: green.

- [ ] **Step 9: moved pins + census.** Update the three `rectWrites` pins with the new arithmetic written into each header (`translate_arm.spec:157` → `PLATES`; `:148`'s child delta → `dx=0 dy=0` plus a NEW line asserting `presentedPosition` delta `3,2`; `nameplates_baseline:172` → `1502 + PLATES + PLATES` — verify by run); `check_elision_census.luau`: `TRANSLATED` fixture (20 rows, each a reactive-offset VStack of two labels) with `EXPECT_TRANSLATED` read off the run and the sentence "the fifth trigger costs one Frame per moving container; the flat count `EXPECT_FLAT` is unchanged". **`host_move_write_cost.spec` becomes the LIVE-adapter oracle (review IM-2).** It is the only spec that drives the real `screen_presentation.applyRect`, it has no solver, and it is therefore cheap enough to loop: rebuild it as a **9-view loop over three fixtures** — (1) a space-host move, (2) a space host inside a space host, (3) a space host inside a scroll host AND a scroll host inside a space host — pinning per-node engine `Position` after the real `applyRect`, with the T0 `engineWrites` counter beside each. Its **six** existing cases (its own header says four — fix the header) keep their counts as controls, with the non-space host keeping today's subtraction. This is what "the live adapter is proved too" means in this plan; the fake cannot see it (BL-4 is exactly that lesson).

- [ ] **Step 10: THE ACCEPTANCE GATE — the step-0 literals hold, and the new facts (ruling R-15).** In RR `tests/facet_translate_host_contract.spec.luau`: **every literal read at step 0 is unchanged** — that single sentence is what "no public number moved on the production consumer" means, and it is T3's acceptance test, not an optional follow-up. PLUS the new facts: `adapter.isHost(dot) == true` for every dot; `adapter.hostOf(dotHit).path == dot`; `hostCount()` = the step-0 number + 8 (+1 if the `Ticker` strip is a host — it has children); the stored `adapter.node(dotHit).rect` composed with its host chain equals `controller.screenRectOf(dotHit)` (the MI-3 identity, not a threshold); and a dots-only frame's `rectWrites` delta = 8 where step 0 read 8 × nodes-per-dot — put BOTH numbers in the spec header. If this step is red, T3 is not done; do not proceed to step 11.

- [ ] **Step 11: gates + RR + commit.** Full gate set (`verify.sh affected --jobs 1`, `test.sh <BASE FACET>`, `check_source_size.py` against the R-14 budget, stylua, `check_brand_drift.py` if step 0b ran); RR suite — EXPECT pins to move in `facet_commit_translate.spec` (`RECT_PASS_VISITS` 13 → read off the run: a dot host's run is now empty so rectPass visits fewer) and possibly `facet_measure_fanout_contract` (no translate hosts on the racer list — unchanged); move them WITH the measurement. Facet and RR commit in the SAME lockstep window (the RR spec from step 0 is already in; this commit carries its step-10 additions). Commit: `T3: a host is a coordinate space — rects beneath a translate host are stored host-relative, composed on read`.

---

### Task 4 (C1 steps 6-9): RR riders, recycling, unify-or-scope, Studio

**Ruling R-15 moved two steps out of this task:** the old step 1 ("the RR pins at HEAD") is **T3 step 0**, because a HEAD literal cannot be read after HEAD moved; the old step 2 ("the same pins hold") is **T3 step 10, the acceptance gate**. What is left is renumbered below, and every cross-reference in this plan points at the new numbers.

**Files:**
- Modify (RR): `tests/facet_translate_host_contract.spec.luau` (created at T3 step 0), `tests/facet_commit_translate.spec.luau` (`RECT_PASS_VISITS`, header table — moved at T3 step 11), `tests/facet_anchor_arrange.spec.luau` (unchanged in T4 — T5 moves it), any `screenRectOf` pin that moved (it must NOT: `facet_node_facts_and_offset_contract`, `facet_motion_and_scroll_contract`, `facet_row_actions_reach_contract` — a moved pin here is a DEFECT in T3, not a pin to update)
- Modify (Facet): `src/render/instance_boundary.luau` ONLY if step 3's number says so. **Recycling (step 2) does NOT modify `parkEligible` in this task** — see MI-7 below.
- Modify (FacetBench): `docs/studio-runs/2026-09-03-facet-parity.md` §C1

- [ ] **Step 1: RR riders for the reader audit.** In the same RR spec: `scrollToVisible` inside the racer list still lands at the same offset (the list is not a translate host — control), and any RR surface where a Facet control with `syncGeometry` (Slider/Table) sits under a reactive-offset container — grep RR `src/client/FacetSponsor` for a `UI.Slider`/`newTable` inside `Ticker`/`StartCountdown`/`ChipRow`; if none, state "none shipped" in the spec header.

- [ ] **Step 2: recycling — MEASURE ONLY; the lift is its own task (review MI-7).** From FacetBench: `lune run tools/profile/attr nameplates L 3` and `damage_fountain L 3` at T3 vs T0 (ABBA, n=2 per arm: A/B/B/A). If `addItem-plates`/`removeItem-plates` p50 is ≤5 % worse: book it with the number and move on. **If it fires (>5 % worse), this task STOPS and books `T4b: park a plain host` as its own task with its own spec** — it is not a parenthetical. What T4b would have to do, recorded here so the booking is concrete: lift the host refusal for PLAIN hosts (`createOpts.instanceHost` without `canvasGroup`) whose `entry.children` array is EMPTY at park time, **on both adapters**; ORDER the removal, because `sweepDeparted` visits `handles` in hash order (S3 §1, `parkEligible`'s corpse note) — sort departed paths by depth DESCENDING so a host's children are parked before it; add the `"host"` bucket `kindOf` already names; and note the second refusal the plan had omitted: **`parkEligible` also refuses on `presentationTransforms[path] ~= nil` (`screen_target.luau:3354`)**, so a host that ever carried a presentation transform stays unrecyclable no matter what T4b does to the children rule. A change to the removal sweep with no test named is exactly the sub-project this plan should not hide in a clause.

- [ ] **Step 3: unify or scope (spec §5.1's ruling).** Try `hostSpace = true` on the scale/rotation branch too (one line), run the suite + `attr` on `battle_hud`/`killfeed` (they have rotated/scaled containers? grep the workloads) and the elision census. Keep if neutral-or-better on every class AND the suite is green without pin movement beyond the ones the ledger predicts; else revert and record "translate hosts only" with the numbers. (R-2 predicts "scope".)

- [ ] **Step 4: Studio.** FacetBench `DRIVING.md` recipe: stamp the marker, `rojo build runner/studio/place.project.json --output artifacts/studio-place.rbxl`, `RobloxStudio -localPlaceFile artifacts/studio-place.rbxl`, read the marker back, drive `{"frameworks":["_fixture","facet","vide"],"workloads":["nameplates"],"sizes":["L"],"samples":250,"warmup":25,"mode":"loop"}` as its OWN `main.run` (the ~10 s loop ceiling), then `battle_hud` L, scrape with `tools/studio_scrape`. Window FOCUSED (the 15 fps trap). Record §C1 in the report: nameplates tick live before (5.143) / after / vide (0.298), and `byKind` per-class rows for facet AND vide (the first per-class vide numbers). Kill the Studio pid.

- [ ] **Step 5: RR milestone canary.** `cd games/RascalRally/code && rojo build default.project.json --output rr-canary.rbxl && RobloxStudio -localPlaceFile rr-canary.rbxl`; probe a T3 comment marker (`script_grep "coordinate-space host"` must hit `ReplicatedStorage.Facet.render.instance_boundary`); destroy the double-boot duplicates; race + results payload per S5 §B7; read: minimap markers present and MOVING over 45 frames, 0 Facet quarantines, diagnostics racing 0 / results 2 advisory, frame p50 with focus stated. Commit RR (`Facet lockstep: translate hosts — the minimap dots are coordinate spaces`), FacetBench (§C1), Facet (any step-3 change, its own commit).

---
### Task 5 (C6): the translate lane — an all-placement tick solves nothing

**The list this fast path owes** (written into the spec header AND the ledger before code — per channel, served or gated). The lane skips, for a consumed host, `layout_node.build` (that node), `solver.solve` (that node's entry), the eight commit walks, `channel.installAnimationRecords`, `premeasureRound.request`, `fullSolveSeq` and `stats.last*`; it SERVES `hit_lift.refresh`, `dragBridge.refreshTargets` and `solvedListeners` by calling them.

**How the "solves nothing" claim is measured (review MI-9).** Pin `solves` and `lastLaneTranslates` as **deltas across the drive** — never `lastCommitVisits == 0`, which is unmeasurable: `stats.last*` are the PREVIOUS solve's by doctrine and the lane does not zero them, so a pin on them would pass for the wrong reason. The sentence "and runs no commit walks" is replaced everywhere by **"no commit ran (`solves` delta 0 — a commit runs only inside `solveAndApply`)"**. The entry-identity claim is proved on the NEXT caster tick, not on the lane tick.

| channel | what it publishes for a translated host | lane verdict |
|---|---|---|
| `nodeDirty` (the classifier's `markDirtyIn`) | the prefix-closed set that makes the NEXT `layout_node.build` rebuild this node and its ancestors | **NOT marked, deliberately (ruling R-10).** The lane removes consumed entries from `dirty`, so `markDirtyIn(nodeDirty, entry.path)` (`renderer.luau:2849`, unconditional) never runs for them; and the `nodeDirty = nil` rebuild-everything valve CANNOT fire, because `refresh` advances `nodeDirtySeen = root.dirtySeq()` at `:2832` BEFORE the loop. That is legal ONLY because the row below serves the build's own fields through the build's own function. If R-10's `applyPlacement` is not in place, this row is a live defect: the warm store hit (`layout_node.luau:315-326`) returns `hit.built` carrying the stale `resolveOffset` |
| `layout_node.build` | `node.anchor`, `node.offsetX`, `node.offsetY`, `node.placementProps` (a nine-prop PRESENCE flag, `:605-615`), `wKey`/`hKey`, the parent-side `inertPlacement` audit, store `built`/`nodes` counts | **SERVED through the build's own code (R-10):** the four placement assignments are extracted into `layout_node.applyPlacement(layoutNode, props, metrics)`; the node literal calls it and the lane's `apply` calls it, so there is ONE copy and no enumeration to get wrong. `wKey`/`hKey` are path-derived and unchanged by a move. `inertPlacement` and `placementProps` move ONLY on a presence flip, which is **GATED**: a placement entry whose old or new value is `nil` stays in the remainder. `store.built`/`nodes` counts are NOT served and are not meant to be — no build happened, and `lastNodeBuilds` is the previous solve's (stated, and pinned: "a lane tick, then an unrelated `hp` solve, leaves the host at the laned position and `lastNodeBuilds` = the hp row's count only") |
| `solver.solve` entry | `rect` | SERVED: `entry.rect = table.freeze(newRect)` on the EXISTING entry table (identity preserved so `commit_walks.skip` prunes the host next commit) |
| | `offerW/offerH`, `selfArrange`, `textState/compact/textFacts`, `containerW/H`, `hitFloor`, `kind`, `overflow` | UNCHANGED by a move (placement props are arrange-only: `tests/layout_prop_dirt.spec` mechanises it; `selfArrangeKey` reads distribute/alignH/alignV) |
| | `ctx.diagnostics` — containment finding for the host vs its parent's inner box (`noteContainment`) | GATED: the lane refuses unless the OLD and the NEW rect are both fully inside the parent's inner box (then no finding exists either way); `unknown anchor` GATED at validation |
| | `work.*` / `stats.last*` | not published: `lastArranged` etc. are the previous solve's (already the doctrine for `lastSkipped`); the lane publishes `stats.laneTranslates` (cumulative) + `stats.lastLaneTranslates` (per refresh, 0 on a refresh that laned nothing) |
| commit `harvest` | hidden set / compositions / textFacts | position-independent — nothing to serve |
| `textScale`/`padding`/`textVerdicts`/`scrollRegions` | arrange-blind | nothing |
| `visible` | `solverHidden`, `pathEscapesClip` (a stroked path vs its CLIP host's box) | **GATED: refuse when `spaceHostHasPath[path]`** — maintained on `livePaths`' EXISTING Path latch (`+1` only on the first sighting, a reparent branch through `noteFromHost`, `−1` inside `sweepDeparted`'s `pathNodes[path] ~= nil` guard — review D-0, step 3 has the code); pinned by a plate with a Path inside it refusing while its neighbours lane. (Not "any Path on the surface": RR's minimap draws four and that rule would kill the lane on the one shipped consumer.) |
| `hitRects` | `lastHitRects[path]` for the host and descendants (centred on r.x/r.y in the host's space) | descendants: unchanged by construction (their rects did not change, and their expanders are host-relative); **the host's OWN: GATED — refuse when `lastHitRects[path] ~= nil`**, because its `want` is centred on the host's rect and only the `hitRects` walk recomputes it |
| `hit_lift.refresh` | overhang constraints between expanders and sinks across the surface | **SERVED (ruling R-12): the lane CALLS it** after applying, when the adapter has the seam and any expander exists — `if adapter.setHitRect ~= nil and next(lastHitRects) ~= nil and hitLift.refresh(lastResult.rects, lastHitRects, inputSinks, parentNodeOf, solverHidden, geometry.hostOriginOf) then syncZOrder() end`, the same call the commit makes **including its feature guard** (`renderer.luau:2181-2183`). The origin is `geometry.hostOriginOf`, not the commit path's fresh-map `originOf`: a lane frame runs no solve, and `apply` has already written `lastRects` and bumped the epoch (review I-1). It reads `lastHitRects`, not the tree, and composes origins after T3. **`hostHitCount` and `hostSinkCount` do not exist**: they would have refused the lane on RascalRally's minimap dots (a `DotHit` `UI.Button` under every dot is a sink), which is the only shipped surface the lane was built for, while an isolated-fixture pin passed and proved nothing |
| the absolute-rect AUDITS (`tests/lib/large_text.auditRects`, `layout/dump.luau`) | window-space findings for every node under the moved host | not a LANE channel — a **T3** channel, and fixed at the PRODUCER: each reads a composed rect (`controller.rectOf` / a `nodeDump` origin accumulator), so a laned move is visible the moment it is asked. Named here so the reader does not go looking for a lane verdict. `text_audit.outOfBounds`/`focusVisibility` are NOT in this row: they have no live producer (spec fixtures only) — review B-1 |
| `surface_overlap.coverRect` | the union of `lastRects` across a surface | no lane channel: `coverRect(rootPath, lastRects, paintsNothing, geometry.hostOriginOf)` — the settled four-argument form from T3 — is computed ON DEMAND at its call site off `lastRects`, which the lane's `apply` has already written, so a laned move is visible to it the moment it is asked. Stated because the composer list (T3) names it and a reader would otherwise expect a lane row |
| `installAnimationRecords` | armed `withAnimation` commit | GATED: refuse when `channel.armed()` |
| `premeasureRound` | text requests | none from a move |
| `dragBridge.refreshTargets` | hover re-evaluation | SERVED: call it after the lane when `liveDrag.isActive()` (one call) |
| `solvedListeners` (presenter `feedGeometry`) | consumers' `syncGeometry(rectOf)` | SERVED: the same notify block runs after a lane that applied ≥1 (extracted into `notifySolved()`), so a Slider inside a moved host re-reads its rect exactly as after a solve |
| `fullSolveSeq` / `layoutDirtIsStale` | the stale-dirt test | untouched: a lane refresh is not a full solve; the entries it consumed are gone from the queue |
| `solverHidden`/`hiddenRoots` | a hidden host | GATED: refuse when `solverHidden[path] == true` |
| `scroll` parents | a `scroll` container also reads `offsetX/Y` | GATED: the parent's layout node kind must be `"anchor"` |
| `fill` dims | `offsetFill` changes w/h with the offset | GATED: both host dims not `fill` (`measure_facts.dim(hostNode, "w").type ~= "fill"`) |
| metric-name offsets | `resolveOffset` against the theme | GATED: value must be a number or `{ scale?: number, offset?: number }` |

**Files:**
- Create: `src/render/translate_lane.luau`
- Modify: `src/render/renderer.luau` (`controller.refresh` — declared `:2790`, running to `:3045`, NOT `:2841`: ONE lane call right after `local dirty = root.takeDirty()`, `dirty` → `remaining`; `stats` `:605` two fields; `solveAndApply`'s notify block `:2260-2290` → `notifySolved()` as a FORWARD LOCAL, see step 3; `livePaths` fills `spaceHostHasPath`/`pathHostOf` off its EXISTING Path latch `:1459-1464`, and `sweepDeparted` decrements inside its EXISTING `if pathNodes[path] ~= nil then` guard `:2584` before `geometry.dropPath` — review D-0)
- Modify: `src/render/layout_node.luau` (`layout_node.applyPlacement(layoutNode, props, metrics)` extracted from the node literal's four placement assignments and CALLED by it — ruling R-10; `layout_node.resolveOffset = resolveOffset` exported for the gate's own use)
- Modify: `src/render/rect_reads.luau` — **nothing new is DECLARED here: `spaceHostHasPath`, `pathHostOf`, `noteUnder` and `noteFromHost` were all created in T1 and are already cleared by `clearHosts` and `dropPath` (review N-8)**; T5 only starts FILLING the two maps, and it fills them **off the latches `livePaths` and `sweepDeparted` already keep** — the `+1` on `livePaths`' existing `isPath ~= (pathNodes[node.path] ~= nil)` transition (`renderer.luau:1459-1463`) at `isPath and pathNodes[node.path] == nil`, the reparent OLD −1 / NEW +1 through `noteFromHost` BEFORE `hostSpaceOf[node.path]` is rewritten, and the `−1` inside `sweepDeparted`'s existing `if pathNodes[path] ~= nil then` guard (`:2584`) BEFORE `geometry.dropPath(path)` — never an unconditional per-walk `+1`, which the bounded structural arm would ratchet forever (reviews B-2 / D-0; T5 step 3 has the code). `noteUnder`/`noteFromHost` delete the key at zero (a `0` count is truthy in Luau and would refuse the host forever). There is no `hostHitCount`, no `hostSinkCount`, no `noteHitEntry`, no `noteSink` — ruling R-12
- Modify: `src/render/commit_walks.luau` (NO CHANGE for the lane — R-12 removed the hit-count hook; if `hitRects` needs anything it is only that `lastHitRects` stays the map the lane and `hit_lift` both read)
- Modify: `tests/lib/nameplates_scene.luau` (`Opts.reactiveAnchor`, `Opts.withButton` (plate 3 carries a 20x20 Button → an expander), `scene.anchorFlip(i)`, `scene.moveOut(i)`, `scene.clearOffset(i)` (sets the offset signal to `nil` — the R-10 nil-flip drive). **`Opts.withPath` ALREADY EXISTS** (`nameplates_scene.luau:120`, "add one UI.Path leaf: the visible prune latch closes") and T3 step 8 already drives it as one of the four oracle fixtures — REUSE it; extend it only if its Path does not sit under a space host, and say so in the ledger if it had to be moved — review N-14)
- Modify: `tests/translate_host.spec.luau` (T3's `solves=1` pins → `solves=0` with the arithmetic), `tests/translate_arm.spec.luau` (`:81` pure-tick `arranged=252 translated=1250` → the tick no longer solves: the case gains a MIXED drive to keep the arm pinned; state it in the header), `tests/nameplates_baseline.spec.luau`, `tests/commit_translate.spec.luau` (pure-tick cases → lane; keep a caster-tick case for the walk pins), `tests/host_space_oracle.spec.luau` (+ `anchorFlip`, `moveOut`, `withButton` fixture)
- Create: `tests/translate_lane.spec.luau`; register
- Modify (RR): `tests/facet_anchor_arrange.spec.luau` (`:312/:343/:352/:395` "every dot moves" → `solves=0 lane=8`; add a mixed frame that solves and keeps `reused=8 offered=0`), `tests/facet_commit_translate.spec.luau` (dots-only frame → lane; keep one solved frame), `tests/facet_translate_host_contract.spec.luau` (a dots-only frame pins `solves=0 lastLaneTranslates=8` and the same `screenRectOf` literals — on the isolated `mapSurface` fixture, AND on the FULL Sponsor surface mounted the way `facet_sponsor_table.spec` mounts it, which is the only pin that speaks for the shipped screen — review IM-4)

**Interfaces:**
- Produces: `translate_lane.new(deps) -> { run: (dirty: { any }) -> ({ any }, number) }` returning `(remaining, applied)`; `stats.laneTranslates`, `stats.lastLaneTranslates`; `layout_node.applyPlacement`, `layout_node.resolveOffset`.
  ```luau
  export type Deps = {
  	handles: { [string]: any }, lastRects: { [string]: any }, lastHitRects: { [string]: any },
  	stats: any, adapter: any, metrics: () -> any,
  	geometry: any,                      -- rect_reads: spaceHosts, hostSpaceOf, invalidateOrigins,
  	                                    -- spaceHostHasPath, hostOriginOf
  	parentNodeOf: { [string]: any },    -- by reference
  	inputSinks: { [string]: any },      -- by reference (for the hit_lift serve)
  	layoutNodeOf: (mountNode: any) -> any,
  	findNode: (path: string) -> any,
  	lastResultRects: () -> any?,        -- the solver's live entry map
  	solverHidden: { [string]: boolean },
  	channelArmed: () -> boolean,
  	rectsEqual: (a: any, b: any) -> boolean,
  	hitLiftRefresh: (rects, hitRects, sinks, parentNodeOf, hidden, originOf) -> boolean,
  	syncZOrder: () -> (),
  }
  ```
  (`clipHostOf` is gone: the `visible` gate is `spaceHostHasPath` alone, per IM-5. `hitLiftRefresh`/`syncZOrder`/`inputSinks` are new, per R-12.)

- [ ] **Step 1: red.** `tests/translate_lane.spec.luau`:

```luau
--!strict
--[[ THE TRANSLATE LANE (Plan C, C6): a refresh whose only layout-class dirt is a
	placement prop on coordinate-space hosts SOLVES NOTHING. Per host the lane
	re-places it with `placement.anchorPlace` — the solver's own function — writes
	the solver's entry in place, and calls `setRect` once. Anything else that would
	need a solve is handed to the solve as the REMAINDER (ruling R-3), so a caster
	tick lanes 200 plates and solves 50.
	THE LIST OF WHAT THE SKIPPED FUNCTIONS PUBLISH, with the verdict per channel, is
	the table in docs/superpowers/plans/2026-09-03-facet-parity-C.md Task 5 and is
	what every case below drives. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local scene = require("./lib/nameplates_scene")
local PLATES, CASTERS = scene.PLATES, scene.PLATES // scene.CASTER_EVERY

local function deltas(s: any, fn: () -> ())
	local a, ew = s.stats(), s.adapter.engineWrites()
	fn()
	local b = s.stats()
	return `solves={b.solves - a.solves} lane={b.lastLaneTranslates} rectWrites={b.rectWrites - a.rectWrites} engineWrites={s.adapter.engineWrites() - ew}`
end

describe("translate lane", function()
	it("a pure tick solves nothing: one lane translate, one rect, one engine write per plate", function()
		local s = scene.new()
		s.tick(3, 2) -- warm
		expect(deltas(s, function() s.tick(3, 2) end)).toBe(`solves=0 lane={PLATES} rectWrites={PLATES} engineWrites={PLATES}`)
		s.dispose()
	end)
	it("a caster tick lanes the movers and solves only the casters", function()
		local s = scene.new()
		s.tickWithCasts(3, 2)
		-- lane = the 200 plates whose only dirt is placement; the 50 casters carry
		-- measure dirt on their Cast bar and take the solve. READ OFF THE RUN:
		-- arranged/translated for the remainder solve go in the header.
		expect(deltas(s, function() s.tickWithCasts(3, 2) end)).toBe(
			`solves=1 lane={PLATES - CASTERS} rectWrites={PLATES + CASTERS} engineWrites={PLATES + CASTERS}`
		)
		s.dispose()
	end)
	it("an anchor flip is a placement write and lanes", function()
		local s = scene.new({ reactiveAnchor = true })
		s.tick(3, 2)
		expect(deltas(s, function() s.anchorFlip(7) end)).toBe("solves=0 lane=1 rectWrites=1 engineWrites=1")
		s.dispose()
	end)
	it("a fractional (scaleOffset) offset lanes; a metric-name offset is refused", function() … end)
	it("GATE: a host that leaves its parent's box takes the solve (the containment finding)", function()
		local s = scene.new()
		s.tick(3, 2)
		expect(deltas(s, function() s.moveOut(5) end)).toBe("solves=1 lane=0 rectWrites=1 engineWrites=1")
		-- ...and the finding a full solve files is filed
		expect(#s.controller.diagnostics() > 0).toBe(true)
		s.dispose()
	end)
	it("GATE: a host that is ITSELF a hit expander takes the solve; a host with an expander BELOW it lanes", function()
		-- the host's own `want` is centred on its rect and only the `hitRects` walk
		-- recomputes it → refuse. A DESCENDANT's expander is host-relative and did
		-- not move → lane, and the lane serves `hit_lift` (R-12) so an expander
		-- outside the host that now overhangs it is still re-evaluated.
		local s = scene.new({ withButton = true }) -- plate 3's Row carries a 20x20 Button
		s.tick(3, 2)
		expect(deltas(s, function() s.tick(3, 2) end)).toBe(`solves=0 lane={PLATES} rectWrites={PLATES} engineWrites={PLATES}`)
		-- and the expander's WINDOW rect tracked the host: hitLift saw the new overlap
		s.dispose()
	end)
	it("B-2: three bounded syncs then a Path removal — the host lanes again", function()
		-- the count must be ONE however many times `livePaths` re-walks the same live
		-- Path. Drive three bounded structural syncs that touch the host's subtree
		-- (add/remove a sibling leaf under it), then remove the Path, then tick:
		-- `spaceHostHasPath[host]` is gone and the host lanes. With an unconditional
		-- `+1` the count is 3, the removal's `-1` leaves 2, and the host never lanes
		-- again — the Step-7 mutation for this pin.
	end)
	it("GATE: a host whose subtree contains a Path takes the solve, its neighbours lane", function()
		-- `spaceHostHasPath[path]`, filled on `livePaths`' EXISTING Path latch (the
		-- +1 only on `isPath and pathNodes[node.path] == nil`, plus the reparent
		-- branch) — the ONLY gate the `visible` walk needs
		local s = scene.new({ withPath = true }) -- plate 3 carries a UI.Path
		s.tick(3, 2)
		expect(deltas(s, function() s.tick(3, 2) end)).toBe(`solves=1 lane={PLATES - 1} rectWrites={PLATES} engineWrites={PLATES}`)
		s.dispose()
	end)
	it("SERVE: a lane tick with an expander anywhere on the surface calls hit_lift once", function()
		-- pin `adapter.zOrderOf` / the ops log the way `hit_expander_overhang.spec` does:
		-- a static Button outside the moved host that the host's expander now overhangs
		-- gets the same z treatment a full solve would have given it. READ OFF THE RUN.
	end)
	it("GATE: a nil-flip placement write takes the solve (R-10)", function()
		-- `item.offsetX:set(nil)` then back: `placementProps` and the parent's
		-- `inertPlacement` audit move on a PRESENCE flip and nothing serves them
		local s = scene.new()
		s.tick(3, 2)
		expect(deltas(s, function() s.clearOffset(5) end)).toBe("solves=1 lane=0 rectWrites=1 engineWrites=1")
		s.dispose()
	end)
	it("R-10: a lane tick then an unrelated solve leaves the host at the LANED position", function()
		-- the failure this pins is the stale warm-store build: lane a move (no
		-- `nodeDirty` mark), then drive an unrelated `hp` change that solves. The host's
		-- `rectOf` must still be the laned one, and `lastNodeBuilds` must equal the hp
		-- row's count only (READ OFF THE RUN) — a rebuild of the host would show up there.
	end)
	it("GATE: an armed withAnimation commit solves", function() … `controller.armAnimation(session)` then tick → solves=1 lane=0 … end)
	it("GATE: a hidden host solves", function() … `s.hide(4, true)` (solves=1), tick → lane={PLATES-1} … end)
	it("the solver's entry is updated in place so the next commit prunes the host", function()
		-- lane tick, then a caster tick: `lastCommitVisitsByWalk.harvest` on the
		-- caster tick equals the T5b caster number (303), not the whole tree — the
		-- laned plates' entries are the SAME tables the last commit noted
	end)
	it("a Slider inside a moved host re-reads its geometry (solvedListeners fire)", function() … end)
	it("negative control: delete the lane call and every pin above goes red", …) -- documented as the Step-7 mutation, not a case
end)
```

- [ ] **Step 2: `src/render/translate_lane.luau`** (full):

```luau
--!strict
--[[ THE TRANSLATE LANE — see the plan's Task 5 table for every channel the solve
	publishes and how this lane serves or gates it. Two passes, and the split is
	the safety property: VALIDATE every candidate against the gates before a
	single write, then APPLY. A candidate that fails stays in the remainder and
	the solve handles it; the others still lane (ruling R-3). ]]
local placementLib = require("../layout/placement")
local measureFacts = require("../layout/measure_facts")
local layoutNodeLib = require("./layout_node")
local authority = require("./authority")

local translate_lane = {}

export type Deps = { … as above … }

local PLACEMENT: { [string]: boolean } = { offsetX = true, offsetY = true, anchor = true }

local function offsetOk(v: any): boolean
	if v == nil or type(v) == "number" then
		return true
	end
	return type(v) == "table"
		and (v.scale == nil or type(v.scale) == "number")
		and (v.offset == nil or type(v.offset) == "number")
end

local function inside(inner: any, r: any): boolean
	return r.x >= inner.x and r.y >= inner.y and r.x + r.w <= inner.x + inner.w and r.y + r.h <= inner.y + inner.h
end

function translate_lane.new(deps: Deps)
	local handles, lastRects, lastHitRects = deps.handles, deps.lastRects, deps.lastHitRects
	local stats, adapter, geometry = deps.stats, deps.adapter, deps.geometry
	local parentNodeOf, layoutNodeOf, findNode = deps.parentNodeOf, deps.layoutNodeOf, deps.findNode
	local solverHidden, channelArmed, rectsEqual = deps.solverHidden, deps.channelArmed, deps.rectsEqual
	local spaceHosts, spaceHostHasPath = geometry.spaceHosts, geometry.spaceHostHasPath

	-- one candidate per host path, however many placement entries it wrote this frame
	-- `props`/`metrics` are in the record because `apply` calls `layout_node.applyPlacement`
	-- with them (ruling R-10); the module is `--!strict`, so they are declared.
	local candidates: { [string]: { node: any, parent: any, entry: any, inner: any, x: number, y: number, props: any, metrics: any } } = {}
	local order: { string } = {}

	local function innerBoxOf(parentPath: string, parentNode: any): any?
		-- the parent's rect in the space the HOST's rect is stored in: a space
		-- host's children are relative to it, so its own box is at the origin
		local pr = if spaceHosts[parentPath] then nil else lastRects[parentPath]
		if pr == nil then
			local own = lastRects[parentPath]
			if own == nil then
				return nil
			end
			pr = { x = 0, y = 0, w = own.w, h = own.h }
		end
		local pt, prr, pb, pl = measureFacts.sides(parentNode.padding)
		-- THE SOLVER'S OWN DERIVATION, NOT A COPY (review IM-3): `placement.innerBox`
		-- is the four lines `arrange` runs, clamp included.
		local ix, iy, iw, ih = placementLib.innerBox(pr.x, pr.y, pr.w, pr.h, pt, prr, pb, pl)
		return { x = ix, y = iy, w = iw, h = ih }
	end

	local function validate(path: string): boolean
		if candidates[path] ~= nil then
			return true
		end
		if not spaceHosts[path] or handles[path] == nil or solverHidden[path] == true then
			return false
		end
		-- the host's OWN expander is centred on its rect and only the `hitRects` walk
		-- recomputes it; a Path in the subtree is the `visible` walk's clip test
		-- (ruling R-12: descendants' expanders and sinks are NOT counted — the lane
		-- SERVES `hit_lift` after applying instead)
		-- `spaceHostHasPath` is a COUNT whose key `noteUnder`/`noteFromHost` delete at
		-- zero, so this truthiness test is exact: a host that once held a Path and no
		-- longer does has no key and lanes again (reviews N-8 / B-2 / D-0 — true only
		-- because every ±1 rides a latch, so a re-walk cannot ratchet the count).
		if lastHitRects[path] ~= nil or spaceHostHasPath[path] ~= nil then
			return false
		end
		local rects = deps.lastResultRects()
		local entry = if rects ~= nil then rects[path] else nil
		local stored = lastRects[path]
		local mount = findNode(path)
		local parentMount = parentNodeOf[path]
		if entry == nil or entry.rect == nil or stored == nil or mount == nil or parentMount == nil then
			return false
		end
		local node, parent = layoutNodeOf(mount), layoutNodeOf(parentMount)
		if node == nil or parent == nil or parent.kind ~= "anchor" then
			return false
		end
		if measureFacts.dim(node, "w").type == "fill" or measureFacts.dim(node, "h").type == "fill" then
			return false
		end
		local props = mount.props
		if props == nil then
			return false
		end
		if not offsetOk(props.offsetX) or not offsetOk(props.offsetY) then
			return false
		end
		-- THE NIL-FLIP GATE (ruling R-10). `layout_node.build` derives
		-- `placementProps` — a nine-prop PRESENCE flag — and the parent's
		-- `inertPlacement` audit from these props, and BOTH move only when a prop
		-- appears or disappears. The lane serves values, not presence, so a write
		-- whose old or new value is `nil` stays in the remainder and the solve does
		-- the whole job. `node` here is the CURRENT layout node, so its field is the
		-- OLD value and `props` carries the new one.
		if
			(props.offsetX == nil) ~= (node.offsetX == nil)
			or (props.offsetY == nil) ~= (node.offsetY == nil)
			or (props.anchor == nil) ~= (node.anchor == nil)
		then
			return false
		end
		if placementLib.ANCHOR_FACTORS[props.anchor or "topLeft"] == nil then
			return false
		end
		local inner = innerBoxOf(parentMount.path, parent)
		if inner == nil then
			return false
		end
		local metrics = deps.metrics()
		local ox = layoutNodeLib.resolveOffset(metrics, props.offsetX)
		local oy = layoutNodeLib.resolveOffset(metrics, props.offsetY)
		local x, y = placementLib.anchorPlace(inner.x, inner.y, inner.w, inner.h, stored.w, stored.h, false, false, props.anchor, ox, oy)
		local newRect = { x = x, y = y, w = stored.w, h = stored.h }
		if not inside(inner, stored) or not inside(inner, newRect) then
			return false
		end
		candidates[path] = { node = node, parent = parent, entry = entry, inner = inner, x = x, y = y, props = props, metrics = metrics }
		table.insert(order, path)
		return true
	end

	local function apply(path: string)
		local c = candidates[path]
		local node, entry = c.node, c.entry
		-- WHAT `layout_node.build` WOULD HAVE WRITTEN, WRITTEN BY THE BUILD'S OWN
		-- CODE (ruling R-10). The lane consumes these dirty entries, so the
		-- classifier never marks `nodeDirty` for this path and the next build takes
		-- the warm-store hit — which returns the node UNCHANGED. `applyPlacement` is
		-- the same function the node literal calls, so there is exactly one copy of
		-- "what a placement prop means on a layout node", and no enumeration here to
		-- fall out of date. (`placementProps` and the parent's `inertPlacement` are
		-- untouched by construction: a presence flip was refused at validation.)
		layoutNodeLib.applyPlacement(node, c.props, c.metrics)
		local old = entry.rect
		local newRect = table.freeze({ x = c.x, y = c.y, w = old.w, h = old.h })
		if rectsEqual(old, newRect) then
			return -- same pixel: nothing moved, nothing to write
		end
		-- THE ENTRY IS MUTATED IN PLACE, DELIBERATELY: `commit_walks.skip` prunes on
		-- entry IDENTITY, and this host's subtree is exactly what the next commit
		-- must prune. The RECT is a fresh frozen table (never mutated).
		entry.rect = newRect
		lastRects[path] = entry.rect
		geometry.invalidateOrigins()
		authority.assertWrite("common", "size", "layout")
		adapter.setRect(handles[path], entry.rect)
		stats.rectWrites += 1
	end

	-- returns the entries the solve must still see (the same array when nothing
	-- was consumed) and how many hosts were re-placed
	local function run(dirty: { any }): ({ any }, number)
		stats.lastLaneTranslates = 0
		if channelArmed() or next(spaceHosts) == nil then
			return dirty, 0
		end
		table.clear(candidates)
		table.clear(order)
		local consumed: { [number]: boolean }? = nil
		for i, entry in dirty do
			if entry.class == "arrange" and entry.prop ~= nil and PLACEMENT[entry.prop] and entry.path ~= nil then
				if validate(entry.path) then
					consumed = consumed or {}
					consumed[i] = true
				end
			end
		end
		if consumed == nil then
			return dirty, 0
		end
		for _, path in order do
			apply(path)
		end
		-- SERVE `hit_lift` (ruling R-12). An expander OUTSIDE a moved host can now
		-- overhang INTO it, and no counter can decide that cheaply — so call the same
		-- function the commit calls. It reads `lastHitRects`, not the tree, and
		-- composes origins through `originOf` after T3, so it costs one pass over the
		-- expander set on a frame that HAS expanders and nothing at all on a frame
		-- that does not.
		-- the commit's OWN feature guard comes with the call (review N-13): on an
		-- adapter without `setHitRect` there is no expander seam at all.
		if #order > 0 and adapter.setHitRect ~= nil and next(lastHitRects) ~= nil then
			if
				deps.hitLiftRefresh(
					deps.lastResultRects(),
					lastHitRects,
					deps.inputSinks,
					parentNodeOf,
					solverHidden,
					geometry.hostOriginOf
				)
			then
				deps.syncZOrder()
			end
		end
		local remaining = {}
		for i, entry in dirty do
			if not consumed[i] then
				table.insert(remaining, entry)
			end
		end
		local n = #order
		stats.laneTranslates += n
		stats.lastLaneTranslates = n
		return remaining, n
	end

	return { run = run }
end

return translate_lane
```

(Adjust `dim` to whatever `measure_facts.dim` expects — it takes the LAYOUT node. `mount.props` may be nil — guard. `inside` on the OLD rect uses the stored rect, which is in the parent's space — the same space `inner` was built in.)

- [ ] **Step 3: the renderer hook.** In `controller.refresh`, right after `local dirty = root.takeDirty()`:

```luau
		-- THE TRANSLATE LANE (Plan C, C6): placement writes on coordinate-space hosts
		-- are served without a solve; what it could not take is the remainder the
		-- rest of this function sees. `render/translate_lane` carries the gates.
		local laned = 0
		profile.span("lane", function()
			dirty, laned = lane.run(dirty)
		end)
```

`stats` literal: `laneTranslates = 0, lastLaneTranslates = 0,` with a two-line comment. After the solve gate block (before `drainAppeared()`): `if laned > 0 and not needsSolve then local liveDrag = dragBridge.peek(); if liveDrag ~= nil and liveDrag.isActive() then liveDrag.refreshTargets() end; notifySolved() end`.

**`notifySolved` is a FORWARD LOCAL, not a function declared above `solveAndApply` (review IM-11).** The block being extracted (`renderer.luau:2260-2290`) assigns the mutable upvalues `notifyingSolved`, `feedbackMark`, `feedbackArmed` AND calls `resolveForFeedback`, which is declared BELOW `solveAndApply` (its doc block starts at `:2293`) — a `local function notifySolved()` above `solveAndApply` would capture a nil global and fail inside a `pcall`ed boundary. So: `local notifySolved: () -> ()` declared beside `solveAndApply`, ASSIGNED (`notifySolved = function() … end`) after `resolveForFeedback` is defined, and both call sites call through the local.

Build `lane = translate_lane.new({...})` right after `rectPass` is built (`:1632-1640`), with `lastResultRects = function() return if lastResult ~= nil then lastResult.rects else nil end`, `metrics = currentMetrics`, `channelArmed = channel.armed`, `hitLiftRefresh = hitLift.refresh`, `syncZOrder = function() syncZOrder() end` (the call is at `:2668`), `inputSinks = inputSinks`. `layout_node.applyPlacement` + `layout_node.resolveOffset` exported.

**`livePaths` fills `geometry.spaceHostHasPath` AND `geometry.pathHostOf`, and every ±1 site RIDES A LATCH THE SOURCE ALREADY KEEPS (review B-2, mechanism settled at D-0).** Not an unconditional `+1` per `Path` per walk: the BOUNDED structural arm re-walks live nodes and never calls `clearHosts()`, so a per-walk increment would ratchet the count upward forever and the host would refuse the lane for the life of the session — which is precisely what the pin above drives. Three clauses:

1. **The `+1` rides `livePaths`' EXISTING latch transition** (`renderer.luau:1459-1463`). The walk already computes `local isPath = node.class == "Path"` and already branches on `if isPath ~= (pathNodes[node.path] ~= nil) then` to keep `pathNodeCount`. Note on the SAME edge — **only when `isPath and pathNodes[node.path] == nil`**, the first sighting of this Path — so a re-walk of an unchanged Path notes nothing. **The write `pathNodes[node.path] = isPath or nil` (`:1464`) stays AFTER the note**, or the edge is already gone when it is read.
2. **The reparent branch, ordered BEFORE `hostSpaceOf[node.path]` is rewritten for this walk.** A Path that is still the same Path but now sits under a different space host must decrement the OLD chain and increment the NEW one. Both sides go through **`geometry.noteFromHost`** (T1's second entry point), never `noteUnder`: `noteUnder(map, oldHost, -1)` would start at `hostSpaceOf[oldHost]` and SKIP `oldHost` itself, and on this line `hostSpaceOf[node.path]` still holds the OLD host, so `noteUnder(map, node.path, …)` would walk the stale chain either way. `space` is the nearest space host THIS walk computes for the node (T3 step 6's sixth parameter, written to `hostSpaceOf[node.path]` afterwards):

```luau
		local isPath = node.class == "Path"
		if isPath then
			--[[ THE COUNT RIDES THE LATCH (Plan C, T5; reviews B-2 / D-0). Never an
				unconditional +1: the bounded structural arm re-walks LIVE nodes and
				never calls `clearHosts()`, so a per-walk increment ratchets and gates
				this host's lane forever. `noteFromHost`, NOT `noteUnder` —
				`hostSpaceOf[node.path]` is still the OLD host on these lines. The two
				arms are EXCLUSIVE by construction: the first sighting is the only one
				that sees `pathNodes[node.path] == nil`, and it sets `pathHostOf`. ]]
			if pathNodes[node.path] == nil then
				geometry.noteFromHost(geometry.spaceHostHasPath, space, 1)
				geometry.pathHostOf[node.path] = space
			elseif geometry.pathHostOf[node.path] ~= space then
				geometry.noteFromHost(geometry.spaceHostHasPath, geometry.pathHostOf[node.path], -1)
				geometry.noteFromHost(geometry.spaceHostHasPath, space, 1)
				geometry.pathHostOf[node.path] = space
			end
		end
		if isPath ~= (pathNodes[node.path] ~= nil) then
			pathNodeCount += if isPath then 1 else -1
		end
		pathNodes[node.path] = isPath or nil
		-- ...and only NOW this walk's own `geometry.hostSpaceOf[node.path] = space`
		-- (T3 step 6), which is what makes clause 2's comparison the OLD-vs-NEW one
```

3. **The `−1` rides `sweepDeparted`'s EXISTING guard** `if pathNodes[path] ~= nil then` (**`renderer.luau:2584`**) — which is also the answer to how `sweepDeparted` knows the departed node was a Path: the node is gone, but that latch map says so. The decrement goes INSIDE that guard and **BEFORE `geometry.dropPath(path)`**, which clears `hostSpaceOf[path]` and `pathHostOf[path]` and would leave the walk nothing to climb: `geometry.noteFromHost(geometry.spaceHostHasPath, geometry.pathHostOf[path], -1)` (`dropPath` then clears `pathHostOf[path]` with the other maps — review N-8). `livePaths` only ever visits LIVE nodes, so without this a removed Path keeps its host gated forever.

`noteUnder`/`noteFromHost` delete the key at zero, so the gate stays the plain truthiness test it is written as. **`spaceHostHasPath` is their ONLY consumer**: there is no `hostSinkCount` and no `hostHitCount` (R-12), so `inputSinks` and `commit_walks.hitRects` get no hooks. Renderer size check after — **against R-14's T5 budget (≤ +900) and the 197,500 STOP line**; if breached, take `src/render/dirty_closure.luau` (T3 step 0b) in its own commit. Not `livePaths`.

- [ ] **Step 4: fixture drives.** `nameplates_scene`: `Opts.reactiveAnchor` (plates bind `anchor = item.anchor` signal, default `"topLeft"`), `scene.anchorFlip(i)` (`"topLeft" ↔ "top"`), `scene.moveOut(i)` (`item.x:set(-500)`), `Opts.withButton` (plate 3's Row gains a `UI.Button({ id = "Btn", width = px(20), height = px(16), label = "b" })`), **`Opts.withPath` is reused, not added** (it exists at `nameplates_scene.luau:120`) — confirm its Path sits UNDER a space host, which is what the `spaceHostHasPath` gate needs, and move it there if not; `scene.clearOffset(i)` (`item.x:set(nil)` — the R-10 nil-flip drive). Update the oracle spec's drive list with `anchorFlip {round}`, `moveOut {round}` then `tick-back`, `clearOffset {round}` then `tick-back`, and `withButton`/`withPath` fixture rows.

- [ ] **Step 5: green + moved pins.** The T3/T5 demonstrator, the O3 spec's pure-tick case (now a MIXED drive so the arm is still exercised — header says why), `nameplates_baseline` ("a pure tick" case becomes "a pure tick LANES; the caster tick is the solve" with both tables), `commit_translate` (pure cases → lane deltas; walk pins on the caster tick), `host_space_oracle` green on 9 views × 5 fixtures × 4 arms. `tests/layout_prop_dirt.spec.luau` unchanged and green. Step-7 mutation: comment out the `lane.run` call → every lane pin red, the oracle STILL green (the lane is an optimisation; the oracle proving nothing here would be the check-that-proves-nothing) — record the mutation's bite count in the ledger.

- [ ] **Step 6: RR lockstep — and the lane's verdict on the FULL Sponsor surface (review IM-4).** Move the three RR specs' pins as the Files block states (with the measurement in each header); `facet_translate_host_contract.spec` gains "a dots-only frame: `solves=0 lastLaneTranslates=8`, same `screenRectOf` literals". **That pin is on the isolated `mapSurface` fixture (`facet_commit_translate.spec.luau:132-162`, `MapCanvas.build` alone at 300x300) where `lastHitRects` may well be empty — it proves nothing about the shipped screen.** So add the real one: mount the FULL Sponsor surface the way `facet_sponsor_table.spec` mounts it (hit expanders elsewhere on the screen, a `DotHit` `UI.Button` under every dot, and — with an omen incoming — a `UI.Path` tick ring), drive a dots-only frame, and pin the lane's actual verdict: `solves`, `lastLaneTranslates`, and which dots refused and why. R-12 predicts the dots LANE (sinks no longer gate; the lane serves `hit_lift`) and that a dot carrying a Path refuses. **Whatever the number is, the closing report says it plainly** — "RR's minimap dots take the lane" or "RR gets T3's write collapse but not T5's lane" — because the isolated-fixture pin passing is exactly how the plan would otherwise ship a fast path its only production consumer never enters. RR suite green. Studio: FacetBench nameplates L loop drive (marker, focused) → the tick's live number beside vide 0.298, ratio stated; RR canary (minimap moving, 0 quarantines) — same recipe as T4 steps 4-5. Commit Facet (`T5: the translate lane — an all-placement tick solves nothing`), RR, FacetBench (§C6 in the report).

---

### Task 6 (C2): the node-resident last-measure serve (profile-gated by T0 §before (c))

Build ONLY if T0's spans put `Facet/measure` (or `solver.solve` minus `Facet/arrange`) at ≥5 % of `battle_hud updateItem-hp`, `war_room setState`, or `killfeed updateItem-hp`; else write the booking line into the report and skip to T7.

**THE PUBLISH TABLE — written into `tests/measure_serve.spec.luau`'s spec header AND the ledger BEFORE any code (ruling R-11; the T9 lesson's rule (1)).** R-9 originally said the serve republishes "the SAME three channels the anchor arm republishes". `measure`'s memo-hit path (`solver.luau:1619-1918`) publishes **eleven**, and a small tuple cannot carry eight of them — so those are GATED, not served, and the gate is what makes the serve legal:

| # | channel | site | verdict |
|---|---|---|---|
| 1 | `ctx.offers[wKey]` / `ctx.offers[hKey]` | `:1786-1787` | **SERVED** — re-recorded from the offer in hand |
| 2 | `ctx.textStates` / `ctx.compact` / `ctx.textFacts` | `:1840-1842` | **SERVED** — from `node.lastTextState/lastCompact/lastTextFacts` |
| 3 | `ctx.fitCuts += hit.cuts` | `:1813`, `:1850` | **SERVED** — `ctx.fitCuts += node.lastCuts`, a number recorded at every return |
| 4 | `ctx.compositions[node.id]` | `:1847` | **GATED** — it feeds the public `controller.compositionAt`, and a tuple cannot carry a composition. Refuse when `node.subtreeHasComposition` |
| 5 | `ctx.hasScroll` | `measureUncached:1936` | **GATED** — refuse when `node.subtreeHasScroll` |
| 6 | `armContainer` → `ctx.scopeKey` | `:1944` | **GATED** by the same two booleans plus `node.containerRelativeInside == true` |
| 7 | `ctx.boundary[node.id]` | `:1950` | **GATED** — analysis-only; refuse when `ctx.analyze` |
| 8 | adopted-slate diagnostics replay | `:1862` | **GATED** — refuse when `not ctx.measureQuiet` (the anchor arm's fourth gate, for the same reason) |
| 9 | `measureReuse.note(store, node.id)` | `:1898` | **NOT SERVED, stated** — a store HIT COUNTER, diagnostic only; a served call is not a store hit and must not be counted as one. The `measure_reuse` oracle compares against arm `c`, where the serve never fires, so the counter's meaning is unchanged where it is read |
| 10 | `ctx.measureCache[node] = perNode` | `:1764` | **NOT SERVED, stated** — a lazily-bound per-solve convenience; any later slow-path call on this node in the same solve binds it |
| 11 | `ctx.mdepth` push/pop + the `ctx.deepNesting` latch | `measureUncached:1926-1930`, popped `:2034` | **BALANCED BY CONSTRUCTION, stated** (review N-11) — the serve returns before both, so the depth it would have pushed is never reached and the pop it would have owed is never owed; `deepNesting` is a perf latch, and a later slow-path call on the same node still arms it. Listed rather than omitted, because an omitted channel is exactly the enumeration failure BL-3 was about |

**The two bottom-up booleans (R-11), SELF-INCLUSIVE (review N-6).** `layout_node.build` computes `subtreeHasScroll` and `subtreeHasComposition` on every node in the **same post-children pass that already computes `containerRelativeInside`** (`layout_node.luau:1405-1415`), so the walk is not new and the cost is one boolean per node:

```luau
	-- SELF-INCLUSIVE, the shape `containerRelativeInside` already has where it ORs
	-- `selfRelative`. `ctx.hasScroll` is set for the node ITSELF
	-- (`solver.luau:1934-1936`) and `ctx.compositions[node.id]` is written for the
	-- composition node itself (`:1847`) — so a child-only OR would leave the OWNER of
	-- each channel ungated, and a served ScrollView or Composition would drop its own
	-- publish. That is rows 4 and 5 of the table above, and it is the whole point.
	node.subtreeHasScroll = node.kind == "scroll" or anyChild("subtreeHasScroll")
	node.subtreeHasComposition = node.kind == "composition" or anyChild("subtreeHasComposition")
```

A node whose subtree — itself included — contains a scroll or a composition never serves, which is what makes rows 4-6 safe without republishing anything.

**Files:**
- Modify: `src/layout/solver.luau` (`measure` `:1619-…`: the serve at the TOP, before `memoPlan`; the MODULE-LEVEL `record(ctx, node, maxW, maxH, cutsAtEntry, w, h)` called at EVERY return, the serve's own included; `Ctx` gains `measureCalls`, `measureServed`; `work` publishes both; the anchor arm `:3136-3160` is LEFT AS IS — it is now a special case of this serve, stated)
- Modify: `src/render/layout_node.luau` (**`subtreeHasScroll` + `subtreeHasComposition`, SELF-INCLUSIVE, in the `containerRelativeInside` post-children pass `:1405-1415`**; the serve's `last*` fields live on the node table and a REBUILT node is a fresh literal without them — PIN that a dirty node is rebuilt fresh: `store.byNode[node].built ~= previousBuilt` after a prop write)
- Modify: `src/render/renderer.luau` (`stats.lastMeasureCalls`, `lastMeasureServed` from `result.work`, 2 lines each)
- Create: `tests/lib/deep_stack_scene.luau` (a `Screen › VStack(1000 × HStack{Text, Text})` world with `scene.text(i, s)`, `scene.width(i, px)`, `scene.snapshot()`, `scene.stats()`), `tests/measure_serve.spec.luau`; register both
- Modify (RR): `tests/facet_measure_fanout_contract.spec.luau` (`measured=26 arranged=24 …` etc. move WITH the measurement; the two accounting identities must still hold)

**Interfaces:** `work.measureCalls` (every entry into `measure`), `work.measureServed` (entries answered from the node's tuple); `stats.lastMeasureCalls`/`lastMeasureServed`; layout `Node.subtreeHasScroll`/`Node.subtreeHasComposition`/`Node.lastOfferW/lastOfferH/lastW/lastH/lastCtrW/lastCtrH/lastTextState/lastCompact/lastTextFacts/lastCuts`.

- [ ] **Step 1: the publish table, then red.** Write the eleven-row table above into the spec header and the ledger FIRST. Then `tests/measure_serve.spec.luau`: on `deep_stack_scene` (1,000 rows), warm, then `scene.text(500, "x")` → pins READ OFF THE RUN at HEAD: `measureCalls=<N≈2000+>` and `lastMeasured=1`; target after: `measureServed == measureCalls - k` with `k` = the nodes genuinely re-measured, READ OFF THE RUN, and `lastMeasured` unchanged (the stack's pass 1 still CALLS measure per child — that is T7's job). Plus the same `solves=1` line; a viewport `env:set` drive that must SERVE NOTHING (`measureServed=0`, no `reuse`); a `scene.width(500, 40)` (measure-class on the row's dim) whose served count EXCLUDES that row and its ancestors; **and one case per GATED row: a subtree with a `ScrollView` in it serves 0, a subtree with a `Composition` in it serves 0 (and `controller.compositionAt` still answers), an `analyze` solve serves 0, a non-quiet solve serves 0.**

- [ ] **Step 2: the serve.** At the top of `measure` (before `local store = ctx.measures`):

```luau
	--[[ THE NODE-RESIDENT SERVE (Plan C, C2 — rulings R-9 + R-11). A node with
		nothing MEASURE-classed dirty inside it, asked the same question it answered
		last solve, against the same container, answers from numbers on itself and
		never reaches the memo (a key string, a slate adopt, a map probe — the whole
		per-clean-sibling bill on a dirty path).

		THE GATE IS WHAT MAKES IT LEGAL. `measure` publishes ELEVEN channels (the table
		in this spec's header and in the plan's Task 6); three are served from the
		node and EIGHT cannot be carried by a tuple — `ctx.compositions` feeds the
		public `controller.compositionAt`, `ctx.hasScroll` and `armContainer` change
		the memo's own key, `ctx.boundary` is the analysis map. So the serve REFUSES
		whenever any of them could be live: two bottom-up booleans off
		`layout_node.build`, the container-relative flag, `ctx.analyze`, and
		`ctx.measureQuiet` (the anchor arm's fourth gate, for the diagnostics replay).
		Gate on the channel you cannot serve — never republish a guess. ]]
	ctx.measureCalls += 1
	local cutsAtEntry = ctx.fitCuts
	local reuse = ctx.reuse
	if
		reuse ~= nil
		and ctx.measureQuiet
		and not ctx.analyze
		and node.subtreeHasScroll ~= true
		and node.subtreeHasComposition ~= true
		and node.containerRelativeInside ~= true
		and node.lastOfferW == maxW
		and node.lastOfferH == maxH
		and reuse.measureContains ~= nil
		and reuse.measureContains[node.id] ~= true
	then
		ctx.measureServed += 1
		ctx.offers[node.wKey or (node.id .. "|w")] = maxW
		ctx.offers[node.hKey or (node.id .. "|h")] = maxH
		ctx.textStates[node.id] = node.lastTextState
		ctx.compact[node.id] = node.lastCompact
		ctx.textFacts[node.id] = node.lastTextFacts
		ctx.fitCuts += node.lastCuts or 0
		-- THROUGH THE RECORDER TOO (review N-4). R-11 says `record` is called at EVERY
		-- return of `measure`, and the source-scan pin below counts exactly that — so
		-- the serve's own return is not an exception. It is idempotent: it rewrites
		-- the same tuple, and `lastCuts = ctx.fitCuts - cutsAtEntry` reproduces the
		-- `node.lastCuts` the line above just added.
		return record(ctx, node, maxW, maxH, cutsAtEntry, node.lastW, node.lastH)
	end
```

**The recorder is a LOCAL CALLED AT EVERY RETURN — NOT a `measureBody` wrapper (R-11, and the T9 lesson's rule (4)).** `measure` has **six** returns (`:1659`, `:1666`, `:1815`, `:1865`, `:1904`, `:1917`), four of them early; a `local w, h = measureBody(...)` wrapper is the exact shape T9 names ("the wrapper here had two early returns that never reach it"). `measureUncached` has one return (`:2035`) and is the wrappable one, which is precisely why it is not where the record belongs. So:

```luau
-- MODULE-LEVEL, beside `measure` — NOT a local inside it (review N-7). It reads
-- `ctx` and `cutsAtEntry`, both per-call, so an inner `local function` would be a
-- fresh CLOSURE on every entry: 2,000+ allocations per solve on T6's own fixture,
-- inside the function T6 exists to make cheaper, in a function that today defines no
-- inner closures at all (`solver.luau:1619`). The per-call values become parameters.
-- Called at EVERY return of `measure`, so the tuple always describes the LAST answer
-- this node gave — uncached, memo hit or served alike.
local function record(ctx, node, maxW: number, maxH: number, cutsAtEntry: number, w: number, h: number): (number, number)
	node.lastOfferW, node.lastOfferH, node.lastW, node.lastH = maxW, maxH, w, h
	node.lastTextState = ctx.textStates[node.id]
	node.lastCompact = ctx.compact[node.id]
	node.lastTextFacts = ctx.textFacts[node.id]
	node.lastCuts = ctx.fitCuts - cutsAtEntry
	if node.containerRelativeInside then
		node.lastCtrW, node.lastCtrH = ctx.containerW, ctx.containerH
	end
	return w, h
end
```

and every `return X, Y` in `measure` becomes `return record(ctx, node, maxW, maxH, cutsAtEntry, X, Y)`, with `local cutsAtEntry = ctx.fitCuts` captured at the top of `measure` (above the serve, so the served return can use it too). **`cutsAtEntry` comes BEFORE the values, and that is load-bearing (review M-3):** two of the six returns are `return measureUncached(ctx, node, maxW, maxH)` (`:1659`, `:1666`) — a two-value call that cannot be spliced into the middle of an argument list. With the values LAST they stay one-liners and the trailing call expands to both:

```luau
		return record(ctx, node, maxW, maxH, cutsAtEntry, measureUncached(ctx, node, maxW, maxH))
```

With `cutsAtEntry` last, those two returns would need an undeclared temp binding, and an implementer who writes `record(ctx, node, maxW, maxH, measureUncached(…), cutsAtEntry)` silently drops the HEIGHT. **`tests/measure_serve.spec.luau` pins this by SOURCE SCAN**: read `src/layout/solver.luau`, isolate `measure`'s body, and assert `#(return statements) == #(record( calls)` — a new return added later without a record is then a red test, not a stale tuple. **The serve's own return is inside that count** (review N-4): `measure` has six returns today and the serve makes seven, all seven routed through `record`, so the pin is a plain equality with no stated exception — an exception plus `== n + 1` is the weaker form and reintroduces exactly the drift the pin exists to catch. (`lastCuts` is this node's own contribution: `ctx.fitCuts` at return minus `cutsAtEntry`.)

`Ctx`/`ctx` literal: `measureCalls = 0, measureServed = 0`; `work` publishes both; renderer copies to `stats.lastMeasureCalls/lastMeasureServed`. Solver size: expect +~2,400 chars — check against R-14; if under 1,000 headroom, take the SCROLL branch seam the ledger names FIRST (own commit).

- [ ] **Step 3: oracle + gates.** `host_space_oracle` + `translate_arm`'s O3 oracle + `measure_split`/`measure_reuse`/`rect_cow`/`node_reuse` oracles all green (they compare against arm `c` = no reuse = the serve never fires); the `deep_stack_scene` gains its own 3-arm oracle case in `measure_serve.spec` over the 9 views (text + width + viewport drives), **and the oracle's compare includes `controller.compositionAt` for the composition fixture** — row 4 of the publish table is a public reader and deserves a public pin. RR suite: move the fanout pins with the measurement. FacetBench `attr battle_hud L 3` before/after in the ledger. Commit `T6: measure serves a clean node from its own last answer, gated on the channels a tuple cannot carry (C2)`.

---

### Task 7 (C3): stack pass 1 serves clean children; the anchor branch skips clean children (profile-gated)

Build if T0's `Facet/arrange` span (or, after T6, the remaining `solver.solve`) is ≥5 % of an update class.

**Files:**
- Modify: `src/layout/stack.luau` (pass 1 `:134-149` + the hug pass `:150-158`: `deps.measure` is already the serve after T6 — so pass 1 costs one call per child; the remaining O(children) is the PLACEMENT loop `:347-437` which must run for every child because of the cursor. NO CHANGE to stack.luau unless T6's numbers still show pass 1 ≥5 % — then a `deps.measureIfDirty` that returns the node tuple WITHOUT the call overhead is the lever)
- Modify: `src/layout/solver.luau` anchor branch: a child that is `dirtyContains`-clean (not just measure-clean), same offer, `containerUnmoved`, AND whose parent inner box is unchanged (`node`'s own `pr` equalled `rect` — the anchor node took no size change: the branch knows because `arrange`'s reuse gate computed `pr.w == rect.w and pr.h == rect.h`; expose it as a local `sizeUnchanged`) → do not compute the placement at all: `out[child.id]` already holds the right entry; count `ctx.anchorSkipped`. Pin: on the nameplates caster tick, the Canvas's 200 clean plates are `anchorSkipped`, 50 offered/served
- Modify: `tests/stack_seam.spec.luau:163` ONLY if stack.luau changes (widen the ctx read-set deliberately)
- Create: `tests/anchor_skip.spec.luau`; register

**Interfaces:** `work.anchorSkipped`, `stats.lastAnchorSkipped`.

- [ ] Steps: red (caster tick pins `anchorSkipped=0` at HEAD → `= PLATES - CASTERS` after; a viewport change pins `anchorSkipped=0`), implement, oracles green, RR (`facet_anchor_arrange.spec` gains the new counter in its mixed-frame pin), commit `T7: the anchor branch skips a clean, same-offer child outright (C3)`.

---

### Task 8 (C4): the dirty-child index for the commit walks (profile-gated)

Build if, after T5-T7, `sum(cw.*) + rectPass` on `battle_hud updateItem-hp` is ≥5 % of the class (T0 says the four class-pruned walks are 2 % on nameplates but ~64 visits per walk on battle_hud — measure THAT class).

**Files:** `src/render/commit_walks.luau` (`skip` `:429-451`, the eight walks' child loops), `src/render/renderer.luau` (`dirtyScan`: per-node `dirtyChildren[path] = { childPath, … }` built beside `markDirtyIn` — the same ancestor walk records each step's child), `tests/commit_dirty_index.spec.luau`.
- Red: 1-leaf update on `deep_stack_scene` pins `lastCommitVisitsByWalk.harvest = <~1002 or 64?>` at HEAD (READ OFF THE RUN) → target `≤ depth + 2` (≈4). Mechanism: a walk at a node that is in the dirty set descends ONLY the children named in `dirtyChildren[node.path]` (plus — for `visible`/`hitRects` — every child when `flipped`), instead of scanning all siblings and asking `skip` of each. `hitRects` keeps its `sawChrome` full-walk latch. Oracle green; RR fanout `lastCommitVisits 182` moves with the measurement. **`python3 tools/check_source_size.py` against R-14's T8 budget (≤ +600) and the 197,500 STOP line — record the delta in the ledger; if breached, take `src/render/dirty_closure.luau` (T3 step 0b) in its own commit first.** Commit `T8: commit walks descend by the dirty-child index (C4)`.

---

### Task 9 (C5): bound `syncZOrder` and `collectRetiringRoots` (profile-gated)

Build if `ssZOrder` ≥5 % of a structural class after T3 (T0 §before: nameplates add 0.252 of ~0.85 ms ⇒ ~30 % — likely IN).

**Files:** `src/render/renderer.luau` (`syncZOrder` `:2377-2410`: take an optional root list; under a bounded structural sync (`roots ~= nil`) walk from each root's nearest COORDINATE-SPACE HOST ancestor (a real parent under `ZIndexBehavior.Sibling` is a z scope: siblings inside it never interleave with nodes outside), starting `z` from `lastZ[hostPath]`; the hit-lift re-run at `:2185` stays whole-tree — it is rare; `collectRetiringRoots` `:549-561`: incremental — on a bounded sync, only re-scan the roots' subtrees and keep the other entries), `tests/zorder_bounded.spec.luau`.
- Red: `scene.add(1)` pins `lastZVisited = MOUNTED` at HEAD → target `≤ NODES_PER_PLATE + 2`; a negative control: add a plate whose parent is NOT a space host (a second `Anchor` canvas without hosts) → the walk is whole-tree (the same number as HEAD). The z of every node equals the whole-tree walk's, and **the differential is stated, not left as a question (review MI-5): the fake stores the z as `handle.z` (`fake_target.luau:881-884`) — there is no `adapter.node(p).zIndex` — and `nameplates_scene.Opts` has no `structuralReuse` (it has nine fields, `:112-130`). So this task ADDS `Opts.structuralReuse` to the fixture and compares `adapter.node(p).z` across arm `a` (bounded) and an arm with `structuralReuse = false` (whole-tree). No test-only `controller._zOrderFull()` seam.** **`python3 tools/check_source_size.py` against R-14's T9 budget (≤ +600) and the 197,500 STOP line — record the delta; if breached, take `src/render/dirty_closure.luau` (T3 step 0b) first.** Commit `T9: the z walk is per host on a bounded structural sync (C5)`.

---

### Task 10 (C9): closing — the matrix, the Studio drive, the report, RED-TEAM, memory

**Files:** FacetBench `docs/studio-runs/2026-09-03-facet-parity.md` (§after, §ABBA, §chart, §misses), `results/*.json`, `runner/studio/main.luau` (marker); Facet `docs/superpowers/specs/2026-09-03-facet-parity-design.md` (an "as built" appendix naming R-1..R-15 (with R-8 shown as REPLACED by R-13) and every spec deviation), `CHANGELOG`/`docs/reference/api.md` wording ONLY if a sentence became false (the numbers did not move: `docs/reference/api.md:2705`'s "solved rect" stays true — add one clause "composed from its host chain"); memory files + `tasks/lessons.md`.

- [ ] **Step 1: Lune after-matrix + ABBA.** `lune run runner/lune/run_matrix --frameworks facet --sizes L --out artifacts/parity-after-lune.json`; ABBA per headline class (nameplates tick pure via `tests/lib` fixture through `attr`'s `--step` if it has one, else the arena's caster tick; battle_hud hp; war_room setState; killfeed hp) B/A/A/B with the T0 checkout as A (a second sibling checkout at the T0 commit, or `git stash`-free: `git worktree add ../Facet-T0 <sha>` and point `attr` at it via its `FACET` constant — record which).
- [ ] **Step 2: Studio.** All five workloads L, `_fixture` + `facet` + `vide`, loop mode one workload per `main.run`, frames mode after; scrape; `byKind` gives the FIRST per-class vide rows — put them beside facet's. Window focused; marker read back; pid killed.
- [ ] **Step 3: the report.** Per class: before (T0 Lune) / after / vide (live, per class now) / target / MET or MISS with the remaining mechanism named (e.g. "war_room reorder: O(shifted) floor, 7,335 rects × 7.0 µs — the per-rect constant is `applyOne`+`setRect`; not attacked"); the nameplates tick: pure (fixture, Lune) ≤1.0 ms with `solves=0`, `engineWrites=250`, `rectWrites=250`, AND the arena's caster tick beside vide 0.29 with the ratio; chart (the dataviz skill, one SVG/PNG under `docs/studio-runs/`); §rulings + deviations (R-3 named plainly, R-8 named as REPLACED by R-13, and R-2's implementation named); **§the RR verdict — one plain sentence saying whether RascalRally's minimap dots take T5's lane on the FULL Sponsor surface (T5 step 6), or get T3's write collapse only**; §what it cost (census, recycling, instance count, the T4 step 2 recycling number and whether T4b was booked).
- [ ] **Step 4: RED-TEAM** (`code-reviewer` agent, fresh context, whole branch diff `main..facet-parity` + the RR and FacetBench ranges), fix rounds ≤5, each fix its own commit with its own review.
- [ ] **Step 5: RR final canary** on the final tree (T4 step 5 recipe), suite counts recorded; Facet `tools/verify.sh full --jobs 1` once.
- [ ] **Step 6: memory + lessons.** `memory/facet-parity-campaign.md` (state, numbers, traps, next), `MEMORY.md` pointer, `tasks/lessons.md` entries for every correction the reviews produced.
- [ ] **Step 7: the branch menu** (`superpowers:finishing-a-development-branch`): nothing merged or pushed — the owner picks.

## Self-review (done while writing)

- Spec coverage: §5.1 → T3 (+T1 seam); §5.2 → T2+T3; §5.3 → T0 (engineWrites) + T3 (adapters, hit_lift, recycling measured in T4 step 2); §5.4 → T5; §5.5 C2 → T6, C3 → T7, C4 → T8, C5 → T9; §6 oracle → T3 step 8 + every task; RR lockstep → T3 step 0 / T3 step 10 / T4 / T5 / T6 steps; §8 → T10. **Deviations:** R-2 (translate hosts only by default; unify = T4 step 3), **R-3** (the lane consumes its qualifying entries and hands the REMAINDER to the solve, rather than refusing on any other dirt — spec §5.4's "never partially applies" is kept in its intended sense, all-or-nothing per validated candidate SET), R-9 as amended by R-11 (C2 mechanism, and the serve is gated rather than "republishes three channels"), **R-8 REPLACED by R-13** (no create-time Composition scan; the solver carries `ctx.spaceOX/spaceOY` and compositions are exact under a host at any time), no `refresh({ full = true })`.
- Names: `geometry.hostSpaceOf/spaceHosts/spaceHostHasPath/pathHostOf/hostOriginOf/originIn/noteUnder/noteFromHost/invalidateOrigins/clearHosts/dropPath` plus the internal `originCache`/`composedCache` — **all DECLARED in T1's `rect_reads` interface** so `clearHosts`/`dropPath` can never forget one; filled in T3 (`hostSpaceOf`, `spaceHosts`) and T5 (`spaceHostHasPath`, `pathHostOf`). **`noteFromHost` is the SECOND entry point onto `noteUnder`'s loop** (review D-0): it starts AT the host it is handed instead of at `hostSpaceOf[path]`, which is what T5's reparent branch needs on both sides — it runs before `hostSpaceOf[node.path]` is rewritten, and `noteUnder(map, oldHost, -1)` would skip `oldHost` itself. `noteUnder` is one line through it, so delete-at-zero lives in one place; **there is no `hostHitCount` and no `hostSinkCount`** (R-12). The per-commit `originOf(path)` closure over `originIn(result.rects, …)` is the FRESH-map origin (`hit_lift` and `commit_walks` ON THE COMMIT PATH, composing into the ENTRY's space); `hostOriginOf` is the `lastRects` origin (`coverRect`, `scroll_into_view`, and the LANE's own `hit_lift` serve, which runs no solve) — the split is decided by which map the composer reads, not by taste; `createOpts.hostSpace`, `RendererAttachOpts.translateHosts`, mount `node.hostSpace`, layout `Node.hostSpace` (T3); `ctx.spaceOX`/`ctx.spaceOY` + `arrangeBody` and its `arrange` wrapper (T3, R-13 — **`ctx.spaceOrigin` was considered and DELETED: its only candidate reader, `layout/dump.luau`, never sees a `ctx`**); `placement.anchorPlace` + `placement.innerBox` (T2, T5); `translateArm.translatable/translateDescendants` (T2, T3); `adapter.engineWrites()` (T0, all); `stats.laneTranslates/lastLaneTranslates` (T5); `layout_node.applyPlacement` + `layout_node.resolveOffset` (T5, R-10); `src/render/dirty_closure.luau` (the R-14 fallback seam, T3 step 0b); `arrangeBody` + the `arrange` wrapper and `layout_node.applyPlacement`'s post-literal call site (T3/T5); the two one-line producer composes — `tests/lib/large_text.auditRects` and `layout/dump.luau`'s `nodeDump` accumulator (T3); `record(ctx, node, maxW, maxH, cutsAtEntry, w, h)` + `Node.subtreeHasScroll`/`subtreeHasComposition` + `work.measureCalls/measureServed` (T6, R-11); `work.anchorSkipped` (T7); `nameplates_scene.Opts.hosts` (T3), `Opts.reactiveAnchor`/`Opts.withButton` + `scene.anchorFlip/moveOut/clearOffset` (T5), `Opts.structuralReuse` (T9). **`Opts.withPath` is NOT introduced by this plan** — it already exists at `nameplates_scene.luau:120`; T3 step 8 and T5 both REUSE it.
- Every name above is introduced in exactly one task (and `Opts.withPath` in none — it predates the plan) and used under that name everywhere later; the rulings table (R-1..R-15) is the index, and R-8's row records what it was replaced by rather than being deleted.
- Placeholders: T5 step 1 has four cases sketched with `…` or a comment-only body (the scaleOffset/metric-name case, the `hit_lift` serve pin, the entry-identity pin, the R-10 stale-build pin, the Slider case) — the implementer writes each from the described drive and READS its number off the run; T6-T9 are profile-gated and carry their mechanism + counters + red pins in prose because their exact shape is decided by T0's numbers (stated at each). Everything else carries code.

---

## As built — Task 10 (C9), 2026-09-06, at `ee5e3dc0`

The campaign is closed. The measurement, the chart and every verdict live in
`GameStudio/ui/FacetBench/docs/studio-runs/2026-09-03-facet-parity.md` **§after**
(committed at FacetBench `151237c`); this section records only what this plan owes its
own reader.

**The rulings held as written.** R-1..R-15 are the index above and none was reversed by
what shipped. Three carry deviations from the SPEC and all three are in the table on
their own row, not hidden here: **R-2** (translate hosts are the only trigger by default;
`createOptsFor` returns `nil` for a `ScrollView` or a `clipChildren` container outright,
and T4 step 3 measured the unify decision and pinned SCOPE), **R-3** (the lane consumes
its qualifying entries and hands the REMAINDER to the solve — spec §5.4's "never
partially applies" kept in its intended sense, all-or-nothing per validated candidate
set), and **R-8, which is REPLACED by R-13** (there is no create-time `Composition` scan;
the solver carries `ctx.spaceOX`/`ctx.spaceOY` down `arrange` and compositions under a
host are exact at any time). R-9 as amended by R-11 shipped gated. `refresh({ full = true })`
was never introduced.

**Task 10's steps, as executed.** Step 1: the ABBA ran as a **paired worktree** pair
(`git worktree add --detach` for Facet at `7cf6bb69` and `ee5e3dc0` beside a FacetBench
worktree at `74d8158` on BOTH arms) rather than by repointing `attr`'s `FACET` constant —
recorded here because the plan asked which. The arena is byte-identical across that range
apart from `attr`'s own counter names, so the swap is Facet and nothing else. Step 2 drove
all five workloads in loop and frames mode plus six settled-session probes, each in a fresh
client VM. Step 3's chart is `docs/studio-runs/2026-09-03-facet-parity-after.svg`. Step 4
(RED-TEAM) ran ahead of Step 5 under ruling C-1 and its wave is `d64c974c`, `a165317e`,
`21665305`, `ee5e3dc0`. Step 5's canary is §12 of the after-doc. **Step 6 (memory files and
`tasks/lessons.md`) is NOT done by this task** and is owed to the session that closes the
branch. Step 7 (the branch menu) is the owner's.

**The two sentences that had to change.** `docs/reference/api.md`'s "Two rect reads" said
`rectOf` answers "what the solver wrote" — under C1 the solver writes a HOST-RELATIVE
number beneath a coordinate-space host and `rectOf` composes the chain, so that clause
became false and now says so. Nothing else in `api.md` or the `CHANGELOG` moved: the
public numbers did not.

**What it cost, and what is owed.** The suite went 8,251 → **8,672**; `renderer.luau` ended
at 197,351 chars against R-14's 197,500 STOP with the `dirty_closure` fallback seam taken
as planned; `solver.luau` 187,617. `tools/verify.sh full --jobs 1` PASS tier=full 402.0 s,
0 `FAIL_RECOVERABLE`; RascalRally 3,599/0 with a clean live canary on a moving field.
Sixteen items are BOOKED or PARKED in §9 of the after-doc, and the first of them is not a
millisecond: **T18-B's `SOLVE_DRAIN_ROUND_CAP` trips in the boot window** on a wide text
key (`battle_hud` L, fresh client VM, step 118 driving nine batches past a cap of eight) —
bounded and named where it used to be a `C stack overflow`, but still a throw.

**Ruling C-3, as landed (fix round 2).** The cap now defers instead of throwing, and the
deferral OWNS its re-arming: `render/solve_queue.trampoline` returns `owed()` beside the
entry point, and the renderer asks it in three places — `refresh` solves when a round is
owed whatever the dirty queue says, `controller.textPending()` ORs it in, and
`initialRender` stops draining the dirty queue while a round is owed. The third is what
fix round 1 was missing and what the RED-TEAM's F1 found: a cap tripped at MOUNT was
stranded for the session, because `initialRender`'s post-solve `takeDirty()` consumed the
dirt the deferred round was the build for and `refresh` then marked that same dirt
classified (`nodeDirtySeen`), so even a forced full solve served a stale layout node —
twenty ordinary frames, zero solves, permanently clipped text where the parent commit had
a loud throw. Also landed: a throwing frame now discards only what its OWN solve queued
(F3), the one diagnostic line names the surface and the measured mechanism instead of the
hypothesis this ruling refuted (F5/F7), and `stats.drainDeferrals` makes a trip assertable
without scraping warnings (F8). `renderer.luau` 197,366 after the boundary-analysis seam
(`1d2680e0`); suite 8,682/0; RascalRally 3,599/0; the three-observable differential
md5-identical at `3db66551b80fe677d314f2092b0a0038`.

**Two more BOOKED by that round, both deliberately not built.** (1) **The drain's real
lever is upstream, not a better cap** (review F4). A cap counted in ROUNDS is not a
millisecond budget — a round is ~0.05 ms on a small surface and ~52 ms on the scene the
number was tuned against — but a wall-clock budget was refused here because it would make
round counts machine-dependent and move the converging-settle observables on an L scene (4
rounds × ~52 ms). The walk is one word per round BECAUSE each learned width brings the next
unmeasured row into the measured set; batching the surface's whole unmeasured vocabulary
into one round removes the walk instead of rationing it. That is step 2 of
`docs/plans/2026-09-06-facet-parity-D-goal.md` and the mechanism is now named there and in
`solve_queue`'s cap block. (2) **`SOLVE_FEEDBACK_ROUND_CAP` still raises out of `refresh`**
(review F6) — the same failure class C-3 exists to remove, in a different loop with a
different cause (a consumer publishing a layout prop derived from the rect that prop
moves). Untouched by ruling, carried in the D goal's "Booked, not perf" line, and the
`solve_queue` cap block no longer claims the two caps exist "for the same reason".
