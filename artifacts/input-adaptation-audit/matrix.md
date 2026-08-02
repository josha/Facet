# LuauUI — Unified Input-Adaptation Audit Matrix

Audit date: **2026-07-21**. Library root: `GameStudio/ui/LuauUI`. All `file:line`
references are relative to that root.

This is **the** durable audit-matrix artifact the gate verifies. It consolidates the
three work-package audits into one master matrix, one example×input proof matrix, the
regression-proof boilerplate baselines, totals, and a synthesized root-cause reading.
It is **evidence, not plan** — the fix design lives in a separate ADR. Cross-file
inconsistencies were re-checked against source; verifications are cited inline.

## Governing principle (`ui_todo.md` §0, director 2026-07-20)

> Auto-adaptation is not just layout. Each control/tool must ship with the right
> interaction for ALL supported inputs — **pointer (mouse), touch, keyboard, AND
> gamepad** — before it counts as done. A control that only works with a mouse is an
> unfinished control. Every interactive surface needs a focus/navigation story
> (D-pad/arrows), an Activate story (A/Cross/Return/tap), a Cancel story where
> applicable, and input-appropriate affordances (touch edit-mode handles, gamepad grab
> mode), **verified per input in tests, with NO CONSUMER WIRING**. (Roblox maps
> PlayStation Cross to ButtonA — one binding covers both consoles.)

The audit measures each control cell against that "no consumer wiring" bar.

## Classification key

| Code | Meaning |
|---|---|
| **AUTO** (FRAMEWORK-AUTOMATIC) | Works when a consumer merely mounts the control and presents the screen — no extra handlers, groups, bindings, or injected systems. (WP-B labels this **FA**; identical meaning.) |
| **CW** (CONSUMER-WIRED) | Works, but only because the consumer hand-passes a handler / group / binding / injected system, or must call an api the control exposes (`buildFocusGroups`, `handleActivate`, `handleGrabNavigate`, `handleFocusMoved`, `handleAdjust`, `handleReorderNav`, `syncGeometry`). Mounting alone does not connect it. |
| **MISSING** | No path exists on that input class. |

One verdict per cell = the load-bearing affordance for that input class. Where an AUTO
sub-affordance (focus reachability, event delivery, a gesture) sits under a CW/​MISSING
verdict, the split is stated inline in the evidence appendix, not re-scored.

## Per-cell evidence appendix (the three WP files)

Each master-matrix cell below carries **one** decisive citation. The full per-cell detail
— every sub-affordance, every alternate seam, the honest test-coverage tables — lives in:

- **WP-A** `artifacts/input-adaptation-audit/wp-a-framework.md` — framework layer:
  Button, Toggle, TextField, TextInput, PopupButton, FocusGraph/NavigationGroups,
  Presenter modal/dialog machinery, the default action context, per-class test coverage.
- **WP-B** `artifacts/input-adaptation-audit/wp-b-composites.md` — Table (6 behaviors),
  VirtualList (3 behaviors), the presenter⇄control seam, the VirtualList touch-pan gap.
- **WP-C** `artifacts/input-adaptation-audit/wp-c-examples.md` — the 7 gallery examples:
  per-example wiring inventory, example×input proof matrix, boilerplate baselines.

---

# 1. Master control matrix

16 rows (7 framework rows + 9 composite behaviors) × 4 input classes = **64 control
cells**. Cell = classification + most load-bearing `file:line`.

## 1a. Framework layer (WP-A) — 28 cells

| Row | pointer | touch | keyboard | gamepad |
|---|---|---|---|---|
| **Button** (leaf) — contract `contract.luau:29-34` | **CW** — no `onClick`/`onActivate` prop; effect only via consumer `opts.onActivate` (`blueprint.luau:159-162`; `presenter.luau:110-119`) | **CW** — same seam; touch only distinguished by meta `pointer="touch"` (`screen_target.luau:562`) | **CW** — Nav+Activate bindings AUTO, effect still consumer `onActivate` (`presenter.luau:180,299-311`) | **CW** — `ButtonA` AUTO-bound; effect still consumer `onActivate` (`presenter.luau:181`) |
| **Toggle** (leaf) — contract `contract.luau:35-40` | **CW** — value→visual is AUTO (`screen_target.luau:392-407`) but "Activate flips value" implemented by **no framework code**; consumer flips (`init.client.luau:144-145`) | **CW** — same | **CW** — same | **CW** — same |
| **TextField** (leaf primitive) — `screen_target.luau:31` | **CW** — entire edit behavior delegated to handler props supplied by composite/consumer (`renderer.luau:260-275`) | **CW** — same | **CW** — same | **CW** — same |
| **TextInput** (composite) — `text_input.luau` | **CW** — native TextBox-focus edit AUTO, but full contract needs `handleActivate` routing (`text_input.luau:330-341`) | **CW** — keep-visible needs consumer `keepVisibleOffset`+`onGeometry` (`presenter.luau:223-228`) | **CW** — "typing≠nav" sink needs injected `actionSystem` (`text_input.luau:44,165`) | **CW** — `ButtonB` revert gated on injected `actionSystem` (`text_input.luau:176-180`) |
| **PopupButton** (composite) — `popup_button.luau` | **CW** — open/select/cancel route via consumer `handleActivate` (`popup_button.luau:104-119`) | **CW** — same; **no scrim / tap-outside-to-close** (sub-affordance MISSING) (`popup_button.luau:158-167`) | **CW** — option nav AUTO; open/select via `Return` is CW | **CW** — `ButtonA` open+select routing CW (`popup_button.spec.luau:186-203`) |
| **FocusGraph / NavigationGroups** — `focus_graph.luau` | **AUTO** — tap-moves-focus `graph.focusOn` (`presenter.luau:114`) | **AUTO** — same `focusOn` seam | **AUTO** (flat ring) — arrow→`navigate(±1)` (`presenter.luau:247-288`); 2D groups are a CW rider (`opts.navigationGroups`) | **AUTO** (flat ring) — DPad drives same ring (`presenter.luau:169-170`); grouped `NavigateH` CW |
| **Presenter modal / dialog** — `presenter.luau` | **CW** — trap machinery AUTO; scrim-to-dismiss consumer-built (`04_confirm_dialog.luau:47-57`) | **CW** — same; no framework scrim | **MISSING** — Escape engine-reserved & deliberately unbound; no other keyboard Cancel (`presenter.luau:198-202`) | **AUTO** — `Cancel`→`ButtonB` dismisses top modal (`presenter.luau:202,312-316`) |

Framework-layer tally: **AUTO 5, CW 22, MISSING 1** (= WP-A §1 tally).
Carried sub-affordance-MISSING inside CW cells: PopupButton touch outside-dismiss; hint
text on every control (no framework code renders `preferredBinding` labels — WP-A §2.5).

## 1b. Composites — Table (WP-B) — 24 cells

| Behavior | pointer | touch | keyboard | gamepad |
|---|---|---|---|---|
| **row-selection** | **CW** — Button hit + `selected` visual FA, but tap→selection via consumer `handleActivate` (`table.luau:1022,1063-1071`) | **CW** — same path; touch meta→additive (`table.luau:1063`) | **CW** — Return-select + arrow-select needs `onFocusNav`→`handleFocusMoved` (`table.luau:1247-1257`) | **CW** — same apis; DPad bindings FA, routing CW |
| **header-sort** | **CW** — tap cycles `sortOrder` via `handleActivate` sort branch (`table.luau:1039-1048`) | **CW** — same tap path (`table.luau:1039`) | **MISSING** — sort hit `focusable=false`, never in focus ring (`table.luau:771`, verified) | **MISSING** — no focusable sort target |
| **column-resize (Grip)** | **FA** — grip drag; blueprint handlers + adapter capture (`table.luau:690-738`; `screen_target.luau:632-702`) | **FA** — `Touch` handled identically, no pointerType gate (`screen_target.luau:638-644`); *no touch test; 8px target* | **CW** — focused grip + Adjust needs `opts.onAdjust`→`handleAdjust` (`table.luau:1217-1241`; presenter binds Adjust only if `onAdjust` `:184-197`) | **CW** — L1/R1/DPadLR Adjust, same seam (`table.spec.luau:1002-1007`) |
| **row-reorder** | **FA** (gesture) — row-body drag; ghost+drop line (`table.luau:614-627,383-556`); needs `reorderable=true`+`onReorder` data | **CW** — pan scrolls; reorder needs edit-mode toggle via `handleActivate` (`table.luau:1024-1027`) | **CW** — shift+Navigate needs `onReorderNav`→`moveRow` (`table.luau:1262-1288`) | **CW** — A-grab/DPad-step/A-drop via `handleGrabNavigate` (`table.luau:1081-1133`) |
| **scroll** | **FA** — wheel via `UI.ScrollView` `onScrollWheel` (`table.luau:821-834`) | **FA** — one-finger `panDrag` on row body (`table.luau:402-408,437-439`) | **MISSING** — focus can step off-screen; nothing calls `scrollOffset` (`table.luau:1247-1257`) | **MISSING** — same; DPad focus does not scroll |
| **cell/row focus-navigation** | **FA** — click focuses `graph.focusOn` (`presenter.luau:114`) | **FA** — same `onNodeTap` | **CW** — row up/down FA, but **horizontal cell/column** nav needs `buildFocusGroups` (`table.luau:1140-1200`) | **CW** — DPad up/down FA; left/right across a row CW (same) |

Table tally: **FA 7, CW 13, MISSING 4** (= WP-B).

## 1c. Composites — VirtualList (WP-B) — 12 cells

| Behavior | pointer | touch | keyboard | gamepad |
|---|---|---|---|---|
| **scroll** | **MISSING** — bare `UI.Anchor`, no ScrollView/onScrollWheel (`virtual_list.luau:147-180`, grep verified NONE) | **MISSING** — no pan handlers; the open item in `ui_todo` §3 "VirtualList touch-pan wiring" | **CW** — programmatic only: consumer drives `scrollTop:set`/`focusKey` (`virtual_list.luau:130-145`); no binding | **CW** — same; no binding exists |
| **focus / navigation** | **MISSING** — row is a plain `VStack`, not focusable; no hit (`virtual_list.luau:169-176`) | **MISSING** — same | **CW** — `pathOf`/`focusKey`/`focusedKey` exposed but no `buildFocusGroups`, no presenter integration (`virtual_list.luau:98-145,182-188`) | **CW** — same; no DPad→row mapping |
| **activate** | **MISSING** — no `handleActivate`, no row hit | **MISSING** — same | **MISSING** — no control activate api | **MISSING** — same |

VirtualList tally: **CW 4, MISSING 8** (= WP-B).

## 1d. Combined control totals (64 cells)

| Classification | Framework (28) | Table (24) | VirtualList (12) | **Total (64)** |
|---|---:|---:|---:|---:|
| **FRAMEWORK-AUTOMATIC** | 5 | 7 | 0 | **12** |
| **CONSUMER-WIRED** | 22 | 13 | 4 | **39** |
| **MISSING** | 1 | 4 | 8 | **13** |

**Per input class** (16 rows each):

| Class | AUTO/FA | CW | MISSING | total |
|---|---:|---:|---:|---:|
| pointer | 5 | 8 | 3 | 16 |
| touch | 4 | 9 | 3 | 16 |
| keyboard | 1 | 11 | 4 | 16 |
| gamepad | 2 | 11 | 3 | 16 |
| **total** | **12** | **39** | **13** | **64** |

**Per control / behavior**:

| Row | AUTO/FA | CW | MISSING |
|---|---:|---:|---:|
| Button | 0 | 4 | 0 |
| Toggle | 0 | 4 | 0 |
| TextField | 0 | 4 | 0 |
| TextInput | 0 | 4 | 0 |
| PopupButton | 0 | 4 | 0 |
| FocusGraph / NavigationGroups | 4 | 0 | 0 |
| Presenter modal | 1 | 2 | 1 |
| Table · row-selection | 0 | 4 | 0 |
| Table · header-sort | 0 | 2 | 2 |
| Table · column-resize | 2 | 2 | 0 |
| Table · row-reorder | 1 | 3 | 0 |
| Table · scroll | 2 | 0 | 2 |
| Table · focus-navigation | 2 | 2 | 0 |
| VirtualList · scroll | 0 | 2 | 2 |
| VirtualList · focus/nav | 0 | 2 | 2 |
| VirtualList · activate | 0 | 0 | 4 |

Headline: only **FocusGraph is fully AUTO on all four classes**. Keyboard is the weakest
class (1 AUTO of 16). VirtualList contributes 8 of the 13 MISSING cells. Every leaf and
composite control lands CW on its own Activate story despite the nav/activate **bindings**
themselves being automatic.

---

# 2. Example × input proof matrix (WP-C)

7 gallery examples × 4 input classes = **28 example cells**. Legend: **PROVEN** = a spec
fires that class's real device input against the example's own controls; **PARTIAL** =
only some affordances, or nav proven via the focus API (`navigateDirection`) rather than a
device key; **UNPROVEN** = no spec exercises that class. G = `tests/examples_gallery.spec.luau`,
M = `tests/examples_games.spec.luau`.

| Example | pointer (mouse) | touch | keyboard | gamepad |
|---|---|---|---|---|
| **01 Temp Converter** | PROVEN — G:137 `tap(FIELD)` | PROVEN — G:141 `tap(FIELD,{pointer="touch"})` | PROVEN — G:146-153 `deviceKey("Return")` enters edit + commit | PROVEN — G:155-170 `ButtonA` enter, `ButtonB` cancel/revert |
| **02 Playlist Table** | PROVEN — G:341-400 tap/drag/scrub | PROVEN — G:402-429 touch Edit + handle reorder | PROVEN — G:312-326 filter edit; typing sunk | PROVEN — G:431-516 full DPad + rate + grab-move-drop |
| **03 Settings Sync** | PROVEN — G:559,581 `tap` toggle/+/− | **UNPROVEN** — no touch tap | **UNPROVEN** — no `deviceKey` activate | **UNPROVEN** — no `ButtonA` |
| **04 Confirm Dialog** | **UNPROVEN** — buttons never `tap`'d | **UNPROVEN** — no touch tap | PROVEN — G:614 `Return` opens; G:621-626 nav+wrap | PROVEN — G:629 `ButtonB` cancel; G:643-651 `ButtonA` |
| **05 Word Game** | **UNPROVEN** — on-screen keys never `tap`'d | **UNPROVEN** — no touch tap | PROVEN — M:52-101 letters/Return/Backspace *(arrow NAV only PARTIAL)* | **PARTIAL** — M:89-101 nav via `navigateDirection`; DPad+ButtonA never fired |
| **06 Tile Game** | PROVEN — M:139-147 `tap` select-then-place | **UNPROVEN** — no touch tap | **UNPROVEN** — no `deviceKey`, no focus nav | **UNPROVEN** — no groups (flat ring; grid nav absent) |
| **07 Match-3** | **UNPROVEN** — swaps via direct `game.swap()` (M:192) | **UNPROVEN** — no touch tap | **UNPROVEN** — no `deviceKey` | **PARTIAL** — M:253-262 nav via `navigateDirection`; DPad+ButtonA never fired |

**Example-cell totals (verified against the matrix rows):** **PROVEN 13, PARTIAL 2,
UNPROVEN 13** (= 28). Not-fully-PROVEN = **15** (2 PARTIAL + 13 UNPROVEN).

> Inconsistency flagged & corrected: WP-C's prose header reads "18 of 28 cells are not
> fully PROVEN." Recounting WP-C's own matrix rows yields 13 PROVEN / 2 PARTIAL / 13
> UNPROVEN → **15** not-fully-PROVEN, not 18. The matrix-derived count (15) is authoritative
> here; the "18" appears to be a prose arithmetic slip in WP-C and does not change any cell
> verdict. Recorded per the cross-check requirement.

Gap reading: **01, 02** fully PROVEN on all four (the model cases — but they carry the two
heaviest `present` wiring blocks, §3). **04** is the inverse of **03**: keyboard+gamepad
PROVEN, pointer+touch UNPROVEN. **06** has gamepad grid nav *structurally absent* (flat
ring, no groups). **05/07** gamepad is only PARTIAL (focus-API nav, no device DPad/ButtonA).

---

# 3. Boilerplate baselines (regression-proof, WP-C)

`wc -l` newline totals; input-wiring counts are the generic (framework-should-own) input
plumbing with the cited primary span. Spans reproducible from the files as read 2026-07-21.
These are the exact baselines a later fix regresses against.

| Example | Total lines | Input-wiring lines (generic) | Primary span(s) | Kind of wiring |
|---|---:|---:|---|---|
| 01 Temp Converter | 171 | ~12 | present 142-151; deps 112-113 | activation route + geometry/keepVisible + sinkNav |
| 02 Playlist Table | 343 | ~44 (+~12 pointer scrub) | present 273-316; Grip 160-171 | nav groups + grab intercept + activation route + focus-nav + geometry/keepVisible |
| 03 Settings Sync | 146 | ~11 | present 122-132 | activation route only |
| 04 Confirm Dialog | 89 | ~15 | present 73-79; modal 51-58 | activation route only |
| 05 Word Game | 347 | ~33 (+~20 app-adjacent letter binds) | groups 214-232; scope 269-270; ctx 276-306; onActivate 249-261 | nav groups + scope swap + device→nav binds + activation route |
| 06 Tile Game | 229 | ~14 | present/onActivate 154-167 | activation route only (no nav story) |
| 07 Match-3 | 354 | ~29 | groups 195/211/238; scope 279-280; ctx 286-302; onActivate 265-273 | nav groups + scope swap + device→nav binds + activation route |
| **Total** | **1,679** | **~158 generic** (+~32 app-adjacent) | — | — |

`assets.luau` (32 lines) and the shared runner `client/init.client.luau` (191 lines) do
**no** per-example input wiring — the runner passes the same
`deps = { env, actionSystem, presenter, adapter }` to every example (76-81) and presents
`{ screen, present }` via `pres.present(...)` (86). It is the neutral seam, not boilerplate.
WP-C estimate: if `Button`/`Toggle`/`TextInput`/`Table` delivered their own Activate and the
presenter accepted first-class navigation groups, **~90 of the ~158 generic lines** would
disappear and the UNPROVEN cells for 03/04/06 would close with no consumer code.

---

# 4. Root causes (synthesized from WP-A/B/C findings)

The 39 CW + 13 MISSING cells trace to seven structural facts, each verified:

**(a) The presenter routes Activate/tap to an opaque consumer callback; nothing reads
`contract.actions`.** `handle.onActivate` is called with a bare `path`
(`presenter.luau:299-311,110-119`); the control's declared `actions`
(`contract.luau:12-53`) are consumed **only** by the conformance test — `forClass`/`.all`
appear nowhere else in `src/` (grep verified NONE this session). So no mounted control's
own behavior is reachable without the consumer re-deriving "which control is this path" by
string match. This alone produces ~20 of the 22 framework-layer CW cells.

**(b) Composites expose uniform apis the consumer must hand-connect.** Table publishes
`handleActivate`/`buildFocusGroups`/`handleGrabNavigate`/`handleFocusMoved`/`handleAdjust`/
`handleReorderNav`/`moveRow` (`table.luau:1022,1140,1081,1247,1217,1262-1288`); TextInput
publishes `handleActivate`/`syncGeometry`/`keepVisibleOffset`. The logic lives in the
control, but mounting does not connect it — every screen re-plumbs the same six methods by
hand (canonical: `02_playlist_table.luau:273-316`). The presenter never walks the mounted
tree to discover these providers (`presenter.luau:127-135,110-119,281-286,184`).

**(c) No framework code creates `uiButton` touch bindings or renders hints.** The action
model supports `uiButton` bindings and `preferredBinding("Touch")`
(`actions.luau:74-119`; adapter `roblox_input.luau:140-142,188-191`) and `env.preferredInput`/
`capabilities` are live (`roblox_env.luau:31-40`), but **no call site ever creates a
`uiButton` binding** (grep: definitions only) and **no framework code renders a hint** — the
gallery hand-builds a hint memo (`init.client.luau:116-122`). Touch works solely through the
tap seam; there is no on-screen Cancel/Nav button and no affordance label.

**(d) VirtualList has no input wiring at all.** It is a bare `UI.Anchor` with `overflow="clip"`
(`virtual_list.luau:147-180`, verified) — no `UI.ScrollView`, no `onScrollWheel`, no pointer/pan
capture, no `handleActivate`, no `buildFocusGroups`, no presenter integration. Only `scrollTop`
(a Signal) and programmatic `focusKey`/`pathOf` exist. Mounting it yields **zero** device
interaction on any class — this is the source of 8 of the 13 MISSING cells and the standing
`ui_todo` §3 open item ("VirtualList touch-pan wiring").

**(e) NavigationGroups are always consumer-supplied.** The presenter auto-derives a **flat**
ring from the mounted tree (`presenter.luau:67-73,247-288`) but discards container structure;
grouped, direction-aware 2D navigation binds only when the consumer passes
`opts.navigationGroups` (`presenter.luau:127-140,173-179`), which it never synthesizes.
Examples 02/05/07 hand-build groups (05's own comment: *"the presenter offers no hook to
supply navigation groups"* `05_word_game.luau:265-268`); 06's *absence* of groups is why its
gamepad grid nav is structurally missing.

**(f) TextInput requires consumer injection of `actionSystem` / geometry / keepVisible —
though it is the only four-class-PROVEN control.** The "typing≠navigation" sink forms only
when the consumer injects `spec.actionSystem` (`text_input.luau:44,165`); keep-visible applies
only when the consumer passes `keepVisibleOffset`+`onGeometry` (`presenter.luau:223-228,
122-125,406-412`). Its full-coverage proof (WP-A §4) is bought entirely with per-consumer
wiring — it proves both the behavior and the boilerplate §0 wants gone.

**(g) Toggle's contract promises Activate-flips-value, but nothing implements it.** The
contract states *"Activate flips value"* (`contract.luau:38-39`); the value→visual half is
automatic (`screen_target.luau:392-407`) but there is **no Toggle control module** and no
presenter default — the consumer performs the flip inside `onActivate`
(`init.client.luau:144-145`). Toggle has **zero** input-simulation test coverage (WP-A §4).

Cross-cutting: the presenter is a "blank pipe" — it acts only on `opts` the screen hands it
and never inspects the mounted tree for controls that could answer for themselves
(`presenter.luau:110-135,184,281-286`). Prior art proves the adaptive pattern is already
viable in one place: the Table's Edit/Done toggle switches idiom purely from
`env:get("preferredInput")` with no consumer flag (`table.luau:132-138,862-884`).

---

# 5. Engine truths (`ui_todo.md` §3, live-probe-verified) and where each must be encoded

These are hard Roblox-platform facts the audit depends on. Each must live somewhere durable
— framework code, a doctor/health check, or docs — so a future consumer cannot re-hit them.

| # | Engine truth (verbatim intent) | Where it must be encoded |
|---|---|---|
| 1 | **`jumpAction` eats ButtonA unconditionally in legacy control scripts.** The legacy control scripts bind gamepad ButtonA to `jumpAction` (CAS prio 2000) even with `Players.CharacterAutoLoads=false` and no character, and silently consume it (`gameProcessed=true`, IAS never fires). D-pad/thumbsticks pass through, masking it. | **Framework code** — a UI-only place must `PlayerModule:GetControls():Disable()` (fallback `UnbindAction("jumpAction")`); real games run the IAS player-script stack or accept contention. This is the reason gamepad Activate can silently die and must be handled in the bootstrap/host, not left to consumers. |
| 2 | **`StarterPlayer.PlayerScriptsUseInputActionSystem` is not script- or rojo-reflectable.** It is a Properties-panel-only flag (re-verified this session); code and Rojo cannot read or set it. | **Doctor check + docs** — a health/doctor check must surface it as unknowable-from-code (assert-or-warn at boot), and the setup docs must instruct the human to toggle it in Studio. It cannot be automated. |
| 3 | **`GuiService.CoreGuiNavigationEnabled` re-enables itself if scripted off** — CoreScripts fight back. (Not the ButtonA eater anyway.) | **Docs + framework code** — record as a known non-fix so no one wires a scripted-off "solution" expecting it to hold; any framework code that touches it must not assume the write sticks. |

Corroborating framework fact (not from §3): **Escape is permanently engine/CoreGui-reserved**
— `cancel` binds only `ButtonB`, and the code comments Escape as deliberately unbound
(`presenter.luau:198-202`, verified). This is why the one framework-layer MISSING cell
(modal keyboard-Cancel) exists and cannot be closed with a keyboard binding — it must be
encoded as a framework-provided scrim/Back path or documented as a hard platform limit.

---

_This matrix is evidence for the gate. It does not propose the fix design — a separate ADR
owns the presenter⇄control discovery seam, VirtualList plumbing, Toggle module, hint layer,
and modal-Cancel resolution. Every cell's full derivation is in WP-A/B/C as cited above._

---

# 6. Closure addendum (2026-07-21, end of day — the lead)

The matrix above is the dated PRE-FIX snapshot. Disposition after the framework work landed
(every claim gate-verified; see `gate.json` and the spec files):

**Control cells (64):** every CONSUMER-WIRED and MISSING cell is now FRAMEWORK-AUTOMATIC
via the ADR-0013 contribution seam + presenter auto-composition (leaf `onActivate` props,
Toggle auto-flip, layout-derived 2D groups, modal outside-tap, Table header-sort kbd/pad +
scroll-into-view, VirtualList full four-input story incl. the ui_todo §3 touch-pan item),
EXCEPT three recorded justified exceptions:
1. **Modal keyboard Cancel** — Escape engine-reserved (D1); sanctioned paths: focusable
   close button (Return/ButtonA), ButtonB, outside-tap. ADR-0013 "Justified exceptions".
2. **Grip column-resize keyboard/gamepad** — Adjust binds only on `opts.onAdjust` so
   non-modal screens never shadow gameplay arrow/bumper keys. ADR-0013 Consequences.
3. **ScrollView** — wheel/pan gesture surface, focusRole="none": named
   `INTERACTIVE_ACTION_EXCEPT` in the checker, not forced to invent four proofs.

**Example cells (28):** all PROVEN (17 new device-true cases for ex03–ex07; ex01/ex02
retained their expansion-textinput proofs with wiring deleted). Boilerplate: ~158 generic
lines → 0; totals 1679 → 1587, no example grew.

**Enforcement:** `controls_registry.inputProofs` + checker rules (7 interactive controls
prove four-input; PROOF_GAPS empty). Scaffold stamps multi-input skeletons.

**Beyond the audit's scope (director direction, same day):** ADR-0014 first-responder model
(passive/engaged/exclusive surfaces, 3000+/3500+ bands, gameplay guard, responder_effects,
`legacyStackActive` detection); guide 07-input.md rewritten user-first (IAS-required warning
up top). Riders: WASD guard set, SelectedObject linkage, live character+flag probe, physical
device — all recorded in ADR-0014 / the standing FAIL_ENVIRONMENT check.
