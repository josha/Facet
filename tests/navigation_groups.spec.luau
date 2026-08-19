--!strict
-- Phase 4 richer navigation groups (design §9.3; UI-FOCUS-001): scopes may
-- structure their focusables into NavigationGroups with an axis, a wrap
-- policy, containment, entry policy ("first" | "restore" | "nearest"), and
-- per-direction exit overrides. Direction-aware navigation moves within the
-- active group along its axis and crosses groups per the exit policy;
-- containment blocks implicit exits; modal traps still trap at the scope
-- level; flat (ungrouped) scopes keep the existing ring semantics.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customCore = require("../src/core/custom")
local focus_graph = require("../src/focus/focus_graph")

local function newGraph()
	local core = (customCore :: any).new()
	return focus_graph.new(core)
end

-- header row (horizontal) above a list (vertical), sidebar to the left
local function groupedScope()
	return {
		name = "screen",
		trap = false,
		groups = {
			{
				name = "header",
				axis = "horizontal",
				wrap = false,
				order = { "/S/Tab1", "/S/Tab2", "/S/Tab3" },
				exit = { down = "list" },
				entry = "restore",
			},
			{
				name = "list",
				axis = "vertical",
				wrap = false,
				order = { "/S/Row1", "/S/Row2", "/S/Row3" },
				exit = { up = "header", left = "sidebar" },
				entry = "first",
			},
			{
				name = "sidebar",
				axis = "vertical",
				wrap = true,
				containment = true,
				order = { "/S/Side1", "/S/Side2" },
				exit = { right = "list" },
				entry = "first",
			},
		},
	}
end

describe("navigation groups (§9.3)", function()
	it("moves along the group axis; the orthogonal axis does not move within the group", function()
		local graph = newGraph()
		graph.pushScope(groupedScope())
		expect(graph.focused:get()).toBe("/S/Tab1") -- first group, first item
		graph.navigateDirection("right")
		expect(graph.focused:get()).toBe("/S/Tab2")
		graph.navigateDirection("up") -- no exit up from header, no axis move
		expect(graph.focused:get()).toBe("/S/Tab2")
	end)

	it("wrap=false stops at the edge; wrap=true wraps inside the group", function()
		local graph = newGraph()
		graph.pushScope(groupedScope())
		graph.navigateDirection("left") -- at Tab1 already, wrap=false
		expect(graph.focused:get()).toBe("/S/Tab1")
		-- sidebar wraps
		graph.focusOn("/S/Side2")
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("/S/Side1")
	end)

	it("a per-direction exit override crosses groups with the target's entry policy", function()
		local graph = newGraph()
		graph.pushScope(groupedScope())
		graph.navigateDirection("down") -- header -> list (entry=first)
		expect(graph.focused:get()).toBe("/S/Row1")
	end)

	it("entry='restore' returns to the group's last-focused item", function()
		local graph = newGraph()
		graph.pushScope(groupedScope())
		graph.navigateDirection("right") -- Tab2
		graph.navigateDirection("down") -- list Row1
		graph.navigateDirection("up") -- back to header: restores Tab2, not Tab1
		expect(graph.focused:get()).toBe("/S/Tab2")
	end)

	it("containment blocks implicit exits; only declared exits leave the group", function()
		local graph = newGraph()
		graph.pushScope(groupedScope())
		graph.focusOn("/S/Side1")
		graph.navigateDirection("left") -- contained, no exit.left: stays
		expect(graph.focused:get()).toBe("/S/Side1")
		graph.navigateDirection("right") -- declared exit
		expect(graph.focused:get()).toBe("/S/Row1")
	end)

	it("without containment, an axis edge falls through to the neighboring group in order", function()
		local graph = newGraph()
		graph.pushScope(groupedScope())
		graph.focusOn("/S/Row3")
		graph.navigateDirection("down") -- list edge, no exit.down: next group (sidebar)
		expect(graph.focused:get()).toBe("/S/Side1")
	end)

	it("a modal trap keeps direction navigation inside the modal scope", function()
		local graph = newGraph()
		graph.pushScope(groupedScope())
		graph.pushScope({
			name = "modal",
			trap = true,
			groups = {
				{ name = "buttons", axis = "horizontal", wrap = true, order = { "/M/Ok", "/M/Cancel" } },
			},
		})
		expect(graph.focused:get()).toBe("/M/Ok")
		graph.navigateDirection("down") -- nowhere to go: stays inside the trap
		expect(graph.focused:get()).toBe("/M/Ok")
		graph.navigateDirection("right")
		expect(graph.focused:get()).toBe("/M/Cancel")
		graph.popScope()
		expect(graph.focused:get()).toBe("/S/Tab1") -- previous focus restored
	end)

	it("replacing a group's order keeps focus or lands on the nearest survivor", function()
		local graph = newGraph()
		graph.pushScope(groupedScope())
		graph.focusOn("/S/Row2")
		graph.setGroupOrder("screen", "list", { "/S/Row1", "/S/Row3" }) -- Row2 gone
		expect(graph.focused:get()).toBe("/S/Row3") -- nearest surviving, prefers following
		graph.setGroupOrder("screen", "list", { "/S/Row1", "/S/Row3", "/S/Row9" })
		expect(graph.focused:get()).toBe("/S/Row3") -- untouched when focus survives
	end)

	it("presenter: navigationGroups opt drives grouped, direction-aware navigation end to end", function()
		-- architecture verifier F2: grouped navigation must be reachable
		-- through the PUBLIC presenter, not only by hand-driving the graph
		local Facet = require("../src") :: any
		local fake_target = require("./lib/fake_target")
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local screen = Facet.UI.Screen({
			id = "Board",
			children = {
				Facet.UI.Button({ id = "A", label = "A" }),
				Facet.UI.Button({ id = "B", label = "B" }),
				Facet.UI.Button({ id = "C", label = "C" }),
				Facet.UI.Button({ id = "D", label = "D" }),
			},
		})
		local handle = pres.present(screen, {
			navigationGroups = {
				{ name = "row1", axis = "horizontal", order = { "/Board/A", "/Board/B" } },
				{ name = "row2", axis = "horizontal", order = { "/Board/C", "/Board/D" } },
			},
		})
		expect(pres.focus.focused:get()).toBe("/Board/A")
		system.deviceKey("Right", true)
		system.deviceKey("Right", false)
		expect(pres.focus.focused:get()).toBe("/Board/B")
		system.deviceKey("Down", true)
		system.deviceKey("Down", false)
		expect(pres.focus.focused:get()).toBe("/Board/C") -- fell through to row2
		system.deviceKey("Left", true)
		system.deviceKey("Left", false)
		-- uncontained axis edge falls through the group array. ENTRY ALONG THE
		-- TARGET'S AXIS lands at the NEAR END (director virtual-controller round):
		-- leftward travel off row2's left edge arrives at row1's RIGHT end —
		-- reading-order navigation, the same rule that makes "right into the
		-- hand" always land on the first card
		expect(pres.focus.focused:get()).toBe("/Board/B")
		pres.dismiss(handle)
		expect(pres.depth()).toBe(0)
	end)

	it("replaceGroups swaps a scope's group map, keeping surviving focus", function()
		local graph = newGraph()
		graph.pushScope(groupedScope())
		graph.focusOn("/S/Row2")
		graph.replaceGroups("screen", {
			{ name = "list", axis = "vertical", order = { "/S/Row1", "/S/Row2" } },
		})
		expect(graph.focused:get()).toBe("/S/Row2") -- survived
		graph.replaceGroups("screen", {
			{ name = "list", axis = "vertical", order = { "/S/RowX", "/S/RowY" } },
		})
		expect(graph.focused:get()).toBe("/S/RowX") -- entry of the new map
	end)

	it("presenter: D-PAD navigates (grouped scopes) and a groups FUNCTION re-derives on refresh", function()
		local Facet = require("../src") :: any
		local fake_target = require("./lib/fake_target")
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local extra = core:signal(false)
		local screen = Facet.UI.Screen({
			id = "G",
			children = {
				Facet.UI.Button({ id = "A", label = "A" }),
				Facet.UI.Button({ id = "B", label = "B" }),
				Facet.UI.When({
					id = "W",
					condition = extra,
					thenView = function()
						return Facet.UI.Button({ id = "C", label = "C" })
					end,
				}),
			},
		})
		local groupsBuilt = 0
		pres.present(screen, {
			navigationGroups = function(rootNode: any)
				groupsBuilt += 1
				local order = {}
				local function walk(node: any)
					if node.class == "Button" then
						table.insert(order, node.path)
					end
					for _, child in node.children or {} do
						walk(child)
					end
				end
				walk(rootNode)
				return { { name = "all", axis = "vertical", order = order } }
			end,
		})
		expect(pres.focus.focused:get()).toBe("/G/A")
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		expect(pres.focus.focused:get()).toBe("/G/B")
		system.deviceKey("DPadUp", true)
		system.deviceKey("DPadUp", false)
		expect(pres.focus.focused:get()).toBe("/G/A")
		-- structure change: the groups fn re-derives on refresh
		extra:set(true)
		pres.refresh()
		expect(groupsBuilt >= 2).toBeTruthy()
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		system.deviceKey("DPadDown", true)
		system.deviceKey("DPadDown", false)
		expect(pres.focus.focused:get()).toBe("/G/W/then/C") -- the new button is reachable
	end)

	it("the INITIAL focus paints its ring (gamepad users must see where focus starts)", function()
		local Facet = require("../src") :: any
		local fake_target = require("./lib/fake_target")
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		local system = Facet.newActionSystem(core)
		local adapter = fake_target.new()
		local pres = Facet.newPresenter(core, env, adapter, system)
		local screen = Facet.UI.Screen({
			id = "R",
			children = { Facet.UI.Button({ id = "First", label = "F" }) },
		})
		pres.present(screen, {})
		expect(pres.focus.focused:get()).toBe("/R/First")
		expect(adapter.node("/R/First").focused).toBe(true) -- ring visible NOW
	end)

	--[[ ADAPT-24 — A HORIZONTAL RAIL NAVIGATED VERTICALLY ON A PAD.

		`focus_map.isHorizontalRun` matched `HStack` and `AdaptiveStack{axis="x"}`
		and nothing else, so the recommended card rail (`VirtualList{axis="x"}`,
		which declares its own group) worked while the NAIVE one — `UI.ScrollView{
		axis = "x" }` with the cards inside it — put its cards in a VERTICAL ring:
		DPadRight moved nothing and DPadDown stepped along the rail. The audit calls
		it the exact defect class the D5 round fixed, one predicate short (B-6), and
		the fix is the predicate, with the SAME "must actually be a run" test the
		adaptive stack carries — a scroller holding one stack of many focusables is
		a container, not a run. ]]
	it("ADAPT-24: a horizontal ScrollView is a HORIZONTAL run, and a vertical one is not", function()
		local Facet = require("../src") :: any
		local fake_target = require("./lib/fake_target")
		local focus_map = require("../src/present/focus_map")
		local function railGroups(axis: string): { any }
			local core = Facet.newCore()
			local env = Facet.newEnvironment(core)
			env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
			local pres = Facet.newPresenter(core, env, fake_target.new(), Facet.newActionSystem(core))
			local cards: { any } = {}
			for index = 1, 4 do
				table.insert(
					cards,
					Facet.UI.Button({
						id = `Card{index}`,
						label = `Card {index}`,
						width = { type = "fixed", px = 120 },
						height = { type = "fixed", px = 90 },
					})
				)
			end
			local handle = pres.present(Facet.UI.Screen({
				id = "S",
				children = { Facet.UI.ScrollView({ id = "Rail", axis = axis, children = cards }) },
			}))
			pres.refresh()
			return focus_map.autoGroups(handle.root.node)
		end
		local across = railGroups("x")
		expect(#across).toBe(1)
		expect(across[1].axis).toBe("horizontal")
		expect(across[1].order[1]).toBe("/S/Rail/Card1")
		expect(across[1].order[4]).toBe("/S/Rail/Card4")
		-- the null hypothesis: a y-axis scroller is untouched, still vertical
		local down = railGroups("y")
		expect(#down).toBe(1)
		expect(down[1].axis).toBe("vertical")
	end)

	it("ADAPT-24: ...but a scroller holding ONE stack of focusables is not a run", function()
		local Facet = require("../src") :: any
		local fake_target = require("./lib/fake_target")
		local focus_map = require("../src/present/focus_map")
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local pres = Facet.newPresenter(core, env, fake_target.new(), Facet.newActionSystem(core))
		local handle = pres.present(Facet.UI.Screen({
			id = "S",
			children = {
				Facet.UI.ScrollView({
					id = "Rail",
					axis = "x",
					children = {
						Facet.UI.VStack({
							id = "Column",
							children = {
								Facet.UI.Button({ id = "A", label = "A" }),
								Facet.UI.Button({ id = "B", label = "B" }),
							},
						}),
					},
				}),
			},
		}))
		pres.refresh()
		local groups = focus_map.autoGroups(handle.root.node)
		expect(#groups).toBe(1)
		-- the stack's own children are the run; the scroller is a container
		expect(groups[1].axis).toBe("vertical")
	end)

	it("flat scopes keep the legacy ring semantics (navigate ±1, all wrap)", function()
		local graph = newGraph()
		graph.pushScope({ name = "flat", trap = false, order = { "/F/A", "/F/B" } })
		graph.navigate(1)
		expect(graph.focused:get()).toBe("/F/B")
		graph.navigate(1)
		expect(graph.focused:get()).toBe("/F/A") -- wraps
		graph.navigateDirection("down") -- directions map onto the ring for flat scopes
		expect(graph.focused:get()).toBe("/F/B")
	end)
end)
