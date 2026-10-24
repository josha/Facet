--!strict
local FixtureRoblox = require("../tools/vendor/verify/src/roblox")
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Compose = require("../src/vendor/compose/core")
	local Facet = require("../src")
	local Types = require("../src/ui/types")
	local engineLib = require("./lib/native_engine")
	local overlay = require("./lib/overlay_world")
	local reservations = require("../src/ui/reservations")
	local Vector2 = require("./lib/native_engine").types.Vector2

	local function mount(build: (any, any) -> any, options: Types.Config?, setup: overlay.Setup?): any
		return overlay.new(function(UI: FacetControls, Host: RobloxHost, engine, gui)
			return Host.Frame({ Name = "Page", build(UI, Host) })
		end, options, setup)
	end

	verifyHarness:suite("native NavBar overflow", function()
		verifyHarness:case("publishes a deferred affixed reservation on the configured native frame", {
			id = "native_notice_navbar::native NavBar overflow::publishes a deferred affixed reservation on the configured native frame",
			run = function()
				local engine = engineLib.new()
				local frameEngine = engineLib.new()
				local frames = frameEngine.heartbeat
				local host = Facet.Roblox.createHost(engine)
				local observation = assert(host.observation)
				local observe = observation.observeProperty
				observation.observeProperty = function(node, property, listener)
					return observe(node, property, function()
						if property ~= "AbsoluteSize" or (node :: Instance).Name ~= "Banner" then
							listener()
						end
					end)
				end
				local runtime: ComposeRuntime = Compose.createRuntime(host)
				local UI = Facet.controls(runtime, {
					types = engine.types,
					services = { RunService = ({ Heartbeat = frames } :: unknown) :: RunService },
				})
				local screen = engine.new("ScreenGui")
				local stop, node = runtime.mount(function()
					return UI.Notice "Banner" { placement = "affixed", message = "Saved" }
				end, screen)
				local banner = (node :: unknown) :: { AbsoluteSize: Vector2 }
				frameEngine.environment.poke(FixtureRoblox.assertInstance(banner), "AbsoluteSize", Vector2.new(800, 96))
				Verify.expect(screen:GetAttribute("FacetInsetTop")):toBe(0)
				frames:Fire(1 / 60)
				Verify.expect(screen:GetAttribute("FacetInsetTop")):toBe(96)
				stop()
				runtime:dispose()
				Verify.expect(frameEngine.census().connections):toBe(0)
			end,
		})
		verifyHarness:case("sizes the wrapped filter viewport from its native list instead of the automatic canvas", {
			id = "native_notice_navbar::native NavBar overflow::sizes the wrapped filter viewport from its native list instead of the automatic canvas",
			run = function()
				for _, width in { 320, 360, 375, 389, 390, 430 } do
					local w = mount(function(UI: FacetControls)
						return UI.NavBar "Header" {
							padding = 8,
							center = UI.TextInput "Search" { value = Compose.cell("Coastal") },
							trailing = UI.Button "Filter" { label = "Filter", icon = "menu" },
						}
					end)
					local header, trailing = w.find("Header"), w.find("Trailing")
					local layout = trailing:FindFirstChildWhichIsA("UIListLayout")
					local padding = header:FindFirstChildWhichIsA("UIPadding").PaddingRight.Offset
					for _, offered in { 1280, width, 1280, width } do
						w.engine.environment.poke(header, "AbsoluteSize", Vector2.new(offered - 38, 116))
						w.engine.environment.poke(trailing, "AbsoluteSize", Vector2.new(4, 48))
						w.engine.environment.poke(trailing, "AbsoluteCanvasSize", Vector2.new(87, 44))
						w.engine.environment.poke(layout, "AbsoluteContentSize", Vector2.new(83, 44))
						Verify.expect(trailing.AutomaticSize):toBe(w.Enum.AutomaticSize.None)
						Verify.expect(trailing.Size.X.Scale):toBe(0)
						Verify.expect(trailing.Size.X.Offset):toBe(83)
						Verify.expect(trailing.Size.Y.Offset):toBe(44)
						local bounds = trailing:FindFirstChild("ViewportBounds").MaxSize.X
						Verify.expect(bounds):toBe(offered - 38 - 2 * padding)
						local right = 16 + offered - 38 - padding
						local left = right - math.min(trailing.Size.X.Offset, bounds)
						Verify.expect(left >= 16 and left + 83 <= offered):toBe(true)
					end
					w.stop()
				end
			end,
		})

		verifyHarness:case("keeps the leading action inside a bounded scrolling row at phone widths", {
			id = "native_notice_navbar::native NavBar overflow::keeps the leading action inside a bounded scrolling row at phone widths",
			run = function()
				for _, width in { 320, 360, 375, 389, 430 } do
					local w = mount(function(UI: FacetControls)
						return UI.NavBar "Header" {
							title = "Discover",
							trailing = UI.HStack {
								UI.Button { label = "Spatial mode" },
								UI.Button { label = "Light mode" },
								UI.Button { label = "About" },
							},
						}
					end)
					local header, trailing = w.find("Header"), w.find("Trailing")
					w.engine.environment.poke(header, "AbsoluteSize", Vector2.new(width - 32, 80))
					Verify.expect(trailing:IsA("ScrollingFrame")):toBe(true)
					local content = trailing:FindFirstChildWhichIsA("UIListLayout")
					w.engine.environment.poke(content, "AbsoluteContentSize", Vector2.new(720, 36))
					Verify.expect(trailing.Size.Y.Offset):toBe(36 + trailing.ScrollBarThickness)
					Verify.expect(trailing.ScrollBarThickness):toBe(0)

					Verify.expect(trailing:FindFirstChild("ViewportBounds").MaxSize.X):toBe(width - 32)
					Verify.expect(trailing.CanvasPosition.X):toBe(0)
					Verify.expect(trailing:FindFirstChildWhichIsA("UIListLayout").HorizontalAlignment)
						:toBe(w.engine.types.Enum.HorizontalAlignment.Left)
					w.stop()
				end
			end,
		})
	end)

	verifyHarness:suite("native Notice: inline copy, accessories and close", function()
		verifyHarness:case("keeps native automatic message height with a text measurement service", function(t)
			local engine = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local height = 16 + 2 / 3
			local service = {
				GetTextBoundsAsync = function(_self: unknown, params: GetTextBoundsParams): Vector2
					return engine.types.Vector2.new(80, if params.Width > 0 then height else params.Size)
				end,
			}
			local UI = Facet.controls(runtime, {
				types = engine.types,
				services = { TextService = (service :: unknown) :: TextService },
			})
			local content = Compose.cell("Saved")
			local stop, node = runtime.mount(function()
				return UI.Notice { message = content }
			end, engine.new("ScreenGui"))
			local message = overlay.find(node, "Message")
			for _, width in { 200, 953 + 1 / 3, 100 } do
				engine.environment.poke(message, "AbsoluteSize", Vector2.new(width, 16))
				content:set(`Saved at {width}`)
				local floor = message:FindFirstChild("TextBoundsFloor")
				t:expect(message.AutomaticSize):toBe(engine.types.Enum.AutomaticSize.Y)
				t:expect(message.Size.Y.Offset):toBe(0)
				t:expect(message.TextWrapped):toBe(true)
				t:expect(floor.MinSize.Y):toBe(Vector2.new(0, height).Y)
				height += 16
			end
			stop()
			runtime:dispose()
			t:expect(engine.census().connections):toBe(0)
		end)
		verifyHarness:case("paints the severity icon, title and message, and the close reports the press only", {
			id = "native_notice_navbar::native Notice: inline copy, accessories and close::paints the severity icon, title and message, and the close reports the press only",
			run = function()
				local closes = 0
				local w = mount(function(UI: FacetControls)
					return UI.Notice "Connection" {
						severity = "warning" :: "warning",
						title = "Connection",
						message = "Connection interrupted",
						onDismiss = function()
							closes += 1
						end,
					}
				end)
				local notice = w.find("Connection")
				Verify.expect(overlay.find(notice, "Title").Text):toBe("Connection")
				Verify.expect(overlay.find(notice, "Message").Text):toBe("Connection interrupted")
				local icon = overlay.find(notice, "Icon")
				Verify.expect((icon:HasTag("facet-icon-warning"))):toBe(true)
				Verify.expect((notice:HasTag("facet-panel"))):toBe(true)
				overlay.find(notice, "Close").Activated:Fire()
				Verify.expect(closes):toBe(1)
				Verify.expect((w.find("Connection"))):toBe(notice)
				w.stop()
			end,
		})

		verifyHarness:case(
			"the link and actions sit beside the copy when there is room and move below it when there is not",
			{
				id = "native_notice_navbar::native Notice: inline copy, accessories and close::the link and actions sit beside the copy when there is room and move below it when there is not",
				run = function()
					local pressed: { string } = {}
					local w = mount(function(UI: FacetControls)
						return UI.Notice "Sync" {
							message = "Your changes are not synced",
							link = {
								label = "Details",
								onActivate = function()
									table.insert(pressed, "Details")
								end,
							},
							actions = {
								{
									id = "Retry",
									label = "Retry",
									role = "default" :: "default",
									onActivate = function()
										table.insert(pressed, "Retry")
									end,
								},
							},
						}
					end)
					local notice = w.find("Sync")
					local layout = overlay.find(notice, "Body"):FindFirstChildWhichIsA("UIListLayout")
					w.engine.environment.poke(
						overlay.find(notice, "MessageMeasure"),
						"TextBounds",
						Vector2.new(220, 18)
					)
					w.engine.environment.poke(overlay.find(notice, "Accessories"), "AbsoluteSize", Vector2.new(160, 44))
					w.engine.environment.poke(notice, "AbsoluteSize", Vector2.new(800, 60))
					Verify.expect(layout.FillDirection):toBe(w.Enum.FillDirection.Horizontal)
					Verify.expect(overlay.find(notice, "Copy"):FindFirstChildWhichIsA("UIFlexItem").FlexMode)
						:toBe(w.Enum.UIFlexMode.Fill)
					Verify.expect((notice:GetAttribute("NoticeAccessories"))):toBe("beside")
					w.engine.environment.poke(notice, "AbsoluteSize", Vector2.new(390, 110))
					Verify.expect(layout.FillDirection):toBe(w.Enum.FillDirection.Vertical)
					Verify.expect(overlay.find(notice, "Copy"):FindFirstChildWhichIsA("UIFlexItem").FlexMode)
						:toBe(w.Enum.UIFlexMode.None)
					Verify.expect((notice:GetAttribute("NoticeAccessories"))):toBe("below")
					overlay.find(notice, "Retry").Activated:Fire()
					overlay.find(notice, "Link").Activated:Fire()
					Verify.expect((table.concat(pressed, ","))):toBe("Retry,Details")
					Verify.expect((w.find("Sync"))):toBe(notice)
					Verify.expect(notice.Parent ~= nil):toBe(true)
					w.stop()
				end,
			}
		)

		verifyHarness:case("arrival never moves focus, and every control is a pad stop in the page's own order", {
			id = "native_notice_navbar::native Notice: inline copy, accessories and close::arrival never moves focus, and every control is a pad stop in the page's own order",
			run = function()
				local shown = Compose.cell(false)
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Button "Before" { label = "Before" } :: unknown,
						Compose.show(shown, function()
							return UI.Notice "Sync" {
								message = "Not synced",
								link = { label = "Details", onActivate = function() end },
								onDismiss = function() end,
							}
						end),
					})
				end)
				local before = w.find("Before")
				w.gui.SelectedObject = before
				shown:set(true)
				Verify.expect(w.gui.SelectedObject):toBe(before)
				Verify.expect(w.find("Link").Selectable):toBe(true)
				Verify.expect(w.find("Close").Selectable):toBe(true)
				Verify.expect((w.find("Scrim"))):toBeNil()
				Verify.expect((w.find("ModalBack"))):toBeNil()
				w.stop()
			end,
		})

		verifyHarness:case("keyboard and gamepad reach the action and press it; a pointer or finger taps it", {
			id = "native_notice_navbar::native Notice: inline copy, accessories and close::keyboard and gamepad reach the action and press it; a pointer or finger taps it",
			run = function()
				local pressed = 0
				local w = mount(function(UI: FacetControls)
					return UI.Notice "Sync" {
						message = "Not synced",
						actions = {
							{
								id = "Retry",
								label = "Retry",
								onActivate = function()
									pressed += 1
								end,
							},
						},
					}
				end)
				local retry = w.find("Retry")
				w.gui.SelectedObject = retry
				w.action("Activate").Pressed:Fire()
				Verify.expect(pressed):toBe(1)
				retry.Activated:Fire()
				Verify.expect(pressed):toBe(2)
				w.stop()
			end,
		})

		verifyHarness:case("malformed specs are refused by name", {
			id = "native_notice_navbar::native Notice: inline copy, accessories and close::malformed specs are refused by name",
			run = function()
				for index, bad in
					{
						{} :: any,
						{ message = 4 },
						{ message = "m", severity = "fatal" },
						{ message = "m", appearance = "loud" },
						{ message = "m", placement = "floating" :: "floating" },
						{ message = "m", icon = 4 },
						{ message = "m", link = { label = "L" } },
						{ message = "m", link = { label = "L", onActivate = function() end, extra = 1 } },
						{ message = "m", actions = { { id = "Close", label = "C", onActivate = function() end } } },
						{
							message = "m",
							actions = {
								{ id = "A", label = "A", onActivate = function() end },
								{ id = "B", label = "B", onActivate = function() end },
								{ id = "C", label = "C", onActivate = function() end },
							},
						},
						{ message = "m", onDismiss = true },
						{ message = "m", controlSize = "huge" :: "huge" },
						{ message = "m", tone = "x" },
					}
				do
					local ok = pcall(function()
						mount(function(UI: FacetControls)
							return UI.Notice(bad)
						end).stop()
					end)
					Verify.expect(`case {index}: {ok}`):toBe(`case {index}: false`)
				end
			end,
		})
	end)

	verifyHarness:suite("native Notice: affixed placement reserves space a real consumer avoids", function()
		local function consumer(w: any): () -> number
			return function()
				return w.screen:GetAttribute("FacetInsetTop") or 0
			end
		end

		verifyHarness:case("content moves down by the notice's real height and returns when it goes", {
			id = "native_notice_navbar::native Notice: affixed placement reserves space a real consumer avoids::content moves down by the notice's real height and returns when it goes",
			run = function()
				local shown = Compose.cell(true)
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					return Compose.show(shown, function()
						return UI.Notice "Banner" {
							placement = "affixed" :: "affixed",
							severity = "warning" :: "warning",
							message = "Offline",
						}
					end)
				end)
				local inset = consumer(w)
				local banner = w.find("Banner")
				Verify.expect(banner.Size.X.Scale):toBe(1)
				w.advance(0.3, 18)
				Verify.expect(banner.AutomaticSize):toBe(w.Enum.AutomaticSize.Y)
				w.engine.environment.poke(banner, "AbsolutePosition", Vector2.new(0, 0))
				w.engine.environment.poke(banner, "AbsoluteSize", Vector2.new(800, 52))
				Verify.expect((inset())):toBe(52)
				shown:set(false)
				Verify.expect((inset())):toBe(0)
				w.stop()
			end,
		})

		verifyHarness:case("two stacked notices reserve the deepest edge, and two worlds never collide", {
			id = "native_notice_navbar::native Notice: affixed placement reserves space a real consumer avoids::two stacked notices reserve the deepest edge, and two worlds never collide",
			run = function()
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						Name = "Stack",
						UI.Notice "Banner" { placement = "affixed" :: "affixed", message = "One" } :: unknown,
						UI.Notice "Banner2" { placement = "affixed" :: "affixed", message = "Two" },
					})
				end)
				local other = mount(function(UI: FacetControls)
					return UI.Notice "Banner" { placement = "affixed" :: "affixed", message = "Elsewhere" }
				end)
				local first, second = w.find("Banner"), w.find("Banner2")
				w.engine.environment.poke(FixtureRoblox.assertInstance(first), "AbsolutePosition", Vector2.new(0, 0))
				w.engine.environment.poke(FixtureRoblox.assertInstance(first), "AbsoluteSize", Vector2.new(800, 40))
				w.engine.environment.poke(FixtureRoblox.assertInstance(second), "AbsolutePosition", Vector2.new(0, 48))
				w.engine.environment.poke(FixtureRoblox.assertInstance(second), "AbsoluteSize", Vector2.new(800, 40))
				Verify.expect((w.screen:GetAttribute("FacetInsetTop"))):toBe(88)
				local far = other.find("Banner")
				other.engine.environment.poke(FixtureRoblox.assertInstance(far), "AbsolutePosition", Vector2.new(0, 0))
				other.engine.environment.poke(FixtureRoblox.assertInstance(far), "AbsoluteSize", Vector2.new(800, 30))
				Verify.expect((other.screen:GetAttribute("FacetInsetTop"))):toBe(30)
				Verify.expect((w.screen:GetAttribute("FacetInsetTop"))):toBe(88)
				local token = {}
				reservations.set(w.screen, token, "top", 0, 120)
				Verify.expect((w.screen:GetAttribute("FacetInsetTop"))):toBe(120)
				reservations.clear(w.screen, token)
				Verify.expect((w.screen:GetAttribute("FacetInsetTop"))):toBe(88)
				w.stop()
				other.stop()
			end,
		})

		verifyHarness:case("a reservation that moves again re-reads on the next frame without an owner error", {
			id = "native_notice_navbar::native Notice: affixed placement reserves space a real consumer avoids::a reservation that moves again re-reads on the next frame without an owner error",
			run = function()
				local problems: { string } = {}
				local message = Compose.cell("Short")
				local w = mount(function(UI: FacetControls)
					return UI.Notice "Banner" { placement = "affixed" :: "affixed", message = message }
				end, {
					onError = function(problem: unknown)
						table.insert(problems, tostring(problem))
					end,
				}, { runService = true })
				local banner = w.find("Banner")
				w.engine.environment.poke(banner, "AbsoluteSize", Vector2.new(800, 40))
				w.advance(1 / 60)
				w.engine.environment.poke(banner, "AbsoluteSize", Vector2.new(800, 64))
				w.advance(1 / 60)
				w.engine.environment.poke(banner, "AbsoluteSize", Vector2.new(800, 96))
				w.advance(1 / 60, 2)
				Verify.expect((table.concat(problems, "\n"))):toBe("")
				Verify.expect((w.screen:GetAttribute("FacetInsetTop"))):toBe(96)
				w.stop()
			end,
		})

		verifyHarness:case("a taller message grows the reservation live", {
			id = "native_notice_navbar::native Notice: affixed placement reserves space a real consumer avoids::a taller message grows the reservation live",
			run = function()
				local message = Compose.cell("Short")
				local w = mount(function(UI: FacetControls)
					return UI.Notice "Banner" { placement = "affixed" :: "affixed", message = message }
				end)
				local banner = w.find("Banner")
				w.engine.environment.poke(banner, "AbsoluteSize", Vector2.new(800, 40))
				Verify.expect((w.screen:GetAttribute("FacetInsetTop"))):toBe(40)
				message:set(string.rep("A much longer message. ", 10))
				w.engine.environment.poke(banner, "AbsoluteSize", Vector2.new(800, 96))
				Verify.expect((w.screen:GetAttribute("FacetInsetTop"))):toBe(96)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native NavBar: the slot form", function()
		verifyHarness:case("Back fires by pointer, touch, keyboard and gamepad", {
			id = "native_notice_navbar::native NavBar: the slot form::Back fires by pointer, touch, keyboard and gamepad",
			run = function()
				local backs = 0
				local w = mount(function(UI: FacetControls)
					return UI.NavBar "Top" {
						title = "Tracks",
						backLabel = "Back",
						onBack = function()
							backs += 1
						end,
					}
				end)
				local back = w.find("Back")
				back.Activated:Fire()
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Touch)
				back.Activated:Fire()
				w.gui.SelectedObject = back
				Verify.expect(w.gui.SelectedObject):toBeNil()
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.KeyboardAndMouse)
				w.gui.SelectedObject = back
				w.action("Activate").Pressed:Fire()
				Verify.expect(backs):toBe(3)
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
				w.gui.SelectedObject = back
				w.action("Activate").Pressed:Fire()
				Verify.expect(backs):toBe(4)
				Verify.expect(overlay.find(back, "LeadingIcon") ~= nil):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("shows Back while a boolean onBack cell is true and writes false", {
			id = "native_notice_navbar::native NavBar: the slot form::shows Back while a boolean onBack cell is true and writes false",
			run = function()
				local onBack = Compose.cell(false)
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					return UI.NavBar "Top" {
						title = "Shop",
						backLabel = "Parts",
						onBack = onBack,
						trailing = Host.Frame({ Name = "Tools", UI.Button "Close" { label = "Close" } }),
					}
				end)
				local back, gap = w.find("Back"), w.find("BackGap")
				local layout = w.find("Top"):FindFirstChildWhichIsA("UIListLayout")
				Verify.expect(back.Visible or gap.Visible):toBe(false)
				w.find("TitleMeasure").TextBounds = w.Vector2.new(70, 24)
				w.size(back, 200, 24)
				w.size(w.find("Trailing"), 40, 40)
				w.size(w.find("Top"), 300, 40)
				Verify.expect(layout.FillDirection):toBe(w.Enum.FillDirection.Horizontal)
				onBack:set(true)
				Verify.expect(back.Visible and gap.Visible):toBe(true)
				Verify.expect(layout.FillDirection):toBe(w.Enum.FillDirection.Vertical)
				back.Activated:Fire()
				Verify.expect((onBack:peek())):toBe(false)
				Verify.expect(back.Visible or gap.Visible):toBe(false)
				Verify.expect(layout.FillDirection):toBe(w.Enum.FillDirection.Horizontal)
				w.stop()
				local readOnly = Compose.formula(function(): boolean
					return true
				end)
				local accepted = pcall(function()
					mount(function(UI: FacetControls)
						return UI.NavBar { onBack = (readOnly :: unknown) :: Facet.Cell<boolean> }
					end).stop()
				end)
				Verify.expect(accepted):toBe(false)
			end,
		})

		verifyHarness:case(
			"a new bar keeps one row while its filling title row is still laid out, so it never flashes",
			{
				id = "native_notice_navbar::native NavBar: the slot form::a new bar keeps one row while its filling title row is still laid out, so it never flashes",
				run = function()
					local w = mount(function(UI: FacetControls, Host: RobloxHost)
						return UI.NavBar "Top" {
							title = "Garage",
							trailing = Host.Frame({ Name = "Tools", UI.Button "Edit" { label = "Edit" } }),
						}
					end)
					local layout = w.find("Top"):FindFirstChildWhichIsA("UIListLayout")
					w.engine.environment.poke(w.find("TitleMeasure"), "TextBounds", w.Vector2.new(70, 24))
					w.size(w.find("Trailing"), 40, 40)
					w.size(w.find("Primary"), 640, 24)
					w.size(w.find("Center"), 0, 0)
					w.size(w.find("Top"), 688, 40)
					Verify.expect(layout.FillDirection):toBe(w.Enum.FillDirection.Horizontal)
					w.stop()
				end,
			}
		)

		verifyHarness:case("UI.NavBar refuses a trailing array and a non-GuiObject slot", {
			id = "native_notice_navbar::native NavBar: the slot form::UI.NavBar refuses a trailing array and a non-GuiObject slot",
			run = function()
				for index, bad in
					{
						{ trailing = "array" } :: any,
						{ leading = "text" },
						{ center = 4 },
						{ onBack = "go" },
						{ titleWidth = 100 },
					}
				do
					local ok = pcall(function()
						mount(function(UI: FacetControls)
							local built: { [string]: any } = table.clone(bad)
							if built.trailing == "array" then
								built.trailing = { UI.Button({ label = "A" }), UI.Button({ label = "B" }) }
							end
							return UI.NavBar(built :: any)
						end).stop()
					end)
					Verify.expect(`case {index}: {ok}`):toBe(`case {index}: false`)
				end
			end,
		})
	end)
end
