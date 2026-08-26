# /goal — Facet phase-2 follow-ups: the punch list after the campaign

You are the controller resuming completed work. Primary repo:
`/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet`
(main, in place). Consumer (lockstep, constitution rule):
`/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/games/RascalRally/code`.

CONTEXT: the framework-gaps-phase2 campaign is COMPLETE — all 42 registry gaps terminal
(27 BUILT / 6 DISSOLVED / 9 DISPOSED), suites 7,445/0 Facet + 3,527/0 RR at close
(2026-08-23). Read FIRST, in order:
1. `.superpowers/sdd/framework-gaps-phase2/progress.md` — the campaign ledger; every
   ruling, trap, and open thread lives here. It is the resume point.
2. `.superpowers/sdd/framework-gaps-phase2/gap-registry.md` (42/42 states),
   `DIRECTOR-REPORT.md` + its wave-3 addendum, `LOOK-LIST.md`.
3. `.superpowers/sdd/framework-gaps-phase2/binding-context.md` — rulings R1-R23,
   ADR-0040 mechanics, command reference, commit discipline. Still binding.

## The punch list, in priority order
1. **The PS5 overlap bug** (top priority): REPRODUCED with screenshot evidence —
   showcase hud demo, PS5 emulator preset, URL-bar toggle → bottom feed overlaps the
   caption. Root cause narrowed to `src/layout/composition.luau`'s lane-budget accounting
   (top-anchored `exclusions` push vs bottom-anchored `bottomLeft` group). A HEADLESS RED
   CASE is staged in `task-fix4-report.md` — start there. Iron Law: isolate the root
   cause before fixing; red-first; fresh-context review after.
2. **Review sweep of FIX-2/FIX-3/FIX-4** (ruling Q1): three fix rounds shipped without
   reviewer seats under the quota ceiling. Dispatch one combined fresh-context review of
   their commits (packages/reports named in the ledger); route findings per the SDD loop.
3. **Director decisions pending — ask, don't assume**:
   a. Edge-padding DEFAULT flip: the `edgeFloor` knob shipped (ADR-0055); flipping the
      default breaks 21 real screens (casualty table in `task-fix4-report.md`). Only on
      the director's word, with an ADR-0040 row.
   b. Sipworks stamps pocket: tab (current) vs pinned-bottom-shelf feature (estimated in
      the G6 report/ADR-0045) — still unanswered.
4. **Device-owed register**: every `docs/handoff/*-OWED-LIVE-WORK.md` — 13 perf-row
   re-captures, device-matrix re-run, four ten-foot capture re-takes, ten-foot GetStyled
   checks (space.tight, textSize="fit"), RR canaries (R5: same-session capture).
5. **Parked minors** (DIRECTOR-REPORT addendum): raise two-in-one-flush + modal-raise
   tests, RR spec-file group retires, ADR-0040 register-pin table-driven cases, guide-
   catalog rows audit, presenter one-way-fit Readable, VTF fill mirror problem.
6. **Parked idea**: make the five reference apps reachable from the showcase menu.

## Process (proven this campaign — binding)
- SDD subagent flow: fresh implementer per task, fresh-context review, scoped re-reviews;
  briefs in the campaign workspace; ledger every ruling with cost-if-wrong.
- Every commit via `python3 tools/commit_isolated.py` — markers QUOTED FROM THE HUNK.
- Suites ONLY in content-pinned `tools/mkpair.sh` pairs, SEQUENTIALLY (concurrent runs
  truncate transcripts; full suite peaks 11-13 GB RSS). stylua scoped to changed files.
- Traps: rojo serves a STALE framework under a current game on this filesystem — probe a
  commit marker before trusting any Studio reading; stale studio_sync on :8642 serves old
  sources; GetStyled, never plain reads, for paint; injected input arrives as Touch.
- Paperwork: next ADR is 0056; next ADR-0040 row is B-31 (VERIFY against the register —
  it survived two ID collisions); surface ledger + api.md + guide catalog for every
  export; RR lockstep or clean-negative evidence every round.
- Never publish/push/package; never edit the frozen 0.6.0 flat baseline; rebuild places
  (`tools/build_places.sh` + `tools/build_reference_places.sh`) whenever behavior ships
  so the director can test.
- Respect any usage-quota ceiling the director states, and report to the director with
  concise, jargon-free language (they ruled: plain words, no p1/p3 shorthand — name the
  apps Glade/Cartwheel/Sipworks/Foyer/Wardrobe).
