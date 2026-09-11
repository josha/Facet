--!strict
-- SplitButton — one control, two forms (picker round, 2026-09-11): the pointer
-- split (primary + chevron segment) and the touch single button whose long
-- press opens the same menu. Both drive the REAL paths: adapter taps, the
-- gesture stream, and the presenter's activation routing.
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local world = require("./lib/world")

local function build(w, calls)
	return Facet.Controls.SplitButton(w.core, {
		id = "S",
		label = "Race",
		onActivate = function()
			calls.n += 1
		end,
		items = { { id = "practice", label = "Practice", onSelect = function() end } },
	})
end

t.describe("SplitButton", function()
	t.it("pointer: primary activation and menu opening are separate focusable actions on ONE plate", function()
		local w = world.new({
			viewport = { x = 0, y = 0, w = 800, h = 600 },
			capabilities = { mouse = true, keyboard = true },
			preferredInput = "KeyboardAndMouse",
		})
		local calls = { n = 0 }
		local c = build(w, calls)
		w.present(Facet.UI.Screen({ id = "Root", children = { c.blueprint } }))
		t.expect(c.dump().form).toBe("split")
		w.adapter.tap("/Root/S/Split/then/Split/Primary")
		t.expect(calls.n).toBe(1)
		w.adapter.tap("/Root/S/Split/then/Split/Menu")
		w.tick(0)
		t.expect(c.dump().menu.open).toBe(true)
		t.expect(calls.n).toBe(1)
		-- the two segments meet edge to edge: no gap between the primary's
		-- trailing edge and the chevron segment's leading edge but the hairline
		local primary = w.adapter.node("/Root/S/Split/then/Split/Primary").rect
		local menu = w.adapter.node("/Root/S/Split/then/Split/Menu").rect
		t.expect(menu.x - (primary.x + primary.w) <= 2).toBe(true)
		c.dispose()
	end)

	t.it("touch: ONE button — a tap runs the action, and there is no chevron cell", function()
		local w = world.new({ capabilities = { touch = true }, preferredInput = "Touch" })
		local calls = { n = 0 }
		local c = build(w, calls)
		w.present(Facet.UI.Screen({ id = "Root", children = { c.blueprint } }))
		t.expect(c.dump().form).toBe("single")
		t.expect(w.adapter.node("/Root/S/Single/then/Primary") ~= nil).toBe(true)
		local menuCell = false
		for _, path in w.adapter.paths() do
			if string.sub(path, -5) == "/Menu" then
				menuCell = true
			end
		end
		t.expect(menuCell).toBe(false)
		w.adapter.tap("/Root/S/Single/then/Primary", { inputType = "Touch" })
		w.tick(0)
		t.expect(calls.n).toBe(1)
		t.expect(c.dump().menu.open).toBe(false)
		-- ...and the menu is still reachable: the long press opens it
		w.adapter.driveTouchGesture(
			"/Root/S/Single/then/Primary",
			{ kind = "longPress", state = "began", positions = {} }
		)
		w.tick(0)
		t.expect(c.dump().menu.open).toBe(true)
		t.expect(calls.n).toBe(1)
		c.dispose()
	end)

	t.it("a hybrid flips forms with the live interaction class", function()
		local w = world.new({
			viewport = { x = 0, y = 0, w = 1024, h = 768 },
			capabilities = { mouse = true, touch = true, keyboard = true },
			preferredInput = "KeyboardAndMouse",
		})
		local c = build(w, { n = 0 })
		w.present(Facet.UI.Screen({ id = "Root", children = { c.blueprint } }))
		t.expect(c.dump().form).toBe("split")
		w.env:set("preferredInput", "Touch")
		w.pres.refresh()
		t.expect(c.dump().form).toBe("single")
		t.expect(w.adapter.node("/Root/S/Single/then/Primary") ~= nil).toBe(true)
		c.dispose()
	end)
end)
