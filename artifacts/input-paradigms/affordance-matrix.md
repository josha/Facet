# Per-control affordance matrix — LuauUI input-paradigms expansion

Status: **reviewed design authority** (UI Designer, 2026-07-21). This is the
build contract for the input-paradigms expansion: every GAP below is meant to
be turned into a failing test. Sources: SwiftUI affordance research
(`docs/research/2026-07-21-swiftui-affordance-research.md`, cited as **R§n**),
ADR-0015 (interaction classes), ADR-0013 (input auto-wiring seam), ADR-0014
(first-responder), `docs/guide/07-input.md`, `ui_todo.md §0`, and the control
inventory in `tests/conformance/controls_registry.luau`.

Control names are the **exact registry/export names**:
`Table`/`newTable`, `VirtualList`/`newVirtualList`, `PopupButton`/`newPopupButton`,
`TextInput`/`newTextInput` (over the `TextField` leaf), and the leaves `Button`,
`Toggle`, `TextField`. Anything not verifiable in code is marked **UNVERIFIED**.

Status legend: **SHIPPED** (cite file/behavior) · **GAP** (missing affordance,
precise) · **N/A-JUSTIFIED** (the class genuinely has no such affordance) ·
**PARTIAL** (present but degraded vs. the required affordance).

---

## A. The interaction-class affordance contract

The framework's live-class model (ADR-0015, `src/env/environment.luau`
`interactionClasses`): affordances derive from the **live set**
`{ pointer, touch, gamepad, keyboard }` plus a single `primary`, never from
`preferredInput` alone. A class is live when its capability fact is true; the
`primary` class (the `preferredInput` name) is forced live so it is always in
the set. **Structural affordances read the set; `primary` is emphasis only**
(hints, which idiom leads) — ADR-0015 Decision 2.

**The three axes** every control spec must satisfy independently (each is a
requirement family in §E):

1. **UI (layout)** — how the tree arranges per size class (`compact`/`regular`/
   `wide`) and per `distanceProfile`. Owned by `UI-ADAPT-001`.
2. **Input (bindings / reachability)** — which named action (Activate / Cancel /
   Navigate / Adjust) reaches the control on each class, and that every verb is
   reachable on every live class with no focus trap. Owned by `UI-INPUT-001/002`.
3. **Paradigm (structural affordances)** — the *shape* of the interaction each
   class expects (direct drag vs. edit-mode grip vs. grab mode; hover vs. focus
   lift; naked pan vs. wheel). Owned by the proposed `UI-PARADIGM-001..003`.
   A control can pass axes 1–2 (it lays out; A/Return/tap all fire) and still
   fail axis 3 (a mouse-only reorder, no hover layer, a thin ring at 3 m).

### Per-class structural rules

**pointer** (mouse/trackpad; `caps.mouse`) — *direct manipulation.* A row/handle
is **directly draggable with no grip and no long-press**, because scroll is a
**separate channel** (wheel / two-finger) distinct from a one-finger press-drag
(R§8). Required layers: a **hover** state (highlight or lift) as a free preview
channel (R§7), plus **pressed**. Idioms: **wheel scroll**, **direct drag**,
**right-click/secondary** for contextual actions (R§3), **modifier-click**
selection (⌘ toggle, ⇧ range — R§1). Nothing essential may live only behind
hover (it does not exist off pointer).

**touch** (`caps.touch`) — *fingers, no hover, 44 px floor.* Every actionable
element has a **≥44 px effective hit target** (R§7; `contract.luau` `minHitSize`).
**Scroll owns the naked pan** (R§8): a bare one-finger drag scrolls, so any
pan-to-reorder / pan-to-drag needs a **grip handle, a long-press lift, or a
distance threshold** — never a naked pan. Reorder/edit surfaces appear via an
**edit-mode ≡ handle** toggle. The on-screen keyboard summons on text focus and
must be kept from occluding the field.

**keyboard** (`caps.keyboard`) — *focus ring + discrete verbs.* Every
interactive element is reachable by a **visible focus ring** and driven by
**Navigate** (arrows) → **Activate** (Return). **Adjust** = arrow (or comma/
period) increment/decrement on a focused value (R§4). Tab-equivalent traversal
is the focus ring order. `Escape` is **engine-reserved** — never a Cancel key
(guide §7.4; ADR-0013 justified exception).

**gamepad** (`caps.gamepad`) — *focus + select, geometry-derived nav.* Focus
ring driven by **D-pad/thumbstick Navigate**; **Activate → ButtonA** (PS Cross
maps to ButtonA — one binding), **Cancel → ButtonB** (PS Circle). Directional
moves derive from on-screen **geometry**, not tree order (R§9). Reorder is a
**grab mode** (A grabs the focused row, D-pad steps, A drops). **Adjust** =
focus-then-directional (D-pad L/R or L1/R1) with a visible ± affordance (R§4,
the tvOS "Adjust idiom"). Focus visibility must be **strong** (scale + glow),
not a hairline, for 3 m viewing when `distanceProfile == "ten-foot"` (R§9/§11).

---

## B. The master matrix

One block per interactive control; within each, one **row per interaction
class** (`required affordances` + `status`). This is the "control × 4 classes"
grid, laid out block-wise so each cell can carry a testable statement.

### Table (`newTable`) — `src/controls/table.luau`

| Class | Required affordance | Status |
|---|---|---|
| pointer | Header tap cycles owner-held `sortOrder`; **direct row drag reorders** with no grip (scroll is a separate channel, R§8); **hover** highlight on rows/headers; **wheel** scrolls a long table; **⌘-click toggle / ⇧-click range** multi-select | **PARTIAL** — sort SHIPPED (`table.spec` "header taps cycle the owner-held sortOrder"); direct-drag reorder SHIPPED ("dragging a selected row drags the WHOLE selection as a block"); **hover state GAP** (no MouseEnter/hover wiring in `src/`; tokens define `control`/`controlSelected`/`pressed` but **no hover role** — `default_style.luau`); **wheel scroll GAP** (Table renders all rows, no built-in scroll viewport; caller must wrap in ScrollView/VirtualList — UNVERIFIED that a bare Table scrolls); **modifier-click multi-select GAP** (header: "modifier-key semantics are Phase B") |
| touch | **Naked pan scrolls**; reorder only via **edit-mode ≡ grip** handle; **auto Edit/Done toggle shows when `touch or gamepad` live** (ADR-0015); column resize via a **touch grip drag** clamped to `minWidth` | **SHIPPED** — `table_input.spec` "a TOUCH drag on the grip previews and commits the new column width" / "clamps to the column minWidth"; auto toggle proven in `table.spec` (ADR-0015: "touch capability live under KeyboardAndMouse shows it") |
| keyboard | Down + Return selects the focused row; Right/Return on a focused header sorts; **edit-mode grab reorder** (Return grabs, Down steps, Return drops); **Adjust resizes the focused column grip** | **PARTIAL** — select/sort/grab-reorder SHIPPED (`table.spec` "keyboard Down + Return select"; "keyboard Right/Return drive the header sort"; "keyboard edit-mode grab is input-agnostic"); **column-resize Adjust GAP** — the resize `Grip` is `focusable=true` (`table.luau:706`) but the presenter binds Adjust keys **only when the screen passes `opts.onAdjust`** (`presenter.luau:807`; ADR-0013 "grip resize stays `opts.onAdjust`-driven"), so a **bare** Table cannot be resized by keyboard |
| gamepad | ButtonA selects the focused row; ButtonA on a focused header cycles sort; **grab mode reorder** (ButtonA grabs, DPadDown steps, ButtonA drops); Adjust (DPad L/R or L1/R1) resizes the focused grip; **D-pad arriving as Thumbstick1 tolerated** | **PARTIAL** — select/sort/grab SHIPPED (`table.spec` "gamepad ButtonA selects the focused row"; "gamepad edit-mode: ButtonA grabs, DPadDown steps"; "ButtonA on a focused header cycles"); **column-resize Adjust GAP** (same `opts.onAdjust` gate as keyboard); **Thumbstick1 GAP** — presenter binds `DPadUp/Down/Left/Right` only (`presenter.luau:788-801`), **no `Thumbstick1`** binding anywhere in `src/`, so a pad that reports the D-pad as Thumbstick1 gets no Navigate |
| all-class GAPs | **Row secondary actions** (delete / contextual) — R§1/§3 require swipe (touch) ∥ context-menu/right-click (pointer) ∥ dedicated button (gamepad). Table has **no secondary-action surface on any class** — UNIMPLEMENTED. **Multi-select range/modifier** — R§1 macOS ⌘/⇧ semantics are Phase B (header), unshipped on pointer and keyboard | **GAP** |

### VirtualList (`newVirtualList`) — `src/controls/virtual_list.luau`

| Class | Required affordance | Status |
|---|---|---|
| pointer | Mouse wheel scrolls the window (drives `scrollTop`); a row tap activates through auto `handleActivate` | **SHIPPED** — `virtualization.spec` "VirtualList pointer: mouse wheel scrolls the window (drives scrollTop)" / "a row tap activates through auto handleActivate". **Minor GAP:** no draggable scrollbar thumb (wheel-only) — R does not require it; UNVERIFIED as a deficiency |
| touch | One-finger pan on a row scrolls and **never activates**; a distinct tap activates | **SHIPPED** — "VirtualList touch: a one-finger pan on a row scrolls and never activates" / "a row tap activates" (naked-pan-owns-scroll, R§8) |
| keyboard | Up/Down moves focus row-by-row through the window; off-band focus **scrolls into view**; Return activates | **SHIPPED** — "VirtualList keyboard: Up/Down moves focus row-by-row through the window" / "Return activates the focused row" (`focusMoved → focusKey`) |
| gamepad | D-pad identical to arrows; ButtonA activates | **SHIPPED** — "VirtualList gamepad: D-pad moves focus identically to arrows" / "ButtonA activates the focused row". Inherits the **Thumbstick1 GAP** (presenter-level, above) |
| all-class N/A | **Reorder / selection / secondary actions** — VirtualList "advertises no input capabilities" beyond scroll+activate (ADR-0013; header: "NO reorder/grab semantics") | **N/A-JUSTIFIED** for reorder within VirtualList itself. **But a structural GAP exists at the inventory level:** there is **no virtualized *reorderable* or *selectable* list** — Table reorders/selects but is not virtualized; VirtualList virtualizes but does neither. A long, reorderable list is unbuildable on any class today |

### PopupButton (`newPopupButton`) — `src/controls/popup_button.luau`

| Class | Required affordance | Status |
|---|---|---|
| pointer | Tap trigger opens a panel of every option; tap an option selects, fires `onChange`, closes, relabels; **tap-away (outside tap) dismisses** without changing selection (R§3 menu) | **PARTIAL** — open/select SHIPPED (`popup_button.spec` "tapping the trigger opens the popup listing every option" / "activating an option selects it, fires onChange, closes, and relabels"); **outside-tap-dismiss GAP** — the popup is a `UI.When` on an `open` signal, **not** a modal, so only re-tapping the trigger or the explicit **Cancel row** closes it (control header). A tap on empty space does not dismiss (no scrim; the modal two-zone machinery is not engaged) |
| touch | Touch-typed tap on the trigger opens the panel | **SHIPPED** — "a TOUCH-typed tap on the trigger opens the popup listing every option". Inherits the **outside-tap-dismiss GAP** |
| keyboard | Open, Navigate the option rows, Activate selects; closed, only the trigger is focusable | **SHIPPED** — "keyboard opens, navigates the options, and Activate selects" (open rows are ordinary focusable Buttons the ring picks up) |
| gamepad | ButtonA drives the same open + Navigate + select path; Cancel (ButtonB) closes without selecting | **SHIPPED (open/select)** — "gamepad ButtonA drives the same open+select path". **GAP:** ButtonB-closes-popup is UNVERIFIED (Cancel binds to the presenter's modal/resign path, not this non-modal `open` signal — the Cancel **row** is the only cited close) |
| all-class GAP | **Presentation does not resolve per platform/context** (R§2 Picker `.automatic`): PopupButton is **always a floating panel**. No segmented style for few options on pointer, no inline-in-form style, no **push-to-focus-subscreen** on `ten-foot`. One shape everywhere | **GAP** (moderate — cosmetic/idiom, not a reachability failure) |

### TextInput (`newTextInput`) / TextField leaf — `src/controls/text_input.luau`

| Class | Required affordance | Status |
|---|---|---|
| pointer | Tap the field enters editing (control-owned handshake); click-to-place-caret | **SHIPPED (enter-edit)** — `text_input.spec` "tapping the field enters editing (the control-owned handshake)". Caret placement is engine-`TextBox`-owned (UNVERIFIED headlessly) |
| touch | Tap enters editing; **on-screen keyboard summons** and **keep-visible** engages so it never occludes; **`keyboardType` hint restricts the on-screen layout** (R§5) | **PARTIAL** — enter-edit + keep-visible SHIPPED ("a touch tap enters editing and the occlusion keep-visible engages (touch story end to end)"); **`keyboardType` hint GAP** — it is "declared-intent only (no public engine keyboard-type API); validate enforces" (`ui_todo §1`), so a numeric field still summons full QWERTY on touch. Same for **`submitLabel`** (Return relabel) — declared, not wired |
| keyboard | Return enters editing; a **sinking text-entry context** so arrows/typing stop being Navigate; Enter commits and navigation resumes | **SHIPPED** — "focused field + Activate (Return) enters editing"; "Enter commits, editing ends, and navigation works again (probe fires post-edit)" |
| gamepad | ButtonA enters editing; D-pad does **not** navigate while editing; ButtonB cancels reverting to snapshot; on a console with no hardware keyboard a **full-screen virtual keyboard** appears (R§5) | **PARTIAL** — enter/no-nav/cancel SHIPPED ("ButtonA enters editing; D-pad does not navigate; ButtonB cancels reverting to the snapshot" / "ButtonA re-enters editing after a cancel"); **virtual-keyboard on gamepad-only UNVERIFIED** — LuauUI ships no virtual keyboard of its own and relies on the engine `TextBox` to summon the platform keyboard on console; headlessly unprovable (standing `physical-device-confirmation` rider) |

### Button (leaf) — `contract.luau` (`focusRole="focusable"`, `minHitSize=44`)

| Class | Required affordance | Status |
|---|---|---|
| pointer | Tap/click activates; **hover** highlight/lift; pressed dip | **PARTIAL** — activate SHIPPED (`auto_input.spec` "pointer tap activates the Button through its onActivate prop"); pressed SHIPPED (`default_style.luau` `pressedScale = 0.985`); **hover GAP** (no hover wiring / no hover token — R§7 "three feedback layers" incomplete) |
| touch | Finger tap activates; ≥44 px effective target | **SHIPPED** — "Button touch: a finger tap activates through the auto dispatch"; `minHitSize = 44` (`contract.luau`) |
| keyboard | Return activates the focused Button; visible focus ring | **SHIPPED** — "keyboard Return activates the focused Button"; focus ring (`screen_target.luau` `FocusRing`, 2 px) |
| gamepad | ButtonA activates; **strong focus visibility (scale + glow)** at `ten-foot` | **PARTIAL** — activate SHIPPED ("gamepad ButtonA activates the focused Button"); **focus-visibility GAP** — focus is a **2 px ring only** (`focusRingThickness = 2`); no scale/glow/lift, and it does **not** strengthen when `distanceProfile == "ten-foot"` (R§9/§11 demand an unmistakable-across-the-room state). Inherits the **Thumbstick1** Navigate GAP |

### Toggle (leaf) — `contract.luau` ("Activate flips value")

| Class | Required affordance | Status |
|---|---|---|
| pointer | Tap flips the owner-held value; hover; pressed | **PARTIAL** — flip SHIPPED (`auto_input.spec` "pointer tap flips the value"); **hover GAP** (as Button) |
| touch | Finger tap flips; ≥44 px target | **SHIPPED** — "Toggle touch: a finger tap flips the value"; `minHitSize = 44` |
| keyboard | Return on the focused Toggle flips; focus ring | **SHIPPED** — "focused Activate (Return) flips the value" |
| gamepad | ButtonA flips; strong focus visibility at `ten-foot` | **PARTIAL** — flip SHIPPED ("Toggle gamepad: ButtonA on the focused Toggle flips the value"); **focus-visibility GAP** (as Button) |
| all-class GAP | **Switch vs checkbox resolution** (R§6): a boolean should render a **switch** on touch/`ten-foot` and may render a **checkbox** in dense pointer/desktop forms. LuauUI renders one visual everywhere (no `ToggleStyle .automatic` analog) | **GAP** (minor — idiom, not reachability) |

### TextField (leaf) — the text-entry leaf `TextInput` drives

Proofs are the TextInput composite's (registry note). Same status profile as
**TextInput** above: SHIPPED enter-edit / sinking-context / cancel on all four
classes; **`keyboardType`/`submitLabel` hint GAP** (touch); **gamepad virtual
keyboard UNVERIFIED**. TextField is never mounted bare in the examples; treat
its contract as TextInput's.

### Example-level rows (01–07) — affordance gaps per gallery example

| Example | Verbs & reachability | Gap |
|---|---|---|
| **01 temperature converter** | The `TextInput` numeric field is the **sole** input affordance (steppers were removed, `ui_todo §1`). | **GAP (design)** — R§5 says *minimize* text entry and prefer selection/adjust on `ten-foot`/gamepad; example 01 makes heavyweight text entry the **only** path, with **no ± Adjust alternative** and an unhonored numeric `keyboardType` hint (touch gets QWERTY). Reachable on all classes but **hostile** on gamepad/TV |
| **02 playlist table** | Reorder = direct-drag (pointer) ∥ edit-grip (touch) ∥ grab-mode (gamepad/keyboard); filter `TextInput` all classes; per-row star rating = 5 focusable `Button`s reachable by the row's horizontal focus group (`buildFocusGroups` recurses cell content, `table.luau:1167-1176`). Star **scrub** (`Grip StarScrub`, `focusable=false`) is a pointer/touch drag. | **No per-class reachability gap** (discrete star Buttons cover gamepad/keyboard where scrub does not — verb reaches every class). **Minor GAP:** columns not keyboard/gamepad-resizable (example passes no `onAdjust`; see Table). This is the director's original repro screen — the missing-Edit-button defect is closed by ADR-0015 |
| **03 settings sync** | `Toggle` (Music) + `Button` ± (`VolMinus`/`VolPlus`) volume, both Activate-driven on all four classes; optimistic apply/reject reconcile. | **GAP (inventory):** volume uses discrete ± Buttons because **no `ValueAdjuster`/Slider/Stepper control exists** — pointer/touch get no continuous drag track, gamepad/TV get no focus-then-Adjust idiom (R§4). Works on all classes; wrong idiom on all classes |
| **04 confirm dialog** | Modal: Confirm/Cancel focusable; Cancel via ButtonB (gamepad) ∥ outside-tap+scrim (pointer/touch, ADR-0014 two-zone) ∥ focusable Close (keyboard/Return). | **No gap** — the canonical every-class-reaches-every-verb screen. Keyboard `Escape` is **N/A-JUSTIFIED** (engine-reserved; guide §7.4) |
| **05 word game** | Letter entry three ways: hardware key (keyboard) ∥ on-screen key tap (touch **and** pointer, same node `onActivate`) ∥ gamepad Navigate+A on the on-screen keyboard's nav-group rows. | **No per-class gap** — every class reaches "type a letter". UNVERIFIED: on-screen Backspace/Enter keys present for touch/gamepad parity with the hardware Return/Backspace (not audited here) |
| **06 tile game** | Select-then-place: tap/click/ButtonA on a focused rack tile or board cell (one Activate path); grid nav-groups for gamepad/keyboard. | **No gap** — deliberately not drag-and-drop; select-then-place is class-uniform |
| **07 match-3** | Tile = image + transparent `Button`; tap/click/ButtonA select; `Grid` → real 2-D nav groups for gamepad/keyboard; layout adapts by `sizeClass`. | **No gap** on reachability. Inherits the pointer **hover** GAP (tiles have no hover preview) and the gamepad **focus-visibility** GAP at `ten-foot` |

---

## C. Hybrid + hot-switch rules

### The live-set rule

Affordances are chosen from the **live class set**, and **all live classes get
their idioms simultaneously** — pointer hover effects, touch pan, gamepad focus,
and keyboard ring coexist, never mutually exclusive (R§10; ADR-0015 Decision 2).
`primary` selects **emphasis only**: which hint text shows ("Press A" vs "Press
Enter", via `LuauUI.inputHint`), which idiom leads visually. A handheld with
`touch` + `gamepad` both live shows the Table's Edit/Done toggle **and** answers
D-pad grab mode **and** answers grip drags — because `touch or gamepad` is true
(ADR-0015 Decision 2). A desktop with a pad connected is both a pointer machine
(direct drag, hover) and a gamepad machine (focus ring, grab mode) at once.

### In-flight transition table

For each in-flight interaction state × a class-flip event (a device arriving or
the `primary` flipping mid-gesture), the defined semantic is **CARRY** (state
survives; the newly-live class's idioms become additionally available) or
**CANCEL** (state cleanly reverts to its pre-gesture snapshot; **no data loss,
never a wedge**). The invariant: a class flip **never** strands an interaction
in a state the now-live class cannot exit.

| In-flight state | Class-flip event | Semantic | Rationale |
|---|---|---|---|
| pointer drag / capture (row reorder, grip resize) | touch or gamepad becomes live | **CARRY** | The active pointer capture completes on pointer release; the new class simply *also* gains its idiom (grab mode / grip) for the next gesture. The in-flight drag is pointer-owned until its own release. |
| pointer drag / capture | pointer goes **away** mid-drag (mouse disconnect) | **CANCEL** | No release event can arrive; the drag reverts to origin (the existing invalid-drop/external-cancel reset, `table.luau:380`) — never a stuck ghost row. |
| touch pan (scroll) | pointer/keyboard/gamepad arrives | **CARRY** | Scroll offset is presentation state that survives; the pan finishes on finger-up. Wheel/arrows become additionally available for the next scroll. |
| touch edit-mode (Edit/Done active, grips shown) | gamepad arrives; touch stays live | **CARRY** | Edit-mode is semantic-ish presentation the surface owns; grips remain, and grab mode is *also* offered. Edit/Done stays shown while `touch or gamepad` (ADR-0015). |
| touch edit-mode | touch goes away, gamepad stays live | **CARRY** | Auto Edit/Done still shows (`gamepad` live keeps the condition true); reorder continues via grab mode. Grips simply stop being tappable. |
| touch edit-mode | **all** of touch+gamepad go away (pure pointer) | **CANCEL** (exit edit-mode) | Pointer reorders directly with no edit-mode (R§1/§8); the Edit/Done toggle unmounts. No pending reorder is lost — edit-mode holds no uncommitted data. |
| gamepad grab-mode (row grabbed, following D-pad) | pointer/touch arrives; gamepad stays live | **CARRY** | The grabbed row keeps following Navigate; a pointer press-drag or grip is available for the *next* reorder. |
| gamepad grab-mode | gamepad goes away mid-grab | **CANCEL** | No ButtonA-drop can arrive; the row drops back to origin (reuse invalid-drop reset). Data (the list order) reverts to pre-grab. |
| focus (ring on a control) | any class flip | **CARRY** | Focus is presentation state; it never replicates and never drops on a device change — the ring stays put and every live class can move/activate it. |
| text entry / on-screen keyboard (field editing, sinking context up) | pointer/gamepad arrives | **CARRY** | Editing continues; the sinking text-entry context is class-agnostic. A hardware keyboard arriving simply supersedes the on-screen one (R§5/§10). |
| text entry / on-screen keyboard | the editing class goes away (touch keyboard dismissed by dock, or field disposed) | **CANCEL → commit-or-revert** | Editing ends through the same commit-on-focus-loss / cancel-reverts path (`onFocusLost`); the model keeps the last accepted value. Never loses typed data silently — commit fires, or ButtonB/Escape reverts to snapshot. The `disposed` guard in `beginEditing` (ADR-0014 Drive-F2) prevents a late Activate racing a dispose. |
| modal / engaged-passive surface up | any class flip | **CARRY** | The responder band (3000+) and Sink are class-independent (ADR-0014); a device change never un-engages a modal. Dismissal stays uniform: outside-tap (pointer/touch) ∥ ButtonB (gamepad) ∥ Close button (keyboard). |

---

## D. Console 10-foot presentation profile

Keyed off **`displaySize == "Large"`** (`GuiService.ViewportDisplaySize`, pushed
by `roblox_env.luau:32-37`, subscribed on change for handheld→TV docking). The
derived key **`distanceProfile`** returns `"ten-foot"` when Large, else `"near"`
(`environment.luau:84-86`; garbage clamps to `"near"`). This profile is keyed on
the **display class, not the input class** — a Large screen earns the treatment
regardless of whether the pad or a keyboard is driving (R§11; env comment
lines 81-83).

**The facts are SHIPPED; every consumer of them is a GAP.** `displaySize`,
`overscanInsets`, and `distanceProfile` exist and are proven
(`renderer.spec.luau:161-179`), but nothing reads `distanceProfile` outside the
test (`grep`: zero `src/` consumers). Each requirement below is therefore a
failing-test target.

1. **Type-scale floor.** Body text must be **≥ ~29 pt-equivalent** at distance
   (R§11). Concretely: when `distanceProfile == "ten-foot"`, apply a **`ten-foot`
   multiplier ≈ 1.5×** *on top of* the existing `typographyScale` seam
   (`environment.luau:52-57`, currently clamped 0.5–3 from `preferredTextSize`
   **only**). **GAP** — `typographyScale` does not read `displaySize`/
   `distanceProfile`; there is no distance floor. Falsifiable: with a `body`=16
   ramp and `displaySize="Large"`, the effective body size is ~24 (16×1.5), not
   16. Also enforce a **min font weight** (medium/semibold) — thin strokes vanish
   at distance (R§11); **GAP** (no weight policy in tokens).
2. **Overscan-safe margins.** Inset all content by the **`overscanInsets` fact**
   (default zero; developer-authored, distinct from `coreSafeInsets`/`topbarInset`
   which are notch/CoreGui geometry — env comment lines 31-33). Recommended
   ten-foot default ≈ **60 pt top/bottom, 90 pt left/right equivalent**, i.e. the
   `{ top=27, bottom=27, left=48, right=48 }` shape the test sets scaled to the
   viewport (R§11; ~10% action-safe industry norm — no Roblox-published percentage,
   UNVERIFIED numerically). **GAP** — the renderer root policy applies
   `coreSafeInsets` only (`renderer.luau:332`); **no root policy folds in
   `overscanInsets`**. Falsifiable: a Screen under `displaySize="Large"` with
   `overscanInsets` set does not inset its content rect.
3. **Layout density.** Low density, few large focusables — "a single row of 5–7
   cards beats a dense grid of 20+" (R§11). Guidance: on `ten-foot`, size-class
   branches should prefer the **`compact`/`regular` (fewer columns, bigger
   targets)** arrangement even on a `wide` viewport. **GAP** — `sizeClass` derives
   from viewport **width only** (`environment.luau:66-70`); it does not consult
   `distanceProfile`, so a Large TV resolves `wide` (densest) — the opposite of
   the requirement.
4. **Focus visibility.** Required: an **unmistakable-at-3 m** focus state —
   **scale ~1.05–1.1× + glow/elevation**, not a hairline (R§9/§11). **GAP** —
   focus is a **2 px ring** (`default_style.luau` `focusRingThickness = 2`;
   `screen_target.luau` `FocusRing`), with **no scale/glow** and **no
   `distanceProfile` strengthening**. Falsifiable: focus visuals are byte-identical
   at `displaySize="Large"` and `"Medium"`.
5. **Input-axis tolerance (D-pad as Thumbstick1).** On some console stacks the
   D-pad arrives as **`Thumbstick1`** rather than `DPad*`. Navigate must bind
   **Thumbstick1** as well as `DPadUp/Down/Left/Right`. **GAP** — `presenter.luau`
   binds `DPad*` only (`:788-801`); `grep`: **no `Thumbstick1` in `src/`**. A pad
   reporting the D-pad as an analog axis cannot Navigate. This is an **input-axis
   requirement**, not a presentation one, but ships with the console profile.

**TV-remote (D-pad-only) is OUT of scope** — deferred to its own remote-input-only
`/goal` (a D-pad-only *constrained gamepad* reusing this console 10-foot profile,
never a 5th device class; `PreferredInput` keeps only three values).

---

## E. Requirement IDs

Existing families: **`UI-ADAPT-001`** (layout adaptation), **`UI-INPUT-001/002`**
(input reachability). The paradigm axis (structural affordances) is proposed as
`UI-PARADIGM-001..003`. Each statement is falsifiable — a build agent asserts it
against `src/` and the conformance registry.

- **`UI-PARADIGM-001` — structural affordances per live class.** *For every
  interactive control and every class in `interactionClasses`'s live set, the
  control exposes that class's structural idiom (pointer: direct drag + hover +
  wheel; touch: 44 px target + naked-pan-scroll + edit-mode grip; keyboard: focus
  ring + Navigate/Activate + Adjust; gamepad: focus + grab mode + A/B), driven
  only by the live set (never `preferredInput` alone), with zero consumer wiring.*
  Falsified by: any interactive control missing hover on pointer (currently
  Button/Toggle/Table), any reorder reachable only by mouse, any value not
  Adjustable on keyboard/gamepad.
- **`UI-PARADIGM-002` — hot-switch transition semantics.** *Every in-flight
  interaction state has a defined CARRY or CANCEL outcome for each class-flip
  event (§C table); a class flip never wedges an interaction and never loses
  uncommitted data — a cancelled gesture reverts to its pre-gesture snapshot and
  a cancelled edit commits-or-reverts through `onFocusLost`.* Falsified by: a
  device removal that strands a drag/grab/edit with no exit, or drops typed text.
- **`UI-PARADIGM-003` — 10-foot presentation.** *When `distanceProfile ==
  "ten-foot"` (`displaySize == "Large"`), the presentation applies a type-scale
  floor (≈1.5× over `typographyScale`, min semibold), `overscanInsets` margins,
  reduced layout density, and a strengthened focus state (scale + glow); and
  Navigate binds `Thumbstick1` alongside `DPad*`.* Falsified by: type/margins/
  density/focus identical between `Large` and `Medium` (all currently identical),
  or a Thumbstick1-only pad that cannot Navigate.

---

*Prepared by the UI Designer, input-paradigms expansion, 2026-07-21. Every GAP
and PARTIAL above is a build-contract line item for the UI Engineer; the
UNVERIFIED items remain on the standing `physical-device-confirmation` rider.*

---

## Amendments — build round (lead, 2026-07-21)

The matrix above is the reviewed pre-build authority; this section records
what the build round corrected or closed, with the proving specs. Cells above
are left as authored for the audit trail — read them WITH these amendments.

### Cells the build found stale or wrong
- **Table pointer "wheel scroll GAP … UNVERIFIED"** — WRONG at authoring time:
  a bare Table has its own ScrollView body with clamped wheel scroll and real
  clipping (`table.luau` Body `onScrollWheel`/`clampScroll`; `table.spec`
  "the mouse wheel scrolls with clamping at both ends"). Status: **SHIPPED**.
- **Hover "no hover role / no MouseEnter wiring"** — overstated: a
  `controlHover` token and an (ungated) MouseEnter fill pre-existed. The real
  gap — ungated allocation, no contract seam, no headless coverage — is now
  closed: hover is a first-class OPTIONAL adapter seam (`enableHover`), gated
  on the live pointer class, proven in `tests/paradigm_hover.spec.luau`.
- **TextInput `keyboardType` "no public engine keyboard-type API"** —
  imprecise: `TextBox.TextInputType` EXISTS (Number/Email/Phone) but is
  RobloxScript-security-locked. Now **wired behind `canSetTextInputType`
  capability detection** (clean degrade on shipping engines,
  forward-compatible). `submitLabel` stays declared-data-only — the engine
  member (`ReturnKeyType`) is hidden/non-public: a **justified engine-absent
  exception**, precisely cited.

### GAP cells closed by the build (status now SHIPPED)
- **Table keyboard/gamepad column-resize Adjust** — bare-Table resize via
  Comma/Period + L1/R1 through the new contribution `adjustTargets` /
  `handleAdjust` seam; Adjust keys bind only while a grip holds focus (no
  gameplay shadow). Includes a reachability fix (grips joined the headers nav
  group). `tests/paradigm_table.spec.luau`, `tests/paradigm_input_axis.spec.luau`.
- **PopupButton outside-tap dismiss / ButtonB Cancel / focus trap+restore** —
  three new contribution seams (`handleCancel`, `outsideDismiss`,
  `transientScope`) + PopupButton adoption; all dismissal paths converge on
  the same non-destructive outcome and restore focus to the trigger.
  `tests/paradigm_popup.spec.luau`.
- **Thumbstick1 Navigate (D.5)** — axis bindings with a deadzone latch;
  Navigate/NavigateH accept Thumbstick1. `tests/paradigm_input_axis.spec.luau`.
  Real-IAS analog realization stays on the physical rider.
- **Ten-foot consumers (D.1–D.4)** — type-scale floor (1.5× composed over the
  accessibility preference, at measure AND paint seams), density cap
  (`wide`→`regular` under Large), focus strengthening (thicker ring + 1.05
  scale at ten-foot, byte-identical near), overscan margins in the renderer
  root policy. `tests/paradigm_tenfoot.spec.luau`, `tests/preview.spec.luau`.
  Known limitation: intrinsic default text sizes (e.g. Toggle's 16) do not
  scale — only explicit `textSize` props do (measure/paint agreement rule).

### §C table refinements proven by the build (test-backed deltas)
- **Grab-mode cancel condition**: CANCEL fires when neither gamepad NOR
  keyboard survives (grab is input-agnostic; a surviving keyboard can still
  exit) — strictly safer than the literal "gamepad goes away" row.
- **Text-entry touch-loss**: CARRIES while a hardware keyboard stays live
  (the matrix's own supersede rule); CANCEL→commit only when no keyboard
  remains (dock). Both wedges found en route (lingering edit-mode grips;
  stranded sink context on dock) are fixed with regression tests.
- **Grab-revert limit**: a non-adjacent multi-selection re-gathers as a
  contiguous block on grab (pre-existing contract), so revert restores the
  block to its origin slot, not the original scattered positions.

### Live-drive discovery (Studio, 2026-07-21, post-wave)
- **Reorderable + selection-"none" wedge (FIXED).** The in-engine drive
  surfaced a gap every headless world missed: with `selection = "none"` the
  row hits were not focusable, so a reorderable table's only focusable was
  the auto Edit/Done toggle — Navigate was a dead end (gamepad user stranded)
  and grab-mode had no row to grab. Fixed: rows are focusable when
  `selection ~= "none"` OR `reorderable == true`; regression cases in
  `tests/paradigm_table.spec.luau` ("reorderable + selection-none keeps rows
  reachable"), including the end-to-end selection-none grab reorder and the
  unchanged non-reorderable case.

### Verifier round (three concurrent Opus verifiers, 2026-07-21)
Reports: architecture FINDINGS (5), reactive-runtime PASS (+2 coverage gaps),
roblox-platform FINDINGS (2). Disposition — every requirement-affecting
finding fixed red-first the same session:
- **arch-F1** Toggle ignored an explicit `textSize` at the measure seam
  (measure/paint divergence) — fixed (renderer + a Toggle.textSize layout
  authority); test in `paradigm_tenfoot.spec`.
- **arch-F2** a displaySize dock did not re-strengthen a RESTING focus visual
  until focus next moved — fixed (distanceProfile observer re-drives the
  focused handle); test in `paradigm_tenfoot.spec`.
- **arch-F3** hover was create-time-gated; a mouse arriving mid-session left
  existing nodes hoverless — fixed (interactionClasses observer enables hover
  on mounted nodes); test in `paradigm_hover.spec`.
- **arch-F4** `MouseButton1Up` unconditionally applied the hover fill,
  leaking a hover tint on pure-touch — fixed in `screen_target.luau`
  (release restores resting unless hover is wired; engine-side, on the
  Studio/physical rider).
- **arch-F5** dual-UIScale (pressed dip × ten-foot focus lift) composition is
  engine-dependent — recorded on the physical rider.
- **platform-F1** the analog Thumbstick1 IAS realization bound a Direction1D
  composite slot, which is NOT the documented analog surface — reworked to a
  companion **Direction2D** action with `InputBinding.KeyCode = Thumbstick1`
  plus a client-side latch mirroring the headless authority (real-pad
  delivery stays on the physical rider).
- **platform-F2** `ReturnKeyType` tag corrected to Hidden/NotScriptable.
- **runtime RT-F1/RT-F2** coverage gaps closed: popup dismiss-WHILE-OPEN and
  class-flip-then-dispose are now registry-neutrality-asserted
  (`paradigm_popup.spec`, `paradigm_table.spec`) — both held (no leak).

### Director live find #2 (Xbox One emulator, 2026-07-21 post-gate) — FIXED
- **New engine truth:** the Studio **Xbox One device emulator reports
  `ViewportDisplaySize.Large`** — the ten-foot profile is live in emulation
  (previously assumed hardware-only; supersedes that caveat in the research
  doc for the emulator case).
- **Bug:** the ten-foot focus LIFT (1.05 UIScale) scaled the near-full-width
  playlist filter field past the screen edge (1888 × 1.05 = 1982 > 1920).
  **Fix:** the lift is a CARD idiom — it now applies only when the lifted
  bounds stay inside the solved root frame (the overscan-safe content rect);
  oversized surfaces keep the strong ring with no scale. Engine rule uses a
  path-segment root lookup (rendering is FLAT — an ancestor walk degenerates,
  caught live); `fake_target` mirrors the same rule headlessly.
  Tests: `paradigm_tenfoot.spec` "ten-foot focus lift is capped…".
- **Gap the same screenshot exposed:** nothing authored overscan margins live,
  so a TV-class display rendered edge-flush. **Fix:** derived
  `effectiveOverscanInsets` — authored values win; `"none"` opts out; an
  unauthored Large display defaults to the tvOS-equivalent 60/90. Renderer
  consumes the derived key. Tests: `paradigm_tenfoot.spec` "ten-foot default
  overscan margins…". Suite 591 → 595.
- Live re-driven on real engine instances (console profile, fresh module
  clone): wide focus = no lift, right edge exactly at the safe rect, 4px
  ring; small focus = 1.05 lift. Matches the headless mirror byte-for-byte.
