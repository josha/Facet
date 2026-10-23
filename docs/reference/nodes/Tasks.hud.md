# Tasks.hud

HUD with destination callbacks.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function hud(app: Facet.App, open: (string) -> (),
  coins: Facet.Readable<number>, xp: Facet.Readable<number>, left: Facet.Readable<string>): Frame
  local UI = app.UI
  local width = UI.environment().scaled(200)
  local captionRoom: Facet.Sides = { bottom = "l" }
  local function action(name: string, icon: string, caption: Facet.ValueString?)
    return UI.Button(name) { icon = icon, shape = "circle", controlSize = "regular",
      caption = caption or name, onActivate = function() open(name) end }
  end
  return UI.Composition "HUD" {
    UI.Region "Actions" { zone = "topRight", rank = 1,
      UI.HStack "Row" { gap = "m", padding = captionRoom, SelectionGroup = true,
        action("Shop", "view.grid"), action("Quests", "check"),
        action("Offer", "clock", function(use) return "Offer " .. use(left) end) } },
    UI.Region "Wallet" { zone = "topRight", rank = 2, reveal = false,
      UI.VStack "Readouts" { surface = "panel", padding = "m", gap = "s",
        UI.Text { textRole = "caption", role = "secondary", text = "Coins" },
        UI.Text { textRole = "numeral", text = function(use: Facet.Use) return Facet.format.compact(use(coins)) end },
        UI.ProgressView "XP" { label = "Level 3", value = xp, max = 100,
          Size = function(use: Facet.Use) return UDim2.fromOffset(use(width), 0) end } },
      UI.HStack "CompactReadouts" { surface = "panel", padding = "s", gap = "m",
        UI.Text { textRole = "numeral", text = function(use: Facet.Use) return Facet.format.compact(use(coins)) .. " Coins" end },
        UI.Text { textRole = "caption", text = function(use: Facet.Use) return `Level 3 · {use(xp)}/100` end } } },
  }
end
```

Keep play clear: [safe layout](Tasks.safe-layout.md).
Bind routes and gamepad hints: [HUD actions](HUD-actions.md).
Bind [server state](Tasks.state.md).
Open a [destination](Tasks.pages.md) with [collection/detail](Tasks.collection-detail.md).
