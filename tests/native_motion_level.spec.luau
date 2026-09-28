--!strict
local t = require("./lib/testkit")
local fadeKit = require("./lib/fade")
local Compose = require("../src/vendor/compose/core")
local overlay = require("./lib/overlay_world")

local function levelWorld(options: any?): (any, any)
	local env: any = nil
	local w = overlay.new(function(UI, Host)
		env = UI.environment()
		return Host.Frame "Screen" {}
	end, options)
	return w, env
end

local function alertWorld(options: any?): (any, any)
	local shown = Compose.cell(false)
	local w = overlay.new(function(UI)
		return UI.Alert {
			isPresented = shown,
			title = "Leave?",
			actions = { { id = "stay", label = "Stay", role = "cancel" } },
		}
	end, options)
	return w, shown
end

t.describe("motion levels", function()
	t.it("follows the device: normal, and limited under the engine's Reduce Motion", function()
		local w, env = levelWorld()
		t.expect(env.motionLevel:peek()).toBe("normal")
		t.expect(env.reducedMotion:peek()).toBe(false)
		w.gui.ReducedMotionEnabled = true
		t.expect(env.motionLevel:peek()).toBe("limited")
		t.expect(env.reducedMotion:peek()).toBe(true)
		w.gui.ReducedMotionEnabled = false
		t.expect(env.motionLevel:peek()).toBe("normal")
		w.stop()
	end)

	t.it("a level the game sets wins over the device, both ways", function()
		local w, env = levelWorld({ motionLevel = "none" })
		t.expect(env.motionLevel:peek()).toBe("none")
		w.stop()
		local chosen = Compose.cell("normal")
		local w2, env2 = levelWorld({ motionLevel = chosen })
		w2.gui.ReducedMotionEnabled = true
		t.expect(env2.motionLevel:peek()).toBe("normal")
		t.expect(env2.reducedMotion:peek()).toBe(false)
		chosen:set("limited")
		t.expect(env2.motionLevel:peek()).toBe("limited")
		w2.stop()
	end)

	t.it("refuses the removed reducedMotion option and an unknown level", function()
		local ok, message = pcall(levelWorld, { reducedMotion = true })
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(message), "motionLevel", 1, true) ~= nil).toBe(true)
		local bad, why = pcall(levelWorld, { motionLevel = "reduced" })
		t.expect(bad).toBe(false)
		t.expect(string.find(tostring(why), "motionLevel", 1, true) ~= nil).toBe(true)
	end)

	t.it("an alert is whole on its first frame under none and scales in under normal", function()
		local w, shown = alertWorld({ motionLevel = "none" })
		shown:set(true)
		local panel = w.find("AlertPanel")
		t.expect(panel:FindFirstChildWhichIsA("UIScale", true).Scale).toBe(1)
		t.expect(fadeKit.of(panel)).toBe(0)
		w.stop()
		local w2, shown2 = alertWorld({ motionLevel = "normal" })
		shown2:set(true)
		local panel2 = w2.find("AlertPanel")
		w2.find("AlertContent").Parent.AbsoluteSize = w2.Vector2.new(300, 60)
		w2.advance(1 / 60, 3)
		t.expect(panel2:FindFirstChildWhichIsA("UIScale", true).Scale < 1).toBe(true)
		w2.stop()
	end)
end)
