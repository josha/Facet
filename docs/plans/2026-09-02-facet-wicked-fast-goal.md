# Goal: make Facet wicked fast — toward Vide speed on game UI

Fresh Claude Fable 5.1 session, effort **high**. A GOAL, not a plan: read the docs, brainstorm + plan before code, then execute autonomously to done.

## Read first
1. `../superpowers/plans/2026-08-31-facetbench-plan2-3-notes.md` — the charter: status, next-levers (L1–L8), "Bookings for the next campaign". START HERE.
2. `../../../FacetBench/docs/profiling/2026-09-01-attribution.md` — where per-step cost goes.
3. `../../../FacetBench/docs/studio-runs/2026-09-02-after-campaign.md` — per-class target table + named bottleneck.
4. `2026-09-02-facet-wicked-fast-reference.md` (beside this) — full trap list + verbatim operating rules.
Also skim `games/RascalRally/CLAUDE.md` — the live consumer; lockstep is constitutional.

## Where it stands (Facet @ 4d9e3aac)
Five fixes (P1–P5) shipped: update-class at L **44.7→2.49ms (18x)**; Studio frame **51→16.6ms (~19→60fps)**. But **13 of 20 step-classes still miss ≤0.5ms-update / ≤1ms-structural.** Two measured reasons, both your job:
- **The last O(N) term:** an empty solve (measures/arranges nothing) still walks all N nodes (~0.97ms at L). Caches are O(touched); the skip-deciding walk is still O(tree).
- **The all-dirty-every-frame class is unattacked** — when every node's inputs change per frame, caches refuse and the frame near-rebuilds. The hard one.

## Mission
1. **Add game-UI stress workloads** to FacetBench (`GameStudio/ui/FacetBench`; follow the existing workload contract — study `workloads/*.luau` + specs). Flagship **`nameplates`**: WoW-style, 50–200+ world-anchored plates whose screen positions change EVERY frame (model camera→world projection in the seeded script), plus range enter/leave churn, health waves, threat flips, cast sweeps — the all-dirty class. Add ≥1 more real-game shape it reveals as unmeasured. All run in Lune + Studio, measuring facet vs **vide** (the speed target) honestly.
2. **Optimize Facet** against those numbers — attack the O(N) walk and the all-dirty class; get per-frame cost well under 1ms, update path toward vide's ~0.02ms/step. Directions to evaluate (don't assume): batched per-frame position writes, a transform/position-only fast path skipping measure+arrange, engine-delegated positioning, a moved-not-resized solve tier. Let the profile pick.
Warm-up fix (booked, user-visible): `propSigCache` recycles instances wearing style props they never declared.

## Method (non-negotiable — the reference doc has the full version)
Profile first, never guess. Each fix: a **red-first COUNTER demonstrator** (extend `work.*`/`stats()`; never wall-time — the Luau VM is bimodal, use median-of-K) + a **differential oracle** vs a forced full solve across the device matrix incl. 320x640. The **prop→dirty-class completeness audit is load-bearing** (a paint-only prop read as layout input was the campaign's hardest bug — extend it, don't trust a grep). Gates every commit: `tools/test.sh` full; `tools/verify.sh affected --jobs 1` FOREGROUND (never background/`--jobs>1`); `check_source_size.py` (solver frozen at 861 chars — extract a LIVE seam first, the ledger has stale triggers); stylua. RascalRally suite + milestone canary on every Facet src change; no public API/behavior change without the user. Fresh-context adversarial review per fix + a RED-TEAM at the end — budget for fix rounds; that's where quality comes from. Use subagents liberally.

## Done when
Nameplate + new workloads measure facet vs vide in both modes; Facet materially faster on the all-dirty class (state achieved per-class numbers vs targets — a miss stated plainly with its bottleneck + next lever beats a softened win); full gate green; RR lockstep + clean canary; public before/after + chart updated keeping the campaign numbers as "before". Honesty over optimism.

Operate autonomously: the user isn't watching live and can't answer mid-task — don't ask permission for requested work; proceed on reversible steps, stop only for destructive actions or scope changes. If a question arises, do everything not blocked on it, then state your assumption. Don't end a turn on a plan or promise — do the work. If compacted, preserve exactly: constraints, decisions, numbers, file:line, shas, and where things stand. Start by brainstorming the workloads and optimization approach.
