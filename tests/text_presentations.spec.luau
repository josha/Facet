--!strict
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local world = require("./lib/harness_world")
local Compose = require("../src/vendor/compose/core")
t.describe("Text presentations", function()
	for _, callback in { "parse", "format", "validate" } do
		for _, action in { "disable", "dispose" } do
			t.it(`numeric {callback} cannot commit after it {action}s the control`, function()
				local w = world.new()
				local value, number, enabled = Compose.cell("1"), Compose.cell(1), Compose.cell(true)
				local commits, callbacks = 0, 0
				local control
				local spec = {
					id = "N",
					value = value,
					numericValue = number,
					enabled = enabled,
					presentation = "number",
					onCommit = function()
						commits += 1
					end,
				}
				spec[callback] = function(input)
					callbacks += 1
					if action == "disable" then
						enabled:set(false)
					else
						control.dispose()
					end
					return if callback == "parse" then tonumber(input) else tostring(input)
				end
				control = harness.Controls.TextInput(w.core, spec)
				w.present(harness.UI.Screen({ id = "S", children = { control.blueprint } }))
				w.adapter.tap("/S/N/Input/Field")
				w.adapter.focusText("/S/N/Input/Field")
				-- An owner-supplied draft isolates commit validation from live edit validation.
				value:set("2.00")
				w.adapter.commitText("/S/N/Input/Field")
				t.expect(callbacks).toBe(1)
				t.expect(number:peek()).toBe(1)
				t.expect(value:peek()).toBe("2.00")
				t.expect(commits).toBe(0)
				w.pres.dismiss(w.handle)
				if action ~= "dispose" then
					control.dispose()
				end
			end)
		end
	end
	t.it("numeric specs refuse nonfinite bounds and invalid parser or formatter callbacks", function()
		local core = harness.newCore()
		Facet.newEnvironment(core)
		for _, invalid in
			{
				{ min = 0 / 0 },
				{ max = math.huge },
				{ parse = true },
				{ format = "decimal" },
				{ enabled = "no" },
				{ disabled = "no" },
				{ clearButton = "yes" },
				{ numericValue = Compose.cell(math.huge) },
			}
		do
			local spec = { value = Compose.cell("1"), numericValue = Compose.cell(1), presentation = "number" }
			for key, value in invalid do
				spec[key] = value
			end
			local ok = pcall(harness.Controls.TextInput, core, spec)
			t.expect(ok).toBe(false)
		end
	end)
	t.it("numeric drafts accept intermediate strings and validate and format only on commit", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 600, h = 400 } })
		local core, env = w.core, w.env
		local value = Compose.cell("")
		local number = Compose.cell(2)
		local commits = 0
		local control = harness.Controls.TextInput(core, {
			id = "N",
			value = value,
			presentation = "number",
			numericValue = number,
			min = 0,
			max = 10,
			onCommit = function()
				commits += 1
			end,
		})
		local adapter = w.adapter
		local pres = w.pres
		pres.present(harness.UI.Screen({ id = "S", children = { control.blueprint } }))
		pres.refresh()
		adapter.tap("/S/N/Input/Field")
		adapter.pasteText("/S/N/Input/Field", "-")
		t.expect(value:peek()).toBe("-")
		adapter.commitText("/S/N/Input/Field")
		t.expect(number:peek()).toBe(2)
		t.expect(commits).toBe(0)
		-- a lone sign is a draft on the way to a number: it reverts in silence
		t.expect(control.dump().validationError).toBe("")
		t.expect(value:peek()).toBe("2")
		adapter.tap("/S/N/Input/Field")
		adapter.pasteText("/S/N/Input/Field", "1.2.3")
		adapter.commitText("/S/N/Input/Field")
		t.expect(number:peek()).toBe(2)
		t.expect(commits).toBe(0)
		t.expect(control.dump().validationError ~= "").toBe(true)
		value:set("3.50")
		pres.refresh()
		adapter.tap("/S/N/Input/Field")
		adapter.commitText("/S/N/Input/Field")
		t.expect(number:peek()).toBe(3.5)
		t.expect(value:peek()).toBe("3.5")
		t.expect(commits).toBe(1)
	end)
	t.it("search presentation supplies an ordinary clearable native text field", function()
		local core = harness.newCore()
		Facet.newEnvironment(core)
		local control = harness.Controls.TextInput(core, { value = Compose.cell("find"), presentation = "search" })
		t.expect(control.dump().clearVisible).toBe(true)
	end)
end)
