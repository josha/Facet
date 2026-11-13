# Tasks.hud

Show progress with a subject and InputAction.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function hud(app: Facet.App, goal: Facet.ReadOnlyValue<string>,
  progress: Facet.ReadOnlyValue<string>, resource: Facet.ReadOnlyValue<string>?,
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
    if resource then UI.Region "Resource" { zone = "topRight", rank = 3, mayDrop = true, reveal = false,
      UI.HStack "Counter" { surface = "panel", padding = "s",
        UI.Text { text = resource, textRole = "numeral" } } } else nil,
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
Test short layouts. A list in a shared row needs `rows = "fit"`.

[Layout](Tasks.safe-layout.md), [actions](HUD-actions.md), [map](Tasks.minimap.md),
[state](Tasks.state.md), [details](Tasks.collection-detail.md).
