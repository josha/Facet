--!strict
local t = require("./lib/testkit")
local Compose = require("../src").Compose
local world = require("./lib/native_motion_world")
t.describe("Native selection indicator motion", function()
	t.it("slides through Compose, reverses continuously, and settles immediately for reduced motion", function()
		local app, adapter, advance, core = world()
		local selected = Compose.cell("a")
		local baseline = core.owner.size()
		local close = app.mount(function()
			local before = core.owner.size()
			local node = app.controls.Picker("Choice")({
				style = "segmented",
				indicator = "pill",
				selected = selected,
				options = { { value = "a", label = "First" }, { value = "b", label = "Second" } },
			})
			t.expect(core.owner.size()).toBe(before)
			return node
		end)
		advance(0.05)
		local path
		for _, candidate in adapter.paths() do
			if candidate:sub(-10) == "/Layer/Bar" then
				path = candidate
			end
		end
		assert(path, "selection indicator missing")
		local function x()
			return adapter.node(path).rect.x
		end
		local first = x()
		selected:set("b")
		advance(0.05)
		local between = x()
		t.expect(between > first).toBe(true)
		selected:set("a")
		t.expect(math.abs(x() - between) < 0.01).toBe(true)
		advance(0.8)
		t.expect(math.abs(x() - first) < 0.01).toBe(true)
		selected:set("b")
		advance(0.8)
		local second = x()
		t.expect(second > between).toBe(true)
		app.environment:set("reducedMotion", true)
		selected:set("a")
		advance(1 / 60)
		t.expect(math.abs(x() - first) < 0.01).toBe(true)
		selected:set("b")
		advance(1 / 60)
		t.expect(math.abs(x() - second) < 0.01).toBe(true)
		close()
		advance(0.5)
		t.expect(core.owner.size()).toBe(baseline)
		t.expect(adapter.rootCount()).toBe(0)
		app.dispose()
	end)
end)
