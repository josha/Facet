# Facet Parity — Plan C ADDENDUM: the lever wave (T12–T17) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **REVISION 3 (2026-09-05), after adversarial review round 2**
> (`.superpowers/sdd/2026-09-03-facet-parity-C/levers-plan-review-2.md`: T12, T13, T14,
> T16 NEEDS AMENDMENT; T15 and T17 READY). Round 2 found **three blocking defects, all of
> them in revision 2's NEW code** — the carrier misaligns under a `ForEach` splice, T14's
> `pMain` was a placed extent compared against a measured one, and T16's `walked` could
> not reach `buildDescend` by the route named. **All three are fixed here, and two of them
> are fixed against MEASUREMENT rather than argument** (rulings A-14, A-15, A-16;
> §Amendment log — round 2). The headline correction: **T13's gate as written reached
> 1.4 % of `battle_hud L updateItem-hp`'s measure calls and T14's replay never fired on
> that class at all.** Read §Amendment log — round 2 before executing any task.
>
> **REVISION 2 (2026-09-05), after adversarial review round 1**
> (`.superpowers/sdd/2026-09-03-facet-parity-C/levers-plan-review.md`, all six tasks
> NEEDS AMENDMENT). Every MUST-FIX and SHOULD-FIX is dispositioned in **§Amendment log**
> at the foot of this file — fixed, or refuted with a citation. The blocking §0 finding
> (T13/T14 cached on a table that is rebuilt every tick) is answered by **ruling A-8**,
> which moves both caches onto the mount-keyed store entry and, in doing so, made both
> mechanisms **smaller**: T13 is now a per-child memo with no aggregate arithmetic at
> all, and T14 replays only when nothing moved. Every code block below carries a
> `<!-- verified: … -->` line naming the `sed -n` ranges at `e26c1daf` that the fields in
> it were read from. **`aade8fac` ("T9 fix round 1") landed after those reads and touched
> `src/render/render_stats.luau`, `src/render/z_order.luau` and
> `tests/zorder_bounded.spec.luau`**, so the `render_stats.luau` citations below have
> drifted by ~9 lines (`lastCommitScans` `:147` → **`:156`**, `publish` `:191` → **`:200`**;
> `render_stats_seam.spec.luau`'s `:89` and `:126` are unmoved). Every other citation
> resolves at `e26c1daf` unchanged. **Locate by the quoted symbol, never by number.**

**Parent plan:** `docs/superpowers/plans/2026-09-03-facet-parity-C.md` (Tasks 0–10). This
file is its ADDENDUM: the build wave the owner ruled for on 2026-09-04, ranked by
`.superpowers/sdd/2026-09-03-facet-parity-C/task-9b-assessment.md`. It renumbers from
**Task 12** so nothing collides with the parent's 0–10. **Task 10 (C9, closing) still
runs LAST**, after T17.

**Goal:** Remove the one defect that is 93 % of every remaining leaf-edit class — *a
container with one dirty child pays a full pass over all of its children*, paid four
times in four modules — and un-poison the headless instrument that has been hiding it.
`battle_hud` L `updateItem-hp` 1.824 ms Lune / 3.382 ms live → toward the measured floor
of **0.124 ms Lune / 0.129 ms live**, with every public counter, every rect and every
engine `Position` byte-identical.

**Architecture:** (1) **T12** makes the Lune arena honest: `tests/lib/fake_target` stops
building a formatted string on every `setRect` and stops walking the whole node map on
every coordinate-space host move. (2) **T13–T15** bound the three solve-side container
walks — `contentSize`'s per-child measure (T13), `stack.arrange`'s pass 1 + placement
loop (T14), `layout_node.build`'s rebuild child loop (T15) — **all three through ONE
carrier**: a per-container memo table that lives on `store.byNode[node]` (mount-keyed,
weak) and is handed to the fresh layout node on every rebuild, under one shared validity
gate (`kids` identity, `axis`, `clip`). (3) **T16** does the same for the commit's
sibling probe, profile-gated. (4) **T17** attributes the live-only 1.5 ms.

**Tech Stack:** unchanged from the parent — Luau under Lune 0.10.4, stylua,
`tools/test.sh`, `tools/verify.sh affected --jobs 1`,
`python3 tools/check_source_size.py`, `python3 tools/commit_isolated.py`;
`tests/lib/fake_target.luau` is the headless render target; FacetBench (`../FacetBench`,
`main` at `af4f519`) is the arena; RascalRally
(`../../../games/RascalRally/code`) is the production consumer.

**Spec:** `docs/superpowers/specs/2026-09-03-facet-parity-design.md` remains the
authority for behaviour (nothing here changes behaviour). The MEASUREMENT authority is
`.superpowers/sdd/2026-09-03-facet-parity-C/task-9b-assessment.md` §2, §3, §6 — lever
letters map L2→T12, L1a→T13, L1b→T14, L1c→T15, L1d→T16, L3→T17.

**Every line number below is at HEAD `e26c1daf` and DRIFTS as tasks land — locate by the
quoted symbol or comment, never by number.**

---

## Task 11 — CLOSED-SUBSUMED (ruling A-1)

**Task 11 (`stack.luau` pass 1, `deps.measureIfDirty`) is closed without being built.**
T7's fix round booked it at "8.3–21.6 % of every `battle_hud` update class" off a
`profile.span("StackPass1")` reading. T9b built the working prototype — a `measureFast`
answering from the node's `mA*`/`mB*` slots without entering `measure` at all — and
measured it **ABBA**: measure entries `2,221 → 1,118`, clock `battle_hud` L
`updateItem-hp` **1.824 → 1.729 ms (−5.2 %)**, `setState` −4.5 %, `addItem-damage`
−4.0 %. The booked gate measured the *whole* of pass 1; the lever is the call overhead
alone, ~0.095 ms.

**It is subsumed by Task 14**, which removes the pass-1 call site for clean children
outright. Its one durable finding is carried into **T13's owed list row 1**: a fast path
that skips `measure` also skips the two `ctx.offers` writes, and `ctx.offers` feeds the
`offerW`/`offerH` of an entry literal
(`solver.luau:2429-2437`) — a `nil` there disarms both anchor arms for the life of the
surface (T7 finding 2).

---

## The conflict table (review §"Task ordering and shared-file conflicts")

Every pair sharing a file or an interface. Clean pairs are listed too, because the review
found the *omissions* to be the problem.

| Pair | Shared file / interface | Produces → consumes | Verdict |
|---|---|---|---|
| T13 → T14 → T15 | **`store.byNode[node].cmemo`** (ruling A-8) | T13 creates the carrier and the validity gate; T14 adds `p*` fields to the SAME table; T15 adds `childArray` to it | **CLEAN, and mandatory in this order.** One carrier, one gate, three payloads. T14 and T15 must not invent a second home. ▲ **The gate is a CONSERVATIVE SUPERSET, not a sufficient condition** (ruling A-14): `prior.kids` is the MOUNT children table and every index-keyed payload is indexed against the LAYOUT children, so T13 and T14 each carry their own `mIds`/`pIds` id key and T15 carries the `store.dirty` child scan. Only T15's payload is safe on the carrier gate alone. |
| T13 ↔ T14 | `cmemo.mMain` (measure offer) vs `cmemo.pMain` (arrange offer) | T13 writes `mMain` at `(innerMaxW, innerMaxH)`; T14 writes `pMain` at `(innerW, innerH)` | **CLEAN — separated by ruling A-9.** T14 does NOT read or write T13's arrays. The two offers are different questions (`solver.luau:1380` vs `stack.luau:144`). |
| T13 ↔ T14 ↔ T13-step-4 | `src/layout/solver.luau` characters | 190,112 now; STOP 197,500 → **7,388 usable** | **SPLIT (ruling A-10):** T13 ≤ +3,200, T14 ≤ +1,600, T15 ≤ +0 (it edits `layout_node.luau`), T16 ≤ +400, reserve 2,188. T13 step 4 (L5) spends from T13's own 3,200 or is dropped. Seam-first if T13 alone would exceed 3,200. |
| T13, T14, T15 → `src/layout/solve_ctx.luau` | `Ctx` type + `new()` initialiser | each adds one counter field (`childVisits`, `arrangeEntries`) | **NOT CLEAN unless listed.** `Ctx` is declared in `solve_ctx.luau` (`:79,:89,:131,:178,:194,:248,:249,:252,:269,:274`), NOT in `solver.luau`; `new()` is `:311-377`. **Both files are in each task's Files list now.** `tests/solve_ctx_seam.spec.luau` pins the field-set size — each task moves it. |
| T13, T14, T15, **T16** → `src/render/render_stats.luau` + **`tests/render_stats_seam.spec.luau`** | one new `last*` field each — `lastChildVisits`, `lastArrangeEntries`, `lastBuildChildVisits`, **`lastCommitProbes`** | the seam spec pins the export set (`:89`), the `new()` field SAMPLE (`:104-119`), the 4-arg `publish` call (`:126`, `:135`) and "one `new`, one `publish`" in the renderer (`:163`) | ▲ **RE-GRADED (review round 2 §3.7, §3.8): FOUR tasks, and the coupling is WEAKER than revision 2 claimed.** `:104-119` is explicitly *"a SAMPLE of the record's own contract, one field per family, so a field deleted in a later edit is caught here"* — it is a fixed literal list, so **ADDING a `last*` field does NOT redden it and no task should plan a red around it.** Adding the new field to the sample is good practice and stays. **Nothing in this spec catches a new `last*` field; the pin that actually does is each task's OWN equality on its counter, read off the run in its new spec** (Global Constraints, "each task pins TWO numbers"). The genuinely load-bearing pins here — `:89` and `:163` — are untouched by all four tasks. |
| T15 ↔ T16 | `src/render/renderer.luau` characters | T15 needs `stats.lastBuildChildVisits = nodeStore.childVisits` beside `:2024`; ▲ T16 needs two ARGUMENTS at the `harvest` call (`:2109`), not two ctx fields at `:1536` (ruling A-14's sibling correction, review round 2 §3.5) | **NOT CLEAN — re-split (ruling A-10):** wave cap raised from ≤ +200 to **≤ +400 total**: T15 ≤ +120, T16 ≤ +280. `renderer.luau` is 195,709, STOP 197,500. |
| T16 → `src/layout/solver.luau` | exporting `work.walkedIds` | `ctx.walkedIds` exists (`solve_ctx.luau:269`, written `solver.luau:2509`, read `:3506`) but is **NOT** on the `work` literal (`solver.luau:3515-3538`) | **NOT CLEAN — now listed.** One line in the `work` literal, budgeted from T16's ≤ +400 solver allowance. |
| T16 → `src/render/commit_walks.luau` **`harvest`** | two new OPTIONAL trailing parameters | `harvest`'s parameter list (`:795-807`, called `renderer.luau:2109`); `commitDirtySet` is the precedent | ▲ **RE-ROUTED (review round 2 §3.5, BLOCKING). `CommitCtx` is NOT touched.** `commit_walks.new` runs ONCE PER ATTACH (`renderer.luau:1532-1536`, its own comment) while `ctx.walkedIds` is a new table every solve, so a ctx field would be frozen at nil. Consequence: `tests/commit_walks_seam.spec.luau`'s bidirectional `CommitCtx` pins (`:203`, `:216`, `:223`) are **untouched**, and `tests/commit_dirt_classes.spec.luau:966-975` / `tests/commit_translate.spec.luau:330-343` — POSITIONAL `walks.harvest(…)` calls, not ctx builders — stay green with the filter off. **Editing those two is optional coverage, not a prerequisite.** |
| T14 → T16 | `ctx.walkedIds` population | T14's replay `return`s out of `stack.arrange` without entering the placement loop, so a replayed container never `place`s its clean children, so they are never marked walked — which is the same set the solve did not touch | **CLEAN, and now stated in T16's owed list.** Also: `walkedIds` is written only under `if reuse ~= nil` (`solver.luau:2508`), and the commit prune is off on a non-reuse solve (`commit_walks.luau:814` `pruning = enabled and dirty ~= nil and stampSame`) — T16 carries that dependency explicitly instead of inheriting it. |
| T12 → T13–T16 | `attr` baselines | T12 changes the harness | **CLEAN as ordered (A-2)**, but every "before (post-T12)" number in T13–T16 is a **prediction**; each task re-reads its own before-column at its parent SHA (arm A). |
| T12 ↔ T13–T16 | **`tests/lib/deep_stack_scene.luau:229`, `tests/lib/nameplates_scene.luau:289`** | T12 gates `ops` per `fake_target.new()` call; these two helpers build the fixtures T13–T16 pin counters on | **NOT CLEAN — resolved by ruling A-11:** `ops` stays **OFF** in both helpers. Arming it there would re-poison the exact rows T12 exists to clean. Specs that need `ops` on those fixtures pass a per-call opt. |
| **T13, T14, T15, T16, T12 → `tests/run.luau`** | the hand-kept require list | each task registers exactly one new spec (`fake_target_ops_opt`, `container_memo`, `stack_replay`, `build_children_reuse`, `commit_probe_filter`) | ▲ **NOT CLEAN — five commits, one file, and it had NO row** (review round 2 §3.7). Sequential by construction, and each task appends its own line; a task that finds the file already carrying a later task's require has a stale tree and STOPS. |
| **T13, T14, T15, T16 → `tools/lune/verify/data/source-cap-ledger.md`** | each records a size | T13 `solver.luau`, T14 `solver.luau` + `stack.luau`, T15 `renderer.luau`, T16 all three | ▲ **NOT CLEAN — four commits, one file, and it had NO row** (review round 2 §3.7). Each task appends its own row in its own commit; never rewrite an earlier task's line. |
| **T13 ↔ T15** | **`layout_node.luau`'s store-entry literal AND the `local prior` read** | T13 introduces `local prior` immediately before the entry write and adds `cmemo`/`kids`; T15 adds `childArray` to the same literal **and HOISTS `local prior` above the child loop at `:1348`** | ▲ **A CODE-MOTION CONFLICT the "CLEAN, and mandatory in this order" row above does not name** (review round 2 §3.7). Ordering fixes it — T13 first, T15 moves T13's own line — but T15's step 3 must state the hoist explicitly and its diff must show the line MOVED, not duplicated. |
| T12 ↔ the other agent | `tests/zorder_bounded.spec.luau`, `src/render/render_stats.luau` | T12 must arm `ops` in `zorder_bounded.spec:140,146`; T13/T14/T15 all edit `render_stats.luau` | **CLEARED 2026-09-05 — those three files landed as `aade8fac` and the tree is clean.** T12 no longer waits. Still check `git status --short` before starting and record it: the rule is standing, only this instance is closed. `zorder_bounded.spec`'s `ops` call sites may have moved off `:140,:146` in that commit — re-grep. |

---

## Global Constraints (inherited from the parent plan; deltas marked ▲)

- Facet repo `/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet`, branch **`facet-parity`**. Commits via `python3 tools/commit_isolated.py -m <msgfile> <path[:marker]>` (`--dry-run` first); **never amend; nothing merged or pushed**.
- Gates on EVERY Facet commit, FOREGROUND, one lune process at a time: `tools/test.sh` (full); `tools/verify.sh affected --jobs 1` BEFORE committing; `python3 tools/check_source_size.py`; `stylua --check src tests tools bench examples`. After any file EXTRACTION also run `python3 tools/check_brand_drift.py` by hand.
- **RascalRally lockstep on every Facet `src/` change:** `cd games/RascalRally/code && ./run-tests.sh 2>&1 | tee <transcript>` green at or above the recorded base (T9 closed at **8,452/0** Facet, **3,591/0** RR), plus the rider spec the task names. ▲ **Every task in this wave names its RR rider, T17 included.**
- ▲ **Source cap, re-split (ruling A-10), and RE-CHECKED after the round-2 amendments.** `solver.luau` **190,112**, STOP 197,500 → **7,388 usable**, split T13 ≤ +3,200 · T14 ≤ +1,600 · T16 ≤ +400 · reserve 2,188. ▲ **The round-2 amendments add characters the original split did not anticipate** — T13's `mIds` array and its comment, T14's `pIds`/`pHug`/`pShrink`/`pPrio` arrays and the record block moved up beside the hug pass (in `stack.luau`, which has no cap constraint), and T16's export moving from one field to a conditional. **Each task re-runs `check_source_size` BEFORE writing its comment block and again after stylua**, and a task over its split takes its named seam first (T13 step 0) or spends from the 2,188 reserve with an explicit line in the ledger saying which task took it and why. `renderer.luau` **195,709** → wave allowance **≤ +400 total**, split T15 ≤ +120 · T16 ≤ +280. `solve_ctx.luau`, `stack.luau` (21,399), `layout_node.luau` (96,496), `commit_walks.luau` (87,667) have no cap constraint. A task that would exceed its split STOPS and takes its named seam first, in its own commit.
- **No public API or behaviour change.** ▲ **No public counter may move except the ones each task names in its Interfaces block**, and a task that moves one re-records every pin on it — Facet AND RascalRally — in the SAME commit.
- **Counters, never wall-time.** Every demonstrator pins a counter AND `solves=N`; `scene.new()` → ONE discarded warm-up tick → the measured tick; pin idiom `` expect(`name={actual}`).toBe(`name={expected}`) ``. ▲ **Every acceptance number is an EQUALITY read off the run — never an inequality** (review cross-cutting: an inequality cannot be written in the mandated idiom). ▲ **Each task pins TWO numbers: (a) an EXISTING counter that moves, as equality at base, and (b) its new counter as equality after the counter-only step.** A "red" that is only a nil-index is not a red.
- ▲ **The AUDIT arm replaces "forced on" (ruling A-12).** T13 and T14 each ship a solve-opt (`containerMemoAudit`, `stackReplayAudit`, both default false, both test-only) that makes the fast path compute its answer **and** the slow one and assert equality inside the solve. The assessment demanded an arm that exercises the arithmetic on every container; forcing the *narrowing* gates off would produce legitimately wrong output, so the arm self-checks instead. Every 9-view oracle in those tasks runs with the audit arm on. ▲ **ITS ROUTE INTO A SPEC IS NOW NAMED (review round 2 §3.7).** `solveOpts` is built internally by the renderer (`renderer.luau:2024+`), so a spec reaches these opts the way the existing controls do — the **ATTACH-OPT path** that `node_reuse.spec`'s `layoutNodeReuse = false` and arm `c`'s `{ measureReuse = false, incremental = false }` already use. The two new opts ride the same channel; each task's step 1 names the attach call it uses, and **each task pins that the flag is ABSENT from the public surface** (a `tests/public_surface*`-class pin, read off the run). Without that route named and that pin recorded, T13 step 6 and T14 step 4 cannot be executed and the opts are an unadvertised public API.
- **Differential oracle** after every driver step, on the fake adapter, all 9 `device_views.VIEWS` incl. `narrow-portrait` 320x640: `scene.snapshot()` byte-equal to the full-solve arm `c` (`{ measureReuse = false, incremental = false }`); non-vacuity guard; `b`/`d` DRIVEN every step, COMPARED selectively. There is no `controller.refresh({ full = true })` and this wave adds none.
- **A fast path that skips a function owes a LIST of everything that function published** (the T9 lesson) — written into the spec header and the ledger BEFORE code, per-channel verdict served / gated / stated-unreachable.
- ▲ **Every task runs `attr` before it commits** (the standing rule T5 booked and no task has yet obeyed), and every task's before-column is READ at its own parent SHA, never inherited from this plan.
- ▲ **Three measurement arms, ABBA where the claim is milliseconds.** **A** = a detached worktree at the task's parent SHA (recorded); **B** = HEAD with the change; **C** = HEAD with the change's COUNTER only and the mechanism off. ▲ **Arm C publishes the counter from the SAME line arm B does**, or the ABBA compares a counter whose definition moved (review T16 MUST-FIX 4). Machine contention invalidates a two-arm read (T7): A/B/B/A interleaved, medians of ≥ 2.
- Spec discovery is the hand-kept require list in `tests/run.luau` — **every new spec is added there**, and considered for `tests/lib/tiers.luau` if it is a device-matrix oracle.
- `commit_walks.skip` compares ENTRY TABLE IDENTITY; rects are `table.freeze`d — never mutate a rect in place.
- Fresh-context adversarial review per task, ≤ 5 fix rounds, rulings in `.superpowers/sdd/2026-09-03-facet-parity-C/progress.md`; RED-TEAM at Task 10.
- ▲ **RESOLVED 2026-09-05: the T9 reviewer committed those three files as `aade8fac`; the tree is clean.** The hazard stands as a standing rule, not as a live blocker. `commit_isolated.py` stages only the named path — **name paths explicitly, never `git add -A`, and re-check your own edits are still present after every long-running command** (the T6/T7 shared-tree hazard). Record `git status --short` at the start of every task.

## Rulings

| # | Ruling | Why |
|---|---|---|
| A-1 | **Task 11 is CLOSED-SUBSUMED, not deferred.** | Measured at −5.2 % against a booked 8–22 %; T14 removes the call site. |
| A-2 | **T12 goes FIRST, before any product lever.** | `nameplates L updateItems-plates` is 23.99 ms Lune of which **21.34 ms is `fake_target.setRect`**; `war_room reorder` is 30.9 ms of which **10.28 ms** is. Ranking T13–T16 against those rows ranks against the instrument. |
| A-3 | **AMENDED. The container memo is keyed by the RAW offer pair the loop actually hands its children, plus `ctx.scopeKey` and `ctx.measureStamp`** — not by `offerHeightKey`. | `offerHeightKey` is `local function` at `solver.luau:1524`; `contentSize` is at `:919`, six hundred lines above it, so the call resolves to a global and throws (review T13 MUST-FIX 1). The raw pair is a STRICTLY NARROWER key: fewer hits, never a wrong one. `ctx.scopeKey` already carries the `\|fit` segment (`rebuildScopeKey`), so a `ViewThatFits` probe cannot collide. |
| A-4 | **AMENDED — WITHDRAWN. No aggregate is patched.** T13 caches PER-CHILD numbers and re-sums them; T14 replays only when nothing moved. | The review found four independent ways the aggregate arithmetic was wrong (post-shrink `aSum` against pre-shrink `aMain`, a truncated `shrinkBasis`, a `crossMax` argmax over a re-entrant scratch array, a fill pass that stops re-measuring). Every one of them is a property of *patching an aggregate*. Re-summing cached per-child numbers is exact by construction, costs an O(n) add loop that HEAD already pays, and removes the whole class. **The measured cost was never the sum — it was the `measure` call**, at 0.47 µs against ~0.03 µs for three hash reads. |
| A-5 | **Every counter this wave adds is a `last*` snapshot published from `work` / `nodeStore`, never a cumulative.** | They answer "how many children did this tick touch", a per-tick question. |
| A-6 | **AMENDED. T16's gate is `cw.harvest` ≥ 0.05 ms, stated as ≥ 10 % of the 0.5 ms campaign target — not as a share of its own class.** | The reviewer is right that a share gate is a tautology once T13–T15 shrink the denominator without touching `cw.harvest`, and that the absolute number is unchanged by construction. The honest gate is "is it worth ≥ 10 % of the target we are chasing". |
| A-7 | **T17 may deliver an ATTRIBUTION and a booking rather than a fix**, and step 4 now carries the STOP condition and the route (review T17 MUST-FIX 1). | 1.5 ms of live cost sits on a class with ZERO engine writes. If it is engine-side, naming the mechanism with a capture is the whole deliverable. |
| **A-8** | **NEW, and it is the blocking §0 answer. The container memo lives on `store.byNode[node]` as one field `cmemo`, and the layout node carries a POINTER to it (`layoutNode.cmemo`), refreshed on every rebuild.** The carry happens in `toLayoutNode`'s rebuild arm, gated on `prior.kids == node.children and prior.axis == parentAxis and prior.clip == (insideClipper == true)`; otherwise a fresh empty table. | `store.byNode[node]` is keyed by the MOUNT node and is `setmetatable({}, WEAK_KEYS)` (`layout_node.luau:1664`); the solver `Node` is a fresh literal (`:605+`) for any container in `store.dirty` (`:386-395`), which on `battle_hud L updateItem-hp` is **every ancestor of the changed leaf** — i.e. exactly the containers T13/T14 target. Fields on the layout node would be `nil` on every measured tick and both levers would return zero. The pointer keeps the solver's access a single field read; the weak mount-keyed entry keeps the lifetime. The three gate terms are the ones T15 needs anyway, so **one gate serves all three tasks**. A `store == nil` build (dump, fuzz, a direct `toLayoutNode` caller) has no `cmemo` and takes today's path exactly — the same "a solve with no reuse is the pre-change solver" property C2 has. |
| **A-9** | **NEW. T14 owns its own placement-time arrays (`pMain`, `pCross`, `pAlign`, `pLineAlign`, `pRect`) inside `cmemo`, and never reads or writes T13's `mMain`/`mCross`.** | `contentSize` measures at `(innerMaxW, innerMaxH)` (`solver.luau:1380`); `stack.arrange` pass 1 measures at `(innerW, innerH)` (`stack.luau:144`) and its `hug` children at `left` in a second pass (`stack.luau:153-160`). For a `hug` or `fill` container those are answers to different questions — the "measured-against-placed" class one axis over (review T14 MUST-FIX 2) — and a writer in the other's array poisons a cache it does not own (MUST-FIX 3). One owner per field. |
| **A-10** | **NEW. The `solver.luau` and `renderer.luau` budgets are split across the wave, not owned by one task.** solver 7,388 usable → T13 3,200 / T14 1,600 / T16 400 / reserve 2,188; renderer ≤ +400 → T15 120 / T16 280. | Revision 1 asserted T13 was "the only task competing", while T14 adds solver fields, T16 exports `work.walkedIds`, and both T15 and T16 need renderer lines (review T13 SHOULD-FIX 16, T15 MUST-FIX 2, T16 MUST-FIX 3). |
| **A-11** | **NEW. `ops` stays OFF in `tests/lib/deep_stack_scene.luau` and `tests/lib/nameplates_scene.luau`.** A spec needing `ops` on those fixtures passes a per-call opt through the helper; the helper's default does not change. | Those two helpers build the fixtures T13–T16 pin their counters on. Arming `ops` there re-poisons exactly the rows T12 exists to clean (review T12 MUST-FIX 4). |
| **A-12** | **NEW. The "forced-on" oracle arm the assessment demanded is an AUDIT arm, not a gate-bypass.** `containerMemoAudit` / `stackReplayAudit` compute both answers and assert equality inside the solve. | T13's shape gates (no `shrinkWeight` child, no verdict-publishing direct child) are CORRECTNESS gates — `solver.luau:1381-1385` builds `shrinkBasis` only in the measuring arm, and `record`'s `publishes` (`solver.luau:1596`) is `kind == "text" or kind == "composition"`. Forcing them off produces legitimately wrong output, so the fuzz would be comparing two wrongs. A self-checking arm exercises the arithmetic on every container the fuzz touches and cannot ship a wrong pixel. |
| **A-13** | **NEW, and a DISAGREEMENT with the review's T14 NOTE 14 (and with revision 1's own text). `node.distribute` is NOT a refusal term in the amended T14.** | NOTE 14 endorsed refusing `distribute` "because `lead`/`step` make δ non-prefix". True of a prefix REBASE — which A-4's amendment deleted. The amended replay fires only when **no** child's placement inputs changed, so `remaining` (`stack.luau:296`) is unchanged, so `distributionOf(mode, remaining, childCount)` (`stack.luau:343`) returns the same `lead`/`step`, so `cursor` (`stack.luau:349`) starts and advances identically. A `distribute` stack whose contents did not move has not moved. Refusing it would cost the lever every distributed row list for no correctness gain. The gate that replaces it is the one that makes the argument true: **every dirty child's main AND cross contributions, `align` and `lineAlign` unchanged, plus `gap` (the PARAMETER — `gap` is not a node field), `node.align` and the inner box unchanged.** ▲ **PARTIALLY SUPERSEDED by ruling A-15:** the argument above is about a `distribute` stack whose CONTENTS did not move, and it stands as written. It says nothing about a write that changes `node.distribute` ITSELF, which dirties the container and no child — so `pDistribute` IS a key term. |
| **A-14** | **NEW (review round 2 §3.1, BLOCKING). Every INDEX-KEYED payload on `cmemo` carries its own `id` array and compares it per child. The carrier gate (`prior.kids == node.children`) is a CONSERVATIVE SUPERSET, never a sufficient condition.** | `prior.kids` is the **mount** node's children; the arrays are indexed against the **layout** node's children, and `layout_node.luau:1357-1364` splices `When`/`ForEach`/`ErrorBoundary` grandchildren into the parent's flow, so the two are different lists. `mount.luau:450` replaces a REGION's `node.children`, never the enclosing panel's, so on `battle_hud`'s `addItem-damage`/`removeItem-damage` the panel's `prior.kids == node.children` HOLDS while every later index shifts. And `node.children` **is** mutated in place, at `mount.luau:197` (When exit-finish) and `:465` (ForEach exit-finish), each followed by `pushDirty(path, "structure")` (`:202`, `:470`). **Measured at `92d3e7e4`:** the index-keyed gate reads 98.0–100 % skippable on exactly those classes; the id-keyed one reads 0.0 %, and 0.0 % is the correct answer for a class whose indices moved. T15 is immune for a DIFFERENT reason — it scans `store.dirty[child.path]` over the mount children and `renderer.luau:2795-2804`'s prefix walk marks a region's own path — and that difference is now stated at both sites. |
| **A-15** | **NEW (review round 2 §3.3). T14's gate gains `node.distribute` (as the key term `pDistribute`), `child.shrinkWeight` and `child.layoutPriority` (as per-child arrays).** | Each changes a rect with **no measurement change**. `node.distribute` (`stack.luau:328`, consumed `:343`) dirties the CONTAINER and no child, so the replay's loop — which tests `dirty[child.id]` — finds nothing to re-measure and every child keeps its old cursor position. `child.shrinkWeight` (read `stack.luau:188`, consumed by `shrinkLib.stack` at `:208`) and `child.layoutPriority` (read inside that call, `shrink.luau:335`) dirty the CHILD, this arm re-measures it, the measurement is unchanged because neither is a measure input, and the shrink redistribution that should have happened is skipped. The alternative the review offered — refusing whenever the container itself is in `dirty` — is rejected: measured, that would cost every `setState` class, and `setState` is T14's actual headline. |
| **A-16** | **NEW (review round 2 §3.6). T13's `text`/`composition` refusal is PER CHILD only; the container-level `memoable = false` is DELETED.** | The per-child term already refuses every publisher, so `record` publishes exactly as today — the container-level kill added no safety and cost the lever its own headline. **Measured at `92d3e7e4`**, as the share of `contentSize`'s per-child `measure` calls the id-keyed skip arm can serve: 1.4 % with it and **96.8 %** without, on `battle_hud L updateItem-hp`; 3.3 % vs 97.2 % on `battle_hud L setState`; **0.0 % vs 75.2 %** on `killfeed L updateItem-hp`. `war_room_inventory` is unaffected either way (99.4–99.7 %) because its rows hold no direct `text` child — which is exactly why measuring one workload would have been the wrong evidence. |

---

### Task 12 (L2 → FacetBench §C10): the headless target stops being the measurement

**No Facet `src/` file is touched. No public Facet number moves.** Product gain zero;
measurement gain is that the next four tasks can be believed.

**Prerequisite (conflict table, last row): CLEARED.** `tests/zorder_bounded.spec.luau`
landed in `aade8fac` and the tree is clean as of 2026-09-05. Still run `git status --short`
and record it — and **re-grep `zorder_bounded.spec` for `.ops()`**, since that commit may
have moved the two call sites off `:140`/`:146`.

**The two charges, measured (T9b §2.4, §2.6):**

| # | site | cost | evidence |
|---|---|---|---|
| 1 | `tests/lib/fake_target.luau:646` builds `\`rect {handle.path} {rect.x},{rect.y} {rect.w}x{rect.h}\`` on **every** `setRect` | **1.40 µs/write** | `os.clock` brackets inside `rect_pass.applyOne`: `war_room reorder` **10.28 ms over 7,335 calls**, against `rectPass.apply` 12.97 ms and a Facet-side remainder of 2.42 ms (0.33 µs/rect) |
| 2 | `tests/lib/fake_target.luau:657-660` — a coordinate-space host's move iterates the WHOLE `nodes` map with `string.sub(path, 1, #prefix) == prefix` | **O(hosts × nodes)**, 85 µs/host | brackets inside `translate_lane.run`: `nameplates L updateItems-plates` `tApply` **21.11 ms over 248 hosts**, `adapter.setRect` **21.34 of the 21.49 ms lane span**; the same class LIVE is **2.876 ms** |

**Files:**
- Modify: `tests/lib/fake_target.luau`
  - `export type Opts` (`:161` `{ trackThemeRoots: boolean? }`) gains `ops: boolean?`. All **642** `fake_target.new(` call sites keep working with `ops` defaulting off.
  - **22** `table.insert(ops, …)` sites — verified exhaustively: `343, 483, 646, 701, 874, 958, 1030, 1039, 1101, 1111, 1147, 1184, 1257, 1419, 1453, 1464, 1528, 1570, 1711, 1838, 1866, 1882` (revision 1 said 21 and omitted `:1866`, `:1882` — review T12 SHOULD-FIX 5).
  - `adapter.ops()` (`:1047`) asserts when unarmed.
  - A `childrenOf` index maintained beside `nodes`, replacing the prefix walk at `:657-660`.
- Modify: **the nine helper sites in seven files** that build the target (review T12 MUST-FIX 4, verified list): `tests/lib/world.luau:142` (already takes an `o.newAdapter` factory; only 12 `world.new(` callers), `tests/lib/deep_stack_scene.luau:229`, `tests/lib/nameplates_scene.luau:289`, `tests/lib/large_text.luau:177`, `tests/lib/showcase_chips.luau:75`, `tests/lib/fault_scenarios.luau:387,552`, `tests/fixtures/soak_fixtures.luau:18`. **Per ruling A-11 the helper DEFAULT stays off**; each grows an optional pass-through so a spec can arm it per construction.
- Modify: the eight specs with real `.ops()` calls: `tests/zorder_bounded.spec.luau:140,146`, `tests/instance_recycling.spec.luau:423,565,568,569`, `tests/menu.spec.luau:853`, `tests/scroll_bar_measure.spec.luau:610`, `tests/commit_scope.spec.luau:356,542,549`, `tests/structural_scope.spec.luau:407,791,798`, `tests/drag_bridge_seam.spec.luau:527,530`, `tests/nested_tree_pins.spec.luau:360`. (`instance_recycling.spec:558` and `zorder_bounded.spec:136` are comments.) **In `commit_scope` and `structural_scope` both A/B arms must be armed** or the `#…ops()` mark comparison dies asymmetrically (review T12 SHOULD-FIX 7).
- Create: `tests/fake_target_ops_opt.spec.luau`; register in `tests/run.luau`.

**Interfaces:**
- Consumes: nothing new.
- Produces: `fake_target.Opts.ops: boolean?` (default **false**); `adapter.ops()` unchanged in shape, now asserting when unarmed. **No change to `adapter.setRect`, `handle.rect`/`storedRect`/`hitRect`/`presentedPosition`, or `adapter.engineWrites()`.**

- [ ] **Step 1: the owed list, then the pins.** Header + ledger: what `ops` is read for (the 18-call list above, path by path) and what the prefix walk publishes (`node.rect`, `node.hitRect`, `adapter._composePresentation(node)` → `presentedPosition`/`presentedSize`). Then:
  - **RED (a real red):** `it("a target built without ops refuses adapter.ops rather than answering empty")` — `expect(function() fake_target.new().ops() end).toThrow()`. Fails at HEAD because `ops()` returns `{}`.
  - **CHARACTERISATION PIN (labelled as such — review SHOULD-FIX 6):** `it("a coordinate-space host move recomposes exactly the descendants the prefix scan did")`. It passes at base *because the prefix walk is the implementation*; it exists to freeze the set before it is re-derived. Three fixtures: (a) a 3-deep host chain; (b) **a path-prefix sibling that is NOT a child** — `/S/Host` vs `/S/Host2/Leaf`, which the trailing-`/` semantics excludes; (c) **an ADOPT re-key** (review MUST-FIX 2 and 3): `adapter.adopt` writes `nodes[newPath] = handle` (`:1029`) and **never deletes the old key** — the three `nodes[…] = nil` sites are `:873`, `:936`, `:1124` — and `spaceOriginOf` (`:561-572`) walks `handle.instanceHost` → `hostFor(h.path)`, never the composed node's own path. So today's walk still visits the stale old-path entry. **The index must keep it too** (ruling: match today's behaviour exactly; fixing `adopt`'s leak is a separate change with its own oracle). Pin the composed positions for every node before and after.
  - Counters for the drive: `solves=1` on mount, `solves=0` + `lastLaneTranslates=1` on the lane-served move.

- [ ] **Step 2: the `ops` gate.**

<!-- verified: sed -n '160,168p;1045,1052p' tests/lib/fake_target.luau -->
```luau
	--[[ THE OP LOG IS OPT-IN (Plan C addendum, T12). All 22 `table.insert(ops, …)`
		sites below interpolate a formatted string, and `setRect` is on the commit's
		hot loop: 1.40 us per write measured from inside `rect_pass.applyOne`, which is
		10.28 ms of the 30.9 ms `war_room_inventory L reorder` class in FacetBench — a
		THIRD of a headline number spent by the instrument reading it.

		THE INTERPOLATION IS INSIDE THE GUARD, NOT AT THE CALL SITE. `note(\`rect …\`)`
		builds the string and throws it away. Only a guard the caller takes BEFORE it
		composes costs nothing, which is why every site reads
		`if recordOps then note(...) end` and why the source scan pins that spelling. ]]
	local recordOps = opts ~= nil and (opts :: any).ops == true
	local function note(line: string)
		table.insert(ops, line)
	end
```

  Each of the 22 sites becomes `if recordOps then note(\`…\`) end`. `adapter.ops()`
  becomes:

```luau
	function adapter.ops(): { string }
		assert(recordOps, "fake_target: the op log is opt-in — build this target with fake_target.new({ ops = true })")
		return ops
	end
```

  The spec pins by SOURCE SCAN that **no `table.insert(ops` remains** and that **every
  `note(` call is lexically inside an `if recordOps then`**.

- [ ] **Step 3: the parent→children index.**

<!-- verified: sed -n '163,166p;240,258p;480,484p;560,573p;648,672p;870,876p;1020,1032p;1120,1128p' tests/lib/fake_target.luau -->
```luau
	--[[ WHO IS DIRECTLY UNDER WHOM (T12). The coordinate-space recompose in `setRect`
		found a host's subtree by walking EVERY node in this target and testing
		`string.sub(path, 1, #prefix) == prefix` — O(hosts x nodes) per commit, which on
		FacetBench's `nameplates L` tick is 248 hosts x 1,503 nodes and 21.3 of the
		class's 24.0 ms. The same class LIVE is 2.876 ms: the engine reparents for free
		and this fake was charging Facet for the difference.

		KEYED ON THE PARENT PATH, WHICH IS WHAT THE PREFIX TEST MEANT. The old test
		matched `prefix = path .. "/"`, so `/S/Host2/Leaf` was NOT under `/S/Host` — the
		trailing separator is the whole of the semantics, and a bare-prefix index would
		silently widen it. `parentPathOf` cuts at the LAST separator, which is where
		`hostFor` STARTS — not the whole of what `hostFor` does. `hostFor` (`:247-258`)
		keeps walking separators upward until it finds a REGISTERED host; this stops at
		the first cut. One cut per level is exactly right for a parent-keyed index that
		is then recursed, but the two are not the same walk (review round 2 §3.7).

		AND THE SELECTION IS BY PATH WHILE THE COMPUTATION IS BY HOST CHAIN, exactly as
		today. `spaceOriginOf` walks `handle.instanceHost`, never the composed node's
		path; `adopt` re-keys `nodes[newPath]` and never deletes the old key, so the old
		key stays in this index too. Matching today's set is the requirement; fixing
		`adopt`'s leak is a different change with its own oracle. ]]
	local childrenOf: { [string]: { [string]: true } } = {}
	local function parentPathOf(path: string): string?
		local i = #path
		while i > 1 do
			if string.sub(path, i, i) == "/" then
				return string.sub(path, 1, i - 1)
			end
			i -= 1
		end
		return nil
	end
	local function indexNode(path: string)
		local parent = parentPathOf(path)
		if parent == nil then
			return
		end
		local bucket = childrenOf[parent]
		if bucket == nil then
			bucket = {}
			childrenOf[parent] = bucket
		end
		bucket[path] = true
	end
	local function unindexNode(path: string)
		local parent = parentPathOf(path)
		local bucket = if parent ~= nil then childrenOf[parent] else nil
		if bucket ~= nil then
			bucket[path] = nil
			if next(bucket) == nil then
				childrenOf[parent :: string] = nil
			end
		end
		childrenOf[path] = nil
	end
```

  **The site sets, verified, and stated ONCE (review round 2 §2 MUST-FIX — revision 2's
  prose contradicted itself inside one sentence):** `nodes[…] = <value>` at **`:482`**
  (`create`) and **`:1029`** (`adopt`'s new key); `nodes[…] = nil` at **`:873`**
  (`remove`), **`:936`** (`discardParked`'s neighbour) and **`:1124`** (`destroyRoot`).
  **`indexNode` is called at BOTH `:482` AND `:1029`.** The re-keyed handle has to be in
  the index: absent from `childrenOf`, the recursion would miss a whole subtree that
  today's prefix walk finds — the exact divergence fixture (c) exists to forbid.
  **`unindexNode` at `:873`, `:936` and `:1124`.** `adopt`'s OLD key is deliberately left
  in BOTH `nodes` and `childrenOf`, because today's walk still visits it. **The pin is an
  explicit enumerated list — 2 index sites, 3 unindex sites, and the named adopt
  exception — never a count equality against the `nodes[x] = v` write count.** (Task 12's
  implementer has already been handed this ruling directly; the plan now agrees with it.)

  The walk at `:657-660` becomes a recursion over the index:

```luau
		if selfHost ~= nil and selfHost.hostSpace == true then
			--[[ DEPTH-FIRST OVER THE INDEX, not a scan of the map. Same set, same
				per-node computation. Order is output-neutral: `spaceOriginOf` (`:561`)
				and `_composePresentation` (`:498`) read only host entries and ancestor
				`props.transform`, never a sibling's composed rect. ]]
			local function recompose(parentPath: string)
				local bucket = childrenOf[parentPath]
				if bucket == nil then
					return
				end
				for path in bucket do
					local node = nodes[path]
					if node ~= nil and node.storedRect ~= nil then
						local sx, sy = spaceOriginOf(node)
						local st = node.storedRect
						node.rect = if sx == 0 and sy == 0
							then st
							else { x = st.x + sx, y = st.y + sy, w = st.w, h = st.h }
						local sh = node.storedHitRect
						if sh ~= nil then
							node.hitRect = if sx == 0 and sy == 0
								then sh
								else { x = sh.x + sx, y = sh.y + sy, w = sh.w, h = sh.h }
						end
						adapter._composePresentation(node)
					end
					recompose(path)
				end
			end
			recompose(handle.path)
		end
```

  **The one semantic difference, and why step 1's fixtures exist:** the old walk visited
  every node whose path carried the prefix **whether or not its intermediate ancestors
  were in `nodes`**; the recursion stops at a missing link. Fixture (c) drives exactly
  that through `adopt`.

- [ ] **Step 4: green + the differential oracle arm.** `fake_target_ops_opt.spec` green. Then every standing suite that runs on this adapter IS this task's oracle — `host_space_oracle` (6 fixtures), `translate_arm`, `measure_split`, `measure_reuse`, `rect_cow`, `node_reuse`, `anchor_skip`, `commit_scope`, `structural_scope`, and `tests/host_move_write_cost.spec.luau` — over all 9 `device_views.VIEWS` incl. `narrow-portrait` 320x640, arm `c` byte-equal, non-vacuity guard in place.
- [ ] **Step 5: the mutation (Step-7 discipline).** Each must BITE, each recorded: (1) key `childrenOf` on a bare prefix → reddens `/S/Host2/Leaf`. (2) remove one `unindexNode` site → reddens a remove-then-move fixture. (3) unindex `adopt`'s OLD path → reddens fixture (c). (4) hoist an interpolation outside its `if recordOps` → reddens the source scan.
- [ ] **Step 6: gates + measurement + commit.** `tools/test.sh` full (≥ 8,452/0); `tools/verify.sh affected --jobs 1`; `stylua --check`; `check_source_size` (attestation — no `src/` change). **RR rider: `./run-tests.sh` ≥ 3,591/0 with NO spec edited** — RR consumes `Facet/src`, not `Facet/tests`, so any movement is a stop. Measurement, three arms, `attr <wl> L 3`:

  | class | before (read at arm A) | **expected after** | live |
  |---|---:|---:|---:|
  | `nameplates L updateItems-plates` | 23.99 | **~2.6** | 2.876 |
  | `war_room_inventory L reorder` | 29.3 | **~19** | — |
  | `war_room_inventory L removeItem-items` | 15.2 | **~10.3** | — |
  | `killfeed_nameplates L addItem-feed` | 2.108 | ~1.0 | — |
  | `battle_hud L updateItem-hp` | 1.824 | **1.824 ± noise (CONTROL: 4 writes, no host move)** | 3.382 |

  Commit `T12: the headless target's op log is opt-in and a host move walks an index, not the map (C10)`.
- [ ] **Step 7: FacetBench §C10.** The two charges with their `os.clock` evidence, the before/after table, the live row that agreed with the fixed number all along, and the standing rule: *a Lune class number is comparable to a live one only once the harness share is under 5 %*.

---

### Task 13 (L1a → FacetBench §C11): `contentSize` memoises its per-child measures

**AMENDED SCOPE (rulings A-3, A-4, A-8).** Revision 1 cached an *aggregate* and patched
it. The review found four independent ways that arithmetic is wrong, all of them
properties of patching. **T13 now caches the per-child numbers `contentSize` already
computes and re-sums them** — the loops stay O(children), the *work inside them* becomes
O(dirty). That is where the milliseconds are: a `measure` entry is **0.47 µs** (T9b: 1.038 ms
over 2,221 entries) against ~0.03 µs for three hash reads.

**The gate is met and is not re-derived:** `span:Facet/measure` is **1.038 ms of 1.824
(57 %)** on `battle_hud L updateItem-hp`, **1.534 of 2.579 (59 %)** on `war_room
setState`, **0.213 of 0.476 (45 %)** on `killfeed hp`. Counters at HEAD, `battle_hud L
updateItem-hp`: `lastMeasureCalls` **2,221**, `lastMeasureServed` **2,206**,
`lastMeasured` **6**, `lastLayoutNodes` 5,127.

**THE OWED LIST — what a skipped child's `measure` would have published.** C2's table
answered "may this CHILD be served"; this asks "may this PARENT skip asking".

| # | channel | site | verdict |
|---|---|---|---|
| 1 | `ctx.offers[child.wKey]` / `[child.hKey]` | `solver.luau:1758-1759`; consumed by the entry literal at **`solver.luau:2422-2423`** (review round 3 §1 — the plan said `:2429-2437`; corrected here by T13's implementer, and post-seam it is `:2306`) | **SERVED** — written from the offer in hand, and the serve writes the **raw** `maxH` there, so the raw `innerMaxH` is the right value. **This is T11's finding and it is not optional**: a `nil` offer disarms both anchor arms for the life of the surface (T7 finding 2) |
| 2 | `ctx.textStates` / `ctx.compact` / `ctx.textFacts` | `solver.luau:1763-1766`; publishers are exactly `kind == "text" or kind == "composition"` (`record`, **`solver.luau:1597`** — review round 3 §1 corrected `:1596`; post-seam `:1481`) | **GATED PER CHILD — and per child ONLY** (RE-AMENDED, review round 2 §3.6). A direct child of either kind is never skipped, and that is the whole of the safety argument: an unskipped child is measured, so `record` publishes exactly what it publishes today. Revision 2 ALSO killed the container's entire memo at the first such child, and **measurement says that second term costs the lever its own headline**: at `92d3e7e4`, of the per-child `measure` calls `contentSize` issues on a one-leaf update, the skip arm can serve **1.4 %** on `battle_hud L updateItem-hp` with the container-level kill and **96.8 %** without it; `killfeed L updateItem-hp` **0.0 %** vs **75.2 %** (Amendment log round 2, measurement L-1a). It is not needed for correctness — the per-child term already refuses every publisher — so **the container-level kill is DELETED and only the per-child refusal remains** |
| 3 | `ctx.fitCuts += <child's contribution>` | **`solver.luau:1769`** (review round 3 §1 corrected `:1771`; post-seam the serve's add is `:1653` and PASS 1's own is in `src/layout/stack_measure.luau`), and `record`'s `cuts = ctx.fitCuts - cutsAtEntry` | **SERVED from the memo's own array** — `cmemo.mCuts[idx]` is recorded as the `ctx.fitCuts` delta across the child's `measure` call in PASS 1, so nothing reads a slot |
| 4 | `shrinkBasis[idx]` | `solver.luau:1381-1385`, consumed `:1425-1426` | **GATED** (amended; review MUST-FIX 4/5). A container **any** of whose children declares `shrinkWeight > 0` never memoises. PASS 1.5 then cannot run on a memoised container, so `mainSum -= absorbed` (`:1434`) never rebases the numbers the memo holds |
| 5 | the fill pass's re-measure | `solver.luau:1471-1485` | **NOT SKIPPED, ever** (amended; review MUST-FIX 3). `crossOf` and `marginMain` are allocated FRESH each call exactly as HEAD does, and a fill child's `crossOf[idx]` is written only by the fill pass — so the fill pass re-measures every fill child on every call, as today. `remaining` depends on `mainSum`, so it must |
| 6 | `ctx.compositions` / `ctx.hasScroll` / `armContainer` / `ctx.boundary` / the adopted-slate diagnostics | C2's table rows 4–8 | **GATED** by C2's own gate asked of the child: `subtreeHasScroll`, `subtreeHasComposition`, `containerRelativeInside`, plus `ctx.analyze` and `ctx.measureQuiet` on the container |
| 7 | `ctx.mdepth` / `ctx.deepNesting` | `measureUncached` | **BALANCED BY CONSTRUCTION, stated** — the child is not entered, so nothing is pushed and nothing owed; `deepNesting` is a latch a later slow path re-arms |
| 8 | `ctx.measureCalls` / `ctx.measureServed` | `solver.luau:1721`, `:1757` | **MOVES BY DESIGN** — both fall, and both pins are re-recorded in this commit, Facet and RR |
| **9** | **the memo's index→child binding** | the splice at `layout_node.luau:1357-1364`; `mount.luau:450` `node.children = newChildren` | **GATED BY AN ID KEY — `kids` identity CANNOT carry it** (review round 2 §3.1, BLOCKING). The carrier gate compares the MOUNT node's `node.children`; the array the memo indexes is the LAYOUT node's spliced FLAT list, and the two are not the same list. `mount.luau:450` replaces the *region's* children, never the root's, so on `battle_hud`'s `addItem-damage` / `removeItem-damage` the root panel's `prior.kids == node.children` still HOLDS while every child after the splice point shifts one index — and the skip arm would serve `mMain[idx]` belonging to a different node. **`cmemo` therefore carries `mIds`, and the skip arm's own term is `cmemo.mIds[idx] == child.id`.** Measured: the index-keyed gate reads **98.0 %** skippable on `removeItem-damage`; the id-keyed one reads **0.0 %**, which is the correct answer for a class whose indices moved |
| **10** | **the O(n) residual** | the PASS 1 loop, the fill pass's `continue` scan, the `crossMax` loop (`solver.luau:1471-1487`) | **NOT SERVED, and BOOKED as the floor** (review round 2 §3.6). Three passes, not one. See the residual paragraph after the memo fill: this task's honest floor is **~0.10–0.15 ms**, 10–15 % of the 1.038 ms it removes, not 3 %. `lastChildVisits` therefore does NOT go to "≤ 12" as the assessment's L1a booked it: it counts the `measure` CALLS the loop still makes, and the loop's own ITERATION count stays at `#children`. Measured survival puts the goal at **1,065.4 → ~34.4** on `battle_hud L updateItem-hp` (the 3.2 % the gate cannot serve), **1,155.2 → ~3.9** on `war_room L setState` and **324.7 → ~80.4** on `killfeed L updateItem-hp` — read each off the run, never quoted. The iteration count is a separate, unmoved fact and this task does not claim it |

**Files:**
- **Step 0 (conditional): the seam.** If the change measures over **+3,200 after stylua** (ruling A-10), STOP and take the seam first in its own commit: `src/layout/stack_measure.luau` carrying `contentSize`'s vstack/hstack branch (`solver.luau:1349-1496`, ~7,500 chars) as `stackMeasure.contentSize(deps, ctx, node, isH, children, n, innerMaxW, innerMaxH, gap, pt, pr, pb, pl)`. **Its real read set, re-read (review SHOULD-FIX 17 — revision 1 wrongly listed `mainDimOf`):** `deps` = `measure`, `dim`, `sides`, `shrinkLib.stack` + `SHRINK_DEPS`; `ctx` = `fitProbe` (`:1422`), plus whatever `fieldsRead` finds on the run. Give it `tests/stack_measure_seam.spec.luau` modelled on `tests/stack_seam.spec.luau` (closed `ctx` set + the read-vs-write half). Run `check_brand_drift.py` by hand after the extraction.
- Modify: `src/render/layout_node.luau` — **the `cmemo` carrier (ruling A-8)**: the `Store` entry literal at `:1519-1521` gains `cmemo` and `kids`; the rebuild arm carries it forward. **This is T13's file even though T15 is "the layout_node task"** — the carrier is a prerequisite for T13 and T14, so it lands here.
- Modify: `src/layout/solver.luau` — `contentSize`'s vstack/hstack branch (`:1349-1496`). ▲ **TAKEN AS STEP 0 (2026-09-05): the branch is now `src/layout/stack_measure.luau`** (`stack_measure.contentSize(deps, ctx, node, innerMaxW, innerMaxH, gap, pt, pr, pb, pl)`, commit `9679891b`), so the memo lands there and `solver.luau` keeps only the `Node.cmemo` field, the `STACK_MEASURE_DEPS` record and `work.childVisits`. The measured spend forced it: the mechanism plus its reasoning is ~9,400 characters against a 3,200 split.
- Modify: **`src/layout/solve_ctx.luau`** (review MUST-FIX 11) — `Ctx` gains `childVisits: number` and `memoAudit: boolean`, both initialised in `new()` (`:311-377`). `tests/solve_ctx_seam.spec.luau`'s field-set count moves.
- Modify: `src/layout/solver.luau`'s `work` literal (`:3515-3538`) — `childVisits = ctx.childVisits`.
- Modify: `src/render/render_stats.luau` — `new()` gains `lastChildVisits = 0`; `publish` (`:191`) gains `stats.lastChildVisits = work.childVisits or 0`. **`publish`'s 4-arg signature does not change.**
- Modify: **`tests/render_stats_seam.spec.luau`** — the `new()` field sample at `:104-119` gains `lastChildVisits`. ▲ **Stated honestly (review round 2 §3.8): that block is a SAMPLE — its own comment says "a SAMPLE of the record's own contract, one field per family, so a field DELETED in a later edit is caught here" — so ADDING a field does not redden it, and this task must not plan a red around it.** The addition documents the contract; the pin that actually catches the new field is this task's own `lastChildVisits` equality in `container_memo.spec`, read off the run. The export-set pin (`:89`), the `publish` call (`:126`, `:135`) and the "one `new`, one `publish`" scan (`:163`) are untouched.
- Create: `tests/container_memo.spec.luau`; register in `tests/run.luau`. Evaluate `tiers.SLOW` if it runs the 9-view oracle over more than 3 fixtures.
- Modify: `tests/measure_serve.spec.luau`, `tests/measure_split.spec.luau`, `tests/nameplates_baseline.spec.luau`, `tests/translate_arm.spec.luau`, `tests/anchor_arrange.spec.luau` — every `lastMeasureCalls`/`lastMeasureServed`/caster-tick pin, re-recorded from a run.
- **RR rider (same commit):** `tests/facet_measure_fanout_contract.spec.luau` — the fanout literals and the two accounting identities. Also run `tests/facet_measure_split.spec.luau`.

**Interfaces:**
- Consumes: `ctx.reuse.measureContains` (measure-half dirty closure, ancestor-closed, keyed by `node.id`, and `solver.Node.id = node.path` — `layout_node.luau:608`); `ctx.scopeKey` (`solve_ctx.luau:131`); `ctx.measureStamp` (**`string?`** — `solve_ctx.luau:194`; review MUST-FIX 9); `ctx.analyze` (`:252`); `ctx.measureQuiet` (`:274`); `ctx.fitProbe` (`:79`); `ctx.fitCuts` (`:89`); child `subtreeHasScroll` / `subtreeHasComposition` / `containerRelativeInside` / `kind` / `shrinkWeight` / `wKey` / `hKey`.
- Produces — **the carrier** (ruling A-8), on the store entry `store.byNode[node]`:
  - `cmemo: ContainerMemo?` — one table, carried across rebuilds
  - `kids: any` — the mount `node.children` table this entry was built from, compared by IDENTITY
- Produces — **T13's payload inside `cmemo`** (exactly these NINE names; T13 is their only writer):
  - `mStamp: string?`, `mScope: string?`, `mOffW: number?`, `mOffH: number?` — the key (ruling A-3)
  - `mMain: { [number]: number }`, `mCross: { [number]: number }`, `mMargin: { [number]: number }`, `mCuts: { [number]: number }` — per-child, indexed by child index
  - **`mIds: { [number]: string }`** — the child `id` each index was recorded against (ruling **A-14**, owed row 9). Without it the index-keyed arrays shift under a `ForEach` splice while the carrier gate still holds
- Produces: `layoutNode.cmemo` (the pointer), `ctx.childVisits`, `work.childVisits`, `stats.lastChildVisits`.
- Produces: solve opt `containerMemoAudit: boolean?` (default false, test-only) → `ctx.memoAudit`.
- **Moves (re-recorded in this commit): `lastMeasureCalls`, `lastMeasureServed`.** **Must NOT move: `lastMeasured`, `lastArranged`, `lastRectInserts`, `lastSkipped`, `lastSolveSkipped` (derived by subtraction at `solver.luau:3469`, so automatic), `lastLayoutNodes`, `lastAnchorSkipped`, `rectWrites`, `propWrites`, `engineWrites`, `solves`, `partialSolves`.**

- [ ] **Step 1: the owed list, then the two pins.** Eight-row table into the spec header and the ledger. Then `tests/container_memo.spec.luau` on `tests/lib/deep_stack_scene.luau` (1,000 rows, `ops` NOT armed — ruling A-11), warm one tick, `scene.text(500, "x")`:
  - **(a) an EXISTING counter as an equality red, read off the run:** `lastMeasureCalls` at HEAD (`≈2,005` on this fixture per T6's own record — **read it, do not quote it**), and the target value after. `lastMeasured=1` and `solves=1` in the same block, unchanged.
  - **(b) the new counter as an equality after step 2:** `lastChildVisits`.
  - `it("a viewport change memoises nothing and serves nothing")` — `env:set` drive, full walk, `solves=1`, no `reuse`.
  - `it("a width write on the container refills the memo at the new offer")` — the key moved, not the dirt.
  - **One case per GATED row (4, 5, 6):** a container with a `shrinkWeight > 0` child (row 4); a container with a `fill` child, pinning that the fill child is re-measured on **every** tick (row 5); a container with a `text` direct child and one with a `composition` direct child (row 2), with `controller.compositionAt` still answering; a `ScrollView` child, a `containerRelative` child, an `analyze` solve and a non-quiet solve (row 6). Each pins `lastChildVisits` at the FULL walk.
  - **`it("a ForEach sibling insert shifts every later index and the memo refuses")`** — owed row 9's fixture, built as `deep_stack_scene` plus a spliced `ForEach` region beside the rows; insert and remove into the SIBLING, pin every rect and pin `lastChildVisits` at the FULL walk. `prior.kids == node.children` holds throughout (that is the point).
  - **`it("a container with a text child still memoises its other children")`** — the re-amended owed row 2: a stack holding one `UI.Text` and 30 boxes; the text child is measured every tick and the 30 boxes are not, and `controller.stats()` shows both facts in one block.
  - `it("the offer channel survives a skipped child")` — the T11/T7 case: a child arrange-dirty but measure-clean whose entry literal IS rebuilt must carry non-nil `offerW`/`offerH`; pin `lastAnchorSkipped` on the NEXT frame at its HEAD value.

- [ ] **Step 2: the counter, alone (arm C).** Add `ctx.childVisits` (+ its `solve_ctx` field and initialiser), the `work` field, the `render_stats` publish and the seam-spec sample — **no mechanism**. Measure. T8 measured a bare `scanCount += 1` at +0.7–2.6 % because `skip` ran 9,040×/step; `childVisits += 1` runs ~2,200×/step here. If arm C is distinguishable from arm A, move the increment to a per-LOOP `+= n` and write the spec's pin against that. Record the arm-C number either way. **Arm C's increment must sit on the same line arm B's does.**

- [ ] **Step 3: the carrier (ruling A-8).** In `layout_node.luau`, the rebuild path:

<!-- verified: sed -n '370,400p;1340,1390p;1512,1525p;1645,1715p' src/render/layout_node.luau; sed -n '435,472p' src/mount.luau -->
```luau
	--[[ THE CONTAINER MEMO'S HOME IS THE STORE ENTRY, NOT THE LAYOUT NODE (Plan C
		addendum, ruling A-8). `store.byNode` is keyed by the MOUNT node and is weak
		(`WEAK_KEYS`, this file's `newStore`), so an entry outlives every rebuild of the
		solver `Node` — and a rebuild is exactly what a container holding one dirty
		child gets: the hit above requires `not store.dirty[node.path]`, and
		`store.dirty` is the renderer's ancestor-closed `nodeDirty`. A memo living on
		the layout node would therefore be `nil` on every tick the levers that read it
		target, and both T13 and T14 would measure zero.

		THE POINTER IS REFRESHED, THE TABLE IS NOT REBUILT. The solver reads
		`node.cmemo` — one field — and the table it points at is the one the previous
		build produced, WHEN all three validity terms hold: the mount children table is
		the same OBJECT (a shape change makes a new one in `mount`, so index-keyed
		arrays cannot shift under the memo), and the two inputs the per-child lookup
		above cannot re-derive, `axis` and `clip`, are the same. Otherwise a fresh
		empty table — never a stale one. ]]
	local prior = if store ~= nil and store.reuse then store.byNode[node] else nil
	local cmemo = if prior ~= nil
			and prior.kids == node.children
			and prior.axis == parentAxis
			and prior.clip == (insideClipper == true)
		then prior.cmemo
		else nil
	if cmemo == nil and store ~= nil and store.reuse then
		cmemo = {}
	end
	layoutNode.cmemo = cmemo
```

  placed immediately before the entry write, which becomes:

```luau
	if store ~= nil and store.reuse then
		store.byNode[node] = {
			built = layoutNode,
			axis = parentAxis,
			clip = insideClipper == true,
			n = store.nodes - nodesAtEntry,
			-- ruling A-8: the memo's durable home, and the mount children table its
			-- index-keyed arrays are only valid against. Compared by IDENTITY, never
			-- iterated. (T15 adds `childArray` beside these two.)
			cmemo = cmemo,
			kids = node.children,
		}
	end
```

  **A `store == nil` or `store.reuse == false` build leaves `layoutNode.cmemo` nil and
  every path below takes today's code exactly** — the same "a solve with no reuse is the
  pre-change solver" property C2 has, and the reason `node_reuse`'s
  `layoutNodeReuse = false` arm is a valid pre-fix control.

- [ ] **Step 4: the mechanism.** In `contentSize`'s vstack/hstack branch, `crossOf` and `marginMain` **stay freshly allocated** (owed row 5):

<!-- verified: sed -n '1349,1400p;1418,1440p;1466,1500p;1740,1775p' src/layout/solver.luau -->
```luau
	--[[ THE CONTAINER MEMOISES ITS CHILDREN'S ANSWERS (Plan C addendum, T13 —
		rulings A-3, A-4, A-8). This branch re-measured every child on every call: on
		`battle_hud L` a ONE-LEAF write measured 6 nodes and entered `measure` 2,221
		times, 2,206 of which C2 answered from the child's own slots in 0.47 us each.
		C2 made the ANSWER cheap; it could not make the PARENT stop asking.

		SO THE PARENT KEEPS THE ANSWERS. Four per-child arrays, indexed by child index,
		on the container's `cmemo`. NOTHING IS AGGREGATED AND NOTHING IS PATCHED
		(ruling A-4): `mainSum` is re-summed from `mMain` exactly as today, which is an
		add loop this branch already pays and which cannot drift from a base the shrink
		pass moved. The saving is the `measure` CALL, at 0.47 us against three hash
		reads.

		THE KEY IS THE RAW OFFER PAIR PLUS C2'S SCOPE AND STAMP (ruling A-3): the pair
		this loop actually hands its children, not `offerHeightKey`'s reduction — which
		is a `local function` six hundred lines below this one and not in scope, and
		which would be a WIDER key than the answers were recorded under. `ctx.scopeKey`
		already carries the `|fit` segment, so a `ViewThatFits` probe cannot collide.

		AND THE GATE IS C2'S GATE ASKED OF THE CHILDREN, PLUS TWO SHAPES THIS BRANCH
		CANNOT SERVE: a child that publishes verdicts (`text`, `composition` — the
		exact pair `record` branches on) and any container holding a `shrinkWeight > 0`
		child, because PASS 1.5 rebases `mainSum` against numbers the memo does not
		hold. `memoable` goes false at the first offender and the container then
		behaves exactly as it does today, at this offer, forever. ]]
	local mainSum, fillWeightSum = 0, 0
	local crossOf: { [number]: number } = {}
	local marginMain: { [number]: number } = {}
	local shrinkBasis: { [number]: number }? = nil
	local cmemo = node.cmemo
	local reuse = ctx.reuse
	local dirty = if reuse ~= nil then reuse.measureContains else nil
	local hit = cmemo ~= nil
		and dirty ~= nil
		and ctx.measureQuiet
		and not ctx.analyze
		and ctx.measureStamp ~= nil
		and cmemo.mStamp == ctx.measureStamp
		and cmemo.mScope == ctx.scopeKey
		and cmemo.mOffW == innerMaxW
		and cmemo.mOffH == innerMaxH
	local memoable = cmemo ~= nil and reuse ~= nil and ctx.measureStamp ~= nil and not ctx.analyze
	local mMain, mCross, mMargin, mCuts, mIds
	if memoable then
		if hit then
			mMain, mCross, mMargin, mCuts, mIds =
				cmemo.mMain, cmemo.mCross, cmemo.mMargin, cmemo.mCuts, cmemo.mIds
		else
			mMain, mCross, mMargin, mCuts, mIds = {}, {}, {}, {}, {}
		end
	end
	-- PASS 1: children with a definite main extent measure against the whole
	-- inner box, and consume it.
	for idx, child in children do
		local childMainDim = dim(child, if isH then "w" else "h")
		if
			hit
			and childMainDim.type ~= "fill"
			and dirty[child.id] ~= true
			-- THE INDEX IS NOT THE IDENTITY (owed row 9, review round 2 §3.1). A
			-- `ForEach` splice shifts every later index while the MOUNT children
			-- table the carrier gate compares stays the SAME OBJECT, so an array
			-- position alone would serve another node's number. One string compare
			-- per child, inside a loop that is already O(children).
			and mIds[idx] == child.id
			and mMain[idx] ~= nil
			and child.kind ~= "text"
			and child.kind ~= "composition"
			and child.shrinkWeight == nil
			and child.subtreeHasScroll ~= true
			and child.subtreeHasComposition ~= true
			and child.containerRelativeInside ~= true
			and not ctx.memoAudit
		then
			--[[ THE SKIP, AND THE TWO CHANNELS IT OWES (owed rows 1 and 3). `measure`
				was not called, so nothing it publishes has been published — and the entry
				literal of a child that is ARRANGE-dirty but MEASURE-clean reads
				`ctx.offers` for its `offerW`/`offerH`. A nil there disarms BOTH anchor
				arms for the life of the surface (T7 finding 2). The RAW `innerMaxH` is
				the right value: the serve writes the raw `maxH` too. ]]
			ctx.offers[child.wKey or (child.id .. "|w")] = innerMaxW
			ctx.offers[child.hKey or (child.id .. "|h")] = innerMaxH
			ctx.fitCuts += mCuts[idx]
			marginMain[idx] = mMargin[idx]
			crossOf[idx] = mCross[idx]
			mainSum += mMain[idx]
			continue
		end
		local mt, mr, mb, ml = sides(child.margin)
		marginMain[idx] = if isH then ml + mr else mt + mb
		if childMainDim.type == "fill" then
			fillWeightSum += childMainDim.weight or 1
		else
			ctx.childVisits += 1
			local cutsBefore = ctx.fitCuts
			local cw, ch = measure(ctx, child, innerMaxW, innerMaxH)
			local mainOf = if isH then cw + ml + mr else ch + mt + mb
			local crossOfIdx = if isH then ch + mt + mb else cw + ml + mr
			mainSum += mainOf
			crossOf[idx] = crossOfIdx
			if child.shrinkWeight ~= nil and child.shrinkWeight > 0 then
				local basis = shrinkBasis or {}
				basis[idx] = if isH then cw else ch
				shrinkBasis = basis
				memoable = false -- owed row 4: PASS 1.5 would rebase `mainSum`
			end
			--[[ RECORDED, OR NOT RECORDED — never "and the container gives up". A
				`text`/`composition` child is refused PER CHILD (owed row 2): its index is
				left unrecorded, so the skip arm's `mIds[idx] == child.id` term refuses it
				on every later tick and `record` publishes its verdicts exactly as today.
				Revision 2 additionally set `memoable = false` here, which took the whole
				container down with one label: measured, that reaches 1.4 % of
				`battle_hud L updateItem-hp`'s measure calls where the per-child form
				reaches 96.8 %, and 0.0 % against 75.2 % on `killfeed L updateItem-hp`. ]]
			if
				memoable
				and child.kind ~= "text"
				and child.kind ~= "composition"
				and child.subtreeHasScroll ~= true
				and child.subtreeHasComposition ~= true
				and child.containerRelativeInside ~= true
			then
				mMain[idx], mCross[idx] = mainOf, crossOfIdx
				mMargin[idx], mCuts[idx] = marginMain[idx], ctx.fitCuts - cutsBefore
				mIds[idx] = child.id
			end
			--[[ THE AUDIT ARM (ruling A-12). When on, the skip above never fires and the
				memo's answer is compared against the real one instead — so the standing
				9-view fuzz exercises this arithmetic on EVERY container it touches
				without any gate being weakened. Off in production; there is no third
				behaviour. ]]
			if ctx.memoAudit and hit and mIds[idx] == child.id and mMain[idx] ~= nil then
				assert(
					mMain[idx] == mainOf and mCross[idx] == crossOfIdx and mMargin[idx] == marginMain[idx],
					`container memo mismatch at {node.id}[{idx}]`
				)
			end
		end
	end
```

  **PASS 1.5, the fill pass and the `crossMax` loop are UNCHANGED.** `crossOf` is fresh
  each call and a fill index is never written in PASS 1, so the fill pass re-measures
  every fill child exactly as today (owed row 5), and `crossMax` stays the O(n)
  `math.max` loop — ~0.005 µs per child against 0.47 µs for a measure, which is why
  ruling A-4 withdrew the argmax machinery. The memo fill:

```luau
	if memoable and not hit then
		cmemo.mStamp, cmemo.mScope, cmemo.mOffW, cmemo.mOffH =
			ctx.measureStamp, ctx.scopeKey, innerMaxW, innerMaxH
		cmemo.mMain, cmemo.mCross, cmemo.mMargin, cmemo.mCuts, cmemo.mIds =
			mMain, mCross, mMargin, mCuts, mIds
	elseif not memoable and cmemo ~= nil then
		-- a container that once memoised and has since gained a shrink child or a text
		-- child must not keep a stale key
		cmemo.mStamp = nil
	end
```

  **Residual, corrected and stated rather than hidden (review round 2 §3.6).** The PASS 1
  loop, the fill pass's `continue` scan and the `crossMax` loop are all still O(children)
  — **three** passes over an array, not one. On `battle_hud L` that is
  3 × ~1,000 × ~0.03 µs ≈ **0.09 ms**, and PASS 1's skip arm itself is not free: six table
  operations per skipped child (two `ctx.offers` writes, the `fitCuts` add, and three
  array reads), plus the new `mIds[idx] == child.id` string compare. **Book the residual
  at ~0.10–0.15 ms — 10–15 % of the 1.038 ms removed, not 3 %.** Arm C measures it: with
  the counter alone and the mechanism off, the loops are HEAD's, so the arm-B minus arm-C
  delta prices the mechanism and the arm-B floor prices what is left. If arm B lands above
  0.15 ms over the predicted floor, say so in §C11 rather than re-deriving the model.

- [ ] **Step 4.5 (NEW, review round 2 §3.6): re-read the gate-survival fraction at THIS task's parent SHA, BEFORE quoting step 8's table.** The survival numbers in step 8 were measured at `92d3e7e4` with a temporary census inside `contentSize` (Amendment log round 2, measurement L-1a); T12 lands in between, and every "before" in this plan is a prediction. **Publish the pair as counters rather than re-instrumenting:** `lastChildVisits` (the `measure` CALLS `contentSize` still makes) against `lastMeasureCalls`, read on **all three** of `battle_hud L updateItem-hp`, `war_room_inventory L setState` and `killfeed_nameplates L updateItem-hp` — three workloads, because the measured spread between them is **75.2 %–99.7 %** and one workload is not evidence for the other two. If any class comes back more than 10 points under the recorded survival, STOP and re-derive that row rather than quoting this file.
- [ ] **Step 5: L5 (`ctx.offers`) — fold in ONLY if the budget allows.** T9b §6-L5: `ctx.offers` grows to 2 × `measureServed` (~4,500 entries/tick) with a `child.id .. "|w"` concat on any node without a cached `wKey`. Its measured time gain is **~zero** (T9b arm 4: −16.6 % allocation, 0 % clock). **If `check_source_size` shows T13 above +2,700 after stylua, SKIP and re-book.** If it goes in: move the pair onto the node beside the C2 slots (`node.oW`, `node.oH`, stamped with `mStamp`) and change the single in-solve reader, the entry literal at `solver.luau:2429-2437`. T7's second NULL mutation established there is no other reader.
- [ ] **Step 6: green + the differential oracle arm.** `container_memo.spec` green. Then, on the fake adapter, all 9 `device_views.VIEWS` incl. 320x640, three drives (text write, width write, viewport change) on **four** fixtures — `deep_stack_scene`, a nested-stack fixture, one with a `fill` child, one with a `shrinkWeight` child — `scene.snapshot()` byte-equal to arm `c`, non-vacuity guard, `b`/`d` driven every step. **Every one of these runs TWICE: once normally and once with `containerMemoAudit = true`** (ruling A-12). Public reader pin: `controller.compositionAt` on the composition fixture. Then the standing suites that compare against arm `c`: `host_space_oracle`, `translate_arm`, `measure_split`, `measure_reuse`, `rect_cow`, `node_reuse`, `anchor_skip`.
- [ ] **Step 7: the mutation (Step-7 discipline).** Each must BITE, each recorded: (1) drop the `ctx.offers` writes in the skip arm → reddens the T7-finding-2 case. (2) drop `child.kind ~= "text"` → reddens the text-child verdict case. (3) drop the `shrinkWeight` → `memoable = false` line → reddens the shrink case. (4) drop `cmemo.mStamp = nil` on the un-memoable arm → reddens the shrink-child-arrives-later case. (5) key the memo on `innerMaxW` alone → reddens the height-offer case. (6) carry `cmemo` forward without the `prior.kids == node.children` term → reddens a case where the CONTAINER's own mount children changed. (6b) **drop the `mIds[idx] == child.id` term → MUST redden the spliced-sibling fixture** (owed row 9): a `ForEach` sibling insert/remove under a container whose own mount children table is unchanged. Measured, this is the difference between 98.0 % and 0.0 % skippable on `battle_hud L removeItem-damage`, so a mutation that does not bite means the fixture is not a witness and step 1 is wrong. (6c) **restore the container-level `memoable = false` on a `text`/`composition` child → MUST NOT change any rect, and MUST collapse `lastChildVisits` back toward the full walk** — the null that proves the deleted term was cost and not safety. (7) remove `child.containerRelativeInside ~= true` → **if it does NOT redden, record the null exactly as T6/T7 recorded theirs and KEEP the term with the null stated at both sites** (C2's own term is a known null).
- [ ] **Step 8: gates, RR, measurement, commit.** `tools/test.sh` full; `tools/verify.sh affected --jobs 1`; `stylua --check`; `check_source_size` **and record `solver.luau`'s new size in `tools/lune/verify/data/source-cap-ledger.md`**; **RR: `./run-tests.sh` with `facet_measure_fanout_contract` re-recorded IN THIS COMMIT**, plus `facet_measure_split`. Measurement, three arms (A = worktree at T12's SHA, B = HEAD, C = step 2), ABBA:

  **Every row below is now derived from the MEASURED gate-survival fraction** (Amendment
  log round 2, measurement L-1a: the share of `contentSize`'s per-child `measure` calls
  the id-keyed skip arm can serve, at `92d3e7e4`), not from the span share alone.

  | class | before (read at arm A) | measured survival | **expected after** |
  |---|---:|---:|---:|
  | `battle_hud L updateItem-hp` | ~1.82 | **96.8 %** (1,031.0 / 1,065.4) | **~0.90** (−1.00 × 0.968, +0.10–0.15 residual) |
  | `battle_hud L setState` | ~1.93 | 97.2 % (1,081.7 / 1,112.8) | ~1.00 |
  | `war_room_inventory L setState` | ~2.58 | 99.7 % (1,151.3 / 1,155.2) | **~1.15** |
  | `killfeed_nameplates L updateItem-hp` | ~0.52 | **75.2 %** (244.3 / 324.7) | **~0.36** |
  | `war_room_inventory L reorder` | ~19 (post-T12) | **0.0 %** — the id key refuses a class whose indices moved | **~19 (NO GAIN, and that is the correct answer)** |
  | `battle_hud L removeItem-damage` | ~2.5 | **0.0 %** (same reason) | **~2.5 (NO GAIN)** |
  | `nameplates L updateItem-hp` | 0.006 | — | **0.006 (CONTROL — anchored, no stack loop)** |

  **The two rows that read 0.0 % are the acceptance evidence, not a disappointment.** The
  index-keyed gate revision 2 shipped reads 98.0–100 % on exactly those classes, and every
  one of those serves would be a number belonging to a different node.

  ▲ **MEASURED 2026-09-05 (T13, three arms interleaved — A `a77cc101`, B the mechanism,
  C the counter alone; medians of four `attr <wl> L 3` runs per arm; FacetBench §C11).
  THE SURVIVAL LANDED AND THE MILLISECONDS DID NOT, and the expected column above is
  REPLACED by this one rather than defended:**

  | class | before (arm A) | survival, MEASURED | expected | **MEASURED after (arm B)** |
  |---|---:|---:|---:|---:|
  | `battle_hud L updateItem-hp` | 1.896 | **97.1 %** (1,133 → 33 `childVisits`) | ~0.90 | **1.800 (−5.1 %)** |
  | `battle_hud L setState` | 2.369 | 97.1 % (1,130 → 33) | ~1.00 | 2.342 (−1.1 %) |
  | `war_room_inventory L setState` | 3.534 | 99.7 % (1,473 → 5) | ~1.15 | **3.415 (−3.4 %)** |
  | `killfeed_nameplates L updateItem-hp` | 0.491 | 73.7 % (335 → 88) | ~0.36 | **0.473 (−3.8 %)** |
  | `war_room_inventory L reorder` | 30.267 | **0.1 %** (1,469 → 1,467) | ~19, NO GAIN | 30.390 (flat, as the id key says it must be) |
  | `battle_hud L removeItem-damage` | 2.622 | 89.2 % (1,123 → 121) | ~2.5, NO GAIN | 2.740 (noise) |
  | `span:Facet/measure`, `battle_hud hp` | 1.258 | — | — | **1.141 (−9.3 %)** |
  | `lastMeasureCalls`, `battle_hud hp` | 2,263 | — | — | **1,163 (−48.6 %)** |

  **WHY THE EXPECTED COLUMN WAS WRONG, AND IT IS THE ESTIMATE FORM RATHER THAN THIS
  LEVER.** Every "expected after" above came from dividing the whole `span:Facet/measure`
  by every entry in it (1.038 ms / 2,221 = **0.47 µs an entry**) and multiplying that
  AVERAGE by the share of entries the gate can serve. The entries a container memo
  removes are the CHEAPEST ones in that average: each was already answered by C2 from two
  fields on the node, with no key string, no slate lookup and no subtree walk — while the
  expensive entries are exactly the ones the memo must not skip. Measured marginally,
  1,100 removed calls bought 0.117 ms of measure span: **~0.106 µs per served call, one
  fifth of the figure the plan spent.** Arm C makes the division trustworthy — the counter
  alone is within noise of arm A on every class. **Any remaining row in this plan that
  prices a lever as `calls × average cost` is overstated by whatever share of those calls
  was already being served, and T14/T16 should take a marginal price before booking one.**

  Commit `T13: a stack memoises its children's measures and re-asks only the dirty ones (C11)`.
- [ ] **Step 9: FacetBench §C11.** The mechanism, the counter table (`lastChildVisits` before/after, `lastMeasured` unmoved), the three-arm ms table, the arm-C number, **and the withdrawal of the aggregate design with the four reasons** — a per-child memo re-summed is exact where a patched aggregate is four separate ways of being wrong.

---

### Task 14 (L1b → FacetBench §C12): `stack.arrange` re-places only its dirty children

**AMENDED SCOPE (rulings A-4, A-9, A-13).** Revision 1 shipped a prefix REBASE — shift
every child after a size change by δ. The review found five independent ways that is
wrong (the dirty child keeps its old rect; a clean `fill` sibling is shifted instead of
resized; `gap`/`align`/`shrunk`/`clipMain`/aspect all change the placement without
changing the inner box). **T14 now replays only when NOTHING moved**: every dirty child
re-measures to the extents it already had, so no cursor advances, no sibling moves, and
only the dirty children need `place`. **The prefix rebase is BOOKED, with the review's
five gate terms as its prerequisites.**

**The gate is met:** `span:Facet/arrange` is **0.612 ms of 1.824 (34 %)** on `battle_hud
L updateItem-hp`, **0.809 of 2.579 (31 %)** on `war_room setState`, **0.186 of 0.476
(39 %)** on `killfeed hp`. `arrangeBody` is entered **1,109** times of which **1,104**
take the early skip and **5** run a body; `lastArranged` 5, `lastRectInserts` 5,
`engineWrites` 4.

**Measured evidence, and the two corrections it carries (Amendment log round 2,
measurement L-1b).** T9b's crude ceiling arm — replay when every dirty child measures to
the size it had — read ABBA `battle_hud setState` **1.822 → 1.535 (−16 %)** and
`removeItem-damage` **2.505 → 1.403 (−44 %)**, and did NOT fire on `updateItem-hp`. The
plan attributed that to measured-against-placed. **A shadow of the amended gate, run at
`92d3e7e4` on all three workloads, says the simpler explanation is the true one and that
this task's headline class is NOT `updateItem-hp`:**

| class | replays / `stack.arrange` entries per step | children skipped per step |
|---|---:|---:|
| `battle_hud L updateItem-hp` | **0.0 / 1.9** | **0** |
| `battle_hud L setState` | 1.5 / 2.0 | 846.7 |
| `battle_hud L updateItem-facing` | 0.6 / 1.9 | 636.6 |
| `battle_hud L add/removeItem-damage` | **0.0 / 1.0** | 0 |
| `war_room_inventory L setState` | 0.8 / 1.6 | 615.0 |
| `war_room_inventory L updateItem-power` | 0.8 / 1.9 | **1,158.8** |
| `war_room_inventory L updateItem-tier` | **0.0 / 1.4** | 0 |
| `war_room_inventory L reorder`, `removeItem-items` | **0.0 / 1.0** | 0 |
| `killfeed_nameplates L setState` | 0.8 / 1.0 | 251.0 |
| `killfeed_nameplates L updateItem-hp` | **0.0 / 1.9** | 0 |

**Why `updateItem-hp` cannot fire, named at both levels.** The hp bar's width IS the
value: the adapter returns `{ type = "fixed", px = (tonumber(use(value)) or 0) *
BAR_SCALE_PX }` (`../FacetBench/frameworks/facet/adapter.luau:39-46`) and the step writes
`field = "hp", value = rng:next()` (`../FacetBench/workloads/battle_hud.luau:92-96`). The
shadow names the two refusals directly: `MAIN` moves for
`/Root/Units/[uN]/UnitRow-uN :: …/UnitHp-uN` (a main-axis change inside the row's HStack),
and `CROSS` moves for `/Root :: /Root/Units/[uN]/UnitRow-uN` (the row's own measured width
follows the bar, so the enclosing 1,000-row VStack refuses too). **T14 compares
measured-to-measured, from the pass that measured (review round 2 §3.2), against its OWN
arrays (ruling A-9), never T13's — and it still refuses this class, correctly.**

**THE OWED LIST:**

| # | channel | site | verdict |
|---|---|---|---|
| 1 | `place(ctx, child, childRect, out)` → `arrangeBody`'s entry write | `stack.luau:438` | **SERVED by not being needed** — `out` IS `reuse.previous.rects` (`solver.luau:2352-2353`) and the gate requires `reuse ~= nil`, so a child whose rect did not change already has the entry that describes it. This is `arrangeBody`'s own skip argument, one level up |
| 2 | `noteContainment(ctx, node, child, childRect, …)` | `stack.luau:437` | **REPLAYED for every dirty child that is re-placed; NOT replayed for a `continue`d clean child** — a clean child took `arrangeBody`'s skip at HEAD too, and `solve`'s existing replay (`solver.luau:3477+`, `ctx.skipped > 0 or ctx.translated > 0`) already carries a skipped subtree's diagnostics forward. **Pinned by a case, not asserted** |
| 3 | the overflow diagnostic + `clipMain` | `stack.luau:258-271`, `:428-432` | **STATED-UNREACHABLE.** The gate requires every dirty child's main contribution unchanged and the inner box and `gap` unchanged, so `fixedMain`, `gaps` and therefore `availMain` are identical — the branch's condition has the value it had, and if it fired last tick the finding is in `ctx.diagnostics` via row 2's solve-level replay |
| 4 | `ctx.walkedIds[child.id]` | `solver.luau:2509`, under `if reuse ~= nil` | **NOT SERVED, stated — and it is T16's premise.** A `continue`d clean child was not walked, which is what the flag means, and is exactly the set T16's filter treats as settled |
| 5 | `ctx.arranged`, `ctx.rectInserts` | `solver.luau:2409-2410`, **after** `arrangeBody`'s skip return | **NOT SERVED, and it is the ACCEPTANCE TEST.** A `continue`d clean child cost 0 at HEAD too, so `lastArranged`/`lastRectInserts` must not move |
| 6 | `deps.measure` in pass 1 and the hug pass | `stack.luau:144`, `:153-160` | **SERVED from `cmemo.pMain`/`pCross`, T14's OWN arrays (ruling A-9)** — recorded at the arrange offer `(innerW, innerH)`, never read from T13's `mMain`, which is recorded at `(innerMaxW, innerMaxH)` |

**Files:**
- **Step 0 (its own commit, ruling T7-3): widen `tests/stack_seam.spec.luau`'s read-set.** The three pins are at **`:161` (`ctx`), `:162` (`node`), `:163` (`child`)** — revision 2 called the whole block `:163` (review round 2 §2). At HEAD they are `ctx = { "diagnostics", "hiddenDepth" }`, `node = { "align", "children", "distribute", "id", "kind" }`, `child = { "align", "lineAlign", "margin", "shrinkWeight" }`. The replay adds **`ctx.reuse`, `ctx.noSkipDepth`, `ctx.replayAudit`** (all declared `Ctx` fields — `solve_ctx.luau:248` is `noSkipDepth`, `:269` is `walkedIds`, so **the `(ctx :: any)` casts revision 1 used are unnecessary**), **`node.cmemo`**, and **`child.id`** (`dirty[child.id]`) plus **`child.layoutPriority`** (ruling A-15). It does **NOT** add `node.gap`: `gap` is a **PARAMETER** of `stack.arrange` (`stack.luau:98-112`) and the replay reads the parameter (`cmemo.pGap == gap`), not a node field — revision 2's list was wrong on both counts. **Read the exact sets off the run**; keep the read-vs-write half (`:166-180`), which the replay passes because it writes only through the local `cmemo` and never assigns a field of `ctx`/`node`/`child`/`deps` — **say that in step 0 so the implementer does not discover it by accident** (review round 2 §3.7). Commit the widening ALONE with its reasoning.
- Modify: `src/layout/stack.luau` — `stack.arrange`'s prologue (the replay) and the placement loop's memo fill.
- Modify: **`src/layout/solve_ctx.luau`** — `Ctx` gains `arrangeEntries: number` and `replayAudit: boolean`, both initialised in `new()`. `tests/solve_ctx_seam.spec.luau`'s count moves.
- Modify: `src/layout/solver.luau` — `ctx.arrangeEntries += 1` at the top of `arrangeBody`; `work.arrangeEntries`. **`arrangeBody` is NOT otherwise restructured** — the replay is entirely inside `stack.arrange`. Budget ≤ +1,600 (ruling A-10).
- Modify: `src/render/render_stats.luau` + **`tests/render_stats_seam.spec.luau`** (the `new()` field sample at `:104-119`) — `lastArrangeEntries`. **The sample does not redden on an ADDED field** (review round 2 §3.8); the real pin is this task's own `lastArrangeEntries` equality in `stack_replay.spec`.
- Create: `tests/stack_replay.spec.luau`; register.
- **RR rider (same commit): `tests/facet_anchor_arrange.spec.luau` must be UNCHANGED and green** — it pins `lastArranged`, which must not move. If it moves, that is a stop. Also run `tests/facet_collection_extent_contract.spec.luau`.

**Interfaces:**
- Consumes: `reuse.dirtyContains` (the FULL closure, not the measure half); `node.cmemo` (ruling A-8, created by T13); `out[child.id].rect`.
- Produces — **T14's payload inside `cmemo`** (T14 is their only writer, ruling A-9):
  - `pN: number?`, `pInnerX/pInnerY/pInnerW/pInnerH: number?`, `pGap: number?`, `pAlign: any` (the container's own `node.align`), **`pDistribute: any`** (ruling A-15) — the key
  - `pMain: { [number]: number }`, `pCross: { [number]: number }` — per-child **MEASURED, margin-inclusive** main/cross contributions, recorded after the hug pass at the pass-1 offer `(innerW, innerH)` (review round 2 §3.2)
  - **`pIds: { [number]: string }`** — the child `id` each index was recorded against (review round 2 §3.1, BLOCKING; scanned over EVERY child, not only the dirty ones)
  - **`pHug: { [number]: boolean }`** — measured in the hug pass at `left` (`stack.luau:153-160`), which the replay does not reproduce and therefore refuses
  - **`pShrink: { [number]: any }`, `pPrio: { [number]: any }`** — `child.shrinkWeight` (`stack.luau:188`, consumed `:208`) and `child.layoutPriority` (`shrink.luau:335`), the two inputs that move a rect with no measurement change (ruling A-15)
  - `pCAlign: { [number]: any }`, `pCLine: { [number]: any }` — per-child `child.align` / `child.lineAlign`, the two arrange-classed props `stack.luau:386` reads that no measurement can see
  - `pRect: { [number]: any }` — the frozen rect each child was placed at
- Produces: `work.arrangeEntries` / `stats.lastArrangeEntries` (**1,109 → the number read off the run**); solve opt `stackReplayAudit: boolean?` → `ctx.replayAudit`.
- **Must NOT move: `lastArranged`, `lastRectInserts`, `lastSkipped`, `lastSolveSkipped`, `rectWrites`, `propWrites`, `engineWrites`, `lastAnchorSkipped`, `lastTranslated`, `lastCommitVisits`, `lastChildVisits`, `solves`.**

- [ ] **Step 1: the owed list, then the two pins.** Six-row table into the spec header and the ledger. `tests/stack_replay.spec.luau` on `deep_stack_scene`, warm, `scene.text(500, "x")`:
  - **(a) an EXISTING counter as an equality red:** `lastMeasureCalls` (pass 1's calls disappear) read off the run at the T13 SHA and after; with `lastArranged`, `lastRectInserts`, `rectWrites`, `engineWrites` pinned at their unchanged values **in the same assertion block**, and `solves=1`.
  - **(b) the new counter as an equality after step 2:** `lastArrangeEntries`.
  - `it("a FILL child is compared measured-to-measured, not against its placed rect")` — the fixture that broke T9b's ceiling arm: one `fill` child, one dirty fixed sibling whose size does not change. **The replay must FIRE.**
  - `it("a dirty child whose size CHANGED refuses the replay")` — `scene.height(500, +12)`: `lastArrangeEntries` at the full walk, and every rect correct. **This is the honest statement of the amended scope.**
  - `it("a child whose align changed refuses")` — an arrange-classed prop write with no measurement change (`stack.luau:386` `child.lineAlign or child.align or node.align`).
  - `it("a gap change on the container refuses")`, `it("a container align change refuses")`.
  - `it("a containment finding survives a re-placed dirty child")` (owed row 2).
  - `it("a distribute stack whose contents did not move REPLAYS")` — ruling A-13's witness.
  - **`it("a ForEach sibling splice refuses even when no child is dirty")`** — the review's blocking fixture: a container whose spliced sibling region loses a row while `prior.kids == node.children` still holds and `dirty` names none of the surviving children. **Without the `pIds` scan the replay returns having placed nothing; pin every rect.**
  - **`it("a distribute FLIP on the container refuses")`** — ruling A-15, the mirror of the replay case above it.
  - **`it("a shrinkWeight write with no measurement change refuses")`** and **`it("a layoutPriority write with no measurement change refuses")`** — ruling A-15, on an OVERFLOWING stack so the shrink pass is live.
  - **`it("a MARGINED child replays")`** — the review round 2 §3.2 case: revision 2's placed `mainSize` is margin-exclusive, so a margined child could never have matched. Pin the replay FIRING.
  - `it("a viewport change replays nothing")`.

- [ ] **Step 2: the counter, alone (arm C).** `ctx.arrangeEntries += 1` at the top of `arrangeBody` (+ `solve_ctx` field, `work`, `render_stats`, seam sample), mechanism off. It runs ~1,100×/step — the same order as T8's `scanCount`, which cost +0.7–2.6 %. Same line as arm B's.

- [ ] **Step 3: the mechanism.** At the top of `stack.arrange`, immediately after `local children = node.children or {}`:

<!-- verified: sed -n '96,170p;178,215p;280,400p' src/layout/stack.luau; sed -n '330,340p' src/layout/shrink.luau; sed -n '248,250p;269,270p' src/layout/solve_ctx.luau -->
```luau
	--[[ THE STACK RE-PLACES ONLY ITS DIRTY CHILDREN (Plan C addendum, T14 — rulings
		A-4, A-9, A-13). A one-leaf write on a 1,000-row list entered `arrangeBody`
		1,109 times to run FIVE bodies: pass 1 measured every child, the placement loop
		built a `childRect` for every child, and 1,104 of them reached `arrangeBody`
		only to take its early skip. The skip was already free; GETTING THERE was the
		bill.

		THE CONDITION IS THAT NOTHING MOVED, AND IT IS WHY EVERY OTHER TERM COMES FREE.
		If the inner box, the gap and the container's align are the same, and every
		dirty child re-measures to the main AND cross contributions it already had with
		the same `align`/`lineAlign`, then `fixedMain`, `gaps`, `availMain`,
		`remaining`, `fillPx`, `shrunk`, `clipMain`, `lead`/`step` and every
		`alignOffset` are the values they were — so no child's rect changes, including
		the dirty ones, and the only work left is to re-enter the dirty subtrees. A
		`distribute` stack whose CONTENTS did not move is therefore not refused for its
		contents (ruling A-13): `distributionOf` (`:343`) reads `remaining` (`:296`),
		which did not move. But `node.distribute` ITSELF is a gate term (ruling A-15,
		review round 2 §3.3): flipping it from `"start"` to `"spaceBetween"` dirties the
		CONTAINER, not any child, so the loop below would find nothing dirty and every
		child would keep its old cursor position. Same class, same fix, for the two
		shrink inputs: `child.shrinkWeight` (read at `:188`, consumed by
		`shrinkLib.stack` at `:208`) and `child.layoutPriority` (read inside that call,
		`shrink.luau:335`) both change a rect with NO measurement change, so a prop
		write there dirties the child, this arm re-measures it, the measurement agrees,
		and the shrink redistribution that should have happened is skipped.

		MEASURED-TO-MEASURED, AND `pMain` IS A MEASUREMENT (review round 2 §3.2).
		Revision 2 recorded `pMain`/`pCross` in the PLACEMENT loop from `mainSize` /
		`crossSize` (`stack.luau:356-358`, `:387-389`) — margin-EXCLUSIVE, clamped, and
		for a `fill` or `shrunk` child not a measurement at all — and compared them
		against a freshly measured margin-INCLUSIVE number here. That is the SAME
		measured-against-placed error the prototype made, one axis over, and any child
		with a margin would have refused unconditionally. So the pair is now recorded
		WHERE THE MEASUREMENT HAPPENS: immediately after the hug pass, from `desired`
		plus `margins`, before the shrink and fill passes overwrite `desired`. That is
		the pass-1 offer `(innerW, innerH)` this arm re-measures at, so the two numbers
		are the same question. A dirty child measured in the HUG pass is refused
		outright (`pHug[idx]`): it was measured at `left`, which this arm does not
		reproduce. Measured incidence of that refusal across all three workloads: ZERO.
		T13's `mMain` is recorded at the MEASURE offer `(innerMaxW, innerMaxH)` and is
		still never read here (ruling A-9).

		A SIZE CHANGE REFUSES, AND THAT IS THE WHOLE OF THE AMENDED SCOPE. Shifting the
		suffix by a delta is a second lever with five more gate terms (`gap`, align,
		`shrunk`, `clipMain`, aspect) and it is BOOKED, not built. ]]
	local reuse = ctx.reuse
	local cmemo = node.cmemo
	local dirty = if reuse ~= nil then reuse.dirtyContains else nil
	if
		cmemo ~= nil
		and dirty ~= nil
		and ctx.noSkipDepth == 0
		and not ctx.replayAudit
		and cmemo.pRect ~= nil
		-- the child LIST, not just the box: a `ForEach` splice changes the length
		-- while the mount children table the carrier gate compares is untouched
		and cmemo.pN == #children
		and cmemo.pDistribute == node.distribute -- ruling A-15
		and cmemo.pInnerX == innerX
		and cmemo.pInnerY == innerY
		and cmemo.pInnerW == innerW
		and cmemo.pInnerH == innerH
		and cmemo.pGap == gap
		and cmemo.pAlign == node.align
	then
		local pMain, pCross = cmemo.pMain, cmemo.pCross
		local pRect, pCAlign, pCLine = cmemo.pRect, cmemo.pCAlign, cmemo.pCLine
		local pIds, pHug, pShrink, pPrio = cmemo.pIds, cmemo.pHug, cmemo.pShrink, cmemo.pPrio
		local ok, hot = true, nil :: { number }?
		for idx, child in children do
			--[[ EVERY CHILD IS CHECKED FOR IDENTITY; only the DIRTY ones are
				re-measured. The id scan is the review's BLOCKING finding (round 2 §3.1)
				and it is not optional: `mount.luau:450` replaces a ForEach REGION's
				children, never the enclosing panel's, so `prior.kids == node.children`
				HOLDS across an insert into a spliced sibling while every later index
				shifts. Measured at `92d3e7e4`, `battle_hud L removeItem-damage` reaches
				this arm with `dirty ~= nil`, ZERO dirty children and an unmoved box over
				1,123 children — so without the scan the arm returns having placed
				NOTHING while the splice moved every surviving row. `war_room L reorder`
				and `removeItem-items` are the same shape at 1,471 and 1,470.5.
				`shrinkWeight`/`layoutPriority` are here for ruling A-15's reason: they
				change a rect with no measurement change. One string compare and four
				field compares per child, in a loop HEAD already runs. ]]
			if
				pIds[idx] ~= child.id
				or pRect[idx] == nil
				or pMain[idx] == nil
				or child.align ~= pCAlign[idx]
				or child.lineAlign ~= pCLine[idx]
				or child.shrinkWeight ~= pShrink[idx]
				or child.layoutPriority ~= pPrio[idx]
			then
				ok = false
				break
			end
			if dirty[child.id] ~= true then
				continue
			end
			if pHug[idx] then
				-- measured at `left` (`stack.luau:153-160`), which this arm does not
				-- reproduce; measured incidence on all three workloads is zero
				ok = false
				break
			end
			local mt, mr, mb, ml = deps.sides(child.margin)
			local w, h = deps.measure(ctx, child, innerW, innerH)
			local mainOf = if isH then w + ml + mr else h + mt + mb
			local crossOf = if isH then h + mt + mb else w + ml + mr
			if mainOf ~= pMain[idx] or crossOf ~= pCross[idx] then
				ok = false
				break
			end
			hot = hot or {}
			table.insert(hot, idx)
		end
		if ok then
			--[[ NOTHING MOVED: every child keeps the rect it has, and only the dirty
				subtrees are re-entered. The clean ones are not `place`d at all, which is
				what removes the 1,104 `arrangeBody` entries — and they were already
				costing `ctx.arranged` nothing, because that bump sits AFTER the skip
				return. A fresh rect table per re-placed child, because `arrangeBody`
				freezes what it is handed and the frozen one is already in `out`. ]]
			if hot ~= nil then
				for _, idx in hot do
					local child = children[idx]
					local prev = pRect[idx]
					local r = { x = prev.x, y = prev.y, w = prev.w, h = prev.h }
					noteContainment(ctx, node, child, r, innerX, innerY, innerW, innerH, not isH)
					place(ctx, child, r, out)
				end
			end
			return
		end
		-- REFUSED: fall through to the full body. Nothing above wrote a rect, wrote to
		-- `cmemo`, or touched T13's arrays — the refusal is free of side effects, which
		-- is the property the first prototype of this arm did not have.
	end
```

  **The measured pair is recorded WHERE IT IS MEASURED**, immediately after the hug pass
  and before the shrink and fill passes overwrite `desired` (review round 2 §3.2) —
  `stack.luau`'s `local availMain = …` line is the seam:

```luau
	--[[ WHAT THE NEXT ARRANGE INTO THIS BOX WILL RE-ASK. `desired` holds the pass-1
		measurement at `(innerW, innerH)` and the hug pass's at `left`; `margins` holds
		the four sides. The pair recorded here is therefore MARGIN-INCLUSIVE and is a
		MEASUREMENT — not `mainSize`/`crossSize`, which are margin-exclusive, clamped,
		and for a `fill` or `shrunk` child are the placement's answer rather than the
		measure's. `pHug` marks the children the replay must refuse. ]]
	if cmemo ~= nil then
		for idx, child in children do
			local m, d = margins[idx], desired[idx]
			if d ~= nil then
				pMain[idx] = if isH then d.w + m.l + m.r else d.h + m.t + m.b
				pCross[idx] = if isH then d.h + m.t + m.b else d.w + m.l + m.r
			end
			pIds[idx] = child.id
			pHug[idx] = hugSet[idx] == true
			pShrink[idx], pPrio[idx] = child.shrinkWeight, child.layoutPriority
		end
	end
```

  (`hugSet` is the index set `hugLater` already holds, turned into a lookup once.)
  Then, at the end of the placement loop beside `place(ctx, child, childRect, out)`, only
  the PLACED rect and the two arrange-classed props:

```luau
		-- the rect this loop decided. `childRect` is the SAME TABLE that reaches `out`
		-- and gets frozen there, and `commit_walks.skip` prunes on entry identity — so
		-- this array holds references, never copies.
		if cmemo ~= nil then
			pRect[idx] = childRect
			pCAlign[idx], pCLine[idx] = child.align, child.lineAlign
		end
```

  with the **nine** arrays created fresh at the top of `stack.arrange` and the key written
  after the placement loop (`cmemo.pN`, `pInnerX/Y/W/H`, `pGap`, `pAlign`, `pDistribute`,
  and the nine arrays). **When `cmemo == nil` (a store-less or reuse-off build) nothing is
  written and nothing is read** — today's code exactly.

  **The audit arm (ruling A-12):** `ctx.replayAudit` disables the fast return and makes
  the full body assert that each child's freshly computed `childRect` equals `pRect[idx]`
  whenever the replay's own gate would have fired, so the standing fuzz exercises the
  comparison on every stack it touches without weakening a gate.

  **`node.pRect = nil` on early returns is DELETED (review SHOULD-FIX 8).** `stack.arrange`
  (`stack.luau:98-442`) has **no** early returns at HEAD — `hwrap`/`vwrap` and `scroll`
  are handled in `contentSize`/`arrangeBody`, not here. Revision 1's step and its
  mutation 5 pinned a branch that does not exist.

- [ ] **Step 4: green + the differential oracle arm.** `stack_replay.spec` green. The 9-view oracle exactly as T13 step 6 defines it, on **five** fixtures: `deep_stack_scene`, a nested-stack fixture, a `fill`-child fixture, a `distribute` fixture (ruling A-13's witness — a refusal that silently changed a rect is the worst outcome this task can have), and an aspect-child fixture. **Every run twice, once with `stackReplayAudit = true`.** Standing: `host_space_oracle`, `translate_arm`, `anchor_skip`, `measure_split`, `rect_cow`, `node_reuse`, `container_memo`.
- [ ] **Step 4.5 (NEW, review round 2 §3.4): re-read the REPLAY-SURVIVAL table at THIS task's parent SHA, before quoting step 6.** `lastArrangeEntries` against the container count is the published pair; read it on `battle_hud L updateItem-hp` **and** `setState`, `war_room_inventory L setState` **and** `updateItem-power`, and `killfeed_nameplates L updateItem-hp` **and** `setState` — the two-per-workload shape is deliberate, because the measured spread inside one workload is 0.0 to 1.5 replays per step. **If `updateItem-hp` shows any replay at all, STOP: the gate is wrong, not the number** — the hp bar's width is the hp value and both the row and the enclosing list must refuse.
- [ ] **Step 5: the mutation (Step-7 discipline).** Each must BITE: (1) compare `mainOf` against `prev.w`/`prev.h` (measured-against-placed) → reddens the `fill` case. (2) drop the `crossOf ~= pCross[idx]` term → reddens a cross-only size change. (3) drop the `child.align ~= pCAlign[idx]` term → reddens the align case. (4) drop `cmemo.pGap == gap` → reddens the gap case. (5) drop the `noteContainment` replay → reddens the diagnostics case. (6) read `cmemo.mMain` instead of `pMain` (ruling A-9's violation) → reddens the `hug`-container fixture. **(7) drop the `pIds[idx] ~= child.id` scan → MUST redden the spliced-sibling fixture** (review round 2 §3.1): measured, that arm is REACHED on `battle_hud L removeItem-damage` with `dirty ~= nil`, zero dirty children and an unmoved box over 1,123 children, so a mutation that does not bite means the fixture is not a witness. **(8) drop `cmemo.pDistribute == node.distribute` → reddens a `distribute` FLIP on the container** (ruling A-15; note this is the opposite fixture to step 1's "a distribute stack whose contents did not move REPLAYS"). **(9) drop the `child.shrinkWeight ~= pShrink[idx]` term → reddens a shrinkWeight prop write on an overflowing stack.** **(10) record `pMain` from `mainSize` in the placement loop instead of from `desired` after the hug pass → reddens a MARGINED child and a `fill` child** (review round 2 §3.2 — the shipped code must not be able to pass this mutation).
- [ ] **Step 6: gates, RR, measurement, commit.** Full gates as T13 step 8; `check_source_size` with `solver.luau` and `stack.luau` recorded. **RR `facet_anchor_arrange.spec` UNCHANGED and green.** Three arms, ABBA:

  **Re-derived from the measured replay-survival table above, not from the arrange span.**

  | class | before (read at arm A) | measured survival | **expected after** |
  |---|---:|---:|---:|
  | `battle_hud L updateItem-hp` | ~0.90 (post-T13) | **0 of 1.9 — never fires** | **~0.90 (NO GAIN — this is not T14's class)** |
  | `battle_hud L setState` | ~1.00 | 1.5 of 2.0, 846.7 kids | **~0.55** |
  | `battle_hud L updateItem-facing` | read at arm A | 0.6 of 1.9, 636.6 kids | ~−25 % |
  | `battle_hud L removeItem-damage` | ~2.5 | **0 of 1.0 — the id scan refuses** | **~2.5 (NO GAIN)** |
  | `war_room_inventory L setState` | ~1.15 | 0.8 of 1.6, 615.0 kids | **~0.75** |
  | `war_room_inventory L updateItem-power` | read at arm A | 0.8 of 1.9, **1,158.8** kids | **the headline row — read it** |
  | `killfeed_nameplates L updateItem-hp` | ~0.36 | **0 of 1.9** | **~0.36 (NO GAIN)** |
  | `killfeed_nameplates L setState` | read at arm A | 0.8 of 1.0, 251.0 kids | ~−40 % |
  | `nameplates L updateItem-hp` | 0.006 | — | 0.006 (CONTROL) |

  **The three NO-GAIN rows are the honest scope of the amended lever and they must be
  reported as such in §C12.** T9b's `−44 %` on `removeItem-damage` came from an arm with
  no id scan; the shadow shows that arm reaching the fast return with ZERO dirty children
  over 1,123 spliced siblings — i.e. it was fast because it was wrong.

  Commit (after step 0's own commit) `T14: a stack re-places only its dirty children when nothing moved (C12)`.
- [ ] **Step 7: FacetBench §C12.** The mechanism, the counter table (`lastArrangeEntries` before/after with `lastArranged`/`rectWrites`/`engineWrites` shown UNMOVED beside it, because that is the safety claim), the ABBA table, the arm-C number, **the measured-vs-placed correction written up plainly**, and **the booked prefix rebase with its five prerequisite gate terms** — so the next round knows exactly what it is buying and what it must prove.

---

### Task 15 (L1c → FacetBench §C13): `layout_node.build` keeps a container's children array

**The gate:** `toLayoutNode` is **0.138 ms of 1.824 (7.6 %)** on `battle_hud L
updateItem-hp` and **0.521 / 0.538 ms** on `war_room`'s remove / reorder. Scaling says
O(tree) at ~26 ns/node (S 0.021 → L 0.138 over 519 → 5,109 nodes).

**The mechanism.** A store HIT is two hash probes and returns a whole subtree
(`layout_node.luau:386-395`). A **MISS** rebuilds and re-visits every child (`:1348-1382`):
`layoutNode.children = {}`, `local function appendChild(child)` (a fresh closure over
eight upvalues), `toLayoutNode(...)` + `table.insert` per child. `store.dirty` is
ancestor-closed, so a one-leaf write makes the enclosing ForEach region a miss and its
loop touches all 1,000 rows.

**THE OWED LIST:**

| # | channel | site | verdict |
|---|---|---|---|
| 1 | `store.nodes += hit.n` | `:394` | **SERVED** — the container's own entry records `n = store.nodes - nodesAtEntry` (`:1520-1521`), so the reuse arm sets `store.nodes = nodesAtEntry + prior.n` |
| 2 | `store.built += 1` / `store.nodes += 1` for the container | `:396-397` | **UNCHANGED** — the container is still rebuilt; only its CHILD LOOP is bounded |
| 3 | `builtIds` collection | `:408-411`, armed by `build`'s `collect` parameter | **GATED — via `store.builtIds ~= nil`, NOT `store.collect`** (review MUST-FIX 1). `newStore` (`:1658-1670`) builds exactly `{ attachOpts, metrics, textScale, prefOffset, byNode, dirty, built, builtIds, nodes, reuse }` — **there is no `store.collect`**; `collect` is a parameter of `build` (`:1686`) which sets `store.builtIds = if collect == true then {} else nil` (`:1693`). Revision 1's term was inert and its mutation could not bite |
| 4 | the `When`/`ForEach`/`ErrorBoundary` splice in `appendChild` | `:1361-1364` | **SERVED, and the argument is restated** (review SHOULD-FIX 4). Revision 1 said "a region's INTERNAL change marks the region in `store.dirty`, which the per-index re-run handles" — **there is no per-index re-run**. The real reason: `renderer.luau:2795-2804`'s `markDirtyIn` walks path STRING PREFIXES (`at = string.match(at, "^(.*)/[^/]*$")`), so a region's own path is in `store.dirty` whenever any descendant is — a conservative superset with no false-clean. `node.children` is not 1:1 with `layoutNode.children` and does not need to be |
| 5 | `hit.axis` / `hit.clip` re-validation per child | `:390-391` | **SERVED BY THE CONTAINER'S OWN PAIR** (review NOTE 9). The children were built with `childAxis` (a pure function of `kind`, fixed for a mount node) and `insideClipper == true or kind == "scroll"` (a function of `kind` plus the checked `insideClipper`), so validating the CONTAINER's `axis`/`clip` gets the children's for free. Stated explicitly because it is not obvious |

**Files:**
- Modify: `src/render/layout_node.luau` — the entry literal (already grew `cmemo`/`kids` in T13) gains `childArray`; the child loop at `:1348-1382` gains the reuse arm; the `Store` type (`:1621+`) and `newStore` (`:1658-1670`) gain `childVisits`, reset in `build` beside `store.built = 0` / `store.nodes = 0` (`:1712-1713`).
- Modify: `src/render/renderer.luau` — one line beside `stats.lastNodeBuilds = nodeStore.built` (`:2024`): `stats.lastBuildChildVisits = nodeStore.childVisits`. **Budget ≤ +120 chars (ruling A-10).**
- Modify: `src/render/render_stats.luau` — `new()` gains `lastBuildChildVisits = 0`. **`publish` is NOT changed** (the value comes from the store, not from `work`), so the seam spec's `publish` pins are untouched.
- Modify: **`tests/render_stats_seam.spec.luau`** — the `new()` field sample (`:104-119`). **Adding a field does not redden it** (review round 2 §3.8); the real pin is this task's own `lastBuildChildVisits` equality in `build_children_reuse.spec`.
- Create: `tests/build_children_reuse.spec.luau`; register.
- **RR rider: `tests/facet_measure_fanout_contract.spec.luau` and `tests/facet_translate.spec.luau`** — verified as the two RR specs that read `lastNodeBuilds`/`lastLayoutNodes` (`grep -ln 'lastNodeBuilds\|lastLayoutNodes\|layoutNodeReuse' tests/*.luau` → `facet_anchor_arrange`, `facet_measure_fanout_contract`, `facet_translate`). There is no `facet_node_reuse_contract.spec.luau` in RR. Both must be green with **no pin moved**; `./run-tests.sh` ≥ the recorded base.

**Interfaces:**
- Consumes: `store.dirty`, `store.byNode`, `store.builtIds`, `parentAxis`, `insideClipper`; the `cmemo`/`kids` carrier T13 installed.
- Produces on the store entry: `childArray: { any }` — the built `layoutNode.children`.
- Produces: `store.childVisits`, `stats.lastBuildChildVisits`.
- **Must NOT move: `lastLayoutNodes`, `lastNodeBuilds`, `lastMeasured`, `lastArranged`, `lastSkipped`, `lastSolveSkipped`, `lastChildVisits`, `lastArrangeEntries`, `rectWrites`, `engineWrites`, `solves`.**
- **INVARIANT, pinned by source scan (review SHOULD-FIX 6): a published `childArray` is NEVER mutated.** It is shared between two `layoutNode`s across ticks the moment it is reused, so any in-place edit is a cross-tick aliasing bug. The spec asserts no `layoutNode.children[` assignment and no `table.insert(layoutNode.children` outside the fresh-array arm.

- [ ] **Step 1: the owed list, then the two pins.** Five-row table into the spec header and the ledger. `tests/build_children_reuse.spec.luau` on `deep_stack_scene`:
  - **(a) an EXISTING counter as an equality red:** `lastNodeBuilds` (`renderer.luau:2024`) read off the run at the T14 SHA and after — a container that reuses still rebuilds itself, but its 1,000 children stop being built, so this moves. `lastLayoutNodes` pinned UNCHANGED in the same block, plus `solves=1`.
  - **(b) `lastBuildChildVisits` as an equality after step 2.**
  - `it("a row inserted into the list rebuilds the array")` — `node.children` is a new table, identity fails, `lastLayoutNodes` grows by exactly the new subtree.
  - `it("a ForEach region whose own children changed rebuilds")` — owed row 4's case, with the `markDirtyIn` prefix argument named in the case's comment. **Drive the ForEach EXIT-FINISH site (`mount.luau:465`, `pushDirty` at `:470`) — the in-place `table.remove` that the identity gate cannot see** (review round 2 §3.7); the `When` exit-finish site (`:197`, `pushDirty` at `:202`) is driven by the `When` fixture in step 4. Name which site each fixture drives, in the case comment.
  - `it("a container re-parented across an axis rebuilds")` / `it("a container that enters a clipper rebuilds")` — owed row 5.
  - `it("the collect arm never reuses")` — driven through `controller.analyzeBoundaries` so `build`'s `collect` is true and `store.builtIds ~= nil` (owed row 3).

- [ ] **Step 2: the counter, alone (arm C).** `store.childVisits += 1` in the child loop (+ the `Store` field, `newStore`, the reset, the renderer line, `render_stats.new`, the seam sample), mechanism off. ~1,110×/step. Same line as arm B's.

- [ ] **Step 3: the mechanism.** Replacing `:1348-1382`:

<!-- verified: sed -n '370,400p;1340,1390p;1512,1525p;1618,1632p;1645,1715p' src/render/layout_node.luau; sed -n '2020,2026p' src/render/renderer.luau; sed -n '190,205p;435,472p' src/mount.luau -->
```luau
	if #node.children > 0 then
		local childAxis: string? = if kind == "hstack" or kind == "hwrap"
			then "x"
			elseif kind == "vstack" or kind == "vwrap" then "y"
			else nil
		--[[ THE CHILDREN ARRAY IS KEPT (Plan C addendum, T15). A store HIT returns a
			whole subtree in two hash probes; a MISS rebuilds the container AND re-visits
			every child — a fresh array, a fresh `appendChild` closure over eight
			upvalues, one `toLayoutNode` call and one `table.insert` per child. The dirty
			closure marks every ANCESTOR of a changed leaf, so a one-leaf write makes the
			enclosing ForEach region a miss and its loop touches all 1,000 rows. Each is
			a 26 ns hit that returns immediately; 1,000 of them is 0.14 ms and 7.6 % of
			the class, for a tree whose shape did not move.

			THE GATE IS TABLE IDENTITY *PLUS A DIRTY SCAN*, AND THE IDENTITY HALF IS ONLY
			A CONSERVATIVE SUPERSET (ruling A-14, review round 2 §3.7). Two things
			revision 2 asserted here are false. `mount.luau:450` `node.children =
			newChildren` runs on EVERY ForEach reconcile, including when both `changed`
			and `orderChanged` are false (`:439-450`) — so identity goes cold on frames
			where nothing moved, which is a silent loss of the lever, not a defect. And
			`node.children` IS mutated in place: `mount.luau:197` (When exit-finish) and
			`:465` (ForEach exit-finish), each followed by `pushDirty(path,
			"structure")` (`:202`, `:470`). What identity actually means is "the shape
			under me is the shape I built for, OR something changed that I will ALSO see
			in `store.dirty`" — and the `store.dirty` child scan below is what closes it.
			That is why T15 is safe on this gate where T13 and T14 are not; they carry
			per-child id keys instead (ruling A-14). A length compare would accept a swap
			and a per-element compare would cost the loop this replaces. `axis`/`clip` come with it: the children were built with
			`childAxis` (a pure function of `kind`, fixed for a mount node) and
			`insideClipper == true or kind == "scroll"`, so the CONTAINER's pair
			validates the children's.

			AND THE ARRAY IS NEVER MUTATED AFTER PUBLICATION. Once reused it is shared
			between two `layoutNode`s across ticks; the spec pins by source scan that
			nothing assigns into it outside the fresh-array arm below. ]]
		local reusableKids = prior ~= nil
			and store.builtIds == nil -- owed row 3: `build`'s `collect` arm never reuses
			and prior.kids == node.children
			and prior.childArray ~= nil
			and prior.axis == parentAxis
			and prior.clip == (insideClipper == true)
		if reusableKids then
			for _, child in node.children do
				if store.dirty[child.path] then
					reusableKids = false
					break
				end
			end
		end
		if reusableKids then
			--[[ NOTHING UNDER THIS CONTAINER MOVED: the array stands and the subtree
				accounting comes off this container's own recorded `n`, which is the same
				arithmetic the per-child hit does with `hit.n`, done once. ]]
			layoutNode.children = (prior :: any).childArray
			store.nodes = nodesAtEntry + ((prior :: any).n or 1)
		else
			layoutNode.children = {}
			local function appendChild(child: any)
				if child.class == "When" or child.class == "ForEach" or child.class == "ErrorBoundary" then
					for _, grandchild in child.children do
						appendChild(grandchild)
					end
				else
					if store ~= nil then
						store.childVisits += 1
					end
					table.insert(
						layoutNode.children,
						toLayoutNode(child, metrics, textScale, prefOffset, childAxis, insideClipper == true or kind == "scroll", store)
					)
				end
			end
			for _, child in node.children do
				appendChild(child)
			end
		end
	end
```

  (`prior` is the local ruling A-8 already introduced in T13's step 3, immediately before
  the entry write; T15 hoists that read above this block.) The entry literal gains
  `childArray = layoutNode.children` beside `cmemo` and `kids`.

  **The conservative shape is deliberate.** The `store.dirty` scan is one hash probe per
  child (~0.02 µs) against a `toLayoutNode` entry plus an insert (~0.03 µs), so it is
  already most of the win and it is sound without reasoning about partial rebuilds.
  **A per-index re-run is BOOKED, not built**: it needs the reused array to be mutated,
  which the invariant above forbids, and the solver may be reading it under
  `analyzeBoundaries`.

- [ ] **Step 4: green + the differential oracle arm.** `build_children_reuse.spec` green. The 9-view oracle on `deep_stack_scene` + a `ForEach`-region fixture + a `When` fixture, three drives each (leaf write, insert, remove), arm `c` byte-equal. **Control, stated honestly (review SHOULD-FIX 7): `node_reuse`'s `layoutNodeReuse = false` arm is `store.reuse` (`layout_node.luau:1669`), which disables the per-child store hit as well — it is the whole store's off-switch, not this task's.** This task's own off-switch is the `reusableKids` predicate, exercised by the four refusal cases in step 1; say so rather than implying a dedicated control exists.
- [ ] **Step 5: the mutation (Step-7 discipline).** (1) `#prior.kids == #node.children` instead of identity → reddens the swap case. (2) drop `prior.axis == parentAxis` → reddens the re-parent case. (3) `store.builtIds == nil` → `true` → reddens the analyze case (**and unlike revision 1's `not store.collect`, this term is live, so the mutation can bite**). (4) drop the `store.dirty` scan → reddens the leaf-write case. (5) `store.nodes += prior.n` instead of `= nodesAtEntry + prior.n` → reddens `lastLayoutNodes`. (6) mutate the reused array → reddens the source-scan invariant.
- [ ] **Step 6: gates, RR, measurement, commit.** Full gates; `check_source_size` with `renderer.luau` recorded against the ≤ +120 split. Three arms, ABBA:

  | class | before (read at arm A) | **expected after** |
  |---|---:|---:|
  | `battle_hud L updateItem-hp` | ~0.33 | **~0.20** (−0.13) |
  | `war_room_inventory L reorder` | ~17 | ~16.5 (−0.52) |
  | `killfeed_nameplates L updateItem-hp` | ~0.16 | ~0.12 |
  | `nameplates L updateItems-plates` | ~2.6 (post-T12) | ~2.4 (−0.23) |

  Commit `T15: a rebuilt container keeps its children array when the shape under it did not move (C13)`.
- [ ] **Step 7: FacetBench §C13.** The store-hit-vs-store-miss asymmetry stated plainly, the counter table, the ABBA table, the never-mutated invariant, and the DEFERRED per-index version with its reason.

---

### Task 16 (L1d → FacetBench §C14): the commit's sibling PROBE, profile-gated

**GATE (ruling A-6, amended).** Build ONLY if, measured at the T15 SHA with
`attr <wl> L 3`, `cw.harvest` is **≥ 0.05 ms — i.e. ≥ 10 % of the 0.5 ms campaign
target** — on at least one of `battle_hud L updateItem-hp`, `war_room L setState`,
`killfeed L updateItem-hp`. At `e26c1daf` it is **0.089 ms**, and T13–T15 do not reduce
it, so this is a real threshold on absolute value rather than a share of a shrinking
denominator. If it does not pass, write the booking line into `progress.md` and the
closing report and go to T17.

**The mechanism, and the two things revision 1 got wrong.** `descendOf`
(`commit_walks.luau:722`) misses the cache and calls `buildDescend` (`:731`), whose loop
(`:607` `for i, child in kids do`) computes `entryVerdict` (`:512-522`) per child.
`lastCommitScans` (`render_stats.luau:147`) is that count: **1,137 against
`lastCommitVisits` 52** on `battle_hud L updateItem-hp`.

1. **The filter must NOT `continue`** (review MUST-FIX 1e). The fork points at `:637-660`
   copy a **prefix of `kids` by index** — `local len = if lb ~= nil then nb else i - 1`,
   `table.move(src, 1, len, 1, forked)` — so a `continue` leaves `i` advancing over
   children that were never appended, and the first fork after a filtered child copies
   the filtered child back into the list. **The filter instead sets the three skip flags
   directly, without probing, and lets the existing fork/aliasing code run unchanged.**
   The saving is `entryVerdict`, which is the cost (`probeEntry` plus a
   `lastCommitEntry[path]` lookup); the loop iteration itself stays.
2. **Therefore `lastCommitScans` does NOT move** — it counts loop iterations and they are
   unchanged. That makes it this task's **safety pin**, and the new counter
   `lastCommitProbes` (the `entryVerdict` calls) is the acceptance number. Revision 1
   moved `lastCommitScans` below the filter, which would have made the aliasing
   regression invisible.

**T8's own refutation is the design.** A `dirtyChildren` index is unsound: a dirty
parent's CLEAN child gets a new entry whenever the solve re-arranged it, and driven, a
`fill` box goes 300 → 220 px while the index is empty and paints 300 for the life of the
surface. **The sound form is a superset over what the SOLVE wrote**, which the solve
holds: `ctx.walkedIds` (every node whose `arrangeBody` ran — `solver.luau:2509`) and
`ctx.translatedPaths` (every node the translate arm re-based —
`translate_arm.luau:103-105`).

**THE OWED LIST:**

| # | channel | site | verdict |
|---|---|---|---|
| 1 | the `(settled, moved)` pair | `:512-522`, consumed `:628-633` | **SERVED conservatively** — a child outside all sets is `settled = true`, i.e. `skipB = skipM = skipC = true`, pruned from all three lists exactly as the probe would prune it |
| 2 | `scanCount` | `:524`, `:608` | **DOES NOT MOVE** (amended) — it counts iterations; the new `probeCount` is the acceptance number |
| 3 | the fork points and the prefix-copy aliasing | `:637-694` | **UNCHANGED, and it is why there is no `continue`** — every child still reaches the fork logic with the same `i` |
| 4 | `sawChrome` | the latch at `:1385` → `:1507`, read `:1500`/`:1567` | **STATED** — T8's Minor 1 established it is output-neutral because of the latch's LIFETIME. A filtered child that would have set it is one with a changed entry, which means it is in one of the sets |
| 5 | the unpruned arm | `:814` `pruning = enabled and dirty ~= nil and stampSame` | **UNTOUCHED** — `descendOf` returns `node.children` when `not pruning` and this task adds nothing there |
| 6 | **`walkedIds` is populated only under `if reuse ~= nil`** | `solver.luau:2508` | **CARRIED EXPLICITLY** (review MUST-FIX 1b) — on a full or structural solve it is `{}`, so an unguarded filter would classify every child as not-walked. `pruning` is separately false on those solves, which masks it; the filter **states and pins that dependency** rather than inheriting it |
| 7 | **T14's replay never walks the children it skipped** | plan T14 step 3's `return` | **SOUND, and now stated** (review MUST-FIX 2) — those are the same children the solve did not touch, so absence from `walked` is the truth about them |
| 8 | `solver.Node.id == node.path` | `layout_node.luau:608` | **LOAD-BEARING, stated** — `walkedIds` is id-keyed and `translatedPaths` is id-valued, so `walked[child.path]` is the same key space |

**Files:**
- Modify: `src/layout/solver.luau` — the `work` literal (`:3511-3540`) gains **`walkedIds = if ctx.reuse ~= nil then ctx.walkedIds else nil`** — NOT a bare `ctx.walkedIds` (review round 2 §3.5, BLOCKING). `ctx.walkedIds` is initialised `{}` in `solve_ctx.new` and is **never nil**; only its POPULATION is guarded (`solver.luau:2508` `if reuse ~= nil then`). Exported bare, the filter's `walked ~= nil` term is vacuous, a non-reuse solve classifies EVERY child as not-walked and prunes all three lists, and mutation 5 cannot bite. Exported as above, the guard is real, a non-reuse solve prunes nothing, and the mutation bites. **Budget ≤ +400 (ruling A-10).**
- Modify: `src/render/commit_walks.luau` — **`harvest` (`:795-807`) gains two OPTIONAL trailing parameters `walkedIds` and `translatedList`; `CommitCtx` is UNTOUCHED** (review round 2 §3.5, BLOCKING). `commit_walks.new` is called **once per attach** — `renderer.luau:1532-1536` says so in its own comment ("Built once per attach") — and destructures its ctx into closure locals one time, while `ctx.walkedIds` is a NEW TABLE EVERY SOLVE. Riding `CommitCtx` would freeze both values at attach, when they are nil. `harvest`'s parameter list is the per-commit route and `commitDirtySet` is its precedent. `buildDescend`'s loop gains the filter; a `probeCount` counter published beside `scanCount`.
- Modify: `src/render/renderer.luau` — pass the two through **at the `harvest` call (`:2109`), NOT at `:1536`** — beside the existing `if solveOpts.reuse ~= nil then builtDirty else nil` argument, which is the same guard shape. **Budget ≤ +280 chars (ruling A-10).** **Passing two tables and testing both inside `buildDescend` is chosen over building a union table in the renderer** (review MUST-FIX 3): a union loop plus this repo's comment density does not fit 280 chars, allocates per commit, and `commit_walks.luau` has 112 KB of headroom.
- Modify (RE-SCOPED by the route change): **`tests/commit_walks_seam.spec.luau`** — its bidirectional `CommitCtx` pins (`:203`, `:216`, `:223`) are **UNTOUCHED**, because no `CommitCtx` field is added; re-read the walk-list pin (`:417-425`) and any `harvest` arity pin off the run and re-record only what actually moves. **`tests/commit_dirt_classes.spec.luau:966-975` and `tests/commit_translate.spec.luau:330-343` call `walks.harvest(…)` POSITIONALLY and are not `CommitCtx` builders** — two optional trailing parameters leave them compiling and green with the filter simply off, so editing them is **optional coverage, not a prerequisite**. Add the two arguments to at least one call site in each so the filter is exercised there, and name which in the commit message.
- Modify: `src/render/render_stats.luau` + `tests/render_stats_seam.spec.luau` (the `new()` field sample at `:104-119`) — `lastCommitProbes`. **T16 is the FOURTH task on this spec** — the conflict table row now says so (review round 2 §3.7) — and, like the other three, it must not plan a red around a SAMPLE that does not catch additions.
- Create: `tests/commit_probe_filter.spec.luau`; register.
- **RR rider: `tests/facet_commit_dirt_classes.spec.luau` and `tests/facet_commit_translate.spec.luau`**, plus `./run-tests.sh` green.

**Interfaces:**
- Consumes: `result.work.walkedIds` (new export), `result.work.translatedPaths` (**an integer-indexed ARRAY — `solve_ctx.luau:249` `translatedPaths: { string }`, appended at `translate_arm.luau:103-105`, truncated in place at `solver.luau:2494-2496`; it must be ITERATED as a list, never merged as a map** — review MUST-FIX 1c), `nodeDirty`, `commitDirty`.
- Produces: `stats.lastCommitProbes`. **Must NOT move: `lastCommitScans`, `lastCommitVisits`, `lastCommitVisitsByWalk`, `lastCommitListCells`, `rectWrites`, `propWrites`, `engineWrites`, `elided`, `creates`, `removes`, `parked`, `recycled`.**

- [ ] **Step 1: run the gate.** `attr` on the three workloads at the T15 SHA; write `cw.harvest`'s ms per class into `progress.md`. If none passes ≥ 0.05 ms, STOP and book.
- [ ] **Step 2: the owed list, then the two pins.** Eight-row table into the spec header and the ledger. `tests/commit_probe_filter.spec.luau`:
  - **(a) `lastCommitScans` as an equality that must NOT move**, read off the run at HEAD — the aliasing safety pin.
  - **(b) `lastCommitProbes` as an equality after step 3**, with `lastCommitVisits` unchanged in the same block, and `solves=1`.
  - **T8's own case as the acceptance test: `it("a clean child of a dirty parent")`** — a `fill` box under a dirty parent whose width goes 300 → 220 while it is in no dirty set; its rect must commit at 220.
  - `it("a reorder degrades to today's probe count")` — `war_room`-shaped, nearly every child dirty.
  - `it("a full solve filters nothing")` — owed row 6: `walkedIds` empty, `pruning` false, probes at the full count.
  - `it("a viewport change filters nothing")` — the unpruned arm.
- [ ] **Step 3: the counter, alone (arm C).** Add `probeCount` and its publish with the filter's predicate evaluated but its effect discarded — i.e. compute the four terms, ignore the result, always probe. That prices the predicate. **`probeCount` sits on the same line in arm B and arm C** (review MUST-FIX 4).
- [ ] **Step 4: the mechanism.** In `buildDescend`'s loop, replacing the `local skipB, skipM, skipC` block:

<!-- verified: sed -n '318,330p;510,526p;576,584p;605,612p;626,660p;790,820p' src/render/commit_walks.luau; sed -n '2500,2515p;3486,3545p' src/layout/solver.luau; sed -n '1525,1545p;2100,2125p' src/render/renderer.luau -->
```luau
			--[[ A CHILD THE SOLVE NEVER TOUCHED CANNOT HAVE A NEW ENTRY (Plan C addendum,
				T16). `arrangeBody`'s skip is the contract: a subtree it skipped kept its
				entry TABLE, and `skip` prunes on entry identity — so `entryVerdict` answers
				`settled = true` for such a child BY CONSTRUCTION and the probe is pure
				cost. On `battle_hud L` a one-leaf write asks it 1,137 times to descend 52
				nodes.

				THE FILTER IS A SUPERSET, WHICH IS THE HALF T8 GOT WRONG AND SAID SO. A
				`dirtyChildren` index is unsound: a dirty parent's CLEAN child gets a new
				entry whenever the solve re-arranged it, and driven, a `fill` box goes
				300 -> 220 px while the index is empty and paints 300 for the life of the
				surface. `walked` is not a dirty set — it is every node whose `arrangeBody`
				RAN plus every node the translate arm re-based, i.e. every node whose entry
				this solve could have REPLACED. A stale or over-wide `walked` costs a
				probe, never a missed write.

				AND IT DOES NOT `continue`. The fork points below copy a PREFIX OF `kids`
				BY INDEX (`i - 1`), so skipping the rest of the body would let the first
				fork after a filtered child copy that child back in — the T8-class defect
				this task exists to avoid, one level down. The flags are set directly and
				every child still reaches the fork logic with the same `i`. `scanCount`
				therefore does not move; `probeCount` is this task's number.

				`walked` IS NIL ON A NON-REUSE SOLVE, AND THAT IS AN EXPORT DECISION.
				`ctx.walkedIds` is `{}` from `solve_ctx.new` and is NEVER nil; only the
				WRITE is guarded (`solver.luau:2508` `if reuse ~= nil then`). So the `work`
				literal exports `if ctx.reuse ~= nil then ctx.walkedIds else nil`: an
				empty-but-present set would make this guard VACUOUS and prune every child
				on a full solve. `pruning` (`:814`) is separately false there — which is
				exactly the inheritance this task exists to stop relying on. The guard is
				real, a case pins it, and mutation 5 can bite.

				AND IT ARRIVES ON `harvest`'s PARAMETER LIST, NOT ON `CommitCtx`.
				`commit_walks.new` runs ONCE PER ATTACH (`renderer.luau:1532-1536`) and
				destructures its ctx into closure locals there; these two tables are new
				every solve, so a ctx field would be frozen at nil forever. ]]
			local skipB, skipM, skipC
			if dirtyAll and dirtyCommit then
				skipB, skipM, skipC = false, false, false
			elseif walked ~= nil and walked[p] ~= true and not dirtyAll and not dirtyCommit then
				skipB, skipM, skipC = true, true, true
			else
				probeCount += 1
				local settled, moved = entryVerdict(child)
				skipB = not dirtyAll and settled
				skipM = not dirtyAll and (settled or moved)
				skipC = not dirtyCommit and (settled or moved)
			end
```

  `walked` is built once per commit inside `harvest`, from that function's own two new
  parameters, beside `nodeDirty = dirty` / `commitDirty = commitDirtySet` (`:808-809`) —
  **iterating `translatedPaths` as the ARRAY it is**:

```luau
		--[[ ONE SET PER COMMIT, FROM WHAT THE SOLVE PUBLISHED. `walkedIds` is already a
			path-keyed set; `translatedPaths` is an integer-indexed ARRAY of ids
			(`solve_ctx.luau:249`, appended in `translate_arm`), so it is iterated, never
			merged. `solver.Node.id == node.path` (`layout_node.luau:608`), so the two are
			the same key space. Nil when the solve published neither — the filter then
			never fires and every child is probed, exactly as today. ]]
		walked = walkedIds
		if walked ~= nil and translatedList ~= nil and #translatedList > 0 then
			local merged = table.clone(walked)
			for _, id in translatedList do
				merged[id] = true
			end
			walked = merged
		end
```

  `commitDirty` is legitimately `nil` on a commit handed no second set (`:581`
  `wantCommit = commitDirty ~= nil`), in which case `dirtyCommit == dirtyAll` and the
  filter is one term weaker than the owed list's wording — **stated in the spec header**
  (review SHOULD-FIX 6).

- [ ] **Step 5: green + the differential oracle arm.** 9 views, arm `c` byte-equal, on `deep_stack_scene` + the `fill`-child fixture + **a chrome-bearing fixture** exercising the unpruned arm. **The two conditions that disable the prune, re-cited (review SHOULD-FIX 7 — revision 1's `:803`/`:967` were a parameter and a comment):** the `UI.Path` condition is `commit_walks.luau:1273` `local prunable = next(pathNodes) == nil` (consumed `:1278`/`:1313`), and the `expandTarget` condition is the chrome latch `:1385` `isFrameworkChrome` → `:1507` `sawChrome = true`, read at `:1500`/`:1567`; the whole-commit switch is `:814`. Standing: every commit-walk oracle plus `commit_dirt_classes.spec`, `commit_scope.spec`, `structural_scope.spec`.
- [ ] **Step 6: the mutation.** (1) drop the `not dirtyAll` term → reddens a dirty-child case. (2) use `nodeDirty` alone as the filter (T8's unsound index) → **must redden the `fill` case**; if it does not, the fixture is not a witness and step 2 is wrong. (3) replace the flag-set with a `continue` → **must redden a fork case** (the aliasing regression, owed row 3). (4) merge `translatedPaths` as a map → reddens a translate fixture. (5) drop the `walked ~= nil` guard → reddens the full-solve case. **It can only bite once the `work` literal exports `if ctx.reuse ~= nil then ctx.walkedIds else nil`** (review round 2 §3.5); if it does not bite, the export is bare and step 4 is wrong. **(6) export `walkedIds = ctx.walkedIds` bare → MUST redden the full-solve case too** — the same defect from the producing side. **(7) move the two tables onto `CommitCtx` / `commit_walks.new` instead of `harvest` → MUST redden every filtered case**, because `new` runs once per attach and both values would be frozen at nil.
- [ ] **Step 7: gates, RR, measurement, commit.** Full gates; `check_source_size` with `solver.luau`, `commit_walks.luau` and `renderer.luau` recorded against their splits. Three arms, ABBA; expected `battle_hud L updateItem-hp` **~0.20 → ~0.14**, `killfeed L hp` ~0.12 → ~0.09, `war_room reorder` ~16.5 → ~16.2. Commit `T16: the commit probes a child only when the solve could have replaced its entry (C14)`.
- [ ] **Step 8: FacetBench §C14.** Including, plainly, that T8 named this mechanism unsound in one form and this is the other form, with the `fill`-child case as the difference — and that the filter deliberately keeps the loop so the fork's prefix arithmetic is untouched.

---

### Task 17 (L3 → FacetBench §C15): the live-only 1.5 ms

**The finding** (T9b §5), measured at `09d2dfcc` through `FacetBenchRun` with the marker
read back (`af4f519`; `solver.luau` 190,112 = clean HEAD):

| class | Lune | live | **surplus** | engine writes |
|---|---:|---:|---:|---:|
| `battle_hud L updateItem-hp` | 1.824 | 3.382 | **+1.56 ms** | 4 |
| `battle_hud L setState` | 1.927 | 3.426 | **+1.50 ms** | **0** |
| `nameplates L updateItem-hp` | 0.006 | 0.295 | +0.29 | 2 |

Live scaling over S/M/L (519 / 2,049 / 5,109 nodes): slope **0.635 µs/node**, intercept
**0.129 ms** — the surplus is in the MARGINAL, ~1.95x the Lune marginal (0.326). A class
with **zero** engine writes costing 1.5 ms more live than headless is not property-write
cost.

**The first HYPOTHESIS, framed as one (review SHOULD-FIX 3).** The session's first live
drive printed `C stack overflow (when calling anonymous function on line 484 in
ReplicatedStorage.ui.Facet.src.client.text_premeasure)` followed by `Script timeout`. At
HEAD `src/client/text_premeasure.luau:484` is `text_premeasure.spawn(function()`, a spawn
callback inside the `deliver`/`measureBatch` body (`:478-489`) — **not visibly
recursive**; the file is 522 lines. The overflow is evidence that *something* on that
path recurses or re-enters under load, not proof of where. Treat it as a lead.

**Files (conditional):**
- Create: `../FacetBench/docs/studio-runs/2026-09-05-microprofiler-battle_hud-hp.md`.
- Modify (only if Facet-side): the named module, plus a headless pin.
- Create (only if Facet-side): the spec the capture names; register.
- **RR rider (review MUST-FIX 2): `tests/facet_text_settle_contract.spec.luau`** — the RR contract over the text-settle path that `src/client/text_premeasure.luau` serves — plus `tests/facet_large_text_contract.spec.luau` and `./run-tests.sh` green. Named now so a `src/client/` change cannot ship without its consumer evidence.

**Interfaces:** none until the capture says. **This task may produce a booking and a
mechanism instead of a change (ruling A-7).**

- [ ] **Step 1: the capture.** Follow `../FacetBench/docs/studio-runs/2026-09-01-microprofiler-campaign-before.md`'s method: read the tick rate from `session:FetchGlobalDesc().TickToMsCpu` rather than calibrating it, and BOUND the frame window to the run's own frames (the 256-frame ring dilutes percentiles). **Failure mode, stated (review SHOULD-FIX 4): if `FetchGlobalDesc` is unavailable in the MCP command VM, fall back to the calibrated tick rate that doc supersedes and SAY SO in the write-up — a capture with a stated calibration is evidence; a capture with an unstated one is not.** Drive `battle_hud` L, facet only, `updateItem-hp`, through the direct `require(...).run{…}` call inside ONE `execute_luau` — the one thing the RemoteEvent relay cannot do — with **nothing else running** (the MCP VM keeps its own require cache, so the "refused, not queued" guard does not span the two VMs). Facet's `profile` spans ON. Stamp and read the marker back first through a probe LocalScript; a disagreement between the disk marker, the mounted `Source` and the console is a hard stop.
- [ ] **Step 2: attribute the 1.5 ms.** The per-span live table for one `updateItem-hp` step — `Facet/measure`, `Facet/arrange`, `Facet/commit`, `Facet/mount`, `Facet/react`, `Facet/dirtyScan`, `Facet/lane` — **and the engine bars beside them**. One sentence: *is the surplus inside Facet's own spans (so T13–T16 take most of it) or outside them (so it is engine or premeasure and a separate lever)?*
- [ ] **Step 3: the `text_premeasure` lead.** Read `:478-489` and the `spawn`/`deliver`/`measureBatch` triangle. **Reproduce the overflow in a spec if it is Facet's** — an unbounded re-entry a 200-sample `battle_hud` drive can reach is a correctness defect independent of any millisecond, and it belongs on the RED-TEAM list at Task 10 whether or not it is the 1.5 ms. If it is not reproducible headless (it may need real `GetTextBoundsAsync`), say so and book it with the console line as the evidence.
- [ ] **Step 4: the fix, or the booking — BOUNDED (review MUST-FIX 1).** If Facet-side: fix it, pin it headless, re-drive live. **STOP CONDITIONS, any one of which routes to the A-7 booking instead:** the fix touches more than ONE `src/` module; it exceeds **+2,000 chars** in that module or breaches `check_source_size`'s allowance for it; it changes a public API, a counter, or the boot-window settle behaviour `tests/text_settle.spec.luau` and RR's `facet_text_settle_contract.spec.luau` pin; or it cannot be pinned headless. On a STOP, write the mechanism, the numbers and the proposed shape into the FacetBench section and `progress.md`, and hand it to Task 10 as a booked item — **that is a complete deliverable, not a failure.** If engine-side: name the mechanism (which Roblox call, on how many objects, why 4 writes cost 1.5 ms) and book it with the number the campaign report must quote.
- [ ] **Step 5: gates + commit.** If any `src/` changed: full gates, `check_source_size`, **RR `./run-tests.sh` with `facet_text_settle_contract` and `facet_large_text_contract` named in the transcript**. If not: the FacetBench doc alone. Commit `T17: the live-only millisecond and a half, attributed (C15)` (or `…, booked`).
- [ ] **Step 6: FacetBench §C15.** The capture (with its calibration stated), the attribution, the per-class live/Lune surplus table, and the standing rule it produces: **a headless lever's live gain is unknown until the live/headless ratio for its class is attributed** — this campaign predicted "about 2x" from a scaling fit and that is the weakest number in the whole report.

---

## Amendment log (review round 1) — every finding, dispositioned

> **Round 2 re-graded four of the dispositions below. Where this section and the round-2
> log disagree, the round-2 log wins.** Specifically: T13-6's "refusing those two kinds
> outright" was re-amended to per-child only (ruling A-16); T14-2's `pMain` fix was
> incomplete (review round 2 §3.2); T14 NOTE 14 / ruling A-13 is partially superseded by
> A-15; T15-1's `:1694` is `:1693`; T16-1b's guard was inert and T16-1d's route was
> wrong.

**§0 (BLOCKING).** FIXED by **ruling A-8**: the memo's home is `store.byNode[node].cmemo`,
mount-keyed and weak, with `layoutNode.cmemo` as a pointer refreshed on rebuild under one
gate (`kids` identity, `axis`, `clip`) shared with T15. Both mechanisms re-derived; every
expected-ms row now says "read at arm A" instead of quoting a prediction as a before.

**T12.** 1 FIXED (the site sets are 2 writes / 3 deletes and the pin is an enumerated
list, not a count equality). 2 FIXED (`adopt` never deletes the old key; the index keeps
it, to match today's walk; fixing the leak is out of scope and said so). 3 FIXED (an
adopt fixture added; the path-selection / host-chain-computation split is stated in the
code comment). 4 FIXED (the nine helper sites in seven files listed; **ruling A-11** keeps
`ops` off in `deep_stack_scene` and `nameplates_scene`; the eight specs listed). 5 FIXED
(22 sites, `:1866` and `:1882` added). 6 FIXED (labelled a characterisation pin; a real
red — the `ops()` assert — added). 7 FIXED (both arms armed in
`commit_scope`/`structural_scope`). 8, 9 NOTED and kept.

**T13.** 1 FIXED (**ruling A-3**: the raw offer pair; no `offerHeightKey` call). 2 FIXED
(`sides`/`marginMain` are written for every child before the fill branch, as at HEAD).
3 FIXED (**owed row 5**: `crossOf` is allocated fresh, so the fill pass re-measures every
fill child on every call, as today). 4 FIXED (**owed row 4**: a container with any
`shrinkWeight > 0` child never memoises). 5 FIXED (dissolved by 4 — PASS 1.5 cannot run
on a memoised container; and by **ruling A-4**, nothing is patched). 6 FIXED (**owed row
2**: `text`/`composition` direct children are never skipped, so no slot is read at all).
7, 8 FIXED (dissolved — `crossMax` stays HEAD's O(n) loop; there is no `touchedThisPass`
and no `ctx.aTouched`). 9 FIXED (`mStamp: string?`, plus an explicit
`ctx.measureStamp ~= nil` term). 10 FIXED (`mMargin` is in the Interfaces list; the count
is stated as seven names). 11 FIXED (`solve_ctx.luau` in the Files list, with its `Ctx`
type, its `new()` initialiser and `solve_ctx_seam.spec`). 12 FIXED (**ruling A-12**: the
audit arm). 13 FIXED (`mainSum += 0` deleted). 14 FIXED (equality pins; Global Constraints
now forbid inequalities). 15 FIXED (each task pins an EXISTING counter as its red).
16 FIXED (**ruling A-10**: the budget is split T13/T14/T16 and T15/T16 for the renderer).
17 FIXED (the seam's Deps re-read; `mainDimOf` removed, `ctx.fitProbe` added). 18, 19,
20 NOTED — 20 is load-bearing and is now cited in owed row 1.

**T14.** 1 FIXED (dissolved: the replay fires only when the dirty child's own extents are
unchanged, so it is placed at a rect that IS correct; a size change refuses). 2 FIXED
(**ruling A-9**: T14 owns `pMain`/`pCross` at the arrange offer and never reads T13's
`mMain`). 3 FIXED (same; and the refusal path writes nothing at all). 4 FIXED (dissolved:
nothing is shifted, so a clean `fill` sibling cannot be shifted-instead-of-resized).
5 FIXED (dissolved and replaced by the stronger single condition — `gap`, `align`,
`shrunk`, `clipMain` and aspect are all functions of inputs the gate holds constant; the
argument is in the mechanism comment). 6 FIXED (`work.walkedIds` is exported by T16 and
listed in its Files; T14's owed row 4 no longer leans on a field that does not exist).
7 FIXED (`solve_ctx.luau` listed). 8 FIXED (`stack.arrange` has no early returns; the
step and its mutation are deleted). 9 FIXED (`ctx.noSkipDepth` added to the read-set; the
`(ctx :: any)` casts removed). 10 FIXED (equality pins). 11 FIXED (audit arm + five
fixtures built to hit the gate).
12, 13 NOTED and cited. **14 REFUTED — see ruling A-13**: refusing `distribute` was
correct for a prefix rebase and is unnecessary for the amended replay, because
`distributionOf` (`stack.luau:343`) reads `remaining` (`:296`), which the gate holds
constant. A `distribute` fixture is added as the witness, and it is a REPLAY case, not a
refusal case.

**T15.** 1 FIXED (`store.builtIds ~= nil`, per `layout_node.luau:1686` — `build`'s `collect` parameter — and **`:1693`**, `store.builtIds = if collect == true then {} else nil`. Revision 2's log said `:1694`, one line off and in disagreement with T15's own owed row; corrected in round 2, review round 2 §2; the
mutation can now bite). 2 FIXED (`renderer.luau` in the Files list with a ≤ +120 split;
`Store` type, `newStore`, and the reset beside `store.built = 0` all listed). 3 FIXED
(`tests/render_stats_seam.spec.luau` is a listed file and an explicit step in T13, T14 and
T15; the `publish` signature does not change in this wave). 4 FIXED (owed row 4 restated
in `markDirtyIn`'s path-prefix terms). 5 FIXED (equality pins). 6 FIXED (the
never-mutated invariant, with a source-scan pin). 7 FIXED (stated: `layoutNodeReuse` is
the whole store's off-switch, not this task's; the four refusal cases are the control).
8, 9, 10, 11 NOTED — 9 and 10 are now cited in owed row 5 and ruling A-8.

**T16.** 1 FIXED (`work.walkedIds` exported, `solver.luau` listed and budgeted).
1b FIXED (owed row 6 carries the `reuse ~= nil` dependency and a case pins it). 1c FIXED
(iterated as an array, with the citation). 1d FIXED (all three test edits listed).
1e FIXED (**no `continue`** — the flags are set directly, the fork arithmetic is
untouched, and `lastCommitScans` becomes the safety pin while a new `lastCommitProbes` is
the acceptance number). 2 FIXED (owed row 7 states the T14→T16 coupling). 3 FIXED (two
tables passed, tested in `buildDescend`; renderer split raised to ≤ +280). 4 FIXED
(`probeCount` on the same line in arms B and C). 5 FIXED (**ruling A-6** amended to
≥ 0.05 ms = 10 % of the campaign target). 6 FIXED (the `commitDirty == nil` case stated).
7 FIXED (`:1273` and `:1385`/`:1507` cited in place of `:803`/`:967`). 8, 9, 10 NOTED —
8 is owed row 8, 10 is why `lastCommitScans` is the safety pin.

**T17.** 1 FIXED (step 4 carries four STOP conditions and routes to A-7). 2 FIXED
(`facet_text_settle_contract.spec.luau` + `facet_large_text_contract.spec.luau` named).
3 FIXED (framed as a hypothesis, with `:484`'s actual content quoted). 4 FIXED (the
`FetchGlobalDesc` fallback and the requirement to state the calibration). 5, 6 NOTED.

**Cross-cutting.** Red pins — FIXED (two pins per task: an existing counter as an
equality red, the new counter as an equality after the counter-only step; inequalities
forbidden in Global Constraints). `solves=N` — kept. Forced-on oracle — FIXED by
**ruling A-12** for both T13 and T14. Never-amend / one-writer / RR lockstep / gates —
kept, and T17 now names its rider. Unlisted files — FIXED: `solve_ctx.luau` (T13, T14),
`renderer.luau` (T15, T16), `solver.luau` (T14, T16), `render_stats_seam.spec.luau`
(T13, T14, T15), the three commit-ctx tests (T16).


---

## Amendment log — round 2 — every finding, dispositioned, and the two measurements it demanded

**Measured at Facet `92d3e7e4`** in a detached worktree (`git worktree add … 92d3e7e4`)
with a private copy of FacetBench beside it, so the Task-12 agent's in-flight
`tests/lib/fake_target.luau` edit in the shared tree could not reach the run. FacetBench
resolves Facet by relative path (`frameworks/facet/adapter.luau:5`
`require("../../../Facet/src")`), which is what makes the worktree arm possible at all.
Instrument: a temporary census inside `contentSize`'s vstack/hstack branch, a temporary
shadow of the amended replay inside `stack.arrange` after the hug pass, and a temporary
`kids` field on the store entry so the carrier gate could be evaluated at HEAD. Driver: a
private `tools/profile/gate_probe.luau` modelled on `attr` — mount, 50 warm-up steps, then
the whole script with the counters reset per step and bucketed by `attr`'s own
`bucketName`. **Neither instrument changes a rect; both are discarded.** One `lune` at a
time throughout.

### Measurement L-1a — T13's gate survival

*"Of the containers `contentSize` enters on a 1-leaf update, how many pass the plan's
gate?"* The useful denominator turned out to be not containers but the per-child `measure`
calls those containers issue, which is what the lever removes.

| class | containers / measures per step | **plan as written** | **id key + per-child text refusal (ruling A-14 + A-16)** |
|---|---:|---:|---:|
| `battle_hud L updateItem-hp` | 5.6 / 1,065.4 | 0.2 % of containers, **15.3 measures = 1.4 %** | **1,031.0 = 96.8 %** |
| `battle_hud L setState` | 3.0 / 1,112.8 | 1.1 %, **36.7 = 3.3 %** | 1,081.7 = 97.2 % |
| `battle_hud L removeItem-damage` | 1.0 / 1,123.0 | 2.2 %, 24.5 = 2.2 % | **0.0 = 0.0 %** (indices moved) |
| `war_room_inventory L setState` | 2.4 / 1,155.2 | 33.3 %, **1,151.3 = 99.7 %** | 1,151.3 = 99.7 % |
| `war_room_inventory L updateItem-power` | 2.8 / 1,367.6 | 33.3 %, 1,359.2 = 99.4 % | 1,362.9 = 99.7 % |
| `war_room_inventory L reorder` | 1.0 / 1,471.0 | 100 %, 1,471.0 = 100 % | **0.0 = 0.0 %** (indices moved) |
| `killfeed_nameplates L updateItem-hp` | 2.9 / 324.7 | 0.0 %, **0.0 = 0.0 %** | **244.3 = 75.2 %** |
| `killfeed_nameplates L setState` | 1.0 / 331.0 | 0.0 %, 0.0 = 0.0 % | 255.0 = 77.0 % |

**Two findings, and neither was predictable from `war_room` alone.**

1. **The container-level `text`/`composition` kill costs T13 its own headline.** The
   review predicted "every `UnitRow` has two `Text` direct children, so no row memoises;
   only the flat root list does". The measurement is worse than that: the flat root list
   **also** holds `text` children — `battle_hud`'s Damage `ForEach` splices `DmgText`
   labels straight into the root panel's flow (`text=9…44` on a 1,110–1,145-child
   container across the run) — so **nothing memoises on `battle_hud` at all**, and
   `killfeed` reads a flat 0.0 %. Ruling **A-16** deletes the container-level term; the
   per-child refusal that was always there carries the correctness. `war_room` reads
   99.4–99.7 % either way, which is exactly why quoting it would have hidden this.
2. **The id key is mandatory and it is not free.** Without it the gate reads 98.0–100 %
   on `removeItem-damage`, `reorder` and `removeItem-items` — every one of those serves a
   number belonging to a different node, because the `ForEach` splice shifted the index
   while `prior.kids == node.children` still held. With it those classes read 0.0 %, which
   is the correct answer and is now written into T13's expected table as **NO GAIN**.

### Measurement L-1b — T14's replay survival

*"On `battle_hud updateItem-hp` and `setState`, does the dirty row's MEASURED main/cross
extent change?"* **Yes on `hp`, at both levels.** The shadow implements the amended gate —
id scan over every child, box/gap/align/distribute key, margin-inclusive measured
contributions taken from `desired` + `margins` after the hug pass — and counts what fires.

| class | `stack.arrange` entries / step | **replays** | children skipped / step |
|---|---:|---:|---:|
| `battle_hud L updateItem-hp` | 1.9 | **0.0** | 0 |
| `battle_hud L setState` | 2.0 | 1.5 | 846.7 |
| `battle_hud L updateItem-facing` | 1.9 | 0.6 | 636.6 |
| `battle_hud L add/removeItem-damage` | 1.0 | **0.0** | 0 |
| `war_room_inventory L setState` | 1.6 | 0.8 | 615.0 |
| `war_room_inventory L updateItem-power` | 1.9 | 0.8 | **1,158.8** |
| `war_room_inventory L updateItem-tier` | 1.4 | **0.0** | 0 |
| `war_room_inventory L reorder`, `removeItem-items` | 1.0 | **0.0** | 0 |
| `killfeed_nameplates L setState` | 1.0 | 0.8 | 251.0 |
| `killfeed_nameplates L updateItem-hp` | 1.9 | **0.0** | 0 |

Refusal reasons on `battle_hud L updateItem-hp`, named by the shadow: `MAIN` moves for
`/Root/Units/[uN]/UnitRow-uN :: …/UnitHp-uN` and `CROSS` moves for
`/Root :: /Root/Units/[uN]/UnitRow-uN`. The review's reading is confirmed exactly — the
bar's fixed width IS the hp value (`adapter.luau:39-46` × `battle_hud.luau:92-96`), the
row refuses on its main axis and the 1,000-row list refuses on its cross axis.

**And a defect the review's §3.1 predicted but did not price.** On `removeItem-damage`,
`reorder`, `removeItem-items`, `removeItem-feed` and `removeItem-plates` the arm is
REACHED with `dirty ~= nil`, **ZERO dirty children** and an unmoved box, over
**1,123 / 1,471 / 1,470.5 / 324.7 / 333.5** children respectively. Revision 2's loop only
examined dirty children, so it would have taken the fast return **having placed nothing at
all** while the splice moved every surviving row. That is the strongest single argument for
ruling A-14, and it is why the `pIds` scan runs over EVERY child, not only the dirty ones.
`dirty == nil` never occurs on any measured class (0.0 everywhere), so `dirty ~= nil` was
carrying no weight here. Hug children: **zero** dirty-hug refusals on all three workloads,
so refusing them costs nothing.

### Findings

| Round-2 finding | Disposition |
|---|---|
| §2 MUST-FIX (T12): `:271-275` self-contradictory | **FIXED.** `indexNode` at `:482` **and** `:1029`; `unindexNode` at `:873`, `:936`, `:1124`; the adopt old key deliberately kept. Stated once, and matched to what Task 12's implementer was already told |
| §2 NOTE: log cites `layout_node.luau:1694` | **FIXED** → `:1693`, and the log now says why it was wrong |
| §2 NOTE: `stack_seam.spec:163` is the whole block | **FIXED** → `:161` (`ctx`), `:162` (`node`), `:163` (`child`) |
| §2 SHOULD-FIX: read-set gains `node.gap` | **FIXED.** `gap` is a **parameter** of `stack.arrange` (`stack.luau:98-112`), not a node field; the set gains `ctx.reuse`, `ctx.noSkipDepth`, **`ctx.replayAudit`**, `node.cmemo`, **`child.id`** and **`child.layoutPriority`**, and NOT `node.gap` |
| §3.1 MUST-FIX (BLOCKING, T13+T14): `kids` identity does not protect an index-keyed array | **FIXED by ruling A-14**, id-keyed at both sites (`mIds`, `pIds`), with the measurement above as the evidence and the spliced-sibling fixture + mutation added to both tasks |
| §3.2 MUST-FIX (BLOCKING, T14): `pMain` is a PLACED extent | **FIXED.** The pair is recorded from `desired` + `margins` immediately after the hug pass — margin-inclusive, measured, at the pass-1 offer this arm re-measures at — and a dirty HUG child is refused (`pHug`). Margins therefore need no separate refusal. Mutation 10 pins it |
| §3.3 MUST-FIX (T14): three placement inputs outside the gate | **FIXED by ruling A-15**: `pDistribute` in the key, `pShrink`/`pPrio` per child, each with its reader cited (`stack.luau:328`/`:343`, `:188`/`:208`, `shrink.luau:335`). Refusing on a dirty container was rejected against the measurement |
| §3.4 MUST-FIX (T14, the headline): the replay cannot fire on `updateItem-hp` | **FIXED. The task's headline class is changed.** Measured (L-1b), the expected table now reads NO GAIN on `updateItem-hp`, `killfeed hp` and `removeItem-damage`, and names `setState` / `updateItem-power` as what T14 actually buys. Step 4.5 STOPS if `hp` ever shows a replay |
| §3.5 MUST-FIX (BLOCKING, T16): route + vacuous guard | **FIXED both halves.** `walked` rides `harvest`'s parameter list (`commit_walks.luau:795-807`, called `renderer.luau:2109`), `CommitCtx` untouched; the `work` literal exports `if ctx.reuse ~= nil then ctx.walkedIds else nil` so the `walked ~= nil` guard is real and mutations 5–7 bite |
| §3.6 MUST-FIX (T13): survival unmeasured; residual counts one pass of three | **FIXED both halves.** Survival measured on all three workloads (L-1a) and every expected-ms row re-derived from it; residual re-booked at **~0.10–0.15 ms (10–15 %)**, not 0.03 ms (3 %), with the skip arm's own six table operations named. Step 4.5 re-reads survival at the task's own SHA |
| §3.7 SHOULD-FIX: `parentPathOf` ≠ `hostFor`'s walk | **FIXED** in the code comment |
| §3.7 SHOULD-FIX: audit arm has no route into a spec | **FIXED.** The attach-opt path `node_reuse`/arm `c` already use, plus a public-surface absence pin, both now blocking for T13 step 6 and T14 step 4 |
| §3.7 SHOULD-FIX (T15): the `mount` invariant is wrong on both halves | **FIXED.** Restated as "a conservative superset the dirty scan closes", with `mount.luau:450` (runs on every reconcile), `:197`/`:202` and `:465`/`:470` cited, and step 1 naming which exit site each fixture drives |
| §3.7 SHOULD-FIX: conflict table missing T16, `run.luau`, the ledger, the `layout_node` code motion | **FIXED.** Four rows added/re-graded, including the `local prior` hoist |
| §3.8 NOTE: `render_stats_seam.spec:104-119` is a SAMPLE | **FIXED, as a correction rather than an addition.** The table row is re-graded and all four tasks now say plainly that adding a field does not redden it and that the real pin is the task's own counter equality. No task plans a red around it |
| §3.7 SHOULD-FIX (T14): `stack_seam`'s read-vs-write half | **FIXED** — stated in step 0 |
| §3.8 NOTE: weak-key lifetime is sound and worth stating | **NOTED** — ruling A-8 already carries the lifetime argument; the "no upward pointer, so the value cannot pin its own key" half is worth one line in T13's §C11 write-up and is booked there |
| §3.8 NOTE: source-cap splits need re-checking after the amendments | **FIXED** in Global Constraints: each task re-runs `check_source_size` before and after stylua, and a task over its split takes its seam or spends the reserve with a ledger line naming it |
| §3.8 NOTEs: T15 arithmetic, `store.builtIds`, T17 READY, cap arithmetic | **NOTED, no change** |

**Verdicts carried forward:** T15 and T17 are READY and are untouched by this round except
for the conflict table, the `:1693` citation, the seam-spec sample re-grade and T15's
restated invariant.

---

## Self-review (round 3)

**What round 2 changed about this plan's honesty.** Two of the six tasks were quoting
expected milliseconds that the mechanism could not deliver — T13 at 1.4 % of the calls it
claimed and T14 at 0 replays on its named headline class — and neither was detectable by
reading the code, because both gates are correct in isolation and wrong against the
workload. **Every expected-ms row in T13 and T14 is now derived from a measured survival
fraction, and three rows say NO GAIN.** The rule this produces, for Task 10's report: *a
narrowing gate's expected gain is unknown until its survival rate is measured on every
workload it is quoted against* — one workload is not evidence for the others, and the
measured spread here was 0.0 %–100 %.

**Spec coverage vs T9b §6.** L2 → T12; L1a → T13; L1b → T14; L1c → T15; L1d → T16
(profile-gated, A-6); L3 → T17; **L4 (allocation) is deliberately NOT a task** — T9b
measured it as a clock null (−16.6 % allocation, 0 % time) and §4 says not to spend a
round on it without a live arm, so it is an observation inside T17's capture
(`gcSwingKb` 31,982 facet vs 44 vide); **L5 (`ctx.offers`) is T13 step 5, conditional on
the character budget**, per its rank-8 placement. Task 11 is dispositioned with its
measured number. Nothing in §6 is unaccounted for. **Every MUST-FIX and SHOULD-FIX in
review round 1 is dispositioned in its amendment log — 47 findings, 45 FIXED, 1 REFUTED
with a citation (T14 NOTE 14 → ruling A-13, itself now partially superseded by A-15).
Every round-2 finding is dispositioned in §Amendment log — round 2: 5 MUST-FIX (3
BLOCKING) and 4 citation corrections FIXED at the source, 7 SHOULD-FIX FIXED, 5 NOTEs
noted, and the two measurements ruling L-1 demanded are in the log with their numbers,
their instrument and their worktree SHA.**

**Placeholder scan.** No step says "similar to Task N", "as above" or "TBD". Every
mechanism block carries a `<!-- verified: … -->` line naming the `sed -n` ranges its
fields were read from, and every field named in a code block appears in one of those
ranges. ▲ **The ranges on the five blocks round 3 touched were re-read at `92d3e7e4`**
(T13's carrier and mechanism, T14's, T15's, T16's) and now also cover `src/mount.luau` and
`src/layout/shrink.luau`, which rulings A-14 and A-15 depend on; `git diff e26c1daf
92d3e7e4` touches only `render_stats.luau`, `z_order.luau`, `zorder_bounded.spec.luau` and
this file, so every other range resolves identically at both SHAs. Four things are left to the implementer and are LABELLED: the exact
`fieldsRead` sets in T14 step 0 ("read off the run"), every "currently N" pin ("read off
the run", never quoted), T16's gate outcome (it may book), and T17's whole shape (A-7).

**Type consistency.** ▲ T13's payload is now **nine** names (`mIds` added, ruling A-14) and
T14's **fifteen** (`pN`, `pDistribute`, `pIds`, `pHug`, `pShrink`, `pPrio` added; rulings
A-14, A-15), each still with exactly one writer. `cmemo` is one optional table on the store entry (`layout_node.luau`
`:1519-1521`) and one optional field on the solver `Node`, both untyped-`any` records like
every other field of those two tables; `kids` and `childArray` sit beside it. T13's seven
payload names (`mStamp: string?`, `mScope: string?`, `mOffW`/`mOffH: number?`, and four
`{ [number]: number }` arrays) and T14's ten (`pInnerX/Y/W/H`, `pGap: number?`,
`pAlign: any`, `pMain`/`pCross: { [number]: number }`, `pCAlign`/`pCLine: { [number]: any }`,
`pRect: { [number]: any }`) have exactly one writer each (ruling A-9). `ctx.childVisits`,
`ctx.arrangeEntries`, `ctx.memoAudit`, `ctx.replayAudit` are declared in
`solve_ctx.luau`'s `Ctx` and initialised in `new()`. `store.childVisits: number` is
declared in `Store` and reset in `build`. The three new `last*` fields are added to
`render_stats.new()`'s record and to `tests/render_stats_seam.spec.luau:104-119`'s sample;
**`publish`'s four-argument signature is unchanged in this wave**, so `:126`/`:135` and the
`:163` call-site scan are untouched. `fake_target.Opts` gains one optional boolean beside
`trackThemeRoots`. ▲ **`CommitCtx` is UNCHANGED**; `commit_walks.harvest` gains two
optional trailing parameters (`walkedIds`, `translatedList`), so the seam spec's three
bidirectional `CommitCtx` pins and the two positional `harvest` call sites in
`commit_dirt_classes.spec` / `commit_translate.spec` all stay green untouched.

**Ordering.** T12 first (A-2); its `zorder_bounded.spec` prerequisite is CLEARED. T13 before T14 and T15 — it installs the `cmemo` carrier both depend on. T14
step 0 is its own commit before T14's behaviour (T7-3). T15 after T14 so its `attr`
baseline is stable. T16 gated on what T13–T15 leave. T17 is independent and could run in
parallel with a second agent; it is last because its deliverable may be a booking and the
closing report needs the four numbers above it.

**The one thing this plan cannot promise.** T13–T16 together approach the measured floor
**headless**. **Live, they clear 0.5 ms only if T17 finds the 1.5 ms.** Task 10's report
must say that in those words if T17 books instead of fixing. ▲ **And a second thing, added
in round 3: `battle_hud L updateItem-hp` — the class this whole addendum's Goal line is
written around — is served by T13 (96.8 % of its measure calls) and NOT by T14 (0
replays), so its predicted landing is ~0.90 ms after T13 and ~0.90 ms after T14.** The
0.5 ms target on that class therefore rests on T15, T16 and T17, not on the two largest
levers. Say that in §C12 and in the closing report.
