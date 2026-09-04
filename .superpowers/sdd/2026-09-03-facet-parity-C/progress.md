# SDD ledger — plan: docs/superpowers/plans/2026-09-03-facet-parity-C.md

Spec: docs/superpowers/specs/2026-09-03-facet-parity-design.md (binding authority).
Task plan: docs/plans/2026-09-03-facet-parity-plan.md. Rules + traps: docs/plans/2026-09-02-facet-wicked-fast-reference.md.
Base (Facet): a46f84c4 (main, Plan B merged). Branch: `facet-parity` (created 2026-09-03 before any edit).
FacetBench: main 1ead3b3. RascalRally: main 07d1a18.
Floors at base: Facet suite 8250/0, RR 3575/0 (Plan B close). Only ratchet up.
Operating rules: every commit — `tools/test.sh`, `tools/verify.sh affected --jobs 1` FOREGROUND (pre-commit), `python3 tools/check_source_size.py`, stylua; RR lockstep on every src change; no public API/behaviour change; never amend; nothing merged/pushed.

## Scouting (2026-09-03)
Five read-only scouts (S1 solver, S2 renderer, S3 boundary+adapters, S4 tests/oracle, S5 bench+RR) → scratchpad briefs/S*.md. Plan is written from those briefs + the spec.

## Plan written 2026-09-03 (1,072 lines, T0–T10) — rulings R-1..R-9 in the plan's own table

## Pre-flight conflict scan (before T0)

| Tasks | Produces → consumes | Found |
|---|---|---|
| T0 ↔ T3 | T0 adds `adapter.engineWrites()` + the fake's host `entry.rect`; T3 reads the mirror with `hostOx = 0` for a space host | T0's mirror subtracts `host.rect` for EVERY host; T3 changes that to "space host → 0". Sequential, same file, stated in T3's mechanism block. OK. |
| T1 → T3, T5 | T1 creates `rect_reads` with `hostSpaceOf`/`hostOriginOf`/`invalidateOrigins`/`clearHosts` (empty-behaviour); T3 fills `hostSpaceOf` + adds `spaceHosts`; T5 adds `hostHitCount`/`hostSinkCount`/`spaceHostHasPath`/`noteUnder` | T1's Interfaces block does NOT list `spaceHosts`/`noteUnder` — T3/T5 add them. **Ruling P-1:** T1 declares `spaceHosts` too (an empty set costs nothing) so T3's renderer diff stays bindings-only; T5 adds its three maps + `noteUnder` inside `rect_reads` (not capped). Cost if wrong: one extra field. |
| T1 ↔ renderer bind order | `presentationShift` comes from `channel` built at `:453`, `scrollHostOf` declared `:327`, old `rectOf` at `:324` | The bind line must sit AFTER `channel` exists; T1 step 3 says so (call-time forwarder allowed). OK. |
| T2 → T3 | T2 exports `translateArm.translatable/translateDescendants`; T3 edits the CALL in `arrange` (hostSpace root → empty run, no call) | T3 says "translate_arm.luau: no change". Consistent. |
| T2 → T5 | `placement.anchorPlace(innerX, innerY, innerW, innerH, w, h, wFill, hFill, anchor, offsetX, offsetY) -> (x, y, w, h, unknownAnchor)` | T5's lane calls it with `false, false` for the fills (gated) — signature matches. OK. |
| T3 ↔ T4 (RR) | T3 changes `fake_target` (RR requires it directly) and moves `facet_commit_translate.spec` pins | T3 step 10 says: commit T3 only together with T4 steps 1-3 if RR reddens. The lockstep window is stated. OK. |
| T3 → T5 | T3 stamps mount `node.hostSpace`, layout `Node.hostSpace`; T5's lane reads `spaceHosts[path]`, `layoutNodeOf(mount)`, `parentNodeOf[path]`, `lastResult.rects` | Names match the renderer's existing locals (`parentNodeOf` :1700, `layoutNodeOf` :1703, `lastResult` :1662). OK. |
| T5 ↔ `solvedListeners` | T5 extracts `notifySolved()` from `solveAndApply`'s tail | The block reads `notifyingSolved`, `feedbackMark`, `resolveForFeedback`, `solvingFromSettle`, `feedbackArmed` — all renderer locals declared ABOVE `solveAndApply`? `resolveForFeedback` is declared at ~:2295 (BELOW). **Ruling P-2:** `notifySolved` is declared as a forward local (`local notifySolved`) beside `solveAndApply` and ASSIGNED after `resolveForFeedback` is defined, or the lane's post-call goes through a tiny closure `runSolvedListeners()` placed after both. Implementer picks; the seam test is the suite. Cost if wrong: a nil call at the first lane tick — the demonstrator catches it. |
| T5 ↔ T3's oracle | T5 adds fixture drives (`anchorFlip`, `moveOut`, `withButton`) to `host_space_oracle.spec` | Additive. OK. |
| T5 ↔ `layout_prop_dirt.spec` | the lane consumes `offsetX/offsetY/anchor` entries WITHOUT marking `nodeDirty` | That spec mounts each arrange-only prop under its parent kind and asserts `measured == 0` + byte-equal geometry vs a full solve; under the lane the drive lanes (solves=0) — its geometry compare still holds (the lane wrote the same rect). Its `measured == 0` reads `lastMeasured` = previous solve's = 0 after mount? After mount the cold solve measured N. **Risk:** the pin may read a stale non-zero. T5 step 5 names the file; the implementer reads it off the run and moves the pin WITH the mechanism (a lane tick measures nothing BECAUSE it solves nothing). |
| T6 ↔ T7 | both touch the anchor branch's neighbourhood; T6 leaves the anchor arm; T7 adds `anchorSkipped` before the arm | Sequential, distinct hunks. OK. |
| T6 ↔ RR fanout pins | `measured=26 arranged=24 translated=2 skipped=11`, `lastMeasured 61` | move WITH measurement (T6 step 3). OK. |
| T8 ↔ T5 | T8's dirty-child index is built in `dirtyScan` over `remaining` | lane entries are consumed before the scan → not in the index → the walks never descend to a laned host — but the lane's host needs NO commit walk. Consistent. |
| Every task ↔ source cap | renderer 196,147; T1 −~2,400; T3 +~1,200; T5 +~700; T8/T9 +? | Each task re-runs the check; T3/T5 carry the STOP rule (extract `livePaths` into `rect_reads`). OK. |

Self-consistency per task: T0 (engine_writes.spec asserts a delta AND an A/A zero — two directions) OK; T1 (seam spec pins bind line + absence of old bodies + a behavioural scroll read) OK; T2 (anchorPlace pins by hand arithmetic; seam spec's write set widened deliberately) OK; T3 (demonstrator pins counters + HEAD literals for public reads + six reader-audit pins; the oracle gains an "e" no-host control compared at mount only — stated) OK; T4 (RR literals read at HEAD FIRST — step 1 is ordered before T3 lands) OK; T5 (the owed list is the spec header; the mutation is named) OK; T6–T9 (profile-gated; each carries counter + red + oracle) OK; T10 OK. Rubric: no task mandates an assertion-free test; the only verbatim duplication risk is the fake's `_composePresentation` host walk vs the live `hostOriginOf(handle)` — two adapters, one rule each, mirrored by design (the existing pattern).

Plan review (fresh-context opus, read-only) dispatched 2026-09-03 → scratchpad `plan-c-review.md`.

## Execution

### Task 0 — instruments + the before
- BASE `a46f84c4`. Brief `task-0-brief.md`. Implementer: sonnet. Dispatched 2026-09-03 (while the plan review runs — T0 is instruments only; any review amendment to T0 is applied as a fix round).

## Plan review (fresh-context opus, read-only vs `a46f84c4`) — NOT READY: 5 BLOCKING / 12 IMPORTANT / 9 MINOR (`plan-c-review.md`)
Rulings (full text: scratchpad `plan-c-rulings.md`), all ACCEPTED with the mechanism the ruling names:
- Ruling BL-1 — the fifth trigger refuses `ScrollView`/`clipChildren`; `registerHost` reuse ORs `hostSpace` — cost if wrong: a scroll list's rows land at rect − host.
- Ruling BL-2 — the lane serves the build's four placement fields through ONE extracted `layout_node.applyPlacement`, never marks `nodeDirty`, and refuses a nil-flip — cost if wrong: a host snaps back on the next solve (oracle `tick`→`hp` catches it).
- Ruling BL-3 — T6's serve is GATED (subtreeHasScroll/subtreeHasComposition/containerRelativeInside/analyze/measureQuiet), records via one `record()` at every return, pinned by source scan — cost if wrong: a stale composition/fit cut behind a correct rect.
- Ruling BL-4 — the fake recomposes a space host's subtree on `setRect`; `pos == sro` identity inside `snapshot()` — cost if wrong: a green oracle over a stale mirror.
- Ruling BL-5 — `paintedRectIn` uses `originIn(rects, path)` over the FRESH map — cost if wrong: a one-frame cull lag under moving hosts.
- Ruling IM-1 — arm `e` = same world with `translateHosts = false` (attach opt), compared every step. IM-2 — live adapter oracle = `host_move_write_cost.spec` × 9 views × 3 host shapes. IM-3 — `placement.innerBox` shared. IM-4 — lane SERVES hit_lift (calls `hitLift.refresh`), sink/hit counts dropped; full-Sponsor-surface pin. IM-5 — rows settled. IM-6/IM-7 — origin-carry `ctx.spaceOX/OY` + `ctx.spaceOrigin`; composition + text_audit compose; R-8 scan DELETED. IM-8 — epoch bump per commit + `dropPath`. IM-9 — `composedCache` per (path, epoch). IM-10 — char budget, STOP 197,500, fallback seam `dirty_closure.luau`. IM-11 — forward local `notifySolved`. IM-12 — RR HEAD literals = T3 step 0; unchanged literals = T3's gate.
- Minors applied as written (MI-2: the floors are the LAST OBSERVED counts; T0 records the true base counts).
Amendment pass dispatched (opus) → `plan-c-amend-report.md`; plan commits after a scoped re-check of T3/T5/T6.
- Task 0 reported DONE at Facet `0e69ceb1` + FacetBench `f446078` (suite 8251/0, RR 3575/0, check.sh green; `engine_writes.spec` RED→GREEN). Extra file: `docs/extending/new-render-target.md` OPTIONAL-METHODS block (required by `render_target_contract.spec`'s MAINT-8b pin). Lever verdicts: C2/C3/C4/C5 all IN. Task review dispatched (sonnet) over `review-a46f84c4..0e69ceb1.diff` + `task-0-facetbench-diff.md`.
- **True floors at base (MI-2):** Facet 8251 (T0's run; base was 8250 by T0's own gate), RR 3575 (task-0-rr-suite.txt).

## Plan re-check round 1 (opus, read-only) — 17/17 rulings ADDRESSED; 4 BLOCKING / 5 IMPORTANT / 7 MINOR NEW defects (`plan-c-recheck.md` §2)
Rulings round 2 (`plan-c-rulings-r2.md`), all accepted as the re-check proposes: N-1 composition origin as NUMBERS at solver:2702 (measure-time call unchanged — already position-blind); N-2 text_audit composed at the PRODUCER; N-3 fresh-map `originIn` closure for hit_lift + authorPressableRects; N-4 served return goes through `record`; N-5 `applyPlacement` called after the literal, nine props; N-6 self-inclusive booleans; N-7 module-level `record`; N-8 `spaceHostHasPath` lifecycle; N-9 types; N-10..16 as written. Amendment round 2 dispatched (same agent).

## Side request (user, 2026-09-03): fix the public-repo CI failure
GitHub `josha/Facet` run 33828183380 on the grafted `public` (9bf94c48): `tools/verify.sh full` FAIL — FAIL_RECOVERABLE rows across ~20 gates (prior-gates-unregressed, registration-and-docs/drift, checker-battery, distribution-readiness rows pinned to private shas 6907f85 / 27c0afd2 and the archived `gate_manifest.luau`). CI was green on `public` 2026-08-31 after "the registration row's second ancestry clause learns the same fallback" — the precedent. Fixer dispatched (opus) in worktrees: private branch `ci-public-verify` off main + cherry-picks onto `public`; nothing pushed — the user pushes `public`.
- Task 0 review (sonnet): Spec ✅; quality NEEDS FIXES — Important 1: `byKind` accumulation runs on frame-paced rows (pollutes `heapNetKb`/`gcSwingKb`); Important 2: no schema spec for the `byKind` branches; Minor 3 (plan-mandated wording): `target_contract.luau:20` claims `hostSpace?` exists today. Ruling: fix all three (the plan-mandated wording was mine and wrong — "today" must not name a T3 field). Minor 4 deferred: duplicated `bucketName` in attr.luau + run_one_lib (no shared require root) → `Task 0: minor (deferred): bucketName duplicated across processes; cross-check test if a shared root appears`.
- Task 0: fix round 1/5 dispatched (resume implementer). Facet gates must wait for the CI fixer's lune run (one lune at a time).
- Plan amendment round 2 applied (1,423 lines); re-check round 2 dispatched (opus).
## Plan re-check round 2 — N-1..N-16 16/16 ADDRESSED; 3 BLOCKING / 1 IMPORTANT / 5 MINOR new (`plan-c-recheck-r2.md`)
Rulings round 3 (`plan-c-rulings-r3.md`), all accepted: B-1 `text_audit` has NO live producer — the real raw-rect site is `tests/lib/large_text.auditRects` (composes via `controller.rectOf`; `text_audit.luau` untouched; R-13's canary clause was FALSE — corrected); B-2 `spaceHostHasPath` ±1 rides `livePaths`' latch transition + `sweepDeparted`'s `pathNodes` guard + a `pathHostOf` map for reparents; B-3 hit-floor composition happens in the ENTRY's space (no return trip); I-1 the lane's hit_lift call uses `hostOriginOf` (its map is `lastRects`); M-1..M-5 as written; `composedCache.src` typed; the origin push/pop becomes an `arrange` → `arrangeBody` wrapper so no early return skips the pop. Amendment round 3 dispatched (same agent).
- Plan amendment round 3 applied (1,472 lines): `ctx.spaceOrigin` DELETED (dump.luau never sees a ctx — the amender's source read); `pathHostOf` added; `arrangeBody` wrapper; large_text.auditRects composes via `controller.rectOf`. Re-check round 3 dispatched (opus).
- CI side request — diagnosis (`ci-public-diagnosis.md`/`ci-public-fix-report.md`): FOUR first-order causes, two of them NOT lineage-specific (red on private main too): A `check_manifest_integrity` cites a stale case id (`twenty-six`→`twenty-seven` records, T8 R2 grew CommitCtx); B `keep-visible-consolidation` greps `keepVisibleOffset` in renderer.luau after the scroll_into_view seam moved it; C/D the two freeze rows pin private shas (their 08-31 fallback was REVERTED by `f27942b5`'s `repair_graph.py` regeneration — the durable fix lands in the generator's tables + graph.json). Three commits on `ci-public-verify` (522ebb9a, b519172a, 87706dda) cherry-picked to `public` (f06cdbbf, a62a9506, 98a21e12); public-lineage rows become FAIL_ENVIRONMENT (exit 2 + the word; non-blocking at full, blocking at release) — measured in a standalone clone. Worktree `verify.sh full` on public: 1 red (`registered-before-work`, shared-object-store artefact). Full CI job in a depth-1 clone requested. **Ruling CI-1:** causes A and B are also cherry-picked onto `facet-parity` after T0's fix lands (they are gate-tool fixes red on main; without them T10's `verify.sh full` cannot be green) — cost if wrong: two duplicate commits at merge.
- Task 0: fix round 1/5 — Facet `7cf6bb69` (target_contract prose), FacetBench `1f3960c` (byKind gated to loop rows + schema spec cases); suite 8251/0, verify affected PASS_PARTIAL, check.sh green. Scoped re-review dispatched (sonnet).
- Ruling CI-1 applied: the three `ci-public-verify` commits cherry-picked onto `facet-parity` (see `git log` — identical patches; git dedups at merge).
## Plan re-check round 3 — 11/12 ADDRESSED; B-2 NOT ADDRESSED (the amender reported lines it never edited — its context had drifted); 1 IMPORTANT (renaming `arrange`→`arrangeBody` breaks `translate_arm.spec:227`'s source scan) + 4 minor.
Round 4 amendment dispatched to a FRESH opus agent (SDD rounds ≥4 rule) with the seven fixes verbatim from the re-check (D-0 three clauses + `noteFromHost` entry point; D-1; MI-1..5).
- Task 0: fix round 1/5 (3 addressed, 0 open; commits 0e69ceb1..7cf6bb69 Facet, f446078..1f3960c FacetBench). Re-review clean.
- **Task 0: complete (commits a46f84c4..7cf6bb69, review clean)** + FacetBench `f446078`, `1f3960c`. Deferred minor: bucketName duplicated across processes.
- CI side request DONE (not pushed): `ci-public-verify` = 02d7e6c1 (4 commits: 522ebb9a, b519172a, 87706dda, 02d7e6c1 — the 4th corrects the lineage witness to `git merge-base` since a worktree's shared object store defeats `cat-file -e`); `public` = 68214d37 (cherry-picks). Full CI Verify job green in a standalone depth-1 clone: `verify: PASS`, 0 FAIL_RECOVERABLE, 219 PASS / 273 FAIL_ENVIRONMENT; all six ci.yml steps exit 0. Ruling CI-1 applied: all four cherry-picked onto `facet-parity` (5af4d32b, 7b3f6b52, 05a9c5d1, dc9aa49f). Worktrees left in place at scratchpad `facet-ci-fix`, `facet-public`. The user pushes `public` → origin main and merges `ci-public-verify` → main.
- Plan amendment round 4 (fresh opus) applied D-0/D-1/MI-1..5 (1,532 lines); scoped re-check dispatched (sonnet). Plan commits on READY.
## Plan re-check round 4 — READY (7/7 ADDRESSED; one MINOR residual). Ruling: the un-Path transition (a live node whose class flips away from "Path" at the same path) is unreachable because a path's class is stable for its life (mount keys paths by id; the adopt/create path never re-creates on a class change) — T5's implementer adds the one-sentence note beside the latch. `Plan: minor (deferred): un-Path edge documented, not coded`.
- `tools/verify.sh affected` on the docs-only tree read FAIL: `check_manifest_integrity` audits the NEWEST stored full-tier suite result (`artifacts/verify/results/suite`, an 8006-case result from before Plan B) — stale relative to HEAD's 8251 — an artefact of never having run `verify.sh full` on this checkout since the graft fixes. Running `tools/verify.sh full --jobs 1` now (transcript `verify-full-after-t0.txt`); the plan commits after it.
- `tools/verify.sh full --jobs 1` on facet-parity at dc9aa49f: **PASS** (316.4s) — the stale suite-result artefact is gone and the four cherry-picked gate fixes hold here. (The run rewrote `examples/places/*.rbxl` nondeterministically — reverted with `git checkout --`, the same noise T0 saw.)
- **Plan committed at `10e331ac`** (1,532 lines, T0–T10, R-1..R-15).

### Task 1 — the renderer's geometry-read seam (`src/render/rect_reads.luau`)
- BASE `10e331ac`. Brief `task-1-brief.md`. Implementer: sonnet. Dispatched 2026-09-03.
- Task 1 reported DONE at `feb85a9e` (suite 8261/0, RR 3575/0, renderer 196,147 → 194,497 = −1,650 vs the −2,100 budget → T3 step 0b NOT triggered (threshold 196,100); collateral: `tests/scroll_into_view_seam.spec.luau` widened `declarationsOf`; a `-- stylua: ignore` pragma on the pinned bind line — first in the repo). Task review dispatched (sonnet) over `review-10e331ac..feb85a9e.diff`.

### Task 2 — the solver seams (`layout/translate_arm.luau`, `placement.anchorPlace/innerBox`)
- BASE `feb85a9e`. Brief `task-2-brief.md`. Implementer: sonnet. Dispatched while T1's review runs (distinct files; lune serialised by polling).
- Task 1 review (sonnet): Spec ✅, quality Approved; 3 minors deferred: `scrollShift` local bound but unused in renderer (dictated by the pinned destructuring shape); a duplicated `scrollHostOf` comment in rect_reads; the `-- stylua: ignore` pragma (first in src/). **Ruling:** keep the pragma — the char-for-char pin is the seam's evidence and stylua re-wrapping a pinned line is a known trap (scrollbar-gutter round); cost if wrong: one line exempt from formatting.
- **Task 1: complete (commits 10e331ac..feb85a9e, review clean)**.
- Task 2 reported DONE at `22897aac` (suite 8293/0, RR 3575/0, solver 195,168 → 191,195). One real regression surfaced by the extraction and fixed in-task (`tests/redteam_closing_round.spec.luau` — see report :160-180). Task review dispatched (sonnet) over `review-feb85a9e..22897aac.diff`.

### Task 3 — the per-host rect space
- BASE `22897aac`. Brief `task-3-brief.md` (310 lines). Implementer: opus. Dispatch text at scratchpad `t3-dispatch.md`. Dispatched while T2's review runs.
- T1 debt found by T2's verify: `check_comment_codes` FAIL — four `rect_reads.luau` comments cite plan review codes (IM-9/IM-8/BL-5) copied from the plan's code blocks; the T1 review missed it (its `verify affected` was read as PASS_PARTIAL). **Ruling:** fixed inside T3 (which edits rect_reads anyway) — reword to plain reasons; standing rule for every later implementer: no review codes in src/ comments. `Task 1: minor (deferred → T3): comment codes`.

### Task 3 — reader audit
Written BEFORE any `src/` edit (step 1). One row per rect reader the plan names
(S2 §8.1/§8.2, as enumerated in the T3 brief's step 1) plus the three ABSOLUTE
readers ruling R-13 exists for. Verdicts: **composes** = it reads through
`controller.rectOf`/`screenRectOf`/the pointer contract, so the origin is added
back for it and nothing is edited; **same space** = it compares two rects that
are host-relative to the SAME host, so the composition cancels — no edit, but
pinned; **must compose** = edited in this task; **origin carry** / **composed at
its producer** = the absolute readers.

| # | Reader (site) | What it reads | Verdict | Pin |
|---|---|---|---|---|
| 1 | `input/drag_registry.luau:215/426/471/657/939/970/999` (`opts.rectOf`, aliased) | the alias handed at `renderer.luau` — the controller read | composes via `rectOf` (no edit) | arm `e` `ro=` compare, `tests/host_space_oracle.spec.luau` |
| 2 | `present/surface_lifecycle.luau:573` `handle.feedGeometry(handle.controller.rectOf)` | hands the composing function itself down the geometry seam | composes via `rectOf` (no edit) | — (the function is passed, never a rect) |
| 3 | `controls/slider.luau:530-558` `syncGeometry(rectOf)` | `trackRect`/`thumbRect` off the fed `rectOf` | composes via `rectOf` (no edit) | `translate_host.spec` "a slider inside a moved host" is covered by the identity pin (d); the IDENTITY concern (`slider:183-185` skips a write when `rectOf` returns the same table) is served by `rect_reads`' `composedCache` |
| 4 | `controls/table.luau`, `table_rows.luau`, `table_header.luau` (46 sites) | all through the controller `rectOf`/`screenRectOf` or the pointer contract's third argument | composes via `rectOf`/`screenRectOf` (no edit) | arm `e` compare |
| 5 | `controls/level_picker.luau:364-365/511-516` | `rectOf` is the POINTER CONTRACT's third argument, which `renderer.luau:1272/1281/3552` supplies as `screenRectOf` | composes via `screenRectOf` (no edit) | arm `e` `sro=` compare |
| 6 | `controls/text_input.luau:534-540` `syncGeometry(rectOf)` | field rect off the fed `rectOf` | composes via `rectOf` (no edit) | arm `e` compare |
| 7 | `controls/virtual_list.luau`, `virtual_list_hosted.luau`, `virtual_grid.luau`, `virtual_reorder.luau` | the fed `rectOf` / the pointer contract | composes (no edit) | arm `e` compare; a `ScrollView` is REFUSED as a space host (step 3), so a virtualiser's own host never changes space |
| 8 | `region_expand.luau:108-112/287/329-363` (`rectOfPath` over the fed `rectOf`) | the region's own rect | composes via `rectOf` (no edit) | arm `e` compare |
| 9 | `present/modal_zones.luau:58-100` `zoneAContains(handle.controller.rectOf, …)` | every focusable's rect vs a window-space pointer | composes via `rectOf` (no edit) | arm `e` compare |
| 10 | `present/catchers.luau:352` `zoneAContains(owner.controller.rectOf, …)` | same | composes via `rectOf` (no edit) | arm `e` compare |
| 11 | `render/presentation_channel.luau:78,587` | `lastRects[path]` for the node it is writing a presentation record FOR | same space by construction (no edit, pinned) | `translate_host.spec` (f) — a focused node inside a moved host keeps its `focusLift` |
| 12 | `controls/selection_indicator.luau:73/679-690` | `rectOf(layerPath)` and `rectOf(segment)` — nodes that share a parent, so the host origin cancels in the subtraction | same space by construction (no edit, pinned + one added sentence in the `:73` comment) | `translate_host.spec` (d) |
| 13 | `renderer.luau:1509/1520` `restoreParkedProps` | carries `lastRects[old]` onto `lastRects[new]` across a recycle | **must compose** — carried only when `hostSpaceOf[old] == hostSpaceOf[new]`; else dropped, costing one spare `setRect` | `translate_host.spec` (e) |
| 14 | `render/hit_lift.luau:138-150` `refresh(rects, hitRects, sinks, …)` | THIS solve's `result.rects` + `lastHitRects` | **must compose** — gains `originOf` (the FRESH-map closure over `geometry.originIn(result.rects, …)`) | `translate_host.spec` (k) |
| 15 | `render/commit_walks.luau:1099-1112` `authorPressableRects` + `:1170` `growWithin` | `rects[path]` off the COMMIT walk's own map | **must compose** — ctx gains the same fresh-map `originOf`; sinks offset by `originOf(sink) − originOf(entry)` so `want` stays in the ENTRY's space | `translate_host.spec` (a) + (k)'s stored-rect half |
| 16 | `render/surface_overlap.luau:145` `coverRect(rootPath, rects, excluded)` | `lastRects` (its caller's map at `renderer.luau:3796`) | **must compose** — four-argument form, handed `geometry.hostOriginOf` | `translate_host.spec` (c) |
| 17 | `render/scroll_into_view.luau:104-117` | `lastRects[hostPath]` and `lastRects[path]`, then subtracts | **must compose** — `Deps` gains `hostOriginOf`; compose both before subtracting | `translate_host.spec` (b) |
| 18 | `render/rect_pass.luau:83-96` `applyOne` | `lastRects[path]` vs `entry.rect` | same space by construction (no edit) — both sides are the STORED value | the write counters in `translate_host.spec` |
| 19 | ABSOLUTE: `layout/composition_resolve.luau:187-188` (`atRoot`, the `{placedX},{placedY}` cache key) | window-space position | absolute reader: **origin carry** — the arrange-time caller (`solver.luau:2702`) passes `innerX + ctx.spaceOX, innerY + ctx.spaceOY`; the measure-time caller (`:1386`) is unchanged and position-blind | arm `e` `diagKey=` compare |
| 20 | ABSOLUTE: `tests/lib/large_text.auditRects` (`tests/lib/large_text.luau:220-244`) | `w.adapter.node(path).rect` — the STORED rect, fed to `audit.overlaps`/`clippedEssential`/`hitFloor` | absolute reader: **composed at its producer** — one line, `w.controller.rectOf(path)` | `tests/large_text_*.spec.luau` (the device matrix) |
| 21 | ABSOLUTE: `layout/dump.luau:11-51` `nodeDump` | `entry.rect` — the SOLVER's entry rect | absolute reader: **composed at its producer** — a two-number accumulator down the recursion it already does | `translate_arm.spec` / `commit_translate.spec` dumps, and arm `e` |

**No row, on purpose:** `layout/text_audit.luau`'s `outOfBounds` / `focusVisibility`.
They are never required from `src/` or `tools/` (every hit there is prose) and are
called only from `tests/text_audit.spec.luau` on hand-built literal rect maps. They
have no live producer.

**The `contentRect`/viewport grep the brief asks for** (`grep -n "contentRect\.\|viewport" src/layout/*.luau`): findings recorded with the implementation below.

- Step 0b decision: **NOT triggered.** `check_source_size.py` at `22897aac` reads
  `renderer.luau` 194,497 — below the 196,100 trigger, and 1,400 below the
  195,897 T3 budget line. `src/render/dirty_closure.luau` is not extracted.
- Step 0 (RR literals) committed at RascalRally `e3bfc45` (3578/0): the minimap
  dot / hit / name tag, the compact Ticker strip + its entry plate, and the
  StartCountdown box + numeral, each pinned to the value read off the run at
  RR `07d1a18` + Facet `a46f84c4`; `hostCount()` 0 and a dots-only frame's
  `rectWrites` delta 48 recorded as the before column.
- Task 2 review (sonnet): Spec ✅, quality Approved, no findings. **Task 2: complete (commits feb85a9e..22897aac, review clean)**. Note: solver 191,195 = 1,195 inside the 190,000 warning band (headroom 8,805 to the cap) — T3's solver edits (~+1,200) and T6's (~+1,800) fit.

### Task 3 — findings that changed the plan's own mechanism
Three of these were found by MEASUREMENT, not by reading the brief, and each one is
a place where the plan's stated reasoning did not hold:

1. **R-13 does NOT make a Composition exact under a moving host.** The plan
   replaced R-8 (the create-time Composition scan) with "the solver carries the
   absolute origin, which is exact at any time". It is exact only where the
   composition is RE-ENTERED. Under a coordinate space a host's move changes no
   descendant's rect in its own space, so both the translate arm AND the ordinary
   arrange SKIP pass, and the composition keeps a resolution computed at the
   position before last. Measured: a reactive-`offsetY` `ZStack` holding a
   Composition excluded `{0,0,200,200}` placed its region **7px low** after one
   slide. Fixed in the solver with `Ctx.spaceStack` / `spaceCompositions` /
   `noSkipDepth`: every space host above a composition is marked (on the arrange
   walk, carried forward in the work record), and such a host suspends both the
   skip and the arm for its own body. Pinned by
   `tests/translate_host.spec.luau`'s composition case, which compares the hosted
   and unhosted worlds on every public read and on `diagnostics()`.
2. **The `hostSpace` stamp cannot live only in `ensureTree`.** `layout_node`
   builds the solver's node from the same mounted node and CAN RUN FIRST: a
   re-solve driven from inside a settle (a virtual list widening its window off
   the geometry it was just fed) builds nodes for rows whose handles do not exist
   yet. Instrumented directly: for a card rail's `[c3]/Row`, `layout_node` built
   five nodes with `hostSpace = nil` and `ensureTree` stamped `true` afterwards —
   so the solver stored that subtree ABSOLUTELY under a host the adapter had
   registered as a coordinate space, and every reader composed an origin that was
   never subtracted. **This was the single cause of ~50 of the 88 first-run
   failures** (all of `gallery_chrome`, `virtual_*`, `examples_gallery`,
   `overflow_sweep`). Fixed by asking the ONE predicate at both sites:
   `instance_boundary.createOptsFor` memoises its coordinate-space answer on the
   mounted node, so whichever caller asks first fixes it for both.
3. **`adopt` never re-resolved `handle.instanceHost` for the new path** — on
   BOTH adapters. The live one wrote it only when the new path HAS a host (so an
   instance adopted out from under one kept the old entry); the fake never wrote
   it at all. Latent before this task (the field only fed the park refusal and the
   engine-write mirror); load-bearing now. Caught by the oracle's `pos == sro`
   identity on the `add 2` step, which is exactly the instrument that clause was
   added for. Both now write it unconditionally, the `nil` included.

Also recorded: `hitRects` STOPPED WALKING A MOVED SUBTREE (1,503 → 253 on the
250-plate fixture). It was the one walk that "never prunes a move by
construction" because it centres its expander on `r.x`/`r.y` — and under a
coordinate space a moved plate's descendants do not move in their own space, so
their entry tables are the ones the last commit saw and plain `skip` stops it. A
consequence of the storage change, not a new prune; `commit_translate.spec` and
`nameplates_baseline.spec` carry the moved numbers and the reason.

Deviations from the brief, each with its number:
- **Renderer +1,757 against R-14's +1,400** (194,497 → 196,254), after taking
  step 0b (`src/render/dirty_closure.luau`, −1.9 KB, with its own seam spec) and
  moving the commit-span origin closure into `render/rect_reads` where the maps
  it walks live. The irreducible CODE alone is ~950 characters; the budget could
  not accommodate it plus any reasoning at this file's register. Under the 197,500
  STOP line; ledger row re-recorded.
- **Solver +6,250** (191,195 → 197,445), against the brief's "+~350". Finding 1
  is most of the excess. **2,555 characters to the cap — the least this file has
  had, and T5 edits it next.** Ledger row re-recorded with TRIGGER: ARRIVED and
  two named candidates (the SCROLL arrange branch; `noteContainment` →
  `arrange_reports`).
- `tests/translate_arm.spec.luau` and `redteam_closing_round.spec.luau`'s
  composition world mount with `translateHosts = false`: their subject is the
  translate ARM, which a coordinate-space host does not use, so the coverage is
  preserved exactly rather than re-pinned against the absence of the mechanism.
  The two cases the brief names by line (`:148`, `:157`) stay on the shipped mount
  and their numbers moved with the measurement.

### Task 3 — the fake target's `rect` ruling (recorded, because it is a contract change)
The first full-suite run after the mechanism landed was **88 failures across 33
spec files**, and the shape of that list is the finding. Two thirds of it was the
`hostSpace`-stamp ordering defect above. The remainder was one question asked
forty times: **what does `fake_target`'s `node.rect` mean?**

It had always meant "where this node is" — every containment rule, every overlap
sweep, every pointer coordinate a spec computes, and `tests/lib/overflow_guard`'s
whole rule set read it that way. Leaving it as the STORED (host-relative) rect
would have made the suite's single most-used instrument mean something different
depending on whether an ancestor happened to carry a reactive offset, and every
future test author would have to know that.

**RULING: `node.rect` is the WINDOW-space rect on both targets; `node.storedRect`
is exactly what the renderer handed `setRect`.** Same split for the hit band
(`hitRect` / `storedHitRect`), because `applyHitExpander` re-bases it for the same
reason and the commit pushes hit rects BEFORE rects — so the fake re-derives the
band inside `setRect` too, mirroring the live `applyRect -> applyHitExpander`
call. `adapter.composedRect(path)` is the explicit name for the first, for a rule
that wants to SAY it means window space. This is the fake's own stated doctrine
(it models the composed engine answer — see `presentedPosition`), not a new one;
what is new is that the host-relative half now has a name of its own, and the
oracle's `snapshot()` compares arm `a` against arm `e` on exactly that column.

It cost ~30 assertions across 12 specs to migrate the ones that genuinely wanted
the stored value or a composed pointer coordinate; the alternative was ~40 in the
other direction plus a permanent trap. **`region_expand`'s "the disc's HIT floor
takes nothing from an interactive control" is the case that proves the hit half:
it fails by exactly the host origin (20 px² of overlap instead of 4) whenever the
band is compared in the wrong space.**
