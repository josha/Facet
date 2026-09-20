--!strict
local t = require("./lib/testkit")
local Compose = require("../src").Compose
local world = require("./lib/native_motion_world")
t.describe("Native Callout", function()
	t.it("uses the shared queue and retires when its feature is used", function()
		local app, adapter, advance, core = world()
		local UI, shown, used = app.controls, Compose.cell(false), Compose.cell(false)
		local live, retired = 0, 0
		local close = app.mount(function()
			local before = core.owner.size()
			local result = UI.Callout("Tip")({
				anchor = UI.Button("Anchor")({
					label = "Add",
					onActivate = function()
						used:set(true)
					end,
				}),
				isPresented = shown,
				featureUsed = used,
				onRetire = function()
					retired += 1
				end,
				content = function()
					live += 1
					Compose.cleanup(function()
						live -= 1
					end)
					return UI.Text({ text = "Add your first item" })
				end,
			})
			t.expect(core.owner.size()).toBe(before)
			return UI.Screen("S")({ result })
		end)
		advance(0.1)
		shown:set(true)
		advance(0.5)
		t.expect(live).toBe(1)
		t.expect(adapter.rootCount() > 1).toBe(true)
		adapter.driveActivate("/S/Anchor")
		advance(0.5)
		t.expect(retired).toBe(1)
		t.expect(live).toBe(0)
		shown:set(false)
		shown:set(true)
		advance(0.2)
		t.expect(live).toBe(0)
		close()
		advance(0.2)
		t.expect(adapter.rootCount()).toBe(0)
		app.dispose()
	end)
end)
