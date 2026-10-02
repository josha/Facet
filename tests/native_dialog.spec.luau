--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local overlay = require("./lib/overlay_world")
local parts = require("../src/ui/overlay_parts")
local controls = require("../src/ui")
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
			content = function(): Instance
				return Host.TextLabel "Line" { Text = "Your lap will not count." }
			end,
			actions = {
				{
					id = "Stay",
					label = "Stay",
					role = "cancel" :: "cancel",
					onActivate = function()
						table.insert(log.pressed, "Stay")
					end,
				} :: typeof(require("@repo/tools/typecheck/example_shapes").DialogAction(nil :: any)),
				{
					id = "Leave",
					label = "Leave",
					role = "default" :: "default",
					onActivate = function()
						table.insert(log.pressed, "Leave")
					end,
				} :: typeof(require("@repo/tools/typecheck/example_shapes").DialogAction(nil :: any)),
			},
		}
		for key, value in (extra or {} :: { [string]: any }) do
			spec[key] = value
		end
		return spec
	end
end

local function mount(specOf: (any, any) -> any, options: any?): any
	return overlay.new(
		function(
			UI: typeof(require("@repo/src").controls(nil :: any)),
			Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host),
			_,
			gui
		)
			local opener = UI.Button "Opener" { label = "Open" }
			gui.SelectedObject = opener
			return Host.Frame({ opener :: unknown, UI.Dialog "Confirm"(specOf(UI, Host)) })
		end,
		options
	)
end

local function actionButton(w: any, id: string): any
	return overlay.find(w.find("Actions"), id)
end

t.describe("native Dialog: one Back press closes one modal", function()
	t.it("the modal under a closing one ignores the Back press that closed it", function()
		local outerOpen, outerLog, outerChange = caller()
		local innerOpen, innerLog, innerChange = caller()
		local held = true
		local w = overlay.new(
			function(
				UI: typeof(require("@repo/src").controls(nil :: any)),
				Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host),
				_,
				gui
			)
				local opener = UI.Button "Opener" { label = "Open" }
				gui.SelectedObject = opener
				return Host.Frame({
					opener :: unknown,
					UI.Dialog "Outer"(standard(outerOpen, outerLog, outerChange)(UI, Host)),
					UI.Dialog "Inner"(standard(innerOpen, innerLog, innerChange)(UI, Host)),
				})
			end,
			{ motionLevel = "none" }
		)
		w.input.IsGamepadButtonDown = function(_, _, key)
			return held and key == w.Enum.KeyCode.ButtonB
		end
		w.advance(0.1)
		w.action("ModalBack").Pressed.fire()
		t.expect(innerOpen:peek()).toBe(false)
		local under = w.action("ModalBack")
		t.expect(under ~= nil).toBe(true)
		under.Pressed.fire()
		t.expect(outerOpen:peek()).toBe(true)
		held = false
		under.Released.fire()
		under.Pressed.fire()
		t.expect(outerOpen:peek()).toBe(false)
		w.stop()
	end)
end)

t.describe("native Dialog: Tab and Escape arrive through UserInputService", function()
	local function key(w: any, name: string, began: boolean)
		local event = { KeyCode = (w.Enum.KeyCode :: any)[name], UserInputType = w.Enum.UserInputType.Keyboard }
		if began then
			w.input.InputBegan.fire(event, true)
		else
			w.input.InputEnded.fire(event, true)
		end
	end

	t.it("a Tab the engine keeps from input actions still walks the dialog, one step per press", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change), { inputs = true })
		w.input.KeyboardEnabled = true
		local first = w.gui.SelectedObject
		t.expect(first ~= nil).toBe(true)
		key(w, "Tab", true)
		local second = w.gui.SelectedObject
		t.expect(second ~= first).toBe(true)
		local traverse
		for _, node in w.screen.Parent:GetDescendants() do
			if node:IsA("InputAction") and node.Name == "Traverse" then
				traverse = node
			end
		end
		traverse.Pressed.fire()
		t.expect(w.gui.SelectedObject).toBe(second)
		key(w, "Tab", false)
		traverse.Released.fire()
		traverse.Pressed.fire()
		t.expect(w.gui.SelectedObject ~= second).toBe(true)
		traverse.Released.fire()
		w.stop()
	end)

	t.it("one Escape closes only the top of two stacked dialogs", function()
		local outerOpen, outerLog, outerChange = caller()
		local innerOpen, innerLog, innerChange = caller()
		local w = overlay.new(
			function(
				UI: typeof(require("@repo/src").controls(nil :: any)),
				Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host),
				_,
				gui
			)
				local opener = UI.Button "Opener" { label = "Open" }
				gui.SelectedObject = opener
				return Host.Frame({
					opener :: unknown,
					UI.Dialog "Outer"(standard(outerOpen, outerLog, outerChange)(UI, Host)),
					UI.Dialog "Inner"(standard(innerOpen, innerLog, innerChange)(UI, Host)),
				})
			end,
			{ inputs = true, motionLevel = "none" }
		)
		w.advance(0.1)
		key(w, "Escape", true)
		key(w, "Escape", false)
		t.expect(`{innerOpen:peek()} {outerOpen:peek()}`).toBe("false true")
		w.stop()
	end)

	t.it("an Escape while the Roblox menu is open closes nothing", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change), { inputs = true, motionLevel = "none" })
		w.advance(0.1)
		w.gui.MenuIsOpen = true
		key(w, "Escape", true)
		key(w, "Escape", false)
		t.expect(open:peek()).toBe(true)
		w.gui.MenuIsOpen = false
		key(w, "Escape", true)
		key(w, "Escape", false)
		t.expect(open:peek()).toBe(false)
		w.stop()
	end)

	t.it("with two Facet control sets, one Escape closes only the dialog that holds the selection", function()
		local firstOpen, firstLog, firstChange = caller()
		local secondOpen, secondLog, secondChange = caller()
		local w = mount(standard(firstOpen, firstLog, firstChange), { inputs = true, motionLevel = "none" })
		local target = w.engine.new("Folder")
		local other = controls(Compose, w.runtime, {
			types = w.engine.types,
			inputParent = target,
			services = { GuiService = w.gui, UserInputService = w.input },
			motionLevel = "none",
		})
		local stop = w.runtime.mount(function()
			return (
				(
					w.runtime.constructors.ScreenGui :: unknown
				) :: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host.ScreenGui)
			)({
				other.Dialog "Second"(standard(secondOpen, secondLog, secondChange)(other, w.runtime.constructors)),
			})
		end, target)
		w.advance(0.1)
		local panel = overlay.find(target, "Actions")
		w.gui.SelectedObject = overlay.find(panel, "Stay")
		key(w, "Escape", true)
		key(w, "Escape", false)
		t.expect(`{firstOpen:peek()} {secondOpen:peek()}`).toBe("true false")
		stop()
		w.stop()
	end)

	t.it("Tab leaves only a Facet text field, and never with Ctrl, Alt or Meta held", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change), { inputs = true })
		w.input.KeyboardEnabled = true
		local start = w.gui.SelectedObject
		local foreign = w.engine.new("TextBox")
		w.input.GetFocusedTextBox = function()
			return foreign
		end
		key(w, "Tab", true)
		key(w, "Tab", false)
		t.expect(w.gui.SelectedObject).toBe(start)
		w.input.GetFocusedTextBox = function()
			return nil
		end
		local down = {}
		w.input.IsKeyDown = function(_, code)
			return down[code.Name] == true
		end
		for _, modifier in { "LeftControl", "RightAlt", "LeftMeta" } do
			down[modifier] = true
			key(w, "Tab", true)
			key(w, "Tab", false)
			t.expect(w.gui.SelectedObject).toBe(start)
			down[modifier] = nil
		end
		key(w, "Tab", true)
		key(w, "Tab", false)
		t.expect(w.gui.SelectedObject ~= start).toBe(true)
		w.stop()
	end)

	t.it("an Escape the engine keeps from input actions closes the dialog once, and not while typing", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change), { inputs = true, motionLevel = "none" })
		w.advance(0.1)
		w.input.GetFocusedTextBox = function()
			return w.engine.new("TextBox")
		end
		key(w, "Escape", true)
		key(w, "Escape", false)
		t.expect(open:peek()).toBe(true)
		w.input.GetFocusedTextBox = function()
			return nil
		end
		key(w, "Escape", true)
		local back = w.action("ModalBack")
		if back then
			back.Pressed.fire()
		end
		key(w, "Escape", false)
		t.expect(open:peek()).toBe(false)
		t.expect(#log.changes).toBe(1)
		w.stop()
	end)
end)

t.describe("native Dialog: the caller's fact decides", function()
	t.it("a ten-foot screen or Larger text stacks the actions full width", function()
		for _, case in { "near", "tv", "text" } do
			local open, log, change = caller()
			open:set(false)
			local w = mount(standard(open, log, change))
			if case == "tv" then
				w.gui.ViewportDisplaySize = w.Enum.DisplaySize.Large
				w.input.MouseEnabled = false
				w.input.TouchEnabled = false
			elseif case == "text" then
				w.gui.PreferredTextSize = w.Enum.PreferredTextSize.Larger
			end
			open:set(true)
			local list = w.find("Actions"):FindFirstChildWhichIsA("UIListLayout")
			local vertical = list.FillDirection == w.Enum.FillDirection.Vertical
			t.expect(`{case}:{vertical}`).toBe(`{case}:{case ~= "near"}`)
			if case ~= "near" then
				t.expect(actionButton(w, "Leave").Size.X.Scale).toBe(1)
			end
			w.stop()
		end
	end)

	t.it("an accepted fact presents the panel with pinned title, body and actions", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change))
		local panel = w.find("Panel")
		t.expect(panel ~= nil).toBe(true)
		t.expect(w.find("Title").Text).toBe("Leave the race?")
		t.expect(overlay.find(w.find("Body"), "Line") ~= nil).toBe(true)
		t.expect(actionButton(w, "Leave") ~= nil).toBe(true)
		t.expect(w.find("Actions"):IsDescendantOf(w.find("Room"))).toBe(true)
		t.expect(w.find("Close")).toBe(nil)
		t.expect(w.find("DialogModal") ~= nil).toBe(true)
		w.stop()
	end)

	t.it("keeps the claimed selection when the entry fade hands the panel's children back", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change))
		local stay = actionButton(w, "Stay")
		t.expect(w.find("Fade") ~= nil and stay:IsDescendantOf(w.find("Fade"))).toBe(true)
		t.expect(w.gui.SelectedObject).toBe(stay)
		stay.AncestryChanged:Connect(function()
			if w.gui.SelectedObject == stay then
				w.gui.SelectedObject = nil
			end
		end)
		w.advance(1, 60)
		t.expect(w.find("Fade")).toBe(nil)
		t.expect(w.gui.SelectedObject).toBe(stay)
		w.stop()
	end)

	t.it("a child that arrives while the entry fade runs joins the fading group", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change))
		local fade = w.find("Fade")
		t.expect(fade ~= nil).toBe(true)
		local late = w.engine.new("Frame")
		late.Name = "Late"
		late.Parent = fade.Parent
		w.advance(1 / 60)
		t.expect(late.Parent).toBe(fade)
		w.advance(1, 60)
		t.expect(w.find("Fade")).toBe(nil)
		t.expect(late.Parent ~= nil and late.Parent.ClassName ~= "CanvasGroup").toBe(true)
		w.stop()
	end)

	t.it("a dialog with actions has no close control unless it asks; one without actions keeps it", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change, { closeButton = true }))
		t.expect(w.find("Close"):IsDescendantOf(w.find("Header"))).toBe(true)
		w.stop()
		local bare = mount(standard(open, log, change, { actions = {} }))
		t.expect(bare.find("Close") ~= nil).toBe(true)
		bare.stop()
	end)

	t.it("the close button proposes: refused keeps the same surface and focus, accepted reports close", function()
		local open, log, change = caller(false)
		local w = mount(standard(open, log, change, { closeButton = true }))
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
		local w2 = mount(standard(open2, log2, change2, { closeButton = true }))
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
		t.expect(w.find("Panel")).toBe(nil)
		t.expect(table.concat(log.dismissed, ",")).toBe("action")
		w.stop()
		local open2, log2, change2 = caller()
		local w2 = mount(standard(open2, log2, change2, {
			actions = {
				{
					id = "Stay",
					label = "Stay",
					role = "cancel" :: "cancel",
					enabled = false,
					onActivate = function() end,
				} :: typeof(require("@repo/tools/typecheck/example_shapes").DialogAction(nil :: any)),
				{ id = "Leave", label = "Leave", onActivate = function() end } :: typeof(require("@repo/tools/typecheck/example_shapes").DialogAction(nil :: any)),
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
					role = "default" :: "default",
					onActivate = function()
						open:set(false)
					end,
				} :: typeof(require("@repo/tools/typecheck/example_shapes").DialogAction(nil :: any)),
			},
		}))
		actionButton(w, "Leave").Activated.fire()
		t.expect(w.find("Panel")).toBe(nil)
		t.expect(table.concat(log.dismissed, ",")).toBe("action")
		w.stop()
	end)

	t.it("an action press proposes the close after its callback; keepOpen opts out", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change, {
			actions = {
				{
					id = "Apply",
					label = "Apply",
					keepOpen = true,
					onActivate = function()
						table.insert(log.pressed, "Apply")
					end,
				} :: typeof(require("@repo/tools/typecheck/example_shapes").DialogAction(nil :: any)),
				{
					id = "Leave",
					label = "Leave",
					onActivate = function()
						table.insert(log.pressed, "Leave")
					end,
				} :: typeof(require("@repo/tools/typecheck/example_shapes").DialogAction(nil :: any)),
			},
		}))
		actionButton(w, "Apply").Activated.fire()
		t.expect(#log.changes).toBe(0)
		t.expect(w.find("Panel") ~= nil).toBe(true)
		actionButton(w, "Leave").Activated.fire()
		t.expect(table.concat(log.pressed, ",")).toBe("Apply,Leave")
		t.expect(#log.changes == 1 and log.changes[1] == false).toBe(true)
		t.expect(table.concat(log.dismissed, ",")).toBe("action")
		w.stop()
		local refused, refusedLog, refuse = caller(false)
		local kept = mount(standard(refused, refusedLog, refuse))
		actionButton(kept, "Leave").Activated.fire()
		t.expect(#refusedLog.changes == 1 and refusedLog.changes[1] == false).toBe(true)
		t.expect(kept.find("Panel") ~= nil).toBe(true)
		t.expect(table.concat(refusedLog.dismissed, ",")).toBe("")
		kept.stop()
		t.expect(function()
			parts.checkActions(
				{} :: any,
				"UI.Sheet",
				{ { id = "A", label = "A", keepOpen = true, onActivate = print } },
				2
			)
		end).toThrow()
	end)

	t.it("a throwing action proposes nothing and leaves the bookkeeping sound", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change, {
			actions = {
				{
					id = "Boom",
					label = "Boom",
					onActivate = function()
						error("caller bug")
					end,
				} :: typeof(require("@repo/tools/typecheck/example_shapes").DialogAction(nil :: any)),
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
		end, { closeButton = true }))
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
		local w2 = mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
			return {
				isPresented = fact,
				closeButton = false,
				title = "Read this",
				content = function(): Instance
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
					role = "default" :: "default",
					busy = true,
					onActivate = function()
						table.insert(log2.pressed, "Go")
					end,
				} :: typeof(require("@repo/tools/typecheck/example_shapes").DialogAction(nil :: any)),
				{
					id = "Stop",
					label = "Stop",
					role = "cancel" :: "cancel",
					busy = true,
					onActivate = function()
						table.insert(log2.pressed, "Stop")
					end,
				} :: typeof(require("@repo/tools/typecheck/example_shapes").DialogAction(nil :: any)),
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
				{
					actions = {
						{ id = "Ok", label = "Ok", onActivate = function() end } :: typeof(require("@repo/tools/typecheck/example_shapes").DialogAction(nil :: any)),
					},
				},
			}
		do
			local w = mount(function(_, Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host))
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
		refuses({ isPresented = fact, closeButton = false, title = "T", width = "huge" :: "huge" }, "width")
		refuses({ isPresented = fact, closeButton = false, title = "T", actionLayout = "grid" }, "actionLayout")
		refuses({ isPresented = fact, closeButton = false, title = "T", hero = { image = "x" } }, "aspectRatio")
		refuses({
			isPresented = fact,
			closeButton = false,
			actions = {
				{ id = "A", label = "A", role = "default" :: "default", onActivate = function() end } :: typeof(require("@repo/tools/typecheck/example_shapes").DialogAction(nil :: any)),
				{ id = "B", label = "B", role = "default" :: "default", onActivate = function() end } :: typeof(require("@repo/tools/typecheck/example_shapes").DialogAction(nil :: any)),
			},
		}, "role default")
		refuses({
			isPresented = fact,
			closeButton = false,
			actions = {
				{ id = "A", label = "A", onActivate = function() end } :: typeof(require("@repo/tools/typecheck/example_shapes").DialogAction(nil :: any)),
				{ id = "A", label = "B", onActivate = function() end } :: typeof(require("@repo/tools/typecheck/example_shapes").DialogAction(nil :: any)),
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
		t.expect(room.Selectable).toBe(false)
		local stay, leave = actionButton(w, "Stay"), actionButton(w, "Leave")
		w.at(room, 16, 32)
		w.size(room, 288, 96)
		room.AbsoluteWindowSize = Vector2.new(288, 96)
		room.AbsoluteCanvasSize = Vector2.new(288, 600)
		w.at(stay, 16, 60)
		w.size(stay, 120, 44)
		w.at(leave, 16, 520)
		w.size(leave, 120, 44)
		w.gui.SelectedObject = stay
		w.advance(1 / 60)
		w.input.InputBegan.fire({ KeyCode = w.Enum.KeyCode.DPadDown })
		w.advance(1 / 10, 6)
		t.expect(w.gui.SelectedObject).toBe(leave)
		t.expect(room.CanvasPosition.Y).toBe(520 + 44 - (32 + 96))
		w.gui.SelectedObject = leave
		w.at(leave, 16, 84)
		w.at(stay, 16, -376)
		w.advance(1 / 60)
		w.input.InputBegan.fire({ KeyCode = w.Enum.KeyCode.DPadUp })
		w.advance(1 / 10, 6)
		t.expect(w.gui.SelectedObject).toBe(stay)
		w.advance(1 / 60)
		w.gui.SelectedObject = leave
		w.input.InputBegan.fire({ KeyCode = w.Enum.KeyCode.DPadUp })
		w.advance(1 / 10, 6)
		t.expect(w.gui.SelectedObject).toBe(leave)
		w.screen.AbsoluteSize = Vector2.new(320, 900)
		t.expect(room.ScrollingEnabled).toBe(false)
		w.gui.SelectedObject = stay
		w.advance(1 / 60)
		w.input.InputBegan.fire({ KeyCode = w.Enum.KeyCode.DPadDown })
		w.advance(1 / 10, 6)
		t.expect(w.gui.SelectedObject).toBe(stay)
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

	t.it("Tab and Shift+Tab stop on the overflowing body", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change), { inputs = true })
		w.size(w.find("Header"), 400, 44)
		w.size(w.find("Actions"), 400, 44)
		local body = w.find("Body")
		w.size(overlay.find(body, "Content"), 400, 1500)
		body.AbsoluteWindowSize = Vector2.new(400, 400)
		body.AbsoluteCanvasSize = Vector2.new(400, 1500)
		w.input.KeyboardEnabled = true
		local traverse
		for _, node in w.screen.Parent:GetDescendants() do
			if node:IsA("InputAction") and node.Name == "Traverse" then
				traverse = node
			end
		end
		t.expect(traverse ~= nil).toBe(true)
		local visited = {}
		for _ = 1, 8 do
			traverse.Pressed.fire()
			traverse.Released.fire()
			visited[w.gui.SelectedObject] = true
		end
		t.expect(visited[body]).toBe(true)
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
		local w = mount(
			function(
				UI: typeof(require("@repo/src").controls(nil :: any)),
				Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
			)
				local spec = standard(open, log, change)(UI, Host)
				spec.content = function()
					return UI.Button "Inner" { label = "Inner", onActivate = function() end }
				end
				return spec
			end
		)
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
		local w = overlay.new(
			function(
				UI: typeof(require("@repo/src").controls(nil :: any)),
				Host: typeof(require("@repo/src/ui/context")(nil :: any, nil :: any).Host)
			)
				return Host.Frame({
					Compose.show(shown, function()
						return UI.Dialog "Confirm"(standard(open, log, change, { closeButton = true })(UI, Host))
					end),
				})
			end
		)
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
