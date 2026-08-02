--!strict
-- Shared interaction tokens + the release-velocity tracker (ADR-0022 Decision 5,
-- rows SF-D3 / SF-D2). Both are pure: the tokens read no environment and the
-- tracker reads no clock, so every case below is exact arithmetic rather than a
-- tolerance.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local tokens = require("../src/input/interaction_tokens")
local drag_velocity = require("../src/input/drag_velocity")
local tableControl = require("../src/controls/table")

describe("interaction tokens: promotion thresholds (SF-D3)", function()
	it("ships the ratified per-class values, inside their published ranges", function()
		expect(tokens.dragPromotionPx.pointer).toBe(6)
		expect(tokens.dragPromotionPx.touch).toBe(14)
		local ranges = tokens.dragPromotionRangePx
		expect(tokens.dragPromotionPx.pointer >= ranges.pointer.min).toBe(true)
		expect(tokens.dragPromotionPx.pointer <= ranges.pointer.max).toBe(true)
		expect(tokens.dragPromotionPx.touch >= ranges.touch.min).toBe(true)
		expect(tokens.dragPromotionPx.touch <= ranges.touch.max).toBe(true)
	end)

	it("non-pointer classes carry ZERO: an armed drag has no travel to measure", function()
		expect(tokens.dragPromotionPx.keyboard).toBe(0)
		expect(tokens.dragPromotionPx.gamepad).toBe(0)
		-- ...and a zero gate promotes immediately rather than never
		expect(tokens.promoted(0, 0, nil, { pointer = 0 })).toBe(true)
	end)

	it("maps engine pointer types to classes, and an unknown type is a pointer", function()
		expect(tokens.classForPointerType("mouse")).toBe("pointer")
		expect(tokens.classForPointerType("pen")).toBe("pointer")
		expect(tokens.classForPointerType("touch")).toBe("touch")
		expect(tokens.classForPointerType(nil)).toBe("pointer")
		expect(tokens.classForPointerType("hologram")).toBe("pointer")
		-- an unknown CLASS falls back to the pointer gate, never to zero: a gate
		-- that is too small still asks the player to move; a zero gate eats taps
		expect(tokens.promotionPx("hologram")).toBe(6)
	end)

	it("promotion is a MAGNITUDE test, not two axis tests", function()
		-- 5,5 is 7.07 px of travel: a drag on a mouse, though neither axis is 6
		expect(tokens.promoted(5, 5, "mouse")).toBe(true)
		expect(tokens.promoted(4, 4, "mouse")).toBe(false) -- 5.66 px
		expect(tokens.promoted(6, 0, "mouse")).toBe(true) -- exactly at the gate
		expect(tokens.promoted(-6, 0, "mouse")).toBe(true) -- direction-blind
	end)

	it("the same travel is a drag on a mouse and still a tap on a finger", function()
		expect(tokens.promoted(0, 10, "mouse")).toBe(true)
		expect(tokens.promoted(0, 10, "touch")).toBe(false)
		expect(tokens.promoted(0, 14, "touch")).toBe(true)
	end)

	it("per-call overrides win, and absent keys still fall through to the token", function()
		expect(tokens.promotionPx("pointer", { pointer = 8 })).toBe(8)
		expect(tokens.promotionPx("touch", { pointer = 8 })).toBe(14)
		expect(tokens.promoted(0, 7, "mouse", { pointer = 8 })).toBe(false)
	end)

	it("Table's reorder threshold is now the TOKEN, not a private copy", function()
		-- the migration's whole point: one grep finds every consumer. The control
		-- source may not carry a bare numeric threshold any more.
		local source = tableControl
		expect(type(source.build)).toBe("function")
		local fs = require("@lune/fs")
		local text = fs.readFile("src/controls/table.luau")
		expect(string.find(text, "DRAG_THRESHOLD = 6", 1, true)).toBe(nil)
		expect(string.find(text, 'interactionTokens.promotionPx("pointer")', 1, true) ~= nil).toBe(true)
	end)
end)

describe("drag velocity: the rolling release window (SF-D2)", function()
	it("answers zero until it has two samples", function()
		local v = drag_velocity.new()
		local vx, vy = v:velocity()
		expect(vx).toBe(0)
		expect(vy).toBe(0)
		v:push(0, 0, 0)
		vx, vy = v:velocity()
		expect(vx).toBe(0)
		expect(vy).toBe(0)
	end)

	it("estimates first-vs-last across the retained window", function()
		local v = drag_velocity.new()
		v:push(0, 0, 0)
		v:push(10, 5, 0.05)
		v:push(20, 10, 0.1)
		local vx, vy = v:velocity()
		expect(vx).toBe(200) -- 20 px over 0.1 s
		expect(vy).toBe(100)
	end)

	it("drops samples older than the window: a flick after a pause reads as a FLICK", function()
		-- a 1 s window on integer timestamps, so the retention rule is asserted
		-- exactly rather than against float noise at 0.1 s boundaries
		local v = drag_velocity.new({ windowS = 1 })
		-- a long slow crawl...
		v:push(0, 0, 0)
		v:push(1, 0, 1)
		v:push(2, 0, 2)
		-- ...then a burst inside the last second
		v:push(60, 0, 2.5)
		v:push(120, 0, 3)
		local vx = v:velocity()
		-- only the samples inside the window survive (t >= 2)
		expect(v:sampleCount()).toBe(3)
		expect(vx).toBe(118) -- (120 - 2) / 1, not the 40 px/s whole-gesture average
	end)

	it("keeps TWO samples even when both are stale: a paused gesture answers a real zero", function()
		local v = drag_velocity.new()
		v:push(0, 0, 0)
		v:push(0, 0, 5) -- five seconds later, same place
		expect(v:sampleCount()).toBe(2)
		local vx, vy = v:velocity()
		expect(vx).toBe(0)
		expect(vy).toBe(0)
	end)

	it("a non-advancing clock is zero, never a division by zero", function()
		local v = drag_velocity.new()
		v:push(0, 0, 3)
		v:push(50, 50, 3)
		local vx, vy = v:velocity()
		expect(vx).toBe(0)
		expect(vy).toBe(0)
	end)

	it("refuses non-finite samples rather than poisoning the estimate", function()
		local v = drag_velocity.new()
		v:push(0, 0, 0)
		v:push(0 / 0, 5, 0.05)
		v:push(math.huge, 5, 0.05)
		expect(v:sampleCount()).toBe(1)
	end)

	it("reset clears the buffer (the read order contract: velocity THEN reset)", function()
		local v = drag_velocity.new()
		v:push(0, 0, 0)
		v:push(30, 0, 0.1)
		expect((v:velocity())).toBe(300)
		v:reset()
		expect(v:sampleCount()).toBe(0)
		expect((v:velocity())).toBe(0)
	end)

	it("honours a custom window and reports it", function()
		local v = drag_velocity.new({ windowS = 0.5 })
		expect(v:windowSeconds()).toBe(0.5)
		v:push(0, 0, 0)
		v:push(10, 0, 0.2)
		v:push(20, 0, 0.4)
		expect(v:sampleCount()).toBe(3) -- all inside a 0.5 s window
		expect((v:velocity())).toBe(50)
	end)
end)
