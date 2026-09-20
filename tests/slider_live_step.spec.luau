--!strict
-- `Slider.step` takes a READABLE. The grid a slider snaps to is a setting like
-- any other — a "turn step" picker beside it — so it is resolved at every
-- quantization rather than once at construction.
local t = require("./lib/testkit")
local Facet = require("../src")
local Compose = Facet.Compose

t.describe("Slider step as a readable", function()
	t.it("quantizes and key-steps on the grid in force right now", function()
		local app, adapter, settle = require("./lib/native_world")({ x = 0, y = 0, w = 640, h = 480 })
		local angle = Compose.cell(0)
		local step = Compose.cell(15)
		local record
		app.mount(function()
			return app.controls.Screen("S")({
				app.controls.Slider("Angle")({
					value = angle,
					min = -180,
					max = 180,
					step = step,
					ref = function(r)
						record = r
					end,
				}),
			})
		end)
		settle(3)
		local model = assert(record).api.model
		t.expect(assert(record).dump().step).toBe(15)
		t.expect(model.stepped(0, 1)).toBe(15)
		t.expect(model.quantize(22)).toBe(15)
		-- a new grid takes effect on the next step, with no remount
		step:set(90)
		settle(1)
		t.expect(assert(record).dump().step).toBe(90)
		t.expect(model.stepped(0, 1)).toBe(90)
		t.expect(model.quantize(22)).toBe(0)
		step:set(45)
		settle(1)
		t.expect(model.stepped(0, 1)).toBe(45)
		t.expect(model.quantize(22)).toBe(0)
		t.expect(model.quantize(40)).toBe(45)
		t.expect(adapter.node("/S/Angle") ~= nil).toBe(true)
		app.dispose()
	end)

	t.it("refuses a live step that goes non-positive, where it is read", function()
		local model = require("../src/controls/value_model")
		local step = Compose.cell(10)
		local m = model.new({ min = 0, max = 100, step = step })
		t.expect(m.quantize(13)).toBe(10)
		t.expect(m.currentStep()).toBe(10)
		step:set(0)
		t.expect((pcall(m.quantize, 13))).toBe(false)
		step:set(nil)
		-- nil is CONTINUOUS, not an error: the caller withdrew the grid
		t.expect(m.quantize(13)).toBe(13)
		t.expect(m.currentStep()).toBe(nil)
	end)

	t.it("still refuses a bad literal at construction", function()
		local model = require("../src/controls/value_model")
		t.expect((pcall(model.new, { min = 0, max = 10, step = 0 }))).toBe(false)
		t.expect((pcall(model.new, { min = 0, max = 10, step = -1 }))).toBe(false)
		t.expect((pcall(model.new, { min = 0, max = 10, step = 2 }))).toBe(true)
	end)
end)
