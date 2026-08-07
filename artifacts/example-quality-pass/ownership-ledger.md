# Ownership ledger — tutorial gallery quality pass (EQ-2)

**Date:** 2026-08-06. Written against the source state this stage judges.

The plan's rule: *"Examples are deliberately thin consumers of LuauUI. They own
tutorial copy, deterministic fixture data, and domain/game rules… LuauUI — not each
example — owns choosing and executing layout, input paradigm, focus/navigation, hit
targets, scrolling, interaction states, accessibility, preferred-text/safe-area
adaptation, resource lifecycle, and reduced-motion behavior."*

Every custom helper, direct engine/adapter reach, device branch and workaround found or
proposed during this stage is below, classified as **example-domain**, **adapter/host
wiring**, or **framework-owned**. A framework-owned need was fixed behind a public
LuauUI API with tests **before** any example consumed it.

## A. Framework-owned needs found, and how each was fixed

| ID | The need | Where it showed up | The fix, in LuauUI | Proof |
|---|---|---|---|---|
| **F-1** | **A bound enum value outside its closed set was accepted and painted nothing.** `PropSpec.enum` exists precisely to stop `surface = "panel"` silently tagging a node with a selector no rule matches — but `schema.checkValue` runs at CONSTRUCTION, over a STATIC value. Example 05 bound `surface` to a memo returning `"tileEmpty"`/`"tileCorrect"`, and all thirty board tiles rendered at `BackgroundTransparency = 1`: the defect the enum was added to remove, re-entering through the reactive door. | Example 05, measured live: every tile `bgT = 1` | `src/render/renderer.luau` `assertEnumValue`, called from `applyProp` and `applyStyleProp` — the one place a bound value lands. Generalises the rule `tint` already had (`sheet_model.tintColor`: *"a bound tint is read long after construction, so this is the only place a reactive one is ever checked"*) to the enum props on the **paint and semantics channels** — `surface`, `role`, `textAlign`, `scaleMode`, `shape`. **It does NOT cover the layout channel** (`anchor`, `alignH`/`alignV`, `overflow`, `align`, `reveal`, `axis`, `minColumnWidth`, `itemSizing`, `focusVisual`), because those are consumed by the solver and never reach `adapter.setProp`. An earlier draft of this row claimed "every enum prop" and the architecture review (M-1) caught it. The complete seam is `mount.luau`'s binding write; moving it there is the recorded follow-up, and it matters because this stage newly depends on `itemSizing`. | `tests/authoring.spec.luau` — refused on first render, refused on a LATER set (so a valid first frame proves nothing), and a legal bound value on a non-surface prop unaffected |
| **F-2** | **`UI.Grid` was a focus dead end.** `emitGridGroups` links its rows to each other and sets `containment = true`; the first row got no `up` exit and the last row no `down`, and containment blocks the fall-through that lets stacked `HStack`s leak into their neighbours. Anything laid out after a Grid was unreachable by D-pad or arrow key. | Example 06: fourteen Downs from the bottom board row, focus never moved; the rack and the Start-over button were unreachable | `src/present/focus_map.luau` `linkGridBoundaries`, run over the finished group array in **both** derivations before the deferred grips group is appended. Adjacency in document order answers "what is above/below this grid", including an adjacent grid's last/first row. Authored exits are never overwritten. | `tests/auto_input_screens.spec.luau` — exit down, exit up, inner 2D nav and left/right containment unchanged, two adjacent grids handing off at the seam, and a grid ALONE on a screen still contained |
| **F-3** | **`MouseButton1Up` threw on every bespoke-path button press.** `screen_target.luau` referenced a bare `scale` that is declared nowhere in that scope — a nil global — while the sibling `MouseLeave` handler and the native-path `recover()` both read `handle.motionScale or handle.uiScale` and nil-guard. The dip is created lazily, so the release path threw on every press and the pressed dip only recovered if the pointer happened to leave afterwards. | Two clicks in example 07 produced exactly two `TweenService:Create failed because Instance is null` errors | `src/client/screen_target.luau` — one `recoverPressDip()` with the guard, used by both connections. Two copies of one rule is how the second copy went stale. | Studio console clean on re-run (EQ-16); the native path already had this function |
| **F-4** | **`newTable`'s `rowGap` accepted only a number**, while its sibling `cellPadding` has accepted *"a number or a theme metric name"* since it shipped, and `UI.Grid.rowGap` accepts a metric. `rowGap` is read in Luau arithmetic (cumulative row tops, content extent, drop slot), so a metric name reached `cum += height + rowGap` and threw. | Example 02, pointing at `controls.table.rowGap` instead of its literal `2` | `src/controls/table.luau` — a `rowGapPx` memo resolving a metric name against the live snapshot on every read, used by all three arithmetic sites; the blueprint keeps the declared value so the solver resolves it live and the two can never disagree. **The default is unchanged (0)**: this widens what the option accepts and moves nothing for an existing caller. | `tests/table.spec.luau` §"Table.rowGap" — number unchanged, spacing step, dotted path, the drop-slot seam that threw, and an unresolvable name refused at the authoring boundary |
| **F-5** | **`UI.Table`'s header band was a fixed-px CAP against unfixed content.** The header cell was `height = { type = "fixed", px = "controls.table.headerHeight" }` — 28px. At a raised text preference a ONE-LINE column title measures 34px, so the title painted out of its own ZStack: up into the auto Edit toolbar and down into the first row. Same defect class as the row box (`paradigm_table.spec` §3) and as the whole [fixed-px-heights] family. **The solver had been filing the finding the entire time** — `Head-<id>/Title :: overflows its zstack by 0x6px … give the box room — a `minMax` FLOOR rather than a fixed CAP` — and nothing in the suite failed on `controller.diagnostics()`, so it was never read. | Example 02, device-reported at Largest text on compact phone portrait AND landscape, under both reference packages (EQ-6 / LT-F3). The example authors no toolbar and no header geometry. | `src/controls/table.luau` — the header cell is now `{ type = "minMax", min = "controls.table.headerHeight" }`. The token is what a header band must never be SHORTER than; the live text facts decide how much taller it has to be, so the header grows with the preference and pushes the body down instead of drawing through its neighbours. **The default is unchanged at the shipped text size** (band still resolves to exactly 28). | `tests/table.spec.luau` §"Table: toolbar, header and body stack at every text preference" — three cases over {0,4,10,14} x {compact portrait, compact landscape}: the diagnostics list is EMPTY, the painted headings never enter the toggle or the first row, and the band grows. All three mutation-proved. Plus `tests/lib/large_text_fixtures.luau` now mounts the Table with `reorderable`, so the LT-8 sweep actually contains the toolbar it collided with. Live A/B in one Studio session (pre-fix -1px, post-fix +2px, both packages) in `studio/large-text.json`. Consumer check: `games/RascalRally/code/tests/luauui_racer_list.spec.luau` — the racer list is headerless, asserted at Medium AND Largest |


## B. Gallery-host (adapter/wiring) needs

The gallery bootstrap is the HOST, not an example. It legitimately sets workspace
attributes, disables CoreGui features and owns the theme picker. These are its bugs.

| ID | The need | Fix | Proof |
|---|---|---|---|
| **H-1** | **The theme picker covered the example it exists to restyle.** The tutorial path mounted it permanently expanded at `DisplayOrder 10200`. Measured on desktop: panel `x 339..899, y 8..219` over example 01's field `x 16..891, y 78..122`; on a 360×691 phone it covered the example entirely. `collapsible = true` existed but was only ever paired with `composed = true`, so the standalone shell carried the *showcase's* geometry — docked top-left and lifted `-BAR_HEIGHT` into a strip only the showcase reserves. | `theme_picker.luau`: the standalone collapsed shell docks **top-right** with no lift; `init.client.luau` mounts the example picker collapsed. The non-composed handle also gained the `open` and `pickPackage` seams the composed one already had — two returns from one function offering different powers is how the showcase's own theme route once shipped as a nil global. | `tests/gallery_theme_picker.spec.luau` §"the standalone collapsed shell" — collapsed by default, docked right, nothing painted left of x=600, opening is a `When` not a rebuild, the scriptable seams work, and the chip fits a compact phone |
| **H-2** | **Tab bound nothing in the gallery.** `newPresenter` was created with no opts, and `keyboardNavigation` defaults FALSE — while this same bootstrap disables the CoreGui players list a hundred lines below *precisely so Tab can reach a developer InputContext*. Six Tab presses moved focus zero times, in all seven examples. | `init.client.luau` passes `{ keyboardNavigation = true }`. | EQ-15 device-matrix `VirtualInput` Tab rows |
| **H-3** | **The host answered the server for the player.** The demo-picker path flushed any `built.server.flush` every frame, which fixed "the first change goes pending and stays pending" by destroying the lesson: the pending state — the whole point of an optimistic-apply example — was answered before a player could see it. | Example 03 exposes `server.deliver` and a visible "Deliver server reply" button, so it does not opt into the auto-answer. The nil-guarded hook stays for a future example whose transport really should answer promptly; its comment now says so instead of describing behaviour that no longer applies. | `tests/examples_gallery.spec.luau` example-03 block |

## C. Example-domain logic — stays in the example

Not framework material, and deliberately not generalised.

| What | Where | Why it stays |
|---|---|---|
| Wordle scoring, the two-pass letter budget, the dictionary and solution lists, the monotonic key ladder | `05_word_game.luau` | Game rules. The plan says so by name: *"Do not move Wordle, tile, or match-3 rules into LuauUI merely because only one example needs them."* |
| Select-then-place, Scrabble point values, the refusal messages | `06_tile_game.luau` | Game rules and tutorial copy |
| Match/gravity/refill, the seeded PRNG, the opening-board deal, `hasLegalMove` | `07_match3.luau` | Game rules |
| The loopback server, its validation rule and its event history | `03_settings_sync.luau` | The plan requires a deterministic loopback and forbids adding networking to teach the transition |
| The numeric grammar (`acceptNumeric`) | `01_temperature_converter.luau` | An app's own validation, which is exactly what `validate` is for |
| The reorder-under-filter rule | `02_playlist_table.luau` | An app policy (the iTunes/SwiftUI convention); the Table hands the app the drop and the app decides |
| Track/rack/tile content, including the five tile-kind art records | `assets.luau`, each example | Content. The five ids are pinned to `standard_icons.ART` by a test so a re-upload fails loudly instead of blanking the board |

## D. Workarounds removed by this stage

| Removed | Was | Now |
|---|---|---|
| **A device branch inside an example** | `07_match3.luau` computed its own cell size: `sizeClass → 40 / 56 / 72 px`. That is imperative responsive geometry in a consumer — the plan bans it by name and assigns adaptation to LuauUI. | One theme metric (`controls.large.height`) on a `UI.Grid`. The example names no device. Its old test *asserted the defect* (`desktopW > phoneW`) and now asserts what matters: reflow with no remount, and a cell never below the touch floor at four viewports. |
| **Hand-rolled boards** | 05, 06 and 07 each built a `VStack` of `HStack`s of fixed-px cells | `UI.Grid` with `columns` + `itemSizing = "uniform"`, which also earns the 2D focus story (F-2) |
| **Invented paint tokens** | `surface = "tileEmpty" / "tileCorrect" / …` | `tint = { role = <theme role>, blend }` — themable, validated at the write site (F-1), and paired with a non-colour glyph cue |
| **Fake asset ids** | `assets.match3Tiles` held `rbxassetid://100000000n`, which draw nothing on a real client — all 36 tiles identical | Five of the framework's own shipped icons: five distinct SHAPES, real ids, cross-checked against `standard_icons.ART` |
| **A dead results modal** | example 05's `Close` button had no `onActivate` | `Close` and `Again` both wired; the card centres through a filling `ZStack` |
| **Style literals in all seven** | `textSize` 14/16/18/20/24/26/28, `padding = 16`, `gap = 4|6|8|12|16`, `px = 40|44|48` | Typography roles, spacing steps and theme metric paths, enforced by `tools/lune/check_example_drift.luau` (R1–R4, mutation-proved) |

## E. Accepted-and-ignored props found while playing

Both are the same class — a prop the schema takes and the runtime does not honour in
that position. **F-1** closed one of them mechanically. The other is recorded, not fixed:

- **`alignH` / `alignV` on a non-ZStack parent.** Documented as *"alignment inside a
  ZStack parent"*. Example 04 authored them on a `UI.Screen`, whose children stack
  vertically, so they were accepted and silently ignored and the "centred" dialog
  rendered at `16,16`. Both example 04 and example 05's results card now centre through
  a filling `UI.ZStack`, which is the documented shape, and example 04 has a test that
  asserts the card's centre sits within 2 px of the scrim's on both axes.
  **Not generalised in this stage:** making the schema refuse a ZStack-only prop under a
  non-ZStack parent is a parent-aware authoring rule the class schema has no concept of
  today, and inventing one is a wider change than this stage's brief. It is a real
  follow-up and it is written here rather than lost.

## E2. The open framework defect this stage found and did NOT close

**LT-F3 — `UI.Table`'s touch Edit toggle overlaps the rating column's header title at
Largest text.** Measured on compact phone portrait and landscape, under both theme
packages: toggle `[280,323,56,34]`, header title `[200,347,128,51]`, overlapping over
`x 280..328, y 347..357`.

**The diagnosis was inverted by a later measurement.** The Edit toggle is BYTE-IDENTICAL at both
text sizes — same text, same `TextSize 18`, same `TextBounds 25`, same `56x34` rect. It is not the
button growing into the header. What moves is the HEADER: it sits **7 px below** the toolbar at
scale 1 and **10 px inside** it at scale 3. Equivalently, **the toolbar row's laid-out height falls
from 41 px to 24 px as the type scale rises**. A row that gets shorter when text gets bigger is
backwards, and it means the row is being squeezed while its child holds its size.

That also explains why three fixes on the toolbar row — `height = hug`, `height = content`, and the
default content sizing — **moved nothing**. All three were
reverted: a comment claiming a fix that does nothing is worse than no comment. What the
investigation established is that the Toolbar HStack and the Header container are both
absent from the live instance tree (the Step-9 inert-container elision removes them), so
the row's height comes from the solver alone and a height authored on the Toolbar has no
Instance to land on. That narrows the cause to the solver's measure of an elided container
against a type-scaled child, which needs solver-level instrumentation to confirm and is
beyond this stage's brief.

It is framework-owned — example 02 authors no toolbar or header geometry — and it is the
only reason `EQ-6` is `FAIL_PRODUCT` rather than passing.

## F. Deliberately NOT changed

- **The plain settings demo** (`00_settings_demo`, `init.client.luau`'s default path)
  still mounts the theme picker expanded. It is not one of the seven and widening the
  scope to it was not this stage's brief; the same one-argument fix applies when it is.
- **Example 05's on-screen keyboard stayed three `HStack` rows** rather than a `UI.Grid`.
  The implementer chose that when a Grid still trapped focus (F-2 was fixed afterwards).
  Stacked `HStack` rows fall through vertically by design and the four per-input gate
  rows pass on them; converting it now would be churn with no behavioural gain.
- **No "fill, but at most N" dimension was added.** On a 1920-wide desktop example 05's
  keyboard spans the full width with wide keys. It is correct, adaptive and
  non-overflowing — LuauUI owns adaptation and this is the answer it gives. A
  readable-measure cap is a framework feature request, not a defect, and adding a
  dimension kind is out of this stage's brief.
- **A bare `UI.Toggle` paints 134×28**, under the 44 px target floor that
  `text_audit.hitFloor` enforces. Reproduced with a three-node fixture containing no
  example code, so it is not an example's doing. Recorded here; example 03's layout test
  asserts every node *except* that Toggle clears the floor, with the reasoning inline.

## Disposition

Example code in all seven files is content/domain logic plus declarative LuauUI
composition. `tools/lune/check_example_drift.luau` enforces it mechanically (R1 literals,
R2 unknown semantic values, R3 raw colour, R4 engine/adapter reach-arounds) with two
allowlisted structural constants, each carrying its reason. No unresolved workaround
remains in an example; the two adapter boundaries that do remain — the gallery host's
engine work, and each example's `deps` table — are named above and are the documented
composition seam.
