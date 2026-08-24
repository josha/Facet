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
`p2_cartwheel/content/metrics.luau` (deleted) and its hand `metricScale` multiply
in `screens/gallery.luau`; `p3_sipworks/content/metrics.luau` (deleted — what is
left of it is `content/dims.luau`, seven shape constructors with no dimension in
them) and its hand-scaled `gatherToggleAt`; Rascal Rally's `TableMetrics`
`NAMES`/`DEFAULTS`/dotted-lookup `resolve` and `ResultsParts`'
`METRIC_NAMES`/`METRIC_DEFAULTS`/dotted-lookup `metrics()`. `TableMetrics.APP` and
`ResultsParts.appMetrics` are what those tables became: the declarations
themselves.

**One adjacent gap is booked, not closed**: `UI.Grid.minColumnWidth` takes a px
number or `"intrinsic"` and is the one dimension-shaped prop in the library that
does not accept a theme metric NAME — so `p2_cartwheel`'s gallery keeps a memo,
now doing something honest (reading the resolved value off the live snapshot)
rather than multiplying by a factor. Widening that prop is a separate, additive
change with its own tests.

**Two deliberate behaviour changes ride the migration, both at ten-foot only:**

- `p2_cartwheel`'s `chartH`, `heroH`, `previewMin` and `cardMin` now scale at a
  Large display, where before only `tileMin` did. That is the half-applied ladder
  above being finished, and it is the point of the change rather than a side
  effect of it.
- Rascal Rally's ~60 sponsor metrics, its HUD story tokens and its results bands
  now scale at a Large display, where before they were constants. Every viewport
  the game ships on is a near display, and the near answer does not move.

  **What actually proves that, precisely.** The near factor is `1` and
  `forDisplay` returns the base table itself at every near display, so the
  structural argument is that no near-distance arithmetic exists to change an
  answer — and `resolve`'s exhaustive loop pins that every key falls back to the
  declaration it came from, which is the table the old `DEFAULTS` was. On top of
  that, `facet_ten_foot_metrics_contract.spec` spot-checks eight named numbers at
  `PHONE` against their frozen legacy citations. That is a strong argument plus a
  sample, not a number-by-number sweep of all sixty, and it should not be
  described as one.

**Ten Rascal Rally names changed spelling**, and each one is a defect the ladder
would otherwise have shipped: `mapFraction*` → `map{Landscape,Portrait}Fraction`
(0.52 × 1.5 = 0.78 of the body), `listRows` → `listRowCount` (eight rows become
twelve), `toastDurationS`/`toastReadFloorS`/`rejectFlashS` → `…Seconds` (a 2.5 s
toast becomes 3.75), and `rowNameSize`/`rowPosRenderSize`/`badgeInitialSize`/
`controlGlyphSize` → `…TextSize` (the 2.25× double application). That is the
suffix vocabulary doing the work it was kept for — and it is the argument for
naming an app metric after what it *is* rather than where it sits.

**Not breaking.** The framework change is additive: a snapshot gains an `app`
section that is empty (`{}`) until an app declares one, no existing name moves, no
default changes value, no prop becomes required, and no package's authored
metrics — and therefore no package's content stamp — move for the section
existing. `check_flat_baseline` passes untouched: an empty section paints nothing,
so no `ALLOWED_ADDED_SUBKEYS` entry was needed. No ADR-0040 row is owed.

**The ordering trap is closed in the framework, not in a rule.** It is the one
thing the migration actually broke, and it broke silently: a HOST creates the
environment and may commit a theme package's snapshot, and only then does the app
build and declare. Every `px = "app.cartwheel.…"` in `p2_cartwheel` resolved to
nothing, every band it sized measured zero, and nothing errored — an unresolvable
metric name is a missing dimension, which is precisely the accepted-and-ignored
class the metric vocabulary exists to remove.

**THREE seams close it, and the third one is the decisive one.** The first draft
of this section listed two, and shipped with the trap still open — the review that
caught it is why this paragraph is worded as a warning:

1. `env/environment.luau` reads the framework's own default **live** when nobody
   has committed a theme (`snapshot.isFrameworkDefault`), instead of replaying the
   module-load object it was seeded with. A package snapshot somebody committed is
   theirs and is never silently replaced.
2. `snapshot.forDisplay` — the one seam every environment read passes through —
   refreshes a base whose **declaration generation** is stale, merging in only the
   names that base has never heard of (a value already there was put there by a
   package, an override or the pixel snap, and it is that snapshot's answer). In
   the steady state, which is every read after boot, this is one weak-table lookup
   returning its argument, so the near-display identity guarantee is untouched.
3. **THE REACTIVE EDGE — `use(appGeneration)` inside the environment's
   `themeMetrics` memo. DO NOT REMOVE IT.** The two seams above are what
   *recompute* a stale answer; this is what makes anyone *ask*. An environment
   MEMOIZES that read, and a memo re-runs only when a signal it `use()`d changed —
   so with 1 and 2 alone, a declaration made after the first read invalidated
   nothing, the memo served its warm value, and `px = "app.…"` went on resolving
   to nil with the band silently measuring zero. Every ten-foot test in the
   framework masked it, because setting `displaySize` invalidates that memo for an
   unrelated reason and the declaration rode in on it.

   `declareApp` publishes its generation to a **weak-keyed** registry of signals
   (`snapshot.observeAppDeclarations`), and `environment.new` registers one — kept
   deliberately OUTSIDE the `signals` fact table, so the vocabulary `env:get` /
   `env:set` police is unchanged and nothing can write it. It is a **dependency,
   never a value**: the number is subscribed to and never read.

   Guard: `tests/app_metrics.spec.luau`, "a declaration reaches a warm
   environment" — it declares AFTER a read on the SAME environment and touches
   nothing else, which is the only shape that can fail.

**Publishing is self-healing, and the failure is QUIET — not loud.** An earlier
draft of this section claimed the opposite, and the claim was false at the throw
point that actually occurs; a reviewer drove the real path and it is corrected
here rather than quietly reworded, because the difference decides how a reader
budgets their attention.

`declareApp` writes reactive state, and the core refuses a write made during an
evaluation. A **direct** call raises. A call from **inside a memo** does not reach
the author at all: the core `pcall`s a memo's compute (`core/custom.luau` —
"Never throws to the caller: compute errors, cycles, and illegal writes quarantine
the node"), so the memo is quarantined with its old value, `get()` answers as if
nothing happened, and the ONE artifact is `core:lastError()`. By then the
vocabulary is live — `isMetricPath` answers true — while an environment that
missed its notification resolves those names to nothing.

Two properties stop that becoming a *permanent* silent zero rather than a
momentary one: every registered signal is offered the generation before the first
failure is reported (so a failing observer never costs a working one its
notification, whatever order the weak registry iterates — the guard registers TWO
failing observers, because with one, a stop-at-first-failure bug passes whenever
it sorts last: measured green in 4 runs of 8), and only a signal that TRAILS is
written, which lets the top of the next `declareApp` — including the identical
retry the value-equality short-circuit would otherwise eat, and including a
declaration for an unrelated group — catch it up.

So: **call `declareApp` at boot, from ordinary code.** The framework makes the
mistake *recoverable*, and now *self-announcing* too. Guard:
`tests/app_metrics.spec.luau`, "a declaration made inside a memo is quarantined,
recorded, and healed later".

**DONE 2026-08-23** (director ruling, framework-gaps-phase2 task-fix2 item 6):
an illegal write during a memo evaluation now gets a real diagnostic, not only a
`lastError` entry — `core/custom.luau`'s `fail()` calls `warn()` (injectable via
`Facet.newCore({ warn = ... })`, real by default) on every quarantine, deduped
against the message it is about to replace so a persistently-failing memo warns
once per DISTINCT failure rather than once per re-evaluation. One change, in the
one place every quarantined-write shape in the framework routes through — this
one, `newMenu`'s reactive `presentation` refusal, an equality-callback throw, a
scope's own double-disposal diagnostic, all of it.

`observeAppDeclarations` and `appGeneration` are **internal**, not exported on
`Facet.themes` and not classified as public surface. The registry is weak, so an
observer that keeps no reference of its own would have its edge collected out from
under it with no diagnostic anywhere; the environment is safe because its signal
lives exactly as long as it does, and `observeAppDeclarations` returns an
`unsubscribe` (which captures the signal) so a deliberate holder is safe the same
way.

The generation rides a weak side table rather than a field, for `densityBases`'
reason: a snapshot's own shape is byte-identical to what it was before this
feature. Declaring is still a boot act — declare before the first form is built —
but forgetting is now a no-op rather than a silent collapse.

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
