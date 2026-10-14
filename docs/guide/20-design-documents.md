# Design documents

A Facet view module is the design document. Facet Design reads the Luau file,
shows its controls as a tree and edits the file in place. There is no scene
format and no export step. A human in the visual builder, an agent and a text
editor all change the same file.

Facet Design parses the file with the Lute `@std/syntax` parser. Each edit
replaces only the bytes of the changed entries. Formatting, comments and other
code stay unchanged.

Run the commands from the repository root with Lute:
`lute run tools/facet <command>`.

## Files

| File | Contents |
|---|---|
| `View.luau` | The view module. This is the design. |
| `View.luau.history.json` | The history of applied batches, with authors and inverse operations. |
| `View.luau.comments.json` | Comment threads. Each thread has a node id as its anchor. |
| `View.luau.lock` | A short-lived lock. One writer at a time changes the file. |

Facet Design makes the sidecar files when it first needs them. Add the sidecars
to `globIgnorePaths` in a Rojo project, or Rojo syncs them as JSON modules:

```json
"globIgnorePaths": ["**/*.history.json", "**/*.comments.json", "**/*.lock"]
```

## Editable subset

A view module ends with `return function(UI, model) ... end`. The first
parameter is the control table. The second parameter is the model and is
optional. The function ends with `return <control>`. That control is the root
node. Statements before it are code and stay unchanged.

```luau
--!strict
local Facet = require(game.ReplicatedStorage.Facet)
local Compose = Facet.Compose

return function(UI: Facet.Controls, model: Model): GuiObject
	return UI.Screen "Screen" {
		gap = "m",
		UI.Text "Title" {
			text = function(use)
				return use(model.title)
			end,
			textRole = "title" :: "title",
		},
		Compose.keyed({
			from = model.items,
			key = function(item)
				return item.id
			end,
			render = function(item)
				return UI.Text "Item" {
					text = function(use)
						return use(item).name
					end,
				}
			end,
		}),
	}
end
```

The tree has three node types:

- A **control** is a call such as `UI.VStack "Panel" { ... }`. The string is
  the label. A call without a label is also a control. A call on a local named
  `Host` is a control with the namespace `Host`. Facet Design does not check
  its properties against the schema.
- A **keyed** node is a `Compose.keyed({ from = ..., key = ..., render = ... })`
  call. The control that `render` returns is its template. The view module
  needs a local named `Compose`.
- A **code** node is any other child expression, such as `table.unpack(rows)`
  or `Compose.show(...)`. Facet Design shows it and keeps its bytes. It cannot
  edit it.

Each named entry in a control table is a property. Each list entry is a child.
A property value has one of these kinds:

| Kind | Source form |
|---|---|
| `string`, `number`, `boolean`, `nil` | A literal. A string can have a singleton cast: `"fill" :: "fill"`. |
| `token` | A string that names a theme token of the property, such as `"m"` for space or `"title"` for typography. |
| `binding` | `function(use) return use(model.path) end`, `model.path`, or `use(item).field` in a template. |
| `datatype` | `UDim2.new`, `UDim2.fromScale`, `UDim2.fromOffset`, `UDim.new`, `Vector2.new`, `Vector3.new`, `Color3.new`, `Color3.fromRGB`, `Color3.fromHSV`, `Color3.fromHex`, `NumberRange.new`, `NumberSequence.new`, `Rect.new`, `BrickColor.new`, `Font.new`, `Font.fromName` or `TweenInfo.new` with literal arguments. |
| `enum` | `Enum.SortOrder.LayoutOrder`. |
| `table` | A table of literal values, for example `{ top = 8, left = 12 }`. |
| `code` | Any other expression, such as a callback or a local. It is read-only. |

## Node ids

A node id is the path of labels from the root, joined with `/`, for example
`Screen/Panel/Title`. A label is unique among its siblings. An operation that
inserts a node gives it a unique label when the input has none.

Some segments do not come from a label:

- An unlabeled control has the segment `#Kind<n>`, for example `#Divider1`.
- A keyed node has the template label and `[]`, for example `Item[]`. Its
  template is `Item[]/Item`.
- A code node has the segment `#code<n>`.
- A second sibling with the same label gets `~2`. The tree reports this as a
  problem.

Positional segments change when siblings change. Give a node a label with
`rename` before you depend on its id.

## Operations

An operation is a JSON object with `op` and its fields. Most operations take a
`node` field. A node field takes an id or a label that is unique in the file.

| Operation | Input | Effect |
|---|---|---|
| `query_tree` | `node?`, `depth?` | Returns the tree and the file hash. |
| `get_node` | `node`, `native?` | Returns one node and the schema of its control. |
| `set_prop` | `node`, `prop`, `value` | Sets or adds a property. |
| `unset_prop` | `node`, `prop` | Removes a property. A required property stays. |
| `insert` | `parent`, `node`, position | Inserts a control or a keyed collection. |
| `remove` | `node` | Removes a node and its subtree. |
| `move` | `node`, `parent`, position | Moves a node to a parent or a position. |
| `wrap` | `nodes` or `node`, `kind`, `label?`, `props?` | Puts adjacent siblings in a new container. |
| `unwrap` | `node` | Replaces a container with its children. |
| `rename` | `node`, `label` | Changes a label, or adds one. |
| `bind` | `node`, `prop`, `path`, `source?`, `form?` | Binds a property to a model path or an item field. |
| `unbind` | `node`, `prop`, `value?` | Replaces a binding with a literal, or removes it. |
| `set_token` | `node`, `prop`, `token` | Sets a property to a theme token of that property. |
| `duplicate` | `node`, `label?` | Inserts a copy after the node. |

A position is one of `index` (zero-based), `before` (a sibling id) or `after`
(a sibling id). With no position, the node goes after the last child.

The `node` field of `insert` takes a new node:

```json
{
  "kind": "HStack",
  "label": "Actions",
  "props": { "gap": "s" },
  "children": [{ "kind": "Button", "props": { "label": "Save" } }]
}
```

A keyed collection uses `keyed` in place of `kind`:

```json
{ "keyed": { "from": "inventory.items", "key": "id", "item": "item", "template": { "kind": "Text", "props": { "text": { "kind": "binding", "source": "item", "path": "name" } } } } }
```

A value is a string, a number, a boolean or an object with `kind`:

```json
{ "kind": "token", "value": "l" }
{ "kind": "binding", "path": "stats.coins", "source": "model", "form": "use" }
{ "kind": "datatype", "type": "UDim2", "constructor": "fromScale", "args": [1, 0.5] }
{ "kind": "enum", "enum": "AutomaticSize", "item": "Y" }
{ "kind": "table", "fields": { "top": 8, "left": 12 } }
```

`query_tree` returns values in the same form, with `text` for the source. A
literal union property gets a cast when the file uses casts. The `bind` form
`use` writes a formula. The form `direct` writes the readable itself, as a
cell property needs.

### Batches

`apply` takes `ops`, an array of operations. It checks each input first. Then
it applies the operations in order, in memory. If one operation fails, the
file does not change and the error names that operation.

Each tree result has `hash`, the `SHA-256` digest of the file. Send it as `base` with a
change. If the file changed since that version, the change fails as `stale`.

Failures have a `code`: `invalid`, `stale`, `conflict`, `forbidden`,
`not_found`, `locked` or `internal`.

## History and undo

Each batch that changes the file adds a history entry. The entry records the
author, the hashes before and after, the operations and the inverse
operations. An inverse operation restores the exact bytes of one region and
names the bytes that it expects there.

`undo` applies the inverse of the latest edit of the calling author.
`redo` applies the latest undo of that author again. A new edit by that
author clears its redo. An author can undo only its own entries. If another
author changed the same region later, the undo fails as `conflict`.

An author is a name such as `human:alice`, `agent:claude` or `plugin:studio`.

## Comments

`comment_add` starts a thread on a node. `comment_reply` adds a message.
`comment_resolve` resolves a thread or opens it again. `comment_list` returns
the threads, optionally for one subtree. A thread follows its node through
`rename`, `move`, `wrap` and `unwrap`. A thread on a removed node stays in the
file with `orphaned` set.

## Schema

`lute run tools/facet schema` reads `src/ui/control_types.luau` with the same
parser. It follows each control to its constructor type and flattens the
property types. Each property has its type shape, whether it is optional and
whether it is native. Literal unions keep their alias names. The aliases
`SpaceStep`, `TextRole`, `ControlSize` and `Status` are theme token sets.

The types do not declare default values, so the schema has none. Operations
use the schema to check property names, value kinds, literal values, tokens
and required properties. Other tools read it through `tools/facet/lib/schema.luau`.

## Command line

```sh
lute run tools/facet design tree View.luau
lute run tools/facet design apply View.luau ops.json --author=human:alice
lute run tools/facet design undo View.luau --author=human:alice
lute run tools/facet design history View.luau
lute run tools/facet design serve examples --port=7878
lute run tools/facet tool list
lute run tools/facet tool describe set_prop
lute run tools/facet tool call set_prop '{"file":"View.luau","node":"Title","prop":"text","value":"Hi"}'
lute run tools/facet schema --control=Button
lute run tools/facet mcp
```

`--json` prints a command result as JSON. An operations file is an array, or an
object with `ops` and `base`.

## Server

`design serve` finds the view modules under its paths and watches them. It
serves HTTP and a WebSocket at `/ws` on `127.0.0.1`. One writer applies changes
in order. The server polls each file. A text edit from an editor reaches every
client as an update with the author `external`.

Each WebSocket message is a JSON object with `type`:

| From the client | Reply or broadcast |
|---|---|
| `hello` with `client.name` and `client.kind` | `welcome` with the client author and the files |
| `subscribe` with `file` | `snapshot` with `hash`, `source`, `tree` and `presence` |
| `apply` with `file`, `base`, `ops` and `request` | `applied` to the sender; `update` to each subscriber; or `rejected` |
| `undo` or `redo` with `file` | The same as `apply` |
| `presence` with `file`, `node` and `selection` | `presence` to the other subscribers |
| `tool` with `name`, `input` and `request` | `result`, and `update` or `comments` when the tool changes the file |
| `ping` | `pong` |

An `update` has the new `hash`, the `previous` hash, the `author`, the
operations, the `source` and the `tree`. A `rejected` message has an `error`
and the current `hash`. A WebSocket `apply` needs `base`.

HTTP has `GET /status`, `GET /files`, `GET /tree?file=`, `GET /source?file=`,
`GET /tools` and `POST /tool/<name>`. The header `x-facet-author` names the
author of a tool call.

## Agents with the Model Context Protocol

`lute run tools/facet mcp` serves the registry with the Model Context Protocol
(MCP). It reads one JSON-RPC 2.0 message for each line on standard input. It
writes one reply for each line on standard output. Each registry operation is
an MCP tool, with `file` and `base` fields for file operations. The tools
`schema_controls`, `schema_control`, `docs` and `list_views` are read-only.
The author is `agent:` and the client name from `initialize`.

Add the server to `.mcp.json` at the repository root:

```json
{
  "mcpServers": {
    "facet-design": {
      "command": "lute",
      "args": ["run", "tools/facet", "mcp"]
    }
  }
}
```

## Limits

- Facet Design edits only the subset on this page. Other code stays as text.
- New code follows the indentation and line endings of the file. Tests check
  edits of Stylua-formatted files with `stylua --check`.
- The file is the shared state. Concurrent writers take turns through the lock
  file and the base hash. The server does not merge two batches.
- The Lute 1.0.1 printer loses some bytes around parenthesized type arguments.
  Facet Design finds each token in the source again, so it keeps every byte.
