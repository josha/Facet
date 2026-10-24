# Tasks.hud

Mount directly. Supply accepted progress with its subject ("Beacons 2/4")
and a bound InputAction.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function hud(app: Facet.App, goal: Facet.Readable<string>,
  progress: Facet.Readable<string>, resource: Facet.Readable<string>,
  label: string, command: InputAction, activate: () -> ()): Frame
  local UI = app.UI
  local width = UI.environment().scaled(260)
  local pressed = command.Pressed:Connect(activate)
  Facet.Compose.cleanup(function() pressed:Disconnect() end)
  local function action()
    local hint: Facet.ShortcutHintActionProps = { action = command, cap = false }
    local hintControl: (Facet.ShortcutHintProps) -> (Frame | TextLabel) = UI.ShortcutHint
    return UI.Button "Command" { label = label, appearance = "emphasis",
      onActivate = function() activate() end, hintControl(hint) }
  end
  return UI.Composition "HUD" {
    UI.Region "Objective" { zone = "topLeft", rank = 1,
      UI.VStack "Full" { width = width, surface = "panel", padding = "m", gap = "s",
        UI.Text { text = goal, textRole = "heading", wrap = true },
        UI.Text { text = progress, textRole = "caption" }, action() },
      UI.HStack "Short" { surface = "panel", padding = "s", gap = "s",
        UI.Text { text = progress }, action() } },
    UI.Region "Resource" { zone = "topRight", rank = 2, reveal = false,
      UI.HStack "Counter" { surface = "panel", padding = "s",
        UI.Text { text = resource, textRole = "numeral" } } },
  }
end
```

Both forms and the bound action call activate. The game owns its InputContext;
activate can act in the world or open a [destination](Tasks.pages.md).
Keep the center and movement controls clear. Test short and narrow room with real text.

[Safe layout](Tasks.safe-layout.md), [HUD actions](HUD-actions.md),
[server state](Tasks.state.md), [collection/detail](Tasks.collection-detail.md).
