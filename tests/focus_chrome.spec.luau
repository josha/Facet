--!strict
--[[ ADOPTED CHROME: the surface a directional press can leave its own scope for.

	=== THE GAP THIS CLOSES, AS MEASURED ===

	Every navigation verb in `focus_graph` reads `top()` — one scope, the last one
	pushed (`navigateDirection` :713, `navigate` :776, `traverse` :849). A second
	presented surface pushes its OWN scope, so its focusables sit in a buried ring
	that no key, no d-pad and no Tab can reach: they are pointer-only. That was
	already measured and pinned once from the other side, by the HUD paint probe's
	case "a second base surface's control is in NEITHER traversal ring".

	It cost the showcase its whole chrome. The demo-picker chip and the settings
	chip live on a strip presented BEFORE the demo — deliberately, so the demo owns
	Tab and the arrows — and the consequence nobody had measured is that a player
	holding only a gamepad could not reach either one. A d-pad pressed against the
	demo walked the demo's two-item ring forever (trail measured 2026-08-16:
	D2,D1,D2,D1,…), because a FLAT scope's ring wraps and a wrapping ring has no
	edge to fall off.

	=== THE CAPABILITY ===

	`presenter.present(bar, { focusChrome = "top" })` declares a surface to be the
	app's persistent frame. Its focusables are then ADOPTED into whatever scope is
	active: one composed focus map, with the chrome's own navigation groups placed
	at the named edge of the active scope's group array. Everything downstream is
	unchanged machinery — `exitFrom` walks the group array, `enterGroup` applies
	each group's entry policy, `traverse` reads the same members the arrows walk —
	which is what keeps Navigate and Traverse walking ONE map (constitution §9).

	Three properties this file exists to pin:

	  1. ADOPTION IS OPT-IN. A second base surface that does not declare
	     `focusChrome` is in NEITHER ring, exactly as before. A HUD that appears
	     unasked must not take the ring away from the screen underneath.
	  2. ENTRY BELONGS TO THE ACTIVE SCOPE. With nothing focused, the first Tab or
	     arrow lands in the CONTENT, never on the chrome — the chrome is somewhere
	     you navigate TO, not where you start.
	  3. A TRAP SUSPENDS IT. A modal covers the screen; its ring may not leak into
	     a strip the player can no longer see.

	And the seam the capability is useless without: ACTIVATING an adopted chip.
	Activate is dispatched against a surface handle, and a path that handle does
	not own resolves to no node at all — which is precisely how the chrome broke
	the last time focus reached it (`showcase_chrome.luau` §1). ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local UI = require("../src/blueprint")
local fake_target = require("./lib/fake_target")

local function world()
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 1200, h = 800 })
	env:set("capabilities", { touch = false, mouse = true, keyboard = true, gamepad = true })
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = LuauUI.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
	return { core = core, env = env, system = system, adapter = adapter, pres = pres }
end

-- the strip: one horizontal row of two chips, the shape the showcase's own bar has
local function bar(pressed: { string }): any
	return UI.Screen({
		id = "Bar",
		children = {
			UI.HStack({
				id = "Chips",
				gap = "s",
				children = {
					UI.Button({
						id = "Left",
						label = "Left",
						onActivate = function()
							table.insert(pressed, "Left")
						end,
					}),
					UI.Button({
						id = "Right",
						label = "Right",
						onActivate = function()
							table.insert(pressed, "Right")
						end,
					}),
				},
			}),
		},
	})
end

local function content(pressed: { string }): any
	return UI.Screen({
		id = "Content",
		gap = "s",
		children = {
			UI.Button({
				id = "A",
				label = "A",
				onActivate = function()
					table.insert(pressed, "A")
				end,
			}),
			UI.Button({ id = "B", label = "B" }),
		},
	})
end

-- present bar-then-content, the showcase's own order (the strip goes down first
-- so the demo above it owns the scope)
local function mounted(chromeEdge: string?): any
	local w = world()
	local pressed: { string } = {}
	local barHandle = w.pres.present(
		bar(pressed),
		if chromeEdge == nil then { responder = "passive" } else { responder = "passive", focusChrome = chromeEdge }
	)
	local contentHandle = w.pres.present(content(pressed))
	w.pres.refresh()
	return {
		w = w,
		pressed = pressed,
		barHandle = barHandle,
		contentHandle = contentHandle,
		focus = w.pres.focus,
		press = function(key: string)
			w.system.deviceKey(key, true)
			w.system.deviceKey(key, false)
		end,
	}
end

-- every path the composed map reports, in traversal order
local function traversalPaths(map: any): { string }
	local out: { string } = {}
	for _, entry in (map.traversal or {}) do
		table.insert(out, entry.path)
	end
	return out
end

local function has(list: { string }, want: string): boolean
	for _, v in list do
		if v == want then
			return true
		end
	end
	return false
end

describe("adopted chrome (1): the focus map is composed, and the arrows cross into it", function()
	it("without the declaration the chrome is in NEITHER ring — the measured gap, kept", function()
		local m = mounted(nil)
		local map = m.focus.focusMap()
		expect(has(traversalPaths(map), "/Bar/Chips/Left")).toBe(false)
		-- ...and no number of presses finds it either
		for _ = 1, 12 do
			m.press("DPadUp")
		end
		expect(m.focus.focused:get()).toBe("/Content/A")
	end)

	it("with `focusChrome` the ACTIVE scope's map carries the chrome's paths", function()
		local m = mounted("top")
		local map = m.focus.focusMap()
		-- the map still belongs to the content — adoption is not a takeover
		expect(map.scope).toBe("Content")
		expect(m.focus.activeScopeName()).toBe("Content")
		local paths = traversalPaths(map)
		expect(has(paths, "/Content/A")).toBe(true)
		expect(has(paths, "/Bar/Chips/Left")).toBe(true)
		expect(has(paths, "/Bar/Chips/Right")).toBe(true)
	end)

	it("a `top` chrome reads BEFORE the content, and its own group order survives", function()
		local m = mounted("top")
		expect(traversalPaths(m.focus.focusMap())).toEqual({
			"/Bar/Chips/Left",
			"/Bar/Chips/Right",
			"/Content/A",
			"/Content/B",
		})
	end)

	it("a `bottom` chrome reads AFTER it", function()
		local m = mounted("bottom")
		expect(traversalPaths(m.focus.focusMap())).toEqual({
			"/Content/A",
			"/Content/B",
			"/Bar/Chips/Left",
			"/Bar/Chips/Right",
		})
	end)

	it("`leading` and `trailing` are the horizontal spellings of the same two placements", function()
		expect(traversalPaths(mounted("leading").focus.focusMap())[1]).toBe("/Bar/Chips/Left")
		expect(traversalPaths(mounted("trailing").focus.focusMap())[1]).toBe("/Content/A")
	end)

	it("THE D-PAD CROSSES: up from the first content row lands on the strip", function()
		local m = mounted("top")
		expect(m.focus.focused:get()).toBe("/Content/A")
		m.press("DPadUp")
		expect(m.focus.focused:get()).toBe("/Bar/Chips/Left")
	end)

	it("...and the strip is a ROW, so left/right walk it and down returns to the content", function()
		local m = mounted("top")
		m.press("DPadUp")
		m.press("DPadRight")
		expect(m.focus.focused:get()).toBe("/Bar/Chips/Right")
		m.press("DPadDown")
		expect(m.focus.focused:get()).toBe("/Content/A")
	end)

	--[[ THE VERTICAL ARROW MEANS VERTICAL, EVEN STANDING ON A HORIZONTAL STRIP. A
		flat screen drives the direction-LESS `navigate(±1)`, which points itself at
		whichever axis the focused group can answer — sound while that group IS the
		whole scope, and wrong the moment a horizontal chrome sits inside a vertical
		screen. Measured before the fix: Down on the FIRST chip stepped sideways to
		the second, so a pad could get onto the strip and not off it. The case has to
		stand on chip ONE of TWO, because from the last chip a sideways step falls out
		of the row and lands in the content anyway — which passes while the defect is
		still there. ]]
	it("DOWN from the first of two chips LEAVES the strip; it does not step along it", function()
		local m = mounted("top")
		m.press("DPadUp")
		expect(m.focus.focused:get()).toBe("/Bar/Chips/Left")
		m.press("DPadDown")
		expect(m.focus.focused:get()).toBe("/Content/A")
	end)

	it("a `bottom` chrome is reached by pressing DOWN off the end instead", function()
		local m = mounted("bottom")
		m.press("DPadDown") -- A -> B
		expect(m.focus.focused:get()).toBe("/Content/B")
		m.press("DPadDown") -- off the end of the content, into the strip
		expect(m.focus.focused:get()).toBe("/Bar/Chips/Left")
	end)

	it("Tab walks the SAME members (§9: one focus map, two readings)", function()
		local m = mounted("top")
		local seen: { [string]: boolean } = {}
		for _ = 1, 8 do
			m.press("Tab")
			local f = m.focus.focused:get()
			if f ~= nil then
				seen[f] = true
			end
		end
		expect(seen["/Bar/Chips/Left"]).toBe(true)
		expect(seen["/Bar/Chips/Right"]).toBe(true)
		expect(seen["/Content/A"]).toBe(true)
		expect(seen["/Content/B"]).toBe(true)
	end)
end)

describe("adopted chrome (2): what adoption must NOT do", function()
	it("ENTRY is the active scope's, so the first press lands in the content", function()
		local m = mounted("top")
		-- the content pushed its scope last and took entry focus, ahead of a chrome
		-- that reads first in the composed order
		expect(m.focus.focused:get()).toBe("/Content/A")
		m.press("Tab")
		expect(m.focus.focused:get()).toBe("/Content/B")
	end)

	it("a MODAL suspends adoption: its ring cannot leak into the strip", function()
		local m = mounted("top")
		m.w.pres.presentModal(UI.Screen({
			id = "Sheet",
			children = { UI.Button({ id = "S1", label = "S1" }), UI.Button({ id = "S2", label = "S2" }) },
		}))
		m.w.pres.refresh()
		expect(has(traversalPaths(m.focus.focusMap()), "/Bar/Chips/Left")).toBe(false)
		for _ = 1, 10 do
			m.press("DPadUp")
		end
		expect(string.sub(tostring(m.focus.focused:get()), 1, 6)).toBe("/Sheet")
	end)

	it("dismissing the chrome takes its paths out of the composed map", function()
		local m = mounted("top")
		expect(has(traversalPaths(m.focus.focusMap()), "/Bar/Chips/Left")).toBe(true)
		m.w.pres.dismiss(m.barHandle)
		m.w.pres.refresh()
		expect(has(traversalPaths(m.focus.focusMap()), "/Bar/Chips/Left")).toBe(false)
	end)

	it("a chrome with nothing above it is simply the active scope, unchanged", function()
		local w = world()
		local pressed: { string } = {}
		-- non-passive, so this is the plain "one screen on the stack" case: a chrome
		-- declaration is not supposed to change what a surface does on its own
		w.pres.present(bar(pressed), { focusChrome = "top" })
		w.pres.refresh()
		expect(w.pres.focus.activeScopeName()).toBe("Bar")
		expect(w.pres.focus.focused:get()).toBe("/Bar/Chips/Left")
		w.system.deviceKey("DPadRight", true)
		w.system.deviceKey("DPadRight", false)
		expect(w.pres.focus.focused:get()).toBe("/Bar/Chips/Right")
	end)

	it("an edge nobody can place is refused, not silently ignored", function()
		local w = world()
		local ok = pcall(function()
			w.pres.present(bar({}), { focusChrome = "middle" })
		end)
		expect(ok).toBe(false)
	end)
end)

describe("adopted chrome (3): the press has to land on the chrome's OWN surface", function()
	it("Activate on an adopted chip runs the CHIP's handler, not nothing", function()
		local m = mounted("top")
		m.press("DPadUp")
		expect(m.focus.focused:get()).toBe("/Bar/Chips/Left")
		m.press("ButtonA")
		expect(m.pressed).toEqual({ "Left" })
	end)

	it("...and a press on the content still runs the content's own handler", function()
		local m = mounted("top")
		expect(m.focus.focused:get()).toBe("/Content/A")
		m.press("ButtonA")
		expect(m.pressed).toEqual({ "A" })
	end)

	it("one press is one activation, not one per surface that saw the key", function()
		local m = mounted("top")
		m.press("DPadUp")
		m.press("Return")
		expect(#m.pressed).toBe(1)
	end)
end)
