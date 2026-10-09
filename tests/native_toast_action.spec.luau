--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

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

	local noop = function() end
	local UNDO = { label = "Undo", onActivate = noop }

	local function mount(list: { Entry }, options: any?): any
		local o = options or {}
		local gate = Compose.cell(true)
		local w = overlay.new(
			function(UI: FacetControls, Host: RobloxHost)
				return Host.Frame({
					Name = "Page",
					UI.Button "Content" { label = "Content" } :: unknown,
					Compose.show(gate, function()
						local nodes: { any } = {}
						for index, entry in list do
							local spec: any = {
								isPresented = entry.c.shown,
								message = entry.message or `Message {index}`,
								onPresentedChange = entry.c.onPresentedChange,
								onDismiss = entry.c.onDismiss,
								action = UNDO,
							}
							for key, value in (entry.spec or {} :: { [string]: any }) do
								spec[key] = value
							end
							table.insert(nodes, UI.Toast(`S{index}`)(spec))
						end
						return Host.Frame({ Name = "Holder", table.unpack((nodes :: unknown) :: { unknown }) })
					end),
				})
			end,
			{ size = o.size or Vector2.new(390, 844), motionLevel = o.motionLevel or "none", runService = o.runService }
		)
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

	verifyHarness:suite("native Toast with an action: presentation", function()
		verifyHarness:case(
			"does not read a disposed presentation formula after its timeout callback removes the page",
			{
				id = "native_toast_action::native Toast with an action: presentation::does not read a disposed presentation formula after its timeout callback removes the page",
				run = function()
					local page, asked, dismissed = Compose.cell(true), 0, 0
					local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame {
							Compose.show(page, function()
								local presented = Compose.formula(function(use: Use)
									return use(page)
								end)
								return UI.Toast {
									message = "Saved",
									isPresented = presented,
									duration = 0.1,
									onPresentedChange = function(value: boolean)
										Verify.expect(value):toBe(false)
										asked += 1
										page:set(false)
									end,
									onDismiss = function()
										dismissed += 1
									end,
								}
							end),
						}
					end)
					frames(w, 1)
					Verify.expect(asked):toBe(1)
					Verify.expect(dismissed):toBe(1)
					frames(w, 1)
					Verify.expect(asked):toBe(1)
					w.stop()
				end,
			}
		)

		verifyHarness:case("excludes its placeholder from layout and preserves caller and ancestor availability", {
			id = "native_toast_action::native Toast with an action: presentation::excludes its placeholder from layout and preserves caller and ancestor availability",
			run = function()
				local c, visible = caller(), Compose.cell(true)
				c.shown:set(true)
				local w = mount({ { c = c, spec = { Visible = visible } } })
				Verify.expect(w.find("S1").Visible):toBe(false)
				Verify.expect(w.rows()):toBe(1)
				visible:set(false)
				Verify.expect(w.rows()):toBe(0)
				visible:set(true)
				Verify.expect(w.rows()):toBe(1)
				w.find("Holder").Visible = false
				Verify.expect(w.rows()):toBe(0)
				w.find("Holder").Visible = true
				Verify.expect(w.rows()):toBe(1)
				w.find("S1").Interactable = false
				Verify.expect(w.rows()):toBe(0)
				w.find("S1").Interactable = true
				Verify.expect(w.rows()):toBe(1)
				w.gate:set(false)
				Verify.expect(w.rows()):toBe(0)
				w.stop()
			end,
		})

		verifyHarness:case("a registration presents nothing and reserves nothing while its fact is false", {
			id = "native_toast_action::native Toast with an action: presentation::a registration presents nothing and reserves nothing while its fact is false",
			run = function()
				local c = caller()
				local w = mount({ { c = c, spec = { closeButton = false, onPresentedChange = noop } } })
				Verify.expect((w.rows())):toBe(0)
				Verify.expect(w.screen:GetAttribute("FacetInsetBottom") or 0):toBe(0)
				Verify.expect((w.find("S1"):GetAttribute("ToastQueued"))):toBe(false)
				local stops = {}
				local registration = w.find("S1")
				for _, node in w.screen:GetDescendants() do
					if node:IsA("GuiObject") and node.Selectable and node:IsDescendantOf(registration) then
						local shown, at = true, node
						while at and at:IsA("GuiObject") do
							shown = shown and at.Visible
							at = at.Parent
						end
						if shown then
							table.insert(stops, `{node.Parent.Name}/{node.Name}:{node.ClassName}`)
						end
					end
					if node:IsA("InputContext") and node.Enabled then
						table.insert(stops, node.Name)
					end
				end
				Verify.expect((table.concat(stops, ","))):toBe("")
				Verify.expect(w.gui.SelectedObject):toBeNil()
				w.stop()
			end,
		})

		verifyHarness:case("shows a message when the caller's fact turns true, and close proposes", {
			id = "native_toast_action::native Toast with an action: presentation::shows a message when the caller's fact turns true, and close proposes",
			run = function()
				local c = caller()
				local w = mount({ { c = c, message = "Saved to your garage" } })
				c.shown:set(true)
				Verify.expect((w.rows())):toBe(1)
				Verify.expect((w.message())):toBe("Saved to your garage")
				local plates = 0
				for _, node in w.screen:GetDescendants() do
					if node:HasTag("facet-snackbar") and node:HasTag("facet-floating") then
						plates += 1
					end
				end
				Verify.expect(plates):toBe(1)
				w.find("Close").Activated:Fire()
				Verify.expect(c.changes):toEqual({ false })
				Verify.expect(c.dismissed):toEqual({ "close" })
				Verify.expect((w.rows())):toBe(0)
				w.stop()
			end,
		})

		verifyHarness:case("the four compositions pick their parts and take the strip's width", {
			id = "native_toast_action::native Toast with an action: presentation::the four compositions pick their parts and take the strip's width",
			run = function()
				for _, case in
					{
						{ name = "message+action", spec = { closeButton = false } },
						{ name = "icon+message+action", spec = { closeButton = false, icon = "status.info" } },
						{ name = "message+action+close", spec = {} },
						{ name = "icon+message+action+close", spec = { icon = "status.info" } },
					} :: { any }
				do
					local c = caller()
					c.shown:set(true)
					local w = mount({ { c = c, message = "Saved", spec = case.spec } })
					local row = w.find("Snack")
					Verify.expect(`{case.name} icon: {overlay.find(row, "Icon") ~= nil}`)
						:toBe(`{case.name} icon: {case.spec.icon ~= nil}`)
					Verify.expect(`{case.name} action: {overlay.find(row, "Action") ~= nil}`)
						:toBe(`{case.name} action: true`)
					Verify.expect(`{case.name} close: {overlay.find(row, "Close") ~= nil}`)
						:toBe(`{case.name} close: {case.spec.closeButton ~= false}`)
					overlay.find(row, "MessageMeasure").TextBounds = Vector2.new(48, 18)
					Verify.expect(`{case.name}: {row.Size.X.Offset}`):toBe(`{case.name}: {math.min(480, 390 - 32)}`)
					local close = overlay.find(row, "Close")
					if close then
						Verify.expect(close.Size.Y.Offset >= 44):toBe(true)
					end
					w.stop()
				end
			end,
		})

		verifyHarness:case("long copy wraps and the action moves below it", {
			id = "native_toast_action::native Toast with an action: presentation::long copy wraps and the action moves below it",
			run = function()
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
				Verify.expect(layout.FillDirection):toBe(w.Enum.FillDirection.Horizontal)
				overlay.find(row, "MessageMeasure").TextBounds = Vector2.new(600, 18)
				Verify.expect(layout.FillDirection):toBe(w.Enum.FillDirection.Vertical)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native Toast with an action: proposals and reasons", function()
		verifyHarness:case("an action runs once and leaves the row mounted; closing inside it reports action", {
			id = "native_toast_action::native Toast with an action: proposals and reasons::an action runs once and leaves the row mounted; closing inside it reports action",
			run = function()
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
				w.find("Action").Activated:Fire()
				Verify.expect(runs):toBe(1)
				Verify.expect((w.rows())):toBe(1)
				Verify.expect(#c.dismissed):toBe(0)
				closeIt = true
				w.find("Action").Activated:Fire()
				Verify.expect(runs):toBe(2)
				Verify.expect(c.dismissed):toEqual({ "action" })
				Verify.expect((w.rows())):toBe(0)
				w.stop()
			end,
		})

		verifyHarness:case("a refused close keeps the same row and reports nothing", {
			id = "native_toast_action::native Toast with an action: proposals and reasons::a refused close keeps the same row and reports nothing",
			run = function()
				local c = caller(false)
				c.shown:set(true)
				local w = mount({ { c = c } })
				local row = w.find("Snack")
				w.find("Close").Activated:Fire()
				Verify.expect(c.changes):toEqual({ false })
				Verify.expect((w.find("Snack"))):toBe(row)
				Verify.expect(#c.dismissed):toBe(0)
				w.stop()
			end,
		})

		verifyHarness:case("an accepted timeout retires with reason timeout; nil duration never expires", {
			id = "native_toast_action::native Toast with an action: proposals and reasons::an accepted timeout retires with reason timeout; nil duration never expires",
			run = function()
				local a = caller()
				a.shown:set(true)
				local w = mount({ { c = a, spec = { duration = 3 } } })
				frames(w, 3.3)
				Verify.expect(a.dismissed):toEqual({ "timeout" })
				w.stop()
				local b = caller()
				b.shown:set(true)
				local w2 = mount({ { c = b } })
				frames(w2, 60)
				Verify.expect((w2.rows())):toBe(1)
				Verify.expect(#b.changes):toBe(0)
				w2.stop()
			end,
		})

		verifyHarness:case("hover and focus pause the dwell; queued time never counts", {
			id = "native_toast_action::native Toast with an action: proposals and reasons::hover and focus pause the dwell; queued time never counts",
			run = function()
				local a, b = caller(), caller()
				a.shown:set(true)
				b.shown:set(true)
				local w = mount({ { c = a, spec = { duration = 3 } }, { c = b, spec = { duration = 3 } } })
				frames(w, 0.5)
				local row = w.find("Snack")
				row.GuiState = w.Enum.GuiState.Hover
				frames(w, 5)
				Verify.expect(#a.changes):toBe(0)
				row.GuiState = w.Enum.GuiState.Idle
				w.gui.SelectedObject = w.find("Close")
				frames(w, 5)
				Verify.expect(#a.changes):toBe(0)
				w.gui.SelectedObject = nil
				frames(w, 2.6)
				Verify.expect(a.dismissed):toEqual({ "timeout" })
				Verify.expect((w.message())):toBe("Message 2")
				frames(w, 2)
				Verify.expect(#b.changes):toBe(0)
				frames(w, 1.1)
				Verify.expect(b.dismissed):toEqual({ "timeout" })
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native Toast with an action: admission and lifetime", function()
		verifyHarness:case("owner teardown never asks and reports cancel once, like Dialog and Popover", {
			id = "native_toast_action::native Toast with an action: admission and lifetime::owner teardown never asks and reports cancel once, like Dialog and Popover",
			run = function()
				local a = caller()
				a.shown:set(true)
				local w = mount({ { c = a } })
				w.gate:set(false)
				Verify.expect(#a.changes):toBe(0)
				Verify.expect((table.concat(a.dismissed, ","))):toBe("cancel")
				Verify.expect((w.rows())):toBe(0)
				w.stop()
			end,
		})

		verifyHarness:case("a visible row reserves its bottom rectangle, and releases it after it has slid out", {
			id = "native_toast_action::native Toast with an action: admission and lifetime::a visible row reserves its bottom rectangle, and releases it after it has slid out",
			run = function()
				local a = caller()
				a.shown:set(true)
				local w = mount({ { c = a } }, { motionLevel = "normal" })
				local row = w.find("Snack")
				row.AbsolutePosition = Vector2.new(16, 844 - 16 - 60)
				row.AbsoluteSize = Vector2.new(358, 60)
				Verify.expect((w.screen:GetAttribute("FacetInsetBottom"))):toBe(76)
				a.shown:set(false)
				Verify.expect((w.find("Snack"))):toBe(row)
				Verify.expect((w.screen:GetAttribute("FacetInsetBottom"))):toBe(76)
				frames(w, 0.1)
				Verify.expect((w.find("Snack"))):toBe(row)
				frames(w, 0.3)
				Verify.expect((w.find("Snack"))):toBeNil()
				Verify.expect((w.screen:GetAttribute("FacetInsetBottom"))):toBe(0)
				local token = {}
				reservations.set(w.screen, token, "bottom", 700, 60)
				Verify.expect((w.screen:GetAttribute("FacetInsetBottom"))):toBe(844 - 700)
				reservations.clear(w.screen, token)
				Verify.expect((w.screen:GetAttribute("FacetInsetBottom"))):toBe(0)
				w.stop()
			end,
		})

		verifyHarness:case("the row docks above the app's bottom chrome, and its own reservation does not lift it", {
			id = "native_toast_action::native Toast with an action: admission and lifetime::the row docks above the app's bottom chrome, and its own reservation does not lift it",
			run = function()
				local a = caller()
				a.shown:set(true)
				local w = mount({ { c = a } })
				local bar = {}
				reservations.set(w.screen, bar, "bottom", 844 - 60, 60)
				frames(w, 0.1)
				local row = w.find("Snack")
				row.AbsolutePosition = Vector2.new(16, 844 - 16 - 60 - 60)
				row.AbsoluteSize = Vector2.new(358, 60)
				frames(w, 0.1)
				Verify.expect(row.Position.Y.Offset):toBe(-16 - 60)
				reservations.clear(w.screen, bar)
				frames(w, 0.1)
				Verify.expect(row.Position.Y.Offset):toBe(-16)
				w.stop()
			end,
		})

		verifyHarness:case("refuses a malformed spec before registering", {
			id = "native_toast_action::native Toast with an action: admission and lifetime::refuses a malformed spec before registering",
			run = function()
				for index, bad in
					{
						{ isPresented = true, message = 4, action = UNDO, closeButton = false },
						{ isPresented = true, message = "m", icon = "", action = UNDO, closeButton = false },
						{ isPresented = true, message = "m", action = { label = "L" }, closeButton = false },
						{ isPresented = true, message = "m", action = UNDO, closeButton = "no" },
						{ isPresented = true, message = "m", action = UNDO },
						{ isPresented = true, message = "m", action = UNDO, closeButton = false, duration = 3 },
						{
							isPresented = true,
							message = "m",
							action = UNDO,
							closeButton = false,
							duration = -1,
							onPresentedChange = noop,
						},
						{ isPresented = true, message = "m", action = UNDO, closeButton = false, priority = 0 / 0 },
						{ isPresented = true, message = "m", action = UNDO, closeButton = false, tone = "x" },
						{ message = "m", closeButton = true },
						{ message = "m", action = UNDO, position = "top" },
						{ message = "m", action = UNDO, onPresentedChange = noop },
					} :: { any }
				do
					local ok = pcall(function()
						overlay
							.new(function(UI: FacetControls)
								return UI.Toast(bad)
							end)
							.stop()
					end)
					Verify.expect(`case {index}: {ok}`):toBe(`case {index}: false`)
				end
			end,
		})

		verifyHarness:case("a throwing caller callback is raised, and the row stays consistent", {
			id = "native_toast_action::native Toast with an action: admission and lifetime::a throwing caller callback is raised, and the row stays consistent",
			run = function()
				local shown = Compose.cell(true)
				local w = overlay.new(function(UI: FacetControls)
					return UI.Toast "S1" {
						isPresented = shown,
						message = "Saved",
						action = UNDO,
						onPresentedChange = function()
							error("proposal bug")
						end,
					}
				end, { motionLevel = "none" })
				local ok, failure = pcall(function()
					w.find("Close").Activated:Fire()
				end)
				Verify.expect(ok):toBe(false)
				Verify.expect(string.find(tostring(failure), "proposal bug", 1, true) ~= nil):toBe(true)
				Verify.expect(#w.findAll("Snack")):toBe(1)
				shown:set(false)
				Verify.expect(#w.findAll("Snack")):toBe(0)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native Toast with an action: the schedule under re-entrant callbacks", function()
		verifyHarness:case("callbacks may show and hide other rows during a retirement without a stale entry", {
			id = "native_toast_action::native Toast with an action: the schedule under re-entrant callbacks::callbacks may show and hide other rows during a retirement without a stale entry",
			run = function()
				local a, b, c = caller(), caller(), caller()
				a.onDismiss = function(reason: string)
					table.insert(a.dismissed, reason)
					b.shown:set(false)
					c.shown:set(true)
				end
				a.shown:set(true)
				b.shown:set(true)
				local w = mount({ { c = a, message = "a" }, { c = b, message = "b" }, { c = c, message = "c" } })
				Verify.expect((w.message())):toBe("a")
				w.find("Close").Activated:Fire()
				Verify.expect(a.dismissed):toEqual({ "close" })
				Verify.expect(b.dismissed):toEqual({ "cancel" })
				Verify.expect((w.message())):toBe("c")
				Verify.expect((w.rows())):toBe(1)
				Verify.expect((w.find("S2"):GetAttribute("ToastQueued"))):toBe(false)
				Verify.expect((w.find("S3"):GetAttribute("ToastVisible"))):toBe(true)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native Toast with an action: focus and input", function()
		verifyHarness:case(
			"arrival never steals focus; Cancel on a focused row returns focus to the content even when refused",
			{
				id = "native_toast_action::native Toast with an action: focus and input::arrival never steals focus; Cancel on a focused row returns focus to the content even when refused",
				run = function()
					local a = caller(false)
					local w = mount({ { c = a } })
					local content = w.find("Content")
					w.gui.SelectedObject = content
					a.shown:set(true)
					Verify.expect(w.gui.SelectedObject):toBe(content)
					w.gui.SelectedObject = w.find("Close")
					w.action("ToastCancel").Pressed:Fire()
					Verify.expect(a.changes):toEqual({ false })
					Verify.expect(w.gui.SelectedObject):toBe(content)
					Verify.expect((w.rows())):toBe(1)
					w.stop()
				end,
			}
		)

		verifyHarness:case("accepted removal of the focused row puts focus back on the content", {
			id = "native_toast_action::native Toast with an action: focus and input::accepted removal of the focused row puts focus back on the content",
			run = function()
				local a = caller()
				local w = mount({ { c = a } })
				local content = w.find("Content")
				w.gui.SelectedObject = content
				a.shown:set(true)
				w.gui.SelectedObject = w.find("Close")
				w.find("Close").Activated:Fire()
				Verify.expect((w.rows())):toBe(0)
				Verify.expect(w.gui.SelectedObject):toBe(content)
				w.stop()
			end,
		})

		verifyHarness:case("an owner teardown of the focused row puts focus back on the content", {
			id = "native_toast_action::native Toast with an action: focus and input::an owner teardown of the focused row puts focus back on the content",
			run = function()
				local a = caller()
				local w = mount({ { c = a } })
				local content = w.find("Content")
				w.gui.SelectedObject = content
				a.shown:set(true)
				w.gui.SelectedObject = w.find("Action")
				w.gate:set(false)
				Verify.expect((w.rows())):toBe(0)
				Verify.expect(w.gui.SelectedObject):toBe(content)
				w.stop()
			end,
		})

		verifyHarness:case("one Down from the control that raised the row reaches it, and the link goes with the row", {
			id = "native_toast_action::native Toast with an action: focus and input::one Down from the control that raised the row reaches it, and the link goes with the row",
			run = function()
				local a = caller()
				local w = mount({ { c = a } })
				local content = w.find("Content")
				w.gui.SelectedObject = content
				a.shown:set(true)
				local undo = w.find("Action")
				Verify.expect(undo ~= nil):toBe(true)
				Verify.expect(content.NextSelectionDown):toBe(undo)
				a.shown:set(false)
				frames(w, 1)
				Verify.expect(content.NextSelectionDown):toBe(nil)
				w.stop()
			end,
		})

		verifyHarness:case("the Down link from the raiser goes away once the selection moves on", {
			id = "native_toast_action::native Toast with an action: focus and input::the Down link from the raiser goes away once the selection moves on",
			run = function()
				local a = caller()
				local w = mount({ { c = a } })
				local content = w.find("Content")
				w.gui.SelectedObject = content
				a.shown:set(true)
				Verify.expect(content.NextSelectionDown):toBe(w.find("Action"))
				w.gui.SelectedObject = w.find("Action")
				Verify.expect(content.NextSelectionDown):toBe(w.find("Action"))
				local page = w.find("Page")
				page.Selectable = true
				w.gui.SelectedObject = page
				Verify.expect(content.NextSelectionDown):toBe(nil)
				Verify.expect((w.rows())):toBe(1)
				w.stop()
			end,
		})

		verifyHarness:case("a pointer press on Close leaves no click-eating catcher behind", {
			id = "native_toast_action::native Toast with an action: focus and input::a pointer press on Close leaves no click-eating catcher behind",
			run = function()
				local a = caller()
				a.shown:set(true)
				local w = mount({ { c = a } })
				w.find("Close").Activated:Fire()
				Verify.expect((w.find("DismissOutside"))):toBeNil()
				Verify.expect((w.find("ModalBack"))):toBeNil()
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native Toast with an action: without a binding", function()
		verifyHarness:case("the action runs and retires it; Close retires it; no duration never expires", {
			id = "native_toast_action::native Toast with an action: without a binding::the action runs and retires it; Close retires it; no duration never expires",
			run = function()
				local runs, reasons = 0, {}
				local shown = Compose.cell(true)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						Compose.show(shown, function()
							return Host.Frame({
								UI.Toast "A" {
									message = "Kart sold",
									action = {
										label = "Undo",
										onActivate = function()
											runs += 1
										end,
									},
									onDismiss = function(
										reason: "action" | "cancel" | "capacity" | "close" | "manual" | "preempt" | "supersede" | "timeout"
									)
										table.insert(reasons, reason)
									end,
								} :: unknown,
								UI.Toast "B" {
									message = "Saved",
									action = UNDO,
									onDismiss = function(
										reason: "action" | "cancel" | "capacity" | "close" | "manual" | "preempt" | "supersede" | "timeout"
									)
										table.insert(reasons, reason)
									end,
								},
							})
						end),
					})
				end, { motionLevel = "none" })
				frames(w, 30)
				Verify.expect((w.find("A"):GetAttribute("ToastVisible"))):toBe(true)
				Verify.expect((w.find("B"):GetAttribute("ToastQueued"))):toBe(true)
				w.find("Action").Activated:Fire()
				Verify.expect(runs):toBe(1)
				Verify.expect((w.find("B"):GetAttribute("ToastVisible"))):toBe(true)
				w.find("Close").Activated:Fire()
				Verify.expect((table.concat(reasons, ","))):toBe("action,close")
				Verify.expect(#w.findAll("Snack")):toBe(0)
				w.stop()
			end,
		})
	end)
end
