--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local overlay = require("./lib/overlay_world")
local reservations = require("../src/ui/reservations")
local Vector2 = require("@lune/roblox").Vector2

type Caller = {
	shown: any,
	changes: { boolean },
	dismissed: { string },
	onPresentedChange: (boolean) -> (),
	onDismiss: (string) -> (),
}

local function caller(accept: boolean?): Caller
	local c: Caller = {
		shown = Compose.cell(false),
		changes = {},
		dismissed = {},
		onPresentedChange = function() end,
		onDismiss = function() end,
	}
	c.onPresentedChange = function(nextValue: boolean)
		table.insert(c.changes, nextValue)
		if accept ~= false then
			c.shown:set(nextValue)
		end
	end
	c.onDismiss = function(reason: string)
		table.insert(c.dismissed, reason)
	end
	return c
end

type Entry = { c: Caller, message: string?, spec: { [string]: any }? }

local function mount(list: { Entry }, options: any?): any
	local o = options or {}
	local gate = Compose.cell(true)
	local w = overlay.new(function(UI, Host)
		return Host.Frame({
			Name = "Page",
			UI.Button "Content" { label = "Content" },
			Compose.show(gate, function()
				local nodes: { any } = {}
				for index, entry in list do
					local spec: any = {
						isPresented = entry.c.shown,
						message = entry.message or `Message {index}`,
						onPresentedChange = entry.c.onPresentedChange,
						onDismiss = entry.c.onDismiss,
					}
					for key, value in entry.spec or {} do
						spec[key] = value
					end
					table.insert(nodes, UI.Snackbar(`S{index}`)(spec))
				end
				return Host.Frame({ Name = "Holder", table.unpack(nodes) })
			end),
		})
	end, { size = o.size or Vector2.new(390, 844), reducedMotion = o.reducedMotion ~= false })
	w.gate = gate
	w.rows = function(): number
		return #w.findAll("Snack")
	end
	w.message = function(): string?
		local rows = w.findAll("Snack")
		local row = rows[#rows]
		local label = if row then overlay.find(row, "Message") else nil
		return if label then label.Text else nil
	end
	return w
end

local function frames(w: any, seconds: number)
	w.advance(seconds, math.max(1, math.floor(seconds * 60 + 0.5)))
end

local noop = function() end

t.describe("native Snackbar: presentation", function()
	t.it("a registration presents nothing and reserves nothing while its fact is false", function()
		local c = caller()
		local w = mount({ { c = c, spec = { closeButton = false, onPresentedChange = noop } } })
		t.expect(w.rows()).toBe(0)
		t.expect(w.screen:GetAttribute("FacetInsetBottom") or 0).toBe(0)
		t.expect(w.find("S1"):GetAttribute("SnackbarAdmitted")).toBe(false)
		w.stop()
	end)

	t.it("shows a message when the caller's fact turns true, and close proposes", function()
		local c = caller()
		local w = mount({ { c = c, message = "Saved to your garage" } })
		c.shown:set(true)
		t.expect(w.rows()).toBe(1)
		t.expect(w.message()).toBe("Saved to your garage")
		w.find("Close").Activated.fire()
		t.expect(c.changes).toEqual({ false })
		t.expect(c.dismissed).toEqual({ "close" })
		t.expect(w.rows()).toBe(0)
		w.stop()
	end)

	t.it("the six compositions pick their parts and widths", function()
		for _, case in
			{
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
			} :: { any }
		do
			local c = caller()
			c.shown:set(true)
			local w = mount({ { c = c, message = "Saved", spec = case.spec } })
			local row = w.find("Snack")
			t.expect(`{case.name} icon: {overlay.find(row, "Icon") ~= nil}`)
				.toBe(`{case.name} icon: {case.spec.icon ~= nil}`)
			t.expect(`{case.name} action: {overlay.find(row, "Action") ~= nil}`)
				.toBe(`{case.name} action: {case.spec.action ~= nil}`)
			t.expect(`{case.name} close: {overlay.find(row, "Close") ~= nil}`)
				.toBe(`{case.name} close: {case.spec.closeButton ~= false}`)
			overlay.find(row, "MessageMeasure").TextBounds = Vector2.new(48, 18)
			local cap = math.min(480, 390 - 32)
			if case.constrained then
				t.expect(`{case.name}: {row.Size.X.Offset}`).toBe(`{case.name}: {cap}`)
			else
				t.expect(row.Size.X.Offset < cap).toBe(true)
				t.expect(row.Size.X.Offset >= 48).toBe(true)
			end
			local close = overlay.find(row, "Close")
			if close then
				t.expect(close.Size.Y.Offset >= 44).toBe(true)
			end
			w.stop()
		end
	end)

	t.it("a plain row hugs a longer message up to the strip's width", function()
		local c = caller()
		c.shown:set(true)
		local w = mount({ { c = c, message = "Saved to your garage.", spec = { closeButton = false } } })
		local row = w.find("Snack")
		overlay.find(row, "MessageMeasure").TextBounds = Vector2.new(160, 18)
		t.expect(row.Size.X.Offset).toBe(160 + 16 + 2)
		overlay.find(row, "MessageMeasure").TextBounds = Vector2.new(900, 18)
		t.expect(row.Size.X.Offset).toBe(358)
		t.expect(overlay.find(row, "Message").TextWrapped).toBe(true)
		w.stop()
	end)

	t.it("long copy wraps and the action moves below it", function()
		local c = caller()
		c.shown:set(true)
		local w = mount({
			{
				c = c,
				message = "Your garage is full",
				spec = { action = { label = "Open garage", onActivate = noop } },
			},
		})
		local row = w.find("Snack")
		local layout = overlay.find(row, "Body"):FindFirstChildWhichIsA("UIListLayout")
		overlay.find(row, "Action").AbsoluteSize = Vector2.new(100, 44)
		overlay.find(row, "MessageMeasure").TextBounds = Vector2.new(120, 18)
		t.expect(layout.FillDirection).toBe(w.Enum.FillDirection.Horizontal)
		overlay.find(row, "MessageMeasure").TextBounds = Vector2.new(600, 18)
		t.expect(layout.FillDirection).toBe(w.Enum.FillDirection.Vertical)
		w.stop()
	end)

	t.it("the strip docks bottom-centre above base screens, and modals and callouts paint above it", function()
		local c = caller()
		c.shown:set(true)
		local w = mount({ { c = c } })
		local row = w.find("Snack")
		t.expect(row.AnchorPoint).toBe(w.Vector2.new(0.5, 1))
		t.expect(row.Position.X.Scale).toBe(0.5)
		t.expect(row.Position.Y.Scale).toBe(1)
		t.expect(row.Position.Y.Offset).toBe(-16)
		t.expect(row.ZIndex < 94).toBe(true)
		t.expect(row.ZIndex < 100).toBe(true)
		t.expect(w.find("DismissOutside")).toBeNil()
		w.stop()
	end)
end)

t.describe("native Snackbar: an art theme's panel carve", function()
	t.it("an art theme's frame carve holds the icon, copy and action inside the plate", function()
		local themes = require("../src/ui/themes")(Compose)
		local package = themes.neutralPackage()
		package.chrome = package.chrome or {}
		package.chrome.panel = { kind = "native", contentInsets = { left = 20, right = 24, top = 12, bottom = 14 } }
		local c = caller()
		c.shown:set(true)
		local gate = Compose.cell(true)
		local w = overlay.new(function(UI, Host)
			return Host.Frame({
				Compose.show(gate, function()
					return UI.Snackbar "S1" {
						isPresented = c.shown,
						message = "Offline",
						icon = "status.warning",
						closeButton = false,
						onPresentedChange = c.onPresentedChange,
					}
				end),
			})
		end, { theme = package, reducedMotion = true })
		local row = w.find("Snack")
		local padding = row:FindFirstChildWhichIsA("UIPadding")
		t.expect(padding.PaddingLeft.Offset).toBe(20)
		t.expect(padding.PaddingRight.Offset).toBe(24)
		t.expect(padding.PaddingTop.Offset).toBe(12)
		t.expect(padding.PaddingBottom.Offset).toBe(14)
		overlay.find(row, "MessageMeasure").TextBounds = Vector2.new(100, 18)
		t.expect(row.Size.X.Offset).toBe(100 + 20 + 24 + 20 + 8 + 2)
		w.stop()
	end)
end)

t.describe("native Snackbar: proposals and reasons", function()
	t.it("an action runs once and leaves the row mounted; closing inside it reports action", function()
		local c = caller()
		local runs, closeIt = 0, false
		c.shown:set(true)
		local w = mount({
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
		w.find("Action").Activated.fire()
		t.expect(runs).toBe(1)
		t.expect(w.rows()).toBe(1)
		t.expect(#c.dismissed).toBe(0)
		closeIt = true
		w.find("Action").Activated.fire()
		t.expect(runs).toBe(2)
		t.expect(c.dismissed).toEqual({ "action" })
		t.expect(w.rows()).toBe(0)
		w.stop()
	end)

	t.it("a refused close keeps the same row and reports nothing", function()
		local c = caller(false)
		c.shown:set(true)
		local w = mount({ { c = c } })
		local row = w.find("Snack")
		w.find("Close").Activated.fire()
		t.expect(c.changes).toEqual({ false })
		t.expect(w.find("Snack")).toBe(row)
		t.expect(#c.dismissed).toBe(0)
		w.stop()
	end)

	t.it("a timeout asks once at max(duration, 2.5 s) of readable time; a refusal makes it persistent", function()
		local c = caller(false)
		c.shown:set(true)
		local w = mount({ { c = c, spec = { duration = 1 } } })
		frames(w, 2.2)
		t.expect(#c.changes).toBe(0)
		frames(w, 0.6)
		t.expect(c.changes).toEqual({ false })
		frames(w, 10)
		t.expect(c.changes).toEqual({ false })
		t.expect(w.rows()).toBe(1)
		w.stop()
	end)

	t.it("an accepted timeout retires with reason timeout; nil duration never expires", function()
		local a = caller()
		a.shown:set(true)
		local w = mount({ { c = a, spec = { duration = 3 } } })
		frames(w, 3.3)
		t.expect(a.dismissed).toEqual({ "timeout" })
		w.stop()
		local b = caller()
		b.shown:set(true)
		local w2 = mount({ { c = b } })
		frames(w2, 60)
		t.expect(w2.rows()).toBe(1)
		t.expect(#b.changes).toBe(0)
		w2.stop()
	end)

	t.it("hover and focus pause the dwell; queued time never counts", function()
		local a, b = caller(), caller()
		a.shown:set(true)
		b.shown:set(true)
		local w = mount({ { c = a, spec = { duration = 3 } }, { c = b, spec = { duration = 3 } } })
		frames(w, 0.5)
		local row = w.find("Snack")
		row.GuiState = w.Enum.GuiState.Hover
		frames(w, 5)
		t.expect(#a.changes).toBe(0)
		row.GuiState = w.Enum.GuiState.Idle
		w.gui.SelectedObject = w.find("Close")
		frames(w, 5)
		t.expect(#a.changes).toBe(0)
		w.gui.SelectedObject = nil
		frames(w, 2.6)
		t.expect(a.dismissed).toEqual({ "timeout" })
		t.expect(w.message()).toBe("Message 2")
		frames(w, 2)
		t.expect(#b.changes).toBe(0)
		frames(w, 1.1)
		t.expect(b.dismissed).toEqual({ "timeout" })
		w.stop()
	end)

	t.it("equal priority waits in order; a higher one supersedes after the floor, once", function()
		local low, same, high = caller(false), caller(), caller()
		low.shown:set(true)
		same.shown:set(true)
		local w = mount({
			{ c = low, message = "low" },
			{ c = same, message = "same" },
			{ c = high, message = "high", spec = { priority = 5 } },
		})
		frames(w, 0.5)
		high.shown:set(true)
		frames(w, 1)
		t.expect(#low.changes).toBe(0)
		frames(w, 1.5)
		t.expect(low.changes).toEqual({ false })
		frames(w, 5)
		t.expect(low.changes).toEqual({ false })
		t.expect(w.message()).toBe("low")
		low.shown:set(false)
		t.expect(low.dismissed).toEqual({ "cancel" })
		t.expect(w.message()).toBe("high")
		w.stop()
	end)

	t.it("an accepted supersession reports superseded", function()
		local low, high = caller(), caller()
		low.shown:set(true)
		local w = mount({ { c = low, message = "low" }, { c = high, message = "high", spec = { priority = 1 } } })
		frames(w, 0.5)
		high.shown:set(true)
		frames(w, 3)
		t.expect(low.dismissed).toEqual({ "superseded" })
		t.expect(w.message()).toBe("high")
		w.stop()
	end)

	t.it("the caller's false while queued removes it and reports cancel once", function()
		local a, b = caller(), caller()
		a.shown:set(true)
		b.shown:set(true)
		local w = mount({ { c = a }, { c = b } })
		t.expect(w.find("S2"):GetAttribute("SnackbarQueued")).toBe(true)
		b.shown:set(false)
		t.expect(b.dismissed).toEqual({ "cancel" })
		t.expect(w.find("S2"):GetAttribute("SnackbarAdmitted")).toBe(false)
		a.shown:set(false)
		t.expect(w.rows()).toBe(0)
		t.expect(b.dismissed).toEqual({ "cancel" })
		w.stop()
	end)
end)

t.describe("native Snackbar: admission and lifetime", function()
	t.it("the tenth admission is refused at construction, and capacity recovers", function()
		local callers: { Caller } = {}
		local list: { Entry } = {}
		for index = 1, 9 do
			local c = caller()
			c.shown:set(true)
			callers[index] = c
			table.insert(list, { c = c })
		end
		local w = mount(list)
		local extra = caller()
		extra.shown:set(true)
		local ok, failure = pcall(function()
			w.runtime.mount(function()
				return w.UI.Snackbar "Tenth" {
					isPresented = extra.shown,
					message = "ten",
					onPresentedChange = extra.onPresentedChange,
				}
			end, w.screen)
		end)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(failure), "full", 1, true) ~= nil).toBe(true)
		t.expect(w.rows()).toBe(1)
		callers[2].shown:set(false)
		local stop = w.runtime.mount(function()
			return w.UI.Snackbar "Tenth" {
				isPresented = extra.shown,
				message = "ten",
				onPresentedChange = extra.onPresentedChange,
			}
		end, w.screen)
		stop()
		w.stop()
	end)

	t.it("owner teardown never asks and reports cancel once, like Dialog and Popover", function()
		local a = caller()
		a.shown:set(true)
		local w = mount({ { c = a } })
		w.gate:set(false)
		t.expect(#a.changes).toBe(0)
		t.expect(table.concat(a.dismissed, ",")).toBe("cancel")
		t.expect(w.rows()).toBe(0)
		w.stop()
	end)

	t.it("two worlds are independent", function()
		local a, b = caller(), caller()
		a.shown:set(true)
		b.shown:set(true)
		local one = mount({ { c = a, message = "one" } })
		local two = mount({ { c = b, message = "two" } })
		t.expect(one.message()).toBe("one")
		t.expect(two.message()).toBe("two")
		one.gate:set(false)
		t.expect(two.message()).toBe("two")
		t.expect(#b.dismissed).toBe(0)
		one.stop()
		two.stop()
	end)

	t.it("a visible row reserves its bottom rectangle, and releases it after it has slid out", function()
		local a = caller()
		a.shown:set(true)
		local w = mount({ { c = a } }, { reducedMotion = false })
		local row = w.find("Snack")
		row.AbsolutePosition = Vector2.new(16, 844 - 16 - 60)
		row.AbsoluteSize = Vector2.new(358, 60)
		t.expect(w.screen:GetAttribute("FacetInsetBottom")).toBe(76)
		a.shown:set(false)
		t.expect(w.find("Snack")).toBe(row)
		t.expect(w.screen:GetAttribute("FacetInsetBottom")).toBe(76)
		frames(w, 0.1)
		t.expect(w.find("Snack")).toBe(row)
		frames(w, 0.3)
		t.expect(w.find("Snack")).toBeNil()
		t.expect(w.screen:GetAttribute("FacetInsetBottom")).toBe(0)
		local token = {}
		reservations.set(w.screen, token, "bottom", 700, 60)
		t.expect(w.screen:GetAttribute("FacetInsetBottom")).toBe(844 - 700)
		reservations.clear(w.screen, token)
		t.expect(w.screen:GetAttribute("FacetInsetBottom")).toBe(0)
		w.stop()
	end)

	t.it("a modal blocks the dwell until it closes", function()
		local a = caller()
		a.shown:set(true)
		local modal = Compose.cell(false)
		local w = overlay.new(function(UI, Host)
			return Host.Frame({
				UI.Snackbar "S1" {
					isPresented = a.shown,
					message = "Saved",
					duration = 3,
					onPresentedChange = a.onPresentedChange,
					onDismiss = a.onDismiss,
				},
				UI.Alert { isPresented = modal, title = "Hold" },
			})
		end, { reducedMotion = true })
		modal:set(true)
		frames(w, 5)
		t.expect(#a.changes).toBe(0)
		modal:set(false)
		frames(w, 3.1)
		t.expect(a.dismissed).toEqual({ "timeout" })
		w.stop()
	end)

	t.it("refuses a malformed spec before registering", function()
		for index, bad in
			{
				{ message = "m" } :: any,
				{ isPresented = true, message = 4, closeButton = false },
				{ isPresented = true, message = "m", icon = "", closeButton = false },
				{ isPresented = true, message = "m", action = { label = "L" }, closeButton = false },
				{ isPresented = true, message = "m", closeButton = "no" },
				{ isPresented = true, message = "m" },
				{ isPresented = true, message = "m", closeButton = false, duration = 3 },
				{ isPresented = true, message = "m", closeButton = false, duration = -1, onPresentedChange = noop },
				{ isPresented = true, message = "m", closeButton = false, priority = 0 / 0 },
				{ isPresented = true, message = "m", closeButton = false, tone = "x" },
			}
		do
			local ok = pcall(function()
				overlay
					.new(function(UI)
						return UI.Snackbar(bad)
					end)
					.stop()
			end)
			t.expect(`case {index}: {ok}`).toBe(`case {index}: false`)
		end
	end)

	t.it("a construction that raises leaves nothing admitted behind it", function()
		local a = caller()
		a.shown:set(true)
		local w = mount({ { c = a } })
		local ok = pcall(function()
			w.runtime.mount(function()
				return w.UI.Snackbar "Broken" { isPresented = true, message = "x" }
			end, w.screen)
		end)
		t.expect(ok).toBe(false)
		a.shown:set(false)
		t.expect(w.rows()).toBe(0)
		w.stop()
	end)

	t.it("a throwing caller callback is raised, and the row stays consistent", function()
		local shown = Compose.cell(true)
		local w = overlay.new(function(UI)
			return UI.Snackbar "S1" {
				isPresented = shown,
				message = "Saved",
				onPresentedChange = function()
					error("proposal bug")
				end,
			}
		end, { reducedMotion = true })
		local ok, failure = pcall(w.find("Close").Activated.fire)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(failure), "proposal bug", 1, true) ~= nil).toBe(true)
		t.expect(#w.findAll("Snack")).toBe(1)
		shown:set(false)
		t.expect(#w.findAll("Snack")).toBe(0)
		w.stop()
	end)
end)

t.describe("native Snackbar: the schedule under re-entrant callbacks", function()
	t.it("callbacks may show and hide other rows during a retirement without a stale entry", function()
		local a, b, c = caller(), caller(), caller()
		a.onDismiss = function(reason: string)
			table.insert(a.dismissed, reason)
			b.shown:set(false)
			c.shown:set(true)
		end
		a.shown:set(true)
		b.shown:set(true)
		local w = mount({ { c = a, message = "a" }, { c = b, message = "b" }, { c = c, message = "c" } })
		t.expect(w.message()).toBe("a")
		w.find("Close").Activated.fire()
		t.expect(a.dismissed).toEqual({ "close" })
		t.expect(b.dismissed).toEqual({ "cancel" })
		t.expect(w.message()).toBe("c")
		t.expect(w.rows()).toBe(1)
		t.expect(w.find("S2"):GetAttribute("SnackbarAdmitted")).toBe(false)
		t.expect(w.find("S3"):GetAttribute("SnackbarVisible")).toBe(true)
		w.stop()
	end)

	t.it("a refused supersession keeps the contender queued and asks only once", function()
		local low, high = caller(false), caller()
		low.shown:set(true)
		local w = mount({ { c = low, message = "low" }, { c = high, message = "high", spec = { priority = 3 } } })
		high.shown:set(true)
		frames(w, 3)
		t.expect(low.changes).toEqual({ false })
		t.expect(w.find("S2"):GetAttribute("SnackbarQueued")).toBe(true)
		frames(w, 6)
		t.expect(low.changes).toEqual({ false })
		t.expect(w.find("S2"):GetAttribute("SnackbarQueued")).toBe(true)
		w.stop()
	end)
end)

t.describe("native Snackbar: focus and input", function()
	t.it(
		"arrival never steals focus; Cancel on a focused row returns focus to the content even when refused",
		function()
			local a = caller(false)
			local w = mount({ { c = a } })
			local content = w.find("Content")
			w.gui.SelectedObject = content
			a.shown:set(true)
			t.expect(w.gui.SelectedObject).toBe(content)
			w.gui.SelectedObject = w.find("Close")
			w.action("SnackbarCancel").Pressed.fire()
			t.expect(a.changes).toEqual({ false })
			t.expect(w.gui.SelectedObject).toBe(content)
			t.expect(w.rows()).toBe(1)
			w.stop()
		end
	)

	t.it("accepted removal of the focused row puts focus back on the content", function()
		local a = caller()
		local w = mount({ { c = a } })
		local content = w.find("Content")
		w.gui.SelectedObject = content
		a.shown:set(true)
		w.gui.SelectedObject = w.find("Close")
		w.find("Close").Activated.fire()
		t.expect(w.rows()).toBe(0)
		t.expect(w.gui.SelectedObject).toBe(content)
		w.stop()
	end)

	t.it("a pointer press on Close leaves no click-eating catcher behind", function()
		local a = caller()
		a.shown:set(true)
		local w = mount({ { c = a } })
		w.find("Close").Activated.fire()
		t.expect(w.find("DismissOutside")).toBeNil()
		t.expect(w.find("ModalBack")).toBeNil()
		w.stop()
	end)
end)
