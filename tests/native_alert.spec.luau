--!strict
local t = require("./lib/testkit")
local Compose = require("../src").Compose
local world = require("./lib/native_motion_world")
t.describe("Native Alert", function()
	t.it("owns editable content through repeated presentation and default action dismissal", function()
		local app, adapter, advance, core = world()
		local UI, shown, text = app.controls, Compose.cell(false), Compose.cell("Name")
		local live, accepted = 0, 0
		local close = app.mount(function()
			local before = core.owner.size()
			local result = UI.Alert("Edit")({
				title = "Edit name",
				isPresented = shown,
				content = function()
					live += 1
					Compose.cleanup(function()
						live -= 1
					end)
					return UI.TextInput("Name")({ value = text })
				end,
				actions = {
					{
						id = "Save",
						label = "Save",
						shortcut = "defaultAction",
						onActivate = function()
							accepted += 1
						end,
					},
					{ id = "Cancel", label = "Cancel", role = "cancel" },
				},
			})
			t.expect(core.owner.size()).toBe(before)
			return result
		end)
		advance(0.1)
		for _ = 1, 2 do
			shown:set(true)
			advance(0.5)
			t.expect(live).toBe(1)
			local found = false
			for _, path in adapter.paths() do
				if path:sub(-5) == "/Save" then
					adapter.driveActivate(path)
					found = true
					break
				end
			end
			t.expect(found).toBe(true)
			advance(0.5)
			t.expect(shown:peek()).toBe(false)
			t.expect(live).toBe(0)
		end
		t.expect(accepted).toBe(2)
		close()
		advance(0.5)
		t.expect(adapter.rootCount()).toBe(0)
		app.dispose()
	end)
end)
