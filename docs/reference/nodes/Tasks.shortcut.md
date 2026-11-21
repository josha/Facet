# Tasks.shortcut

Give a HUD command a key, a gamepad button and a visible hint.

```luau
local Players = game:GetService("Players")
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local context = Instance.new("InputContext")
context.Name = "HudCommands"
context.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local function command(name: string, key: Enum.KeyCode, pad: Enum.KeyCode, run: () -> ()): InputAction
  local action = Instance.new("InputAction")
  action.Name = name
  for _, code in { key, pad } do
    local binding = Instance.new("InputBinding")
    binding.KeyCode = code
    binding.Parent = action
  end
  action.Pressed:Connect(run)
  action.Parent = context
  return action
end
local function menu(app: Facet.App, openBag: () -> ()): Instance
  local UI = app.UI
  local bag = command("Bag", Enum.KeyCode.B, Enum.KeyCode.ButtonY, openBag)
  return UI.Button "Bag" { icon = "bag", label = "Bag", shortcutHint = bag,
    onActivate = function() openBag() end }
end
```

Make one action for each HUD Button that opens a panel or runs a frequent
command. The Button shows the key on a keyboard and the button glyph on a
gamepad, and hides the hint on touch. The key and the Button run the same
function. Do not bind Escape, Start, Space or Return. Do not bind a key
that moves the character. A Sheet or a Dialog closes with Escape and
gamepad B.

Related: [Tasks.hud](Tasks.hud.md), [HUD-actions](HUD-actions.md).
