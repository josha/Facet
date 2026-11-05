# Edit a Compose Design module

A Compose Design module is a Luau ModuleScript that the design editor reads and
writes. The Studio plugin links the editor to the module. An edit to the module
updates the editor, and an edit in the editor writes the module. This is true
for every route that changes the source: a file that Rojo syncs, Studio MCP, the
script editor, or Studio Assistant.

The editor keeps syncing only while the module parses as a design. If the
module does not parse, the editor shows "custom code" and stops syncing. It does
not overwrite the module. Keep every edit inside the shapes below.

## Shape of the module

1. The `--!strict` line and the library prelude, for example
   `local Facet = require(game:GetService("ReplicatedStorage").Facet)`.
   Additional static `local Name = require(...)` declarations can import public
   prop types used by contract `luauType` annotations. The editor retains them.
   Use string module paths or named paths with literal string indexing;
   `game:GetService("Service")` can start a path. Prepare computed paths outside
   the Design.
2. Exported types: one `export type <List>Item` for each list input with
   fields, and `export type Props`. The editor writes these from the contract.
   Do not edit them by hand. Change the contract in the header.
3. The header: `local _design = { name = ..., contract = { inputs = ..., outputs = ... }, state = ..., sequences = ... }`.
   - An input has `id`, `kind` (`value`, `readable` or `cell`), `type`
     (`string`, `number`, `boolean`, `color`, `image`, `list`, `record` or
     `slot`) and an optional `preview`, `fields` and `required`.
   - An output has an `id` that starts with `on`, and optional `args` or `row`.
     `row` names the list input whose row the output passes.
   - Input and state ids use lower camel case.
   - A sequence has an `id`, an optional `autoplay = true` and 1 to 32 `steps`.
     A step has optional `delay`, `duration` and `easing` theme token names, an
     optional `state` with the value `to` that the step moves it to, and an
     optional `output` that the step calls when it ends. The header is the
     source of truth: the editor writes the `local sequences` block from it.
4. One component function that returns one control tree, and `return <Name>`.

## Shapes inside the tree

- A control: `UI.Kind "Name" { prop = value, child, child }`. `Name` is the
  layer name in the editor.
- A literal: a string, a number, a boolean or a table of literals. Write colors
  as `Color3.fromHex "RRGGBB"` and enum items as `Enum.Category.Item`.
- An input: `props.id`. A state value: `state.id`.
- A datatype component: a number, token, or required numeric input.
  `{ input = "offset" }` emits `props.offset` in a constructor, or
  `use(props.offset)` inside a constructor formula for a readable or cell input.
  Prepare arithmetic in the caller.
- An item field inside a row: `function(use) return use(current).field end`.
  Wrap a non-text field that a text property reads in `tostring(...)`.
- An output call: `function(...) if props.onThing then props.onThing(...) end end`.
  In a row, pass the row with `props.onThing(current:peek())`.
  For a typed row action, set `arguments = { { item = "id" }, { event = 1 } }`
  on its output binding and declare output `args = { "string", "string" }`.
  It emits `function(event1: string)` calling `props.onThing(current:peek().id, event1)`.
  A focus action uses only `{ item = "id" }` and emits `function()`.
  Arguments keep their declared order; event positions must be positive and contiguous.
  Supply editor/frame `outputs` to receive the same argument arrays as `Design.render`.
- A repeated list: `from = props.list, key = "id", render = function(current) return <node> end`.
  A list inside a row reads a list field of the row:
  `from = function(use) return use(current).rows end`.
  A qualified `Bind.from = "pages.rows"` emits a local `row_pages` alias
  and `from = function(use) return use(row_pages).rows end` in that page row.
- A conditional child: `<show>(props.flag, function() return <node> end)`, where
  `<show>` is the library's show call (Facet: `Facet.Compose.show`).
  In a row, the condition can read a boolean item field.
- A table column cell: `render = function(current) return <node> end` inside a
  column record.
- Row actions: `rowActions = function(current) return { ... } end`.
- A style tag: `<tag>(<node>, { "tag-name" })`, where `<tag>` is the library's
  tag call (Facet: `Facet.tag`). Tags can also read `props.paint` or
  `function(use) return use(current).paint end`. Prepare the string or string
  list in the caller; the document contains no tag selection expression.
  `Design.document.bindTags` stores the input or item binding. For a list,
  declare a named string-list `luauType` in the library prelude.
- A node reference wraps its target in `capture("nN", <node>)`. Fields default to
  a deferred `function(use)` that asserts `use(refs.nN)`. A library field with
  `type = "node", reference = "native"` emits
  `assert(refs.nN:peek(), "Node reference is not captured")` directly. Capture
  that target before the receiving node; native fields reject `nodeFrom`.
  Direct-render builders still sample `Resolved.node` before passing it onward.
- A static root variant: a required string input declares enum `options`.
  `Design.document.setRootVariant` selects one alternative kind and its props
  for a matching option. An optional `children` list gives the alternative its
  own content tree and distinct node ids. Without it, both roots share one
  content function. Both forms keep one direct root name.
- A row variant: the row item's string field declares enum `options`.
  `Design.document.setRowVariant` stores `{ item, cases }` on the row root.
  Each case has `value`, `kind`, `props` and `children`. The row factory chooses
  a case once from `current:peek().kind`, then returns the selected root with
  the same name, including a shared row-bound `nameField` across different kinds.
  Other enum options use the ordinary row. Include the kind in
  the caller's key if changing it must replace a retained row. Arbitrary
  conditions and variants outside row roots are custom code.
- A caller slot inside a layout: `props.body()` at an ordinary child position
  in Frame/VStack/HStack/ZStack or another list container. Optional slots use
  `if props.body then props.body() else nil`, checking only factory presence.
  `Design.document.insertSlot` stores a `$slot` node with `slot = "body"`.
  The factory runs under the active owner and adds no wrapper node.
- An input inside a literal page record: `label = props.title` beside a
  document-owned `content = function() return <node> end`. The literal marker
  is `{ ["$input"] = "title" }`; it names one input and contains no other keys.
- A content property that holds a subtree: `glyph = function() return <node> end`.
  The node is a child of the control in the editor.
- A value property that takes one node: `trailing = UI.Kind "Name" { ... }`.
  `Design.document.content` on a value field stores the child with a top-level
  `$template` marker. It builds the node directly before the receiving control.
- An imported Design registered by the library's `Design.imports`:
  `Wall(UI, { name = "WestWall", offset = props.offset, detail = function() return <node> end })`.
  The first field is the imported root's required name input. Other fields
  follow its typed contract, including readable inputs and named slots.
  Keep geometry in the canonical sub-Design. The assembly stores only the call
  and its authored slot children. Each source round-trips independently.
- A moving value: `<follow>(state.id, "role")`, where `<follow>` is the
  library's motion call (Facet: `UI.follow`) and `role` is one of its motion
  roles. The wrapped value is an input, a state value or an item field. The
  theme sets the timing of each role.
- A sequence play: `onActivate = sequences.id.play` on an event property.
- A token: `<token>(name)`, or `T.space.md` when the library's token prefix ends
  with a dot (for example `T.`). Add the prefix's `require` to the prelude.

Any other expression is custom code. Put game logic, computed values and
effects in game code, and pass the results in through inputs.

## Edit by route

- **File and Rojo.** Edit the `.luau` file. Rojo syncs it, and the editor
  updates.
- **Studio MCP.** Write the module source with the script editor API, for
  example `ScriptEditorService:UpdateSourceAsync(module, function() return source end)`.
  Do not set `Source` while the module is open in a script editor tab.
- **Studio Assistant.** Ask it to edit the module and to keep the design shapes
  above.

In every route, change only what the task needs. Keep layer names, so selection
and references stay stable.

## Check an edit

Parse the module with the design library and emit it again:

```luau
local value = Design.parse(source, library)
assert(Design.emit(value, library, { name = value.name }) == source)
```

If parsing fails, the editor treats the module as custom code. If the emitted
source differs, the editor rewrites the module in its own format on the next
edit. A library can provide a command for this check. Facet provides
`lute run tools/facet design check <module>`.

Multiple typed node references emit width-aware cell tables. Their declarations
and the supported tree forms keep their bytes after formatting and parse/emit.
Keep library preludes and supplied source snippets formatted as well.

Imported sources come from library-owned readables. Saving a canonical source
updates every instance; saving the assembly updates its bindings and hierarchy.
Keep the imported contract stable while linked. Select an instance and choose
**Edit Design** to edit its canonical layers, then **Back to assembly** to return.
The library supplies the source writer and publishes saved bytes to its readable.
Keep layer names stable so linked edits preserve selection.

For populated slot previews, supply editor or frame `slotSamples = { body = function(library, device) return Design.render(child, library, childContext) end }`.
Factories run under each frame's owner with its projected library and must build fresh children.
Slot inputs use `kind = "value"`; optional `luauType` names the factory's return type
(for example `Model`) instead of the library's root return type. Bind native samples
to the host runtime and WorldModel outside the source; normal owners release replacements.
Keep live sample bindings and `previews` callbacks in the host. `execute` shares named controls;
Read reports preview/device/camera selections and source identity, Capture returns host file paths,
and Close disposes once. These callbacks do not belong in the Design module.
