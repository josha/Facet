--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type SheetDetent = typeof(require("@repo/tools/typecheck/aliases").SheetDetent)
	type OverlayAction = typeof(require("@repo/tools/typecheck/aliases").OverlayAction)

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
		local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
			local spec: any = {
				isPresented = shown,
				detent = detent,
				title = "Race details",
				content = function(): Instance
					builds += 1
					return Host.TextLabel "Copy" { Text = LONG, TextWrapped = true }
				end,
			}
			for key, value in (extra or {} :: { [string]: any }) do
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

	verifyHarness:suite("native Sheet: placement, width, title and close", function()
		verifyHarness:case("a function-bound title renders as its type promises", {
			id = "native_sheet_parts::native Sheet: placement, width, title and close::a function-bound title renders as its type promises",
			run = function()
				local w = mount({
					title = function()
						return "Live title"
					end,
				})
				Verify.expect(w.find("Title").Text):toBe("Live title")
				w.stop()
			end,
		})

		verifyHarness:case("explicit placements pin the panel to the bottom or the center", {
			id = "native_sheet_parts::native Sheet: placement, width, title and close::explicit placements pin the panel to the bottom or the center",
			run = function()
				local w = mount({ placement = "bottom" :: "bottom" })
				local panel = w.find("SheetPanel")
				Verify.expect(panel.AnchorPoint):toBe(w.Vector2.new(0.5, 1))
				Verify.expect(panel.Position.Y.Scale):toBe(1)
				Verify.expect(panel.Position.X.Scale):toBe(0.5)
				w.stop()
				local c = mount({ placement = "center" :: "center" })
				local centered = c.find("SheetPanel")
				Verify.expect(centered.AnchorPoint):toBe(c.Vector2.new(0.5, 0.5))
				Verify.expect(centered.Position.Y.Scale):toBe(0.5)
				c.stop()
				local a = mount({ placement = "automatic" :: "automatic" })
				Verify.expect(a.find("SheetPanel").AnchorPoint):toBe(a.Vector2.new(0.5, 1))
				a.stop()
			end,
		})

		verifyHarness:case("side placement docks to its physical edge, detents stay vertical", {
			id = "native_sheet_parts::native Sheet: placement, width, title and close::side placement docks to its physical edge, detents stay vertical",
			run = function()
				local w = mount(
					{ placement = "side" :: "side" },
					{ room = Vector2.new(1200, 800), motionLevel = "none" }
				)
				local panel = w.find("SheetPanel")
				Verify.expect(panel.AnchorPoint):toBe(w.Vector2.new(1, 1))
				Verify.expect(panel.Position.X.Scale):toBe(1)
				Verify.expect(panel.Position.X.Offset):toBe(0)
				Verify.expect(panel.Position.Y.Scale):toBe(1)
				Verify.expect(panel.Size.Y.Offset):toBe(400)
				w.stop()
				local left = mount(
					{ placement = "side" :: "side", edge = "left" :: "left", width = "narrow" :: "narrow" },
					{ room = Vector2.new(1200, 800), motionLevel = "none" }
				)
				local leftPanel = left.find("SheetPanel")
				Verify.expect(leftPanel.AnchorPoint):toBe(left.Vector2.new(0, 1))
				Verify.expect(leftPanel.Position.X.Scale):toBe(0)
				Verify.expect(leftPanel.Size.X.Offset):toBe(360)
				left.stop()
			end,
		})

		verifyHarness:case("width presets reuse the dialog widths, bounded by safe room", {
			id = "native_sheet_parts::native Sheet: placement, width, title and close::width presets reuse the dialog widths, bounded by safe room",
			run = function()
				local widths = {}
				for _, preset in { "narrow", "automatic", "wide" } :: { "automatic" | "narrow" | "wide" } do
					local w = mount(
						{ width = preset :: "automatic" | "narrow" | "wide" },
						{ room = Vector2.new(1200, 800) }
					)
					widths[preset] = w.find("SheetPanel").Size.X.Offset
					w.stop()
				end
				Verify.expect(widths):toEqual({ narrow = 360, automatic = 560, wide = 800 })
				local narrow = mount({ width = "wide" :: "wide" }, { room = Vector2.new(500, 800) })
				Verify.expect(narrow.find("SheetPanel").Size.X.Offset):toBe(500)
				narrow.stop()
			end,
		})

		verifyHarness:case("side sheets enter and leave toward their own edge", {
			id = "native_sheet_parts::native Sheet: placement, width, title and close::side sheets enter and leave toward their own edge",
			run = function()
				local w = mount(
					{ placement = "side" :: "side", edge = "left" :: "left" },
					{ room = Vector2.new(1200, 800), unsettled = true }
				)
				local panel = w.find("SheetPanel")
				Verify.expect(panel.Position.X.Offset):toBe(-560)
				w.advance(1 / 300, 2)
				w.advance(0.3, 6)
				Verify.expect(panel.Position.X.Offset):toBe(0)
				w.shown:set(false)
				Verify.expect((w.find("SheetPanel"))):toBe(panel)
				w.advance(0.1, 2)
				Verify.expect(panel.Position.X.Offset < 0):toBe(true)
				w.advance(0.3, 6)
				Verify.expect((w.find("SheetPanel"))):toBeNil()
				w.stop()
				local right = mount(
					{ placement = "side" :: "side" },
					{ room = Vector2.new(1200, 800), unsettled = true }
				)
				Verify.expect(right.find("SheetPanel").Position.X.Offset):toBe(560)
				right.stop()
				local bottom = mount(nil, { room = Vector2.new(1200, 800), unsettled = true })
				Verify.expect(bottom.find("SheetPanel").Position.X.Offset):toBe(0)
				bottom.shown:set(false)
				Verify.expect((bottom.find("SheetPanel"))):toBeNil()
				bottom.stop()
			end,
		})

		verifyHarness:case("closeButton=false removes Close; Size and interactive dismissal remain", {
			id = "native_sheet_parts::native Sheet: placement, width, title and close::closeButton=false removes Close; Size and interactive dismissal remain",
			run = function()
				local w = mount({ closeButton = false })
				Verify.expect((w.find("Close"))):toBeNil()
				Verify.expect(w.find("Grabber").Selectable):toBe(true)
				w.find("ModalBack").Pressed.fire()
				Verify.expect((w.shown:peek())):toBe(false)
				w.stop()
				local label = Compose.cell("Fertig")
				local named = mount({ closeButton = label })
				local close = named.find("Close")
				Verify.expect(close.Text):toBe("Fertig")
				label:set("Schliessen")
				Verify.expect(close.Text):toBe("Schliessen")
				close.Activated.fire()
				Verify.expect((named.shown:peek())):toBe(false)
				named.stop()
			end,
		})

		verifyHarness:case("refuses malformed placement, edge, width and closeButton", {
			id = "native_sheet_parts::native Sheet: placement, width, title and close::refuses malformed placement, edge, width and closeButton",
			run = function()
				for _, change in
					{
						{ placement = "top" } :: any,
						{ edge = "left" :: "left" },
						{ placement = "side" :: "side", edge = "start" :: "start" },
						{ width = "huge" :: "huge" },
						{ closeButton = 4 },
						{ dragIndicator = "sometimes" },
						{ scrollPolicy = "never" },
					}
				do
					local ok = pcall(function()
						mount(change).stop()
					end)
					Verify.expect(ok):toBe(false)
				end
			end,
		})

		verifyHarness:case("the Size control reads player words, never a detent id", {
			id = "native_sheet_parts::native Sheet: placement, width, title and close::the Size control reads player words, never a detent id",
			run = function()
				local w = mount({
					detents = { "hug", "medium" } :: { SheetDetent },
				})
				local grabber = w.find("Grabber")
				Verify.expect((grabber:GetAttribute("AccessibleLabel"))):toBe("Close sheet")
				w.detent:set("hug")
				Verify.expect((grabber:GetAttribute("AccessibleLabel"))):toBe("Resize: Fit")
				w.stop()
				local custom = mount({
					detents = { { id = "compact", fraction = 0.3 }, "large" } :: { SheetDetent },
				}, { detent = "compact" })
				Verify.expect((custom.find("Grabber"):GetAttribute("AccessibleLabel"))):toBe("Resize: Compact")
				custom.stop()
			end,
		})
	end)

	verifyHarness:suite("native Sheet: parts", function()
		verifyHarness:case(
			"default parts: pinned title and utilities, one body scroller (the panel no longer scrolls)",
			{
				id = "native_sheet_parts::native Sheet: parts::default parts: pinned title and utilities, one body scroller (the panel no longer scrolls)",
				run = function()
					local w = mount({ closeButton = true })
					local room, body = w.find("Room"), w.find("SheetContent")
					Verify.expect(w.find("Title").Parent.Name):toBe("Header")
					Verify.expect(w.find("Close").Parent.Name):toBe("Header")
					Verify.expect(body.ClassName):toBe("ScrollingFrame")
					Verify.expect(body.Parent):toBe(room)
					Verify.expect(w.find("Header").Parent):toBe(room)
					Verify.expect(room.ScrollingEnabled):toBe(false)
					Verify.expect(body.ScrollingEnabled):toBe(true)
					Verify.expect(w.find("Copy").Parent):toBe(w.find("SheetFlow"))
					Verify.expect((w.find("SheetFlow"):IsDescendantOf(body))):toBe(true)
					w.stop()
				end,
			}
		)

		verifyHarness:case("contentInset none drops only the body padding", {
			id = "native_sheet_parts::native Sheet: parts::contentInset none drops only the body padding",
			run = function()
				local w = mount()
				Verify.expect(w.find("SheetFlow"):FindFirstChildWhichIsA("UIPadding").PaddingLeft.Offset):toBe(8)
				w.stop()
				local none = mount({ contentInset = "none" })
				Verify.expect(none.find("SheetFlow"):FindFirstChildWhichIsA("UIPadding").PaddingLeft.Offset):toBe(0)
				Verify.expect(none.find("SheetColumn"):FindFirstChildWhichIsA("UIPadding").PaddingLeft.Offset):toBe(16)
				none.stop()
			end,
		})

		verifyHarness:case("a header replaces the title; header=false removes it; utilities stay", {
			id = "native_sheet_parts::native Sheet: parts::a header replaces the title; header=false removes it; utilities stay",
			run = function()
				local w = mount({
					header = built(function(_, Host: RobloxHost)
						return Host.TextLabel "Custom" { Text = "Lobby" }
					end),
					closeButton = true,
				})
				Verify.expect((w.find("Title"))):toBeNil()
				Verify.expect(w.find("Custom").Parent.Name):toBe("Header")
				Verify.expect(w.find("Close").Parent.Name):toBe("Header")
				Verify.expect(w.find("Grabber") ~= nil):toBe(true)
				w.stop()
				local bare = mount({ header = false, closeButton = true })
				Verify.expect((bare.find("Title"))):toBeNil()
				Verify.expect(bare.find("Close").Parent.Name):toBe("Header")
				bare.stop()
			end,
		})

		verifyHarness:case("pinned actions stay reachable over a long body; Cancel runs the cancel action", {
			id = "native_sheet_parts::native Sheet: parts::pinned actions stay reachable over a long body; Cancel runs the cancel action",
			run = function()
				local pressed = {}
				local function log(name: string): () -> ()
					return function()
						table.insert(pressed, name)
					end
				end
				local w = mount({
					actions = {
						{ id = "Later", label = "Later", role = "cancel" :: "cancel", onActivate = log("Later") } :: OverlayAction,
						{ id = "Join", label = "Join race", role = "default" :: "default", onActivate = log("Join") } :: OverlayAction,
					},
				})
				local actions, body = w.find("Actions"), w.find("SheetContent")
				Verify.expect(actions.Parent):toBe(w.find("Room"))
				Verify.expect((actions:IsDescendantOf(body))):toBe(false)
				overlay.find(actions, "Join").Activated.fire()
				Verify.expect((table.concat(pressed, ","))):toBe("Join")
				Verify.expect((w.shown:peek())):toBe(true)
				w.find("ModalBack").Pressed.fire()
				Verify.expect((table.concat(pressed, ","))):toBe("Join,Later")
				Verify.expect((w.shown:peek())):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("a room too small for the pinned regions unpins them into one scroller", {
			id = "native_sheet_parts::native Sheet: parts::a room too small for the pinned regions unpins them into one scroller",
			run = function()
				local w = mount({
					closeButton = true,
					actionLayout = "stacked",
					actions = {
						{ id = "One", label = "One", onActivate = noop } :: OverlayAction,
						{ id = "Two", label = "Two", onActivate = noop } :: OverlayAction,
						{ id = "Three", label = "Three", onActivate = noop } :: OverlayAction,
					},
				}, { room = Vector2.new(800, 400), motionLevel = "none" })
				local room, body = w.find("Room"), w.find("SheetContent")
				w.size(w.find("Header"), 500, 44)
				w.size(w.find("Actions"), 500, 3 * 44 + 16)
				content(w, 900)
				Verify.expect(room.ScrollingEnabled):toBe(true)
				Verify.expect(body.ScrollingEnabled):toBe(false)
				Verify.expect(body.Size.Y.Offset):toBe(900)
				Verify.expect(body:FindFirstChildWhichIsA("UIFlexItem").FlexMode):toBe(w.Enum.UIFlexMode.None)
				Verify.expect((overlay.find(w.find("Actions"), "Three"):IsDescendantOf(room))):toBe(true)
				Verify.expect(room.Selectable):toBe(false)
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
				Verify.expect(w.gui.SelectedObject):toBe(one)
				Verify.expect(room.CanvasPosition.Y):toBe(1100 + 44 - 350)
				w.detent:set("large")
				w.advance(0.5, 5)
				w.find("Modal").AbsoluteSize = Vector2.new(800, 900)
				Verify.expect(room.ScrollingEnabled):toBe(false)
				Verify.expect(body.ScrollingEnabled):toBe(true)
				Verify.expect(body:FindFirstChildWhichIsA("UIFlexItem").FlexMode):toBe(w.Enum.UIFlexMode.Fill)
				w.stop()
			end,
		})

		verifyHarness:case("a sticky image hero stays pinned; header=false puts Close over it", {
			id = "native_sheet_parts::native Sheet: parts::a sticky image hero stays pinned; header=false puts Close over it",
			run = function()
				local w = mount({
					header = false,
					closeButton = true,
					hero = { image = "rbxassetid://1", height = 160, sticky = true },
				})
				local hero = w.find("Hero")
				Verify.expect(hero.Parent):toBe(w.find("Room"))
				Verify.expect(hero.Size.Y.Offset):toBe(160)
				local close = w.find("Close")
				Verify.expect((close:IsDescendantOf(hero))):toBe(true)
				Verify.expect((w.find("Header"))):toBeNil()
				Verify.expect(close.Size.Y.Offset >= 44):toBe(true)
				close.Activated.fire()
				Verify.expect((w.shown:peek())):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("a scrolling content hero reserves the utility strip; utilities stay pinned", {
			id = "native_sheet_parts::native Sheet: parts::a scrolling content hero reserves the utility strip; utilities stay pinned",
			run = function()
				local w = mount({
					header = false,
					closeButton = true,
					hero = built(function(UI: FacetControls)
						return { height = 200, content = UI.Button "Top" { label = "Top of hero" } }
					end),
				})
				local hero = w.find("Hero")
				Verify.expect((hero:IsDescendantOf(w.find("SheetContent")))):toBe(true)
				local strip, top = w.find("Strip"), w.find("Top")
				Verify.expect(strip.Size.Y.Offset):toBe(44)
				Verify.expect(strip.LayoutOrder < top.LayoutOrder):toBe(true)
				Verify.expect((w.find("Close"):IsDescendantOf(w.find("Utilities")))):toBe(true)
				Verify.expect((w.find("Close"):HasTag("facet-appearance-inverse"))):toBe(true)
				Verify.expect(w.find("Art"):FindFirstChildWhichIsA("UIPadding").PaddingLeft.Offset):toBe(16)
				w.stop()
			end,
		})

		verifyHarness:case(
			"a hero given as an Instance survives a dismissal and shows again on the next presentation",
			{
				id = "native_sheet_parts::native Sheet: parts::a hero given as an Instance survives a dismissal and shows again on the next presentation",
				run = function()
					local banner: any
					local w = mount({
						header = false,
						hero = built(function(_, Host: RobloxHost)
							banner = Host.TextLabel "Banner" { Text = "Lobby" }
							return { height = 140, content = banner }
						end),
					}, { motionLevel = "none" })
					Verify.expect((banner:IsDescendantOf(w.find("Hero")))):toBe(true)
					w.shown:set(false)
					w.advance(1 / 30, 60)
					Verify.expect((banner.isDestroyed())):toBe(false)
					w.shown:set(true)
					w.advance(1 / 300, 2)
					Verify.expect((w.shown:peek())):toBe(true)
					Verify.expect((banner:IsDescendantOf(w.find("Hero")))):toBe(true)
					w.stop()
				end,
			}
		)

		verifyHarness:case("content and a header given as Instances survive a dismissal and show again", {
			id = "native_sheet_parts::native Sheet: parts::content and a header given as Instances survive a dismissal and show again",
			run = function()
				local copy: any, head: any
				local w = mount({
					content = built(function(_, Host: RobloxHost)
						copy = Host.TextLabel "Body" { Text = "Body" }
						return copy
					end),
					header = built(function(_, Host: RobloxHost)
						head = Host.TextLabel "Head" { Text = "Head" }
						return head
					end),
				}, { motionLevel = "none" })
				for _ = 1, 2 do
					Verify.expect((copy:IsDescendantOf(w.find("SheetFlow")))):toBe(true)
					Verify.expect((w.find("Head"))):toBe(head)
					w.shown:set(false)
					w.advance(1 / 30, 60)
					Verify.expect((copy.isDestroyed())):toBe(false)
					Verify.expect((head.isDestroyed())):toBe(false)
					w.shown:set(true)
					w.advance(1 / 300, 2)
					Verify.expect((w.shown:peek())):toBe(true)
				end
				w.stop()
			end,
		})

		verifyHarness:case("a non-sticky hero spans the panel width without the body inset", {
			id = "native_sheet_parts::native Sheet: parts::a non-sticky hero spans the panel width without the body inset",
			run = function()
				local w = mount({ hero = { image = "rbxassetid://1", aspectRatio = 16 / 9 } })
				local hero, body = w.find("Hero"), w.find("SheetFlow")
				Verify.expect(hero.Parent):toBe(body)
				Verify.expect((body:FindFirstChildWhichIsA("UIPadding"))):toBeNil()
				Verify.expect(w.find("Copy").Parent.Name):toBe("Inset")
				Verify.expect(w.find("Inset"):FindFirstChildWhichIsA("UIPadding").PaddingLeft.Offset):toBe(8)
				Verify.expect(hero.Size.X.Scale):toBe(1)
				local ratio = hero:FindFirstChildWhichIsA("UIAspectRatioConstraint")
				Verify.expect(ratio.AspectRatio):toBe(16 / 9)
				Verify.expect(ratio.DominantAxis.Name):toBe("Width")
				w.stop()
			end,
		})

		verifyHarness:case("the keyboard takes its room from the one safe rectangle", {
			id = "native_sheet_parts::native Sheet: parts::the keyboard takes its room from the one safe rectangle",
			run = function()
				local w = mount({
					actions = {
						{ id = "Go", label = "Go", onActivate = noop } :: OverlayAction,
					},
				}, { detent = "large", motionLevel = "none" })
				local panel = w.find("SheetPanel")
				local tall = panel.Size.Y.Offset
				w.input.OnScreenKeyboardSize = Vector2.new(800, 250)
				w.input.OnScreenKeyboardVisible = true
				Verify.expect(panel.Size.Y.Offset):toBe(math.floor(350 * 0.95))
				Verify.expect(panel.Position.Y.Offset):toBe(-250)
				Verify.expect(panel.Size.Y.Offset < tall):toBe(true)
				Verify.expect((w.find("Actions"):IsDescendantOf(panel))):toBe(true)
				w.input.OnScreenKeyboardVisible = false
				Verify.expect(panel.Size.Y.Offset):toBe(tall)
				w.stop()
			end,
		})

		verifyHarness:case("refuses malformed header, hero, actions and inset before mounting", {
			id = "native_sheet_parts::native Sheet: parts::refuses malformed header, hero, actions and inset before mounting",
			run = function()
				for _, change in
					{
						{ header = true } :: any,
						{ header = "Title" },
						{ contentInset = "wide" },
						{ hero = { image = "rbxassetid://1", content = function() end, height = 10 } },
						{ hero = { height = 10 } },
						{ hero = { content = function() end, height = 10, scaleMode = "fit" :: "fit" } },
						{ hero = { image = "rbxassetid://1", height = 10, sticky = "yes" } },
						{ actions = { { id = "A", label = "A" } } },
						{
							actions = {
								{ id = "A", label = "A", role = "default" :: "default", onActivate = noop } :: OverlayAction,
								{ id = "B", label = "B", role = "default" :: "default", onActivate = noop } :: OverlayAction,
							},
						},
						{ actionLayout = "grid" },
					}
				do
					local ok = pcall(function()
						mount(change).stop()
					end)
					Verify.expect(ok):toBe(false)
				end
			end,
		})

		verifyHarness:case("hug fits the whole body plus the pinned regions, and follows live copy both ways", {
			id = "native_sheet_parts::native Sheet: parts::hug fits the whole body plus the pinned regions, and follows live copy both ways",
			run = function()
				local w = mount({
					detents = { "hug", "large" } :: { SheetDetent },
					actions = {
						{ id = "Go", label = "Go", onActivate = noop } :: OverlayAction,
					},
				}, { detent = "hug", motionLevel = "none" })
				local panel, body = w.find("SheetPanel"), w.find("SheetContent")
				w.size(w.find("Header"), 500, 44)
				w.size(w.find("Actions"), 500, 44)
				content(w, 120)
				local chrome = 20 + 24 + 8 + 8
				local pinned = 44 + 44 + 2 * 8
				local short = panel.Size.Y.Offset
				Verify.expect(short):toBe(math.max(208, 120 + pinned + chrome))
				Verify.expect(body.Size.Y.Offset >= 120):toBe(true)
				content(w, 300)
				local tall = panel.Size.Y.Offset
				Verify.expect(tall):toBe(300 + pinned + chrome)
				Verify.expect(body.Size.Y.Offset >= 300):toBe(true)
				content(w, 120)
				Verify.expect(panel.Size.Y.Offset):toBe(short)
				Verify.expect((w.builds())):toBe(1)
				w.stop()
			end,
		})

		verifyHarness:case("hug measures the content, not the scroll canvas that fills the window", {
			id = "native_sheet_parts::native Sheet: parts::hug measures the content, not the scroll canvas that fills the window",
			run = function()
				local w = mount({
					detents = { "hug" } :: { SheetDetent },
				}, { detent = "hug" })
				local panel, body = w.find("SheetPanel"), w.find("SheetContent")
				content(w, 120)
				w.advance(1, 30)
				local settled = panel.Size.Y.Offset
				for _ = 1, 20 do
					body.AbsoluteCanvasSize = Vector2.new(500, math.max(body.Size.Y.Offset, 120) + 40)
					w.advance(1 / 60)
					Verify.expect(panel.Size.Y.Offset):toBe(settled)
				end
				w.stop()
			end,
		})

		verifyHarness:case("text and height settle off screen before the sheet moves, and hold during the slide", {
			id = "native_sheet_parts::native Sheet: parts::text and height settle off screen before the sheet moves, and hold during the slide",
			run = function()
				local w = mount({
					detents = { "hug" } :: { SheetDetent },
				}, { detent = "hug", unsettled = true })
				local panel = w.find("SheetPanel")
				content(w, 40)
				w.advance(1 / 60)
				Verify.expect(panel.Position.Y.Offset):toBe(panel.Size.Y.Offset)
				content(w, 160)
				w.advance(1 / 60)
				Verify.expect(panel.Position.Y.Offset):toBe(panel.Size.Y.Offset)
				w.advance(1 / 60)
				local height = panel.Size.Y.Offset
				local previous = panel.Position.Y.Offset
				for _ = 1, 20 do
					w.advance(1 / 60)
					Verify.expect(panel.Size.Y.Offset):toBe(height)
					Verify.expect(panel.Position.Y.Offset <= previous):toBe(true)
					previous = panel.Position.Y.Offset
				end
				Verify.expect(previous):toBe(0)
				w.stop()
			end,
		})

		verifyHarness:case("a late text size change, such as a font that loads, holds the sheet off screen", {
			id = "native_sheet_parts::native Sheet: parts::a late text size change, such as a font that loads, holds the sheet off screen",
			run = function()
				local w = mount(nil, { unsettled = true })
				local panel, title = w.find("SheetPanel"), w.find("Title")
				title.TextBounds = Vector2.new(75, 12)
				w.advance(1 / 60)
				title.TextBounds = Vector2.new(143, 25)
				w.advance(1 / 60)
				w.advance(1 / 60)
				Verify.expect(panel.Position.Y.Offset):toBe(panel.Size.Y.Offset)
				w.advance(1 / 60)
				w.advance(1 / 60)
				Verify.expect(panel.Position.Y.Offset < panel.Size.Y.Offset):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("reduced motion also waits for the settled layout, then appears at rest", {
			id = "native_sheet_parts::native Sheet: parts::reduced motion also waits for the settled layout, then appears at rest",
			run = function()
				local w = mount(nil, { unsettled = true, motionLevel = "none" })
				local panel = w.find("SheetPanel")
				Verify.expect(panel.Position.Y.Offset):toBe(panel.Size.Y.Offset)
				w.advance(1 / 300, 2)
				Verify.expect(panel.Position.Y.Offset):toBe(0)
				w.stop()
			end,
		})

		verifyHarness:case("hug clamps to the safe room and keeps the minimum floor", {
			id = "native_sheet_parts::native Sheet: parts::hug clamps to the safe room and keeps the minimum floor",
			run = function()
				local w = mount({
					detents = { "hug" } :: { SheetDetent },
				}, { detent = "hug", motionLevel = "none" })
				content(w, 5000)
				Verify.expect(w.find("SheetPanel").Size.Y.Offset):toBe(600)
				content(w, 1)
				Verify.expect(w.find("SheetPanel").Size.Y.Offset):toBe(4 * 44 + 2 * 16)
				w.stop()
			end,
		})

		verifyHarness:case("coinciding heights keep the declared id; the grabber grows past ties, then closes", {
			id = "native_sheet_parts::native Sheet: parts::coinciding heights keep the declared id; the grabber grows past ties, then closes",
			run = function()
				local w = mount({
					detents = { { id = "a", height = 300 }, { id = "b", height = 300 }, "large" } :: { SheetDetent },
				}, { detent = "b", motionLevel = "none" })
				Verify.expect((w.detent:peek())):toBe("b")
				Verify.expect(w.find("SheetPanel").Size.Y.Offset):toBe(300)
				w.find("Grabber").Activated.fire()
				Verify.expect((w.detent:peek())):toBe("large")
				w.detent:set("b")
				local drag = w.find("UIDragDetector")
				drag.DragStart.fire(w.Vector2.new(0, 0))
				w.tick(0.5)
				drag.DragContinue.fire(w.Vector2.new(0, 2))
				w.tick(0.5)
				drag.DragEnd.fire()
				Verify.expect((w.detent:peek())):toBe("b")
				w.stop()
			end,
		})

		verifyHarness:case("an invalid late detent keeps the last geometry and a valid one recovers", {
			id = "native_sheet_parts::native Sheet: parts::an invalid late detent keeps the last geometry and a valid one recovers",
			run = function()
				local w = mount(nil, { motionLevel = "none" })
				local panel = w.find("SheetPanel")
				local before = panel.Size.Y.Offset
				w.detent:set("bogus")
				Verify.expect(panel.Size.Y.Offset):toBe(before)
				w.detent:set("large")
				Verify.expect(panel.Size.Y.Offset):toBe(570)
				w.stop()
			end,
		})

		verifyHarness:case("refuses a malformed hug entry", {
			id = "native_sheet_parts::native Sheet: parts::refuses a malformed hug entry",
			run = function()
				for _, detents in
					{
						{ "hug", "hug" } :: { any },
						{ { id = "hug", fraction = 0.5 }, "hug" } :: { any },
						{ "Hug" } :: { any },
					}
				do
					local ok = pcall(function()
						mount({ detents = detents }, { detent = "hug" }).stop()
					end)
					Verify.expect(ok):toBe(false)
				end
			end,
		})

		verifyHarness:case("action callbacks that throw, close or dispose leave no stale surface", {
			id = "native_sheet_parts::native Sheet: parts::action callbacks that throw, close or dispose leave no stale surface",
			run = function()
				local shown = Compose.cell(false)
				local mounted = Compose.cell(true)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						Compose.show(mounted, function()
							return UI.Sheet "Sheet" {
								isPresented = shown,
								detent = Compose.cell("large"),
								title = "T",
								content = function(): Instance
									return Host.TextLabel "Body" { Text = "Body" }
								end,
								actions = {
									{
										id = "Boom",
										label = "Boom",
										onActivate = function()
											error("caller bug")
										end,
									} :: OverlayAction,
									{
										id = "Finish",
										label = "Done",
										onActivate = function()
											shown:set(false)
											shown:set(true)
										end,
									} :: OverlayAction,
									{
										id = "Drop",
										label = "Drop",
										onActivate = function()
											mounted:set(false)
										end,
									} :: OverlayAction,
								},
							}
						end),
					})
				end)
				local baseline = w.engine.census()
				shown:set(true)
				Verify.expect((pcall(overlay.find(w.find("Actions"), "Boom").Activated.fire))):toBe(false)
				Verify.expect(w.find("SheetPanel") ~= nil):toBe(true)
				overlay.find(w.find("Actions"), "Finish").Activated.fire()
				Verify.expect(w.find("SheetPanel") ~= nil):toBe(true)
				Verify.expect((shown:peek())):toBe(true)
				overlay.find(w.find("Actions"), "Drop").Activated.fire()
				Verify.expect((w.find("SheetPanel"))):toBeNil()
				mounted:set(true)
				shown:set(false)
				local after = w.engine.census()
				Verify.expect(after.live):toBe(baseline.live)
				w.stop()
			end,
		})

		verifyHarness:case("a failing content build does not leave a surface behind", {
			id = "native_sheet_parts::native Sheet: parts::a failing content build does not leave a surface behind",
			run = function()
				local failures = {}
				local shown = Compose.cell(true)
				local w = overlay.new(function(UI: FacetControls)
					return UI.Sheet "Sheet" {
						isPresented = shown,
						detent = Compose.cell("medium"),
						title = "T",
						content = function(): Instance
							error("content failed")
						end,
					}
				end)
				Verify.expect((w.find("SheetPanel"))):toBeNil()
				Verify.expect((shown:peek())):toBe(false)
				Verify.expect(
					string.find(tostring(w.find("Sheet"):GetAttribute("FacetError")), "content failed", 1, true) ~= nil
				)
					:toBe(true)
				Verify.expect(#failures):toBe(0)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native Sheet: gestures", function()
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

		verifyHarness:case("a fast flick projects past the nearest detent; a slow drag does not", {
			id = "native_sheet_parts::native Sheet: gestures::a fast flick projects past the nearest detent; a slow drag does not",
			run = function()
				local w = mount(nil, { motionLevel = "none" })
				flick(w, { { -40, 0.01 }, { -40, 0.01 } })
				Verify.expect(380 + 4000 * release.PROJECTION_S > 570):toBe(true)
				Verify.expect((w.detent:peek())):toBe("large")
				w.stop()
				local slow = mount(nil, { motionLevel = "none" })
				flick(slow, { { -40, 0.5 }, { -40, 0.5 } })
				Verify.expect((slow.detent:peek())):toBe("medium")
				slow.stop()
			end,
		})

		verifyHarness:case("a hold after motion does not fling", {
			id = "native_sheet_parts::native Sheet: gestures::a hold after motion does not fling",
			run = function()
				local w = mount(nil, { motionLevel = "none" })
				local drag = flick(w, { { -80, 0.01 } }, false)
				w.tick(0.6)
				drag.DragEnd.fire()
				Verify.expect((w.detent:peek())):toBe("medium")
				w.stop()
			end,
		})

		verifyHarness:case("an unrelated input change carries the drag", {
			id = "native_sheet_parts::native Sheet: gestures::an unrelated input change carries the drag",
			run = function()
				local w = mount(nil, { motionLevel = "none" })
				flick(w, { { -150, 0.1 } }, false)
				w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
				Verify.expect(w.find("SheetPanel").Size.Y.Offset):toBe(450)
				w.stop()
			end,
		})

		verifyHarness:case("an external detent change during a drag wins and drops the stale session", {
			id = "native_sheet_parts::native Sheet: gestures::an external detent change during a drag wins and drops the stale session",
			run = function()
				local w = mount(nil, { motionLevel = "none" })
				local drag = flick(w, { { -100, 0.1 } }, false)
				w.detent:set("large")
				Verify.expect(w.find("SheetPanel").Size.Y.Offset):toBe(570)
				drag.DragContinue.fire(w.Vector2.new(0, -400))
				drag.DragEnd.fire()
				Verify.expect((w.detent:peek())):toBe("large")
				Verify.expect(w.find("SheetPanel").Size.Y.Offset):toBe(570)
				w.stop()
			end,
		})

		verifyHarness:case("the panel's native detector acquires only past the pointer slop", {
			id = "native_sheet_parts::native Sheet: gestures::the panel's native detector acquires only past the pointer slop",
			run = function()
				local w = mount(nil, { motionLevel = "none" })
				local panel = w.find("SheetPanel")
				local detector = w.find("PanelDrag")
				Verify.expect(detector.Parent):toBe(panel)
				detector.DragStart.fire(w.Vector2.new(400, 300))
				w.tick(0.05)
				detector.DragContinue.fire(w.Vector2.new(400, 296))
				Verify.expect(panel.Size.Y.Offset):toBe(300)
				w.tick(0.5)
				detector.DragContinue.fire(w.Vector2.new(400, 50))
				Verify.expect(panel.Size.Y.Offset):toBe(300 + 250 - 6)
				w.tick(0.5)
				detector.DragEnd.fire()
				Verify.expect((w.detent:peek())):toBe("large")
				w.input.PreferredInput = w.Enum.PreferredInput.Touch
				detector.DragStart.fire(w.Vector2.new(400, 300))
				detector.DragContinue.fire(w.Vector2.new(400, 310))
				Verify.expect(panel.Size.Y.Offset):toBe(570)
				detector.DragEnd.fire()
				w.stop()
			end,
		})

		verifyHarness:case("a drag on the panel drives the sheet; a second stream cannot take it over", {
			id = "native_sheet_parts::native Sheet: gestures::a drag on the panel drives the sheet; a second stream cannot take it over",
			run = function()
				local w = mount(nil, { motionLevel = "none" })
				local detector, grip = w.find("PanelDrag"), w.find("UIDragDetector")
				detector.DragStart.fire(w.Vector2.new(400, 300))
				w.tick(0.3)
				detector.DragContinue.fire(w.Vector2.new(400, 100))
				local height = w.find("SheetPanel").Size.Y.Offset
				Verify.expect(height):toBe(300 + 200 - 6)
				grip.DragStart.fire(w.Vector2.new(0, 0))
				grip.DragContinue.fire(w.Vector2.new(0, 300))
				grip.DragEnd.fire()
				Verify.expect(w.find("SheetPanel").Size.Y.Offset):toBe(height)
				Verify.expect((w.shown:peek())):toBe(true)
				w.tick(0.3)
				detector.DragEnd.fire()
				Verify.expect((w.detent:peek())):toBe("large")
				w.stop()
				local touch = mount(nil, { motionLevel = "none" })
				touch.input.PreferredInput = touch.Enum.PreferredInput.Touch
				local panel = touch.find("PanelDrag")
				panel.DragStart.fire(touch.Vector2.new(400, 300))
				panel.DragContinue.fire(touch.Vector2.new(400, 290))
				Verify.expect(touch.find("SheetPanel").Size.Y.Offset):toBe(300)
				panel.DragContinue.fire(touch.Vector2.new(400, 100))
				Verify.expect(touch.find("SheetPanel").Size.Y.Offset):toBe(300 + 200 - 14)
				panel.DragEnd.fire()
				Verify.expect(panel.Enabled):toBe(true)
				touch.input.PreferredInput = touch.Enum.PreferredInput.Gamepad
				Verify.expect(panel.Enabled):toBe(false)
				touch.stop()
			end,
		})

		verifyHarness:case(
			"default scrollPolicy never hands a body pan to the sheet; atLargestDetent yields below the tallest",
			{
				id = "native_sheet_parts::native Sheet: gestures::default scrollPolicy never hands a body pan to the sheet; atLargestDetent yields below the tallest",
				run = function()
					local w = mount(nil, { motionLevel = "none" })
					Verify.expect(w.find("SheetContent").ScrollingEnabled):toBe(true)
					w.stop()
					local policy = mount({ scrollPolicy = "atLargestDetent" }, { motionLevel = "none" })
					local body = policy.find("SheetContent")
					Verify.expect(body.ScrollingEnabled):toBe(false)
					Verify.expect(body.Active):toBe(false)
					policy.detent:set("large")
					Verify.expect(body.ScrollingEnabled):toBe(true)
					Verify.expect(body.Active):toBe(true)
					policy.stop()
				end,
			}
		)

		verifyHarness:case("resistance holds a dismissal-disabled sheet near its lowest detent", {
			id = "native_sheet_parts::native Sheet: gestures::resistance holds a dismissal-disabled sheet near its lowest detent",
			run = function()
				local w = mount({ interactiveDismissDisabled = true }, { motionLevel = "none" })
				local drag = flick(w, { { 400, 0.5 } }, false)
				local panel = w.find("SheetPanel")
				Verify.expect(panel.Size.Y.Offset):toBe(300)
				Verify.expect(panel.Position.Y.Offset > 0 and panel.Position.Y.Offset <= 44):toBe(true)
				w.tick(0.5)
				drag.DragEnd.fire()
				Verify.expect((w.shown:peek())):toBe(true)
				Verify.expect(w.find("SheetPanel").Size.Y.Offset):toBe(300)
				Verify.expect(w.find("SheetPanel").Position.Y.Offset):toBe(0)
				w.stop()
			end,
		})

		verifyHarness:case("a flick hands its speed to the settle and bounces under 2 percent; reduced motion snaps", {
			id = "native_sheet_parts::native Sheet: gestures::a flick hands its speed to the settle and bounces under 2 percent; reduced motion snaps",
			run = function()
				local w = mount()
				flick(w, { { -40, 0.01 }, { -40, 0.01 } })
				Verify.expect((w.detent:peek())):toBe("large")
				Verify.expect(w.find("SheetPanel").Size.Y.Offset):toBe(380)
				w.advance(1 / 60)
				local early = w.find("SheetPanel").Size.Y.Offset
				Verify.expect(`early {early}: {early > 380 + 40 and early < 570}`):toBe(`early {early}: true`)
				local peak = 0
				for _ = 1, 60 do
					w.advance(1 / 60)
					peak = math.max(peak, w.find("SheetPanel").Size.Y.Offset)
				end
				Verify.expect(peak > 570 and peak <= 570 * 1.02 + 1):toBe(true)
				w.advance(1, 30)
				Verify.expect(w.find("SheetPanel").Size.Y.Offset):toBeCloseTo(570, 0.5)
				w.stop()
				local snap = mount(nil, { motionLevel = "none" })
				flick(snap, { { -40, 0.01 }, { -40, 0.01 } })
				Verify.expect(snap.find("SheetPanel").Size.Y.Offset):toBe(570)
				snap.stop()
			end,
		})

		verifyHarness:case("disposal mid-drag releases the session and returns to baseline", {
			id = "native_sheet_parts::native Sheet: gestures::disposal mid-drag releases the session and returns to baseline",
			run = function()
				local mounted = Compose.cell(false)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						Compose.show(mounted, function()
							return UI.Sheet "Sheet" {
								isPresented = Compose.cell(true),
								detent = Compose.cell("medium"),
								title = "T",
								content = function(): Instance
									return Host.TextLabel "Body" { Text = "Body" }
								end,
							}
						end),
					})
				end, { motionLevel = "none" })
				local baseline = w.engine.census()
				mounted:set(true)
				flick(w, { { -100, 0.1 } }, false)
				w.find("PanelDrag").DragStart.fire(w.Vector2.new(0, 0))
				mounted:set(false)
				Verify.expect((w.find("SheetPanel"))):toBeNil()
				local after = w.engine.census()
				Verify.expect(after.live):toBe(baseline.live)
				Verify.expect(after.connections):toBe(baseline.connections)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native Sheet: the grabber is the close and resize control", function()
		verifyHarness:case("a sheet with a grabber shows no Close button; the grabber resizes or closes", {
			id = "native_sheet_parts::native Sheet: the grabber is the close and resize control::a sheet with a grabber shows no Close button; the grabber resizes or closes",
			run = function()
				local w = mount()
				Verify.expect((w.find("Close"))):toBeNil()
				local grabber = w.find("Grabber")
				Verify.expect(grabber.Selectable):toBe(true)
				Verify.expect((grabber:GetAttribute("AccessibleLabel"))):toBe("Resize: Medium")
				grabber.Activated.fire()
				Verify.expect((w.detent:peek())):toBe("large")
				Verify.expect((grabber:GetAttribute("AccessibleLabel"))):toBe("Close sheet")
				grabber.Activated.fire()
				Verify.expect((w.shown:peek())):toBe(false)
				w.stop()
				local single = mount({
					detents = { "medium" } :: { SheetDetent },
				})
				local only = single.find("Grabber")
				Verify.expect(only.Selectable):toBe(true)
				Verify.expect((only:GetAttribute("AccessibleLabel"))):toBe("Close sheet")
				only.Activated.fire()
				Verify.expect((single.shown:peek())):toBe(false)
				single.stop()
			end,
		})

		verifyHarness:case(
			"an automatic sheet moves to the centre of a ten-foot screen and docks at the bottom nearby",
			{
				id = "native_sheet_parts::native Sheet: the grabber is the close and resize control::an automatic sheet moves to the centre of a ten-foot screen and docks at the bottom nearby",
				run = function()
					local shown = Compose.cell(false)
					local w = mount(nil, { shown = shown })
					w.gui.ViewportDisplaySize = w.Enum.DisplaySize.Large
					w.input.MouseEnabled = false
					w.input.TouchEnabled = false
					shown:set(true)
					Verify.expect((w.find("SheetPanel"):GetAttribute("FacetPlacement"))):toBe("center")
					w.input.MouseEnabled = true
					Verify.expect((w.find("SheetPanel"):GetAttribute("FacetPlacement"))):toBe("bottom")
					w.stop()
				end,
			}
		)

		verifyHarness:case(
			"a press-drag that starts on the grabber pill drags the sheet, shows grab cursors and is not also a tap",
			{
				id = "native_sheet_parts::native Sheet: the grabber is the close and resize control::a press-drag that starts on the grabber pill drags the sheet, shows grab cursors and is not also a tap",
				run = function()
					local w = mount(nil, { motionLevel = "none" })
					local grabber = w.find("Grabber")
					local drag = grabber:FindFirstChildWhichIsA("UIDragDetector")
					Verify.expect(drag ~= nil):toBe(true)
					Verify.expect(drag.CursorIcon):toBe("rbxasset://SystemCursors/SizeNS")
					Verify.expect(drag.ActivatedCursorIcon):toBe("rbxasset://SystemCursors/ClosedHand")
					drag.DragStart.fire(w.Vector2.new(0, 0))
					drag.DragContinue.fire(w.Vector2.new(0, 30))
					drag.DragEnd.fire()
					grabber.Activated.fire()
					Verify.expect((w.detent:peek())):toBe("medium")
					Verify.expect((w.shown:peek())):toBe(true)
					w.tick(0.5)
					drag.DragStart.fire(w.Vector2.new(0, 0))
					drag.DragContinue.fire(w.Vector2.new(0, 500))
					drag.DragEnd.fire()
					Verify.expect((w.shown:peek())):toBe(false)
					w.stop()
				end,
			}
		)

		verifyHarness:case("a hidden grabber gets an icon-only Close in the header's trailing corner", {
			id = "native_sheet_parts::native Sheet: the grabber is the close and resize control::a hidden grabber gets an icon-only Close in the header's trailing corner",
			run = function()
				local w = mount({ dragIndicator = "hidden" })
				local close = w.find("Close")
				Verify.expect(close.Parent.Name):toBe("Header")
				Verify.expect((close:GetAttribute("label"))):toBe("Close")
				Verify.expect(close.Text):toBe("")
				Verify.expect(close.Size.X.Offset >= 44 and close.Size.Y.Offset >= 44):toBe(true)
				Verify.expect(close.LayoutOrder > w.find("Title").LayoutOrder):toBe(true)
				close.Activated.fire()
				Verify.expect((w.shown:peek())):toBe(false)
				w.stop()
				local opted = mount({ closeButton = true })
				Verify.expect((opted.find("Close"):GetAttribute("label"))):toBe("Close")
				Verify.expect(opted.find("Close").Text):toBe("")
				opted.stop()
			end,
		})
	end)

	verifyHarness:suite("native Sheet: the grabber sits on the edge the sheet came from", function()
		local WIDE = { room = Vector2.new(1200, 800), motionLevel = "none" }
		local function grip(w: any): (any, any, any)
			local handle = w.find("DragHandle")
			return handle, w.find("Pill"), w.find("SheetColumn"):FindFirstChildWhichIsA("UIPadding")
		end

		verifyHarness:case("the grip is a direct child of a panel that neither lays out nor pads it", {
			id = "native_sheet_parts::native Sheet: the grabber sits on the edge the sheet came from::the grip is a direct child of a panel that neither lays out nor pads it",
			run = function()
				local bindThemes = require("../src/ui/themes")
				local fantasy = (require :: any)("../examples/themes/fantasy_ornate").build(bindThemes(Compose))
				for _, extra in { {}, { placement = "side" :: "side" } } :: { any } do
					local w = mount(extra, { room = WIDE.room, motionLevel = "none", theme = fantasy })
					local panel = w.find("SheetPanel")
					Verify.expect(w.find("DragHandle").Parent):toBe(panel)
					Verify.expect((panel:FindFirstChildWhichIsA("UIListLayout"))):toBeNil()
					local inset = panel:FindFirstChildWhichIsA("UIPadding")
					Verify.expect(inset == nil or (inset.PaddingLeft.Offset == 0 and inset.PaddingTop.Offset == 0))
						:toBe(true)
					Verify.expect(w.find("SheetColumn").Parent):toBe(panel)
					w.stop()
				end
			end,
		})

		verifyHarness:case("a bottom sheet has a horizontal bar at the top and reserves the top", {
			id = "native_sheet_parts::native Sheet: the grabber sits on the edge the sheet came from::a bottom sheet has a horizontal bar at the top and reserves the top",
			run = function()
				local w = mount(nil, WIDE)
				local handle, pill, padding = grip(w)
				Verify.expect(handle.Size):toBe(w.engine.types.UDim2.new(1, 0, 0, 20))
				Verify.expect(handle.Position):toBe(w.engine.types.UDim2.new(0, 0, 0, 0))
				Verify.expect(pill.Size):toBe(w.engine.types.UDim2.fromOffset(36, 5))
				Verify.expect((handle:IsDescendantOf(w.find("Room")))):toBe(false)
				Verify.expect(padding.PaddingTop.Offset):toBe(40)
				Verify.expect(padding.PaddingLeft.Offset):toBe(padding.PaddingRight.Offset)
				w.stop()
			end,
		})

		verifyHarness:case("a sheet from the right has a vertical bar on its left edge and reserves the left", {
			id = "native_sheet_parts::native Sheet: the grabber sits on the edge the sheet came from::a sheet from the right has a vertical bar on its left edge and reserves the left",
			run = function()
				local w = mount({ placement = "side" :: "side" }, WIDE)
				local handle, pill, padding = grip(w)
				Verify.expect(handle.Size):toBe(w.engine.types.UDim2.new(0, 20, 1, 0))
				Verify.expect(handle.AnchorPoint):toBe(w.Vector2.new(0, 0))
				Verify.expect(handle.Position):toBe(w.engine.types.UDim2.new(0, 0, 0, 0))
				Verify.expect(pill.Size):toBe(w.engine.types.UDim2.fromOffset(5, 36))
				Verify.expect(padding.PaddingLeft.Offset - 28):toBe(padding.PaddingRight.Offset)
				Verify.expect(padding.PaddingTop.Offset):toBe(12)
				Verify.expect(padding.PaddingRight.Offset):toBe(16)
				w.stop()
				local left = mount({ placement = "side" :: "side", edge = "left" :: "left" }, WIDE)
				local leftHandle, _, leftPadding = grip(left)
				Verify.expect(leftHandle.AnchorPoint):toBe(left.Vector2.new(1, 0))
				Verify.expect(leftHandle.Position):toBe(left.engine.types.UDim2.new(1, 0, 0, 0))
				Verify.expect(leftPadding.PaddingRight.Offset):toBe(44)
				Verify.expect(leftPadding.PaddingLeft.Offset):toBe(16)
				left.stop()
			end,
		})

		verifyHarness:case("a hidden grabber reserves no side", {
			id = "native_sheet_parts::native Sheet: the grabber sits on the edge the sheet came from::a hidden grabber reserves no side",
			run = function()
				local w = mount({ dragIndicator = "hidden", placement = "side" :: "side" }, WIDE)
				local handle, _, padding = grip(w)
				Verify.expect(handle.Visible):toBe(false)
				Verify.expect(padding.PaddingLeft.Offset):toBe(16)
				Verify.expect(padding.PaddingTop.Offset):toBe(12)
				w.stop()
			end,
		})

		verifyHarness:case("dragging a side grabber toward its edge dismisses; a short pull springs back", {
			id = "native_sheet_parts::native Sheet: the grabber sits on the edge the sheet came from::dragging a side grabber toward its edge dismisses; a short pull springs back",
			run = function()
				local w = mount({ placement = "side" :: "side" }, { room = Vector2.new(1200, 800) })
				w.advance(0.5, 10)
				local panel = w.find("SheetPanel")
				local drag = w.find("UIDragDetector")
				Verify.expect(drag.DragAxis):toBe(w.Vector2.new(1, 0))
				drag.DragStart.fire(w.Vector2.new(100, 300))
				w.tick(0.5)
				drag.DragContinue.fire(w.Vector2.new(130, 300))
				Verify.expect(panel.Position.X.Offset):toBe(30)
				w.tick(0.5)
				drag.DragEnd.fire()
				Verify.expect((w.shown:peek())):toBe(true)
				w.advance(0.5, 10)
				Verify.expect(panel.Position.X.Offset):toBe(0)
				drag.DragStart.fire(w.Vector2.new(100, 300))
				w.tick(0.5)
				drag.DragContinue.fire(w.Vector2.new(400, 300))
				Verify.expect(panel.Position.X.Offset):toBe(300)
				w.tick(0.5)
				drag.DragEnd.fire()
				Verify.expect((w.shown:peek())):toBe(false)
				w.advance(0.05, 1)
				Verify.expect(panel.Position.X.Offset >= 300):toBe(true)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native Sheet: the whole sheet moves as one unit", function()
		verifyHarness:case(
			"a drag below the lowest detent moves the whole sheet down; dismissal continues from there",
			{
				id = "native_sheet_parts::native Sheet: the whole sheet moves as one unit::a drag below the lowest detent moves the whole sheet down; dismissal continues from there",
				run = function()
					local w = mount({
						actions = {
							{ id = "Apply", label = "Apply", onActivate = noop } :: OverlayAction,
						},
					})
					w.advance(0.5, 10)
					local panel = w.find("SheetPanel")
					local rest = panel.Size.Y.Offset
					Verify.expect(rest):toBe(300)
					local drag = w.find("UIDragDetector")
					drag.DragStart.fire(w.Vector2.new(0, 0))
					w.tick(0.5)
					drag.DragContinue.fire(w.Vector2.new(0, 100))
					Verify.expect(panel.Size.Y.Offset):toBe(rest)
					Verify.expect(panel.Position.Y.Offset):toBe(100)
					Verify.expect((w.find("Actions"):IsDescendantOf(panel))):toBe(true)
					drag.DragContinue.fire(w.Vector2.new(0, 250))
					w.tick(0.5)
					drag.DragEnd.fire()
					Verify.expect((w.shown:peek())):toBe(false)
					Verify.expect(panel.Position.Y.Offset):toBe(250)
					w.advance(0.02, 1)
					Verify.expect(panel.Size.Y.Offset):toBe(rest)
					Verify.expect(panel.Position.Y.Offset >= 250):toBe(true)
					w.stop()
				end,
			}
		)
	end)

	verifyHarness:suite("native panels: a skinned panel keeps its content inside the art carve", function()
		local bindThemes = require("../src/ui/themes")
		local fantasy = (require :: any)("../examples/themes/fantasy_ornate").build(bindThemes(Compose))
		local function sides(padding: any): string
			return `{padding.PaddingTop.Offset} {padding.PaddingRight.Offset} {padding.PaddingBottom.Offset} {padding.PaddingLeft.Offset}`
		end

		verifyHarness:case("a skinned Sheet insets header, body and actions by the carve; the grabber sits inside it", {
			id = "native_sheet_parts::native panels: a skinned panel keeps its content inside the art carve::a skinned Sheet insets header, body and actions by the carve; the grabber sits inside it",
			run = function()
				local w = mount({
					actions = {
						{ id = "Apply", label = "Apply", onActivate = noop } :: OverlayAction,
					},
				}, { theme = fantasy })
				Verify.expect((sides(w.find("SheetColumn"):FindFirstChildWhichIsA("UIPadding")))):toBe("70 46 42 46")
				local bar = w.find("DragHandle").Position.Y.Offset
				Verify.expect(bar >= 30 and bar + 20 <= 58):toBe(true)
				Verify.expect((w.find("Grabber"):GetAttribute("FacetFocusPart"))):toBe("Pill")
				w.stop()
				local side = mount({ placement = "side" :: "side" }, { theme = fantasy, room = Vector2.new(1200, 800) })
				Verify.expect((sides(side.find("SheetColumn"):FindFirstChildWhichIsA("UIPadding")))):toBe("42 46 42 74")
				local x = side.find("DragHandle").Position.X.Offset
				Verify.expect(x >= 30 and x + 20 <= 58):toBe(true)
				side.stop()
			end,
		})

		verifyHarness:case("keeps Sheet spacing inside a live theme carve even without body padding", {
			id = "native_sheet_parts::native panels: a skinned panel keeps its content inside the art carve::keeps Sheet spacing inside a live theme carve even without body padding",
			run = function()
				local themes = bindThemes(Compose)
				local theme = Compose.cell(fantasy)
				local w = mount({ contentInset = "none", dragIndicator = "hidden" }, { theme = theme })
				local padding = w.find("SheetColumn"):FindFirstChildWhichIsA("UIPadding")
				Verify.expect((sides(padding))):toBe("42 46 42 46")
				theme:set((require :: any)("../examples/themes/fantasy_parchment").build(themes))
				Verify.expect((sides(padding))):toBe("30 34 30 34")
				local neutral = assert(themes.define(themes.neutralPackage()))
				theme:set(neutral)
				Verify.expect((sides(padding))):toBe("12 16 12 16")
				w.stop()
			end,
		})

		verifyHarness:case("stacks Sheet actions when the theme frame leaves too little width", {
			id = "native_sheet_parts::native panels: a skinned panel keeps its content inside the art carve::stacks Sheet actions when the theme frame leaves too little width",
			run = function()
				local parchment = (require :: any)("../examples/themes/fantasy_parchment").build(bindThemes(Compose))
				local w = mount({
					actionLayout = "row",
					actions = {
						{ id = "Cancel", label = "Cancel", onActivate = noop },
						{ id = "Apply", label = "Apply", onActivate = noop },
					},
				}, { theme = parchment, room = Vector2.new(390, 640) })
				w.find("Cancel").TextBounds = Vector2.new(150, 20)
				w.find("Apply").TextBounds = Vector2.new(150, 20)
				Verify.expect(w.find("Actions"):FindFirstChildWhichIsA("UIListLayout").FillDirection)
					:toBe(w.Enum.FillDirection.Vertical)
				w.stop()
			end,
		})

		verifyHarness:case(
			"a wrapping Sheet title takes its height at the width it gets, so it never runs into the body",
			{
				id = "native_sheet_parts::native panels: a skinned panel keeps its content inside the art carve::a wrapping Sheet title takes its height at the width it gets, so it never runs into the body",
				run = function()
					local w = mount({ closeButton = true })
					local title = w.find("Title")
					Verify.expect(title.TextWrapped):toBe(true)
					Verify.expect(title.AutomaticSize):toBe(w.Enum.AutomaticSize.Y)
					Verify.expect(title.Size.X.Scale):toBe(1)
					w.stop()
				end,
			}
		)

		verifyHarness:case("a skinned Dialog and Popover inset by the carve and follow a live theme change", {
			id = "native_sheet_parts::native panels: a skinned panel keeps its content inside the art carve::a skinned Dialog and Popover inset by the carve and follow a live theme change",
			run = function()
				local theme = Compose.cell(fantasy)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Dialog "Confirm" {
							isPresented = Compose.cell(true),
							onPresentedChange = noop,
							title = "Leave?",
							content = function(): Instance
								return Host.TextLabel "Line" { Text = "Body" }
							end,
						} :: unknown,
						UI.Popover "Tip" {
							isPresented = Compose.cell(true),
							onPresentedChange = noop,
							trigger = UI.Button "Open" { label = "Open" },
							content = function(): Instance
								return Host.TextLabel "PopLine" { Text = "Body" }
							end,
						},
					})
				end, { theme = theme })
				local dialog = w.find("Panel")
				local popover = w.find("PopLine")
				while popover.Name ~= "Panel" do
					popover = popover.Parent
				end
				Verify.expect((sides(dialog:FindFirstChildWhichIsA("UIPadding")))):toBe("30 30 30 30")
				Verify.expect((sides(popover:FindFirstChildWhichIsA("UIPadding")))):toBe("30 30 30 30")
				theme:set(bindThemes(Compose).neutralPackage())
				Verify.expect((sides(dialog:FindFirstChildWhichIsA("UIPadding")))):toBe("16 16 16 16")
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native panels: the theme title plaque carries the surface title", function()
		local bindThemes = require("../src/ui/themes")
		local fantasy = (require :: any)("../examples/themes/fantasy_ornate").build(bindThemes(Compose))
		local PLAQUE = fantasy.assets.ornate_plaque.content
		local function plaque(root: any): any
			for _, node in root:GetDescendants() do
				if node:IsA("ImageLabel") and node.Image == PLAQUE then
					return node
				end
			end
			return nil
		end

		verifyHarness:case("a titled Sheet paints its title in the plaque, and the header title steps aside", {
			id = "native_sheet_parts::native panels: the theme title plaque carries the surface title::a titled Sheet paints its title in the plaque, and the header title steps aside",
			run = function()
				local w = mount({ title = "Filters" }, { theme = fantasy })
				local art = plaque(w.find("SheetPanel"))
				Verify.expect(art.Visible):toBe(true)
				Verify.expect(overlay.find(art, "PlaqueCaption").Text):toBe("Filters")
				Verify.expect((w.find("SheetPanel"):HasTag("facet-skin-caption"))):toBe(true)
				Verify.expect(w.find("Title").Visible):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("a surface without a title draws no plaque", {
			id = "native_sheet_parts::native panels: the theme title plaque carries the surface title::a surface without a title draws no plaque",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Dialog "Plain" {
						isPresented = Compose.cell(true),
						onPresentedChange = noop,
						content = function(): Instance
							return Host.TextLabel "Line" { Text = "Body" }
						end,
					}
				end, { theme = fantasy })
				local art = plaque(w.find("Panel"))
				Verify.expect(art.Visible):toBe(false)
				Verify.expect((overlay.find(art, "PlaqueCaption"))):toBeNil()
				Verify.expect((w.find("Panel"):HasTag("facet-skin-caption"))):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("the plaque grows around its title, centred on its edge, and never shrinks below its art", {
			id = "native_sheet_parts::native panels: the theme title plaque carries the surface title::the plaque grows around its title, centred on its edge, and never shrinks below its art",
			run = function()
				local w = mount({ title = "Filters" }, { theme = fantasy })
				local art = plaque(w.find("SheetPanel"))
				Verify.expect(art.AnchorPoint):toBe(w.Vector2.new(0.5, 0.5))
				Verify.expect(art.Position):toBe(w.engine.types.UDim2.new(0.5, 0, 0, 0))
				local caption = overlay.find(art, "PlaqueCaption")
				local insets = caption:FindFirstChildWhichIsA("UIPadding")
				local across = insets.PaddingLeft.Offset + insets.PaddingRight.Offset
				local down = insets.PaddingTop.Offset + insets.PaddingBottom.Offset
				Verify.expect(art.ScaleType):toBe(w.Enum.ScaleType.Slice)
				Verify.expect(insets.PaddingTop.Offset >= 13 and insets.PaddingBottom.Offset >= 15):toBe(true)
				caption.TextBounds = w.Vector2.new(300.4, 38)
				Verify.expect(art.Size):toBe(w.engine.types.UDim2.fromOffset(301 + across, 38 + down))
				caption.TextBounds = w.Vector2.new(20, 10)
				Verify.expect(art.Size):toBe(w.engine.types.UDim2.fromOffset(176, 40))
				w.stop()
			end,
		})
	end)
end
