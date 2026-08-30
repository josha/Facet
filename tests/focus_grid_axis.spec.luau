--!strict
--[[ THE SECOND AXIS OF A FOCUS GROUP (design §9.3, UI-FOCUS-001).

	A grid's focus ring is TWO-dimensional and the focus graph's ring was not, so
	both lazy grids declared a 1-D group along their LANE axis and intercepted the
	perpendicular key through `navigateIntercept`, converting it to ±`columns` by
	hand. This file proves the mechanism that replaced both intercepts: a
	`NavigationGroup` may declare `columns`, which says "my order is LINES of
	`columns` LANES in row-major document order" — and the graph then answers the
	perpendicular direction itself, by a whole line.

	THE INVARIANT THE ARITHMETIC RESTS ON: a 2-D group's order is a complete
	row-major rectangle, and only the LAST line may be short. Everything below is
	either that arithmetic or the answer at an edge of it.

	WHAT IS DELIBERATELY NOT HERE. The 1-D groups are unchanged, and their proof
	is where it already lives — `tests/navigation_groups.spec.luau`,
	`tests/focus.spec.luau`, `tests/focus_skip.spec.luau`,
	`tests/traversal_order.spec.luau`, `tests/keyboard_navigation.spec.luau`. The
	one case this file DOES carry about them is the null hypothesis at the bottom:
	a group with no `columns` walks byte-identically to a group that never heard of
	the field, which is what makes "every existing group is unchanged" a claim with
	a check behind it rather than a reading of the diff.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local focus_graph = require("../src/focus/focus_graph")
local fuzz = require("./lib/fuzz")
local prng = require("./lib/prng")

-- `count` cells named c1..cN
local function cells(count: number): { string }
	local out = table.create(count)
	for i = 1, count do
		out[i] = `c{i}`
	end
	return out
end

-- one scope holding one 2-D group. `axis` is the LANE axis, exactly as the grids
-- declare it: "horizontal" is a vertical grid (lanes across, lines down), "vertical"
-- is a sideways grid (lanes down, lines rightward).
local function gridScope(count: number, columns: number, axis: string?, extra: any?): any
	local core = customFactory.new()
	local graph = focus_graph.new(core)
	local group: any = {
		name = "Cells",
		axis = axis or "horizontal",
		columns = columns,
		order = cells(count),
	}
	for key, value in extra or {} do
		group[key] = value
	end
	graph.pushScope({ name = "S", trap = false, groups = { group } })
	return graph
end

-- ===========================================================================
describe("focus graph: a 2-D group answers the perpendicular direction itself", function()
	it("the perpendicular direction moves a whole LINE, not one cell", function()
		-- 12 cells, 4 lanes: the vertical grid shape. Down from c1 must be c5.
		local graph = gridScope(12, 4)
		expect(graph.focused:get()).toBe("c1")
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("c5") -- NOT c2
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("c9")
		graph.navigateDirection("up")
		expect(graph.focused:get()).toBe("c5")
	end)

	it("the LANE axis is untouched: ±1 in document order, crossing lines row-major", function()
		-- the half that already worked, pinned so the new arithmetic cannot eat it.
		-- Right off the end of a line lands on the NEXT LINE'S FIRST CELL, which is
		-- what row-major document order means and what the shipped grids do today.
		local graph = gridScope(12, 4)
		graph.navigateDirection("right")
		expect(graph.focused:get()).toBe("c2")
		graph.navigateDirection("right")
		graph.navigateDirection("right")
		expect(graph.focused:get()).toBe("c4") -- the end of line 1
		graph.navigateDirection("right")
		expect(graph.focused:get()).toBe("c5") -- ...and over into line 2
		graph.navigateDirection("left")
		expect(graph.focused:get()).toBe("c4")
	end)

	it("TRANSPOSE: on a `vertical` lane axis the LINE move is Right/Left", function()
		-- the sideways grid. Lanes run DOWN, lines advance RIGHTWARD, so the group's own
		-- axis takes Down/Up and the perpendicular pair is Right/Left. The two grids
		-- differ only in this direction pair, which is the whole reason the mechanism
		-- is one field rather than two intercepts.
		local graph = gridScope(12, 4, "vertical")
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("c2") -- a LANE step
		graph.navigateDirection("right")
		expect(graph.focused:get()).toBe("c6") -- a LINE step
		graph.navigateDirection("left")
		expect(graph.focused:get()).toBe("c2")
	end)

	it("a 2-D group answers all FOUR directions, so `navigate(±1)` means down/up", function()
		--[[ `navigate(delta)` is the unsigned ring verb, and the presenter drives it
			from the VERTICAL arrow on a scope whose groups arrived after the push
			(`replaceGroups` upgrading a flat scope — device round 1, DB-4). For a 1-D
			group it maps ±1 onto that group's only navigable axis, which for a
			a vertical grid's `horizontal` group would send a DOWN press RIGHTWARD. A 2-D
			group has both axes, so the mapping stops guessing and the verb keeps its
			own reading: down/up. ]]
		local vgrid = gridScope(12, 4, "horizontal")
		vgrid.navigate(1)
		expect(vgrid.focused:get()).toBe("c5") -- down a line, not right a cell
		vgrid.navigate(-1)
		expect(vgrid.focused:get()).toBe("c1")
		-- ...and on the transpose "down" is the LANE axis, so the same verb steps one
		local hgrid = gridScope(12, 4, "vertical")
		hgrid.navigate(1)
		expect(hgrid.focused:get()).toBe("c2")
	end)
end)

-- ===========================================================================
describe("focus graph: a ragged last line has an answer in both directions", function()
	it("FORWARD the move CLAMPS into a short last line rather than falling out", function()
		--[[ 10 cells, 4 lanes: lines are [1-4] [5-8] [9-10]. From c7 (line 2, lane 3)
			the cell below would be index 11, which does not exist — but LINE 3 does,
			and a player looking at a grid with a third row and pressing Down expects
			to reach it. The pre-mechanism intercept declined this press outright
			(`target > #items` -> `return false`), so lane 3 and lane 4 could not reach
			the last line at all without stepping sideways first. ]]
		local graph = gridScope(10, 4)
		graph.focusOn("c7")
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("c10") -- the nearest lane that exists
		graph.focusOn("c8")
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("c10")
	end)

	it("...and clamping is NOT a wrap: from the last line itself the move exits", function()
		local graph = gridScope(10, 4)
		graph.focusOn("c9")
		graph.navigateDirection("down") -- already in the last line: nothing below
		expect(graph.focused:get()).toBe("c9")
	end)

	it("BACKWARD needs no clamp — only the last line can be short", function()
		local graph = gridScope(10, 4)
		graph.focusOn("c10") -- line 3, lane 2
		graph.navigateDirection("up")
		expect(graph.focused:get()).toBe("c6") -- line 2, lane 2: the lane is kept
		graph.navigateDirection("up")
		expect(graph.focused:get()).toBe("c2")
		graph.navigateDirection("up")
		expect(graph.focused:get()).toBe("c2") -- the top: the move exits, focus stays
	end)

	it("a single short line is still a line (fewer cells than lanes)", function()
		local graph = gridScope(3, 4)
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("c1")
		graph.navigateDirection("right")
		expect(graph.focused:get()).toBe("c2")
	end)
end)

-- ===========================================================================
describe("focus graph: 2-D edges, eligibility and wrap", function()
	it("the perpendicular step SKIPS ineligible cells down the same lane", function()
		-- focus-skip (SF-L3) is evaluated at navigation time on both axes, and the
		-- perpendicular skip keeps the LANE: it steps by whole lines, not by ones.
		local core = customFactory.new()
		local graph = focus_graph.new(core)
		local blocked: { [string]: boolean } = { c5 = true, c9 = true }
		local order: { any } = {}
		for _, id in cells(16) do
			table.insert(order, {
				id = id,
				focusable = function()
					return not blocked[id]
				end,
			})
		end
		graph.pushScope({
			name = "S",
			trap = false,
			groups = { { name = "Cells", axis = "horizontal", columns = 4, order = order } },
		})
		expect(graph.focused:get()).toBe("c1")
		graph.navigateDirection("down") -- c5 and c9 are out; c13 is the lane's survivor
		expect(graph.focused:get()).toBe("c13")
	end)

	it("...and the ragged clamp still fires when the walk REACHED the last line by skipping", function()
		--[[ WRITTEN BY THE ORACLE, KEPT FOR THE READER. Mutation M4 — clamping on the
			opening step only — reddened exactly one case in the whole suite, and it was
			the generated corpus, which reports a seed rather than a story. This is that
			seed's shape as a sentence: 13 cells in 4 lanes, so the lines are
			[1-4][5-8][9-12][13]. From c2 the lane-2 walk finds c6 and c10 ineligible and
			arrives at the ragged last line from ABOVE the line before it — which is the
			only way to get there without the opening step, and therefore the only way a
			first-step-only clamp could miss. ]]
		local core = customFactory.new()
		local graph = focus_graph.new(core)
		local blocked: { [string]: boolean } = { c6 = true, c10 = true }
		local order: { any } = {}
		for _, id in cells(13) do
			table.insert(order, {
				id = id,
				focusable = function()
					return not blocked[id]
				end,
			})
		end
		graph.pushScope({
			name = "S",
			trap = false,
			groups = { { name = "Cells", axis = "horizontal", columns = 4, order = order } },
		})
		graph.focusOn("c2")
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("c13")
	end)

	it("`wrap` governs the group's DECLARED axis only; the perpendicular exits", function()
		--[[ The rule is already written down for 1-D (`FocusScope.traversalWrap`: "a
			group's own `wrap` governs the DIRECTIONAL arrows along that group's axis
			and nothing else"). A 2-D group does not get a second, unstated wrap: the
			bottom of a column is an EXIT, which is what lets a grid hand focus to
			whatever sits under it. ]]
		local core = customFactory.new()
		local graph = focus_graph.new(core)
		graph.pushScope({
			name = "S",
			trap = false,
			groups = {
				{ name = "Cells", axis = "horizontal", columns = 4, wrap = true, order = cells(8) },
				{ name = "After", axis = "horizontal", order = { "ok", "cancel" } },
			},
		})
		graph.focusOn("c8")
		graph.navigateDirection("right") -- the lane axis wraps, as declared
		expect(graph.focused:get()).toBe("c1")
		graph.focusOn("c6")
		graph.navigateDirection("down") -- the perpendicular does NOT
		expect(graph.focused:get()).toBe("ok")
	end)

	it("exiting perpendicular hands the LANE on, so the column survives the crossing", function()
		--[[ `exitFrom` passes an ordinal that the receiving group reads as "nearest".
			For a 1-D group that ordinal is its index; for a 2-D group the index is a
			flattened one (cell 7 of a 4-lane grid is lane 3), and handing THAT on
			would land the ring seven controls into the next row. The lane is the
			ordinal that means the same thing on both sides. ]]
		local core = customFactory.new()
		local graph = focus_graph.new(core)
		graph.pushScope({
			name = "S",
			trap = false,
			groups = {
				{ name = "Cells", axis = "horizontal", columns = 4, order = cells(8) },
				{ name = "After", axis = "horizontal", entry = "nearest", order = { "a", "b", "c", "d" } },
			},
		})
		graph.focusOn("c7") -- line 2, lane 3
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("c") -- lane 3 of the row below, not "d" (index 7 clamped)
	end)
end)

-- ===========================================================================
describe("focus graph: perpendicular ENTRY into a 2-D group is the near LINE", function()
	it("entering DOWNWARD lands in the FIRST line, at the ordinal lane", function()
		local core = customFactory.new()
		local graph = focus_graph.new(core)
		graph.pushScope({
			name = "S",
			trap = false,
			groups = {
				{ name = "Before", axis = "horizontal", order = { "a", "b", "c", "d" } },
				{ name = "Cells", axis = "horizontal", columns = 4, order = cells(12) },
			},
		})
		graph.focusOn("c") -- ordinal 3
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("c3") -- line 1, lane 3
	end)

	it("entering UPWARD lands in the LAST line, at the ordinal lane", function()
		--[[ This is the case the 1-D reading got visibly wrong. `enterGroup` puts
			every perpendicular entry at index 1 of the group it enters, and index 1 of
			a grid is its TOP-LEFT cell — so a pad pressing Up from beneath a grid
			jumped over the whole grid to its first cell. The near-end rule the graph
			applies along an axis is exactly the rule that was missing across one. ]]
		local core = customFactory.new()
		local graph = focus_graph.new(core)
		graph.pushScope({
			name = "S",
			trap = false,
			groups = {
				{ name = "Cells", axis = "horizontal", columns = 4, order = cells(12) },
				{ name = "After", axis = "horizontal", order = { "a", "b", "c", "d" } },
			},
		})
		graph.focusOn("c") -- ordinal 3
		graph.navigateDirection("up")
		expect(graph.focused:get()).toBe("c11") -- line 3, lane 3
	end)

	it("entering upward into a RAGGED last line clamps to the lane that exists", function()
		local core = customFactory.new()
		local graph = focus_graph.new(core)
		graph.pushScope({
			name = "S",
			trap = false,
			groups = {
				{ name = "Cells", axis = "horizontal", columns = 4, order = cells(10) },
				{ name = "After", axis = "horizontal", order = { "a", "b", "c", "d" } },
			},
		})
		graph.focusOn("d") -- ordinal 4; the last line holds c9, c10
		graph.navigateDirection("up")
		expect(graph.focused:get()).toBe("c10")
	end)

	it("entry ALONG the lane axis is unchanged: the near END of the order", function()
		local core = customFactory.new()
		local graph = focus_graph.new(core)
		graph.pushScope({
			name = "S",
			trap = false,
			groups = {
				{ name = "Left", axis = "vertical", order = { "a", "b" } },
				{ name = "Cells", axis = "horizontal", columns = 4, order = cells(12) },
			},
		})
		graph.focusOn("b")
		graph.navigateDirection("right")
		expect(graph.focused:get()).toBe("c1")
	end)
end)

-- ===========================================================================
describe("focus graph: the rectangle invariant", function()
	it("a SPLICE degrades a 2-D group to its 1-D reading rather than mis-navigating", function()
		--[[ `columns` describes the order it was declared WITH. `remove` splices one
			entry out, which shifts every following cell into the wrong lane — so from
			that moment the arithmetic would be confidently wrong. It fails to the
			reading that is merely OLD instead: the lane axis keeps working and the
			perpendicular exits, until the emitter replaces the order wholesale, which
			is what every 2-D emitter does on refresh. ]]
		local graph = gridScope(12, 4)
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("c5")
		graph.remove("c2")
		graph.focusOn("c1")
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("c1") -- the perpendicular no longer answers
		graph.navigateDirection("right")
		expect(graph.focused:get()).toBe("c3") -- ...and the lane axis still does
	end)

	it("the HIDDEN filter punches the same hole, and drops the field the same way", function()
		--[[ `focus_map.filterGroupsHidden` splices entries out of a group's order when
			a subtree goes hidden (a losing `ViewThatFits` candidate, an exit
			transition) — the same shape of hole `remove` makes, one layer up, and it
			reaches every group on its way to the graph. Grepping the callers of the
			thing you touch is how this one was found rather than reasoned about. ]]
		local focus_map = require("../src/present/focus_map")
		local groups = {
			{ name = "Cells", axis = "horizontal", columns = 4, order = { "/S/a", "/S/b", "/S/c", "/S/d" } },
			{ name = "Untouched", axis = "horizontal", columns = 2, order = { "/S/x", "/S/y" } },
		}
		local filtered = focus_map.filterGroupsHidden(groups, { ["/S/b"] = true })
		expect(#filtered[1].order).toBe(3)
		expect(filtered[1].columns).toBe(nil) -- the rectangle is gone; so is the claim
		expect(filtered[2].columns).toBe(2) -- a group it did not cut keeps its lanes
		expect(groups[1].columns).toBe(4) -- ...and the CALLER's table is never written
	end)

	it("a whole-order replacement re-declares `columns` and the arithmetic returns", function()
		local graph = gridScope(12, 4)
		graph.replaceGroups("S", { { name = "Cells", axis = "horizontal", columns = 3, order = cells(9) } })
		graph.focusOn("c1")
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("c4") -- three lanes now, not four
	end)

	it("`setGroupOrder` carries the lane count with the order, or clears it", function()
		-- the same rule as `replaceGroups`'s `rank`: the shape describes THIS order,
		-- so it comes from the derivation that produced it. Omitting it is not
		-- "keep what you had", it is "I am no longer claiming a rectangle".
		local graph = gridScope(12, 4)
		graph.setGroupOrder("S", "Cells", cells(9), 3)
		graph.focusOn("c1")
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("c4")
		graph.setGroupOrder("S", "Cells", cells(9))
		graph.focusOn("c1")
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("c1") -- no claim, no second axis
	end)
end)

-- ===========================================================================
describe("focus graph: a group with no `columns` is unchanged", function()
	it("NULL HYPOTHESIS: 1-D groups walk byte-identically with the field absent", function()
		--[[ The mechanism is gated on `columns`, and this is the check that says so
			rather than the diff saying so. The same walk is run over a group declared
			with no `columns` and over one declared `columns = nil` explicitly, and both
			must produce the pre-mechanism answer: the perpendicular direction moves
			nothing (there is one group, so its exit falls out of the scope). ]]
		local function walk(group: any): { string? }
			local core = customFactory.new()
			local graph = focus_graph.new(core)
			graph.pushScope({ name = "S", trap = false, groups = { group } })
			local seen: { string? } = {}
			for _, direction in { "right", "down", "right", "up", "left", "down", "left" } do
				graph.navigateDirection(direction)
				table.insert(seen, graph.focused:get())
			end
			return seen
		end
		local implicit = walk({ name = "G", axis = "horizontal", order = cells(6) })
		local explicit = walk({ name = "G", axis = "horizontal", columns = nil, order = cells(6) })
		expect(implicit).toEqual(explicit)
		-- ...and it is the ONE-dimensional answer: only the lane axis ever moved
		expect(implicit).toEqual({ "c2", "c2", "c3", "c3", "c2", "c2", "c1" })
	end)

	it("`columns` is refused as a navigable claim unless it is an integer >= 1", function()
		-- a malformed declaration must fall back to the 1-D reading, never to
		-- arithmetic on a fraction or a string
		for _, bad in { 0, -2, 1.5, "4", true } do
			local graph = gridScope(12, 4, "horizontal", { columns = bad })
			graph.navigateDirection("down")
			expect(graph.focused:get()).toBe("c1")
		end
	end)
end)

-- ===========================================================================
--[[ THE DIFFERENTIAL ORACLE.

	Three hand-picked cases prove three hand-picked answers. The claim this
	mechanism actually makes is arithmetic over a rectangle, so the check is a
	MODEL written in the vocabulary of the claim — (line, lane) coordinates,
	derived from the ADR's rules and not from the implementation — run against the
	graph over a generated corpus of grids and walks.

	The model and the mechanism are independent formulations on purpose: the graph
	walks ONE flat order with ±1 and ±columns and never computes a coordinate; the
	model computes coordinates and never touches an index. They can only agree by
	both being right.
]]
local DIRECTIONS = { "up", "down", "left", "right" }

-- the model: a grid as coordinates. `lanesInLine` is the only place raggedness
-- exists, and it is the last line by construction.
local function model(count: number, columns: number, axis: string, eligible: { [string]: boolean })
	local lastLine = math.max(1, math.ceil(count / columns))
	local function lineOf(i: number): number
		return math.floor((i - 1) / columns) + 1
	end
	local function laneOf(i: number): number
		return ((i - 1) % columns) + 1
	end
	local function lanesInLine(line: number): number
		return if line < lastLine then columns else count - (lastLine - 1) * columns
	end
	local function indexAt(line: number, lane: number): number
		return (line - 1) * columns + lane
	end
	local function ok(i: number): boolean
		return eligible[`c{i}`] ~= false
	end
	-- returns the id the ring lands on, or nil when the move leaves the group
	return function(from: number, direction: string): string?
		local laneAxis = if axis == "horizontal" then { right = 1, left = -1 } else { down = 1, up = -1 }
		local along = laneAxis[direction]
		if along ~= nil then
			-- ALONG the lanes: one step in document order, skipping the ineligible
			local j = from + along
			while j >= 1 and j <= count do
				if ok(j) then
					return `c{j}`
				end
				j += along
			end
			return nil
		end
		-- ACROSS the lanes: one whole line, keeping the lane, clamping into a
		-- short last line
		local step = if direction == "down" or direction == "right" then 1 else -1
		local lane = laneOf(from)
		local line = lineOf(from) + step
		while line >= 1 and line <= lastLine do
			local j = indexAt(line, math.min(lane, lanesInLine(line)))
			if ok(j) then
				return `c{j}`
			end
			line += step
		end
		return nil
	end
end

local function oracleCase(rng: prng.Prng)
	local columns = rng:range(1, 5)
	local lines = rng:range(1, 6)
	-- a last line that is short as often as it is full: raggedness is the edge the
	-- corpus exists to hammer, so it must not be rare
	local count = (lines - 1) * columns + rng:range(1, columns)
	local axis = if rng:bool() then "horizontal" else "vertical"
	local eligible: { [string]: boolean } = {}
	local order: { any } = {}
	for i = 1, count do
		local id = `c{i}`
		if rng:bool(0.2) and count > 1 then
			eligible[id] = false
		end
		table.insert(order, {
			id = id,
			focusable = function()
				return eligible[id] ~= false
			end,
		})
	end
	local core = customFactory.new()
	local graph = focus_graph.new(core)
	graph.pushScope({
		name = "S",
		trap = false,
		groups = { { name = "G", axis = axis, columns = columns, order = order } },
	})
	local predict = model(count, columns, axis, eligible)
	-- start wherever the graph's own entry rule put the ring; if everything is
	-- ineligible there is nothing to walk
	local at = graph.focused:get()
	if at == nil then
		return
	end
	for _ = 1, 12 do
		local direction = rng:pick(DIRECTIONS)
		local from = tonumber(string.match(at :: string, "c(%d+)")) :: number
		local want = predict(from, direction)
		graph.navigateDirection(direction)
		local got = graph.focused:get()
		-- a move that leaves the one-group scope has nowhere to go, so the ring stays
		local expected = want or at
		if got ~= expected then
			error(
				`grid {count} cells / {columns} lanes / axis={axis}: {direction} from {at} `
					.. `gave {tostring(got)}, model says {tostring(expected)}`
			)
		end
		at = got
	end
end

describe("focus graph: the 2-D ring matches a coordinate model over a generated corpus", function()
	it("agrees with the (line, lane) oracle over 300 seeded grids and walks", function()
		local report = fuzz.run({ name = "focus-grid-axis", baseSeed = 815300, cases = 300, case = oracleCase })
		if #report.failures > 0 then
			local first = report.failures[1]
			error(`focus grid axis fuzz failed: seed={first.seed} case={first.case} err={first.error}`)
		end
		expect(#report.failures).toBe(0)
	end)

	it("is replayable: identical base seed, identical fingerprint", function()
		local a = fuzz.run({ name = "focus-grid-axis", baseSeed = 815300, cases = 40, case = oracleCase })
		local b = fuzz.run({ name = "focus-grid-axis", baseSeed = 815300, cases = 40, case = oracleCase })
		expect(a.fingerprint).toBe(b.fingerprint)
	end)

	it("THE CORPUS BITES: the oracle rejects a one-cell perpendicular step", function()
		--[[ A corpus that agrees with a broken mechanism proves nothing, so the
			generator is aimed at a deliberately wrong model — the LIST's answer, where
			the perpendicular walks one cell instead of one line, which is the exact
			defect shape the grids' header calls "reachable and wrong". If this case
			ever stops finding a disagreement, the corpus has stopped covering the
			claim. ]]
		local disagreements = 0
		local rng = prng.new(815300)
		for _ = 1, 60 do
			local columns = rng:range(2, 5)
			local count = columns * rng:range(2, 5)
			local truth = model(count, columns, "horizontal", {})
			for from = 1, count do
				local want = truth(from, "down")
				local wrong = if from + 1 <= count then `c{from + 1}` else nil
				if want ~= wrong then
					disagreements += 1
				end
			end
		end
		expect(disagreements > 0).toBe(true)
	end)
end)
