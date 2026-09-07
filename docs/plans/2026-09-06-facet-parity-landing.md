# Facet parity Plan C — where the performance landed, and what is left

2026-09-06. Branch `facet-parity` (83 commits over main `a46f84c4`, head `577eda25`).
Authority for every number: `FacetBench/docs/studio-runs/2026-09-03-facet-parity.md` §after
(and §8b for the last fix). Gates at the head: Facet suite 8,683/0, RascalRally 3,599/0,
`tools/verify.sh full` PASS (0 FAIL_RECOVERABLE), FacetBench `check.sh` green.

## 1. The short version

- Every leaf-edit and state class got **40–58 % cheaper** headless at size L.
- The flagship nameplates tick pin is **MET**: Facet's own work 2.94 → 0.92 ms, `solves` 1 → 0,
  engine writes 1,500 → 250. The shipped RascalRally minimap moves 57 nodes on 8 engine writes.
- The settled-session classes that cost 39–77 ms went to **3.0–5.7 ms live** (13x).
- Every workload holds **60 fps** (16.5–17.0 ms frame p50) in Studio with the field moving.
- **The stated targets are mostly still missed**: ≤0.5 ms live is met on 4 of 12 update
  classes, ≤1 ms live on 4 of 13 structural classes. Every miss has a named mechanism (§3).
- One hard failure found by the close-out (a cap that threw out of `refresh` in the boot window)
  is **fixed** (`bec8e935` … `577eda25`, three review rounds): the cap defers to the next frame instead of throwing, and the deferred round re-arms itself from every frame entry point.

## 2. The headline classes

| class | Lune before | Lune after | live | vide live | target | verdict |
|---|---:|---:|---:|---:|---:|---|
| battle_hud updateItem-hp | 2.397 | 1.008 | 1.539 | 0.003 | 0.5 | MISS 3.1x |
| battle_hud setState | 3.002 | 1.272 | 1.602 · 2.952 [S] | 0.001 | 0.5 | MISS 3.2x |
| war_room setState | 3.811 | 1.832 | 1.942 · 4.189 [S] | 0.005 | 0.5 | MISS 3.9x |
| killfeed updateItem-hp | 0.657 | 0.283 | 0.448 | 0.002 | 0.5 | MET |
| killfeed setState | 0.677 | 0.313 | 0.458 | 0.002 | 0.5 | MET |
| nameplates tick (arena) | 5.853 | 4.667 | 3.071 | 0.307 | 0.5 | MISS 6.1x (68 % of the Lune number is the fake target) |
| battle_hud addItem-damage | 5.091 | 2.910 | 5.667 [S] | 0.019 | 1.0 | MISS 5.7x |
| war_room reorder | 30.421 | 31.181 | 36.488 | 6.896 | 1.0 | MISS 36.5x (vide gap 5.3x) |
| battle_hud updateItem-facing [S] | — | — | 47.243 | 0.003 | 0.5 | MISS, wide-key settle |
| war_room updateItem-power [S] | — | — | 73.365 | 0.003 | 0.5 | MISS, wide-key settle |

`[S]` = the step learned a new word and paid the text settle. Full 29-row table: §after §2.

## 3. Why the misses miss — three mechanisms, no silver bullet

1. **Floor-bound (finished).** A live number is `Lune × 1.37 (Luau host) + 0.129 ms (floor)`.
   Every class under ~0.4 ms live is the floor plus its engine writes; no Luau lever moves it.
2. **Tree-size-bound.** battle_hud hp / setState, war_room setState and tier, the tick,
   damage_fountain numbers: 1,500–7,500-node trees where the residue is per-node walk cost. Plan C
   removed the getting-there in four modules (measure serve, stack O(dirty) aggregate, cross-only
   arrange lane, commit descend cache, z-order skip); what is left is the walks themselves. To hit
   0.5 live the Luau work must reach ~0.27 ms Lune, i.e. another ~3.7x on battle_hud hp.
   The §before span table is the lead: seven `cw.*` commit walks at a flat ~0.07 ms each on a
   one-leaf edit, plus `rectPass.apply` 0.083 and `build` 0.122 — if those are still O(live nodes)
   at HEAD they are the first lever of Plan D.
3. **Settle-bound (largest millisecond left).** When a changed (font, size) key has more users
   than `max(64, nodes // 8)`, the narrow re-solve is refused and the settle is a whole-tree cold
   solve: 47–84 ms live, 8.3 % of war_room's steps. This is a correctness refusal (a word is a
   token shared across labels; the narrow route used to discard corrections). Right-and-fast is
   not built.

Structural classes are O(shifted) with a per-rect `applyOne + setRect` constant; vide pays the
same shape at 5.3x less. `mountMs` is 3–5x vide's on every workload and was never attacked.

## 4. What shipped in the framework (all internal, no public API change)

Per-host rect space + translate lane (a moving host writes one rect, descendants ride), two-slot
measure serve, anchor clean-child skip, commit descend cache, z-order subtree skip, O(dirty) stack
aggregate, cross-only arrange lane, children-array reuse, commit probes only where owed, settled
text re-solve narrowed to the changed key (routed through the dirty closure), solve queue-and-drain
with a deferring frame budget, plus the RED-TEAM fixes (commit list count, drain tails, the
per-surface re-solve trigger). Six new seams keep `renderer.luau` under its 200k Source cap
(197,351 at head — the STOP line is 197,500).

## 5. Booked and parked (pointers in §after §9)

| # | item | status |
|---|---|---|
| 2 | wide-key settle: whole-tree cold solve over the push budget (47–84 ms) | BOOKED — Plan D step 2 |
| 3 | prefix rebase | BOOKED — buys nothing on this arena |
| 4 | war_room reorder +2.5 % (arrange scan + hit-rect composition) | BOOKED |
| 5 | damage_fountain updateItems-numbers +5.7 % (`toLayoutNode`) | BOOKED — Plan D step 3 |
| 6 | structural per-rect constant | PARKED by design — Plan D step 4 |
| 8 | elided node materialising after the z walk gets no ZIndex | BOOKED |
| 9 | T15 per-index clone-and-patch (~7 %) | PARKED, arena gap named |
| 13/14 | text store is process-global; C-2's reach needs two hosts cold in one frame | OPEN, stated |
| 15 | mountMs 3–5x vide | PARKED — Plan D step 5 |
| — | C-3 fix: the drain cap defers instead of throwing (16 rounds ≈ 890 ms worst frame); three review rounds found and closed two stranding paths (`bec8e935`, `b59a01f3`, `88e53087`, `577eda25`) | SHIPPED, accepted |
| — | the one-word-per-round vocabulary walk (~63 such frames on the pathological scene) | BOOKED — Plan D step 2 |
| — | `SOLVE_FEEDBACK_ROUND_CAP` still raises out of `refresh` | BOOKED |

The next campaign's goal prompt: `docs/plans/2026-09-06-facet-parity-D-goal.md`.

---

# Plan D — where it landed (2026-09-07)

Branch `facet-parity-d` (33 commits over main `b315dc34`; head `4c56f1c9` after the RED-TEAM wave, `f4fab4ac` before it).
Authority: `FacetBench/docs/studio-runs/2026-09-03-facet-parity.md` **§after-2** (and §D1–§D9 per task).
Gates at the head: Facet suite 8,779/0, `tools/verify.sh full` PASS (0 FAIL_RECOVERABLE, 454.3 s), RascalRally 3,601/0,
FacetBench `check.sh` green, differential re-baselined over the axes it was blind to (`6f14ec6b…`, 360 blocks; zero public-reader differences against the base), renderer 197,305.

## 1. The short version

- The goal's step-1 hypothesis was wrong and the first measurement said so: the seven commit walks were already
  tiny; **one function, `memoPlan`, re-walked the whole tree every solve** and no wrap-based profile could see it.
- Update classes ≤ 0.5 ms live: **8 of 12 MET** (was 4). `battle_hud updateItem-hp` 1.54 → **0.32**, `war_room
  setState` 1.94 → **0.32**, `updateItem-tier` 2.49 → **0.39**, `killfeed updateItem-hp` 0.45 → **0.26**.
- The wide-key settle rows (47–84 ms, the largest number Plan C left) are **1.4–1.5 ms**: the drain was the
  collector's 1,024-word budget re-consumed by in-flight words (one new word per solve), and the over-cap route
  now probes the WORD's users instead of cold-solving the tree. Boot-window `stepP95` on `battle_hud` **890 → 3.2 ms**.
- Structural classes: a list row is a coordinate space now — `war_room reorder` writes 1,467 engine positions
  where it wrote 7,335: **36.5 → 19.7 ms**, `removeItem-items` **18.6 → 8.3**. Still over the 1 ms bar; vide's
  honest bound at the same shape is 7.7 / 4.3 because the engine slides its rows in C++, which is an architecture
  decision (Luau owns layout) this campaign did not make.
- Three real defects found and fixed: the collector DROPPED words past its budget and nothing marked their owners
  (a > 1,024-word surface could settle believing it was settled); a coordinate-space host's children were re-based
  TWICE on a structural shift (shipped on RowActions trays); the word index was blind to numeric text (every HUD
  number). One lever (D5, mount) was built, measured, refuted and reverted. Two pre-existing defects booked with repros.

## 2. The headline classes (live, settled, fresh client VM)

| class | Plan C close | Plan D | vide | target |
|---|---:|---:|---:|---|
| battle_hud updateItem-hp | 1.539 | **0.321** | 0.002 | 0.5 MET |
| battle_hud setState | 1.602 | **0.357** | 0.001 | 0.5 MET |
| war_room setState / tier | 1.942 / 2.493 | **0.322 / 0.389** | 0.006 / 0.003 | 0.5 MET |
| killfeed updateItem-hp / setState | 0.448 / 0.458 | **0.263 / 0.296** | 0.002 | 0.5 MET |
| battle_hud updateItem-facing [S] | 47.243 | **1.418** | 0.003 | 0.5 |
| war_room updateItem-power [S] | 73.365 | **1.525** | 0.004 | 0.5 |
| war_room addItem-items [S] | 83.668 | **6.958** | — | 1.0 |
| war_room reorder / removeItem-items | 36.488 / 18.612 | **19.698 / 8.261** | 7.671 / 4.346 | 1.0 |
| nameplates tick | 3.071 | 2.901 | 0.303 | 0.5 |
| damage_fountain updateItems-numbers | 1.609 | 1.635 | 0.179 | 0.5 |

## 3. What shipped (all internal, no public API change)

memoPlan on the node literal · per-index child patch · arrange replay over the dirty children · in-flight words
uncharged from the collector budget · probe budget on the dirty-set walks · `render/settle_solve.luau` seam + the
over-cap leaf probe · per-rect constant (assertWrite once per apply, bar-inset guard, cheaper z visit) · collector
overflow queue · hitRects walk refused when no sinks · per-word settle index with numeric text · rows as
coordinate-space hosts (translate arm stops at a host's own rect). Refuted and reverted: the cold-solve serve.

## 3b. The RED-TEAM (§after-2 §6)

11 concerns, no blocker. C-1 (a compact-form label the over-cap probe dropped — fixed, and pinned on the game side
where the shape ships), C-2 (the differential could not see six of the eight fast paths — re-baselined over
row hosts, the push cap, the collector cap, numeric text, compact labels, host-under-host; zero public-reader
differences against the base), C-3 (composed-rect identity churn — measured null: readers compare values), eight
minors fixed. A pre-existing RascalRally spec that walked nothing was found and fixed.

## 4. Booked (pointers in §after-2 §5)

The settle probe's per-word take loop (the `[S]` rows' last ms) · the structural floor is the engine's per-write
cost × the row count — the `UIListLayout` route is the owner's call · `damage_fountain`'s per-leaf constants ·
the tick's per-plate lane constant · two pre-existing defects (When-branch return after an insert; ScrollView
canvas width after reorder → branch toggle) · D2b's harvest descend list (a renderer seam) · mount (no O(1) lever) ·
`SOLVE_FEEDBACK_ROUND_CAP`.
