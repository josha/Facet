# Tasks.safe-layout

Keep controls usable with touch and a gamepad.

Controls: Screen, AdaptiveStack, Button, Text.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local Compose = Facet.Compose
local app = Facet.app({ name = "Game" })
local UI = app.UI

app.mount(function()
    return UI.Screen "Root" {
        UI.AdaptiveStack "Actions" {
            width = "fill", gap = "s", padding = "m",
            UI.Text "Help" { text = "Choose an action", wrap = true },
            UI.Button "Play" { label = "Play", onActivate = function() print("Play") end },
        },
    }
end)
script.Destroying:Connect(app.dispose)
```

Facet.app sets ScreenGui.ScreenInsets to Enum.ScreenInsets.CoreUISafeInsets and disables fullscreen compatibility expansion. Presented content stays inside the core UI and device safe area. Modal scrim paint covers the full screen; its dismissal button stays inside the safe area. Composition uses GuiService.TopbarInset and Enum.ScreenInsets.TopbarSafeInsets for a topbar region. Native selection and control input handle activation. Use UI.environment for available room and preferred input. Do not branch on the device. Do not bind Escape or gamepad Start.

The core safe area does not reserve space for movement or action buttons.
Keep the game's HUD and its own controls in one Composition so their regions
share the available room. Use Screen.padding for persistent game chrome that
is outside that Composition. Keep that padding in the game's layout model;
do not repeatedly scan native touch controls to calculate it.

Give each HUD region a form that fits a short landscape view as well as a
narrow portrait view. A wider screen can have less height. Composition
selects forms from the measured room after a resize; it does not keep a
smaller form when a richer form fits again. Check portrait, landscape and
the return to portrait with Roblox's movement and Jump controls visible.
Check them again after closing each panel.

When the game knows the space reserved by its own controls, bind that value
to native UIPadding around the Composition. In this example,
`bottomClearance` starts at zero. The game's control layout must update it
with its required clearance in layout pixels. It is not a guessed phone
margin or an automatic measurement of Roblox's default Jump button.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
local app = Facet.app({ name = "Game" })
local UI, Host = app.UI, app.runtime.constructors
app.mount(function()
  local bottomClearance = C.cell(0)
  return Host.Frame "GameRoom" {
    BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
    Host.UIPadding {
      PaddingBottom = function(use: Facet.Use): UDim
        return UDim.new(0, use(bottomClearance))
      end,
    },
    UI.Composition "HUD" {
      UI.Region "Status" { zone = "topRight", rank = 1, reveal = false,
        UI.Text "FullStatus" { text = "Coins 300 · Level 3", textRole = "strong" },
        UI.Text "ShortStatus" { text = "300 · L3", textRole = "caption" },
      },
    },
  }
end)
```

Open:

- [AdaptiveStack.card](AdaptiveStack.card.md)
- [Screen.card](Screen.card.md)
- [environment](environment.md)
- [Tasks.hud](Tasks.hud.md)
- [Composition.layout.step-down](Composition.layout.step-down.md)
