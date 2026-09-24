--!strict
--[[ MIXED-EDGE CHROME and LIVE chrome participation. A bottom notification
	strip and a top app bar can both be adopted by one content screen: the order
	is top chrome, content, bottom chrome whatever order they were presented in.
	A chrome surface with nothing focusable takes no part at all, so an empty
	notification host does not bind the horizontal arrows on a flat screen; the
	binding follows the chrome's live entries both ways. Cancel on an adopted
	chrome row goes to the chrome's own surface, exactly once. ]]
local harness = require("./lib/harness")
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local Facet = require("../src") :: any
local Compose = Facet.Compose
local UI = harness.UI
local harnessWorld = require("./lib/harness_world")

local function world(): any
	return harnessWorld.new({
		viewport = { x = 0, y = 0, w = 1200, h = 800 },
		capabilities = { touch = false, mouse = true, keyboard = true, gamepad = true },
		presenterOpts = { keyboardNavigation = true },
	})
end

local function strip(id: string, names: { string }, extra: any?): any
	local buttons = {}
	for _, name in names do
		table.insert(buttons, UI.Button({ id = name, label = name }))
	end
	local row = UI.HStack({ id = "Row", gap = "s", children = buttons })
	return UI.Screen({ id = id, children = { if extra ~= nil then extra(row) else row } })
end

local function content(): any
	return UI.Screen({
		id = "Content",
		gap = "s",
		children = { UI.Button({ id = "A", label = "A" }), UI.Button({ id = "B", label = "B" }) },
	})
end

local function paths(w: any): { string }
	local out = {}
	for _, entry in w.pres.focus.focusMap().traversal or {} do
		table.insert(out, entry.path)
	end
	return out
end

local function navigateHBindings(handle: any): number
	for _, action in handle.context.actions do
		if action.name == "NavigateH" then
			return #action.bindings
		end
	end
	return -1
end

local ORDER = { "/Top/Row/T1", "/Top/Row/T2", "/Content/A", "/Content/B", "/Snack/Row/S1", "/Snack/Row/S2" }

describe("mixed-edge chrome", function()
	it("top, content, bottom — bottom chrome presented FIRST", function()
		local w = world()
		w.pres.present(strip("Snack", { "S1", "S2" }), { responder = "passive", focusChrome = "bottom" })
		w.pres.present(strip("Top", { "T1", "T2" }), { responder = "passive", focusChrome = "top" })
		w.pres.present(content())
		w.pres.refresh()
		expect(paths(w)).toEqual(ORDER)
		expect(w.pres.focus.focused:peek()).toBe("/Content/A")
	end)

	it("top, content, bottom — top chrome presented FIRST", function()
		local w = world()
		w.pres.present(strip("Top", { "T1", "T2" }), { responder = "passive", focusChrome = "top" })
		w.pres.present(strip("Snack", { "S1", "S2" }), { responder = "passive", focusChrome = "bottom" })
		w.pres.present(content())
		w.pres.refresh()
		expect(paths(w)).toEqual(ORDER)
	end)

	it("up from content enters the top strip, down off the end enters the bottom one, and back", function()
		local w = world()
		w.pres.present(strip("Snack", { "S1", "S2" }), { responder = "passive", focusChrome = "bottom" })
		w.pres.present(strip("Top", { "T1", "T2" }), { responder = "passive", focusChrome = "top" })
		w.pres.present(content())
		w.pres.refresh()
		w.press("DPadUp")
		expect(w.pres.focus.focused:peek()).toBe("/Top/Row/T1")
		w.press("DPadRight")
		expect(w.pres.focus.focused:peek()).toBe("/Top/Row/T2")
		w.press("DPadDown")
		expect(w.pres.focus.focused:peek()).toBe("/Content/A")
		w.press("DPadDown")
		w.press("DPadDown")
		expect(w.pres.focus.focused:peek()).toBe("/Snack/Row/S1")
		w.press("DPadRight")
		expect(w.pres.focus.focused:peek()).toBe("/Snack/Row/S2")
		w.press("DPadUp")
		expect(w.pres.focus.focused:peek()).toBe("/Content/B")
	end)

	it("Tab and Shift+Tab read the same composed order", function()
		local w = world()
		w.pres.present(strip("Snack", { "S1", "S2" }), { responder = "passive", focusChrome = "bottom" })
		w.pres.present(strip("Top", { "T1", "T2" }), { responder = "passive", focusChrome = "top" })
		w.pres.present(content())
		w.pres.refresh()
		local seen = {}
		for _ = 1, 4 do
			w.press("Tab")
			table.insert(seen, w.pres.focus.focused:peek())
		end
		expect(seen).toEqual({ "/Content/B", "/Snack/Row/S1", "/Snack/Row/S2", "/Top/Row/T1" })
	end)
end)

describe("live chrome participation", function()
	it("an EMPTY chrome host binds no horizontal arrows on a flat screen; entries bind and unbind them", function()
		local w = world()
		local show = Compose.cell(false)
		w.pres.present(
			strip("Snack", { "S1" }, function(row)
				return UI.When({
					id = "Gate",
					condition = show,
					thenView = function()
						return row
					end,
				})
			end),
			{ responder = "passive", focusChrome = "bottom", initialFocus = "none" }
		)
		local screen = w.pres.present(content())
		w.pres.refresh()
		expect(w.pres.focus.hasChromeScope()).toBe(false)
		expect(navigateHBindings(screen)).toBe(0)
		show:set(true)
		w.pres.refresh()
		expect(w.pres.focus.hasChromeScope()).toBe(true)
		expect(navigateHBindings(screen) > 0).toBe(true)
		expect(w.pres.focus.focused:peek()).toBe("/Content/A") -- arrival never steals
		show:set(false)
		w.pres.refresh()
		expect(navigateHBindings(screen)).toBe(0)
	end)

	it("a content screen presented while the host is empty upgrades when rows arrive", function()
		local w = world()
		local show = Compose.cell(false)
		w.pres.present(
			strip("Snack", { "S1", "S2" }, function(row)
				return UI.When({
					id = "Gate",
					condition = show,
					thenView = function()
						return row
					end,
				})
			end),
			{
				responder = "passive",
				focusChrome = "bottom",
				initialFocus = "none",
				-- a host that starts empty declares its grouping up front
				navigationGroups = require("../src/present/focus_map").autoGroups,
			}
		)
		w.pres.present(content())
		w.pres.refresh()
		show:set(true)
		w.pres.refresh()
		w.press("DPadDown")
		w.press("DPadDown")
		local at = w.pres.focus.focused:peek()
		expect(at).toBe("/Snack/Gate/then/Row/S1")
		w.press("DPadRight")
		expect(w.pres.focus.focused:peek()).toBe("/Snack/Gate/then/Row/S2")
	end)
end)

-- the arrow KEYS NavigateH holds (the Thumbstick axis is not an arrow)
local function navigateHKeys(handle: any): number
	local n = 0
	for _, action in handle.context.actions do
		if action.name == "NavigateH" then
			for _, b in action.bindings do
				if b.keyCode ~= nil then
					n += 1
				end
			end
		end
	end
	return n
end

describe("a focused horizontal value control and live chrome share one owner of the arrows", function()
	local function setup(): (any, any, any, { number })
		local w = world()
		local show = Compose.cell(false)
		w.pres.present(
			strip("Snack", { "S1" }, function(row)
				return UI.When({
					id = "Gate",
					condition = show,
					thenView = function()
						return row
					end,
				})
			end),
			{ responder = "passive", focusChrome = "bottom", initialFocus = "none" }
		)
		local hits: { number } = {}
		local adj = require("../src/input/contribution").attach(
			UI.VStack({ id = "Vol", children = { UI.Button({ id = "Knob", label = "Knob" }) } }),
			{
				adjustAxis = "horizontal",
				adjustTargets = function(): { [string]: boolean }
					return { ["/Content/Vol/Knob"] = true }
				end,
				handleAdjust = function(_path: string, dir: number): boolean
					table.insert(hits, dir)
					return true
				end,
			}
		)
		local screen =
			w.pres.present(UI.Screen({ id = "Content", children = { UI.Button({ id = "A", label = "A" }), adj } }))
		w.pres.refresh()
		return w, show, screen, hits
	end

	it("chrome leaving while the control is focused leaves no arrow on the flat screen", function()
		local w, show, screen = setup()
		show:set(true)
		w.pres.refresh()
		w.pres.focus.focusOn("/Content/Vol/Knob")
		w.pres.refresh()
		expect(navigateHKeys(screen)).toBe(0)
		show:set(false)
		w.pres.refresh()
		w.pres.focus.focusOn("/Content/A")
		w.pres.refresh()
		expect(navigateHKeys(screen)).toBe(0)
	end)

	it("chrome arriving while the control is focused leaves the arrows with the control", function()
		local w, show, screen, hits = setup()
		w.pres.focus.focusOn("/Content/Vol/Knob")
		w.pres.refresh()
		show:set(true)
		w.pres.refresh()
		expect(navigateHKeys(screen)).toBe(0)
		w.press("Right")
		expect(hits).toEqual({ 1 })
		expect(w.pres.focus.focused:peek()).toBe("/Content/Vol/Knob")
		w.pres.focus.focusOn("/Content/A")
		w.pres.refresh()
		expect(navigateHKeys(screen)).toBe(4)
	end)
end)

describe("Cancel on adopted chrome", function()
	it("goes to the chrome's own contribution exactly once", function()
		local w = world()
		local cancels = 0
		local contribution = require("../src/input/contribution")
		w.pres.present(
			strip("Snack", { "S1" }, function(row)
				return contribution.attach(UI.VStack({ id = "Owner", children = { row } }), {
					handleCancel = function(): boolean
						cancels += 1
						return true
					end,
				})
			end),
			{ responder = "passive", focusChrome = "bottom" }
		)
		w.pres.present(content())
		w.pres.refresh()
		w.press("DPadDown")
		w.press("DPadDown")
		expect(w.pres.focus.focused:peek()).toBe("/Snack/Owner/Row/S1")
		w.press("ButtonB")
		expect(cancels).toBe(1)
	end)
end)
