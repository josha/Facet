# SwiftUI ↔ LuauUI: what LuauUI has, what it doesn't

**Report only.** Producing this document changed no library, example, or test code.

---

## 1. What this document is, and how to read it

LuauUI is a declarative UI framework for Roblox. SwiftUI is the most complete
declarative UI framework in wide production use, so it is the yardstick this
document measures against — capability by capability, with a citation on every
verdict. The point is not a score. The point is that a developer (or an agent)
picking up LuauUI can find out, in one read, whether the thing they need exists,
exists-with-caveats, or does not exist at all.

**How to read a verdict.** Each area below opens with a few sentences of plain
framing, then a table of capabilities, then the caveats that did not fit in a
table cell. Four verdicts are used:

| Verdict | Means |
|---|---|
| **Covered** | A first-class equivalent ships, is exported, and its conformance tests pass. |
| **Partial** | It ships and works, but with named behavior gaps a consumer will hit. |
| **Composable** | Not a shipped construct, but buildable today from the public surface with no framework change. The recipe is named. |
| **Missing** | No construct and no honest recipe. Where the Roblox engine is the reason, that is said. |

Two rules keep those verdicts from inflating:

1. **A control that works on only some input devices is Partial at best.** LuauUI
   targets mouse, touch, keyboard, and gamepad; "a control that only works with a
   mouse is an unfinished control." Being *reachable* on all four is also not
   enough — if the control does not behave the way that device's users expect
   (a slider you can only jump-to-value with a gamepad, never nudge), it stays
   Partial. ([`ADR-0016`](../adr/ADR-0016-three-axes-contract.md), `ui_todo.md:3-13`)
2. **Nothing in LuauUI has been confirmed on physical hardware.** Every
   four-input claim in this document rests on headless test runs plus scripted
   drives of the Roblox Studio device emulator. §14 lists what a human with a
   real phone, keyboard, and gamepad still needs to check.

**Vocabulary you need for the rest of the document.** LuauUI's terms, in SwiftUI
terms where an analogue exists:

| LuauUI term | What it is |
|---|---|
| **Blueprint** | The tree of plain Lua tables describing what should be on screen — LuauUI's equivalent of a SwiftUI `View` body. `UI.VStack{ UI.Text{...} }`. |
| **Signal** / **Memo** | The reactive primitives. A signal is a mutable observed value (`@State`); a memo is a derived, cached value (`computed`). Tracking is per-value, not per-view. |
| **Solver** | The layout engine. It measures the blueprint, then arranges it into rectangles. Runs headlessly, with no engine objects involved. |
| **Renderer** / **target** | The layer that turns solved rectangles into real Roblox `GuiObject` instances. Swappable — that is why the solver can be tested with no Roblox running. |
| **Presenter** | The layer that owns on-screen surfaces (screens, modals, popovers, toasts) and their focus, layering, and dismissal rules. |
| **Composite** | A shipped, exported, tested control assembled from primitives — `LuauUI.newSlider`. The opposite of a "recipe" the consumer writes by hand. |
| **Four-input proof** | An automated conformance test asserting a control is genuinely operable with mouse, touch, keyboard, *and* gamepad. |
| **Gate** | A named CI check that must pass before a piece of work is considered landed. There are 25 of them. |
| **Evidence level** | How a claim was verified: **E1** headless test run, **E3** Roblox Studio device emulator, **E4** physical hardware. No E4 evidence exists yet. |

---

## 2. The honest summary

LuauUI's reactive core, layout solver, motion system, theming system, and
tooling are strong — in several places stronger than SwiftUI's equivalents, and
in a few places (screen-level adaptive composition, information-preserving
Reduce Motion, arrival-radius chase animation) there is no single SwiftUI
built-in that does the same job. The controls catalog is real but smaller than
SwiftUI's, and the gaps that remain are structural rather than incidental: there
is no way to swap what a control *renders as* while keeping its behavior (no
`ButtonStyle`-style protocol); there is no screen-to-screen navigation model,
only surface stacking; there is no translucent-material system, and Apple's
Liquid Glass has widened that gap rather than narrowed it; there is no
right-to-left or bidirectional text support anywhere; and there is no assistive-
technology bridge at all — nothing in LuauUI talks to a screen reader. On
performance, the framework has deep headless instrumentation, executable
regression budgets, and real shipped wins (incremental layout, instance
recycling), but **zero measurements from a physical device**, and one shipped
feature (row swipe actions) costs materially more than its own plan budgeted.
Where a verdict here is generous, the caveat is in the same section, not
buried.

---

## 3. State & data flow

This is LuauUI's strongest area. Where SwiftUI re-runs a view's `body` and
diffs the result, LuauUI tracks dependencies per *value*: a signal read inside a
memo subscribes that memo to that signal alone. That makes invalidation
finer-grained than SwiftUI's, at the cost of SwiftUI's whole-object ergonomics —
there is no `@Observable`-style "mark the model, forget about it" macro, and
two-way binding is a convention (pass the signal down) rather than a type.

| SwiftUI capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `@State` — owned, per-instance mutable value | **Covered** | `core:signal`, a fine-grained observable value rather than a per-view struct field | `src/core/custom.luau:356-372`; `src/core/contract.luau:21-26`; test `signal-read-write` (`tests/conformance/suite.luau:26`) |
| `@Binding` — two-way reference to caller-owned state | **Covered by convention, not by type** | A control simply takes the caller's `Signal` and writes to it. There is no projection/wrapper type; misuse is caught at write time by a runtime assertion, not at authoring time | `src/controls/value_model.luau:1-12` |
| `@Observable` — auto-tracked property access | **Partial** — finer-grained, not object-shaped | Tracking is per-signal/per-memo via `use()`. You get precision SwiftUI does not have; you do not get "one annotation on a model class" | `custom.luau:104-109`; test `dynamic-dependencies-swap-atomically` (`suite.luau:134`) |
| Derived/computed state | **Covered**, glitch-free | `core:memo`, eager-stale marking plus pull-based recompute, so a diamond dependency never fires an observer twice with inconsistent inputs | `custom.luau:374-390,165-174,85-132`; tests `memo-derives-and-updates`, `glitch-free-diamond`, `no-spurious-fire-on-unchanged-recompute` (`suite.luau:35,71,359`) |
| Transactions (`withTransaction`) | **Covered** as pure write-batching | Many writes, one observer fire; a reverted transaction fires nothing | `custom.luau:436-451`; tests at `suite.luau:50,383,399` |
| `withAnimation` — wrap a state write, downstream reads interpolate | **Missing** | Animation in LuauUI is always explicit and separately typed: you build a `MotionValue` and drive it. There is no way to wrap an ordinary signal write and get interpolation for free. The motion clock does use transactions internally, but that is an implementation detail with no public seam | `src/motion/clock.luau:210-219` |
| Cycles / self-referential derivation | **Covered** — reported, not hung | A dependency cycle raises with a readable error instead of recursing | `custom.luau:89-96`; test `cycle-reported-not-hung` (`suite.luau:164`) |
| Writing state during a derivation | **Covered** — refused | Illegal by construction, not by convention | `custom.luau:177-179`; test `write-during-memo-is-error` (`suite.luau:191`) |
| `.task` — async work scoped to view lifetime | **Partial**, with stronger cancellation than SwiftUI | `LuauUI.newResourceProvider` gives scope-owned handles and generation-counter stale-completion rejection: a slow request that returns after its owner changed identity is discarded rather than applied. Bounded, spaced retry. Not a `.task`-shaped modifier, though | `src/async/resources.luau:358-366` |
| `@Environment(\.foo)` — implicit value propagation | **Covered** | Per-key signals with derived memos on top, so a keyboard-occlusion change cannot invalidate a subscriber that only reads colors. Widely consumed across the framework (`themeMetrics`, `effectiveInput`, `interactionClasses`, `typographyScale`, and more) | `src/env/environment.luau:316-344,125-312`; consumers include `renderer.luau`, `presenter.luau`, `table.luau`, `text_input.luau`, `rating.luau`, `row_actions.luau:611`, `theme_controller.luau`, `hint.luau:69` |
| Environment values that clamp/default bad input | **Covered** | `typographyScale`, `effectiveTransparency`, `effectiveOverscanInsets` all sanitize rather than propagate garbage | `environment.luau:125-153,200-218` |
| `ForEach(id:)` / `.id()` — identity and structural diffing | **Covered**, closer to `ForEach` than to whole-tree diffing | Adds, removes, and moves only; duplicate keys are a hard error. A row removed and re-added *while its exit animation is still playing* resumes the same mounted subtree, scope, and instances rather than remounting — stronger than SwiftUI's default | `src/mount.luau:224-407,288-300` |
| Instance reuse below `ForEach`/`When` | **Covered** — no direct SwiftUI analogue | A recycling pool keyed by node shape hands a retiring node's Roblox instances to the next node that needs the same shape, instead of destroy-then-create | `src/render/renderer.luau:1556-1722`; `tests/instance_park_corpse.spec.luau` |
| Ownership scopes / disposal | **Covered**, stricter than SwiftUI | Reverse-order idempotent dispose, double-dispose detection, and a releasability check at registration time — `scope:own()` raises immediately if handed something with no `dispose()`. Cleanup errors are quarantined, not propagated | `src/core/scope_impl.luau` |
| Runaway-effect protection | **Covered** — no public SwiftUI equivalent | A feedback loop between effects is capped and reported rather than hanging the client | `custom.luau:22,264-273`; test `feedback-loop-hits-iteration-cap` (`suite.luau:236`) |

**Caveats.**

- The absence of a `withAnimation` equivalent is the single largest ergonomic
  gap in this area. Every animated value has to be declared as a distinct
  `MotionValue` type up front; you cannot retrofit animation onto an existing
  plain value at the call site.
- `lastError()` on the core is sticky and cannot be reset. You can ask a
  long-lived core "were you ever in a quarantined state", but not "are you
  healthy right now."
- The environment key that describes screen size class (`sizeClass`) is read by
  exactly three files today — the adaptive-layout policy module and two controls
  (`src/layout/adaptive.luau`, `src/controls/popup_button.luau`,
  `src/controls/picker.luau`). Other files read *other* environment facts; they
  do not adapt to size class. It is a real capability with narrow adoption.

---

## 4. Layout

LuauUI's solver is a headless, testable measure-then-arrange pass over the
blueprint, with weighted flexbox-style stacks, a grid, a `ViewThatFits`
equivalent, and safe-area insets. Two things here go beyond SwiftUI. The first
is `UI.Composition`/`UI.Region`, where a screen declares its content once as a
set of *ranked regions*, each carrying an ordered ladder of forms from richest to
minimum-viable; the framework then tests arrangements and steps a region down its
ladder — or drops it entirely, lowest rank first — until everything fits. That is
closer to a full `Layout` protocol plus `layoutPriority` combined than SwiftUI
ships in any single construct, and it means no screen contains a device-name
branch. The second is incremental layout: a single changed bound value re-solves
only the smallest enclosing subtree it can affect, not the whole tree.

| SwiftUI capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `HStack`/`VStack` core (weighted, aligned, with margins) | **Partial** | Weighted flexbox distribution, `align`, `margin`. No shrink negotiation (next row) | `src/layout/solver.luau:1917-2100` |
| `layoutPriority` — who shrinks first when over-committed | **Missing**, deliberately | There is no priority or shrink pass in the solver. `Composition`'s `rank` is adjacent but not equivalent: it drops or degrades whole screen regions, it does not negotiate sizes inside one stack | no `priority` path in `solver.luau` |
| `ZStack` | **Partial** | Deterministic paint order. No per-child `.zIndex` override. The overflow diagnostic is per-axis and understands `fill` children, so a child granted its full box is no longer reported as overflowing a box it cannot leave | `renderer.luau:419-437`; `tests/zstack_fill_diagnostic.spec.luau` |
| `Grid` — cell sizing and alignment | **Partial** | A `fill`-dimensioned cell occupies its full column/row, and per-cell alignment is applied. The grid's measured size is a proven fixed point of its own arrange report (measure it, arrange it, measure again — same answer) | `solver.luau:1890-1897,1904-1906`; `tests/grid_measure_arrange.spec.luau` |
| `GridRow` / per-column widths / `gridCellColumns` (spanning) | **Missing** | One uniform column width for every column; no spanning | `solver.luau:1863` |
| `LazyHGrid` | **Missing** | The grid is row-major and vertical only | — |
| `ViewThatFits` | **Covered** | A real solver construct (`kind == "fits"`) that measures candidates against the offered box and picks the first that fits | `solver.luau`; `blueprint.luau`; `blueprint_schema.luau` |
| Reactive-axis stack (no SwiftUI single equivalent; nearest is `AnyLayout`) | **Covered** | `UI.AdaptiveStack` — one class whose `axis` is a bound value. Flipping horizontal↔vertical re-solves without remounting the children | `blueprint.luau:566-570`; `renderer.luau:386-389` |
| Whole-screen adaptive composition | **Covered** — exceeds SwiftUI in one respect | `UI.Composition` + `UI.Region`: ranked regions with richest→minimum-viable form ladders, legality-tested in rank order. Carries all five reference apps' adaptation (§12) with zero device-name branches. The resolver is a pure function, so it is exhaustively testable headlessly | [`ADR-0023`](../adr/ADR-0023-declared-content-composition.md); `src/layout/composition.luau` (1703 lines); `renderer.luau:394-398`; `tests/composition.spec.luau` (1988 lines) |
| Size-class-driven adaptation (`horizontalSizeClass` etc.) | **Covered** | `src/layout/adaptive.luau` derives `sizeClass`, `heightClass`, `axisFor`, `columnsFor`, `navPlacement`, and `conditions()` from viewport facts. Consumed by all five reference apps | `src/layout/adaptive.luau` |
| Safe areas | **Covered** | Four-edge insets as environment facts, with a full-bleed (`edgeToEdge`) root policy for scrims and backgrounds | `environment.luau:22-23`; `renderer.luau:2278-2315` |
| `GeometryReader` | **Partial** | You can learn a node's solved rectangle (`controller.rectOf`, an `onGeometry` callback, a `syncGeometry` contribution) but it is a push callback keyed by node path, not a readable value you can compose into a memo | `controller.rectOf`, `opts.onGeometry`, `syncGeometry` |
| `containerRelativeFrame` | **Composable** | The `percent` dimension type expresses "half the parent" directly | `solver.luau:481-517` |
| `.alignmentGuide` — custom alignment anchors | **Missing** | No construct exists | — |
| `ScrollView` — a real scroll container | **Covered** | Backed by a native Roblox `ScrollingFrame`: it genuinely scrolls, clips, and reports its content size | `screen_target.luau:107-113,2029-2036,3097-3152` |
| `ScrollView` — horizontal axis | **Covered** | `axis = "x"` measures and arranges correctly | `solver.luau:832-858` |
| Scroll-indicator policy | **Covered** | `indicators: "auto" \| "none"`; a size-to-content scroller's *measure* includes the scrollbar its *arrange* reserves, so it cannot under-measure itself | `blueprint.luau:132`; `screen_target.luau:2998-3141` |
| Drag-to-edge autoscroll | **Covered** — no SwiftUI built-in | Dragging an item toward a scroller's edge scrolls it, through any nested chain of scrollers, innermost first, falling through when the innermost is pinned | `src/input/autoscroll.luau`; `renderer.luau:3384-3580` |
| `ScrollView` content virtualization | **Missing** | Every `ScrollView` child is measured and arranged regardless of visibility. Only the dedicated `VirtualList` and `Table` virtualize, and each does so independently | — |
| `LazyVStack` (as `VirtualList`) | **Partial** | Windowed rendering of a long list, with configurable row gap and a focus policy keyed by row identity or index. But: fixed row height only, vertical only, no pinned section headers, no fling/inertia, no scrollbar | `src/controls/virtual_list.luau` |
| Incremental relayout | **Covered** — no SwiftUI-visible equivalent | A changed bound value re-solves only the subtree that can be affected. Measured on the framework's own instrumented surface: 141 arranged nodes down to 8 (~17×) for a one-value change, with zero pixel differences across 185 nodes in an engine-level visual diff. On by default | `solver.luau:462-465`; `renderer.luau:2262-2280,2278`; `presenter.luau:2057`; `tests/incremental_layout.spec.luau` |
| Live 3D content inside a laid-out box | **Covered** — no SwiftUI equivalent (Roblox-specific) | `UI.Stage` hosts a Roblox `ViewportFrame` inside a solver-owned rectangle, with a pure camera/lighting contract. To the solver it is just another content leaf. Live consumers: a 3D dashboard hero and an avatar mannequin preview (§12) | `src/render/stage_content.luau` (147 lines); `blueprint.luau`; `screen_target.luau`; `billboard_target.luau` |
| Device-matrix testing | **Covered** | Named device profiles and a matrix runner drive any surface across five viewport shapes headlessly and in the Studio emulator | `src/preview/device_profiles.luau`; `src/preview/matrix_rows.luau` |

**Caveats.**

- **No container unifies virtualization, reordering, and selection.** `Table`
  reorders and selects but does not virtualize; `VirtualList` virtualizes but
  does neither. A long, reorderable, selectable list is not buildable on any
  single class today. Row swipe actions shipped inside both classes separately
  rather than closing this.
- Two layout proposals with live supporting evidence remain deliberately
  deferred: a flow-stack "compress toward `min`" step, and splitting the
  overloaded `align` property into distinct channels.
- Two patterns in `src/controls/row_actions.luau` are worth knowing about but are
  *recipes built on existing seams*, not framework primitives: a per-row height
  override signal driven by a physics spring (to animate a row collapsing to
  zero), and reading `syncGeometry` on the scroll cadence to keep a floating
  menu anchored to a moving row.

---

## 5. Controls catalog

LuauUI ships 16 registered control classes with conformance proofs plus 20
non-interactive leaves — far short of SwiftUI's catalog, but every interactive
one carries an automated four-input proof, and 15 of 15 also prove the
device-idiom axis. Six controls that used to be "here's how you'd build it"
recipes are now real exported composites: `newSlider`, `newStepper`, `newPicker`,
`newProgressView`, `newLabel`, `newDisclosureGroup`. The headline recent addition
is a generalized swipe-actions construct, covered in detail below.

| SwiftUI item | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `.swipeActions` — secondary actions on a row | **Partial** | `LuauUI.newRowActions` / `LuauUI.newRowActionsCoordinator`, a general construct that wraps *any* row content, not just table rows. Detail and gaps in §5.1 | `src/controls/row_actions.luau`; `src/init.luau:186,191`; `tests/row_actions.spec.luau`, `tests/row_actions_input.spec.luau`; `src/controls/table.luau:1159-1351` |
| `Slider` | **Partial** | Real composite: pointer drag, tap-to-position, touch drag, keyboard/gamepad nudge. Cancels cleanly if the input device changes mid-drag | `src/controls/slider.luau:135`; `tests/conformance/controls_registry.luau:428-464` |
| `Stepper` | **Partial** | Real composite | `src/controls/stepper.luau:134`; registry `:466-500` |
| `Picker` (`.segmented` and `.inline`) | **Partial** | One adaptive composite replaces both styles: `picker.resolvePresentation(optionCount, sizeClass, longestLabel)` chooses segmented vs inline from option count, screen size class, and label length — never from a device name | `src/controls/picker.luau`; registry `:373-399` |
| `ProgressView` (determinate) | **Partial** | Real composite, declared non-interactive (so it is exempt from the four-input proof by design, not by omission) | `src/controls/progress_view.luau:140`; registry `:345-358` |
| `ProgressView` (indeterminate / spinner) | **Missing** | Zero occurrences of the concept in source | `grep -rn "indeterminate" src/controls/progress_view.luau` → 0 |
| `Label` (title + icon) | **Partial** | Real composite with the presentation resolution SwiftUI's `LabelStyle` provides: `presentation: "titleAndIcon" \| "titleOnly" \| "iconOnly"`, and `iconOnly` degrades safely to `titleOnly` when no icon resolves. **Its `title` is a static value, not bindable** — a known follow-on | `src/controls/label.luau:23,30`; open item at `framework-fixes.md:874` |
| `DisclosureGroup` | **Partial** | Real composite, including the correct focus behavior on collapse (focus moves to the header before the content unmounts, so it is never lost) | `src/controls/disclosure_group.luau`; registry `:400-426` |
| `Divider` | **Covered** | A real axis-aware hairline leaf that infers its own orientation — not a hand-sized box | `blueprint.luau:699`; registry `:869` |
| Star-rating strip | **Covered** — no SwiftUI standard-library counterpart | `newRating`: a single focus stop that supports tap, scrub, and keyboard/gamepad adjust, and cancels back to its prior value if the pointer is lost mid-scrub | `src/controls/rating.luau` |
| `Menu` / dropdown button | **Partial** | `newPopupButton` adapts its presentation: `resolvePresentation(optionCount, sizeClass, touchLive)` returns a sheet whenever touch is live, a sheet on compact screens with more than 6 options, an inline list at 3 or fewer options on larger screens, and a menu otherwise. See caveat below on row heights | `src/controls/popup_button.luau` |
| `Table` / `List` with selection and reordering | **Partial** | Reorderable rows, selection, per-cell rendering via `cellFor`, and swipe actions via `spec.rowActions` — leading/trailing trays, per-edge full-swipe, keyboard Delete/Backspace, gamepad menu. **No modifier-click multi-select. No virtualization.** Column resize still remounts every row | `src/controls/table.luau:185-231,1159-1351` |
| `.contextMenu` | **Missing** | See §5.2 — the menu half is proven, the trigger half is not wired |
| `ButtonStyle` / `ToggleStyle` / `PickerStyle` protocols | **Missing** | See §6 — this is a styling-architecture gap, not a catalog gap |
| Palette `Picker` | **Missing** | Zero occurrences | — |
| `DatePicker`, `ColorPicker`, `SecureField`, multi-line `TextEditor`, `Gauge`, `Link`, `ShareLink`, `NavigationSplitView` | **Missing** | Each reconfirmed absent by direct search of current source | — |
| `.sensoryFeedback` at the control level | **Missing** at the control level | No per-control haptic/audio hook. There *is* a framework-level semantic feedback bus (§7), which is a different and real thing | — |

### 5.1 Row swipe actions, in detail

`LuauUI.newRowActions` and `LuauUI.newRowActionsCoordinator` are standalone
public exports — proven working in a hand-built `ScrollView > VStack` list with
no `Table` involved. `Table.rowActions` is `Table` wiring the same two seams for
consumers who don't want to hand-roll a list.

What ships, per `tests/conformance/controls_registry.luau:612-734` and
`tests/row_actions*.spec.luau`:

- **Leading and trailing action trays**, revealed by mouse drag or touch pan,
  growing proportionally under a spring.
- **Full-swipe commit per edge** (`fullSwipe` as a bool or `{leading, trailing}`):
  swiping past the threshold fires the first action of that edge. For a
  destructive action the row slides off and its height collapses to zero;
  `onAction` fires exactly once either way.
- **Keyboard Delete/Backspace** fires the row's first destructive action. It is
  scoped to the row's own mounted subtree (so it cannot fire for a row you are
  not focused on) and inert while that row's menu is open.
- **Shift+Return and gamepad ButtonX** open an action menu listing every action —
  the framework's first modifier-aware key binding.
- **An edit-mode minus affordance** that opens whichever edge actually holds the
  destructive action.
- **A one-open coordinator**: opening row B closes row A; scrolling or tapping
  outside closes the open row.
- **Arbitration against reorder drag**: an 8px axis lock sends horizontal motion
  to the actions and vertical motion to the scroller; ties go vertical; a drag
  starting on the reorder handle always wins.
- **Mid-gesture device switching** behaves predictably: a touch that lands
  mid-mouse-drag is declined and the mouse keeps the drag; the reverse likewise;
  a cancelled touch springs the row back to closed.

**Its named gaps**, all real:

- **Performance.** A closed, wrapped row inside `LuauUI.newVirtualList` costs
  **+57% steady-scroll time, +81% fling time, and +5 extra Roblox instances per
  row** versus an unwrapped row (200 rows, 13-row window). The feature's own plan
  budgeted ≤5% and ≤4 instances. Root-cause profiling attributed ~98% of the
  delta to the shared renderer/solver creating, measuring, and destroying those
  5 extra instances every time a row crosses the virtualization window boundary —
  not to the feature's own reactive graph (~2%). A scratch build with a
  true-inert passthrough path recovered wall time to within ~10% of baseline,
  confirming the attribution. By director ruling (2026-08-11) the CI ceiling was
  re-baselined to the *measured* numbers (steady ≤57%, fling ≤81%, instances ≤5,
  `tools/check_row_actions_matrix.py:52-55`), with the original budget left on
  record as "missed, not massaged." The named next lever, not started: give
  `VirtualList` a gesture-composition hook (mirroring `table.luau`'s
  `composeWithReorder`) so a wrapped row's capture surface rides the list's own
  hit surface instead of mounting its own — or, larger, add cell recycling to
  `VirtualList`. Charter: `docs/plans/row-actions-perf-mission.md`.
- **No right-to-left support.** "Leading" means left and "trailing" means right,
  unconditionally. This is an explicit non-goal (`docs/plans/row-actions.md:16`)
  and matches the framework-wide absence of RTL/BiDi.
- **Two of five secondary-action triggers are absent.** Of swipe, keyboard,
  gamepad, mouse secondary-click, and touch long-press, the first three are real.
  Mouse right-click and touch long-press reach the menu only through the reveal
  tray, not directly.
- Only `Table` has a turnkey integration. The coordinator is public and general,
  but no other composite (notably `VirtualList`) wires it.

An adversarial code review of the whole feature closed at 16 findings — 15 fixed
directly, 1 resolved by a design change (see `bindPresent` in §9). A five-viewport
Studio device matrix passes. Six physical-device checks remain owed (§14).

### 5.2 `.contextMenu` — why it is still Missing

The *menu* half is proven: row actions render exactly that kind of action list.
The *trigger* half is not. A normalization and arbitration layer over Roblox's
native gesture recognizers ships and is publicly exported
(`src/input/touch_gestures.luau`, `LuauUI.touchGestures`) — tap, long-press, pan,
pinch, rotate, and swipe, all wired end-to-end through the adapter contract and
part of the formal target contract. **No control calls it.** `Button` still
filters input to primary mouse button and touch only. So the blocker is no longer
"there is no adaptation layer" but "the adaptation layer is built, tested, and
exported, and nothing consumes it as a trigger" — a materially smaller gap, and
the most obvious next candidate.

### 5.3 Caveats on the catalog

- **`PopupButton` row heights.** Its `sheet` presentation derives row height from
  a theme token (`controlSizes.large.height` = 56px), so the touch path never
  serves a row below the 44px minimum hit target. The pointer-only `menu`
  presentation still serves 36px rows — genuinely below 44px, but now confined
  to a pointer-only code path. Panel flip/clamp behavior and selection-only rows
  are unchanged and unaddressed.
- **No `*Style` protocol.** Every composite is built by composing styled
  primitives. There is no way to substitute what a control renders as while the
  framework keeps its interaction and state. This is a deliberate, durable
  architectural difference — see §6.
- The full 69-item SwiftUI catalog comparison is not re-listed here. Items not
  named above were not independently re-examined in the current audit pass.

---

## 6. Styling & theming

Theming is a complete, shipped capability class, and it goes further than
"swap a palette": a *theme package* owns typography, spacing, control heights,
corner radii, strokes, content insets the solver can see, and asset-backed
chrome art. Installing or swapping one happens in a single transaction, so paint
and geometry land on the same frame with mount identity, focus, scroll position,
selection, and in-progress text entry all surviving. Dark/Light swapping rides
Roblox's native StyleSheets with no remount at all.

The durable gap is the opposite of the strength: LuauUI lets a *theme* change
everything about how controls look, but does not let a *consumer* change what one
control renders as. There is no `ButtonStyle` protocol, and the only per-instance
rendering-injection seam in the whole library is `Table`'s `cellFor`.

| SwiftUI capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `*Style` protocols (`ButtonStyle`, `ToggleStyle`, `LabelStyle`, `PickerStyle`) | **Missing** | No equivalent anywhere. A control's rendering is imperative instance code in the render target; substituting it means writing a whole new render target | — |
| View modifiers that attach validated data to a node | **Partial** | Three ship: `UI.shadow`, `UI.corners`, `UI.styleGroup`. They attach data, they do not substitute rendering | `src/render/renderer.luau` |
| Style properties that react to state changes after mount | **Covered** | `surface`, `role`, `shadow`, `gradient`, `corners`, `textAlign`, `shape`, `icon`, `compactLabel`, `stroke`, `scaleMode` are re-applied on every reactive change, through the live paint/semantics dirty loop | `renderer.luau:76-106` (`STYLE_PROPS`, `STYLE_PROP_ORDER`) |
| Materials — blur, vibrancy, translucency | **Missing** | Nothing in the framework produces a blurred, backdrop-sampling, or translucent material. Theme packages work in flat fills, nine-slice art, gradients (alpha capped at 0.9), and layered image chrome — all opaque compositing | — |
| Liquid Glass (`.glassEffect()`, `GlassEffectContainer`) | **Missing**, and **the gap widened** | Apple shipped Liquid Glass as a mature production system in the interim; LuauUI has no counterpart at any layer, and none is planned in any open design record | — |
| `.tint(_:)` cascading down a subtree | **Partial** | Per-node tinting is real and reactive: `tintRole` tints semantic icon art from the active theme's roles, `Image.tint` is a live reactive write, and a continuous colour-blend channel (`{role, blend, from?}`) can animate between two theme roles. **What is absent is inheritance** — no `.tint()` recolors an entire subtree; every tint is per-node opt-in | [`ADR-0022`](../adr/ADR-0022-sponsor-framework-gaps.md) Decision 6 |
| Dark mode / color schemes | **Covered** | Native StyleSheets ship `Theme Dark` and `Theme Light`, swapped at runtime with no remount and no loss of focus or scroll | [`ADR-0018`](../adr/ADR-0018-native-stylesheets.md) |
| Theme packages owning metrics and chrome, not just colors | **Covered** — no SwiftUI equivalent | A package owns typography, spacing, control heights, radii, strokes, solver-visible content insets, and asset chrome. `theme_controller.install`/`.swap` performs one transaction — a `SetDerives` plus the snapshot commit — so geometry and paint cannot disagree for a frame. Validated at definition time for contrast, completeness, legal properties, insets, and touch-target floors | [`ADR-0019`](../adr/ADR-0019-theme-packages.md); `src/themes/theme_controller.luau` |
| Rich, image-driven skinning | **Covered** — no SwiftUI equivalent | Up to 8 layered art slots, per-state art maps, value-display hosts drawn full-size and revealed through a clip window (so a value change costs no instance write), semantic icons with an ASCII-safe fallback that can never render as tofu, a pixel-art rendering mode, and `selectBy` to pick a package by input paradigm. 9 dedicated spec files | [`ADR-0020`](../adr/ADR-0020-rich-skinning-v2.md) |
| Dynamic Type | **Covered** — a rigorous equivalent | The player's Roblox "Text size" preference is first-class layout input. The framework measured the actual pixel offset each preference adds and uses those **measured per-preference constants** (Medium 0, Large 4, Larger 10, Largest 14 — uniform across font, weight, and size) rather than guesses; the engine paints `TextSize + offset` and the solver reserves exactly that box. Changing the preference mid-session re-solves every mounted surface in place, preserving identity, focus, scroll, and state. Eight typography roles carry font descriptor and line height together, and the offset composes additively with ten-foot (TV) scaling | `preferredTextOffset` environment fact — `src/env/environment.luau`, consumed at `src/render/renderer.luau:2352` and `src/layout/text_fit.luau:59,117`; `docs/guide/05-styling.md` |
| Cascade / selector model | **Covered** (supporting infrastructure) | Rules resolve by priority first, then insertion order (later wins); there is no CSS-style specificity, on purpose, so the generator and the runtime can never disagree about which rule applies. Instances are classified for the cascade by `luau-*` CollectionService tags | `ADR-0018`; `native_style.priorityFor` |

**Caveats.**

- The style lint (jagged-corner warnings, a ~100-shadow budget) is warnings-only.
  It has no CLI and is wired into no gate — nothing fails if you ignore it.
- Rich skinning has three open verification items: a human walkthrough of the
  Roblox Style Editor, a physical-phone pass over ornate chrome art, and low-end
  device cost. All tracked, none closed by a device run.

---

## 7. Input & accessibility

**This is the area with the largest honest gap.** Focus management, keyboard
traversal, four-input conformance, drag-and-drop, and cross-device gesture
hand-off are all genuinely strong. But there is **no assistive-technology
bridge of any kind** — a repository-wide search for screen-reader, VoiceOver,
TalkBack, accessibility-label, or ARIA concepts returns nothing outside
design-intent comments. A blind player cannot use a LuauUI interface. There is
also no consumer-facing hover state, no raw key-press seam, and no
Home/End/PageUp/PageDown or type-ahead navigation.

The other structural issue here is architectural: gesture machinery exists in
**four independent implementations** that share almost nothing.

| SwiftUI capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| Assistive-technology bridge (VoiceOver / TalkBack) | **Missing** | Nothing. Confirmed by whole-repository search | — |
| Focus system (`@FocusState`, `.focusSection`, Tab order) | **Covered** | `LuauUI.newFocusGraph`: flat and grouped scopes, directional navigation, and Tab/Shift+Tab traversal in true document order | `src/input/focus_graph.luau` |
| Four-input + device-idiom conformance proof | **Covered** | **15 of 15** interactive controls prove reachability on mouse, touch, keyboard, and gamepad *and* prove the device-idiom axis, across 16 registered classes and 153 conformance specs | `tests/conformance/controls_registry.luau` |
| Gesture value type (normalized `Gesture`) | **Partial** — real primitive, zero consumers | Kind, state, positions, translation, velocity, scale, rotation; all six Roblox gesture events connected; publicly exported. No control calls it | `src/input/touch_gestures.luau:19-28` |
| Gesture composition (`.simultaneously`, `.sequenced`, `.exclusively`) | **Partial** | A ranked single-owner arbiter (pinch/rotate > pan > long-press > tap/swipe) with a begin/change/end ownership lifecycle. No simultaneous delivery and no chaining. Same "no consumers" caveat as above | `touch_gestures.newArbiter()` |
| `DragGesture` → general drag & drop | **Partial**, materially deeper than SwiftUI's | Public `UI.draggable`/`UI.dropTarget` with a typed payload, tap-to-arm, per-input-class promotion thresholds. Three acquisition paths — Roblox's native `UIDragDetector`, a pointer-capture fallback, and a non-pointer arm→navigate→commit flow for keyboard and gamepad — funnel into **one** shared session lifecycle | `src/input/drag_contract.luau`, `drag_session.luau`, `drag_registry.luau`; [`ADR-0022`](../adr/ADR-0022-sponsor-framework-gaps.md) Decision 5 |
| Detecting and adapting to which device is in use | **Covered** | Per-class promotion thresholds; live hot-switching proven mid-gesture (a user who starts with a mouse and continues with touch is handled explicitly, not accidentally) | `src/input/interaction_tokens.luau:45-87` |
| Keyboard modifier chords | **Partial**, new | `action.bind` accepts `modifiers = { shift = true }`, and the real-engine realization compiles that into two engine bindings (left and right Shift as `PrimaryModifier`). **Shift only** — Ctrl and Cmd collapse into one untracked group, Alt/Option is untracked entirely | `src/input/actions.luau:96-112` |
| `.onKeyPress` — raw key seam | **Missing** | No raw key event surface | — |
| Home / End / PageUp / PageDown / type-ahead | **Missing** | — | — |
| Escape to dismiss a modal | **Partial** — an engine constraint | The Escape key is permanently reserved by Roblox for the CoreGui menu and cannot be bound. Cancel is bindable on gamepad ButtonB; keyboard and mouse users close a modal via whatever the screen provides. A keyboard-only user has no framework-level dismiss | — |
| `GuiService.SelectedObject` mirror (engine selection bridge) | **Partial**, experimental | Ships opt-in and modal-only: `presentModal({ engineSelectionBridge = true })`, gated so passive surfaces never opt in, with explicit `Selectable` restore when selection moves off. **This does not touch VoiceOver or TalkBack** — it drives Roblox's own gamepad selection cursor, nothing more. Gated behind a physical-device check before it becomes contract | `adapter.setEngineSelection`; supersedes the risk framing in [`ADR-0014`](../adr/ADR-0014-first-responder.md), which was never updated after its own probe shipped |
| Dynamic Type / preferred text size | **Partial** | See §6 — the mechanism is thorough; the physical-phone-at-Largest check and the subjective-feel check are still owed | — |
| `.accessibilityAction` — custom accessibility actions | **Missing** | — | — |
| A control's accessibility description | **Partial** — prose only | `ControlContract.accessibility` is typed as a human-readable summary string; the only consumer asserts it is non-empty. It reaches no platform API | `src/controls/contract.luau:21` |
| `.onHover` / `isHovered` | **Missing** as a consumer surface | Hover exists but is framework-internal: an automatic, pointer-gated chrome effect. No consumer-facing hover state exists. One narrow dwell-based seam exists for a single feature (revealing truncated text) | `src/render/target_contract.luau:42-47`; `screen_target.luau:3501-3529` |
| `.pointerStyle` — cursor shape | **Partial** — seam live, no art | A `cursorHint` prop exists on `UI.Grip` only, and the cursor-art table is empty, so every hint falls back to the default arrow | — |
| `.sensoryFeedback` — haptics tied to state changes | **Composable** — deliberately | `src/present/feedback.luau` publishes a closed, versioned taxonomy of 12 verbs (`activate, select, adjust, pickup, commit, reject, cancel, arrive, land, dismiss, supersede, celebrate`), fired synchronously on the frame that caused them, with subscriber errors quarantined. The design rule is explicit: **LuauUI plays nothing** — the game maps verbs to its own haptics and sound. No `HapticService` or `VibrationMotor` is reached anywhere, on purpose. Live-consumed in production | `games/RascalRally/code/src/client/LuauUISponsor/PlayFlow.luau:609` |

**Caveats.**

- **Gesture machinery is fragmented four ways**: the touch-gesture arbiter (which
  nothing consumes), the general drag contract, row actions' own pointer-capture
  and axis-lock, and `Table`'s hand-rolled vertical reorder drag. None of them
  share axis-lock code; only two share a velocity tracker. Each new gesture
  feature has so far meant a fifth hand-written path.
- Six physical-device checks are newly owed by row swipe actions alone (§14).

---

## 8. Motion

LuauUI's motion system is authoritative and opinionated. Springs are declared
with SwiftUI's two-number model (response and damping ratio, never mass and
stiffness), and an inline spring literal at a call site is a **hard error** that
names the registration function — springs must come from one of four registered
classes, so the design system cannot drift one call site at a time. Retargeting a
spring mid-flight never touches its current value or velocity, so a spring
interrupted by a new target continues rather than jumping; a differential test
proves it, by showing a velocity-cut twin travels measurably less on the next
frame.

The one large gap is `withAnimation`: animation is always explicit here. You
cannot wrap an ordinary state write and get interpolation.

| SwiftUI capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `withAnimation` — implicit write⇄interpolation coupling | **Missing** | A plain bound number always jumps. To animate, you construct a `MotionValue` (`clock:spring`/`counter`/`glide`/`timer`) and drive it with `setTarget`/`setVelocity`/`snap` | — |
| `.spring(response:dampingRatio:)` | **Covered** | The same two-number model. Four named classes ship (`container`, `object`, `reward`, `decay`); inline literals are refused | `src/motion/spring.luau` |
| Spring interruption / retargeting | **Covered** | `setTarget` never touches value or velocity — enforced at three call sites and proved by a differential test that a visible jump would fail | — |
| Animation completion callbacks | **Covered**, callback-based | `MotionValue:onSettle(fn)` fires exactly once per arrival, after that frame's writes commit. No awaitable form | — |
| `phaseAnimator` | **Missing** | No looping or state-driven phase construct | zero occurrences |
| `keyframeAnimator` | **Partial**, via a different shape | `clock:timeline(spec)` is beat-sequenced choreography with `interrupt()` and `skip()`. Each beat is a callback, not a per-property value track with its own curve, and a timeline never loops | — |
| `.transition(.insertion/.removal)` | **Covered** — general, reusable | `UI.ForEach{transition}` and `UI.When` share one structural-region property. Forms: `fade`, `slide-*`, `materialize`, `instant`. A removed row **retires in place** — it stays mounted at its clamped slot, non-interactive, and disposes on exit-complete — rather than vanishing. Hard 500ms exit cap | `src/render/transitions.luau` |
| `matchedGeometryEffect` — shared-element / hero transitions | **Missing** | No cross-tree geometry interpolation. The nearest thing (`virtual_list.luau`'s row slide) animates an offset delta *within one list*, not a shared identity across two layout trees | zero occurrences |
| `.scrollTransition` | **Missing** | No API ties paint to a node's live proximity to the viewport edge | zero occurrences |
| Reduce Motion | **Covered** — information-preserving, not a switch | The OS signal is read live on every retarget, not snapshotted at boot. Motion is categorized: *decorative* motion snaps instantly but still fires `onSettle`, so completion logic is unaffected; *informational* motion (a count-up whose number is the message) keeps running to the same terminus but quantizes its writes to a 250ms step, so the information survives while the animation stops being animation | `GuiService.ReducedMotionEnabled` |
| `.numericText` / animated numerals | **Covered**, plus more | `clock:counter` publishes whole numbers only and never overshoots its target. On top of it, `motion.newValueReveal` composes a hold/count/land layer under two rules — never state a new value before its moment, never withdraw a stated one — with 5 documented rules, exhaustively tested. SwiftUI has no single built-in for this | `src/motion/value_reveal.luau` |
| Countdown / depleting timer | **Covered** | `clock:timer(spec)` advances on raw wall-clock delta, not frame-clamped time, so a frame spike cannot stretch a countdown | — |
| Gesture → animation velocity hand-off | **Covered** | A 100ms rolling-window velocity tracker feeds both a general drag flight (seed velocity, then chase a live target) and row-actions flick momentum (read the tracker at release, seed the persistent spring) | `src/input/drag_velocity.luau` |
| "Arrive at a live, moving target" in 2-D | **Covered** — no single SwiftUI API | `clock:chase(opts)`: two scalar springs against a target re-read every frame, firing `onArrive` once the value enters a *perceptual* arrival radius (4px by default) rather than waiting for physics settle epsilon — which the framework measured as trailing perceived landing by about 0.7 seconds | `src/motion/clock.luau` |
| `.sensoryFeedback` | **No host equivalent by design** | See §7 — the verbs are published, the playback is the game's | `src/present/feedback.luau` |

**Caveats.**

- Row swipe actions' collapse animation builds its **own second spring** rather
  than going through the general `ForEach` transition primitive
  (`row_actions.luau:875-887`). It works, but it is a duplicate mechanism a
  future generalization should unify.

---

## 9. Presentation & navigation

LuauUI presents *surfaces*: screens, modals, popovers, toasts, and a couple of
presenter-private surfaces. That stack is well specified — closed, validated
option sets rather than free-form tables; focus trapped and restored per surface;
five named display-order bands rather than one running counter; theme-derived
rather than hardcoded dismissal geometry.

What it does not have is **navigation**. There is no push/pop screen model, no
`NavigationPath`, no back button, no titles, no deep-link or state-restoration
surface. A consumer swaps blueprints under a single `present()` call by hand.
That is the largest structural gap in this area.

One capability here is worth calling out because it generalizes: a control can
put a *floating* surface on screen — one that renders above everything and
contributes **zero** to any ancestor's measured size. That seam is `bindPresent`,
and it exists because the first version of the row-actions menu measured as a
child of its row, silently inflating the row and, inside a table, the whole list.
A pinned test now asserts a sibling row's solved rectangle is byte-identical
whether the menu is open or closed.

| SwiftUI capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| `.sheet` — modal presentation | **Partial** | `presenter.presentModal` with a focus trap and per-depth priority banding. Named, validated options: `cancelPolicy`, `scrim`, `outsideTapCancel` swallow semantics, `initialFocus` | `src/present/presenter.luau` |
| `.interactiveDismissDisabled` / tap-outside behavior | **Covered** internally, no public mirror | The dismissal geometry is forgiving by design: the "inside" region is the painted panel plus a 24px forgiveness ring, unioned with each focusable's 44px hit rectangle, so a near-miss on a control does not dismiss the modal. The ring is derived from theme metrics, not a magic number. No public property mirrors `.interactiveDismissDisabled` | `src/present/modal_zones.luau` |
| `.fullScreenCover` | **Composable** | `presentModal` + an edge-to-edge root policy + a full-bleed root blueprint | — |
| `.alert` / `.confirmationDialog` | **Composable** | Recipes only. **No item-binding sugar** — SwiftUI's `.alert(item:)` pattern has no analogue; a consumer wires its own signal. Nothing orders or tints a Cancel row automatically | — |
| `.popover` / transient panel | **Partial** | `newPopupButton` plus a presenter-managed tap-away catcher. The catcher supports a non-consuming mode, so a tap-away can close the popup *and* still reach the control underneath | `presenter.syncPopupCatcher` |
| `.swipeActions` / `.contextMenu` as a secondary-action container | **Partial** | `LuauUI.newRowActions` — a real construct, not a recipe, with the gaps named in §5.1 | `src/controls/row_actions.luau` |
| Floating surface that contributes nothing to its ancestor's layout | **Covered** — architecturally significant, no SwiftUI-named equivalent | `bindPresent` on the contribution contract. Deliberately routes through `presentModal`, never `present`: two screen-kind surfaces sharing one priority band would double-deliver Navigate/Activate/Cancel | `src/input/contribution.luau:138-161`; `row_actions.luau:675-838` |
| `ButtonRole` (destructive / cancel) | **Partial** | `role: "normal" \| "destructive"` on an action paints the shipped danger style. No `cancel` role, no automatic dialog-row ordering | — |
| `NavigationStack` — screen push/pop | **Partial** at best | Only surface stacking: `presentModal` pushes, `back()` pops the top *modal*, `depth()` reports the stack size. There are exactly two surface kinds, `"screen"` and `"modal"`. No `pushScreen`, no `navigationPath`, no `screenStack` construct exists anywhere in source | confirmed by source search |
| `NavigationSplitView` / `.inspector` / scene management | **Missing** | Zero occurrences | — |
| `.presentationDetents` — snap-to-fraction sheet heights | **Missing** | A modal's size is whatever its blueprint measures to. Building detents would need canvas-height-aware drag physics that do not exist; the closest primitive, `Grip`, is a 1-D value adjuster, not a sheet-height controller | zero occurrences |
| Toast / transient feedback surface | **Covered** — no SwiftUI built-in | `presenter.presentToast`, with pure headless scheduling: max 3 visible, queue cap 8, priority-ordered FIFO, four typed dismiss reasons, reduced-motion parity, and input-transparent by construction | `src/present/toast_schedule.luau` (351 lines) |
| Semantic feedback bus | **Covered** | `presenter.onFeedback`/`emitFeedback` over the closed 12-verb taxonomy, wired into surface lifecycle and toast supersession. LuauUI still plays nothing (§7) | `src/present/feedback.luau` |
| Focus trap and restore | **Covered** | Scope push/pop/remove on the focus graph, used by modals and transient popups alike. Row actions' floating menu reusing it unchanged is evidence the mechanism generalizes beyond its original proving ground | `src/input/focus_graph.luau` |
| Passive (non-capturing) surfaces | **Covered** | `responder = "passive"` plus explicit `engage()`/`resign()`, so a surface can sit over a live 3D world without stealing its input | [`ADR-0014`](../adr/ADR-0014-first-responder.md) |
| Display-order layering | **Covered** | Five named bands (base < toast < dragProxy < modal) with an explicit guarantee, rather than one incrementing counter | `SURFACE_LAYER` |
| Full-value disclosure plate; auto-reveal marquee | **Covered** — no SwiftUI equivalent | `presenter.disclosure()` shows a truncated value in full on a presenter-private surface with no focus scope and no input context; `presenter.reveal()`/`movingText()` animates long text into view | — |
| Surface enter/exit transitions | **Covered** | `opts.transition` on `present`/`presentModal`; `dismiss` defers teardown to the exit coordinator under a flat 500ms cap | [`ADR-0022`](../adr/ADR-0022-sponsor-framework-gaps.md) Decision 3 |
| Keyboard-only modal dismissal | **Partial** — engine constraint | Gamepad ButtonB is bound to Cancel; Escape is not bindable (§7) | — |

---

## 10. Performance

LuauUI has serious performance instrumentation: nine named production-shaped
workloads in a self-contained lab place, p50/p95/p99 headless timing, live heap
and reactive-graph counters, nine closed MicroProfiler phase scopes (a *fixed*
set — the scope count does not grow with row count), and — the most durable
piece — regression budgets encoded as **ratio tests rather than wall-clock
thresholds**. Those five rules (work scales with what changed; a cache key must
cover what it caches; nothing unchanged gets rebuilt; an unchanged value fires
nothing; the cheap path stays cheap) are each annotated with the real historical
regression that motivated them, so they cannot be quietly deleted as flaky.

Real instance-cost wins have shipped and been measured: instance recycling,
theme-aware recycling, incremental layout (141→8 arranged nodes, ~17×), eliding
inert containers (137→91 instances, −34%), and lazy `UIScale` (about −10%
instances framework-wide).

**The unavoidable caveat: none of this has ever run on a physical device.**

| Capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| Named, production-shaped workloads | **Covered** | Nine: `idle-baseline`, `mount-ramp`, `dense-scroll`, `dense-scroll-native`, `collection-churn`, `layout-style-churn`, `large-text-overflow`, `async-image-churn`, `lifecycle-soak` | `bench/perf_scenes.luau`; `examples/performance/lab/perf_lab.luau` |
| Percentile timing | **Covered** | p50/p95/p99, headless | `bench/perf_runner.luau:413-415,461-471`; `tools/perf.sh` |
| Regression budgets as executable tests | **Covered** — stronger than a wall-clock gate | Five invariant/ratio rules, each tied to the regression it once caught | `bench/perf_budgets.json`; `tests/perf_principles.spec.luau` |
| Heap / reactive counters | **Covered** | `handle.controller.stats()` reports property writes, rect writes, creates, removes, arranged and skipped counts; a lifecycle census counts GuiObjects, signals, memos, and scopes, proven zero-drift across 8 identical mount/unmount cycles | — |
| Profiler phase attribution | **Covered** | Nine closed phases: `mutate`, `react`, `measure`, `arrange`, `commit`, `mount`, `resource`, `scenario`, `reset` | `src/core/profile.luau` |
| Per-property invalidation granularity vs SwiftUI | **Covered**, with one counterexample | A single bound-value change costs the same at 100, 800, and 3200 rows — work scales with what changed, not with what exists, enforced as a ratio test. Incremental layout narrows that change from a full-tree re-solve to its relayout boundary (~17× measured). The counterexample is the next row | `tests/perf_principles.spec.luau`; `tests/incremental_layout.spec.luau` |
| Cell recycling for composite-wrapped rows | **Missing** | LuauUI's instance recycling works and is proven for an *unwrapped* row shape, but `VirtualList` has no cell-recycling seam for a row wrapped in extra structure. Crossing the virtualization window boundary destroys and recreates that structure — coarser than SwiftUI's `List`/`LazyVStack`, which reuse cell identity. This is what makes swipe actions cost +57%/+81% (§5.1) and would affect any future consumer wrapping a `VirtualList` row | `docs/plans/row-actions-perf-mission.md` |
| On-device performance measurement | **Missing** | `artifacts/phase-4/perf.json` records `"deviceRun": false`, `"authoritative": false`, `"evidenceLevel": "E1"`. The budget file's `skippedDeviceBudgets` lists `phone-physical`, `desktop-retail`, and `console-physical` as all pending. The full phone-capture procedure is documented in enough detail for an agent to execute — the artifact slot is simply unfilled | `artifacts/phase-4/perf.json`; `bench/perf_budgets.json` |
| Xcode Instruments equivalent | **Partial** — headless only | Headless percentile timing with versioned budgets. No on-device, symbolicated, UI-specific profiler. Xcode 27's Instruments added Processor Trace, an updated CPU-counters instrument, expanded concurrency visibility, and a hitches metric; LuauUI has no counterpart | `tools/perf.sh`, `tools/bench.sh` |

**Caveats.**

- The lab place ships with a build doctor and a scriptable driver, and its
  low-end-Android capture procedure is written so that a Studio row relabeled as
  a phone cannot spoof it. It still has not been run on hardware.
- The one honest thing about the swipe-actions perf miss is procedural: the gate
  was re-baselined to the measured ceiling with the original budget kept on
  record, and a named follow-on charter filed — not silently passed, not deleted,
  not converted to a TODO.

---

## 11. Tooling & authoring model

This is where LuauUI most clearly optimizes for something SwiftUI does not:
**being maintained by agents as well as humans.** Unknown properties are refused
at construction with a did-you-mean suggestion and the full valid set enumerated.
51 exported `*Spec` types describe the public constructor surface. And a family of
checkers reconciles independent views of the same truth so they cannot drift:
one reconciles six views of every declared property (schema, dirty map, render
authority, adapter, layout, docs, types); one verifies every public export is
classified in the surface ledger; one verifies documentation matches the live
export table; one lints the example gallery against the framework's own live
role vocabularies.

What it lacks is the interactive half of Xcode: there is no live, hot-reloading,
resizable in-editor preview, and no compiler-enforced type safety comparable to
Swift 6 — Luau cannot provide it, so LuauUI's answer is a fast, comprehensive
runtime/test-time layer instead.

| SwiftUI / Xcode capability | Verdict | What LuauUI has | Evidence |
|---|---|---|---|
| Strict construction-time validation | **Covered** | `UI.Button({ lable = "hi" })` → *unknown property 'lable'. Did you mean 'label'? Valid properties: …* | live reproduction, `src/blueprint_schema.luau` |
| Typed public constructor surface | **Covered** | 51 exported `*Spec` types (27 in `blueprint.luau` alone, the rest across controls, motion, layout, drag, transitions). Public core types are re-exported at the boundary; `grep -c ": any" src/init.luau` returns 1, and that one is inside an explanatory comment | `src/init.luau:36-40` |
| Property-authority reconciliation | **Covered** — no Xcode analogue | `tools/lune/check_prop_parity.luau` reconciles six independent views of every property. It exists because a bound `Text.color` was once silently dropped between two of those views | `tools/lune/check_prop_parity.luau` |
| Conformance registry | **Covered** | Every control must appear with its proofs; enforced by a test, so a control cannot ship unregistered | `tests/conformance/controls_registry.luau` (919 lines); `tests/extension_checker.spec.luau` |
| Docs-vs-code drift check | **Covered** | `check_docs.luau` holds documentation to a zero-tolerance list against the live export table | `tools/lune/check_docs.luau` |
| Example-gallery drift lint | **Covered** | Reads its role vocabularies live from the framework; fails on raw numbers for style-owned properties, unknown role strings, raw colors, or reaching around the public API into the engine | `tools/lune/check_example_drift.luau` |
| Public-surface ledger coverage | **Covered** | Every top-level export and nested namespace member must be classified in the surface ledger | `tools/lune/check_surface_ledger.luau` |
| Client/server require-graph boundary check | **Covered** | 97 source files, 379 consumer files, verified acyclic and correctly split | `tools/lune/check_boundary.luau` |
| Gate system | **Covered** | 25 named gates, plus an integrity checker that verifies every gate's test grep is anchored to the pass marker (a grep that could never fail is itself a defect), plus automated re-running of prior gates | `tools/lune/gate_manifest.luau`; `tools/check_manifest_integrity.py` |
| Scriptable in-Studio verification | **Covered** | A `LuauUIScenarioAPI` folder of BindableFunctions lets an external driver run scenarios inside a live Studio session | `examples/gallery/scenarios/runner.luau:1359` |
| Deterministic render dumps | **Covered** | Every control exposes a `dump()` seam, required by the scaffold template and the registry, so layout output can be diffed exactly | `tests/conformance/corpus_cli.luau` |
| Runtime diagnostics surface | **Covered** | `controller.diagnostics()` returns a defensive copy of live layout complaints. Project history records this surface naming a shipped layout defect that a screenshot review had missed | `renderer.luau:3754-3756` |
| Reference apps as scale proofs | **Covered** | Five clean-room apps (§12) | `examples/reference/` |
| Extension scaffold and playbooks | **Covered** | `tools/lune/scaffold.luau` stamps a new control's source seam, dump surface, deliberately-failing spec, and registration edits, so a scaffolded control cannot ship silently unregistered. Six playbooks cover new control / engine feature / platform mode / render target / theme / skinned control | `docs/extending/` |
| Deprecation policy | **Covered** | A machine-readable `LuauUI.DEPRECATIONS` ledger; a deprecated surface keeps working for at least one minor version | [`ADR-0011`](../adr/ADR-0011-semver-and-deprecation.md) |
| Fuzz / fault / soak testing | **Covered** | Layout, replication, and scheduler fuzzers plus a fault-injection suite | `tests/fuzz_*.spec.luau`, `tests/faults.spec.luau` |
| `#Preview` — live, resizable, hot-reloading in-editor preview | **Missing**, mitigated | No in-editor live preview exists for LuauUI. Mitigated by deterministic dumps, the reference-app corpus, scripted Studio drives, and the showcase place — but all of those are batch, not interactive. Xcode 27 added interactive resize handles to Live Previews; LuauUI's device matrix is the scripted analogue | — |
| Compiler-enforced type and concurrency safety | **Partial** — runtime-enforced | `--!strict` Luau plus the checkers above plus a 4048-case suite, all running in seconds. It catches misuse at test time, not edit time. Swift 6's strict concurrency is compiler-level and Luau cannot match it | — |
| Documentation tooling | **Covered** — a stronger claim than generation | Three checkers together make it impossible for documentation, the live export table, and tutorial examples to drift from shipped code without failing a gate. DocC generates and publishes documentation; it does not enforce that documentation is true | — |

**Caveats — where the machinery does and does not help.**

The agentic-maintainability claim holds up, and the row-actions branch is its
best evidence: the registration checker caught a missing conformance row *and*
an implementer's incorrect claim that the failure predated their change; a
second trap in the same task exposed the checker's own name-matching pattern
being blind to underscore-containing exports (passing when it should have
failed); an architectural decision about which directory a module belonged in
was steered directly by the registry's shape of enforcement; and the adversarial
review pass found 16 issues under an all-green suite — the registry catches
*absence*, adversarial review catches *presence of wrong behavior*, and they are
complementary.

**But the machinery is a backstop, not a preventer.** It refused to let mistakes
merge; it rarely stopped the first occurrence. One class of mistake — an agent
sweeping a whole shared file it did not own — recurred at least five times on a
single branch. That is a process and isolation problem (multiple agents in one
working tree), not a tooling defect, and no checker fixes it.

One residual weakness this pass did not re-investigate: a fuzzer that
asserts only "does not throw / stays finite / is deterministic" can pass over a
real behavioral bug. The historical `ScrollView` horizontal-axis defect is the
named example of exactly that.

---

## 12. Reference-app validation

The question underneath this whole document — *can a developer build the
in-experience parts of Apple's own reference apps from one declarative
description?* — was answered by building five of them clean-room. Ledgers and
evidence: `artifacts/swiftui-reference-app-validation/`.

| Proof | Interprets | Representative loop proven |
|---|---|---|
| Glade (`examples/reference/p1_glade`) | Backyard Birds | supply drain/refill, visit schedule, premium consumables, three-tier subscription-shaped commerce with scripted rejections |
| Cartwheel (`p2_cartwheel`) | Food Truck | adaptive split navigation, live order arrivals, a status machine and service-owned countdown that survive navigation, charts, entitlement gates, and a `UI.Stage` 3D hero |
| Sipworks (`p3_sipworks`) | Fruta | catalog/search/favorites, orders plus reward stamps plus threshold redemption, purchase-shaped recipe unlock, deep localization including plural fixtures and a ≥1.4× pseudo-locale, and a compact entry flow reusing the full components |
| Foyer (`p4_foyer`) | Roblox app home screen | sectioned discovery feed, friends carousel, search collapse, refresh and visit command lifecycles |
| Wardrobe (`p5_wardrobe`) | Roblox app avatar editor | try-on with undo/redo history over a live `UI.Stage` mannequin, purchase lifecycle with visible rejections, split ⇄ stacked layout survival |

All five carry their adaptation through `UI.ViewThatFits`, `UI.AdaptiveStack`,
and `UI.Composition`/`UI.Region` with **zero device-name branches** — the
strongest available evidence that the adaptive-layout story is real rather than
demo-shaped.

**Honest approximations the proofs declare.** Where a SwiftUI original does
something LuauUI cannot, the proof says so instead of faking it: shared-element
and hero transitions become a materialize modal (no matched-geometry subsystem);
3-D perspective card flips become width collapses; UI-over-UI blur is not
attempted (an engine limit); area-fill charts become banded strips (Roblox's
`Path2D` is stroke-only).

**Apple host-OS surfaces are never simulated.** Widgets, App Clips, Live
Activities, Dynamic Island, WeatherKit, StoreKit and Apple Pay chrome, and Sign
in with Apple are all recorded as **no host equivalent** rows in the ledger. They
are not gaps in LuauUI; they are operating-system features with nothing on the
other side of the comparison. The complete per-feature classification lives in
that stage's `capability-ledger.md`, and its follow-on candidates (reactive
compact labels, a bindable `newLabel.title`, fill-inside-hug contribution, and
the rest) in its `framework-fixes.md`.

*One caveat on that ledger:* `capability-ledger.md:59` still reads "no
secondary-action/swipe model yet." That predates `LuauUI.newRowActions` and is
stale; **this document supersedes it** for the controls area (§5.1).

---

## 13. Durable gaps

Cross-cutting gaps that no single mission is scoped to close. Each names the
section that owns it.

| Gap | Verdict | Owning section |
|---|---|---|
| Assistive-technology bridge (screen readers) — nothing at all | **Missing** | §7 |
| Right-to-left and bidirectional text — nothing at all | **Missing** | §5, §7 |
| Materials / translucency; Apple's Liquid Glass | **Missing, and the gap widened** | §6 |
| `*Style` protocols — no way to substitute a control's rendering | **Missing** | §6 |
| Screen navigation (`NavigationStack`, `NavigationSplitView`), presentation detents, alert item-binding | **Missing / Partial** — surface stacking only | §9 |
| `matchedGeometryEffect`, `phaseAnimator`, `keyframeAnimator`, `.scrollTransition` | **Missing** | §8 |
| `layoutPriority` shrink negotiation; alignment guides | **Missing** (the former deliberately) | §4 |
| No container unifying virtualization + reorder + selection | **Missing** | §4 |
| Cell recycling for composite-wrapped `VirtualList` rows | **Missing** — the concrete lever the perf work needs | §10, §5.1 |
| Physical-device performance measurement | **Absent** — `deviceRun=false`, evidence level E1 | §10 |
| Gesture machinery fragmented into four non-sharing implementations | **Confirmed** | §7 |
| `#Preview`-equivalent interactive authoring loop | **Missing** (no Roblox analogue), mitigated by scripted drives | §11 |
| Palette `Picker`, indeterminate `ProgressView` | **Missing** | §5 |

---

## 14. What still requires a physical device

**Nothing in LuauUI has been confirmed on physical hardware.** Every four-input
claim above rests on headless test runs (evidence level E1) plus Roblox Studio
emulator drives (E3). No E4 row has ever been filled.

The six checks below are owed by the row-actions work specifically. Each is a
single check a human can run in well under a minute with the `row_actions`
scenario selected and playing. Source: `artifacts/row-actions/device-matrix.md`.

| Check | What to do |
|---|---|
| Touch capture vs native scroll | On a real touch device, swipe a list row *mostly vertically*, starting on the row: the list should scroll (not the row), and no residual horizontal offset should remain on the row after release. |
| Scroll steals pan | Fling the list hard enough that it is still decelerating, then touch down on a row and immediately drag horizontally: the row should still open — native momentum scrolling must not eat the gesture. |
| Shift+Return on real hardware | Hold physical Shift and press Return on a focused row: the action menu should open, not the row's own primary action. This exercises the real engine modifier-binding path, which headless tests can only simulate. |
| Releasing Shift mid-chord | Press Shift, press Return, then **release Shift before releasing Return**: the menu should open exactly once — no double-fire, no stuck-open state. Real-hardware release ordering that a scripted sequence cannot reproduce. |
| Same-frame gamepad chord | Press ButtonX and a D-pad direction in the same physical input frame: the menu should open *and* D-pad navigation inside it should still work — the same-frame ambiguity must not swallow one of them. |
| Multi-touch bleed | With two fingers, touch down on two different rows at once and drag both outward (opposite trays): each row's tray should open independently, and the one-open coordinator must not cross-close one because of the other's claim. |

Three older riders also remain open and are not repeated in full here: physical
confirmation of the Dynamic Type equivalent at the Largest preference, a
subjective feel pass on the same, and physical confirmation of the engine
selection bridge. See `artifacts/large-text-accessibility/acceptance.md` and
`artifacts/native-substrate/acceptance-ledger.md`.

---

## 15. Verification appendix

| | |
|---|---|
| LuauUI version | `0.9.0` (`src/init.luau:90`) |
| Audit date | 2026-08-11 |
| Method | Nine independent fresh-context passes, one per area (state & reactivity, layout, controls, styling, input & accessibility, motion, performance, presentation, tooling), each verdict cited against source or a named test |
| SwiftUI baseline | Shipping surface plus Apple's **June 2026 / Xcode 27** update (WWDC26, iOS 27) |
| LuauUI baseline | Source only: `src/blueprint.luau`, `src/init.luau`, `src/controls/`, `src/layout/`, `src/render/`, `src/present/`, `src/client/`, `src/motion/`, `src/themes/`, `src/input/`, plus `tests/conformance/controls_registry.luau` |
| Raw per-area findings | `.superpowers/sdd/row-actions-implementation/audit/{state-reactivity,layout,controls,styling,input-a11y,motion,performance,presentation,tooling}.md` |

Every check below was run live for this report:

```bash
cd GameStudio/ui/LuauUI
./run-tests.sh                                    # 4048 passed, 0 failed, exit 0
lune run tools/lune/check_registration_cli        # PASS — 16 controls, 87 exports documented,
                                                  #   153 specs registered, 15/15 four-input + paradigm
lune run tools/lune/check_boundary                # PASS — 97 src files, 379 consumer files
lune run tests/conformance/corpus_cli             # a11y-l10n-corpus: 15/15 passed
lune run tools/lune/check_docs_cli                # PASS — 8 documents, 77 surface anchors,
                                                  #   64 local links, 7 themes exports, 11 stale phrases absent
lune run tools/lune/check_prop_parity_cli         # PASS — 25 classes, 438 properties, 2 diagnosed
lune run tools/lune/check_surface_ledger          # PASS — every public export and nested member classified
python3 tools/check_manifest_integrity.py         # exit 0 — 650 suite greps, all anchored to the pass marker
python3 tools/check_row_actions_matrix.py         # exit 0 — functional matrix intact, perf within
                                                  #   re-baselined ceilings (steady ≤57%, fling ≤81%, ≤5 instances)
```

Counts quoted in §11, reproducible:

```bash
grep -c '^\t\["' tools/lune/gate_manifest.luau                        # 25 gates
grep -rc '^export type.*Spec' src/ | awk -F: '{s+=$2} END {print s}'  # 51 exported Spec types
grep -c ': any' src/init.luau                                         # 1 (inside an explanatory comment)
```

**A note on section numbering.** Section 12's heading text is load-bearing:
`tools/lune/gate_manifest.luau` greps this document for the literal strings
`## 12. Reference-app validation`, `no host equivalent`, `UI.Stage`, and
`measured per-preference constants` as part of two closed gates. Renumbering or
rewording that heading breaks a passing gate; the other section numbers are free.
