# SwiftUI ↔ LuauUI capability audit and selected control inventory

> **2026-07-22 Roblox correction:** Read
> [`../plans/roblox-native-audit-corrections.md`](../plans/roblox-native-audit-corrections.md)
> with this inventory. Roblox has `UIDragDetector`, per-`GuiObject` touch gesture
> events, `Path2D`, and `UIPageLayout`; the older feasibility notes below must not
> be used to justify rebuilding those engine behaviors.

**Report only.** No library, example, or test code was changed to produce this document.

| | |
|---|---|
| LuauUI version | `0.5.0` (`src/init.luau:27`) |
| Audit date | 2026-07-22 validation of the 2026-07-21 source inventory |
| SwiftUI baseline | Shipping surface plus Apple's **June 2026 / Xcode 27** update. The original 69-item catalog remains stable for comparison; the newer capabilities are recorded in §0 instead of silently changing its denominator. |
| LuauUI baseline | source only — `src/blueprint.luau`, `src/init.luau`, `src/controls/`, `src/layout/solver.luau`, `src/render/`, `src/present/`, `src/client/`, plus `tests/conformance/controls_registry.luau` |

## 0. Validation update: what the first audit got right and what it missed

### Verdict

The source classifications in the original 69-item inventory are substantially
correct. In particular, it correctly identifies the weak ScrollView, limited Button,
missing adaptive-layout constructs, incomplete styling substitution, lack of an
assistive-technology bridge, strong logical focus, and unusually complete four-input
proofs for registered controls.

The original report should not be read as “LuauUI is N percent of SwiftUI.” It is a
selected control and container catalog. SwiftUI also supplies an authoring model,
environment propagation, accessibility behavior, previews, animation, presentation,
gesture composition, and diagnostics. Those cross-cutting qualities decide whether a
framework actually delivers “write the UI once,” especially when agents author the
code.

The updated work order is in
[`../plans/swiftui-parity-next.md`](../plans/swiftui-parity-next.md). The most important
new finding is not a missing control: it is that an unknown blueprint property is
accepted and can later be dropped silently. Strict public schemas and useful types
therefore precede expansion of the API.

### SwiftUI's June 2026 delta

Apple's current update adds capabilities that were not represented in the original
69 rows. They do not invalidate those rows, but they reveal additional framework
directions.

| Current SwiftUI direction | LuauUI today | Planning effect |
|---|---|---|
| General `reorderable()` containers | Table reorders; VirtualList virtualizes; there is no shared general container behavior | Merge virtualization, selection, reorder, payload/drop policy, and native drag acquisition into reusable collection services |
| Generalized `swipeActions` containers | Missing | Build one secondary-action model across touch swipe/long-press, mouse secondary click, keyboard, and gamepad |
| Gesture input-source selection, velocity, and richer gesture types | Native Roblox recognizers exist, but LuauUI has no normalized gesture value/composition layer | Adapt `UIDragDetector` and `GuiObject` events; keep normalization, arbitration, and headless drivers in LuauUI |
| `onKeyPress` | Semantic actions exist; arbitrary view-level key events are not a public construct | Keep standard controls semantic; expose raw/key-specific input only as an explicit advanced seam that cannot bypass responder ownership |
| Palette Picker | Missing | Treat it as a later presentation of the shared Picker selection model, not an independent state/control system |
| `sensoryFeedback` for haptic/audio intent | No public semantic feedback event surface | Add framework intent events; the game keeps asset, device, mixing, and haptic policy |
| Stronger focus interactions and focus-effect control | Logical focus is a LuauUI strength; the engine-selection bridge is intentionally unproven | Keep logical focus authoritative; test an opt-in modal/menu bridge only, never passive HUD selection |
| New Preview macro and preview traits | LuauUI has deterministic render dumps, an edit preview, and device profiles | Make the profile matrix and runnable fixtures the normal authoring loop; add docs/example drift and real-device capture |
| Spatial event location, selection ray, device pose, handedness, phase, and target | No spatial event or SurfaceGui target contract | Preserve an extensible event/environment seam now; claim VR only after physical target, comfort, focus, and performance proof |

Sources: [SwiftUI updates](https://developer.apple.com/documentation/updates/swiftui),
[SwiftUI gestures](https://developer.apple.com/documentation/swiftui/gestures),
[SwiftUI focus](https://developer.apple.com/documentation/swiftui/focus), and
[SwiftUI spatial selection ray](https://developer.apple.com/documentation/swiftui/spatialeventcollection/event/selectionray).

### Product-quality comparison

| Axis | LuauUI strength | Material gap |
|---|---|---|
| Declarative state and identity | Signals/memos, keyed `ForEach`, ownership scopes, deterministic lifecycle, server-state adapters | Public constructor types are weak; property validity and render authority are not one enforced schema |
| Cross-platform input | Semantic actions, live interaction-class set, hot-switch contracts, four-input proof registry, ten-foot focus, desktop Tab/Shift+Tab traversal + Space activation + focused-axis Adjust (Step 8) | Gesture and secondary-action behavior is still control-specific; no Home/End/PageUp/PageDown or type-ahead; `Escape` is engine-reserved so keyboard modal exit is screen-provided; physical device proof is open |
| Layout | Deterministic solver, stack/grid/anchor primitives, device profiles, safe-area facts | ScrollView is not a real scroll container; no `ViewThatFits`, adaptive stack, layout priority, or custom-layout contract |
| Controls | Deep TextInput, Table, VirtualList, PopupButton, Toggle, Chip | Button is too limited; Slider/Stepper and several common display/selection controls are absent or only recipes |
| Styling | Token validation plus strong native StyleSheet opportunity | Current adapter hard-codes control chrome; reactive style hints can be dropped; Style Editor handoff is not implemented yet |
| Accessibility and inclusion | Reduced-motion/transparency facts, contrast checks, focus, target declarations, exact/conservative text metrics, adaptive composition, and an exact-once paint/measure split | No semantic tree/announcement bridge; the live preferred-text adapter still uses guessed offsets and misses live preference changes; full-surface/Sponsor proof at `Largest` is planned in Step 8.5 |
| Agentic development | Scaffolds, failing test stubs, conformance registry, deterministic dumps, gates, fuzz/fault/soak tools, extension playbooks | Unknown props can fail silently; public `any` boundaries and stale guide samples weaken autocomplete and diagnostics; some primitives bypass registration |
| Performance | Named production-shaped scenes, p50/p95/p99 headless timing, regression budgets, heap/reactive counters | Fake target only; device slots remain empty; no authoritative phone/console frame, Instance, connection, memory, or latency result |
| Future spatial UI | Existing BillboardGui target and semantic action architecture | No SurfaceGui target, spatial environment facts/event values, ray/pose input, VR focus/hover/occlusion contract, or hardware proof |

### Performance finding

LuauUI is not “untested for performance,” but it is not device-performance-proven.
`tools/perf.sh` already exercises named mounted scenes across geometry/input profiles,
records p50/p95/p99, and enforces versioned headless budgets. `tools/bench.sh` also
tracks the reactive core and mounted slices. Both label the measurements as trend
screening, and `artifacts/phase-4/perf.json` records `deviceRun = false` with an empty
device-measurement slot. The next work should extend this system with real Studio and
device captures rather than create a parallel benchmark framework.

### Spatial/VR finding

Future VR belongs in the architecture now but not in the support claim. Roblox
already exposes VR device state, head/hand frames, a GUI input frame, and laser
pointer policy through `VRService`; screen UI can also render in world containers.
LuauUI should make its environment, semantic events, focus, and render-target
contracts extensible to a spatial pointer or world surface. Physical VR testing must
still prove target size, occlusion, hover/focus, comfort, cancellation, and frame
budget before the framework says a screen “runs properly” in VR.

Sources: [Roblox `VRService`](https://create.roblox.com/docs/reference/engine/classes/VRService),
[Roblox VR guidance](https://create.roblox.com/docs/production/publishing/vr-guidelines),
and [Roblox UI render spaces](https://create.roblox.com/docs/ui).

**Verification commands** (all run for this report; output in [§8](#8-verification-run-for-this-report)):

```bash
cd GameStudio/ui/LuauUI
./run-tests.sh                                   # 595 passed
lune run tools/lune/check_registration_cli       # docs-drift + conformance checker
lune run tools/lune/check_boundary               # client/server require-graph
lune run tests/conformance/corpus_cli            # a11y + l10n corpus
```

---

## 1. Status scale

| Status | Means |
|---|---|
| **Available** | A first-class equivalent exists, is exported, and its conformance tests pass. |
| **Partial** | It exists, but with named behavior gaps that a consumer will hit. Per `ui_todo.md:3-13`, **anything that works on only some input classes is Partial at best** — "a control that only works with a mouse is an unfinished control". |
| **Composable** | Not shipped as a construct, but buildable today from the existing public surface with no framework change. The recipe is named in the detail section. |

**Caveat on "public surface".** Three recipes below (Slider §3.3, Menu §3.16, the input half of `.toolbar` §4.8) call `contribution.attach`. That module — `src/input/contribution.luau` — is **documented in the API reference** ("Contribution bundle", `docs/reference/api.md:349-373`) but is **not on the `LuauUI` export table** (`src/init.luau:24-75`). A consumer must require it directly. Those recipes need no framework *change*, so they stay **Composable**, but the packaging wart is real and is called out at each one.
| **Missing** | No construct and no honest recipe. A Roblox-engine feasibility note is given. |

Two anti-inflation rules were applied throughout:

1. A control whose *reachability* is proven on four inputs is still **Partial** if its *paradigm* idiom is incomplete (the distinction ADR-0016 exists to enforce — `docs/adr/ADR-0016-three-axes-contract.md:15-18`).
2. **Nothing** in LuauUI has been confirmed on physical hardware. The gate cell `physical-device-confirmation` reports `FAIL_ENVIRONMENT` and has never closed (`ui_todo.md:166-167`). Every four-input claim below rests on headless Lune + Studio MCP drives.

Engine-feasibility verdicts use three grades: **engine gives it to us** (the platform supplies the primitive; this is a library gap), **engine makes it hard** (possible but requires a spike or workaround), **engine makes it impossible** (no reachable API). Engine facts are cited from in-repo lessons/ADRs where they exist; anything else is flagged *engine claim — unverified in repo*.

---

## 2. Summary table

**Selected 69-item catalog · Available 2 · Partial 27 · Composable 18 · Missing 22.**

### A. Controls (24)

| SwiftUI item | LuauUI equivalent | Status |
|---|---|---|
| `Button` | `UI.Button` — `src/blueprint.luau:165` | **Partial** |
| `Toggle` | `UI.Toggle` — `src/blueprint.luau:169` | **Partial** |
| `Slider` | — (recipe: `Anchor` + `Box` track/fill + `Grip` thumb + `contribution.attach`) | **Composable** |
| `Stepper` | — (recipe: `HStack{Button −, Text, Button +}`) | **Composable** |
| `TextField` | `UI.TextField` + `LuauUI.newTextInput` — `src/controls/text_input.luau:96` | **Partial** |
| `SecureField` | — | **Missing** |
| `TextEditor` | — | **Missing** |
| `.searchable` / search field | — (recipe: `newTextInput{clearButton}` + filter memo; shipped in example 02) | **Composable** |
| `Picker` `.menu` | `LuauUI.newPopupButton` — `src/controls/popup_button.luau:36` | **Partial** |
| `Picker` `.segmented` | — (recipe: `HStack` of `Button{selected}`) | **Composable** |
| `Picker` `.inline` | — (recipe: `VStack` of `Button{selected}`) | **Composable** |
| `Picker` `.wheel` | — | **Missing** |
| `Picker` `.navigationLink` | — | **Missing** |
| `Picker` `.palette` | — | **Missing** |
| `DatePicker` | — | **Missing** |
| `ColorPicker` | — | **Missing** |
| `ProgressView` (determinate) | — (recipe: `ZStack{Box control, Box accent width=memo}`) | **Composable** |
| `ProgressView` (indeterminate) | — | **Missing** |
| `Gauge` | — | **Missing** |
| `Label` (title + icon) | — (recipe: `HStack{Image, Text}`; tappable needs a `ZStack` wrap) | **Composable** |
| `Link` | — | **Missing** |
| `Menu` (action menu) | — (recipe: `When` + `contribution.attach{outsideDismiss, transientScope}`) | **Composable** |
| `.contextMenu` | — | **Missing** |
| `ShareLink` | — | **Missing** |

### B. Containers & layout (22)

| SwiftUI item | LuauUI equivalent | Status |
|---|---|---|
| `HStack` | `UI.HStack` — `src/blueprint.luau:134`; solver `src/layout/solver.luau:192-215,428-498` | **Partial** |
| `VStack` | `UI.VStack` — `src/blueprint.luau:131`; same solver path | **Partial** |
| `ZStack` | `UI.ZStack` — `src/blueprint.luau:137`; solver `:150-159,342-360` | **Partial** |
| `Grid` | `UI.Grid` — `src/blueprint.luau:152`; solver `:161-190,384-426` | **Partial** |
| `GridRow` | — | **Missing** |
| `LazyVGrid` | `UI.Grid` (`minColumnWidth` ≈ `.adaptive(minimum:)`) | **Partial** |
| `LazyHGrid` | — | **Missing** |
| `LazyVStack` | `LuauUI.newVirtualList` — `src/controls/virtual_list.luau:50` | **Partial** |
| `LazyHStack` | — | **Missing** |
| `List` | `LuauUI.newTable` with `header = false` (ADR-0007 "headerless mode") | **Partial** |
| `Table` | `LuauUI.newTable` — `src/controls/table.luau:82` (ADR-0007, ADR-0010) | **Partial** |
| `ScrollView` | `UI.ScrollView` — `src/blueprint.luau:140`; solver `:135-148,302-340` | **Partial** |
| `Form` | — (recipe: `ScrollView` → `VStack` → `HStack{Text, Spacer(fill), control}`) | **Composable** |
| `GroupBox` | — (recipe: `VStack{surface}` + `UI.corners` / `UI.shadow`) | **Composable** |
| `DisclosureGroup` | — (recipe: `Button` flipping a signal + `UI.When`) | **Composable** |
| `TabView` | — (recipe: `HStack` of `Button{selected}` + `UI.When` per tab) | **Composable** |
| `NavigationStack` | `presenter.presentModal` / `.back()` — `src/present/presenter.luau:1464-1472` | **Partial** |
| `NavigationSplitView` | — | **Missing** |
| `.toolbar` | — (recipe: `Anchor` child + a named focus group; Table does exactly this) | **Composable** |
| `Divider` | — (recipe: `UI.Box{surface, width=fill, height=1}`) | **Composable** |
| `Spacer` | `UI.Spacer` — `src/blueprint.luau:143` | **Partial** |
| `GeometryReader` | `controller.rectOf` / `opts.onGeometry` / contribution `syncGeometry` | **Partial** |

### C. Presentation (5)

| SwiftUI item | LuauUI equivalent | Status |
|---|---|---|
| `.sheet` | `presenter.presentModal` — `src/present/presenter.luau:1411` | **Partial** |
| `.fullScreenCover` | — (recipe: `presentModal` + `rootPolicy="edgeToEdge"` + painted full-bleed root) | **Composable** |
| `.alert` | — (recipe: `presentModal` + `outsideTapCancel=false`; example 04) | **Composable** |
| `.confirmationDialog` | — (recipe: `presentModal` of a `VStack` of action Buttons) | **Composable** |
| `.popover` | `newPopupButton` + the transient-popup seam — `presenter.luau:629-726` | **Partial** |

### D. Images & async (2)

| SwiftUI item | LuauUI equivalent | Status |
|---|---|---|
| `Image` | `UI.Image` — `src/blueprint.luau:162` | **Partial** |
| `AsyncImage` | — (recipe: `newResourceProvider` + a memo on `handle.value`; example 07) | **Composable** |

### E. Gestures (7)

| SwiftUI item | LuauUI equivalent | Status |
|---|---|---|
| `.onTapGesture` | presenter activate dispatch — `presenter.luau:755-813` | **Partial** |
| `LongPressGesture` | — | **Missing** |
| `DragGesture` | `UI.Grip` + `adapter.setPointerHandlers` (ADR-0008) | **Partial** |
| `MagnifyGesture` | — | **Missing** |
| `RotateGesture` | — | **Missing** |
| `.simultaneousGesture` / `.highPriorityGesture` / `.sequenced` | one-bit claim/decline — `renderer.luau:249-258` | **Partial** |
| `@GestureState` | — | **Missing** |

### F. Cross-cutting modifiers & system services (9)

| SwiftUI item | LuauUI equivalent | Status |
|---|---|---|
| `ForEach` (keyed) | `UI.ForEach` — `src/blueprint.luau:188` | **Available** |
| `Group` (modifier fan-out) | `UI.styleGroup` — `src/blueprint.luau:223` | **Partial** |
| `.shadow` | `UI.shadow` — `src/blueprint.luau:211` | **Partial** |
| `.cornerRadius` / `.clipShape` | `UI.corners` — `src/blueprint.luau:217` | **Partial** |
| `ButtonStyle` / `ToggleStyle` / `*Style` protocols | — | **Missing** |
| `.accessibilityLabel` / `.accessibilityValue` / VoiceOver | — | **Missing** |
| `@Environment(\.horizontalSizeClass)` | `env:get("sizeClass")` — `src/env/environment.luau:70` | **Partial** |
| `@FocusState` / `.focusable` / `.focusSection` | `LuauUI.newFocusGraph` — `src/focus/focus_graph.luau` | **Available** |
| `.disabled` | per-control `enabled` prop | **Partial** |

---

## 3. Controls — detail

### 3.1 Button — **Partial**

`UI.Button{ id?, label (required), enabled?, focusable?, selected?, surface?, onActivate? }` (`src/blueprint.luau:165`); contract `src/controls/contract.luau:29-34`; renders as a `TextButton` (`src/client/screen_target.luau:28`).

**Input coverage (§0): complete and enforced.** All four classes cite verbatim spec cases in `tests/conformance/controls_registry.luau:341-365` — pointer tap, touch finger tap, keyboard Return, gamepad ButtonA (`tests/auto_input.spec.luau:51,58,67,74`), plus paradigm proofs: a pointer-live renderer enables a hover layer and the default style defines a distinct hover role; focus visuals differ between a Large and a Medium display.

**Gaps that matter:**
- **No `ButtonStyle` protocol.** A consumer cannot restyle a Button's rendering; the chrome is imperative adapter code (`screen_target.luau:289` corner, `:296-310` fills). See [§7.2](#72-styling).
- **No `ButtonRole`.** Nothing in `src/` mentions `destructive`/`cancel` — grep finds only comments about "non-destructive dismissal". Alerts and menus therefore have no role tinting or role-driven ordering.
- **No content slot.** `label` is a `string`, and `Button` is not in `CONTAINER` (`blueprint.luau:89-97`), so it takes no children. Icon+label buttons need the `ZStack{Button(label=""), HStack{Image,Text}}` hack — which is what the adapter itself does internally for the Toggle (`screen_target.luau:373-410`).
- **The 44px hit floor is declared but not enforced where it matters.** `contract.luau:7` says "the renderer/ScreenTarget honors `minHitSize`", but `minHitSize` appears nowhere in `src/render/` or `src/client/` — it is never applied to layout or hit-testing. The only real layout floor is the one `Chip` declares for itself (`src/controls/chip.luau:53-55`). The floor *is* honored in exactly one place — the presenter's modal-dismissal Zone-A geometry inflates each focusable to a 44px rect (`presenter.luau:103`, `:115-119`) — but that is a dismiss decision, not a control's hit rect.
- **Dynamic-Type-like scaling misses default text.** `typographyScale` is applied at measure and paint, but only to nodes carrying an explicit `textSize`; a plain Button's `TextSize = 16` is hardcoded (`screen_target.luau:488`). Carried as a known limitation in `ADR-0016:103-105`.

**Adaptation (good):** hover is enabled only when the pointer class is live, and is applied retroactively to existing nodes when a mouse arrives mid-session (`renderer.luau:233-237`, `:552-565`); ten-foot focus strengthening (ring 2→4 px, 1.05× scale) fires on `displaySize == "Large"` (`src/tokens/default_style.luau:53-54`).

### 3.2 Toggle — **Partial**

`UI.Toggle{ id?, label (required), value?, enabled?, onActivate? }` (`blueprint.luau:169`). Activate auto-flips a settable `value` signal with zero consumer wiring (ADR-0013). Four-input proven (`controls_registry.luau:370-391`).

**Gaps:** switch presentation only — no `.checkbox` (SwiftUI macOS-only) or `.button` style, and no `ToggleStyle` seam to add one; the 44×24 track and 20px knob are hardcoded in the adapter (`screen_target.luau:373-410`), not token-derived; no mixed/indeterminate state (SwiftUI's `Toggle(sources:isOn:)`); label `TextSize = 16` hardcoded (`screen_target.luau:384`). SwiftUI's `.automatic` resolution (checkbox on macOS, switch elsewhere) has no analogue — LuauUI renders one visual everywhere.

### 3.3 Slider — **Composable**

No control exists; the only mention of "slider" anywhere in `src/` is a forward-looking comment at `presenter.luau:931` (and one of "steppers" at `contribution.luau:32`). It is the first item on the deferred ledger (`ui_todo.md:143-147`, "ValueAdjuster / Slider / Stepper").

**Recipe that works today:** `UI.Anchor` root → `UI.Box{surface="control"}` track + `UI.Box{surface="accent", width=<memo on value>}` fill + `UI.Grip{focusable=true, onPointerDown/Move/Up/Cancel}` thumb, then `contribution.attach(root, { adjustTargets, handleAdjust, focusGroups })` — see the [§1 caveat](#1-status-scale): `contribution` is a documented but non-exported module. This is precisely Table's column-resize implementation (`table.luau:711-756` for the Grip drag, `:1325` for `handleAdjust`), and it inherits Table's proven four-input story: pointer and touch drag the Grip, keyboard gets Comma/Period, gamepad gets L1/R1 — bound *dynamically*, only while the focused path is a declared adjust target (`presenter.luau:977-1025`), so a bare screen never shadows gameplay bumper keys.

**Caveat that keeps this from being trivial:** `Adjust` is a `Direction1D` action delivering **discrete ±1 steps only** — the presenter rejects any other magnitude outright (`presenter.luau:1315-1317`) and the axis latch fires one step per threshold crossing (`src/input/actions.luau:137-154`). A thumbstick cannot drive a slider proportionally. SwiftUI has the same discreteness on arrow keys, so this is a parity gap only against analog-stick expectations — but it is why the deferred item is framed as a *ValueAdjuster*, not a slider.

### 3.4 Stepper — **Composable**

Same deferral. The shipped idiom is literally the recipe: `examples/gallery/examples/03_settings_sync.luau:121-129` builds volume as `HStack{Button "–", Text, Button "+"}`, and each Button auto-composes its own four-input story (ADR-0013), so the composite is already device-complete. Missing versus SwiftUI: no `in:` range clamp with auto-disable at the bounds, no repeat-on-hold (there is no timing primitive anywhere in `src/` — see [§6.2](#62-longpressgesture--missing)), no `format:` overload.

### 3.5 TextField — **Partial** (the deepest control in the library)

Leaf `UI.TextField` (`blueprint.luau:177`) → engine `TextBox` (`screen_target.luau:31`); composite `LuauUI.newTextInput` (`src/controls/text_input.luau:96`).

**Input coverage (§0): the strongest evidence set in the repo.** `controls_registry.luau:259-294` cites four reachability cases *and* four hot-switch cases: gamepad-arrives-mid-edit CARRIES; touch-leaves-with-hardware-keyboard CARRIES; the on-screen-keyboard surface leaving ends the edit via commit (no wedge, no lost text); the sink context comes down and navigation resumes. The mechanism is a priority-10000 sinking `InputContext` that swallows the navigation vocabulary while editing, deliberately leaving Activate un-sunk so re-entry keeps working (`text_input.luau:193-217`).

**Gaps that matter:**
- **`keyboardType` is declared intent only.** `TextBox.TextInputType` is CoreScript-locked, so the adapter detects capability and degrades (`screen_target.luau:1033-1046`; `ui_todo.md:30-33`). A numeric field still summons full QWERTY on touch — a real behavior gap where SwiftUI's `keyboardType` genuinely changes the keyboard.
- **`submitLabel` is never applied.** `ReturnKeyType` is `[Hidden, NotScriptable]` (`text_input.luau:48-52`); the declaration is carried as data and nothing consumes it.
- **No `axis: .vertical`, no selection binding, no `TextField(value:format:)` deferred-commit-with-revert contract.** LuauUI's `onChange`/`onCommit` split covers SwiftUI's continuous vs. submit modes, but not format-parse-revert.
- **Physical-device unconfirmed** — touch keyboard occlusion and gamepad edit-mode are the standing rider (`ui_todo.md:38-39`).

**Strengths worth recording:** keyboard-occlusion keep-visible is real and reactive (reads `env.keyboardOcclusionRect`, publishes a presentation-authority transform with no remount, `text_input.luau:162-179`); `maxLength` clamps at the value-model boundary in Unicode scalars and rejects malformed UTF-8 outright; `validate` is contractually required to be idempotent because the engine echoes programmatic `.Text` writes back.

### 3.6 SecureField — **Missing**

No masking prop exists on `TextField` (`blueprint.luau:39-47`), in `BINDING_PROPS` (`renderer.luau:23-36`), or in the adapter's `setProp`.

**Engine feasibility: engine makes it hard.** No in-repo lesson or research file establishes a public secure-entry mode on `TextBox` (*engine claim — unverified in repo*). Hand-masking in the value model is unsound: every accepted edit round-trips through `applyProposed` writing the visible value (`text_input.luau:225-245`), while caret and selection are engine-owned, so backspacing a masked string misbehaves. A correct implementation needs either an engine property or a shadow-value model with engine-side caret control that the current `setTextInputHandlers` seam does not expose.

### 3.7 TextEditor — **Missing**

**Engine feasibility: engine makes it hard, and the repo says so explicitly.** `screen_target.luau:512-519` hardcodes `MultiLine = false` and `TextWrapped = false` with the reason inline: *"wrap-while-typing is engine-broken on mobile (devforum 1014598), so multi-line stays unshipped/ungated."* This is an in-repo engine fact, not an omission — multi-line was deliberately declined rather than shipped broken on the platform LuauUI most needs to support.

### 3.8 `.searchable` / search field — **Composable**

Already shipped as a pattern, not a construct: example 02 gained an iTunes-style filter-as-you-type field (`ui_todo.md:34-36`). Recipe: `LuauUI.newTextInput{ value, clearButton = true, onChange }` (the in-field `×` exists only while the value is non-empty and not disabled) + a `core:memo` filtering the row source + `newTable`/`newVirtualList`. Inherits TextInput's full four-input story.

**Missing versus SwiftUI:** no `SearchFieldPlacement` vocabulary and therefore no placement fallback contract; no `.searchScopes` scope bar; no `.searchSuggestions`/`.searchCompletion`; no search-glyph slot (Button has no icon slot at all); `submitLabel = .search` is unwirable ([§3.5](#35-textfield--partial-the-deepest-control-in-the-library)).

### 3.9 Picker — **Partial** (`.menu` only)

`LuauUI.newPopupButton(LuauUI, core, { id?, options, value: Signal<string>, onChange? })` (`src/controls/popup_button.luau:36`). Closed it is one focusable trigger showing the selected label; activating opens a floating panel of option rows plus a Cancel row.

**Input coverage: four classes proven** (`controls_registry.luau:208-248`), and the transient-surface behavior is genuinely good: `handleCancel` closes on ButtonB (`popup_button.luau:222-228`); `outsideDismiss` gives tap-away plus a presenter-synthesized full-viewport catcher so a tap on empty space dismisses (`presenter.luau:629-726`); `transientScope` traps focus and restores it to the trigger from *every* close path — a registry proof explicitly asserts gamepad Navigate cannot escape the open panel.

**Gaps that matter:**
- **One style, everywhere.** SwiftUI's `.automatic` is a real container- and platform-sensitive resolver; PopupButton is always a floating panel. `.segmented`/`.inline`/ten-foot-subscreen resolution is on the deferred ledger (`ui_todo.md:154-156`).
- **Row geometry violates the contract floor.** `TRIGGER_HEIGHT = 40` and `ROW_HEIGHT = 36` (`popup_button.luau:33-34`) are hardcoded and both **below** the 44px `minHitSize` that Button/Toggle/TextField declare. Neither reads `sizeClass`, `displaySize`, nor `interactionClasses`.
- **No panel flip/clamp.** The panel is pinned `offsetY = TRIGGER_HEIGHT` below the trigger at `anchor = "topLeft"` (`popup_button.luau:158-168`) with no viewport-overflow handling.
- **Selection-only.** Option rows write the owner's `value` signal; there are no per-row action callbacks, icons, separators, or nesting (`popup_button.luau:21-24`).

**Other Picker styles.** `.segmented` is **Composable** (an `HStack` of Buttons carrying `selected`, which is a real paint/semantics prop at `blueprint.luau:31`; the HStack auto-derives a horizontal navigation group with zero opts). `.inline` is **Composable** (the same as a `VStack`). `.wheel` is **Missing** — it needs snap-scrolling, and `UI.ScrollView` neither scrolls nor offers a `scrollTargetBehavior` analogue ([§4.9](#49-scrollview--partial)); *engine gives it to us* (a Roblox `ScrollingFrame` has `CanvasPosition`), so this is a library gap. `.navigationLink` is **Missing** — there is no screen push/pop ([§4.15](#415-navigationstack--partial)). `.palette` is **Missing**.

### 3.10 DatePicker — **Missing**

Nothing date-, time-, or calendar-related exists in `src/`.

**Engine feasibility: engine gives it to us.** Nothing in Roblox blocks a calendar; `UI.Grid` would host the month view directly. The blockers are internal: no date type or formatting layer, and `env:get("locale")` (`src/env/environment.luau:28`) has **zero consumers anywhere in `src/`**, so a locale-aware `.graphical` picker has no substrate. The `.wheel` variant additionally needs the scroll fix.

### 3.11 ColorPicker — **Missing**

**Engine feasibility: engine gives it to us; the blocker is LuauUI's color model.** A discrete swatch grid composes trivially (`UI.Grid` + `UI.Button{surface}`). A real HSV picker cannot be built because **there is no per-node fill or content color prop**: `Box` takes only a named `surface` token (`blueprint.luau:73`), and `UI.Text{ color = … }` is a **dead prop** — `blueprint.luau:25` declares `color` while `authority.luau:36` declares `textColor` and `BINDING_PROPS` (`renderer.luau:23-36`) contains neither, so the value is silently dropped (and had it reached the adapter, `authority.assertWrite` would have errored for lack of a manifest entry). The single consumer-supplied color anywhere in the API is a shadow's (`src/tokens/styling.luau:60` → `screen_target.luau:154`) — and that one is mount-time-only ([§7.2](#72-styling)). There is also no gradient primitive and no 2-D continuous drag surface.

### 3.12 ProgressView — **Composable** (determinate) / **Missing** (indeterminate)

Determinate recipe: `UI.ZStack{ UI.Box{surface="control"}, UI.Box{surface="accent", width = core:memo(...)} }`. Non-interactive, so it needs no input contribution. The data half of a progress model already ships — `LuauUI.newResourceProvider` exposes a `pending | ready | failed` state readable (`src/async/resources.luau`).

Indeterminate is **Missing**: there is no animation or ticker primitive in blueprint space. All motion lives inside the adapter's `TweenService` state feedback (`screen_target.luau:315-323`, `:404-410`) and is not exposed. *Engine gives it to us* — this is purely a missing public seam.

### 3.13 Gauge — **Missing**

**Engine feasibility: native primitive exists, framework seam is missing.** A
linear-capacity gauge is the determinate ProgressView recipe. Roblox `Path2D` can
draw editable stroked arcs, and GuiObjects expose rotation, but LuauUI does not yet
surface either. Spike the real Sponsor rings/needle, then add a native-backed
`Path`/`Gauge` abstraction; retain rotated-half workarounds only if required.

### 3.14 Label (title + icon) — **Composable**, awkwardly

Recipe: `UI.HStack{ UI.Image{image}, UI.Text{text} }`. For a *tappable* icon+label you cannot nest — `Button` is not a container (`blueprint.luau:89-97`) — so the workaround is `UI.ZStack{ UI.Button{label=""}, UI.HStack{Image, Text} }`, structurally the same trick the adapter uses internally for the Toggle.

**Gaps:** no `LabelStyle` and therefore no environment-propagating `.iconOnly`/`.titleOnly` resolution — which in SwiftUI is what makes the same `Label` render icon-only in a toolbar and title+icon in a menu. `UI.Image` also exposes only `image`: no tint, no `ScaleType` control, no sizing mode ([§5.1](#51-image--partial)).

### 3.15 Link — **Missing**

No URL, browser, or navigation surface exists in `src/`.

**Engine feasibility: engine makes it impossible for the general case.** Roblox experiences cannot open arbitrary URLs from experience code; the nearest engine surfaces are protected/CoreScript-only (*engine claim — unverified in repo*: no lesson or research file in this repo establishes `GuiService:OpenBrowserWindow`'s permission level). A styled `UI.Button` with an `onActivate` is the only stand-in, and it cannot navigate anywhere.

### 3.16 Menu (action menu) — **Composable**

PopupButton models a *selecting* menu; SwiftUI `Menu` dispatches *actions*. The generalization is directly supported and documented: `contribution.luau:41` names "an open PopupButton, **a menu**" as the intended case for the transient-surface seams. Recipe: `UI.When` on an `open` signal + `contribution.attach(root, { handleActivate, handleCancel, outsideDismiss, transientScope })` (the [§1 caveat](#1-status-scale) applies — `contribution` is documented but not exported), routing each row path to a command instead of `select()`. That yields tap-away dismissal, ButtonB close, and focus trap-and-restore for free.

**Gaps:** no submenus, no dividers, no destructive roles, no `primaryAction:` split behavior, no icons in rows.

### 3.17 `.contextMenu` — **Missing**

On the deferred ledger as "Table row secondary actions … **no surface on any class today**" (`ui_todo.md:148-150`).

**Engine feasibility: engine gives it to us — this is a library gap, blocked on two triggers.**
1. **No long press.** There is no timing primitive in any interaction path in `src/` — no `os.clock`, `task.delay`, or `RunService` outside the Studio preview harness. Buildable today behind the existing `setPointerHandlers` seam (arm a delay on `down`, cancel on `up` or on movement past a threshold).
2. **No secondary button.** The adapter filters `InputBegan` to `MouseButton1` or `Touch` only (`screen_target.luau:674-680`); `MouseButton2` is never observed. The engine supplies it.

The *presentation* half already ships — the transient-panel + dismissal + focus-trap seam is general-purpose. Only the trigger is missing.

### 3.18 ShareLink — **Missing**

**Engine feasibility: engine makes it impossible as specified.** Roblox has no general share sheet; the closest is a game-invite prompt (*engine claim — unverified in repo* — no in-repo file establishes it). Not composable.

---

## 4. Containers & layout — detail

### 4.1 HStack / VStack — **Partial**

`solver.luau:428-498` is a single-pass weighted flexbox: measure every child at the inner box, sum non-`fill` children, split the remainder among `fill` children by weight with largest-remainder rounding, lay out. Cross-axis `align: start|center|end|stretch` and per-side `margin` are real.

**Where it diverges from SwiftUI's layout contract:**
- **No `layoutPriority`.** Grep finds no `priority` in `src/layout/`. When a stack is over-committed, `remaining = math.max(0, availMain)` (`solver.luau:451`) — fills collapse to zero and the stack overflows; no child is asked to shrink. SwiftUI's whole "which Text truncates" story has no analogue.
- **No proposal/response round-trip.** `measure` proposes `(maxW, maxH)` once and takes the answer; a child is never re-proposed a smaller size after siblings claim theirs.
- **No ideal-size pass / no `fixedSize()`.** `minMax` with `preferred` (`solver.luau:106-108`) is per-node, not negotiated.
- `gap`/`padding` take raw numbers, not token names — consumers reach into `LuauUI.tokens` by hand.

**What is better than SwiftUI:** an `HStack` (or `Grid`) with ≥2 focusables auto-derives real 2-D D-pad/arrow navigation groups with **zero** `present()` opts (`presenter.luau:352-429`; `tests/auto_input_screens.spec.luau:41-60`). SwiftUI requires `.focusSection()` by hand.

### 4.2 ZStack — **Partial**

The core is good: per-child `alignH`/`alignV` with inheritance from the stack, `fill` children stretching to the stack, and deterministic paint order assigned by an explicit tree walk (`renderer.luau:419-437`, an ADR-0008 fix for a live-found nondeterminism). Tested at `tests/layout_v1.spec.luau:20-44`.

**Three named gaps keep it off Available:** no test asserts paint order for a *plain* ZStack (only for Table rows, `tests/table.spec.luau:217-231`); there is no `.zIndex` override; and its `PROP_DIRTY` entry is `{ surface, width, offsetX, offsetY }` only (`blueprint.luau:60`), so `height`, `padding`, `alignH` and `alignV` are accepted as static props and read by the solver but **can never be reactive** — a Signal passed to `alignV` silently never re-arranges.

### 4.3 Grid — **Partial**; GridRow — **Missing**

**`UI.Grid` is not SwiftUI's `Grid`.** SwiftUI sizes each column to the widest cell *across all rows*; LuauUI computes one uniform width for every column: `colW = max(0, floor((innerW - gap*(cols-1))/cols))` (`solver.luau:394`). Cells are pinned to the cell's top-left with `w = math.min(size.w, colW)` (`:415-420`) — a cell cannot be centered in its column. There is no `GridRow`, no `gridCellColumns` spanning, no per-cell alignment, and one `gap` serves both axes.

**Defect found in source:** the grid arrange branch (`solver.luau:384-426`) has **no `fill` special case**, unlike `zstack` (`:347-352`), `anchor` (`:366-371`) and `scroll` (`:326-332`). A `fill`-dimensioned child is arranged at `w = math.min(size.w, colW)` (`:415-420`), where `size` came from `measure` — and `fill` resolves at measure to the child's *content* size (`solver.luau:108-111`, "fill resolves at arrange; desired contribution is content"). So **a `fill` child in a Grid cell never expands to the cell**; it renders at its content size and any leftover column width is dead space. It collapses to literal 0×0 only when the child is a `Box` or `Spacer`, which measure 0×0 (`solver.luau:131-133`) — a `Button` maps to layout kind `text` (`renderer.luau:62-63`) and so keeps its label box. Either way, "make this cell's content fill its cell" — the most natural grid idiom in a game UI — does not work.

**Best honest reading:** `UI.Grid` ≈ `LazyVGrid` with `.fixed`/`.adaptive` columns, minus laziness and minus alignment. `minColumnWidth` (`solver.luau:388-392`) is a faithful `.adaptive(minimum:)`. Both are marked **Partial** above for that reason. `LazyHGrid` is **Missing** — Grid is row-major/vertical only, and *engine gives it to us*; this is a solver gap.

Note also that `Grid`, `Anchor`, `Grip`, `When`, `ForEach`, and `ErrorBoundary` are **absent from `src/controls/contract.luau`**, so they receive none of the dirty-map / dump-determinism / dispose-neutrality checks in `tests/controls_conformance.spec.luau`.

### 4.4 LazyVStack / LazyHStack

`LuauUI.newVirtualList` (`src/controls/virtual_list.luau:50`) is a correct, well-tested vertical virtualizer: bounded keyed window plus overscan, key-sequence equality so a same-window scroll is rect-writes-only, per-row `offsetY` memos owned by the item scope, focus-by-key with nearest-surviving-neighbor. Four-input proven with zero opts (`tests/virtual_list_input.spec.luau:88-219`); the viewport is a real engine clip host so partial rows crop.

**Partial because:** fixed `rowHeight` only, asserted at build (`virtual_list.luau:52-54`) with variable heights named a later gate; vertical only; no pinned section headers (SwiftUI's `pinnedViews:`); no fling/inertia; no scrollbar. `LazyHStack` is **Missing** for the same axis reason.

### 4.5 List — **Partial**

There is no `List`; ADR-0007 frames the headerless Table as the list, and the mode is real — `table.luau:767` gates the header block on `if spec.header ~= false then`.

| SwiftUI `List` feature | LuauUI |
|---|---|
| `.onMove` | ✅ `spec.onReorder(keys, toIndex)` with a specified post-removal slot contract, block drags of a whole selection, ghost chip + drop indicator |
| `EditButton` / `editMode` | ✅ **and better** — auto Edit/Done toggle keyed off the *live interaction-class set*, not `preferredInput` (`table.luau:143-150`; ADR-0015), with hot-switch CARRY/CANCEL semantics |
| `.onDelete` | ❌ no delete affordance |
| `.swipeActions` / `.contextMenu` | ❌ deferred (`ui_todo.md:148-150`) |
| Sections / headers / footers | ❌ |
| Hierarchical `children:` outline | ❌ (deferred in ADR-0007) |
| Selection | ✅ richer than SwiftUI's — see [§4.6](#46-table--partial) |

The structural gap the repo names itself: **Table reorders but does not virtualize; VirtualList virtualizes but does neither reorder nor select**, so "a long, reorderable list is unbuildable on any class today" (`ui_todo.md:152-153`).

### 4.6 Table — **Partial**

`LuauUI.newTable` (`src/controls/table.luau:82`) is the deepest construct in the library and is deliberately SwiftUI-shaped (ADR-0010): columns own their cells, width sugar mirrors `.width(min:ideal:max:)`, alignment mirrors `TableColumnAlignment`, and **`sortOrder` is owner-held — the table reports the requested order and never sorts your data**, exactly as SwiftUI does.

**Selection is richer than SwiftUI's**: `none | single | multi` with device-correct semantics chosen from the activate meta — touch = additive toggle, plain click = replace, ctrl/cmd = toggle, shift = range from anchor (`table.luau:1138-1146`) — selection follows focus on arrows/D-pad (the Apple model), and removed rows prune from both the selection and the range anchor.

**Input coverage: all four classes proven, auto-composed with zero `present()` opts** via the ADR-0013 contribution bundle (`table.luau:1571-1589`). Column resize is keyboard/gamepad-reachable through `adjustTargets`/`handleAdjust` with the Adjust keys bound only while a grip holds focus (`tests/paradigm_table.spec.luau:98-143`), and the hot-switch table proves CANCEL on capability loss mid-drag and CARRY of edit-mode, grabbed row, and pan offset across class flips.

**Gaps that matter:**
- **No compact adaptation.** SwiftUI's `Table` hides headers and shows only the first column in a compact horizontal size class. LuauUI has no such behavior — and cannot easily, because `sizeClass` has **zero consumers in `src/`** ([§7.4](#74-platform-adaptation)).
- **No virtualization**; column resize remounts every row (`table.luau:1471-1484` bumps a `widthsVersion` keyed into the row items) — a documented Phase-A cost, wrong at scale.
- **No Home/End/PageUp/PageDown and no type-ahead** — a 20-row table is one row at a time on keyboard (Tab/Shift+Tab traverse the header and rows since Step 8, but there is still no jump-to-edge or first-letter seek).
- **No secondary row actions, no `.onDelete`, no modifier-click multi-select** (⌘/⇧ is "Phase B", unshipped).

### 4.7 Form — **Composable**

Recipe (precedent: `examples/gallery/examples/03_settings_sync.luau:113-132`): `UI.ScrollView` → `UI.VStack{gap}` → per-row `UI.HStack{ UI.Text(label), UI.Spacer(fill), control }`. **Caveat that matters:** `UI.ScrollView` does not actually scroll ([§4.9](#49-scrollview--partial)), so a settings form taller than the viewport is currently a dead end unless the author re-implements Table's offset trick. No grouped-section styling and no `.formStyle` label/control column alignment.

### 4.8 GroupBox / DisclosureGroup / TabView / Toolbar / Divider — **Composable**

- **GroupBox:** `UI.VStack{ surface = "surfaceStrong", padding, children = { UI.Text(title), … } }`, optionally wrapped in `UI.corners` / `UI.shadow`. No label-slot or frame semantics.
- **DisclosureGroup:** `UI.Button` (chevron + label) flipping a `core:signal(false)`, plus `UI.When{ condition = expanded, thenView = … }`. `When` is layout-transparent (`renderer.luau:140-147`) so the disclosed content splices into the parent's flow, and the presenter re-derives focus order on every refresh so the focus map stays correct. Missing: no animation and no chevron primitive.
- **TabView:** tab bar = `UI.HStack` of `UI.Button{selected}` writing a signal; body = `UI.When` per tab. **Missing** in any recipe: swipe-between-pages (`.page` style), page indicators, the `.sidebarAdaptable` per-platform resolution, and any lazy tab-retention model.
- **Toolbar:** `UI.Anchor` child with an anchor/offset plus a named focus group — exactly what Table does for its Edit/Done affordance (root `Anchor` at `table.luau:876`, focus group `{ name = "toolbar", axis = "horizontal", entry = "first" }` at `:1297`). The layout half needs only exported primitives; contributing the focus group goes through the non-exported `contribution` module ([§1 caveat](#1-status-scale)). **Missing:** any placement vocabulary (`.principal`, `.confirmationAction`, `.bottomBar`), overflow-menu behavior, and topbar-inset integration.
- **Divider:** `UI.Box{ surface = "surfaceStrong", width = {type="fill",weight=1}, height = {type="fixed",px=1} }`. Note `box` measures 0×0 (`solver.luau:131-133`), so explicit dimensions are mandatory — SwiftUI's container-inferred orientation has no analogue.

### 4.9 ScrollView — **Partial**

`UI.ScrollView{ id?, axis?, padding?, children? }` (`blueprint.luau:140`). This is the weakest container in the library, and effectively an internal detail of `Table`.

1. **It does not scroll by itself.** Nothing in the solver or renderer applies a scroll offset for `kind == "scroll"`; `solver.luau:317-320` only annotates `contentSize` and flips `overflow = "scroll"`. There is no `scrollTop`/`contentOffset` prop. Every consumer re-implements scrolling: Table drives per-row `offsetY` plus its own wheel handler and touch pan; VirtualList does it again independently and **does not even use `UI.ScrollView`** (it uses an `Anchor`, `virtual_list.luau:285`).
2. **It does not clip by itself.** Clipping rides an unrelated `clipChildren` prop implemented as a reparenting clip host (`renderer.luau:311-314`, `screen_target.luau:442-470`). `Table` sets it explicitly (`table.luau:853`), as does `VirtualList` (`:292`) — but `clipChildren` and `onScrollWheel` **are not documented on `ScrollView` in `docs/reference/api.md:118-120`**, and `clipChildren` is not in `PROP_DIRTY` for `ScrollView` (`blueprint.luau:61` lists only `padding`), so it cannot be reactive.
3. **No engine `ScrollingFrame`.** `CLASS_TO_INSTANCE` (`screen_target.luau:26-33`) maps only Text/Button/Toggle/Image/TextField; everything else is a `Frame`. No `CanvasSize`, no scrollbar, no inertia.
4. **`axis = "x"` is unimplemented in arrange.** `axis` reaches four sites — the unbounded-axis proposal (`solver.luau:136-138`), the axis read at `:303`, the overflow test at `:318`, and cross-axis fill stretching at `:326-332` — but the two that decide horizontal layout ignore it: the arrange cursor advances **vertically** unconditionally (`y += size.h + gap`, `:337`), and `contentSize` sums heights and maxes widths regardless of axis (`:314-316`). So on `axis = "x"` children stack downward, and the overflow test compares a max-of-widths against `innerW` and therefore under-reports horizontal overflow. The layout fuzzer randomizes `axis = "x"` (`tests/lib/fuzzers/layout.luau:121`) but asserts only no-throw/finite/deterministic, so this passes CI silently.
5. **No virtualization** — every child is measured and arranged.

### 4.10 Spacer — **Partial**

`UI.Spacer{}` measures **0 × 0** (`solver.luau:131-133`) and has an empty dirty map (`blueprint.luau:72`). SwiftUI's `Spacer()` expands to consume available space by default; LuauUI's does not push anything apart until you write `UI.Spacer({ height = { type = "fill", weight = 1 } })` — which is exactly what the one real usage does (`examples/gallery/client/init.client.luau:140`). The name promises SwiftUI semantics and delivers a zero-size hole; this is a naming/defaults footgun, not a capability gap.

### 4.11 GeometryReader — **Partial**

The substrate is real: `controller.rectOf(path)` reads solved window-space rects (`renderer.luau:180-182`, exposed at `:582`); `presenter` re-feeds geometry after the initial render **and after every `refresh()`** (`presenter.luau:839-851`, `:1478-1479`); the contribution bundle carries `syncGeometry` so controls get it automatically; pointer handlers receive `rectOf` as their third argument, which is how all drag math works (ADR-0008). Real consumers: Table's scroll-into-view, TextInput's keyboard keep-visible.

**Why it is not a GeometryReader:** it is a **push callback, not a `Readable`** — nothing writes solved rects into the reactive graph, so `GeometryReader`-like use means hand-writing `onGeometry(function(rectOf) sig:set(rectOf(path)) end)` with no cycle guard. It is **path-keyed, not scoped** (you must know a node's full mounted path). The sharp footgun this entry used to name — `opts.onGeometry` and contribution `syncGeometry` being **mutually exclusive**, so passing `onGeometry` on a screen containing a Table silently disabled that Table's scroll-into-view and any TextInput's keep-visible — is **fixed** (2026-07-27): the feed is additive, and the framework's `syncGeometry` implementations are idempotent, so both run.

### 4.12 NavigationStack — **Partial**; NavigationSplitView — **Missing**

The presenter maintains a genuine stack: `presentModal` pushes, `back()` pops the top modal (`presenter.luau:1464-1472`), `depth()` reports it, each modal gets a focus trap and an IAS priority `+500`, and `dismiss(handle)` removes *that* handle's scope wherever it sits in the stack. But it is **modals only** — there is no push/pop of screens, no path binding, no navigation title or back-button chrome, and no transitions.

`NavigationSplitView` is **Missing**: you can hand-build `HStack{sidebar, detail}` with a `UI.When` swap, but there is no column-visibility model, no size-class-driven collapse to a stack, and no sidebar/detail focus-section semantics. *Engine gives it to us*; the adaptation input (`sizeClass`) even exists — it simply has no consumer.

---

## 5. Images & async — detail

### 5.1 Image — **Partial**

`UI.Image{ id?, image, width?, height? }` (`blueprint.luau:162`) → `ImageLabel` (`screen_target.luau:30`), and the only write is `instance.Image = tostring(value)`. There is no `resizable`, no `aspectRatio`/`scaledToFit`/`scaledToFill`, no `renderingMode`/template tinting, and no `ScaleType` control — `ScaleType` is set exactly once, as a side effect of the `surface = "badge"` style branch (`screen_target.luau:221-223`). SwiftUI's SF Symbols family (symbol rendering modes, `.imageScale`, symbol effects) has no analogue.

### 5.2 AsyncImage — **Composable**

`LuauUI.newResourceProvider` (`src/async/resources.luau`) is a good provider: bounded concurrency, LRU cache budget, generation-checked stale rejection so a late completion can never resurrect a released request, and scope-owned cancellation. But **nothing connects it to `UI.Image`** — no `AsyncImage` blueprint, no placeholder/failure props, no renderer awareness of load state.

Recipe (precedent `examples/gallery/examples/07_match3.luau:170-203`): `provider.acquire(scope, key)` then a `core:memo` reading `handle.value` with a pending-asset fallback bound to `UI.Image.image`. Two honest caveats: that example never consumes the `failed` state, so a failed load shows the pending placeholder forever; and the transport is consumer-owned by design — there is no Roblox transport in-repo (`grep` for `ContentProvider`/`PreloadAsync`: zero hits), so every test drains `pendingRequests()` and calls `complete()` by hand.

---

## 6. Gestures — detail

**LuauUI has no normalized gesture layer, although Roblox supplies important native
recognizers.** The current framework surface is one raw pointer stream with a single
capture slot. The future layer should adapt `UIDragDetector` and `GuiObject` touch
events into headlessly drivable value types, policy, composition, and arbitration.

### 6.1 `.onTapGesture` — **Partial**

Tap is activation, not a gesture: `adapter.setActivateHandler` → `presenter.onNodeTap` (`presenter.luau:755-813`), carrying meta `{ source, pointer = "mouse"|"touch"|"gamepad", x, y, shift, toggle }` read live from the device. It is available only on Button/Toggle/TextField (and `Grip` for raw pointer), **cannot be attached to arbitrary views**, and has no `count:` parameter — no double-tap.

### 6.2 LongPressGesture — **Missing**

There is no public framework timing/gesture primitive, but `GuiObject.TouchLongPress`
already performs native recognition. Adapt it and provide a keyboard/gamepad
secondary-action equivalent; do not begin with another touch timer.

### 6.3 DragGesture — **Partial**

No framework gesture object exists: no normalized translation, velocity, predicted
result, payload, or target. Each consumer re-implements policy. Roblox
`UIDragDetector` should own supported acquisition and cross-input motion; LuauUI
should own the drag-session value, drop legality, list behavior, and fallback.

The threshold is also a magic number rather than a token, and identical for touch and mouse — contradicting the repo's own research, which recommends ~20pt on touch (`docs/research/2026-07-21-swiftui-affordance-research.md` §8).

**Input coverage is nonetheless real at the intent level:** drag-as-reorder has a four-input story (pointer direct drag ∥ touch edit-grip ∥ keyboard grab-mode ∥ gamepad grab-mode), proven per class in `controls_registry.luau:127-152`, including CARRY/CANCEL semantics for a device arriving or leaving mid-gesture. The cost is that it is four hand-written code paths per control, which every new draggable control must rewrite.

### 6.4 MagnifyGesture / RotateGesture — **Missing**

**Engine feasibility: native per-object events exist.** `GuiObject.TouchPinch` and
`TouchRotate` respect the target object surface. A Studio spike still needs to pin
their exact delivery, cancellation, and composition behavior through LuauUI's flat
renderer, after which the adapter can normalize them for headless tests.

### 6.5 Gesture composition — **Partial**; `@GestureState` — **Missing**

The one arbitration mechanism is a **claim/decline verdict**: `handlers.down` may return `false` to dissolve the capture so a sibling zone under the same point can take it (`renderer.luau:249-258`; consumer at `table.luau:404-415`, the edit-gutter handoff). That is a crude one-bit `.highPriorityGesture`. There is no simultaneous delivery and no sequencing.

`@GestureState`'s defining property — auto-reset on gesture end — has no analogue. Every LuauUI drag holds plain locals nil'd by hand on each exit path (`table.luau:385-389`, `:453-457`, `:495-503`, `:565-570`), and ADR-0008's hardening log records both a shipped bug of exactly this class and a still-live benign one ("after an off-row release, the first later tap on the ORIGIN row is swallowed once"). *Engine gives it to us* — this is a framework-design gap.

One hard engine constraint any future recognizer must inherit: `GuiService.MenuOpened` aborts every live capture with reason `"interrupted"` (`screen_target.luau:643-650`), because Escape is core-reserved and uninterceptable (ADR-0008 engine truth D1).

---

## 7. Cross-cutting — detail

### 7.1 Presentation (`.sheet` / `.alert` / `.confirmationDialog` / `.popover` / `.fullScreenCover`)

`presenter.presentModal` (`presenter.luau:1411`) is deep where it counts: focus trap with scope restore on pop, a synthesized full-viewport scrim catcher so every tap hits something, and a genuinely well-specified **two-zone** dismissal model — Zone A is the modal's *painted* panel plus a 24px forgiveness ring and each focusable's 44px hit rect; Zone B dismisses (`presenter.luau:97-164`). `outsideTapCancel = false` is a true barrier (swallow, never clickthrough). Because only *painted* surface counts, `.fullScreenCover` falls out by construction: a visible fullscreen takeover has no outside (`tests/modal_dismissal.spec.luau:147-166`), while an invisible `fill` root cannot swallow taps.

**Gaps:** no detents, no drag indicator, no swipe-down (there is no pan recognizer to build it on), no sheet chrome or transitions; `scrim = "scrim" | "none"` is the only presentation-style knob. `.alert` and `.confirmationDialog` have **no role semantics at all** — no `destructive`/`cancel`, no system button reordering — and `presentModal`'s `outsideTapCancel` default of `true` is the *wrong* default for an alert (`docs/research/2026-07-21-modal-dismissal-spec.md:50`: alerts require an explicit press); the shipped example 04 does not override it. `.popover` has excellent light-dismiss and focus trap/restore but no anchoring, arrow edge, or flip-on-overflow, and is a control rather than a view modifier.

**Dismissal parity is not complete across the four inputs.** `presenter.luau:1030` binds Cancel to `ButtonB` **only**, with the reason inline: *"Escape is permanently bound to the Roblox CoreGui menu (engine VirtualInput refuses it outright; verified live 2026-07-19, D1) — keyboard/mouse close affordances are screen-provided."* That engine fact is real and ADR-0013 records it as a named justified exception. The consequence is nonetheless load-bearing for this report: **a keyboard-only user can dismiss a modal only by navigating to an in-blueprint close Button, and nothing in the framework requires a modal to have one.**

The presenter also applies **no `interactionClasses` or device-profile adaptation** — `interactionClasses` never appears in `presenter.luau`. Modal style, scrim behavior, and dismissal affordances are identical on phone, desktop, and the 10-foot console profile.

### 7.2 Styling

**There is no `*Style` protocol — this is the sharpest structural divergence from SwiftUI in the report.** SwiftUI's `ButtonStyle`/`ToggleStyle`/`PickerStyle`/`LabelStyle`/`ListStyle` are environment-propagating protocols that let a consumer replace a control's rendering while the system keeps the interaction (and `PrimitiveButtonStyle`/`MenuStyle` hand over the trigger too). LuauUI has none of that:

- The three shipped modifiers — `UI.shadow`, `UI.corners`, `UI.styleGroup` (`blueprint.luau:195-240`) — attach validated **data props** to a node. They cannot change what a control renders *as*. (`styleGroup` is explicitly SwiftUI `Group` semantics, but only for shadow and corners, hence **Partial**.)
- A control's rendering is imperative Roblox instance code inside `src/client/screen_target.luau` — the Button chrome, the Toggle track and knob, the tween, the focus ring, the disabled opacity. None of it is substitutable.
- What a consumer **can** do is swap the token *values* wholesale, once: `screen_target.new({ style = compiled })` (`screen_target.luau:49-50`) re-colors, re-spaces, re-radiuses and re-times every control at once. That is retheming, not restyling.
- The only wholesale-restyle escape hatch is writing an entirely new render target (`docs/extending/new-render-target.md`) — which replaces the adapter for the *whole tree*, with no per-control granularity. The one genuine per-instance rendering-injection seam in the library is Table's `cellFor`.

`UI.shadow` and `UI.corners` are strong in their validation: engine-true `UIShadow` parameter shapes with a build-time assertion that a shadow's `zIndex` is negative (`src/tokens/styling.luau:55-59`), a one-form-per-node rule for corners because mixing the uniform alias with per-corner values misbehaves in the engine (`styling.luau:100-103`), and capability-detected degradation at the adapter.

**But every style hint is mount-time-only, which is why both are rated Partial.** The style-authority loop that writes `{ surface, role, shadow, corners }` sits **inside the node-creation branch** of `ensureTree` — `renderer.luau:329-338`, reachable only when `handles[node.path] == nil` (`:202`). Both reactive write paths, `applyProps` (`:195`) and the paint/semantics dirty loop (`:505`), are gated on `BINDING_PROPS` (`:23-36`), which contains **none** of the four. Consequences a consumer will hit:

- A shadow or corner radius **cannot change after mount** — no state-driven elevation, where SwiftUI's `.shadow` is fully dynamic.
- `surface` and `role` are declared paint-dirty in `PROP_DIRTY` (e.g. `blueprint.luau:54,59,60,73`), so a Signal bound to them *schedules* an update that is then **silently dropped** at the `BINDING_PROPS` gate. This is the same dead-end class as the `Text.color` prop ([§3.11](#311-colorpicker--missing)), but harder to spot because the dirty accounting looks correct.
- The controls that *do* repaint reactively (Chip's pill, Table's row selection) do so through `selected`/`value`/`enabled` — real `BINDING_PROPS` — with the adapter deriving the fill. That path is sound; authoring a reactive `surface` is not.

`.cornerRadius` is additionally **Partial** because there is no `.clipShape` — corners are rectangles; there is no circle or arbitrary shape clip.

The token compiler enforces completeness plus a **4.5:1 contrast gate** on the three required surface/content pairs (`src/tokens/tokens.luau:66-70`), returning `nil` for the compiled style on failure, and the built-in Studio Neutral style asserts against its own gate at require time. Honest limit: the `extra` roles (`control`, `controlHover`, `controlPressed`, `contentSecondary`, `hairline`) are attached *after* compilation and are never contrast-checked. The style lint (jagged-corner caveat, ~100-shadow budget) is warnings-only, has **no CLI, and is wired into no gate**.

### 7.3 Accessibility — **Missing** (assistive technology), real (inclusive design)

Searched the whole repo for `screenreader`/`screen reader`/`voiceover`/`talkback`/`AccessibilityService`/`accessibilityLabel`/`aria`/`a11y`/`assistive`:

- **No screen-reader surface of any kind.** No semantic labeling API, no announcement channel, no role/trait vocabulary reaching any platform service. `GuiService.SelectedObject` is deliberately **not** driven — ADR-0014 defers it because "`SelectedObject` and IAS are parallel systems with undocumented linkage; driving it alongside LuauUI's own focus graph risks a double-drive."
- **The `semantics` dirty class is not an accessibility tree.** It is an invalidation-scheduling label handled **identically to `paint`** — `renderer.luau:490`: `if (entry.class == "paint" or entry.class == "semantics") …`. It means "a non-geometric prop write that does not re-solve layout". Any report inferring a semantics tree from the name would be wrong.
- **`ControlContract.accessibility` is prose.** `contract.luau:16` types it as "readable summary of behavior"; its single consumer (`tests/controls_conformance.spec.luau:60`) asserts only that the string is non-empty.

**What does exist is a substantial inclusive-design foundation, not yet a proven
assistive-technology one:** reduced-motion and transparency facts, contrast checks,
a declared hit-target floor, never-color-only guidance, exact/conservative text
measurement, `lineLimit`, `ViewThatFits`, adaptive composition, and scroll-to-visible.
The renderer now separates measurement reservation from paint: the live engine path
does not multiply the player's preference into `TextSize` a second time. The remaining
gap is still material. `src/client/roblox_env.luau` uses unmeasured generous offsets
for the four preference values and does not subscribe to `PreferredTextSize`; all
public surfaces and Sponsor View have not been proved at `Largest`, and permitted
truncation does not yet guarantee full-value access. Roadmap Step 8.5 owns the exact
native seam, reflow/overflow policy, mobile Sponsor proof, and performance bounds:
[`large-text-accessibility.md`](../plans/large-text-accessibility.md). BiDi/RTL and
assistive semantics remain separate gaps.

### 7.4 Platform adaptation

**Automatic, zero consumer code:** injected text-reserve modeling plus an authored
ten-foot scale (with live offset exactness still pending Step 8.5); overscan insetting of
the solved tree on a Large display; focus-ring strengthening; a density cap;
pointer-gated hover; four-input control wiring; derived navigation groups; modal
dismissal; reduced-motion/transparency facts; and keyboard-occlusion keep-visible.

**By hand:** **all layout branching.** `sizeClass` is derived (`src/env/environment.luau:70`) and consumed by **nothing in `src/`** — the only consumer in the entire repo is one gallery example hand-writing `if sizeClass == "compact" then 40 elseif … else 72`. This is the direct analogue of `@Environment(\.horizontalSizeClass)`, and LuauUI provides the signal and nothing else: **no `ViewThatFits`, no adaptive stack, no `Layout` protocol.** Hence the **Partial** rating. Also by hand: authoring a token schema, calling the style lint, setting `Workspace.PlayerScriptsUseInputActionSystem` (Properties-panel only — the framework detects, never sets), and including a visible close affordance in any modal.

Architectural ruling worth recording: **the console TV is not a fifth device class.** Ten-foot is keyed on `displaySize == "Large"`, independent of input class, so a keyboard *or* a pad on a TV both earn it (ADR-0016:122-124).

### 7.5 Focus — **Available**

`LuauUI.newFocusGraph` is a genuine first-class focus engine and the clearest place where LuauUI matches or beats SwiftUI. Flat scopes and **grouped** scopes with per-group `axis`, `order`, `wrap`, `containment`, `entry` (`first | restore | nearest`), and declared `exit` targets; `navigateDirection` moves within the active group along its axis and at edges wraps, follows a declared exit, or falls through; modal scopes trap and restore; structural churn keeps focus when it survives, else the nearest surviving neighbor preferring the follower; `removeScope(name)` so dismissing a *covered* screen removes its scope rather than the top one.

Mapped to SwiftUI: `@FocusState` ↔ `graph.focused` (a `Readable`) + `focusOn(path)`; `.focusSection()` ↔ `NavigationGroup`; `prefersDefaultFocus` ↔ `entry`. And unlike SwiftUI, the groups are **auto-derived from layout structure** with zero declaration (`presenter.luau:352-429`) — a `Grid` emits one group per row with `containment = true` and declared `up`/`down` exits between rows (`presenter.luau:376-392`), which is a stronger construct than `.focusSection()`: SwiftUI's focus engine still resolves direction from raw geometry, while these groups make the row topology explicit. Gamepad axis tolerance is real: D-pad-arriving-as-`Thumbstick1` is handled via a companion Direction2D action plus a client deadzone/re-center latch (`presenter.luau:945`, `roblox_input.luau:193-271`), with the honest rider that real analog delivery is unverifiable in Studio (`docs/lessons/synthetic-gamepad-unreachable.md`).

The **logical focus engine is Available, and the desktop keyboard conventions
landed on it in Step 8** ([`desktop-keyboard-navigation.md`](../plans/desktop-keyboard-navigation.md)),
as a second READING of the same graph rather than a second graph: `graph.traverse`
walks the active scope's own order (a flat scope's order, or every group's order
concatenated in group order), crossing group containment because leaving is what
Tab is for, honoring a scope-declared `traversalWrap`, trapping and restoring in a
modal, and reporting through the same keep-visible service a directional move uses.
`Space` joins `Return` as Activate, and a focused value control consumes the arrows
on the axis it declares (`adjustAxis`) while the other axis keeps navigating (with
the flat-scope caveat recorded in the API reference). All of
it is bound at the IAS adapter edge only while keyboard capability is live and the
surface's responder is engaged, so a passive HUD still binds nothing.

Mapped to SwiftUI: `.focusable()`'s Tab ordering ↔ the mounted focus order (SwiftUI
derives Tab order from view order; LuauUI derives it from the same order it derives
navigation from). What remains open is narrower and named below: no
Home/End/PageUp/PageDown, no type-ahead, and `Escape` is engine-reserved so a modal's
keyboard exit is still its focusable Close button.

### 7.6 `ForEach` — **Available**

`UI.ForEach{ items, key, row }` (`blueprint.luau:188`) is keyed structural diffing: add/remove/move only, surviving keys keep their mounted identity and scopes, duplicate keys are hard errors, and `row` receives the item's **ownership scope** so cells can own item-lifetime resources that die when the row leaves. That last property is better than SwiftUI's. Not covered: `.onMove`/`.onDelete` attachment (those live on Table) and range-based `ForEach`.

One caveat on the **Available** rating: like `Grid`, `Anchor`, `Grip`, `When` and `ErrorBoundary`, `ForEach` has **no entry in `src/controls/contract.luau:19-53`**, so it sits outside the conformance harness (dirty-map, dump-determinism, dispose-neutrality) that backs the "conformance tests pass" clause of §1. Its behavior is exercised throughout the green suite; it simply is not *registered*.

### 7.7 `.disabled` — **Partial**

`enabled` is a per-control prop on Button/Toggle/TextField riding the binding authority; a disabled control is excluded from focus and dimmed via `disabledContentOpacity`. It is **not** an environment-propagating modifier — you cannot disable a subtree with one call, as `.disabled(true)` does in SwiftUI.

---

## 8. Verification (run for this report)

```
$ ./run-tests.sh
595 passed

$ lune run tools/lune/check_registration_cli
check_registration: PASS (5 controls, 40 exports documented, 48 specs registered,
8 interactive controls prove four-input, 8 prove the paradigm axis)

$ lune run tools/lune/check_boundary
boundary: PASS (40 files) -> artifacts/boundary.json

$ lune run tests/conformance/corpus_cli
a11y-l10n-corpus: 15/15 passed -> artifacts/phase-4/a11y-l10n-corpus.json
```

**Docs-drift scope.** `tools/lune/check_registration.luau` is the drift checker and it reads **only `docs/reference/api.md`** (`:124`, `:154`, `:189`, `:199`) — it fails an undocumented export *and* a documented non-export. This file is therefore outside its scope: adding it neither satisfies nor breaks the check, and it does not substitute for the API reference. `tools/gate.sh input-paradigms` reports PASS with one `FAIL_ENVIRONMENT` cell, `physical-device-confirmation` — the standing, never-closed rider that **nothing here has been confirmed on physical hardware**.

---

## 9. Prioritized gap list

The first audit ranked only missing controls. The validated order below also asks
what most improves write-once behavior, agent reliability, and evidence quality.
Detailed scope and acceptance are in
[`../plans/swiftui-parity-next.md`](../plans/swiftui-parity-next.md).

1. **Strict, typed, self-explaining authoring.** Reject unknown properties; align
   schema, dirty class, property authority, adapter binding, types, documentation,
   examples, and conformance registration. A silent misspelling is more damaging
   than a missing convenience, especially in agent-authored code.
2. **A real native-backed ScrollView.** Give forms and long screens one scrolling,
   clipping, offset, keep-visible, and virtualization substrate instead of repeated
   Table/VirtualList implementations.
3. **A complete Button.** Add custom content, semantic label and role, consistent
   disabled behavior, native stylesheet states, and a genuinely enforced hit floor.
4. **Slider + Stepper over one value model.** Reuse focus-gated Adjust; start the live
   drag with `UIDragDetector`; keep the value/session model and tests pure.
5. **Automatic adaptive layout.** Add `ViewThatFits`-like selection and an adaptive
   stack so width, viewing distance, input, and preferred text can change layout
   without screen copies or device-name branches.
6. **Everyday layout vocabulary.** Fix Grid fill and Spacer defaults; add frame,
   padding, overlay, background, offset, aspect ratio, alignment, layout priority,
   and Divider with documented modifier order and authority.
7. **Common display and selection controls.** Package ProgressView, Label, segmented
   and inline Picker, DisclosureGroup, and later Path2D-backed Gauge/radial progress;
   fix PopupButton target sizing and adaptive presentation.
8. **General collection interaction.** Merge virtualization, selection, reorder, and
   drop; add native-backed drag sessions and one semantic secondary-action layer for
   swipe, long-press, mouse secondary click, keyboard, and gamepad.
9. **Semantics, presentation, and motion.** Make role/label/value/state/actions and
   feedback intent framework data; then add reusable navigation, safe alerts/dialogs,
   popovers/sheets/pages, and reduced-motion-aware style/value/structural animation.
10. **Performance/device proof and a spatial extension seam.** Extend the existing
    headless benchmark and preview systems with real phone/console captures. Define
    world-surface and spatial-event contracts now, but do not claim VR support until
    physical comfort, input, focus, occlusion, and frame-budget gates pass.

Native StyleSheets are not a separate custom-control priority: they are the runtime
paint system that investments 3–9 must consume. Sponsor Mode can pull its reusable
gaps forward, but its game-specific implementation remains the later parallel path.

---

## 10. Cross-check against the exported surface

The table below names every constructor in `src/blueprint.luau` and every export in
`src/init.luau`, and shows where each appears above. No LuauUI construct is omitted.

| Export | Appears as |
|---|---|
| `UI.Screen` | Presentation root; no distinct SwiftUI item (closest: the root of a `NavigationStack` scene) — §7.1 |
| `UI.VStack` / `UI.HStack` | §4.1 |
| `UI.ZStack` | §4.2 |
| `UI.ScrollView` | §4.9 |
| `UI.Grid` | §4.3 |
| `UI.Anchor` | Recipe substrate for `.toolbar`, `.popover`, Slider (§4.8, §3.3); no SwiftUI equivalent (closest: `.overlay(alignment:)`) |
| `UI.Spacer` | §4.10 |
| `UI.Box` | Recipe substrate for `Divider`, `ProgressView`, Slider track (§4.8, §3.12, §3.3) |
| `UI.Text` | Implicit in every row; the `color` prop is dead (§3.11) |
| `UI.Image` | §5.1 |
| `UI.Button` | §3.1 |
| `UI.Toggle` | §3.2 |
| `UI.TextField` | §3.5 |
| `UI.Grip` | The whole `DragGesture` surface — §6.3 |
| `UI.When` | Recipe substrate for `DisclosureGroup`, `TabView`, `Menu` (§4.8, §3.16); closest SwiftUI item is `if` in a ViewBuilder |
| `UI.ForEach` | §7.6 |
| `UI.ErrorBoundary` | No SwiftUI equivalent — SwiftUI has no view-level error boundary; LuauUI is ahead here |
| `UI.shadow` / `UI.corners` / `UI.styleGroup` | §7.2 |
| `LuauUI.newTable` | §4.5 (`List`), §4.6 (`Table`) |
| `LuauUI.newVirtualList` | §4.4 |
| `LuauUI.newPopupButton` | §3.9 (`Picker`), §3.16 (`Menu`), §7.1 (`.popover`) |
| `LuauUI.newTextInput` | §3.5, §3.8 |
| `LuauUI.newChip` | No SwiftUI item in the requested catalog; closest is `Toggle(.button)` / a filter pill. Four-input + paradigm proven (`controls_registry.luau:319-329`); it is the scaffold-born dry-run control |
| `LuauUI.newPresenter` | §7.1 |
| `LuauUI.newFocusGraph` | §7.5 |
| `LuauUI.newActionSystem` | §6, §7.1 — the semantic-action pipeline behind every Activate/Cancel/Adjust claim |
| `LuauUI.inputHint` | No SwiftUI equivalent — a reactive input-affordance label ("Enter" / "A" / "Tap"). LuauUI is ahead |
| `LuauUI.newResourceProvider` | §5.2 |
| `LuauUI.newEnvironment` | §7.4 (`@Environment` values) |
| `LuauUI.renderer` / `LuauUI.mount` / `LuauUI.newCore` | Infrastructure; `newCore` is the `@State`/`@Observable` analogue, `mount`+`renderer` the view-graph/render split |
| `LuauUI.replication` | No SwiftUI equivalent (client/server state adapters) |
| `LuauUI.tokens` | §7.2 |
| `LuauUI.VERSION` / `LuauUI.DEPRECATIONS` | Metadata; ledger currently empty |

Scope note: the table covers every **constructor** in `src/blueprint.luau` (21) and every **export** in `src/init.luau` (19). Two non-constructor public fields on the `UI` table are not listed because they are introspection helpers, not constructs: `blueprint.PROP_DIRTY` (`blueprint.luau:87`) and `blueprint.isReadable` (`:102`).

Three known misstatement risks, recorded rather than hidden:

1. `Grid`, `Anchor`, `Grip`, `When`, `ForEach`, and `ErrorBoundary` carry **no entry in `src/controls/contract.luau:19-53`**, so they sit outside the conformance harness that backs every other claim in this report.
2. `blueprint.make` (`blueprint.luau:104-125`) validates the *class* but not prop names, so an unknown prop is accepted, frozen into the blueprint, and — because both adapter write paths are gated on `BINDING_PROPS` (`renderer.luau:195`, `:505`) — **never written to the adapter at all**. A reactive unknown prop additionally defaults to the `paint` dirty class (`src/mount.luau:295`), so it schedules an update that is then dropped. `Text.color` is the canonical instance.
3. By the same gate, the style hints `surface`, `role`, `shadow` and `corners` are written **once, at node creation** (`renderer.luau:329-338`) and are not reactive even where `PROP_DIRTY` declares them paint-dirty — see [§7.2](#72-styling).

---

## 11. Resolution of §10's recorded risks, and the intentional differences (2026-07-24)

Roadmap Step 3's Milestone 0 closed all three risks §10 recorded. They are kept above as
the original finding; this section records what changed and, where LuauUI now
deliberately diverges from SwiftUI, why.

### The three risks

1. **Unregistered constructors — closed.** `Anchor`, `Grid`, `Grip`, `Path`, `When`,
   `ForEach` and `ErrorBoundary` now have entries in `src/controls/contract.luau` and rows
   in `tests/conformance/controls_registry.luau`. `Grip` — focusable and pointer-handling —
   proves all four input classes and the paradigm axis. The conformance kit mounts all 19
   classes for dump determinism and dispose neutrality.
2. **Unknown props accepted — closed.** `blueprint.make` validates every spec against
   `src/blueprint_schema.luau`. `Text.color` is diagnosed with its replacement rather than
   accepted (ADR-0011 "diagnosed-not-preserved"), as is `Text.font`, which reached the
   measure seam only and therefore made measured and painted bounds silently disagree.
3. **Style hints written once — closed.** `renderer.STYLE_PROPS` re-applies
   `surface`/`role`/`shadow`/`corners` on every reactive change. The same audit found
   `active` had the same defect (written by a creation-time branch only) and promoted it to
   a real binding prop. `tools/lune/check_prop_parity.luau` now fails when any property
   dirties `paint`/`semantics` without a path in the refresh loop, so this class of drift
   cannot return silently.

A fourth, unrecorded instance of the same class was found live: every enum-valued prop
accepted any string, so a typo produced a style tag no rule matched and the node painted
nothing. Two shipped controls were affected. See
`docs/lessons/enum-props-accept-any-string.md`.

### Styling status after the native-StyleSheet stage

The historical §7.2 findings remain useful evidence of what was wrong when audited,
but Step 2 has since moved runtime paint, named rules/tokens, native interaction
states, and Dark/Light palette swapping to Roblox StyleSheets. LuauUI therefore no
longer needs a SwiftUI-style `ButtonStyle` protocol merely to recolor or restate
standard control chrome.

That gap is now closed on the other axis too. Step 3.5 (ADR-0019) shipped a public,
versioned theme-package API: a theme owns its font families, type/spacing/control
metrics, solver-visible content insets and bounded asset-backed nine-slice chrome,
and a swap **does** remeasure the mounted tree — one transaction commits the native
derive and the frozen metric snapshot together, so the surface re-solves without a
remount. Controls speak semantic roles rather than literals, which is what lets a
screen restyle without being edited. A custom render-replacement protocol is
therefore still not the right solution here; see
[`../adr/ADR-0019-theme-packages.md`](../adr/ADR-0019-theme-packages.md) and the
walkthrough in [`../guide/09-custom-themes.md`](../guide/09-custom-themes.md).

### Intentional differences from SwiftUI

| Area | SwiftUI | LuauUI, and why |
|---|---|---|
| Invalid authoring | A misspelled modifier is a compile error | A **runtime** error at blueprint construction, naming the control, the property and the closest valid alternatives. Luau has no compile step in the shipping path, and the plan's priority rule 1 puts a silent wrong result above a missing convenience — so the check moved to the earliest boundary that exists. |
| Text colour and font | `.foregroundStyle(_:)` / `.font(_:)` take values | **Style authority only** (`role`, or the native StyleSheet). Roblox's `FontFace` and text colour are sheet-owned once native styling is on (`authority.nativeSheetOwned`), and a second authoring authority would silently defeat the sheet. Authored literals are diagnosed, not accepted. |
| Enumerated values | Type-checked enums | Closed string sets validated at construction. Kept as strings so blueprints stay plain frozen tables that serialise into deterministic dumps, but the value set is enforced. |
| `Spacer` | Expands along the enclosing stack's axis | Same behaviour, and it is now the **default** (it previously required an explicit `fill` dimension on the correct axis, where naming the wrong axis produced a silent zero). Outside a stack it stays inert — a `ZStack`/`Anchor` has no main axis to expand along. |
| `Grid` cells | Cells size to content and align in the cell | Same, **plus** a cell with a `fill` dimension occupies its column/row. Roblox layouts lean on fill far more than SwiftUI's grids do, and a fill cell collapsing to content rendered whole grids invisible. |
| Keep-visible | `ScrollViewReader` + `scrollTo`, opted into per screen | A framework **service**: the presenter calls `controller.scrollToVisible` on every focus move, so any focusable inside any `ScrollView` is reachable by keyboard and gamepad with no per-screen wiring. Ten-foot and gamepad reachability is a correctness requirement here (`ui_todo` §0), not an opt-in convenience. |
| `layoutPriority` | Decides which sibling gives up space when a stack is over-committed | **Not implemented, deliberately.** LuauUI's solver has no compression pass at all: an over-committed stack overflows and the container's declared `overflow` handles it. A priority number only means something once there is a shrink algorithm to prioritise, so shipping the prop first would be exactly the accepted-and-ignored property Milestone 0 removed. It is recorded here as a gap rather than declared in the schema. |
| Scroll offset | `ScrollPosition` is framework state | Read from the **engine** (`CanvasPosition`), which co-authors it. A framework-cached offset would be wrong after any user fling the framework did not observe. |
