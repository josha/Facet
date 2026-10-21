# Tasks.safe-layout

Keep controls usable with touch and a gamepad.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
local app = Facet.app({ name = "Game" })
local UI = app.UI
app.mount(function()
  local bottomClearance = C.cell(0)
  return UI.Screen "Root" {
    padding = function(use: Facet.Use): Facet.Sides
      return { bottom = use(bottomClearance) }
    end,
    UI.AdaptiveStack "Actions" { width = "fill", gap = "s", padding = "m",
      UI.Text "Help" { text = "Choose an action", wrap = true },
      UI.Button "Play" { label = "Play", onActivate = function() print("Play") end },
    },
  }
end)
script.Destroying:Connect(app.dispose)
```

Facet.app uses CoreUISafeInsets and disables fullscreen compatibility
expansion. This clears device cutouts and core UI, not movement or action
buttons. Modal scrim paint covers the screen; dismissal stays in the safe area.

Keep game-owned HUD and controls in one Composition. For persistent game
chrome outside it, bind Screen.padding to the game's known clearance in
layout pixels. The example's bottomClearance starts at zero; update it from
the game's control layout. It does not measure Roblox's default Jump button.
Do not poll native touch controls to calculate padding.

Give regions a short landscape form as well as a narrow portrait form.
Composition selects from measured room and restores richer forms when they
fit. Check portrait, landscape and the return to portrait with movement and
Jump visible, including after panel dismissal. Use UI.environment for room
and input. Do not branch on the device or bind Escape or gamepad Start.

- [Tasks.hud](Tasks.hud.md)
- [Composition.layout.step-down](Composition.layout.step-down.md)
