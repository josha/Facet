--!strict
type Facet = typeof(require("@repo/src"))
type Controls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type Host = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Compose = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
type Runtime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
type ThemeCell = typeof(require("@repo/tools/typecheck/aliases").ThemeCell)
type VectorCell = typeof(require("@repo/src/vendor/compose/core").cell(Vector2.zero))
type Environment = { runtime: Runtime, theme: ThemeCell }
type Live = {
	Facet: Facet,
	mount: (
		(Controls, Host, Compose, Environment) -> Frame,
		{ size: VectorCell, environment: { touchEnabled: boolean, preferredTextSize: string } }
	) -> Frame,
	check: (string, boolean, unknown?) -> (),
	settle: (number) -> (),
}

local function run(t: Live, textSize: string)
	local Facet = t.Facet
	local C = Facet.Compose
	local size = C.cell(Vector2.new(390, 844))
	local capture = C.cell<<(Rect | GuiObject)?>>(nil)
	local stick: GuiObject
	local chat: GuiObject
	local prompt: GuiObject
	local function bottom(node: GuiObject): number
		return node.AbsolutePosition.Y + node.AbsoluteSize.Y
	end
	t.mount(function(_UI: Controls, Host: Host, _C: Compose, env: Environment): Frame
		local UI = Facet.controls(env.runtime, {
			theme = env.theme,
			motionLevel = "none",
			touchReservations = { capture },
			environment = { touchEnabled = true, preferredTextSize = textSize },
		})
		local player = game:GetService("Players").LocalPlayer
		local native = player:WaitForChild("PlayerGui"):FindFirstChild("TouchGui")
		if native and native:IsA("ScreenGui") then
			local enabled = native.Enabled
			native.Enabled = false
			C.cleanup(function()
				native.Enabled = enabled
			end)
		end
		local gui = game:GetService("GuiService")
		local controlsEnabled = gui.TouchControlsEnabled
		gui.TouchControlsEnabled = false
		C.cleanup(function()
			gui.TouchControlsEnabled = controlsEnabled
		end)
		stick = UI.Button "HostStick" {
			label = "Move",
			Size = UDim2.fromOffset(140, 140),
			Position = UDim2.new(0, 12, 1, -152),
		}
		chat = UI.Text { text = "Chat ready", textRole = "body" }
		prompt = UI.Button { label = "Interact" }
		return Host.Frame {
			Size = UDim2.fromScale(1, 1),
			stick,
			UI.Screen {
				padding = 0,
				UI.Composition "HUD" {
					topbar = false,
					padding = 8,
					UI.Region "Chat" { zone = "bottomLeft", rank = 1, chat },
					UI.Region "Prompt" { zone = "bottomRight", rank = 1, prompt },
				},
			},
		}
	end, { size = size, environment = { touchEnabled = true, preferredTextSize = textSize } })
	for _, dimensions in { Vector2.new(390, 844), Vector2.new(844, 390) } do
		size:set(dimensions)
		capture:set(stick)
		t.settle(30)
		local label = `{dimensions.X}x{dimensions.Y} {textSize}`
		t.check(`{label} chat clears the stick`, bottom(chat) <= stick.AbsolutePosition.Y + 1)
		t.check(`{label} prompt clears the stick`, bottom(prompt) <= stick.AbsolutePosition.Y + 1)
		t.check(`{label} nested clearance is not doubled`, stick.AbsolutePosition.Y - bottom(prompt) < 24)
		capture:set(Rect.new(stick.AbsolutePosition - Vector2.new(0, 40), stick.AbsolutePosition + stick.AbsoluteSize))
		t.settle(30)
		t.check(
			`{label} larger Rect lifts both regions`,
			bottom(chat) <= stick.AbsolutePosition.Y - 39 and bottom(prompt) <= stick.AbsolutePosition.Y - 39
		)
		capture:set(nil)
		t.settle(30)
		t.check(`{label} removing Rect restores room`, bottom(prompt) > stick.AbsolutePosition.Y)
	end
end

return {
	{
		id = "medium",
		contracts = { "UI.Screen", "UI.Composition" },
		run = function(t: Live)
			run(t, "Medium")
		end,
	},
	{
		id = "largest",
		contracts = { "UI.Screen", "UI.Composition" },
		run = function(t: Live)
			run(t, "Largest")
		end,
	},
}
