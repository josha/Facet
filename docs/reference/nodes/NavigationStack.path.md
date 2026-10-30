# NavigationStack.path

Clone the path array before editing it, preserving the existing entry tables.
Entries are retained by table identity; `id` selects a destination and is not a
page-instance key. Rebuilding the prefix replaces pages and changes motion,
focus restoration and local state. Multiple entries may use the same `id`.

```luau
local initial: { Facet.NavigationEntry<string> } = { { id = "collection" } }
local path = Facet.Compose.cell(initial)
local nextPath = table.clone(path:peek())
table.insert(nextPath, { id = "detail", value = "item-1" })
path:set(nextPath)
```

For Back, clone the path, remove its last entry, then set the cell. Clearing
the path intentionally returns to root. Retain existing entries when their page
state and focus should survive; use fresh entries for deliberate replacements.

To replace the current destination, clone the path and assign the last entry
before one `path:set`. Do not pop and defer a push: that requests two changes
and can expose the previous page between them. For a child, append one entry
and keep the parent in history.

A destination's `onBack(entry)` runs when the player asks to leave that page
with B, Escape, the stack Back or an edge swipe. Return `false` to keep the
page, for example to ask about unsaved changes in a Dialog. A path that the
game sets itself does not call `onBack`.
