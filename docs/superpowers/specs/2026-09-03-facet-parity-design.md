# Facet Parity — change how rects are written — Design (Plan C)

Goal text: `docs/plans/2026-09-03-facet-parity-goal.md`. Task plan: `docs/plans/2026-09-03-facet-parity-plan.md`.
Method + traps: `docs/plans/2026-09-02-facet-wicked-fast-reference.md` (unchanged, still binding).
Predecessor: Plan B (`docs/superpowers/specs/2026-09-02-facet-wicked-fast-design.md`, branch
`wicked-fast-facet`); its T9 after-picture (`FacetBench/docs/studio-runs/2026-09-02-wicked-fast.md`)
is the **"before"** of this campaign.

Owner request (2026-09-02): "We should change how rects are written. Assess update and how we compare
to vide across all our bench stress tests and ensure we have a plan to get much closer to parity."

## 1. Where it stands (the assessment)

Every number is L viewport. "Lune" = FacetBench Lune runner; "live" = Studio runner. Rows marked
`stale` were measured at Facet `4d9e3aac` (before Plan B) and are re-measured by C0 before any lever
is judged. Targets are the standing ones: update class ≤0.5 ms, structural ≤1 ms, mount ≤ vide×3.

| Workload · class | Facet | vide | Target | Over | Source |
|---|---|---|---|---|---|
| nameplates · tick (all 250 translate) | **5.39** Lune (`0bbd14de`, was 8.58; live before 9.43) | 0.29 live | 0.5 | ~11x target, ~19x vide | wicked-ledger summary |
| nameplates · add / remove | 0.85 / 0.79 Lune | — | 1 | met | wicked-ledger T7 |
| damage_fountain · add / remove | 0.31 / 0.34 Lune | **unmeasured** | 1 | met | wicked-ledger |
| battle_hud · updateItem hp / facing / setState | 2.49 / 2.93 / 2.59 live `stale` | step p50 0.022 | 0.5 | 5–6x | after-campaign §3 |
| battle_hud · add / remove damage | 5.80 / 5.70 live `stale` | — | 1 | 5.7x | after-campaign §3b |
| war_room · updateItem power / tier / setState | 3.67 / 3.71 / 3.30 live `stale` | p50 0.021 | 0.5 | 6.6–7.4x | after-campaign |
| war_room · addItem / removeItem / reorder | 8.76 / 29.1 / 51.6 live `stale` | p95 6.6 | 1 | 8.8x / floor / floor | after-campaign |
| killfeed · updateItem hp / setState | 0.64 / 0.60 live `stale` | p50 0.217 | 0.5 | 1.2x | after-campaign |
| killfeed · add / remove plates · add / remove feed | 1.07 / 2.11 · 3.79 / 3.74 live `stale` | — | 1 | 1–3.8x | after-campaign |

"Floor" = O(shifted rects): war_room remove moves 3,460 rects at 8.4 µs each, reorder 7,335 at 7.0 µs;
killfeed feed shifts move 776/835 rects at 4.5–4.9 µs. Those rows really move relative to their parent,
so the lever there is the per-rect constant (C3/C4), not the rect count.

### 1a. Why a 1-leaf update costs 2.5 ms and a 250-plate tick costs 5.4 ms

Measured at Facet `4d9e3aac`, battle_hud L, 5,115 nodes (after-campaign §3), confirmed unchanged in
shape by the Plan B ledger (T4–T7 shaved constants; none of these mechanisms changed):

1. **Measure visits every node even when nothing is dirty.** A 0-dirty solve costs 0.969 ms — the
   measure walk enters every child (`solver.luau` `measure()` ~:1602, call sites at 1263/1380/1456/
   1522/1561/2642/2848/2900/3019/3123), `adopt`s the memo (`:1735-1745`) and returns. 0.19 µs × 5,115.
   `memoPlans` is rebuilt every solve (`:3466`, `measure_facts.luau:408-410`).
2. **Arrange re-enters at the root stack.** 1.000 ms to arrange 3 nodes: `stack.arrange`
   (`src/layout/stack.luau:96-183`, loop `:127-157`) walks every direct child unconditionally.
3. **Commit sibling scan.** 0.609 ms: eight commit walks (`renderer.luau:2140-2228`) each
   `skip(child)` every sibling on the path to the dirty leaf (~64 visits per walk).
4. **Translate = O(subtree) rect writes.** A nameplate move is `offsetX/offsetY` (arrange class,
   `blueprint_schema.luau:763-780`). The solver's translate arm (`arrange()` `:2298`, `translatable`
   `:2334-2337`, `translateDescendants` `:2235`) re-bases the absolute rect of EVERY descendant, and
   `rect_pass.apply` (`src/render/rect_pass.luau:103-244`, `applyOne` `:83-96`) writes each one:
   1,488 `setRect`s for 250 plates ≈ 6 per plate (Plate, Head, Name, Level, Hp, Cast). The engine
   tree is **flat by construction** (`screen_presentation.luau:204-212`, ZIndexBehavior=Sibling
   `screen_target.luau:995`), so each of those is a real `Position` write. vide writes ONE
   `Position` per plate because the plate's children are parented to it.
5. **Structural: `syncZOrder` is still a whole-tree walk** (`renderer.luau:2384-2409`, called
   `:2671`; ssZOrder 0.795 ms of the 2.389 ms structuralSync at §3b) and so is
   `collectRetiringRoots`. T7 bounded ensureTree/livePaths/sweep only.

The number the owner asked about — "how rects are written" — is item 4, and it is the single
biggest gap on the flagship workload. Items 1–3 are the whole cost of every update class on the
three big workloads. Item 5 is the structural remainder.

## 2. Goals

1. nameplates tick: 5.39 → **≤1.0 ms Lune** (stretch ≤0.5 = the standing target), with
   `stats.solves = 0` on an all-translate tick.
2. Every `updateItem`/`setState` class on battle_hud, war_room, killfeed: **≤0.5 ms live** at L
   (the standing target), i.e. cost O(dirty × depth), not O(nodes).
3. Structural classes: add/remove ≤1 ms live where the rect count allows (battle_hud, killfeed
   plates, war_room add); the O(shifted) rows get their per-rect constant down and are reported
   against the floor, not the target.
4. Zero public API/behavior change: `rectOf`, `screenRectOf`, hit rects, focus, scroll-into-view,
   presentation, and every RascalRally screen read back byte-identical numbers (oracle §5).
5. Every lever profile-first, counter-pinned, differential-oracle'd across the matrix (incl.
   320x640), gated on every commit; RascalRally lockstep on every Facet src change.

## 3. Non-goals

- Virtualisation of long lists (war_room's O(shifted) floor is reported, not virtualised).
- Changing any workload, the vide adapter, or the fixture oracle.
- Wall-time-based demonstrators (counters only; wall-time is the report, never the gate).
- Touching the legacy Sponsor modules in RascalRally.

## 4. Approaches considered

**A. Per-host rect space (chosen).** A container that moves as a unit becomes a real engine parent
(an *instance host*, the existing `instance_boundary` mechanism) AND a coordinate space: every rect
beneath it is stored relative to the host. A translate is then one stored rect and one engine write.
Reads compose on demand, exactly the way `screenRectOf` already composes `scrollShift` and
`presentationShift` today (`renderer.luau:465-491`). Public numbers do not change because the public
readers compose. Cost: +1 Frame for a translate host whose container was elided; hosts cannot be
recycled today (`instance_boundary.luau` `parkEligible`); readers of raw rects must be audited.

**B. Host-only (rejected as the whole answer, kept as the fallback).** Register the same hosts but
keep the solver's absolute rect space; the engine write-skip (`screen_presentation.luau:395-403`)
would then collapse the 1,488 Position writes to ~250. The Luau side — translateDescendants,
rect_pass applyOne per descendant, hitRects per descendant — stays O(subtree), so Lune tick goes
from ~5.4 to maybe ~4 ms. Cannot reach the goal. If A's reader audit finds an unfixable consumer,
B ships as the ruling and the miss is reported.

**C. Cache/skip at the adapter only.** Already done (write-skip, W1 propSigCache). Not a lever any
more.

## 5. Design

### 5.1 The rule: a host is a coordinate space

Today `instance_boundary.createOptsFor` (`src/render/instance_boundary.luau:69-98`) registers a host
on four triggers (canvasGroup, opacity, scale-with-children, rotation-with-children). Plan C adds a
fifth: **a container whose `offsetX`/`offsetY`/`anchor` is reactive and that has children** — a
"translate host". (Detection: the blueprint's placement props are reactive values, which the
renderer already knows at mount because it subscribes to them.)

Rect space becomes **per host**: `lastRects[path]` for every node beneath a host is stored relative
to that host's origin; the host's own rect is stored in ITS parent host's space (or root space).
Root space is unchanged, so a tree with no hosts is byte-identical to today.

Composition on read: a new `hostOriginOf(path)` (cached per host, invalidated when a host's rect
changes) sums the host chain. `screenRectOf` adds it beside `scrollShift`/`presentationShift`.
`rectOf` — public contract "solver-space absolute" (`docs/reference/api.md:2705`) — also composes,
so **both public reads return exactly today's numbers**. The store changes; the API does not.

All host kinds share the rule (canvasGroup/scale/rotation/scroll hosts too), which retires the
deferred host re-base in `settleRects` (`screen_presentation.luau`) — one rule instead of two. If the
first measurement (task C1a) shows the non-translate hosts cost more than they save, the ruling is
"translate hosts only" and `settleRects` stays for the others; recorded in the ledger.

### 5.2 Solver: arrange beneath a host starts at (0,0)

In `arrange()` the child rect of a host is placed at origin, not at the host's absolute rect, and
`translatable()` on a host root skips `translateDescendants` entirely — the descendants' rects are
unchanged in their own space. The solver is frozen at the source cap, so the translate arm
(`translatable` + `translateDescendants` + the `:2388` call) is extracted first as a LIVE seam
(`src/layout/translate_arm.luau`, Deps-style like `stack.luau`), mechanised read-vs-write seam test,
then changed in the seam. The Anchor placement formula (parentRect × ownSize × anchor × offset)
becomes its own pure function `src/layout/anchor_place.luau` because §5.4 needs to call the SAME
function — no second copy of the maths.

### 5.3 Renderer and adapters

- `rect_pass.apply`: unchanged shape; it now writes host-relative rects. `applyOne` on a translate
  host's descendants finds `rectsEqual` true and writes nothing — that is where 1,488 → ~250 comes
  from, and `stats.rectWrites` proves it.
- `hitRects` walk (`commit_walks.luau`, not moveBlind because it centres on r.x/r.y): descendants'
  rects no longer change on a translate, so the walk's `skip` short-circuits — free. `hit_lift.luau
  :80-149` does overlap tests on raw rects in commit: overlap between nodes in different host spaces
  must compose (`hostOriginOf`); a test pins a hit expander under a translated host against a sibling
  outside it.
- Adapters: `screen_target.setRect` → `applyRect` (`screen_presentation.luau:333-402`) computes
  `px = rect.x - host.ox`; with host-relative input `host.ox` is 0 for the new spaces, so the maths
  collapses. `tests/lib/fake_target.luau:524 setRect` (and its region "widen" logic) must model the
  same parenting, because it is the oracle's adapter. `target_contract.luau:29-35` is unchanged.
- New counter `stats.engineWrites` (adapter-side, both adapters) so the Position-write collapse is
  pinned in Lune and not inferred.
- Recycling: `parkEligible` refuses hosts. A nameplate plate becomes a host, so add/remove would
  lose recycling. C1 measures; if add/remove regress >5 %, lift the refusal for plain-Frame hosts
  with their own `kindOf` bucket ("host") — the discriminator already names buckets by engine object
  for exactly this day.

### 5.4 The translate lane (C6): an all-translate tick solves nothing

`dirtyScan` (`renderer.luau:2836-2895`) already classifies dirt. New lane: when every dirty entry in
a refresh is a placement prop (`offsetX`/`offsetY`/`anchor`) on a translate host and nothing else is
dirty, the renderer does not solve and runs no commit walks. Per touched host it computes
`newRect = anchor_place(parentSpaceRect, hostSize, anchor, offsetX, offsetY)` with the host's stored
w/h (placement props are arrange-only — the prop→dirty-class audit is what makes "size cannot have
changed" a fact, not a hope), updates `lastRects[host]`, updates the host's own hit entry, and calls
`adapter.setRect` once. `stats.solves = 0`, `stats.laneTranslates = N`. Mixed ticks (any non-placement
dirt) take the normal path; the lane never partially applies.

Expected: 250 hosts × (a few table ops + one setRect) ≈ 0.3–0.5 ms Lune plus dirtyScan's O(entries).

### 5.5 The update-class levers (C2–C4) — same method, other walks

- **C2 measure pruning (Plan B's O1, never built).** `adopt` before the per-kind body so a clean
  subtree returns at its root without visiting children; `memoPlans` survives across solves and is
  invalidated per dirty path. Counter: `work.visited` — a 1-leaf solve visits O(depth), not O(nodes).
- **C3 stack arrange O(dirty).** The T6 anchor-arm shape applied to stacks: when a stack's children's
  measured sizes are unchanged, re-place only from the first dirty child (a following sibling only
  moves if a preceding size changed). Counter: `work.arrangeVisits`.
- **C4 dirty-child index (Plan B's O5, never built).** The eight commit walks descend by a per-node
  dirty-child set instead of scanning siblings. Counter: `lastCommitVisits` = O(depth × walks).
- **C5 bound `syncZOrder` + `collectRetiringRoots`** to the dirty subtree — under per-host spaces a
  host is also a sibling-order boundary, so the z walk is naturally per host. Profile-gated
  (>5 % of the structural class at the time, else booked).

Order: C1 → C6 (the owner's ask, biggest gap) → C2 → C3 → C4 → C5. Every lever is profile-first
(C0's per-class spans, ≥5 % or it is not a lever), red-first counter, oracle, gates, RR lockstep,
fresh-context adversarial review.

## 6. Oracle and gates

- **Differential oracle:** for every path, `rectOf` and `screenRectOf` byte-equal to a forced full
  solve (`controller.refresh({ full = true })`) after every step of every workload's driver, across
  the device matrix incl. 320x640, under both adapters. Extended for Plan C with hit rects, focus
  rects, and the engine `Position` of every live instance (fake target records them).
- **Counters (red-first, never wall-time):** `stats.rectWrites`, `stats.engineWrites`,
  `stats.solves`, `stats.laneTranslates`, `work.visited`, `work.arrangeVisits`,
  `lastCommitVisits`(byWalk). Every demonstrator pins `solves=N` (the check-that-proves-nothing
  class bit twice in Plan B).
- **Gates every commit:** `tools/test.sh` full; `tools/verify.sh affected --jobs 1` FOREGROUND;
  `python3 tools/check_source_size.py` (seam first when a frozen file is touched); stylua. Never a
  second lune process.
- **RascalRally lockstep:** every Facet src commit runs RR's suite + the milestone canary; the
  minimap markers, sponsor screens, and anything with reactive placement become translate hosts —
  RR contract/integration tests pin their `screenRectOf` numbers before and after.
- **Elision census** re-recorded after C1 (translate hosts add a Frame where the container was
  elided).

## 7. Risks

| Risk | Mitigation |
|---|---|
| A raw-rect reader (row_actions:1946, virtual_reorder:105, selection_indicator:73, anchored:200, presenter:954, text_reveal:198, anchor_placement:64, autoscroll_bridge:61, drag_bridge:77, scroll_into_view:68) mixes spaces | C1's reader audit table: each reader → same-space or composes; pinned by the extended oracle |
| Host registration costs a Frame on elided containers | Census before/after; nameplates instance count reported |
| Hosts cannot be recycled → add/remove regress | Measured in C1; "host" recycling bucket if >5 % |
| Fake target diverges from the live adapter | Both adapters run the oracle; Studio matrix on C1 and C6 |
| Lane's placement maths drifts from the solver's | One function (`anchor_place`), called by both |
| RR minimap pins move | Lockstep tests before/after; product behaviour unchanged by construction |
| Source cap | Seams first; renderer has no clean seam left — C6 lives in a new module `src/render/translate_lane.luau` |

## 8. Success criteria

- nameplates tick ≤1.0 ms Lune with `solves=0`, `engineWrites≈250`, `rectWrites≈250`; live number
  reported beside vide's 0.29 with the ratio stated plainly.
- battle_hud/war_room/killfeed update classes ≤0.5 ms live at L, or the miss and its remaining
  mechanism named.
- Oracle green on the full matrix under both adapters; suites at or above the Plan B floors
  (Facet 8193/0 → higher, RR 3570/0 → higher) on every commit; RED-TEAM at the end.
- Report at `FacetBench/docs/studio-runs/2026-09-03-facet-parity.md` with before/after per class,
  both runners, targets and misses stated.
