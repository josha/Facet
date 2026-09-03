# Goal: Facet parity — change how rects are written (Plan C)

Fresh Claude Fable 5.1 session, effort **high**. A GOAL, not a plan: read the docs, brainstorm + write the code-level SDD plan, then execute autonomously to done.

## Read first
- `GameStudio/ui/Facet/docs/superpowers/specs/2026-09-03-facet-parity-design.md` — the authority (assessment, design, oracle, risks).
- `GameStudio/ui/Facet/docs/plans/2026-09-03-facet-parity-plan.md` — task plan C0, C1, C6, C2, C3, C4, C5, C9 with files + counters. Turn it into `docs/superpowers/plans/2026-09-03-facet-parity-C.md` (writing-plans format, full code) before any code.
- `GameStudio/ui/Facet/docs/plans/2026-09-02-facet-wicked-fast-reference.md` — method + traps, still binding.
- Plan B's after-picture `GameStudio/ui/FacetBench/docs/studio-runs/2026-09-02-wicked-fast.md` = this campaign's "before".
- `memory/facet-wicked-fast-campaign.md`, `tasks/lessons.md`.

## The problem
A nameplate move (`offsetX/offsetY`) re-bases and rewrites EVERY descendant rect (1,488 setRects for 250 plates; the engine tree is flat, so each is a real Position write). vide writes one Position per plate. nameplates tick: Facet 5.39 ms Lune vs vide 0.29 live. A 1-leaf update on battle_hud costs ~2.5 ms live because measure visits every node, arrange re-enters at the root stack, and eight commit walks scan siblings. Targets: update ≤0.5 ms, structural ≤1 ms, live at L.

## The design (spec §5)
1. **A host is a coordinate space.** A container with reactive placement + children registers as an instance host; rects beneath it are stored host-relative; `rectOf`/`screenRectOf` compose on read (like `scrollShift`), so public numbers do not change. Translate = one rect write + one engine write.
2. **Translate lane.** An all-placement tick solves nothing: `stats.solves = 0`, one `anchor_place` per host (the SAME function the solver uses), one setRect.
3. Then the walks: measure pruning (O1), stack arrange O(dirty), dirty-child index (O5), bounded z-order — each profile-gated (≥5 % of its class or booked).

## Operating rules
- Branch `facet-parity` off `wicked-fast-facet` (or main if merged). SDD: fresh implementer per task, task review, rulings in the ledger, ≤5 fix rounds, never amend.
- Profile first (C0). Red-first COUNTER demonstrators, never wall-time; every one pins `stats.solves = N`.
- Differential oracle after every driver step, both adapters, full matrix incl. 320x640: `rectOf`, `screenRectOf`, hit rects, focus, engine Position — byte-equal to a forced full solve.
- Solver and renderer are at the source cap: extract a LIVE seam in its own commit first (`tools/check_source_size.py`).
- Gates every commit, FOREGROUND, one lune at a time: `tools/test.sh`; `tools/verify.sh affected --jobs 1`; source size; stylua.
- RascalRally lockstep on every Facet src change: RR suite + milestone canary + `screenRectOf` pins on minimap/sponsor/recap screens before and after.
- Hosts cannot be recycled today: measure add/remove; add a "host" bucket if >5 % worse.
- No public API/behaviour change without the owner. Nothing merged/pushed; finish with the branch menu.
- Fresh-context adversarial review per fix; RED-TEAM at the end. Honesty over optimism: a miss is named with its mechanism.
- Subagents liberally (sonnet/opus for work, haiku for scouting); one task at a time; never end a turn on a plan or promise.

## Done means
Report `FacetBench/docs/studio-runs/2026-09-03-facet-parity.md`: per class, before / after / vide / target, Lune + Studio, ABBA, chart; nameplates tick ≤1.0 ms Lune with `solves=0` and `engineWrites≈250`; battle_hud/war_room/killfeed update classes ≤0.5 ms live or the miss named; oracle green on the matrix; suites above the Plan B floors; memory + lessons updated.
