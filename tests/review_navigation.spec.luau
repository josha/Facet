--!strict
local t = require("./lib/testkit")
local world = require("./lib/world")
local Facet = require("../src") :: any
local UI = Facet.UI

t.describe("review navigation", function()
	t.it("reaches every form control going down", function()
		local w = world.new({ preferredInput = "Gamepad", viewport = { x = 0, y = 0, w = 900, h = 700 } })
		local scenario = require("../examples/gallery/scenarios/selection_controls").build({
			Facet = Facet,
			core = w.core,
			env = w.env,
			presenter = w.pres,
		})
		w.present(scenario.screen)
		w.settle(2)
		local seen = {}
		for _ = 1, 25 do
			local p = w.pres.focus.focused:get()
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
		local slider = Facet.Controls.Slider(
			w.core,
			{ id = "Brightness", label = "Brightness", value = w.core:signal(40), min = 0, max = 100 }
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
		t.expect(string.find(w.pres.focus.focused:get(), "Brightness", 1, true) ~= nil).toBe(true)
		w.pres.focus.focusOn("/S/Quality")
		w.press("DPadUp")
		t.expect(string.find(w.pres.focus.focused:get(), "Brightness", 1, true) ~= nil).toBe(true)
		w.pres.dismiss(w.handle)
	end)
	t.it("enters Card rail after opening the real demo menu's UI laboratory", function()
		local w = world.new({ preferredInput = "Gamepad", viewport = { x = 0, y = 0, w = 960, h = 540 } })
		local picker = require("../examples/gallery/client/demo_picker").mount({
			Facet = Facet,
			core = w.core,
			env = w.env,
			presenter = w.pres,
			composed = true,
			mountDemo = function()
				return nil
			end,
		})
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.ScrollView({
					id = "Menu",
					width = UI.fill(),
					height = UI.fill(),
					children = {
						picker.rows,
					},
				}),
			},
		}))
		local header
		for _, p in w.adapter.paths() do
			if p:match("/Laboratory/Header$") then
				header = p
			end
		end
		t.expect(header ~= nil).toBe(true)
		w.pres.focus.focusOn(header)
		w.press("ButtonA")
		w.settle(40)
		w.press("DPadDown")
		t.expect(w.pres.focus.focused:get():find("/card-rail", 1, true) ~= nil).toBe(true)
		w.pres.dismiss(w.handle)
		picker.dispose()
	end)
end)
