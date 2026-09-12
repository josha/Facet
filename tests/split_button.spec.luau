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

--[[ THE FOCUS STOPS UNDER A PREFIX, read off the ring the presenter actually
	walks. `focusable` is a SEMANTIC-channel prop the adapter never records, so
	counting nodes whose props say so is the check that cannot fail
	(`level_picker.spec`'s own note). ]]
local function focusStopsIn(handle: any, prefix: string): { string }
	local out: { string } = {}
	for _, entry in handle.focusOrder().traversal do
		if string.find(entry.path, prefix, 1, true) == 1 then
			table.insert(out, entry.path)
		end
	end
	table.sort(out)
	return out
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

	--[[ THE MENU HINT (user review, 2026-09-12: *"nothing shows a menu exists"*).
		The long press is the only way in on this form and a long press is
		invisible, so the button carries a trailing chevron. The whole point is that
		it is a HINT and not a second cell: one focus stop, one activation, and the
		gesture that opens the menu is the one that always did. All four halves are
		asserted here, because "there is a chevron" and "it is still one control"
		fail in opposite directions. ]]
	t.it("touch: the single button SHOWS its menu — a trailing chevron hint, still one control", function()
		local w = world.new({ capabilities = { touch = true }, preferredInput = "Touch" })
		local calls = { n = 0 }
		local c = build(w, calls)
		local handle = w.present(Facet.UI.Screen({ id = "Root", children = { c.blueprint } }))
		t.expect(c.dump().form).toBe("single")
		-- ONE focus stop under the control, and it is the button itself
		t.expect(focusStopsIn(handle, "/Root/S/")).toEqual({ "/Root/S/Single/then/Primary" })
		-- ...whose TRAILING child is the icon hint, not a second button
		local hint = w.adapter.node("/Root/S/Single/then/Primary/Hint")
		local label = w.adapter.node("/Root/S/Single/then/Primary/Label")
		t.expect(hint ~= nil).toBe(true)
		t.expect(hint.decorationHint.icon).toBe("chevron.down")
		t.expect(hint.rect.x >= label.rect.x + label.rect.w).toBe(true)
		-- the WORDS are still the primary action's, drawn by the button's own
		-- content, so the control did not become "chevron" (a content Button draws
		-- no text of its own — B-BTN1 — which is why the label moved into a child)
		t.expect(label.props.text).toBe("Race")
		-- a tap is STILL the primary action, and the long press STILL opens the menu
		w.adapter.tap("/Root/S/Single/then/Primary", { inputType = "Touch" })
		w.tick(0)
		t.expect(calls.n).toBe(1)
		t.expect(c.dump().menu.open).toBe(false)
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
