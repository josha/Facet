--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local overlay = require("./lib/overlay_world")
local release = require("../src/ui/sheet_release")
local Vector2 = require("@lune/roblox").Vector2

local LONG = string.rep("A long line of body copy that wraps across the sheet. ", 40)
local noop = function() end

local function mount(extra: { [string]: any }?, options: any?): any
	local o = options or {}
	local detent = Compose.cell(o.detent or "medium")
	local shown = o.shown or Compose.cell(true)
	local builds = 0
	local w = overlay.new(function(UI, Host)
		local spec: any = {
			isPresented = shown,
			detent = detent,
			title = "Race details",
			content = function()
				builds += 1
				return Host.TextLabel "Copy" { Text = LONG, TextWrapped = true }
			end,
		}
		for key, value in extra or {} do
			spec[key] = if type(value) == "table" and value.__build then value.__build(UI, Host) else value
		end
		return UI.Sheet "Sheet"(spec)
	end, o)
	w.detent, w.shown = detent, shown
	w.builds = function()
		return builds
	end
	local modal = w.find("Modal")
	if modal then
		modal.AbsoluteSize = o.room or Vector2.new(800, 600)
	end
	if not o.unsettled then
		w.advance(1 / 300, 2)
	end
	return w
end

local function content(w: any, height: number)
	local flow = w.find("SheetFlow")
	flow:FindFirstChildWhichIsA("UIListLayout").AbsoluteContentSize = Vector2.new(500, height - 16)
end

local function built(fn: (any, any) -> any): any
	return { __build = fn }
end

t.describe("native Sheet: placement, width, title and close", function()
	t.it("a function-bound title renders as its type promises", function()
		local w = mount({
			title = function()
				return "Live title"
			end,
		})
		t.expect(w.find("Title").Text).toBe("Live title")
		w.stop()
	end)

	t.it("explicit placements pin the panel to the bottom or the center", function()
		local w = mount({ placement = "bottom" })
		local panel = w.find("SheetPanel")
		t.expect(panel.AnchorPoint).toBe(w.Vector2.new(0.5, 1))
		t.expect(panel.Position.Y.Scale).toBe(1)
		t.expect(panel.Position.X.Scale).toBe(0.5)
		w.stop()
		local c = mount({ placement = "center" })
		local centered = c.find("SheetPanel")
		t.expect(centered.AnchorPoint).toBe(c.Vector2.new(0.5, 0.5))
		t.expect(centered.Position.Y.Scale).toBe(0.5)
		c.stop()
		local a = mount({ placement = "automatic" })
		t.expect(a.find("SheetPanel").AnchorPoint).toBe(a.Vector2.new(0.5, 1))
		a.stop()
	end)

	t.it("side placement docks to its physical edge, detents stay vertical", function()
		local w = mount({ placement = "side" }, { room = Vector2.new(1200, 800), reducedMotion = true })
		local panel = w.find("SheetPanel")
		t.expect(panel.AnchorPoint).toBe(w.Vector2.new(1, 1))
		t.expect(panel.Position.X.Scale).toBe(1)
		t.expect(panel.Position.X.Offset).toBe(0)
		t.expect(panel.Position.Y.Scale).toBe(1)
		t.expect(panel.Size.Y.Offset).toBe(400)
		w.stop()
		local left = mount(
			{ placement = "side", edge = "left", width = "narrow" },
			{ room = Vector2.new(1200, 800), reducedMotion = true }
		)
		local leftPanel = left.find("SheetPanel")
		t.expect(leftPanel.AnchorPoint).toBe(left.Vector2.new(0, 1))
		t.expect(leftPanel.Position.X.Scale).toBe(0)
		t.expect(leftPanel.Size.X.Offset).toBe(360)
		left.stop()
	end)

	t.it("width presets reuse the dialog widths, bounded by safe room", function()
		local widths = {}
		for _, preset in { "narrow", "automatic", "wide" } do
			local w = mount({ width = preset }, { room = Vector2.new(1200, 800) })
			widths[preset] = w.find("SheetPanel").Size.X.Offset
			w.stop()
		end
		t.expect(widths).toEqual({ narrow = 360, automatic = 560, wide = 800 })
		local narrow = mount({ width = "wide" }, { room = Vector2.new(500, 800) })
		t.expect(narrow.find("SheetPanel").Size.X.Offset).toBe(500)
		narrow.stop()
	end)

	t.it("side sheets enter and leave toward their own edge", function()
		local w = mount({ placement = "side", edge = "left" }, { room = Vector2.new(1200, 800), unsettled = true })
		local panel = w.find("SheetPanel")
		t.expect(panel.Position.X.Offset).toBe(-560)
		w.advance(1 / 300, 2)
		w.advance(0.3, 6)
		t.expect(panel.Position.X.Offset).toBe(0)
		w.shown:set(false)
		t.expect(w.find("SheetPanel")).toBe(panel)
		w.advance(0.1, 2)
		t.expect(panel.Position.X.Offset < 0).toBe(true)
		w.advance(0.3, 6)
		t.expect(w.find("SheetPanel")).toBeNil()
		w.stop()
		local right = mount({ placement = "side" }, { room = Vector2.new(1200, 800), unsettled = true })
		t.expect(right.find("SheetPanel").Position.X.Offset).toBe(560)
		right.stop()
		local bottom = mount(nil, { room = Vector2.new(1200, 800), unsettled = true })
		t.expect(bottom.find("SheetPanel").Position.X.Offset).toBe(0)
		bottom.shown:set(false)
		t.expect(bottom.find("SheetPanel")).toBeNil()
		bottom.stop()
	end)

	t.it("closeButton=false removes Close; Size and interactive dismissal remain", function()
		local w = mount({ closeButton = false })
		t.expect(w.find("Close")).toBeNil()
		t.expect(w.find("Grabber").Selectable).toBe(true)
		w.find("ModalBack").Pressed.fire()
		t.expect(w.shown:peek()).toBe(false)
		w.stop()
		local label = Compose.cell("Fertig")
		local named = mount({ closeButton = label })
		local close = named.find("Close")
		t.expect(close.Text).toBe("Fertig")
		label:set("Schliessen")
		t.expect(close.Text).toBe("Schliessen")
		close.Activated.fire()
		t.expect(named.shown:peek()).toBe(false)
		named.stop()
	end)

	t.it("refuses malformed placement, edge, width and closeButton", function()
		for _, change in
			{
				{ placement = "top" } :: any,
				{ edge = "left" },
				{ placement = "side", edge = "start" },
				{ width = "huge" },
				{ closeButton = 4 },
				{ dragIndicator = "sometimes" },
				{ scrollPolicy = "never" },
			}
		do
			local ok = pcall(function()
				mount(change).stop()
			end)
			t.expect(ok).toBe(false)
		end
	end)

	t.it("the Size control reads player words, never a detent id", function()
		local w = mount({ detents = { "hug", "medium" } })
		local grabber = w.find("Grabber")
		t.expect(grabber:GetAttribute("AccessibleLabel")).toBe("Size: Medium")
		w.detent:set("hug")
		t.expect(grabber:GetAttribute("AccessibleLabel")).toBe("Size: Fit")
		w.stop()
		local custom = mount({ detents = { { id = "compact", fraction = 0.3 }, "large" } }, { detent = "compact" })
		t.expect(custom.find("Grabber"):GetAttribute("AccessibleLabel")).toBe("Size: Compact")
		custom.stop()
	end)
end)

t.describe("native Sheet: parts", function()
	t.it("default parts: pinned title and utilities, one body scroller (the panel no longer scrolls)", function()
		local w = mount()
		local room, body = w.find("Room"), w.find("SheetContent")
		t.expect(w.find("Title").Parent.Name).toBe("Header")
		t.expect(w.find("Close").Parent.Name).toBe("Header")
		t.expect(body.ClassName).toBe("ScrollingFrame")
		t.expect(body.Parent).toBe(room)
		t.expect(w.find("Header").Parent).toBe(room)
		t.expect(room.ScrollingEnabled).toBe(false)
		t.expect(body.ScrollingEnabled).toBe(true)
		t.expect(w.find("Copy").Parent).toBe(w.find("SheetFlow"))
		t.expect(w.find("SheetFlow"):IsDescendantOf(body)).toBe(true)
		w.stop()
	end)

	t.it("contentInset none drops only the body padding", function()
		local w = mount()
		t.expect(w.find("SheetFlow"):FindFirstChildWhichIsA("UIPadding").PaddingLeft.Offset).toBe(8)
		w.stop()
		local none = mount({ contentInset = "none" })
		t.expect(none.find("SheetFlow"):FindFirstChildWhichIsA("UIPadding").PaddingLeft.Offset).toBe(0)
		t.expect(none.find("SheetPanel"):FindFirstChildWhichIsA("UIPadding").PaddingLeft.Offset).toBe(16)
		none.stop()
	end)

	t.it("a header replaces the title; header=false removes it; utilities stay", function()
		local w = mount({
			header = built(function(_, Host)
				return Host.TextLabel "Custom" { Text = "Lobby" }
			end),
		})
		t.expect(w.find("Title")).toBeNil()
		t.expect(w.find("Custom").Parent.Name).toBe("Header")
		t.expect(w.find("Close").Parent.Name).toBe("Header")
		t.expect(w.find("Grabber") ~= nil).toBe(true)
		w.stop()
		local bare = mount({ header = false })
		t.expect(bare.find("Title")).toBeNil()
		t.expect(bare.find("Close").Parent.Name).toBe("Header")
		bare.stop()
	end)

	t.it("pinned actions stay reachable over a long body; Cancel runs the cancel action", function()
		local pressed = {}
		local function log(name: string): () -> ()
			return function()
				table.insert(pressed, name)
			end
		end
		local w = mount({
			actions = {
				{ id = "Later", label = "Later", role = "cancel", onActivate = log("Later") },
				{ id = "Join", label = "Join race", role = "default", onActivate = log("Join") },
			},
		})
		local actions, body = w.find("Actions"), w.find("SheetContent")
		t.expect(actions.Parent).toBe(w.find("Room"))
		t.expect(actions:IsDescendantOf(body)).toBe(false)
		overlay.find(actions, "Join").Activated.fire()
		t.expect(table.concat(pressed, ",")).toBe("Join")
		t.expect(w.shown:peek()).toBe(true)
		w.find("ModalBack").Pressed.fire()
		t.expect(table.concat(pressed, ",")).toBe("Join,Later")
		t.expect(w.shown:peek()).toBe(true)
		w.stop()
	end)

	t.it("a room too small for the pinned regions unpins them into one scroller", function()
		local w = mount({
			actionLayout = "stacked",
			actions = {
				{ id = "One", label = "One", onActivate = noop },
				{ id = "Two", label = "Two", onActivate = noop },
				{ id = "Three", label = "Three", onActivate = noop },
			},
		}, { room = Vector2.new(800, 400), reducedMotion = true })
		local room, body = w.find("Room"), w.find("SheetContent")
		w.size(w.find("Header"), 500, 44)
		w.size(w.find("Actions"), 500, 3 * 44 + 16)
		content(w, 900)
		t.expect(room.ScrollingEnabled).toBe(true)
		t.expect(body.ScrollingEnabled).toBe(false)
		t.expect(body.Size.Y.Offset).toBe(900)
		t.expect(body:FindFirstChildWhichIsA("UIFlexItem").FlexMode).toBe(w.Enum.UIFlexMode.None)
		t.expect(overlay.find(w.find("Actions"), "Three"):IsDescendantOf(room)).toBe(true)
		t.expect(room.Selectable).toBe(false)
		local one, three = overlay.find(w.find("Actions"), "One"), overlay.find(w.find("Actions"), "Three")
		w.at(room, 0, 200)
		w.size(room, 500, 150)
		room.AbsoluteWindowSize = Vector2.new(500, 150)
		room.AbsoluteCanvasSize = Vector2.new(500, 1200)
		for _, node in { overlay.find(w.find("Actions"), "Two"), one, three } do
			w.size(node, 500, 44)
		end
		w.at(one, 0, 1100)
		w.at(overlay.find(w.find("Actions"), "Two"), 0, 1152)
		w.at(three, 0, 1204)
		local close = w.find("Close")
		w.at(close, 450, 210)
		w.size(close, 44, 44)
		w.gui.SelectedObject = close
		w.advance(1 / 60)
		w.input.InputBegan.fire({ KeyCode = w.Enum.KeyCode.DPadDown })
		w.advance(1 / 10, 6)
		t.expect(w.gui.SelectedObject).toBe(one)
		t.expect(room.CanvasPosition.Y).toBe(1100 + 44 - 350)
		w.detent:set("large")
		w.advance(0.5, 5)
		w.find("Modal").AbsoluteSize = Vector2.new(800, 900)
		t.expect(room.ScrollingEnabled).toBe(false)
		t.expect(body.ScrollingEnabled).toBe(true)
		t.expect(body:FindFirstChildWhichIsA("UIFlexItem").FlexMode).toBe(w.Enum.UIFlexMode.Fill)
		w.stop()
	end)

	t.it("a sticky image hero stays pinned; header=false puts Close over it", function()
		local w = mount({ header = false, hero = { image = "rbxassetid://1", height = 160, sticky = true } })
		local hero = w.find("Hero")
		t.expect(hero.Parent).toBe(w.find("Room"))
		t.expect(hero.Size.Y.Offset).toBe(160)
		local close = w.find("Close")
		t.expect(close:IsDescendantOf(hero)).toBe(true)
		t.expect(w.find("Header")).toBeNil()
		t.expect(close.Size.Y.Offset >= 44).toBe(true)
		close.Activated.fire()
		t.expect(w.shown:peek()).toBe(false)
		w.stop()
	end)

	t.it("a scrolling content hero reserves the utility strip; utilities stay pinned", function()
		local w = mount({
			header = false,
			hero = built(function(UI)
				return { height = 200, content = UI.Button "Top" { label = "Top of hero" } }
			end),
		})
		local hero = w.find("Hero")
		t.expect(hero:IsDescendantOf(w.find("SheetContent"))).toBe(true)
		local strip, top = w.find("Strip"), w.find("Top")
		t.expect(strip.Size.Y.Offset).toBe(44)
		t.expect(strip.LayoutOrder < top.LayoutOrder).toBe(true)
		t.expect(w.find("Close"):IsDescendantOf(w.find("Utilities"))).toBe(true)
		w.stop()
	end)

	t.it("a non-sticky hero spans the panel width without the body inset", function()
		local w = mount({ hero = { image = "rbxassetid://1", aspectRatio = 16 / 9 } })
		local hero, body = w.find("Hero"), w.find("SheetFlow")
		t.expect(hero.Parent).toBe(body)
		t.expect(body:FindFirstChildWhichIsA("UIPadding")).toBeNil()
		t.expect(w.find("Copy").Parent.Name).toBe("Inset")
		t.expect(w.find("Inset"):FindFirstChildWhichIsA("UIPadding").PaddingLeft.Offset).toBe(8)
		t.expect(hero.Size.X.Scale).toBe(1)
		hero.AbsoluteSize = w.engine.types.Vector2.new(480, 0)
		t.expect(hero.Size.Y.Offset).toBe(math.floor(480 / (16 / 9) + 0.5))
		hero.AbsoluteSize = w.engine.types.Vector2.new(320, 180)
		t.expect(hero.Size.Y.Offset).toBe(180)
		w.stop()
	end)

	t.it("the keyboard takes its room from the one safe rectangle", function()
		local w = mount(
			{ actions = { { id = "Go", label = "Go", onActivate = noop } } },
			{ detent = "large", reducedMotion = true }
		)
		local panel = w.find("SheetPanel")
		local tall = panel.Size.Y.Offset
		w.input.OnScreenKeyboardSize = Vector2.new(800, 250)
		w.input.OnScreenKeyboardVisible = true
		t.expect(panel.Size.Y.Offset).toBe(math.floor(350 * 0.95))
		t.expect(panel.Position.Y.Offset).toBe(-250)
		t.expect(panel.Size.Y.Offset < tall).toBe(true)
		t.expect(w.find("Actions"):IsDescendantOf(panel)).toBe(true)
		w.input.OnScreenKeyboardVisible = false
		t.expect(panel.Size.Y.Offset).toBe(tall)
		w.stop()
	end)

	t.it("refuses malformed header, hero, actions and inset before mounting", function()
		for _, change in
			{
				{ header = true } :: any,
				{ header = "Title" },
				{ contentInset = "wide" },
				{ hero = { image = "rbxassetid://1", content = function() end, height = 10 } },
				{ hero = { height = 10 } },
				{ hero = { content = function() end, height = 10, scaleMode = "fit" } },
				{ hero = { image = "rbxassetid://1", height = 10, sticky = "yes" } },
				{ actions = { { id = "A", label = "A" } } },
				{
					actions = {
						{ id = "A", label = "A", role = "default", onActivate = noop },
						{ id = "B", label = "B", role = "default", onActivate = noop },
					},
				},
				{ actionLayout = "grid" },
			}
		do
			local ok = pcall(function()
				mount(change).stop()
			end)
			t.expect(ok).toBe(false)
		end
	end)

	t.it("hug fits the whole body plus the pinned regions, and follows live copy both ways", function()
		local w = mount({
			detents = { "hug", "large" },
			actions = { { id = "Go", label = "Go", onActivate = noop } },
		}, { detent = "hug", reducedMotion = true })
		local panel, body = w.find("SheetPanel"), w.find("SheetContent")
		w.size(w.find("Header"), 500, 44)
		w.size(w.find("Actions"), 500, 44)
		content(w, 120)
		local chrome = 20 + 24 + 8 + 8
		local pinned = 44 + 44 + 2 * 8
		local short = panel.Size.Y.Offset
		t.expect(short).toBe(math.max(208, 120 + pinned + chrome))
		t.expect(body.Size.Y.Offset >= 120).toBe(true)
		content(w, 300)
		local tall = panel.Size.Y.Offset
		t.expect(tall).toBe(300 + pinned + chrome)
		t.expect(body.Size.Y.Offset >= 300).toBe(true)
		content(w, 120)
		t.expect(panel.Size.Y.Offset).toBe(short)
		t.expect(w.builds()).toBe(1)
		w.stop()
	end)

	t.it("hug measures the content, not the scroll canvas that fills the window", function()
		local w = mount({ detents = { "hug" } }, { detent = "hug" })
		local panel, body = w.find("SheetPanel"), w.find("SheetContent")
		content(w, 120)
		w.advance(1, 30)
		local settled = panel.Size.Y.Offset
		for _ = 1, 20 do
			body.AbsoluteCanvasSize = Vector2.new(500, math.max(body.Size.Y.Offset, 120) + 40)
			w.advance(1 / 60)
			t.expect(panel.Size.Y.Offset).toBe(settled)
		end
		w.stop()
	end)

	t.it("text and height settle off screen before the sheet moves, and hold during the slide", function()
		local w = mount({ detents = { "hug" } }, { detent = "hug", unsettled = true })
		local panel = w.find("SheetPanel")
		content(w, 40)
		w.advance(1 / 60)
		t.expect(panel.Position.Y.Offset).toBe(panel.Size.Y.Offset)
		content(w, 160)
		w.advance(1 / 60)
		t.expect(panel.Position.Y.Offset).toBe(panel.Size.Y.Offset)
		w.advance(1 / 60)
		local height = panel.Size.Y.Offset
		local previous = panel.Position.Y.Offset
		for _ = 1, 20 do
			w.advance(1 / 60)
			t.expect(panel.Size.Y.Offset).toBe(height)
			t.expect(panel.Position.Y.Offset <= previous).toBe(true)
			previous = panel.Position.Y.Offset
		end
		t.expect(previous).toBe(0)
		w.stop()
	end)

	t.it("a late text size change, such as a font that loads, holds the sheet off screen", function()
		local w = mount(nil, { unsettled = true })
		local panel, title = w.find("SheetPanel"), w.find("Title")
		title.TextBounds = Vector2.new(75, 12)
		w.advance(1 / 60)
		title.TextBounds = Vector2.new(143, 25)
		w.advance(1 / 60)
		w.advance(1 / 60)
		t.expect(panel.Position.Y.Offset).toBe(panel.Size.Y.Offset)
		w.advance(1 / 60)
		w.advance(1 / 60)
		t.expect(panel.Position.Y.Offset < panel.Size.Y.Offset).toBe(true)
		w.stop()
	end)

	t.it("reduced motion also waits for the settled layout, then appears at rest", function()
		local w = mount(nil, { unsettled = true, reducedMotion = true })
		local panel = w.find("SheetPanel")
		t.expect(panel.Position.Y.Offset).toBe(panel.Size.Y.Offset)
		w.advance(1 / 300, 2)
		t.expect(panel.Position.Y.Offset).toBe(0)
		w.stop()
	end)

	t.it("hug clamps to the safe room and keeps the minimum floor", function()
		local w = mount({ detents = { "hug" } }, { detent = "hug", reducedMotion = true })
		content(w, 5000)
		t.expect(w.find("SheetPanel").Size.Y.Offset).toBe(600)
		content(w, 1)
		t.expect(w.find("SheetPanel").Size.Y.Offset).toBe(4 * 44 + 2 * 16)
		w.stop()
	end)

	t.it("coinciding heights keep the declared id; Size cycles distinct ids; ties keep the current", function()
		local w = mount({
			detents = { { id = "a", height = 300 }, { id = "b", height = 300 }, "large" },
		}, { detent = "b", reducedMotion = true })
		t.expect(w.detent:peek()).toBe("b")
		t.expect(w.find("SheetPanel").Size.Y.Offset).toBe(300)
		local seen = {}
		for _ = 1, 3 do
			w.find("Grabber").Activated.fire()
			table.insert(seen, w.detent:peek())
		end
		t.expect(seen).toEqual({ "large", "a", "b" })
		local drag = w.find("UIDragDetector")
		drag.DragStart.fire(w.Vector2.new(0, 0))
		w.tick(0.5)
		drag.DragContinue.fire(w.Vector2.new(0, 2))
		w.tick(0.5)
		drag.DragEnd.fire()
		t.expect(w.detent:peek()).toBe("b")
		w.stop()
	end)

	t.it("an invalid late detent keeps the last geometry and a valid one recovers", function()
		local w = mount(nil, { reducedMotion = true })
		local panel = w.find("SheetPanel")
		local before = panel.Size.Y.Offset
		w.detent:set("bogus")
		t.expect(panel.Size.Y.Offset).toBe(before)
		w.detent:set("large")
		t.expect(panel.Size.Y.Offset).toBe(570)
		w.stop()
	end)

	t.it("refuses a malformed hug entry", function()
		for _, detents in { { "hug", "hug" } :: any, { { id = "hug", fraction = 0.5 }, "hug" }, { "Hug" } } do
			local ok = pcall(function()
				mount({ detents = detents }, { detent = "hug" }).stop()
			end)
			t.expect(ok).toBe(false)
		end
	end)

	t.it("action callbacks that throw, close or dispose leave no stale surface", function()
		local shown = Compose.cell(false)
		local mounted = Compose.cell(true)
		local w = overlay.new(function(UI, Host)
			return Host.Frame({
				Compose.show(mounted, function()
					return UI.Sheet "Sheet" {
						isPresented = shown,
						detent = Compose.cell("large"),
						title = "T",
						content = function()
							return Host.TextLabel "Body" { Text = "Body" }
						end,
						actions = {
							{
								id = "Boom",
								label = "Boom",
								onActivate = function()
									error("caller bug")
								end,
							},
							{
								id = "Finish",
								label = "Done",
								onActivate = function()
									shown:set(false)
									shown:set(true)
								end,
							},
							{
								id = "Drop",
								label = "Drop",
								onActivate = function()
									mounted:set(false)
								end,
							},
						},
					}
				end),
			})
		end)
		local baseline = w.engine.census()
		shown:set(true)
		t.expect((pcall(overlay.find(w.find("Actions"), "Boom").Activated.fire))).toBe(false)
		t.expect(w.find("SheetPanel") ~= nil).toBe(true)
		overlay.find(w.find("Actions"), "Finish").Activated.fire()
		t.expect(w.find("SheetPanel") ~= nil).toBe(true)
		t.expect(shown:peek()).toBe(true)
		overlay.find(w.find("Actions"), "Drop").Activated.fire()
		t.expect(w.find("SheetPanel")).toBeNil()
		mounted:set(true)
		shown:set(false)
		local after = w.engine.census()
		t.expect(after.live).toBe(baseline.live)
		w.stop()
	end)

	t.it("a failing content build does not leave a surface behind", function()
		local failures = {}
		local shown = Compose.cell(true)
		local w = overlay.new(function(UI)
			return UI.Sheet "Sheet" {
				isPresented = shown,
				detent = Compose.cell("medium"),
				title = "T",
				content = function(): Instance
					error("content failed")
				end,
			}
		end)
		t.expect(w.find("SheetPanel")).toBeNil()
		t.expect(shown:peek()).toBe(false)
		t.expect(string.find(tostring(w.find("Sheet"):GetAttribute("FacetError")), "content failed", 1, true) ~= nil)
			.toBe(true)
		t.expect(#failures).toBe(0)
		w.stop()
	end)
end)

t.describe("native Sheet: gestures", function()
	local function flick(w: any, steps: { { number } }, finish: boolean?)
		local drag = w.find("UIDragDetector")
		local y = 0
		drag.DragStart.fire(w.Vector2.new(0, y))
		for _, step in steps do
			w.tick(step[2])
			y += step[1]
			drag.DragContinue.fire(w.Vector2.new(0, y))
		end
		if finish ~= false then
			drag.DragEnd.fire()
		end
		return drag
	end

	t.it("a fast flick projects past the nearest detent; a slow drag does not", function()
		local w = mount(nil, { reducedMotion = true })
		flick(w, { { -40, 0.01 }, { -40, 0.01 } })
		t.expect(380 + 4000 * release.PROJECTION_S > 570).toBe(true)
		t.expect(w.detent:peek()).toBe("large")
		w.stop()
		local slow = mount(nil, { reducedMotion = true })
		flick(slow, { { -40, 0.5 }, { -40, 0.5 } })
		t.expect(slow.detent:peek()).toBe("medium")
		slow.stop()
	end)

	t.it("a hold after motion does not fling", function()
		local w = mount(nil, { reducedMotion = true })
		local drag = flick(w, { { -80, 0.01 } }, false)
		w.tick(0.6)
		drag.DragEnd.fire()
		t.expect(w.detent:peek()).toBe("medium")
		w.stop()
	end)

	t.it("an unrelated input change carries the drag", function()
		local w = mount(nil, { reducedMotion = true })
		flick(w, { { -150, 0.1 } }, false)
		w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
		t.expect(w.find("SheetPanel").Size.Y.Offset).toBe(450)
		w.stop()
	end)

	t.it("an external detent change during a drag wins and drops the stale session", function()
		local w = mount(nil, { reducedMotion = true })
		local drag = flick(w, { { -100, 0.1 } }, false)
		w.detent:set("large")
		t.expect(w.find("SheetPanel").Size.Y.Offset).toBe(570)
		drag.DragContinue.fire(w.Vector2.new(0, -400))
		drag.DragEnd.fire()
		t.expect(w.detent:peek()).toBe("large")
		t.expect(w.find("SheetPanel").Size.Y.Offset).toBe(570)
		w.stop()
	end)

	t.it("the panel's native detector acquires only past the pointer slop", function()
		local w = mount(nil, { reducedMotion = true })
		local panel = w.find("SheetPanel")
		local detector = w.find("PanelDrag")
		t.expect(detector.Parent).toBe(panel)
		detector.DragStart.fire(w.Vector2.new(400, 300))
		w.tick(0.05)
		detector.DragContinue.fire(w.Vector2.new(400, 296))
		t.expect(panel.Size.Y.Offset).toBe(300)
		w.tick(0.5)
		detector.DragContinue.fire(w.Vector2.new(400, 50))
		t.expect(panel.Size.Y.Offset).toBe(300 + 250 - 6)
		w.tick(0.5)
		detector.DragEnd.fire()
		t.expect(w.detent:peek()).toBe("large")
		w.input.PreferredInput = w.Enum.PreferredInput.Touch
		detector.DragStart.fire(w.Vector2.new(400, 300))
		detector.DragContinue.fire(w.Vector2.new(400, 310))
		t.expect(panel.Size.Y.Offset).toBe(570)
		detector.DragEnd.fire()
		w.stop()
	end)

	t.it("a drag on the panel drives the sheet; a second stream cannot take it over", function()
		local w = mount(nil, { reducedMotion = true })
		local detector, grip = w.find("PanelDrag"), w.find("UIDragDetector")
		detector.DragStart.fire(w.Vector2.new(400, 300))
		w.tick(0.3)
		detector.DragContinue.fire(w.Vector2.new(400, 100))
		local height = w.find("SheetPanel").Size.Y.Offset
		t.expect(height).toBe(300 + 200 - 6)
		grip.DragStart.fire(w.Vector2.new(0, 0))
		grip.DragContinue.fire(w.Vector2.new(0, 300))
		grip.DragEnd.fire()
		t.expect(w.find("SheetPanel").Size.Y.Offset).toBe(height)
		t.expect(w.shown:peek()).toBe(true)
		w.tick(0.3)
		detector.DragEnd.fire()
		t.expect(w.detent:peek()).toBe("large")
		w.stop()
		local touch = mount(nil, { reducedMotion = true })
		touch.input.PreferredInput = touch.Enum.PreferredInput.Touch
		local panel = touch.find("PanelDrag")
		panel.DragStart.fire(touch.Vector2.new(400, 300))
		panel.DragContinue.fire(touch.Vector2.new(400, 290))
		t.expect(touch.find("SheetPanel").Size.Y.Offset).toBe(300)
		panel.DragContinue.fire(touch.Vector2.new(400, 100))
		t.expect(touch.find("SheetPanel").Size.Y.Offset).toBe(300 + 200 - 14)
		panel.DragEnd.fire()
		touch.stop()
	end)

	t.it(
		"default scrollPolicy never hands a body pan to the sheet; atLargestDetent yields below the tallest",
		function()
			local w = mount(nil, { reducedMotion = true })
			t.expect(w.find("SheetContent").ScrollingEnabled).toBe(true)
			w.stop()
			local policy = mount({ scrollPolicy = "atLargestDetent" }, { reducedMotion = true })
			local body = policy.find("SheetContent")
			t.expect(body.ScrollingEnabled).toBe(false)
			t.expect(body.Active).toBe(false)
			policy.detent:set("large")
			t.expect(body.ScrollingEnabled).toBe(true)
			t.expect(body.Active).toBe(true)
			policy.stop()
		end
	)

	t.it("resistance holds a dismissal-disabled sheet near its lowest detent", function()
		local w = mount({ interactiveDismissDisabled = true }, { reducedMotion = true })
		local drag = flick(w, { { 400, 0.5 } }, false)
		local height = w.find("SheetPanel").Size.Y.Offset
		t.expect(height >= 300 - 44 and height < 300).toBe(true)
		w.tick(0.5)
		drag.DragEnd.fire()
		t.expect(w.shown:peek()).toBe(true)
		t.expect(w.find("SheetPanel").Size.Y.Offset).toBe(300)
		w.stop()
	end)

	t.it("a flick hands its speed to the settle; reduced motion snaps", function()
		local w = mount()
		flick(w, { { -40, 0.01 }, { -40, 0.01 } })
		t.expect(w.detent:peek()).toBe("large")
		t.expect(w.find("SheetPanel").Size.Y.Offset).toBe(380)
		w.advance(1 / 60)
		local early = w.find("SheetPanel").Size.Y.Offset
		t.expect(`early {early}: {early > 380 + 40 and early < 570}`).toBe(`early {early}: true`)
		local peak = 0
		for _ = 1, 60 do
			w.advance(1 / 60)
			peak = math.max(peak, w.find("SheetPanel").Size.Y.Offset)
		end
		t.expect(peak <= 570).toBe(true)
		w.advance(1, 30)
		t.expect(w.find("SheetPanel").Size.Y.Offset).toBeCloseTo(570, 0.5)
		w.stop()
		local snap = mount(nil, { reducedMotion = true })
		flick(snap, { { -40, 0.01 }, { -40, 0.01 } })
		t.expect(snap.find("SheetPanel").Size.Y.Offset).toBe(570)
		snap.stop()
	end)

	t.it("disposal mid-drag releases the session and returns to baseline", function()
		local mounted = Compose.cell(false)
		local w = overlay.new(function(UI, Host)
			return Host.Frame({
				Compose.show(mounted, function()
					return UI.Sheet "Sheet" {
						isPresented = Compose.cell(true),
						detent = Compose.cell("medium"),
						title = "T",
						content = function()
							return Host.TextLabel "Body" { Text = "Body" }
						end,
					}
				end),
			})
		end, { reducedMotion = true })
		local baseline = w.engine.census()
		mounted:set(true)
		flick(w, { { -100, 0.1 } }, false)
		w.find("PanelDrag").DragStart.fire(w.Vector2.new(0, 0))
		mounted:set(false)
		t.expect(w.find("SheetPanel")).toBeNil()
		local after = w.engine.census()
		t.expect(after.live).toBe(baseline.live)
		t.expect(after.connections).toBe(baseline.connections)
		w.stop()
	end)
end)
