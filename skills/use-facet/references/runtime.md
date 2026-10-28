# Runtime essentials

Use the installed Facet module and one app with one mount. Pages and overlays
belong inside that tree. Facet supplies Compose and the Roblox constructors.
Edit persistent source; Play-only edits are not the delivered change.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
local app = Facet.app({ name = "Game", theme = theme, suspendGameplay = true })
local UI = app.UI
local Host = Facet.host(app.runtime)
app.mount(function()
    return UI.Composition "HUD" {
        UI.Region "Status" { zone = "topRight", rank = 2,
            UI.Text { text = "Ready", textRole = "caption" } },
    }
end)
script.Destroying:Connect(app.dispose)
```

Use Facet controls for input, navigation, collections and overlays, and Host
for the game's art and world content. Host children go in the parent's
positional list; a Compose-owned object passed as `Parent` needs
`C.static(object)`. Build controls only inside the mount function or a
component it calls.

## State and commands

`C.cell(value)` owns state. Read it with `use(cell)` in property functions and
`cell:peek()` in callbacks; write with `set` or `update`. Derive with
`C.formula(function(use) ... end)`, branch with `C.show(condition, builder)`
and clean up subscriptions with `C.cleanup(function() connection:Disconnect() end)`.
Keep durable selection and drafts outside disposable pages and recycled rows.

NavigationStack keeps pages by entry identity. Push and pop a shallow copy of
the path:

```luau
local nextPath = table.clone(path:peek())
table.insert(nextPath, { id = "Shop" })
path:set(nextPath)
```

The server owns validation. Keep the draft, the pending request and the
accepted state apart; sending a request is not acceptance. Block duplicate
submissions, keep edits on rejection, offer retry and apply the server's
values. An input's `onChange` can request a value instead of writing the cell.

## Types

Use named constructors (`UI.VStack "Details" { ... }`) and annotate reactive
callbacks `function(use: Facet.Use)`. Type option lists before you pass them,
even with one entry: `local actions: { Facet.DialogAction } = { ... }`.
Otherwise Luau widens a literal to `string` and rejects the constructor. Fix
the type at that boundary; do not cast the whole spec.

## Sizing

| Intended relationship | Configuration |
| --- | --- |
| Bounded paragraph | Parent width; `UI.Text { wrap = true }` |
| Full-width button | Parent VStack `align = "stretch"`, or `Size = UDim2.new(1, 0, 0, 0)` |
| Equal peer buttons in a row | `UI.fill()` inside each Button |
| Label and trailing value | `UI.Spacer {}` between them in a bounded HStack |
| Two or three actions that may turn into a column | AdaptiveStack |
| Many short choices | `HStack { width = "fill", wrap = true }` |
| A page body | The page shell in [game screens](game-screens.md) |

Stacks hug by default. `width`, `height`, `gap`, `padding` and `maxWidth` are
container options; Button, Text and TextInput take native `Size`. Bound the
space before you use fill. Spacing steps are `xs`, `s`, `m`, `l` and `xl`. Do
not repair overflow by shrinking all text.

## Input

Bind game commands as native InputActions in a game-owned InputContext. A
Button's `shortcutHint` shows an action's binding; it does not connect it.
Gate gameplay commands while `UI.environment().gameplaySuspended` is true. Do
not bind Escape or gamepad Start. `UI.environment()` gives the viewport size,
the primary input and `thumbTarget`; choose layout from room and prompts from
the actual input. Call it once at the top of a screen function
(`local env = UI.environment()`) and read `use(env.viewportWidth)` in
property functions.

A page whose builder errors shows "This page could not be displayed." and
warns with the page id and the error in the output; read the output after
each Play.

## Exact contracts

In Studio, read a node at
`ServerStorage.FacetDocs.docs.reference.nodes["Button.card.md"].Value`; with a
shell, `lute run tools/facet docs Button.card`. Read a card only for a control
the recipes do not show, batch the ones you need in one call and keep the
answers. [Runtime details](runtime-details.md) covers Sheets, overloaded
collections, the top bar, localization and the type checker.
