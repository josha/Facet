# Tasks.shortcut

Give a HUD command a key, a gamepad button and a visible hint.

```luau
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local function menu(app: Facet.App, playerGui: Instance, openBag: () -> ()): Instance
  local UI, Host = app.UI, Facet.host(app.runtime)
  local bag = Host.InputAction "Bag" {
    Type = Enum.InputActionType.Bool,
    Pressed = function() openBag() end,
    Host.InputBinding { KeyCode = Enum.KeyCode.B },
    Host.InputBinding { KeyCode = Enum.KeyCode.ButtonY },
  }
  Host.InputContext "HudCommands" { Parent = playerGui, bag }
  return UI.Button "Bag" { icon = "bag", label = "Bag", shortcutHint = bag,
    onActivate = function() openBag() end }
end
```

Call this inside the mount function, with `Players.LocalPlayer.PlayerGui`.
Make one action for each HUD Button that opens a panel or runs a frequent
command, and put the actions in one InputContext. The Button shows the key
on a keyboard and the button glyph on a gamepad, and hides the hint on
touch. The key and the Button run the same function. Do not bind Escape,
Start, Space or Return. Do not bind a key that moves the character. A Sheet
or a Dialog closes with Escape and gamepad B.

Related: [Tasks.hud](Tasks.hud.md), [HUD-actions](HUD-actions.md).
