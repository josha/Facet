# Facet: Signals and authoring before and after

Facet now has two clearer layers: **Roblox Signals handles reactive dependencies;
Facet turns those updates into a managed, interactive UI.**

## 1. What Signals replaced, and what Facet still does

Previously, Core contained our own reactive engine. It remembered which values
depended on other values and decided what needed recalculating.

That engine has been replaced with the official Roblox Signals library.

| Responsibility | Before | Now |
|---|---|---|
| Store reactive values | Custom Core implementation | Roblox Signals |
| Calculate and cache derived values | Custom Core memos | Roblox Signals computed values, behind Facet's memo API |
| Track dependencies and mark calculations for updates | Custom dependency graph | Roblox Signals |
| Group changes and deliver callbacks in predictable order | Facet | Still Facet |
| Notify observers only when their value changes | Facet | Still Facet |
| Own resources and clean them up | Explicit Facet scopes | Facet scopes, usually managed automatically by components |
| Recover from callback errors, detect misuse, and provide diagnostics | Facet | Still Facet |
| Coordinate updates with layout and rendering | Facet | Still Facet |

**Core still exists as Facet's integration layer.** Its old custom dependency
engine is gone. Existing `core:signal`, `core:memo`, and other Core calls continue
working through the Signals backend.

Layout, controls, focus, input, virtualization, themes, and animation remain
Facet responsibilities. Signals does not provide those systems.

## 2. How writing Facet code changed

The new mental model is:

> Describe a view once. Give changing properties a function that answers “what
> should this be now?” Facet watches the values that function reads and updates
> the affected properties. When the view goes away, Facet cleans up what it owns.

A component's setup runs once per mount. Changing state updates its bindings; it
does not rerun the entire component.

The following “after” examples use `local UI = Facet.View`. The `ui` context
comes from `Facet.component(function(ui) ... end)`.

### State and ownership become part of the component's lifetime

Before:

```luau
local count = scope:own(core:signal(0))

local function increment()
    count:set(count:get() + 1)
end
```

After:

```luau
local count, setCount = ui.state(0)

local function increment()
    setCount(count() + 1)
end
```

You no longer declare ownership for each piece of component state. Facet creates
separate state for each mounted instance and disposes it on unmount.

State that must survive closing the screen still belongs in your model. A
component can read existing Core state with:

```luau
local balance = ui.read(model.balance)
```

Explicit `ui.own(...)` remains useful for external resources, such as an engine
connection.

### Simple derived values become ordinary functions

Before:

```luau
local enabled = scope:own(core:memo(function(use)
    return use(balance) >= use(price)
end))

scope:own(core:observe(enabled, function(on)
    reportAvailability(on)
end))
```

After, with `balance` and `price` as getters:

```luau
local function enabled()
    return balance() >= price()
end

ui.watch(enabled, reportAvailability)
```

The same function can go directly into a property:

```luau
UI.Button {
    label = "Buy",
    enabled = enabled,
    onActivate = buy,
}
```

For an expensive calculation, explicitly cache its answer:

```luau
local total = ui.memo(function()
    return calculateTotal(items())
end)
```

Plain functions are enough for simple recipes. `ui.memo` remains useful when
other calculations repeatedly need the cached answer. Facet also reuses the
binding when the same getter is assigned to several properties within one
mounted owner.

`ui.watch` runs on changes. `ui.effect` runs initially, tracks its inputs, and
can return a cleanup function.

### Blueprints and controls use one composition style

Before:

```luau
local button = scope:own(Facet.Controls.Button(core, {
    label = "Save",
    onActivate = save,
}))

local view = Facet.UI.VStack {
    gap = "s",
    children = {
        Facet.UI.Text { text = "Settings" },
        button.blueprint,
    },
}
```

After:

```luau
local view = UI.VStack {
    gap = "s",
    UI.Text "Settings",
    UI.Button {
        label = "Save",
        onActivate = save,
    },
}
```

This removes routine `core` arguments, control handles, `.blueprint`, ownership
calls, and the extra `children` table.

**Child ordering is guaranteed:** Facet validates the numbered entries and visits
them in order. Named properties do not affect that order. This is ordinary
Roblox Luau, with no JSX compiler or invented arrow-function syntax.

Custom components use the same shape:

```luau
Section {
    title = "Audio",
    footer = UI.Text "Saved automatically",
    MusicControl {},
    VolumeControl {},
}
```

`Section` receives the ordered children as `props.children`; `footer` is an
ordinary named property containing another view.

### Branches and lists need fewer wrapper functions

Before:

```luau
UI.When {
    condition = expanded,
    thenView = function()
        return Details {}
    end,
}

UI.ForEach {
    items = items,
    key = function(item) return item.id end,
    row = function(item) return ItemRow(item) end,
}
```

After:

```luau
UI.When {
    condition = expanded,
    Details {},
}

UI.ForEach {
    items = items,
    key = "id",
    row = ItemRow,
}
```

Stable keys preserve row identity when items move. Row components receive a
getter for the current item, so replacing its data updates the existing row.
Large collections still use `VirtualList` or `VirtualGrid`.

### Animation is usually declared where the view lives

Before, callers had to remember to wrap the change:

```luau
onChange = function(value)
    presenter.withAnimation("container", function()
        expanded:set(value)
    end)
end
```

After, the layout declares how changes should move:

```luau
UI.VStack {
    animation = { layout = "container" },

    UI.Toggle {
        label = "Details",
        value = expanded,
        onChange = setExpanded,
    },

    UI.When {
        condition = expanded,
        transition = { enter = "fade" },
        Details {},
    },

    Footer {},
}
```

Ordinary state changes now coordinate the movement of surviving children. The
branch's `transition` controls its appearance. Exceptional actions can still
use `ui.withAnimation`.

Individual properties can declare their own motion:

```luau
UI.ZStack {
    opacity = function() return if selected() then 1 else 0.65 end,
    animation = { opacity = "object" },
    Content {},
}
```

Animated values also need less wiring:

```luau
-- Before
local displayed = scope:own(
    presenter.motionClock:animate(balance, "object")
)

-- After, with balance as a getter
local displayed = ui.animate(balance, "object")
```

Native styled paint now uses Roblox **StyleRule transitions by default**. Timed
curves use Roblox's easing evaluator. Facet retains its spring calculations and
shared animation coordination for interruptible layout motion. Reduced-motion
handling remains integrated.

### Types now describe more of the actual runtime contract

For example, Button's callback type previously claimed it received no arguments:

```luau
-- Before
onActivate: () -> ()

-- After
onActivate: (Facet.ActivationMetadata?) -> ()
```

Code can now use the supplied metadata with type checking:

```luau
onActivate = function(meta)
    if meta and meta.source == "shortcut" then
        -- Handle shortcut-specific behavior.
    end
    save()
end
```

Missing Button fields were added, and all 29 public control entries now expose
spec types. Tests check valid and invalid properties, callback metadata,
children, and reactive getters.

The existing lower-level APIs remain available. The new component API supplies
the shorter path for ordinary UI work. The initial authoring rollout passed **10,083 tests**,
with performance checks staying within unchanged budgets; the Signals migration
does have measurable overhead in some workloads.

[Component guide and examples](../guide/15-components.md) ·
[Validation results](2026-09-17-authoring-ergonomics-validation.md)

The subsequent [example migration](../guide/15-components.md#copy-current-examples) applies this vocabulary to maintained tutorials, showcase chrome and reference views.
Toast rows now animate reflow; their edge and width are configurable, and the default
slide keeps text outside a rasterized CanvasGroup. See the [example index](../../examples/README.md) for code to copy and the [migration validation](2026-09-17-example-migration-validation.md) for current checks.
