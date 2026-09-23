--!strict
--[[ UI.Dialog — a caller-owned modal presentation with pinned header, hero,
	action label and actions around one scrolling body. Every case drives a real
	route (adapter.tap, deviceKey, the backdrop catcher) and asserts what is
	mounted and where. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local world = require("./lib/world")
local fake = require("./lib/fake_target")
local Facet = require("../src") :: any
local Compose = Facet.Compose

local PANEL = "/Confirm/Center/Panel"
local CLOSE = `{PANEL}/Header/Close`
local BODY = `{PANEL}/Body`

type Log = { changes: { boolean }, dismissed: { string }, pressed: { string } }

local function caller(accept: boolean?): (any, Log, (boolean) -> ())
	local open = Compose.cell(true)
	local log: Log = { changes = {}, dismissed = {}, pressed = {} }
	return open,
		log,
		function(next: boolean)
			table.insert(log.changes, next)
			if accept ~= false then
				open:set(next)
			end
		end
end

local function mount(spec: (UI: any, log: Log?) -> any, opts: any?): any
	local o = opts or {}
	local w = world.new({
		viewport = { x = 0, y = 0, w = o.w or 800, h = o.h or 600 },
		reducedMotion = true,
		newAdapter = function()
			local a = fake.new()
			a.scrollBarThickness = fake.SCROLL_BAR_RESERVE
			return a
		end,
	})
	if o.classes ~= nil then
		w.env:set("capabilities", o.classes.capabilities)
		w.env:set("preferredInput", o.classes.preferredInput)
	end
	local UI = w.UI
	w.present(function()
		return UI.Screen("S")({
			UI.Button("Opener")({ label = "Open" }),
			UI.Dialog("Confirm")(spec(UI)),
		})
	end)
	w.settle(2)
	return w
end

local function paragraphs(UI: any, n: number): any
	local lines = {}
	for i = 1, n do
		table.insert(
			lines,
			UI.Text(`P{i}`)({ text = `Paragraph {i} of the race rules, long enough to wrap.`, width = UI.fill() })
		)
	end
	return UI.VStack("Copy")({ width = UI.fill(), gap = "s", table.unpack(lines) })
end

local function standard(open: any, log: Log, change: any, extra: { [string]: any }?): (UI: any) -> any
	return function(UI)
		local spec: any = {
			isPresented = open,
			onPresentedChange = change,
			onDismiss = function(reason: string)
				table.insert(log.dismissed, reason)
			end,
			title = "Leave the race?",
			content = function()
				return UI.Text("Line")({ text = "Your lap will not count.", width = UI.fill() })
			end,
			actions = {
				{
					id = "Stay",
					label = "Stay",
					role = "cancel",
					onActivate = function()
						table.insert(log.pressed, "Stay")
					end,
				},
				{
					id = "Leave",
					label = "Leave",
					role = "default",
					onActivate = function()
						table.insert(log.pressed, "Leave")
					end,
				},
			},
		}
		for k, v in extra or {} do
			spec[k] = v
		end
		return spec
	end
end

local function actionPath(w: any, id: string): string
	for _, path in w.adapter.paths() do
		if string.match(path, `/Actions/Order/%[{id}%]/{id}$`) or string.match(path, `/Actions/Order/.-/{id}$`) then
			return path
		end
	end
	local seen = {}
	for _, path in w.adapter.paths() do
		if string.find(path, "Actions", 1, true) then
			table.insert(seen, path)
		end
	end
	error(`no action button {id} in {table.concat(seen, " ")}`)
end

describe("Dialog: the caller's fact decides", function()
	it("an accepted fact presents the panel with pinned title, body and actions", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change))
		expect(w.adapter.node(`{PANEL}/Header/Title`).props.text).toBe("Leave the race?")
		expect(w.adapter.node(`{BODY}/Line`) ~= nil).toBe(true)
		expect(w.adapter.node(actionPath(w, "Leave")) ~= nil).toBe(true)
		expect(w.record("Confirm").dump().presented).toBe(true)
	end)

	it("the close button proposes: refused keeps the same surface and focus, accepted reports close", function()
		local open, log, change = caller(false)
		local w = mount(standard(open, log, change))
		local panel = w.adapter.node(PANEL)
		w.pres.focus.setFocusOrigin("navigation")
		expect(w.pres.focus.focusOn(CLOSE)).toBe(true)
		w.press("Return")
		w.adapter.tap(CLOSE)
		w.settle(2)
		expect(w.adapter.node(PANEL) == panel).toBe(true)
		expect(w.pres.focus.focused:peek()).toBe(CLOSE)
		expect(log.changes[#log.changes]).toBe(false)
		local open2, log2, change2 = caller()
		local w2 = mount(standard(open2, log2, change2))
		w2.adapter.tap(CLOSE)
		w2.settle(2)
		expect(w2.adapter.node(PANEL)).toBeNil()
		expect(table.concat(log2.dismissed, ",")).toBe("close")
		expect(w2.pres.focus.focused:peek()).toBe("/S/Opener")
	end)

	it("Cancel runs an eligible cancel action first; without one it proposes cancel", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change))
		w.press("ButtonB")
		w.settle(2)
		expect(table.concat(log.pressed, ",")).toBe("Stay")
		-- the action decided nothing, so the dialog stays
		expect(w.adapter.node(PANEL) ~= nil).toBe(true)
		local open2, log2, change2 = caller()
		local w2 = mount(standard(open2, log2, change2, {
			actions = {
				{ id = "Stay", label = "Stay", role = "cancel", enabled = false, onActivate = function() end },
				{ id = "Leave", label = "Leave", onActivate = function() end },
			},
		}))
		w2.press("ButtonB")
		w2.settle(2)
		expect(w2.adapter.node(PANEL)).toBeNil()
		expect(table.concat(log2.dismissed, ",")).toBe("cancel")
	end)

	it("an action that accepts false during its callback closes with reason action", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change, {
			actions = {
				{
					id = "Leave",
					label = "Leave",
					role = "default",
					onActivate = function()
						open:set(false)
					end,
				},
			},
		}))
		w.adapter.tap(actionPath(w, "Leave"))
		w.settle(2)
		expect(w.adapter.node(PANEL)).toBeNil()
		expect(table.concat(log.dismissed, ",")).toBe("action")
	end)

	it("an action never closes by itself, and a throwing one leaves the bookkeeping sound", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change, {
			actions = {
				{
					id = "Boom",
					label = "Boom",
					onActivate = function()
						error("caller bug")
					end,
				},
			},
		}))
		w.adapter.tap(actionPath(w, "Boom"))
		w.settle(2)
		expect(w.adapter.node(PANEL) ~= nil).toBe(true)
		open:set(false)
		w.settle(2)
		expect(table.concat(log.dismissed, ",")).toBe("cancel")
	end)

	it("the backdrop proposes outside; with no callback and no close it only swallows", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change))
		w.adapter.tap(w.pres.topScrimPath() :: string, { x = 5, y = 5 })
		w.settle(2)
		expect(table.concat(log.dismissed, ",")).toBe("outside")
		local fact = Compose.cell(true)
		local w2 = mount(function(UI)
			return {
				isPresented = fact,
				closeButton = false,
				title = "Read this",
				content = function()
					return UI.Text("Line")({ text = "Body" })
				end,
			}
		end)
		w2.adapter.tap(w2.pres.topScrimPath() :: string, { x = 5, y = 5 })
		w2.press("ButtonB")
		w2.settle(2)
		expect(w2.adapter.node(PANEL) ~= nil).toBe(true)
		fact:set(false)
		w2.settle(2)
		expect(w2.adapter.node(PANEL)).toBeNil()
	end)

	it("Return fires the default action; a disabled or busy one cannot fire by any route", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change))
		w.press("Return")
		w.settle(1)
		expect(table.concat(log.pressed, ",")).toBe("Leave")
		local open2, log2, change2 = caller()
		local w2 = mount(standard(open2, log2, change2, {
			-- no close button, so no other control holds the ring when Return lands
			closeButton = false,
			actions = {
				{
					id = "Go",
					label = "Go",
					role = "default",
					busy = true,
					onActivate = function()
						table.insert(log2.pressed, "Go")
					end,
				},
				{
					id = "Stop",
					label = "Stop",
					role = "cancel",
					busy = true,
					onActivate = function()
						table.insert(log2.pressed, "Stop")
					end,
				},
			},
		}))
		w2.press("Return")
		w2.adapter.tap(actionPath(w2, "Go"))
		w2.settle(1)
		expect(#log2.pressed).toBe(0)
		-- a busy cancel is not eligible: Cancel falls back to the root proposal
		w2.press("ButtonB")
		w2.settle(2)
		expect(#log2.pressed).toBe(0)
		expect(table.concat(log2.dismissed, ",")).toBe("cancel")
	end)
end)

describe("Dialog: composition, layout and the height budget", function()
	it("title-only, body-only, hero-only, action-label-only and actions-only all present", function()
		for index, extra in
			{
				{ title = "Title" },
				{ content = true },
				{ hero = { image = "rbxassetid://75342910516929", aspectRatio = 2 } },
				{ actionLabel = "Pick one" },
				{ actions = { { id = "Ok", label = "Ok", onActivate = function() end } } },
			}
		do
			local w = mount(function(UI)
				local spec: any = { isPresented = Compose.cell(true), closeButton = false }
				for k, v in extra :: any do
					spec[k] = if k == "content"
						then function()
							return UI.Text("Line")({ text = "Body" })
						end
						else v
				end
				return spec
			end)
			expect(`case {index}: {w.adapter.node(PANEL) ~= nil}`).toBe(`case {index}: true`)
		end
	end)

	it("the spec is closed and malformed compositions are refused by name", function()
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 } })
		local UI = w.UI
		local open = Compose.cell(false)
		local noop = function() end
		for index, bad in
			{
				{ isPresented = open, closeButton = false },
				{ isPresented = open, closeButton = false, title = "", actionLabel = " ", actions = {} },
				{ isPresented = open, title = "T" },
				{ title = "T", closeButton = false },
				{ isPresented = open, closeButton = false, title = "T", width = "huge" },
				{ isPresented = open, closeButton = false, title = "T", actionLayout = "grid" },
				{
					isPresented = open,
					closeButton = false,
					actions = {
						{ id = "A", label = "A", role = "default", onActivate = noop },
						{ id = "B", label = "B", role = "default", onActivate = noop },
					},
				},
				{
					isPresented = open,
					closeButton = false,
					actions = {
						{ id = "A", label = "A", role = "cancel", onActivate = noop },
						{ id = "B", label = "B", role = "cancel", onActivate = noop },
					},
				},
				{ isPresented = open, closeButton = false, title = "T", hero = { image = "x" } },
				{ isPresented = open, closeButton = false, title = "T", extra = 1 },
			}
		do
			local ok = pcall(function()
				w.scoped(function()
					return UI.Dialog(bad :: any)
				end)
			end)
			expect(`case {index} refused: {not ok}`).toBe(`case {index} refused: true`)
		end
	end)

	it("a long body fits the room: pinned header, label and actions stay on screen while it scrolls", function()
		local open, log, change = caller()
		local ui: any = nil
		local w = mount(function(UI)
			ui = UI
			return standard(open, log, change, {
				actionLabel = "Choose carefully",
				content = function()
					return paragraphs(UI, 30)
				end,
			})(UI)
		end, { w = 800, h = 480 })
		local panel = w.adapter.node(PANEL).rect
		expect(panel.y >= 0 and panel.y + panel.h <= 480).toBe(true)
		local title = w.adapter.node(`{PANEL}/Header/Title`).rect
		local leave = w.adapter.node(actionPath(w, "Leave")).rect
		expect(leave.y + leave.h <= panel.y + panel.h + 1).toBe(true)
		local before = { title.y, leave.y }
		local body = w.adapter.node(BODY)
		expect(body.class).toBe("ScrollView")
		w.adapter.setScrollPosition(body, { x = 0, y = 200 })
		w.settle(2)
		expect(w.adapter.node(`{PANEL}/Header/Title`).rect.y).toBe(before[1])
		expect(w.adapter.node(actionPath(w, "Leave")).rect.y).toBe(before[2])
		local _ = ui
	end)

	it("the keyboard's occlusion takes its room from the budget", function()
		local open, log, change = caller()
		local w = mount(function(UI)
			return standard(open, log, change, {
				content = function()
					return paragraphs(UI, 30)
				end,
			})(UI)
		end, { w = 800, h = 600 })
		local tall = w.adapter.node(PANEL).rect.h
		w.env:set("keyboardOcclusionRect", { x = 0, y = 300, w = 800, h = 300 })
		w.settle(3)
		local short = w.adapter.node(PANEL).rect
		expect(short.h < tall).toBe(true)
		expect(short.y + short.h <= 300 + 1).toBe(true)
	end)

	it("automatic actions stack for three; an explicit row that cannot fit falls to the safe stack", function()
		local open, log, change = caller()
		local noop = function() end
		local w = mount(standard(open, log, change, {
			actions = {
				{ id = "A", label = "One", onActivate = noop },
				{ id = "B", label = "Two", onActivate = noop },
				{ id = "C", label = "Three", onActivate = noop },
			},
		}))
		local a, b = w.adapter.node(actionPath(w, "A")).rect, w.adapter.node(actionPath(w, "B")).rect
		expect(b.y > a.y).toBe(true)
		local long = string.rep("Withdraw from the championship ", 3)
		local w2 = mount(standard(open, log, change, {
			width = "narrow",
			actionLayout = "row",
			actions = {
				{ id = "A", label = long, onActivate = noop },
				{ id = "B", label = long, onActivate = noop },
			},
		}))
		local a2, b2 = w2.adapter.node(actionPath(w2, "A")).rect, w2.adapter.node(actionPath(w2, "B")).rect
		expect(b2.y > a2.y).toBe(true)
		local w3 = mount(standard(open, log, change, {
			actionLayout = "row",
			actions = {
				{ id = "A", label = "Yes", onActivate = noop },
				{ id = "B", label = "No", onActivate = noop },
			},
		}))
		local a3, b3 = w3.adapter.node(actionPath(w3, "A")).rect, w3.adapter.node(actionPath(w3, "B")).rect
		expect(b3.y).toBe(a3.y)
	end)

	it("the width presets resolve to theme ceilings inside the safe room", function()
		local widths: { [string]: number } = {}
		for _, preset in { "narrow", "automatic", "wide" } do
			local open, log, change = caller()
			local w = mount(function(UI)
				return standard(open, log, change, {
					width = preset,
					content = function()
						-- longer than every ceiling, so the preset is what bounds it
						return UI.Text("Long")({
							text = string.rep("Race rules and lap scoring. ", 20),
							width = UI.fill(),
						})
					end,
				})(UI)
			end, { w = 1200, h = 800 })
			widths[preset] = w.adapter.node(PANEL).rect.w
		end
		expect(widths.narrow < widths.automatic and widths.automatic < widths.wide).toBe(true)
		expect(widths.wide <= 1200).toBe(true)
	end)

	it("a bound title may start empty and fill in later, in the same presentation", function()
		local title = Compose.cell("")
		local w = mount(function(UI)
			return {
				isPresented = Compose.cell(true),
				closeButton = false,
				title = title,
				content = function()
					return UI.Text("Line")({ text = "Loading" })
				end,
			}
		end)
		local panel = w.adapter.node(PANEL)
		expect(w.adapter.visibleOf(`{PANEL}/Header/Title`)).toBe(false)
		title:set("Ready")
		w.settle(2)
		expect(w.adapter.visibleOf(`{PANEL}/Header/Title`)).toBe(true)
		expect(w.adapter.node(PANEL) == panel).toBe(true)
	end)
end)

describe("Dialog: a plain overflowing body is one pad stop that scrolls", function()
	local PAD = {
		capabilities = { keyboard = false, mouse = false, touch = false, gamepad = true },
		preferredInput = "Gamepad",
	}

	local function longDialog(extra: { [string]: any }?): any
		local open, log, change = caller()
		return mount(function(UI)
			return standard(open, log, change, extra and {
				contentSelectable = extra.contentSelectable,
				content = extra.content and function()
					return extra.content(UI)
				end or function()
					return paragraphs(UI, 30)
				end,
			} or {
				content = function()
					return paragraphs(UI, 30)
				end,
			})(UI)
		end, { w = 800, h = 480, classes = PAD })
	end

	local function press(w: any, key: string)
		w.press(key)
		w.settle(1)
	end

	it("the ring reaches the body, Down scrolls it to the end, and then moves on to the actions", function()
		local w = longDialog()
		local body = w.adapter.node(BODY)
		expect(w.pres.focus.focusOn(BODY)).toBe(true)
		local positions: { number } = {}
		for _ = 1, 20 do
			press(w, "Down")
			if w.pres.focus.focused:peek() ~= BODY then
				break
			end
			table.insert(positions, (body.scrollPosition or { y = 0 }).y)
		end
		expect(#positions > 1).toBe(true)
		expect(positions[#positions] > 0).toBe(true)
		expect(string.find(w.pres.focus.focused:peek() or "", "/Actions/", 1, true) ~= nil).toBe(true)
		-- and Up comes back into the body, scrolling toward the top before leaving it
		press(w, "Up")
		expect(w.pres.focus.focused:peek()).toBe(BODY)
		local before = (body.scrollPosition or { y = 0 }).y
		press(w, "Up")
		expect((body.scrollPosition or { y = 0 }).y < before).toBe(true)
	end)

	it("a body that fits offers no stop, and contentSelectable = false never does", function()
		local w = longDialog({
			content = function(UI)
				return UI.Text("Short")({ text = "Short copy." })
			end,
		})
		expect(w.pres.focus.focusOn(BODY)).toBe(false)
		local w2 = longDialog({ contentSelectable = false })
		expect(w2.pres.focus.focusOn(BODY)).toBe(false)
	end)

	it("interactive content keeps its own stops inside the body", function()
		local w = longDialog({
			content = function(UI)
				return UI.VStack("Copy")({
					width = UI.fill(),
					gap = "s",
					UI.Button("First")({ label = "First" }),
					paragraphs(UI, 30),
					UI.Button("Last")({ label = "Last" }),
				})
			end,
		})
		expect(w.pres.focus.focusOn(`{BODY}/Copy/First`)).toBe(true)
		expect(w.pres.focus.focusOn(`{BODY}/Copy/Last`)).toBe(true)
	end)
end)

describe("Dialog: lifetime", function()
	it("owner disposal releases physically and reports cancel once; reopen cycles return to baseline", function()
		local open, log, change = caller()
		local present = Compose.cell(true)
		local w = world.new({ viewport = { x = 0, y = 0, w = 800, h = 600 }, reducedMotion = true })
		local UI = w.UI
		w.present(function()
			return UI.Screen("S")({
				UI.When("Gate")({
					condition = present,
					thenView = function()
						return UI.Dialog("Confirm")(standard(open, log, change)(UI))
					end,
				}),
			})
		end)
		w.settle(2)
		local depth = w.pres.depth()
		for _ = 1, 3 do
			open:set(false)
			w.settle(2)
			expect(w.pres.depth()).toBe(depth - 1)
			open:set(true)
			w.settle(2)
			expect(w.pres.depth()).toBe(depth)
		end
		log.dismissed = {}
		present:set(false)
		w.settle(2)
		expect(w.adapter.node(PANEL)).toBeNil()
		expect(table.concat(log.dismissed, ",")).toBe("cancel")
	end)
end)
