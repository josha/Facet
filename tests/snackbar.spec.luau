--!strict
--[[ UI.Snackbar and app.presentSnackbar: one application service, one
	persistent bottom host. Every case drives the public app, the fake native
	target and a scripted frame clock, and asserts what is mounted. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local Facet = require("../src") :: any
local Compose = Facet.Compose
local fake = require("./lib/fake_target")
local world = require("./lib/world")

local HOST = "/FacetSnackbars"

local function app(opts: any?): any
	local o = opts or {}
	local adapter = fake.new()
	local now, frame = 0, nil
	local core: any = nil
	local system: any = nil
	local a = Facet.new({
		now = function()
			return now
		end,
		newAdapter = function()
			return adapter
		end,
		newInputSystem = function(value)
			core = value
			system = Facet.newActionSystem(value)
			return system
		end,
		keyboardNavigation = true,
		bindEnv = function(env)
			env:set("viewportRect", { x = 0, y = 0, w = o.w or 390, h = o.h or 844 })
			if o.env then
				for k, v in o.env do
					env:set(k, v)
				end
			end
			return function() end
		end,
		connectFrame = function(callback)
			frame = callback
			return function() end
		end,
	})
	world.own(a, adapter)
	local w = { app = a, adapter = adapter, core = core }
	function w.press(key: string)
		system.deviceKey(key, true)
		system.deviceKey(key, false)
	end
	function w.advance(seconds: number)
		for _ = 1, math.max(1, math.floor(seconds * 60 + 0.5)) do
			now += 1 / 60
			frame(1 / 60)
		end
	end
	function w.find(suffix: string): string?
		for _, path in adapter.paths() do
			if string.sub(path, -#suffix) == suffix then
				return path
			end
		end
		return nil
	end
	function w.rows(): number
		local n = 0
		for _, path in adapter.paths() do
			if string.match(path, "/Snack$") then
				n += 1
			end
		end
		return n
	end
	return w
end

-- a caller that accepts or refuses proposals and logs everything
local function caller(accept: boolean?): any
	local c = { shown = Compose.cell(false), changes = {}, dismissed = {} }
	c.onPresentedChange = function(next: boolean)
		table.insert(c.changes, next)
		if accept ~= false then
			c.shown:set(next)
		end
	end
	c.onDismiss = function(reason: string)
		table.insert(c.dismissed, reason)
	end
	return c
end

describe("Snackbar: the host", function()
	it("the first registration presents one persistent host, empty and reserving nothing", function()
		local w = app()
		w.advance(0.1)
		expect(w.adapter.node(HOST)).toBeNil() -- an app that never shows one carries nothing
		w.app.mount(function()
			return w.app.controls.Snackbar({ isPresented = false, message = "m", closeButton = false })
		end)
		w.advance(0.1)
		expect(w.adapter.node(HOST) ~= nil).toBe(true)
		expect(w.rows()).toBe(0)
		expect(#w.app.presenter.hudReservations:peek()).toBe(0)
		expect(w.app.presenter.focus.hasChromeScope()).toBe(false)
	end)
end)

describe("Snackbar: controlled presentation", function()
	it("shows a message when the caller's fact turns true, and close proposes", function()
		local w = app()
		local c = caller()
		w.app.mount(function()
			return w.app.controls.Snackbar("Saved")({
				isPresented = c.shown,
				message = "Saved to your garage",
				onPresentedChange = c.onPresentedChange,
				onDismiss = c.onDismiss,
			})
		end)
		w.advance(0.1)
		expect(w.rows()).toBe(0)
		c.shown:set(true)
		w.advance(0.5)
		expect(w.rows()).toBe(1)
		w.adapter.driveActivate(assert(w.find("/Snack/Row/Close"), "close"))
		w.advance(0.6)
		expect(c.changes).toEqual({ false })
		expect(c.dismissed).toEqual({ "close" })
		expect(w.rows()).toBe(0)
	end)
end)

-- mount one snackbar per caller, in one component
local function mountAll(w: any, list: { any }): () -> ()
	return w.app.mount(function()
		local UI = w.app.controls
		local nodes = {}
		for i, entry in list do
			local spec: any = {
				isPresented = entry.c.shown,
				message = entry.message or `Message {i}`,
				onPresentedChange = entry.c.onPresentedChange,
				onDismiss = entry.c.onDismiss,
			}
			for k, v in entry.spec or {} do
				spec[k] = v
			end
			table.insert(nodes, UI.Snackbar(`S{i}`)(spec))
		end
		return UI.Screen("Page")({
			UI.Button("Content")({ label = "Content" }),
			table.unpack(nodes),
		})
	end)
end

local function message(w: any): string?
	local path = w.find("/Snack/Row/Body/Message")
	return if path ~= nil then w.adapter.node(path).props.text else nil
end

describe("Snackbar: the six compositions and their widths", function()
	local noop = function() end
	local cases = {
		{ name = "message", spec = { closeButton = false }, constrained = false },
		{ name = "icon+message", spec = { closeButton = false, icon = "status.info" }, constrained = false },
		{
			name = "message+action",
			spec = { closeButton = false, action = { label = "Undo", onActivate = noop } },
			constrained = true,
		},
		{ name = "message+close", spec = {}, constrained = true },
		{
			name = "message+action+close",
			spec = { action = { label = "Undo", onActivate = noop } },
			constrained = true,
		},
		{
			name = "icon+message+action+close",
			spec = { icon = "status.info", action = { label = "Undo", onActivate = noop } },
			constrained = true,
		},
	}
	for _, case in cases do
		it(case.name, function()
			local w = app()
			local c = caller()
			c.shown:set(true)
			mountAll(w, { { c = c, message = "Saved", spec = case.spec } })
			w.advance(0.5)
			local snack = w.adapter.node(assert(w.find("/Snack"), "row"))
			expect(snack ~= nil).toBe(true)
			expect(w.find("/Snack/Row/Icon") ~= nil).toBe(case.spec.icon ~= nil)
			expect(w.find("/Snack/Row/Body/Action") ~= nil).toBe(case.spec.action ~= nil)
			expect(w.find("/Snack/Row/Close") ~= nil).toBe(case.spec.closeButton ~= false)
			local cap = math.min(480, 390 - 32)
			if case.constrained then
				expect(math.abs(snack.rect.w - cap) < 1).toBe(true)
			else
				expect(snack.rect.w < cap).toBe(true)
			end
			for _, path in { "/Snack/Row/Body/Action", "/Snack/Row/Close" } do
				local p = w.find(path)
				if p ~= nil then
					expect(w.adapter.node(p).rect.h >= 44).toBe(true)
				end
			end
		end)
	end
	it("long copy wraps and the action moves below it", function()
		local w = app()
		local c = caller()
		c.shown:set(true)
		mountAll(w, {
			{
				c = c,
				message = string.rep("Your garage is full; sell a kart to make room. ", 3),
				spec = { action = { label = "Open garage", onActivate = noop } },
			},
		})
		w.advance(0.5)
		local msg = w.adapter.node(assert(w.find("/Snack/Row/Body/Message"), "msg")).rect
		local act = w.adapter.node(assert(w.find("/Snack/Row/Body/Action"), "act")).rect
		expect(act.y >= msg.y + msg.h - 0.5).toBe(true)
	end)
end)

describe("Snackbar: proposals and reasons", function()
	it("an action runs once and leaves the row mounted; closing inside it reports action", function()
		local w = app()
		local c = caller()
		local runs = 0
		local closeIt = false
		c.shown:set(true)
		mountAll(w, {
			{
				c = c,
				spec = {
					action = {
						label = "Undo",
						onActivate = function()
							runs += 1
							if closeIt then
								c.shown:set(false)
							end
						end,
					},
				},
			},
		})
		w.advance(0.5)
		w.adapter.driveActivate(assert(w.find("/Snack/Row/Body/Action"), "action"))
		w.advance(0.3)
		expect(runs).toBe(1)
		expect(w.rows()).toBe(1)
		expect(#c.dismissed).toBe(0)
		closeIt = true
		w.adapter.driveActivate(assert(w.find("/Snack/Row/Body/Action"), "action"))
		w.advance(0.6)
		expect(runs).toBe(2)
		expect(c.dismissed).toEqual({ "action" })
		expect(w.rows()).toBe(0)
	end)

	it("a refused close keeps the same row and reports nothing", function()
		local w = app()
		local c = caller(false)
		c.shown:set(true)
		mountAll(w, { { c = c } })
		w.advance(0.5)
		local before = w.find("/Snack")
		w.adapter.driveActivate(assert(w.find("/Snack/Row/Close"), "close"))
		w.advance(0.5)
		expect(c.changes).toEqual({ false })
		expect(w.find("/Snack")).toBe(before)
		expect(#c.dismissed).toBe(0)
	end)

	it("a timeout asks once at max(duration, 2.5 s) of readable time; a refusal makes it persistent", function()
		local w = app()
		local c = caller(false)
		c.shown:set(true)
		mountAll(w, { { c = c, spec = { duration = 1 } } })
		w.advance(2.2)
		expect(#c.changes).toBe(0)
		w.advance(0.6)
		expect(c.changes).toEqual({ false })
		w.advance(10)
		expect(c.changes).toEqual({ false })
		expect(w.rows()).toBe(1)
	end)

	it("an accepted timeout retires with reason timeout; nil duration never expires", function()
		local w = app()
		local a, b = caller(), caller()
		a.shown:set(true)
		mountAll(w, { { c = a, spec = { duration = 3 } } })
		w.advance(3.3)
		expect(a.dismissed).toEqual({ "timeout" })
		local w2 = app()
		b.shown:set(true)
		mountAll(w2, { { c = b } })
		w2.advance(60)
		expect(w2.rows()).toBe(1)
		expect(#b.changes).toBe(0)
	end)

	it("hover and focus pause the dwell; queued time never counts", function()
		local w = app()
		local a, b = caller(), caller()
		a.shown:set(true)
		b.shown:set(true)
		mountAll(w, { { c = a, spec = { duration = 3 } }, { c = b, spec = { duration = 3 } } })
		w.advance(0.5)
		local snack = assert(w.find("/Snack"), "row")
		w.adapter.hover(snack)
		w.advance(5)
		expect(#a.changes).toBe(0)
		w.adapter.unhover(snack)
		w.advance(3)
		expect(a.dismissed).toEqual({ "timeout" })
		w.advance(0.5)
		expect(message(w)).toBe("Message 2")
		w.advance(2)
		expect(#b.changes).toBe(0) -- its own dwell began when it showed
		w.advance(1)
		expect(b.dismissed).toEqual({ "timeout" })
	end)

	it("equal priority waits in order; a higher one supersedes after the floor, once", function()
		local w = app()
		local low, same, high = caller(false), caller(), caller()
		low.shown:set(true)
		same.shown:set(true)
		mountAll(w, {
			{ c = low, message = "low" },
			{ c = same, message = "same" },
			{ c = high, message = "high", spec = { priority = 5 } },
		})
		w.advance(0.5)
		high.shown:set(true)
		w.advance(1)
		expect(#low.changes).toBe(0)
		w.advance(1.5)
		expect(low.changes).toEqual({ false }) -- asked once, refused
		w.advance(5)
		expect(low.changes).toEqual({ false })
		expect(message(w)).toBe("low")
		low.shown:set(false) -- the caller closes it itself
		w.advance(0.6)
		expect(low.dismissed).toEqual({ "close" })
		expect(message(w)).toBe("high")
	end)

	it("an accepted supersession reports superseded", function()
		local w = app()
		local low, high = caller(), caller()
		low.shown:set(true)
		mountAll(w, { { c = low, message = "low" }, { c = high, message = "high", spec = { priority = 1 } } })
		w.advance(0.5)
		high.shown:set(true)
		w.advance(3)
		expect(low.dismissed).toEqual({ "superseded" })
		w.advance(0.6)
		expect(message(w)).toBe("high")
	end)

	it("the caller's false while queued removes it and reports close once", function()
		local w = app()
		local a, b = caller(), caller()
		a.shown:set(true)
		b.shown:set(true)
		mountAll(w, { { c = a }, { c = b } })
		w.advance(0.5)
		b.shown:set(false)
		w.advance(0.1)
		expect(b.dismissed).toEqual({ "close" })
		a.shown:set(false)
		w.advance(0.6)
		expect(w.rows()).toBe(0)
		expect(b.dismissed).toEqual({ "close" })
	end)
end)

describe("Snackbar: admission and lifetime", function()
	it("the tenth admission is refused at construction, and capacity recovers", function()
		local w = app()
		local list = {}
		for _ = 1, 9 do
			local c = caller()
			c.shown:set(true)
			table.insert(list, { c = c })
		end
		mountAll(w, list)
		w.advance(0.5)
		local extra = caller()
		extra.shown:set(true)
		local ok, err = pcall(function()
			w.app.presentSnackbar({
				isPresented = extra.shown,
				message = "one too many",
				onPresentedChange = extra.onPresentedChange,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "queue is full", 1, true) ~= nil).toBe(true)
		list[5].c.shown:set(false) -- a queued one leaves: nothing painted, capacity returns
		w.advance(0.1)
		local release = w.app.presentSnackbar({
			isPresented = extra.shown,
			message = "fits now",
			onPresentedChange = extra.onPresentedChange,
		})
		expect(type(release)).toBe("function")
		release()
		release()
	end)

	it("forced teardown never asks and never reports", function()
		local w = app()
		local c = caller()
		c.shown:set(true)
		local close = mountAll(w, { { c = c } })
		w.advance(0.5)
		expect(w.rows()).toBe(1)
		close()
		w.advance(0.6)
		expect(#c.changes).toBe(0)
		expect(#c.dismissed).toBe(0)
		expect(w.rows()).toBe(0)
		local d = caller()
		d.shown:set(true)
		local release = w.app.presentSnackbar({
			isPresented = d.shown,
			message = "imperative",
			onPresentedChange = d.onPresentedChange,
			onDismiss = d.onDismiss,
		})
		w.advance(0.5)
		expect(w.rows()).toBe(1)
		release()
		w.advance(0.6)
		expect(#d.dismissed).toBe(0)
		expect(w.rows()).toBe(0)
		w.app.dispose()
	end)

	it("two applications are independent", function()
		local w1, w2 = app(), app()
		local a, b = caller(), caller()
		a.shown:set(true)
		b.shown:set(true)
		mountAll(w1, { { c = a } })
		mountAll(w2, { { c = b } })
		w1.advance(0.5)
		w2.advance(0.5)
		w1.app.dispose()
		w2.advance(0.5)
		expect(w2.rows()).toBe(1)
		expect(#b.dismissed).toBe(0)
	end)

	it("a visible row reserves its bottom rectangle, and releases it after", function()
		local w = app()
		local c = caller()
		c.shown:set(true)
		mountAll(w, { { c = c } })
		w.advance(0.5)
		local list = w.app.presenter.hudReservations:peek()
		expect(#list).toBe(1)
		expect(list[1].edge).toBe("bottom")
		local snack = w.adapter.node(assert(w.find("/Snack"), "row")).rect
		expect(math.abs(list[1].rect.y - snack.y) < 1).toBe(true)
		c.shown:set(false)
		w.advance(1)
		expect(#w.app.presenter.hudReservations:peek()).toBe(0)
	end)

	it("a modal blocks the dwell until it closes", function()
		local w = app()
		local c = caller()
		c.shown:set(true)
		mountAll(w, { { c = c, spec = { duration = 3 } } })
		w.advance(0.5)
		local closeModal = w.app.presentModal(function()
			return w.app.controls.Screen("Modal")({ w.app.controls.Button("Ok")({ label = "OK" }) })
		end)
		w.advance(6)
		expect(#c.changes).toBe(0)
		closeModal()
		w.advance(3.2)
		expect(c.dismissed).toEqual({ "timeout" })
	end)

	it("refuses a malformed spec before registering", function()
		local w = app()
		for _, bad in
			{
				{ message = "m", closeButton = false },
				{ isPresented = true, closeButton = false },
				{ isPresented = true, message = "m" }, -- close button without a proposal
				{ isPresented = true, message = "m", closeButton = false, duration = 3 },
				{ isPresented = true, message = "m", closeButton = false, duration = -1 },
				{ isPresented = true, message = "m", closeButton = false, priority = math.huge },
				{ isPresented = true, message = "m", closeButton = false, title = "t" },
				{ isPresented = true, message = "m", closeButton = false, action = { label = "x" } },
			}
		do
			expect(pcall(function()
				w.app.presentSnackbar(bad)
			end)).toBe(false)
		end
	end)
end)

describe("Snackbar: focus and input", function()
	local function focused(w: any): string?
		return w.app.presenter.focus.focused:peek()
	end
	it("arrival never steals focus; the row is reached last and Cancel returns to content even when refused", function()
		local w = app()
		local c = caller(false)
		mountAll(w, { { c = c, spec = { action = { label = "Undo", onActivate = function() end } } } })
		w.advance(0.3)
		w.app.presenter.focus.focusOn("/Page/Content")
		c.shown:set(true)
		w.advance(0.5)
		expect(focused(w)).toBe("/Page/Content")
		w.press("DPadDown")
		local at = focused(w)
		expect(at ~= nil and string.find(at, "/Snack/", 1, true) ~= nil).toBe(true)
		w.press("ButtonB")
		expect(c.changes).toEqual({ false }) -- proposed, refused
		expect(focused(w)).toBe("/Page/Content")
		expect(w.rows()).toBe(1)
	end)

	it("accepted removal of the focused row puts focus back on the content", function()
		local w = app()
		local c = caller()
		mountAll(w, { { c = c } })
		w.advance(0.3)
		w.app.presenter.focus.focusOn("/Page/Content")
		c.shown:set(true)
		w.advance(0.5)
		w.press("DPadDown")
		expect(string.find(tostring(focused(w)), "/Snack/", 1, true) ~= nil).toBe(true)
		w.press("ButtonA") -- Close
		w.advance(0.6)
		expect(c.dismissed).toEqual({ "close" })
		expect(focused(w)).toBe("/Page/Content")
	end)

	it("an empty host binds no horizontal arrows on the content screen", function()
		local w = app()
		local c = caller()
		mountAll(w, { { c = c } })
		w.advance(0.3)
		expect(w.app.presenter.focus.hasChromeScope()).toBe(false)
		c.shown:set(true)
		w.advance(0.3)
		expect(w.app.presenter.focus.hasChromeScope()).toBe(true)
		c.shown:set(false)
		w.advance(1)
		expect(w.app.presenter.focus.hasChromeScope()).toBe(false)
	end)
	it("a pointer press on the action does not leave the passive host engaged", function()
		local w = app()
		local c = caller()
		local runs = 0
		c.shown:set(true)
		mountAll(w, {
			{
				c = c,
				spec = {
					action = {
						label = "Undo",
						onActivate = function()
							runs += 1
						end,
					},
				},
			},
		})
		w.advance(0.5)
		w.adapter.tap(assert(w.find("/Snack/Row/Body/Action"), "action"))
		w.advance(0.3)
		expect(runs).toBe(1)
		expect(w.app.presenter.exclusiveSurfaceActive:peek()).toBe(false)
		expect(w.rows()).toBe(1)
	end)
end)

describe("Snackbar: the Status showcase", function()
	it("the showcase buttons present through the same service; a burst is capped, never dropped silently", function()
		local scenarioCtx = require("./lib/scenario_ctx")
		local w = world.new({ overflowGuardOff = "the snackbar host is presented over the page on purpose" })
		local built = require("../examples/gallery/scenarios/status_family").build(scenarioCtx.of(w))
		w.present(built.screen, built.present)
		w.settle(3)
		local function tap(suffix: string)
			for _, path in w.adapter.paths() do
				if string.sub(path, -#suffix) == suffix then
					w.adapter.tap(path)
					w.settle(3)
					return
				end
			end
			error(`no {suffix}`)
		end
		tap("/SnackAll")
		local rows = 0
		for _, path in w.adapter.paths() do
			if string.match(path, "/Snack$") then
				rows += 1
			end
		end
		expect(rows).toBe(1)
		tap("/SnackBurst")
		local last
		for _, path in w.adapter.paths() do
			if string.sub(path, -5) == "/Last" then
				last = w.adapter.node(path).props.text
			end
		end
		expect(last).toBe("Last: refused — the snackbar queue is full")
		built.reset()
		w.settle(3)
	end)
end)
