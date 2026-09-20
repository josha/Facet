--!strict
local t = require("./lib/testkit")
local Compose = require("../src").Compose
local world = require("./lib/native_motion_world")
t.describe("Native ComboBox", function()
	t.it("edits and commits text while keeping rejected input out of selection", function()
		local app, adapter, advance, core = world()
		local selected, text = Compose.cell("alpine"), Compose.cell("")
		local close = app.mount(function()
			local before = core.owner.size()
			local result = app.controls.ComboBox("Choice")({
				value = selected,
				text = text,
				options = { { id = "alpine", label = "Alpine" } },
				acceptCustom = function(value)
					return value == "Coast", "Choose a supported destination."
				end,
			})
			t.expect(core.owner.size()).toBe(before)
			return app.controls.Screen("S")({ result })
		end)
		advance(0.1)
		local editor = "/S/Choice/Row/Editor/Field"
		t.expect(adapter.node(editor) ~= nil).toBe(true)
		adapter.focusText(editor)
		adapter.typeText(editor, "Coast")
		adapter.commitText(editor)
		advance(0.1)
		t.expect(text:peek()).toBe("Coast")
		t.expect(selected:peek()).toBe("Coast")
		text:set("")
		advance(0.1)
		adapter.focusText(editor)
		adapter.typeText(editor, "Invalid")
		adapter.commitText(editor)
		advance(0.1)
		t.expect(selected:peek()).toBe("Coast")
		t.expect(adapter.node("/S/Choice/Validation").props.text).toBe("Choose a supported destination.")
		close()
		advance(0.1)
		t.expect(adapter.rootCount()).toBe(0)
		app.dispose()
	end)
end)
