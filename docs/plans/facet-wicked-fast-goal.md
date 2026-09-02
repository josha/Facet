# Goal: Make Facet wicked fast — vide-class per-step cost under game-grade stress

You are a fresh Claude Fable 5.1 session picking up a finished performance campaign and driving it to its real destination. Two deliverables, in order:

**A.** Extend FacetBench with stress tests a game UI system must be fast at — headlined by **WoW-style real-time nameplates** (spec below).
**B.** Optimize Facet until its per-step and per-frame costs are in vide's class on those stress tests — "wicked fast." Vide parity is the dream; every honest multiple closer counts.

## Where things stand (2026-09-02, all measured, all committed)

The last campaign (P1–P5, Facet `4b460f0c → 4d9e3aac`) made every update-class stage O(touched) except one and delivered, ABBA-clean at size L (1,000-unit battle HUD): one-item update **44.7 → 2.49 ms**; Studio frame **51.3 → 16.6 ms (~19 → 60 fps)**; structural add **43.7 → 5.80 ms**. But the targets of ≤0.5 ms (update) / ≤1 ms (structural) at L are still **missed in 13 of 20 step classes**, and vide sits around **0.02–0.03 ms** for the same steps. The gap is measured, attributed, and yours:

- **The named bottleneck:** a solve that measures and arranges *nothing* still walks all N nodes — **0.969 ms at L, 0.19 µs/node — the last O(N) term.** Killing it is the campaign's charter. Booked levers L1–L8 live in `docs/superpowers/plans/2026-08-31-facetbench-plan2-3-notes.md` (same folder tree as this file) with file:line attributions.
- **The known structural weakness:** the all-dirty-every-frame path. When *every* node has dirt (per-frame position feeds), all five caches refuse and the frame pays close to a full rebuild — exactly what the nameplates test will expose. The T6/T9 reports name it.
- **war_room reorder/remove floor:** O(shifted) rect writes at ~7–8.4 µs each (7,335 writes = 51.6 ms). A structural answer (windowing/virtualization at the solver level, or engine-delegated positioning) is in scope if it preserves semantics.
- **Chrome/path pruning loss:** a UI.Path or cover-expander on a surface costs ~26× the pruned commit visits (measured; `tools/profile/chrome.luau`). Re-enabling pruning under chrome is a booked lever.

## Deliverable A — game-grade stress tests

Add workloads to FacetBench (neutral scene-spec + seeded cycle-safe scripts, same contract as the existing three — `runner/lune/lib/scene.luau` is the law, `workloads/battle_hud.luau` the