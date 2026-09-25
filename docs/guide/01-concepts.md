# Concepts

## Components and native Instances

A Facet component is a function that returns native Instances. A component can
mix controls, such as `UI.Button` and `UI.Table`, with Host objects, such as
`Host.Frame` and `Host.UIListLayout`. You can use any class that the Compose
Roblox host supports. Numeric children set the parent of each child. Native
property names set layout and engine behavior.

## State and ownership

A model cell holds durable state. A mounted row, a selection outline and a
temporary dialog are presentation, and each has an owner. Keep inventory, draft
fields and selected ids in model cells when they must survive the removal of
their current view. Compose `cell`, `formula`, `watch` and `cleanup` supply the
only reactive and lifetime model.

```luau
local enabled = Compose.cell(true)
local function Preferences()
    return UI.Toggle {
        label = "Show hints",
        value = enabled,
        onChange = function(nextValue) enabled:set(nextValue) end,
    }
end
```

A reactive property uses a readable directly or a `function(use)` body. `use`
subscribes to a value. `:peek()` reads a value and does not subscribe. Event
callbacks command the model.

An input control with an `onChange` callback requests a change. The callback
accepts the change when it writes the model. A programmatic model update does
not become a user-edit notification.

## Responsibilities

- Compose owns construction, bindings, owners, collections, portals and motion.
- Roblox lays out the native objects, edits text, scrolls and selects.
- Facet adds the behavior that is specific to each control.

There is no intermediate Facet scene, no second reactor and no general geometry
solver.

## Paint

Theme rules own ordinary paint. Native properties are explicit overrides. Keep
semantic intent in the controls. Customize the game-owned theme package before
you paint individual screens.

## Viewports

A viewport is a native fact, not a device name. Read the available size and
choose an applicable arrangement. Native layout and text measurements arrive
asynchronously. A test of deterministic behavior does not prove the final
engine geometry.

## Server authority

The server owns the game truth. UI cells hold a view of that truth and the
temporary interaction state. The server must validate each request that crosses
the network. A pending button does not authorize the requested operation.
