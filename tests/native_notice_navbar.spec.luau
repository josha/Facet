--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Compose = require("../src/vendor/compose/core")
	local overlay = require("./lib/overlay_world")
	local reservations = require("../src/ui/reservations")
	local Vector2 = require("@lune/roblox").Vector2

	local function mount(build: (any, any) -> any, options: any?): any
		return overlay.new(function(UI: FacetControls, Host: RobloxHost, engine, gui)
			return Host.Frame({ Name = "Page", build(UI, Host) })
		end, options)
	end

	verifyHarness:suite("native Notice: inline copy, accessories and close", function()
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
				overlay.find(notice, "Close").Activated.fire()
				Verify.expect(closes):toBe(1)
				Verify.expect((w.find("Connection"))):toBe(notice)
				w.stop()
			end,
		})

		verifyHarness:case("icon = false hides only the artwork, and an explicit source paints that source", {
			id = "native_notice_navbar::native Notice: inline copy, accessories and close::icon = false hides only the artwork, and an explicit source paints that source",
			run = function()
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Notice "Plain" { message = "No art", icon = false } :: unknown,
						UI.Notice "Custom" { message = "Custom art", icon = "rbxassetid://123" },
					})
				end)
				Verify.expect((overlay.find(w.find("Plain"), "Icon"))):toBeNil()
				Verify.expect(overlay.find(w.find("Plain"), "Message").Text):toBe("No art")
				Verify.expect(overlay.find(w.find("Custom"), "Icon").Image):toBe("rbxassetid://123")
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
					overlay.find(notice, "MessageMeasure").TextBounds = Vector2.new(220, 18)
					overlay.find(notice, "Accessories").AbsoluteSize = Vector2.new(160, 44)
					notice.AbsoluteSize = Vector2.new(800, 60)
					Verify.expect(layout.FillDirection):toBe(w.Enum.FillDirection.Horizontal)
					Verify.expect((notice:GetAttribute("NoticeAccessories"))):toBe("beside")
					notice.AbsoluteSize = Vector2.new(390, 110)
					Verify.expect(layout.FillDirection):toBe(w.Enum.FillDirection.Vertical)
					Verify.expect((notice:GetAttribute("NoticeAccessories"))):toBe("below")
					overlay.find(notice, "Retry").Activated.fire()
					overlay.find(notice, "Link").Activated.fire()
					Verify.expect((table.concat(pressed, ","))):toBe("Retry,Details")
					Verify.expect((w.find("Sync"))):toBe(notice)
					Verify.expect(notice.Parent ~= nil):toBe(true)
					w.stop()
				end,
			}
		)

		verifyHarness:case(
			"a link wears no plate, and on an emphasis fill the link and default action are ordinary controls",
			{
				id = "native_notice_navbar::native Notice: inline copy, accessories and close::a link wears no plate, and on an emphasis fill the link and default action are ordinary controls",
				run = function()
					local function spec(appearance: string): any
						return {
							message = "Update ready",
							appearance = appearance,
							severity = "success",
							link = { label = "Notes", onActivate = function() end },
							actions = {
								{
									id = "Install",
									label = "Install",
									role = "default" :: "default",
									onActivate = function() end,
								},
							},
						}
					end
					local w = mount(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							UI.Notice "Standard"(spec("standard")) :: unknown,
							UI.Notice "Loud"(spec("emphasis")),
						})
					end)
					local standard, loud = w.find("Standard"), w.find("Loud")
					Verify.expect((overlay.find(standard, "Link"):HasTag("facet-appearance-link"))):toBe(true)
					Verify.expect((overlay.find(standard, "Install"):HasTag("facet-accent"))):toBe(true)
					Verify.expect((overlay.find(loud, "Link"):HasTag("facet-appearance-link"))):toBe(false)
					Verify.expect((overlay.find(loud, "Install"):HasTag("facet-accent"))):toBe(false)
					Verify.expect((loud:HasTag("facet-status-success"))):toBe(true)
					Verify.expect((loud:HasTag("facet-panel"))):toBe(false)
					Verify.expect((overlay.find(loud, "Message"):HasTag("facet-status-success"))):toBe(true)
					Verify.expect((overlay.find(loud, "Icon"):HasTag("facet-icon-success"))):toBe(false)
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
				Verify.expect((w.find("DismissOutside"))):toBeNil()
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
				w.action("Activate").Pressed.fire()
				Verify.expect(pressed):toBe(1)
				retry.Activated.fire()
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
				banner.AbsolutePosition = Vector2.new(0, 0)
				banner.AbsoluteSize = Vector2.new(800, 52)
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
				first.AbsolutePosition, first.AbsoluteSize = Vector2.new(0, 0), Vector2.new(800, 40)
				second.AbsolutePosition, second.AbsoluteSize = Vector2.new(0, 48), Vector2.new(800, 40)
				Verify.expect((w.screen:GetAttribute("FacetInsetTop"))):toBe(88)
				local far = other.find("Banner")
				far.AbsolutePosition, far.AbsoluteSize = Vector2.new(0, 0), Vector2.new(800, 30)
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
					runService = true,
					onError = function(problem: unknown)
						table.insert(problems, tostring(problem))
					end,
				})
				local banner = w.find("Banner")
				banner.AbsoluteSize = Vector2.new(800, 40)
				w.advance(1 / 60)
				banner.AbsoluteSize = Vector2.new(800, 64)
				w.advance(1 / 60)
				banner.AbsoluteSize = Vector2.new(800, 96)
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
				banner.AbsoluteSize = Vector2.new(800, 40)
				Verify.expect((w.screen:GetAttribute("FacetInsetTop"))):toBe(40)
				message:set(string.rep("A much longer message. ", 10))
				banner.AbsoluteSize = Vector2.new(800, 96)
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
				back.Activated.fire()
				w.input.PreferredInput = w.Enum.PreferredInput.Touch
				back.Activated.fire()
				w.gui.SelectedObject = back
				w.action("Activate").Pressed.fire()
				Verify.expect(backs):toBe(3)
				Verify.expect(overlay.find(back, "LeadingIcon") ~= nil):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("Back, leading, a filling center and trailing share one row when there is room", {
			id = "native_notice_navbar::native NavBar: the slot form::Back, leading, a filling center and trailing share one row when there is room",
			run = function()
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					return UI.NavBar "Top" {
						onBack = function() end,
						leading = UI.Button "Home" { label = "Home" },
						center = UI.TextInput "Search" { value = Compose.cell("") },
						trailing = Host.Frame({ Name = "Tools", UI.Button "Filter" { label = "Filter" } }),
					}
				end)
				local bar = w.find("Top")
				local layout = bar:FindFirstChildWhichIsA("UIListLayout")
				Verify.expect(layout.FillDirection):toBe(w.Enum.FillDirection.Horizontal)
				local primary = w.find("Primary")
				Verify.expect(w.find("Back").Parent):toBe(primary)
				Verify.expect(w.find("Leading").Parent):toBe(primary)
				Verify.expect(w.find("Center").Parent):toBe(primary)
				Verify.expect(w.find("Back").LayoutOrder < w.find("Leading").LayoutOrder):toBe(true)
				Verify.expect(w.find("Leading").LayoutOrder < w.find("Center").LayoutOrder):toBe(true)
				Verify.expect(w.find("Center"):FindFirstChildWhichIsA("UIFlexItem").FlexMode)
					:toBe(w.Enum.UIFlexMode.Fill)
				Verify.expect(w.find("Search").Parent):toBe(w.find("Center"))
				Verify.expect(w.find("Tools").Parent):toBe(w.find("Trailing"))
				w.stop()
			end,
		})

		verifyHarness:case("Back is content-coloured text tight to its chevron, with a spacing step before the title", {
			id = "native_notice_navbar::native NavBar: the slot form::Back is content-coloured text tight to its chevron, with a spacing step before the title",
			run = function()
				local w = mount(function(UI: FacetControls)
					return UI.NavBar "Top" { onBack = function() end, title = "Garage" }
				end)
				local back = w.find("Back")
				Verify.expect((back:HasTag("facet-appearance-utility"))):toBe(true)
				Verify.expect((back:HasTag("facet-appearance-link"))):toBe(false)
				Verify.expect(overlay.find(back, "LeadingIcon") ~= nil):toBe(true)
				local row = overlay.find(back, "LeadingIcon").Parent:FindFirstChildWhichIsA("UIListLayout")
				Verify.expect(row.Padding.Offset):toBe(2)
				local gap = w.find("BackGap")
				Verify.expect(gap.Size.X.Offset):toBe(8)
				Verify.expect(back.LayoutOrder < gap.LayoutOrder and gap.LayoutOrder < w.find("Center").LayoutOrder)
					:toBe(true)
				w.stop()
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
					w.find("TitleMeasure").TextBounds = w.Vector2.new(70, 24)
					w.size(w.find("Trailing"), 40, 40)
					w.size(w.find("Primary"), 640, 24)
					w.size(w.find("Center"), 0, 0)
					w.size(w.find("Top"), 688, 40)
					Verify.expect(layout.FillDirection):toBe(w.Enum.FillDirection.Horizontal)
					w.stop()
				end,
			}
		)

		verifyHarness:case("a narrow bar moves the trailing content to a second row, without rebuilding the center", {
			id = "native_notice_navbar::native NavBar: the slot form::a narrow bar moves the trailing content to a second row, without rebuilding the center",
			run = function()
				local query = Compose.cell("coast")
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					return UI.NavBar "Top" {
						onBack = function() end,
						center = UI.TextInput "Search" { value = query },
						trailing = Host.Frame({ Name = "Tools", UI.Button "Filter" { label = "Filter" } }),
					}
				end)
				local bar, search = w.find("Top"), w.find("Search")
				local layout = bar:FindFirstChildWhichIsA("UIListLayout")
				w.size(w.find("Back"), 44, 44)
				w.size(w.find("Trailing"), 120, 44)
				w.size(w.find("Primary"), 1000 - 128, 44)
				w.size(w.find("Center"), 1000 - 128 - 52, 44)
				w.size(bar, 1000, 44)
				Verify.expect(layout.FillDirection):toBe(w.Enum.FillDirection.Horizontal)
				w.size(w.find("Primary"), 480 - 128, 44)
				w.size(w.find("Center"), 480 - 128 - 52, 44)
				w.size(bar, 480, 44)
				Verify.expect(layout.FillDirection):toBe(w.Enum.FillDirection.Vertical)
				Verify.expect((w.find("Search"))):toBe(search)
				Verify.expect(search.Text):toBe("coast")
				Verify.expect(w.find("Primary").Size.X.Scale):toBe(1)
				w.size(bar, 1000, 44)
				Verify.expect(layout.FillDirection):toBe(w.Enum.FillDirection.Horizontal)
				w.stop()
			end,
		})

		verifyHarness:case("the default center is the one-line title, and every slot subset mounts", {
			id = "native_notice_navbar::native NavBar: the slot form::the default center is the one-line title, and every slot subset mounts",
			run = function()
				local w = mount(function(UI: FacetControls)
					return UI.NavBar "Top" { title = "A very long track title that does not fit", titleSize = "heading" }
				end)
				local title = w.find("Title")
				Verify.expect(title.TextWrapped):toBe(false)
				Verify.expect(title.TextTruncate):toBe(w.Enum.TextTruncate.AtEnd)
				Verify.expect((title:HasTag("facet-type-heading"))):toBe(true)
				Verify.expect(title.Parent.Name):toBe("Center")
				Verify.expect((w.find("Back"))):toBeNil()
				w.stop()
				for index, spec in
					{
						{} :: any,
						{ onBack = function() end },
						{ leading = "button" },
						{ center = "button" :: "button" },
						{ trailing = "button" },
						{ onBack = function() end, trailing = "button", title = "T" },
					}
				do
					local bar = mount(function(UI: FacetControls)
						local built: { [string]: any } = table.clone(spec)
						for key, value in built do
							if value == "button" then
								built[key] = UI.Button({ label = tostring(key) })
							end
						end
						return UI.NavBar "Top"(built :: any)
					end)
					Verify.expect(`case {index}: {bar.find("Top") ~= nil}`):toBe(`case {index}: true`)
					bar.stop()
				end
			end,
		})

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
