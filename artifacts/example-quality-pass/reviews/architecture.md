# Architecture review — example-quality-pass (roadmap Step 10)

**verdict: ACCEPT-WITH-FINDINGS**

Reviewer scope: the six changed framework source files, the `examples` scenario's
lifecycle, and whether `tools/lune/check_example_drift.luau` mechanically enforces
the ledger's central claim. Read-only; nothing was edited. Findings are ordered
BLOCKER / MAJOR / MINOR. No BLOCKER found — every finding below is a correctness or
one-authority gap inside a change whose *direction* I judge correct.

Summary of the five questions:

| Question | Answer |
|---|---|
| Is `assertEnumValue` in the right layer? | Direction right, **seam wrong**. It is not "the one place a bound value lands"; it is the one place a bound *paint/semantics* value lands. It covers 5 of the schema's 21 enum PropSpecs and misses every layout-channel enum, including `itemSizing`, which this same stage newly depends on. `src/mount.luau:511-521` is the cheaper, complete, better-placed seam. |
| Is `linkGridBoundaries` sound? | Sound for the shapes it was tested on; **it can link a grid to a group that is not its visual neighbour** on any screen that mixes an auto-derived Grid with an input contribution. It also derives structural identity by parsing a group *name*. |
| Does the `rating.luau` change alter the public contract? | **No public contract change** (Spec, key set, dump schema, focus-stop count all unchanged) and the director ruling's four requirements survive. One behaviour is traded: the strip now has no floor under the glyph. |
| Is the `text_metrics` change safe for measure >= paint? | **Safe in the interior**, byte-identical for single-spaced and newline gaps as claimed. **Leading and trailing space runs are still unreserved**, which is the unsafe side of the same invariant, and multi-space strings can now change line count (not just width). |
| Does the `examples` scenario leak? | Two leaks and one ordering inversion: a failed `install` orphans the controller permanently, `dispose` runs *before* `dismiss`, and the runner keeps a stale handle after a re-select. |

---

## MAJOR

### M-1 `assertEnumValue` is not the choke point it claims to be — 11 enum props stay unguarded
`src/render/renderer.luau:1450-1483`, called from `:1488` and `:1510`.

The comment at `:1463` says "This generalises it to every enum prop, at the one place a
bound value lands," and `ownership-ledger.md` §A F-1 repeats it ("**every** enum prop").
Both are false as written. `assertEnumValue` runs only inside `applyProp`/`applyStyleProp`,
which are reached only for `BINDING_PROPS` (`:39-67`) and `STYLE_PROPS` (`:76-106`). The
covered enum props are exactly five: `Box.surface`, `Text.surface`, `Text.role`,
`Button.role`, `textAlign`, `scaleMode`, `shape`.

Every enum prop whose `dirty` channel is `measure`/`arrange` (or which is read by the
presenter rather than the adapter) is consumed by the solver, never by `adapter.setProp`,
and is therefore still accepted-and-silently-ignored when bound:

- `anchor` — `src/blueprint_schema.luau:479-484`
- `alignH` / `alignV` — `:506-511`, `:515-520`
- `overflow` — `:590-595`
- `align` (shared `ALIGN`) — `:634-639`
- `reveal` — `:747-749`
- `axis` — `:908-911`, `:1012-1016`, `:1173-1177`
- `minColumnWidth` — `:973-979`
- **`itemSizing`** — `:985-993`
- `width`/`height` `sizing` (`hug` | `fill`) — `:1117-1120`
- `focusVisual` — `:1633-1637`

`itemSizing` is the one this stage newly leans on, in `src/controls/rating.luau:298-301`
and in examples 05/06/07. A bound `itemSizing = "unifrom"` today reproduces F-1 exactly:
accepted at construction because bindings skip `schema.checkValue`, then silently
resolved as `natural`.

**Required change (either):**
(a) Move the check to `src/mount.luau:511-521`, which *is* the one place every bound
value lands — `node.props[propName] = value:get()` at `:513` and
`node.props[propName] = newValue` at `:516`. That site already requires the blueprint
module (`blueprintLib.PROP_DIRTY` at `:509`), so it adds no dependency edge; it runs
once per binding *evaluation* instead of once per prop *write*; it covers all four dirty
channels; and it names the binding rather than the paint. Keep the renderer copy only if
a control can synthesize a prop value after mount (I found no such path).
(b) If (a) is out of scope, then correct `renderer.luau:1463` and the ledger to say
"every enum prop on the paint/semantics channels", and open a named follow-up for the
layout-channel half. A ledger that overstates a closure is how the *next* reviewer stops
looking.

**Smallest corrective test:** in `tests/authoring.spec.luau`, bind `itemSizing` (or
`overflow`) to a memo returning a non-member and assert the same refusal the `surface`
case gets. It fails today.

### M-2 `linkGridBoundaries` can link a grid to a group that is not its visual neighbour
`src/present/focus_map.luau:513-547`, called at `:611` and `:693`.

The inference is "the group at `index-1`/`index+1` in the array is the visual neighbour."
That holds for groups this module *itself* emits (`auto-flat-*`, `auto-v-*`, `auto-h-*`,
`auto-grid-*`), because they are appended in document order by a single depth-first walk.
It does **not** hold for contribution-supplied groups. At `:569-577` a contribution's
whole bundle is spliced in at the contribution's document position, in whatever order
`bundle.focusGroups(node)` chose to return them — there is no rule anywhere that
`focusGroups[1]` is the topmost group of that subtree. So on a screen shaped
`Grid -> <control that contributes focusGroups>`, `exit.down` from the grid's last row is
set to `contributionGroups[1]`, which may be that control's *last* visual row.

Two secondary cases in the same class:

- **Visual order != document order.** A Grid inside a `UI.ZStack` (or beside an overlay /
  toast / floating card) gets `exit.down` pointing at the overlapping sibling's group,
  which is not below it in any sense a player would recognise.
- **Empty-after-filter targets.** `filterGroupsHidden` (`:119-140`) keeps a group whose
  `order` filters to zero members (it clones and inserts, it does not drop). Exits are
  computed *before* that filter, so a grid adjacent to a fully hidden group (a losing
  `ViewThatFits` candidate) can be handed an exit into a group with no members. Not a
  regression — the grid was a dead end before this change — but it is the same dead end
  F-2 exists to remove, and it is now silent instead of obvious.

**Required change:** restrict the inferred exit to groups this derivation produced, i.e.
only accept `before`/`after` whose `name` begins `auto-`, and skip a candidate whose
filtered `order` would be empty. If a contribution neighbour must be reachable, resolve
the target by geometry (nearest group by solved rect) rather than by array index — the
array is a document-order artifact, not a spatial one, and every other spatial decision
in this file (`entry = "nearest"`) already uses rects.

**Smallest corrective test:** `tests/auto_input_screens.spec.luau` — a screen of
`Grid` followed by a control whose `focusGroups` returns `{ bottomRow, topRow }` in that
order; assert Down from the grid's last row lands in `topRow`, not `bottomRow`.

### M-3 `recoverPressDip` writes the PRESENTATION channel's UIScale
`src/client/screen_target.luau:1252-1263`, used at `:1270` and `:1292`.

`local scale = handle.motionScale or handle.uiScale` (`:1254`) — `handle.motionScale` is
**not** the press dip's scale. It is created and owned by `applyPresentationPaint`
(`:1796-1801`) for the presentation authority (`controller.setPresentationTransform`), and
its liveness is load-bearing elsewhere: `parkEligible` refuses to recycle a handle that has
one (`:4026`). `recoverPressDip` unconditionally tweens/sets that instance to `Scale = 1`.

So a bespoke-path button that receives a mouse release *while a presentation scale is live*
— a pop, an enter `materialize`, a drag ghost's pickup lift — has the presentation
transform's scale snapped to 1 by the interaction-state path, with no one re-asserting it
(the presentation write is idempotent-on-change and will not fire again). The same is true
of the press *down* at `:1272-1281`, since `ensureScale` (`:830`) returns the existing
`motionScale` too.

This is pre-existing on `MouseLeave`; F-3 **extends it to every mouse release**, which is a
far more common event, so the exposure is materially wider after this stage than before it.
It is a straight one-authority violation: two authorities writing one engine property, with
the lower-priority one winning last.

**Required change:** the press dip must own its own `UIScale` (a second, dip-only instance,
or a `handle.pressDipScale` field), and `recoverPressDip` must restore *that*, never
`motionScale`. If a second UIScale is unacceptable, record the presentation scale at
`MouseButton1Down` and restore to the recorded value rather than the literal `1`, and make
`assertBespokePaint` refuse a press-path write to `motionScale`.

**Smallest corrective test:** in the bespoke-path screen-target spec, call
`controller.setPresentationTransform(path, { scale = 1.1 })`, fire
`MouseButton1Down`+`MouseButton1Up` on that node, assert the handle's presentation scale is
still 1.1.

### M-4 `Table.rowGap` now has two resolvers, and they disagree when `spec.env == nil`
`src/controls/table.luau:276-288` (`rowGapPx`) versus `:1345` (`gap = spec.rowGap or 0`).

The ledger's claim is: "the blueprint keeps the declared value so the solver resolves it
live and the two can never disagree." The memo's own fallback breaks that:

```luau
local env = spec.env
local snap = if env == nil then themeSnapshot.neutral() else metricsOr(use(env:get("themeMetrics")))
return themeSnapshot.resolveNumber(snap, declared) or 0
```

`spec.env` is optional (`newTable` accepts a Table with no env). The blueprint's `gap`
metric name is resolved by the renderer against `currentMetrics()` — the **live** snapshot
(`src/render/renderer.luau:1502` shows the same resolution point for `thickness`) —
regardless of whether the control was handed an env. So an env-less Table with
`rowGap = "controls.table.rowGap"` under any non-neutral package paints one gutter and
computes its cumulative row tops (`:353`), content extent (`:365`), drop-slot boundary
(`:688`, `:693`) and keep-visible from **Studio Neutral's** number. That is precisely the
class of defect the ledger says the change avoids, and it is the reason `rowGap` was worth
widening at all.

**Required change:** refuse a metric-name `rowGap` at the authoring boundary when
`spec.env == nil` (the ledger already says an unresolvable name is refused there — this is
the same refusal, one condition wider), or make the blueprint carry the *resolved* number
from the same memo so there is one authority instead of two.

**Smallest corrective test:** `tests/table.spec.luau` §"Table.rowGap" — build a Table with
a metric `rowGap` and **no** `env` under a non-neutral snapshot; assert the drop-slot
boundary matches the solved row tops. It should fail today, or the constructor should
refuse.

### M-5 The drift lint does not cover the ledger's central claim
`tools/lune/check_example_drift.luau:82-150` (R1-R4), `:154-175` (allowlist).

The claim under review is: "domain/content logic plus declarative composition, with **no
workaround, platform branch, raw GUI/input bypass or parallel control machinery**." R1-R4
are a values-and-engine-reach lint. Mapping the claim onto the rules:

| Claim clause | Covered by | Verdict |
|---|---|---|
| no style literals | R1 (7 prop patterns) | covered, **first-order only** |
| no invented semantic values | R2 (3 props) | covered for `textSize`/`surface`/`role` |
| no raw colour | R3 | covered |
| no raw GUI / input bypass | R4 (8 denylist patterns) | **partial** |
| no platform branch | R4 `UserInputType.Touch` only | **essentially uncovered** |
| no parallel control machinery | — | **not covered by any rule** |

Concretely:

1. **The device branch this stage removed would not be caught if it came back in a
   theme-metric spelling.** §D's headline removal was `07_match3.luau`'s
   `sizeClass -> 40 / 56 / 72`. R1 catches it only incidentally, through the px literals.
   Rewritten as `local cell = ({ compact = "controls.small.height", regular = "controls.large.height" })[sizeClass]`
   it passes all four rules: no literal, no colour, no engine reach, no `UserInputType`.
   Adaptation is the property the plan assigns to LuauUI by name, and it is the one with no
   mechanical rule. **Required: an R5 that bans an example reading `sizeClass`,
   `preferredInput`, `interactionClasses`, `safeArea*` or `viewport*` off `env` — with an
   allowlist entry for any legitimate content use.**
2. **R4 checks exactly one method on the adapter.** The examples are handed
   `adapter = ctx.adapter` in their `deps` (`examples/gallery/scenarios/examples.luau:110-115`),
   so every adapter method except `setProp` is invisible to the lint — as are
   `RunService`, `Players.LocalPlayer`, `ScreenGui`, `:GetPropertyChangedSignal`, and
   `Instance.new` behind a local alias. If the `deps` table is "the documented composition
   seam", the lint should assert the *shape* of what an example may pull out of it
   (an allowlist of deps keys and adapter methods), not deny eight spellings.
3. **R1/R2 are line-local regexes.** `textSize =\n\t14`, `textSize = SIZES[i]`, and any
   value routed through a local all pass. That is an acceptable limit for a lint, but it
   means "enforced mechanically" is really "enforced against the obvious spelling"; the
   ledger should say so.
4. `isComment` (`:172-175`) only skips lines that *start* with `--`, so a trailing comment
   containing a banned pattern false-positives. Cosmetic.

**Required change:** add R5 (platform/adaptation reads) and widen R4 from a method
denylist to a deps/adapter allowlist, or soften the ledger's Disposition paragraph to the
three clauses the lint actually proves.

---

## MINOR

### m-1 The refusal is thrown after the dirty queue has been drained
`src/render/renderer.luau:2940` (`local dirty = root.takeDirty()`), `:2975-3001` (the commit
loop), `:3002` (the solve block).

`assertEnumValue` raises inside `applyProp`/`applyStyleProp`, which run inside the commit
loop, which runs **after** `takeDirty()` has already emptied the mounted graph's queue and
**before** the solve/arrange block. One bad bound enum therefore (a) throws out of
`controller.refresh`, (b) permanently discards every remaining dirty entry in that batch,
and (c) skips the solve. The surface is left partially written and unsolved, and nothing
re-queues the lost work even if the app's next state change is legal. Compare
`src/blueprint.luau:430`, which refuses at construction where nothing has been half-written.

This is inherent to validating at the write site and is the strongest argument for the
`mount.luau` seam in M-1: a throw there happens before the dirty entry is queued and
before any partial write. If the renderer seam stays, `refresh` should re-queue the
undrained entries on a failed write (or the failure mode should be documented as
"one refused bound enum wedges the surface").

**Smallest corrective test:** bind two props on two nodes, make the first illegal, assert
the second node's legal change is still applied on the following frame.

### m-2 Per-write schema lookup on the mount path
`src/render/renderer.luau:1488`, reached from `:1523-1525` for every binding prop of every
created node.

`assertEnumValue` also runs over **static** values that `schema.checkValue` already
validated at construction — pure duplicate work, on the path Step 9 identified as the
frame's largest single component (`LuauUI/mount`). Per string-valued prop it is
`schema.forClass` + a props index + a nil test (three hash lookups); `text` is a string and
is the most-written prop in the framework. Not a blocker at this size, and I did not
measure it. If the mount ramp moves, memoize a flat `class .. "\0" .. prop -> enum|false`
table built once, or (better) take the M-1 seam, which pays once per binding evaluation
rather than once per write.

**Check not run:** I did not benchmark. `bench/` has the mount-ramp workload;
an A/B with the call stubbed would settle it.

### m-3 `linkGridBoundaries` derives structural identity by parsing a group name
`src/present/focus_map.luau:514-521`.

`gridPathOf` re-derives "is this a grid row, and whose" from
`string.match(name, "^auto%-grid%-(.*)%-r%d+$")`. Group names are author-visible: an
explicit `navigationGroups` opt or a contribution's `focusGroups` may name a group
`auto-grid-anything-r1`, and it will then be treated as a grid row and given synthesized
exits. The greedy `.*` happens to survive a node id containing `-r12`, but only by luck of
greediness. `emitGridGroups` (`:485-492`) already builds these tables; it should stamp
`gridPath = node.path` on each and `linkGridBoundaries` should read the field. Exact,
cheaper, and unforgeable.

### m-4 The two focus derivations disagree about a Grid inside a contribution subtree
`src/present/focus_map.luau:569-577` (autoGroups returns without descending) versus
`:668-672` (layoutGroups has no contribution awareness).

Which derivation runs is decided at `src/present/presenter.luau:2250-2262` by whether *any*
mounted contribution declares `focusGroups`. So the same Grid gets per-row 2D navigation
with boundary exits under `layoutGroups` and no grid groups at all under `autoGroups`,
decided by an unrelated sibling control. Pre-existing, but `linkGridBoundaries` now makes
the divergence observable at the boundary as well as the interior, and the ledger's F-2
proof ("run over the finished group array in **both** derivations") reads as if the two are
equivalent. Worth one sentence in the module comment, or a test that pins the divergence
deliberately.

### m-5 Leading and trailing space runs are still unreserved
`src/layout/text_metrics.luau:404-420`.

The change is on the safe side of measure >= paint for interior runs, and the byte-identity
claims hold exactly as stated: a single space gives `math.max(gsub(gap, " "), 1) == 1`
(`:415`), and a newline-only gap gives `max(0, 1) == 1`, so
`docs/lessons/embedded-newlines-measure-as-one-line.md` is untouched. Confirmed.

But `extra` is only added when `lineWidth > 0` (`:408`), so a **leading** space run
(`"   hello"`) reserves nothing, and gmatch's `(%s*)(%S+)` never yields a **trailing** gap
at all, so `"hello   "` reserves nothing either. Roblox's `TextLabel` does render leading
spaces. That is measure < paint — the unsafe direction, in the very function this stage
touched to fix the safe one. The magnitude is small (n × ~2.5 px) but it is the same defect
family, one character position away.

**Required change:** count the leading gap and the trailing `string.match(text, "%s*$")`
run at the same rate, or state in the comment that boundary whitespace is deliberately not
reserved and why.

**Smallest corrective test:** measure `"  ab"` and `"ab"` at a font where the space width is
exact, and assert the first is wider.

### m-6 Multi-space strings can now change line COUNT, not just width
`src/layout/text_metrics.luau:417-421`.

`extra` participates in the break decision `lineWidth + extra + wordW > maxWidth`, so a
string with interior space runs can now wrap one word earlier than it did before this
stage. Line count feeds height, `truncated` and `lineLimit` verdicts. The direction is safe
(more reserved), but it is consumer-visible geometry, and the ledger presents the change as
width-only ("a run of spaces reserves its own width"). Per the root `CLAUDE.md`, this is
exactly the kind of change that owes a Rascal Rally compatibility test or evidence.

**Check not run:** I did not grep the RR string table for multi-space labels. Command:
`grep -rn '"[^"]*  [^"]*"' /Users/josha/Dropbox/Documents/UntitledRacingGame/games/RascalRally/code/src --include=*.luau`.

### m-7 `rating.luau`: the public contract is intact; one behaviour is traded
`src/controls/rating.luau:298-320` (the Grid), `:268` (the star's `width = { type = "hug" }`),
`:275` (the ZStack root), `:322-350` (the Grip).

Contract: `Spec`, `RATING_KEYS`, `api.dump()`'s `luauui-rating-dump/1`, `semanticText`,
`onInteractionClassLost`, and the scrub/adjust seams are all unchanged. The director
ruling's four requirements survive the swap:

- *one focus stop* — the `Grip` is a sibling of the Grid inside the ZStack, not a child of
  it, so `focusableCount(Grid) == 0` and `emitGridGroups` never fires for a Rating. The
  strip keeps exactly one focus stop, and M-2's boundary linking cannot touch it. Verified
  by construction against `focus_map.luau:583` and `:668`.
- *the run groups (gap stays the theme's, not the caller's)* — `itemSizing = "uniform"`
  makes the pitch `innerWidth / columns` and the Grid still hugs, so `innerWidth` is
  content, so the pitch is the widest glyph. Preserved.
- *capped at the offer* — `width = { type = "hug" }` on both the Grid and each star.
  Preserved.
- *centred in its cell* — `alignH = "center"` on a ZStack child. Still the documented
  position (and note this is the same `alignH`-outside-a-ZStack class the ledger records
  as unfixed in §E — here it is used correctly, but a control now depends on a rule the
  schema cannot enforce).

What is traded: the HStack's failure mode was "two stars vanish"; the Grid's is "all five
shrink together". That is the better failure, and it is what the ruling asked for. But
neither shape has a **floor**: at a tight offer the uniform pitch can fall below the glyph,
every star's `hug` box clamps, and `TextTruncate.AtEnd` (set on every text node, per
`text_metrics.luau:461-467`) turns five stars into five ellipses. The old `minMax` cap at
the icon metric at least pinned the box to a theme number. Low severity because the
`semanticText` fallback exists, and the stage's own ten-foot finding was the *opposite*
failure.

**Smallest corrective test:** extend the existing rating layout test — at
`typographyScale = 3` in a 144 px column, assert every star's `textFits` is true (not merely
that the five widths are equal).

### m-8 `examples` scenario: three lifecycle defects
`examples/gallery/scenarios/examples.luau`.

1. **Orphaned theme controller on a failed install** (`:154-186`, `:161`, `:188`).
   `installed = controllerModule.install(...)` happens *inside* the `pcall`. If `install`
   throws after taking the env's `themeMetrics` fact, `installed` stays `nil`, the
   controller is unreachable forever, and — because `install` "REFUSES a second controller
   on an environment that already has one" — **every subsequent swap and the restore fail
   permanently**, which is the exact failure mode the comment block at `:128-139` was
   written to prevent. Required: assign to a local inside the pcall and to `installed`
   outside it, or have `install` be transactional.
2. **`dispose` runs before `dismiss`** (`:70-84`). `disposeCurrent` calls
   `current.dispose()` first and `presenter.dismiss(current.handle)` second. For examples
   1-4 that tears down the example's scope (its signals, memos and event wiring) while its
   screen is still mounted, and then asks the presenter to run a dismissal — including any
   exit transition — over a tree whose scope is gone. Both calls are `pcall`ed, so the
   symptom is silence, not an error. Required: dismiss, then dispose.
3. **The runner keeps a stale handle after a re-select** (`:120-122`, `:229-232`). `build`
   returns `handle = current.handle` once, as a snapshot. `step("select", n)` disposes that
   example and presents a new one, but the runner's `session.built.handle` still points at
   the dead first handle — so a teardown or any handle-keyed matrix step operates on it,
   and the first example's handle can be dismissed twice while the live one is dismissed by
   the scenario only. Required: return a `handle()` accessor (or have the scenario keep the
   runner's reference current) rather than a value captured at build time.

Not a leak: `uninstallCurrent()` is correctly ordered before every install (`:161`, `:188`)
and is called from `dispose` (`:253`), and the scenario allocates no core scope of its own.

---

## Evidence and commands

Read-only inspection of:
`src/render/renderer.luau` (1-200, 1420-1530, 1955-2020, 2900-3020),
`src/blueprint_schema.luau` (415-443, 1265-1300, 1775-1832 and every `enum =` site),
`src/mount.luau` (480-549),
`src/present/focus_map.luau` (100-175, 380-726),
`src/focus/focus_graph.luau` (exit/containment surface),
`src/client/screen_target.luau` (1240-1300, 1790-1825, 4018-4035),
`src/controls/table.luau` (119-130, 270-300, 1335-1350, 1415-1440),
`src/layout/text_metrics.luau` (350-470),
`src/controls/rating.luau` (full),
`tools/lune/check_example_drift.luau` (full),
`examples/gallery/scenarios/examples.luau` (full),
`artifacts/example-quality-pass/ownership-ledger.md` (full).

Enum-coverage evidence (M-1) was produced by extracting every `enum =` PropSpec from
`src/blueprint_schema.luau` and intersecting it with `renderer.BINDING_PROPS` /
`renderer.STYLE_PROPS` (`renderer.luau:39-106`).

## Checks not run, and why

- **No test suite was executed.** This review is read-only and the stage's own gate
  (`artifacts/example-quality-pass/gate.json`) owns the green/red evidence. Every finding
  above is stated as a source-level claim with a named corrective test, so each is
  falsifiable by running that one test.
- **No benchmark for m-2.** The mount-ramp A/B in `bench/` would settle it; I judged the
  cost qualitatively (three hash lookups per string-valued prop write).
- **Rascal Rally consumer sweep not run** for M-1's new hard error or m-6's line-count
  change. Root `CLAUDE.md` requires the consumer work in the same task; I did not read
  `artifacts/example-quality-pass/consumer-impact.md` and cannot say whether it covers
  them. The two commands a follow-up should run:
  `grep -rn 'surface = \|role = \|shape = \|scaleMode = \|textAlign = ' <RR>/code/src --include=*.luau | grep -i 'memo\|signal\|derive'`
  and the multi-space grep in m-6.
- **`UI.Custom` escape-hatch contract** was not exercised: none of the six changed files
  touches it, and no example uses it.
- **Live/device verification** of M-2 and M-3 (both are engine-path behaviours) was not
  performed; both are stated from source and both have headless corrective tests above.
