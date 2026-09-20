--!strict
local t = require("./lib/testkit")
local Compose = require("../src").Compose
local world = require("./lib/native_motion_world")
t.describe("Native menus", function()
	for _, presentation in { "menu", "sheet" } do
		t.it("owns nested " .. presentation .. " content and releases it with the trigger", function()
			local app, adapter, advance, core = world()
			local UI, checked = app.controls, Compose.cell(false)
			local close = app.mount(function()
				local before = core.owner.size()
				local result = UI.Menu("Actions")({
					label = "Actions",
					presentation = presentation,
					items = {
						{
							id = "options",
							label = "Options",
							children = { { id = "check", label = "Enabled", checked = checked, dismiss = true } },
						},
					},
				})
				t.expect(core.owner.size()).toBe(before)
				return UI.Screen("S")({ result })
			end)
			advance(0.1)
			for _ = 1, 2 do
				adapter.driveActivate("/S/Actions")
				advance(0.3)
				local function activateItem(id)
					for _, path in adapter.paths() do
						if path:sub(-#id - 6) == "/Item:" .. id then
							adapter.driveActivate(path)
							return
						end
					end
					error(
						"missing menu item "
							.. id
							.. " paths="
							.. table.concat(adapter.paths(), ",")
							.. " error="
							.. tostring(core.lastError())
					)
				end
				activateItem("options")
				advance(0.3)
				local previous = checked:peek()
				activateItem("check")
				advance(0.3)
				t.expect(checked:peek()).toBe(not previous)
			end
			adapter.driveActivate("/S/Actions")
			advance(0.3)
			close()
			advance(0.5)
			t.expect(adapter.rootCount()).toBe(0)
			app.dispose()
		end)
	end
	t.it("keeps SplitButton primary and menu actions separate across form changes", function()
		local app, adapter, advance, core = world()
		local fired = 0
		local close = app.mount(function()
			local before = core.owner.size()
			local result = app.controls.SplitButton("Split")({
				label = "Save",
				onActivate = function()
					fired += 1
				end,
				items = {
					{
						id = "copy",
						label = "Save copy",
						onSelect = function()
							fired += 10
						end,
					},
				},
			})
			t.expect(core.owner.size()).toBe(before)
			return result
		end)
		advance(0.1)
		local function activateEnding(suffix)
			for _, path in adapter.paths() do
				if path:sub(-#suffix) == suffix then
					adapter.driveActivate(path)
					return
				end
			end
			error("missing " .. suffix .. " in " .. table.concat(adapter.paths(), ","))
		end
		activateEnding("/Primary")
		t.expect(fired).toBe(1)
		activateEnding("/Menu")
		advance(0.3)
		t.expect(fired).toBe(1)
		activateEnding("/Item:copy")
		advance(0.3)
		t.expect(fired).toBe(11)
		app.environment:set("preferredInput", "Touch")
		advance(0.1)
		activateEnding("/Primary")
		t.expect(fired).toBe(12)
		close()
		advance(0.3)
		t.expect(adapter.rootCount()).toBe(0)
		app.dispose()
	end)
end)
