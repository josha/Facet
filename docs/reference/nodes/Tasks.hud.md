# Tasks.hud

Read a wallet; open actions from a top-right row.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local app = Facet.app({ name = "Game", environment = { viewingDistance = "near" }, screen = { ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets } })
local UI = app.UI
local coins, xp, left = Facet.Compose.cell(1234567), Facet.Compose.cell(40), Facet.Compose.cell("2:30")
app.mount(function()
  local env = UI.environment()
  local compact, gap = env.scaled("controlSizes.compact.height"), env.scaled("space.xs")
  local function diameter(use: Facet.Use): number
    local d = use(env.topbarControlDiameter)
    return if d > 0 then d else use(compact)
  end
  local function action(name: string, icon: string, caption: Facet.ValueString?): TextButton
    return UI.Button(name) {
      icon = icon, shape = "circle",
      Size = function(use: Facet.Use): UDim2
        return UDim2.fromOffset(diameter(use), diameter(use))
      end,
      caption = caption or name,
      onActivate = function() end,
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
      action("Quests", "check"), action("Offer", "clock", function(use) return "Offer " .. use(left) end),
    },
    UI.VStack "Readouts" { surface = "panel", padding = "s", gap = "xs", align = "end",
      UI.Text { text = function(use: Facet.Use) return Facet.format.compact(use(coins)) .. " Coins" end },
      UI.ProgressView "XP" { label = "Level 3", value = xp, max = 100,
        Size = function(use: Facet.Use): UDim2 return UDim2.fromOffset(use(env.scaled(160)), 0) end },
    },
  }
end)
```

- [HUD-actions](HUD-actions.md)
- [Tasks.shop](Tasks.shop.md)
- [Tasks.sheet](Tasks.sheet.md)
