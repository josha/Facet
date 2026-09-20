--!strict
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local world = require("./lib/harness_world")
local Compose = require("../src/vendor/compose/core")

t.describe("HUD meters", function()
	t.it("segments preserve fractional health and reuse mounted cells", function()
		local w = world.new()
		local value = Compose.cell(0.625)
		local meter = harness.Controls.ProgressView(w.core, { id = "Health", value = value, segments = 4 })
		w.present(harness.UI.Screen({ id = "S", children = { meter.blueprint } }))
		local cell = w.adapter.node("/S/Health/Bar/Segments/Segment3")
		local fill = w.adapter.node("/S/Health/Bar/Segments/Segment3/Fill")
		t.expect(math.abs(fill.rect.w / cell.rect.w - 0.5) < 0.03).toBe(true)
		value:set(0.75)
		w.settle()
		t.expect(w.adapter.node("/S/Health/Bar/Segments/Segment3")).toBe(cell)
		t.expect(w.adapter.node("/S/Health/Bar/Segments/Segment3/Fill").rect.w).toBe(cell.rect.w)
		w.pres.dismiss(w.handle)
		meter.dispose()
	end)

	t.it("damage trails wait, settle, and cancel immediately on healing", function()
		local w = world.new()
		local value = Compose.cell(1)
		local meter = harness.Controls.ProgressView(w.core, {
			value = value,
			trail = { delay = 0.2, duration = 0.3 },
			motionClock = w.pres.motionClock,
		})
		value:set(0.5)
		w.core.reactor:settle()
		w.tick(0.1)
		t.expect(meter.dump().trailFraction).toBe(1)
		for _ = 1, 12 do
			w.tick(0.05)
		end
		t.expect(meter.dump().trailFraction).toBe(0.5)
		value:set(0.25)
		w.core.reactor:settle()
		value:set(0.8)
		w.core.reactor:settle()
		t.expect(meter.dump().trailFraction).toBe(0.8)
		meter.dispose()
	end)

	t.it("large circular meters display an unclipped central value", function()
		local w = world.new()
		local meter = harness.Controls.ProgressView(w.core, {
			id = "Gauge",
			value = 0.75,
			presentation = "circular",
			diameter = 120,
			showValue = true,
		})
		w.present(harness.UI.Screen({ id = "S", children = { meter.blueprint } }))
		local ring = w.adapter.node("/S/Gauge/Gauge/Ring").rect
		local value = w.adapter.node("/S/Gauge/Gauge/Ring/Readout/then/Value").rect
		t.expect(w.adapter.node("/S/Gauge/Gauge/Ring/Readout/then/Value").props.textAlign).toBe("center")
		t.expect(ring.w).toBe(120)
		t.expect(value.x >= ring.x and value.x + value.w <= ring.x + ring.w).toBe(true)
		w.pres.dismiss(w.handle)
		meter.dispose()
	end)

	t.it("rejects incompatible meter options before allocating", function()
		local w = world.new()
		for _, spec in
			{
				{ value = 1, segments = 0 },
				{ value = 1, segments = 2.5 },
				{ value = 1, presentation = "circular", segments = 4 },
				{ value = 1, diameter = 120 },
				{ value = 1, trail = { delay = -1 } },
				{ value = 1, trail = { duration = 0 } },
			}
		do
			t.expect(pcall(function()
				harness.Controls.ProgressView(w.core, spec)
			end)).toBe(false)
		end
	end)
	t.it("reduced motion cancels a pending trail and disposal is safe", function()
		local w = world.new()
		local value = Compose.cell(1)
		local meter = harness.Controls.ProgressView(w.core, { value = value, trail = {} })
		value:set(0.4)
		w.core.reactor:settle()
		w.env:set("reducedMotion", true)
		w.settle(4)
		t.expect(meter.dump().trailFraction).toBe(0.4)
		meter.dispose()
		value:set(0.1)
		w.settle(4)
	end)

	t.it("a gauge preserves long values at large preferred text", function()
		local w = world.new({ env = { preferredTextOffset = 14 } })
		local meter = harness.Controls.ProgressView(w.core, {
			id = "G",
			label = "A long localized resource label",
			value = 1,
			presentation = "circular",
			diameter = 80,
			showValue = true,
			format = function()
				return "10000 / 10000"
			end,
		})
		w.present(harness.UI.Screen({ id = "S", children = { meter.blueprint } }))
		w.settle()
		local v = w.adapter.node("/S/G/Gauge/Below/then/Value")
		t.expect(v.props.textAlign).toBe("center")
		t.expect(v.props.visible ~= false and v.rect.w > 80).toBe(true)
		w.pres.dismiss(w.handle)
		meter.dispose()
	end)
end)
