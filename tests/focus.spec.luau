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
