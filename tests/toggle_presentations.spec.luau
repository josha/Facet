--!strict
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local fakeTarget = require("./lib/fake_target")
local Compose = require("../src/vendor/compose/core")
t.describe("Toggle presentations", function()
	for _, presentation in { "switch", "checkbox", "button" } do
		for _, input in { "pointer", "touch", "keyboard", "gamepad" } do
			t.it(presentation .. " toggles once through " .. input, function()
				local core = harness.newCore()
				local env = Facet.newEnvironment(core)
				env:set("viewportRect", { x = 0, y = 0, w = 600, h = 400 })
				local value = Compose.cell(false)
				local mixed = if presentation == "checkbox" then Compose.cell(true) else nil
				local enabled = Compose.cell(true)
				local changes = 0
				local control = harness.Controls.Toggle(core, {
					id = "T",
					label = "Receive race updates with detailed results",
					value = value,
					mixed = mixed,
					presentation = presentation,
					enabled = enabled,
					onChange = function()
						changes += 1
					end,
				})
				local adapter = fakeTarget.new()
				local system = Facet.newActionSystem(core)
				local pres = harness.newPresenter(core, env, adapter, system)
				pres.present(harness.UI.Screen({ id = "S", children = { control.blueprint } }))
				pres.refresh()
				if input == "pointer" or input == "touch" then
					adapter.tap("/S/T", { pointer = input })
				else
					system.deviceKey(if input == "keyboard" then "Return" else "ButtonA", true)
					system.deviceKey(if input == "keyboard" then "Return" else "ButtonA", false)
				end
				t.expect(value:peek()).toBe(true)
				t.expect(changes).toBe(1)
				if mixed then
					t.expect(mixed:peek()).toBe(false)
				end
				enabled:set(false)
				pres.refresh()
				adapter.tap("/S/T")
				t.expect(changes).toBe(1)
				t.expect(adapter.node("/S/T").rect.h >= 44).toBe(true)
			end)
		end
	end
end)

t.describe("switch value paint", function()
	local source = require("@lune/fs").readFile("src/client/screen_paint.luau")
	local body = require("./lib/adapter_source").bodyOf(source, "local function applyToggleValue(")
	local factory = require("@lune/luau").load([[return function(TweenService, Enum, isReducedMotion)
		local style = { motion = { normal = 0.2 } }
		local TOGGLE_KNOB_ON, TOGGLE_KNOB_OFF = 1, 0
		local function motionInfo() return "smooth" end
		local function overshootInfo() return "overshoot" end
		local function syncTags() end
		local function syncToggleArt() end
		local function stopToggleTweens() end
		local function togglePalette() return {trackOn=1, trackOff=0, knobOn=1, knobOff=0} end
	]] .. body .. "\nreturn applyToggleValue end")()
	for _, initial in { false, true } do
		t.it("paints initial " .. tostring(initial) .. " immediately, then slides without overshoot", function()
			local tweens = {}
			local paint = factory({
				Create = function(_, target, curve, values)
					table.insert(tweens, { target = target, curve = curve, values = values })
					return { Completed = { Once = function() end }, Play = function() end }
				end,
			}, { PlaybackState = { Completed = "Completed" } }, function()
				return false
			end)
			local h = { track = {}, knob = { Position = 0 } }
			-- A theme refresh before the binding must not count as an initial value.
			paint(h, false, true)
			paint(h, initial)
			t.expect(#tweens).toBe(0)
			t.expect(h.knob.Position).toBe(if initial then 1 else 0)
			paint(h, not initial)
			t.expect(#tweens).toBe(2)
			t.expect(tweens[2].curve).toBe("smooth")
			t.expect(tweens[2].values.Position).toBe(if initial then 0 else 1)
		end)
	end
end)
