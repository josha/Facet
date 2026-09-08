--!strict
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local world = require("./lib/world")
t.describe("ComboBox", function()
	t.it("rejects malformed public field types", function()
		local core = Facet.newCore()
		Facet.newEnvironment(core)
		for _, bad in
			{
				{ enabled = "yes" },
				{ enabled = core:signal("yes") },
				{ placeholder = false },
				{ value = core:signal(42) },
				{ text = core:signal(42) },
				{ acceptCustom = true },
				{ onChange = true },
				{ commitOnFocusLost = "yes" },
				{ options = { { id = "a", label = "" } } },
				{ options = { { id = "a", label = "Alpine", enabled = "yes" } } },
			}
		do
			local spec = {
				value = core:signal("a"),
				text = core:signal("Alpine"),
				options = { { id = "a", label = "Alpine" } },
				acceptCustom = function()
					return true
				end,
			}
			for key, value in bad do
				spec[key] = value
			end
			local ok = pcall(function()
				Facet.Controls.ComboBox(core, spec)
			end)
			assert(not ok, "ComboBox accepted malformed " .. tostring(next(bad)))
		end
	end)
	t.it("forwards an explicit environment when the core has multiple surfaces", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		Facet.newEnvironment(core)
		local control = Facet.Controls.ComboBox(core, {
			value = core:signal("a"),
			text = core:signal("Alpine"),
			options = { { id = "a", label = "Alpine" } },
			env = env,
			acceptCustom = function()
				return true
			end,
		})
		t.expect(control.dump().value).toBe("a")
		control.dispose()
	end)
	for _, action in { "disable", "dispose" } do
		t.it(`custom validation cannot commit after it {action}s the control`, function()
			local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
			local core, env = w.core, w.env
			local value, text, enabled = core:signal("a"), core:signal("Alpine"), core:signal(true)
			local changes = 0
			local control
			control = Facet.Controls.ComboBox(core, {
				id = "C",
				value = value,
				text = text,
				enabled = enabled,
				options = { { id = "a", label = "Alpine" } },
				acceptCustom = function()
					if action == "disable" then
						enabled:set(false)
					else
						control.dispose()
					end
					return true
				end,
				onChange = function()
					changes += 1
				end,
			})
			local target = w.adapter
			local pres = w.pres
			pres.present(Facet.UI.Screen({ id = "S", children = { control.blueprint } }))
			pres.refresh()
			text:set("")
			pres.refresh()
			target.tap("/S/C/Editor/Field")
			target.focusText("/S/C/Editor/Field")
			target.pasteText("/S/C/Editor/Field", "Custom")
			target.commitText("/S/C/Editor/Field")
			t.expect(value:get()).toBe("a")
			t.expect(changes).toBe(0)
			control.dispose()
			pres.dismiss()
		end)
	end
	t.it("custom commits validate separately from supplied suggestions and cancel restores committed text", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
		local core, env = w.core, w.env
		local value = core:signal("a")
		local text = core:signal("Alpine")
		local control = Facet.Controls.ComboBox(core, {
			id = "C",
			value = value,
			text = text,
			options = { { id = "a", label = "Alpine" } },
			acceptCustom = function(s)
				return #s >= 3, "Use at least three characters."
			end,
		})
		local target = w.adapter
		local pres = w.pres
		pres.present(Facet.UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		text:set("")
		pres.refresh()
		target.tap("/S/C/Editor/Field")
		target.focusText("/S/C/Editor/Field")
		target.pasteText("/S/C/Editor/Field", "X")
		target.commitText("/S/C/Editor/Field")
		t.expect(value:get()).toBe("a")
		t.expect(control.dump().validationError ~= "").toBe(true)
		text:set("")
		pres.refresh()
		target.tap("/S/C/Editor/Field")
		target.focusText("/S/C/Editor/Field")
		target.pasteText("/S/C/Editor/Field", "Custom")
		target.commitText("/S/C/Editor/Field")
		t.expect(value:get()).toBe("Custom")
		text:set("")
		pres.refresh()
		target.tap("/S/C/Editor/Field")
		target.focusText("/S/C/Editor/Field")
		target.pasteText("/S/C/Editor/Field", "Uncommitted")
		control.api.cancel()
		t.expect(text:get()).toBe("Custom")
		control.dispose()
		pres.dismiss()
	end)
end)
