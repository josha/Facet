# Goal: Facet parity Plan E — reorder and remove on a list of row hosts

Fresh Claude Fable 5.1 session, effort **high**. A GOAL, not a plan: read, write the code-level SDD plan, execute autonomously to done.

## Read first
- `GameStudio/ui/FacetBench/docs/studio-runs/2026-09-03-facet-parity.md` **§after-2** (the authority: §2 table, §3.3 the structural mechanism, §5 booked) and **§D9.6** (rows as coordinate spaces, `mount.markRow`, the translate arm stopping at a host's own rect).
- `GameStudio/ui/Facet/docs/plans/2026-09-06-facet-parity-landing.md` §Plan D; `.superpowers/sdd/2026-09-06-facet-parity-D/progress.md` D4/D6a rows; `tasks/lessons.md` 2026-09-06/07 (binding).

## The problem
Live, settled, size L, `war_room_inventory` (1,500 rows × 5 boxes, rows are coordinate-space hosts since D6a): `reorder` **19.7 ms**, `removeItem-items` **8.3 ms**; target ≤ 1 ms; vide 7.7 / 4.3 (the engine slides its rows in C++). The engine's own cost is ~5–6 ms for the 1,467 row-position writes and is NOT this plan's — the Luau side is: `arrange` ~6.5 ms (~4 µs per row placing rows whose SIZES did not change), `measure` ~2.2 ms (asking 1,500 served rows a question a permutation cannot change), `ssZOrder` ~2.5 ms (a monotone renumber from the insertion point), `rectPass` own ~2.5, build/dirty/harvest ~2. Honest Luau floor for a pure permutation: new y per row from known heights + one write per row ≈ 1–2 µs a row.

## Work, in order — each PROFILE-GATED (red-first counter, three-arm ABBA with paired worktrees incl. a counter-only arm C, ships only if its class moves with the safety counters identical)
1. **Attribute first, at HEAD**: `attr war_room_inventory L 3` with FacetBench's `target.*` columns (the fake `setRect` is a third of the raw span and recomposes host subtrees — quote Facet's OWN share only), on `reorder` and `removeItem-items`. Rank the levers below by measured share BEFORE building.
2. **A pure permutation skips measure.** A structural refresh whose row set is unchanged and whose rows' props are unchanged re-uses every row's measured extents (`cmemo.mMain`/`mCross` already hold them); `lastMeasureCalls` on `reorder` 2,937 → ~0 is the red. Exactness: a row whose content DID change in the same frame is not a permutation — the differential oracle drives both.
3. **Arrange's per-row constant.** A stack of row hosts with known extents places by prefix sum: the replay's index (D2c/D3b) + the kept extents give each row's new y without the per-child protocol; counter `lastArrangeEntries`/`lastPlaceScanned` beside `span:Facet/arrange`. The prefix rebase (§C12) is the booked half — measure it now on THIS shape.
4. **Z-order per host.** `ssZOrder` renumbers from the insertion point to the end; with rows as hosts the renumber can be per-host (siblings inside a host keep their relative z); `zVisits` is the counter.
5. Then `removeItem-items` with the same three, then `killfeed`'s feed and `battle_hud`'s damage list (short shifts — say what each lever buys there).

## Rules (all standing)
No public API change. Observables byte-identical: `tools/lune/text_reentry_differential` md5 `6f14ec6b3e184809d8cef15094e6997b` (360 blocks; the fixture crosses row hosts) or every differing block explained, plus an oracle that toggles a DIFFERENT switch than the mechanism (`host_space_oracle` arm e / `structuralReuse=false` / forced full). One lune process at a time (`pgrep -x lune`). `renderer.luau` at 197,305 of the 197,500 STOP — seam first. RascalRally lockstep every task (the racer list is a list of row hosts: contract test + Studio canary; floor 3,602/0). Measure the SETTLED session in a FRESH client VM per workload. `tools/verify.sh full` before close (then `git checkout -- examples/places/`). RED-TEAM at the end. Register a FacetBench §En per task. Owner rule: a class still well over target after the planned levers gets an assessment and more levers before close-out, never a named miss — and state plainly that ≤ 1 ms needs the engine's list layout, which is the owner's architecture call, not this plan's.

## Done
§after-3: `reorder`/`removeItem` per workload before/after/live/vide/verdict with Facet's own share and the engine's share stated separately; every miss with its mechanism; gates green in all three repos; nothing merged or pushed; a branch menu.
