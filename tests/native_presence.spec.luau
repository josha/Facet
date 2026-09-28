--!strict
local t = require("./lib/testkit")
local fadeKit = require("./lib/fade")
local Compose = require("../src/vendor/compose/core")
local overlay = require("./lib/overlay_world")

local function dialog(shown: any, options: any?): any
	return overlay.new(function(UI, Host)
		return UI.Dialog "D" {
			isPresented = shown,
			onPresentedChange = function(value: boolean)
				shown:set(value)
			end,
			title = "Quit race?",
			content = function()
				return Host.TextLabel "Body" { Text = "Progress is lost." }
			end,
		}
	end, options)
end

t.describe("presence: opacity leads travel", function()
	t.it("a dialog is opaque at 60 percent of its travel and clear at half of its exit", function()
		local shown = Compose.cell(true)
		local w = dialog(shown)
		local panel = w.find("Panel")
		local scale = panel:FindFirstChildWhichIsA("UIScale", true)
		local sawOpaqueEarly = false
		for _ = 1, 30 do
			w.advance(1 / 60)
			if fadeKit.of(panel) == 0 and scale.Scale < 1 then
				sawOpaqueEarly = true
			end
		end
		t.expect(sawOpaqueEarly).toBe(true)
		shown:set(false)
		local sawClearEarly = false
		for _ = 1, 30 do
			w.advance(1 / 60)
			if panel.Parent and fadeKit.of(panel) == 1 and scale.Scale > 0.94 then
				sawClearEarly = true
			end
		end
		t.expect(sawClearEarly).toBe(true)
		w.stop()
	end)
end)
