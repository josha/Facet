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
		--
		-- THE CONTROL IS TWO FILES SINCE 2026-08-18 (the row/cell builder left for
		-- `controls/table_rows.luau` — SOURCE_CAP_LEDGER), and the threshold went
		-- with the gesture that reads it. Both are scanned, and the token call is
		-- required in the PAIR rather than in a named half, so a later move of the
		-- same seam cannot make this check pass by making its subject disappear —
		-- while a re-introduced bare `6` in either file still fails.
		local source = tableControl
		expect(type(source.build)).toBe("function")
		local fs = require("@lune/fs")
		local control = fs.readFile("src/controls/table.luau")
		local rows = fs.readFile("src/controls/table_rows.luau")
		expect(string.find(control, "DRAG_THRESHOLD = 6", 1, true)).toBe(nil)
		expect(string.find(rows, "DRAG_THRESHOLD = 6", 1, true)).toBe(nil)
		local token = 'interactionTokens.promotionPx("pointer")'
		expect(string.find(control, token, 1, true) ~= nil or string.find(rows, token, 1, true) ~= nil).toBe(true)
	end)
end)

-- ===== framework-gaps-phase2 item 41: the responder priority bands ========
--
-- Audit: "`Facet.EXIT_CAP_SECONDS` and `interactionTokens.contextPriority`
-- (two framework constants currently known to consumers only by comment)".
-- `presenter.luau` is still the live authority for the numbers a responder is
-- actually arbitrated at (this round's lane excludes `src/present/*`); this
-- pins that `interactionTokens.contextPriority` publishes THE SAME three
-- numbers presenter.luau's own ADR-0014 section states in its comment, so a
-- consumer reads a value instead of copying a literal out of prose.

describe("interaction tokens: the responder priority bands (framework-gaps-phase2 item 41)", function()
	it("publishes the three ADR-0014 bands presenter.luau's own comment states", function()
		expect(tokens.contextPriority.baseScreen).toBe(1500)
		expect(tokens.contextPriority.engagedBase).toBe(3000)
		expect(tokens.contextPriority.modalStep).toBe(500)
		-- strictly ordered: a base screen never outranks an engaged surface,
		-- and one modal step is a real gap, not a tie
		expect(tokens.contextPriority.baseScreen < tokens.contextPriority.engagedBase).toBe(true)
		expect(tokens.contextPriority.modalStep > 0).toBe(true)
	end)

	it(
		"matches presenter.luau's own literals — a drift here fails loudly instead of shipping quietly wrong",
		function()
			local fs = require("@lune/fs")
			local presenterSource = fs.readFile("src/present/presenter.luau")
			expect(
				string.find(
					presenterSource,
					"BASE_SCREEN_PRIORITY = " .. tostring(tokens.contextPriority.baseScreen),
					1,
					true
				) ~= nil
			).toBe(true)
			expect(
				string.find(
					presenterSource,
					"ENGAGED_BASE_PRIORITY = " .. tostring(tokens.contextPriority.engagedBase),
					1,
					true
				) ~= nil
			).toBe(true)
			expect(
				string.find(presenterSource, "top += " .. tostring(tokens.contextPriority.modalStep), 1, true) ~= nil
			).toBe(true)
		end
	)

	it("is frozen — a consumer cannot mutate the shared band table", function()
		expect(table.isfrozen(tokens.contextPriority)).toBe(true)
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
