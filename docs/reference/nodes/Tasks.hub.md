# Tasks.hub

Keep the world as the main subject. Mount this lobby at the empty navigation path.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function hub(app: Facet.App, title: Facet.ValueString, status: Facet.ValueString,
  label: string, command: InputAction, activate: () -> (), openTasks: () -> ()): Frame
  local UI = app.UI
  local env = UI.environment()
  local function act()
    if not env.gameplaySuspended:peek() then activate() end
  end
  local pressed = command.Pressed:Connect(act)
  Facet.Compose.cleanup(function() pressed:Disconnect() end)
  return UI.Composition "Hub" {
    UI.Region "Identity" { zone = "topLeft", rank = 2,
      UI.VStack "Full" { width = env.scaled(320), surface = "panel", padding = "m", gap = "s",
        UI.Text { text = title, textRole = "title", wrap = true },
        UI.Text { text = status, wrap = true } },
      UI.VStack "Compact" { width = env.scaled(220), surface = "panel", padding = "s",
        UI.Text { text = title, textRole = "heading", wrap = true },
        UI.Text { text = status, textRole = "caption", wrap = true } } },
    UI.Region "Actions" { zone = "action", rank = 1,
      UI.VStack "Primary" { width = env.scaled(260), align = "stretch", gap = "s",
        UI.Button { label = label, appearance = "emphasis", shortcutHint = command,
          onActivate = function() act() end },
        UI.Button { label = "Tasks and settings", onActivate = function() openTasks() end } } },
  }
end
```

The world is first; the primary action is second; status and other tasks are
third. Region rank controls retention, not the world's visual size. Keep the
subject clear of both regions. The game owns the bound InputContext.
Use [pages](Tasks.pages.md) for other tasks; keep every destination reachable.
[Examples](Composition.examples.md) show this hub beside an object-led workbench.
