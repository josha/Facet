# Design library

Author Facet screens as Compose Design documents. A document uses the format
`compose-design/1` and the library name `Facet`.

`Facet.designLibrary(context)` returns a `Facet.DesignLibrary` for
`Facet.Design`. Each Facet control is a kind with fields, defaults and a
category.

```luau
local UI = Facet.controls(runtime)
local library = Facet.designLibrary({
    UI = UI,
    rgb = Color3.fromRGB,
    udim2 = UDim2.new,
    offset = UDim2.fromOffset,
})
local document = Facet.Design.document.new("Shop", library, "VStack")
local view = Facet.Design.render(document, library, { inputs = { title = "Shop" } })
local source = Facet.Design.emit(document, library, { name = "Shop" })
```

- `Facet.Design` is the Compose Design module: `document`, `history`,
  `session`, `render`, `link`, `extend`, `emit` and `parse`.
- `Facet.designControls` maps each control name to its fields, defaults,
  category and child mode.
- `Facet.designSeeds(kind)` returns the child nodes that a new node of that
  kind starts with.

Child modes:

- Stacks, grids and other containers take a list of children.
- Dialog, Sheet, Popover, Callout, DisclosureGroup, CollapsibleView, Card and
  RowActions take one content node. The control builds it when it presents
  the content.
- VirtualList, VirtualGrid and Outline bind a list input. One child is the row
  template.

The game keeps its state and server validation. Give state to a design as
contract inputs. Receive events as contract outputs. Use `Facet.Design.extend`
to add a game's own kinds to the library.
