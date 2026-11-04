# Design library

Author Facet screens as Compose Design documents. A document uses the format
`compose-design/1` and the library name `Facet`.

`Facet.design()` returns the design kit. `kit.library(context)` returns a `Facet.DesignLibrary` for
`kit.Design`. Each Facet control is a kind with fields, defaults and a
category.

```luau
local UI = Facet.controls(runtime)
local kit = Facet.design()
local library = kit.library({
    UI = UI,
    host = function(className, name, props)
        return runtime.constructors[className](props, name)
    end,
})
local document = kit.Design.document.new("Shop", library, "VStack")
local view = kit.Design.render(document, library, { inputs = { title = "Shop" } })
local source = kit.Design.emit(document, library, { name = "Shop" })
```

- `kit.Design` is the Compose Design module: `document`, `history`,
  `session`, `render`, `link`, `extend`, `emit` and `parse`.
- `kit.controls` maps each control name to its fields, defaults,
  category and child mode.
- `kit.seeds(kind)` returns the child nodes that a new node of that
  kind starts with.

Child modes:

- Stacks, grids and other containers take a list of children.
- Dialog, Sheet, Popover, Callout, DisclosureGroup, CollapsibleView, Card and
  RowActions take one content node. The control builds it when it presents
  the content.
- VirtualList, VirtualGrid and Outline bind a list input. One child is the row
  template.

Fields:

- Each kind has its curated fields. It also has every other prop of the
  control's prop type, in the groups `Control` and `Roblox`.
- A callback prop named `onSomething` is an event field. Bind it to a
  contract output.
- A Roblox enum or datatype prop is a datatype field. Its literal is an enum
  item name, such as `"Y"`, or a list of numbers, such as `{ 1, 0, 0, 48 }`.
  The library converts it with the Roblox datatypes in `context.types`. The
  default is the engine datatypes. In the engine double, pass `ctx.types`.
  Emitted source writes `Enum.AutomaticSize.Y` and `UDim2.new(1, 0, 0, 48)`.
- `lute run tools/facet types props` generates the fields from the prop types.

Kinds:

- Facet controls with no curated entry are in the category `More`.
- When the context has `host`, the Roblox classes `Frame`, `TextLabel`,
  `ImageLabel`, `ScrollingFrame` and the UI layout objects are kinds in the
  category `Roblox`. They emit `Host.Frame "Name" { ... }`.

Whole views:

- `kit.Design.document.nameFromInput` names a node from a text input. The
  source is `UI.VStack(props.name)`.
- A stack can bind a list input. Its one child is the row template, emitted
  with `Facet.Compose.keyed`.
- `kit.Design.document.showWhen` shows a child of a stack while a true or
  false input or state holds, emitted with `Facet.Compose.show`.
- `kit.Design.document.setState` declares local state, such as an expanded
  flag. Bind a field to it with `{ state = "expanded" }`.
- A bound value can move: `{ state = "glow", motion = "move" }` emits
  `UI.follow(state.glow, "move")`. The roles are the theme's springs.
- `kit.Design.document.setSequences` keeps timed steps in the design. An
  event plays one with `{ play = "reveal" }`. Pass `motion = kit.motion(UI)`
  in the context to animate them in a render.
- Emit with `{ name = "ShopView", controls = "local UI = ..." }` to write a
  view that takes only `props`. `propsType` reuses an exported props type.
  `prelude` adds lines.

The game keeps its state and server validation. Give state to a design as
contract inputs. Receive events as contract outputs.

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

Use this same library for `Design.emit`, `Design.parse`, `Design.render` and
`DesignEditor.create` or the library in a `DesignEditor.kit` workspace.
The editor lists the added category and kinds, edits their fields and calls
their builders on the stage. `Facet.composeDesign()` supplies the base Facet
library; a game editor kit supplies its extended library. A document must use
that library to parse its custom source calls.
