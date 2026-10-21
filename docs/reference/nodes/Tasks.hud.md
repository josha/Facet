# Tasks.hud

Read a wallet and progress at a glance; keep navigation distinct from readouts.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
local app = Facet.app({ name = "Game" })
local UI = app.UI
local coins, xp, left = C.cell(1234567), C.cell(40), C.cell("2:30")
app.mount(function()
  local env = UI.environment()
  local progressWidth = env.scaled(200)
  local captionRoom: Facet.Sides = { bottom = "l" }
  local function action(name: string, icon: string, caption: Facet.ValueString?): TextButton
    return UI.Button(name) { icon = icon, shape = "circle", controlSize = "regular",
      caption = caption or name, onActivate = function() end }
  end
  return UI.Composition "HUD" {
    UI.Region "Actions" { zone = "topRight", rank = 1,
      UI.HStack "Row" { gap = "m", padding = captionRoom, SelectionGroup = true,
        action("Shop", "view.grid"), action("Quests", "check"),
        action("Offer", "clock", function(use) return "Offer " .. use(left) end) } },
    UI.Region "Wallet" { zone = "topRight", rank = 2, reveal = false,
      UI.VStack "Readouts" { surface = "panel", padding = "m", gap = "s",
        UI.Text "Currency" { textRole = "caption", role = "secondary", text = "Coins" },
        UI.Text "Balance" { textRole = "numeral", text = function(use: Facet.Use) return Facet.format.compact(use(coins)) end },
        UI.ProgressView "XP" { label = "Level 3", value = xp, max = 100,
          Size = function(use: Facet.Use): UDim2 return UDim2.fromOffset(use(progressWidth), 0) end } },
      UI.HStack "CompactReadouts" { surface = "panel", padding = "s", gap = "m",
        UI.Text "Balance" { textRole = "numeral", text = function(use: Facet.Use) return Facet.format.compact(use(coins)) .. " Coins" end },
        UI.Text "XP" { textRole = "caption", text = function(use: Facet.Use) return `Level 3 · {use(xp)}/100` end } } },
  }
end)
```

Both regions stack in the core safe area; `captionRoom` keeps the captions
clear of the readouts. The balance is the main readout, with a smaller currency
label and progress below. The second form is shorter for a shallow viewport
and preserves the same information. Composition chooses between the forms.
Do not make another ScreenGui or concatenate every statistic into one label.
Replace the sample cells with server state as shown in [Tasks.state](Tasks.state.md).

The core safe area does not reserve space for gameplay touch controls. Keep
game-owned controls in this Composition and check both phone orientations
with movement controls visible. Reserve space for other persistent game
chrome as described in [Tasks.safe-layout](Tasks.safe-layout.md).

- [HUD-actions](HUD-actions.md)
- [Tasks.shop](Tasks.shop.md)
- [Tasks.sheet](Tasks.sheet.md)
