# Tasks.shop

Browse items and buy from a short collection in one scrolling Sheet.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
local app = Facet.app({})
local UI, runtime = app.UI, app.runtime
type Item = { id: string, name: string, price: number }
local items: { Item } = { { id = "kart", name = "Kart", price = 250 } }
local open, coins = C.cell(false), C.cell(300)
local owned = C.cell({} :: { [string]: boolean })
local buy = assert(game.ReplicatedStorage:FindFirstChild("Purchase")) :: RemoteFunction
app.mount(function()
  local env = UI.environment()
  local height = C.cell(1)
  local actions: { [string]: Facet.CardControls } = {}
  local cards: { [string]: Frame } = {}
  local grid: Facet.KeyedCollectionSpec<Item, string> = {
    from = items, key = "id", mode = "all", measure = true,
    minColumnWidth = env.scaled(220), itemSize = env.scaled(132),
    gap = env.scaled(16), VerticalScrollBarInset = Enum.ScrollBarInset.Always,
    Size = function(use: Facet.Use): UDim2 return UDim2.new(1, 0, 0, use(height)) end,
    onActivate = function(_item, key)
      local entry = actions[key]
      if entry and entry.enterActions then entry.enterActions() end
    end,
    render = function(row, _placement, key)
      local controls: Facet.CardControls = {}
      actions[key] = controls
      local card = UI.Card(key) {
        title = function(use: Facet.Use): string return use(row).name end,
        reveal = "always", controls = controls,
        browseTarget = function()
          local card = cards[key]
          local hit = card and card.Parent and card.Parent:FindFirstChild("RowHit")
          return if hit and hit:IsA("GuiObject") then hit else nil
        end,
        caption = function(use: Facet.Use): string
          local item = use(row)
          local missing = math.max(0, item.price - use(coins))
          return `{item.price} Coins` .. (if missing > 0 then ` · Need {missing} more` else "")
        end,
        primaryAction = {
          label = function(use: Facet.Use): string return if use(owned)[key] then "Owned" else "Buy" end,
          enabled = function(use: Facet.Use): boolean return not use(owned)[key] end,
          onActivate = function()
            local ok: boolean = buy:InvokeServer(key)
            owned:update(function(v) v = table.clone(v) v[key] = ok return v end)
          end,
        },
      }
      cards[key] = card
      C.cleanup(function() cards[key], actions[key] = nil, nil end)
      return card
    end,
  }
  return UI.VStack "Hud" {
    UI.Button "Shop" { label = "Shop", onActivate = function() open:set(true) end },
    UI.Sheet "ShopPanel" { title = "Shop", isPresented = open, closeButton = "Close",
      placement = "center", width = "wide", detents = { "hug" },
      content = function()
        local collection = UI.VirtualGrid "Items"(grid)
        local canvas = runtime.observe(collection, "CanvasSize")
        C.watch(function(use: Facet.Use)
          local size = use(canvas)
          assert(typeof(size) == "UDim2")
          height:set(size.Y.Offset)
        end)
        return collection
      end },
  }
end)
```

Allow low-funds Buy. [Feedback](Tasks.purchase.md).
Keep pending requests and confirmed ownership in the model, outside row owners.
Read current wallet and item values in property functions; a row can retain its
key while its value changes.

The Sheet uses a `hug` detent and owns scrolling. It grows with short content
and clamps to the safe height when the collection needs scrolling.
`mode = "all"` keeps this deliberately short
collection mounted, and the published canvas height gives it a content height.
Do not add a second fixed-height scrolling viewport inside the Sheet.
For a large catalog, use a bounded windowed collection instead. See
[collection sizing](VirtualList-and-VirtualGrid.sizing.md).

Buy stays visible with `reveal = "always"`. Gamepad activation enters the
card's actions without purchasing; Back returns to its browse stop. See
[card browsing](Card.browseTarget.md).

Categories use `Picker` with `style = "segmented"` when every category must
stay directly available. Derive `from` from the category, query
and confirmed ownership cells. Keep stable item keys, show an empty result
and provide Clear. Test category changes, an empty Owned filter, refilling the
same collection and returning from its last action. [Panels](Tasks.sheet.md).
