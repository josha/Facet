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
