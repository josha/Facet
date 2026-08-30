--!strict
-- Focus-skip by live predicate + the active-interaction exemption (row SF-L3). The predicate is evaluated AT NAVIGATION TIME, so
-- every case here flips eligibility between presses without touching the order —
-- which is the whole point: a row that becomes ineligible while a card is armed
-- must drop out of the ring with nobody rebuilding anything.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local focus_graph = require("../src/focus/focus_graph")

local function graphWith(entries: { any }, opts: any?)
	local core = Facet.newCore()
	local graph = focus_graph.new(core)
	local options = opts or {}
	if options.grouped then
		graph.pushScope({ name = "s", trap = false, groups = entries })
	else
		graph.pushScope({ name = "s", trap = false, order = entries })
	end
	return graph
end

describe("focus-skip: the live predicate (SF-L3)", function()
	it("bare string entries stay eligible forever (every pre-existing caller)", function()
		local graph = graphWith({ "a", "b", "c" })
		expect(graph.focused:get()).toBe("a")
		graph.navigate(1)
		expect(graph.focused:get()).toBe("b")
		expect(graph.isFocusable("b")).toBe(true)
	end)

	it("navigation skips a false predicate", function()
		local graph = graphWith({
			"a",
			{
				id = "b",
				focusable = function()
					return false
				end,
			},
			"c",
		})
		expect(graph.focused:get()).toBe("a")
		graph.navigate(1)
		expect(graph.focused:get()).toBe("c") -- b was skipped
	end)

	it("the predicate is re-read every navigation, never cached", function()
		local eligible = true
		local graph = graphWith({
			"a",
			{
				id = "b",
				focusable = function()
					return eligible
				end,
			},
			"c",
		})
		graph.navigate(1)
		expect(graph.focused:get()).toBe("b")
		graph.navigate(1)
		expect(graph.focused:get()).toBe("c")
		eligible = false -- the flip happens with the order untouched
		graph.navigate(-1)
		expect(graph.focused:get()).toBe("a") -- b is gone from the ring now
		eligible = true
		graph.navigate(1)
		expect(graph.focused:get()).toBe("b") -- ...and back the moment it flips
	end)

	it("entry focus lands on the first ELIGIBLE node", function()
		local graph = graphWith({
			{
				id = "a",
				focusable = function()
					return false
				end,
			},
			{
				id = "b",
				focusable = function()
					return false
				end,
			},
			"c",
		})
		expect(graph.focused:get()).toBe("c")
	end)

	it("a ring with nothing eligible leaves focus where it stands", function()
		local live = true
		local graph = graphWith({
			"a",
			{
				id = "b",
				focusable = function()
					return live
				end,
			},
		})
		graph.navigate(1)
		expect(graph.focused:get()).toBe("b")
		live = false
		-- a is still eligible, so this lands on a; then nothing else is
		graph.navigate(1)
		expect(graph.focused:get()).toBe("a")
		graph.navigate(1)
		expect(graph.focused:get()).toBe("a") -- the only eligible node: no move
	end)

	it("skipping never turns a step into a jump: a ±1 press advances ONE eligible slot", function()
		local graph = graphWith({
			"a",
			{
				id = "b",
				focusable = function()
					return false
				end,
			},
			{
				id = "c",
				focusable = function()
					return false
				end,
			},
			"d",
			"e",
		})
		graph.navigate(1)
		expect(graph.focused:get()).toBe("d")
		graph.navigate(1)
		expect(graph.focused:get()).toBe("e")
	end)

	it("pointer focus REFUSES an ineligible node — but that is not refusing the tap", function()
		local graph = graphWith({
			"a",
			{
				id = "b",
				focusable = function()
					return false
				end,
			},
		})
		expect(graph.focusOn("b")).toBe(false)
		expect(graph.focused:get()).toBe("a")
		expect(graph.focusOn("a")).toBe(true)
	end)
end)

describe("focus-skip: grouped scopes (SF-L3)", function()
	local function grouped()
		return {
			{
				name = "left",
				axis = "vertical",
				order = {
					"L1",
					{
						id = "L2",
						focusable = function()
							return false
						end,
					},
					"L3",
				},
			},
			{ name = "right", axis = "vertical", order = { "R1", "R2" } },
		}
	end

	it("steps along the axis skipping ineligible entries", function()
		local graph = graphWith(grouped(), { grouped = true })
		expect(graph.focused:get()).toBe("L1")
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("L3")
	end)

	it("wrap finds the next eligible entry around the ring", function()
		local groups = {
			{
				name = "only",
				axis = "vertical",
				wrap = true,
				containment = true,
				order = {
					"A",
					{
						id = "B",
						focusable = function()
							return false
						end,
					},
					"C",
				},
			},
		}
		local graph = graphWith(groups, { grouped = true })
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("C")
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("A") -- wrapped past the ineligible B
	end)

	it("a group with NO eligible entries is transparent to navigation", function()
		local groups = {
			{ name = "top", axis = "vertical", order = { "T1" } },
			{
				name = "dead",
				axis = "vertical",
				order = {
					{
						id = "D1",
						focusable = function()
							return false
						end,
					},
					{
						id = "D2",
						focusable = function()
							return false
						end,
					},
				},
			},
			{ name = "bottom", axis = "vertical", order = { "B1" } },
		}
		local graph = graphWith(groups, { grouped = true })
		expect(graph.focused:get()).toBe("T1")
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("B1") -- the whole dead group was skipped
	end)

	it('entry = "nearest" lands on the nearest ELIGIBLE index', function()
		local groups = {
			{ name = "left", axis = "vertical", order = { "L1", "L2", "L3" }, exit = { right = "right" } },
			{
				name = "right",
				axis = "vertical",
				entry = "nearest",
				order = {
					"R1",
					{
						id = "R2",
						focusable = function()
							return false
						end,
					},
					"R3",
				},
			},
		}
		local graph = graphWith(groups, { grouped = true })
		graph.navigateDirection("down") -- L2
		graph.navigateDirection("right")
		-- index 2 is ineligible; R1 and R3 are equidistant, and a tie goes to the
		-- FOLLOWING item — the same preference §9.3 applies everywhere else focus
		-- has to pick a survivor
		expect(graph.focused:get()).toBe("R3")
	end)

	it('entry = "restore" ignores a remembered node that is no longer eligible', function()
		local ok = true
		local groups = {
			{ name = "left", axis = "vertical", order = { "L1" }, exit = { right = "right" } },
			{
				name = "right",
				axis = "vertical",
				entry = "restore",
				exit = { left = "left" },
				order = {
					"R1",
					{
						id = "R2",
						focusable = function()
							return ok
						end,
					},
				},
			},
		}
		local graph = graphWith(groups, { grouped = true })
		graph.navigateDirection("right")
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("R2") -- remembered
		graph.navigateDirection("left")
		ok = false
		graph.navigateDirection("right")
		expect(graph.focused:get()).toBe("R1") -- the remembered node is ineligible
	end)
end)

describe("focus-skip: the active-interaction exemption (SF-L3, binding)", function()
	it("the interaction's target keeps its focusability while its predicate says no", function()
		local armed = false
		local graph = graphWith({
			"a",
			{
				id = "b",
				focusable = function()
					return not armed
				end,
			},
			"c",
		})
		graph.navigate(1)
		expect(graph.focused:get()).toBe("b")
		-- a card is armed: every row of b's class becomes ineligible...
		armed = true
		-- ...but b is what the gesture is aiming at, so it is exempt
		graph.beginInteraction("b")
		expect(graph.isFocusable("b")).toBe(true)
		graph.navigate(-1)
		expect(graph.focused:get()).toBe("a")
		graph.navigate(1)
		expect(graph.focused:get()).toBe("b") -- still reachable mid-gesture
		-- the flip takes effect when the interaction ENDS, not before
		graph.endInteraction()
		expect(graph.isFocusable("b")).toBe(false)
		graph.navigate(1)
		expect(graph.focused:get()).toBe("c")
	end)

	it("the exemption MOVES with the target: the graph holds exactly one", function()
		local graph = graphWith({
			{
				id = "a",
				focusable = function()
					return false
				end,
			},
			{
				id = "b",
				focusable = function()
					return false
				end,
			},
			"c",
		})
		graph.beginInteraction("a")
		expect(graph.interactionTarget()).toBe("a")
		expect(graph.isFocusable("a")).toBe(true)
		expect(graph.isFocusable("b")).toBe(false)
		graph.beginInteraction("b") -- the drag's hovered target moved
		expect(graph.interactionTarget()).toBe("b")
		expect(graph.isFocusable("a")).toBe(false)
		expect(graph.isFocusable("b")).toBe(true)
	end)

	it("removing the exempt node clears the exemption (it cannot protect a ghost)", function()
		local graph = graphWith({ "a", "b", "c" })
		graph.beginInteraction("b")
		graph.remove("b")
		expect(graph.interactionTarget()).toBe(nil)
	end)

	it("an exempt node is still focusable through the pointer path", function()
		local graph = graphWith({
			"a",
			{
				id = "b",
				focusable = function()
					return false
				end,
			},
		})
		expect(graph.focusOn("b")).toBe(false)
		graph.beginInteraction("b")
		expect(graph.focusOn("b")).toBe(true)
	end)
end)

describe("focus-skip: structural updates carry predicates", function()
	it("setOrder replaces the predicate map with the new order's", function()
		local graph = graphWith({ "a", "b" })
		graph.setOrder("s", {
			"a",
			{
				id = "b",
				focusable = function()
					return false
				end,
			},
			"c",
		})
		graph.navigate(1)
		expect(graph.focused:get()).toBe("c")
	end)

	it("setGroupOrder replaces one group's predicates and lands on an eligible fallback", function()
		local groups = { { name = "g", axis = "vertical", order = { "g1", "g2", "g3" } } }
		local graph = graphWith(groups, { grouped = true })
		graph.navigateDirection("down")
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("g3")
		graph.setGroupOrder("s", "g", {
			"g1",
			{
				id = "g2",
				focusable = function()
					return false
				end,
			},
		})
		-- g3 is gone: the fallback clamps to the old index and skips the
		-- ineligible neighbour rather than parking on it
		expect(graph.focused:get()).toBe("g1")
	end)

	it("replaceGroups normalizes predicates on the new map", function()
		local graph = graphWith({ { name = "g", axis = "vertical", order = { "g1" } } }, { grouped = true })
		graph.replaceGroups("s", {
			{
				name = "g",
				axis = "vertical",
				order = {
					{
						id = "n1",
						focusable = function()
							return false
						end,
					},
					"n2",
				},
			},
		})
		expect(graph.focused:get()).toBe("n2")
	end)

	it("a removed node's predicate is dropped with it (no stale entry for a reused id)", function()
		local graph = graphWith({
			"a",
			{
				id = "b",
				focusable = function()
					return false
				end,
			},
		})
		graph.remove("b")
		graph.setOrder("s", { "a", "b" })
		graph.navigate(1)
		expect(graph.focused:get()).toBe("b") -- plain again: the old predicate is gone
	end)
end)
