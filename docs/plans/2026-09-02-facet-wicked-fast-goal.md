# Goal: make Facet wicked fast — toward Vide speed on game UI

Fresh Claude Fable 5.1 session, effort **high**. This is a GOAL: read the ground-truth docs below, brainstorm + plan before code, then execute autonomously to done. A fuller companion with the full trap list is `2026-09-02-facet-wicked-fast-reference.md` beside this file — open it once you've read the two docs.

## Read first (the campaign that got Facet this far — its numbers, method, and bottleneck)
1. `../superpowers/plans/2026-08-31-facetbench-plan2-3-notes.md` — the charter: campaign status, the booked next-levers (L1–L8), and the "Bookings for the next campaign" list. START HERE.
2. `../../../FacetBench/docs/profiling/2026-09-01-attribution.md` — where per-step cost goes.
3. `../../../FacetBench/docs/studio-runs/2026-09-02-after-campaign.md` — the per-class target table and named bottleneck.
Also skim `games/RascalRally/CLAUDE.md` (the live consumer; lockstep is constitutional) and the reference companion for the paid-for trap list.

## Where it stands (measured, Facet @ 4d9e3aac)
Five fixes (P1–P5) shipped: update-class at L **44.7→2.49ms (18x)**; Studio frame **51→16.6ms (~19→60fps)**. But **13 of 20 step-classes still miss the ≤0.5ms-update / ≤1ms-structural target.** Two reasons, both measured and both your job:
- **The last O(N) term:** a solve that measures/arranges NOTHING still walks all N nodes (~0.97ms at L). Every per-step cache is O(touched) now; the walk that *decides* what to skip is still O(tree).
- **The all-dirty-every-frame class is unattacked** — when every node's inputs change per frame, the caches refuse and the frame near-rebuilds. This is the hard one.

## The mission
1. **Add game-UI stress workloads to FacetBench** (`GameStudio/ui/FacetBench`, follow the existing workload contract exactly — study `workloads/*.luau` + their specs). Flagship: **`nameplates`** — WoW-style, 50–200+ world-anchored plates whose screen positions update EVERY frame (model camera→world projection in the seeded script so all position props change per step), plus range enter/leave churn, health-bar waves, threat flips, cast sweeps. This is the all-dirty class. Add ≥1 more real-game shape the nameplate work shows is unmeasured. All must run in both Lune + Studio modes and measure facet vs **vide** (the speed target) honestly.
2. **Optimize Facet** against those numbers — attack the O(N) walk and the all-dirty class. Get per-frame cost on these workloads well under 1ms; approach vide's ~0.02ms/step on the update path. Candidate directions (evaluate, don't assume): batched per-frame position writes, a transform/position-only fast path skipping measure+arrange, engine-delegated positioning, a "moved-not-resized" solve tier. Let the profile pick.
First warm-up fix (booked, real, user-visible): `propSigCache` recycles instances wearing style props they never declared (RED-TEAM finding 3 in the notes).

## Method (non-negotiable — this is why the last campaign's numbers are trustworthy)
Profile first, never guess. Each fix ships a **red-first COUNTER demonstrator** (extend `work.*`/`stats()`; never wall-time asserts — the Luau VM is bimodal, use median-of-K) + a **differential oracle** proving pixel-identical output vs a forced full solve across the device matrix incl. 320x640. The **prop→dirty-class completeness audit is load-bearing** (a "paint-only" prop read as a layout input was this campaign's hardest bug — extend the audit, don't trust a grep). Gates before every commit: `tools/test.sh` full green; `tools/verify.sh affected --jobs 1` FOREGROUND (never background/`--jobs>1`); `check_source_size.py` (solver frozen at 861 chars — extract a LIVE seam first, audit the ledger for stale triggers); stylua. RascalRally suite + milestone canary every Facet src change; no public API/behavior change without the user. Fresh-context adversarial review per fix + a RED-TEAM at the end — that is where the quality came from; budget for fix rounds. Use subagents liberally; keep main context clean.

## Done when
The nameplate + new workloads exist and measure facet vs vide in both modes; Facet is materially faster on the all-dirty class (state achieved per-class numbers vs targets — a miss stated plainly with its named bottleneck and next lever beats a softened win); full gate green; RR lockstep + clean canary; public before/after + chart updated keeping the campaign numbers as "before". Honesty over optimism at every step.

You are operating autonomously — the user isn't watching live and can't answer mid-task, so don't ask permission for work already requested; proceed on reversible steps, stop only for destructive actions or genuine scope changes. If a question arises, do everything not blocked on it, then state your assumption. Don't end a turn on a plan or a promise — do the work. If compacted, preserve exactly: constraints/decisions/numbers/file:line/shas and where things stand. Start by brainstorming the workload designs and optimization approach before writing code.
