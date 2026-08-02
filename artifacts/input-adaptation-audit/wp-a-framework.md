# WP-A — Input Auto-Adaptation Framework Audit (LuauUI)

Audit date: 2026-07-21. Library root: `GameStudio/ui/LuauUI`. All `file:line`
references are relative to that root.

Scope: leaf controls (Button, Toggle, TextField), composites (TextInput,
PopupButton), and machinery (focus graph + NavigationGroups, presenter
modal/dialog machinery, the action system + adapters, env facts). `table.luau`
and `virtual_list.luau` were out of scope.

Director standing principle audited against (`ui_todo.md:3-14`, §0): *every
control must ship the right interaction for ALL four input classes — pointer,
touch, keyboard, gamepad — with a focus/navigation story, an Activate story, a
Cancel story where applicable, and input-appropriate affordances, WITH NO
CONSUMER WIRING.*

Classification key:
- **AUTO** = FRAMEWORK-AUTOMATIC: works when a consumer merely mounts the
  control and presents the screen — no extra handlers/groups/bindings.
- **CW** = CONSUMER-WIRED: works, but only because the consumer passes handlers
  / groups / bindings / injected systems by hand (cited).
- **MISSING** = no path at all.

A single verdict is assigned per cell (the *load-bearing* affordance for that
input class). Where a cell has automatic sub-affordances (focus reachability,
event delivery) under a CW verdict, the split is stated inline.

---

## 1. Matrix

### Row: **Button** (leaf) — contract `src/controls/contract.luau:29-34`; focus role `src/present/presenter.luau:49`

| | pointer | touch | keyboard | gamepad |
|---|---|---|---|---|
| verdict | **CW** | **CW** | **CW** | **CW** |

- **pointer — CW.** Focus-on-tap and the activate *event* are AUTO: `TAPPABLE`
  nodes get `setActivateHandler` wired by the renderer
  (`src/render/renderer.luau:208-213`), routed to `onNodeTap` which does
  `graph.focusOn(path)` then calls `handle.onActivate`
  (`src/present/presenter.luau:110-119`); the engine adapter supplies pointer
  kind + modifiers meta (`src/client/screen_target.luau:553-580`). But a
  Button has **no `onClick`/`onActivate` prop** (`src/blueprint.luau:159-162`)
  — its *effect* exists only if the consumer supplies `opts.onActivate` and
  switches on `path` by hand (gallery: `examples/gallery/client/init.client.luau:143-146`).
  A merely-mounted Button does nothing on tap.
- **touch — CW.** Identical seam; touch is distinguished only by the meta
  `pointer="touch"` (`src/client/screen_target.luau:562`,
  `tests/lib/fake_target.luau:260-265`). No touch-specific affordance; no
  `uiButton` on-screen control is ever created (see §3). Same missing effect.
- **keyboard — CW.** Focus reach + nav are AUTO: presenter auto-derives a flat
  focus ring from the mounted tree (`focusWalk`/`focusOrder`
  `src/present/presenter.luau:54-73`, `pushScope … order`
  `src/present/presenter.luau:137-139`) and binds `Navigate` to Up/Down
  (`src/present/presenter.luau:165-166`) and `Activate` to `Return`
  (`src/present/presenter.luau:180`). But the Activate *effect* is again only
  the consumer's `onActivate` (`src/present/presenter.luau:299-311`). No
  framework path from a Button's mounted contract to its behavior.
- **gamepad — CW.** DPadUp/DPadDown auto-bound (`src/present/presenter.luau:169-170`),
  `ButtonA` auto-bound (`src/present/presenter.luau:181`); PS Cross maps to
  ButtonA in the engine (`ui_todo.md:12`). Effect still CW via `onActivate`.
- Hint text: **MISSING** at framework level (see §"hint text" below).

### Row: **Toggle** (leaf) — contract `src/controls/contract.luau:35-40`

| | pointer | touch | keyboard | gamepad |
|---|---|---|---|---|
| verdict | **CW** | **CW** | **CW** | **CW** |

- All four: same nav/event automation as Button. The distinguishing semantic —
  contract says *"Activate flips value"* (`src/controls/contract.luau:38-39`) —
  is **not implemented by any framework code**. There is no Toggle *control
  module* (unlike `popup_button.luau`/`text_input.luau`); `UI.Toggle` is a raw
  leaf (`src/blueprint.luau:163-165`). The value→visual reflection IS automatic
  (`setProp "value"` → `applyToggleValue`, `src/client/screen_target.luau:392-407`,
  `src/client/screen_target.luau:940-941`), but the flip-on-Activate is
  hand-wired by the consumer: gallery does `draftMusic:set(not draftMusic:get())`
  inside its `onActivate` (`examples/gallery/client/init.client.luau:144-145`).
  So every input class delivers the Activate but the consumer must perform the
  toggle. **CW** across the board.

### Row: **TextField** (leaf primitive) — contract `src/controls/contract.luau:46-52`; instance map `src/client/screen_target.luau:31`

| | pointer | touch | keyboard | gamepad |
|---|---|---|---|---|
| verdict | **CW** | **CW** | **CW** | **CW** |

- The bare leaf's entire input behavior is delegated to handler props
  (`onTextChanged`/`onFocusGained`/`onFocusLost`) which the renderer auto-wires
  to the engine TextBox **only if the node carries them**
  (`src/render/renderer.luau:260-275`; adapter seam
  `src/client/screen_target.luau:736-795`). Those handlers are supplied by the
  TextInput composite or the consumer — a bare TextField mounted alone has no
  edit handshake, no commit, no cancel. Focus reachability is AUTO (it is
  `FOCUSABLE`, `src/present/presenter.luau:49`), but every actual text
  interaction (pointer/touch native-focus edit, keyboard/gamepad
  activate-to-edit) requires the composite's or consumer's handlers → **CW**
  for all four. (In practice the leaf is only ever used *inside* TextInput —
  see next row.)

### Row: **TextInput** (composite) — `src/controls/text_input.luau`

| | pointer | touch | keyboard | gamepad |
|---|---|---|---|---|
| verdict | **CW** | **CW** | **CW** | **CW** |

- **pointer — CW.** Two edit-entry paths exist. (a) Native TextBox focus →
  `onFocusGained` → `beginEditing` is AUTO on a real engine once the renderer
  wires the text seam from props (`src/render/renderer.luau:260-275`;
  `src/client/screen_target.luau:759-766`; control learns its path here,
  `src/controls/text_input.luau:304-309`). (b) The presenter Activate/tap →
  `onActivate` → `control.api.handleActivate` (`src/controls/text_input.luau:330-341`)
  is **CW** — the consumer must route it (`examples/gallery/examples/01_temperature_converter.luau:144-146`;
  harness `tests/text_input.spec.luau:66-71`). Verdict CW because the full
  contract beyond native focus requires wiring (below).
- **touch — CW.** Touch's load-bearing affordance is keyboard-occlusion
  keep-visible. The control *publishes* `keepVisibleOffset`
  (`src/controls/text_input.luau:139-156`, `:321`) but it only takes effect if
  the consumer passes `opts.keepVisibleOffset` **and** `opts.onGeometry`
  (feeding `syncGeometry`) to `present()`
  (`examples/gallery/examples/01_temperature_converter.luau:147-150`; harness
  `tests/text_input.spec.luau:72-78`). Presenter applies the offset only when
  the opt is present (`src/present/presenter.luau:223-228`) and feeds geometry
  only when `onGeometry` is present (`src/present/presenter.luau:122-125,406-412`).
  → CW.
- **keyboard — CW.** Field reach is AUTO; entering edit via `Return` is CW
  (activate routing). The "typing does not navigate" sink context is built
  *inside* the control (`ensureEditContext`, `src/controls/text_input.luau:161-189`)
  but **only if the consumer injects `spec.actionSystem`**
  (`src/controls/text_input.luau:44,165`;
  `examples/gallery/examples/01_temperature_converter.luau:113`; harness
  `tests/text_input.spec.luau:63`). Escape-cancel arrives AUTO via the adapter
  text seam mapping FocusLost→`"cancel"` (`src/client/screen_target.luau:774-784`).
  → CW (activate routing + actionSystem injection).
- **gamepad — CW.** `ButtonA` enters edit (CW routing); `ButtonB` reverts via
  the control's edit context (`src/controls/text_input.luau:176-180`) — gated on
  the injected `actionSystem`. → CW.

### Row: **PopupButton** (composite) — `src/controls/popup_button.luau`

| | pointer | touch | keyboard | gamepad |
|---|---|---|---|---|
| verdict | **CW** | **CW** | **CW** | **CW** |

- **pointer — CW.** Open/select/cancel all route tap → `onActivate` →
  `control.api.handleActivate` (`src/controls/popup_button.luau:104-119`), which
  the consumer must wire (harness `tests/popup_button.spec.luau:49-52`). Also
  requires `sinkNavigation=true` passed by hand so nav keys don't leak
  (`tests/popup_button.spec.luau:49`).
- **touch — CW, with a MISSING sub-affordance.** Same routing as pointer. There
  is **no scrim / tap-outside-to-close**: the floating panel is a plain VStack
  overlay (`src/controls/popup_button.luau:158-167`) with no backdrop; closing
  requires re-tapping the trigger or the Cancel row
  (`src/controls/popup_button.luau:105-112`). Touch dismiss-by-outside =
  MISSING.
- **keyboard — CW.** Navigating the open options is AUTO — the option rows are
  ordinary focusable Buttons the presenter's ring picks up on `refresh`
  (`src/controls/popup_button.luau:11-13,133-155`; presenter re-derives focus on
  refresh `src/present/presenter.luau:406-423`). Open/select via `Return` is CW
  (activate routing).
- **gamepad — CW.** Same; `ButtonA` open+select routing CW
  (`tests/popup_button.spec.luau:186-203`).

### Row: **FocusGraph / NavigationGroups** — `src/focus/focus_graph.luau`

| | pointer | touch | keyboard | gamepad |
|---|---|---|---|---|
| verdict | **AUTO** | **AUTO** | **AUTO** | **AUTO** |

- **pointer / touch — AUTO.** Tap-moves-keyboard-focus is automatic:
  `graph.focusOn(path)` on every tap (`src/present/presenter.luau:114`;
  `focus_graph.focusOn` `src/focus/focus_graph.luau:414-421`, active-scope
  guarded).
- **keyboard — AUTO (flat ring), with a CW rider for 2D groups.** The presenter
  auto-derives a flat ring from the mounted tree and drives it from arrow keys:
  `Navigate` → `graph.navigate(±1)` (`src/present/presenter.luau:247-288`;
  flat ring wraps `src/focus/focus_graph.luau:272-297`). **Grouped, direction-
  aware (Left/Right axis, containment, exits) 2D navigation is CW** — the
  consumer must pass `opts.navigationGroups` (a static array or a function of
  the mounted root), which the presenter does not synthesize; it only builds a
  flat `order` otherwise (`src/present/presenter.luau:127-140`). Example 02
  hand-builds groups from row paths
  (`examples/gallery/examples/02_playlist_table.luau:280-290`). Nothing derives
  groups from control contracts or layout containers.
- **gamepad — AUTO (flat ring) / CW (groups).** DPad drives the same ring
  (`src/present/presenter.luau:169-170`; `tests/navigation_groups.spec.luau:237-250`).
  Grouped `NavigateH`/DPadLeft-Right only bound *when* `navigationGroups` is
  supplied (`src/present/presenter.luau:173-179`).

### Row: **Presenter modal / dialog machinery** — `src/present/presenter.luau`

| | pointer | touch | keyboard | gamepad |
|---|---|---|---|---|
| verdict | **CW** | **CW** | **MISSING** | **AUTO** |

- **pointer — CW.** The modal *machinery* is AUTO: `presentModal` builds a focus
  trap (`pushScope … trap = kind=="modal"`, `src/present/presenter.luau:135,139`;
  trap+restore `src/focus/focus_graph.luau:142-161`) and a higher-priority
  **sinking** nav context (`src/present/presenter.luau:154-158,81-89`). But the
  pointer *Cancel affordance* (tap-scrim-to-dismiss) is CW — the consumer builds
  the scrim/close button and calls `presenter.dismiss` in its `onActivate`
  (`examples/gallery/examples/04_confirm_dialog.luau:47-57`).
- **touch — CW.** Same — no framework-provided scrim; consumer-built.
- **keyboard — MISSING.** Escape is permanently engine/CoreGui-reserved and
  cannot be bound (`src/present/presenter.luau:198-201`). No other keyboard key
  is bound to Cancel/back. A keyboard-only user has **no framework Cancel path**
  out of a modal; close is entirely screen-provided (scrim tap / gear). The
  focus trap itself is automatic, but the Cancel *story* is absent.
- **gamepad — AUTO.** `Cancel` action bound to `ButtonB`
  (`src/present/presenter.luau:202`); `cancel.onPressed` auto-dismisses the top
  modal (`src/present/presenter.luau:312-316`); `self.back()` pops the top modal
  (`src/present/presenter.luau:396-404`). Proven end to end
  (`tests/presenter.spec.luau:74-90`).

### Cell tally

| verdict | count |
|---|---|
| FRAMEWORK-AUTOMATIC | **5** |
| CONSUMER-WIRED | **22** |
| MISSING | **1** |
| **total** | **28** |

(AUTO = FocusGraph ×4 + Presenter/gamepad ×1. MISSING = Presenter/keyboard
cancel. Everything else CW.) Sub-affordance MISSING items carried inside CW
cells: PopupButton touch outside-dismiss; hint text on every control.

---

## 2. Where the auto-wiring seam belongs

Each item names the file/function where the framework could *lift* the wiring
so mounting the control is sufficient. (Seam naming only — no code proposed.)

1. **Per-control Activate routing (fixes 20 of the 22 CW cells).** Today
   `handle.onActivate` is an opaque consumer callback the presenter calls with a
   `path` (`src/present/presenter.luau:299-311,110-119`); nothing reads a
   control's declared `actions` (`src/controls/contract.luau:12-53`) — confirmed:
   `contract.forClass`/`.all` are consumed only by the conformance test, never by
   the presenter or renderer. **Seam:** `presenter.makeHandle`
   (`src/present/presenter.luau:103`) should maintain a mount-time registry of
   focusable nodes → their control's own `handleActivate`, and auto-dispatch
   Activate/tap to the control that owns the path, falling back to `onActivate`
   only for app-level commands. Composites already expose the uniform
   `api.handleActivate(path, meta)` seam
   (`src/controls/popup_button.luau:104`, `src/controls/text_input.luau:330`) —
   the registry just needs the presenter to call it instead of the consumer.

2. **Toggle flip-on-Activate.** There is no Toggle control module. **Seam:**
   either a `src/controls/toggle.luau` composite (mirroring popup/text_input)
   exposing `handleActivate` that flips its bound `value`, or a presenter
   default keyed on `contract.forClass(class).actions` containing `"Activate"`
   for class `Toggle` (`src/controls/contract.luau:35-39`). The value→visual
   half already exists (`src/client/screen_target.luau:392-407`).

3. **Auto-derived NavigationGroups.** `presenter.focusOrder`
   (`src/present/presenter.luau:67-73`) walks the mounted tree for a flat ring
   but discards container structure. **Seam:** extend that same walk to emit
   `NavigationGroup`s from layout containers (HStack→`axis="horizontal"`,
   VStack→`axis="vertical"`), so 2D navigation is automatic without the consumer
   passing `opts.navigationGroups` (`src/present/presenter.luau:127-140`). The
   grouped graph already consumes such groups (`src/focus/focus_graph.luau:19-27`).

4. **Auto keep-visible + actionSystem injection for composites.** The presenter
   applies `keepVisibleOffset` and feeds `onGeometry` only when the consumer
   passes those opts (`src/present/presenter.luau:122-125,223-228,406-412`), and
   TextInput's sink context only forms when the consumer injects `actionSystem`
   (`src/controls/text_input.luau:44,165`). **Seam:** at `makeHandle`, the
   presenter (which already owns `actionSystem` and the controller's `rectOf`)
   could auto-inject `actionSystem` into mounted composites and auto-observe any
   control that publishes a `keepVisibleOffset`/`syncGeometry` api — removing the
   three hand-wired opts per TextInput consumer.

5. **Hint text.** `action.preferredBinding(preferredInput)` exists
   (`src/input/actions.luau:109-119`; engine parity `src/client/roblox_input.luau:178-197`)
   and `env.preferredInput`/`capabilities` are live
   (`src/client/roblox_env.luau:31-40`), but **no framework code renders a
   hint** — the gallery hand-builds a hint memo off `env.preferredInput`
   (`examples/gallery/client/init.client.luau:116-122`). **Seam:** a small
   `UI.Hint`/presenter-provided binding that observes `env:get("preferredInput")`
   and an action's `preferredBinding().displayName`, so controls surface the
   correct affordance label with no consumer memo.

6. **Modal keyboard Cancel (the one MISSING cell) + auto scrim.** Escape is
   engine-reserved (`src/present/presenter.luau:198-201`), so keyboard back is
   absent and touch/pointer dismiss is consumer-built
   (`examples/gallery/examples/04_confirm_dialog.luau:47-57`). **Seam:**
   `presenter.presentModal` (`src/present/presenter.luau:350-354`) could auto-
   insert a tappable scrim child (covering pointer/touch dismiss) and bind a
   non-reserved keyboard key (or route the platform Back) to `self.back()`
   (`src/present/presenter.luau:396`), giving all four classes a Cancel story.

7. **Touch on-screen action buttons.** The action model supports `uiButton`
   bindings and `preferredBinding("Touch")` (`src/input/actions.luau:74-119`;
   `src/client/roblox_input.luau:140-142,188-191`), but **no framework code ever
   creates a `uiButton` binding** (grep: only definitions, no call sites). Touch
   works solely through the tap seam; there is no on-screen Cancel/Nav button for
   touch. **Seam:** the same presenter nav-context builder
   (`src/present/presenter.luau:154-202`) that binds keys could, under
   `env.preferredInput=="Touch"`/`capabilities.touch`, also emit `uiButton`
   bindings for Cancel/Adjust.

---

## 3. Default action context

**Yes — framework code DOES create a standard navigation/activate/cancel action
context with bindings, automatically, for every presented screen.** It is the
one substantial piece of auto-adaptation already in place.

`presenter.makeHandle` (`src/present/presenter.luau:154-202`) creates, per
presented screen/modal, a nav `InputContext` and binds:

- `Navigate` (Direction1D): `Down`/`Up` (`:165-166`) **+** `DPadDown`/`DPadUp`
  (`:169-170`) — keyboard arrows and gamepad d-pad, automatically.
- `Activate` (Bool): `Return` (`:180`) **+** `ButtonA` (`:181`) — keyboard and
  gamepad (PS Cross = ButtonA). Automatic.
- `Cancel` (Bool): `ButtonB` (`:202`) — gamepad. Automatic. Escape is engine-
  reserved and deliberately unbound (`:198-201`).
- `NavigateH` (Left/Right + DPadLeft/Right): auto-bound **only** for grouped
  screens (`:173-179`).
- `Adjust` (Left/Right/Comma/Period/DPadLeft-Right/L1/R1): auto-bound **only**
  when the consumer passes `opts.onAdjust` (`:184-197`).

The pointer/touch tap half is likewise auto-wired: the renderer attaches
`setActivateHandler` to tappable nodes (`src/render/renderer.luau:208-213`) and
the presenter's `onNodeTap` runs focus + activate
(`src/present/presenter.luau:110-119`).

**Two gaps in this otherwise-automatic context:**
- It binds **no `uiButton`** — touch has no on-screen action buttons; touch
  relies entirely on tapping controls (§2 item 7).
- It routes Activate to the opaque consumer `onActivate`, **not** to any mounted
  control's own handler (§2 item 1) — which is why every leaf/composite row above
  lands on CW despite the bindings themselves being automatic.

No shared harness in `tests/lib` or `examples/gallery/client` creates a
*different* default context; they all rely on this presenter-built one (the
gallery client injects the real IAS via `roblox_input.newSystem` and lets the
presenter build the context, `examples/gallery/client/init.client.luau:27-28`).
The only consumers that build their *own* extra contexts are the game examples
that need bespoke keymaps — e.g. Wordle binds letter keys + Enter/Backspace in a
sink context by hand (`examples/gallery/examples/05_word_game.luau:276-297`),
which is app-specific and expected. Notably, example 05's own comment concedes
the framework limit: *"the presenter offers no hook to supply navigation
groups"* for its grid (`examples/gallery/examples/05_word_game.luau:265-268`),
corroborating §2 item 3.

---

## 4. Honest per-input-class test coverage (audit-scope controls)

"Simulated" = the test drives the class through a real seam: `system.deviceKey`
(keyboard/gamepad key codes), `adapter.tap` (pointer; `meta.pointer="touch"` for
touch), or the engine text seam (`focusText`/`typeText`/`commitText`).

| control | pointer | touch | keyboard | gamepad | evidence |
|---|---|---|---|---|---|
| **Button** | indirect | indirect | ✓ (nav) | ✓ (dpad) | No dedicated Button spec. Keyboard/gamepad focus-nav via `graph.navigate` (`tests/focus.spec.luau:25-33`) and `deviceKey "DPad…"` (`tests/navigation_groups.spec.luau:237-250`); pointer only as popup option rows via `adapter.tap` (`tests/popup_button.spec.luau:101`). Activate *effect* of a standalone Button is not unit-tested — only mount/dispose/dump (`tests/controls_conformance.spec.luau:57-80`). |
| **Toggle** | ✗ | ✗ | ✗ | ✗ | Only contract/mount/dump conformance (`tests/controls_conformance.spec.luau:25-26,57-80`; authority `:86`). No input simulation at all; flip-on-Activate is exercised only in the un-unit-tested gallery. |
| **TextField** | via seam | ✗ | ✗ | ✗ | Bare-leaf render only (text/placeholder/maxLength through the renderer, `tests/text_input.spec.luau:105-127`). All interaction tested through the TextInput composite, not the leaf. |
| **TextInput** | ✓ | ✓ | ✓ | ✓ | **All four.** pointer `adapter.tap(FIELD)` (`:131`), + engine seam `focusText`/`typeText`/`commitText`/`blurText` (`:146-181`); touch `adapter.tap(FIELD,{pointer="touch"})` end-to-end incl. occlusion (`:529-547`); keyboard `deviceKey "Return"/"DPadDown"` incl. sink-blocks-nav (`:197-251`); gamepad `deviceKey "ButtonA"/"ButtonB"` enter/cancel/re-enter (`:254-286`). Strongest coverage of any control. |
| **PopupButton** | ✓ | ✗ | ✓ | ✓ | pointer `adapter.tap` open/select/cancel/re-tap (`tests/popup_button.spec.luau:99-158`); keyboard `deviceKey "Return"/"Down"` (`:161-184`); gamepad `deviceKey "ButtonA"/"Down"` (`:186-203`). **Touch has no dedicated test** (no `pointer="touch"` tap in the spec) and outside-dismiss is untested because it does not exist (§1). |
| **FocusGraph / NavGroups** | ✓ | — | ✓ | ✓ | pointer `focusOn` via tap exercised through composite specs; keyboard `deviceKey "Down"/"Left"/"Right"` grouped nav (`tests/navigation_groups.spec.luau:167-174`) + flat ring (`tests/focus.spec.luau:20-92`); gamepad `deviceKey "DPad…"` + initial-ring paint (`tests/navigation_groups.spec.luau:237-268`). Touch = same tap-focus seam as pointer (not separately simulated). |
| **Presenter modal** | ✓ (dismiss) | ✗ | trap ✓ / cancel ✗ | ✓ | gamepad `deviceKey "ButtonB"` dismiss+restore+dispose (`tests/presenter.spec.luau:74-90`); keyboard `deviceKey "Return"` activate routing (`:93-105`) and `deviceKey "Down"` trap (`:59-72`) — but **no keyboard Cancel test** (none exists, §1 MISSING); pointer dismiss via consumer `onActivate`+`dismiss` (`:106-121`, `examples/…/04_confirm_dialog.luau:47-57`); no touch-specific modal test. |

Coverage headline: **TextInput** is the only audit-scope control with genuine
four-class simulation. **Toggle** has zero input simulation. **PopupButton** and
**Button** lack a real touch test. The one MISSING cell (modal keyboard Cancel)
is, correctly, untested because there is no path.

---

## Appendix — key evidence index

- Action system (contexts/actions/bindings, arbitration, modifiers, deviceKey,
  `uiButton`/`preferredBinding`): `src/input/actions.luau:74-119,125-227`.
- Roblox action adapter (1:1 IAS, `uiButton`→UIButton, PreferredBinding):
  `src/client/roblox_input.luau:112-197`.
- Env facts (`preferredInput`, `capabilities`, `keyboardOcclusionRect`):
  `src/client/roblox_env.luau:31-75`; defaults `src/env/environment.luau:23-24`.
- Presenter nav-context + bindings + tap seam + modal machinery:
  `src/present/presenter.luau:103-202,247-316,350-404`.
- Focus graph (flat ring, grouped 2D, trap/restore, focusOn):
  `src/focus/focus_graph.luau:142-297,414-421`.
- Control contracts (declared `actions`, unused by runtime):
  `src/controls/contract.luau:12-61`.
- Renderer input wiring (activate handler, text seam, focus visual):
  `src/render/renderer.luau:208-213,260-275,446-461`.
- Screen target (tap meta, focus ring, text seam, pointer capture):
  `src/client/screen_target.luau:553-580,736-824`.
