# Facet: distance and gamepad adaptation audit

Date: 2026-09-09. Scope: framework audit and implementation plan, requested against Apple’s tvOS guidance. Baseline: Facet `370a2a96`, including the current working tree. No runtime changes were made. Existing changes to screen presentation, its performance test, the changelog, and the PerformanceLab place were left in place.

**Finding: the concern is justified. Facet has strong input plumbing and substantial distance scaling, but some of its automatic compositions still behave like desktop controls traversed by a controller.** The clearest failure is directional: a pair of vertical button columns inside an `HStack` navigates as one horizontal sequence. The broader missing layer is semantic presentation for lists, settings, and navigation between panes.

This is a source and headless behavioral audit, not a physical-console usability certification. Apple’s examples and documentation were reviewed; no native SwiftUI comparison app, live Roblox visual walkthrough, or couch-distance playtest was run. Visual and ergonomic judgments below identify changes to prototype and validate, rather than measured readability failures on hardware.

**Game and engine review:** the decisions below are for a reusable game UI framework. Correct direction, legibility, explicit activation, and continuity transfer well from tvOS. Sidebar placement, sparse card layouts, and focus-driven presentation changes are task-dependent hypotheses. Their adoption requires improvement in a game task. Gameplay input ownership and bounded engine cost are release requirements from the first phase.

## What the references actually imply

Apple treats television use as a distinct interaction context: distant viewing, directional focus, deliberate activation, readable content, and restrained animation. Those concerns apply to Facet on a TV. Directional predictability and low interaction cost also apply to a gamepad on a small screen. [Apple: Designing for tvOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-tvos/).

The supplied LobeHub page could not be fetched, but its [underlying tvos-design skill](https://github.com/dirnbauer/webconsulting-skills/blob/main/skills/tvos-design/SKILL.md) was retrieved through GitHub. It is useful for focus visibility, focus memory, legibility, simple input, and reduced motion. Several prescriptions need qualification:

- Top tabs are one option. Since tvOS 18, `NavigationSplitView` defaults to a floating sidebar; `.balanced` retains the earlier collapsed-stack behavior. A sidebar is therefore not simply an iPad or desktop pattern. [Apple: tvOS 18 release notes](https://developer.apple.com/documentation/tvos-release-notes/tvos-18-release-notes).
- Apple also demonstrates `TabView` with `.sidebarAdaptable`, which collapses navigation and gives content more room. This is appropriate for peer destinations; split navigation expresses a selection-to-detail relationship. These are different jobs. [Apple: Migrate your TVML app to SwiftUI](https://developer.apple.com/videos/play/wwdc2024/10207/).
- Apple currently lists 29 pt as the default tvOS text size and 23 pt as the minimum, rather than making 29 pt a universal minimum. These are Apple logical units, not automatically Roblox pixels. [Apple: Typography](https://developer.apple.com/design/human-interface-guidelines/typography?changes=_5).
- The skill’s 250×150 card size is not a universal control minimum. Apple lists 66×66 pt default and 56×56 pt minimum control sizes; spacing also matters. [Apple: Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).
- “Every swipe moves” must allow genuine boundaries. “Never trap focus” must allow a modal that contains navigation and offers Cancel. Mandatory parallax, Siri, Top Shelf, and native media integrations are not requirements for a Roblox framework.

The supplied [Oxagile article](https://www.oxagile.com/article/tvos-focus-engine-navigation-guide/) usefully distinguishes spatial defaults from deliberately authored exceptions such as looping. Its examples are a secondary design discussion; the technical basis for this plan is Apple’s focus documentation and demonstration of focus sections. Apple shows a full-height category section making a short sidebar reachable from lower grid rows. That is exactly the kind of intent Facet needs to express through its existing graph. [Apple: The SwiftUI cookbook for focus, final tvOS example](https://developer.apple.com/videos/play/wwdc2023/10162/?time=1288).

## Game tasks determine the presentation

Apple’s game guidance emphasizes precise controls, familiar menu bindings, controller-appropriate labels, and customizable bindings. Roblox likewise treats input as contextual: gameplay and menu actions can have different ownership. These references support adapting to the player’s task and platform; they do not prescribe a streaming-app shell for a game. [Apple: Game controls](https://developer.apple.com/design/human-interface-guidelines/game-controls), [Roblox: Input Action System](https://create.roblox.com/docs/input/input-action-system).

| Game task | Preferred starting point | Constraint on this plan |
|---|---|---|
| Main menu or pause/options | Short action list; category tabs where needed; obvious Resume/Back | No mandatory sidebar or extra activation just to reveal core commands. The game decides the initial action and whether anything pauses. |
| Inventory, garage, loadout, crafting | Grid/list plus stable detail and comparison area; category tabs or sidebar if useful | Keep equipped state, candidate stats, costs, and differences visible together. Collapse panes only when usable content cannot fit. |
| Familiar quick actions during play | Existing RadialMenu, direct prompt, or hotbar | Preserve learned compass slots and explicit hold/release or tap completion. Do not replace these with a slower list just because the input is a controller. |
| HUD, race timing, scoreboard, combat feedback | Glanceable, spatially stable information; explicit engagement for interactive HUD | Passive information does not acquire focus. Preserve the view of gameplay and meaningful data density. |
| Map, skill tree, board, placement tool | Spatial task with declared neighbors or continuous pan/zoom/aim as appropriate | UI geometry is a fallback. A game’s map links, board cells, and continuous controls retain their declared semantics. |
| Codex, quest log, store catalogue | Search/filter plus list/grid and detail; sidebar is a candidate | Browsing patterns apply here, but confirmation and server validation remain separate from focus and preview. |

Use Facet’s existing [Choosing controls](../guide/14-choosing-controls.md) as the starting decision route. A new reusable mechanism must solve a demonstrated gap in at least two representative compositions, such as settings and a garage, before expanding the public API. The minimal nested-focus correction does not need to wait for a new navigation container.

“Less dense at distance” means removing competing detail and improving reading hierarchy where needed. A racing scoreboard or equipment comparison can benefit from several aligned columns. Test it against the actual reading task before converting it into oversized cards or serial detail pages. Keep artistic themes and compact handheld layouts when they meet legibility and interaction requirements.

### Gameplay ownership is part of every UI decision

Use the existing [passive, engaged, and modal responder modes](../guide/07-input.md#73-the-responder-chain-ui-in-a-game-with-an-avatar). A passive speedometer must not consume steering, jump, or camera input. An engaged inventory or modal claims the actions its contract owns and releases them predictably. A quick-action overlay may intentionally coexist with gameplay; the game declares that policy through shared Facet mechanisms.

Opening a UI surface must not imply pausing simulation, a race timer, networking, or other players. A multiplayer pause menu may only be a local menu. The game owns pause/resume, scene changes, timeouts, and server-authoritative equip/purchase rules; Facet owns focus, presentation lifetime, and action dispatch. Keep focused, previewed, pending, selected, and equipped states distinct where the game needs them. A rejected server command must not leave an item painted as equipped or unexpectedly relocate focus.

Test the handoff with buttons and sticks already held. A press that opened or closed a menu must not also activate a destination or trigger a gameplay action. Clear UI repeat and capture on dismissal, ownership loss, or disconnect; decide explicitly whether the returning gameplay action resumes continuously or requires a fresh press. Do not globally neutralize controls that the game intentionally continues to own. A disconnect or focus loss must never execute a radial choice by accident.

Use platform-supported bindings and the existing action system. Roblox reserves Escape and ButtonStart for its menu, so this plan must not promise either as an interceptable custom pause key. Present hints from the active binding/controller scheme, including game-authored remapping; do not introduce a second rebinding store in Facet. [Roblox: Input Action System, default bindings](https://create.roblox.com/docs/input/input-action-system#input-bindings).

Directional navigation, Activate, and Cancel are a baseline route through conventional menus. They are not a restriction on gameplay, maps, analog adjustment, or efficient quick actions. Retain shoulders, triggers, both sticks, hold actions, and direct shortcuts where appropriate, with alternatives for menu functions that would otherwise be inaccessible. A Siri Remote is a useful simplicity stress test, not the definition of a gamepad.

### Engine constraints on implementation

- Keep one focus graph and eligibility authority. Use explicit topology for grids, radial sectors, and authored connections; use solved geometry where topology does not answer. Fix nested group derivation before considering a broad spatial-search implementation. Add an index only if profiling demonstrates a need.
- Update navigation data when relevant layout, visibility, eligibility, scroll, or ownership changes. Do not rebuild all candidate pairs every frame or scan off-window inventory items for each directional press. Preserve key-based virtualization and stable tie-breaking. Focus animation must not invalidate navigation geometry continually.
- A focus move must not reconstruct the whole screen or reload a model. Coalesce expensive preview work during fast traversal and discard stale results after focus or scope changes. Buttons respond immediately; decorative animation must not delay action dispatch, Back, or Resume.
- Bookmarks are bounded presentation data owned by the navigation lifetime. Clear them on the appropriate profile/session/domain reset and invalidate missing keys. Do not retain evicted instances, item models, or unbounded history to remember focus.
- Keep engine input, safe-area, text, and accessibility facts at the existing adapter boundaries. Portable focus/layout policy remains testable headlessly; no UIKit dependency or screen-local input system. Keep screen, billboard, and world-surface semantics within their documented support, without implying ray/VR input support.
- Measure with active gameplay, long virtualized inventories, changing HUD data, and repeated open/close. Track p95/p99 UI time, end-to-end input feedback, frame spikes, allocations, live instances/connections, and idle work. Use the [existing performance budgets](../../bench/perf_budgets.json) and evidence classes; the declared console allocation is not measured spare capacity. No rebaseline merely to accommodate a new animation or focus search.

## Evidence from Facet

### 1. Automatic directional navigation can contradict the screen — P0, reproduced

The audit probe mounts this ordinary composition through the real presenter with a fake render target and gamepad bindings:

```text
HStack
  VStack: A       VStack: C
          B               D

From A: expected Down → B; Right → C.
Observed: Down → A; Right → B.
```

Run `lune run docs/research/2026-09-09-gamepad-audit-probe` from the Facet root to reproduce the current behavior. This is a characterization probe, not a passing acceptance test for the desired behavior.

The cause is visible in [focus_map.luau](../../src/present/focus_map.luau): horizontal-run derivation collects descendant focusables into one horizontal group. [focus_graph.luau](../../src/focus/focus_graph.luau), particularly `exitFrom` and `navigateDirection`, then steps ordinals or adjacent groups. `entry = "nearest"` is primarily an ordinal policy, not a comparison of solved rectangles. Explicit grid topology and exits work, but do not make arbitrary compositions spatially correct. [presenter.luau](../../src/present/presenter.luau) routes Navigate into this graph.

**Change:** preserve nested navigation regions and choose automatic directional neighbors from solved geometry. Extend the current map and graph, maintaining one eligibility set. Keep document-order Tab traversal as a distinct traversal of that same set. Retain explicit exits for authored exceptions and known grid lanes for stable collection navigation.

### 2. Distance detection contains an unsafe assumption — P0, policy gap

[adaptive.effectiveDisplaySize](../../src/layout/adaptive.luau) changes `Large` to `Medium` whenever touch is available. This fixed a real handheld misclassification, but capability is not viewing distance. A touch-capable laptop or handheld driving an external TV can still expose touch capability. Conversely, the source itself records an ordinary windowed desktop reporting `Large`.

The probe confirms `Large + touch → Medium`. Docked-device behavior is an inference requiring physical testing, not an observed failure in this audit.

**Change:** retain automatic inference, expose its provenance and uncertainty, and provide a central explicit near/distant presentation override that a host or user setting can supply. Preserve raw platform facts. Touch and controller connection must not overrule an explicit viewing context. Apply the resolved policy consistently to type, spacing, safe area, density, and navigation.

### 3. Navigation adapts placement more than navigation structure — P1, confirmed capability gap

[adaptive.navPlacement](../../src/layout/adaptive.luau) chooses top tabs for a roomy distant screen. Compact width and short height win earlier; the probe confirms a short distant surface resolves `bottomBarCompact`. Pointer-primary and gamepad-primary also select different homes, so some input switches can restructure navigation.

[TabView](../../src/controls/tab_view.luau) has a persistent sidebar placement, but no shared focus-expanding/collapsing sidebar behavior. [NavigationStack](../../src/controls/navigation_stack.luau) provides drill-down and focus restoration. The public catalog exposes no selection-driven split-navigation construct. A consumer assembling two panes does not automatically receive pane-entry, return, collapse, or focus-memory semantics.

**Change:** prototype selection/detail behavior using existing containers, then extract the reusable composition once settings and inventory/detail demonstrate the need. Compare TabView’s current strip/sidebar with a collapsing sidebar for peer destinations; ship the new presentation only where it improves task cost or usable content. Stable panes or shoulder-driven tabs may be better for loadout comparison. Keep short pause menus direct. Avoid moving navigation when the player nudges a mouse, and keep layout stable during an active adjustment or learned quick-action gesture.

### 4. Lists and settings lack a shared semantic row presentation — P1, confirmed gap

[The control guide](../guide/16-controls.md) explicitly describes forms as manually assembled ScrollViews, stacks, and controls. VirtualList owns windowing, not a platform-style list appearance. Table provides selection, actions, adaptive row metrics, and disclosure, but remains a table-oriented composition.

This distinction matters. A settings entry is often one action with a label, current value, and accessory. If authors assemble an independent label plus a small control, controller focus belongs to the small control, and the framework has no shared instruction to highlight or explain the whole setting. [Slider](../../src/controls/slider.luau), for example, intentionally paints focus on its thumb. That can suit an isolated slider while failing to identify the surrounding setting from across a room.

**Change:** provide a reusable semantic row with label, optional secondary text, value/accessory, activation, and adjustment semantics. Reuse existing controls and row actions. In a controller presentation, the row supplies one coherent focus identity and a visible whole-row treatment. Its decorative accessory is not an extra navigation stop. Rows with multiple independent actions need an explicit action-reveal or editing interaction. Build settings grouping on this row; a general form-validation framework is outside this plan.

### 5. Automatic menus still treat roomy gamepad use like pointer use — P1, reproduced policy

[menu_recipe.resolvePresentation](../../src/controls/menu_recipe.luau) considers option count, size class, and touch-primary. It does not consider distance or directional interaction. Twelve options on a regular gamepad surface resolve `menu`, with the compact control-height row recipe. [Menu](../../src/controls/menu.luau) makes compact surfaces single-panel, but roomy gamepad hierarchies can still use adjacent floating panels. [PopupButton](../../src/controls/popup_button.luau) shares the underlying rule.

This does not mean menus lack controller activation or cancellation; they have both. The missing adaptation is their presentation and navigation cost.

**Change:** prototype a bounded single-panel chooser for reading-heavy options and deep actions on distant or constrained controller surfaces. Select advances one level; Back returns one level with focus restored. Keep short inline choices and direct quick actions. Retain adjacent panels when they fit, preserve important comparison/context, and navigate clearly. Preserve RadialMenu’s learned directions for familiar game commands. The default must follow measured task efficiency, readable space, and interaction intent; gamepad availability alone does not force a sheet.

### 6. Distance typography is a multiplier, not a legibility guarantee — P1, verified arithmetic

[Neutral’s type roles](../../src/tokens/default_style.luau) are caption 12, label 14, body 16, heading 20, title 24, control 18. [The shared distance multiplier](../../src/themes/snapshot.luau) is 1.5, yielding 18, 21, 24, 30, 36, and 27 respectively before text preferences. The source comment refers to approximately 29 pt body text, while the test explicitly asserts `16 → 24`.

This is a mismatch between a stated intention and its evidence, not proof that 24 Roblox pixels equal 24 Apple points. Uniform scaling also preserves the desktop information hierarchy, including small secondary metadata.

**Change:** calibrate semantic distant type roles in a documented logical presentation space. Use Apple’s values as a comparison reference, then measure actual Roblox output at supported resolutions and viewing distances. Give essential secondary text a deliberate floor. Reuse `metrics.tenFoot` overrides and the existing measurement/paint split rather than adding another scale. Keep preference scaling and reflow intact.

### 7. Focus visibility and safe areas have foundations, but need contextual treatment — P1/P2

Neutral already provides a 4-unit distant focus ring and 1.05 focus scale; these are real improvements. The missing proof is whether rows, image cards, text fields, and value controls each communicate focus appropriately across themes and backgrounds.

Apple recommends a whole-row highlight for lists/collections and generally a ring for text entry. It also distinguishes moving focus from activating an item. A selected/equipped row needs to remain recognizable when focus moves away. [Apple: Focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection).

[environment.luau](../../src/env/environment.luau) supplies explicit overscan overrides and defaults of 90 left/right and 60 top/bottom on distant displays. Those defaults are fixed values. Their behavior across actual 720p, 1080p, and 4K render coordinates needs calibration; they should not be interpreted as a universal physical safe-area measurement.

**Change:** define row, card, field, and value focus recipes through the existing theme/presentation system. Reserve room for the focused bounds, including at scroll edges. Keep focus, selection, disabled, pressed, and editing states distinct. Reduced motion must preserve a strong static cue. Normalize default safe margins in the same logical presentation space, honoring explicit overrides and combining correctly with engine-safe areas. Background artwork can extend beyond content-safe bounds.

### 8. Returning to content can require repeated controller traversal — P1, documented behavior

[TabView](../../src/controls/tab_view.luau) deliberately disposes inactive content and documents reset scroll position and lost local editing state unless the caller owns them outside the tab. Eviction is sensible; making every caller reconstruct navigation continuity is a poor default for a controller. NavigationStack already captures page focus, which is a useful starting point.

**Change:** preserve lightweight presentation bookmarks by destination and item key: last focus, collection anchor, and relative scroll position. Restore after mount/layout, then fall back to a nearby surviving item. The game can reset or replace a bookmark when a match, profile, or task changes; a pause menu can deliberately start at Resume rather than the previously focused Quit. Keep data and drafts caller-owned, and allow content scopes to remain evicted. Do not retain entire screens merely to remember an item.

### 9. Input semantics are strong, but some convenience and editing contracts need review — P2

Facet already has semantic Navigate/Activate/Cancel/Adjust, modal restoration, disabled/hidden filtering, input arbitration, gamepad analog thresholds with hysteresis, and navigation repeat. [presenter.luau](../../src/present/presenter.luau) uses a 0.4-second initial navigation-repeat delay and 0.1-second interval. That repeat explicitly excludes Adjust. [TabView](../../src/controls/tab_view.luau) exposes shoulder adjustment only when its strip holds focus. These are existing policies to evaluate, not missing gamepad support.

**Change:** test long-list traversal, stick diagonals, repeat stopping at scope changes, value adjustment, and navigation out of controls at value boundaries. Supply a visible current action hint. Consider shoulder tab switching throughout the owning navigation region, subordinate to modal/editing control ownership and gameplay arbitration. Conventional menu functions need a direction/Activate/Cancel route; game interactions retain their appropriate analog and shortcut vocabulary. Evaluate hold-to-adjust separately from navigation repeat. A value at its limit should not unexpectedly send held adjustment input into another setting; define the clamp, explicit edit mode, or deliberate exit policy for that composition.

Apple distinguishes directional movement, intentional press, Back, and context-specific playback/game actions. Its current remote guidance explicitly allows game-specific Play/Pause behavior, unlike the skill’s blanket media-only rule. Transfer the predictable verbs and feedback to Facet; do not invent Siri Remote or dictation support in Roblox. [Apple: Remotes](https://developer.apple.com/design/human-interface-guidelines/remotes?changes=_9).

### 10. Evidence is concentrated on separate device categories — P1, verified coverage gap

[tests/lib/device_views.luau](../../tests/lib/device_views.luau) includes distant gamepad, touch phones/tablet, and pointer/keyboard desktop. It lacks a canonical near-gamepad row and a canonical hybrid row. Dedicated input tests do cover hybrid behavior, so those cases are not wholly untested, but shared visual/layout sweeps do not systematically exercise them.

A consumer example also shows why framework and authoring issues need separate labels: [Rascal Rally’s settings screen](../../../../../games/RascalRally/code/src/client/FacetSettingsScreen.luau) fixes the panel maximum to 340 and rows to 56, with literal padding and gaps. It is a useful pilot for long text and distant presentation. These authored dimensions are not evidence that Facet’s adaptive theme metrics fail. Its actual live presentation needs testing before calling it a shipped visual defect.

## What a list should become in each context

SwiftUI’s value as a reference is the semantic component choosing an appropriate presentation. Apple specifically describes tvOS list rows highlighting and slightly enlarging on focus, with room for rounded focused bounds. This differs from desktop multicolumn table conventions and touch-oriented disclosure/accessory interactions. [Apple: Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables).

The following is the proposed Facet design, not a claim that every native SwiftUI List uses one exact appearance:

| Concern | Near pointer/keyboard | Near gamepad, including handheld | Distant gamepad or remote-like input |
|---|---|---|---|
| Settings row | Direct access to control; clear keyboard order | One row stop, readable value, directional adjustment | Spacious highlighted row; clear label/value; explanation beside or below |
| Secondary action | Direct button/context menu | Revealed action group or labeled shortcut | Bounded action chooser with large readable rows |
| Collection | Dense table/grid when useful | Task-appropriate density; efficient navigation; near-size text | Readable task-appropriate density; preserve aligned comparison data; image cards where useful |
| Detail navigation | Concurrent panes when they fit | Split when usable; stack or overlay when constrained | Stable comparison/detail panes or collapsing navigation, chosen by task |
| Scroll feedback | Scrollbar and precise wheel | Focus reveal plus next-item visibility | Visible continuation and unclipped focused item |
| Current selection | Persistent selection marker | Selection marker distinct from moving focus | Selection marker distinct from large focus highlight |

For example, “Music volume — 70%” should be one understandable setting. Up/Down move between settings; Left/Right adjust where that row owns the axis. A complex editor opens deliberately. Explanatory copy belongs to the row or a stable detail region, rather than a tiny independent label whose relationship to a focused thumb is easy to miss.

For long informational text, provide a controller-scrollable reading region. Do not turn every paragraph into a fake button. For browse-only records, group navigation and scrolling should work even when a record has no activation action.

## Implementation sequence and acceptance gates

Each phase changes shared Facet mechanisms. Consumer screens supply content and state, not local focus or layout engines. Proposed API names and defaults must go through the repository’s written-decision, documentation, and compatibility process before implementation.

| Phase | Concrete work and owning files | Acceptance gate |
|---|---|---|
| 1 — Direction, context, and ownership | Fix nested automatic groups in `present/focus_map.luau`; extend `focus/focus_graph.luau` only where explicit topology is insufficient; centralize distance override/provenance in `env/environment.luau` and `layout/adaptive.luau`; pin input handoff through the existing presenter/action system | The A/B/C/D probe yields Down→B and Right→C. Unequal row heights, gaps, RTL layout, hidden/disabled items, and resize preserve meaningful directional movement. Explicit distance survives capability changes. Passive HUD and menu open/close do not steal or leak gameplay actions. Measure focus cost before expanding the algorithm. |
| 2 — Navigation composition | Prototype settings and inventory/detail with existing NavigationStack, TabView, scopes, and caller-owned state. Compare stable tabs/panes with a collapsing sidebar; extract only demonstrated shared behavior. Add bounded key-based bookmarks. | Re-entering a pane restores its valid item unless the game specifies a new task entry. Narrow/wide changes preserve selection and route. Comparison data remains available without needless page changes. Returning to a tab restores position without retaining its subtree. Any new sidebar beats or matches the existing game task flow. |
| 3 — Rows and choosers | Introduce shared semantic list/settings rows; extend existing control contributions and theme recipes; evaluate `controls/menu_recipe.luau`, Menu and PopupButton changes against direct and radial alternatives | A setting is one focus stop with a readable value; no duplicate accessory stops. Both gamepad sizes complete the same tasks. Reading-heavy nested choosers have clear level ownership and return behavior. Quick actions retain stable slots and efficient completion. |
| 4 — Distant visual calibration | Tune semantic distant type roles, density, row/card focus recipes, safe margins and focus overflow through `themes/snapshot.luau`, tokens, and presentation owners | Essential text is readable at the declared distance and physical display sizes. Focus is immediately identifiable across supported themes and representative game backgrounds. No clipping of focused bounds, no overlapping rows, and a usable static focus state with reduced motion. |
| 5 — Input and task efficiency | Audit repeat and analog direction resolution; define adjustment/editing escape behavior and scoped optional shortcuts; reuse input hints and feedback | One press causes one activation. Holding navigation never leaks into a newly opened modal or gameplay. Every editing mode has a clear exit. Conventional menu tasks have a direction/Activate/Cancel route. Quick actions and continuous game interactions retain their declared controller semantics and discoverable alternatives. |
| 6 — Integrated pilots and rollout | Add near-gamepad/hybrid canonical matrix rows; pilot pause/settings, inventory/comparison, live radial actions, and a long collection with active gameplay | Scripted paths pass headlessly and in Studio. Physical handheld and TV sessions meet usability and performance gates. Include disconnect, match transition, server rejection, and repeated open/close. Updated API/guide/changelog evidence accompanies each runtime change, plus full verification and local package checks. |

Start with phase 1’s smallest two-pane fixture and ownership handoff. Prototype phases 2 and 3 together in settings and inventory comparison on handheld and TV, while keeping live quick actions as a regression task. New containers and sidebar defaults are conditional on those results. A global size increase or ornamental redesign cannot resolve the reproduced directional error.

### Directional selection contract to settle in phase 1

The existing graph remains the authority. Candidate membership comes from the existing visible, eligible focus map. Use solved resting geometry so a focus-scale animation does not move navigation targets. At a boundary, prefer an explicit valid exit, then an appropriate neighboring region/candidate in the requested direction. Use overlap/alignment and distance with deterministic tie-breaking; define the exact ranking with asymmetric fixtures. Grid lane behavior should remain stable. Sections bridge intentional empty space and can remember their last focused child.

Keep virtual collection traversal key-based: it may reveal and mount the next logical item beyond the current window before focusing it. A geometry-only search over mounted items would regress existing long-list behavior. A modal’s scope boundary and an active control’s ownership outrank automatic geometry. Automatic finite spatial edges stop; explicit wrap or authored neighbors remain valid for game menus, boards, hotbars, and radial controls. Test those intentional transitions against their declared topology rather than marking every non-geometric move as an error. Tab can retain its own documented wrap policy.

### Navigation state contract to settle in phase 2

Separate focused item, selected destination, sidebar visibility, and detail route. Moving focus may update a harmless preview but must not equip, purchase, submit, or unexpectedly push a route. Activating a navigation row commits its destination. Back first leaves a nested editor or chooser, then unwinds the current navigation layer; behavior at the game’s root belongs to its existing UI/gameplay ownership contract. One Back press must never close several layers.

A collapsing sidebar should retain a visible navigation cue and a predictable entry path. Where a horizontal value control owns Left/Right, Back or a clear region exit must still make navigation reachable. On a compact handheld, collapsing to a stack must preserve the same selection and return bookmark; the handheld does not inherit distant typography merely because it has a controller.

### Required validation matrix

| Session | Minimum configurations |
|---|---|
| Distant TV | 720p, 1080p, 4K effective render sizes; 16:9; roughly 8–12 ft; real controller; known physical display size recorded |
| Near controller | 1280×720 and 1280×800 handheld/monitor layouts; 1920×1080 near monitor; physical controller |
| Hybrid | Touch+controller; mouse+controller; switching during navigation, editing, an open chooser, and scroll; dock/undock or display-change cases |
| Accessibility/content | Default and larger text; reduced motion; light/dark and decorative themes; longer localized labels; RTL; missing/disabled items; long lists |
| Game integration | Modal over gameplay, passive HUD, live radial actions, held-input open/close, focus loss, disconnect/reconnect, scene/match transitions, server rejection, and Input Action System configuration |

Use five repeatable game tasks: open pause/options, change a setting and resume; compare two loadout items, equip one and return; find an off-window item, reveal a secondary action and cancel; select a familiar radial action while gameplay remains visible; read a changing race result/scoreboard and continue. Run failure variants for disconnect, item removal, scene change, and rejected equip. Record key-by-key focus paths, action counts, scroll anchor, completion time, wrong-direction moves, recovery attempts, input leakage, and frame/latency measurements with the same gameplay load.

Proposed release gates: zero unreachable essential menu actions, unintended activations, focus traps, or gameplay-input leaks; zero wrong-direction transitions against automatic geometry or explicitly declared game topology; and exact bookmark restoration when valid and appropriate to the current task. Existing platform and performance gates must pass; sustained memory/connection growth across open/close cycles is a failure. UI animation must never gate Resume or action dispatch.

For a formative test with at least five people unfamiliar with the screens, aim for at least 90% unassisted task completion on both handheld and TV, with no conventional menu task requiring a pointer. Also test experienced controller players after familiarization: new navigation must not make repeated pause/resume or quick actions slower or require more actions than the baseline. Compare under the same gameplay load and investigate meaningful latency/frame regressions. Record actual observations rather than treating this small sample as population-level proof. Screenshots alone cannot establish usability.

## Verification performed for this audit

Eight existing spec files were run individually with `lune run tests/run_one <name>`; all 227 tests passed:

| Spec | Passed |
|---|---:|
| `focus` | 9 |
| `focus_grid_axis` | 25 |
| `paradigm_tenfoot` | 26 |
| `ten_foot_metrics` | 48 |
| `navigation_stack` | 23 |
| `tab_view` | 63 |
| `paradigm_input_axis` | 15 |
| `virtual_list_focus_policy` | 18 |

The additional [audit probe](../research/2026-09-09-gamepad-audit-probe.luau) reproduced the nested-column failure and printed the distance, navigation-placement, and popup-policy outcomes described above. These passing existing tests establish substantial foundations; they do not establish the missing paradigm behavior. This was not a full-suite, package, Studio, or physical-device run. Follow the distinction between evidence classes in [Device verification](../guide/11-device-verification.md).

The immediate next implementation should correct nested directional navigation and add the near-gamepad/hybrid fixtures that expose it. The first design prototype should then pair adaptive navigation with semantic settings rows, so the framework is evaluated on a complete controller task rather than individual reachable controls.

The game/engine revision adds task selection, input handoff, bounded runtime work, and live-game validation to those gates. It makes sidebar and chooser defaults conditional on game-task results. This revision changes the plan only; it does not claim any new runtime or hardware verification.
