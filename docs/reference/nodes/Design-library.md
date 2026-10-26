# Design library

Author Facet screens as Compose Design documents. A document uses the format
`compose-design/1` and the library name `Facet`.

`Facet.design()` returns the design kit, loaded on first use. `kit.library(context)` returns a `Facet.DesignLibrary` for
`kit.Design`. Each Facet control is a kind with fields, defaults and a
category.

```luau
local UI = Facet.controls(runtime)
local kit = Facet.design()
local library = kit.library({
    UI = UI,
    rgb = Color3.fromRGB,
    udim2 = UDim2.new,
    offset = UDim2.fromOffset,
    datatype = function(name, components)
        local constructors = { UDim2 = UDim2.new, UDim = UDim.new, Vector2 = Vector2.new }
        return constructors[name](table.unpack(components))
    end,
    enumItem = function(enumName, item)
        for _, enum in Enum:GetEnums() do
            if tostring(enum) == enumName then
                return enum:FromName(item)
            end
        end
        return nil
    end,
    host = function(className, name, props)
        return runtime.constructors[className](name)(props)
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
  The context converts it with `enumItem` and `datatype`. Emitted source
  writes `Enum.AutomaticSize.Y` and `UDim2.new(1, 0, 0, 48)`.
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
- Emit with `{ name = "ShopView", controls = "local UI = ..." }` to write a
  view that takes only `props`. `propsType` reuses an exported props type.
  `prelude` adds lines.

The game keeps its state and server validation. Give state to a design as
contract inputs. Receive events as contract outputs. Use `kit.Design.extend`
to add a game's own kinds to the library.
