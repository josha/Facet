--!strict
local t = require("./lib/testkit")
local Compose = require("../src").Compose
local world = require("./lib/native_motion_world")
t.describe("Native Sheet", function()
	t.it("reopens fresh content, changes detents, and closes with its owner", function()
		local app, adapter, advance, core = world()
		local UI, shown, detent = app.controls, Compose.cell(false), Compose.cell("medium")
		local live, visits = 0, 0
		local close = app.mount(function()
			local before = core.owner.size()
			local result = UI.Sheet("Details")({
				title = "Details",
				isPresented = shown,
				detent = detent,
				content = function()
					live += 1
					visits += 1
					Compose.cleanup(function()
						live -= 1
					end)
					return UI.Button("Body")({
						label = "Done",
						onActivate = function()
							shown:set(false)
						end,
					})
				end,
			})
			t.expect(core.owner.size()).toBe(before)
			return result
		end)
		advance(0.1)
		t.expect(live).toBe(0)
		for i = 1, 2 do
			shown:set(true)
			advance(0.5)
			t.expect(live).toBe(1)
			t.expect(visits).toBe(i)
			local panel = adapter.node("/Details/Layer/Panel")
			t.expect(panel ~= nil).toBe(true)
			adapter.driveActivate("/Details/Layer/Panel/Room/Column/Header/Size")
			advance(0.5)
			t.expect(detent:peek()).toBe(if i == 1 then "large" else "medium")
			adapter.driveActivate("/Details/Layer/Panel/Room/Column/Header/Close")
			advance(0.5)
			t.expect(shown:peek()).toBe(false)
			t.expect(live).toBe(0)
		end
		shown:set(true)
		advance(0.5)
		close()
		advance(0.5)
		t.expect(live).toBe(0)
		t.expect(adapter.rootCount()).toBe(0)
		app.dispose()
	end)
	t.it("retargets Compose height motion and settles immediately for reduced motion", function()
		local app, adapter, advance = world()
		local shown, detent = Compose.cell(false), Compose.cell("medium")
		local close = app.mount(function()
			return app.controls.Sheet("Motion")({
				title = "Details",
				isPresented = shown,
				detent = detent,
				content = function()
					return app.controls.Text({ text = "Details" })
				end,
			})
		end)
		shown:set(true)
		advance(0.6)
		local function height()
			return adapter.node("/Motion/Layer/Panel").rect.h
		end
		local medium = height()
		detent:set("large")
		advance(1 / 60)
		t.expect(height() > medium and height() < 480).toBe(true)
		local inFlight = height()
		detent:set("medium")
		t.expect(height()).toBe(inFlight)
		app.environment:set("reducedMotion", true)
		advance(1 / 60)
		t.expect(math.abs(height() - medium) < 0.1).toBe(true)
		close()
		advance(0.6)
		t.expect(adapter.rootCount()).toBe(0)
		app.dispose()
	end)
end)
