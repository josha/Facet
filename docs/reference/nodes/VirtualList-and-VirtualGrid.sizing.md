# VirtualList-and-VirtualGrid.sizing

For a short collection inside a content-sized Sheet, bind its viewport height
to its published `CanvasSize`. Do not calculate rows from the outer width:
the native scrollbar inset and the grid's paint gutters reduce the space for
columns. `mode = "all"` changes row lifetime, not viewport size.

Keep the scrollbar inset stable:

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
local app = Facet.app({})
local UI, runtime = app.UI, app.runtime
app.mount(function()
  local env, height = UI.environment(), C.cell(1)
  local spec: Facet.KeyedCollectionSpec<string, string> = {
    from = { "Amber", "Blue" }, key = function(item) return item end,
    minColumnWidth = env.scaled(220), itemSize = env.scaled(132),
    gap = env.scaled(16), VerticalScrollBarInset = Enum.ScrollBarInset.Always,
    render = function(current) return UI.Text { text = current } end,
    Size = function(use: Facet.Use): UDim2
      return UDim2.new(1, 0, 0, use(height))
    end,
  }
  local grid = UI.VirtualGrid(spec)
  local canvas = runtime.observe(grid, "CanvasSize")
  C.watch(function(use: Facet.Use)
    local size = use(canvas)
    assert(typeof(size) == "UDim2")
    height:set(size.Y.Offset)
  end)
  return grid
end)
```

`CanvasSize` includes paint gutters. Compose owns the observation and watch.
For large collections, keep a bounded viewport and let the collection scroll.
`AutomaticCanvasSize` changes canvas size, not viewport size; native child
measurement cannot measure unmounted rows.
