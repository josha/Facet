# Design consumer kinds and theme tables

## Theme tables

Set `context.tokens` when the source reads a game's token module. `Path.points`
takes a whole points token, such as `{ token = "glyph.sparkle.points" }`.
The source writes `points = T.glyph.sparkle.points`. The token must supply the
public `{ Facet.PathPoint }` list. Its handles can come from theme values in
the token module. A render can supply a readable list with `resolveToken`.
Path observes that list when it changes.

`RadialMenu.skin` takes a whole skin token, such as
`{ token = "skins.commands" }`. It supplies the public skin table with optional
`item`, `center`, `launcher` and `background` entries. Each entry has optional
`default`, `pressed`, `hover` and `selected` image strings. A render supplies
the table through `token` or `resolveToken`. The skin is set when the control
is built; it is not a readable prop.

Compose Design does not resolve token markers inside a plain points or skin
table. Use one token for the complete table when it contains theme values.
Literal tables remain valid when the art does not use theme values.

## Consumer kinds

Use `context.extension` to register a consumer component. This is Compose
Design's `Extension` contract. Facet calls `Design.extend` after it builds the
Facet library. An extension adds kinds and prelude lines. It cannot replace an
existing kind.

## Registered Designs

`context.designs` maps kind names to `Facet.DesignRegistered` entries with
`contract`, `call`, `build` and optional `prelude` and `category`.
Facet derives fields and calls `Design.extend`. Names must be unique.

`build(UI, props, name)` receives the context's controls and resolved props.
Bindings keep their identity; readable or cell previews become cells.
Outputs become callbacks.
`call` names the emitted constructor; `prelude` loads it. Use the same controls.

## Custom kinds

For example, assume a game exports a named component `Game.Emblem(name)(props)`
with a string `label`. Its editor builder can use the same component:

```luau
local kit = Facet.design()
local emblem: Facet.DesignKind = {
    fields = { label = { type = "string", default = "Emblem" } },
    defaults = { label = "Emblem" },
    children = "none",
    category = "Game",
    call = "Game.Emblem",
    build = function(props: { [string]: Facet.DesignResolved }, _children: { unknown }, name: string): unknown
        local label = props.label.literal
        assert(type(label) == "string")
        return Game.Emblem(name) { label = label }
    end,
}
local extension: Facet.DesignExtension = {
    kinds = { Emblem = emblem },
    prelude = { 'local Game = require(game:GetService("ReplicatedStorage").GameComponents)' },
}
local library = kit.library({ UI = UI, extension = extension })
```

`fields` declares each prop type for document validation and the inspector.
Use `luauType` on a field when a literal table needs a concrete emitted type.
Set `tokens = true` on a field that accepts theme tokens. The library must also
have `context.tokens` for emission. `children = "none"` declares a leaf.
`call` names the emitted named constructor. Its module must export that call.
The prelude loads that module in the emitted source.

`build` receives resolved props for rendering and the editor stage. Read
`literal` for plain data, `readable` for a live value, `callback` for an event
and `value` for a value supplied by a binding or token resolver. Check each
value before passing it to the component's typed props. The example above
accepts literal labels and plain value inputs. A component with readable props
must also pass the resolved readable value to its component.

Use this library for `Design.emit`, `Design.parse`, `Design.render` and the editor.
`Facet.composeDesign({ registry, samples })`
opens registered Designs with Facet's device, theme and text-size previews and
returns the Compose editor handle. See [host Design workspace](Design-workspace.md).
A document must use that library to parse its custom source calls.
