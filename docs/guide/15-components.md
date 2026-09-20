# Components with Compose

A component is an ordinary Luau function that returns a Facet view. Compose owns
its reactive values and cleanup. Facet supplies controls, layout, themes and input.

Create an application, then use its controls:

```luau
local Facet = require(game.ReplicatedStorage.Facet)
local Compose = Facet.Compose
local app = Facet.new()
local UI = app.controls

local function Counter()
    local count = Compose.cell(0)
    return UI.Screen {
        padding = "m", gap = "s",
        UI.Text {
            text = function(use) return `Count: {use(count)}` end,
        },
        UI.Button {
            label = "Add one",
            onActivate = function()
                count:update(function(n) return n + 1 end)
            end,
        },
        UI.Button {
            label = "Reset",
            enabled = function(use) return use(count) > 0 end,
            onActivate = function() count:set(0) end,
        },
    }
end

local close = app.mount(Counter)
-- Call close() to remove this screen.
-- Call app.dispose() when the application ends.
```

Numeric entries set child order. Named fields set properties. Ordinary controls
need no IDs. Use an optional constructor name when another API needs a stable path:
`UI.Button("Save") { label = "Save", onActivate = save }`.

## Read values and send commands

A property function receives `use`. Calling `use(value)` subscribes that property
to the value. Compose updates the property when the value changes.

Use `:peek()` to read without a subscription. Event callbacks usually need this
form. Use `:set(value)` to replace a cell or `:update(function)` to transform it.

Writable cells work directly with value controls:

```luau
local music = Compose.cell(true)
local draft = Compose.cell("")

UI.VStack {
    UI.Toggle { label = "Music", value = music },
    UI.TextInput { value = draft, placeholder = "Message" },
}
```

Use an explicit callback when a model must approve a change:

```luau
UI.Toggle {
    label = "Music",
    value = music,
    onChange = function(wanted) model.requestMusic(wanted) end,
}
```

The control displays the model's value. With `onChange`, it writes no state:
`model.requestMusic` must write `music` to accept the request. Rejecting or
delaying a request leaves the value and appearance unchanged. The callback's
return value is ignored. This form also accepts a Compose formula or
`function(use)` as `value`; a checkbox's model also owns clearing `mixed`.
Keep server validation in the game model.

Use `Compose.formula` for a shared calculation:

```luau
local canBuy = Compose.formula(function(use)
    return use(balance) >= use(price)
end)

UI.Button {
    label = "Buy",
    enabled = canBuy,
    onActivate = buy,
}
```

Use `Compose.watch(function(use) ... end)` for a reactive external effect. It runs
initially and tracks the values it reads. Keep user commands in event callbacks.

## Keep state for the required lifetime

`app.mount(Component)` runs the component under a Compose owner. Setup runs once
per mount. Property updates do not rerun the component.

Create local cells inside the component. Create shared model cells outside it
when their values must survive removal of the screen. Pass those cells to each
presentation of the model.

Register external cleanup with Compose:

```luau
Compose.cleanup(app.onFrame(function(dt)
    model.advance(dt)
end))
```

Removing the component disconnects this callback. Compose also releases its
watches and child owners. Use `Compose.cleanup` for engine connections and other
external resources that must end with the component.

Component setup and reactive functions must finish synchronously. Use
`app.runtime:batch(function() ... end)` when several writes form one update.

## Create branches and keyed collections

Use a factory for content that exists only while a condition is true:

```luau
Compose.show(expanded, function()
    return UI.Text { text = "Details" }
end)
```

Compose creates the branch when the condition becomes true. It removes the branch
and releases its owner when the condition becomes false.

Use `Compose.keyed` for a small collection that stays fully mounted:

```luau
Compose.keyed {
    from = inventory,
    key = function(item) return item.id end,
    render = function(item)
        return UI.Button {
            label = function(use) return use(item).name end,
            onActivate = function() equip(item:peek().id) end,
        }
    end,
}
```

The item readable holds the current record for that key. Replacing a record
updates its row. Reordering the array preserves each retained row and its state.
Removing a key releases its row owner.

Use virtual controls for large collections:

```luau
UI.VirtualGrid {
    items = games,
    key = "id",
    columns = columns,
    itemExtent = 208,
    gap = "m", rowGap = "m",
    onActivate = openGame,
    cell = function(game, ctx)
        local current = Compose.formula(ctx.current)
        return UI.Text {
            text = function(use) return use(current).title end,
        }
    end,
}
```

`cell(item, ctx)` receives the item's current value and a context table.
`ctx.current` is a `function(use)` that follows later edits to that item; wrap it
in `Compose.formula` when the cell must track them. `ctx.scope` is the row's own
Compose owner.

`UI.VirtualList` uses the same vocabulary without `columns` or `rowGap`, and
names its array `rows` or `items`. Both controls use Compose's
`OrderedCollection` for windowing and row lifetime. Facet supplies the scroll
container and focus navigation.

Keep durable row state in the model. Rows outside the retained window can
unmount. For variable sizes, set `itemExtent = "measured"` and give
`estimatedItemExtent` the pixel seed an unmeasured row windows at.
Use `follow = "end"` for a feed that follows new content until the reader scrolls
away. See the [collection reference](../reference/api.md#virtual-collections-in-appcontrols).

## Compose custom views

Call a component function directly inside another component. Its props are
ordinary Luau values. Pass readables for values that can change.

```luau
local function Section(props)
    return UI.VStack {
        gap = "s",
        UI.Text { text = props.title, textSize = "heading" },
        UI.VStack(props.children),
    }
end

Section {
    title = "Audio",
    children = {
        UI.Toggle { label = "Music", value = music },
    },
}
```

A direct function call uses the current Compose owner. Use Compose branches,
keyed collections or layer stacks when content needs a separate lifetime.
These structures accept component factories.

## Animate values with the Compose runtime

Use the application's Compose runtime for spring and tween animation:

```luau
local displayed = app.runtime.spring(function(use)
    return if use(selected) then 1.04 else 1
end, { period = 0.35, damping = 1 })

UI.ZStack {
    scale = function(use)
        return if use(app.environment:get("reducedMotion")) then 1 else use(displayed)
    end,
    UI.Text { text = "Selected item" },
}
```

The application supplies the frame driver. Compose owns the animated readable
and releases it with the component. Use the model value for game decisions.
Read the animated value only where a visual calculation needs it.

This example suppresses decorative scaling when reduced motion is active. Choose
an appropriate final value for motion that conveys information. Styled paint on
Roblox uses the target's native `StyleRule` transitions and reduced-motion policy.

### Stream text into a Text node

Let the model own the string and let the reveal own the presentation:

```luau
local reveal = Facet.motion.newTextReveal({
    value = function(use) return use(message).content end,
    placeholder = "Thinking…",
    policy = app.environment:get("motionPolicy"),
})

UI.Text({ text = reveal.text })
```

The reveal never splits a codepoint, paints the placeholder only while nothing
has arrived, and lands the whole value under reduced motion. Pass `cursor` when
your model advances a character count instead of rewriting the string.

### Grow a detail view out of the card that opened it

Declare the branch at its own full size and name the card as the transition's
source. Facet reads the card's painted rect every frame and paints the branch
from there:

```luau
UI.When("Expand")({
    condition = function(use) return use(selected) ~= nil end,
    transition = { enter = "transform", source = { path = cardPath }, content = "Body" },
    thenView = Detail,
})
```

`source` takes `{ path = "…" }` for a mounted node or `{ rect = … }` for a rect
readable; either may itself be a readable. The motion is paint-only, so nothing
reflows. Deselecting mid-flight reverses from the painted rectangle without a
jump, and reduced motion lands it on the frame it starts. Use `fromRect` instead
when the origin cannot move.

## Place the interface in the world

Pass a surface configuration to `Facet.new`:

```luau
local terminalApp = Facet.new {
    surface = {
        kind = "surface", target = terminal, face = Enum.NormalId.Front,
        canvas = { w = 800, h = 600 },
    },
}
local close = terminalApp.mount(function()
    return terminalApp.controls.Screen {
        terminalApp.controls.Text { text = "Terminal ready" },
    }
end)
```

Choose `kind = "billboard"` for a canvas that follows an object. Omit `surface`
for a screen. A world surface remains a flat UI canvas. Its canvas dimensions
are independent of the player's window size.

Read the [target contracts](../reference/api.md#client-entry-points) for input
and rendering support. Read adaptive facts through `app.environment`. Select
layout from those facts rather than a device name.

## Run a maintained example

The [standalone consumer](../../examples/consumer/src/screen.luau) uses this API
in Studio and in headless tests. It includes controlled values, adaptive layout,
frame cleanup and application disposal.

The [API reference](../reference/api.md#new) describes the application surface.
The [Compose reference](../reference/api.md#compose) links the pinned upstream
contracts for state, ownership, collections, layers and motion.

## Present a decision

Keep presentation in a Compose cell. The application supplies the presenter.
Content is a component function, so each presentation gets its own lifetime.

```luau
local shown = Compose.cell(false)
local name = Compose.cell("")

UI.VStack {
    UI.Button {
        label = "Edit name",
        onActivate = function() shown:set(true) end,
    },
    UI.Alert {
        title = "Edit name",
        isPresented = shown,
        content = function()
            return UI.TextInput { value = name, placeholder = "Name" }
        end,
        actions = {
            { id = "save", label = "Save", shortcut = "defaultAction" },
            { id = "cancel", label = "Cancel", role = "cancel" },
        },
    },
}
```

Use the same pattern with `UI.Sheet` for a larger task. Give it a `detent` cell
and a content function. Use `UI.Menu { label = "Actions", items = ... }` for a
list of commands attached to a button. Keep all three in the existing screen's
layout and navigation.
