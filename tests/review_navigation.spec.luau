--!strict
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local scenarioCtx = require("./lib/scenario_ctx")
local scenario_app = require("./lib/scenario_app")
local world = require("./lib/harness_world")
local Facet = require("../src") :: any
local Compose = require("../src/vendor/compose/core")
local UI = harness.UI

t.describe("review navigation", function()
	t.it("reaches every form control going down", function()
		local w = world.new({ preferredInput = "Gamepad", viewport = { x = 0, y = 0, w = 900, h = 700 } })
		local scenario = require("../examples/gallery/scenarios/selection_controls").build(scenarioCtx.ofHarness(w))
		w.present(scenario.screen)
		w.settle(2)
		local seen = {}
		for _ = 1, 25 do
			local p = w.pres.focus.focused:peek()
			seen[p] = true
			w.press("DPadDown")
		end
		local checkbox, join = false, false
		for p in seen do
			checkbox = checkbox or string.find(p, "Checkbox", 1, true) ~= nil
			join = join or string.find(p, "/Join", 1, true) ~= nil
		end
		t.expect(checkbox).toBe(true)
		t.expect(join).toBe(true)
		w.pres.dismiss(w.handle)
	end)
	t.it("reaches a slider between ordinary controls in either direction", function()
		local w = world.new({ preferredInput = "Gamepad" })
		local slider = harness.Controls.Slider(
			w.core,
			{ id = "Brightness", label = "Brightness", value = Compose.cell(40), min = 0, max = 100 }
		)
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.HStack({
					id = "VolumeRow",
					children = {
						UI.Button({ id = "Volume", label = "Volume" }),
						UI.Button({
							id = "Mute",
							label = "Mute",
						}),
					},
				}),
				slider.blueprint,
				UI.Button({ id = "Quality", label = "Quality" }),
			},
		}))
		w.pres.focus.focusOn("/S/VolumeRow/Volume")
		w.press("DPadDown")
		t.expect(string.find(w.pres.focus.focused:peek(), "Brightness", 1, true) ~= nil).toBe(true)
		w.pres.focus.focusOn("/S/Quality")
		w.press("DPadUp")
		t.expect(string.find(w.pres.focus.focused:peek(), "Brightness", 1, true) ~= nil).toBe(true)
		w.pres.dismiss(w.handle)
	end)
	t.it("reaches Collections directly in the simplified demo menu", function()
		local w = world.new({ preferredInput = "Gamepad", viewport = { x = 0, y = 0, w = 960, h = 540 } })
		local picker = require("../examples/gallery/client/demo_picker").mount({
			Facet = Facet,
			app = scenario_app.over(w.core, w.pres),
			core = w.core,
			env = w.env,
			presenter = w.pres,
			composed = true,
			mountDemo = function()
				return nil
			end,
		})
		-- `picker.rows` is a component (demo_picker.luau's own header comment:
		-- "the host that places it builds it in its own mount") — called
		-- inside the deferred screen, not eagerly before any owner exists.
		w.present(function()
			return UI.Screen({
				id = "S",
				children = {
					UI.ScrollView({
						id = "Menu",
						width = UI.fill(),
						height = UI.fill(),
						children = {
							picker.rows(),
						},
					}),
				},
			})
		end)
		local allControls, collections
		for _, path in w.adapter.paths() do
			if path:match("/all%-controls$") then
				allControls = path
			end
			if path:match("/collections$") then
				collections = path
			end
		end
		assert(allControls and collections)
		w.pres.focus.focusOn(allControls)
		w.press("DPadDown")
		t.expect(w.pres.focus.focused:peek()).toBe(collections)
		w.pres.dismiss(w.handle)
		picker.dispose()
	end)
end)
