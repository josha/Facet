# ADR-0049 — A box declares its height in CONTENT TERMS

**Date:** 2026-08-23
**Status:** Accepted
**Number:** 0049. 0048 is the nav predicates + headless measurement entry
point. This decision adds ONE row to the ADR-0040 register (B-26 — two
example-fixture viewport heights change value at Neutral, measured and
documented) and nothing else breaks: every other surface below is additive
(new dim fields, two new pure functions, one diagnostic's scope narrowed to
exclude a shape it never should have flagged).
**Companions:** [ADR-0023](ADR-0023-declared-content-composition.md) (`UI.Composition`
Region floors — the vocabulary this decision generalizes),
[ADR-0044](ADR-0044-fit-as-a-declaration.md) (`textSize = "fit"` — the C-1
measure-key lesson this decision applies rather than re-learns), `docs/handoff/
SOURCE_CAP_LEDGER.md` (`solver.luau`'s row, checked before this round opened
the file), `.superpowers/sdd/framework-gaps-phase2/task-g3-brief.md` /
`gap3-audit.md` (the mission).
**Home:** `src/blueprint_schema.luau` (`DIM_TYPES`, `dim`'s cross-validation),
`src/themes/snapshot.luau` (`DIM_METRIC_FIELDS`, `resolveDim`),
`src/layout/measure_facts.luau` (`Dim`, `memoPlan`'s documentation),
`src/layout/solver.luau` (`contentTermsPx`, `resolveAxis`, the nested-scroll
diagnostic), `src/render/layout_node.luau` (`stampContentTermsFacts`),
`src/blueprint.luau` (`UI.fill`/`UI.hug`, item 14).
**Guards:** `tests/content_terms_height.spec.luau` (construction, resolution,
solver arithmetic, the nested-scroll regression, the four migrated sites,
`UI.fill`/`UI.hug`), `tests/measure_memo.spec.luau` (the plan-class /
cache-key proof), `tests/lib/fuzzers/layout.luau` (the differential-oracle
vocabulary).

## Context

`framework-gaps-phase2` audit §3: `UI.Composition` already has a vocabulary
for "how tall should this box be, in terms of its content" — Region floors
are `{ lines = n }` / `{ targets = n }`, resolved by `composition.floorPx`
against the live theme snapshot. It is **locked inside Composition**. Outside
one, a scroller or panel viewport that must show LESS than all of its own
content (the defining shape of a scrollable window: `List` holds twelve rows
and shows four, `Scroll` holds eight and shows a little over four, `Form`
holds more than fits and shows about five) has no way to say that
declaratively, and got pinned in a literal px instead — next to content that
scales with the player's accessibility text preference and the ten-foot
ladder, which the literal never did.

Four sites in the adaptation slice, named by the audit: `flow_wrap.luau`'s
`AlignBox` (a 14-line comment justifying `360`), `keyboard_navigation.luau`'s
`List` (`150`), `native_style.luau`'s `Scroll` (`120`), and
`preferred_text.luau`'s `Form` (`180`, in the very fixture whose subject is
text growth).

**The load-bearing constraint, carried from this campaign's own C-1
(ADR-0044, `measure_memo.spec.luau`):** a content-height read is exactly the
shape that broke the measure cache once already — `textSize = "fit"` reads
the offered box, and `PLAN_HEIGHT_FREE` (`measure_facts.memoPlan`) dropped
`maxH` from its key before the fix, so the same node asked at two different
heights in one solve served the first answer to the second (measured: a
41px-capped box painted a 531px line block). Any new content-height
mechanism has to state, explicitly, which cache-key plan it takes and why —
not merely ship a green suite that happens not to have found the counter-
example yet.

## Decision

### 1. Two shapes on the existing `content` dim type, not a new type

`{ type = "content", lines = n, role: string? }` and `{ type = "content",
rows = n, of = metric }`. Both ride the `content` tag rather than inventing a
fourth type name, because the underlying question — "how tall, without
measuring a child" — is the same one `blueprint_schema`'s own DIM_TYPES
comment already used `content` for; `lines`/`rows` turn the historic
"measure my children" default into a FORMULA instead. `blueprint_schema.luau`
refuses both present at once, `rows` without `of`, `of` without `rows`,
`role` without `lines`, and any of the four on a non-`content` type — the
"an enum prop that accepts any string and silently does nothing" lesson this
file's own header states, applied to a shape rather than a string: `role` is
validated against the theme package's closed `TYPE_ROLES` set at
construction, loud, rather than falling back silently the way
`composition.floorPx`'s own `role` field already does (a design choice
`ADR-0049`'s own review should weigh against that precedent — see
"Alternatives").

`lines` spends the SAME two calls `Facet.text.lineBox` (`text_fit.lineBox`)
already publishes: `ceil(lines * (roleSize * scale + offset) * lineHeight)`.
`rows` is `n * of` — arithmetic, once `of` is a number.

### 2. `of` rides the EXISTING metric-name resolution, not a new one

`of` joined `DIM_METRIC_FIELDS` in both `blueprint_schema.luau` (construction-
time validation) and `themes/snapshot.luau` (`resolveDim`, prop-normalization-
time resolution) — the same list `px`/`min`/`max`/`preferred` already ride,
so a metric name, a literal px, or an additive list of either (`{ "xs", 4 }`)
were free: no new resolution code, no new escape-hatch rule, the one this
file already documented ("a literal number remains legal everywhere a metric
name is accepted"). By the time `solver.luau`'s `contentTermsPx` reads
`d.of`, it is already a plain number.

### 3. `lines`'s scale/offset are pre-resolved OUTSIDE the solver too — and this is the round's own finding, not a plan

The first implementation had `contentTermsPx` call
`textFitLib.facts({ metrics = ctx.metrics })` the way `composition.floorPx`
does. **Wiring it up found this was wrong**: `ctx.metrics` is
`render/renderer.luau`'s `currentMetrics()` — `env:get("themeMetrics"):get()`
— and that fact is NOT re-derived on every accessibility nudge; the renderer
deliberately keeps `preferredTextOffset` OUT of it and re-reads it FRESH
every solve as a separate local (`prefOffset`), threading it straight into
`toLayoutNode` for every text node's own reservation (`textFit.offset`,
`reservedSize`'s additive half). A solver-side read of
`ctx.metrics.preferredText.offset` is therefore last-theme-swap's value, not
this solve's — measured directly: a raised `preferredTextOffset` moved
nothing until fixed.

The fix mirrors `textFit.offset`'s own seam exactly:
`render/layout_node.luau`'s new `stampContentTermsFacts` spends the SAME live
`textScale`/`prefOffset` `toLayoutNode` already carries, stamping them onto
the resolved `Dim` as `scale`/`textOffset` at the SAME prop-normalization
step `resolveDim` runs at. `contentTermsPx` then reads `d.scale`/
`d.textOffset` (defaulting to `1`/`0` for a tree built straight against the
solver — the fuzzer, a low-level spec) rather than `ctx.metrics.preferredText`.
`rows` needs none of this: a theme metric's own resolution never depended on
the live text-preference fact in the first place (`controlSizes.compact.height`
scales with the ten-foot ladder via `metricScale`, baked into the snapshot at
resolve time; it has never scaled with `preferredTextOffset` — see "What is
NOT built" below).

**This is a real, if narrower, cousin of the campaign's own C-1**, found by
the same discipline that fixed C-1: measure the live behavior rather than
trust that "reads the snapshot" means "reads the current facts". It shipped
fixed, not shipped-then-found, because this ADR's own drafting is what
surfaced it before a suite ever ran.

### 4. The cache-key argument, stated and proved (the brief's own bar)

`measure_facts.memoPlan` already put `t == "content"` in the height-free-
eligible set, for the historic (measuring) meaning of bare `content`. This
decision's new comment on that branch (`measure_facts.luau`) states the
argument for the FORMULA meaning explicitly: neither `lines` nor `rows`
reads `limit` (the offer) at any point — `lines` reads `ctx.metrics`
(invariant for the whole solve) plus the two already-resolved numbers on the
`Dim`; `rows` reads only the `Dim` itself. So the answer is offer-invariant
BY CONSTRUCTION, and `PLAN_HEIGHT_FREE`'s promise (cache it, drop `maxH` from
the key) holds without needing the C-1-style exception carved out for
`textSize = "fit"` (which genuinely does read the offer). A node whose KIND
is height-coupled (`scroll`, `composition`, `grid`/`gridrow`, `vwrap`) still
falls to `PLAN_KEYED` regardless — unchanged, and correctly so, because that
guard is about what the NODE's kind reads, not what this dim FORMULA reads.

**Proved, not asserted**: `tests/measure_memo.spec.luau` adds a case built
exactly like the C-1 case above it — the same node, asked at two genuinely
different `maxH` values in one solve via a `hug`-capped ancestor, armed vs.
unarmed by a scroller elsewhere in the tree (`ctx.hasScroll` gates the memo).
Both arms agree, and the agreed answer is the formula's own (`77`), not
either candidate a wrongly-dropped-`limit` bug would leak. **Mutation-
verified**: temporarily making `contentTermsPx` cap its result at `limit`
(the plausible "maybe it should still respect a hug-style cap" mistake) reds
the case (`expected 77 to be 41`); reverted, it is green again.

### 5. A regression the migration itself found: a content-terms viewport is DEFINITE inside another scroller's unbounded axis

Migrating `preferred_text.luau`'s `Form` (nested inside `Doc`, its own
y-scroller) turned up 261 findings on `tests/overflow_sweep.spec.luau`: the
solver's own "a scroll region on an unbounded axis materializes everything"
diagnostic (booked ruling G5c) decides "is this extent definite" by testing
`mainDim.type ~= "fixed"` — and `content` (even carrying `lines`/`rows`,
making it a formula) failed that test exactly as a bare, MEASURING `content`
correctly does, because the diagnostic could not tell the two apart. Fixed
by naming the content-terms case a THIRD definite shape beside `fixed` in
that one condition (`solver.luau`). A bare `content` scroller in the same
nested position is still, correctly, reported — `tests/content_terms_height.
spec.luau` §4 pins both the fix and the un-regressed historic case as a
negative control.

### 6. `UI.fill(weight?)` / `UI.hug(bounds?)` — in-brief item 14, dissolved with demonstration

Not this gap's shape (the audit's own "next steps" lists content-terms
height and `UI.fill`/`UI.hug` shorthands as two SEPARATE next steps, not one
merging into the other — see "Registry evidence" below) but cheap once
`blueprint.luau` was already open for `contentTermsPx`'s consumers, and the
brief's own note authorizes it. `{ type = "fill", weight = 1 }` is written
**326 times** across the reference corpus per the audit (two apps built
private dim DSLs rather than keep repeating it); `UI.fill(weight?)` is the
named shorthand, a plain VALUE producer (`width = UI.fill()`) rather than a
blueprint modifier like `aspectRatio`/`containerRelativeFrame` beside it —
a fill dim is authored on one axis at a time, exactly where the raw table
already went. `UI.hug(bounds?)` is the same shorthand for `{ type = "hug",
min?, max? }`. **Demonstrated, not swept**: nine of this round's own sites,
across all four migrated scenario files, moved from the raw table to
`UI.fill()`; the remaining ~317 corpus sites are OWED, not claimed.

## What is NOT built (and why each is a real boundary, not a shortcut)

**`rows`+`of` does not track the player's accessibility text preference.**
A theme metric (`controlSizes.compact.height`, a space step) has never
scaled with `preferredTextOffset`/`preferredTextSize` — those are text-seam
facts, not theme-snapshot facts (`snapshot.resolve`'s `facts` argument stores
them into `out.preferredText` for the TEXT seam to spend; `metricScale`,
which DOES apply to `controlSizes`, keys only on `displaySize`). A `rows`
viewport therefore grows at the ten-foot ladder and NOT at a raised text
preference — pinned as a negative control in `tests/content_terms_height.
spec.luau` §3, not left as an unstated gap. `lines` is the shape that tracks
BOTH (it goes through the text seam's own scale/offset), which is why
`native_style.luau`'s migration used it even though its content is discrete
rows, not flowing text: the choice trades a slightly awkward "why `lines`
for a row list" reading for the axis this specific box actually needed to
track.

**No gap term in either formula.** Both are pure products (`n * unit`), with
no per-line/per-row spacing added — the SAME limitation `composition.floorPx`
already has (`lines * lineBox`, `targets * minimum`, no gap). `flow_wrap.
luau`'s `AlignBox` is the site this bites hardest: its real per-line unit
(a chip's own measured content height, `46`px at Neutral) sits between
`controlSizes.compact.height` (`36`) and `.large.height` (`56`), with a
`TAG_GAP` between wrapped lines the formula cannot add — which is why its
migration uses `rows = 10` (not `4`) to reproduce the historical worst-case
margin as a formula rather than as a line count that reads naturally. Adding
a gap term was considered and rejected for THIS round (see "Alternatives") —
it is a real, scoped follow-up, not silently declined.

## What is breaking, and what is not

**One row.** `keyboard_navigation.luau`'s `List` (`150` → `144`, `-6px`) and
`native_style.luau`'s `Scroll` (`120` → `116`, `-4px`) change value at
Studio Neutral — booked as ADR-0040 **B-26**, following the B-25 precedent
(a gallery-fixture value change is still a shipped-geometry change worth a
row, even though it pins no public control default). Both deltas are
MEASURED, not guessed, and both move in the SAFE direction (smaller, so
nothing that fit before now overflows) — see B-26's own row for the
per-site arithmetic. `flow_wrap.luau`'s `AlignBox` (`360` → `360`) and
`preferred_text.luau`'s `Form` (`180` → `180`) are value-identical at
Neutral; no row for either. Every other surface in this decision — the two
new `Dim` fields (`lines`/`rows`/`of`/`role`, `scale`/`textOffset`), the two
new `blueprint.luau` functions, the widened `DIM_METRIC_FIELDS` lists, the
narrowed diagnostic condition — is additive: no prop flipped to required, no
documented default changed value, nothing removed.

## Registry evidence

Per the round's own instruction: dissolve with demonstration, or stay open
with a stated reason — evidence first, never assumed from "same home file".

- **Item 14** (dim shorthand, `UI.fill`/`UI.hug`) — **DISSOLVES WITH
  DEMONSTRATION.** Built (§6 above), tested (`tests/content_terms_height.
  spec.luau` §6, 8 cases), and adopted at 9 real sites across all four
  migrated scenarios. The remaining ~317 corpus occurrences are an owed
  sweep, not claimed as done.
- **Item 17** (Table content-hugging height / header+body-union column
  sizing) — **STAYS OPEN.** Checked `src/controls/table.luau`'s own row-
  height arithmetic (`family.rowLines[paradigm] * lineBox + 2 * padV +
  artV`): it is a multi-factor computation over the table's OWN theme family,
  never published as a single resolvable `themeSnapshot` metric path — so a
  caller cannot spell `height = { rows = n, of = "<a table's row metric>" }`
  for a Table today. Closing it needs Table itself to either publish that
  arithmetic as a metric name or grow a first-class `rows`-shaped height prop
  that spends this decision's own formula internally; neither exists. The
  column-sizing half of the same in-brief item is a WIDTH concern, entirely
  unrelated to a height dim.
- **Item 18** (no `"intrinsic"` minimum outside `UI.Grid`) — **STAYS OPEN.**
  `"intrinsic"` (`blueprint_schema.luau`, `UI.Grid`'s `minColumnWidth`,
  ADR-0040 B-2) names a WIDTH-axis MEASUREMENT — "as wide as the content
  naturally needs" — which is architecturally the opposite of what
  `lines`/`rows` do (a FORMULA independent of measured content, on the
  height axis in every one of this round's own uses). Same home file, same
  "noun layer" wave as item 14; not the same shape.
- **Item 19** (`surface = "badge"` carries no intrinsic size) — **STAYS
  OPEN.** A paint-surface-token default-size question, coupled by the audit
  to item 18's intrinsic-sizing theme, not to content-terms height. No
  overlap with `lines`/`rows` in mechanism, home, or axis.

## Alternatives, and why not

**Pre-collapse `lines` into `{ type = "fixed", px = N }` at prop-
normalization time too**, the way `rows`'s `of` already effectively is.
Considered seriously (it would have avoided touching `solver.luau`'s
`resolveAxis`/`memoPlan` at all, and `layout_node.luau` had every input
needed). Rejected because it would have made the brief's own central
question — "which cache-key plan does a content-height dim take, and why" —
UNASKABLE: a dim the solver only ever sees as `fixed` needs no plan-class
argument, which would have sidestepped the discipline the brief is
explicitly testing rather than satisfied it. Keeping the formula solver-side
(reading pre-resolved facts, per §3) is a genuine plan-class question with a
proved answer, not a dodge.

**Add a gap term to `rows`/`lines`** (`{ rows = n, of = metric, gap = "xs" }`
computing `n * of + (n - 1) * gap`). Would have let `flow_wrap.luau`'s
`AlignBox` read `rows = 4` instead of the opaque `rows = 10`. Rejected for
THIS round: it is a real extension beyond the audit's own stated shape
(`composition.floorPx`'s two existing forms, `lines`/`targets`, carry no gap
term either — this decision's whole framing is "publish the vocabulary that
was already locked inside Composition," not "improve on it"), and adding it
well — deciding whether the gap comes from the node's own `gap` prop or a
separate declaration, and proving it against `flowPlan`'s wrap arithmetic —
is its own scoped piece of work. Recorded as an owed follow-up, not silently
declined.

**Let `role` fall back silently to `"body"` on an unrecognised name**, matching
`composition.floorPx`'s own existing behavior (`floor.role or "body"`, with
a theme that lacks the named role ALSO falling back). Rejected: this file's
own header states the "an enum prop that accepts any string and silently
does nothing" lesson, and a public, blueprint-schema-validated prop is
exactly where that lesson applies — construction-time validation against the
theme package's closed `TYPE_ROLES` set is loud, cheap, and consistent with
every other closed vocabulary `blueprint_schema.luau` already refuses by
name. `composition.floorPx`'s own silent fallback is a pre-existing,
narrower precedent (an internal resolver spending a runtime theme, not a
constructed prop) and is left as-is; not revisited here.
