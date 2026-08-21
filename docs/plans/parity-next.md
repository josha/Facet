# Plan: the next work toward SwiftUI-quality authoring on Roblox

**Status:** Written 2026-07-24 as a revised proposal; **status table refreshed
against shipped reality 2026-08-13** (see "Where this stands today" and the
milestone table at the end). This plan changes no runtime code.  
**Governing platform correction:**
[`roblox-native-audit-corrections.md`](roblox-native-audit-corrections.md).

> **Read the audit verdict below as a dated snapshot, not as current state.**
> It was written on 2026-07-24 and several of its findings — "no `ViewThatFits`,
> adaptive stack, or custom-layout protocol", "the current primitive calculates
> overflow but does not provide native scrolling" — describe a build that no
> longer exists. The current inventory is
> [`../reference/swiftui-parity.md`](../reference/swiftui-parity.md), rewritten
> 2026-08-13 with a citation on every verdict. The ten investments and the
> priority rules are still the governing plan; only the *state* claims are
> historical.

## Outcome

Facet should let a Roblox developer describe a screen once and rely on the
framework to make it usable, appropriate, and efficient on phones, tablets,
desktop computers, and television/console setups. A future spatial target should
fit the same model without forcing every game screen to be rewritten.

That goal is larger than matching a list of SwiftUI type names. The useful parts of
SwiftUI are the authoring guarantees around the controls:

- common layouts and controls are easy to express;
- state, identity, environment, focus, and presentation compose predictably;
- standard controls carry accessibility and platform behavior automatically;
- a view can adapt to available space without duplicating the whole screen;
- previews and diagnostics make mistakes visible before release.

Facet adds Roblox-specific guarantees SwiftUI does not need: semantic Input Action
System integration, simultaneous input classes, ten-foot presentation, server-owned
state adapters, headless deterministic tests, and world-space render targets.

## Audit verdict

The detailed inventory in
[`../reference/swiftui-parity.md`](../reference/swiftui-parity.md) is substantially
correct about the currently exported controls and layouts. Its original 69-item
count is a bounded catalog, not a percentage score for all of SwiftUI. The 2026
validation adds several conclusions that change the work order:

1. **Authoring safety is a release feature.** Blueprint constructors accept unknown
   property names today. A misspelled or unsupported property can be frozen into a
   node and then ignored by the renderer. This is especially damaging to agent-made
   changes because a plausible-looking screen can silently omit behavior.
2. **Adaptive layout is central to “write once.”** Facet exposes size facts but
   makes each screen branch manually. It has no `ViewThatFits`, adaptive stack, or
   custom-layout protocol.
3. **A real ScrollView is foundational.** The current primitive calculates overflow
   but does not provide native scrolling or clipping. Table and VirtualList each
   carry their own scrolling behavior.
4. **Roblox-native styling replaces the proposed custom style-protocol priority.**
   Native StyleSheets, state selectors, tags, and the Style Editor should cover the
   common restyling need. A SwiftUI-like rendering-replacement protocol should be
   added later only for behavior native styling cannot express. Step 2 established
   native paint and palette themes, but not metric-aware or asset-backed theme
   packages; that cross-cutting gap follows the Step 3 control vocabulary.
5. **The performance foundation exists but the product claim is unproven.** The
   repository already records p50/p95/p99 headless timings and regression budgets for
   named scenes. Those runs use a fake target and deliberately mark themselves
   non-authoritative. There are no completed low-end-phone, console, or VR device
   measurements.
6. **The extension workflow is unusually strong.** The control and render-target
   scaffolds, four-input proof registry, deterministic dumps, lifecycle neutrality,
   fault tests, fuzzers, and gates are a real advantage. They do not yet compensate
   for weak public types, silent properties, stale guide examples, or incomplete
   conformance registration.
7. **SwiftUI moved further in 2026.** General container reordering, generalized
   swipe actions, gesture-source and velocity APIs, key-press handling, stronger
   focus interaction, sensory feedback, and spatial event data now belong in the
   comparison. They reinforce the need for reusable semantic interaction layers
   instead of control-specific input code.

Official comparison sources:
[SwiftUI overview](https://developer.apple.com/documentation/swiftui),
[SwiftUI June 2026 updates](https://developer.apple.com/documentation/updates/swiftui),
[SwiftUI layout fundamentals](https://developer.apple.com/documentation/swiftui/layout-fundamentals),
[SwiftUI gestures](https://developer.apple.com/documentation/swiftui/gestures), and
[SwiftUI accessibility fundamentals](https://developer.apple.com/documentation/swiftui/accessibility-fundamentals).

## Priority rules

Use these rules when two items compete for time:

1. A silent wrong result ranks above a missing convenience.
2. A capability that helps every screen ranks above a specialized control.
3. Automatic cross-platform behavior ranks above a recipe every screen must repeat.
4. Roblox-native mechanism ranks above a parallel custom mechanism when it meets the
   behavior and evidence bar.
5. A control is unfinished until its layout, reachability, platform idiom, focus,
   disabled behavior, preferred-text behavior, and teardown are proven.
6. Headless timing is a regression signal. Only a real Roblox device run can support
   a device-performance claim.
7. APIs should make the correct path easy for both a new developer and an agent with
   no repository history.

## The next ten investments

### 1. Make the public authoring surface strict and self-explaining

This is the prerequisite for adding more API surface.

- Reject unknown public properties at blueprint construction with the control name,
  bad property, and valid alternatives. Reserve a separate internal channel for
  framework metadata such as input contributions.
- Give every primitive and composite an exported, useful spec type. Remove `any`
  from public constructor boundaries where Luau can express the contract.
- Reconcile the property schema, dirty classification, render authority, adapter
  binding, documentation, and tests. Every declared property must either work, be
  diagnosed as unsupported, or be removed through the deprecation policy.
- Resolve known examples such as `Text.color` and reactive style hints rather than
  leaving a property that schedules work which the adapter drops.
- Make a documented extension seam actually public, or mark it internal. In
  particular, recipes should not require a direct import of an otherwise unexported
  input-contribution module.
- Register every public primitive in an appropriate conformance category. Structural
  nodes may be non-interactive, but they should not be invisible to the registry.
- Add a docs/example drift check so the getting-started path and public-surface list
  stay aligned with the shipped API.

Acceptance: misspelled properties fail immediately in headless tests and Studio;
public examples type-check; an agent can add a small control using only the guide and
receive a clear failure for each omitted contract; the existing valid API remains
compatible or follows the documented deprecation window.

### 2. Make `ScrollView` a real native-backed container

Use `ScrollingFrame` for live clipping, momentum, touch pan, wheel behavior, scroll
bars, and native scroll state. Keep the pure solver responsible for content geometry
and keep a headless scroll driver.

The public construct needs vertical and horizontal axes, a readable/settable offset,
scroll-to-visible, programmatic positioning, and a virtualization integration seam.
Table and VirtualList should consume that one substrate after it is proven rather
than keep separate hand-written scroll systems.

Acceptance: nested interactive content, touch momentum, wheel, gamepad focus
keep-visible, horizontal scrolling, safe areas, resize/orientation changes, and
teardown pass in headless tests and Studio. Reparenting into the native host must not
break style rules, paths, drag detectors, or logical identity.

### 3. Finish `Button` as the base control

`Button` should support custom visual content while keeping a required semantic
label. Add semantic roles such as default, cancel, and destructive; enforce the hit
floor in solved/hit geometry; and make disabled behavior affect focus, activation,
appearance, and semantics consistently.

The visual states belong to native StyleSheets. Custom content must remain inside one
activation surface and must not create duplicate focus or activation sites.

Acceptance: text, icon-and-text, and icon-only buttons work on pointer, touch,
keyboard, gamepad, and hybrid devices; roles produce tags/semantics and style rules;
every button meets the effective target floor; disabled and destructive cases are
covered in alerts, menus, and normal screens.

### 4. Add the Slider and Stepper value-control family

Both controls should share a clamped value model, formatting, bounds, step behavior,
disabled rules, semantic value text, and the existing focus-gated `Adjust` action.

The live slider begins with `UIDragDetector`, as required by the native correction.
Keep a pure value/session model and headless driver. Pointer and touch may update
continuously; keyboard and gamepad use predictable increments. Do not make a
continuous thumbstick mandatory unless product testing shows it improves control.

Acceptance: drag, tap-to-position if chosen, keyboard/gamepad adjustment, bounds,
formatting, hot input switching, reduced motion, right-to-left direction, and
teardown pass. Roblox styling owns hover, press, focus, disabled, and role paint.

### 5. Add automatic adaptive-layout tools

Size facts alone do not deliver write-once UI. Add:

- a `ViewThatFits` equivalent that tries candidate layouts in declared order using
  the real measurement contract;
- an adaptive stack that can change axis and spacing without rebuilding unrelated
  state;
- container-relative conditions for compact, regular, wide, and ten-foot
  presentation without branching on device names;
- an explicit custom-layout extension point only after the two common constructs
  prove what the contract must expose.

Adaptation should be based on available space, distance, live interaction classes,
and accessibility facts. “Phone,” “Xbox,” and “VR” should not appear as screen-level
layout branches when the real requirement is width, viewing distance, or input
capability.

Acceptance: one settings screen and one dense HUD use the same semantic tree across
phone portrait/landscape, tablet, desktop, console/ten-foot, preferred-text sizes,
and hybrid input. State and focus survive each live change.

### 6. Complete the everyday layout vocabulary

Fix `Grid` children with fill dimensions and make `Spacer` expand along a stack's
main axis by default. Add composable `frame`, `padding`, `offset`, `overlay`,
`background`, `aspectRatio`, `layoutPriority`, and alignment tools. Add `Divider` as
a small axis-aware primitive.

Modifiers need explicit rules for identity, order, reactivity, and property
authority. A modifier must not silently write a value another subsystem owns.

Acceptance: inventory grids, forms, toolbars, overlays, badges, responsive cards,
and 16:9 media require no manual pixel positioning; narrow or enlarged text has a
defined compression/wrapping result; modifier order is documented with executable
examples.

### 7. Package the common display and selection controls

After Button and the layout work, add the high-leverage small constructs:

- determinate linear `ProgressView` and an axis-aware `Divider`;
- `Label` with icon/title slots and a semantic text fallback;
- segmented and inline Picker presentations;
- `DisclosureGroup` with correct focus updates;
- `Gauge` and radial progress on `Path2D` only after the path spike proves authored
  curves, clipping, layering, and device cost.

Raise PopupButton rows to the enforced target floor and adapt popup presentation when
the platform idiom calls for a menu, inline list, or larger touch sheet. Do not create
a separate visual-state system for these controls.

### 8. Generalize collection interaction

SwiftUI's current direction is instructive: reordering and swipe actions apply to
containers, not only one List type. Facet should similarly provide reusable pieces:

- one virtualized, selectable, reorderable collection substrate;
- native-backed drag sessions with payload and legal-drop policy kept in pure Luau;
- edge autoscroll and stable identity;
- a semantic secondary-action model that maps mouse secondary click, touch
  long-press/swipe, keyboard, and gamepad to context actions;
- reusable row actions, deletion confirmation, and context menus.

Use `UIDragDetector` and native `GuiObject` touch events for recognition. Facet owns
normalization, arbitration, hot-switch behavior, focus, and headless drivers.

### 9. Make semantics, presentation, and motion framework services

Standard controls should automatically carry semantic role, label, value, state,
available actions, focusability, and feedback intent. Keep this useful even where
Roblox exposes no screen-reader bridge; do not confuse the renderer's current
`semantics` dirty class or prose contract strings with an accessibility tree.

Add reusable navigation and presentation constructs after the foundation: screen
path navigation, alerts with safe defaults and button roles, confirmation dialogs,
anchored popovers, sheets, and paged `TabView` where `UIPageLayout` proves suitable.

Separate three kinds of motion:

- StyleSheet transitions for native style changes;
- value animation for numeric/geometry values;
- interruptible structural choreography for insertion, removal, and multi-stage
  sequences.

All three honor reduced motion and deterministic completion/cancellation contracts.
Sound and haptics remain semantic feedback events whose assets and policy belong to
the game.

### 10. Prove performance and preserve a path to spatial UI

Extend the existing benchmark system; do not replace it.

- Keep the named Lune scenes and their p50/p95/p99 regression budgets.
- Add console/ten-foot to the headless profile matrix and add production-shaped
  scenes for a large virtual list, native scroll/drag, a dense Sponsor-like HUD,
  stylesheet state churn, async images, and mount/unmount churn.
- Add a Studio/device capture path that records real frame work, Facet update time,
  live Instances and connections, memory, input-to-visible latency where measurable,
  and engine/game build. Store device results separately from headless trends.
- Establish budgets from the supported frame target and measured baseline. Do not
  invent a “low-end Android” service-level claim from desktop Lune timings.
- Gate regressions on at least the weakest supported touch device and the supported
  console/ten-foot path before calling the framework performance-proven.

For future spatial support, define only the extensibility contract now:

- environment facts can describe flat versus world presentation, viewing distance,
  and available spatial pointing without naming a headset model;
- semantic actions remain Activate, Cancel, Navigate, Adjust, Drag, and secondary
  action where possible;
- a normalized pointer event can later carry a selection ray, three-dimensional hit,
  device/hand pose, handedness, phase, and target while two-dimensional controls keep
  using the same callbacks;
- render targets can add `SurfaceGui` alongside the existing screen and billboard
  targets;
- focus, hover, target sizing, occlusion, comfort, and performance receive physical
  VR tests before Facet claims VR support.

Roblox exposes `VRService`, user-frame tracking, a GUI-input frame, and a laser
pointer mode, while its own VR guidance makes stable high frame rate a comfort
requirement. Those are reasons to preserve the seam, not evidence that current
Facet screens already work in VR.

Sources: [Roblox `VRService`](https://create.roblox.com/docs/reference/engine/classes/VRService),
[Roblox VR guidance](https://create.roblox.com/docs/production/publishing/vr-guidelines),
and [Roblox UI render spaces](https://create.roblox.com/docs/ui).

## Post-foundation desktop keyboard fidelity

The focus graph and semantic actions already provide the right substrate, but the
desktop binding contract remains incomplete: Tab/Shift+Tab traversal, Space
activation, and arrow adjustment for focused value controls are not automatic. Add
them through the existing focus/responder and Input Action System path in
[`desktop-keyboard-navigation.md`](desktop-keyboard-navigation.md), not through a
second graph or screen-local key listeners. This cross-cutting stage follows the API
constitution so new public options, if any, use the same patterns as the rest of the
framework.

## Post-foundation large-text accessibility

Preferred text must become a live layout input rather than a generous reservation
guess. Follow
[`large-text-accessibility.md`](large-text-accessibility.md): prove the Roblox
measurement and paint seam across `Medium`, `Large`, `Larger`, and `Largest`; reflow
before truncating; keep essential content fully reachable; and permit moving-text
disclosure only as a bounded, engaged, reduced-motion-safe last resort. Prove the
policy across public controls and on the production Rascal Rally Sponsor presenter,
including compact mobile portrait and landscape. This inclusive-design stage must
not claim a screen-reader bridge Roblox does not expose.

## Cross-cutting stage after the everyday control vocabulary

Once Milestone B is stable, add the public theme-package contract in
[`theme-packages-and-skinning.md`](theme-packages-and-skinning.md). Roblox
StyleSheets remain the paint and visual-authoring authority. Facet adds only the
bridge required for solver-owned geometry: versioned packages, semantic font/spacing/
control metrics, one exported effective snapshot, font-aware measurement, and bounded
native or nine-slice decoration slots.

This stage is required for the same “write once” promise as adaptive layout. A
palette swap alone does not prove that a compact desktop theme, a larger glossy touch
theme, or an ornate game skin can reuse the same screen. The mounted all-controls
fixture must swap among materially different packages and prove that solved and
actual geometry, focus, state, accessibility floors, failure fallbacks, and resource
cost remain correct across the device matrix.

## Milestone order

| Milestone | Investments | Exit condition | Status (2026-08-13) |
|---|---|---|---|
| 0 — trustworthy authoring | 1 | Invalid public UI fails clearly; guides and types match the runtime | **DONE.** Strict schema with did-you-mean refusals, 55 exported `*Spec` types, `check_prop_parity` reconciling six views of every property plus a class-restriction cross-check, `check_docs`, `check_surface_ledger`, `check_registration`, 25 gates |
| A — adaptive foundation | 2, 5, 6 | Common screens scroll and adapt without device-specific copies | **DONE**, and extended past its own bar. Native `ScrollingFrame`-backed `ScrollView` on both axes; `ViewThatFits`, `AdaptiveStack`, `Composition`/`Region`; the everyday layout vocabulary completed by parity round 2 (`distribute`, `layoutPriority` × `shrinkWeight`, `lineAlign`, `GridRow` + `gridSpan`, `containerRelativeFrame`) — see §4.1 of the parity doc for the resulting native-flex superset |
| B — everyday controls | 3, 4, 7 | Button, value, progress, label, and selection families pass all supported profiles | **DONE.** `Button` as a container with roles and an enforced hit floor; `newSlider`/`newStepper`/`newRating`; `newPicker`, `newPopupButton`, `newDisclosureGroup`, `newLabel`, `Divider`; `newProgressView` now determinate **and** indeterminate (bar + spinner). 15 of 15 interactive controls prove four-input and the paradigm axis. `Gauge` remains unbuilt (the `Path2D` spike bar was never met) |
| B.5 — theme packages | Cross-cutting styling contract | Public packages change paint, font/metrics, and bounded chrome; the solver reflows without remount or source edits | **DONE.** [`ADR-0019`](../adr/ADR-0019-theme-packages.md) + [`ADR-0020`](../adr/ADR-0020-rich-skinning-v2.md): 17 decoration slots, up to 8 art layers each, atomic install/swap, a `"pixel"` rendering mode, `selectBy` |
| C — rich interaction | 8, 9 | Collections, gestures, presentation, semantics, and motion use shared contracts | **MOSTLY DONE, with two named holes.** Delivered: drag sessions with typed payloads and three acquisition paths; edge autoscroll; `newRowActions`/`newRowActionsCoordinator` with turnkey integration on **both** `Table` and `newVirtualList`; `Table.onPrimaryAction`; the closed 12-verb feedback bus, now authorable as `UI.sensoryFeedback` with an opt-in `HapticEffect` adapter; presentation surfaces, toasts, focus trap/restore, `bindPresent`; and `presenter.withAnimation` closing the last of the three motion kinds this investment asked for. **Not delivered: screen-path navigation** (no `NavigationStack`, no alerts/confirmation-dialog constructs, no `TabView`) and **no single virtualized + selectable + reorderable substrate** — `Table` and `VirtualList` still divide those capabilities |
| D — proof and future platform seam | 10 | Real-device evidence exists; spatial extension is possible without claiming untested support | **NOT DONE, and the blocker is unchanged.** The headless half is complete and then some — 20 named scenes, p50/p95/p99, five executable ratio budgets, 12 profiler scopes, and a measurement discipline (stated same-arm noise floor, interleaved ABBA arms, ≥5-run means). **Zero physical-device measurements exist**; `artifacts/phase-4/perf.json` still records `deviceRun: false`, and `phone-physical` / `desktop-retail` / `console-physical` are all `PENDING_PHYSICAL`. The spatial seam is preserved and no VR claim is made ([`ADR-0021`](../adr/ADR-0021-spatial-seam.md)) |

Milestone 0 should finish before the public surface grows. Native StyleSheet work may
run alongside Milestones A and B after property authority is settled. Sponsor-required
framework work can pull a later item forward, but must use the same reusable contract
and cannot embed RascalRally policy in Facet.

## Where this stands today (2026-08-13)

Milestones 0, A, B and B.5 are closed; C is closed but for navigation and the
unified collection substrate; **D is the only milestone whose exit condition is
still structurally unmet**, and the thing standing in its way is a person with a
phone, not more code.

**What parity round 2 closed** (`parity-round2.md`, merged as `a42ef97`
and `be37e92`; suite 4534 green):

| Gap this plan named | Closed by |
|---|---|
| investment 6 — `layoutPriority` | `layoutPriority` (tiers) × `shrinkWeight` (proportional), running in **both** solver passes |
| investment 5 — container-relative conditions | `UI.containerRelativeFrame(bp, { axis, fraction })` and the paging form, measured against the nearest ancestor viewport rather than the immediate parent |
| investment 6 — the everyday layout vocabulary | `distribute`, `lineAlign`, `UI.GridRow` + `gridSpan`, and the inert-placement-prop audit that makes "a property that is accepted must do something" checkable |
| investment 9 — motion as a framework service | `presenter.withAnimation(class, fn)` — position only, decorative, reduced-motion branch that installs nothing |
| investment 9 — sensory feedback | `UI.sensoryFeedback(bp, { trigger, event })` over the closed 12-verb bus, plus one opt-in `HapticEffect` client adapter, default off |
| investment 7 — indeterminate progress | `value = nil` selects indeterminate; `presentation = "bar" \| "spinner"`; registered `informational` so reduced motion steps it rather than freezing it |
| investment 8 — collection interaction | `Table.onPrimaryAction`; hosted `rowActions` on `newVirtualList`, which also restored the row-actions perf gate to its **original** ≤5 %/≤5 %/≤1 ceilings |

**Decisions this round made that close items rather than deferring them:**

- **No `*Style` protocols, ever** — investment 4's "Roblox-native styling replaces
  the proposed custom style-protocol priority" is now a settled architectural
  position, not a sequencing choice. The mapping a SwiftUI author needs is in
  §6.1 of the parity doc.
- **No `LazyVStack`/`LazyHStack` names.** `newVirtualList` is the one lazy
  collection surface and gained both axes; a constructor wearing SwiftUI's name
  over a uniform-extent requirement would be a parity claim the code does not
  honour.
- **`sensoryFeedback` emits; it never plays.** The adapter is the game's opt-in.

**What is now explicitly queued rather than vague:**

| Open work | Where it is scoped |
|---|---|
| Variable item extents in the virtualized collection | parity doc §4.2 — requirement plus both candidate designs and what each costs |
| Flow-wrap (`UIListLayout.Wraps`) — the one place Facet is behind Roblox's own layout controls | parity doc §4.1, §4.3 — its own mission, not a prop |
| `Toggle` cannot compose a `Label` (it is a leaf, not a container) | parity doc §5.3 |
| Baseline alignment and `.alignmentGuide` | parity doc §4.4 |
| Screen-path navigation, alerts, `TabView` | investment 9, unstarted |
| One virtualized + selectable + reorderable collection substrate | investment 8, unstarted |
| Physical-device performance evidence | investment 10 — the whole of milestone D |
| Unfulfilled placement intents found by the §2.1 audit (migrations that would move real pixels, each with its measured cost) | [`unfulfilled-placement-intents.md`](unfulfilled-placement-intents.md) |

## Relationship to Sponsor Mode

Sponsor Mode is a demanding acceptance case, not the framework architecture. It
raises the priority of native scrolling, virtualized reorder/drop, drag sessions,
`Path2D`, adaptive layout, async images, interruptible choreography, banners/toasts,
world targets, semantic feedback, and device performance.

The game-specific implementation and its retained rollback path are governed by
[`../../../../../games/RascalRally/docs/FACET_SPONSOR_PARALLEL.md`](../../../../../games/RascalRally/docs/FACET_SPONSOR_PARALLEL.md).
The Facet presenter became the production default on 2026-08-03; legacy remains
shipped and untouched behind `UseFacetSponsor = false`.

## Completion standard

This plan is complete only when:

- a new author or agent gets immediate, actionable errors for invalid UI;
- one semantic screen adapts across every supported layout/input profile without
  screen copies;
- native Roblox mechanisms own live scrolling, drag recognition, style, and other
  adopted engine behavior at the adapter edge;
- common controls carry input, focus, hit-target, disabled, semantics, and platform
  idioms automatically;
- public theme packages can change palette, typography, density, control metrics,
  and bounded rich chrome through native Style Editor authoring while solved and
  actual geometry remain aligned;
- all Roblox preferred-text values update mounted UI exactly once; public controls
  and Sponsor View reflow without overlap or inaccessible essential text on compact
  mobile portrait and landscape;
- headless regression evidence and real-device performance evidence are labeled and
  gated separately;
- guides, API reference, examples, registries, and public types describe the same
  surface;
- no VR support claim is made until a physical spatial-input, world-target, comfort,
  and performance matrix passes.
