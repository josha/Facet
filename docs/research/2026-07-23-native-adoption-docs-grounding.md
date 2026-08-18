# Native-adoption docs grounding — 2026-07-23

**Mission:** Facet native-adoption evidence gathering (Roblox-native primitives audit +
corrections addendum). **Date fetched:** 2026-07-23. Every claim below carries the
exact `create.roblox.com` URL it was fetched from; where a fetch could not confirm a
fact from the reference page's rendered content, that is stated explicitly rather than
filled in from memory.

**Method caveat (read once, applies throughout):** several Creator Hub reference pages
(class/property "stub" pages, especially individual property sub-pages like
`.../GuiService/SelectedObject`) returned only a property table (type, "Read
Parallel"/"Read Only", Capabilities) with **no prose description** in the fetched
markdown, even though the live page likely renders one. Wherever that happened it is
called out as "no prose description captured" rather than silently omitted or guessed.
Enum reference pages consistently returned names + numeric values but not always the
per-value description sentence — same caveat applies there.

**Governing documents compared against:** `docs/plans/roblox-native-audit-corrections.md`
(2026-07-22, the current governing addendum) and `docs/plans/roblox-native-primitives.md`
(2026-07-22 draft, superseded wherever it conflicts with the addendum). Disagreements
against either are marked `⚠ DISAGREEMENT`.

---

## 1. `UIDragDetector`

Properties (all "Read Parallel", Capabilities: UI): `ActivatedCursorIcon` (ContentId),
`ActivatedCursorIconContent` (Content), `BoundingBehavior`
(`Enum.UIDragDetectorBoundingBehavior`), `BoundingUI` (GuiBase2d), `CursorIcon`
(ContentId), `CursorIconContent` (Content), `DragAxis` (Vector2), `DragRelativity`
(`Enum.UIDragDetectorDragRelativity`), `DragRotation` (number), `DragSpace`
(`Enum.UIDragDetectorDragSpace`), `DragStyle` (`Enum.UIDragDetectorDragStyle`),
`DragUDim2` (UDim2), `Enabled` (boolean), `MaxDragAngle`/`MinDragAngle` (number),
`MaxDragTranslation`/`MinDragTranslation` (UDim2), `ReferenceUIInstance` (GuiObject),
`ResponseStyle` (`Enum.UIDragDetectorResponseStyle`), `SelectionModeDragSpeed` (UDim2),
`SelectionModeRotateSpeed` (number), `UIDragSpeedAxisMapping`
(`Enum.UIDragSpeedAxisMapping`).

Methods: `AddConstraintFunction(priority: number, function): RBXScriptConnection`,
`GetReferencePosition(): UDim2`, `GetReferenceRotation(): number`,
`SetDragStyleFunction(function): ()`.

Events (each fires with a single `inputPosition: Vector2`): `DragStart`,
`DragContinue`, `DragEnd`.

**`DragStyle` enum values** (`Enum.UIDragDetectorDragStyle`): `TranslatePlane` (0),
`TranslateLine` (1), `Rotate` (2), `Scriptable` (3). Per-value description sentences
were not present in the fetched content — only names/numbers.

**`ResponseStyle` enum values** (`Enum.UIDragDetectorResponseStyle`): `Offset` (0),
`Scale` (1), `CustomOffset` (2), `CustomScale` (3). Same caveat — no per-value prose
captured.

**`BoundingBehavior` enum values** (`Enum.UIDragDetectorBoundingBehavior`):
`Automatic` (0), `EntireObject` (1), `HitPoint` (2). No per-value prose captured.

**Input-type support (mouse/touch/gamepad):** ⚠ **not explicitly stated on the
reference page** — the fetch returned "the documentation provided does not specify
input support details" for the class reference. The **guide** page (item 2, below)
also does not mention gamepad at all in its documented text; it only demonstrates
mouse/touch-style drag via `DragContinue`. The corrections addendum's claim that
`UIDragDetector` "handles mouse, touch, and gamepad" is **not directly confirmed by
either fetched doc page** — treat it as needing a Studio gamepad spike (which the
addendum and audit already require via Q1/Phase 2) rather than an established fact.

**Studio compatibility caveat (from the guide, item 2):** `UIDragDetector`s work in
Studio edit/play mode "as long as you're not using the Select, Move, Scale, or Rotate
tools."

**ScrollingFrame/ScreenGui compatibility, beta flags:** not mentioned on either fetched
page — no statement found either way.

Source: https://create.roblox.com/docs/reference/engine/classes/UIDragDetector (fetched 2026-07-23)
Source: https://create.roblox.com/docs/reference/engine/enums/UIDragDetectorDragStyle (fetched 2026-07-23)
Source: https://create.roblox.com/docs/reference/engine/enums/UIDragDetectorResponseStyle (fetched 2026-07-23)
Source: https://create.roblox.com/docs/reference/engine/enums/UIDragDetectorBoundingBehavior (fetched 2026-07-23)

## 2. `UIDragDetector` guide (`ui-drag-detectors`)

Presents `UIDragDetector` as a no-code drag-enabler: add it as a child of any
`GuiObject` and it drives drag interaction. The documented slider recipe: set
`ResponseStyle = Scale` for proportional movement, `DragStyle = TranslateLine` to
restrict motion to one axis, assign the container as `BoundingUI` to constrain the
handle, and read `DragContinue` to update a value ("change transparency by how much it
dragged in scale"). Default `DragAxis` is `(1, 0)` (horizontal only unless changed).
Bounds are customized via `MinDragTranslation`/`MaxDragTranslation`/`MinDragAngle`/
`MaxDragAngle`.

**Not mentioned in the guide's documented text:** `ScrollingFrame` interaction,
gamepad support, or performance/limit guidance. This is a real gap in the current
official guide relative to what the corrections addendum needs proven — the Studio
spike (billboard canvases, reparented scroll hosts, gamepad speed, Sponsor
card-to-row drop) is not something the published guide answers; it must still be
verified empirically as the addendum already assumes.

Source: https://create.roblox.com/docs/ui/ui-drag-detectors (fetched 2026-07-23)

## 3. `GuiObject` touch events, `GuiState`, input events

**Touch event signatures** (exact per fetched page):
- `TouchLongPress(touchPositions: {any}, state: Enum.UserInputState)`
- `TouchPan(touchPositions: {any}, totalTranslation: Vector2, velocity: Vector2, state: Enum.UserInputState)`
- `TouchPinch(touchPositions: {any}, scale: number, velocity: number, state: Enum.UserInputState)`
- `TouchRotate(touchPositions: {any}, rotation: number, velocity: number, state: Enum.UserInputState)`
- `TouchSwipe(swipeDirection: Enum.SwipeDirection, numberOfTouches: number)` — **no
  state parameter** (single-shot event).
- `TouchTap(touchPositions: {any})` — **no state parameter** (single-shot event).

Documented `Enum.UserInputState` values used by the four gesture-with-state events:
`Begin`, `Change`, `End`.

**`GuiState` property:** type `Enum.GuiState`, access **"Read Only"** (confirms
corrections addendum §5 — it is observed, not assigned). Per-value descriptions were
not captured from the `GuiObject` page itself, but the separate `Enum.GuiState` page
(fetched directly) gives the actual member names: **`Idle` (0), `Hover` (1), `Press`
(2), `NonInteractable` (3)**.

⚠ **DISAGREEMENT:** `docs/plans/roblox-native-primitives.md` line 79 describes
`GuiState` as "an engine enum (`None`/`Hover`/`Press`/`NonInteractable`)". The actual
enum member is **`Idle`, not `None`**. This is a small naming error in the primitives
audit that should be corrected before any code or docs reference `Enum.GuiState.None`
(it does not exist under that name — the idle/default state is `Enum.GuiState.Idle`).

**Input events:** `InputBegan(input: InputObject)`, `InputChanged(input: InputObject)`,
`InputEnded(input: InputObject)` — all single-parameter, no additional signature
detail captured beyond the `InputObject` parameter.

Source: https://create.roblox.com/docs/reference/engine/classes/GuiObject (fetched 2026-07-23)
Source: https://create.roblox.com/docs/reference/engine/enums/GuiState (fetched 2026-07-23)

## 4. `Path2D`

**Properties:** `Closed` (boolean), `Color3` (Color3), `SelectedControlPoint` (number,
not replicated), `SelectedControlPointData` (`Path2DControlPoint`, not replicated),
`Thickness` (number), `Visible` (boolean), `ZIndex` (number).

**Control-point methods:** `GetControlPoint(index)`, `GetControlPoints()`,
`SetControlPoints(controlPoints)`, `InsertControlPoint(index, point)`,
`RemoveControlPoint(index)`, `UpdateControlPoint(index, point)`.

**Curve-query methods:** `GetPositionOnCurve(t): UDim2`,
`GetPositionOnCurveArcLength(t): UDim2`, `GetTangentOnCurve(t): Vector2`,
`GetTangentOnCurveArcLength(t): Vector2`, `GetLength(): number`,
`GetBoundingRect(): Rect`, **`GetMaxControlPoints(): number`**.

**Events:** `ControlPointChanged`.

**Control-point limit:** a hard limit **does exist and is queryable** —
`GetMaxControlPoints()` returns it — but the fetched reference text did not surface
the actual numeric ceiling. Call `GetMaxControlPoints()` in Studio to get the concrete
number for the Sponsor ring/needle spike rather than assuming one.

**Transparency:** ⚠ no `Transparency` property was found on this class in the fetched
content at all — the mission item assumed one exists. Treat `Path2D` as having no
documented transparency control; if a faded path is needed, it may require layering,
`Color3` blending, or a different mechanism — verify in Studio before designing around
a `Transparency` property that may not exist.

**Fill support:** confirmed **no mention of fill/filled paths anywhere** in the
reference content — consistent with the corrections addendum's caution ("Do not
promise filled paths").

**Parenting rules** (from the guide, item 5): a `Path2D` must ultimately be under a
visible `ScreenGui` or `SurfaceGui`, but **"it does not need to be a direct child"** —
i.e., it can be nested arbitrarily deep (inside a `Frame`, `ScrollingFrame`, etc.) as
long as the ancestor chain includes a `ScreenGui`/`SurfaceGui`. This directly answers
the mission's "where can it render" question: yes, inside a `Frame`/`ScrollingFrame`
under a `ScreenGui`, not only as a screen-level root.

Source: https://create.roblox.com/docs/reference/engine/classes/Path2D (fetched 2026-07-23)

## 5. `Path2D` guide (`2D-paths`)

Studio authoring workflow: insert `Path2D` under a visible `ScreenGui`/`SurfaceGui`;
use the **Add Point** tool (default) to click control points, dragging to create
tangents; finish with Done/Enter. Editing: **Move** (Select tool, V) drags points or
sets precise `UDim2` values in Properties; **Add** inserts/extends points (P);
**Delete** via right-click; **Tangents** added via the Add Tangent tool, adjusted by
dragging, or broken/mirrored via right-click.

Capabilities described: 2D splines/curved lines for UI effects such as path-based
animation and graph editors; visual customization via `Color3`, `Thickness` (pixels),
`Visible`, `ZIndex`; scripted use includes arranging objects along a path and
animating along a curve via `GetPositionOnCurveArcLength()`.

**No max-control-point number, performance threshold, or closed-path fill capability**
is stated in the guide's documented text (consistent with item 4's finding — the
number exists via `GetMaxControlPoints()` but isn't published in prose here).

Source: https://create.roblox.com/docs/ui/2D-paths (fetched 2026-07-23)

## 6. `UIPageLayout`

**Properties** (all "Capabilities: UI"): `Animated` (boolean), `Circular` (boolean),
`CurrentPage` (GuiObject, **read-only, not replicated**), `EasingDirection`
(`Enum.EasingDirection`), `EasingStyle` (`Enum.EasingStyle`), `GamepadInputEnabled`
(boolean), `Padding` (UDim), `ScrollWheelInputEnabled` (boolean),
`TouchInputEnabled` (boolean), `TweenTime` (number).

⚠ **Not found on this class:** `VerticalAlignment`/`HorizontalAlignment` — the
fetched reference page did not list either property on `UIPageLayout`. (Those
properties belong to layout objects like `UIListLayout`/`UIGridLayout`, not
`UIPageLayout`.) This corrects an assumption baked into the mission's own question
list, not the corrections addendum — no plan document currently depends on
`UIPageLayout` having alignment properties, so this is informational rather than a
plan-breaking disagreement.

**Page-selection API:** `JumpTo(page: Instance): ()`, `JumpToIndex(index: number): ()`,
`Next(): ()`, `Previous(): ()`, plus the read-only `CurrentPage` property.

**Events:** `PageEnter(page: Instance): RBXScriptSignal`,
`PageLeave(page: Instance): RBXScriptSignal`, `Stopped(currentPage: Instance):
RBXScriptSignal`.

This confirms the corrections addendum §4 claim that `UIPageLayout` supports animated,
touch/gamepad/wheel-driven page changes with lifecycle events, appropriate for a paged
`TabView` evaluation.

Source: https://create.roblox.com/docs/reference/engine/classes/UIPageLayout (fetched 2026-07-23)

## 7. `ScrollingFrame`

**Properties confirmed with type:** `CanvasSize` (UDim2), `CanvasPosition` (Vector2),
`AbsoluteCanvasSize` (Vector2, read-only), `AutomaticCanvasSize`
(`Enum.AutomaticSize`), `ElasticBehavior` (`Enum.ElasticBehavior`),
`ScrollingDirection` (`Enum.ScrollingDirection`), `ScrollBarThickness` (number),
`ScrollBarImageColor3` (Color3), `ScrollBarImageTransparency` (number),
`ScrollingEnabled` (boolean), `VerticalScrollBarInset` (`Enum.ScrollBarInset`),
`VerticalScrollBarPosition` (enum, values not captured on this page),
`HorizontalScrollBarInset` (`Enum.ScrollBarInset`), `TopImage`/`MidImage`/`BottomImage`
(ContentId).

**Enum values fetched directly:**
- `Enum.AutomaticSize`: `None` (0), `X` (1), `Y` (2), `XY` (3).
- `Enum.ElasticBehavior`: `WhenScrollable` (0), `Always` (1), `Never` (2).
- `Enum.ScrollingDirection`: `X` (1), `Y` (2), `XY` (4) — note the bitmask-style
  numeric values (1/2/4, not 0/1/2); per-value descriptions were not captured, names
  are self-explanatory.
- `Enum.ScrollBarInset`: `None` (0), `ScrollBar` (1), `Always` (2).

⚠ **Not confirmed in fetched docs — flag for Studio verification (this is exactly
what primitives-audit Q1/Q2 and corrections-addendum item 1 of the spike checklist
already require):**
- **Gamepad scroll-to-selection behavior.** No fetched page states that a
  `ScrollingFrame` automatically scrolls `CanvasPosition` to keep a `SelectedObject`
  descendant visible. This is a real gap between what the primitives audit's summary
  table asserts ("gamepad scroll support when a selected object scrolls out of view")
  and what the official reference pages actually document. Treat this as an
  **unverified assumption**, not a confirmed fact, until the Phase-2/Q2 Studio spike
  proves it.
- **`ClipsDescendants` interaction.** No fetched text states whether
  `ClipsDescendants` is implicitly forced `true` on a `ScrollingFrame` or remains an
  independently settable property. Verify directly in Studio (Q1 in the primitives
  audit already calls for exactly this comparison).

Source: https://create.roblox.com/docs/reference/engine/classes/ScrollingFrame (fetched 2026-07-23)
Source: https://create.roblox.com/docs/reference/engine/enums/AutomaticSize (fetched 2026-07-23)
Source: https://create.roblox.com/docs/reference/engine/enums/ElasticBehavior (fetched 2026-07-23)
Source: https://create.roblox.com/docs/reference/engine/enums/ScrollBarInset (fetched 2026-07-23)

## 8. `GuiService`

**`GetInsetArea` — exact signature:**
```
GuiService:GetInsetArea(screenInsets: Enum.ScreenInsets): Rect
```
It takes a **single `Enum.ScreenInsets` parameter** and returns a **single `Rect`**
(not four separate numbers) — the `Rect` datatype carries `Min`/`Max` `Vector2`s, so
all four edges come back from one call keyed by which inset class you ask for.

**`GetGuiInset` — exact signature:**
```
GuiService:GetGuiInset(): Tuple
```
Returns a `Tuple` (a legacy, pre-`ScreenInsets` API). The fetched page did not spell
out the tuple's element names/types, and no explicit deprecation notice was present in
the fetched content, though the page references `GetInsetArea` as the newer
alternative. Per the corrections addendum, prefer `GetInsetArea(Enum.ScreenInsets...)`
for the four-edge model rather than relying on this legacy tuple.

**`TopbarInset`:** type `Rect`, **read-only**.

**`ViewportDisplaySize`:** type `Enum.DisplaySize`, **read-only**; per a separate
fetch, has at least `Small`/`Large` plus a default/medium-tier value (exact full member
list not captured from this page — cross-check against `Enum.DisplaySize` directly if
an exhaustive list is needed).

**`SelectedObject`:** type `GuiObject`, **read-write** (not marked read-only). No
prose description was captured directly from the class page, but a `GuiService`
property is documented (per direct sub-page + search-indexed snippet of the official
docs) to state that it **"may reset to nil if the object is off screen"** — i.e., the
engine can clear selection on its own when the selected object scrolls/moves offscreen.
This is exactly the risk the corrections addendum §11 and the primitives audit §7/Q3
already warn about ("Roblox may clear a selection that moves offscreen") — now backed
by the actual property description rather than assumption. Related events exist:
`GuiService.SelectionGained`/`SelectionLost` fire on selection change.

**`GuiNavigationEnabled`:** type boolean; controls whether the engine's default
controller GUI navigation (Select button / Backslash auto-selecting a GUI) is active.
Disabling it means gamepad navigation still works once `SelectedObject` is set
manually, but the engine no longer auto-picks an initial selection.

**Selectable-related / selection API:** deprecated methods `AddSelectionParent()`,
`AddSelectionTuple()`, `RemoveSelectionGroup()`; the current method is
`Select(selectionParent: Instance): ()`, which (per the docs-indexed description) —
when called on the `PlayerGui` or a descendant — makes the engine search all
selectable, visible, on-screen `GuiObject`s under that instance and sets
`SelectedObject` to the one with the smallest `SelectionOrder`.

**`PreferredTextSize`:** type `Enum.PreferredTextSize`, **read-only**, on
**`GuiService`** (not `UserGameSettings` — see item 16). Default `Medium`; other
values `Large`, `Larger`, `Largest`. Maps to the player's Text Size setting in the
Roblox/in-game Settings menu; combine with `GetPropertyChangedSignal()` to react to
changes.

**`ReducedMotionEnabled`:** boolean, **"Hidden, Read Only"** — also lives on
`GuiService`, not `UserGameSettings`.

**No `GetSafeZoneOffsets`-like method** was found in any fetched `GuiService` content.

⚠ Note for item 16 below: this directly resolves where the two accessibility
properties actually live — **`GuiService`, not `UserGameSettings`**.

Source: https://create.roblox.com/docs/reference/engine/classes/GuiService (fetched 2026-07-23)
Source: https://create.roblox.com/docs/reference/engine/classes/GuiService/SelectedObject (fetched 2026-07-23)
Source: https://create.roblox.com/docs/reference/engine/classes/GuiService/GuiNavigationEnabled (fetched 2026-07-23)
Source: https://create.roblox.com/docs/reference/engine/classes/GuiService/GetGuiInset (fetched 2026-07-23)

## 9. `Enum.ScreenInsets`

Members and numeric values as fetched: `None` (0), `DeviceSafeInsets` (1),
`CoreUISafeInsets` (2), `TopbarSafeInsets` (3). Per-value description sentences were
not present in the fetched content — only names and numbers were captured; the names
are self-describing and align with the corrections addendum's "four-edge insets" /
`deviceSafeInsets` vs `coreSafeInsets` distinction (§10, §8 of the primitives audit).

Source: https://create.roblox.com/docs/reference/engine/enums/ScreenInsets (fetched 2026-07-23)

## 10. `ScreenGui`

**`ScreenInsets`:** type `Enum.ScreenInsets` (values as in item 9). No default value
captured.

**`SafeAreaCompatibility`:** type `Enum.SafeAreaCompatibility`. Direct enum fetch
gives: `None` (0), `FullscreenExtension` (1). No per-value description captured.

**`IgnoreGuiInset`:** type boolean, marked **"Not Replicated."** ⚠ **No explicit
deprecation notice was found in the fetched content** — the mission item assumed it
might be marked deprecated; that could not be confirmed. Functionally it is superseded
by `ScreenInsets`/`SafeAreaCompatibility` for the four-edge model, but the docs text
fetched does not itself say "deprecated." Treat "not confirmed deprecated" as the
accurate status rather than assuming a deprecation banner exists.

**`ClipToDeviceSafeArea`:** boolean — exists, described as clipping GUI content to
device-safe areas (matches the mission's guessed name/purpose).

**`DisplayOrder`:** number — controls GUI layering/render order.

`ResetOnSpawn` and `ZIndexBehavior` were not present in the fetched excerpt for this
page (they exist on `ScreenGui` per general Roblox knowledge, but were not captured in
this fetch — do not cite this document for their exact defaults without re-fetching).

Source: https://create.roblox.com/docs/reference/engine/classes/ScreenGui (fetched 2026-07-23)
Source: https://create.roblox.com/docs/reference/engine/enums/SafeAreaCompatibility (fetched 2026-07-23)

## 11. `ContentProvider`

**`PreloadAsync` — exact signature (as fetched):**
```
PreloadAsync(contentIdList: {any}, callbackFunction: function?): ()
```
Callback parameters: `assetId: string` (the content ID), `assetFetchStatus:
Enum.AssetFetchStatus`.

**Yields:** confirmed — the fetched page states plainly **"Yields."**

**Cancellation:** confirmed **no cancellation mechanism is documented** — the fetch
explicitly reports "the documentation does not mention any mechanism for cancelling
preloads or stopping them once initiated." This directly backs corrections addendum
§12: cancellation is logical (ignore/discard a stale callback), never physical
(stopping an in-flight fetch).

**`RequestQueueSize`:** type `number`, **"Read Only."**

Source: https://create.roblox.com/docs/reference/engine/classes/ContentProvider (fetched 2026-07-23)

## 12. `Enum.AssetFetchStatus`

Members and numeric values as fetched: `Success` (0), `Failure` (1), `None` (2),
`Loading` (3), `TimedOut` (4). Per-value descriptions were not present in the fetched
content beyond the names themselves. Note there are **five** values, not just
success/failure — `None` (not yet requested/no status) and `Loading`/`TimedOut` are
real intermediate/terminal states a `PreloadAsync` callback consumer should switch on.

Source: https://create.roblox.com/docs/reference/engine/enums/AssetFetchStatus (fetched 2026-07-23)

## 13. `StyleQuery` and `docs/ui/styling` (GA/beta status)

**`SetCondition` — exact signature (as fetched):**
```
SetCondition(name: string, value: Variant): ()
```

⚠ **Built-in condition names are NOT enumerated on the `StyleQuery` reference page
itself** — that fetch returned only the method signature, with no list of accepted
built-in names and no statement about what happens with an unrecognized name. This
particular fact (closed set vs open dictionary, silent-fail behavior) — which the
corrections addendum §6 asserts plainly ("Custom names fail silently") — **could not
be directly re-confirmed from the `StyleQuery` reference page in this pass.** Treat
addendum §6 as still the operative guidance but flag it for a direct Studio
`SetCondition("bogusName", true)` check before relying on silent-failure semantics in
implementation.

**What the Style Editor guide (`docs/ui/styling/editor`) does confirm:** built-in
queries can be used with an `@` prefix **without needing an actual `StyleQuery`
instance** — e.g. `@ViewportDisplaySizeLarge`, `@ViewportDisplaySizeMedium`,
`@ViewportDisplaySizeSmall` (mapped from `Enum.DisplaySize`). A separate search of
Creator Hub content corroborates: "built-in queries... map directly to global
environment states such as `ViewportDisplaySize` or `ReducedMotionEnabled`... do not
require a `StyleQuery` definition and can be used directly with an `@` prefix." This
is consistent with the corrections addendum's "closed native set" framing — the
mechanism really is a fixed list of engine-recognized globals, not an arbitrary
key/value store — but the **complete enumerated list** (does it include something
literally named `preferredInput`, `aspectRatio`, `sizeRange` as the addendum
assumes?) was not captured verbatim in this pass and should be pulled from the Style
Editor guide's full reference table directly in Studio or via a follow-up fetch
targeting that specific table.

**GA/beta status — directly confirmed:**
- **Style Editor:** described as a standard, "comprehensive tool" — no beta
  qualifier found. Treat as GA.
- **Styling Transitions:** explicitly **"This feature is currently in beta. Enable
  it through File ⟩ Beta Features ⟩ Styling Transitions."** This is a strong,
  verbatim confirmation of corrections addendum §7's claim that Styling Transitions
  "remain a Studio beta and must not be required by a publishable build."
- **StyleSheet core class / `docs/ui/styling` / `docs/ui/styling/compatibility`:**
  none of these three pages contained the words "beta," "experimental," "GA," or
  "generally available" in the fetched content — they present StyleSheets and the
  Style Editor as established, undated documentation. Combined with the explicit
  beta banner found on the Style Editor guide for Transitions specifically, the
  overall picture is: **core StyleSheets = GA, Style Editor = GA, Styling
  Transitions = beta** — exactly the split the corrections addendum already assumes.

**`StyleRule:SetPropertyTransition` — exact signature (as fetched):**
```
SetPropertyTransition(property: string, transitionParams: Variant): ()
```
Other `StyleRule` members: properties `Priority` (number), `Selector` (string),
`SelectorError` (string, read-only); methods `GetDefaultPropertyTransition()`,
`GetProperties()`, `GetProperty(name)`, `GetPropertyTransitions()`,
`SetDefaultPropertyTransition(transitionParams)`, `SetProperties(styleProperties)`,
`SetProperty(name, value)`, `SetPropertyTransitions(properties)`. No beta notice was
present on the `StyleRule` class page itself — the beta banner is on the guide page,
not the reference page.

Source: https://create.roblox.com/docs/reference/engine/classes/StyleQuery (fetched 2026-07-23)
Source: https://create.roblox.com/docs/ui/styling (fetched 2026-07-23)
Source: https://create.roblox.com/docs/ui/styling/compatibility (fetched 2026-07-23)
Source: https://create.roblox.com/docs/ui/styling/editor (fetched 2026-07-23)
Source: https://create.roblox.com/docs/reference/engine/classes/StyleSheet (fetched 2026-07-23)
Source: https://create.roblox.com/docs/reference/engine/classes/StyleRule (fetched 2026-07-23)

## 14. Accessibility guidance (`production/publishing/accessibility`) — `PreferredTextSize`

Confirmed, quoted verbatim from the fetched page:

- TextScaled opt-out: **"When TextScaled is enabled for a TextLabel or TextButton,
  the element's text will not be scaled by the PreferredTextSize value."**
- `UITextSizeConstraint` bound: **"Text that is constrained to a minimum and/or
  maximum size through a UITextSizeConstraint will not shrink below or expand above
  the set MinTextSize/MaxTextSize, regardless of the player's text size setting."**
- `AutomaticSize` interaction: **"UI elements with AutomaticSize enabled will
  shrink/grow as PreferredTextSize decreases/increases (element bounds will resize to
  fit the resized text)."**
- `TextWrapped` interaction: **"When TextWrapped is enabled for a TextLabel or
  TextButton, the element's text will wrap to additional lines as PreferredTextSize
  increases, within limits of the element's absolute size."**
- Measurement APIs: **"The results returned by TextService:GetTextSize() and
  TextService:GetTextBoundsAsync() honor changes related to PreferredTextSize."**
- The property scripts read is **`GuiService.PreferredTextSize`** (confirmed again
  here, matching item 8) — defaults to `Medium`, with `Large`/`Larger`/`Largest`.

This is a strong, direct confirmation of corrections addendum §9's entire premise:
the engine's font pipeline already applies `PreferredTextSize`; `TextScaled` opts a
node out; `UITextSizeConstraint` bounds it; `AutomaticSize` grows containers around
it. Facet's current double-application risk (mapping the preference to
`typographyScale` *and* multiplying `TextSize`) is exactly the failure mode this page's
facts predict — no disagreement, this fully supports the addendum's required Studio
matrix.

Source: https://create.roblox.com/docs/production/publishing/accessibility (fetched 2026-07-23)

## 15. `ImageLabel`

**`IsLoaded`:** boolean, **"Read Only"**, "Not Replicated." Confirmed to exist,
checks whether the image has finished loading.

⚠ **`LoadingImageFailed`: existence NOT confirmed.** Two separate fetches — the main
`ImageLabel` reference page, and a direct fetch of
`.../ImageLabel/LoadingImageFailed` — both failed to surface any description; the
direct sub-page fetch returned no content for that member at all. This directly
concerns a fact the primitives audit's §9 recommendation table asserts as an
existing engine signal ("the image load/failure signals `ImageLabel.IsLoaded` and
`ImageLabel.LoadingImageFailed`"). **This could not be confirmed from official docs
in this pass** — it may still exist (WebFetch struggled with several sub-pages
throughout this research), but do not treat it as confirmed; verify directly via
Studio autocomplete/API dump (`game:GetService("Selection")`-style introspection or
the `ImageLabel` class's actual member list in Studio) before writing an adapter that
depends on this event/property existing under this exact name.

**`ScaleType`:** `Enum.ScaleType` — full member list confirmed via direct enum fetch:
**`Stretch` (0), `Slice` (1), `Tile` (2), `Fit` (3), `Crop` (4)** — five values, not
three; the initial `ImageLabel`-page fetch only surfaced Stretch/Tile/Slice in prose,
but the enum itself also has `Fit` and `Crop`, both directly relevant to "crop"
behavior the mission asked about. Per the initial fetch's prose: "Stretch simply
stretches the source image to fit the UI element's space," "Tile will render the
source image multiple times enough to fill the UI element's space," "Slice will turn
the image into a nine-slice UI" — per-value prose for `Fit`/`Crop` was not captured,
but their names are self-describing (fit-within vs crop-to-fill).

**`ResampleMode`:** type is actually **`Enum.ResamplerMode`** (not "ResampleMode" —
the property name and enum type name differ slightly in casing/spelling from what the
mission assumed). Members: `Default` (0), `Pixelated` (1). This is directly relevant
to crisp pixel-art icon rendering at non-native resolutions.

**`Image` vs `ImageContent`:** `Image` is `ContentId`; `ImageContent` is a separate,
newer `Content`-typed, "Read Parallel" property alongside it. The exact
precedence/interaction between the two when both are set was not documented in the
fetched content — treat as unconfirmed and verify in Studio if both will ever be set
simultaneously.

Source: https://create.roblox.com/docs/reference/engine/classes/ImageLabel (fetched 2026-07-23)
Source: https://create.roblox.com/docs/reference/engine/enums/ScaleType (fetched 2026-07-23)
Source: https://create.roblox.com/docs/reference/engine/enums/ResamplerMode (fetched 2026-07-23)

## 16. `UserGameSettings`

⚠ **DISAGREEMENT / correction to the mission's own premise:** the fetched
`UserGameSettings` reference content contains **no accessibility-related properties at
all** — no `PreferredTextSize`, no reduced-motion preference, nothing of the kind. The
documented properties are all visual (graphics quality, vignette, camera modes), audio
(master/party volume), UI visibility (badges, chat, player list/names), input (mouse
sensitivity, gamepad camera sensitivity, rotation type), and VR-specific settings.

**Resolution:** per items 8 and 14 above, **`PreferredTextSize` and
`ReducedMotionEnabled` both live on `GuiService`, not `UserGameSettings`.** Any
implementation code or design doc that reads these off `UserGameSettings` is reading
the wrong class — this is worth propagating back into the Facet Roblox adapter
(`src/client/roblox_env.luau`) if it currently assumes `UserGameSettings` for either
fact.

**Studio-vs-live permission caveat:** the fetch surfaced one general caution — "sometimes
[a property-changed] event fires with properties that LocalScripts can't access" —
indicating some `UserGameSettings` properties have LocalScript-only or
permission-gated access in certain contexts, but no accessibility-specific permission
caveat was found (since no accessibility properties exist on this class at all).

Source: https://create.roblox.com/docs/reference/engine/classes/UserGameSettings (fetched 2026-07-23)

## 17. `Selectable` / `SelectedObject` navigation behavior

**`GuiObject.Selectable`:** type boolean. Direct sub-page fetches
(`GuiObject/Selectable`, `GuiButton/Selectable`) returned only the bare type/
capability stub with no prose — `Selectable` is not a member of `GuiButton` itself
(confirmed absent from that class's fetched member list), consistent with it being
declared on `GuiObject` and inherited. A search-indexed snippet of the official docs
states its effect in prose: **"The Selectable property determines whether the
GuiObject can be selected when navigating GUIs using a gamepad. If this property is
true, a GUI can be selected, which also sets the GuiService.SelectedObject property to
that object."** This snippet reads as a paraphrase/quote of the actual Creator Hub
text but was not independently reproduced by a direct WebFetch of the property
sub-page in this pass — treat it as high-confidence but not verbatim-confirmed.

**Automatic engine behavior when `SelectedObject` is set** (per the same
search-indexed docs content, corroborating item 8's `SelectedObject` finding):
- The engine's GUI navigator uses `SelectedObject` as the current focus for
  `NextSelectionUp/Down/Left/Right`-based navigation.
- **`SelectedObject` "may reset to nil if the object is off screen"** — auto-clear on
  offscreen is a real, if loosely worded, documented behavior (matches corrections
  addendum §11's explicit warning almost verbatim).
- `GuiNavigationEnabled` (item 8) gates whether the engine **automatically** promotes
  a GUI to `SelectedObject` when the player presses Select/Backslash on a gamepad;
  disabling it means gamepad navigation still functions once `SelectedObject` is set
  by script, but the engine no longer auto-picks an initial selection.
- Calling `GuiService:Select(selectionParent)` makes the engine search all selectable,
  visible, on-screen descendants of `selectionParent` and set `SelectedObject` to the
  one with the smallest `SelectionOrder`.
- `GuiService.SelectionGained`/`SelectionLost` events fire on selection change.

⚠ **Not confirmed anywhere in this pass:** whether a `ScrollingFrame` autoscrolls
(`CanvasPosition`) to keep a `SelectedObject` descendant on-screen. This is the same
gap flagged in item 7 — it is exactly the open question the primitives audit's Q2/Q3
and the corrections addendum's item-9 spike already require settling with a live
Studio + physical-gamepad test, not something the current published docs state
outright. Do not implement Facet's modal/menu selection-bridge experiment (Phase 4 of
the primitives audit) assuming autoscroll-on-select is free — prove it or keep the
explicit scroll-into-view path as primary regardless.

Source: https://create.roblox.com/docs/reference/engine/classes/GuiService (fetched 2026-07-23)
Source: https://create.roblox.com/docs/reference/engine/classes/GuiService/SelectedObject (fetched 2026-07-23)
Source: https://create.roblox.com/docs/reference/engine/classes/GuiObject (fetched 2026-07-23)

---

## Summary of disagreements and open gaps for the mission owner

1. **⚠ Naming error in `roblox-native-primitives.md` (line 79):** `GuiState`'s idle
   member is `Idle`, not `None`. Fix any reference to `Enum.GuiState.None`.
2. **⚠ `UserGameSettings` does not carry accessibility preferences.**
   `PreferredTextSize` and `ReducedMotionEnabled` are `GuiService` properties. If any
   Facet doc or code assumes `UserGameSettings`, it is wrong and should be corrected
   to `GuiService`.
3. **⚠ `UIDragDetector` mouse/touch/gamepad input support is not directly stated** in
   either the reference page or the guide as currently published — the corrections
   addendum's claim is plausible but unconfirmed by these two docs; the required
   Studio spike still carries the real burden of proof.
4. **⚠ `ScrollingFrame` gamepad-autoscroll-to-selection is not documented** on the
   `ScrollingFrame` reference page. This is asserted as fact in the primitives audit's
   recommendation table but is, per the fetched docs, an assumption pending the
   Phase-2/Q1/Q2 Studio spike — treat it as unproven, exactly as the addendum's spike
   checklist already implies it should be.
5. **⚠ `ImageLabel.LoadingImageFailed` could not be confirmed to exist** under that
   name via two separate fetch attempts. Verify directly in Studio before building the
   `AsyncImage` transport (primitives-audit §9/Phase 6) around it.
6. **⚠ `Path2D.Transparency` was not found** in the fetched reference content at all —
   if the Sponsor ring/needle design calls for a fading path, this needs a Studio
   check; don't assume the property exists.
7. **⚠ `StyleQuery`'s exact enumerated list of built-in condition names** (whether it
   literally includes `preferredInput`, `aspectRatio`, `sizeRange` etc., and whether
   unknown names truly fail silently vs error) was **not** found spelled out on the
   `StyleQuery` reference page itself in this pass — corrections addendum §6's
   "closed set, silent-fail" framing is supported in spirit by the Style Editor guide's
   `@`-prefixed-globals description, but the complete name list still needs a direct
   Studio/`SetCondition` check.

**Confirmed, no disagreement (mission facts that check out cleanly against the
corrections addendum):**
- `GuiState` is read-only (item 3) — confirms addendum §5.
- `Path2D` has no fill/filled-path support and no mention in either doc (item 4) —
  confirms addendum §3's caution.
- `UIPageLayout` has `Animated`/`TouchInputEnabled`/`GamepadInputEnabled`/
  `ScrollWheelInputEnabled` plus `PageEnter`/`PageLeave`/`Stopped` events (item 6) —
  confirms addendum §4.
- `PreloadAsync` yields and has no cancellation API (item 11) — confirms addendum §12
  verbatim ("Yields," "no mechanism for cancelling").
- Styling Transitions is confirmed **in beta** ("Enable it through File ⟩ Beta
  Features ⟩ Styling Transitions"); core StyleSheets and the Style Editor are GA
  (item 13) — confirms addendum §7 exactly.
- `PreferredTextSize` is engine-applied with `TextScaled` opt-out,
  `UITextSizeConstraint` bounding, and `AutomaticSize` growth (item 14) — confirms
  addendum §9's entire premise, including the double-application risk Facet
  currently carries.
- `GetInsetArea(Enum.ScreenInsets): Rect` is the modern, single-call, four-edge-via-
  `Rect` API (item 8/9) — supports addendum §10's "choose one coordinate model"
  guidance; `GetGuiInset()` is the older `Tuple`-returning method to move away from.
- `SelectedObject` documented to reset to `nil` when its object goes offscreen (items
  8, 17) — directly backs addendum §11's warning that "Roblox may clear a selection
  that moves offscreen."

**File written:**
`/Users/josha/Library/CloudStorage/Dropbox/Documents/UntitledRacingGame/GameStudio/ui/Facet/docs/research/2026-07-23-native-adoption-docs-grounding.md`
