# Roblox-native capability audit corrections

**Date:** 2026-07-22  
**Status:** Governing addendum. When this document conflicts with an older audit or
plan, this document wins.

This addendum corrects gaps found while reviewing the native-primitives,
native-stylesheet, SwiftUI-parity, and Sponsor View plans together. It exists so an
implementation agent does not build a custom Roblox substitute based on an outdated
platform assumption.

The product rule is simple:

> Keep LuauUI's decisions deterministic and headlessly testable. At the Roblox
> adapter edge, use the engine primitive that already owns the behavior. Build a
> framework abstraction only for composition, policy, fallback, or behavior Roblox
> does not provide.

## Corrections that change the implementation plan

### 1. Drag acquisition and motion start with `UIDragDetector`

Roblox has a native cross-input drag detector. It handles mouse, touch, and gamepad,
supports constrained or scriptable motion, exposes drag lifecycle events, and can be
used for sliders as well as free dragging.

LuauUI should therefore not begin by generalizing its raw `UI.Grip` pointer capture
into another platform-level recognizer.

- Put `UIDragDetector` behind an adapter capability.
- Keep a pure Luau drag-session model for payloads, legal drop targets, enter/leave,
  predicted result, cancellation, and deterministic tests.
- Keep a headless input driver and a fallback for targets where the detector is not
  usable, including billboard canvases until their coordinate mapping is proven.
- Use the detector for Slider before inventing slider-specific pointer capture.
- Preserve the raw pointer seam only where it represents genuinely missing behavior.

The Studio spike must prove coordinate mapping through LuauUI's flat renderer,
reparented scroll hosts, scrolling during drag, gamepad speed, cancellation, and the
Sponsor card-to-row drop case.

Sources: [Roblox drag detector guide](https://create.roblox.com/docs/ui/ui-drag-detectors),
[`UIDragDetector` reference](https://create.roblox.com/docs/reference/engine/classes/UIDragDetector).

### 2. Touch gestures start with `GuiObject` events

`GuiObject` already exposes `TouchLongPress`, `TouchPan`, `TouchPinch`,
`TouchRotate`, `TouchSwipe`, and `TouchTap`. The SwiftUI audit's claim that the
engine surface is unverified is outdated.

LuauUI still needs a framework gesture layer, but its job is to normalize native
events into stable value objects, compose gestures, arbitrate conflicts, express
cross-input alternatives, and provide headless drivers. It should not re-recognize
touch gestures from raw samples unless a Studio test proves a native event is
insufficient.

Source: [`GuiObject` reference](https://create.roblox.com/docs/reference/engine/classes/GuiObject).

### 3. Paths and arcs start with `Path2D`

Roblox has an editable native 2D spline primitive with color, thickness, visibility,
and layering properties. Designers can edit its control points in Studio. The older
claim that Roblox has no vector-path surface is too broad.

Adopt a `Path` adapter backed by `Path2D` for strokes, curves, radial-progress arcs,
and suitable graybox icons. Keep rotation as a normal bound property for simpler
nodes. Do not promise filled paths, arbitrary Canvas drawing, more than the engine's
control-point limit, or cheap large particle fields without measuring them.

The Sponsor countdown ring and Race Drama indicator are the acceptance spikes. Only
keep the rotated-frame ring workaround if the native path fails one of their concrete
requirements.

Sources: [Roblox 2D paths guide](https://create.roblox.com/docs/ui/2D-paths),
[`Path2D` reference](https://create.roblox.com/docs/reference/engine/classes/Path2D).

### 4. Paged presentation should evaluate `UIPageLayout`

`UIPageLayout` already supports animated page changes and touch, gamepad, and wheel
input. Evaluate it for paged `TabView` and similar full-page navigation. It is not a
replacement for structural enter/exit transitions, matched geometry, toasts, or
Sponsor choreography.

Source: [`UIPageLayout` reference](https://create.roblox.com/docs/reference/engine/classes/UIPageLayout).

### 5. `GuiState` is observed, not assigned

`GuiObject.GuiState` is read-only. The adapter may classify app-defined state with
CollectionService tags. The engine itself supplies native hover, press, and
non-interactable states.

Replace every instruction to "set" or "flip" `GuiState` with this division:

- use `:Hover`, `:Press`, and `:NonInteractable` rules for engine-owned button state;
- add or remove named tags for LuauUI-owned state such as `selected`, logical focus,
  validation, drag eligibility, and semantic role.

Source: [`GuiObject` reference](https://create.roblox.com/docs/reference/engine/classes/GuiObject).

### 6. `StyleQuery` conditions are a closed native set

`StyleQuery:SetCondition` accepts named built-in conditions; it is not a general
store for arbitrary LuauUI environment values. Custom names fail silently. Use native
queries only for native facts such as preferred input, display size, reduced motion,
aspect ratio, and size ranges. Use tags for LuauUI's filtered interaction class,
pointer-live rule, and other framework decisions.

In particular, do not call `SetCondition("preferredInput", ...)`. Native
`PreferredInput` and LuauUI's noise-filtered paradigm are not the same thing.

Source: [`StyleQuery` reference](https://create.roblox.com/docs/reference/engine/classes/StyleQuery).

### 7. StyleSheets are live; Styling Transitions are progressive enhancement

Core StyleSheets and the Style Editor are current production capabilities. Styling
Transitions remain a Studio beta and must not be required by a publishable build.
Transitions run when styling changes because a rule, tag, native state, derive, or
token changes; they do not animate ordinary layout or direct property writes.

Use the built-in `ReducedMotionEnabled` query to omit or zero transitions for users
who request reduced motion. Keep an instant state-change path. Re-check the beta's
publish status immediately before enabling it in a release.

Sources: [Roblox styling guide](https://create.roblox.com/docs/ui/styling),
[Style Editor guide](https://create.roblox.com/docs/ui/styling/editor),
[compatibility guide](https://create.roblox.com/docs/ui/styling/compatibility).

### 8. The Style Editor promise has an explicit boundary

The native sheet is authoritative for paint and other engine-styleable properties:
fills, content color, fonts, corners, strokes, shadows where supported, semantic
roles, native interaction states, themes, and transitions when available. A designer
must be able to change these in the Style Editor and see the result without editing
Luau.

The headless solver remains authoritative for layout geometry and the values it must
read while no DataModel exists. Do not claim that a spacing or type-size edit in the
Style Editor affects LuauUI layout unless a tested export/synchronization workflow is
installed. Choose one honest workflow:

1. a Studio-owned sheet plus an exported, freshness-checked layout-token snapshot;
2. a plain-Luau layout-token source that generates only the sheet's layout mirrors;
3. another single-source workflow proven to round-trip without silently clobbering
   designer edits.

Paint remains Studio-owned in every option. The implementation guide must label
which editor fields affect runtime paint immediately and which require export.

### 9. Preferred text size must not be applied twice

Roblox applies `PreferredTextSize` in its font-rendering pipeline. Text measurement
APIs honor it; `TextScaled` opts out; `UITextSizeConstraint` can bound it; and
`AutomaticSize` can grow containers around it. LuauUI currently maps the preference
to `typographyScale` and also multiplies `TextSize`, which may apply the preference
twice.

Before changing text scaling, run a Studio matrix covering every
`PreferredTextSize`, explicit/default `TextSize`, `TextScaled`,
`UITextSizeConstraint`, wrapped text, and the measurement API LuauUI uses. The likely
target is:

- the engine owns the player's preferred text rendering in production;
- LuauUI applies only authored scale such as the ten-foot treatment;
- the headless solver models the same reserved bounds using injected preference
  facts, without writing the player's preference back as another scale;
- measured and painted bounds agree and never clip.

Source: [Roblox accessibility guidance](https://create.roblox.com/docs/production/publishing/accessibility).

### 10. Safe-area authority must be singular

Read four-edge insets from `GuiService:GetInsetArea(Enum.ScreenInsets...)` and choose
one coordinate model. If LuauUI applies injected inset facts in the solver, configure
the root `ScreenGui` so Roblox does not apply the same inset again. Verify portrait,
landscape notch, topbar, console overscan, and orientation changes.

Sources: [`GuiService` reference](https://create.roblox.com/docs/reference/engine/classes/GuiService),
[`ScreenGui` reference](https://create.roblox.com/docs/reference/engine/classes/ScreenGui),
[`ScreenInsets` reference](https://create.roblox.com/docs/reference/engine/enums/ScreenInsets).

### 11. Engine selection is not a general-purpose focus mirror

Do not promise free selection sounds, haptics, autoscroll, or a passive one-way
`SelectedObject` mirror until a real gamepad spike proves them without double-driving
IAS. Setting an object selected while making everything non-selectable is not a
sound design contract, and Roblox may clear a selection that moves offscreen.

Use this safety rule:

- LuauUI's logical focus graph always owns focus identity and navigation.
- Gameplay/passive HUDs, including the normal Sponsor race surface, keep
  `GuiService.SelectedObject = nil`; selecting UI can reserve controls that gameplay
  needs.
- A modal/menu may opt into an engine-selection bridge only while its responder owns
  UI input, after Studio and physical-gamepad verification.
- If the bridge cannot be made passive, use LuauUI's own focus visual and explicit
  scroll-to-visible command.

### 12. `PreloadAsync` cancellation is logical, not physical

`ContentProvider:PreloadAsync` yields and reports final per-asset fetch status through
its callback. It exposes no cancellation API. Releasing a LuauUI resource handle can
ignore a stale completion and prevent queued work from starting, but it cannot stop
an in-flight Roblox fetch.

Acceptance must therefore say "no stale state resurrection; no unstarted work begins"
instead of "scroll-away stops the active download."

Source: [`ContentProvider` reference](https://create.roblox.com/docs/reference/engine/classes/ContentProvider).

### 13. Existing work that must be reused

`src/client/billboard_target.luau` is an implemented `BillboardGui` render target,
not a stub. Sponsor parity work should verify and extend it only for missing live
requirements such as coordinate mapping or pointer capture.

Haptics and sound stay semantic seams. LuauUI may emit events such as select,
activate, error, commit, land, or celebrate; the game owns `HapticEffect` selection,
sound assets, mixing, and policy. Confetti and other authored particles remain game
presentation unless a broadly reusable framework need is demonstrated.

## Revised native-first spike checklist

Before production implementation, capture machine evidence for:

1. `ScrollingFrame` as LuauUI's scroll/clip host, including virtualization.
2. `UIDragDetector` through flat hierarchy, scrolling, gamepad, and Sponsor drop.
3. Native touch gesture events and their arbitration behavior.
4. `Path2D` for Sponsor rings/needle and Studio authoring.
5. `UIPageLayout` for paged `TabView` only.
6. StyleSheet property ownership, native states, tags, derives, queries, editor
   round-trip, and transition beta behavior.
7. Preferred-text measurement versus paint, with no double scaling.
8. Four-edge safe areas with exactly one inset authority.
9. Modal-only engine selection bridge; passive Sponsor HUD keeps selection nil.
10. `PreloadAsync` success/failure and stale-completion behavior.

Any failed spike keeps the current headless seam or adapter fallback. It does not
justify a game-specific workaround inside the framework.
