# Tasks.hud

A race HUD with a wallet and a Garage button in the top bar strip.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function hud(app: Facet.App, open: (string) -> (), coins: Facet.Readable<number>,
  standing: Facet.Readable<string>, lap: Facet.Readable<string>): Frame
  local UI = app.UI
  local function garage() open("Garage") end
  local edge: Facet.Sides = { left = "m", right = "m" }
  return UI.Composition "HUD" { padding = "m",
    UI.Region "Garage" { zone = "topbar", trailing = true, rank = 1,
      UI.Button "Garage" { label = "Garage", icon = "view.grid", controlSize = "compact",
        corners = "pill", onActivate = garage },
      UI.Button "GarageIcon" { icon = "view.grid", name = "Garage", shape = "circle",
        controlSize = "compact", onActivate = garage } },
    UI.Region "Wallet" { zone = "topbar", leading = true, rank = 2,
      UI.Button "Wallet" { controlSize = "compact", corners = "pill",
        label = function(use: Facet.Use) return Facet.format.compact(use(coins)) .. " Coins" end,
        onActivate = function() open("Shop") end } },
    UI.Region "Race" { zone = "topLeft", rank = 3,
      UI.HStack "Race" { surface = "panel", height = 44, padding = edge, gap = "s", align = "center",
        UI.Text { textRole = "numeral", text = standing },
        UI.Text { textRole = "caption", role = "secondary", text = lap } } },
  }
end
```

Strip items join Roblox's row, so they match its buttons: `compact` controls 44 pixels tall, centered on its line, round like its pills and flat.  The race plate takes the same height and no shadow, and `padding = "m"` lines the HUD up under Roblox's first button.  Garage ranks first, so the wallet moves below the bar before Garage leaves the strip.
Keep play clear: [safe layout](Tasks.safe-layout.md).
Bind routes and gamepad hints: [HUD actions](HUD-actions.md).
Bind [server state](Tasks.state.md).
Open a [destination](Tasks.pages.md) with [collection/detail](Tasks.collection-detail.md).
