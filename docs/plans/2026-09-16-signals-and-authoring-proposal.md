# Facet: standard reactivity and simpler authoring

> Implementation refinement: the unified constructors are exported as `Facet.View`
> (`local UI = Facet.View`), preserving `Facet.UI` primitive callback contracts.
> See [the implemented guide](../guide/15-components.md).

Proposal for review, 2026-09-16. Facet inspected at `c71a1610`. No runtime or
public API changes are implemented by this document. Every “after” example is
proposed API, not code that works in today's Facet.

## Recommendation

Adopt Roblox Signals for the reactive dependency graph. Keep Facet's layout,
input, motion, adaptation, lifecycle, and diagnostic responsibilities in Facet.
Validate the compatibility seam before switching the default runtime.

Make the usual authoring unit a component that describes its children once.
Accept functions for changing properties, own subscriptions at the mounted
component boundary, and expose one composable UI vocabulary. Keep explicit
resource ownership as an advanced integration tool.

The substantial change is who does the bookkeeping. Shortening `own(observe())`
alone would leave authors responsible for the same mistakes.

## The mental model, in ordinary language

Think of a component as a little room:

1. **Describe what's in the room.** A button, a label, a list. Facet builds it
   when the room opens.
2. **Give changing labels a recipe.** `text = function() return count() end`
   means “keep this text equal to the count.” Facet remembers which values the
   recipe reads and updates the affected property when those values change.
3. **Buttons do things.** `onActivate` is an instruction to run when the player
   activates the button. A property recipe calculates an answer; an event does
   something.
4. **The room cleans up after itself.** Its listeners, local animations, and
   child components stop when it closes. The player's inventory belongs to the
   game and survives closing an inventory window.

The setup function runs once per mount. Property recipes run when needed.
Only an explicit conditional or collection changes the tree. Ordinary local
variables and ordinary `if` statements do not become reactive by magic.

Ownership still matters, but authors choose a lifetime once: component, row,
surface, or game model. They do not repeat that choice around every resource.

## What the current implementation tells us

| Finding | Evidence | Consequence |
|---|---|---|
| Properties already subscribe individually; node setup runs once | `src/mount.luau`, particularly `mountNode` and `dynamicProps` | Preserve this architecture; a whole-component render loop would discard an established advantage |
| Composite controls allocate resources before mounting and return handles | `src/controls/button.luau`, `toggle.luau`, `slider.luau` | Authors must manage both a handle and its `.blueprint`; move ordinary construction into mount lifetime |
| The observer in the request cancels a held button | `src/controls/button.luau:143` | It is a real side effect; shortening it must preserve its change-only behavior |
| Primitive and composite Button have different APIs and callbacks | `src/blueprint.luau`, `src/init.luau`, `src/controls/button.luau` | “Which Button?” is unnecessary knowledge for screen authors |
| Core is more than a graph | `src/core/contract.luau`, `custom.luau`, `scope_impl.luau` | Replacing it requires a behavior audit, not a rename of three constructors |
| Types and runtime validation have separate coverage | `tools/check_types.py`, `tools/lune/check_prop_parity.luau` | Existing green checks do not prove complete public contracts |

## Lessons from other systems

These are design inferences from the linked primary sources, not evidence that
any proposed Facet API is already faster or easier for users.

| System | Useful lesson for Facet | Choice for this proposal |
|---|---|---|
| [SwiftUI identity, lifetime, dependencies](https://developer.apple.com/videos/play/wwdc2021/10022/) | Stable identity connects state, lifetime, and transitions | Give components mount lifetimes and collection rows stable keys; preserve identity across adaptive layout changes |
| [React's JSX](https://react.dev/learn/writing-markup-with-jsx) and [guidance on effects](https://react.dev/learn/you-might-not-need-an-effect) | Compose views where their behavior is readable; derived UI usually needs no synchronization effect | Keep ordinary Luau tables and functions; use effects for external work and property functions for derived UI |
| [Solid's fine-grained reactivity](https://docs.solidjs.com/advanced-concepts/fine-grained-reactivity) | Component-shaped authoring can coexist with updates to individual consumers | Keep setup separate from reactive evaluation and retain Facet's property dirty classes |
| [Vide's scopes](https://centau.github.io/vide/tut/crash-course/6-scope.html) | Stable and reactive lifetimes make small reactive functions practical in Luau | Make component lifetime stable; bind evaluation must not accidentally create persistent controls or listeners |
| [Fusion's scopes](https://elttob.uk/Fusion/0.3/tutorials/fundamentals/scopes/) | Resource ownership and reverse cleanup are essential even in declarative UI | Automate ownership at a named boundary; retain deterministic teardown |
| [Amulet UI research](https://www.cs.cmu.edu/~amulet/papers/amuletca.abs.html) | Computed object properties, high-level input, and debugging support belong together | Treat declarative relationships and understandable diagnostics as part of the toolkit |
| [Roblox Input Action System](https://create.roblox.com/docs/input/input-action-system) and [UI containers](https://create.roblox.com/docs/ui) | Semantic input contexts and native surface containers are platform capabilities | Preserve Facet's existing input, focus, styling, and target mechanisms |
| [SwiftUI + RealityKit](https://developer.apple.com/videos/play/wwdc2025/274/) | A reusable view can attach to an entity while input and presentation remain explicit concerns | Make the surface and anchor declarative separately from the view's content |

JSX's main benefit here is readable composition, not angle brackets. A new
transpiler or Swift-like language would add installation and editor work before
it improves a single Facet control. Named `children` tables remain the first
version's composition syntax; aliases and chained modifier DSLs are unnecessary
for this change.

## Before and after

### 1. A property follows state

Before, using the current public core and a primitive:

```luau
local enabled = scope:own(core:memo(function(use)
    return use(canDrive) and not use(busy)
end))

local button = UI.Button {
    label = "Race",
    enabled = enabled,
    onActivate = startRace,
}
```

After, with `canDrive` and `busy` as proposed readable getter functions:

```luau
local button = UI.Button {
    label = "Race",
    enabled = function()
        return canDrive() and not busy()
    end,
    onActivate = startRace,
}
```

Facet evaluates this recipe under dependency tracking when mounted. It validates
the returned boolean initially and on updates. It changes enabled/input state
through the existing authority, without reconstructing the button.

A direct getter also works: `enabled = canDrive`. A snapshot is explicit:
`enabled = canDrive()` computes a fixed value during setup. That distinction
needs an early guide example and an actionable development diagnostic when
detectable. Do not claim that static types can distinguish every snapshot mistake.

### 2. Something must happen when a value changes

The exact current pattern:

```luau
scope:own(core:observe(enabled, function(on)
    if not on then
        stop()
    end
end))
```

After, inside a component or control setup:

```luau
ui.watch(enabled, function(on)
    if not on then
        stop()
    end
end)
```

`watch` records an initial value and calls the handler only on a subsequent
unequal settled value, matching `observe`. The handler is untracked; reads in
the handler do not silently expand the subscription. An optional
`{ immediate = true }` explicitly opts into initial notification. The component
keeps the disposer alive and releases it on teardown.

For work that must run initially and automatically track several dependencies:

```luau
ui.effect(function()
    local cancel = previewService.show(selectedCar())
    return cancel
end)
```

An effect's returned cleanup runs before its next execution and when its owner
unmounts. The example assumes `show` returns a cancellation function. Property
recipes and effect callbacks cannot yield. Existing async resources provide the
loading, cancellation, and stale-result path; async continuation lifetime must
not depend on an ambient component context.

Assigning a function to an ordinary local variable does not install a watcher.
Functions become reactive specifically in schema-declared property slots,
`ui.memo`, `ui.watch`, or `ui.effect`.

### 3. A complete reusable component

Before, a simplified current control composition:

```luau
local function counter(core)
    local scope = core:scope("Counter")
    local count = scope:own(core:signal(0))
    local label = scope:own(core:memo(function(use)
        return `Count: {use(count)}`
    end))
    local bump = scope:own(Facet.Controls.Button(core, {
        label = "Bump",
        onActivate = function()
            count:set(count:get() + 1)
        end,
    }))
    return {
        blueprint = UI.Screen {
            children = {
                UI.Text { text = label },
                bump.blueprint,
            },
        },
        dispose = function()
            scope:dispose()
        end,
    }
end
```

After:

```luau
local UI = Facet.UI

local Counter = Facet.component(function(ui)
    local count, setCount = ui.state(0)

    return UI.Screen {
        children = {
            UI.Text {
                text = function() return `Count: {count()}` end,
            },
            UI.Button {
                label = "Bump",
                onActivate = function()
                    setCount(function(n) return n + 1 end)
                end,
            },
        },
    }
end)

local h = host.new()
local surface = h.presenter.present(Counter {})
```

`Counter {}` creates a reusable description. Its setup runs when mounted, not
when declared. Two mounts receive independent local state. The surface owns its
mounted component tree; dismissing it tears down that tree. The host remains a
session resource with an explicit teardown at the application's boundary.

`ui` is an explicit component context with typed helpers. Helpers close over
the correct owner; ownership does not depend on a global “current component.”
Reactive dependency tracking is a separate, synchronous evaluation context.

The canonical `UI.Button` would gain the composite's semantic capabilities and
return a description like other UI nodes. Internal primitives stay available to
the library. Existing public primitive/composite signatures need a documented
migration; this proposal does not silently reinterpret old callbacks.

### 4. Editable state stays explicit

Before:

```luau
local soundOn = scope:own(core:signal(true))
local toggle = scope:own(Facet.Controls.Toggle(core, {
    label = "Sound",
    value = soundOn,
}))
-- place toggle.blueprint in children
```

After:

```luau
local soundOn, setSoundOn = ui.state(true)

UI.Toggle {
    label = "Sound",
    value = soundOn,
    onChange = setSoundOn,
}
```

Getters read; setters write. A computed getter cannot accidentally be treated as
writable state. Interactive value controls require a change handler; a declared
read-only presentation is a separate, explicit case. This also lets a game use a
command instead of a local setter, retaining server authority.

Use a named `ui.memo(function() ... end)` for an expensive calculation shared by
several properties. An inline function is the normal choice for a simple value
used once. Facet should not allocate an additional memo layer around an already
memoized getter merely for convenience.

### 5. Conditional children and collections

Retain the existing structural vocabulary, with automatic mounted ownership:

```luau
UI.When {
    condition = inventoryOpen,
    thenView = function()
        return Inventory { model = inventoryModel }
    end,
}

UI.ForEach {
    items = players,
    key = function(player) return player.id end,
    row = function(player)
        return PlayerRow { player = player }
    end,
}
```

Proposed collection contract: the key callback receives a snapshot; the row
callback receives a readable getter for the current item with that key. A row
reads `props.player()` inside property recipes and event callbacks. Replacing
an item under the same key updates that getter without recreating local state
or capturing stale row data. Reordering retains row identity. Duplicate keys
are errors; array indexes are not the identity of reorderable domain objects.

`When` unmounts an inactive branch; hiding a node preserves its local state.
Exit animations retain only the visual lifetime required to finish, with input
already deactivated. Virtualized rows own temporary view state; durable
selection, edits, and game data remain in the keyed model. Large collections
continue to use the existing VirtualList/VirtualGrid mechanisms rather than
making every `ForEach` virtual or fully mounting every inventory by default.

## Roblox Signals: migration findings

Inspected upstream revision:
[`7ef2ff7db01f6955cf7d9e5a0becb3129f7f8d60`](https://github.com/Roblox/signals/tree/7ef2ff7db01f6955cf7d9e5a0becb3129f7f8d60).
Its [Wally manifest](https://github.com/Roblox/signals/blob/7ef2ff7db01f6955cf7d9e5a0becb3129f7f8d60/wally.toml)
declares `0.9.0`; this is an inspected source revision, not a claim about release
availability or stability guarantees.

The [core source](https://github.com/Roblox/signals/blob/7ef2ff7db01f6955cf7d9e5a0becb3129f7f8d60/modules/signals/src/Signals.lua)
supplies signals, lazy computeds, and effects. The
[scheduler](https://github.com/Roblox/signals/blob/7ef2ff7db01f6955cf7d9e5a0becb3129f7f8d60/modules/signals-scheduler/src/SignalsScheduler.lua)
supplies batching and flushing. There is also an
[implicit-scope reference implementation](https://github.com/Roblox/signals/blob/7ef2ff7db01f6955cf7d9e5a0becb3129f7f8d60/modules/signals-implicit-scope/README.md).
The default project does not bundle that implicit module. It must be deliberately
included or used as the reference for a small Facet tracking adapter; it is not
an API that a normal top-level `require(Signals)` currently exposes.

Keep upstream graph code pinned, licensed, and unchanged. A small Facet adapter
can provide implicit getters and owner-aware helpers while using the upstream
graph. It should also evaluate raw official getters with their explicit tracking
argument, so existing Signals models can bind directly. A custom expression can
accept that argument when necessary:

```luau
enabled = function(track)
    return externalEnabled(track) and not externalBusy(track)
end
```

This interoperability is an implementation requirement to test, not a property
proved by the implicit-module probe. Simply calling raw getters with no tracking
argument would silently fail to subscribe. Do not maintain a second dependency
graph or translate every update through mirrored state to obtain interoperability.

### Executed behavioral probes

Six small probes ran under Lune against the pinned upstream modules. Only the
Roblox `script`-relative imports were replaced with relative filesystem imports.
The local files and runner are in `/private/tmp/facet-signals-review/`. These are
isolated semantic probes, not Facet conformance or performance measurements.

| Probe | Observed upstream result | Facet implication |
|---|---|---|
| Implicit derived boolean, dynamic dependencies, then effect disposal | Notifications `[true, false, true]`; no notification after disposal | The proposed concise read style has a working upstream foundation |
| Batch `0 → 1 → 0` with a direct signal effect | Notifications `[0, 0]`, including initial execution | `watch` needs last-delivered equality to preserve change-only observer semantics |
| Set NaN to NaN | Two effect executions including initial execution | Preserve Facet's NaN-safe equality at the adapter boundary |
| Write a signal inside a computed getter | Succeeded; getter returned 0 and signal became 1 | Facet's prohibition on writes in property recipes needs its own guard |
| Effect throws on value 1, then value changes to 2 | First setter threw; second succeeded; successful observations `[0, 2]` | Facet callback containment must be deliberate |
| Batch writes 3 then throws, followed by write 4 | Error rethrown; observations `[0, 3, 4]` | Matches the broad publish-before-rethrow grouping behavior in this probe |

The error tests used the flags module's non-engine fallback. Studio behavior,
including its flag path, still requires verification. These samples do not prove
all equality, failure-recovery, reentrant-write, or disposal cases.

Additional differences found by source/contract inspection:

- Upstream sources hold observers weakly. The effect's returned disposer must
  remain strongly referenced; component ownership must hold it, not just rely on
  garbage collection. See the [upstream lifetime warning](https://github.com/Roblox/signals#readme).
- Signals/computeds expose no deterministic `dispose` method corresponding to
  Facet's public signal/memo disposal and frozen-source diagnostics.
- The scheduler is module-wide; separate Facet cores currently have separate
  transaction/settle state. Cross-host batching and externally initiated writes
  must be covered, not assumed to be isolated.
- Facet promises observer order by source-node creation order, and registration
  order within a node. Upstream's weak-set traversal does not establish that
  contract. Test actual notification order rather than relying on coincidental
  table traversal.
- Facet's settle loop repeats layout/publication until quiescent, with a bounded
  feedback cap. No corresponding Facet settle API exists upstream.
- Facet's cycle paths, last-good-value quarantine, successful-evaluation-only
  dependency replacement, counters, and cleanup error handling need explicit
  compatibility decisions.

The recommended boundary is: upstream owns signal dependencies and invalidation;
Facet owns ordered delivery where required, UI commit/settle, mounted resource
lifetimes, and error reporting. Upstream batched updates must also trigger the
Facet commit path, including writes made through externally supplied setters.

The old Core contract is a migration checklist. Each row must either pass on the
adapter or have an explicitly reviewed replacement contract. In particular,
do not pretend raw Signals values can preserve explicit signal disposal simply
by changing the name to `dispose`. If preserving an old low-level promise
requires rebuilding the graph, reconsider that promise with the user before
shipping. Keep the current default until this seam is proven.

## Types: fix the contract, then prevent drift

Executed `python3 tools/check_types.py` on the inspected Facet revision:

```text
PASS — 29 Controls entries (25 typed, 4 declared any)
2 target files carry 0 diagnostics
782 graph diagnostics ignored by design
```

That last number is analyzer output under the current configuration, not a claim
of 782 independent runtime defects. The checker examines `src/init.luau` and its
witness file, and tests whether constructors reject a number. It does not prove
that every valid field or callback shape is typed. The property-parity checker
enumerates primitive blueprint schemas; composite spec key sets need coverage too.

Confirmed cleanup targets:

| Surface | Current gap | Required correction |
|---|---|---|
| `ButtonSpec` | Omits `image`, `imageAspectRatio`, `imageFraming`, `subtitle`, `row`, `pop` accepted by Button's key set | Type each field using its actual runtime grammar, including reactive/static distinctions |
| `ButtonSpec.onActivate` | Declares `() -> ()`; implementation passes metadata | Publish the current optional metadata argument and cover every input route |
| `ToggleSpec` | Runtime accepts `row`; exported type omits it | Shared semantic-row types, with control-specific restrictions |
| `SplitButtonSpec.onActivate` | Callback is typed with no arguments, but forwarded into controls with metadata | Trace both presentation forms and type their actual behavior |
| Chip, VirtualList, VirtualGrid, AsyncImage | Public constructors take `spec: any` | Proper specs; generic item/key/value relationships for collections |
| Slider and other partly typed specs | For example `value: any`, `enabled: any?`, `row: any?` in Slider | Concrete readable/writable types and nested records, not comments describing intended types |
| Activation pipeline | Primitive callback `(path, meta)` versus composite `(meta)`; `meta.pointer` can be a device string or a repeat boolean | First type the existing shape honestly, then normalize it in the new API |
| Handles and public helpers | Mixed `any` return/context/options surfaces | Audit constructor inputs, nested specs, callbacks, return handles, and generic relationships across all public exports and blessed client entries |

For the new API, use one event object. A proposed activation event has `path`,
`source` (`pointer`, `action`, `shortcut`, `repeat`, or `programmatic`), an
optional actual input device, modifiers, and optional position. Coordinates must
name their space. A repeat is a source, not a boolean masquerading as a device.
Do not invent a device when the input route does not supply it. Zero-argument
callbacks may ignore the event normally.

The implementation should first inventory every export against runtime reads,
validators, callbacks, docs, and type declarations, with a disposition per gap.
Put shared contract types in lightweight modules so adding types does not eagerly
load control implementations. Extend the existing parity/type tools rather than
introducing an unrelated schema generator.

Required checks: valid complete specs compile; invalid field values and missing
required fields fail; callback metadata is accessible with correct types; events
and property functions cannot be confused; list item/key generics propagate;
return handles expose their real methods. Cover direct annotated literals and
ordinary constructor calls under the pinned analyzer. Luau's structural typing
does not make all tables exact, so runtime unknown-key checks remain necessary.

Audit the whole require graph and client entry points with the appropriate
platform definitions. Classify existing diagnostics and eliminate public API
holes; do not simply expand an ignore list or cast whole implementations to
`any`. A compatibility baseline may track unrelated internal diagnostics while
the new public contracts and examples must be clean.

## UI in a 3D world

The near-term opportunity is a view that keeps its semantics wherever it is
placed. Surface placement belongs to the host; content belongs to the component.
The same Shop description should be usable on screen or on a terminal:

```luau
-- Proposed host convenience over the existing surface_target adapter.
local terminalHost = host.new {
    surface = {
        kind = "surface",
        target = terminal,
        face = Enum.NormalId.Front,
        canvas = { w = 800, h = 600 },
    },
}
terminalHost.presenter.present(Shop { model = shopModel })
```

A corresponding billboard host can use the same view. Existing world-anchor
projection should become an owner-aware helper for contextual screen overlays.
Explicit types distinguish canvas pixels from world studs and positions from
screen projections. Native target setup should supply correct input parenting,
and disappearance/streaming should suspend interaction and end the relevant
mounted lifetime according to the declared target policy.

Preserve semantic actions, focus restoration, input switching, theme adaptation,
reduced motion, and readable target sizes. A world target must not acquire its
own competing frame loop or input stack. Hidden/occluded UI must not remain an
invisible input target. Camera/anchor motion should use the existing transform
and presentation paths, not recompute text and layout by default.

Today Facet renders flat screen, billboard, and SurfaceGui canvases. This proposal
does not turn those into volumetric layout, VR, gaze, or hand input. Those need
separate capabilities, coordinate contracts, and device evidence. The authoring
model should leave room for them without requiring every screen author to learn
3D mathematics now. Preserve the documented target-specific limitations until
actual target tests establish support.

## How the simpler API preserves the established work

- Descriptions remain inert until mounted. Never-mounted components acquire no
  subscriptions. A mount failure cleans up partial setup.
- One mounted node keeps its identity. Property recipes feed the existing dirty
  classes; they do not rerun a component or reconstruct a subtree.
- Static props allocate no observers. Avoid redundant computed/effect layers
  and keep currently deferred controls deferred. Measure both cold require and
  first construction; type improvements must not quietly tax startup.
- Only explicit `When`, keyed collection changes, and teardown alter structure.
  Keep keyed reuse, row coordinate spaces, layout caches, no-op suppression,
  virtualization, and batching intact.
- Keep one geometry/style/binding/presentation authority per property and the
  existing frame source. All world and screen targets use those same seams.
- Resources are released in a defined order, even if one cleanup throws.
  Borrowed model state is never disposed by a child component. Early child
  disposal removes ownership records so a churning list cannot grow forever.
- Failures identify the component path, property, and creation site. Unknown
  fields, wrong recipe return types, writes/yields during computation, and
  stale owners should fail where the author can act on them.

## Implementation sequence after review

1. **Inventory and contract cleanup.** Publish the full public-surface gap list,
   fix additive type omissions against today's behavior, and strengthen the
   current checkers. Keep event-shape redesign distinct from typing existing
   behavior accurately.
2. **Signals compatibility candidate.** Pin the dependency, preserve licensing,
   port it through the existing Core seam as far as practical, and run the
   conformance corpus plus targeted semantic probes. Resolve every incompatible
   promise. Update the no-third-party-runtime statements and package/import
   rules as part of the actual migration.
3. **Small authoring slice.** Component lifetime, state/memo/watch/effect,
   function-valued properties, and semantic Button/Toggle. Migrate the standalone
   counter/settings examples and the exact Button observer pattern first.
4. **Stress the semantics.** Keyed row replacement/reorder, conditional mount,
   virtualization, exit-animation cleanup, errors, shared models across two
   surfaces, and third-party raw Signals updates. Cover async cancellation and
   nested tracking restoration without relying on a global owner.
5. **Complete the surface.** Bring controls, client helpers, documentation,
   authoring guidance, examples, and the production consumer onto the reviewed
   model. Apply the repository's actual release/deprecation status; do not leave
   two equally recommended authoring styles indefinitely.

Use three benchmark arms so causes stay visible: A = current Core/current API,
B = Signals/current API through the compatibility seam, C = Signals/proposed
authoring. Compare identical workloads and rendered output at the same revision
of FacetBench. If the compatibility seam cannot express an old semantic,
resolve that difference before calling the arms equivalent.

Performance acceptance uses a fresh baseline, not historical headline ratios.
Run nameplates, damage_fountain, battle_hud, killfeed_nameplates, and
war_room_inventory across their existing update/structural/no-op classes.
Collect per-class p50/p95/p99, setup and require cost, memory after churn,
subscription counts, layout work, engine writes, and retained node identity.
Use paired runs and the existing harness drift controls, then live Studio with
the same trees. Any reproducible regression outside the measured noise envelope
blocks promotion until explained and accepted; do not hide a slow class in a
whole-workload median. Headless timings cannot establish device performance.

Usability acceptance: the counter, settings screen, keyed inventory, and world
terminal examples contain no manual `scope:own`, `core` argument plumbing, or
`.blueprint` extraction in ordinary view composition. Readers can identify the
state owner, explain exactly which functions rerun, and distinguish a getter
from an event without reading framework internals. All examples typecheck.
Fresh human/agent authoring exercises should test these claims before calling
the model easier; this proposal itself is not user-study evidence.

The repo's full verification tier, package build/status for runtime changes,
and relevant live Studio checks remain implementation gates. No Signals-backed
Facet performance or full migration success is claimed in this proposal.

## Decision requested

Review this direction before the ergonomic API is implemented: function-valued
properties, a single explicit component lifetime context, getter/setter state,
one composable UI namespace, and upstream Signals underneath. The syntax can be
refined independently of that model. The Core switch is conditional on preserving
or explicitly revising its audited contracts, not on visual similarity alone.
