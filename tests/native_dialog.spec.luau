--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local overlay = require("./lib/overlay_world")
local parts = require("../src/ui/overlay_parts")
local Vector2 = require("@lune/roblox").Vector2

type Log = { changes: { boolean }, dismissed: { string }, pressed: { string } }

local function caller(accept: boolean?): (any, Log, (boolean) -> ())
	local open = Compose.cell(true)
	local log: Log = { changes = {}, dismissed = {}, pressed = {} }
	return open,
		log,
		function(nextValue: boolean)
			table.insert(log.changes, nextValue)
			if accept ~= false then
				open:set(nextValue)
			end
		end
end

local function standard(open: any, log: Log, change: any, extra: { [string]: any }?): (any, any) -> any
	return function(UI: any, Host: any)
		local spec: any = {
			isPresented = open,
			onPresentedChange = change,
			onDismiss = function(reason: string)
				table.insert(log.dismissed, reason)
			end,
			title = "Leave the race?",
			content = function()
				return Host.TextLabel "Line" { Text = "Your lap will not count." }
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
		for key, value in extra or {} do
			spec[key] = value
		end
		return spec
	end
end

local function mount(specOf: (any, any) -> any, options: any?): any
	return overlay.new(function(UI, Host, _, gui)
		local opener = UI.Button "Opener" { label = "Open" }
		gui.SelectedObject = opener
		return Host.Frame({ opener, UI.Dialog "Confirm"(specOf(UI, Host)) })
	end, options)
end

local function actionButton(w: any, id: string): any
	return overlay.find(w.find("Actions"), id)
end

t.describe("native Dialog: the caller's fact decides", function()
	t.it("an accepted fact presents the panel with pinned title, body and actions", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change))
		local panel = w.find("Panel")
		t.expect(panel ~= nil).toBe(true)
		t.expect(w.find("Title").Text).toBe("Leave the race?")
		t.expect(overlay.find(w.find("Body"), "Line") ~= nil).toBe(true)
		t.expect(actionButton(w, "Leave") ~= nil).toBe(true)
		t.expect(w.find("Actions"):IsDescendantOf(w.find("Room"))).toBe(true)
		t.expect(w.find("Close"):IsDescendantOf(w.find("Header"))).toBe(true)
		t.expect(w.find("DialogModal") ~= nil).toBe(true)
		w.stop()
	end)

	t.it("the close button proposes: refused keeps the same surface and focus, accepted reports close", function()
		local open, log, change = caller(false)
		local w = mount(standard(open, log, change))
		local panel = w.find("Panel")
		local close = w.find("Close")
		w.gui.SelectedObject = close
		close.Activated.fire()
		t.expect(w.find("Panel")).toBe(panel)
		t.expect(w.gui.SelectedObject).toBe(close)
		t.expect(log.changes[#log.changes]).toBe(false)
		t.expect(#log.dismissed).toBe(0)
		w.stop()
		local open2, log2, change2 = caller()
		local w2 = mount(standard(open2, log2, change2))
		t.expect(w2.gui.SelectedObject).toBe(actionButton(w2, "Stay"))
		w2.find("Close").Activated.fire()
		t.expect(w2.find("Panel")).toBe(nil)
		t.expect(table.concat(log2.dismissed, ",")).toBe("close")
		t.expect(w2.gui.SelectedObject).toBe(w2.find("Opener"))
		w2.stop()
	end)

	t.it("Cancel runs an eligible cancel action first; without one it proposes cancel", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change))
		w.find("ModalBack").Pressed.fire()
		t.expect(table.concat(log.pressed, ",")).toBe("Stay")
		t.expect(w.find("Panel") ~= nil).toBe(true)
		w.stop()
		local open2, log2, change2 = caller()
		local w2 = mount(standard(open2, log2, change2, {
			actions = {
				{ id = "Stay", label = "Stay", role = "cancel", enabled = false, onActivate = function() end },
				{ id = "Leave", label = "Leave", onActivate = function() end },
			},
		}))
		w2.find("ModalBack").Pressed.fire()
		t.expect(w2.find("Panel")).toBe(nil)
		t.expect(table.concat(log2.dismissed, ",")).toBe("cancel")
		w2.stop()
	end)

	t.it("an action that accepts false during its callback closes with reason action", function()
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
		actionButton(w, "Leave").Activated.fire()
		t.expect(w.find("Panel")).toBe(nil)
		t.expect(table.concat(log.dismissed, ",")).toBe("action")
		w.stop()
	end)

	t.it("an action never closes by itself, and a throwing one leaves the bookkeeping sound", function()
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
		local ok, failure = pcall(actionButton(w, "Boom").Activated.fire)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(failure), "caller bug", 1, true) ~= nil).toBe(true)
		t.expect(w.find("Panel") ~= nil).toBe(true)
		open:set(false)
		t.expect(table.concat(log.dismissed, ",")).toBe("cancel")
		w.stop()
	end)

	t.it("a throwing proposal is raised and changes nothing", function()
		local open, log = caller()
		local w = mount(standard(open, log, function()
			error("proposal bug")
		end))
		local ok, failure = pcall(w.find("Close").Activated.fire)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(failure), "proposal bug", 1, true) ~= nil).toBe(true)
		t.expect(w.find("Panel") ~= nil).toBe(true)
		open:set(false)
		t.expect(table.concat(log.dismissed, ",")).toBe("cancel")
		w.stop()
	end)

	t.it("the backdrop proposes outside; with no callback and no close it only swallows", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change))
		w.find("DismissOutside").Activated.fire()
		t.expect(table.concat(log.dismissed, ",")).toBe("outside")
		w.stop()
		local fact = Compose.cell(true)
		local w2 = mount(function(_, Host)
			return {
				isPresented = fact,
				closeButton = false,
				title = "Read this",
				content = function()
					return Host.TextLabel "Line" { Text = "Body" }
				end,
			}
		end)
		t.expect(w2.find("Close")).toBe(nil)
		w2.find("DismissOutside").Activated.fire()
		w2.find("ModalBack").Pressed.fire()
		t.expect(w2.find("Panel") ~= nil).toBe(true)
		fact:set(false)
		t.expect(w2.find("Panel")).toBe(nil)
		w2.stop()
	end)

	t.it("Return fires the default action; a disabled or busy one cannot fire by any route", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change))
		w.action("Shortcut").Pressed.fire()
		t.expect(table.concat(log.pressed, ",")).toBe("Leave")
		w.stop()
		local open2, log2, change2 = caller()
		local w2 = mount(standard(open2, log2, change2, {
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
		t.expect(w2.action("Shortcut")).toBe(nil)
		actionButton(w2, "Go").Activated.fire()
		t.expect(#log2.pressed).toBe(0)
		w2.find("ModalBack").Pressed.fire()
		t.expect(#log2.pressed).toBe(0)
		t.expect(table.concat(log2.dismissed, ",")).toBe("cancel")
		w2.stop()
	end)
end)

t.describe("native Dialog: composition, layout and the height budget", function()
	t.it("title-only, body-only, hero-only, action-label-only and actions-only all present", function()
		for index, extra in
			{
				{ title = "Title" } :: any,
				{ content = true },
				{ hero = { image = "rbxassetid://75342910516929", aspectRatio = 2 } },
				{ actionLabel = "Pick one" },
				{ actions = { { id = "Ok", label = "Ok", onActivate = function() end } } },
			}
		do
			local w = mount(function(_, Host)
				local spec: any = { isPresented = Compose.cell(true), closeButton = false }
				for key, value in extra do
					spec[key] = if key == "content"
						then function()
							return Host.TextLabel "Line" { Text = "Body" }
						end
						else value
				end
				return spec
			end)
			t.expect(`case {index}: {w.find("Panel") ~= nil}`).toBe(`case {index}: true`)
			w.stop()
		end
	end)

	t.it("the spec is closed and malformed compositions are refused by name", function()
		local function refuses(spec: any, fragment: string)
			local ok, failure = pcall(function()
				local w = mount(function()
					return spec
				end)
				w.stop()
			end)
			t.expect(ok).toBe(false)
			t.expect(`{fragment}: {string.find(tostring(failure), fragment, 1, true) ~= nil}`).toBe(`{fragment}: true`)
		end
		local fact = Compose.cell(true)
		refuses({ title = "T", closeButton = false }, "isPresented")
		refuses({ isPresented = fact, title = "T" }, "onPresentedChange")
		refuses({ isPresented = fact, closeButton = false }, "nothing to show")
		refuses({ isPresented = fact, closeButton = false, title = "T", widht = "wide" }, "widht")
		refuses({ isPresented = fact, closeButton = false, title = "T", width = "huge" }, "width")
		refuses({ isPresented = fact, closeButton = false, title = "T", actionLayout = "grid" }, "actionLayout")
		refuses({ isPresented = fact, closeButton = false, title = "T", hero = { image = "x" } }, "aspectRatio")
		refuses({
			isPresented = fact,
			closeButton = false,
			actions = {
				{ id = "A", label = "A", role = "default", onActivate = function() end },
				{ id = "B", label = "B", role = "default", onActivate = function() end },
			},
		}, "role default")
		refuses({
			isPresented = fact,
			closeButton = false,
			actions = {
				{ id = "A", label = "A", onActivate = function() end },
				{ id = "A", label = "B", onActivate = function() end },
			},
		}, "unique")
		refuses({ isPresented = fact, closeButton = false, content = "text" }, "content")
	end)

	local function sized(w: any, bodyHeight: number)
		w.size(w.find("Header"), 400, 44)
		if w.find("ActionLabel") then
			w.size(w.find("ActionLabel"), 400, 20)
		end
		w.size(w.find("Actions"), 400, 44)
		w.size(overlay.find(w.find("Body"), "Content"), 400, bodyHeight)
	end

	t.it("a long body fits the room: pinned header, label and actions stay on screen while it scrolls", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change, { actionLabel = "Leaving forfeits this heat." }))
		sized(w, 2000)
		local body, room = w.find("Body"), w.find("Room")
		local budget = 600 - 64
		local pinned = 44 + 20 + 44 + 3 * 8
		t.expect(body.Size.Y.Offset).toBe(budget - pinned)
		t.expect(body.ScrollingEnabled).toBe(true)
		t.expect(room.ScrollingEnabled).toBe(false)
		t.expect(room.AutomaticSize).toBe(w.Enum.AutomaticSize.Y)
		t.expect(w.find("Actions").Parent).toBe(room)
		t.expect(w.find("Header").Parent).toBe(room)
		w.stop()
	end)

	t.it("a tiny room unpins every region into one scroller: the last action is reachable", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change, { actionLabel = "Leaving forfeits this heat." }), {
			size = Vector2.new(320, 160),
		})
		sized(w, 400)
		local body, room = w.find("Body"), w.find("Room")
		t.expect(room.ScrollingEnabled).toBe(true)
		t.expect(room.Size.Y.Offset).toBe(160 - 64)
		t.expect(body.ScrollingEnabled).toBe(false)
		t.expect(body.Size.Y.Offset).toBe(400)
		t.expect(actionButton(w, "Leave"):IsDescendantOf(room)).toBe(true)
		w.screen.AbsoluteSize = Vector2.new(320, 900)
		t.expect(room.ScrollingEnabled).toBe(false)
		t.expect(body.ScrollingEnabled).toBe(true)
		w.stop()
	end)

	t.it("a phone dialog hugs its content and rows two actions that fit", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change), { size = Vector2.new(390, 844) })
		sized(w, 60)
		t.expect(w.find("Body").Size.Y.Offset).toBe(60)
		t.expect(w.find("Panel").Size.X.Offset).toBe(390 - 32)
		t.expect(w.find("Panel").AutomaticSize).toBe(w.Enum.AutomaticSize.Y)
		actionButton(w, "Stay").TextBounds = Vector2.new(40, 20)
		actionButton(w, "Leave").TextBounds = Vector2.new(48, 20)
		local list = w.find("Actions"):FindFirstChildWhichIsA("UIListLayout")
		t.expect(list.FillDirection).toBe(w.Enum.FillDirection.Horizontal)
		t.expect(actionButton(w, "Stay").LayoutOrder < actionButton(w, "Leave").LayoutOrder).toBe(true)
		w.stop()
	end)

	t.it("the keyboard's occlusion takes its room from the budget", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change), { size = Vector2.new(390, 844) })
		sized(w, 2000)
		local before = w.find("Body").Size.Y.Offset
		w.input.OnScreenKeyboardSize = Vector2.new(390, 300)
		w.input.OnScreenKeyboardVisible = true
		t.expect(w.find("Body").Size.Y.Offset).toBe(before - 300)
		t.expect(w.find("Panel").Position.Y.Offset).toBe(-150)
		w.input.OnScreenKeyboardVisible = false
		t.expect(w.find("Body").Size.Y.Offset).toBe(before)
		w.stop()
	end)

	t.it("automatic actions stack for three; an explicit row that cannot fit falls to the safe stack", function()
		local function three(): any
			local list = {}
			for _, id in { "A", "B", "C" } do
				table.insert(list, { id = id, label = id, onActivate = function() end })
			end
			return list
		end
		local open, log, change = caller()
		local w = mount(standard(open, log, change, { actions = three() }))
		local list = w.find("Actions"):FindFirstChildWhichIsA("UIListLayout")
		t.expect(list.FillDirection).toBe(w.Enum.FillDirection.Vertical)
		t.expect(actionButton(w, "A").Size.X.Scale).toBe(1)
		w.stop()
		local open2, log2, change2 = caller()
		local w2 = mount(standard(open2, log2, change2, { actionLayout = "row" }), { size = Vector2.new(390, 844) })
		local list2 = w2.find("Actions"):FindFirstChildWhichIsA("UIListLayout")
		t.expect(list2.FillDirection).toBe(w2.Enum.FillDirection.Horizontal)
		actionButton(w2, "Stay").TextBounds = Vector2.new(200, 20)
		actionButton(w2, "Leave").TextBounds = Vector2.new(200, 20)
		t.expect(list2.FillDirection).toBe(w2.Enum.FillDirection.Vertical)
		w2.stop()
		local open3, log3, change3 = caller()
		local w3 = mount(standard(open3, log3, change3, { actionLayout = "stacked" }))
		t.expect(w3.find("Actions"):FindFirstChildWhichIsA("UIListLayout").FillDirection)
			.toBe(w3.Enum.FillDirection.Vertical)
		t.expect(actionButton(w3, "Stay").LayoutOrder > actionButton(w3, "Leave").LayoutOrder).toBe(true)
		w3.stop()
	end)

	t.it("the width presets resolve to theme ceilings inside the safe room", function()
		t.expect(parts.WIDTHS.automatic).toBe("controls.alert.maxWidth")
		t.expect(parts.WIDTHS.narrow).toBe("controls.popup.panelWidth")
		t.expect(parts.WIDTHS.wide).toBe("controls.dialog.wideWidth")
		for _, case in
			{
				{ nil, 1200, 560 } :: { any },
				{ "automatic", 1200, 560 },
				{ "narrow", 1200, 360 },
				{ "wide", 1200, 800 },
				{ "wide", 500, 500 - 32 },
				{ "narrow", 300, 300 - 32 },
			}
		do
			local open, log, change = caller()
			local w = mount(standard(open, log, change, { width = case[1] }), { size = Vector2.new(case[2], 700) })
			t.expect(`{case[1]}@{case[2]}: {w.find("Panel").Size.X.Offset}`).toBe(`{case[1]}@{case[2]}: {case[3]}`)
			w.stop()
		end
	end)

	t.it("a bound title may start empty and fill in later, in the same presentation", function()
		local title = Compose.cell("")
		local open, log, change = caller()
		local w = mount(standard(open, log, change, { title = title }))
		local panel, heading = w.find("Panel"), w.find("Title")
		t.expect(heading.Visible).toBe(false)
		title:set("Leave the race?")
		t.expect(w.find("Panel")).toBe(panel)
		t.expect(w.find("Title")).toBe(heading)
		t.expect(heading.Visible).toBe(true)
		t.expect(heading.Text).toBe("Leave the race?")
		w.stop()
	end)
end)

t.describe("native Dialog: a plain overflowing body is one pad stop that scrolls", function()
	t.it("the ring reaches the body, Down scrolls it to the end, and then moves on to the actions", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change))
		w.size(w.find("Header"), 400, 44)
		w.size(w.find("Actions"), 400, 44)
		local body = w.find("Body")
		w.size(overlay.find(body, "Content"), 400, 1500)
		body.AbsoluteWindowSize = Vector2.new(400, 400)
		body.AbsoluteCanvasSize = Vector2.new(400, 1500)
		t.expect(body.Selectable).toBe(true)
		w.gui.SelectedObject = body
		local down = w.action("DialogBodyDown")
		t.expect(down ~= nil).toBe(true)
		t.expect(w.action("DialogBodyUp")).toBe(nil)
		down.Pressed.fire()
		t.expect(body.CanvasPosition.Y).toBe(320)
		for _ = 1, 5 do
			local again = w.action("DialogBodyDown")
			if again then
				again.Pressed.fire()
			end
		end
		t.expect(body.CanvasPosition.Y).toBe(1100)
		t.expect(w.action("DialogBodyDown")).toBe(nil)
		t.expect(w.action("DialogBodyUp") ~= nil).toBe(true)
		w.stop()
	end)

	t.it("a body that fits offers no stop, and contentSelectable = false never does", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change))
		w.size(overlay.find(w.find("Body"), "Content"), 400, 40)
		t.expect(w.find("Body").Selectable).toBe(false)
		w.stop()
		local open2, log2, change2 = caller()
		local w2 = mount(standard(open2, log2, change2, { contentSelectable = false }))
		w2.size(overlay.find(w2.find("Body"), "Content"), 400, 3000)
		t.expect(w2.find("Body").Selectable).toBe(false)
		w2.gui.SelectedObject = w2.find("Body")
		t.expect(w2.action("DialogBodyDown")).toBe(nil)
		w2.stop()
	end)

	t.it("interactive content keeps its own stops inside the body", function()
		local open, log, change = caller()
		local w = mount(function(UI, Host)
			local spec = standard(open, log, change)(UI, Host)
			spec.content = function()
				return UI.Button "Inner" { label = "Inner", onActivate = function() end }
			end
			return spec
		end)
		w.size(overlay.find(w.find("Body"), "Content"), 400, 3000)
		local inner = w.find("Inner")
		t.expect(inner.Selectable).toBe(true)
		t.expect(inner:IsDescendantOf(w.find("Body"))).toBe(true)
		t.expect(w.find("Body").Selectable).toBe(true)
		w.stop()
	end)
end)

t.describe("native Dialog: lifetime", function()
	t.it("owner disposal releases physically and reports cancel once; reopen cycles return to baseline", function()
		local open, log, change = caller()
		local shown = Compose.cell(true)
		local w = overlay.new(function(UI, Host)
			return Host.Frame({
				Compose.show(shown, function()
					return UI.Dialog "Confirm"(standard(open, log, change)(UI, Host))
				end),
			})
		end)
		t.expect(w.find("Panel") ~= nil).toBe(true)
		shown:set(false)
		t.expect(w.find("Panel")).toBe(nil)
		t.expect(table.concat(log.dismissed, ",")).toBe("cancel")
		t.expect(#log.changes).toBe(0)
		shown:set(true)
		open:set(false)
		local baseline = w.engine.census()
		for _ = 1, 3 do
			open:set(true)
			w.find("Close").Activated.fire()
		end
		local after = w.engine.census()
		t.expect(after.live).toBe(baseline.live)
		t.expect(after.connections).toBe(baseline.connections)
		t.expect(table.concat(log.dismissed, ",")).toBe("cancel,cancel,close,close,close")
		w.stop()
	end)
end)
