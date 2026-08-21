# ADR-0040 — Breaking changes may ride an unreleased version, if the record and the instrument both exist

**Date:** 2026-08-21
**Status:** Accepted
**Number:** 0040. 0039 is the ten-foot metric ladder; 0031 is a burned number
([ADR-0032](ADR-0032-nested-instance-tree.md) records why).
**Companions:** [ADR-0011](ADR-0011-semver-and-deprecation.md) (the versioning and
deprecation policy this qualifies), `docs/reference/constitution.md` §14 (which
declares ADR-0011 binding and now carries this ruling's clause),
`tests/api_surface.spec.luau` + `tests/lib/public_shape.luau` (the instrument),
`artifacts/release-candidate-review/adapt-audit/fixes.md` (where most of the
measurements below already live).
**Ruling:** controller ruling **R15**, 2026-08-21, from wave LAYOUT-FIX's fresh-context
review. Director veto open — see "Carried to the director".

## Context — a gate that was green over a hole

Wave LAYOUT-FIX made `UI.AdaptiveStack.axis` **required** and changed `UI.Grid`'s
undeclared **lane default** from one lane to the intrinsic measure. Both are
director-ordered fixes to critical paradigm findings, both shipped with red-first
specs and a green suite, and both turn code that worked at `0.10.0` into code that
does not work at `0.10.0` — a construction error in the first case, a silent
re-layout in the second.

**Nothing in the repository could see it, and that is the finding.** Three separate
mechanisms each had a reason not to fire:

* `blueprint_schema.deprecations()` emits a ledger row only for a prop carrying an
  explicit `deprecated` field. Making a prop **required** generates nothing at all.
* `tests/api_surface.spec.luau` enforced the ledger's *schema* and that ADR-0011
  names the current `VERSION` — which it still did, because nothing bumped.
* `VERSION` has been frozen at `0.10.0` for seventy commits across the whole
  release-candidate campaign, so "not bumping" reads as campaign practice rather
  than as an omission.

So the question is not "was this wave careless". It is: **what is the honest policy
for a pre-release library whose whole campaign is behaviour change, and what
instrument makes the answer checkable?**

## Decision

### 1. A breaking change may ride an unreleased version, with a record

ADR-0011's deprecation window — "a deprecated surface keeps working for at least one
MINOR after `since`" — is a promise to **published** consumers. `0.10.0` has not been
published: it is the version the release-candidate campaign is *building*, and every
consumer of it is inside this repository or is Rascal Rally, which moves in the same
task by the root constitution's own rule.

Therefore: **while a version is unreleased, a breaking change may land in it
directly, provided it is recorded here.** After the first publish of a version, the
full ADR-0011 window applies with no exception.

**A compatibility shim is explicitly NOT the answer for the two changes above**, and
the reason is not convenience. Both fixes exist *because* a silent default was the
defect: `AdaptiveStack` defaulting to `"y"` is a class named for adapting that could
be built unable to adapt, and `UI.Grid` defaulting to one lane is a card container
that ignored the box it was given. A shim that kept the old behaviour behind a flag
would re-ship the exact silence the refuse-don't-guess idiom was adopted to end, and
would have to be removed by the same argument that removed it. The record is the
obligation; the shim would be a second defect.

### 2. The record: what is breaking in the unreleased `0.10.0`

**Method, stated so the next reader knows what this is and is not.** This table was
built by reading the campaign's own artifacts (`fixes.md` and its three addenda, the
two paradigm matrices, ADR-0036/0037/0039) against the seventy commits between the
`0.10.0` bump (`8691380`) and this one, and by re-reading the diffs of the rows
marked *measured here*. **It is not a proof of completeness** — a behaviour change
with no artifact and an unremarkable commit subject would not appear. Decision 3 is
what makes the *next* one impossible to miss, and it is the half of this ADR that
does not depend on my reading.

| # | surface | what changed | why it is breaking | recorded |
|---|---|---|---|---|
| B-1 | `UI.AdaptiveStack.axis` | optional (default `"y"`) → **required** | a bare `UI.AdaptiveStack{…}` was a permanent VStack and now raises at construction | measured here; `tests/layout_defaults.spec.luau` |
| B-2 | `UI.Grid` with neither `columns` nor `minColumnWidth` | 1 lane at every width → `minColumnWidth = "intrinsic"` | a bare grid silently re-lays out — the same six cards go from one column to 2/4/6/9/5/7 across the audit's combos | measured here; `tests/layout_defaults.spec.luau` |
| B-3 | `newPicker`, `newMenu`, `newPopupButton`, `newTabView`, `newTextInput`, `newVirtualList` (`itemExtent = "cards"`) | each **refuses to construct** when no environment can be found | previously each silently substituted the large-screen / near-distance / no-cutout answer. Six controls, one line each: the refusal replaced *wrong* behaviour, not working behaviour, and the audit counted the consequence (0 of 17 shipped `Picker` sites reached the adaptive default). Rascal Rally, the only external consumer, migrated in the same wave | `44a495f`, `f3d2fe8`; `tests/adaptive_defaults.spec.luau`, whose refusal guard derives the set from the SOURCE rather than a hand-written list |
| B-4 | `adaptive.navPlacement` on a tablet | `bottomBar` → `topBar` | a documented policy answers differently for a real device class; six shipped assertions were re-pinned because they asserted the defect | `fixes.md` §2, with the full re-pin trail |
| B-5 | `adaptive.columnsFor` at ten-foot | uncapped → capped against `BREAKPOINTS.wide` | a television gets FEWER columns than a desktop where it used to get more | `fixes.md` Family B / ADAPT-23 |
| B-6 | unauthored text on a `Large` display | authored size only → the whole type ladder scales 1.5x | every screen written the natural way is 1.5x on a television | ADAPT-7 in `fixes.md`; [ADR-0039](ADR-0039-ten-foot-metric-ladder.md) |
| B-7 | every theme metric on a `Large` display | unscaled → scaled by the type floor's own factor | control heights, spacing, icon sizes and the 44px hit floor all move on a television | [ADR-0039](ADR-0039-ten-foot-metric-ladder.md) |
| B-8 | `UI.Composition`'s content lane at ten-foot | uncapped share → capped at `adaptive.LANE_MEASURE x metricScale` (900) | a shipped composition re-measures on a television; Rascal Rally's results lane moves 992 → 900 there and nowhere else | controller ruling R14; `fixes.md` §7 |
| B-9 | `newTable` narrower than its columns | clipped → **collapses** a column by priority and discloses it | shipped tables re-lay out at compact; a `fill` column's `minWidth` is now honoured (a playlist went 30px → 66px) | `fixes.md` wave TABLE addendum (J-1, J-2, J-3) |
| B-10 | `newTable` selection and edit-mode keys | arrow replaces; no modifier semantics | Ctrl/Cmd moves without selecting, Shift extends, and on a table with no `onPrimaryAction` a device Activate toggles | `fixes.md` wave TABLE addendum (L-6, L-7) |
| B-11 | a horizontal `UI.ScrollView`'s focus ring | vertical run → **horizontal** run | Left/Right now step the rail and Up/Down leave it; the opposite of what shipped | ADAPT-24 in `fixes.md` |
| B-12 | `newTabView` / `newPicker` band placement | corner-parked → centred in the band | shipped geometry moves on three placements | ADAPT-4 in `fixes.md` |
| B-13 | the library's own name and call shapes | `LuauUI` → `Facet`; `Facet.newTable(Facet, core, spec)` → `Facet.Controls.Table(core, spec)` | every consumer require path and nineteen call shapes | [ADR-0036](ADR-0036-facet-rename.md), [ADR-0037](ADR-0037-public-call-shapes.md) — recorded, and the builders still work |

| B-14 | `showcase_chrome.TOGGLE_GAMEPAD` (the gallery example, not the library) | `"ButtonY"` → **removed** | the showcase chrome bound the pad toggle to `ButtonY`, which is `newMenu`'s own gamepad trigger (`menu.luau` `TRIGGER_KEYS.gamepad`, a sinking context at priority 1200) — measured with the shipped `menu` demo mounted, one press opened both. Controller ruling **R20** (2026-08-21) gives `ButtonY` back to the menu verb; the pad reaches the chrome through `SECTION_GAMEPAD` (the two shoulders, R19), and the constant is deleted rather than left naming a binding that no longer exists. An example's export rather than a `src/` surface, recorded here because a consumer copying the showcase's key map is exactly who this ledger is for | `tests/gallery_chrome.spec.luau` case (16), which drives `menu.luau`'s OWN binding rather than asserting an absence |

**B-13 is the shape the rest should have had**: two ADRs, a ledger entry, and the old
builders kept working. B-1 through B-12 are the ones that had a *measurement* and no
*record*, which is what this document supplies.

### 3. The instrument: the two shape changes a ledger cannot see

`tests/lib/public_shape.luau` extracts the two facts, and
`tests/api_surface.spec.luau` pins them:

* **the REQUIRED set** — every `Class.prop` carrying `required = true`, by name;
* **every DOCUMENTED DEFAULT**, by extracted value — shared box/container props once,
  per-class props by `Class.prop`.

A prop flipping to required, or a documented default changing value, now moves a pin
and reddens the suite with a message naming the surface and pointing here. A change
that *is* intended is landed by updating the pin **and** adding a row to Decision 2 in
the same commit — and a third case asserts that every surface named in this ADR's
breaking table is really in the pinned sets, so the record and the schema cannot
drift apart in either direction.

The extraction has one owner for the usual reason: a pin produced by a different
parser than the live read is a claim about a parser that no longer exists.

### 4. Constitution §14 gains the pre-release clause

Stated there in one sentence so the rule is where the rules are, pointing here for
the reasoning and the table.

## Consequences

* **The two changes are on the record**, with their measurements, and a consumer
  reading `DEPRECATIONS` alone would still miss them — which is why §14 now names
  this document beside the ledger.
* **The blindness is closed for the future, not just apologised for.** The pins are
  the deliverable; the table is the backlog they were built to prevent.
* **The pins will collide with other waves, deliberately.** A wave that changes a
  documented default now has to say so in the same commit. That is the friction the
  policy is made of, and the pin is deliberately narrow — an extracted *value*, not
  the doc string — so rewording a doc without changing its default moves nothing.
* **The sweep in Decision 2 is a reading, not a proof.** It is signed as such.

## Carried to the director

1. **Does seventy commits of accumulated public behaviour change still belong inside
   `0.10.0`?** This ADR rules that it *may*, because nothing has been published. It
   does not rule that it *should*. A `0.11.0` bump with this table as its changelog
   is the alternative, and it is a release decision rather than an implementer's.
2. **The publish boundary is the only thing that makes this policy safe**, so it needs
   to be a real event with a name. After it, ADR-0011's window applies unqualified.
