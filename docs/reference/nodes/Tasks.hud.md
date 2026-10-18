# Tasks.hud

Read a wallet and open actions from a top-right row.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local app = Facet.app({ name = "Game", environment = { viewingDistance = "near" }, screen = { ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets } })
local UI = app.UI
local coins, left = Facet.Compose.cell(100), Facet.Compose.cell("2:30")
app.mount(function()
  local env = UI.environment()
  local compact, gap = env.scaled("controlSizes.compact.height"), env.scaled("space.xs")
  local function diameter(use: Facet.Use): number
    local d = use(env.topbarControlDiameter)
    return if d > 0 then d else use(compact)
  end
  local function action(name: string, icon: string): TextButton
    return UI.Button(name) {
      icon = icon, shape = "circle", ClipsDescendants = false,
      Size = function(use: Facet.Use): UDim2
        return UDim2.fromOffset(diameter(use), diameter(use))
      end,
      caption = name,
      onActivate = function() print(name) end,
    }
  end
  return UI.VStack "HUD" {
    width = "hug", gap = "xl", align = "end",
    AnchorPoint = Vector2.new(1, 0),
    Position = function(use: Facet.Use): UDim2
      return UDim2.new(1, 0, 0, use(env.topbarInset).Height - diameter(use) - use(gap) / 2)
    end,
    UI.HStack "Actions" { gap = "m", align = "start", SelectionGroup = true,
      action("Shop", "view.grid"), action("Boosts", "chevron.up"),
      action("Quests", "check"), action("Offer", "clock"),
    },
    UI.VStack "Readouts" { gap = "xs", align = "end",
      UI.Text { text = left, textRole = "body" },
      UI.Text { text = function(use: Facet.Use)
        return Facet.format.grouped(use(coins)) .. " Coins"
      end, textRole = "numeral" },
    },
  }
end)
script.Destroying:Connect(app.dispose)
```

[HUD-actions](HUD-actions.md)

- [Tasks.shop](Tasks.shop.md)
- [Tasks.sheet](Tasks.sheet.md)
