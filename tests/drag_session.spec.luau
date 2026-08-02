--!strict
-- Pure drag-session model tests (corrections addendum §1): payloads, legal drop
-- targets, enter/leave-exactly-once, predicted result, cancellation, retarget
-- under a moving scroll host, overlapping-target z-order, and inertness after
-- terminal states. Fully deterministic — no engine, no DataModel.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local drag_session = require("../src/input/drag_session")

-- record enter/leave/predict transitions for exactly-once assertions
local function tracker()
	local log = { enter = {}, leave = {}, predict = {} }
	local hooks = {
		onEnter = function(id: string)
			table.insert(log.enter, id)
		end,
		onLeave = function(id: string)
			table.insert(log.leave, id)
		end,
		onPredict = function(id: string?, _payload: any)
			table.insert(log.predict, id == nil and "<none>" or id)
		end,
	}
	return log, hooks
end

-- two side-by-side 100×100 cells: A at x∈[0,100), B at x∈[100,200)
local function twoCellTargets()
	return {
		{ id = "A", rect = { x = 0, y = 0, w = 100, h = 100 } },
		{ id = "B", rect = { x = 100, y = 0, w = 100, h = 100 } },
	}
end

describe("drag_session (corrections §1)", function()
	it("update before any target hit returns nil and starts active with no hover", function()
		local session = drag_session.new({ payload = "card", source = "Deck/1", targets = twoCellTargets() })
		expect(session:update(500, 500)).toBe(nil)
		local s = session:state()
		expect(s.active).toBe(true)
		expect(s.hovered).toBe(nil)
		expect(s.source).toBe("Deck/1")
	end)

	it("fires enter/leave exactly once per hover change", function()
		local log, hooks = tracker()
		local session = drag_session.new({
			payload = "card",
			source = "Deck/1",
			targets = twoCellTargets(),
			onEnter = hooks.onEnter,
			onLeave = hooks.onLeave,
		})
		expect(session:update(10, 10)).toBe("A")
		expect(session:update(20, 20)).toBe("A") -- still inside A: no new transition
		expect(session:update(150, 10)).toBe("B") -- crosses into B
		expect(session:update(500, 500)).toBe(nil) -- leaves everything
		expect(log.enter).toEqual({ "A", "B" })
		expect(log.leave).toEqual({ "A", "B" })
	end)

	it("predicts the result on each hover change, including to no target", function()
		local log, hooks = tracker()
		local session = drag_session.new({
			payload = "card",
			source = "Deck/1",
			targets = twoCellTargets(),
			onPredict = hooks.onPredict,
		})
		session:update(10, 10) -- -> A
		session:update(150, 10) -- -> B
		session:update(999, 999) -- -> none
		expect(log.predict).toEqual({ "A", "B", "<none>" })
	end)

	it("accepts-filter makes a target illegal: no hover, no enter", function()
		local log, hooks = tracker()
		local session = drag_session.new({
			payload = "gem",
			source = "Bag/1",
			targets = {
				{
					id = "GoldSlot",
					rect = { x = 0, y = 0, w = 100, h = 100 },
					accepts = function(p: any)
						return p == "gold"
					end,
				},
			},
			onEnter = hooks.onEnter,
		})
		expect(session:update(50, 50)).toBe(nil) -- "gem" not accepted -> illegal
		expect(#log.enter).toBe(0)
	end)

	it("overlapping targets: the LAST in the array wins (paint z-order)", function()
		local session = drag_session.new({
			payload = "x",
			source = "s",
			targets = {
				{ id = "Under", rect = { x = 0, y = 0, w = 100, h = 100 } },
				{ id = "Over", rect = { x = 0, y = 0, w = 100, h = 100 } },
			},
		})
		expect(session:update(50, 50)).toBe("Over")
	end)

	it("drop over a legal target returns dropped with payload; then inert", function()
		local session = drag_session.new({ payload = "card", source = "Deck/1", targets = twoCellTargets() })
		session:update(150, 10)
		local result = session:drop(150, 10)
		expect(result.kind).toBe("dropped")
		expect((result :: any).targetId).toBe("B")
		expect((result :: any).payload).toBe("card")
		expect(session:state().active).toBe(false)
		-- inert: further calls are no-ops
		expect(session:update(10, 10)).toBe(nil)
		expect(session:drop(10, 10).kind).toBe("rejected")
	end)

	it("drop over no legal target rejects", function()
		local session = drag_session.new({ payload = "card", source = "Deck/1", targets = twoCellTargets() })
		local result = session:drop(999, 999)
		expect(result.kind).toBe("rejected")
		expect(session:state().active).toBe(false)
	end)

	it("cancel mid-hover fires leave for the hovered target, then goes inert", function()
		local log, hooks = tracker()
		local session = drag_session.new({
			payload = "card",
			source = "Deck/1",
			targets = twoCellTargets(),
			onLeave = hooks.onLeave,
		})
		session:update(10, 10) -- hover A
		local result = session:cancel("escape")
		expect(result.kind).toBe("cancelled")
		expect(result.reason).toBe("escape")
		expect(log.leave).toEqual({ "A" })
		expect(session:state().active).toBe(false)
		-- inert cancel is a no-op that fires no further leave
		session:cancel("again")
		expect(log.leave).toEqual({ "A" })
	end)

	it("retarget re-evaluates hover at the last position: moved-away target leaves, new one enters", function()
		local log, hooks = tracker()
		local session = drag_session.new({
			payload = "card",
			source = "Deck/1",
			targets = twoCellTargets(),
			onEnter = hooks.onEnter,
			onLeave = hooks.onLeave,
		})
		expect(session:update(50, 50)).toBe("A") -- hovering A
		-- the scroll host moves: A slides away from the pointer, C slides under it
		session:retarget({
			{ id = "A", rect = { x = -200, y = 0, w = 100, h = 100 } },
			{ id = "C", rect = { x = 0, y = 0, w = 100, h = 100 } },
		})
		expect(session:state().hovered).toBe("C")
		expect(log.leave).toEqual({ "A" })
		expect(log.enter).toEqual({ "A", "C" })
	end)

	it("retarget before any position is a no-op (no phantom hover)", function()
		local log, hooks = tracker()
		local session = drag_session.new({
			payload = "card",
			source = "Deck/1",
			targets = twoCellTargets(),
			onEnter = hooks.onEnter,
		})
		session:retarget({ { id = "Z", rect = { x = 0, y = 0, w = 100, h = 100 } } })
		expect(session:state().hovered).toBe(nil)
		expect(#log.enter).toBe(0)
	end)

	it("retarget after a terminal state stays inert", function()
		local session = drag_session.new({ payload = "card", source = "Deck/1", targets = twoCellTargets() })
		session:drop(10, 10)
		session:retarget({ { id = "Z", rect = { x = 0, y = 0, w = 100, h = 100 } } })
		expect(session:state().hovered).toBe(nil)
		expect(session:state().active).toBe(false)
	end)
end)
