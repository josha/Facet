# LuauUI — director TODO / decision notes

## 0. STANDING PRINCIPLE (director, 2026-07-20): every control supports EVERY input

Auto-adaptation is not just layout. Each control/tool must ship with the
right interaction for ALL supported inputs — pointer (mouse), touch, keyboard,
AND gamepad — before it counts as done. A control that only works with a
mouse is an unfinished control. Concretely: every interactive surface needs a
focus/navigation story (D-pad/arrows), an Activate story (A/Cross/Return/tap),
and input-appropriate affordances (e.g. touch edit-mode handles, gamepad grab
mode), verified per input in tests. This applies to everything new and is the
review bar for existing controls. (Roblox maps PlayStation Cross to ButtonA —
one binding covers both consoles.)

Working notes from the director's example-review sessions (2026-07-20).
Standing riders and gate-tracked work live in the gate manifest and
`artifacts/`; this file is the informal product-direction list.

## 1. Text input control (TextInput: `LuauUI.newTextInput` over the `UI.TextField` primitive) — BUILT (2026-07-20)

Shipped: `LuauUI.newTextInput` — a composite over a new `UI.TextField` leaf
primitive (the engine-`TextBox` seam) plus an optional in-field clear ✕. The
owner holds the `value: Signal<string>`; the control never creates it. All four
design concerns below are resolved: the text-entry-mode handshake raises a
high-priority SINKING action context so keystrokes/arrows stop being navigation
while a field is focused (Activate is deliberately left un-sunk; ButtonB/Escape
cancels-reverts); keyboard-occlusion keep-visible reads the env's occlusion rect
and publishes a minimal upward presentation transform (no remount); the value
model is headless and Lune-tested (clamp→validate→accept, `onChange` live vs
`onCommit` on Enter/focus-loss); `keyboardType` is a declared-intent hint only
(no public engine keyboard-type API — validate enforces). The two tutorial
examples adopted it: **01** temperature converter now uses a numeric field as
the PRIMARY input (steppers + Convert button removed) and demonstrates live
(`onChange` preview) vs commit (`onCommit` Result) side by side; **02** playlist
table gained an iTunes-style filter-as-you-type field (`clearButton`, a derived
`filteredRows` memo, reorder disabled while filtering). A `textinput-typing-storm`
bench scene asserts typing never remounts. All cross-platform: pointer, touch,
keyboard, gamepad each proven per §0. Physical-device confirmation (touch
keyboard occlusion, gamepad edit-mode) remains the standing pending rider.

Original direction (kept for context) — why there was no text field:
real text entry means the engine `TextBox`,
and wrapping it properly is design work, not a composite:

- **Focus collision** — a focused TextBox captures the keyboard; keystrokes
  must stop being semantic actions (typing "w" must not navigate). Needs an
  explicit text-entry-mode handshake with the action system + focus graph,
  including gamepad behavior when focus lands on a field.
- **Platform surface** — phones summon the on-screen keyboard (the
  environment already tracks its occlusion rect; no control consumes it yet),
  plus engine-owned IME/autocorrect.
- **Headless testability** — needs the split: signal-backed value model
  (tests drive it) + a thin engine TextBox adapter layer (Studio-verified).

Proposed shape (first expansion gate, per the design's expansion rules):
engine `TextBox` behind the render adapter with capability detection;
contract `{ value: Signal<string>, onCommit }`; text-entry-mode handshake;
keyboard-occlusion awareness. Roughly a day of the standard TDD + Studio
loop. The temperature converter and playlist filter switch to it for free
(both already route through a signal). Until then, steppers are the
current-primitives input affordance (see `01_temperature_converter`).

## 2. Tutorial example lineup — director revision (2026-07-20)

Old examples 02 (star rating) and 03 (track browser) are COMBINED into one
iTunes-style playlist table example:

- rows = tracks; columns = name, length, rating;
- the rating column is a SETTABLE star control living inside a table cell
  (the example-01 style interactive control, embedded per row);
- playlist rows rearrange by drag & drop (the Table control's built-in row
  reorder: ghost chip + drop indicator, `onReorder(keys, toIndex)`).

The tutorial is now 7 examples (01 converter, 02 playlist table, 03 settings
sync, 04 confirm dialog, 05 word game, 06 tile game, 07 match-3). This
supersedes the original 8-example list in the design document §17 — the
design doc should be synced next time it is edited.

## 3. Touch scroll-vs-reorder — BUILT (v1, 2026-07-20; director-approved design)

Shipped: touch pan on row bodies scrolls (never reorders); mouse wheel
scrolls; Table `editing` signal (owner-held or internal via `api.editing`)
grows trailing ≡ handles that reorder on any pointer; auto Edit/Done toggle
when reorderable + no owner signal (+ env-gated to non-mouse input);
REAL engine clipping (2026-07-20 round 2): the body is a clip host — the
adapter parents row instances under it with relative coordinates and
ClipsDescendants crops partial rows at both edges (culling removed). The
edit handle is a visible LEADING ≡ glyph in a gutter (cells inset); mobile
multi-reorder = tap-select rows then drag any selected row's handle (group
drag). GAMEPAD (2026-07-20 round 3): D-pad row/cell navigation via
`api.buildFocusGroups` + presenter groups-FUNCTION (re-derived each refresh)
+ DPadUp/Down bindings; A/Cross activates; edit-mode grab: A grabs the
focused row (selected-block aware), D-pad steps it per press via
`api.handleGrabNavigate` + presenter `onNavigateIntercept`, A drops.
Remaining open: VirtualList touch-pan wiring.
[STATUS 2026-07-21: the §0 principle now holds automatically — ADR-0013
contribution seam + ADR-0014 first-responder model; VirtualList touch-pan
CLOSED with its full four-input story; consumer wiring above (buildFocusGroups
/ onNavigateIntercept hand-offs) is auto-composed by the presenter; gate:
`input-adaptation-audit`.]
ENGINE TRUTH (2026-07-20, live gamepad, probe-verified): the LEGACY control
scripts bind gamepad ButtonA to `jumpAction` (CAS prio 2000)
UNCONDITIONALLY — even with Players.CharacterAutoLoads=false and no
character — and silently consume it (gameProcessed=true, IAS never fires).
D-pad/thumbsticks pass through, which masks the problem. UI-only places must
`PlayerModule:GetControls():Disable()` (fallback: UnbindAction("jumpAction"));
real games run the IAS player-script stack (Properties-panel-only flag
`Workspace.PlayerScriptsUseInputActionSystem` [corrected from StarterPlayer, doc-verified 2026-07-21] — NOT script- or
rojo-reflectable, verified again this session) or accept the contention.
Also observed: GuiService.CoreGuiNavigationEnabled re-enables itself if
scripted off (CoreScripts fight back) — not the eater anyway.

Original design notes below.

Problem (seen in the playlist place, landscape): a touch drag on a row starts
drag-reorder, so there is no gesture left to scroll — and the flat renderer
does not yet scroll/clip in-engine at all (recorded device-emulator truth).

Apple's resolution (SwiftUI List / HIG): scroll owns the naked vertical pan
on touch; reordering is entered explicitly — edit mode with trailing ≡ drag
handles (`.onMove` + EditButton), or long-press lift (`draggable`). Mouse
pointers keep direct drag because the wheel handles scrolling.

Proposed for LuauUI (3 pieces):
1. touch pan -> scroll: row hits stop capturing touch drags outside edit
   mode; pan drives the scroll container (Table body / VirtualList
   scrollTop); engine clipping + wheel scroll at the adapter (the missing
   scroll plumbing is the substantial half);
2. Table gains owner-held `editing` signal: trailing ≡ Grip handles per row
   while editing; only handle-drags reorder on touch; demo gets Edit/Done;
3. pointer-aware: mouse keeps today's direct row-body drag; touch requires
   the handle (preferredInput/capabilities decide). Long-press lift = later
   alternative idiom; gamepad "grab mode" = same concept for a future
   console consumer (existing rider).

## 3b. Input-paradigms mission — deferred matrix gaps (lead scope ruling, 2026-07-21)

The affordance matrix (`artifacts/input-paradigms/affordance-matrix.md`) found
these NEW-FEATURE gaps: uniformly absent on ALL classes (so not per-class
parity failures), deferred out of the paradigms mission rather than silently
dropped:

- **ValueAdjuster / Slider / Stepper control** (matrix §B example-03 row, R§4):
  continuous values currently fall back to ± Buttons — no drag track on
  pointer/touch, no focus-then-Adjust idiom on gamepad/TV. First candidate for
  the next control expansion; the Adjust auto-wiring seam this mission ships is
  its input story.
- **Table row secondary actions** (matrix Table all-class row, R§1/§3): swipe
  (touch) ∥ context-menu (pointer) ∥ dedicated button (gamepad) — no surface on
  any class today.
- **Modifier-click multi-select** (⌘/⇧ — already the header's "Phase B" note).
- **Virtualized reorderable/selectable list** (matrix VirtualList row): Table
  reorders but doesn't virtualize; VirtualList virtualizes but doesn't reorder.
- **PopupButton per-platform presentation styles** (R§2 `.automatic`):
  segmented/inline/ten-foot-subscreen resolution; today always a floating panel
  (dismissal parity IS in-mission).
- **Example 01 ten-foot ergonomics** (matrix example row, R§5): sole-path
  heavyweight text entry is hostile on gamepad/TV; revisit alongside
  ValueAdjuster (a ± affordance next to the field).

## 4. Other deferred items already on the ledger (for reference)

- `newTable`/`newVirtualList` taking `LuauUI` as first arg — signature
  cleanup queued for the 0.5.0 window via the `DEPRECATIONS` ledger
  (architecture review F5).
- Physical phone + gamepad confirmation — the one pending release item
  (gate: `physical-device-confirmation`, non-blocking).
- Cursor art assets for pointer hints (`CURSOR_ART` empty); touch
  reorder-vs-scroll design + gamepad grab-mode before any scrolling/console
  reorder consumer (part-2 riders).

## 5. Deferred: a BLOCK table publishes a scroll path it has no host for (2026-08-13)

`Table.api.scrollPath()` returns `<root>/Main/Body` unconditionally, including
for a table built with `scrolls = false` — a table that is deliberately a BLOCK,
whose rows are scrolled by the page around it. That node paints nothing, so the
renderer elides it and the engine has no `ScrollingFrame` there at all. The
gallery bootstrap's auto-bind then hands that path to
`Table.bindNativeScroll`, which registers two `observeScroll` callbacks on it (the
`scrollTop` CanvasPosition mirror, and — for a table with `rowActions` — the
coordinator's scroll-closes-the-open-tray).

The immediate consequence was a live crash, and that half IS fixed:
`screen_target.observeScroll` indexed a nil instance and threw, so the shipped
playlist example logged "'Playlist table' failed to mount" on the real client and
abandoned its mount there. All four public scroll-seam entry points now guard a
nil instance the way their four `indicator*` neighbours already did, pinned by
`tests/native_scroll.spec.luau`.

What is NOT fixed, and is the real design question:

* a block table's `scrollTop` mirror is bound to a node that can never report a
  scroll, so it stays 0 while the PAGE scrolls under it — and the reorder drag
  math and keep-visible both read that mirror;
* `rowActions`' "any scroll closes the open tray" never fires on a block table
  for the same reason. On the playlist example you can open a tray, scroll the
  page, and the tray rides along still open;
* `tests/examples_gallery.spec.luau`'s "the bootstrap auto-bind reaches a
  returned Table's api.bindNativeScroll" asserts `dump().scrollTop == 120` after
  driving a scroll on that path — true headlessly (the fake target's handle IS
  the node) and unreachable on the engine. The case still guards the CTRL-05a
  regression it was written for; it just cannot speak for a block table.

The likely shape of the fix is that a `scrolls = false` table either reports no
scroll path at all, or is told which ancestor scroller owns it, so both the
mirror and the tray-close bind to the node that actually moves.
