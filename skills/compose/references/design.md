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
- An item field inside a row: `function(use) return use(current).field end`.
  Wrap a non-text field that a text property reads in `tostring(...)`.
- An output call: `function(...) if props.onThing then props.onThing(...) end end`.
  In a row, pass the row with `props.onThing(current:peek())`.
- A repeated list: `from = props.list, key = "id", render = function(current) return <node> end`.
  A list inside a row reads a list field of the row:
  `from = function(use) return use(current).rows end`.
- A conditional child: `<show>(props.flag, function() return <node> end)`, where
  `<show>` is the library's show call (Facet: `Facet.Compose.show`).
  In a row, the condition can read a boolean item field.
- A table column cell: `render = function(current) return <node> end` inside a
  column record.
- Row actions: `rowActions = function(current) return { ... } end`.
- A style tag: `<tag>(<node>, { "tag-name" })`, where `<tag>` is the library's
  tag call (Facet: `Facet.tag`).
- A node reference: `refs.nN`, with the node wrapped in `capture("nN", <node>)`.
- A content property that holds a subtree: `glyph = function() return <node> end`.
  The node is a child of the control in the editor.
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
