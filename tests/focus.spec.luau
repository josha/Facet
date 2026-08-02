--!strict
-- Modal focus restoration spike tests (design §9.3, UI-FOCUS-001): trap
-- wrapping, restoration after pop, nearest-surviving-neighbor on removal,
-- and focus identity independent of any engine object.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local focus_graph = require("../src/focus/focus_graph")

local function makeScreen()
	local core = customFactory.new()
	local graph = focus_graph.new(core)
	graph.pushScope({ name = "Settings", trap = false, order = { "Music", "Sfx", "Haptics", "Save" } })
	return core, graph
end

describe("logical focus", function()
	it("navigates the screen ring and wraps at the edges (director 2026-07-20)", function()
		-- hand-test finding: focus must CYCLE through a list — clamping at the
		-- ends reads as "focus went nowhere" (the old spike clamped non-traps)
		local _, graph = makeScreen()
		expect(graph.focused:get()).toBe("Music")
		graph.navigate(-1)
		expect(graph.focused:get()).toBe("Save") -- wraps backward
		graph.navigate(1)
		expect(graph.focused:get()).toBe("Music") -- and forward again
		graph.navigate(1)
		graph.navigate(1)
		graph.navigate(1)
		expect(graph.focused:get()).toBe("Save")
		graph.navigate(1)
		expect(graph.focused:get()).toBe("Music") -- wraps forward
	end)

	it("modal traps navigation with wrap and restores previous focus on pop", function()
		local _, graph = makeScreen()
		graph.navigate(1) -- focus Sfx
		expect(graph.focused:get()).toBe("Sfx")
		graph.pushScope({ name = "ConfirmReset", trap = true, order = { "Confirm", "Cancel" } })
		expect(graph.focused:get()).toBe("Confirm")
		expect(graph.activeScopeName()).toBe("ConfirmReset")
		-- wraps inside the modal, never escapes to the screen ring
		graph.navigate(1)
		expect(graph.focused:get()).toBe("Cancel")
		graph.navigate(1)
		expect(graph.focused:get()).toBe("Confirm")
		graph.navigate(-1)
		expect(graph.focused:get()).toBe("Cancel")
		-- pop restores the pre-modal focus exactly
		graph.popScope()
		expect(graph.focused:get()).toBe("Sfx")
		expect(graph.activeScopeName()).toBe("Settings")
	end)

	it("nested modals restore in LIFO order", function()
		local _, graph = makeScreen()
		graph.pushScope({ name = "ModalA", trap = true, order = { "A1", "A2" } })
		graph.navigate(1)
		expect(graph.focused:get()).toBe("A2")
		graph.pushScope({ name = "ModalB", trap = true, order = { "B1" } })
		expect(graph.focused:get()).toBe("B1")
		graph.popScope()
		expect(graph.focused:get()).toBe("A2")
		graph.popScope()
		expect(graph.focused:get()).toBe("Music")
	end)

	it("removing the focused item falls to the nearest surviving neighbor", function()
		local _, graph = makeScreen()
		graph.navigate(1) -- Sfx
		graph.remove("Sfx")
		expect(graph.focused:get()).toBe("Haptics") -- following item preferred
		graph.remove("Save")
		expect(graph.focused:get()).toBe("Haptics") -- unfocused removal: no move
		graph.navigate(1)
		expect(graph.focused:get()).toBe("Music") -- last -> wraps to the first
		graph.remove("Music")
		expect(graph.focused:get()).toBe("Haptics") -- fell back to the survivor
	end)

	it("focus changes are observable client-local state", function()
		local core, graph = makeScreen()
		local seen = {}
		core:observe(graph.focused, function(v)
			table.insert(seen, v)
		end)
		graph.navigate(1)
		graph.navigate(1)
		expect(#seen).toBe(2)
		expect(seen[2]).toBe("Haptics")
	end)
end)

--[[ THE ARGUMENT IS READ, NEVER CONSUMED (api-architecture-consistency F-14).
	`pushScope`/`replaceGroups` used to normalize the CALLER's tables in place:
	they rewrote `scope.order`, injected `_focusable`/`_lastFocus` into a public
	exported type, and every later `remove`/`setOrder`/`setGroupOrder` spliced the
	caller's own array. Three costs, all pinned below: a frozen literal — this
	library's own idiom for immutable data — was a hard error from inside the
	graph; one NavigationGroup literal reused across two surfaces shared a
	predicate map; and a caller reading its own array back after `remove` saw the
	graph's edits. The graph now normalizes into internal copies. ]]
describe("focus graph: the caller's tables are never written", function()
	it("a table.freeze'd flat scope pushes, navigates and removes without erroring", function()
		local core = customFactory.new()
		local graph = focus_graph.new(core)
		local order = table.freeze({ "A", "B", "C" })
		local scope = table.freeze({ name = "Frozen", trap = false, order = order })
		graph.pushScope(scope)
		expect(graph.focused:get()).toBe("A")
		graph.navigate(1)
		expect(graph.focused:get()).toBe("B")
		graph.remove("B")
		expect(graph.focused:get()).toBe("C")
		-- the caller's array is untouched: it still holds what it declared
		expect(#order).toBe(3)
		expect(order[2]).toBe("B")
		expect((scope :: any)._focusable).toBeNil()
	end)

	it("a table.freeze'd grouped scope pushes and navigates, groups included", function()
		local core = customFactory.new()
		local graph = focus_graph.new(core)
		local group = table.freeze({
			name = "rows",
			axis = "vertical",
			wrap = true,
			order = table.freeze({
				"R1",
				{
					id = "R2",
					focusable = function()
						return true
					end,
				},
				"R3",
			}),
		})
		local scope = table.freeze({ name = "Grouped", trap = false, groups = table.freeze({ group }) })
		graph.pushScope(scope)
		expect(graph.focused:get()).toBe("R1")
		graph.navigateDirection("down")
		expect(graph.focused:get()).toBe("R2")
		graph.remove("R2")
		expect(graph.focused:get()).toBe("R3")
		-- the caller's group is untouched: order still holds the ENTRY table it
		-- declared (not a normalized string), and no private field was injected
		expect(#group.order).toBe(3)
		expect(type(group.order[2])).toBe("table")
		expect((group :: any)._focusable).toBeNil()
	end)

	it("one NavigationGroup literal pushed onto two scopes does not share a predicate map", function()
		local core = customFactory.new()
		local graph = focus_graph.new(core)
		local shared = {
			name = "rows",
			axis = "vertical",
			order = { "X", "Y" },
		}
		graph.pushScope({ name = "First", trap = false, groups = { shared } })
		graph.pushScope({ name = "Second", trap = true, groups = { shared } })
		-- edit the SECOND scope's copy; the first scope must not see it
		graph.setGroupOrder("Second", "rows", { "X" })
		graph.popScope()
		expect(graph.focused:get()).toBe("X")
		graph.navigate(1)
		expect(graph.focused:get()).toBe("Y") -- First still has both rows
		expect(#shared.order).toBe(2) -- and the caller's literal is intact
	end)

	it("replaceGroups copies too: the caller's array survives a later remove", function()
		local core = customFactory.new()
		local graph = focus_graph.new(core)
		graph.pushScope({ name = "S", trap = false, order = { "A" } })
		local groups = table.freeze({
			table.freeze({ name = "g", axis = "vertical", order = table.freeze({ "G1", "G2" }) }),
		})
		graph.replaceGroups("S", groups)
		expect(graph.focused:get()).toBe("G1")
		graph.remove("G1")
		expect(graph.focused:get()).toBe("G2")
		expect(#groups[1].order).toBe(2)
	end)
end)
