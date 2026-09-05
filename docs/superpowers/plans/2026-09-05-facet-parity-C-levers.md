# Facet Parity — Plan C ADDENDUM: the lever wave (T12–T17) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

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
| T13 → T14 → T15 | **`store.byNode[node].cmemo`** (ruling A-8) | T13 creates the carrier and the validity gate; T14 adds `p*` fields to the SAME table; T15 adds `childArray` to it | **CLEAN, and mandatory in this order.** One carrier, one gate, three payloads. T14 and T15 must not invent a second home. |
| T13 ↔ T14 | `cmemo.mMain` (measure offer) vs `cmemo.pMain` (arrange offer) | T13 writes `mMain` at `(innerMaxW, innerMaxH)`; T14 writes `pMain` at `(innerW, innerH)` | **CLEAN — separated by ruling A-9.** T14 does NOT read or write T13's arrays. The two offers are different questions (`solver.luau:1380` vs `stack.luau:144`). |
| T13 ↔ T14 ↔ T13-step-4 | `src/layout/solver.luau` characters | 190,112 now; STOP 197,500 → **7,388 usable** | **SPLIT (ruling A-10):** T13 ≤ +3,200, T14 ≤ +1,600, T15 ≤ +0 (it edits `layout_node.luau`), T16 ≤ +400, reserve 2,188. T13 step 4 (L5) spends from T13's own 3,200 or is dropped. Seam-first if T13 alone would exceed 3,200. |
| T13, T14, T15 → `src/layout/solve_ctx.luau` | `Ctx` type + `new()` initialiser | each adds one counter field (`childVisits`, `arrangeEntries`) | **NOT CLEAN unless listed.** `Ctx` is declared in `solve_ctx.luau` (`:79,:89,:131,:178,:194,:248,:249,:252,:269,:274`), NOT in `solver.luau`; `new()` is `:311-377`. **Both files are in each task's Files list now.** `tests/solve_ctx_seam.spec.luau` pins the field-set size — each task moves it. |
| T13, T14, T15 → `src/render/render_stats.luau` + **`tests/render_stats_seam.spec.luau`** | one new `last*` field each | the seam spec pins the export set (`:89`), the `new()` field sample (`:104-119`), the **4-arg `publish` call** (`:126`, `:135`) and "one `new`, one `publish`" in the renderer (`:163`) | **NOT CLEAN — three commits, one spec.** Each task has an explicit step for it. The `publish` SIGNATURE does not change in this wave (all three read from `work` / `nodeStore`), so `:126`'s call site is untouched; only the field sample at `:104-119` grows. |
| T15 ↔ T16 | `src/render/renderer.luau` characters | T15 needs `stats.lastBuildChildVisits = nodeStore.childVisits` beside `:2024`; T16 needs two tables into the commit ctx at `:1536` | **NOT CLEAN — re-split (ruling A-10):** wave cap raised from ≤ +200 to **≤ +400 total**: T15 ≤ +120, T16 ≤ +280. `renderer.luau` is 195,709, STOP 197,500. |
| T16 → `src/layout/solver.luau` | exporting `work.walkedIds` | `ctx.walkedIds` exists (`solve_ctx.luau:269`, written `solver.luau:2509`, read `:3506`) but is **NOT** on the `work` literal (`solver.luau:3515-3538`) | **NOT CLEAN — now listed.** One line in the `work` literal, budgeted from T16's ≤ +400 solver allowance. |
| T16 → `src/render/commit_walks.luau` `CommitCtx` | two new fields | `CommitCtx` is a 26-field record (`:176-225`) destructured by `commit_walks.new` (`:227`) and pinned **bidirectionally** by `tests/commit_walks_seam.spec.luau` against the renderer's call and the module's reads | **NOT CLEAN — three test edits mandatory and now listed:** `tests/commit_walks_seam.spec.luau`, `tests/commit_dirt_classes.spec.luau:955`, `tests/commit_translate.spec.luau:317` (the two hand-built ctxs). |
| T14 → T16 | `ctx.walkedIds` population | T14's replay `return`s out of `stack.arrange` without entering the placement loop, so a replayed container never `place`s its clean children, so they are never marked walked — which is the same set the solve did not touch | **CLEAN, and now stated in T16's owed list.** Also: `walkedIds` is written only under `if reuse ~= nil` (`solver.luau:2508`), and the commit prune is off on a non-reuse solve (`commit_walks.luau:814` `pruning = enabled and dirty ~= nil and stampSame`) — T16 carries that dependency explicitly instead of inheriting it. |
| T12 → T13–T16 | `attr` baselines | T12 changes the harness | **CLEAN as ordered (A-2)**, but every "before (post-T12)" number in T13–T16 is a **prediction**; each task re-reads its own before-column at its parent SHA (arm A). |
| T12 ↔ T13–T16 | **`tests/lib/deep_stack_scene.luau:229`, `tests/lib/nameplates_scene.luau:289`** | T12 gates `ops` per `fake_target.new()` call; these two helpers build the fixtures T13–T16 pin counters on | **NOT CLEAN — resolved by ruling A-11:** `ops` stays **OFF** in both helpers. Arming it there would re-poison the exact rows T12 exists to clean. Specs that need `ops` on those fixtures pass a per-call opt. |
| T12 ↔ the other agent | `tests/zorder_bounded.spec.luau`, `src/render/render_stats.luau` | T12 must arm `ops` in `zorder_bounded.spec:140,146`; T13/T14/T15 all edit `render_stats.luau` | **CLEARED 2026-09-05 — those three files landed as `aade8fac` and the tree is clean.** T12 no longer waits. Still check `git status --short` before starting and record it: the rule is standing, only this instance is closed. `zorder_bounded.spec`'s `ops` call sites may have moved off `:140,:146` in that commit — re-grep. |

---

## Global Constraints (inherited from the parent plan; deltas marked ▲)

- Facet repo `/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet`, branch **`facet-parity`**. Commits via `python3 tools/commit_isolated.py -m <msgfile> <path[:marker]>` (`--dry-run` first); **never amend; nothing merged or pushed**.
- Gates on EVERY Facet commit, FOREGROUND, one lune process at a time: `tools/test.sh` (full); `tools/verify.sh affected --jobs 1` BEFORE committing; `python3 tools/check_source_size.py`; `stylua --check src tests tools bench examples`. After any file EXTRACTION also run `python3 tools/check_brand_drift.py` by hand.
- **RascalRally lockstep on every Facet `src/` change:** `cd games/RascalRally/code && ./run-tests.sh 2>&1 | tee <transcript>` green at or above the recorded base (T9 closed at **8,452/0** Facet, **3,591/0** RR), plus the rider spec the task names. ▲ **Every task in this wave names its RR rider, T17 included.**
- ▲ **Source cap, re-split (ruling A-10).** `solver.luau` **190,112**, STOP 197,500 → **7,388 usable**, split T13 ≤ +3,200 · T14 ≤ +1,600 · T16 ≤ +400 · reserve 2,188. `renderer.luau` **195,709** → wave allowance **≤ +400 total**, split T15 ≤ +120 · T16 ≤ +280. `solve_ctx.luau`, `stack.luau` (21,399), `layout_node.luau` (96,496), `commit_walks.luau` (87,667) have no cap constraint. A task that would exceed its split STOPS and takes its named seam first, in its own commit.
- **No public API or behaviour change.** ▲ **No public counter may move except the ones each task names in its Interfaces block**, and a task that moves one re-records every pin on it — Facet AND RascalRally — in the SAME commit.
- **Counters, never wall-time.** Every demonstrator pins a counter AND `solves=N`; `scene.new()` → ONE discarded warm-up tick → the measured tick; pin idiom `` expect(`name={actual}`).toBe(`name={expected}`) ``. ▲ **Every acceptance number is an EQUALITY read off the run — never an inequality** (review cross-cutting: an inequality cannot be written in the mandated idiom). ▲ **Each task pins TWO numbers: (a) an EXISTING counter that moves, as equality at base, and (b) its new counter as equality after the counter-only step.** A "red" that is only a nil-index is not a red.
- ▲ **The AUDIT arm replaces "forced on" (ruling A-12).** T13 and T14 each ship a solve-opt (`containerMemoAudit`, `stackReplayAudit`, both default false, both test-only) that makes the fast path compute its answer **and** the slow one and assert equality inside the solve. The assessment demanded an arm that exercises the arithmetic on every container; forcing the *narrowing* gates off would produce legitimately wrong output, so the arm self-checks instead. Every 9-view oracle in those tasks runs with the audit arm on.
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
| **A-13** | **NEW, and a DISAGREEMENT with the review's T14 NOTE 14 (and with revision 1's own text). `node.distribute` is NOT a refusal term in the amended T14.** | NOTE 14 endorsed refusing `distribute` "because `lead`/`step` make δ non-prefix". True of a prefix REBASE — which A-4's amendment deleted. The amended replay fires only when **no** child's placement inputs changed, so `remaining` (`stack.luau:296`) is unchanged, so `distributionOf(mode, remaining, childCount)` (`stack.luau:343`) returns the same `lead`/`step`, so `cursor` (`stack.luau:349`) starts and advances identically. A `distribute` stack whose contents did not move has not moved. Refusing it would cost the lever every distributed row list for no correctness gain. The gate that replaces it is the one that makes the argument true: **every dirty child's main AND cross contributions, `align` and `lineAlign` unchanged, plus `node.gap`, `node.align` and the inner box unchanged.** |

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
		silently widen it. `parentPathOf` cuts at the LAST separator, the same cut
		`hostFor` walks.

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

  **The site sets, verified and NOT equal in size (review MUST-FIX 1 — revision 1's pin
  was false by construction):** `nodes[…] = <value>` at **`:482`** (`create`) and
  **`:1029`** (`adopt`); `nodes[…] = nil` at **`:873`** (`remove`), **`:936`**
  (`discardParked`'s neighbour) and **`:1124`** (`destroyRoot`). So `indexNode` is called
  at `:482` **only** — `adopt`'s new key is indexed too, and its **old key is left in
  place deliberately** to match today's walk — and `unindexNode` at `:873`, `:936`,
  `:1124`. **The pin is therefore "2 index sites for 2 `nodes[x] = v` writes minus the
  adopt exception, 3 unindex sites for 3 deletes", written as an explicit enumerated list
  in the spec, not a count equality.**

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
| 1 | `ctx.offers[child.wKey]` / `[child.hKey]` | `solver.luau:1758-1759`; consumed by the entry literal at `solver.luau:2429-2437` | **SERVED** — written from the offer in hand, and the serve writes the **raw** `maxH` there, so the raw `innerMaxH` is the right value. **This is T11's finding and it is not optional**: a `nil` offer disarms both anchor arms for the life of the surface (T7 finding 2) |
| 2 | `ctx.textStates` / `ctx.compact` / `ctx.textFacts` | `solver.luau:1766-1770`; publishers are exactly `kind == "text" or kind == "composition"` (`record`, `solver.luau:1596`) | **GATED, not served** (amended). A direct child of either kind is never skipped. Revision 1 replayed them from the child's `mA*`/`mB*` slots using a **two-term** A/B test where `record` requires three (`mAOfferW`, `mAOfferH`, `mAScope` — review MUST-FIX 6); refusing those two kinds outright removes the slot read entirely and costs a handful of measures per container |
| 3 | `ctx.fitCuts += <child's contribution>` | `solver.luau:1771`, and `record`'s `cuts = ctx.fitCuts - cutsAtEntry` | **SERVED from the memo's own array** — `cmemo.mCuts[idx]` is recorded as the `ctx.fitCuts` delta across the child's `measure` call in PASS 1, so nothing reads a slot |
| 4 | `shrinkBasis[idx]` | `solver.luau:1381-1385`, consumed `:1425-1426` | **GATED** (amended; review MUST-FIX 4/5). A container **any** of whose children declares `shrinkWeight > 0` never memoises. PASS 1.5 then cannot run on a memoised container, so `mainSum -= absorbed` (`:1434`) never rebases the numbers the memo holds |
| 5 | the fill pass's re-measure | `solver.luau:1471-1485` | **NOT SKIPPED, ever** (amended; review MUST-FIX 3). `crossOf` and `marginMain` are allocated FRESH each call exactly as HEAD does, and a fill child's `crossOf[idx]` is written only by the fill pass — so the fill pass re-measures every fill child on every call, as today. `remaining` depends on `mainSum`, so it must |
| 6 | `ctx.compositions` / `ctx.hasScroll` / `armContainer` / `ctx.boundary` / the adopted-slate diagnostics | C2's table rows 4–8 | **GATED** by C2's own gate asked of the child: `subtreeHasScroll`, `subtreeHasComposition`, `containerRelativeInside`, plus `ctx.analyze` and `ctx.measureQuiet` on the container |
| 7 | `ctx.mdepth` / `ctx.deepNesting` | `measureUncached` | **BALANCED BY CONSTRUCTION, stated** — the child is not entered, so nothing is pushed and nothing owed; `deepNesting` is a latch a later slow path re-arms |
| 8 | `ctx.measureCalls` / `ctx.measureServed` | `solver.luau:1721`, `:1757` | **MOVES BY DESIGN** — both fall, and both pins are re-recorded in this commit, Facet and RR |

**Files:**
- **Step 0 (conditional): the seam.** If the change measures over **+3,200 after stylua** (ruling A-10), STOP and take the seam first in its own commit: `src/layout/stack_measure.luau` carrying `contentSize`'s vstack/hstack branch (`solver.luau:1349-1496`, ~7,500 chars) as `stackMeasure.contentSize(deps, ctx, node, isH, children, n, innerMaxW, innerMaxH, gap, pt, pr, pb, pl)`. **Its real read set, re-read (review SHOULD-FIX 17 — revision 1 wrongly listed `mainDimOf`):** `deps` = `measure`, `dim`, `sides`, `shrinkLib.stack` + `SHRINK_DEPS`; `ctx` = `fitProbe` (`:1422`), plus whatever `fieldsRead` finds on the run. Give it `tests/stack_measure_seam.spec.luau` modelled on `tests/stack_seam.spec.luau` (closed `ctx` set + the read-vs-write half). Run `check_brand_drift.py` by hand after the extraction.
- Modify: `src/render/layout_node.luau` — **the `cmemo` carrier (ruling A-8)**: the `Store` entry literal at `:1519-1521` gains `cmemo` and `kids`; the rebuild arm carries it forward. **This is T13's file even though T15 is "the layout_node task"** — the carrier is a prerequisite for T13 and T14, so it lands here.
- Modify: `src/layout/solver.luau` — `contentSize`'s vstack/hstack branch (`:1349-1496`).
- Modify: **`src/layout/solve_ctx.luau`** (review MUST-FIX 11) — `Ctx` gains `childVisits: number` and `memoAudit: boolean`, both initialised in `new()` (`:311-377`). `tests/solve_ctx_seam.spec.luau`'s field-set count moves.
- Modify: `src/layout/solver.luau`'s `work` literal (`:3515-3538`) — `childVisits = ctx.childVisits`.
- Modify: `src/render/render_stats.luau` — `new()` gains `lastChildVisits = 0`; `publish` (`:191`) gains `stats.lastChildVisits = work.childVisits or 0`. **`publish`'s 4-arg signature does not change.**
- Modify: **`tests/render_stats_seam.spec.luau`** (review T15 MUST-FIX 3) — the `new()` field sample at `:104-119` gains `lastChildVisits`. The export-set pin (`:89`), the `publish` call (`:126`, `:135`) and the "one `new`, one `publish`" scan (`:163`) are untouched.
- Create: `tests/container_memo.spec.luau`; register in `tests/run.luau`. Evaluate `tiers.SLOW` if it runs the 9-view oracle over more than 3 fixtures.
- Modify: `tests/measure_serve.spec.luau`, `tests/measure_split.spec.luau`, `tests/nameplates_baseline.spec.luau`, `tests/translate_arm.spec.luau`, `tests/anchor_arrange.spec.luau` — every `lastMeasureCalls`/`lastMeasureServed`/caster-tick pin, re-recorded from a run.
- **RR rider (same commit):** `tests/facet_measure_fanout_contract.spec.luau` — the fanout literals and the two accounting identities. Also run `tests/facet_measure_split.spec.luau`.

**Interfaces:**
- Consumes: `ctx.reuse.measureContains` (measure-half dirty closure, ancestor-closed, keyed by `node.id`, and `solver.Node.id = node.path` — `layout_node.luau:608`); `ctx.scopeKey` (`solve_ctx.luau:131`); `ctx.measureStamp` (**`string?`** — `solve_ctx.luau:194`; review MUST-FIX 9); `ctx.analyze` (`:252`); `ctx.measureQuiet` (`:274`); `ctx.fitProbe` (`:79`); `ctx.fitCuts` (`:89`); child `subtreeHasScroll` / `subtreeHasComposition` / `containerRelativeInside` / `kind` / `shrinkWeight` / `wKey` / `hKey`.
- Produces — **the carrier** (ruling A-8), on the store entry `store.byNode[node]`:
  - `cmemo: ContainerMemo?` — one table, carried across rebuilds
  - `kids: any` — the mount `node.children` table this entry was built from, compared by IDENTITY
- Produces — **T13's payload inside `cmemo`** (exactly these seven names; T13 is their only writer):
  - `mStamp: string?`, `mScope: string?`, `mOffW: number?`, `mOffH: number?` — the key (ruling A-3)
  - `mMain: { [number]: number }`, `mCross: { [number]: number }`, `mMargin: { [number]: number }`, `mCuts: { [number]: number }` — per-child, indexed by child index
- Produces: `layoutNode.cmemo` (the pointer), `ctx.childVisits`, `work.childVisits`, `stats.lastChildVisits`.
- Produces: solve opt `containerMemoAudit: boolean?` (default false, test-only) → `ctx.memoAudit`.
- **Moves (re-recorded in this commit): `lastMeasureCalls`, `lastMeasureServed`.** **Must NOT move: `lastMeasured`, `lastArranged`, `lastRectInserts`, `lastSkipped`, `lastSolveSkipped` (derived by subtraction at `solver.luau:3469`, so automatic), `lastLayoutNodes`, `lastAnchorSkipped`, `rectWrites`, `propWrites`, `engineWrites`, `solves`, `partialSolves`.**

- [ ] **Step 1: the owed list, then the two pins.** Eight-row table into the spec header and the ledger. Then `tests/container_memo.spec.luau` on `tests/lib/deep_stack_scene.luau` (1,000 rows, `ops` NOT armed — ruling A-11), warm one tick, `scene.text(500, "x")`:
  - **(a) an EXISTING counter as an equality red, read off the run:** `lastMeasureCalls` at HEAD (`≈2,005` on this fixture per T6's own record — **read it, do not quote it**), and the target value after. `lastMeasured=1` and `solves=1` in the same block, unchanged.
  - **(b) the new counter as an equality after step 2:** `lastChildVisits`.
  - `it("a viewport change memoises nothing and serves nothing")` — `env:set` drive, full walk, `solves=1`, no `reuse`.
  - `it("a width write on the container refills the memo at the new offer")` — the key moved, not the dirt.
  - **One case per GATED row (4, 5, 6):** a container with a `shrinkWeight > 0` child (row 4); a container with a `fill` child, pinning that the fill child is re-measured on **every** tick (row 5); a container with a `text` direct child and one with a `composition` direct child (row 2), with `controller.compositionAt` still answering; a `ScrollView` child, a `containerRelative` child, an `analyze` solve and a non-quiet solve (row 6). Each pins `lastChildVisits` at the FULL walk.
  - `it("the offer channel survives a skipped child")` — the T11/T7 case: a child arrange-dirty but measure-clean whose entry literal IS rebuilt must carry non-nil `offerW`/`offerH`; pin `lastAnchorSkipped` on the NEXT frame at its HEAD value.

- [ ] **Step 2: the counter, alone (arm C).** Add `ctx.childVisits` (+ its `solve_ctx` field and initialiser), the `work` field, the `render_stats` publish and the seam-spec sample — **no mechanism**. Measure. T8 measured a bare `scanCount += 1` at +0.7–2.6 % because `skip` ran 9,040×/step; `childVisits += 1` runs ~2,200×/step here. If arm C is distinguishable from arm A, move the increment to a per-LOOP `+= n` and write the spec's pin against that. Record the arm-C number either way. **Arm C's increment must sit on the same line arm B's does.**

- [ ] **Step 3: the carrier (ruling A-8).** In `layout_node.luau`, the rebuild path:

<!-- verified: sed -n '377,398p;1516,1523p;1655,1671p;1680,1714p' src/render/layout_node.luau -->
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

<!-- verified: sed -n '1349,1396p;1418,1440p;1466,1496p' src/layout/solver.luau -->
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
	local mMain, mCross, mMargin, mCuts
	if memoable then
		if hit then
			mMain, mCross, mMargin, mCuts = cmemo.mMain, cmemo.mCross, cmemo.mMargin, cmemo.mCuts
		else
			mMain, mCross, mMargin, mCuts = {}, {}, {}, {}
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
			if memoable then
				if child.kind == "text" or child.kind == "composition" then
					memoable = false -- owed row 2: this branch cannot replay the verdicts
				elseif
					child.subtreeHasScroll ~= true
					and child.subtreeHasComposition ~= true
					and child.containerRelativeInside ~= true
				then
					mMain[idx], mCross[idx] = mainOf, crossOfIdx
					mMargin[idx], mCuts[idx] = marginMain[idx], ctx.fitCuts - cutsBefore
				end
			end
			--[[ THE AUDIT ARM (ruling A-12). When on, the skip above never fires and the
				memo's answer is compared against the real one instead — so the standing
				9-view fuzz exercises this arithmetic on EVERY container it touches
				without any gate being weakened. Off in production; there is no third
				behaviour. ]]
			if ctx.memoAudit and hit and mMain[idx] ~= nil then
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
		cmemo.mMain, cmemo.mCross, cmemo.mMargin, cmemo.mCuts = mMain, mCross, mMargin, mCuts
	elseif not memoable and cmemo ~= nil then
		-- a container that once memoised and has since gained a shrink child or a text
		-- child must not keep a stale key
		cmemo.mStamp = nil
	end
```

  **Residual, stated rather than hidden:** the PASS 1 loop, the fill pass's `continue`
  scan and the `crossMax` loop are all still O(children) — three cheap passes over an
  array. On `battle_hud L` that is ~1,000 × ~0.03 µs ≈ **0.03 ms**, which is the floor
  this task reaches and is 3 % of the 1.038 ms it removes. It is booked, not attacked.

- [ ] **Step 5: L5 (`ctx.offers`) — fold in ONLY if the budget allows.** T9b §6-L5: `ctx.offers` grows to 2 × `measureServed` (~4,500 entries/tick) with a `child.id .. "|w"` concat on any node without a cached `wKey`. Its measured time gain is **~zero** (T9b arm 4: −16.6 % allocation, 0 % clock). **If `check_source_size` shows T13 above +2,700 after stylua, SKIP and re-book.** If it goes in: move the pair onto the node beside the C2 slots (`node.oW`, `node.oH`, stamped with `mStamp`) and change the single in-solve reader, the entry literal at `solver.luau:2429-2437`. T7's second NULL mutation established there is no other reader.
- [ ] **Step 6: green + the differential oracle arm.** `container_memo.spec` green. Then, on the fake adapter, all 9 `device_views.VIEWS` incl. 320x640, three drives (text write, width write, viewport change) on **four** fixtures — `deep_stack_scene`, a nested-stack fixture, one with a `fill` child, one with a `shrinkWeight` child — `scene.snapshot()` byte-equal to arm `c`, non-vacuity guard, `b`/`d` driven every step. **Every one of these runs TWICE: once normally and once with `containerMemoAudit = true`** (ruling A-12). Public reader pin: `controller.compositionAt` on the composition fixture. Then the standing suites that compare against arm `c`: `host_space_oracle`, `translate_arm`, `measure_split`, `measure_reuse`, `rect_cow`, `node_reuse`, `anchor_skip`.
- [ ] **Step 7: the mutation (Step-7 discipline).** Each must BITE, each recorded: (1) drop the `ctx.offers` writes in the skip arm → reddens the T7-finding-2 case. (2) drop `child.kind ~= "text"` → reddens the text-child verdict case. (3) drop the `shrinkWeight` → `memoable = false` line → reddens the shrink case. (4) drop `cmemo.mStamp = nil` on the un-memoable arm → reddens the shrink-child-arrives-later case. (5) key the memo on `innerMaxW` alone → reddens the height-offer case. (6) carry `cmemo` forward without the `prior.kids == node.children` term → reddens an insert-a-row case. (7) remove `child.containerRelativeInside ~= true` → **if it does NOT redden, record the null exactly as T6/T7 recorded theirs and KEEP the term with the null stated at both sites** (C2's own term is a known null).
- [ ] **Step 8: gates, RR, measurement, commit.** `tools/test.sh` full; `tools/verify.sh affected --jobs 1`; `stylua --check`; `check_source_size` **and record `solver.luau`'s new size in `tools/lune/verify/data/source-cap-ledger.md`**; **RR: `./run-tests.sh` with `facet_measure_fanout_contract` re-recorded IN THIS COMMIT**, plus `facet_measure_split`. Measurement, three arms (A = worktree at T12's SHA, B = HEAD, C = step 2), ABBA:

  | class | before (read at arm A) | **expected after** |
  |---|---:|---:|
  | `battle_hud L updateItem-hp` | ~1.82 | **~0.82** (−1.00; 0.03 of the 1.038 stays as the O(n) loops) |
  | `battle_hud L setState` | ~1.93 | ~0.92 |
  | `war_room_inventory L setState` | ~2.58 | **~1.09** |
  | `killfeed_nameplates L updateItem-hp` | ~0.52 | **~0.30** |
  | `war_room_inventory L reorder` | ~19 (post-T12) | ~17 |
  | `nameplates L updateItem-hp` | 0.006 | **0.006 (CONTROL — anchored, no stack loop)** |

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

**Measured evidence, and the correction it carries.** T9b's crude ceiling arm — replay
when every dirty child measures to the size it had — read ABBA `battle_hud setState`
**1.822 → 1.535 (−16 %)** and `removeItem-damage` **2.505 → 1.403 (−44 %)**. It did NOT
fire on `updateItem-hp`, because it compared a child's **measured** extent to its
**placed** rect, which differ for a `fill` child (`stack.luau:356-358`: `mainSize` comes
from `fillPx[idx]`, not from `desired`). **T14 compares measured-to-measured, against its
OWN placement-time array (ruling A-9), never T13's.**

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
- **Step 0 (its own commit, ruling T7-3): widen `tests/stack_seam.spec.luau:163`'s read-set.** At HEAD the pins are `ctx = { "diagnostics", "hiddenDepth" }`, `node = { "align", "children", "distribute", "id", "kind" }`, `child = { "align", "lineAlign", "margin", "shrinkWeight" }`. The replay adds `ctx.reuse` and `ctx.noSkipDepth` (both declared `Ctx` fields — `solve_ctx.luau:269` is `walkedIds`, `:248` is `noSkipDepth`, so **the `(ctx :: any)` casts revision 1 used are unnecessary**, review SHOULD-FIX 9) and `node.gap`, `node.cmemo`. **Read the exact sets off the run**; keep the read-vs-write half asserting the module assigns no field of `ctx`/`node`/`child`/`deps`. Commit the widening ALONE with its reasoning.
- Modify: `src/layout/stack.luau` — `stack.arrange`'s prologue (the replay) and the placement loop's memo fill.
- Modify: **`src/layout/solve_ctx.luau`** — `Ctx` gains `arrangeEntries: number` and `replayAudit: boolean`, both initialised in `new()`. `tests/solve_ctx_seam.spec.luau`'s count moves.
- Modify: `src/layout/solver.luau` — `ctx.arrangeEntries += 1` at the top of `arrangeBody`; `work.arrangeEntries`. **`arrangeBody` is NOT otherwise restructured** — the replay is entirely inside `stack.arrange`. Budget ≤ +1,600 (ruling A-10).
- Modify: `src/render/render_stats.luau` + **`tests/render_stats_seam.spec.luau`** (the `new()` field sample) — `lastArrangeEntries`.
- Create: `tests/stack_replay.spec.luau`; register.
- **RR rider (same commit): `tests/facet_anchor_arrange.spec.luau` must be UNCHANGED and green** — it pins `lastArranged`, which must not move. If it moves, that is a stop. Also run `tests/facet_collection_extent_contract.spec.luau`.

**Interfaces:**
- Consumes: `reuse.dirtyContains` (the FULL closure, not the measure half); `node.cmemo` (ruling A-8, created by T13); `out[child.id].rect`.
- Produces — **T14's payload inside `cmemo`** (T14 is their only writer, ruling A-9):
  - `pInnerX/pInnerY/pInnerW/pInnerH: number?`, `pGap: number?`, `pAlign: any` (the container's own `node.align`) — the key
  - `pMain: { [number]: number }`, `pCross: { [number]: number }` — per-child main/cross contributions at the ARRANGE offer
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
  - `it("a viewport change replays nothing")`.

- [ ] **Step 2: the counter, alone (arm C).** `ctx.arrangeEntries += 1` at the top of `arrangeBody` (+ `solve_ctx` field, `work`, `render_stats`, seam sample), mechanism off. It runs ~1,100×/step — the same order as T8's `scanCount`, which cost +0.7–2.6 %. Same line as arm B's.

- [ ] **Step 3: the mechanism.** At the top of `stack.arrange`, immediately after `local children = node.children or {}`:

<!-- verified: sed -n '98,135p;136,160p;340,362p;384,412p;424,442p' src/layout/stack.luau; sed -n '248,250p;269,270p' src/layout/solve_ctx.luau -->
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
		`distribute` stack is therefore NOT refused (ruling A-13): `distributionOf`
		reads `remaining`, which did not move.

		MEASURED-TO-MEASURED, AGAINST THIS FILE'S OWN ARRAY. `cmemo.pMain` is recorded
		at the ARRANGE offer `(innerW, innerH)`; T13's `mMain` is recorded at the
		MEASURE offer `(innerMaxW, innerMaxH)` and for a `hug` or `fill` container those
		are different questions. Comparing across them is the same class of error as
		comparing a measurement to a placed rect, which is what made the first prototype
		of this arm fire on `setState` and `removeItem` and never on `updateItem-hp`.

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
		and cmemo.pInnerX == innerX
		and cmemo.pInnerY == innerY
		and cmemo.pInnerW == innerW
		and cmemo.pInnerH == innerH
		and cmemo.pGap == gap
		and cmemo.pAlign == node.align
	then
		local pMain, pCross = cmemo.pMain, cmemo.pCross
		local pRect, pCAlign, pCLine = cmemo.pRect, cmemo.pCAlign, cmemo.pCLine
		local ok, hot = true, nil :: { number }?
		for idx, child in children do
			if dirty[child.id] ~= true then
				continue
			end
			local before = pMain[idx]
			if before == nil or pRect[idx] == nil or child.align ~= pCAlign[idx] or child.lineAlign ~= pCLine[idx] then
				ok = false
				break
			end
			local mt, mr, mb, ml = deps.sides(child.margin)
			local w, h = deps.measure(ctx, child, innerW, innerH)
			local mainOf = if isH then w + ml + mr else h + mt + mb
			local crossOf = if isH then h + mt + mb else w + ml + mr
			if mainOf ~= before or crossOf ~= pCross[idx] then
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

  and at the end of the placement loop, beside `place(ctx, child, childRect, out)`:

```luau
		-- record what this loop decided, so the next arrange into the same box can
		-- replay it. `childRect` is the SAME TABLE that reaches `out` and gets frozen
		-- there, and `commit_walks.skip` prunes on entry identity — so this array holds
		-- references, never copies.
		if cmemo ~= nil then
			pRect[idx], pMain[idx], pCross[idx] = childRect, mainOf, crossOfIdx
			pCAlign[idx], pCLine[idx] = child.align, child.lineAlign
		end
```

  with the arrays created fresh at the top of the placement loop and the key written
  after it (`cmemo.pInnerX/Y/W/H`, `pGap`, `pAlign`, and the six arrays). `mainOf` and
  `crossOfIdx` are the two extents the loop already computes (`stack.luau:356-358`,
  `:387-389`) recorded as locals. **When `cmemo == nil` (a store-less or reuse-off
  build) nothing is written and nothing is read** — today's code exactly.

  **The audit arm (ruling A-12):** `ctx.replayAudit` disables the fast return and makes
  the full body assert that each child's freshly computed `childRect` equals `pRect[idx]`
  whenever the replay's own gate would have fired, so the standing fuzz exercises the
  comparison on every stack it touches without weakening a gate.

  **`node.pRect = nil` on early returns is DELETED (review SHOULD-FIX 8).** `stack.arrange`
  (`stack.luau:98-442`) has **no** early returns at HEAD — `hwrap`/`vwrap` and `scroll`
  are handled in `contentSize`/`arrangeBody`, not here. Revision 1's step and its
  mutation 5 pinned a branch that does not exist.

- [ ] **Step 4: green + the differential oracle arm.** `stack_replay.spec` green. The 9-view oracle exactly as T13 step 6 defines it, on **five** fixtures: `deep_stack_scene`, a nested-stack fixture, a `fill`-child fixture, a `distribute` fixture (ruling A-13's witness — a refusal that silently changed a rect is the worst outcome this task can have), and an aspect-child fixture. **Every run twice, once with `stackReplayAudit = true`.** Standing: `host_space_oracle`, `translate_arm`, `anchor_skip`, `measure_split`, `rect_cow`, `node_reuse`, `container_memo`.
- [ ] **Step 5: the mutation (Step-7 discipline).** Each must BITE: (1) compare `mainOf` against `prev.w`/`prev.h` (measured-against-placed) → reddens the `fill` case. (2) drop the `crossOf ~= pCross[idx]` term → reddens a cross-only size change. (3) drop the `child.align ~= pCAlign[idx]` term → reddens the align case. (4) drop `cmemo.pGap == gap` → reddens the gap case. (5) drop the `noteContainment` replay → reddens the diagnostics case. (6) read `cmemo.mMain` instead of `pMain` (ruling A-9's violation) → reddens the `hug`-container fixture.
- [ ] **Step 6: gates, RR, measurement, commit.** Full gates as T13 step 8; `check_source_size` with `solver.luau` and `stack.luau` recorded. **RR `facet_anchor_arrange.spec` UNCHANGED and green.** Three arms, ABBA:

  | class | before (read at arm A) | **expected after** |
  |---|---:|---:|
  | `battle_hud L updateItem-hp` | ~0.82 | **~0.33** (the hp bar's row does not resize, so the replay fires) |
  | `battle_hud L setState` | ~0.92 | ~0.36 (T9b's arm read −16 % on the un-memoised base) |
  | `battle_hud L removeItem-damage` | ~2.0 | ~1.2 (T9b's arm read −44 %) |
  | `war_room_inventory L setState` | ~1.09 | ~0.40 |
  | `killfeed_nameplates L updateItem-hp` | ~0.30 | ~0.16 |
  | `nameplates L updateItem-hp` | 0.006 | 0.006 (CONTROL) |

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
- Modify: **`tests/render_stats_seam.spec.luau`** — the `new()` field sample (`:104-119`).
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
  - `it("a ForEach region whose own children changed rebuilds")` — owed row 4's case, with the `markDirtyIn` prefix argument named in the case's comment.
  - `it("a container re-parented across an axis rebuilds")` / `it("a container that enters a clipper rebuilds")` — owed row 5.
  - `it("the collect arm never reuses")` — driven through `controller.analyzeBoundaries` so `build`'s `collect` is true and `store.builtIds ~= nil` (owed row 3).

- [ ] **Step 2: the counter, alone (arm C).** `store.childVisits += 1` in the child loop (+ the `Store` field, `newStore`, the reset, the renderer line, `render_stats.new`, the seam sample), mechanism off. ~1,110×/step. Same line as arm B's.

- [ ] **Step 3: the mechanism.** Replacing `:1348-1382`:

<!-- verified: sed -n '377,398p;1348,1385p;1516,1523p;1618,1632p;1655,1671p;1680,1714p' src/render/layout_node.luau; sed -n '2020,2026p' src/render/renderer.luau -->
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

			THE GATE IS TABLE IDENTITY, NOT LENGTH — the same `prior` the container memo
			(ruling A-8) is carried on, so one validity question serves both. `mount`
			builds a NEW `node.children` whenever the child set changes and mutates it
			never, so identity is exactly "the shape under me is the shape I built for";
			a length compare would accept a swap and a per-element compare would cost the
			loop this replaces. `axis`/`clip` come with it: the children were built with
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
- Modify: `src/layout/solver.luau` — the `work` literal (`:3515-3538`) gains `walkedIds = ctx.walkedIds`. **Budget ≤ +400 (ruling A-10).**
- Modify: `src/render/commit_walks.luau` — `CommitCtx` (`:176-225`) gains `walked: any` and `walkedList: any`; `commit_walks.new` (`:227`) destructures both; `buildDescend`'s loop gains the filter; a `probeCount` counter published beside `scanCount`.
- Modify: `src/render/renderer.luau` — pass the two through at `:1536`. **Budget ≤ +280 chars (ruling A-10).** **Passing two tables and testing both inside `buildDescend` is chosen over building a union table in the renderer** (review MUST-FIX 3): a union loop plus this repo's comment density does not fit 280 chars, allocates per commit, and `commit_walks.luau` has 112 KB of headroom.
- Modify: **`tests/commit_walks_seam.spec.luau`** (the bidirectional `CommitCtx` pin), **`tests/commit_dirt_classes.spec.luau:955`** and **`tests/commit_translate.spec.luau:317`** (the two hand-built ctxs) — review MUST-FIX 1d; without all three the seam spec reddens.
- Modify: `src/render/render_stats.luau` + `tests/render_stats_seam.spec.luau` — `lastCommitProbes`.
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

<!-- verified: sed -n '318,330p;510,526p;576,584p;605,612p;626,660p;806,818p' src/render/commit_walks.luau; sed -n '2494,2496p;2506,2510p;3515,3538p' src/layout/solver.luau -->
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

				`walked` IS EMPTY ON A NON-REUSE SOLVE (`solver.luau:2508` guards the
				write with `if reuse ~= nil`). `pruning` is separately false there
				(`:814`), so the filter is unreachable — but it is gated on `walked ~= nil`
				explicitly rather than inheriting that, and a case pins it. ]]
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

  `walked` is built once per commit inside `harvest`, beside `nodeDirty = dirty`
  (`:810-811`), from the two things the solve publishes — **iterating
  `translatedPaths` as the ARRAY it is**:

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
- [ ] **Step 6: the mutation.** (1) drop the `not dirtyAll` term → reddens a dirty-child case. (2) use `nodeDirty` alone as the filter (T8's unsound index) → **must redden the `fill` case**; if it does not, the fixture is not a witness and step 2 is wrong. (3) replace the flag-set with a `continue` → **must redden a fork case** (the aliasing regression, owed row 3). (4) merge `translatedPaths` as a map → reddens a translate fixture. (5) drop the `walked ~= nil` guard → reddens the full-solve case.
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

**T15.** 1 FIXED (`store.builtIds ~= nil`, per `layout_node.luau:1686`/`:1694`; the
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

## Self-review (round 2)

**Spec coverage vs T9b §6.** L2 → T12; L1a → T13; L1b → T14; L1c → T15; L1d → T16
(profile-gated, A-6); L3 → T17; **L4 (allocation) is deliberately NOT a task** — T9b
measured it as a clock null (−16.6 % allocation, 0 % time) and §4 says not to spend a
round on it without a live arm, so it is an observation inside T17's capture
(`gcSwingKb` 31,982 facet vs 44 vide); **L5 (`ctx.offers`) is T13 step 5, conditional on
the character budget**, per its rank-8 placement. Task 11 is dispositioned with its
measured number. Nothing in §6 is unaccounted for. **Every MUST-FIX and SHOULD-FIX in the
review is dispositioned in the amendment log above — 47 findings, 45 FIXED, 1 REFUTED
with a citation (T14 NOTE 14 → ruling A-13), and every NOTE either cited in an owed list
or acknowledged.**

**Placeholder scan.** No step says "similar to Task N", "as above" or "TBD". Every
mechanism block carries a `<!-- verified: … -->` line naming the `sed -n` ranges its
fields were read from at `e26c1daf`, and every field named in a code block appears in one
of those ranges. Four things are left to the implementer and are LABELLED: the exact
`fieldsRead` sets in T14 step 0 ("read off the run"), every "currently N" pin ("read off
the run", never quoted), T16's gate outcome (it may book), and T17's whole shape (A-7).

**Type consistency.** `cmemo` is one optional table on the store entry (`layout_node.luau`
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
`trackThemeRoots`. `CommitCtx` gains two `any` fields and is re-pinned in three places.

**Ordering.** T12 first (A-2), and it waits on the other agent's `zorder_bounded.spec`
commit. T13 before T14 and T15 — it installs the `cmemo` carrier both depend on. T14
step 0 is its own commit before T14's behaviour (T7-3). T15 after T14 so its `attr`
baseline is stable. T16 gated on what T13–T15 leave. T17 is independent and could run in
parallel with a second agent; it is last because its deliverable may be a booking and the
closing report needs the four numbers above it.

**The one thing this plan cannot promise.** T13–T16 together approach the measured floor
**headless**. **Live, they clear 0.5 ms only if T17 finds the 1.5 ms.** Task 10's report
must say that in those words if T17 books instead of fixing.
