# WP-C — Gallery examples: input auto-adaptation audit

Audit date: 2026-07-21. Scope: the 7 tutorial gallery examples, `assets.luau`, the
shared runner `examples/gallery/client/init.client.luau`, and the two specs that
drive the examples headlessly (`tests/examples_gallery.spec.luau`,
`tests/examples_games.spec.luau`). No other spec drives an example (grep of
`tests/` for `examples/gallery/examples` returns exactly those two files).

Governing bar — `ui_todo.md` §0 (director, 2026-07-20): *every control/example must
work on ALL FOUR input classes — pointer (mouse), touch, keyboard, gamepad — with a
focus/navigation story, an Activate story, and input-appropriate affordances, verified
per input in tests, and with NO consumer wiring.* The examples are the consumers; this
audit inventories the input wiring they still hand-do and how much of it §0 says the
framework should own.

Paths below are relative to
`GameStudio/ui/LuauUI/`. Line spans are file line numbers as read this session.

---

## How the tests simulate each input class (decoder)

The two specs are the only headless drivers. What each helper actually exercises:

| Test helper | Input class it stands for |
|---|---|
| `adapter.tap(path)` (no opts) | **pointer** (mouse) |
| `adapter.tap(path, { pointer = "touch" })` / `adapter.pointerDown(..., "touch")` | **touch** |
| `adapter.pointerDown/Move/Up(...)` (no "touch") | **pointer** drag (mouse) |
| `system.deviceKey("Return"/"Down"/"Up"/letter, ...)` | **keyboard** |
| `system.deviceKey("ButtonA"/"ButtonB"/"DPadDown"/...)` | **gamepad** (Roblox maps Cross→ButtonA) |
| `focus.navigateDirection("right"/"down")` | **NOT a device** — a direct focus-graph API call. Proves the nav graph, but bypasses the example's own DPad/arrow→`navigateDirection` bindings and any device key. Counts as PARTIAL evidence only. |
| `game.press(k)` (05 only) | `actions.deviceKey(k,±)` internally → **keyboard** for letters/Return/Backspace |

Critical fact for the games spec: `tests/examples_games.spec.luau` **never calls
`deviceKey` for DPad/ButtonA and never uses a touch pointer.** Its only real device
inputs are `adapter.tap` (mouse, 06 only) and `game.press`→`deviceKey` (keyboard, 05
only). All 05/07 "gamepad" coverage is `focus.navigateDirection` (focus API).

---

## Per-example wiring inventory (evidence-cited)

### 01 — Temperature Converter (`examples/gallery/examples/01_temperature_converter.luau`, 171 lines)
Sole interactive control = one `LuauUI.newTextInput` field (98–114). All four-input
behavior is delegated to that control; the example only *plumbs* it.

Input wiring the example does itself:
- **deps passthrough into the control** — `env = deps.env`, `actionSystem = deps.actionSystem` (112–113). Feeds the field's keyboard-occlusion + text-entry-sink handshake.
- **`present` table** (142–151), 10 lines, all generic TextInput plumbing:
  - `sinkNavigation = true` (143) — focus-driven-screen policy
  - `onActivate = function(path,meta) field.api.handleActivate(path, meta) end` (144–146) — routes presenter Activate into the field
  - `onGeometry = function(rectOf) field.api.syncGeometry(rectOf) end` (147–149) — keyboard-occlusion geometry
  - `keepVisibleOffset = field.api.keepVisibleOffset` (150) — keyboard-occlusion offset
- App-semantic (legitimately example-level, NOT counted as input boilerplate): `acceptNumeric` numeric grammar (42–47), `toCelsius` (49–51), the two `onChange`/`onCommit` parse callbacks (104–111).

Input-boilerplate lines: **~12** (present block 142–151 = 10; deps passthrough 112–113 = 2).

### 02 — Playlist Table (`02_playlist_table.luau`, 343 lines)
Two controls: a `newTextInput` filter (107–114) and a `newTable` (180–249). The
heaviest `present` surface in the suite.

Input wiring the example does itself — `present` table (273–316), **44 lines**:
- `navigationGroups = function(rootNode) …` (280–288) — prepends the filter as nav group "filter", then splices in `tbl.api.buildFocusGroups(rootNode)`; re-derived every refresh. (gamepad/keyboard 2D focus graph)
- `onNavigateIntercept = function(direction) return tbl.api.handleGrabNavigate(direction) end` (291–293) — gamepad grab-move-drop reorder intercept
- `onActivate = function(path, meta) …` (294–305) — three-way router: filter `handleActivate` → star-by-path regex → `tbl.api.handleActivate`
- `onFocusNav = function(path) tbl.api.handleFocusMoved(path) end` (308–310) — "selection follows focus" (Apple model)
- `onGeometry = function(rectOf) filterControl.api.syncGeometry(rectOf) end` (312–314) — filter keyboard-occlusion
- `keepVisibleOffset = filterControl.api.keepVisibleOffset` (315)
- plus `env = deps.env` passthrough to both controls (113, 216).

Also input-idiom (pointer): the `Grip` scrub over the stars (160–171) with `scrubRating`
ratio math (127–137) — a pointer-drag rating idiom.

App-semantic (stays): star value from path `ratings[trackId]:set(...)` (299–303),
`onReorder` splice into `baseRows` with the reorder-under-filter rule (225–248),
`filteredRows` memo (78–91).

Input-boilerplate lines: **~44** (present block) + ~12 (Grip/scrub pointer) ≈ **56**.

### 03 — Settings Sync (`03_settings_sync.luau`, 146 lines)
Controls: a `UI.Toggle` (107) and two `UI.Button` +/– (113, 115). **No focus, nav,
gamepad, or touch wiring at all** — which is exactly why it is UNPROVEN on three input
classes (below).

Input wiring the example does itself — `present` table (122–132), **11 lines**:
- `onActivate = function(path) … end` — path-string router: `/Settings/Music` → toggle+`commit`; `/Settings/VolumeRow/VolPlus`/`VolMinus` → `commit`.

App-semantic (stays): the optimistic `mutation`, loopback `server`, `commit` (44–90).

Input-boilerplate lines: **~11** (activation routing only). No nav/gamepad/touch story
present.

### 04 — Confirm Dialog (`04_confirm_dialog.luau`, 89 lines)
Controls: base `Delete` button (69); modal `Confirm`/`Cancel` buttons (38–39). Uses the
presenter's modal stack; Cancel/B routing is already presenter-owned (comment 49–50).

Input wiring the example does itself:
- base `present.onActivate` (73–79), 7 lines — `/DangerScreen/Delete` → `openDialog()`
- modal `onActivate` inside `presentModal` (51–58), 8 lines — Confirm/Cancel → set `result` + `dismiss`

Input-boilerplate lines: **~15**, all activation routing. (No pointer/touch story is
exercised — see matrix.)

### 05 — Word Game / Wordle (`05_word_game.luau`, 347 lines)
Richest self-wired input. Board (188–211) + a 3-row on-screen keyboard (213–233), plus a
dedicated sinking action context.

Input wiring the example does itself:
- **nav groups** built inline with the keyboard blueprint: `keyPathByLetter`, per-row `order`, `groups[ri] = { name, axis="horizontal", entry="nearest", order }` (214–232)
- **focus scope swap** `pres.focus.popScope(); pres.focus.pushScope({ name="Wordle", groups })` (269–270) — the example's own comment (267–268) flags this as *"the one rough edge: the presenter offers no hook to supply navigation groups."*
- **input context** `actions.createContext({ name="WordleInput", priority=2000, sink=true })` (276) then:
  - 26 hardware-letter actions `Type_A..Z` binding `keyCode = letter` (280–287)
  - `Submit` bound `Return` (288–290), `Backspace` bound `Backspace` (291–293)
  - `navAction` helper + `NavUp/Down/Left/Right` binding `Up/DPadUp` … → `pres.focus.navigateDirection` (294–306)
- **`onActivate`** router `/key_(.+)$` → `submit`/`backspace`/`typeLetter` (249–261)

App-semantic (stays): `evaluate` scoring (45–71), `typeLetter`/`backspace`/`submit`/
`openResults` game commands (126–185). The 26 letter bindings straddle: *typing a letter
is the game's semantics*, but manually binding 26 hardware keys is boilerplate a real
text-entry/command layer would own.

Input-boilerplate lines: generic (framework-should-own) ≈ **~33** — nav-group build (~5),
popScope/pushScope (2), nav actions (~13), activation router (13). Plus ~20 app-adjacent
lines (letter/submit/back bindings).

### 06 — Tile Game / Scrabble (`06_tile_game.luau`, 229 lines)
Board of `UI.Button` cells (102–107) + rack of `UI.Button` tiles (126–133). **Structurally
the thinnest and weakest**: NO navigation groups, NO input context, NO focus-scope swap.
It relies entirely on the presenter's default flat focus ring.

Input wiring the example does itself:
- `present.onActivate` router (154–167), 14 lines — `/rack/rt(%d+)$` → `selectSlot`; `/board/brow…/cell…$` → `placeAt`.

App-semantic (stays): `selectSlot`/`placeAt` select-then-place (66–90), `score` memo
(56–63).

Input-boilerplate lines: **~14** (activation routing only). Gamepad grid nav is *absent*,
not merely untested (flat ring, no groups).

### 07 — Match-3 (`07_match3.luau`, 354 lines)
Board of image+transparent-button tiles (192–239) + adaptive `cellDim` + async image
provider. Same self-wired gamepad pattern as 05.

Input wiring the example does itself:
- **nav groups** inline with the board: per-row `order` of `.../hit` paths, `groups[r] = { name, axis="horizontal", entry="nearest", order }` (195, 211, 238)
- **focus scope swap** `pres.focus.popScope(); pres.focus.pushScope({ name="Match3", groups })` (279–280)
- **input context** `actions.createContext({ name="Match3Input", priority=2000, sink=true })` (286) + `navAction` + `NavUp/Down/Left/Right` binding `Up/DPadUp`… → `navigateDirection` (290–302). Activation deliberately left on the presenter's default Activate (comment 284–285).
- **`onActivate`** router `/mrow…/cell…/hit$` → `activateCell` (265–273)

App-semantic (stays): `activateCell` adjacency/swap-direction (253–263), board logic
`findMatches`/`collapse`/`resolve`/`swapCells` (86–166), adaptive `cellDim` from
`sizeClass` (181–185), resource provider (172–177).

Input-boilerplate lines: generic ≈ **~29** — nav-group build (~5), popScope/pushScope
(2), nav actions (~13), activation router (9).

---

## Proof matrix — example × input class

Legend: **PROVEN** = a spec fires that class's real device input against the example's
own controls; **PARTIAL** = only some affordances, or nav proven via the focus API
(`navigateDirection`) rather than a device key; **UNPROVEN** = no spec exercises that
class. Spec file abbreviations: G = `tests/examples_gallery.spec.luau`, M =
`tests/examples_games.spec.luau`.

| Example | Pointer (mouse) | Touch | Keyboard | Gamepad |
|---|---|---|---|---|
| **01 Temp Converter** | **PROVEN** — G:137 `tap(FIELD)` enters edit | **PROVEN** — G:141 `tap(FIELD,{pointer="touch"})` | **PROVEN** — G:146–153 focus=field, `deviceKey("Return")` enters edit; commit via Enter | **PROVEN** — G:155–170 `ButtonA` enters edit, `ButtonB` cancels/reverts |
| **02 Playlist Table** | **PROVEN** — G:341–400 tap stars/rows/clear, pointer drag reorder + scrub | **PROVEN** — G:402–429 touch Edit toggle + `pointerDown/Move/Up(...,"touch")` handle reorder | **PROVEN** — G:312–326 `deviceKey("Return")` enters filter edit; G:257–283 typing sunk | **PROVEN** — G:431–516 full DPad nav + `ButtonA` rate + grab-move-drop + selection-follows-focus |
| **03 Settings Sync** | **PROVEN** — G:559,581 `tap("/Settings/Music")`, `tap(".../VolPlus")` | **UNPROVEN** — no touch tap | **UNPROVEN** — no `deviceKey` activate | **UNPROVEN** — no `ButtonA` |
| **04 Confirm Dialog** | **UNPROVEN** — base/modal buttons never `tap`'d | **UNPROVEN** — no touch tap | **PROVEN** — G:614 `deviceKey("Return")` opens; G:621–626 `Down` nav+wrap | **PROVEN** — G:629 `ButtonB` cancel; G:643–651 `ButtonA` open+activate |
| **05 Word Game** | **UNPROVEN** — on-screen keys never `tap`'d | **UNPROVEN** — no touch tap | **PROVEN** — M:52–101 `game.press`→`deviceKey` letters/Return/Backspace fill+submit+win. *(arrow-key NAV only PARTIAL: M:95–98 uses `navigateDirection`, not `deviceKey("Up")`)* | **PARTIAL** — M:89–101 grid nav via `focus.navigateDirection` only; DPad device bindings + `ButtonA` activate never fired |
| **06 Tile Game** | **PROVEN** — M:139–147 `tap(rack)`+`tap(cell)` select-then-place | **UNPROVEN** — no touch tap | **UNPROVEN** — no `deviceKey`, no focus nav | **UNPROVEN** — no `deviceKey`, no groups (flat ring; grid nav absent) |
| **07 Match-3** | **UNPROVEN** — tiles never `tap`'d; swaps via `game.swap()` direct API (M:192) | **UNPROVEN** — no touch tap | **UNPROVEN** — no `deviceKey` | **PARTIAL** — M:253–262 grid nav via `focus.navigateDirection` only; DPad device bindings + `ButtonA` activate never fired |

### Matrix gaps summary (18 of 28 cells are not fully PROVEN)
- **01, 02** — fully PROVEN on all four (the model cases; but heavy consumer wiring, see below).
- **03** — pointer only; **touch/keyboard/gamepad UNPROVEN** (no wiring exists for them). Matches director expectation.
- **04** — inverse of 03: **keyboard + gamepad PROVEN, pointer + touch UNPROVEN** (a modal-focus example that never tests a mouse/touch click).
- **05** — keyboard PROVEN (typing), but **pointer + touch UNPROVEN** (on-screen keys never tapped) and **gamepad PARTIAL** (focus-API nav only; device DPad + ButtonA never fired). Arrow-key navigation itself is PARTIAL.
- **06** — pointer only; **touch/keyboard/gamepad UNPROVEN**, and gamepad grid nav is *structurally absent* (no nav groups at all — flat focus ring).
- **07** — **gamepad PARTIAL** (focus-API nav only), everything else UNPROVEN; even pointer activation is untested (swaps go through the direct `game.swap` API, never a tap).

---

## Boilerplate baseline table (for the later regression proof)

Totals are `wc -l` newline counts; input-wiring counts are the generic (framework-should-own)
input plumbing with the cited primary span. Spans are reproducible from the files as read
2026-07-21.

| Example | Total lines | Input-wiring lines (generic) | Primary span(s) | Kind of wiring |
|---|---:|---:|---|---|
| 01 Temp Converter | 171 | ~12 | present 142–151; deps 112–113 | activation route + geometry/keepVisible + sinkNav |
| 02 Playlist Table | 343 | ~44 (+~12 pointer scrub) | present 273–316; Grip 160–171 | nav groups + grab intercept + activation route + focus-nav + geometry/keepVisible |
| 03 Settings Sync | 146 | ~11 | present 122–132 | activation route only |
| 04 Confirm Dialog | 89 | ~15 | present 73–79; modal 51–58 | activation route only |
| 05 Word Game | 347 | ~33 (+~20 app-adjacent letter binds) | groups 214–232; scope 269–270; ctx 276–306; onActivate 249–261 | nav groups + scope swap + device→nav binds + activation route |
| 06 Tile Game | 229 | ~14 | present/onActivate 154–167 | activation route only (no nav story) |
| 07 Match-3 | 354 | ~29 | groups 195/211/238; scope 279–280; ctx 286–302; onActivate 265–273 | nav groups + scope swap + device→nav binds + activation route |
| **Total** | **1,679** | **~158 generic** (+~32 app-adjacent) | — | — |

`assets.luau` (32 lines) and the shared runner `client/init.client.luau` (191 lines) do no
per-example input wiring; the runner passes the same `deps = { env, actionSystem,
presenter, adapter }` to every example (76–81) and presents `{ screen, present }` examples
via `pres.present(built.screen, built.present)` (86) — it is the neutral seam, not a
source of boilerplate.

---

## Wiring that should disappear (grouped by kind)

Everything below is generic control/input adaptation that §0 says the framework should own
automatically — the example is doing the framework's job. Genuinely app-semantic logic is
called out separately and *stays* at the consumer level.

### A. Navigation groups / focus graph (D-pad + arrow story)
Framework-should-own. §0: "every interactive surface needs a focus/navigation story
(D-pad/arrows)."
- **02** `present.navigationGroups` (280–288) — prepends the filter, splices `tbl.api.buildFocusGroups`. The Table already computes its own groups; the consumer only forwards them.
- **05** inline `groups` build (214–232) + `popScope`/`pushScope({groups})` (269–270). The example itself flags this as the framework's missing hook (267–268).
- **07** inline `groups` build (195/211/238) + `popScope`/`pushScope` (279–280).
- **06** — the *absence* of this is itself the bug: a flat focus ring, no 2D grid nav for gamepad.
- *Legitimately app-level (the shape, not the plumbing):* which cells form a row/column of a game board or keyboard is app knowledge; but supplying it must be a first-class presenter input (a `groups`/`navigation` prop), not a `popScope`/`pushScope` dance.

### B. Activation routing (Activate story)
Framework-should-own the *routing*; the *command* is app. §0: "every surface needs an
Activate story (A/Cross/Return/tap)." Every example hand-writes a `present.onActivate`
that string-matches control paths and dispatches:
- **01** (144–146) → `field.api.handleActivate` (pure control forward — 100% framework).
- **02** (294–305) → filter `handleActivate` + star-by-regex + `tbl.api.handleActivate` (control forwards are framework; the star `ratings[id]:set` is app).
- **03** (122–132) → path→`commit` (routing is framework; `commit`/mutation is app).
- **04** (73–79, 51–58) → path→`openDialog`/`dismiss` (routing is framework; the outcome record is app).
- **05** (249–261) → `/key_…`→command (routing is framework; `typeLetter`/`submit` is app).
- **06** (154–167) → rack/board path→`selectSlot`/`placeAt` (routing is framework; select-then-place is app).
- **07** (265–273) → `/…/hit`→`activateCell` (routing is framework; swap-adjacency is app).
- *Pattern:* a `Button`/`Toggle`/`TextInput` should deliver its own activation to its own `onActivate`/`onToggle` handler; the presenter should not require the consumer to re-derive "which control was this path" by regex.

### C. Grab / reorder intercepts
Framework-should-own (Table idiom).
- **02** `present.onNavigateIntercept → tbl.api.handleGrabNavigate` (291–293). The Table owns grab-move-drop; the consumer only forwards the intercept. Should auto-wire when a reorderable Table is present.

### D. Geometry sync + keyboard-occlusion keep-visible
Framework-should-own (TextInput idiom).
- **01** `present.onGeometry → field.api.syncGeometry` + `keepVisibleOffset` (147–150).
- **02** `present.onGeometry → filterControl.api.syncGeometry` + `keepVisibleOffset` (312–315).
- The TextInput already exposes `api.syncGeometry`/`api.keepVisibleOffset`; the presenter should call them when a focused TextInput needs the on-screen keyboard cleared, with no consumer forwarding.

### E. Selection-follows-focus
Framework-should-own (Table/list idiom).
- **02** `present.onFocusNav → tbl.api.handleFocusMoved` (308–310). Generic Apple-model "arrow/d-pad focus re-selects the row." Should be a Table option, not consumer glue.

### F. Device→navigation key bindings + sinking contexts
Framework-should-own. The presenter already ships a default Navigate; these examples
re-create it only because they raise a sinking context.
- **05** `NavUp/Down/Left/Right` binding `Up/DPadUp/…` → `navigateDirection` (294–306) inside `WordleInput` (priority 2000, sink).
- **07** identical `NavUp/…` (290–302) inside `Match3Input`.
- **01** `sinkNavigation = true` (143) is presenter policy the consumer shouldn't have to know.
- *Note:* the sink itself is needed so game keys (Enter=submit, arrows=grid) shadow the default Activate/Navigate — but the DPad/arrow → `navigateDirection` re-binding is pure boilerplate the presenter should provide behind the sink.

### G. Legitimately app-semantic — DOES NOT disappear (keep at consumer level)
These encode real game/app rules, not input-class adaptation:
- **05** letter scoring `evaluate` (45–71); the *meaning* of typing a letter into the word grid. (But the 26 raw `keyCode=letter` hardware binds (280–287) are a command-map the framework/a text-command layer could own — straddles B/F.)
- **07** swap-direction adjacency in `activateCell` (253–263) and all board logic (86–166).
- **06** select-then-place semantics `selectSlot`/`placeAt` (66–90).
- **03** optimistic mutation `commit`/loopback server (44–90).
- **02** star rating value from scrub ratio `scrubRating` (127–137) and `onReorder` data splice (225–248); the reorder-under-filter rule.
- **01** numeric grammar `acceptNumeric` (42–47), `onChange`/`onCommit` parse (104–111).

---

## Bottom line
- Two examples (01, 02) are fully PROVEN across all four input classes — but only by
  carrying the two heaviest `present` wiring blocks in the suite (~12 and ~44 generic
  lines). They prove the behavior *and* prove the boilerplate that §0 wants gone.
- Five examples have real matrix holes: **03** (touch/kbd/pad UNPROVEN), **04** (pointer/touch
  UNPROVEN), **05** (pointer/touch UNPROVEN, pad PARTIAL), **06** (touch/kbd/pad UNPROVEN,
  grid nav structurally absent), **07** (only pad, and only PARTIAL).
- The single largest reusable savings: **activation routing (kind B, all 7 examples)** and
  **navigation groups (kind A, 4 examples)** — if `Button`/`Toggle`/`TextInput`/`Table`
  delivered their own Activate and the presenter accepted first-class navigation groups,
  ~90 of the ~158 generic input-wiring lines would disappear, and the UNPROVEN cells for
  03/04/06 would close without any consumer code.
