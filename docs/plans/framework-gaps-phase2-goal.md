# /goal — Facet phase 2: close ALL the framework capability gaps

You are the controller for a directed mission on the Facet UI framework.
Primary repo: `/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet`
(work on `main`, in place). Consumer repo (moves in lockstep, constitution rule):
`/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/games/RascalRally/code`.
Read first: the root `CLAUDE.md` (studio constitution, the Facet↔RascalRally
lockstep rule), `GameStudio/ENGINEERING.md`, and in the Facet repo:
`artifacts/release-candidate-review/framework-gaps.md` (the binding gap list —
each gap carries its audit evidence), `docs/handoff/SOURCE_CAP_LEDGER.md`
(size-frozen-file discipline: an owed extraction PRECEDES any edit to a file in
its band), and `.superpowers/sdd/release-candidate-review/progress.md` (the
prior campaign's ledger — rulings R1–R23 and ADR-0040 rows B-1..B-19 bind you;
ADR-0041 binds hit floors; the release stays version 0.10.0 and pre-release
breaking changes ride it WITH an ADR-0040 row each, ruling R15).

## The scope (director order, 2026-08-22): ALL 34 gaps

`artifacts/release-candidate-review/framework-gaps.md` is the complete binding
list — 11 gaps in detail plus 23 in brief, distilled from 97 consumer sites.
**Every one of the 34 ends this mission in exactly one of two states:**

1. **BUILT** — the default. Shipped API, ADR'd, taught, consumers migrated.
2. **DISPOSED with measurement** — only where building is genuinely wrong
   (the audit over-reached, the gap dissolved under a sibling gap's fix, or
   the honest API is worse than the workaround). A disposition requires the
   same evidence bar a build does — measured, red-first where a claim is
   testable — and every disposition lands on the director's veto list in the
   final report. "It was hard" is not a disposition.

Work in waves: the six below FIRST (director-ranked, highest pain), then the
remaining five detailed gaps (§3, §5, §6, §7, §11 of `framework-gaps.md`),
then the 23 in-brief ones — batching coupled gaps into shared rounds where one
seam answers several (the audit marks the couplings). Expect several of the 23
to dissolve into the detailed fixes; prove it per gap, never assume it.

The first six, chat numbering mapped to `framework-gaps.md` sections:

1. **App-namespace theme metrics** (audit §1): a game must be able to declare
   `metrics.<app>.*` entries that ride the theme system — validated, dumped,
   and DISTANCE-SCALED by the ten-foot ladder like built-ins. Four independent
   consumer shims exist today (two showcase reference apps, RR `TableMetrics`,
   RR `ResultsParts`); all four must migrate onto the new channel and delete
   their shims in the same round.
2. **`Facet.text` fit as a declarative prop** (audit §10): shrink-to-fit as a
   Text/label property, not a helper call. RR holds four hand-rolled copies of
   the fit arithmetic and THREE ARE WRONG (one uses 1.25 against its declared
   1.2; none applies `typographyScale` — up to 1.5× under-reserve on TV).
   The prop must be typographyScale-correct by construction; the four RR
   copies migrate and their wrongness becomes red-first evidence.
3. **`ViewThatFits` × the ten-foot ladder** (audit §2): a `hug` child silently
   pins the ladder's first rung forever, defended today only by prose comments
   in four files. Either support it honestly or refuse it loudly
   (refuse-don't-guess is the house doctrine); a value-form is the audit's
   suggested shape. Whatever ships, the silent-breakage path must become
   impossible, red-first at a non-1.0 scale.
4. **Self-measuring list viewports** (audit §4): `newVirtualList`/`VirtualGrid`
   measure the box they were given instead of demanding a window number.
   `Table` already does this privately (~30 lines of commentary in its source
   name the technique) — promote, don't reinvent. Consumer literals like the
   fixed windows the prior campaign kept fixing (the "336" class) migrate off.
5. **HUD band policy** (audit §9 + §8): `rootPolicy` is a three-value enum in a
   four-case world and `bandInsets` ships with no policy applying it; the hud
   fixture's ~150-line hand-rolled version is currently better than the
   framework's. Ship the real policy; the fixture's version becomes a consumer
   of it (delete the hand-roll, keep its behavior as the spec).
6. **The missing spacing step** (the `gap = 6` finding): wanted 61 times across
   25 files; the framework routes around its own missing step through a private
   channel. Add the token to the scale (name it per the scale's own naming
   doctrine; it must ride the ten-foot ladder like its neighbors). The purity
   lint already carries this as a PENDING finding — the day the token exists,
   ~60 sites redden for conversion; sweeping them to the new token is part of
   this gap, each swap value-identical at neutral (and mind the day-2 lesson:
   value-identity is a scale-1.0 guarantee — check coupled constants at the
   ten-foot rung, the lint's coupledConstants detector names them).

The focus-ring thickness metric (`t16-triage.md` row — two packages have a 4px
ring against 3px reserved room; layout cannot see the ring's size) joins the
list as gap 35 — same two-state rule.

## How to run it

- This is a CAMPAIGN, not a round: keep the ledger discipline the prior
  campaign proved (a progress ledger under `.superpowers/sdd/<mission>/`,
  every ruling recorded with cost-if-wrong, per-wave closure entries) — with
  34+ gaps you WILL be compacted mid-mission, and the ledger is what survives.
- Subagent-driven: one implementer round per gap (or honestly-coupled groups),
  fresh-context review after each, scoped re-reviews on fix rounds — the SDD
  flow in `.claude`/superpowers. Every round red-first; every claimed mutation
  proven to bite; suites measured ONLY in content-pinned copies via
  `tools/mkpair.sh <dest> <facet-ref> <rr-ref>` (refs resolved at MEASUREMENT
  time — a dispatch-time sha fabricates reds that survive A/Bs). Concurrent
  writers use `python3 tools/commit_isolated.py` for every commit.
- Each gap is public API: one ADR each (or one per coupled pair), an ADR-0040
  row if it changes shipped behavior pre-publish (R15), `check_surface_ledger`
  fed for every new export, `docs/reference/api.md` taught, and the RR consumer
  migrated in the same round with its own red-first evidence (no manufactured
  churn where RR genuinely doesn't consume — evidence instead).
- Size-frozen discipline: check `docs/handoff/SOURCE_CAP_LEDGER.md` before
  touching `src/client/screen_target.luau` (owes the vocabulary extraction on
  next open), `src/present/presenter.luau` (extraction owed), or
  `src/controls/virtual_list.luau` (805 chars from its trigger — gap 4 lands
  HERE, so its extraction, the hosted block per the ledger's analysis, comes
  FIRST in that round).
- Gates: run `python3 tools/check_gate_pins.py`, `check_manifest_integrity.py`,
  and the purity lint (`check_theme_drift_cli`) at every landing; the always-on
  containment invariant and the overflow sweep will judge your geometry free.
- Studio verification: the live half runs in the open Facet-Showcase place via
  the studio_sync inject pattern (`tools/lune/studio_sync` + the inject snippet
  in `tools/studio/inject.luau`); durable captures via
  `tools/studio/capture_viewport.sh` (never full-screen). Gap 2 and 6 deserve a
  ten-foot on-glass check (GetStyled, never plain reads).
- Do NOT publish, push, or package anything; publishing is the director's
  manual click. Never edit the frozen 0.6.0 flat baseline; additive vocabulary
  changes go through `ALLOWED_ADDED_SUBKEYS` with a mutation proof.
- Report to the director at the end: a per-gap table (all 35: BUILT or
  DISPOSED-with-evidence), every ruling made (with cost-if-wrong), every
  disposition for veto, suite tails both repos, and what the device half owes.
  Interim reports at each wave boundary so the director can redirect early.
