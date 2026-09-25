# Facet: controls over Compose and Roblox

This is one breaking change in `codex/compose-ui-simplification`. It is not a
sequence of supported architectures. No deprecated aliases, compatibility host,
second scene, or migration runtime ships. The original checkout stays untouched.

## Final authoring contract

```luau
local Facet = require(ReplicatedStorage.Facet)
local Compose, Roblox = Facet.Compose, Facet.Roblox
local runtime = Roblox.createRuntime()
local Host = runtime.constructors
local UI = Facet.controls(runtime)

local stop = runtime.mount(function()
    local count = Compose.cell(0)
    return Host.ScreenGui {
        ResetOnSpawn = false,
        UI.Button {
            label = function(use) return `Count: {use(count)}` end,
            onActivate = function() count:update(function(n) return n + 1 end) end,
        },
    }
end, playerGui)
```

Every returned control root is a Roblox Instance owned by Compose. Native
properties, events and children use Compose's native constructor vocabulary.
Control options describe control behavior; they do not introduce another
property-binding, sizing, lifetime, target, or composition protocol. UI and 3D
can share the same runtime. Callers use Compose mounts, owners, portals, branches,
collections, boundaries and motion directly.

Facet has no `new`, `createHost`, application record, `mount`, `dispose`, target
factory, private domain nodes, renderer, general solver, or service reactor.
Its remaining code consists of controls, control-specific policies and native
styling/adaptation integration. Roblox targets are ordinary `ScreenGui`,
`SurfaceGui`, `BillboardGui` and `ViewportFrame` constructors.

## Whole-codebase replacement map

| Existing responsibility | Final owner | Remove or replace together |
|---|---|---|
| Application bootstrap and frame/lifetime orchestration | Compose Roblox runtime, caller's owner | `client/application`, `client/host`, application type/exports, application factories in examples/tests/bench, application scaffolder |
| Domain tree and property dirty tracking | Compose native Roblox host | `render/compose_scene`, domain half of `compose_controls`, blueprint/schema/classification, mounted-layout nodes and property-authority pipeline |
| Scene rendering and target adapters | Compose constructors and Roblox Instances | `render/renderer`, target contract, custom screen/billboard/surface adapters, engine-instance handle registry |
| General layout and text measurement | Engine layouts, constraints, AutomaticSize, TextBounds/TextService | general solver, wrapping approximation, premeasurement cache and settle loop; replace their callers with native layout objects |
| Virtual collection indexing, geometry, anchoring and ownership | `Compose.OrderedCollection` | Facet virtual-window/index/prefix/anchor machinery, duplicate row lifetime; native ScrollingFrame mirrors viewport and desiredOffset |
| Retained resource pool | `Compose.createPool` | Facet recycle arrays and custom capacity/lifetime bookkeeping; borrow pooled Instances during row ownership |
| Whole-screen/modal/navigation ownership | Compose owners, portal/show/LayerStack; control behavior in Facet | presenter stack, application present methods, custom mount registry; port modal focus/Back/dismiss behavior into controls |
| Focus geometry/navigation mechanism | GuiService, native selection groups/order/links | general focus graph and solved-rectangle navigation; retain explicit control-specific navigation rules |
| Input transport and drag mechanism | InputContext/InputAction, engine events, UIDragDetector | duplicate transport/context/lifetime model and pointer fallback; retain semantic control decisions and eligibility |
| Scroll mechanics and keep-visible | ScrollingFrame; control policy where needed | custom scrolling fallback, engine property mirrors and general scroll renderer |
| Styling, rich skins and theme swaps | StyleSheet/StyleRule/StyleLink and engine decoration | target-owned paint replication; retain semantic theme/skin definitions and only compilation the engine does not provide |
| Motion and transitions | Compose motion/presence plus native style transitions | Facet motion clocks, render transform channels and lifetime coordination; retain control-specific motion choices and reduced-motion policy |
| Display/accessibility facts | Native observations, Compose Roblox viewport/input helpers | service-owned environment replication; retain derived control policies, safe areas, preferred text size and viewing-distance adaptation |
| Images/async resources | Engine image loading; Compose shared resources for additional work | independent async ownership/cache framework where equivalent facilities exist; retain cancellation/stale-result policies that are still required |
| Replication/domain data | Consumer model and Compose readables | Facet application scaffolding for game/network state; preserve example server-validation behavior |
| Diagnostics and preview | Native Instances, Compose inspection, engine observations | solver/renderer diagnostics presented as runtime requirements; port useful control diagnostics and preview tools |

Native APIs above were checked against the local `creator-docs` engine reference,
including UIListLayout flex/wrapping, UIFlexItem, GuiObject.AutomaticSize,
ScrollingFrame canvas properties, GuiService.SelectedObject, InputContext,
UIDragDetector and ScreenGui.ScreenInsets. Native layout does not replace
control-specific decisions such as radial geometry or choosing an adaptive form.
Those remain small policies inside their controls, not a second general solver.

## Behavior inventory that must survive

| Control family | Preserve while changing implementation |
|---|---|
| Button, SplitButton, Chip, ShortcutHint | activation eligibility, repeat/shortcuts, busy/disabled states, semantic labels, input parity |
| Toggle, Stepper, Slider, Rating, LevelPicker | value/commit callbacks, range/step rules, drag and keyboard/gamepad adjustment |
| TextInput, ComboBox | native editing/IME/focus, draft versus committed values, filtering and selection |
| Picker, Menu, RadialMenu | available presentations, item identity, disabled items, outside/cancel behavior, selection and restoration |
| DisclosureGroup, CollapsibleView | controlled expansion, child ownership, focus behavior, adaptation |
| Alert, Callout, Sheet | presentation state, actions, cancellation, focus containment/restoration, responsive sizing and detents |
| NavigationStack, PageView, TabView | route identity, Back, selection, retention rules, adaptive outer navigation and shared durable model |
| VirtualList, VirtualGrid, Table, RowActions | keyed current-item reads, measured/variable extents, scroll anchoring, focus retention, follow behavior, sorting, selection and row actions |
| Label, Badge, StatusIndicator, ProgressView, Skeleton | semantic content/status, range and progress behavior, loading/motion policy |
| AsyncImage, Avatar, AvatarGroup | loading/failure behavior, shared content, cancellation and native image presentation |
| Stage and custom native content | Compose-owned embedded 3D, camera/content lifetime, error containment |
| Layout/adaptive composition | same application tasks and accessibility behavior through native layouts and small control policies |

`PopupButton` is an existing deprecated alias: delete it and change its callers
to the actual Picker/Menu control. Do not preserve an alias under the new API.
Do the same for other existing deprecated spellings.

## Coordinated execution

1. Fix the final public contract and inventory existing behavior before replacing
   more implementation. The native prototype is an experiment, not a second
   supported API and not a substitute for the inventory above.
2. Port control families and their policies onto native Compose construction.
   Reuse existing pure behavior where it remains necessary; do not replace rich
   controls with superficial lookalikes. Make collections depend on Compose's
   placement/status/controls, with no Facet index or anchor algorithm alongside.
3. Change all maintained consumers and scaffolding in the same worktree: gallery
   bootstrap/tutorials/scenarios, virtual monitors and desktop, reference apps,
   standalone consumer, performance lab, benchmark fixtures, preview/package
   tools, types and snippets. Use a codemod for repeated syntax changes once the
   target contract is fixed, not a runtime compatibility adapter.
4. Switch the root export and delete the old architecture and all now-unreachable
   support code. Audit source and generated artifacts for old imports/API calls.
   There must be one runtime path and no public factory that recreates the old app.
5. Port behavioral verification, run it, repair failures, and rebuild/check the
   package. Rewrite architectural checks to enforce the new contract rather than
   suppressing them. Remove only assertions about mechanisms actually deleted;
   preserve equivalent observable behavior coverage and record replacements.

This ordering is internal to one change, not permission to ship intermediate
states. Do not mark the task complete while both architectures remain.

## Completion evidence

- **Architecture:** no Facet application/scene/solver/renderer ownership path;
  no compatibility/deprecation shims; vendor snapshot unchanged and hash check
  passes; all maintained imports and public declarations use the final contract.
- **Behavior:** ported coverage for the inventory above, including modal focus,
  typing, accessibility, theme swap, teardown, collection reorder/measurement,
  and data/content preservation. A native engine double proves ownership and
  bindings; it does not prove real geometry or input behavior.
- **Gallery:** build and run the actual maintained gallery in Studio, exercise
  navigation and representative controls across input/size modes, record engine
  errors and native layout observations. Do not replace it with a smaller demo
  and call that regression proof.
- **Virtual monitors:** preserve Discover, Avatar and Chat, spatial/flat switching,
  filtering/sorting/saved data, embedded scenes and streaming conversation.
  Exercise interactions in Studio, including scroll after sorting and teardown.
- **Performance:** retain the existing workload intent when porting benchmarks;
  compare baseline and candidate without concurrent verification load. The
  original checkout already fails the recorded typing-storm gate; report that
  separately from regressions, never silently reset the baseline.
- **Repository:** `tools/verify.sh full`, formatting, package build and package
  status; report live/manual gaps and benchmark failures explicitly. A targeted
  green run or the pre-cutover monitor render is not completion evidence.

## Current status

The architecture has cut over: the public surface is Compose runtime construction
and Facet controls, and the old application, scene and solver code is deleted.
Public controls and generated scaffolds have strict type checks. The isolated
worktree remains uncommitted, and the user explicitly requested no PR yet.

Executable verification and live parity are separate. The latest consolidated
native suite passed 586 cases before subsequent live repairs and their additional
regressions. Unchanged performance gates passed; paired main measurements still
show three slower controlled paths. Final source requires another full run.

Live comparison has driven repairs to theme interpolation, collection workflows,
whole-card activation and source transitions, native Path2D properties, disclosure
ordering and contrast, and Callout sizing. Gallery and Virtual Monitors still have
explicit live input/geometry obligations; full parity is not certified. Track
current findings in `tools/lune/parity_blockers.json`,
`tools/lune/coverage_virtual_monitors.json`, and the local comparison artifacts.
