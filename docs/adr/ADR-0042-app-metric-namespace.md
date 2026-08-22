# ADR-0042 — An app's own numbers get a name, a theme and a ladder

**Date:** 2026-08-22
**Status:** Accepted
**Number:** 0042. 0031 is a burned number
([ADR-0032](ADR-0032-nested-instance-tree.md) records why).
**Companions:** [ADR-0019](ADR-0019-theme-packages.md) §2 (the snapshot is the
one effective metric authority, and metric REFERENCES are its vocabulary),
[ADR-0039](ADR-0039-ten-foot-metric-ladder.md) (the ladder these numbers now
climb, and the classification doctrine this reuses),
`src/themes/snapshot.luau` (`declareApp` / `appMetrics` / `resolve` step 1b /
`densityClassOf`), `src/themes/package.luau` (`metrics.app`),
`src/themes/token_sync.luau` (the dump), `tests/app_metrics.spec.luau` (the
contract), `.superpowers/sdd/framework-gaps-phase2/gap1-audit.md` (the finding).

## Context — the same shim, written four times

The release-candidate audit's strongest signal was a defect **rediscovered
independently four times**, twice in the showcase and twice in production, each
time by an author who wrote the reason down and then worked around it:

- `examples/reference/p2_cartwheel/content/metrics.luau` — *"THE SPEC ASKS FOR
  `metrics.cartwheel.*` IN THE TOKEN SCHEMA, AND A PROOF CANNOT PUT THEM THERE."*
- `examples/reference/p3_sipworks/content/metrics.luau` — *"The spec states these
  as dotted theme-metric names (`metrics.sip.rowArt`). They cannot be."*
- Rascal Rally `FacetSponsor/TableMetrics.luau` — 1,392 lines carrying ~60 dotted
  `metrics.sponsor.*` names, a `DEFAULTS` table of frozen legacy pixels, and a
  `resolve(snapshot)` that did a dotted lookup and fell back.
- Rascal Rally `FacetSponsor/ResultsParts.luau` — `METRIC_NAMES` /
  `METRIC_DEFAULTS` / `metrics()`, the same shim shape a second time.

They were right that it could not be done. `snapshot.isMetricPath` validates a
name against `snapshot.neutral()`, so a name no shipped package declares is a
**construction error**; `themes.resolve` refuses an unknown `overrides` path and
an unknown `metrics.tenFoot` path; and the ten-foot density ladder walks a closed
hardcoded set of sections, so even a section smuggled into a snapshot would
receive **no distance transform**.

The consequence was ~100 structural numbers sitting outside every theme, outside
a package swap and outside the ladder — and two of the four then re-implemented
the distance transform **by hand** (`metricScale` multiply). One of those,
`p2_cartwheel`, applied it to `tileMin` and left `chartH`, `heroH` and
`previewMin` behind, so the ten-foot ladder was **half-applied inside a single
flagship proof**: a television measured a 144 px tile minimum inside a 160 px
chart band that had not moved. A hand-rolled ladder is a ladder somebody has to
remember to climb.

## Decision — a reserved `app.*` namespace the application declares once

```lua
Facet.themes.declareApp("cartwheel", { tileMin = 96, gallery = { rowHeight = 56 } })
```

From that call on, `"app.cartwheel.tileMin"` is a metric name in every sense the
framework already has one:

1. **Spellable.** `isMetricPath("app.cartwheel.tileMin")` is true, so
   `px = "app.cartwheel.tileMin"` passes the same construction check
   `px = "iconSizes.large"` passes — and an
   **undeclared** `app.*` name is refused exactly as `iconSizes.enormous` is.
   Declaring is what makes a name legal; a typo is a build error, not a nil size
   on the first solve of a themed screen.
2. **Universal.** `themes.resolve` publishes the namespace on **every** package,
   so a proof that must mount under Studio Neutral *and* Fantasy Parchment with
   zero source edits keeps its geometry either way.
3. **Theme-owned.** A package's `metrics.app` moves any declared name, exactly as
   `metrics.space` moves a spacing step; `themes.resolve`'s `overrides` and a
   package's `metrics.tenFoot` reach `app.*` paths with no special case, because
   both already walk the resolved snapshot and the snapshot now has the section.
4. **On the ladder.** `densityClassOf` classifies `app.*` with `controls.*`'s rule
   word for word: a **length** unless a name segment says otherwise (`*TextSize`,
   `*Lines`, `*Count`, `*Duration`, `*Seconds`, `*Ratio`, `*Fraction`, `*Scale`,
   `*Opacity`, `*Weight`).
5. **Dumped.** A package's authored `metrics.app` entries appear in
   `token_sync.records` as `app.<path>` and round-trip back.

### Why a process-wide declaration, and not a package section alone

`isMetricPath` runs at **construction**, inside `blueprint_schema`, with no
snapshot in scope. That is the whole point of it — a typo caught when the form is
built rather than on the first solve of a screen a designer may not open for a
week. So a vocabulary an app adds has to be knowable *without* a snapshot, which
a per-package section by definition is not; and the two showcase proofs install no
theme package at all, so a package-only channel would have left exactly the four
consumers that reported the gap unable to use the fix.

`declaredApp` is therefore the one mutable module-level fact in the pure theme
half, and it is fenced: `declareApp` validates, deep-freezes, and drops the
`neutral()` memo, so the snapshot `isMetricPath` spells names against can never
outlive the vocabulary it was resolved with.

### Why a declaration claims a GROUP rather than the whole section

The first draft took `declareApp(metrics)` and replaced the section. That is
wrong in this repository's own showcase: `examples/gallery` mounts **five**
reference proofs in one place and the picker switches between them at runtime, so
the second proof's boot would have silently un-spelled the first proof's names —
and every form the picker rebuilt after the switch would have refused to
construct, with a message blaming a name that was correct when it was written.

So a declaration claims exactly one top-level group and replaces only that group;
`nil` retires it, which is also how a test puts the process back the way it found
it. Two apps cannot collide by construction, and the group name is the one
segment that says **whose** number this is — which is what `metrics.sponsor.*`
was trying to spell in the Rascal Rally shim all along.

### Why the default class is LENGTH

`app.*` is an **open** section, like `controls.<family>.<anything>`, so the
classification has to be a default plus a vocabulary rather than a list nobody
outside this repo could maintain. The default is *length* because that is what an
app declares here: every one of the four shims held tile minimums, chart bands,
row heights and dock bands, and every one of them failed to scale on a
television. The suffix vocabulary is the escape and it earns its keep on the
first migration — a `mapFraction` multiplied by 1.5 is 0.78 of a viewport, a
`listRowCount` of 8 becomes 12, a `toastDurationSeconds` of 2.5 becomes 3.75, and
a `rowNameTextSize` scaled here is the 2.25× double application the type floor
already guards at the measure seam.

One vocabulary, shared with `controls.*`, so an author who has read one has read
both. `tests/ten_foot_metrics.spec.luau`'s completeness rule still holds: no
`app.*` leaf classifies to nothing.

### Refuse, don't guess — on both sides

- **Declaring**: every key must be an identifier (`^[%a_][%w_]*$` — a `.` would
  make the dotted path ambiguous) and every leaf a finite number. A string, a
  NaN, an infinity or a `tile-min` is an error at the declaration, not a surprise
  at the solve.
- **A package moving one**: `metrics.app`'s **shape** is checked in
  `themes.define` (identifiers, finite numbers, any depth) and its **names** in
  `themes.resolve`, against the live declaration — the same split `metrics.tenFoot`
  already uses, because the declaration is a runtime fact and `define` may
  legitimately run before an app has made it. A package that invents an app name
  is refused, because the failure mode of accepting it is the worst one
  available: a number that silently never moves, on a surface nobody thought to
  check.

### Deviation from the audit's sketch

The audit wrote the shape as `tokens.compile{ app = { tileMin = 96 } }`. The
declaration landed on `themes` instead, deliberately: `tokens.compile` produces a
compiled **paint/token style** consumed by `screen_target` and `sheet_model`, and
an app metric never reaches either — it is a *snapshot* fact, and the snapshot is
`themes`' half of the library. A compiler that also mutates process-wide state is
not a compiler, and `compile`'s `(value, report)` contract has no error channel
for a malformed metric NAME (its `missing` list is about absent required keys).
The audit's binding requirements — a reserved `app.*` namespace `isMetricPath`
accepts and the distance transform walks, so `px = "app.tileMin"` works everywhere
`px = "iconSizes.large"` does — are met exactly.

## Consequences

**Four shim files migrate and the shims are deleted** in the same round:
`p2_cartwheel/content/metrics.luau` (gone) and its hand `metricScale` multiply in
`screens/gallery.luau`; `p3_sipworks/content/metrics.luau`'s number half (gone,
with its hand-scaled `gatherToggleAt`); Rascal Rally's `TableMetrics`
`NAMES`/`DEFAULTS`/dotted-lookup `resolve` and `ResultsParts`'
`METRIC_NAMES`/`METRIC_DEFAULTS`/`metrics()`.

**Two deliberate behaviour changes ride the migration, both at ten-foot only:**

- `p2_cartwheel`'s `chartH`, `heroH`, `previewMin` and `cardMin` now scale at a
  Large display, where before only `tileMin` did. That is the half-applied ladder
  above being finished, and it is the point of the change rather than a side
  effect of it.
- Rascal Rally's ~60 sponsor metrics now scale at a Large display, where before
  they were constants. Every viewport the game ships on is a near display, where
  the numbers are **byte-identical** — asserted, not assumed — so the change is
  confined to a display class the game does not ship on today and is the same fix
  the framework's own ruling (ADR-0039) made for every other metric.

**Not breaking.** The framework change is additive: a snapshot gains an `app`
section that is empty (`{}`) until an app declares one, no existing name moves, no
default changes value, no prop becomes required, and no package's authored
metrics — and therefore no package's content stamp — move for the section
existing. `check_flat_baseline` passes untouched: an empty section paints nothing,
so no `ALLOWED_ADDED_SUBKEYS` entry was needed. No ADR-0040 row is owed.

**The declaration is boot-ordered**, and that is the one sharp edge: a snapshot
resolved *before* `declareApp` carries the older namespace. The framework makes
this as narrow as it can — `declareApp` drops the neutral memo, so the snapshot
every screen gets for free is always current — but an app that resolves a package
into `themeMetrics` before declaring gets a snapshot without its own numbers.
Declare at boot, before the first form is built.

## Alternatives rejected

- **Accept any `app.<name>` syntactically.** Cheapest, and it throws away the
  only thing the namespace is for: an undeclared name would resolve to nil and
  paint a zero-size box, which is the defect `isMetricPath` exists to catch.
- **Validate `isMetricPath` against a snapshot passed in.** There is no snapshot
  at construction; threading one through `blueprint_schema` would make every form
  construction theme-dependent, which is the opposite of the design.
- **Let each package declare its own app names.** Leaves the two showcase proofs
  — which install no package — exactly where they were, and makes the same app
  number a different name under two themes.
- **A flat namespace.** Twice load-bearing. The ten-foot classification reads
  every path SEGMENT, so `app.sponsor.mapFraction.landscape` is exempt while a
  flattened `app.sponsorMapFractionLandscape` would not be; and the top-level
  group is what keeps two apps in one process from clobbering each other.
