# Tasks.hud

Mount accepted progress with its subject ("Beacons 2/4") and a bound InputAction.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function hud(app: Facet.App, goal: Facet.ReadOnlyValue<string>,
  progress: Facet.ReadOnlyValue<string>, resource: Facet.ReadOnlyValue<string>,
  label: string, command: InputAction, activate: () -> ()): Frame
  local UI = app.UI
  local env = UI.environment()
  local width, wide = env.scaled(260), env.scaled(200)
  local pressed = command.Pressed:Connect(activate)
  Facet.Compose.cleanup(function() pressed:Disconnect() end)
  return UI.Composition "HUD" {
    UI.Region "Objective" { zone = "topLeft", rank = 2,
      UI.VStack "Full" { width = width, surface = "panel", padding = "m", gap = "s",
        UI.Text { text = goal, textRole = "heading", wrap = true },
        UI.Text { text = progress, textRole = "caption" } },
      UI.HStack "Short" { surface = "panel", padding = "s",
        UI.Text { text = progress } } },
    UI.Region "Resource" { zone = "topRight", rank = 3, reveal = false,
      UI.HStack "Counter" { surface = "panel", padding = "s",
        UI.Text { text = resource, textRole = "numeral" } } },
    UI.Region "Command" { zone = "action", rank = 1,
      UI.VStack "Primary" { width = wide, align = "stretch",
        UI.Button "Command" { label = label, appearance = "emphasis",
          shortcutHint = command, onActivate = function() activate() end } } },
  }
end
```

The `action` zone keeps the command in thumb reach: bottom centre on a
portrait screen, bottom right otherwise. The Button and the bound action
call activate; `shortcutHint` shows the action's glyph. The game owns its
InputContext; activate can act in the world or open a
[destination](Tasks.pages.md). Keep the center and movement controls clear.
Test narrow layouts.

[Safe layout](Tasks.safe-layout.md), [HUD actions](HUD-actions.md),
[minimaps](Tasks.minimap.md),
[server state](Tasks.state.md), [collection/detail](Tasks.collection-detail.md).
