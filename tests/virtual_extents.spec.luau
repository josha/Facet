--!strict
--[[
	THE RUNNING-OFFSET INDEX — `src/virtual_extents.luau`.

	`newVirtualList` windowed by `index × pitch` for its whole life, which is O(1)
	and exact ONLY because the pitch is one number. Variable item extents need the
	other arithmetic: a PREFIX SUM of every preceding item's extent, searched
	rather than divided.

	This spec pins that arithmetic on its own, outside the control, because it is
	the load-bearing half of the feature and it is pure: given the extents and the
	gap, every question a virtualized list asks — where is slot i, which slots does
	this viewport touch, which insertion boundary is this pointer nearest — has one
	right answer that no engine, theme or text preference can change.

	THE INVARIANT THAT MATTERS MOST is `agrees with uniform when every extent is
	equal`: the variable index must CONTAIN the uniform one as its special case,
	not merely resemble it. That is the check that would catch a prefix sum that is
	off by a gap, a boundary that is off by half of one, or a search that lands on
	the wrong side of a slot edge.

	THE SECOND INVARIANT IS BOUNDEDNESS. Virtualization exists to not touch the
	items you cannot see. A `window()` that walked the list would be a correct
	answer that destroys the point, so the search is asserted to be logarithmic by
	COUNTING the extents it reads — an instrumented index, not a timing.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local virtual_extents = require("../src/virtual_extents")

local function evenExtents(n: number, px: number): { number }
	local out = {}
	for _ = 1, n do
		table.insert(out, px)
	end
	return out
end

describe("virtual_extents: the uniform index is today's arithmetic, unchanged", function()
	it("content extent carries no trailing gutter", function()
		-- N slots span N*extent + (N-1)*gap — exactly a UIListLayout's padding
		expect(virtual_extents.uniform(4, 56, 0).content).toBe(224)
		expect(virtual_extents.uniform(4, 56, 8).content).toBe(248)
		expect(virtual_extents.uniform(1, 56, 8).content).toBe(56)
		expect(virtual_extents.uniform(0, 56, 8).content).toBe(0)
	end)

	it("offsetOf is (index-1)*pitch and extentOf is the one number", function()
		local ix = virtual_extents.uniform(5, 56, 8)
		expect(ix.offsetOf(1)).toBe(0)
		expect(ix.offsetOf(2)).toBe(64)
		expect(ix.offsetOf(5)).toBe(256)
		expect(ix.extentOf(3)).toBe(56)
	end)

	it("window reproduces floor/ceil + overscan, the pre-feature formula", function()
		-- 56px rows, 498px viewport, overscan 2, scrolled to the top
		local ix = virtual_extents.uniform(100, 56, 0)
		local first, last = ix.window(0, 498, 2)
		expect(first).toBe(1)
		expect(last).toBe(11)
		-- ...and one whole row down
		first, last = ix.window(56, 498, 2)
		expect(first).toBe(1)
		expect(last).toBe(12)
	end)

	it("window clamps to the data at both ends", function()
		local ix = virtual_extents.uniform(6, 56, 0)
		local first, last = ix.window(0, 498, 2)
		expect(first).toBe(1)
		expect(last).toBe(6)
		local ef, el = virtual_extents.uniform(0, 56, 0).window(0, 498, 2)
		expect(ef).toBe(1)
		expect(el).toBe(0)
	end)
end)

describe("virtual_extents: the variable index is a prefix sum", function()
	it("offsetOf sums every preceding extent plus one gap each", function()
		local ix = virtual_extents.variable({ 40, 80, 20, 100 }, 10)
		expect(ix.offsetOf(1)).toBe(0)
		expect(ix.offsetOf(2)).toBe(50) -- 40 + 10
		expect(ix.offsetOf(3)).toBe(140) -- 40+10 + 80+10
		expect(ix.offsetOf(4)).toBe(170) -- + 20+10
		expect(ix.content).toBe(270) -- 240 of item + 3 gaps
	end)

	it("extentOf answers each item's own size", function()
		local ix = virtual_extents.variable({ 40, 80, 20, 100 }, 10)
		expect(ix.extentOf(1)).toBe(40)
		expect(ix.extentOf(2)).toBe(80)
		expect(ix.extentOf(4)).toBe(100)
	end)

	it("window covers exactly the slots the viewport touches, plus overscan", function()
		-- offsets: 1@0..40, 2@50..130, 3@140..160, 4@170..270
		local ix = virtual_extents.variable({ 40, 80, 20, 100 }, 10)
		-- a viewport of 60 at the very top touches slots 1 and 2
		local first, last = ix.window(0, 60, 0)
		expect(first).toBe(1)
		expect(last).toBe(2)
		-- ...scrolled to 140 it starts inside slot 3
		first, last = ix.window(140, 60, 0)
		expect(first).toBe(3)
		expect(last).toBe(4)
		-- overscan reaches one either side
		first, last = ix.window(140, 60, 1)
		expect(first).toBe(2)
		expect(last).toBe(4)
	end)

	it("a viewport inside ONE tall item windows only that item", function()
		-- the accessibility shape: one row of 249px in a 320x640 phone's list
		local ix = virtual_extents.variable({ 84, 249, 84, 84 }, 0)
		local first, last = ix.window(100, 120, 0)
		expect(first).toBe(2)
		expect(last).toBe(2)
	end)

	it("degenerate inputs answer rather than throw", function()
		local empty = virtual_extents.variable({}, 8)
		expect(empty.content).toBe(0)
		expect(empty.count).toBe(0)
		local first, last = empty.window(0, 498, 2)
		expect(first).toBe(1)
		expect(last).toBe(0)
		local one = virtual_extents.variable({ 84 }, 8)
		expect(one.content).toBe(84)
		expect(one.offsetOf(1)).toBe(0)
		-- a zero viewport still names the slot the offset sits in
		first, last = one.window(0, 0, 0)
		expect(first).toBe(1)
		expect(last).toBe(1)
	end)

	it("an offset past the content clamps to the last slot", function()
		local ix = virtual_extents.variable({ 40, 80, 20 }, 0)
		local first, last = ix.window(9999, 100, 0)
		expect(first).toBe(3)
		expect(last).toBe(3)
	end)
end)

describe("virtual_extents: the variable index CONTAINS the uniform one", function()
	it("every question agrees when every extent is equal", function()
		-- THE invariant: the general mechanism must reproduce the special case it
		-- replaces, for every question, at every scroll offset — not resemble it.
		for _, gap in { 0, 8 } do
			local uniform = virtual_extents.uniform(40, 56, gap)
			local variable = virtual_extents.variable(evenExtents(40, 56), gap)
			expect(variable.content).toBe(uniform.content)
			expect(variable.count).toBe(uniform.count)
			for i = 1, 40 do
				expect(variable.offsetOf(i)).toBe(uniform.offsetOf(i))
				expect(variable.extentOf(i)).toBe(uniform.extentOf(i))
			end
			for slot = 0, 40 do
				expect(variable.boundaryOffset(slot)).toBe(uniform.boundaryOffset(slot))
			end
			for offset = 0, uniform.content, 7 do
				expect(variable.slotAt(offset)).toBe(uniform.slotAt(offset))
			end
			-- ...and the WINDOW agrees at every slot-aligned offset, which is where
			-- the two rules are the same rule (see the divergence case below)
			for slot = 0, 39 do
				local uf, ul = uniform.window(uniform.offsetOf(slot + 1), 498, 2)
				local vf, vl = variable.window(variable.offsetOf(slot + 1), 498, 2)
				expect(vf).toBe(uf)
				expect(vl).toBe(ul)
			end
		end
	end)

	it("mid-slot, the variable rule windows one MORE row — and that is deliberate", function()
		--[[ THE ONE PLACE THE TWO RULES DIVERGE, pinned so it is a decision rather
			than a surprise. The uniform rule takes the visible COUNT from the
			viewport alone (`ceil(viewport / pitch)`), which is independent of where
			between two slots the scroll sits — so at a fractional offset it names one
			row fewer than the viewport actually touches, and `overscan` (default 2)
			has always covered the difference.

			The variable rule cannot use a count: with ragged extents "how many rows
			fit in 498px" has no answer. It asks the exact question instead — which
			slot contains the viewport's trailing edge — and is therefore a strict
			SUPERSET of the uniform window, never a subset.

			The uniform rule is kept EXACTLY as it was rather than upgraded to the
			exact one, because it is the baseline every shipped list, every window
			assertion in this suite and the perf lab's instance counts are measured
			against; tightening it is a separate, deliberate change with its own
			before/after. Recorded in `docs/plans/variable-item-extents.md`. ]]
		local uniform = virtual_extents.uniform(40, 56, 0)
		local variable = virtual_extents.variable(evenExtents(40, 56), 0)
		local uf, ul = uniform.window(28, 498, 0)
		local vf, vl = variable.window(28, 498, 0)
		expect(uf).toBe(vf)
		expect(ul).toBe(9)
		expect(vl).toBe(10)
	end)
end)

describe("virtual_extents: insertion boundaries snap to the nearer edge", function()
	it("uniform boundaries sit in the middle of the gutter, clamped to the canvas", function()
		local ix = virtual_extents.uniform(4, 56, 8)
		expect(ix.boundaryOffset(0)).toBe(0) -- clamped up from -gap/2
		expect(ix.boundaryOffset(1)).toBe(60) -- 64 - 8/2
		expect(ix.boundaryOffset(4)).toBe(ix.content) -- clamped down
	end)

	it("slotAt counts the whole slots whose midpoint the offset has passed", function()
		-- ragged: 1@0..40, 2@40..120, 3@120..140
		local ix = virtual_extents.variable({ 40, 80, 20 }, 0)
		expect(ix.slotAt(0)).toBe(0)
		expect(ix.slotAt(19)).toBe(0)
		expect(ix.slotAt(21)).toBe(1) -- past item 1's midpoint (20)
		expect(ix.slotAt(79)).toBe(1)
		expect(ix.slotAt(81)).toBe(2) -- past item 2's midpoint (80)
		expect(ix.slotAt(9999)).toBe(3) -- clamped to count
	end)

	it("variable boundaries land on the item edge, gutter split", function()
		local ix = virtual_extents.variable({ 40, 80, 20 }, 10)
		expect(ix.boundaryOffset(0)).toBe(0)
		expect(ix.boundaryOffset(1)).toBe(45) -- item 2 starts at 50, less half the gutter
		expect(ix.boundaryOffset(2)).toBe(135) -- item 3 starts at 140
		expect(ix.boundaryOffset(3)).toBe(ix.content)
	end)
end)

describe("virtual_extents: the search is bounded, which is the whole point", function()
	it("windowing a 10,000-item list reads a logarithmic number of extents", function()
		--[[ VIRTUALIZATION IS THE PROMISE NOT TO TOUCH WHAT YOU CANNOT SEE. A
			`window()` that scanned the prefix sums would give the right answer and
			destroy the reason the control exists — the perf lab breaks its window on
			purpose and requires the scenario to REFUSE, and this is the same property
			one level down. Counted, not timed: an instrumented extents table records
			every read, so the assertion is on the mechanism rather than on a clock. ]]
		local reads = 0
		local raw = evenExtents(10000, 56)
		local counting = setmetatable({}, {
			__index = function(_, k)
				reads += 1
				return raw[k]
			end,
			__len = function()
				return #raw
			end,
		})
		local ix = virtual_extents.variable(counting :: any, 0)
		-- BUILDING the index is O(N) arithmetic — one pass, no measurement, no
		-- item built — and that is the cost the design accepts. What must stay
		-- bounded is every QUERY after it.
		local afterBuild = reads
		-- slot 5001 starts at 280000; its trailing edge at +498 is inside slot 5009
		local first, last = ix.window(280000, 498, 2)
		expect(first).toBe(4999)
		expect(last).toBe(5011)
		-- log2(10000) is ~13.3; two searches plus a handful of edge reads
		expect(reads - afterBuild < 64).toBe(true)
	end)

	it("the window never grows with the list", function()
		local small = virtual_extents.variable(evenExtents(20, 56), 0)
		local huge = virtual_extents.variable(evenExtents(20000, 56), 0)
		local sf, sl = small.window(0, 498, 2)
		local hf, hl = huge.window(0, 498, 2)
		expect(hl - hf).toBe(sl - sf)
	end)
end)
