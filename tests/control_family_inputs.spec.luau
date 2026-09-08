--!strict
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local world = require("./lib/world")
t.describe("Control family inputs", function()
	t.it(
		"toggle button combo and split controls share pointer touch keyboard and gamepad activation and disable guards",
		function()
			for _, kind in { "Toggle", "Button", "ComboBox", "SplitButton" } do
				for _, input in { "pointer", "touch", "keyboard", "gamepad" } do
					local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
					local enabled = w.core:signal(true)
					local value = w.core:signal(false)
					local calls = 0
					local function onActivate()
						calls += 1
					end
					local spec = { id = "C", enabled = enabled, label = "Test action", onActivate = onActivate }
					local path = "/S/C"
					if kind == "Toggle" then
						spec = {
							id = "C",
							enabled = enabled,
							label = "Test checkbox",
							value = value,
							mixed = w.core:signal(true),
							presentation = "checkbox",
							onChange = onActivate,
						}
					elseif kind == "SplitButton" then
						spec.items = { { id = "option", label = "Choose this", onSelect = function() end } }
						path ..= "/Primary"
					elseif kind == "ComboBox" then
						spec = {
							id = "C",
							enabled = enabled,
							value = w.core:signal("a"),
							text = w.core:signal("A"),
							options = { { id = "a", label = "A" } },
							acceptCustom = function()
								return true
							end,
						}
						path ..= "/Editor/Field"
					end
					local c = Facet.Controls[kind](w.core, spec)
					w.present(Facet.UI.Screen({ id = "S", children = { c.blueprint } }))
					w.pres.refresh()
					w.tick(0)
					local function activate(target)
						if input == "pointer" or input == "touch" then
							w.adapter.tap(target, { source = "pointer", pointer = input })
						else
							w.pres.focus.focusOn(target)
							w.press(if input == "keyboard" then "Return" else "ButtonA")
						end
						w.pres.refresh()
					end
					activate(path)
					if kind == "ComboBox" then
						t.expect(c.dump().editing).toBe(true)
					else
						t.expect(calls).toBe(1)
					end
					if kind == "SplitButton" then
						activate("/S/C/Menu")
						t.expect(c.dump().menu.open).toBe(true)
						t.expect(calls).toBe(1)
					end
					enabled:set(false)
					w.pres.refresh()
					w.tick(0)
					activate(path)
					if kind == "ComboBox" then
						t.expect(c.dump().editing).toBe(false)
					else
						t.expect(calls).toBe(1)
					end
					c.dispose()
					w.pres.dismiss()
				end
			end
		end
	)
end)
