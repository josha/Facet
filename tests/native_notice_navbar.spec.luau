--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local overlay = require("./lib/overlay_world")
local reservations = require("../src/ui/reservations")
local Vector2 = require("@lune/roblox").Vector2

local function mount(build: (any, any) -> any, options: any?): any
	return overlay.new(function(UI, Host, engine, gui)
		return Host.Frame({ Name = "Page", build(UI, Host) })
	end, options)
end

t.describe("native Notice: inline copy, accessories and close", function()
	t.it("paints the severity icon, title and message, and the close reports the press only", function()
		local closes = 0
		local w = mount(function(UI)
			return UI.Notice "Connection" {
				severity = "warning",
				title = "Connection",
				message = "Connection interrupted",
				onDismiss = function()
					closes += 1
				end,
			}
		end)
		local notice = w.find("Connection")
		t.expect(overlay.find(notice, "Title").Text).toBe("Connection")
		t.expect(overlay.find(notice, "Message").Text).toBe("Connection interrupted")
		local icon = overlay.find(notice, "Icon")
		t.expect(icon:HasTag("facet-icon-warning")).toBe(true)
		t.expect(notice:HasTag("facet-panel")).toBe(true)
		overlay.find(notice, "Close").Activated.fire()
		t.expect(closes).toBe(1)
		t.expect(w.find("Connection")).toBe(notice)
		w.stop()
	end)

	t.it("icon = false hides only the artwork, and an explicit source paints that source", function()
		local w = mount(function(UI, Host)
			return Host.Frame({
				UI.Notice "Plain" { message = "No art", icon = false },
				UI.Notice "Custom" { message = "Custom art", icon = "rbxassetid://123" },
			})
		end)
		t.expect(overlay.find(w.find("Plain"), "Icon")).toBeNil()
		t.expect(overlay.find(w.find("Plain"), "Message").Text).toBe("No art")
		t.expect(overlay.find(w.find("Custom"), "Icon").Image).toBe("rbxassetid://123")
		w.stop()
	end)

	t.it("the link and actions sit beside the copy when there is room and move below it when there is not", function()
		local w = mount(function(UI)
			return UI.Notice "Sync" {
				message = "Your changes are not synced",
				link = { label = "Details", onActivate = function() end },
				actions = { { id = "Retry", label = "Retry", onActivate = function() end } },
			}
		end)
		local notice = w.find("Sync")
		local layout = overlay.find(notice, "Body"):FindFirstChildWhichIsA("UIListLayout")
		overlay.find(notice, "MessageMeasure").TextBounds = Vector2.new(220, 18)
		overlay.find(notice, "Accessories").AbsoluteSize = Vector2.new(160, 44)
		notice.AbsoluteSize = Vector2.new(800, 60)
		t.expect(layout.FillDirection).toBe(w.Enum.FillDirection.Horizontal)
		t.expect(notice:GetAttribute("NoticeAccessories")).toBe("beside")
		notice.AbsoluteSize = Vector2.new(390, 110)
		t.expect(layout.FillDirection).toBe(w.Enum.FillDirection.Vertical)
		t.expect(notice:GetAttribute("NoticeAccessories")).toBe("below")
		w.stop()
	end)

	t.it("a link wears no plate, and on an emphasis fill the link and default action are ordinary controls", function()
		local function spec(appearance: string): any
			return {
				message = "Update ready",
				appearance = appearance,
				severity = "success",
				link = { label = "Notes", onActivate = function() end },
				actions = { { id = "Install", label = "Install", role = "default", onActivate = function() end } },
			}
		end
		local w = mount(function(UI, Host)
			return Host.Frame({ UI.Notice "Standard"(spec("standard")), UI.Notice "Loud"(spec("emphasis")) })
		end)
		local standard, loud = w.find("Standard"), w.find("Loud")
		t.expect(overlay.find(standard, "Link"):HasTag("facet-appearance-link")).toBe(true)
		t.expect(overlay.find(standard, "Install"):HasTag("facet-accent")).toBe(true)
		t.expect(overlay.find(loud, "Link"):HasTag("facet-appearance-link")).toBe(false)
		t.expect(overlay.find(loud, "Install"):HasTag("facet-accent")).toBe(false)
		t.expect(loud:HasTag("facet-status-success")).toBe(true)
		t.expect(loud:HasTag("facet-panel")).toBe(false)
		t.expect(overlay.find(loud, "Message"):HasTag("facet-status-success")).toBe(true)
		t.expect(overlay.find(loud, "Icon"):HasTag("facet-icon-success")).toBe(false)
		w.stop()
	end)

	t.it("arrival never moves focus, and every control is a pad stop in the page's own order", function()
		local shown = Compose.cell(false)
		local w = mount(function(UI, Host)
			return Host.Frame({
				UI.Button "Before" { label = "Before" },
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
		t.expect(w.gui.SelectedObject).toBe(before)
		t.expect(w.find("Link").Selectable).toBe(true)
		t.expect(w.find("Close").Selectable).toBe(true)
		t.expect(w.find("DismissOutside")).toBeNil()
		t.expect(w.find("ModalBack")).toBeNil()
		w.stop()
	end)

	t.it("keyboard and gamepad reach the action and press it; a pointer or finger taps it", function()
		local pressed = 0
		local w = mount(function(UI)
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
		t.expect(pressed).toBe(1)
		retry.Activated.fire()
		t.expect(pressed).toBe(2)
		w.stop()
	end)

	t.it("malformed specs are refused by name", function()
		for index, bad in
			{
				{} :: any,
				{ message = 4 },
				{ message = "m", severity = "fatal" },
				{ message = "m", appearance = "loud" },
				{ message = "m", placement = "floating" },
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
				{ message = "m", controlSize = "huge" },
				{ message = "m", tone = "x" },
			}
		do
			local ok = pcall(function()
				mount(function(UI)
					return UI.Notice(bad)
				end).stop()
			end)
			t.expect(`case {index}: {ok}`).toBe(`case {index}: false`)
		end
	end)
end)

t.describe("native Notice: affixed placement reserves space a real consumer avoids", function()
	local function consumer(w: any): () -> number
		return function()
			return w.screen:GetAttribute("FacetInsetTop") or 0
		end
	end

	t.it("content moves down by the notice's real height and returns when it goes", function()
		local shown = Compose.cell(true)
		local w = mount(function(UI, Host)
			return Compose.show(shown, function()
				return UI.Notice "Banner" { placement = "affixed", severity = "warning", message = "Offline" }
			end)
		end)
		local inset = consumer(w)
		local banner = w.find("Banner")
		t.expect(banner.Size.X.Scale).toBe(1)
		w.advance(0.3, 18)
		t.expect(banner.AutomaticSize).toBe(w.Enum.AutomaticSize.Y)
		banner.AbsolutePosition = Vector2.new(0, 0)
		banner.AbsoluteSize = Vector2.new(800, 52)
		t.expect(inset()).toBe(52)
		shown:set(false)
		t.expect(inset()).toBe(0)
		w.stop()
	end)

	t.it("two stacked notices reserve the deepest edge, and two worlds never collide", function()
		local w = mount(function(UI, Host)
			return Host.Frame({
				Name = "Stack",
				UI.Notice "Banner" { placement = "affixed", message = "One" },
				UI.Notice "Banner2" { placement = "affixed", message = "Two" },
			})
		end)
		local other = mount(function(UI)
			return UI.Notice "Banner" { placement = "affixed", message = "Elsewhere" }
		end)
		local first, second = w.find("Banner"), w.find("Banner2")
		first.AbsolutePosition, first.AbsoluteSize = Vector2.new(0, 0), Vector2.new(800, 40)
		second.AbsolutePosition, second.AbsoluteSize = Vector2.new(0, 48), Vector2.new(800, 40)
		t.expect(w.screen:GetAttribute("FacetInsetTop")).toBe(88)
		local far = other.find("Banner")
		far.AbsolutePosition, far.AbsoluteSize = Vector2.new(0, 0), Vector2.new(800, 30)
		t.expect(other.screen:GetAttribute("FacetInsetTop")).toBe(30)
		t.expect(w.screen:GetAttribute("FacetInsetTop")).toBe(88)
		local token = {}
		reservations.set(w.screen, token, "top", 0, 120)
		t.expect(w.screen:GetAttribute("FacetInsetTop")).toBe(120)
		reservations.clear(w.screen, token)
		t.expect(w.screen:GetAttribute("FacetInsetTop")).toBe(88)
		w.stop()
		other.stop()
	end)

	t.it("a reservation that moves again re-reads on the next frame without an owner error", function()
		local problems: { string } = {}
		local message = Compose.cell("Short")
		local w = mount(function(UI)
			return UI.Notice "Banner" { placement = "affixed", message = message }
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
		t.expect(table.concat(problems, "\n")).toBe("")
		t.expect(w.screen:GetAttribute("FacetInsetTop")).toBe(96)
		w.stop()
	end)

	t.it("a taller message grows the reservation live", function()
		local message = Compose.cell("Short")
		local w = mount(function(UI)
			return UI.Notice "Banner" { placement = "affixed", message = message }
		end)
		local banner = w.find("Banner")
		banner.AbsoluteSize = Vector2.new(800, 40)
		t.expect(w.screen:GetAttribute("FacetInsetTop")).toBe(40)
		message:set(string.rep("A much longer message. ", 10))
		banner.AbsoluteSize = Vector2.new(800, 96)
		t.expect(w.screen:GetAttribute("FacetInsetTop")).toBe(96)
		w.stop()
	end)
end)

t.describe("native NavBar: the slot form", function()
	t.it("Back fires by pointer, touch, keyboard and gamepad", function()
		local backs = 0
		local w = mount(function(UI)
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
		t.expect(backs).toBe(3)
		t.expect(overlay.find(back, "LeadingIcon") ~= nil).toBe(true)
		w.stop()
	end)

	t.it("Back, leading, a filling center and trailing share one row when there is room", function()
		local w = mount(function(UI, Host)
			return UI.NavBar "Top" {
				onBack = function() end,
				leading = UI.Button "Home" { label = "Home" },
				center = UI.TextInput "Search" { value = Compose.cell("") },
				trailing = Host.Frame({ Name = "Tools", UI.Button "Filter" { label = "Filter" } }),
			}
		end)
		local bar = w.find("Top")
		local layout = bar:FindFirstChildWhichIsA("UIListLayout")
		t.expect(layout.FillDirection).toBe(w.Enum.FillDirection.Horizontal)
		local primary = w.find("Primary")
		t.expect(w.find("Back").Parent).toBe(primary)
		t.expect(w.find("Leading").Parent).toBe(primary)
		t.expect(w.find("Center").Parent).toBe(primary)
		t.expect(w.find("Back").LayoutOrder < w.find("Leading").LayoutOrder).toBe(true)
		t.expect(w.find("Leading").LayoutOrder < w.find("Center").LayoutOrder).toBe(true)
		t.expect(w.find("Center"):FindFirstChildWhichIsA("UIFlexItem").FlexMode).toBe(w.Enum.UIFlexMode.Fill)
		t.expect(w.find("Search").Parent).toBe(w.find("Center"))
		t.expect(w.find("Tools").Parent).toBe(w.find("Trailing"))
		w.stop()
	end)

	t.it("a narrow bar moves the trailing content to a second row, without rebuilding the center", function()
		local query = Compose.cell("coast")
		local w = mount(function(UI, Host)
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
		t.expect(layout.FillDirection).toBe(w.Enum.FillDirection.Horizontal)
		w.size(w.find("Primary"), 480 - 128, 44)
		w.size(w.find("Center"), 480 - 128 - 52, 44)
		w.size(bar, 480, 44)
		t.expect(layout.FillDirection).toBe(w.Enum.FillDirection.Vertical)
		t.expect(w.find("Search")).toBe(search)
		t.expect(search.Text).toBe("coast")
		t.expect(w.find("Primary").Size.X.Scale).toBe(1)
		w.size(bar, 1000, 44)
		t.expect(layout.FillDirection).toBe(w.Enum.FillDirection.Horizontal)
		w.stop()
	end)

	t.it("the default center is the one-line title, and every slot subset mounts", function()
		local w = mount(function(UI)
			return UI.NavBar "Top" { title = "A very long track title that does not fit", titleSize = "heading" }
		end)
		local title = w.find("Title")
		t.expect(title.TextWrapped).toBe(false)
		t.expect(title.TextTruncate).toBe(w.Enum.TextTruncate.AtEnd)
		t.expect(title:HasTag("facet-type-heading")).toBe(true)
		t.expect(title.Parent.Name).toBe("Center")
		t.expect(w.find("Back")).toBeNil()
		w.stop()
		for index, spec in
			{
				{} :: any,
				{ onBack = function() end },
				{ leading = "button" },
				{ center = "button" },
				{ trailing = "button" },
				{ onBack = function() end, trailing = "button", title = "T" },
			}
		do
			local bar = mount(function(UI)
				local built = table.clone(spec)
				for key, value in built do
					if value == "button" then
						built[key] = UI.Button({ label = key })
					end
				end
				return UI.NavBar "Top"(built)
			end)
			t.expect(`case {index}: {bar.find("Top") ~= nil}`).toBe(`case {index}: true`)
			bar.stop()
		end
	end)

	t.it("UI.NavBar refuses a trailing array and a non-GuiObject slot", function()
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
				mount(function(UI)
					local built = table.clone(bad)
					if built.trailing == "array" then
						built.trailing = { UI.Button({ label = "A" }), UI.Button({ label = "B" }) }
					end
					return UI.NavBar(built)
				end).stop()
			end)
			t.expect(`case {index}: {ok}`).toBe(`case {index}: false`)
		end
	end)
end)
