--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type SheetDetent = typeof(require("@repo/tools/typecheck/aliases").SheetDetent)
	type OverlayAction = typeof(require("@repo/tools/typecheck/aliases").OverlayAction)
	type FrameNativeProps = typeof(require("@repo/tools/typecheck/aliases").FrameNativeProps)

	local Compose = require("../src/vendor/compose/core")
	local Facet = require("../src")
	local overlay = require("./lib/overlay_world")
	local release = require("../src/ui/sheet_release")
	local Vector2 = require("./lib/native_engine").types.Vector2

	local LONG = string.rep("A long line of body copy that wraps across the sheet. ", 40)
	local noop = function() end

	local function mount(extra: { [string]: any }?, options: any?, setup: overlay.Setup?): any
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
		end, o, setup)
		w.detent, w.shown = detent, shown
		w.builds = function()
			return builds
		end
		local modal = w.find("Modal")
		if modal then
			w.engine.environment.poke(modal, "AbsoluteSize", o.room or Vector2.new(800, 600))
		end
		if not o.unsettled then
			w.advance(1 / 300, 2)
		end
		return w
	end

	local function content(w: any, height: number)
		local flow = w.find("SheetFlow")
		w.engine.environment.poke(
			flow:FindFirstChildWhichIsA("UIListLayout"),
			"AbsoluteContentSize",
			Vector2.new(500, height - 16)
		)
	end
	local function sheetInsets(
		w: { find: (string) -> GuiObject }
	): { left: number, top: number, right: number, bottom: number }
		local room, panel = w.find("Room"), w.find("SheetPanel")
		return {
			left = room.Position.X.Offset,
			top = room.Position.Y.Offset,
			right = -room.Size.X.Offset - room.Position.X.Offset,
			bottom = panel.Size.Y.Offset - room.Size.Y.Offset - room.Position.Y.Offset,
		}
	end
	local function insetSides(w: { find: (string) -> GuiObject }): string
		local inset = sheetInsets(w)
		return `{inset.top} {inset.right} {inset.bottom} {inset.left}`
	end

	local function built(fn: (any, any) -> any): any
		return { __build = fn }
	end

	verifyHarness:suite("native Sheet: placement, width, title and close", function()
		verifyHarness:case("lets the model reject and later accept dismissal without rebuilding the draft", {
			id = "native_sheet_parts::guarded-dismissal",
			run = function()
				for _, route in { "Close", "Grabber", "ModalBack", "DismissTarget", "Drag", "SideDrag" } do
					local shown = Compose.cell(true)
					local accept, requests = false, 0
					local w = mount({
						detents = { "medium" },
						placement = if route == "SideDrag" then "side" else "bottom",
						closeButton = if route == "Close" then true else nil,
						onPresentedChange = function(nextValue: boolean)
							Verify.expect(nextValue):toBe(false)
							requests += 1
							if accept then
								shown:set(nextValue)
							end
						end,
					}, { shown = shown, motionLevel = "none" })
					local body = w.find("Copy")
					local function dismiss()
						if route == "ModalBack" then
							w.action(route).Pressed:Fire()
						elseif route == "Drag" or route == "SideDrag" then
							w.tick(0.5)
							local drag = w.find("Grabber"):FindFirstChildWhichIsA("UIDragDetector")
							drag.DragStart:Fire(w.Vector2.new(0, 0))
							drag.DragContinue:Fire(
								if route == "SideDrag" then w.Vector2.new(500, 0) else w.Vector2.new(0, 500)
							)
							drag.DragEnd:Fire()
						else
							w.find(route).Activated:Fire()
						end
					end
					dismiss()
					Verify.expect(requests == 1):toBeTrueWith(route .. " should request dismissal once")
					Verify.expect(shown:peek()):toBe(true)
					Verify.expect(w.find("Copy")):toBe(body)
					Verify.expect(w.builds()):toBe(1)
					accept = true
					dismiss()
					Verify.expect(requests):toBe(2)
					Verify.expect(shown:peek()):toBe(false)
					w.stop()
				end
			end,
		})
		verifyHarness:case("keeps background input blocked through a nested Sheet", {
			id = "native_sheet_parts::nested-modal-native-input",
			run = function()
				local shown, child = Compose.cell(false), Compose.cell(false)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					local props: FrameNativeProps = {
						Host.TextButton "HUDAction" { Text = "Shop", Selectable = true },
						UI.Sheet "Shop" {
							isPresented = shown,
							title = "Shop",
							content = function()
								local body: FrameNativeProps = {
									UI.Button "ParentAction" { label = "More" },
									UI.Sheet "More" {
										isPresented = child,
										title = "More",
										content = function()
											return UI.Button "ChildAction" { label = "Buy" }
										end,
									},
								}
								return Host.Frame(body)
							end,
						},
					}
					return Host.Frame(props)
				end)
				shown:set(true)
				child:set(true)
				Verify.expect(w.find("HUDAction").Interactable):toBe(false)
				Verify.expect(w.find("ParentAction").Interactable):toBe(false)
				Verify.expect(w.find("ChildAction").Interactable):toBe(true)
				child:set(false)
				Verify.expect(w.find("HUDAction").Interactable):toBe(false)
				Verify.expect(w.find("ParentAction").Interactable):toBe(true)
				shown:set(false)
				Verify.expect(w.find("HUDAction").Interactable):toBe(true)
				w.stop()
			end,
		})
		verifyHarness:case("blocks native background actions and restores them after closing", {
			id = "native_sheet_parts::modal-native-input",
			run = function()
				local shown = Compose.cell(false)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					local props: FrameNativeProps = {
						Host.TextButton "HUDAction" { Text = "Shop", Selectable = true, Interactable = true },
						Host.TextButton "DisabledAction" {
							Text = "Unavailable",
							Selectable = false,
							Interactable = false,
						},
						UI.Sheet "Shop" {
							isPresented = shown,
							title = "Shop",
							content = function()
								return UI.Button "Buy" { label = "Buy" }
							end,
						},
					}
					return Host.Frame(props)
				end)
				local button = w.find("HUDAction")
				for _ = 1, 2 do
					shown:set(true)
					Verify.expect(button.Interactable):toBe(false)
					Verify.expect(button.Selectable):toBe(false)
					Verify.expect(w.find("Buy").Interactable):toBe(true)
					shown:set(false)
					Verify.expect(button.Interactable):toBe(true)
					Verify.expect(button.Selectable):toBe(true)
					Verify.expect(w.find("DisabledAction").Interactable):toBe(false)
					Verify.expect(w.find("DisabledAction").Selectable):toBe(false)
				end
				w.stop()
			end,
		})
		verifyHarness:case("a gamepad lands on the task, not Close; initialFocus names where", {
			id = "native_sheet_parts::gamepad-entry-skips-close",
			run = function()
				type Case = { initialFocus: (string | () -> string?)?, expect: string }
				local cases: { Case } = {
					{ expect = "Blade" },
					{ initialFocus = "Speed", expect = "Speed" },
					{
						initialFocus = function(): string?
							return "Storage"
						end,
						expect = "Storage",
					},
					{ initialFocus = "Missing", expect = "Blade" },
				}
				for _, case in cases do
					local w = mount({
						placement = "center",
						closeButton = true,
						initialFocus = case.initialFocus,
						content = built(function(UI, Host: RobloxHost)
							return Host.Frame {
								UI.Button "Blade" { label = "Blade" } :: unknown,
								Host.Frame "Speed" { UI.Button "Buy" { label = "Buy speed" } },
								UI.Button "Storage" { label = "Storage" },
							}
						end),
					}, { shown = Compose.cell(false), motionLevel = "none" })
					w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
					w.shown:set(true)
					w.advance(1 / 60, 3)
					local selected = w.gui.SelectedObject
					local name = if selected
						then (if selected.Name == "Buy" then selected.Parent.Name else selected.Name)
						else "nil"
					Verify.expect(name):toBe(case.expect)
					w.stop()
				end
			end,
		})
		verifyHarness:case("gamepad entry skips hidden targets and hero Close, and waits for late content", {
			id = "native_sheet_parts::gamepad-entry-edges",
			run = function()
				local calls = 0
				local hidden = mount({
					placement = "center",
					closeButton = true,
					initialFocus = function(): string?
						calls += 1
						return "Secret"
					end,
					content = built(function(UI, Host: RobloxHost)
						return Host.Frame {
							Host.Frame "Folded" { Visible = false, UI.Button "Secret" { label = "Secret" } } :: unknown,
							UI.Button "Visible" { label = "Visible" },
						}
					end),
				}, { shown = Compose.cell(false), motionLevel = "none" })
				hidden.engine.environment.poke(hidden.input, "PreferredInput", hidden.Enum.PreferredInput.Gamepad)
				hidden.shown:set(true)
				hidden.advance(1 / 60, 30)
				Verify.expect(if hidden.gui.SelectedObject then hidden.gui.SelectedObject.Name else "nil")
					:toBe("Visible")
				Verify.expect(calls):toBe(1)
				hidden.stop()

				local hero = mount({
					placement = "center",
					closeButton = true,
					header = false,
					hero = built(function(_, Host: RobloxHost)
						return { height = 120, content = Host.TextLabel "Banner" { Text = "Lobby" } }
					end),
					content = built(function(UI)
						return UI.Button "Continue" { label = "Continue" }
					end),
				}, { shown = Compose.cell(false), motionLevel = "none" })
				hero.engine.environment.poke(hero.input, "PreferredInput", hero.Enum.PreferredInput.Gamepad)
				hero.shown:set(true)
				hero.advance(1 / 60, 3)
				Verify.expect(if hero.gui.SelectedObject then hero.gui.SelectedObject.Name else "nil"):toBe("Continue")
				hero.stop()

				for _, case in
					{
						{ role = "default", expected = "Claim" },
						{ role = "destructive", expected = "Later" },
					}
				do
					local reward = mount({
						placement = "center",
						content = built(function(_, Host: RobloxHost)
							return Host.TextLabel "Reward" { Text = "Daily reward" }
						end),
						actions = {
							{ id = "Later", label = "Later", role = "cancel", onActivate = noop },
							{ id = "Claim", label = "Claim", role = case.role, onActivate = noop },
						},
					}, { shown = Compose.cell(false), motionLevel = "none" })
					reward.engine.environment.poke(reward.input, "PreferredInput", reward.Enum.PreferredInput.Gamepad)
					reward.shown:set(true)
					reward.advance(1 / 60, 3)
					Verify.expect(if reward.gui.SelectedObject then reward.gui.SelectedObject.Name else "nil")
						:toBe(case.expected)
					reward.stop()
				end

				local ready = Compose.cell(false)
				local late = mount({
					placement = "center",
					closeButton = true,
					content = built(function(UI, Host: RobloxHost)
						return Host.Frame {
							Compose.show(ready, function()
								return UI.Button "Row" { label = "Row" }
							end),
						}
					end),
				}, { shown = Compose.cell(false), motionLevel = "none" })
				late.engine.environment.poke(late.input, "PreferredInput", late.Enum.PreferredInput.Gamepad)
				late.shown:set(true)
				late.advance(1 / 60, 3)
				Verify.expect(if late.gui.SelectedObject then late.gui.SelectedObject.Name else "nil"):toBe("Close")
				ready:set(true)
				late.advance(1 / 60, 3)
				Verify.expect(if late.gui.SelectedObject then late.gui.SelectedObject.Name else "nil"):toBe("Close")
				late.size(late.find("Row"), 120, 44)
				late.advance(1 / 60, 3)
				Verify.expect(if late.gui.SelectedObject then late.gui.SelectedObject.Name else "nil"):toBe("Row")
				late.stop()
			end,
		})
		verifyHarness:case("a gamepad still lands on Close when the sheet has nothing else to act on", {
			id = "native_sheet_parts::gamepad-entry-close-fallback",
			run = function()
				local w = mount({ placement = "center", closeButton = true }, { shown = Compose.cell(false) })
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
				w.shown:set(true)
				w.advance(1 / 60, 3)
				Verify.expect(if w.gui.SelectedObject then w.gui.SelectedObject.Name else "nil"):toBe("Close")
				w.stop()
			end,
		})
		verifyHarness:case("routes Close to footer actions when the body has only text", {
			id = "native_sheet_parts::text-body-footer-selection",
			run = function()
				local w =
					mount({ placement = "center", actions = { { id = "Buy", label = "Buy", onActivate = noop } } })
				Verify.expect(w.find("SheetContent").Selectable):toBe(false)
				Verify.expect(w.find("SheetContent").SelectionGroup):toBe(false)
				Verify.expect(w.find("Room").SelectionGroup):toBe(false)
				Verify.expect(w.find("Close").NextSelectionDown):toBe(w.find("Buy"))
				Verify.expect(w.find("Buy").NextSelectionUp):toBe(w.find("Close"))
				w.stop()
			end,
		})
		verifyHarness:case("arrival wrapper releases supplied hero content before destroying its ancestors", {
			id = "native_sheet_parts::arrival-keeps-hero",
			run = function()
				local banner: Instance? = nil
				local w = mount({
					header = false,
					hero = built(function(_, Host: RobloxHost)
						banner = Host.TextLabel "Banner" { Text = "Lobby" }
						return { height = 140, content = banner }
					end),
				}, { motionLevel = "none" }, { runService = true, preRender = true })
				for _ = 1, 3 do
					Verify.expect(w.find("OverlayArrival") ~= nil):toBe(true)
					w.shown:set(false)
					w.advance(2, 60)
					Verify.expect(w.find("OverlayArrival") == nil):toBe(true)
					local retained = assert(banner)
					Verify.expect(not w.engine.environment.isAlive(retained)):toBe(false)
					w.shown:set(true)
					w.advance(1 / 30, 2)
					Verify.expect(assert(banner):IsDescendantOf(w.find("Hero"))):toBe(true)
				end
				w.stop()
			end,
		})

		verifyHarness:case("hero close replaces the grabber and enters body controls without self links", {
			id = "native_sheet_parts::hero-close-selection",
			run = function()
				for _, interactiveBody in { false, true } do
					local w = mount({
						header = false,
						closeButton = true,
						hero = { height = 140, image = "rbxassetid://1" },
						actions = { { id = "Join", label = "Join", onActivate = noop } },
						content = built(function(UI, Host)
							return if interactiveBody
								then UI.Button "Continue" { label = "Continue" }
								else Host.TextLabel "Copy" { Text = "Lobby details" }
						end),
					})
					local close, grabber = w.find("Close"), w.find("Grabber")
					Verify.expect(grabber.Visible or grabber.Selectable):toBe(false)
					Verify.expect(close.NextSelectionUp == grabber):toBe(false)
					Verify.expect(close.NextSelectionDown == close):toBe(false)
					if interactiveBody then
						Verify.expect(close.NextSelectionDown == w.find("Continue")):toBe(true)
					end
					w.stop()
				end
			end,
		})

		verifyHarness:case("keeps pinned regions in layout units under an ancestor scale", {
			id = "native_sheet_parts::native Sheet: placement, width, title and close::keeps pinned regions in layout units under an ancestor scale",
			run = function()
				local w = mount(
					{ detents = { "hug", "large" }, actions = { { id = "Go", label = "Go", onActivate = noop } } },
					{ detent = "hug", motionLevel = "none" }
				)
				w.size(w.find("Modal"), 400, 300)
				for _, probe in w.findAll("LayoutUnit") do
					w.size(probe, 50, 0.5)
				end
				w.size(w.find("Header"), 250, 22)
				w.size(w.find("Actions"), 250, 22)
				w.engine.environment.poke(
					w.find("SheetFlow"):FindFirstChildWhichIsA("UIListLayout"),
					"AbsoluteContentSize",
					Vector2.new(250, 142)
				)
				Verify.expect(w.find("SheetPanel").Size.Y.Offset):toBe(464)
				Verify.expect(w.find("SheetContent").Size.Y.Offset):toBe(308)
				w.stop()
			end,
		})

		verifyHarness:case("shows Popover Close only for compact or covering modal content and explicit overrides", {
			id = "native_sheet_parts::native Sheet: placement, width, title and close::shows Popover Close only for compact or covering modal content and explicit overrides",
			run = function()
				for _, policy in
					{
						{
							modal = true,
							width = 800,
							height = 600,
							bodyWidth = 200,
							bodyHeight = 100,
							expected = false,
						},
						{ modal = true, width = 390, height = 844, bodyWidth = 200, bodyHeight = 100, expected = true },
						{ modal = true, width = 800, height = 600, bodyWidth = 760, bodyHeight = 560, expected = true },
						{
							modal = false,
							width = 390,
							height = 844,
							bodyWidth = 200,
							bodyHeight = 100,
							expected = false,
						},
						{
							modal = false,
							closeButton = true,
							width = 800,
							height = 600,
							bodyWidth = 200,
							bodyHeight = 100,
							expected = true,
						},
						{
							modal = true,
							closeButton = false,
							width = 390,
							height = 844,
							bodyWidth = 200,
							bodyHeight = 100,
							expected = false,
						},
					}
				do
					local shown = Compose.cell(true)
					local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
						return UI.Popover {
							isPresented = shown,
							onPresentedChange = function(value: boolean)
								shown:set(value)
							end,
							modal = policy.modal,
							closeButton = policy.closeButton,
							compact = "popover" :: "popover",
							source = { rect = { x = 20, y = 20, w = 20, h = 20 } },
							content = function(): Instance
								return Host.Frame "PolicyBody" {}
							end,
						}
					end, nil, { size = Vector2.new(policy.width, policy.height) })
					w.size(w.find("PolicyBody"), policy.bodyWidth, policy.bodyHeight)
					local command = w.find("CloseCommand")
					Verify.expect(command ~= nil and command.Visible):toBe(policy.expected)
					if policy.expected then
						command.Activated:Fire()
						Verify.expect(shown:peek()):toBe(false)
					end
					w.stop()
				end
			end,
		})

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
				w.find("ModalBack").Pressed:Fire()
				Verify.expect((w.shown:peek())):toBe(false)
				w.stop()
				local label = Compose.cell("Fertig")
				local named = mount({ closeButton = label })
				local close = named.find("Close")
				local function shown(): { string }
					local texts: { string } = {}
					for _, node in close:GetDescendants() do
						if node:IsA("TextLabel") and node.Text ~= "" then
							table.insert(texts, node.Text)
						end
					end
					return texts
				end
				Verify.expect(table.find(shown(), "Fertig") ~= nil or close.Text == "Fertig"):toBe(true)
				label:set("Schliessen")
				Verify.expect(table.find(shown(), "Schliessen") ~= nil or close.Text == "Schliessen"):toBe(true)
				close.Activated:Fire()
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
				local padding = w.find("SheetFlow"):FindFirstChildWhichIsA("UIPadding")
				Verify.expect(padding.PaddingLeft.Scale > 0):toBe(true)
				Verify.expect(padding.PaddingTop.Offset):toBe(8)
				Verify.expect(padding.PaddingBottom.Offset):toBe(8)
				w.stop()
				local none = mount({ contentInset = "none" })
				Verify.expect(none.find("SheetFlow"):FindFirstChildWhichIsA("UIPadding").PaddingLeft.Offset):toBe(0)
				Verify.expect(none.find("SheetFlow"):FindFirstChildWhichIsA("UIPadding").PaddingLeft.Scale):toBe(0)
				Verify.expect(sheetInsets(none).left):toBe(16)
				none.stop()
			end,
		})

		verifyHarness:case("updates horizontal feedback clearance with the theme while keeping its minimum inset", {
			id = "native_sheet_parts::native Sheet: parts::updates horizontal feedback clearance with the theme while keeping its minimum inset",
			run = function()
				local theme = Compose.cell(Facet.themes.neutralPackage())
				local w = mount({ width = "wide" }, { theme = theme })
				local padding = w.find("SheetFlow"):FindFirstChildWhichIsA("UIPadding")
				Verify.expect(padding.PaddingLeft.Scale):toBeCloseTo(0.04, 0.0001)
				local stronger = Facet.themes.neutralPackage()
				assert(stronger.metrics.motion.materialize).lift = 1.12
				theme:set(stronger)
				Verify.expect(padding.PaddingLeft.Scale):toBeCloseTo(0.12, 0.0001)
				Verify.expect(padding.PaddingRight.Scale):toBe(padding.PaddingLeft.Scale)
				local still = Facet.themes.neutralPackage()
				assert(still.metrics.motion.materialize).lift = 1
				theme:set(still)
				Verify.expect(padding.PaddingLeft.Scale):toBe(0)
				Verify.expect(padding.PaddingLeft.Offset):toBe(8)
				Verify.expect(padding.PaddingTop.Offset):toBe(8)
				Verify.expect(padding.PaddingBottom.Offset):toBe(8)
				w.stop()
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
				overlay.find(actions, "Join").Activated:Fire()
				Verify.expect((table.concat(pressed, ","))):toBe("Join")
				Verify.expect((w.shown:peek())):toBe(true)
				w.find("ModalBack").Pressed:Fire()
				Verify.expect((table.concat(pressed, ","))):toBe("Join,Later")
				Verify.expect((w.shown:peek())):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("the default action has the emphasis appearance, as in a Dialog", {
			id = "native_sheet_parts::native Sheet: parts::the default action has the emphasis appearance, as in a Dialog",
			run = function()
				local function act(id: string, role: ("default" | "cancel" | "destructive")?): OverlayAction
					return { id = id, label = id, role = role, onActivate = noop }
				end
				local list = { act("Skip", "cancel"), act("Reset", "destructive"), act("Map"), act("Join", "default") }
				local w = mount({ actions = list })
				local actions = w.find("Actions")
				local appearances = {}
				for _, id in { "Skip", "Reset", "Map", "Join" } do
					local button = overlay.find(actions, id)
					table.insert(appearances, `{id}={button:GetAttribute("appearance")}`)
				end
				local expected = "Skip=standard,Reset=standard,Map=standard,Join=emphasis"
				Verify.expect((table.concat(appearances, ","))):toBe(expected)
				Verify.expect((overlay.find(actions, "Join"):HasTag("facet-accent"))):toBe(true)
				Verify.expect((overlay.find(actions, "Reset"):HasTag("facet-role-destructive"))):toBe(true)
				Verify.expect((overlay.find(actions, "Skip"):HasTag("facet-role-cancel"))):toBe(true)
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
				w.engine.environment.poke(room, "AbsoluteWindowSize", Vector2.new(500, 150))
				w.engine.environment.poke(room, "AbsoluteCanvasSize", Vector2.new(500, 1200))
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
				w.input.InputBegan:Fire({ KeyCode = w.Enum.KeyCode.DPadDown })
				w.advance(1 / 10, 6)
				Verify.expect(w.gui.SelectedObject):toBe(one)
				Verify.expect(room.CanvasPosition.Y):toBe(1100 + 44 - 350)
				w.detent:set("large")
				w.advance(0.5, 5)
				w.engine.environment.poke(w.find("Modal"), "AbsoluteSize", Vector2.new(800, 900))
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
				close.Activated:Fire()
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
				Verify.expect(strip.Size.Y.Offset)
					:toBeGreaterThanOrEqual(w.find("Utilities").Position.Y.Offset + w.find("Close").Size.Y.Offset)
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
					Verify.expect((not w.engine.environment.isAlive(banner))):toBe(false)
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
					Verify.expect((not w.engine.environment.isAlive(copy))):toBe(false)
					Verify.expect((not w.engine.environment.isAlive(head))):toBe(false)
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
				Verify.expect(w.find("Inset"):FindFirstChildWhichIsA("UIPadding").PaddingLeft.Scale > 0):toBe(true)
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
				w.engine.environment.poke(w.input, "OnScreenKeyboardSize", Vector2.new(800, 250))
				w.engine.environment.poke(w.input, "OnScreenKeyboardVisible", true)
				Verify.expect(panel.Size.Y.Offset):toBe(math.floor(350 * 0.95))
				Verify.expect(panel.Position.Y.Offset):toBe(-250)
				Verify.expect(panel.Size.Y.Offset < tall):toBe(true)
				Verify.expect((w.find("Actions"):IsDescendantOf(panel))):toBe(true)
				w.engine.environment.poke(w.input, "OnScreenKeyboardVisible", false)
				Verify.expect(panel.Size.Y.Offset):toBe(tall)
				w.stop()
			end,
		})

		verifyHarness:case("keyboard dismissal keeps the native pointer target still through release or cancellation", {
			id = "native_sheet_parts::native Sheet: parts::keyboard dismissal keeps the native pointer target still through release or cancellation",
			run = function()
				for _, kind in { "Touch", "MouseButton1" } do
					for _, ending in { "End", "Cancel", "Destroy" } do
						local w = mount({
							content = built(function(UI: FacetControls)
								local function Composer(): Instance
									return UI.TextInput "Message" {
										value = Compose.cell("Draft"),
										trailing = UI.Button "Send" { label = "Send", onActivate = noop },
									}
								end
								return Composer
							end),
						}, { detent = "large", motionLevel = "none" })
						local panel, field = w.find("SheetPanel"), w.find("Field")
						w.engine.environment.poke(w.input, "OnScreenKeyboardSize", Vector2.new(800, 250))
						w.engine.environment.poke(w.input, "OnScreenKeyboardVisible", true)
						local connections = w.engine.census().connections
						local press = w.engine.new("InputObject")
						w.engine.environment.poke(press, "UserInputType", w.engine.types.Enum.UserInputType[kind])
						w.engine.environment.poke(press, "UserInputState", w.engine.types.Enum.UserInputState.Begin)
						field.FocusLost:Fire(false, press)
						w.engine.environment.poke(w.input, "OnScreenKeyboardSize", Vector2.new(0, 0))
						Verify.expect(panel.Position.Y.Offset):toBe(-250)
						w.engine.environment.poke(w.input, "OnScreenKeyboardVisible", false)
						Verify.expect(panel.Position.Y.Offset):toBe(-250)
						if ending == "Destroy" then
							w.stop()
							w.engine.environment.poke(press, "UserInputState", w.engine.types.Enum.UserInputState.End)
							w.advance(1 / 60, 2)
						else
							w.engine.environment.poke(
								press,
								"UserInputState",
								w.engine.types.Enum.UserInputState[ending]
							)
							Verify.expect(panel.Position.Y.Offset):toBe(-250)
							w.advance(1 / 60, 2)
							Verify.expect(panel.Position.Y.Offset):toBe(0)
							Verify.expect(w.engine.census().connections):toBe(connections)
							w.stop()
						end
						Verify.expect(w.engine.census().connections):toBe(0)
					end
				end
			end,
		})

		verifyHarness:case("keyboard submission releases its clearance without waiting for a pointer", {
			id = "native_sheet_parts::native Sheet: parts::keyboard submission releases its clearance without waiting for a pointer",
			run = function()
				local w = mount({
					content = built(function(UI: FacetControls)
						local function Composer(): Instance
							return UI.TextInput "Message" { value = Compose.cell("Draft") }
						end
						return Composer
					end),
				}, { detent = "large", motionLevel = "none" })
				w.engine.environment.poke(w.input, "OnScreenKeyboardSize", Vector2.new(800, 250))
				w.engine.environment.poke(w.input, "OnScreenKeyboardVisible", true)
				local press = w.engine.new("InputObject")
				w.engine.environment.poke(press, "UserInputType", w.engine.types.Enum.UserInputType.Keyboard)
				w.engine.environment.poke(press, "KeyCode", w.engine.types.Enum.KeyCode.Return)
				w.engine.environment.poke(press, "UserInputState", w.engine.types.Enum.UserInputState.End)
				w.find("Message").FocusLost:Fire(true, press)
				w.engine.environment.poke(w.input, "OnScreenKeyboardSize", Vector2.new(0, 0))
				w.engine.environment.poke(w.input, "OnScreenKeyboardVisible", false)
				Verify.expect(w.find("SheetPanel").Position.Y.Offset):toBe(0)
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
					w.engine.environment.poke(
						body,
						"AbsoluteCanvasSize",
						Vector2.new(500, math.max(body.Size.Y.Offset, 120) + 40)
					)
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

		verifyHarness:case("preparation frame cost does not advance the entrance clock", {
			id = "native_sheet_parts::native Sheet: parts::preparation frame cost does not advance the entrance clock",
			run = function()
				local function positions(preparationDelta: number): { number }
					local w = mount(nil, { unsettled = true })
					local panel, title = w.find("SheetPanel"), w.find("Title")
					for width = 1, 2 do
						w.engine.environment.poke(title, "TextBounds", Vector2.new(width * 75, 25))
						w.advance(preparationDelta)
						Verify.expect(panel.Position.Y.Offset):toBe(panel.Size.Y.Offset)
					end
					w.advance(1 / 60)
					Verify.expect(panel.Position.Y.Offset):toBe(panel.Size.Y.Offset)
					local result: { number } = {}
					for _ = 1, 24 do
						w.advance(1 / 60)
						table.insert(result, panel.Position.Y.Offset)
					end
					Verify.expect(result[1] < panel.Size.Y.Offset):toBe(true)
					Verify.expect(result[#result]):toBe(0)
					w.stop()
					return result
				end
				local cold, warm = positions(0.12), positions(1 / 60)
				for index, position in cold do
					Verify.expect(position):toBe(warm[index])
				end
			end,
		})

		verifyHarness:case("appears when fonts finish after the preparation clock", function(t)
			local prepare = require("../src/ui/font_readiness")
			local environment = getfenv(prepare)
			local originalTask = environment.task
			local pending: { thread } = {}
			local waiting: { thread } = {}
			environment.task = {
				defer = function(callback: () -> ()): thread
					local work = coroutine.create(callback)
					table.insert(pending, work)
					return work
				end,
				cancel = function(work: thread)
					coroutine.close(work)
				end,
			}
			t:defer(function()
				environment.task = originalTask
			end)
			local engine = require("./lib/native_engine").new()
			local now = 0
			engine.clock = function()
				return now
			end
			local Facet = require("../src")
			local runtime = Facet.Roblox.createRuntime(engine)
			local Host = (runtime.constructors :: unknown) :: RobloxHost
			local provider = {
				PreloadAsync = function(_self: unknown, sources: { Instance })
					for _, source in sources do
						t:expect(source:IsA("TextLabel") or source:IsA("TextButton") or source:IsA("TextBox"))
							:toBe(true)
					end
					table.insert(waiting, coroutine.running())
					coroutine.yield()
				end,
			}
			local UI = Facet.controls(runtime, {
				types = engine.types,
				motionLevel = "none",
				services = { ContentProvider = (provider :: unknown) :: ContentProvider },
			})
			local stop, mounted = runtime.mount(function()
				return Host.ScreenGui {
					UI.Sheet {
						isPresented = Compose.cell(true),
						detent = Compose.cell("medium"),
						title = "Details",
						content = function()
							return Host.TextLabel { Text = "Sheet content" }
						end,
					},
				}
			end, engine.new("Folder"))
			local screen = mounted :: ScreenGui
			t:defer(function()
				stop()
				runtime:dispose()
			end)
			engine.environment.poke(
				(screen :: unknown) :: typeof(engine.new("ScreenGui")),
				"AbsoluteSize",
				Vector2.new(800, 600)
			)
			local sheet = assert(overlay.find(screen, "Sheet"))
			t:expect(sheet:GetAttribute("FacetError")):toBe(nil)
			local modal = assert(overlay.find(screen, "Modal")) :: Frame
			engine.environment.poke(
				(modal :: unknown) :: typeof(engine.new("Frame")),
				"AbsoluteSize",
				Vector2.new(800, 600)
			)
			local panel = assert(overlay.find(screen, "SheetPanel")) :: Frame
			local function advance()
				now += 1 / 60
				engine.heartbeat:Fire(1 / 60)
				while #pending > 0 do
					local queued = pending
					pending = {}
					for _, work in queued do
						if coroutine.status(work) == "suspended" then
							t:expect((coroutine.resume(work))):toBe(true)
						end
					end
				end
			end
			for _ = 1, 40 do
				advance()
			end
			t:expect(#waiting > 0):toBe(true)
			t:expect(panel.Position.Y.Offset):toBe(panel.Size.Y.Offset)
			for _, work in waiting do
				if coroutine.status(work) == "suspended" then
					t:expect((coroutine.resume(work))):toBe(true)
				end
			end
			for _ = 1, 5 do
				advance()
			end
			t:expect(panel.Position.Y.Offset):toBe(0)
		end)

		verifyHarness:case("a late text size change, such as a font that loads, holds the sheet off screen", {
			id = "native_sheet_parts::native Sheet: parts::a late text size change, such as a font that loads, holds the sheet off screen",
			run = function()
				local w = mount(nil, { unsettled = true })
				local panel, title = w.find("SheetPanel"), w.find("Title")
				w.engine.environment.poke(title, "TextBounds", Vector2.new(75, 12))
				w.advance(1 / 60)
				w.engine.environment.poke(title, "TextBounds", Vector2.new(143, 25))
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
				w.find("Grabber").Activated:Fire()
				Verify.expect((w.detent:peek())):toBe("large")
				w.detent:set("b")
				local drag = w.find("UIDragDetector")
				drag.DragStart:Fire(w.Vector2.new(0, 0))
				w.tick(0.5)
				drag.DragContinue:Fire(w.Vector2.new(0, 2))
				w.tick(0.5)
				drag.DragEnd:Fire()
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

		verifyHarness:case("a plain detent id starts the sheet there and the sheet owns later detent changes", {
			id = "native_sheet_parts::native Sheet: parts::a plain detent id starts the sheet there and the sheet owns later detent changes",
			run = function()
				local w = mount({ detent = "large" }, { motionLevel = "none" })
				local panel = w.find("SheetPanel")
				Verify.expect(panel.Size.Y.Offset):toBe(570)
				Verify.expect((w.detent:peek())):toBe("medium")
				w.stop()
				local grown = mount({ detent = "medium" }, { motionLevel = "none" })
				local before = grown.find("SheetPanel").Size.Y.Offset
				grown.find("Grabber").Activated:Fire()
				Verify.expect(grown.find("SheetPanel").Size.Y.Offset):toBe(570)
				Verify.expect(before < 570):toBe(true)
				Verify.expect((grown.detent:peek())):toBe("medium")
				grown.stop()
				local unknown = mount({ detent = "bogus" }, { motionLevel = "none" })
				Verify.expect(unknown.find("SheetPanel").Size.Y.Offset):toBe(before)
				unknown.stop()
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
							return UI.Sheet "Sheet"({
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
							})
						end),
					})
				end)
				local baseline = w.engine.census()
				shown:set(true)
				Verify.expect((pcall(function()
					overlay.find(w.find("Actions"), "Boom").Activated:Fire()
				end))):toBe(false)
				Verify.expect(w.find("SheetPanel") ~= nil):toBe(true)
				overlay.find(w.find("Actions"), "Finish").Activated:Fire()
				Verify.expect(w.find("SheetPanel") ~= nil):toBe(true)
				Verify.expect((shown:peek())):toBe(true)
				overlay.find(w.find("Actions"), "Drop").Activated:Fire()
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
			drag.DragStart:Fire(w.Vector2.new(0, y))
			for _, step in steps do
				w.tick(step[2])
				y += step[1]
				drag.DragContinue:Fire(w.Vector2.new(0, y))
			end
			if finish ~= false then
				drag.DragEnd:Fire()
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
				drag.DragEnd:Fire()
				Verify.expect((w.detent:peek())):toBe("medium")
				w.stop()
			end,
		})

		verifyHarness:case("an unrelated input change carries the drag", {
			id = "native_sheet_parts::native Sheet: gestures::an unrelated input change carries the drag",
			run = function()
				local w = mount(nil, { motionLevel = "none" })
				flick(w, { { -150, 0.1 } }, false)
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
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
				drag.DragContinue:Fire(w.Vector2.new(0, -400))
				drag.DragEnd:Fire()
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
				detector.DragStart:Fire(w.Vector2.new(400, 300))
				w.tick(0.05)
				detector.DragContinue:Fire(w.Vector2.new(400, 296))
				Verify.expect(panel.Size.Y.Offset):toBe(300)
				w.tick(0.5)
				detector.DragContinue:Fire(w.Vector2.new(400, 50))
				Verify.expect(panel.Size.Y.Offset):toBe(300 + 250 - 6)
				w.tick(0.5)
				detector.DragEnd:Fire()
				Verify.expect((w.detent:peek())):toBe("large")
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Touch)
				detector.DragStart:Fire(w.Vector2.new(400, 300))
				detector.DragContinue:Fire(w.Vector2.new(400, 310))
				Verify.expect(panel.Size.Y.Offset):toBe(570)
				detector.DragEnd:Fire()
				w.stop()
			end,
		})

		verifyHarness:case("a drag on the panel drives the sheet; a second stream cannot take it over", {
			id = "native_sheet_parts::native Sheet: gestures::a drag on the panel drives the sheet; a second stream cannot take it over",
			run = function()
				local w = mount(nil, { motionLevel = "none" })
				local detector, grip = w.find("PanelDrag"), w.find("UIDragDetector")
				detector.DragStart:Fire(w.Vector2.new(400, 300))
				w.tick(0.3)
				detector.DragContinue:Fire(w.Vector2.new(400, 100))
				local height = w.find("SheetPanel").Size.Y.Offset
				Verify.expect(height):toBe(300 + 200 - 6)
				grip.DragStart:Fire(w.Vector2.new(0, 0))
				grip.DragContinue:Fire(w.Vector2.new(0, 300))
				grip.DragEnd:Fire()
				Verify.expect(w.find("SheetPanel").Size.Y.Offset):toBe(height)
				Verify.expect((w.shown:peek())):toBe(true)
				w.tick(0.3)
				detector.DragEnd:Fire()
				Verify.expect((w.detent:peek())):toBe("large")
				w.stop()
				local touch = mount(nil, { motionLevel = "none" })
				touch.engine.environment.poke(touch.input, "PreferredInput", touch.Enum.PreferredInput.Touch)
				local panel = touch.find("PanelDrag")
				panel.DragStart:Fire(touch.Vector2.new(400, 300))
				panel.DragContinue:Fire(touch.Vector2.new(400, 290))
				Verify.expect(touch.find("SheetPanel").Size.Y.Offset):toBe(300)
				panel.DragContinue:Fire(touch.Vector2.new(400, 100))
				Verify.expect(touch.find("SheetPanel").Size.Y.Offset):toBe(300 + 200 - 14)
				panel.DragEnd:Fire()
				Verify.expect(panel.Enabled):toBe(true)
				touch.engine.environment.poke(touch.input, "PreferredInput", touch.Enum.PreferredInput.Gamepad)
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
				drag.DragEnd:Fire()
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
				w.find("PanelDrag").DragStart:Fire(w.Vector2.new(0, 0))
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
		verifyHarness:case("a docked sheet uses its grabber without a duplicate Close", {
			id = "native_sheet_parts::docked-single-dismissal",
			run = function()
				local w = mount()
				Verify.expect(w.find("Close").Visible):toBe(false)
				local grabber = w.find("Grabber")
				Verify.expect(grabber.Selectable):toBe(true)
				Verify.expect((grabber:GetAttribute("AccessibleLabel"))):toBe("Resize: Medium")
				grabber.Activated:Fire()
				Verify.expect((w.detent:peek())):toBe("large")
				Verify.expect((grabber:GetAttribute("AccessibleLabel"))):toBe("Close sheet")
				grabber.Activated:Fire()
				Verify.expect((w.shown:peek())):toBe(false)
				w.stop()
				local single = mount({
					detents = { "medium" } :: { SheetDetent },
				})
				local only = single.find("Grabber")
				Verify.expect(only.Selectable):toBe(true)
				Verify.expect((only:GetAttribute("AccessibleLabel"))):toBe("Close sheet")
				only.Activated:Fire()
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
					w.engine.environment.poke(w.gui, "ViewportDisplaySize", w.Enum.DisplaySize.Large)
					w.engine.environment.poke(w.input, "MouseEnabled", false)
					w.engine.environment.poke(w.input, "TouchEnabled", false)
					shown:set(true)
					Verify.expect((w.find("SheetPanel"):GetAttribute("FacetPlacement"))):toBe("center")
					Verify.expect(w.find("Grabber").Visible or w.find("Grabber").Selectable):toBe(false)
					Verify.expect(w.find("Close").Visible):toBe(true)
					Verify.expect(w.find("Grabber"):FindFirstChildWhichIsA("UIDragDetector").Enabled):toBe(false)
					local centeredInsets = sheetInsets(w)
					Verify.expect(centeredInsets.top):toBe(centeredInsets.bottom)
					w.engine.environment.poke(w.input, "MouseEnabled", true)
					Verify.expect((w.find("SheetPanel"):GetAttribute("FacetPlacement"))):toBe("bottom")
					Verify.expect(w.find("Grabber").Visible and w.find("Grabber").Selectable):toBe(true)
					Verify.expect(w.find("Close").Visible):toBe(false)
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
					drag.DragStart:Fire(w.Vector2.new(0, 0))
					drag.DragContinue:Fire(w.Vector2.new(0, 30))
					drag.DragEnd:Fire()
					grabber.Activated:Fire()
					Verify.expect((w.detent:peek())):toBe("medium")
					Verify.expect((w.shown:peek())):toBe(true)
					w.tick(0.5)
					drag.DragStart:Fire(w.Vector2.new(0, 0))
					drag.DragContinue:Fire(w.Vector2.new(0, 500))
					drag.DragEnd:Fire()
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
				close.Activated:Fire()
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
			local handle = w.find("Grabber")
			local part = w.find("DragHandle")
			Verify.expect(part.ClassName):toBe("Frame")
			Verify.expect(part.Selectable):toBe(false)
			return handle, part, sheetInsets(w)
		end

		verifyHarness:case("explicit Close replaces the grabber without a hidden selection link", {
			id = "native_sheet_parts::explicit-close-replaces-grabber",
			run = function()
				local w = mount({ closeButton = true }, WIDE)
				local grabber, close = w.find("Grabber"), w.find("Close")
				Verify.expect(grabber.Visible or grabber.Selectable):toBe(false)
				Verify.expect(close.NextSelectionUp == grabber or close.NextSelectionLeft == grabber):toBe(false)
				close.Activated:Fire()
				Verify.expect(w.shown:peek()):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("links the visible dismissal control directly to content in every placement", {
			id = "native_sheet_parts::visible-dismissal-selection",
			run = function()
				for _, extra in
					{
						{},
						{ placement = "side", edge = "left" },
						{ placement = "side", edge = "right" },
						{ placement = "center" },
						{ dragIndicator = "hidden" },
						{ header = false, hero = { image = "rbxassetid://1", height = 100, sticky = true } },
					} :: { any }
				do
					extra.content = built(function(UI: FacetControls)
						return UI.VStack {
							UI.Button "First" { label = "First" },
							UI.Button "Second" { label = "Second" },
						}
					end)
					local w = mount(extra, WIDE)
					local grabber, close, first = w.find("Grabber"), w.find("Close"), w.find("First")
					local panel = w.find("SheetPanel")
					local command = if grabber.Visible then grabber else close
					Verify.expect(close.Visible ~= grabber.Visible):toBe(true)
					Verify.expect(command.Selectable):toBe(true)
					Verify.expect(command.NextSelectionDown):toBe(first)
					Verify.expect(first.NextSelectionUp):toBe(command)
					Verify.expect(command.SelectionOrder < first.SelectionOrder):toBe(true)
					Verify.expect(command:IsDescendantOf(panel)):toBe(true)
					Verify.expect(panel.SelectionGroup):toBe(true)
					for _, direction in { "Up", "Down", "Left", "Right" } do
						Verify.expect(panel["SelectionBehavior" .. direction]):toBe(w.Enum.SelectionBehavior.Stop)
					end
					command.Activated:Fire({ UserInputType = w.Enum.UserInputType.MouseButton1 })
					Verify.expect(w.shown:peek()):toBe(false)
					w.stop()
				end
			end,
		})

		verifyHarness:case("the grip and content share an unpadded presentation group", {
			id = "native_sheet_parts::native Sheet: the grabber sits on the edge the sheet came from::the grip and content share an unpadded presentation group",
			run = function()
				local bindThemes = require("../src/ui/themes")
				local fantasy = (require :: any)("../examples/themes/fantasy_ornate").build(bindThemes(Compose))
				for _, extra in { {}, { placement = "side" :: "side" } } :: { any } do
					local w = mount(extra, { room = WIDE.room, motionLevel = "none", theme = fantasy })
					local panel = w.find("SheetPanel")
					local group = panel:FindFirstChild("Fade")
					Verify.expect(group.ClassName):toBe("CanvasGroup")
					Verify.expect(w.find("Grabber").Parent):toBe(group)
					Verify.expect(group:FindFirstChildWhichIsA("UIListLayout")):toBeNil()
					Verify.expect(group:FindFirstChildWhichIsA("UIPadding")):toBeNil()
					Verify.expect((panel:FindFirstChildWhichIsA("UIListLayout"))):toBeNil()
					local inset = panel:FindFirstChildWhichIsA("UIPadding")
					Verify.expect(inset == nil or (inset.PaddingLeft.Offset == 0 and inset.PaddingTop.Offset == 0))
						:toBe(true)
					Verify.expect(w.find("Room").Parent):toBe(group)
					w.stop()
				end
			end,
		})

		verifyHarness:case("a bottom sheet has a horizontal bar at the top and reserves the top", {
			id = "native_sheet_parts::native Sheet: the grabber sits on the edge the sheet came from::a bottom sheet has a horizontal bar at the top and reserves the top",
			run = function()
				local w = mount(nil, WIDE)
				local handle, pill, padding = grip(w)
				Verify.expect(handle.Size):toBe(w.engine.types.UDim2.fromOffset(88, 44))
				Verify.expect(handle.Position):toBe(w.engine.types.UDim2.new(0.5, 0, 0, 10))
				Verify.expect(handle.AnchorPoint):toBe(w.Vector2.new(0.5, 0.5))
				Verify.expect(pill.Size):toBe(w.engine.types.UDim2.fromOffset(36, 5))
				Verify.expect((handle:IsDescendantOf(w.find("Room")))):toBe(false)
				Verify.expect(padding.top):toBe(40)
				Verify.expect(padding.left):toBe(padding.right)
				w.stop()
			end,
		})

		verifyHarness:case("a sheet from the right has a vertical bar on its left edge and reserves the left", {
			id = "native_sheet_parts::native Sheet: the grabber sits on the edge the sheet came from::a sheet from the right has a vertical bar on its left edge and reserves the left",
			run = function()
				local w = mount({ placement = "side" :: "side" }, WIDE)
				local handle, pill, padding = grip(w)
				Verify.expect(handle.Size):toBe(w.engine.types.UDim2.fromOffset(44, 88))
				Verify.expect(handle.AnchorPoint):toBe(w.Vector2.new(0.5, 0.5))
				Verify.expect(handle.Position):toBe(w.engine.types.UDim2.new(0, 10, 0.5, 0))
				Verify.expect(pill.Size):toBe(w.engine.types.UDim2.fromOffset(5, 36))
				Verify.expect(padding.left - 28):toBe(padding.right)
				Verify.expect(padding.top):toBe(12)
				Verify.expect(padding.right):toBe(16)
				w.stop()
				local left = mount({ placement = "side" :: "side", edge = "left" :: "left" }, WIDE)
				local leftHandle, _, leftPadding = grip(left)
				Verify.expect(leftHandle.AnchorPoint):toBe(left.Vector2.new(0.5, 0.5))
				Verify.expect(leftHandle.Position):toBe(left.engine.types.UDim2.new(1, -10, 0.5, 0))
				Verify.expect(leftPadding.right):toBe(44)
				Verify.expect(leftPadding.left):toBe(16)
				left.stop()
			end,
		})

		verifyHarness:case("a hidden grabber reserves no side", {
			id = "native_sheet_parts::native Sheet: the grabber sits on the edge the sheet came from::a hidden grabber reserves no side",
			run = function()
				local w = mount({ dragIndicator = "hidden", placement = "side" :: "side" }, WIDE)
				local handle, _, padding = grip(w)
				Verify.expect(handle.Visible):toBe(false)
				Verify.expect(padding.left):toBe(16)
				Verify.expect(padding.top):toBe(12)
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
				drag.DragStart:Fire(w.Vector2.new(100, 300))
				w.tick(0.5)
				drag.DragContinue:Fire(w.Vector2.new(130, 300))
				Verify.expect(panel.Position.X.Offset):toBe(30)
				w.tick(0.5)
				drag.DragEnd:Fire()
				Verify.expect((w.shown:peek())):toBe(true)
				w.advance(0.5, 10)
				Verify.expect(panel.Position.X.Offset):toBe(0)
				drag.DragStart:Fire(w.Vector2.new(100, 300))
				w.tick(0.5)
				drag.DragContinue:Fire(w.Vector2.new(400, 300))
				Verify.expect(panel.Position.X.Offset):toBe(300)
				w.tick(0.5)
				drag.DragEnd:Fire()
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
					drag.DragStart:Fire(w.Vector2.new(0, 0))
					w.tick(0.5)
					drag.DragContinue:Fire(w.Vector2.new(0, 100))
					Verify.expect(panel.Size.Y.Offset):toBe(rest)
					Verify.expect(panel.Position.Y.Offset):toBe(100)
					Verify.expect((w.find("Actions"):IsDescendantOf(panel))):toBe(true)
					drag.DragContinue:Fire(w.Vector2.new(0, 250))
					w.tick(0.5)
					drag.DragEnd:Fire()
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

	verifyHarness:suite("native Sheet: a bottom sheet's plate reaches the glass", function()
		type Bands = { width: number, height: number, top: number, left: number, bottom: number, right: number }
		local PORTRAIT: Bands = { width = 390, height = 844, top = 106, left = 0, bottom = 34, right = 0 }
		local LANDSCAPE: Bands = { width = 844, height = 390, top = 58, left = 47, bottom = 21, right = 47 }
		type GlassSpec = { width: string?, placement: string?, motionLevel: string?, unsettled: boolean? }
		local RADIUS = 12

		local function glassSheet(bands: Bands, spec: GlassSpec)
			local safe = Vector2.new(bands.width - bands.left - bands.right, bands.height - bands.top - bands.bottom)
			local options = { shown = Compose.cell(false), motionLevel = spec.motionLevel, unsettled = spec.unsettled }
			local w = mount({ width = spec.width, placement = spec.placement }, options, { size = safe })
			local T = w.engine.types
			w.engine.environment.fakeOn(w.gui, "GetInsetArea", function(_self: unknown, inset: unknown): unknown
				if inset == T.Enum.ScreenInsets.None then
					return T.Rect.new(0, 0, bands.width, bands.height)
				end
				return T.Rect.new(bands.left, bands.top, bands.width - bands.right, bands.height - bands.bottom)
			end)
			w.engine.environment.poke(w.gui, "TopbarInset", T.Rect.new(0, 0, bands.width, bands.top))
			w.screen.ScreenInsets = T.Enum.ScreenInsets.CoreUISafeInsets
			w.screen.ClipToDeviceSafeArea = true
			w.shown:set(true)
			w.engine.environment.poke(w.find("Modal"), "AbsoluteSize", safe)
			if not spec.unsettled then
				w.advance(1 / 300, 2)
			end
			return w
		end

		local function box(node: GuiObject): { number }
			return { node.Position.X.Offset, node.Position.Y.Offset, node.Size.X.Offset, node.Size.Y.Offset }
		end

		verifyHarness:case("the plate continues under the home indicator; the content keeps its safe place", {
			id = "native_sheet_parts::native Sheet: a bottom sheet's plate reaches the glass::the plate continues under the home indicator; the content keeps its safe place",
			run = function()
				local safe = Vector2.new(390, 704)
				local plain = mount(nil, { room = safe, motionLevel = "none" }, { size = safe })
				local room = box(plain.find("Room"))
				local grip = box(plain.find("Grabber"))
				Verify.expect(box(plain.find("SheetPanel"))):toEqual({ 0, 0, 390, 352 })
				plain.stop()
				local w = glassSheet(PORTRAIT, { motionLevel = "none" })
				local band = 34 + RADIUS
				Verify.expect(box(w.find("SheetPanel"))):toEqual({ 0, band, 390, 352 + band })
				Verify.expect(box(w.find("Room"))):toEqual(room)
				Verify.expect(box(w.find("Grabber"))):toEqual(grip)
				Verify.expect((w.find("SheetPanel"):HasTag("facet-sheet"))):toBe(true)
				w.engine.environment.poke(w.input, "OnScreenKeyboardSize", Vector2.new(390, 250))
				w.engine.environment.poke(w.input, "OnScreenKeyboardVisible", true)
				Verify.expect(box(w.find("SheetPanel"))):toEqual({ 0, -250, 390, 227 })
				w.engine.environment.poke(w.input, "OnScreenKeyboardVisible", false)
				Verify.expect(box(w.find("SheetPanel"))):toEqual({ 0, band, 390, 352 + band })
				w.stop()
			end,
		})

		verifyHarness:case("the plate shares the device clipping lease with the scrim and returns it", {
			id = "native_sheet_parts::native Sheet: a bottom sheet's plate reaches the glass::the plate shares the device clipping lease with the scrim and returns it",
			run = function()
				local w = glassSheet(PORTRAIT, { motionLevel = "none" })
				local scrim = w.find("Scrim")
				Verify.expect(scrim.Position.Y.Offset):toBe(-106)
				Verify.expect(scrim.Size.Y.Offset):toBe(106 + 34)
				Verify.expect(w.screen.ClipToDeviceSafeArea):toBe(false)
				w.engine.environment.poke(w.input, "OnScreenKeyboardSize", Vector2.new(390, 250))
				w.engine.environment.poke(w.input, "OnScreenKeyboardVisible", true)
				Verify.expect(w.find("SheetPanel").Position.Y.Offset):toBe(-250)
				Verify.expect(w.screen.ClipToDeviceSafeArea):toBe(false)
				w.engine.environment.poke(w.input, "OnScreenKeyboardVisible", false)
				w.shown:set(false)
				w.advance(0.5, 10)
				Verify.expect((w.find("SheetPanel"))):toBeNil()
				Verify.expect((w.find("Scrim"))):toBeNil()
				Verify.expect(w.screen.ClipToDeviceSafeArea):toBe(true)
				w.shown:set(true)
				w.engine.environment.poke(w.find("Modal"), "AbsoluteSize", Vector2.new(390, 704))
				w.advance(1 / 300, 2)
				Verify.expect(w.find("SheetPanel").Position.Y.Offset):toBe(34 + RADIUS)
				Verify.expect(w.screen.ClipToDeviceSafeArea):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("a sheet as wide as the screen also reaches the side cutouts", {
			id = "native_sheet_parts::native Sheet: a bottom sheet's plate reaches the glass::a sheet as wide as the screen also reaches the side cutouts",
			run = function()
				for _, side in
					{
						{ left = 47, right = 47, past = 47 },
						{ left = 0, right = 48, past = 0 },
						{ left = 0, right = 47, past = 1 },
					}
				do
					local bands: Bands = {
						width = 844,
						height = 390,
						top = 58,
						left = side.left,
						bottom = 21,
						right = side.right,
					}
					local band = 21 + RADIUS
					local w = glassSheet(bands, { width = "wide", motionLevel = "none" })
					local panel, room = w.find("SheetPanel"), w.find("Room")
					Verify.expect(panel.Size.X.Offset):toBe(844 - side.left + side.past)
					Verify.expect(panel.Position.X.Offset):toBe((side.right - side.past) / 2)
					Verify.expect(panel.Position.Y.Offset):toBe(band)
					Verify.expect(room.Position.X.Offset):toBe(16 + side.past)
					Verify.expect(room.Size.X.Offset):toBe(-32 - side.past - side.right)
					Verify.expect(w.find("Grabber").Position.X.Offset):toBe((side.past - side.right) / 2)
					w.stop()
					local narrow = glassSheet(bands, { motionLevel = "none" })
					Verify.expect(box(narrow.find("SheetPanel"))[1]):toBe(0)
					Verify.expect(box(narrow.find("SheetPanel"))[2]):toBe(band)
					Verify.expect(box(narrow.find("SheetPanel"))[3]):toBe(560)
					Verify.expect(box(narrow.find("Room"))[1]):toBe(16)
					narrow.stop()
				end
			end,
		})

		verifyHarness:case("side and center sheets keep their plate at the safe area", {
			id = "native_sheet_parts::native Sheet: a bottom sheet's plate reaches the glass::side and center sheets keep their plate at the safe area",
			run = function()
				local safe = Vector2.new(750, 311)
				local still = { room = safe, motionLevel = "none" }
				for _, placement in { "side", "center" } do
					local plain = mount({ placement = placement }, still, { size = safe })
					local panel, room = box(plain.find("SheetPanel")), box(plain.find("Room"))
					plain.stop()
					local w = glassSheet(LANDSCAPE, { placement = placement, motionLevel = "none" })
					Verify.expect(box(w.find("SheetPanel"))):toEqual(panel)
					Verify.expect(box(w.find("Room"))):toEqual(room)
					Verify.expect(w.screen.ClipToDeviceSafeArea):toBe(false)
					w.shown:set(false)
					w.advance(0.5, 10)
					Verify.expect(w.screen.ClipToDeviceSafeArea):toBe(true)
					w.stop()
				end
			end,
		})

		verifyHarness:case("the plate moves with the panel past the glass and through a drag", {
			id = "native_sheet_parts::native Sheet: a bottom sheet's plate reaches the glass::the plate moves with the panel past the glass and through a drag",
			run = function()
				local w = glassSheet(PORTRAIT, { unsettled = true })
				local panel = w.find("SheetPanel")
				local band = 34 + RADIUS
				Verify.expect(panel.Size.Y.Offset):toBe(352 + band)
				Verify.expect(panel.Position.Y.Offset - panel.Size.Y.Offset):toBe(band)
				w.advance(1 / 300, 2)
				w.advance(0.5, 10)
				Verify.expect(box(panel)):toEqual({ 0, band, 390, 352 + band })
				local drag = w.find("UIDragDetector")
				drag.DragStart:Fire(w.Vector2.new(0, 0))
				w.tick(0.5)
				drag.DragContinue:Fire(w.Vector2.new(0, 100))
				Verify.expect(box(panel)):toEqual({ 0, 100 + band, 390, 352 + band })
				drag.DragContinue:Fire(w.Vector2.new(0, 250))
				w.tick(0.5)
				drag.DragEnd:Fire()
				Verify.expect((w.shown:peek())):toBe(false)
				w.advance(0.02, 1)
				Verify.expect(panel.Size.Y.Offset):toBe(352 + band)
				Verify.expect(panel.Position.Y.Offset >= 250 + band):toBe(true)
				w.advance(1, 20)
				Verify.expect((w.find("SheetPanel"))):toBeNil()
				Verify.expect(w.screen.ClipToDeviceSafeArea):toBe(true)
				w.stop()
			end,
		})
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
				Verify.expect((insetSides(w))):toBe("70 46 42 46")
				local bar = w.find("Grabber").Position.Y.Offset
				Verify.expect(bar - 10 >= 30 and bar + 10 <= 58):toBe(true)
				Verify.expect((w.find("Grabber"):GetAttribute("FacetFocusPart"))):toBe("DragHandle")
				w.stop()
				local side = mount({ placement = "side" :: "side" }, { theme = fantasy, room = Vector2.new(1200, 800) })
				Verify.expect((insetSides(side))):toBe("42 46 42 74")
				local x = side.find("Grabber").Position.X.Offset
				Verify.expect(x - 10 >= 30 and x + 10 <= 58):toBe(true)
				side.stop()
			end,
		})

		verifyHarness:case("keeps Sheet spacing inside a live theme carve even without body padding", {
			id = "native_sheet_parts::native panels: a skinned panel keeps its content inside the art carve::keeps Sheet spacing inside a live theme carve even without body padding",
			run = function()
				local themes = bindThemes(Compose)
				local theme = Compose.cell(fantasy)
				local w = mount({ contentInset = "none", dragIndicator = "hidden" }, { theme = theme })
				local padding = function(): string
					return insetSides(w)
				end
				Verify.expect((padding())):toBe("42 46 42 46")
				theme:set((require :: any)("../examples/themes/fantasy_parchment").build(themes))
				Verify.expect((padding())):toBe("30 34 30 34")
				local neutral = assert(themes.define(themes.neutralPackage()))
				theme:set(neutral)
				Verify.expect((padding())):toBe("12 16 12 16")
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
				w.engine.environment.poke(w.find("Cancel"), "TextBounds", Vector2.new(150, 20))
				w.engine.environment.poke(w.find("Apply"), "TextBounds", Vector2.new(150, 20))
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
				w.engine.environment.poke(caption, "TextBounds", w.Vector2.new(300.4, 38))
				Verify.expect(art.Size):toBe(w.engine.types.UDim2.fromOffset(301 + across, 38 + down))
				w.engine.environment.poke(caption, "TextBounds", w.Vector2.new(20, 10))
				Verify.expect(art.Size):toBe(w.engine.types.UDim2.fromOffset(176, 40))
				w.stop()
			end,
		})
	end)
end
