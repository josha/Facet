# Outline.Outline

Use `UI.Outline` for expandable rows. It has the same `from`, `key`,
`render(current, placement, key)`, selection, editing, drag and focus options
as VirtualList. Table and vertical VirtualList also accept the hierarchy
options below. VirtualGrid does not accept a hierarchy; pass the children of
the current folder as its flat source.

| Option | Meaning |
|---|---|
| `children` | Required for Outline. A field name or `(item) -> { child }?`. Return `nil` for a leaf and an array, including an empty array, for a folder. |
| `expanded` | Optional writable cell of `{ [key] = true }`. Omitted: local state, initially collapsed. Keep the cell in the model to share expansion across views. |
| `onExpansionChange` | Receives the proposed full expansion map. When supplied, the callback must write accepted changes to `expanded`. |
| `indent` | Non-negative indentation per level. Defaults to the theme's `space.l`. Deep indentation is capped to leave room for content. |

Keys must be stable and unique across the entire tree. Children must form an
acyclic tree. A children accessor reads the current model; make `from` reactive
when descendants change. The renderer receives the original item. It does not
need to draw a disclosure button or calculate indentation.

```luau
local expanded = Compose.cell({})
local selection = Compose.cell({})
local outline = UI.Outline {
    from = {
        { id = "folder", name = "Images", children = {
            { id = "portrait", name = "Portrait" },
        } },
    },
    key = "id",
    children = "children",
    expanded = expanded,
    selection = selection,
    selectionMode = "multiple",
    render = function(current)
        return UI.Text { text = function(use) return use(current).name end }
    end,
}
```

The disclosure button changes expansion without changing selection. Right
expands a folder or focuses its first child. Left collapses a folder or focuses
its parent. These commands also use D-pad Left/Right. They apply to row and
disclosure focus, leaving text editors and other cell controls their native
input. When a focused descendant closes, focus returns to its visible ancestor.
Hidden descendants keep their selection; `selectionFrom` can override the
complete tree used for selection validation.

Opening and closing animate row extents and the disclosure arrow with theme
motion tokens through Compose. A branch reveals its rows progressively so
expansion keeps windowed rendering bounded by the viewport. Cells retain their
natural size and clip within the animated row. Reduced motion changes expansion immediately. The native
button size and measured content determine the minimum height across themes.
