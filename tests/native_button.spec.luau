--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local Compose = Facet.Compose
local world = require("./lib/native_motion_world")
local function scale(adapter, path)
	local node = adapter.node(path)
	return if node and node.motionScaleInstance then node.motionScaleInstance.scale else 1
end

t.describe("Native button ownership and motion", function()
	t.it("renders plain labels on the button and supports a compact title", function()
		local app, adapter, advance = world()
		local label = Compose.cell("Switch to screen mode")
		local calls = 0
		app.mount(function()
			return app.controls.Button("Mode")({
				label = label,
				compactLabel = "Screen",
				width = { type = "fixed", px = 100 },
				onActivate = function()
					calls += 1
				end,
			})
		end)
		advance(0.1)
		t.expect(adapter.node("/Mode/Label")).toBeNil()
		local node = adapter.node("/Mode")
		t.expect(node ~= nil).toBe(true)
		label:set("Switch to spatial mode")
		advance(0.1)
		t.expect(adapter.node("/Mode")).toBe(node)
		adapter.driveActivate("/Mode")
		t.expect(calls).toBe(1)
		app.dispose()
	end)
	t.it("pops continuously on repeated activation, settles, and honors reduced motion", function()
		local app, adapter, advance, core = world()
		local calls = 0
		local close = app.mount(function()
			local scopes = core.owner.size()
			local node = app.controls.Button("Action")({
				label = "Open",
				pop = true,
				onActivate = function()
					calls += 1
				end,
			})
			t.expect(core.owner.size()).toBe(scopes)
			return node
		end)
		advance(0.05)
		adapter.driveActivate("/Action")
		advance(0.1)
		local before = scale(adapter, "/Action")
		t.expect(before > 1).toBe(true)
		adapter.driveActivate("/Action")
		t.expect(math.abs(scale(adapter, "/Action") - before) < 0.001).toBe(true)
		advance(0.7)
		t.expect(scale(adapter, "/Action")).toBe(1)
		t.expect(calls).toBe(2)
		app.environment:set("reducedMotion", true)
		adapter.driveActivate("/Action")
		advance(0.1)
		t.expect(scale(adapter, "/Action")).toBe(1)
		close()
		advance(0.5)
		t.expect(adapter.rootCount()).toBe(0)
		app.dispose()
	end)
	t.it("owns busy indicators across repeated busy cycles", function()
		local app, adapter, advance = world()
		local busy = Compose.cell(false)
		local calls = 0
		app.mount(function()
			return app.controls.Button("Action")({
				label = "Send",
				busy = busy,
				onActivate = function()
					calls += 1
				end,
			})
		end)
		for _ = 1, 3 do
			busy:set(true)
			advance(0.05)
			t.expect(adapter.node("/Action/Progress/Spinner/Dot1") ~= nil).toBe(true)
			adapter.driveActivate("/Action")
			t.expect(calls).toBe(0)
			busy:set(false)
			advance(0.05)
			t.expect(adapter.node("/Action/Progress/Spinner/Dot1")).toBeNil()
		end
		adapter.driveActivate("/Action")
		t.expect(calls).toBe(1)
		app.dispose()
		t.expect(adapter.rootCount()).toBe(0)
	end)
end)
