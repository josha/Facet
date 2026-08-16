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

---

## 6. OWED, WITH A NUMBER: the resize divider's touch band was 27px, now 44px (2026-08-15)

**Status: THE FIX SHIPPED the same day — `src/render/hit_lift.luau`, the overhang
lift. The band below is history; the device row is still owed and its question
CHANGED, which is why the old numbers stay on the page.**

**Re-measured live after the fix** (showcase place, parallel real-engine mount of
`table_columns`, native stylesheets on, a per-pixel scan of who owns each column
of the divider's band):

| axis | before | after |
|---|---|---|
| x | `EXP 18px + Grip 8px` = **26px** of 44, outer 18px to `Head-team/Column` | `EXP 18 + Grip 8 + EXP 18` = **44px of 44** |
| y | `EXP 8 + Grip 28 + EXP 2` = **38px** of 44, bottom 6px to row 1's `Hit` | `EXP 8 + Grip 28 + EXP 8` = **44px of 44** |

...and the three gestures that failed below now pass, driven with injected input
against the same positive control (a clean header tap moving `team` `""` → `"▲"`):
an outer-half drag at x = 130 (10px past the divider, over the neighbour's painted
header) resized `Entrant` 108px → **158px**; the outer-half tap sorted **nothing**;
the inner-half tap still forwards to its own cell and sorts. The desktop figure the
row was written against is closed. **The device row below is what remains.**

`contract.luau` gives `Grip` `minHitSize = 44`, and the renderer materialises a
44px `LuauUIHitExpander` centred on the Table's 8-10px resize divider. Measured
live in the showcase (`table_columns`, glossy-touch), the z-order is:

| node | z | x band |
|---|---|---|
| `Head-name/Column` | 10 | `[39..318]` |
| `Head-name/Grip` expander | **12** | `[291..335]` |
| `Head-team/Column` | **14/15** | `[318..537]` |

The neighbouring column's header button comes later in the tree walk and
therefore paints higher, and Roblox delivers input to the topmost interactive
object only. So the advertised 44px band is **27px delivered** (`[291..318]`),
and the outer 17px belongs to the next column's header. Confirmed by four
gestures against an established positive control (an injected tap on the header
moving `name` from `""` to `"▲"`, so "no sort fired" is evidence rather than a
null that agrees with itself):

| gesture | engine x | result |
|---|---|---|
| tap, header body | 58 | sorts ✓ |
| drag, inner half | 225 → 305 | `auto` → **279px**, no sort ✓ |
| drag, outer half | 246 → 326 | **nothing at all** ✗ |
| tap, outer half | 326 | **sorts the NEIGHBOUR column** ✗ |

**What is owed, precisely.** 27px is a *derivation* of a desktop z-order
measurement, not a device measurement. Against the 44px finger floor this
framework itself declares, a 27px band should be measurably harder to hit, and a
miss does not merely fail — it **sorts the wrong column**, which is a destructive
outcome for a gesture the player did not make. The device pass should measure the
miss rate on a real phone, not ask whether it "feels" reachable.

**And it changed what the device pass is testing.** The band IS the full 44px
now, straddling the divider (measured above). The device question is therefore no
longer *"is this broken"* but *"is 44px actually enough with a real finger on a
divider between two tap targets that both do something"* — a genuinely open
question this framework has never measured, and worth an explicit answer either
way. **Touch reachability remains unmeasured: nothing here was driven by a
finger.** The device pass should also spend one gesture on the transfer the rule
makes deliberately — a tiled list gives each row's overhang to the row ABOVE now
rather than to the row below (same 8px, opposite direction), and only a finger can
say whether either is noticeable.

**IT IS NOT A TABLE BUG — measured 2026-08-15 across 48 shipped scenarios on a
real `screen_target` (`artifacts/hit-expander-overhang/corpus-measurement.md`).**
86 hit expanders, **82 overhang relations**, and the same defect is live and
unreported in two more fixtures: `virtual_list_native` (row `Hit` 20px tall,
±12px of its 44px floor belongs to the adjacent row) and `keyboard_navigation`
(`Row1..Row12`, ±4px). Nobody noticed because a miss there lands on a plausible
neighbour; in the Table a miss sorts a column the player never touched.

**The paint-reorder worry is dead: 0 of those 82 lift-relations have painted
rects that intersect.** The rule ships unqualified across all four `minHitSize`
classes, with one qualifier that IS required — outrank non-expander siblings
only, leaving expander-vs-expander to host z order (two 44px floors overlap each
other; measured on `hud` host `R1`, 5%).

**Instrument note for whoever picks this up.** The showcase was unusable as a
live instrument on 2026-08-15: `LuauUIShowcaseAPI.showNext` *returns* the
advanced demo id (`surface-overlap`, `sorted-entries`) while a subsequent
`current` read answers `hud` and `LuauUI_HudScreen` stays mounted — something
snaps the picker back to the HUD fixture. A demo sweep run against that state
silently scans `hud` 21 times instead of the corpus and reports a clean bill of
health for demos it never looked at. Confirm the picker actually advances before
trusting any sweep over it.

> **RESOLVED 2026-08-15 — and the picker was never the thing that snapped back.**
> Driven live in the showcase place, `showNext` advances correctly through all 32
> catalogue demos, each one proved by its own `ScreenGui` and not by the returned
> id. Two separate things were being read as one:
>
> 1. **`LuauUI_HudScreen` was a directly-mounted probe, not a picker mount.** It
>    was watched appearing in `PlayerGui` *between two picker advances that never
>    visited `hud`*, carrying `LuauUIHitExpander` children — i.e. this very
>    measurement's own scan, mounting scenarios off `LuauUIScenarios` as its own
>    advice recommends and leaving them parented. A sweep that identifies "the
>    demo on screen" by scanning `PlayerGui` reads the leftover, not the picker's
>    mount, and `GetChildren()` order puts the older leftover first. That is the
>    21 scans. **Destroy what you mount and verify it absent in the same call.**
> 2. **The API really did answer with an id it had not delivered.** `mountDemo`
>    runs under a `pcall`, so a mount that throws was a client-console `warn` no
>    scripted caller can see while `showNext`/`current` reported the demo as if it
>    were up — reproduced live by renaming one scenario module out from under the
>    host: `{"current":"measured-extents"}` over an empty screen. Fixed: both
>    answers now carry `mounted` (`false` when the last mount failed) and `ok`
>    beside `current`, and the same drive now answers
>    `{"mounted":false,"current":"row-actions","ok":false}`. The all-demos
>    acceptance drive is `tests/gallery_demo_picker.spec.luau`, "showcase host:
>    advancing the picker actually mounts the demo it names".
