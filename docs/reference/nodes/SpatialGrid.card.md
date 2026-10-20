# SpatialGrid.card

Place items that span several cells.

```luau
local spec: Facet.SpatialGridSpec<Facet.SpatialPlacement, number> = {
    from = { { column = 1, row = 1, width = 2, height = 2 } },
    key = function() return 1 end,
    placement = function(item) return item end,
    columns = 5,
    rows = 4,
    render = function()
        return UI.Button { label = "Pack" }
    end,
}
UI.SpatialGrid(spec)
```

Open [SpatialGrid.reference](SpatialGrid.reference.md) for placement,
drag/drop and input behavior. Use VirtualGrid for ordered equal-sized items.
