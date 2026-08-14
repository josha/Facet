# Device bug round — 2026-08-12 (showcase, real hardware)

Nine findings from the game director testing `LuauUI-Showcase` on a phone.
Evidence in `UntitledRacingGame/bugs/` (seven stills, three recordings, plus
`iOS.mov` as the motion reference). **Fix at the framework level where
applicable, never in the example place** — a showcase screen papering over a
framework defect is the defect shipping to every consumer instead.

This is an additional phase of the SwiftUI-parity round 2 mission
([`swiftui-parity-round2.md`](swiftui-parity-round2.md)) and it closes with the
same obligations: suite green, mutation-proved checks, the showcase `.rbxl`
rebuilt and committed, and a device canary through the in-experience picker.

## The three groups, and why they are three

The nine findings are not nine bugs. They cluster into three causes, and the
clustering is the useful part:

- **Group A — the row-actions tray is laid out wrong** (findings 1, 2, 3, 4).
  Geometry and icon resolution around the swipe tray.
- **Group B — content wider than the viewport, with nothing to scroll it**
  (findings 5, 6, 7). The solver already *says* so; nobody is listening.
- **Group C — the row-actions flight is not iOS-smooth** (findings 8, 9, and the
  second 9). Sequencing, overshoot, and pops.

## Group A — row-actions tray geometry

| # | Evidence | Symptom | Suspected cause |
|---|---|---|---|
| A1 | `IMG_3679` | The trash tray butts directly against the row with no negative space, and the flag tray is **clipped by the right screen edge** | Two defects in one shot. The tray band is laid out from the row's edge with no gutter, and the band's total width is not constrained to the viewport — so the second action falls off-screen and is unreachable |
| A2 | `IMG_3683` | Edit mode: no negative space between the leading minus button and the row | Same missing gutter, leading edge |
| A3 | `IMG_3685` | Parchment theme: "Mark Read" label and its button are cut off | The tray button is sized from a theme metric that the parchment package makes larger (an ornate frame), and the label is not being fitted to what is left — the "painted at a size nobody measured" family (`docs/lessons/measure-the-requirement-not-the-render.md`) |
| A4 | `IMG_3686` | Pixel Quest theme: the delete and flag buttons show the letters **"U"** and **"P"** instead of icons | Icon resolution falls back to a *letter* when a theme package does not carry the semantic icon. A letter fallback is a silent wrong result — the shipped icons are `trash` and `flag`, and neither starts with U or P, so the fallback is not even deriving from the right string |

A1 and A2 are one fix. A4 is the most alarming of the four because it is a
**silent** wrong result in a themed package, which is the class the roadmap ranks
above every missing convenience.

## Group B — overflow with no escape

| # | Evidence | Symptom |
|---|---|---|
| B5 | `IMG_3689` | Landscape: the table is entirely below the fold and unreachable — nothing scrolls |
| B6 | `IMG_3690` | Match 3: the bottom button row is clipped horizontally; a third button is sliced by the right edge |
| B7 | `IMG_3691` | All controls: clipped on the right with no horizontal scroll, **and** the `S1`…`S12` labels overflow their buttons to the left |

**The framework already knows.** The solver emits, today, in these exact words:

> `content overflows this hstack by 132px on the main axis; it will paint outside its box (wrap it in a ScrollView, or give it room)`

and `docs/lessons/the-solver-already-told-you.md` records the last time this
shipped past a green suite, a green gate, a five-view matrix and four reviews —
because **nothing ever called `controller.diagnostics()`**. The same instrument
that missed it then is missing it now.

So Group B's framework-level fix is in two parts, and the second matters more
than the first:

1. the screens that overflow get room or a scroller;
2. **an overflow diagnostic stops being something a human has to remember to ask
   for.** Whatever shape that takes — a gate check over the showcase's own
   scenarios at the five device sizes, failing on any non-empty overflow
   diagnostic — it has to be a check that runs without anybody deciding to run
   it. A diagnostic nobody reads is not an instrument, it is a comment.

B7's label overflow (`S1` sitting left of its button) is a separate, smaller
defect in the same shot and is tracked as its own fix.

## Group C — the flight

Reference: `iOS.mov`. Findings, in the director's own terms:

| # | Evidence | Symptom |
|---|---|---|
| C8a | `rec1.mov` | On swipe-to-delete the row leaves, but the **trays remain** and then animate away vertically; the row briefly **reappears** before the delete lands; the next row does not slide up smoothly |
| C8b | `rec1.mov` | A slow swipe carries the row **too far** horizontally; on tap-to-close the row slides back and the trays **pop** rather than travelling with it |
| C9a | `rec2.mov` | Opening: the trays appear **first**, then the row slides — so a block of red flashes before the row moves over it |
| C9b | `rec2.mov` | Closing: the row stops, then **pops** a frame or two later. The director explicitly rules out sampling — it is a real pop |
| C9c | `rec3.mov` | The "Mark Read" button is far too tall and drives odd row resizing |
| C9d | `rec3.mov` | On the return flight the row **overlaps** Mark Read, which collapses into a different row's space instead of animating away, and the other rows pop when the too-tall button disappears |

C9a and C8b are plausibly one cause: the trays are being revealed as a
*visibility* change rather than being uncovered by the row's own travel. C9b and
C9d smell like the settle handoff — a final write landing a frame after the
spring reports it is done.

C9c is a sizing defect and probably shares a cause with A3 (the same button, the
same unmeasured fit).

## Working rules for this phase

- **Root cause before fix.** `ENGINEERING.md` is explicit: a story about what
  went wrong is a hypothesis, and a fix on an unmeasured hypothesis is a guess
  that compiles. Each finding gets reproduced headlessly or in Studio *first*.
  The device is the only place several of these are visible, and that is a
  reason to instrument, not to guess.
- **`controller.diagnostics()` in every fixture this phase touches.** The lesson
  file exists because the last round did not.
- **Every fix leaves a check that bites.** Mutation-prove it: break the fixed
  code deliberately, watch the new test fail, restore.
- **No example-place patches.** If a finding can only be fixed in the showcase,
  that is itself a finding and gets recorded with the reason.
- **Every comment this phase touches names the path it describes.** Game-director
  instruction, 2026-08-12, after a stale-scoped header misled this very session:
  see [`../lessons/a-header-comment-describes-the-path-it-was-written-for.md`](../lessons/a-header-comment-describes-the-path-it-was-written-for.md).
  The showcase carries composed and standalone forms of the same controls, and a
  header that documents one without naming it reads as though it documents both.
  A dedicated freshness pass over `examples/gallery/client/*` runs at the end of
  this phase, once the parallel fixes have landed and can no longer conflict.

---

## Group B — outcome (2026-08-12)

**The instrument, first.** `tests/overflow_sweep.spec.luau`, registered in
`tests/run.luau`, mounts every showcase surface — 25 engine-free gallery
scenarios, all 7 tutorial examples, all 5 reference proofs — at eight viewports
and fails on any `controller.diagnostics()` finding containing "on the main
axis". The viewports are the five the device matrix recorded
(359x718, 705x338, 1079x809, 1232x1067, 1920x1078), the narrowest supported
viewport in both orientations (320x640, 640x320), and the 1320x742 desktop
Studio client the director drives. Every row lays out under the showcase's own
chrome reservation, read from `demo_picker.barReservation(58, nil, 8)` so the
sweep and the picker cannot drift. Fixtures whose shape is chosen by a step
declare their variants (`row_actions` drives list/table/vlist), because a sweep
only covers the configurations its fixture builds.

**It failed on fourteen surfaces on its first run**, of which three were B5/B6/B7
and eleven were unreported. Every one is now green.

| surface | overflow the sweep reported | fix |
|---|---|---|
| `row_actions` (B5) | table pane squeezed to 0 in landscape; `ModeBar` hstack +24px at 320x640; hosted `VListPane` +245px | heading collapses on `isShort`, gutters shrink, `ModeBar` is a `minColumnWidth = "intrinsic"` Grid, VirtualList window fed from its own solved pane via `onGeometry` |
| `07_match3` (B6) | `/Match3/Page/Art` hstack +253px at 359x718 | the artwork button row is a `minColumnWidth = "intrinsic"` Grid |
| `probe` | `/ProbeScreen` +146px | inner ScrollView takes `fill` |
| `scroll_host` | `/ScrollHost` +414px | the three demo regions take proportional `fill` |
| `path_ring` | `/PathRing` +72px | page wrapped in a ScrollView |
| `drag_session` | `/DragLab/Board` +350px | board is an x-axis ScrollView |
| `virtual_list_native` | `/VLNative` +227px | `viewportHeight` derived from the live viewport + core insets |
| `native_style` | `/NativeStyle` +352px, `SurfaceRow` +82px | body ScrollView; chip row is a wrapping Grid |
| `authoring` | `/AuthoringScreen/Row` +82px | row is an x-axis ScrollView |
| `sponsor_list` | `/ListLab` +101px and every row's `Card/Labels` +11px | (see the sponsor_list fix) |
| `composition` | `/CompositionScreen` +162px | body ScrollView |
| `keyboard_navigation` | `/KbdNav` +239px | body ScrollView |
| `06_tile_game` | `/TileGame/Page/Stats` +19px | the stats row is a `minColumnWidth = "intrinsic"` Grid (see the correction below) |
| `p4_foyer` | `HomeBody` +5px | (see the foyer fix) |

**B7(b) was a framework defect and is fixed as one.** `UI.padding` on a `UI.Text`
was measured into the node's box (`solver.contentSize`, the text branch) and
painted by nobody: `arrange` returns at a leaf without insetting anything, the
renderer's padding seam visited only `Button`, and `screen_target`'s
`setProp("padding")` had only a `Button` branch. So each `S1`…`S12` plate came out
label+12 wide with the glyphs drawn from its leading edge. The seam now carries a
padded `Text` too, all four sides, in both adapters.
`tests/text_padding_paint.spec.luau` pins it, including the instance budget in
both directions.

### Correction — the tile-game fix cost visible content (2026-08-13)

The `06_tile_game` row above was originally fixed with a **`UI.ViewThatFits`
candidate ladder**: an `HStack` candidate and a `VStack` candidate, each carrying
its own copy of `Score` and `Progress`. It closed the overflow and it was wrong,
for a reason the overflow sweep structurally cannot see.

A candidate ladder makes you write the content **twice**, once per candidate, and
the two copies need different ids to be different nodes — so the two readouts left
`/TileGame/Page/Stats/Score` and `/TileGame/Page/Stats/Progress`, the paths this
example has published since Step 10, and became
`/Stats/StatsRow/Score` and `/Stats/StatsColumn/Score`. Measured at eleven
viewports, the *winning* candidate always rendered: the readouts were never
actually invisible to a player. What was lost was every claim anything made about
them. `./run-tests.sh` stayed green, including the example's own test named
*"progress and completion are visible"* — because that test proved a node with
that path carried that text, and a **losing** candidate satisfies both (the
framework keeps losers mounted at a deliberate zero rect,
`src/layout/solver.luau`). The only instrument that noticed was
`tools/lune/check_flat_baseline`, which is not in the suite.

**The fix is a different composition, not a better ladder.** `UI.Grid` with
`minColumnWidth = "intrinsic"` — the same answer `07_match3`'s artwork row and
`row_actions`' `ModeBar` take in the table above — states the same intent with the
content written once: side by side where two columns fit, stacked where they do
not. The readouts are direct children again, at their published paths, with real
rects at all eight swept viewports (320x640 and 640x320 included), and
`tests/overflow_sweep.spec.luau` stays green, so the overflow this round fixed has
not come back.

**And the suite now asks the question.** `tests/example_readouts.spec.luau` mounts
all seven tutorial examples at the same eight viewports and fails if any declared
readout is missing from the render or arranged to a zero rect. It is the twin of
the overflow sweep — that one sees content spilling *out* of its box, this one sees
content that left the tree or collapsed to nothing — and it is deliberately a
named list rather than a rule over every node, because "every Text with text must
have area" is false by construction here: a losing candidate is *supposed* to
measure to zero, and a check that has to exempt the case that hid the defect is
noise. Both sweeps read their viewport table from `tests/lib/device_views.luau`, so
a size only one of them visits cannot exist.

### Found and NOT fixed (recorded, out of Group B's scope)

> **RE-VERIFIED 2026-08-13, and all five are still real.** The sweep that found
> them could not *fail* on them — it greped `"on the main axis"` — so they sat
> here as prose for a day. That filter is now deleted (the sweep fails on every
> solver finding) and each of the five is a recorded waiver carrying its
> measurement. At `preferredTextOffset` +0 the numbers below reproduce **byte for
> byte**, with two corrections: the chevron glyphs fire on *all eight* viewports
> rather than the ten-foot row alone, and `p4_foyer`'s `FeedPage` now collapses on
> `padding 8 + 8` (the padding halved since), which bought back the 705x338 cell
> at +0 and nothing else. Full table and verdicts:
> `docs/plans/swiftui-parity-round3.md`, "The overflow sweep asks about every
> finding".

Non-main-axis findings the same sweep surfaces, enumerated over all 37 surfaces x
8 viewports x the declared variants (measured after the Group B fixes landed).
They are OVERLAP and COLLAPSED-BOX diagnostics, not "content with nothing to
scroll it", and several belong to Group A:

- `row_actions`, vlist surface — `.../[m1,m3,m4,m5,m6]/Row/RowBody` overflows its
  zstack by 0x4px on both portrait phones and by **0x15px on the ten-foot row**
  (the type scale is part of the geometry, lesson §10). Group A, the row-actions
  tray family.
- `row_actions`, table surface — `.../[m4,m5]/.../Cell-from/Value` by 0x7px on the
  ten-foot row. Same cause.
- `sponsor_drop` — `/DropLab/Main/ListZone/Rows` by 0x38px (705x338) and 0x47px
  (640x320); `Chevrons/Chev{Top,Bottom}/Glyph` by 0x6px on the ten-foot row.
- `sponsor_toast` — `/ToastLab/Stage/Beneath` by 0x11px at 640x320.
- `p4_foyer` — `.../HomeBody/FeedPage` still reports "content box collapses to 0px
  on y: padding 16 + 16" at 705x338 (21px of height) and 640x320 (3px). The
  main-axis overflow is closed; the scroll page itself has no room for its own
  padding at those viewports and needs its own decision.

### B7(a) — the right-edge clipping: FIXED 2026-08-12 (option (a); director ruling REVERSED)

> **DECISION, taken 2026-08-12.** The director authorized option (a): publish
> `SCROLL_BAR_THICKNESS` as the layout reserve under the overlay policy too. This
> **reverses the director ruling of 2026-08-09** ("an overlay indicator lays claim
> to no layout space"). Reasoning, on the record: *8px of real content on every
> phone beats a cosmetic flash indicator, and Roblox offers no free overlay bar.*
>
> Confirmed live in Studio on the running showcase before the fix:
> `/AdaptiveScreen/BodyScroll` `AbsoluteSize` 703x203, `AbsoluteWindowSize`
> 695x203, `ScrollBarThickness` 8, `AbsoluteCanvasSize` 703x528 — nine nodes
> painted past the invisible edge, matching `bugs/IMG_3691.jpeg`.
>
> It also corrects the inference below that a pointer session cannot overrun: the
> measuring session reported `TouchEnabled = true` **and** `MouseEnabled = true`,
> so it derives `"auto"` and overruns anyway. **A machine that merely *can* accept
> touch gets the phone behaviour** — this was never a phone-only fault, which is
> why the desktop capture showed it too.
>
> Changed: `src/client/screen_target.luau` `setScrollIndicatorPolicy` (and the
> `SCROLL_BAR_THICKNESS` header, which now states the one true rule),
> `tests/lib/fake_target.luau`'s lockstep mirror, `src/present/presenter.luau` and
> `src/render/target_contract.luau` comments, `docs/reference/api.md`, and the pins
> in `tests/scroll_indicators.spec.luau` + `tests/scroll_window_clip.spec.luau` —
> where the RECORDED-DEFECT case is now the fix's pin (overrun must be 0).
> **A future agent must not "restore" the zero reserve thinking it found a
> regression.**

The original analysis, kept for its measurements:

The overflow sweep is clean for `adaptive_controls` at every swept size,
including the 1320x742 the director captured: every right-aligned node ends at
exactly `viewport - 16`, the screen's own padding, with zero overrun. The layout
is right. The clipped pixels are lost between the solved box and the ENGINE
WINDOW, and no headless check could see that because `tests/lib/fake_target.luau`
modelled no window at all — a scroll host's canvas and its visible box were the
same rect.

**The instrument now exists** (`tests/lib/fake_target.luau` `setScrollRegion` +
`adapter.windowRectOf(path)`, pinned by `tests/scroll_window_clip.spec.luau`,
registered in `tests/run.luau`). It models the engine fact `screen_target.luau`
already records at its cross-axis canvas clamp: a `ScrollingFrame`'s window is
narrower than its own frame by the BAR THICKNESS on the cross axis whenever the
scroll axis overflows, even at `ScrollBarInset.None`.

**The disagreement, measured.** Two different numbers, both real:

| number | where | value |
|---|---|---|
| the LAYOUT reserve published to the solver | `screen_target.luau` `setScrollIndicatorPolicy` (~:3085) | **0** under the overlay ("auto") policy, `SCROLL_BAR_THICKNESS` under "always" |
| the INSTANCE thickness the engine charges for | `screen_target.luau:46`, written at every host's creation (~:2036) | **8**, whatever the policy is — the policy only fades the bar's IMAGE |

A touch or gamepad session derives the overlay policy
(`environment.scrollIndicatorPolicy`: `primary == "pointer"` -> "always", else
"auto"). So on every touch surface the solver fills a box **exactly 8px wider**
than the box the player can see, and the engine clips the difference. Measured
headlessly, with the instrument, on a 360-wide touch scroller: frame 360, window
352, fill-width row 0..360 — an 8px overrun, every row, every touch device. That
is the size of the missing "5" in "0.35" and of the sliced "…" button.

**Not fixed at the time this was written; the decision was taken 2026-08-12 — see
the box at the head of this section.** Closing it means
either (a) publishing `SCROLL_BAR_THICKNESS` as the reserve under the overlay
policy too — which changes the cross-axis layout of every touch scroller in the
framework and in RascalRally, and reverses the director ruling of 2026-08-09
("an overlay indicator lays claim to no layout space", pinned by
`scroll_indicators.spec.luau`); or (b) setting the INSTANCE's
`ScrollBarThickness = 0` under that policy so the engine charges nothing — which
removes the flash indicator the same ruling asked for, because Roblox has no
overlay scrollbar that costs no window. **Recommendation: (a).** An 8px reserve
is a visible strip of content on every phone; an indicator that flashes over
reserved space is a cosmetic loss. But it is a product call with a consumer
blast radius, so it goes to the director rather than into this task.
**The director chose (a) on 2026-08-12 and it is shipped.**

**It does not explain the DESKTOP capture.** ~~A Studio desktop client derives
`primary == "pointer"` -> "always" -> reserve 8 -> layout and window agree~~ —
**ANSWERED 2026-08-12, and this inference was wrong.** The measuring Studio
session reported `TouchEnabled = true` alongside `MouseEnabled = true`, so
`interactionClasses.primary` was not "pointer" and the session derived "auto"
like a phone. A machine that merely CAN accept touch got the phone behaviour, so
the desktop capture is the SAME defect, not a second cause. To settle it, run this
with the "All controls" demo mounted and paste the result:

```lua
print(_G.LuauUIScenario.report())   -- its `diagnostics` block is the whole question
```

plus, for the `BodyScroll` `ScrollingFrame`: `AbsoluteSize`,
`AbsoluteWindowSize`, `ScrollBarThickness`, and the environment's
`scrollIndicatorPolicy` / `preferredInput` / `capabilities` / `viewportRect`.

### B7 — the "Edit item" cluster, root-caused, not fixed

Three renderings of one label in one row is the fixture's DECLARED purpose
(`adaptive_controls.luau`, the `compactWidth = 52` comment): a `fill` button that
says its whole label, a 52px button with `compactLabel = "Ed"`, a 52px button with
`compactLabel = { icon = "edit" }`, and a 52px control that declares nothing.

The real defect in it is the fourth one wrapping to `Edit / ite / m`.
`src/render/renderer.luau:450` sets `buttonSingleLine = kind == "text" and
isSingleWord(props.label)` — a PHRASE is allowed to wrap, by a documented rule
whose own comment says "a WORD has no legal break, so breaking it is always
damage". "Edit item" is a phrase, so wrapping is permitted; its 52px box less the
theme's 12px-a-side button inset leaves ~28px, which no word in it fits, so the
engine breaks one anyway. The honest rule is that wrapping is only the right
answer when the phrase's LONGEST WORD fits the drawable width. Not changed here:
it is a director-ruled wrap rule feeding the compact-label ladder, and it is a
separate defect from Group B's overflow class.

---

## Owed: the TD-13/TD-14 re-record (opened 2026-08-13, BLOCKING that stage's gate)

**Group B's `keyboard_navigation` fix invalidated a prior stage's Studio evidence,
and the invalidation was not noticed at the time.** Wrapping the fixture's body in
a `UI.ScrollView` (`Body`, the +239px landscape overflow in the Group B table
above) moved every focusable in that screen one path segment deeper —
`/KbdNav/Volume/TrackHost/Track` became `/KbdNav/Body/Volume/TrackHost/Track`. The
`traversal-document-order` gate's `studio-evidence` check reads
`artifacts/traversal-document-order/studio/traversal.json`, recorded **2026-08-03**
against the pre-`Body` screen.

What happened next is the part worth writing down: **the check was edited to the
new paths and the evidence was left alone.** The gate has been red ever since, and
it was red with the wrong sentence — `AssertionError: the grip must be reached
THIRD, in document position`, which reads as a traversal-order regression in
shipped framework code. It is nothing of the kind. `docs/lessons/` records the
can't-ever-fail class repeatedly; this is its inverse, and it is worse, because a
check that fails for the wrong reason sends the next agent to fix code that is
correct.

**Disposition, 2026-08-13 (Milestone-1 architecture review, C1).** The scenario
restructure STAYS — it fixed a real defect on a real device. The artifact is NOT
hand-edited. The check now fails as staleness, in
[`tools/check_traversal_evidence.py`](../../tools/check_traversal_evidence.py),
which derives the expected path prefix from the scenario source on disk and says:

> `STALE EVIDENCE — the artifact predates the scenario it claims to describe.`
> … `THE FIX IS A RE-RECORD, NOT AN EDIT.`

That guard is structural, so the *next* restructure of this fixture reddens the
same check on the day it lands rather than a mission later. It is also not a
permanent red: proved 2026-08-13 that the same script exits 0 against a
`Body`-shaped artifact, so the re-record below is the whole of what is owed.

### The re-record, exactly

Needs a human at Studio; no agent can close it headlessly.

> **ATTEMPTED 2026-08-14, AND THE BLOCKER IS NOW MEASURED RATHER THAN ASSUMED.**
> "Needs a human" was written before the MCP path had been tried. It has now been
> tried, and the reason is sharper than "no agent can": **the Studio MCP's Play
> bridge does not work in this environment at all.**
> `mcp__Roblox_Studio__start_stop_play` times out on every call and then answers
> `Start play hasn't finished yet` for the rest of that Studio instance's life,
> and while a session *is* in Play (it does start — `get_studio_state` reports
> `Play` with `Client, Server`), `execute_luau` answers
> `Target is not reachable (createExecuteLuauBridge_loadCodeAsync, …)` for **both**
> datamodels, so `user_keyboard_input` (which is Client-only) can never be
> reached. Reproduced on **two** Studio instances, the second one fresh, so it is
> not one wedged session. Synthetic input is not a way around it either: `CGEvent`
> mouse clicks and `System Events` keystrokes and menu selections were all posted
> at Studio and **none** of them reached it (proved by clicking an Explorer row
> and a ribbon tab and observing no change).
>
> **Steps 1–2 and the source half are already done and can be skipped.** The
> showcase place was injected from `tools/lune/studio_sync` this session and is
> current at stamp `20950a06-5154740` with `LuauUI_SourceStale = 2` (only
> `renderer`/`presenter`, both over the 200,000-char Source cap, both at
> `965b8ed`); the device emulator was stopped; `LuauUI_Showcase` /
> `LuauUI_Scenario` were restored afterwards, so set
> `LuauUI_Showcase = false` and `LuauUI_Scenario = "keyboard_navigation"` again
> before pressing Play. What is owed is a session in which **raw Tab actually
> reaches the client** — a human pressing Play with a working input path, or the
> MCP Play bridge repaired.
>
> Step 3's `tools/studio/install_matrix_driver` **does not exist as a file**; the
> driver is installed by fetching `http://127.0.0.1:8642/driver` from
> `tools/lune/studio_sync` into a `workspace.LuauUIMatrixDriver` ModuleScript
> (`tools/studio/device_matrix.luau`'s own header). Note also that the artifact's
> own `TD13-forward-traversal.driver` field records the 2026-08-03 session as
> having used **`mcp user_keyboard_input keyPress Tab x5`**, not VirtualInput —
> so that, not `run({ mode = "keyboard" })`, is the path known to have worked.

1. Publish/sync the current source into the gallery place and open
   **`examples/places/LuauUI-Showcase.rbxl`** (or the stage's own Place1), then
   **Play (Client datamodel)** — the Edit datamodel caches `require()` results and
   will run stale modules. Confirm the staleness markers exactly as the existing
   `preflight.stalenessMarkerNote` in the artifact describes (`traversalPriority`
   accepted, `traversalPriorty` still refused).
2. `game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)`
   — **DKN-1: Tab is not deliverable at all with the players list on**, and
   `preflight.playerListEnabled` must record `false`.
3. Install the driver (`tools/studio/install_matrix_driver`) and drive the
   `keyboard_navigation` scenario:
   `local run = require(workspace.LuauUIMatrixDriver)` then
   `run({ mode = "keyboard", keys = { … } })` for the forward Tab sequence, the
   reverse Shift+Tab sequence and the arrow sequence, plus
   `run({ mode = "step", step = "focusOrder" })` for the live dump. Each call
   returns a JSON **string**.
4. Rebuild `artifacts/traversal-document-order/studio/traversal.json` from those
   returns, keeping the existing schema. It must carry:
   - `preflight`: `scenarioState = "ready"`, `stalenessMarkerChecked = true`,
     `playerListEnabled = false`, plus the session's own
     `studioVersion`/`sourceStamp`/`libraryVersion`/`viewportSize`;
   - rows `TD13-forward-traversal`, `TD13-reverse-traversal`,
     `TD2-arrows-unregressed`, `TD14-dump-matches-behavior`, `TD13-capture` at
     `PASS_AUTOMATED`, and `TD15-consumer-canary` still `PENDING` (the game-place
     canary is a separate row and is not closed by this);
   - the forward row's `focusLog` with the **grip third** and its `rawInput` with
     `gameProcessed = false` on every entry;
   - the arrows row's `focusLog` visiting no `Track`;
   - the dump row's `traversal` agreeing with the observed order and its
     `navigation` still ending in the `auto-grips` group.
5. Re-take `artifacts/traversal-document-order/studio/td13-fixture.png` in the same
   session (the check requires the file, and a capture from the old screen is the
   same lie in picture form).
6. `python3 tools/check_traversal_evidence.py` must exit 0, then
   `tools/gate.sh traversal-document-order`.

**Until then the `traversal-document-order` gate is legitimately RED**, and any
prior-gates sweep will report it. That is the honest state: the stage's Studio
claim is currently unevidenced at the live source.

---

## Group C — outcome (2026-08-13)

**The instrument, first, again.** `tests/row_actions_motion.spec.luau`
(registered in `tests/run.luau`) is the first row-actions check that asserts over
a **recorded per-frame trace** rather than a settled state. That is not a style
choice: every one of the six lives strictly *between* two settled states, and by
the time the suite's existing questions ("is it open", "did it fire", "what is
the offset after 90 frames") are asked, the defect has finished happening. It
records, per frame: the row's `offset`, the band each tray actually PAINTS (the
reach from the row's edge to the furthest plate with a non-zero width — the tray
CONTAINER paints nothing and carries fixed extras, so measuring it would have
made every check untrue by a constant), the band's own box, whether the tray is
mounted, and the row's content box and height. `controller.diagnostics()` is
asserted empty in every fixture.

**Six findings, five mechanisms, all in shared code.** The hosted VirtualList,
Table and standalone rows shared every one of them.

| # | Mechanism (file:line at the time of the fix) | Measured before | Measured after |
|---|---|---|---|
| C9a, C8b | `row_actions.luau` `buildWidthProps` — the plate-width fallback read `spring == nil or n == nil`. `spring` is built lazily by the first `retarget`, and **a live drag never retargets** (it writes `offset` straight through `applySlide`), so every plate painted at the `buttonMinWidth` FLOOR for the whole of every gesture-driven reveal. `n == nil` is the tray's first mounted frame, which paints the whole band before the row has moved | drag: 14 frames, `offset` −27 → −183, band a constant **159px** on all of them. `_open`: frame 1 band **159px at `offset` 0**, frame 2 **26px** | drag: band **27 → 159px**, tracking the finger to within 1px on every frame. `_open`: frame 1 **0px**, then 15 → 37 → 59 → … |
| C8b (the "too far") | same line. The LEADING plate painted at the 64px floor during the drag while the release settles to its real natural (117px + gutter) | the row flew **53px further** than the band the player had been watching | band at drag distance *d* == band at settled distance *d*, ±2px |
| C9a residue | the band's inter-plate gap and row-facing gutter were spent in FULL at every reveal fraction, while `bandWidth` counts both into the travel | band box ahead of the row's own travel by up to **`trayGap + rowGutter`** | band box == `|offset|` within 2.5px (four independently rounded terms) on every frame |
| C9b | `row_actions.luau` reveal memos — unmount gated on `offset == 0` EXACTLY. `spring.luau`'s `DEFAULT_EPS` is `1e-3`, and its own header says a position-domain spring "settles a few frames after they visually arrive" | showcase list: row within half a pixel of home at **frame 23**, tray unmounted at **frame 58** — 35 frames, **0.58 s** of a visible sliver of band standing after the motion ended, then gone in one frame | unmount at frame **23** (leading) / **24** (trailing) — the same frame as arrival. The host's engagement now ends on the same test (`row_actions.REVEAL_EPS`, published for `virtual_list.luau`'s `hostedApplySlide`) |
| C9c, C9d | `row_actions.luau`'s `Content` ZStack: `width = fill`, `anchor = "topLeft"`, `offsetX = offset`. `solver.luau`'s `offsetFill` gives a fill anchor child back the room its own offset costs it, and exempts only a child anchored to the edge it is being PUSHED PAST. A trailing swipe is negative and was always inside that exemption; a **leading** swipe took the tray's whole width out of the row's content box | showcase list row: `Content` **319 → 194px**, preview re-wrapped, `Content/Row` **88 → 117px**, and `controller.diagnostics()` reported *"overflows its zstack by 0x29px"* for the whole time the tray was open — 29px of row painted over the row below. Closing re-wrapped in two discrete 14px steps mid-flight | `Content` stays **319px**, `Content/Row` stays **88px**, diagnostics **empty**. The anchor now follows the offset's sign, which puts both directions inside the same exemption with identical placement arithmetic |
| C8a (i) | `row_actions.luau` `doCommitAction` set `openEdge` to the committing edge and left it there for the whole slide-off AND the whole height collapse | the band stood **fully painted, 159px, from frame 1 to frame 115** of the commit — **95 frames (1.58 s)** of it with the row entirely off-screen — and was then squashed vertically as the height went to 0 | no plate mounted at any frame of the commit; the row leaves alone |
| C8a (ii) | `row_actions.luau` — the chain fired `onAction` and then called `resetToClosed()`, which puts the height override back to `nil` and springs the row home | at the fire frame the row went **0px → 48px tall** and travelled **−400 → −252 in four frames**: a whole row, repainted and flying back, before the owner's `rows:set(…)` reached the diff | bookkeeping still runs at the fire; the PAINT is deferred to the next `syncGeometry` and is a `snap`. A row the owner really removed is disposed first and never repaints; a row the owner kept (the "phantom row") is back one sync later, instantly |
| C8a (iii) | nothing animated the re-flow at all | rows below a deletion teleported up one row height on the commit frame | `examples/gallery/scenarios/row_actions.luau` commits its deletion inside `presenter.withAnimation("container", …)` (`animateReflow`), proved by `presenter.animationRecordCount() > 0` at the removal frame — which is also the proof the call is legal from inside a settle callback, since a refusal there would be silent |

**Reduced motion, deliberately.** None of the five mechanisms needed a
reduced-motion branch, and that is asserted rather than assumed: the motion
authority places every value instantly, so an open lands on its target on the
frame it is asked for with the band already exactly the travel it uncovered, a
commit fires with no slide and still leaves nothing standing, and
`withAnimation` installs no records at all. Two cases in the new spec and one in
`row_actions_scenario.spec.luau` pin it.

### Two existing checks changed, and why

Both described the post-commit RETURN FLIGHT, which finding C8a (ii) removes.
Neither guarantee was weakened — each is now asserted over the whole trace, or
at the moment the guard actually applies.

- `tests/row_actions_input.spec.luau` "a re-swipe DURING the commit's return
  flight cannot fire the action twice" → **"a re-swipe the instant a commit
  clears…"**. It asserted `offset < -rowWidth/2` at the fire frame, which was
  true only because the row was still flying home. It now asserts the row really
  was carried a row width out (the minimum over the whole trace) and re-swipes at
  the same instant. Guarantee unchanged: exactly one fire.
- `tests/virtual_list_row_actions.spec.luau` "(l)" takes the identical change,
  and "(y) the PHANTOM ROW" is rewritten. (y) documented the OLD behaviour as
  deliberate — *"It paints the tray, and that is deliberate… parity with
  standalone/Table is the specification here"* — which is exactly the behaviour
  the director filmed. It now asserts the new contract (nothing painted once the
  row is carried clear; the latched row refuses a gesture *during* the commit,
  where the latch actually applies; a surviving row is a normal full-height row
  afterwards). Still parity with standalone/Table, which is what it was for.

### What only a device can confirm

Everything above is geometry and sequencing, which is what a headless trace can
answer. **Whether it FEELS right is a human gate** (`STUDIO.md`'s anti-drift
protocol) and none of it is self-certified:

- the *feel* of each of the five, against `iOS.mov`, on real hardware;
- **C8a's deviation from `iOS.mov` is a live decision.** iOS expands the
  destructive plate to fill the row and the row leaves over it, so nothing has to
  vanish. What ships is the director's own sentence — *"the row should just go
  away"* — which un-reveals the band at the instant the commit starts. On a full
  swipe the band is already fully exposed and standing alone by then, so the two
  events coincide; it is still a change of state in one frame and it is the one
  place a measurement cannot settle the question;
- the `withAnimation` re-flow's duration and class (`"container"`, 0.35 s) on a
  phone — the record count proves it runs, not that 0.35 s is the right feel;
- engine text bounds: every natural width here is `text_metrics`' estimate, so a
  package whose real bounds differ shifts the band by that difference.

### A seventh, found by audit rather than by the phone: the menu was unpositioned

Not one of the six, and it arrived from the placement-prop audit while this phase
was open. It is in the same file and it is the same trap one container over, so it
is fixed here.

`anchor` / `offsetX` / `offsetY` are read by a node's **parent**, and only by an
**`anchor`-kind** one — which `row_actions.luau`'s own header already states, for
the row slide: *"honoured ONLY by an `anchor`-kind parent … the sibling `zstack`
branch does not — a ZStack child's `offsetX` is silently inert."* The action
menu's `Menu` node **is** a `UI.Anchor`, but it declared all three on **itself**,
where its parent is the `UI.Screen` the menu is presented as — a vstack, which
reads none of them.

| | before | after |
|---|---|---|
| trigger row, screen space | `(20, 148, 760x48)` | unchanged |
| `menuOx` / `menuOy` (correctly computed all along) | `(20, 196)` | unchanged |
| where the menu solved | **`(0, 0)`** — the surface origin | `(20, 196)` |
| `controller.diagnostics()` | **empty** | empty |
| the anchor's own box vs the menu it places | `91x73` at `(0,0)` while painting at `(20, 556)` — a box that does not contain its own child | the whole surface; it contains what it places |

The fix moves the three props onto `MenuRows`, the anchor's child, and fills the
anchor to its edge-to-edge surface (which is also what makes its inner origin the
window origin — the space `computeMenuAnchor` measures the trigger in). **Every
path is unchanged**, so the Activate pattern, the focus assertions and the
contribution subtree all stay put. Pinned by
`tests/row_actions_input.spec.luau` "the menu is placed at its TRIGGER, not at the
origin of its own surface", which asserts against a fixture that deliberately
pushes the row off the origin on **both** axes — the reason no existing case saw
this is that every other menu test uses a world whose row sits at `(0, 0)`, where
the wrong answer and the right one are the same number.

**It is NOT the same cause as C9d, and that was checked rather than assumed.** The
menu has no touch entry at all — `ButtonX` and Shift+Return are its only openers —
and `rec3` is a touch recording, so the menu was never on screen for it. C9d's
"collapse into something on a different row" is the leading-reveal squeeze
(`offsetFill`), which is reproduced, measured and fixed above and which needs no
menu to happen.

**Left as it was, deliberately:** the menu is still not clamped to the viewport. A
menu opened on a row near the bottom edge is placed below that row and may extend
past it (measured: trigger at y = 508 on a 600px viewport puts the menu at
y = 556..629). That was equally true before, an anchor parent emits no overflow
diagnostic for it, and flipping the menu above its trigger is a placement decision
rather than part of this fix.
