# Tasks.hud

Read a wallet; open actions from the top-right corner.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
local app = Facet.app({ name = "Game" })
local UI = app.UI
local coins, xp, left = C.cell(1234567), C.cell(40), C.cell("2:30")
app.mount(function()
  local env = UI.environment()
  local captionRoom: Facet.Sides = { bottom = "l" }
  local function action(name: string, icon: string, caption: Facet.ValueString?): TextButton
    return UI.Button(name) { icon = icon, shape = "circle", controlSize = "compact",
      caption = caption or name, onActivate = function() end }
  end
  return UI.Composition "HUD" {
    UI.Region "Actions" { zone = "topRight", rank = 1,
      UI.HStack "Row" { gap = "m", padding = captionRoom, SelectionGroup = true,
        action("Shop", "view.grid"), action("Quests", "check"),
        action("Offer", "clock", function(use) return "Offer " .. use(left) end) } },
    UI.Region "Wallet" { zone = "topRight", rank = 2,
      UI.VStack "Readouts" { surface = "panel", padding = "s", gap = "xs",
        UI.Text { text = function(use: Facet.Use) return Facet.format.compact(use(coins)) .. " Coins" end },
        UI.ProgressView "XP" { label = "Level 3", value = xp, max = 100,
          Size = function(use: Facet.Use): UDim2 return UDim2.fromOffset(use(env.scaled(160)), 0) end } } },
  }
end)
```

Both regions stack in the core safe area; `captionRoom` keeps the captions
clear of the readouts. Do not make another ScreenGui. Set cells from the server state, for example
`client.onStateChanged(function(s) coins:set(s.coins) end)`.

- [HUD-actions](HUD-actions.md)
- [Tasks.shop](Tasks.shop.md)
- [Tasks.sheet](Tasks.sheet.md)
