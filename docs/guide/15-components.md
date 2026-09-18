# Components: describe once, update what changes

Use `local UI = Facet.View` for new interfaces. A component describes its screen
once. A property function is a little recipe that Facet reruns when its inputs
change. Closing that component puts away its state, subscriptions and effects.
The same description can live on a player's screen, a billboard, or a flat world
surface.

```luau
local Facet = require(game.ReplicatedStorage.Facet)
local host = require(game.ReplicatedStorage.Facet.client.host)
local UI = Facet.View

local Counter = Facet.component(function(ui)
    local count, setCount = ui.state(0)
    return UI.Screen {
        id = "Counter", padding = "m", gap = "s",
        UI.Text "Live counter",
        UI.Text(function() return `Count: {count()}` end),
        UI.Button {
            label = "Add one",
            onActivate = function() setCount(function(n) return n + 1 end) end,
        },
        UI.Button {
            label = "Reset", enabled = function() return count() > 0 end,
            confirm = { title = "Reset counter?" },
            onActivate = function() setCount(0) end,
        },
    }
end)

local h = host.new()
local presented = h.presenter.present(Counter {})
-- At the application's lifetime boundary:
-- h.presenter.dismiss(presented)
-- h.dispose()
```

This is ordinary Roblox Luau. The table's numeric entries define child order;
Facet validates a dense array and visits it by index. Named fields do not affect
that order. Arrow functions are not Luau syntax. `UI.Text "Hello"` is Luau's
normal shorthand for a function called with one string.

## Read values; send commands

A getter answers a question. A change callback asks the model to do something.
This distinction matters when a server may refuse a change:

```luau
UI.Toggle {
    label = "Music", value = music,
    onChange = function(wanted) model.requestMusic(wanted) end,
}
```

Facet displays the model's current answer. A rejected command does not change
it. For local state, use `onChange = setMusic`.

An ordinary function is enough for a short derived value. Use `ui.memo` when a
calculation is expensive or shared. A memo getter passed as a property reuses
its binding instead of acquiring another memo layer.

Before:

```luau
local enabled = scope:own(core:memo(function(use)
    return use(balance) >= use(price)
end))
scope:own(core:observe(enabled, function(on)
    logAvailability(on)
end))
```

After, inside a component:

```luau
local balanceNow, priceNow = ui.read(balance), ui.read(price)
local enabled = ui.memo(function() return balanceNow() >= priceNow() end)
ui.watch(enabled, logAvailability)
```

`watch` runs on changes, with an optional `{ immediate = true }` initial call.
Use an event callback for a command that must run even when its selected value
is unchanged. The showcase motion preference illustrates this: a demo may have
overridden the live environment, so reselecting the stored preference must still
apply it. Watching equal writes cannot express that command.

## Lifetimes follow the interface

`Component {props}` is an inert description. Each mount gets independent local
state. Setup runs once per mount; property updates do not rerun it. State that
must outlive the screen belongs in the model and enters through props or
`ui.read`. Changing a plain prop table after declaration is not a reactive update;
pass getters/readables for changing values.

`ui.state`, `ui.memo`, `ui.watch` and `ui.effect` belong to the component.
`ui.effect` runs initially and can return a cleanup function. Cleanup runs before
the next effect execution and at unmount. Use `ui.own(function() connection:Disconnect()
end)` for external subscriptions. Explicit ownership remains useful at application
and engine integration boundaries.

Reactive recipes, component setup, watch callbacks and transaction bodies must
finish synchronously. An effect can start a task and return its cancellation
function. `ui.untrack` reads a value without subscribing to it; `ui.batch` groups
Facet updates.

## Branches and collections

```luau
UI.When {
    condition = expanded,
    Details { item = selectedItem },
}

UI.VirtualList {
    items = inventory, itemExtent = 64,
    key = "id",
    row = function(item)
        return UI.Button {
            label = function() return item().name end,
            onActivate = function() equip(item().id) end,
        }
    end,
}
```

The item getter returns the latest record for that key. Replacing a record or
reordering the array preserves the row's identity and updates its bindings.
Removing the key disposes its row after the exit transition. Virtualization
mounts only the needed window; keep durable item state in the model.
`UI.ForEach` uses the same vocabulary for small, fully mounted collections.
`UI.VirtualGrid` adds `columns` and keeps its existing line extent rules.
If a row needs local state, return a row component. Its `ui` owns that state;
using the outer component's `ui` deliberately gives it the outer lifetime.

## Place the same interface in the world

```luau
local terminalHost = host.new {
    surface = {
        kind = "surface", target = terminal, face = Enum.NormalId.Front,
        canvas = { w = 800, h = 600 },
    },
}
local presented = terminalHost.presenter.present(Shop { model = shopModel })
```

Choose `kind = "billboard"` for a canvas following an object; omit `surface` for
a screen. Pixel canvas dimensions stay fixed when the player's window changes.
Input and accessibility facts still update. These are flat interfaces in the
world; Facet does not add 3D layout or a VR input system.

For projected contextual actions, own the existing
[`client.world_anchor`](../reference/api.md#client-entry-points) handle through
`ui.own`, and use `ui.read(handle.anchor)` to bind its current projection. It
shares the presenter's clock.

## Core and explicit handles

`Facet.UI` retains primitive descriptions. `Facet.Controls` retains explicit
`(core, spec)` constructors and handles. `newCore` retains signals, memos,
change-only observers, transactions, error diagnostics and settling. Compose
supplies the dependency graph, watches, batching and ownership. `Facet.Signals`
is removed; shared model state uses `newCore` and components borrow it with
`ui.read`. Native scheduling and failure semantics are documented in
[`src/core/README.md`](../../src/core/README.md).

See the [API reference](../reference/api.md#view) and the migrated
[Settings Sync](../../examples/gallery/examples/03_settings_sync.luau) example.
The [example index](../../examples/README.md) points to maintained source.
Design rehearsals in `docs/plans/` record earlier decisions, not current recipes.

World hosts retain the existing target capabilities: native paint, native scrolling,
and pointer capture follow each target's documented support. `nativeStyle` is a
screen option; world targets keep their established fallback. This convenience
places a two-dimensional canvas in the world, without adding a 3D layout or VR
input system. Nested radial-menu items retain their explicit value/readable
contract; use `ui.memo` plus the outer `items` recipe when rebuilding their data.

## Animate where the layout lives

Declare coordination on the layout. A normal state change is enough:

```luau
return UI.VStack {
    animation = { layout = "container" },
    UI.Toggle { label = "Details", value = expanded, onChange = setExpanded },
    UI.When {
        condition = expanded,
        transition = { enter = "fade" },
        Details {},
    },
    Footer {},
}
```

Surviving nodes whose layout changes move together at the next visual commit.
Consecutive changes before that commit coalesce visually; model observers still
see ordinary Core transaction semantics. Nested declarations select their own
preset. A property's animation is local to its node:

```luau
UI.ZStack {
    scale = function() return if selected() then 1.04 else 1 end,
    opacity = function() return if available() then 1 else 0.5 end,
    animation = { scale = "object", opacity = "decay" },
    Content {},
}
```

Supported keys are `layout`, `scale`, `opacity`, `rotation`, and `offset`.
Values are registered spring/curve names or `false`. Unknown keys, unsupported
properties and unknown presets fail loudly. The table is static and copied at
construction. Paint rules override an explicit action's animation; `false`
disables that property. A layout group does not implicitly animate paint.
Initial layout appears immediately. Branch insertion/removal uses `transition`;
exit retains the visual lifetime and stops interaction through the existing
transition system. Alert and Sheet keep their built-in modal transitions; declare
animation on their content rather than on the presentation binding. Geometry changes from the environment suppress decorative
flights; motion-clock ticks, native scroll observation, and world-anchor tracking
do not trigger automatic layout flights. All motion uses the presenter's clock.

For an animated number needed by another calculation, use
`local displayed = ui.animate(targetGetter, "object", opts?)`. It returns a
getter, owns its source binding and motion, and accepts the existing motion value
options, including informational reduced-motion behavior. Use the original target
for gameplay decisions. `ui.withAnimation(preset, action)` exposes the explicit
presenter operation for exceptional actions; its existing synchronous and
non-nesting restrictions still apply.

## Compose custom views like built-ins

Custom components receive numeric children as a frozen `props.children` array;
named props can hold other view slots. Declare `Facet.ComponentChildren` in a
component's prop type when it accepts children. A description snapshots its props
shallowly, so later mutation of the input table cannot change its declaration.
Pass getters for changing data.

```luau
local Section = Facet.component(function(_ui, props)
    return UI.VStack {
        UI.Text(props.title),
        UI.VStack { children = props.children },
        props.footer,
    }
end)

Section {
    title = "Audio",
    footer = UI.Text "Saved automatically",
    MusicControl {},
    VolumeControl {},
}
```

`UI.When` accepts one direct child or its existing `thenView` factory, never both.
Group several children in a layout. Direct component children remain inert until
mounted, and acquire new local state on each fresh branch mount.

`ForEach`, `VirtualList`, and `VirtualGrid` accept `key = "id"` as shorthand for
extracting `item.id`. A row component can be passed directly as `row`; its props
argument is the current-item getter. Keys remain explicit and must be unique.

Plain getters bound to several properties share a memo within their mounted
owner. Separate component mounts and branch lifetimes do not share that cache.
Each destination still validates the result. `ui.memo` remains useful when a
cached answer is called by other calculations; ordinary function calls are not
implicitly cached. Borrow existing Core state through `ui.read`, rather than
using Core's untracked `:get()` inside a recipe.

The showcase's **Motion → Automatic** tab combines these features in
[`component_motion.luau`](../../examples/gallery/scenarios/component_motion.luau).

On Roblox, styled paint changes use native `StyleRule` transitions by default.
`nativeStyle = { transitions = false }` disables them for a target. Reduced motion
strips and restores these transitions live. Timed Facet curves use
`TweenService:GetValue` through both client frame drivers; interruptible springs
and coordinated layout keep Facet's shared clock and presentation composition.


## Copy current examples

Start with the [standalone consumer](../../examples/consumer/src/screen.luau),
[temperature converter](../../examples/gallery/examples/01_temperature_converter.luau),
[confirmation dialog](../../examples/gallery/examples/04_confirm_dialog.luau), or
[automatic motion](../../examples/gallery/scenarios/component_motion.luau).
The [progress demo](../../examples/gallery/scenarios/progress_ring.luau) shows
activity indicators and trails without scope or clock plumbing. The
[toast demo](../../examples/gallery/scenarios/sponsor_toast.luau) uses the same
component model for transient bodies and demonstrates content-fit sizing.

For new features, update the View type, mounted example and guide together.
Keep callbacks and nested data types accurate, including runtime metadata.
A control implementation or explicit diagnostic handle may use `Facet.Controls`;
that is a separate integration concern from ordinary view composition. Explain
the need beside any such example, and let `ui.own` release an external handle
when its component leaves. Historical design plans and before/after sections
preserve old syntax only to explain a migration.

## Compose controls without lifetime plumbing

`UI.ProgressView` inherits the component owner and presenter clock. `UI.AsyncImage`
inherits the owner for its request lease; leaving the screen releases that lease
and rejects stale completion. Its content key is static: mount a new keyed image
to load a different key. Neither control needs a scope argument.
Use `UI` modifiers around component descriptions, for example
`UI.corners(UI.AsyncImage { id = "Photo", provider = images, key = photoKey }, "control")`.

NavigationStack page factories and Alert custom content can return components.
Their state and subscriptions last as long as the page or modal content is mounted.
`UI.draggable(view, { enabled = canDrag, payload = makePayload })` tracks an
`enabled` getter; `payload` remains a callback invoked when a drag begins.
