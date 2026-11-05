# Tasks.safe-layout

Keep touch actions clear of native movement controls.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local app = Facet.app({ name = "Game" })
app.mount(function()
  local UI = app.UI
  return UI.Composition "HUD" {
    UI.Region "Actions" { zone = "action", rank = 1,
      UI.VStack { gap = "s", align = "stretch",
        UI.Button { label = "Continue", onActivate = function() print("Continue") end },
        UI.Button { label = "Help", onActivate = function() print("Help") end },
      },
    },
  }
end)
script.Destroying:Connect(app.dispose)
```

Facet.app uses CoreUISafeInsets and SafeAreaCompatibility.None for device
cutouts and core UI. Screen with default `chrome = "device"` and Composition
also reserve the bottom band occupied by visible Roblox TouchGui buttons and
thumbstick regions when UserInputService.TouchEnabled is true. They observe
native bounds, visibility and lifetime. Rotation updates the clearance.
Nested surfaces add only clearance that their own bounds still overlap.
Bottom actions stay grouped above these controls; the world stays visible.

This policy applies to ScreenGui content in PlayerGui. Plugin and world
surfaces do not reserve touch space. Screen `chrome = "band"` or `"edge"`
opts out; keep interactive content in safe children. Game-owned controls
outside TouchGui still need authored `padding`.

Keep one Composition per HUD. Supply shorter region forms when the remaining
height is small. Check native-control clearance after rotation and dismissal
with actual touch input. A capture alone does not prove activation.

- [Tasks.hud](Tasks.hud.md)
- [Composition.layout.step-down](Composition.layout.step-down.md)
