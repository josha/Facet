--!strict
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local world = require("./lib/harness_world")
local Facet = require("../src") :: any
local Compose = require("../src/vendor/compose/core")
local UI = harness.UI
t.describe("semantic control rows", function()
	t.it("fits a described toggle beside its natural-width value in a narrow desktop theme", function()
		local snapshot = require("../src/themes/snapshot")
		local w = world.new({
			viewport = { x = 0, y = 0, w = 320, h = 640 },
			themeMetrics = snapshot.resolve(require("../examples/themes/classic_desktop").build(Facet.themes), nil, {}),
		})
		local toggle = harness.Controls.Toggle(w.core, {
			id = "Assist",
			label = "Driving assistance",
			value = Compose.cell(true),
			row = { description = "Keep the car stable on rough terrain", icon = "settings" },
		})
		w.present(UI.Screen({
			id = "S",
			children = {
				UI.ScrollView({
					id = "Rows",
					width = UI.fill(),
					height = UI.fill(),
					padding = { left = 8, right = 8 },
					children = { toggle.blueprint },
				}),
			},
		}))
		-- Unnamed row stacks carry generated ids, so the lookups go by suffix.
		local function find(suffix: string): string
			for _, path in w.adapter.paths() do
				if string.sub(path, 1, 15) == "/S/Rows/Assist/" and string.sub(path, -#suffix) == suffix then
					return path
				end
			end
			error("missing " .. suffix)
		end
		local descriptionPath = find("/Description")
		local labels = w.controller.rectOf(string.sub(descriptionPath, 1, -#"/Description" - 1))
		local value = w.controller.rectOf(find("/Value"))
		local description = w.controller.rectOf(descriptionPath)
		t.expect(description.y + description.h <= labels.y + labels.h).toBe(true)
		t.expect(labels.w).toBeGreaterThan(value.w * 2)
		w.pres.dismiss(w.handle)
		toggle.dispose()
	end)
	for _, input in { "Gamepad", "Keyboard", "Touch", "MouseKeyboard" } do
		t.it("keeps one semantic target and readable content for " .. input, function()
			local w = world.new({ preferredInput = input, viewport = { x = 0, y = 0, w = 390, h = 844 } })
			local value = Compose.cell(false)
			local volume = Compose.cell(50)
			local hits = 0
			local action = harness.Controls.Button(w.core, {
				id = "Action",
				label = "Manage equipment",
				row = { description = "Choose equipment for the next expedition", icon = "search", value = "12 items" },
				onActivate = function()
					hits += 1
				end,
			})
			local toggle = harness.Controls.Toggle(w.core, {
				id = "Toggle",
				label = "Camera assistance",
				row = { description = "Keep the route in view", icon = "search" },
				value = value,
			})
			local slider = harness.Controls.Slider(w.core, {
				id = "Volume",
				label = "Music volume",
				row = { description = "Adjust music while playing", icon = "search" },
				value = volume,
				min = 0,
				max = 100,
				step = 10,
			})
			w.present(UI.Screen({
				id = "S",
				children = {
					UI.VStack({
						id = "Rows",
						width = UI.fill(),
						gap = "m",
						children = { action.blueprint, toggle.blueprint, slider.blueprint },
					}),
				},
			}))
			local function activate(path)
				if input == "Touch" or input == "MouseKeyboard" then
					w.adapter.tap(path, { pointer = if input == "Touch" then "touch" else "pointer" })
				else
					w.pres.focus.focusOn(path)
					w.press(if input == "Keyboard" then "Return" else "ButtonA")
				end
			end
			activate("/S/Rows/Toggle")
			t.expect(value:peek()).toBe(true)
			activate("/S/Rows/Action")
			t.expect(hits).toBe(1)
			local paths = {}
			require("../src/present/focus_map").collectFocusables(w.handle.root.node, paths)
			t.expect(#w.pres.focus.focusMap().traversal).toBe(3)
			local path = "/S/Rows/Volume/TrackHost/Track"
			if input == "Touch" or input == "MouseKeyboard" then
				local rect = w.adapter.node(path).rect
				w.adapter.pointerDown(
					path,
					rect.x + rect.w,
					rect.y + rect.h / 2,
					if input == "Touch" then "touch" else "pointer"
				)
				w.adapter.pointerUp(path, rect.x + rect.w, rect.y + rect.h / 2)
				t.expect(volume:peek()).toBe(100)
			else
				w.pres.focus.focusOn(path)
				w.press("ButtonR1")
				t.expect(volume:peek()).toBe(60)
			end
			w.settle(2)
			w.pres.dismiss(w.handle)
			action.dispose()
			toggle.dispose()
			slider.dispose()
		end)
	end
end)
