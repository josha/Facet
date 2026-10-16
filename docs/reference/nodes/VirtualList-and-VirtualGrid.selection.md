# VirtualList-and-VirtualGrid.selection

- `selection` is a writable key-set map.
- `selectionMode` defaults to single when you supply `selection` or its
  callback. Otherwise it defaults to none.
- `onSelectionChange(nextMap)`, `onActivate(item, key)` and `onReachEnd`
  connect control events to domain behavior.
- When the selection mode is not `none`, one mouse click selects a row. A
  double click, Return, a gamepad press or a touch tap runs `onActivate`. A
  double click keeps the selection. When the mode is `none`, each activation
  runs `onActivate`. Table rows follow the same rule.
- `selectable(item)`, `reorderable`, `movable(item)`, `dragLabel` and
  `onReorder(keys, insertionSlot)` use the same zero-based insertion contract
  among the remaining rows as Table.
- A keyboard or gamepad move steps along the scrolling axis. A vertical
  collection uses Up and Down. A horizontal collection uses Left and Right.
- A reorder that would move a row that is not movable does not occur.

Native properties and children stay available.

In strict Luau, give the spec a type on a local and pass the local to the
constructor. `Facet.KeyedCollectionSpec<Item, Key>` is a spec with `key`.
`Facet.IdentityCollectionSpec<Item>` is a spec without `key`. Outline and
Table use `Facet.KeyedOutlineSpec`, `Facet.IdentityOutlineSpec`,
`Facet.KeyedTableSpec` and `Facet.IdentityTableSpec`. The type gives `render`,
`current` and `use` their types, so they need no annotation. A key function, a
positional child such as `UI.fill()` or an unannotated `render` in an inline
spec makes the type checker report `None of the overloads ... are compatible`
without the cause. Put the type on the spec to see the cause.

```luau
type Item = { id: string, title: string }

local rows = Compose.cell({ { id = "a", title = "Amber" } } :: { Item })
local spec: Facet.KeyedCollectionSpec<Item, string> = {
    UI.fill(),
    from = rows,
    key = function(item, _index) return item.id end,
    itemSize = 52,
    render = function(current)
        return UI.Button {
            label = function(use) return use(current).title end,
            onActivate = function() inspect(current:peek().id) end,
            Size = UDim2.new(1, 0, 0, 52),
        }
    end,
}
local list = UI.VirtualList "Rows" (spec)
```
