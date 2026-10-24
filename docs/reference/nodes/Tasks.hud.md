# Tasks.hud

HUD with destination callbacks and a wallet in the top bar strip.

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
  local function coinText(use: Facet.Use): string return Facet.format.compact(use(coins)) .. " Coins" end
  return UI.Composition "HUD" {
    UI.Region "Wallet" { zone = "topbar", leading = true, rank = 1,
      UI.HStack "Readouts" { surface = "panel", padding = "s", gap = "m",
        UI.Text { textRole = "label", text = coinText },
        UI.Text { textRole = "caption", role = "secondary", text = function(use: Facet.Use) return `Level 3 · {use(xp)}/100` end } },
      UI.HStack "CompactReadouts" { surface = "panel", padding = "s",
        UI.Text { textRole = "label", text = coinText } } },
    UI.Region "Actions" { zone = "topRight", rank = 2,
      UI.HStack "Row" { gap = "m", padding = captionRoom, SelectionGroup = true,
        action("Shop", "view.grid"), action("Quests", "check"),
        action("Offer", "clock", function(use) return "Offer " .. use(left) end) } },
  }
end
```

The wallet rides the free strip of the top bar beside Roblox's buttons.  It steps to its compact form when the strip narrows and moves into the `top` zone when even that does not fit, as on a console.  Keep each strip form 44 pixels tall or less.
Keep play clear: [safe layout](Tasks.safe-layout.md).
Bind routes and gamepad hints: [HUD actions](HUD-actions.md).
Bind [server state](Tasks.state.md).
Open a [destination](Tasks.pages.md) with [collection/detail](Tasks.collection-detail.md).
