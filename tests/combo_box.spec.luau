--!strict
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local world = require("./lib/harness_world")
local Compose = require("../src/vendor/compose/core")
t.describe("ComboBox", function()
	t.it("rejects malformed public field types", function()
		local core = harness.newCore()
		Facet.newEnvironment(core)
		for _, bad in
			{
				{ enabled = "yes" },
				{ enabled = Compose.cell("yes") },
				{ placeholder = false },
				{ value = Compose.cell(42) },
				{ text = Compose.cell(42) },
				{ acceptCustom = true },
				{ onChange = true },
				{ commitOnFocusLost = "yes" },
				{ options = { { id = "a", label = "" } } },
				{ options = { { id = "a", label = "Alpine", enabled = "yes" } } },
			}
		do
			local spec = {
				value = Compose.cell("a"),
				text = Compose.cell("Alpine"),
				options = { { id = "a", label = "Alpine" } },
				acceptCustom = function()
					return true
				end,
			}
			for key, value in bad do
				spec[key] = value
			end
			local ok = pcall(function()
				harness.Controls.ComboBox(core, spec)
			end)
			assert(not ok, "ComboBox accepted malformed " .. tostring(next(bad)))
		end
	end)
	t.it("forwards an explicit environment when the core has multiple surfaces", function()
		local core = harness.newCore()
		local env = Facet.newEnvironment(core)
		Facet.newEnvironment(core)
		local control = harness.Controls.ComboBox(core, {
			value = Compose.cell("a"),
			text = Compose.cell("Alpine"),
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
			local value, text, enabled = Compose.cell("a"), Compose.cell("Alpine"), Compose.cell(true)
			local changes = 0
			local control
			control = harness.Controls.ComboBox(core, {
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
			pres.present(harness.UI.Screen({ id = "S", children = { control.blueprint } }))
			pres.refresh()
			text:set("")
			pres.refresh()
			target.tap("/S/C/Row/Editor/Field")
			target.focusText("/S/C/Row/Editor/Field")
			target.pasteText("/S/C/Row/Editor/Field", "Custom")
			target.commitText("/S/C/Row/Editor/Field")
			t.expect(value:peek()).toBe("a")
			t.expect(changes).toBe(0)
			control.dispose()
			pres.dismiss()
		end)
	end
	--[[ ONE LINE, ONE HEIGHT (found live in the showcase's search row,
		2026-09-20: a 56x41 opener beside a 44px field, its bottom edge three pixels
		short of the field's).

		The field states the theme's own field height; the opener hugged its own
		content and its anchored child was placed at that hugged size, so a parent
		that stretched the control moved a box nobody could see and left the painted
		trigger where it was. What is asserted here is the PAINTED node — the
		trigger's own rect, not its anchor's — because that is the half that stayed
		wrong through the first attempt at this fix. ]]
	t.it("the suggestions opener is exactly as tall as the field beside it", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
		local control = harness.Controls.ComboBox(w.core, {
			id = "C",
			value = Compose.cell("a"),
			text = Compose.cell("Alpine"),
			options = { { id = "a", label = "Alpine" }, { id = "b", label = "Birch" } },
			acceptCustom = function()
				return true
			end,
		})
		w.pres.present(harness.UI.Screen({ id = "S", children = { control.blueprint } }))
		w.pres.refresh()
		-- the field's PLATE: its inner hairline sits inside it, so the
		-- editor within is inset by the band while the painted field is the plate
		local field = w.adapter.node("/S/C/Row/Editor").rect
		local trigger = w.adapter.node("/S/C/Row/Suggestions/Trigger").rect
		t.expect(`field {field.h}, trigger {trigger.h}`).toBe(`field {field.h}, trigger {field.h}`)
		-- ...and they sit on the same line, which is the other half of "one row"
		t.expect(trigger.y).toBe(field.y)
		control.dispose()
		w.pres.dismiss()
	end)
	t.it("custom commits validate separately from supplied suggestions and cancel restores committed text", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
		local core, env = w.core, w.env
		local value = Compose.cell("a")
		local text = Compose.cell("Alpine")
		local control = harness.Controls.ComboBox(core, {
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
		pres.present(harness.UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		text:set("")
		pres.refresh()
		target.tap("/S/C/Row/Editor/Field")
		target.focusText("/S/C/Row/Editor/Field")
		target.pasteText("/S/C/Row/Editor/Field", "X")
		target.commitText("/S/C/Row/Editor/Field")
		t.expect(value:peek()).toBe("a")
		t.expect(control.dump().validationError ~= "").toBe(true)
		text:set("")
		pres.refresh()
		target.tap("/S/C/Row/Editor/Field")
		target.focusText("/S/C/Row/Editor/Field")
		target.pasteText("/S/C/Row/Editor/Field", "Custom")
		target.commitText("/S/C/Row/Editor/Field")
		t.expect(value:peek()).toBe("Custom")
		text:set("")
		pres.refresh()
		target.tap("/S/C/Row/Editor/Field")
		target.focusText("/S/C/Row/Editor/Field")
		target.pasteText("/S/C/Row/Editor/Field", "Uncommitted")
		control.api.cancel()
		t.expect(text:peek()).toBe("Custom")
		control.dispose()
		pres.dismiss()
	end)
end)
