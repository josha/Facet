### Reserved collection slots

<!-- aliases: Reserved collection slots | reserved-collection-slots -->

VirtualList and VirtualGrid accept `slots: Input<{ K }>` with unique item keys.
The keys define the slot order. A key absent from `from` shows a non-selectable
recess. When that item returns to `from`, it uses its reserved slot. Items not
listed in `slots` follow the listed keys in source order. Remove a key from
`slots` to release its slot. Remaining items reflow with the theme travel spring.
Without `slots`, collections keep their compact layout. Field-name keys use
strings. A key function can return another key type.

`slotControls: SlotControls<K>` receives `nodeOfKey(key) -> GuiObject?`.
It returns the native slot anchor while that slot is retained. Pass that node
to `UI.Travel.destination` for a programmatic Recall. Use `mode = "all"` when
every reserved slot must have an anchor. The function clears on disposal.
The transparent anchor stays visible when occupied. Only its recess paint hides,
so content landed by Travel stays visible after a recalled item returns.

```luau
local slots = Compose.cell({ "A", "M", "I", "G", "O", "S", "E" })
local rack = Compose.cell({ { id = "A" }, { id = "M" }, { id = "I" } })
local function renderTile(current)
    return UI.Button { label = function(use) return use(current).id end }
end
UI.VirtualGrid {
    from = rack,
    key = "id",
    slots = slots,
    columns = 7,
    itemSize = 52,
    render = renderTile,
}
```

Keep a transferred key in `slots` until Play or Recall releases it. The
consumer owns both lists. The collection owns recesses, placement and reflow.
A collection drop target supplies the reserved key's landing rectangle when
its payload has `keys`, unless `drop.landing` supplies another rectangle.
Use `drop.travel = true` for the shared Travel engine to return to that slot.
