# Concepts

A Facet component is a function returning native Instances. It can mix `UI.Button`, `UI.Table` and other controls with `Host.Frame`, `Host.UIListLayout` and any other class supported by the Compose Roblox host. Numeric children describe parentage. Native property names describe layout and engine behavior.

A model cell is durable state. A mounted row, selection outline or temporary dialog is presentation with an owner. Keep inventory, draft fields and selected ids in model cells when they must survive removal of their current view. Compose cell/formula/watch/cleanup provide the one reactive and lifetime model.

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

A reactive property uses a readable directly or a `function(use)` body. `use` subscribes; `:peek()` reads without subscribing. Event callbacks command the model. An input control with an `onChange` callback requests a change; the callback accepts it by writing the model. Programmatic model updates do not become user-edit notifications.

Compose owns construction, bindings, owners, collections, portals and motion. Roblox lays out the resulting native objects, edits text, scrolls and selects. Facet adds behaviors specific to controls. There is no intermediate Facet scene, second reactor or general geometry solver.

Theme rules own ordinary paint. Native properties are explicit overrides. Keep semantic intent in controls and customize the game-owned package before painting individual screens.

A viewport is a native fact, not a device name. Observe available size and choose an appropriate arrangement. Native layout and text measurements arrive asynchronously; tests of deterministic behavior are not proof of final engine geometry.

The server owns game truth. UI cells hold a view of that truth and temporary interaction state. Requests crossing the network must be validated by the server; showing a pending button does not authorize the requested operation.
