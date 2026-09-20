--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local Compose = Facet.Compose

local world = require("./lib/native_motion_world")

t.describe("Native progress motion", function()
	t.it("animates on Compose frames without a Core scope and STEPS for reduced motion", function()
		local app, adapter, advance, core = world()
		local close = app.mount(function()
			local before = core.owner.size()
			local node = app.controls.ProgressView("Loading")({ presentation = "spinner" })
			t.expect(core.owner.size()).toBe(before)
			return node
		end)
		advance(0.05)
		local function blend()
			return adapter.node("/Loading/Spinner/Dot1").props.tint.blend
		end
		local before = blend()
		advance(0.25)
		t.expect(blend() ~= before).toBe(true)
		--[[ REDUCED MOTION QUANTIZES THE PULSE; IT DOES NOT STOP IT. A frozen
			spinner and a hung process look identical, so the one piece of motion
			that CARRIES information keeps stepping — four times a second instead of
			sixty (`src/controls/progress_view.luau`'s REDUCED_STEP). This case used
			to assert the freeze, with `advance(0.3)` deliberately crossing the tick. ]]
		app.environment:set("reducedMotion", true)
		advance(0.02)
		local stepped = blend()
		-- inside the tick: no write
		advance(0.02)
		t.expect(blend()).toBe(stepped)
		-- across it: moved
		advance(0.3)
		t.expect(blend() ~= stepped).toBe(true)
		close()
		advance(0.1)
		t.expect(adapter.rootCount()).toBe(0)
		app.dispose()
	end)

	t.it("reads Compose values and delays damage trails while healing cancels motion", function()
		local app, adapter, advance = world()
		local value = Compose.cell(100)
		app.mount(function()
			return app.controls.ProgressView("Health")({
				value = value,
				min = 0,
				max = 100,
				trail = { delay = 0.2, duration = 0.4 },
			})
		end)
		local function fraction(name)
			return adapter.node("/Health/Bar/Segments/Segment1/" .. name).rect.w
				/ adapter.node("/Health/Bar/Segments/Segment1").rect.w
		end
		advance(0.05)
		t.expect(fraction("Fill")).toBe(1)
		value:set(40)
		advance(0.1)
		t.expect(math.abs(fraction("Fill") - 0.4) < 0.005).toBe(true)
		t.expect(fraction("Trail")).toBe(1)
		advance(0.3)
		t.expect(fraction("Trail") > 0.4 and fraction("Trail") < 1).toBe(true)
		value:set(90)
		advance(0.05)
		t.expect(math.abs(fraction("Trail") - 0.9) < 0.005).toBe(true)
		value:set(10)
		app.environment:set("reducedMotion", true)
		advance(0.05)
		t.expect(math.abs(fraction("Trail") - 0.1) < 0.005).toBe(true)
		app.dispose()
		t.expect(adapter.rootCount()).toBe(0)
	end)
end)
