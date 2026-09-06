# Goal: Facet parity Plan D — the remaining per-class misses

Fresh Claude Fable 5.1 session, effort **high**. A GOAL, not a plan: read, write the code-level SDD plan, execute autonomously to done.

## Read first
- `GameStudio/ui/FacetBench/docs/studio-runs/2026-09-03-facet-parity.md` §after — the authority. §2 = the 29-row table; §6b = every miss by mechanism; §9 = the booked list.
- `GameStudio/ui/Facet/docs/plans/2026-09-06-facet-parity-landing.md` — where Plan C landed; the lever list with its evidence.
- `GameStudio/ui/Facet/docs/superpowers/plans/2026-09-03-facet-parity-C.md` §As built, `memory/facet-parity-campaign.md`, `tasks/lessons.md` (2026-09-05/06 entries binding).

## The problem
Plan C cut every leaf-edit class 40–58 % headless and met the tick pin, but 17 of 29 classes still miss: update ≤0.5 ms live MET 4/12, structural ≤1 ms live MET 4/13. Live = `Lune × 1.37 (host) + 0.129 ms (floor)`, so 0.5 live ≈ 0.27 Lune. `battle_hud updateItem-hp` 1.008 Lune / 1.539 live; `war_room setState` 1.832 / 1.942. The 47–84 ms wide-key settle is the largest millisecond left.

## Work, in order — each PROFILE-GATED (ships only if its counter goes red-first and a three-arm ABBA moves the class)
1. **Attribute first, at HEAD.** T9b's method: per-span `attr`, three arms incl. a control, on `battle_hud updateItem-hp`, `war_room setState`, `damage_fountain updateItems-numbers`, beside vide. §before's span table: seven `cw.*` commit walks at a FLAT ~0.07 ms each + `rectPass.apply` 0.083 + `build` 0.122 on a ONE-LEAF edit. If any walk is still O(live nodes) at HEAD, one dirty-scoped (or fused) commit walk is the first lever. Price the MARGINAL call, never calls × average. Rank levers (counter moved + expected gain) BEFORE building.
2. **The wide-key settle** (§9 #2): over `max(64, nodes // 8)` paths the settle is a whole-tree cold solve. Build right-AND-fast: a word is a TOKEN shared across labels (§C16 fix round 1), so the narrow route must re-solve every label drawing a corrected token, then re-sweep the cutoff. Never reintroduce the wrong-and-fast route. Same area: the boot-window drain learns ONE word per round (each learned width pulls the next unmeasured row into the measured set; ~52 ms/round on L) — batch the surface's whole unmeasured vocabulary in one round.
3. **Tree-size-bound residue** (§6b class 2): whatever is still O(children)/O(tree) per leaf edit in `layout_node.build` (§7.3's `toLayoutNode`), measure, arrange. `crossMax` measured 1.9 % — leave it unless step 1 says otherwise.
4. **Structural classes**: O(shifted) with a per-rect `applyOne + setRect` constant; vide's honest bound is 5.3x (reorder 36.5 vs 6.9 live). Attack the constant, not the count; `ssZOrder` on `reorder` is still 3.485 ms.
5. **mountMs** 3–5x vide (§9 #15, never attacked): attribute, then decide.
Skip the prefix rebase (§C12: buys nothing) unless step 1 reopens it. Booked, not perf: `SOLVE_FEEDBACK_ROUND_CAP` still raises out of `refresh`.

## Rules (all standing from Plan C)
No public API change. Observables byte-identical: the three-observable differential vs the parent commit, plus an oracle that does NOT share the mechanism's switch (§11). ABBA with a THIRD control arm; one lune process at a time; gates in the foreground with long timeouts. `renderer.luau` is AT the 197,500 Source STOP line: seam first. RascalRally lockstep every task (contract test + Studio canary, floor 3,599/0). Measure the SETTLED session in a FRESH client VM per workload. `tools/verify.sh full` before every close (then `git checkout -- examples/places/`). RED-TEAM at the end. Register a FacetBench §Dn per task. Owner rule: a class still well over target after the planned tasks gets an assessment and more levers before close-out, never a named miss.

## Done
A §after-2 table (29 classes: before/after/live/vide/verdict), every miss with its mechanism, gates green in all three repos, nothing merged or pushed, a branch menu.
