# Goal: make Facet wicked fast — the all-dirty frame, toward Vide speed

> Point a fresh Claude Fable 5.1 session at this file. It is a GOAL, not a plan: read the ground truth, brainstorm and plan before touching code, then execute. Recommended effort: **high** (the default; step to xhigh only for the hardest attribution/design turns, and re-run an effort sweep — 5.1's effort levels don't match 5's). Everything below the "Session operating rules" heading is standing instruction for how to work; everything above it is the mission.

## The one-sentence mission
Extend FacetBench with the game-UI stress tests a real-time game engine must be fast at — a World-of-Warcraft-style **real-time nameplate** field being the flagship — then optimize Facet until per-frame cost on those workloads is well under 1 ms and, on the update path, approaches Vide's ~0.02 ms/step. Get it wicked fast.

## Where things stand (measured, not assumed — 2026-09-02, Facet @ 4d9e3aac / campaign closed at b5524466+)
A five-fix campaign (P1 measure cache, P2 hand-over rect map, P3 persistent node store, P4 changed-set commit, P5 boundary-rooted structural solves) already shipped. Clean paired (ABBA) numbers at size L, battle_hud, one-leaf update: **44.7 ms → 2.49 ms** (18x). Studio frame at L: **51 ms → 16.6 ms (~19 → 60 fps)**. Facet's Luau layout cost is now ~40% of the frame where it was ~90%.

**But the target was ≤0.5 ms/update and ≤1 ms/structural, and 13 of 20 step classes still miss it.** The campaign's own attribution names exactly why, and it is your starting point:

- **THE BOTTLENECK: a solve that measures and arranges NOTHING still walks all N nodes — ~0.969 ms at L, ~0.19 µs/node.** This is the last O(N) term on the update path. Every per-step cache now refuses O(touched), but the *walk that decides what to skip* is still O(tree). Read `FacetBench/docs/profiling/2026-09-01-attribution.md` and the campaign's per-fix reports under `GameStudio/ui/Facet/.superpowers/` history for the full split. The levers already booked (L1–L8) live in `GameStudio/ui/Facet/docs/superpowers/plans/2026-08-31-facetbench-plan2-3-notes.md` — read that file first; it is the charter.
- **The all-dirty-every-frame class is unattacked and is the hardest.** When every node's inputs change each frame (nameplates: world→screen projection feeds a position prop per plate per frame), `dirtyContains` covers everything, P3's node store refuses, and the frame pays a near-full rebuild — the caches buy nothing. This is the class your new stress tests must expose and your optimization must crack. Candidate directions (yours to evaluate, not prescribed): batched per-frame position writes, a transform/position-only fast path that bypasses measure+arrange when only offsets change, delegating pure positioning to engine layout objects, a "moved but not resized" solve tier. Let the profile pick.

## What to build

### 1. New FacetBench stress workloads (the arena is at `GameStudio/ui/FacetBench`)
Add game-UI workloads following the existing contract exactly (framework-neutral scene + seeded deterministic script; cycle-safe; per-workload spec with pinned step-mix counts; register in `workloads/registry.luau`). Study `workloads/battle_hud.luau`/`war_room_inventory.luau`/`killfeed_nameplates.luau` first. Build at minimum:
- **`nameplates` (flagship, the all-dirty class):** 50–200+ world-anchored plates whose screen positions update EVERY frame (model a camera+world projection in the seeded script so all plates' position props change per step); plus range-based enter/leave churn, health-bar waves, threat-color flips, and cast-bar sweeps. Sizes scaling plate count. This is the workload that must reach "wicked fast".
- At least one more real-game shape you judge valuable and that a game UI must be fast at (e.g. a damage-number fountain, a scrolling combat log at high event rate, a minimap with many moving blips, an inventory grid drag-reorder). Pick from what the nameplate work teaches you is unmeasured.
Every new workload runs under BOTH the Lune matrix and (where it mounts) the Studio runner, produces honest rows for facet + rivals, and the rivals' adapters must express it idiomatically or declare it unsupported — never shim. Vide is the speed target; make sure the arena measures facet against vide on these.

### 2. Optimize Facet against those numbers
Attack the named bottleneck and the all-dirty class. This is production code with a live consumer (RascalRally) — the discipline below is not optional.

## The proven method (this campaign's discipline — follow it)
1. **Profile first, guess never.** Every fix names its mechanism with file:line and a measured before/after. The `FacetBench/tools/profile/` harnesses (monkey-patch attribution, honest control arms) are your instrument; extend them.
2. **Red-first demonstrator per fix:** a COUNTER-based test (extend the `work.*` / `stats()` families) asserting the O(touched) bound the fix creates, shown RED at pre-fix HEAD, committed WITH the fix. Never wall-time asserts (the Luau VM is bimodal on bare loops — see the loop-shape lesson; use median-of-K interleaved windows and immune loop shapes for any ratio).
3. **Differential oracle:** every layout-affecting change proves pixel-identical output vs a forced full solve across the device matrix INCLUDING 320x640. Caches need a differential oracle, not self-agreement — this campaign's memo shipped wrong twice historically for lack of one.
4. **The invalidation-completeness trap is real and cost this campaign its hardest bug:** a prop declared "paint-only" was read as a layout input, so a cache served stale geometry forever. If you add or touch a cache, the prop→dirty-class table and the `layout_node` reads-vs-declared audit (`tests/layout_prop_dirt.spec.luau`, the mechanised src_tree scan) are load-bearing — extend them, don't trust a grep.
5. **Gates before every commit:** `tools/test.sh` full green; `tools/verify.sh affected --jobs 1` FOREGROUND (never background — the lock orphans; never `--jobs>1` — producer race); `python3 tools/check_source_size.py` (SOLVER IS AT 861 CHARS — it is frozen; any solver change extracts a named seam FIRST, and AUDIT the ledger's other rows for stale triggers, two were already dead); stylua.
6. **RascalRally lockstep (constitution):** every Facet src change runs RR's suite as compatibility evidence and, at milestones, a live Studio canary (RR consumes `Facet/src` directly; read `games/RascalRally/CLAUDE.md`). No public API or behavior change without the user's word.
7. **Adversarial review at each fix and a RED-TEAM at the end** — this campaign's reviews caught engine-crash bugs, stale-cache wrongness, and false gate rows that the implementers missed every time. Budget for fix rounds; they are where the quality is.

## Known traps (paid for already — don't re-pay)
- Lune rejects requires ending in "init"; `@self/` inside init files; use directory/registry form.
- Bare accumulate-only numeric loops run at two speeds under Lune (~2.6x) — bounded-reset branch immunizes; median-of-K for ratios.
- Studio: string requires work in real ModuleScripts (not the command-bar VM); the yardstick is unusable in-engine (drift to 105% — don't trust *Norm there); `warn` writes to STDOUT; HttpService blocked in this channel (console-dump+checksum transport); an empty place kills the character every ~7s and respawn WIPES PlayerGui mid-measurement (CharacterAutoLoads=false + a host-alive guard); a rojo-BUILT RR place double-boots the client (game-side bug 878375e); probe a commit MARKER before trusting any Studio reading.
- Measurement machine carries variable load (a backup app) — capture on a quiet machine, gate committed baselines on drift, and pair (ABBA) the headline before/after so day-to-day variance cancels.
- FIRST BOOKED FIX CANDIDATE: `propSigCache` recycles instances that wear style props they never declared (RED-TEAM finding 3, pre-existing) — a real user-visible correctness bug, good warm-up.
- `tools/verify.sh affected --jobs 1` on a CLEAN tree selects nothing ("no changed paths against HEAD", 2 s) and evaluates no producer — run it BEFORE committing, or use `tools/verify.sh fast --jobs 1` as the HEAD attestation.
- RascalRally's `./run-tests.sh` writes no durable artifact — tee the transcript and record the pass count in a committed doc.

## Definition of done
The nameplate and new stress workloads exist, run in both modes, and measure facet vs vide honestly; Facet is materially faster on the all-dirty class than campaign-close (state the achieved per-class numbers vs the ≤0.5/≤1 ms targets — and if a class still misses, name the remaining bottleneck with evidence and book the next lever, never soften the workload or instrument to claim a win); the full gate is green; RR lockstep holds with a clean canary; the public before/after story and chart are updated keeping the campaign's numbers as the "before". Honesty over optimism at every step — a missed target stated plainly is worth more than a met target that isn't real.

---

## Session operating rules (Fable 5.1)

You are operating autonomously. The user is not watching in real time and cannot answer questions mid-task, so asking 'Want me to…?' or 'Shall I…?' will block the work. For reversible actions that follow from the original request, proceed without asking. Stop only for destructive actions or genuine scope changes the user must decide. Offering follow-ups after the task is done is fine; asking permission before doing the work is not.

Exception: when the user is describing a problem, asking a question, or thinking out loud rather than requesting a change, the deliverable is your assessment. Report your findings and stop. Don't apply a fix until they ask for one.

Before ending your turn, check your last paragraph. If it is a plan, an analysis, a question, a list of next steps, or a promise about work you have not done ('I'll…', 'let me know when…'), do that work now with tool calls. That includes retrying after errors and gathering missing information yourself. Do not stop because the context or session is long. End your turn only when the task is complete or you are blocked on input only the user can provide.

Before running a command that changes system state (restarts, deletes, config edits), check that the evidence actually supports that specific action. A signal that pattern-matches to a known failure may have a different cause.

The user's request — or the plan they approved — sets the scope, and the scope is the deliverable: don't quietly narrow, widen, or swap it. Read ambiguity the way a careful colleague would: make routine judgment calls yourself, and check in only when different readings would lead to materially different work. If you see a real problem with the task as specified, say so in a sentence or two and keep building under stated assumptions; if the user hears the concern and reaffirms, that is their decision, so deliver the full request. If a question comes up partway, first do everything that doesn't depend on the answer; then state the assumption you made, or — when going ahead on a wrong guess would be unsafe or make the work useless — put the question at the end of a turn that also delivers that progress. If one part is blocked, complete every other part in full and say exactly what you left out and why.

If, while working, you find a pre-existing bug or behavior the task doesn't mention, don't fix or extend it in this change unless the requested behavior cannot work without it; report it as a follow-up in your summary. This is about extras only: implement every behavior the task asks for, completely. Commit tests only where the task asks or the repo already keeps them for this kind of change, sized like neighboring test files — but note this repo's demonstrator discipline DOES ask for a counter-based test per fix, so those are in scope.

Minimize tokens spent editing files: surgically edit rather than rewrite a whole file when it won't change the result.

If your work is compacted into a summary, preserve exactly: (1) difficulties and how they were resolved; (2) approaches tried or set aside and why; (3) anything asked for, decided, ruled out, or set as a constraint — stated exactly; (4) exactly where things stand; (5) anything still open or promised; (6) hard-to-reconstruct specifics — file:line, numbers, commit shas, exact wording — kept exactly. Be complete on these even at length; condense your own reasoning to what it concluded.

Use subagents liberally for parallel research/attribution and for fresh-context adversarial review — this campaign's quality came from a fresh reviewer adversarially checking every fix and a RED-TEAM at the end. Keep the main context clean; hand artifacts (diffs, reports) as files.

Start by brainstorming the workload designs and the optimization approach before writing any code or entering plan mode.
