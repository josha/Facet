# Tasks.hud

HUD actions and a wallet in the top bar strip.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function hud(app: Facet.App, open: (string) -> (),
  coins: Facet.Readable<number>, xp: Facet.Readable<number>, left: Facet.Readable<string>): Frame
  local UI = app.UI
  local captionRoom: Facet.Sides = { bottom = "l" }
  local function action(name: string, icon: string, caption: Facet.ValueString?)
    return UI.Button(name) { icon = icon, shape = "circle", controlSize = "regular",
      caption = caption or name, onActivate = function() open(name) end }
  end
  local function coinText(use: Facet.Use): string return Facet.format.compact(use(coins)) end
  return UI.Composition "HUD" {
    UI.Region "Wallet" { zone = "topbar", leading = true, rank = 1,
      UI.HStack "Readouts" { surface = "panel", padding = "s", gap = "s", align = "center",
        UI.Text { textRole = "numeral", text = coinText },
        UI.Text { textRole = "caption", role = "secondary", text = function(use: Facet.Use) return `Coins · Level 3 · {use(xp)}%` end } },
      UI.HStack "CompactReadouts" { surface = "panel", padding = "s", gap = "s", align = "center",
        UI.Text { textRole = "numeral", text = coinText },
        UI.Text { textRole = "caption", role = "secondary", text = "Coins" } } },
    UI.Region "Actions" { zone = "topRight", rank = 2,
      UI.HStack "Row" { gap = "m", padding = captionRoom, SelectionGroup = true,
        action("Shop", "view.grid"), action("Quests", "check"),
        action("Offer", "clock", function(use) return "Offer " .. use(left) end) } },
  }
end
```

The wallet rides the top bar's free strip, steps to its compact form as the strip narrows and moves to the `top` zone when none fits.  Keep strip forms 44 pixels tall at most.
Keep play clear: [safe layout](Tasks.safe-layout.md).
Bind routes and gamepad hints: [HUD actions](HUD-actions.md).
Bind [server state](Tasks.state.md).
Open a [destination](Tasks.pages.md) with [collection/detail](Tasks.collection-detail.md).
