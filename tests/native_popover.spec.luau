--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local overlay = require("./lib/overlay_world")
local placement = require("../src/ui/overlay_placement")
local Vector2 = require("@lune/roblox").Vector2

type Log = { changes: { boolean }, dismissed: { string } }

local function caller(accept: boolean?): (any, Log, (boolean) -> ())
	local open = Compose.cell(false)
	local log: Log = { changes = {}, dismissed = {} }
	return open,
		log,
		function(nextValue: boolean)
			table.insert(log.changes, nextValue)
			if accept ~= false then
				open:set(nextValue)
			end
		end
end

local function content(UI: any, Host: any): any
	return Host.Frame({
		Name = "Card",
		BackgroundTransparency = 1,
		Host.TextLabel "Line" { Text = "Popover body" },
		UI.Button "Inner" { label = "Inner" },
	})
end

local function mount(specOf: (any, any) -> any, options: any?): any
	local o = options or {}
	local w = overlay.new(function(UI, Host, engine, gui)
		local children = { UI.Popover "Tip"(specOf(UI, Host)), UI.Button "Other" { label = "Other" } }
		for _, extra in o.extra or {} do
			table.insert(children, extra(UI, Host))
		end
		return Host.Frame({ Name = "S", table.unpack(children) })
	end, o)
	return w
end

local function standard(open: any, log: Log, change: any, extra: { [string]: any }?): (any, any) -> any
	return function(UI, Host)
		local spec: any = {
			isPresented = open,
			onPresentedChange = change,
			onDismiss = function(reason: string)
				table.insert(log.dismissed, reason)
			end,
			trigger = UI.Button "Open" { label = "Open" },
			content = function()
				return content(UI, Host)
			end,
		}
		for key, value in extra or {} do
			spec[key] = value
		end
		return spec
	end
end

t.describe("native Popover: the caller's fact decides, proposals ask", function()
	t.it("a trigger press proposes, and an accepted fact presents an anchored panel", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change))
		t.expect(w.find("Panel")).toBeNil()
		w.find("Open").Activated.fire()
		t.expect(#log.changes).toBe(1)
		t.expect(log.changes[1]).toBe(true)
		t.expect(overlay.find(w.find("Body"), "Line").Text).toBe("Popover body")
		t.expect(w.find("TipModal"):GetAttribute("FacetRoute")).toBe("popover")
		t.expect(w.find("DismissOutside").BackgroundTransparency).toBe(1)
		w.stop()
	end)

	t.it("a refused proposal presents nothing, and a refused close keeps the same surface and focus", function()
		local open, log, change = caller(false)
		local w = mount(standard(open, log, change))
		w.find("Open").Activated.fire()
		t.expect(w.find("Panel")).toBeNil()
		open:set(true)
		local panel = w.find("Panel")
		t.expect(panel ~= nil).toBe(true)
		local inner = overlay.find(panel, "Inner")
		w.gui.SelectedObject = inner
		w.find("ModalBack").Pressed.fire()
		w.find("DismissOutside").Activated.fire({ Position = Vector2.new(790, 590) })
		t.expect(w.find("Panel")).toBe(panel)
		t.expect(w.gui.SelectedObject).toBe(inner)
		t.expect(#log.dismissed).toBe(0)
		t.expect(log.changes[#log.changes]).toBe(false)
		w.stop()
	end)

	t.it("Cancel, an outside tap and a press on the trigger each close with their own reason, once", function()
		for _, case in { "cancel", "outside", "trigger" } do
			local open, log, change = caller()
			local w = mount(standard(open, log, change))
			open:set(true)
			t.expect(w.find("Panel") ~= nil).toBe(true)
			if case == "cancel" then
				w.find("ModalBack").Pressed.fire()
			elseif case == "outside" then
				w.find("DismissOutside").Activated.fire({ Position = Vector2.new(790, 590) })
			else
				w.find("Open").Activated.fire()
				t.expect(w.find("Panel") ~= nil).toBe(true)
				w.find("DismissOutside").Activated.fire({ Position = Vector2.new(5, 5) })
			end
			t.expect(`{case}: {tostring(w.find("Panel") == nil)}`).toBe(`{case}: true`)
			t.expect(open:peek()).toBe(false)
			t.expect(table.concat(log.dismissed, ",")).toBe(if case == "trigger" then "outside" else case)
			w.stop()
		end
	end)

	t.it("without onPresentedChange nothing interactive opens or closes it; the fact still does", function()
		local open = Compose.cell(false)
		local w = mount(function(UI, Host)
			return {
				isPresented = open,
				trigger = UI.Button "Open" { label = "Open" },
				content = function()
					return content(UI, Host)
				end,
			}
		end)
		w.find("Open").Activated.fire()
		t.expect(w.find("Panel")).toBeNil()
		open:set(true)
		t.expect(w.find("Panel") ~= nil).toBe(true)
		w.find("ModalBack").Pressed.fire()
		t.expect(w.find("Panel") ~= nil).toBe(true)
		open:set(false)
		t.expect(w.find("Panel")).toBeNil()
		w.stop()
	end)
end)

t.describe("native Popover: every input class opens and closes it through a real route", function()
	t.it("pointer: a click on the trigger opens it and a click outside closes it", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change))
		w.input.PreferredInput = w.Enum.PreferredInput.KeyboardAndMouse
		w.find("Open").Activated.fire()
		t.expect(w.find("Panel") ~= nil).toBe(true)
		w.find("DismissOutside").Activated.fire({ Position = Vector2.new(790, 590) })
		t.expect(open:peek()).toBe(false)
		t.expect(table.concat(log.dismissed, ",")).toBe("outside")
		w.stop()
	end)

	t.it("keyboard: Return on the focused trigger opens it into the content, and closing returns focus", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change))
		local trigger = w.find("Open")
		w.gui.SelectedObject = trigger
		w.action("Activate").Pressed.fire()
		t.expect(open:peek()).toBe(true)
		t.expect(w.gui.SelectedObject:IsDescendantOf(w.find("Body"))).toBe(true)
		open:set(false)
		t.expect(table.concat(log.dismissed, ",")).toBe("cancel")
		t.expect(w.gui.SelectedObject).toBe(trigger)
		w.stop()
	end)

	t.it("gamepad: ButtonA on the focused trigger opens it, and ButtonB proposes the close", function()
		local open, log, change = caller()
		local w = mount(standard(open, log, change))
		w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
		local trigger = w.find("Open")
		w.gui.SelectedObject = trigger
		trigger.Activated.fire()
		t.expect(open:peek()).toBe(true)
		t.expect(w.gui.SelectedObject:IsDescendantOf(w.find("Panel"))).toBe(true)
		w.find("ModalBack").Pressed.fire()
		t.expect(open:peek()).toBe(false)
		t.expect(table.concat(log.dismissed, ",")).toBe("cancel")
		t.expect(w.gui.SelectedObject).toBe(trigger)
		w.stop()
	end)
end)

t.describe("native Popover: sources, anchor loss and bounds", function()
	local function sourced(open: any, log: Log, change: any, target: any): (any, any) -> any
		return function(UI, Host)
			return {
				isPresented = open,
				onPresentedChange = change,
				onDismiss = function(reason: string)
					table.insert(log.dismissed, reason)
				end,
				source = { node = target },
				content = function()
					return content(UI, Host)
				end,
			}
		end
	end

	t.it("a node source follows its node; removing it releases at once and reports anchorLost once", function()
		local open, log, change = caller()
		local target: any
		local w = mount(function(UI, Host)
			target = Host.Frame "Target" {}
			return sourced(open, log, change, target)(UI, Host)
		end, {
			extra = {
				function()
					return target
				end,
			},
		})
		open:set(true)
		local panel = w.find("Panel")
		t.expect(panel ~= nil).toBe(true)
		target.AbsolutePosition = Vector2.new(100, 100)
		target.AbsoluteSize = Vector2.new(80, 40)
		panel.AbsoluteSize = Vector2.new(200, 100)
		t.expect(panel.Position.Y.Offset).toBe(148)
		local holder = target.Parent
		target.Parent = nil
		t.expect(w.find("Panel")).toBeNil()
		t.expect(table.concat(log.dismissed, ",")).toBe("anchorLost")
		t.expect(open:peek()).toBe(false)
		target.Parent = holder
		t.expect(w.find("Panel")).toBeNil()
		open:set(true)
		t.expect(w.find("Panel") ~= nil).toBe(true)
		w.stop()
	end)

	t.it("a caller who refuses the anchorLost proposal keeps its fact, and nothing reopens", function()
		local open, log, change = caller(false)
		local target: any
		local w = mount(function(UI, Host)
			target = Host.Frame "Target" {}
			return sourced(open, log, change, target)(UI, Host)
		end, {
			extra = {
				function()
					return target
				end,
			},
		})
		open:set(true)
		local holder = target.Parent
		target.Parent = nil
		target.Parent = holder
		t.expect(open:peek()).toBe(true)
		t.expect(w.find("Panel")).toBeNil()
		t.expect(table.concat(log.dismissed, ",")).toBe("anchorLost")
		w.stop()
	end)

	t.it("a source that has not mounted yet waits instead of being lost", function()
		local open = Compose.cell(true)
		local target: any
		local w = mount(function(UI, Host)
			target = Host.Frame "Target" {}
			return {
				isPresented = open,
				source = { node = target },
				content = function()
					return content(UI, Host)
				end,
			}
		end)
		t.expect(w.find("Panel")).toBeNil()
		target.Parent = w.find("S")
		t.expect(w.find("Panel") ~= nil).toBe(true)
		w.stop()
	end)

	t.it("a rect source never draws a tail; crossOffset and edge reach the placement", function()
		local open = Compose.cell(true)
		local w = mount(function(UI, Host)
			return {
				isPresented = open,
				source = { rect = { x = 300, y = 200, w = 40, h = 40 } },
				edge = "trailing",
				align = "start",
				crossOffset = 10,
				tail = true,
				content = function()
					return content(UI, Host)
				end,
			}
		end)
		local panel = w.find("Panel")
		panel.AbsoluteSize = Vector2.new(120, 80)
		t.expect(w.find("Tail")).toBeNil()
		local expected = placement.solve({
			source = { x = 300, y = 200, w = 40, h = 40 },
			size = { w = 120, h = 80 },
			safe = { x = 8, y = 8, w = 800 - 16, h = 600 - 16 },
			edge = "trailing",
			align = "start",
			gap = 8,
			crossOffset = 10,
		})
		t.expect(expected.x).toBe(348)
		t.expect(panel.Position.X.Offset).toBe(expected.x)
		t.expect(panel.Position.Y.Offset).toBe(210)
		w.stop()
		local tailed = mount(function(UI, Host)
			return {
				isPresented = Compose.cell(true),
				trigger = UI.Button "Open" { label = "Open" },
				content = function()
					return content(UI, Host)
				end,
			}
		end)
		local trigger = tailed.find("Open")
		trigger.AbsolutePosition = Vector2.new(300, 100)
		trigger.AbsoluteSize = Vector2.new(100, 44)
		tailed.find("Panel").AbsoluteSize = Vector2.new(160, 80)
		local tail = tailed.find("Tail")
		t.expect(tail.Visible).toBe(true)
		t.expect(tail.Position.X.Offset).toBe(350)
		t.expect(tail.Position.Y.Offset).toBe(152)
		tailed.stop()
	end)

	t.it("maxWidth and maxHeight bound the whole panel inside the live safe box, and the body scrolls", function()
		local w = mount(function(UI, Host)
			return {
				isPresented = Compose.cell(true),
				source = { rect = { x = 100, y = 20, w = 40, h = 40 } },
				maxWidth = 220,
				maxHeight = 180,
				content = function()
					return content(UI, Host)
				end,
			}
		end)
		local body = w.find("Body")
		t.expect(body.ClassName).toBe("ScrollingFrame")
		t.expect(body.AutomaticCanvasSize).toBe(w.Enum.AutomaticSize.None)
		local limit = body:FindFirstChildWhichIsA("UISizeConstraint")
		t.expect(limit.MaxSize).toBe(w.Vector2.new(220 - 16, 180 - 16))
		local flow = w.find("Flow")
		flow.AbsoluteSize = Vector2.new(200, 1050)
		t.expect(body.CanvasSize.Y.Offset).toBe(1050)
		local list = flow:FindFirstChildWhichIsA("UIListLayout")
		list.AbsoluteContentSize = Vector2.new(200, 60)
		t.expect(body.Size.Y.Offset).toBe(60)
		list.AbsoluteContentSize = Vector2.new(200, 1050)
		t.expect(body.Size.Y.Offset).toBe(180 - 16)
		t.expect(body.AutomaticSize).toBe(w.Enum.AutomaticSize.X)
		w.screen.AbsoluteSize = Vector2.new(150, 600)
		t.expect(limit.MaxSize.X).toBe(150 - 16 - 16)
		local panel = w.find("Panel")
		panel.AbsoluteSize = Vector2.new(134, 164)
		t.expect(panel.Position.X.Offset + 134 <= 150 - 8).toBe(true)
		w.stop()
	end)

	t.it("a source that never mounts waits without an error", function()
		local open = Compose.cell(true)
		local w = mount(function(UI, Host)
			return {
				isPresented = open,
				source = { node = Host.Frame "Nowhere" {} },
				content = function()
					return content(UI, Host)
				end,
			}
		end)
		t.expect(w.find("Panel")).toBeNil()
		open:set(false)
		open:set(true)
		t.expect(w.find("Panel")).toBeNil()
		w.stop()
	end)
end)

t.describe("native Popover: the compact sheet and the live route switch", function()
	local function compactWorld(extra: { [string]: any }?): (any, any, Log)
		local open, log, change = caller()
		local w = mount(standard(open, log, change, extra))
		w.input.PreferredInput = w.Enum.PreferredInput.Touch
		w.screen.AbsoluteSize = Vector2.new(390, 800)
		return w, open, log
	end

	t.it("a compact touch screen presents it as a sheet; compact = popover suppresses that", function()
		local w, open = compactWorld()
		open:set(true)
		t.expect(w.find("SheetPanel") ~= nil).toBe(true)
		t.expect(w.find("Popup")).toBeNil()
		t.expect(overlay.find(w.find("SheetContent"), "Line").Text).toBe("Popover body")
		w.stop()
		local p, openP = compactWorld({ compact = "popover" })
		openP:set(true)
		t.expect(p.find("SheetPanel")).toBeNil()
		t.expect(p.find("Popup") ~= nil).toBe(true)
		p.stop()
	end)

	t.it("a sheet dismissed by something the popover did not drive still proposes and reports", function()
		local w, open, log = compactWorld()
		open:set(true)
		t.expect(w.find("SheetPanel") ~= nil).toBe(true)
		w.find("S").Visible = false
		t.expect(w.find("SheetPanel")).toBeNil()
		t.expect(open:peek()).toBe(false)
		t.expect(table.concat(log.dismissed, ",")).toBe("cancel")
		w.stop()
	end)

	t.it("the sheet's Close asks first: refused keeps it, accepted closes with cancel", function()
		local open, log, change = caller(false)
		local w = mount(standard(open, log, change))
		w.input.PreferredInput = w.Enum.PreferredInput.Touch
		w.screen.AbsoluteSize = Vector2.new(390, 800)
		open:set(true)
		local panel = w.find("SheetPanel")
		w.find("Close").Activated.fire()
		t.expect(w.find("SheetPanel")).toBe(panel)
		t.expect(log.changes[#log.changes]).toBe(false)
		t.expect(#log.dismissed).toBe(0)
		w.stop()
		local w2, open2, log2 = compactWorld()
		open2:set(true)
		w2.find("Close").Activated.fire()
		t.expect(w2.find("SheetPanel")).toBeNil()
		t.expect(table.concat(log2.dismissed, ",")).toBe("cancel")
		w2.stop()
	end)

	t.it("a live class change switches the route silently, with one content owner", function()
		local builds, live = 0, 0
		local open, log, change = caller()
		local w = mount(function(UI, Host)
			local spec = standard(open, log, change)(UI, Host)
			spec.content = function()
				builds += 1
				live += 1
				Compose.cleanup(function()
					live -= 1
				end)
				return content(UI, Host)
			end
			return spec
		end)
		w.screen.AbsoluteSize = Vector2.new(390, 800)
		open:set(true)
		t.expect(w.find("Popup") ~= nil).toBe(true)
		w.gui.SelectedObject = w.find("Inner")
		w.input.PreferredInput = w.Enum.PreferredInput.Touch
		t.expect(w.find("Popup")).toBeNil()
		t.expect(w.find("SheetPanel") ~= nil).toBe(true)
		t.expect(builds).toBe(2)
		t.expect(live).toBe(1)
		t.expect(#log.changes).toBe(0)
		t.expect(#log.dismissed).toBe(0)
		t.expect(w.gui.SelectedObject).toBe(w.find("Inner"))
		w.input.PreferredInput = w.Enum.PreferredInput.KeyboardAndMouse
		t.expect(w.find("Popup") ~= nil).toBe(true)
		t.expect(live).toBe(1)
		w.stop()
	end)

	t.it("a refused drag on the compact sheet goes back to the accepted detent", function()
		local open, log, change = caller(false)
		local w = mount(standard(open, log, change), { reducedMotion = true })
		w.input.PreferredInput = w.Enum.PreferredInput.Touch
		w.screen.AbsoluteSize = Vector2.new(390, 800)
		open:set(true)
		local rest = w.find("SheetPanel").Size.Y.Offset
		local drag = w.find("UIDragDetector")
		drag.DragStart.fire(w.Vector2.new(0, 0))
		drag.DragContinue.fire(w.Vector2.new(0, 500))
		w.tick(0.5)
		drag.DragEnd.fire()
		t.expect(log.changes[#log.changes]).toBe(false)
		t.expect(w.find("SheetPanel") ~= nil).toBe(true)
		t.expect(w.find("SheetPanel").Size.Y.Offset).toBe(rest)
		w.stop()
	end)
end)

t.describe("native Popover: callbacks that throw or re-enter, and branch cycles", function()
	t.it("a throwing onPresentedChange changes nothing, and a throwing onDismiss still closes once", function()
		local open = Compose.cell(true)
		local w = mount(function(UI, Host)
			return {
				isPresented = open,
				onPresentedChange = function()
					error("proposal bug")
				end,
				trigger = UI.Button "Open" { label = "Open" },
				content = function()
					return content(UI, Host)
				end,
			}
		end)
		local ok, failure = pcall(w.find("ModalBack").Pressed.fire)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(failure), "proposal bug", 1, true) ~= nil).toBe(true)
		t.expect(w.find("Panel") ~= nil).toBe(true)
		w.stop()
		local fact, calls = Compose.cell(true), 0
		local w2 = mount(function(UI, Host)
			return {
				isPresented = fact,
				onDismiss = function()
					calls += 1
					error("dismiss bug")
				end,
				trigger = UI.Button "Open" { label = "Open" },
				content = function()
					return content(UI, Host)
				end,
			}
		end)
		pcall(function()
			fact:set(false)
		end)
		t.expect(w2.find("Panel")).toBeNil()
		t.expect(calls).toBe(1)
		w2.stop()
	end)

	t.it("a caller that re-opens inside its own close callback keeps one live surface", function()
		local open = Compose.cell(true)
		local w = mount(function(UI, Host)
			return {
				isPresented = open,
				onPresentedChange = function(nextValue: boolean)
					open:set(nextValue)
					if not nextValue then
						open:set(true)
					end
				end,
				trigger = UI.Button "Open" { label = "Open" },
				content = function()
					return content(UI, Host)
				end,
			}
		end)
		w.find("ModalBack").Pressed.fire()
		t.expect(#w.findAll("Panel")).toBe(1)
		t.expect(open:peek()).toBe(true)
		w.stop()
	end)

	t.it("open/close/branch cycles return the native tree to its baseline", function()
		local open, log, change = caller()
		local shown = Compose.cell(true)
		local w = overlay.new(function(UI, Host)
			return Host.Frame({
				Name = "S",
				Compose.show(shown, function()
					return UI.Popover "Tip"(standard(open, log, change)(UI, Host))
				end),
			})
		end)
		local baseline = w.engine.census()
		for _ = 1, 3 do
			w.find("Open").Activated.fire()
			w.find("ModalBack").Pressed.fire()
			shown:set(false)
			shown:set(true)
		end
		local after = w.engine.census()
		t.expect(after.live).toBe(baseline.live)
		t.expect(after.connections).toBe(baseline.connections)
		t.expect(table.concat(log.dismissed, ",")).toBe("cancel,cancel,cancel")
		w.stop()
	end)
end)

t.describe("native Popover: lifetime and contract", function()
	t.it("owner disposal releases physically and reports cancel once; two worlds stay apart", function()
		local open, log, change = caller()
		local shown = Compose.cell(true)
		local w = overlay.new(function(UI, Host)
			return Host.Frame({
				Name = "S",
				Compose.show(shown, function()
					return UI.Popover "Tip"(standard(open, log, change)(UI, Host))
				end),
			})
		end)
		local open2, log2, change2 = caller()
		local w2 = mount(standard(open2, log2, change2))
		open:set(true)
		open2:set(true)
		shown:set(false)
		t.expect(w.find("Panel")).toBeNil()
		t.expect(table.concat(log.dismissed, ",")).toBe("cancel")
		t.expect(#log.changes).toBe(0)
		t.expect(w2.find("Panel") ~= nil).toBe(true)
		t.expect(#log2.dismissed).toBe(0)
		w.stop()
		w2.stop()
	end)

	t.it("the spec is closed and the contract is refused by name", function()
		local function refuses(specOf: (any, any) -> any, fragment: string)
			local ok, failure = pcall(function()
				mount(specOf).stop()
			end)
			t.expect(ok).toBe(false)
			t.expect(`{fragment}: {string.find(tostring(failure), fragment, 1, true) ~= nil}`).toBe(`{fragment}: true`)
		end
		local function base(UI: any, Host: any, extra: { [string]: any }): any
			local spec: any = {
				isPresented = Compose.cell(false),
				trigger = UI.Button "Open" { label = "Open" },
				content = function()
					return content(UI, Host)
				end,
			}
			for key, value in extra do
				spec[key] = if value == "nil" then nil else value
			end
			return spec
		end
		refuses(function(UI, Host)
			return base(UI, Host, { isPresented = "nil" })
		end, "isPresented")
		refuses(function(UI, Host)
			return base(UI, Host, { content = "nil" })
		end, "content")
		refuses(function(UI, Host)
			return base(UI, Host, { source = { rect = { x = 0, y = 0, w = 1, h = 1 } } })
		end, "exactly one")
		refuses(function(UI, Host)
			return base(UI, Host, { trigger = "nil", source = { rect = { x = 0, y = 0, w = 1, h = math.huge } } })
		end, "source.rect.h")
		refuses(function(UI, Host)
			return base(UI, Host, { edge = "overlap" })
		end, "edge")
		refuses(function(UI, Host)
			return base(UI, Host, { align = "middle" })
		end, "align")
		refuses(function(UI, Host)
			return base(UI, Host, { crossOffset = 0 / 0 })
		end, "crossOffset")
		refuses(function(UI, Host)
			return base(UI, Host, { maxWidth = -4 })
		end, "maxWidth")
		refuses(function(UI, Host)
			return base(UI, Host, { compact = "never" })
		end, "compact")
		refuses(function(UI, Host)
			return base(UI, Host, { widht = 3 })
		end, "widht")
	end)
end)
