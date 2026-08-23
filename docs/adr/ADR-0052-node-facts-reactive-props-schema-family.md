# ADR-0052 — The node-facts / reactive-props / schema family (framework-gaps-phase2, wave 3-C)

**Date:** 2026-08-23
**Status:** Accepted
**Number:** 0052. This decision touches ONE row in the ADR-0040 register — none:
every surface below is additive (a new controller method, a new optional
argument, a new blueprint prop, a new pure module, a new construct method) —
nothing flips to required and no documented default changes value. See "What
is breaking, and what is not".
**Companions:** [ADR-0026](ADR-0026-authored-presentation-composition.md) and
its 2026-08-23 amendment (item 16, `offset` — the composition-rule decision
lives there, not duplicated here), [ADR-0049](ADR-0049-content-terms-height.md)
(items 17/18's DISPOSE evidence — the content-terms machinery these two items
asked to ride was scoped and built there, and stays scoped),
`.superpowers/sdd/framework-gaps-phase2/task-w3c-brief.md` / `gap-registry.md`
(the mission), `task-g3-report.md` §6 (items 17/18's original evidence).
**Home:** `src/paths.luau` (`stripThenSegments`), `src/render/renderer.luau`
(`controller.mountedPathOf`, `screenRectOf`'s `relativeTo`), `src/blueprint_schema.luau`
+ `src/render/presentation.luau` + `src/render/presentation_channel.luau`
(`offset`), `src/layout/transform_footprint.luau` (new module) + `src/init.luau`
(`Facet.layout`), `src/controls/menu.luau` (`presentation` as `Readable<string>`),
`src/controls/virtual_list.luau` (`list.positionOf`).
**Guards:** `tests/node_facts.spec.luau` (new — items 15/37/40, 13 cases),
`tests/transform_footprint.spec.luau` (new — item 33, 6 cases),
`tests/authored_presentation.spec.luau` §F (item 16, 6 cases),
`tests/menu.spec.luau` (item 20, 5 new cases). RR:
`tests/facet_node_facts_and_offset_contract.spec.luau` (new — items 15/16/33/40
reachability + live behavior through this game's own require path);
`tests/facet_sponsor_story.spec.luau` (item 37 — `StoryFlow`'s migrated call
sites, pre-existing coverage, unaffected in verdict but exercising the new
code path); `tests/facet_motion_and_scroll_contract.spec.luau` (item 22's
DISSOLVE — the C-SCROLL case, pre-existing).

## Context

`gap-registry.md`'s node-facts/reactive-props/schema family: nine items named
in the brief's title (15, 16, 17, 18, 20, 21, 22, 33, 40), with two more
folded into the node-fact trio's own investigation per the brief's body text
(37, 38 — "one seam likely answers all three... census the real consumer
needs... DISPOSE-with-census where no consumer exists"). Eleven items total,
each closed BUILT / DISSOLVED-with-demonstration / DISPOSED-with-measurement.

Three items (17, 18) had their evidence already gathered by G3 (`task-g3-report.md`
§6) under an EARLIER gap (content-terms height, gap 3) that shares a home file
with them; this round's job for those two was to re-verify that evidence still
holds against the live tree and formalize the terminal state, not re-derive it.
One item (22) turned out to have been fixed by an EARLIER, pre-campaign round
(O-31, 2026-08-15) the audit's own citation predates. Two items (21, 38) had no
consumer site named by the audit and none found by a fresh, targeted census.
The remaining six (15, 16, 20, 33, 37, 40) had real, evidenced consumer need
and shipped small, additive builds.

## Decision

### The node-fact trio (15, 37, 38) — one seam, two BUILD, one DISPOSE

**Item 15 (a node cannot hand back its own mounted path) — BUILT.**
`examples/reference/p5_wardrobe/init.luau` resolved a `UI.Stage` node's
mounted path by calling `controller.stageHost(PANE_PATH)` and, on failure,
falling back to `deps.adapter.paths()` — a live-path dump that **does not
exist** on either target (`fake_target.luau`, `client/screen_target.luau`):
the fallback was dead code, so the site silently returned no stage host
whenever a `UI.When` ancestor's injected `/then` segment (`mount.luau`:
`branchPath = path .. "/then"`) put the real path anywhere other than the
literal declared string. `controller.mountedPathOf(declaredPath) -> string?`
(`renderer.luau`) resolves it directly: exact match first, then the live path
whose `paths.stripThenSegments`-normalized form equals the declared one.
`paths.luau` is the "one home for shared path helpers" this module already
documents itself as — the right owner for a second structural-splice rule
beside `isPrefix`/`escape`. The wardrobe site now reads
`controller.mountedPathOf(PANE_PATH) or PANE_PATH` in place of the dead
enumeration; `tests/reference/wardrobe_spec.luau`'s "the stage host is live
headlessly" case exercises the migrated line.

**Item 37 (a node-relative `screenRectOf`) — BUILT.** Census found a REAL,
current production consumer with the exact "root-relative-then-subtract"
shape the registry's DISPOSED clause anticipated: RascalRally's
`StoryFlow.luau` carried THREE separate functions
(`_layerRectOf`/`_centreOf`/`_layerPoint`) each reading `screenRectOf(path)`
and `screenRectOf(layerPath)` and subtracting the two rects by hand to
convert a window-space rect into the HUD layer's own space. `screenRectOf(path,
relativeTo?)` (`renderer.luau`) takes an optional second path and returns the
first rect translated into the second's origin, in one call; `nil` when
either side is not live; a node relative to itself is `{x=0,y=0,w,h}`.
`StoryFlow:_layerRectOf`/`_centreOf` (the two that read a mounted PATH, not a
raw point) now call it directly, deleting the by-hand subtraction; `_layerPoint`
(which converts a raw point, not a node's own rect) is unchanged — a genuinely
different shape, not this gap's business.

**Item 38 (`registry.ghostRect()`) — DISPOSED, measured.** Census (both
repos, production code and tests): no Facet construct computes "where is the
currently-dragged ghost painted" by querying a registry — `table.luau`'s
`DragGhost` and RascalRally's `HandDock`'s `CardGhost` both position their
ghost DECLARATIVELY (reactive `offsetX`/`offsetY` memos, or a computed
`slotStagingPoint`/`armStaging` target), never reading it back. The one
"ghost rect" reach-around found is `games/RascalRally/code/tests/facet_sponsor_cards.spec.luau`'s
local `ghostRect()` helper — a TEST-only function scanning proxy paths for a
`/CardGhost` suffix and reading `presentedPosition or rect` — a single,
stable test-assertion helper, not a production pattern two independent sites
grew. No `src/input/drag_registry.luau` (the "registry" home the audit's bare
name most plausibly points at) consumer needs this: `registry.dump()` already
exposes `sourcePath`/`payload`/`pointerPosition`, and nothing reaches around
it for a ghost's *painted* rect specifically. Nothing shipped.

### Reactive-props trio (16, 20, 33) — three BUILD, one bundled

**Item 16 (`offset` takes numbers, not Readables) — BUILT.** Full decision in
[ADR-0026's 2026-08-23 amendment](ADR-0026-authored-presentation-composition.md#amendment-2026-08-23--offset-a-fourth-authored-term-framework-gaps-phase2-gap-16).
Summary: `offset` joins `scale`/`rotation` as a fourth authored presentation
term (`{x=,y=}`, paint-only, composes ADDITIVELY), closing the live DELETE#5
bug — `p2_cartwheel/screens/celebration.luau`'s every-frame `app.onTick`
calling `setPresentationTransform` even at rest. `celebration.luau`'s dip is
now a `bottleOffset` memo bound to the `Bottle` button's `offset` prop, the
same shape `dashboard.luau`'s neighbouring `tallyScale` memo already used for
`scale` (that file's own comment, which named `offset`'s missing declarative
twin as the reason `celebration.luau` "correctly" stayed imperative, is
updated in the same edit — a stale comment is a bug per `ENGINEERING.md`).

**Item 33 (a transformed-footprint reservation, audit-marked "teaches-wrong
12") — BUILT, the SMALLEST honest form.** The audit named two shapes: a pure
`Facet.layout.transformFootprint(w, h, scale, deg)` helper, "or better, a
`UI.reservedFor(bp, { scale, rotation })` that reserves automatically". The
second is a layout-solver feature (auto-reservation for any scaled/rotated
child, a multi-file solver change) — out of scope for one round alongside ten
other items, and not what the round's own evidence asked for: the ONE real
consumer, `examples/gallery/scenarios/nested_compositing.luau`, already
reserves manually (a plain sibling box, per the framework's own documented
pattern) and only wanted the TRIGONOMETRY computed rather than hand-transcribed
— its own comment named exactly this function as the owed API. Built the pure
form: `src/layout/transform_footprint.luau`, published at
`Facet.layout.transformFootprint`, reproduces `api.md`'s exact device
measurement (100×70 @ scale 1.5/rotate 30° → 183×166, rounded up) and is now
what `nested_compositing.luau`'s `turnedFootprint` calls, with its own
`FOOTPRINT_SLACK` buffer kept as a caller-side choice, not baked into the
formula. RR census: no hand-rolled scale+rotation footprint math found
anywhere in `games/RascalRally/code/src` — clean negative, no migration owed,
reachability pinned instead (`facet_node_facts_and_offset_contract.spec.luau`).
The auto-reservation half stays a design-pass candidate, not silently folded
in — see "Alternatives".

**Item 20 (`newMenu.presentation` is a static string) — BUILT.** Census found
`sizeClass`/`interactionClasses` (the file's OTHER two adaptive facts) already
accept `Readable`s — the audit's own adjacent citation (teaches-wrong #8, an
inert `sizeClass`) reads as ALREADY FIXED by an earlier round; only
`presentation` itself, when the author FORCES a non-`"automatic"` value, was
frozen at construction. `presentation` now accepts `string | Readable<string>`,
riding the exact `presentationMemo`/hot-switch machinery the file already
built for `sizeClass`/`interactionClasses` (`scope:own(core:observe(presentationMemo,
...))`, proven live by the pre-existing "a live class flip while a submenu is
open CARRIES the open path" test) — so a forced-then-flipped presentation
re-presents an OPEN menu exactly like an automatic resolution already does,
with zero new machinery. A static misspelling still fails fast at
construction (unchanged behavior); a reactive value out of domain is refused
loudly on `core:lastError()` at the read site rather than thrown synchronously
through `pres.refresh()` — the reactive core QUARANTINES a memo compute error
by design (`src/core/custom.luau`'s `fail()`/`lastError` mechanism, the same
one `an equality callback error quarantined` uses), unlike `scale`/`rotation`/
`opacity`'s domain check, which lives in the renderer's plain commit walk and
genuinely throws. Documented as a deliberate architectural difference, not an
inconsistency to paper over — see "What is NOT built, stated plainly".

### Schema pair (17, 18) — both DISPOSED, formalizing G3's evidence

**Item 17 (Table content-hugging height / header+body-union column sizing) —
DISPOSED, measured.** G3's report (§6, `task-g3-report.md`) already read
`table.luau`'s row-height arithmetic directly: `family.rowLines[paradigm] *
lineBox + 2 * padV + artV`, a multi-factor computation over the table's own
theme family, never published as a single resolvable metric path — closing it
needs Table to publish that arithmetic as a metric or grow its own
`rows`-shaped height prop, neither of which is this round's content-terms
machinery (`{type="content",lines=n}`/`{rows=n,of=metric}`) as-shipped. Checked
against the LIVE tree this round (`table.luau:520`'s `rowLines` arithmetic
still unpublished, unchanged since G3): the evidence holds. The column-sizing
half is a WIDTH concern, architecturally unrelated to a height dim, and was
never in scope for either G3 or this round.

**Item 18 (no `"intrinsic"` minimum outside `UI.Grid`) — DISPOSED, measured.**
G3 checked `blueprint_schema.luau`/ADR-0040 B-2 directly: `"intrinsic"` names
a WIDTH-axis MEASUREMENT (`UI.Grid.minColumnWidth`, "as wide as the content
naturally needs") — architecturally the opposite of `lines`/`rows` (a FORMULA
independent of measured content, height axis). Same home file as gap 3/item
14's "noun layer" wave, not the same shape. Re-checked this round: no
`"intrinsic"`-outside-Grid site landed anywhere in the tree since G3; the
evidence holds unchanged.

Neither item was re-litigated from scratch — new evidence would be needed to
overturn a G3 finding this round did not find, per binding-context's own rule
("Don't re-litigate a ruling without new evidence — cite the number and
supersede explicitly").

### The remaining pair (21, 22)

**Item 21 (construct lifecycle facts are `dump()` snapshots, not Readables,
"two files independently invented the same write-skip poller") — DISPOSED,
measured.** Fresh census (the audit names no file/line): `grep`'d every
`.dump()` call site across both repos (184 non-test hits, 61 files),
cross-referenced against every timer/loop construct
(`RunService`/`Heartbeat`/`RenderStepped`/`onTick`/`while true`/`task.spawn`,
20 files matching both), and inspected each for a "read `.dump()`, compare to
a stored previous snapshot, act only on a change" shape. Zero genuine matches:
every `.dump()` call found is a one-shot, on-demand read (a test driver's
`steps.X = function() return control.dump() end` idiom, or a synchronous
snapshot embedded in another diagnostic) — none stores a previous snapshot
inside a tick loop and compares. Separately grepped
`wasOpen|wasMounted|lastOpen|lastMounted|prevOpen|prevMounted` repository-wide;
both hits found are false positives (a diagnostic signal set once on an
explicit event, and a synchronous local flag inside one function call, neither
a poller). Either the audit's citation was already fixed by an earlier round,
or it never corresponded to surviving code; either way, nothing to build
against today's tree.

**Item 22 (a control's native scroll must be bound imperatively after
`present`) — DISSOLVED, demonstrated.** Fixed BEFORE this campaign
(2026-08-15, O-31 — `src/controls/native_scroll_binding.luau`'s own header:
*"Until 2026-08-15 that mirror only existed if the CONSUMER called
`bindNativeScroll(controller)` after `present`... the framework binds it
itself now and the public call is an override rather than an obligation"*).
`tests/native_scroll_autobind.spec.luau` is the framework's own live
demonstration; RascalRally's `facet_motion_and_scroll_contract.spec.luau`'s
C-SCROLL case ("this game's sponsor list follows an engine scroll with NO
`bindNativeScroll` call") is the production consumer's. Nothing shipped this
round — the audit's own citation predates a fix that already exists, exactly
the "STAYS OPEN, evidence gathered not assumed" shape this campaign applies
when re-checking a stale claim against a moved tree.

### VirtualList's own gap (40)

**Item 40 (`list.api.positionOf(key)`) — BUILT, small.** No standalone `List`
construct exists in this framework (`src/controls/list.luau` does not exist;
the audit's home guess is "inferred"); `VirtualList` is the nearest analog and
already computes what this needs internally — `indexByKey`, the live
per-key-index map `virtual_window.luau`'s hover/drag/pin machinery already
reads, was simply never exposed. `list.positionOf(key) -> number?` is a thin
public wrapper over the existing map: free, no new bookkeeping, answers a
key's current 1-based index in `spec.rows`. RR consumes `Facet.Controls.VirtualList`
directly (`FacetSponsor/RacerList.luau:916`) but has no hand-rolled index
lookup to migrate (censused — clean negative); reachability is pinned through
the SAME entry point RR's own list is built from
(`facet_node_facts_and_offset_contract.spec.luau`), not a private
`virtual_list.build` reach-around.

## What is NOT built, stated plainly

- **Item 33's "or better" auto-reservation form** (`UI.reservedFor`) is not
  built. The pure `transformFootprint` helper closes the audit's OWED-API
  citation and the one real consumer's need; solver-integrated automatic
  reservation for every scaled/rotated child is a separate, larger design
  question (does it change every container's measured box when a descendant
  authors `scale`? does it interact with `ViewThatFits`?) that this round's
  evidence does not require an answer to.
- **A reactive `menu.presentation`'s domain-check does NOT throw synchronously
  through `pres.refresh()`**, unlike `scale`/`rotation`/`opacity`'s. This is a
  genuine, deliberate consequence of where each check lives (a `core:memo`
  vs. the renderer's plain commit walk), not an oversight — the reactive
  core's own quarantine design exists precisely so one screen's malformed
  reactive value cannot crash an unrelated surface mid-frame. Flagged for a
  future reader who expects the two paths to behave identically; they do not,
  by design, and `tests/menu.spec.luau`'s own case documents why in place.
- **`offset` does not participate in a `withAnimation` flight's interpolation**
  (see the ADR-0026 amendment) — no consumer has asked to animate a CHANGE of
  authored offset yet, as distinct from animating a node's solved position via
  `withAnimation` itself, which already works.
- **Items 21 and 38 ship no code.** Both are honest DISPOSE-with-census
  outcomes: a fresh, described search found no surviving evidence for either
  citation.

## Alternatives, and why not

**Fold item 33 into a full `UI.reservedFor` auto-reservation feature this
round**, matching the audit's "or better" phrasing literally. Rejected: the
audit itself frames the two as alternatives, not a required escalation; the
smaller form closes the actual owed-API comment and the actual consumer's
need, and a solver-integrated feature touching every scaled/rotated
container's measured box is exactly the kind of "flag refactors, don't
smuggle them" scope `ENGINEERING.md` warns against landing inside an
eleven-item round.

**Build a `registry.ghostRect()` anyway, to literally match item 38's audit
name.** Rejected: no production consumer exists on either side of the
lockstep, live or historical (both drag-ghost implementations found compute
their position declaratively and never read it back); a speculative export
with no reader is the same "framework should own this floor ahead of a need"
shape this campaign's gap-3/gap-14/W3-A rounds already refuse to ship.

**Re-open items 17/18 with a fresh design pass** (a Table row-height metric
publication, or an `"intrinsic"` height-axis form) rather than formalizing
G3's DISPOSE. Rejected: no new evidence surfaced this round that G3's
evidence-gathering missed or got wrong; binding-context's own rule is not to
re-litigate a ruling without new evidence, and a design pass for either is a
correctly-scoped FUTURE mission (Table height metric publication; a possible
height-axis sibling to `"intrinsic"`), not a mechanical extension of this
round's node-fact/reactive-prop work.

## Consequences

- Nine top-level surfaces gained (or, for 21/22/38, explicitly did not gain)
  capability: `controller.mountedPathOf`, `screenRectOf`'s `relativeTo`,
  `offset` (blueprint prop, every rendered class), `Facet.layout.transformFootprint`,
  `newMenu.presentation` as `Readable<string>`, `VirtualList.positionOf`, and
  `paths.stripThenSegments` (a shared internal helper, not itself
  `Facet`-table-exported — same non-eligibility precedent as `src/measure.luau`
  the surface ledger already carries for `text.AVG_GLYPH_FRACTION`).
- Every new surface is purely ADDITIVE: no existing required/default flips, so
  the ADR-0040 register gains no row this round.
- Two real, live consumer sites lost their workaround: `p5_wardrobe/init.luau`'s
  dead `adapter.paths()` enumeration (item 15), and `celebration.luau`'s
  every-frame imperative write (item 16). One got a strict simplification
  (`StoryFlow.luau`'s three rect-subtraction copies, item 37).
- `src/render/renderer.luau` grew 190,088 → 192,666 chars (re-recorded,
  `docs/handoff/SOURCE_CAP_LEDGER.md`) — still 7,334 clear of the 200,000
  write cap, and the growth is nowhere near the recycle-pool/parked-props
  block that row's own trigger watches.
