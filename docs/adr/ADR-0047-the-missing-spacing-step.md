# ADR-0047 — `space.tight`, the missing spacing step

**Date:** 2026-08-23
**Status:** Accepted
**Number:** 0047. 0040 is the unreleased-breaking-changes register; **this
decision adds one row there — B-25**, for the two G4/G5 fixtures whose gutter
restores from a forced 4px to the intended 6px. The token itself is additive
(§"Not a breaking change" below) — the same shape ADR-0043's `gutter`/derived
metrics used.
**Companions:** [ADR-0019](ADR-0019-theme-packages.md) §2 (the metric
vocabulary this scale belongs to), [ADR-0039](ADR-0039-ten-foot-metric-ladder.md)
(the ladder this step rides), [ADR-0043](ADR-0043-collections-measure-and-name.md)
§3 (`gap_metric`, the VirtualList/VirtualGrid channel this step is legal in),
[ADR-0040](ADR-0040-unreleased-breaking-changes.md) row B-25.
**Home:** `src/themes/package.luau` (`DERIVED_SPACE_STEPS`/`SPACE_STEPS`),
`src/themes/snapshot.luau` (`resolve`'s derivation, beside `space.gutter`),
`tools/lune/check_theme_drift.luau` (the purity lint whose PENDING finding this
resolves).
**Guards:** `tests/space_tight_step.spec.luau` (the token's own contract),
`tests/ten_foot_metrics.spec.luau` (`"space.tight"` rides the proportion-equality
sweep at ten-foot), `tools/lune/check_theme_drift_cli` (the sweep census).

## Context — a private channel, quoted verbatim

The declarative-purity audit (2026-08-21) found `gap = 6` wanted 61 times
across 25 files in the teaching corpus, plus the framework's own
`controls.label.gap = 6` (`src/themes/snapshot.luau`). The spacing scale's five
required steps — `xs` (4), `s` (8), `m` (16), `l` (24), `xl` (40) — have no
rung between the two smallest, so every one of those sites spent a raw pixel
count because there was nowhere else to point it. `tools/lune/check_theme_drift.luau`
carried this as a documented, deliberate exemption rather than a violation —
its header said so verbatim: *"`gap = 8` is a violation because `"s"` is 8;
`gap = 6` is not, because no space step is 6 and there is nothing to rewrite it
to... That is not a loophole, it is a pending finding: the day the spacing
scale grows a rung for 6, this lint starts failing all sixty of those sites for
free."*

Re-counted at execution time (framework-gaps-phase2's TabView, solver and HUD
rounds rewrote several of the 25 files since the audit): **62 sites across 25
files** — one more than the audit's count, same shape.

**Two gallery fixtures already knew the shape of this gap and paid for it.**
The G4/G5 round (`virtual_grid.luau`/`virtual_hgrid.luau`, task G4G5) needed a
theme-tracking gutter for two collections whose `gap`/`rowGap` had refused a
string until that round. It wanted 6 and could not have it — its own report
states the measurement: *"No metric in any shipped package resolves to 6...
The two grid fixtures therefore move 6 → 4 (`"xs"`) at neutral."* A deliberate,
recorded value change, made because the token this ADR adds did not exist yet.

## Decision

### 1. The token: `space.tight`, derived as the midpoint of `xs` and `s`

```lua
if type(out.space.tight) ~= "number" then
	out.space.tight = (out.space.xs + out.space.s) / 2
end
```

Placed in `snapshot.resolve`, immediately beside `space.gutter`'s own
derivation, and for the identical reason: **authored beats derived**. A
package that declares its own `metrics.space.tight` wins outright; every other
package gets the midpoint of its OWN `xs`/`s` — 6 at Studio Neutral (4, 8), and
correspondingly different under any package that re-ladders either neighbour.
**Not baked into the neutral DEFINITION** (`src/tokens/default_style.luau`
stays untouched) for the reason every derived metric in that file's orbit
already carries: an authored `metrics.space.tight` entry would move the
authored metrics — and therefore the CONTENT STAMP — of every package derived
from Studio Neutral, for a value no package wrote. `gutter`, `controls.
rowActions.trayGap`, `controls.rowActions.rowGutter` and `controls.progress.
spinnerDotSize` all made the same choice, all for the measured reason recorded
at their own sites.

It rides `package.DERIVED_SPACE_STEPS`/`SPACE_STEPS` beside `gutter`, which is
what makes it legal wherever a space step already is: `snapshot.isSpaceStep`,
`resolveNumber`, the blueprint boundary's refusal message, and — because all
three read the SAME list — the `gap`/`rowGap`/`padding`/`px=` channels and the
VirtualList/VirtualGrid `gap_metric` module (ADR-0043 §3) for free. Proved
directly in `tests/space_tight_step.spec.luau`: a blueprint `gap = "tight"`
prop, a `gap_metric.reader({ value = "tight" })` call (the exact seam
VirtualList/VirtualGrid spend), `isSpaceStep`/`resolveNumber`, an authored
override, and the ten-foot rung (`space.tight` is 9 at `displaySize =
"Large"`, `metricScale = 1.5` — `tests/ten_foot_metrics.spec.luau`'s
proportion-equality sweep now walks `"space.tight"` beside `"space.gutter"`).

### 2. Naming doctrine: `tight`, not a repositioned letter

The brief's instruction was to read `src/tokens/` for the scale's own naming
pattern and follow it without inventing a new class. The five REQUIRED steps
are a closed, five-symbol vocabulary of relative-size letters — `xs`/`s`/`m`/
`l`/`xl` — with no established convention for a rung strictly *between* two
adjacent letters (industry T-shirt scales that subdivide do it by adding
`2xs`/`3xs` *below* the smallest symbol, never between two already-named
ones; this scale's own five symbols do not even follow a clean
doubling — `xs=4, s=8, m=16, l=24, xl=40` — so there is no numeric pattern to
extrapolate from either).

But this repository already answered the harder version of this question,
twice, before this round: **every step added to a ladder AFTER its initial
five shipped took a semantic, role-describing word instead of a repositioned
letter, and was DERIVED rather than authored in the neutral definition.**
`space.gutter` (the screen-edge floor) is the space ladder's own precedent,
verbatim in `package.luau`: *"a sixth, DERIVED space step"*, named for what it
is FOR. One ladder over, `type`'s `strong`/`numeral` (`package.
OPTIONAL_TYPE_ROLES`) did the same thing to the six required type roles —
added later, named for their role (emphasis, a glanceable figure), derived
when unauthored. `tight` follows that established doctrine rather than
inventing a third naming class: it names what the step is FOR — a gap tighter
than the default `s` reading, which is what the swept corpus overwhelmingly
uses it for (icon/label pairs, chip rows, compact HStacks/VStacks across
branch_scope, adaptive_controls, canvas_group, sensory_feedback and sixteen
other files — a generic "closer than `s`" spacing value, not a single
control's private constant). The word itself is already idiomatic in this
codebase's own prose (`default_style.luau`: *"a tight drop that actually
READS"*; `level_picker.luau`, `rating.luau`, `tab_view.luau`: "the tighter of
the two runs/chrome") and collides with no existing token name in any section.

## The sweep

Re-counted at execution time against `check_theme_drift_cli`'s own report
(the corpus moved since the audit): **62 sites across 25 files.**

| outcome | count | detail |
|---|---|---|
| **converted** | 55 | mechanical `gap`/`padding` literal `6` → `"tight"`, value-identical at neutral (6 == 6) on every site, across 23 files |
| **handed off** | 6 | `examples/gallery/scenarios/hud.luau` — the HUD round (G8+G9)'s territory per the campaign's concurrent-lane rule; listed here rather than edited |
| **refused, documented** | 1 | `examples/themes/fantasy_parchment.luau:212` — a theme PACKAGE's own `metrics.controls.label.gap`; `package.luau`'s `CONTROL_FAMILIES` validation is `isFiniteNumber`-only for this field, so it cannot legally take a string name. Marked `-- THEME-OPT-OUT` naming the reason (the same one `default_style.luau`'s own `controls.label.gap` has — see §"What did not move" below) |

**Coupled-constants check (the day-2 lesson — value-identity is a scale-1.0
guarantee only).** `check_theme_drift.luau`'s `coupledConstants` detector
flagged two files as carrying raw geometry-predicting constants alongside a
swept site: `hud.luau` (hand-off, untouched) and `perf_capture.luau`. Read at
the site: `perf_capture.luau`'s coupled constants (`ROSTER_ROW_PADDING`,
`viewportExtent=<literal>`) belong to a named, isolated block — *"THE ROSTER
ROW, in one place"* — that predicts a **different** control's geometry (a
200-row virtualized roster) entirely apart from the swept site (the
`"Readouts"` HStack's own `gap`). Verified no arithmetic anywhere in the file
reads the Readouts gap: the coupling is a same-file, different-subtree
false-positive shape, not a true pair, so the site converts normally rather
than needing a coherent joint move or a refusal.

### The two 4→6 restorations

`examples/gallery/scenarios/virtual_grid.luau` and `virtual_hgrid.luau`'s
`CELL_GAP`/`LINE_GAP` move from `"xs"` (4) back to `"tight"` (6) — the value
the G4/G5 round wanted and could not name. **A deliberate value CHANGE at
neutral**, not a value-identical rewrite: both gutters grow 4px → 6px in the
shipped gallery. Recorded as ADR-0040 row B-25 below. Neither file's
`coupledConstants` scan reports a coupled constant (verified: `LINE_EXTENT`/
`CELL_PADDING`/`LANE_CHOICES` are independent geometry, not predictions built
from the gutter), so the restoration costs nothing else.

### What did not move: `controls.label.gap`

`snapshot.luau:158`'s `label = { gap = 6 }` — the finding's own anchor quote
— is **deliberately left as a raw literal**, not repointed at `space.tight`
even though the two values are identical. Moving it into a resolve-time
derivation (the same shape `gutter`/`trayGap` take) would **remove** an
already-AUTHORED key from `neutralDefinition()`, and removing an authored key
moves Studio Neutral's package content STAMP exactly as adding one does — the
precise hazard this file's own `iconSizes`/`gutter` notes warn a *new*
addition away from, applying here to a *pre-existing* one. The comment at the
site is corrected instead (it no longer claims "no space step is 6"); a
package that wants this specific gap to track its own `space.tight` still can,
by authoring `controls.label.gap = "tight"` itself.

## Ladder proof (non-1.0 rung)

`tests/ten_foot_metrics.spec.luau`'s `"the text-to-control proportion at
ten-foot equals its near proportion"` case RED-FIRST: adding `"space.tight"`
to its `CONTROLS` list before the token existed failed with `attempt to
compare number < nil` (the leaf resolved to nothing at either display class).
After the derivation landed, the same case passes at 48/48 — `space.tight`
scales by the identical 1.5x factor every metric-ladder leaf does (6 → 9 at
`displaySize = "Large"`), because `space` is an unconditional
`DENSITY_LENGTH_SECTIONS` member and needed zero special-casing in
`snapshot.densityClassOf` or the density transform.

## flat-baseline (byte-compatibility)

`lune run tools/lune/check_flat_baseline` — PASS, **zero new waiver entries**.
Verified rather than assumed: `gap`/`padding`/`rowGap` are layout-internal
(they position children; they are never serialized into a node's `props`
string the flat-baseline dump compares), the eight fixtures that dump compares
are the seven numbered TUTORIAL examples plus `control-vocabulary` — none of
which contain a swept site — and `controls.label.gap` (the one framework-scope
site that DOES render inside `control-vocabulary`) was deliberately left
unmoved (§"What did not move" above), so that fixture's render is untouched
too. No `ALLOWED_ADDED_SUBKEYS`/`ALLOWED_ADDED_PROPS` entry was needed.

## What is breaking, and what is not

The **token** is purely additive — a new optional, derived space step, exactly
`gutter`'s shape. No existing package's compile, content stamp or resolved
snapshot changes for a value it never authored.

**Row B-25** is the one breaking-in-the-loose-R15-sense change: two shipped
gallery fixtures' rendered gutters grow 4px → 6px at Studio Neutral. Judged
against the B-18/B-14 bar (an example/gallery-visible geometry move earns a
register row even though no `src/` contract changed) rather than left
unrecorded, because a reader who tuned anything against the G4/G5 report's "6
→ 4" note needs to be told it moved back.

## Consequences

* The purity lint's PENDING finding is RESOLVED, not suppressed: it went
  GREEN → RED (62 sites, the moment the token existed) → **GREEN except the 6
  hand-off sites in `hud.luau`**, which the controller sequences after the HUD
  round (G8+G9) lands, per this campaign's concurrent-lane rule.
* RR lockstep: **one real site, refused with reason; the rest a clean
  negative.** RR authors no Facet blueprint `gap`/`padding`/`rowGap` prop as a
  raw `6` literal anywhere (`grep` for the exact `gap = 6,`/`padding = 6,`/
  `rowGap = 6,` shape returns nothing), but ONE of its `= 6` constants IS this
  token's channel and not a lookalike: `TableMetrics.luau:94`'s
  `listRowGap = 6` reaches `FacetSponsor/init.luau:2162`'s
  `rowGap = metrics.listRowGap`, which is a genuine `newVirtualList.rowGap` —
  the same `gap_metric` channel `space.tight` rides (`RacerList.luau:936`
  constructs the real `newVirtualList`, not a native `UIListLayout`). It
  stays raw, refused rather than migrated: RR's own comment names the coupling
  ("D1: legacy's 6 px gutter, so the SLOT is 62 and the row stays 56/60"), and
  `tests/facet_collection_extent_contract.spec.luau` already pins the NUMBER
  form as a deliberate, tested "spelling this package ships" — moving it to
  `"tight"` would let the gutter scale at ten-foot while that fixed SLOT/row
  arithmetic beside it does not, the exact coupled-constant hazard this round's
  own day-2 lesson warns against. Full reasoning:
  `docs/handoff/GSPACE-OWED-LIVE-WORK.md` §3. The other five `= 6` constants
  (`HudZoneModel.gap`, `GearDockModel.edgeGap`, `ResultsLayoutModel`'s
  `BAIT_ROW_GAP`/`HEADER_CHIP_GAP`, `SponsorGui.LIST_ROW_GAP`) DO feed native
  Roblox `UIListLayout`/manual-offset code in the pre-Facet Sponsor layer, not
  a Facet blueprint prop — outside this token's channel by construction, and
  `HudZoneModel`/`GearDockModel` are additionally the HUD round's territory.
* the brief's booked item 5 (relocate `TAG_PREFIX`/`ownsTag` into
  `src/tokens/sheet_model`, "the tokens lane is open now") is **MOOTED**, not
  skipped: SCREEN-X's `98a90f4` already relocated that exact ruling, before
  this round started, to `src/render/tag_sync.luau` — a deliberately BETTER
  home than the one either brief named, for a measured reason (`sheet_model`/
  `screen_vocabulary` cannot be required headlessly, so a spec could never
  drive the ruling from either). No action taken here; none was owed.

## Alternatives considered

* **Author `tight = 6` directly in `default_style.luau`**, matching how `xs`
  through `xl` are authored. Rejected: it would move Studio Neutral's own
  package content stamp (and every package derived `base =
  neutralPackage()`'s stamp with it) for a value most consumers never asked
  about — the exact regression `iconSizes`/`gutter`'s own comments record
  having caused and reverted once already.
* **A numeric/positional name** (e.g. a `"2xs"`-style symbol). Rejected: `2xs`
  conventionally means *smaller than the smallest* symbol, not *between* two
  already-named ones, and this scale's five symbols carry no clean numeric
  progression to extrapolate a position from — inventing one would be the
  "new naming class" the brief said not to.
* **Fold `controls.label.gap` into `space.tight`.** Considered, and declined
  for the content-stamp reason in §"What did not move" — the two already read
  the same number, so nothing about the finding's spirit is left unresolved by
  leaving the private channel's literal exactly where it is with a corrected
  comment.
