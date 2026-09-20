--!strict
local t = require("./lib/testkit")
local world = require("./lib/native_motion_world")
t.describe("Native RadialMenu", function()
	t.it("opens from its launcher, selects a command, and releases its rows", function()
		local app, adapter, advance, core = world()
		local fired = 0
		local close = app.mount(function()
			local before = core.owner.size()
			local result = app.controls.RadialMenu("Actions")({
				items = {
					{
						id = "wave",
						label = "Wave",
						onSelect = function()
							fired += 1
						end,
					},
					{
						id = "point",
						label = "Point",
						onSelect = function()
							fired += 10
						end,
					},
				},
			})
			t.expect(core.owner.size()).toBe(before)
			return app.controls.Screen("S")({ result })
		end)
		advance(0.3)
		local function activateEnding(suffix)
			for _, path in adapter.paths() do
				if path:sub(-#suffix) == suffix then
					adapter.driveActivate(path)
					return
				end
			end
			error("missing " .. suffix .. " in " .. table.concat(adapter.paths(), ","))
		end
		activateEnding("/Launcher")
		advance(0.7)
		local hit
		for _, path in adapter.paths() do
			if string.find(path, "wave", 1, true) and path:sub(-5) == "/Item" then
				hit = path
				break
			end
		end
		assert(hit, "missing wave item in " .. table.concat(adapter.paths(), ","))
		adapter.driveActivate(hit)
		advance(0.7)
		t.expect(fired).toBe(1)
		close()
		advance(0.5)
		t.expect(adapter.rootCount()).toBe(0)
		app.dispose()
	end)
end)
