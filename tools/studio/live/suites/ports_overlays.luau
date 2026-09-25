--!strict
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local cases = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function interactive(
	id: string,
	contracts: { string },
	plan: string,
	setup: (any) -> any,
	steps: { [string]: (any, any) -> () }
)
	table.insert(cases, { id = id, contracts = contracts, plan = plan, setup = setup, steps = steps })
end

local function selectedName(): string
	local selected = GuiService.SelectedObject
	return if selected then selected.Name else "nil"
end

local function visibleNamed(t: any, root: Instance, name: string): any
	for _, node in root:GetDescendants() do
		if node.Name == name and node:IsA("GuiObject") and t.visible(node) then
			return node
		end
	end
	return nil
end

local function layerOf(stage: any): any
	return stage:FindFirstAncestorWhichIsA("LayerCollector")
end

local function box(x: number, y: number, r: number, b: number): any
	return { x = x, y = y, w = r - x, h = b - y, r = r, b = b }
end

local function shrink(rect: any, left: number, top: number, right: number, bottom: number): any
	return box(rect.x + left, rect.y + top, rect.r - right, rect.b - bottom)
end

local function overlap(a: any, b: any): boolean
	local w = math.min(a.r, b.r) - math.max(a.x, b.x)
	local h = math.min(a.b, b.b) - math.max(a.y, b.y)
	return w > 0.5 and h > 0.5
end

local function whole(t: any, node: any): boolean
	local seen = t.clipped(node)
	if seen == nil then
		return false
	end
	local full = t.rect(node)
	return seen.h >= full.h - 1 and seen.w >= full.w - 1
end

local function styled(node: any, property: string): any
	local ok, value = pcall(function()
		return node:GetStyled(property)
	end)
	if ok and value ~= nil then
		return value
	end
	return node[property]
end

local function luminance(color: Color3): number
	local function channel(value: number): number
		return if value <= 0.03928 then value / 12.92 else ((value + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
end

local function contrast(a: Color3, b: Color3): number
	local x, y = luminance(a), luminance(b)
	if x < y then
		x, y = y, x
	end
	return (x + 0.05) / (y + 0.05)
end

local function scenario(t: any, name: string, size: any, theme: any?): (any, any)
	local built
	local stage = t.mount(function(UI, Host, Compose, env)
		built = t.scenario(name).build(t.context(UI, Host, Compose, env))
		return if type(built) == "function" then built() else built.screen()
	end, { size = size, theme = theme, frames = 20 })
	return stage, built
end

local function chain(node: Instance): { any }
	local list = {}
	local at: Instance? = node
	while at do
		if at:IsA("GuiObject") or at:IsA("LayerCollector") then
			table.insert(list, at)
		end
		if at:IsA("LayerCollector") then
			break
		end
		at = at.Parent
	end
	return list
end

local function paintsAbove(a: Instance, b: Instance): (boolean?, any)
	local ca, cb = chain(a), chain(b)
	local index = {}
	for position, node in cb do
		index[node] = position
	end
	for position, node in ca do
		local other = index[node]
		if other then
			if position == 1 or other == 1 then
				return nil, { "nested", node.Name }
			end
			local ea, eb = ca[position - 1], cb[other - 1]
			local detail = { ea.Name, ea.ZIndex, eb.Name, eb.ZIndex, node.Name }
			if ea.ZIndex == eb.ZIndex then
				return nil, detail
			end
			return ea.ZIndex > eb.ZIndex, detail
		end
	end
	local la, lb = ca[#ca], cb[#cb]
	if la and lb and la:IsA("ScreenGui") and lb:IsA("ScreenGui") and la.DisplayOrder ~= lb.DisplayOrder then
		return la.DisplayOrder > lb.DisplayOrder, { la.Name, la.DisplayOrder, lb.Name, lb.DisplayOrder }
	end
	return nil, "unrelated"
end

local function device(t: any, options: { [string]: any }): Vector2?
	local ok, result = pcall(t.device, options)
	if not ok then
		t.note(`device {options.device} failed`, tostring(result))
		return nil
	end
	return result
end

local LONG = string.rep(
	"Your lap will not count, and your place in the grid goes to the next driver. You can rejoin from the lobby at any time. ",
	25
)

local function longContent(UI: any, Host: any, width: number?): any
	return Host.Frame "Words" {
		BackgroundTransparency = 1,
		Size = if width then UDim2.fromOffset(width, 0) else UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }),
		UI.Label({
			Name = "Copy",
			LayoutOrder = 1,
			text = LONG,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}),
		Host.Frame "Spacer" {
			LayoutOrder = 2,
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 900),
		},
	}
end

local function copyFits(t: any, where: string, root: any)
	local copy = root and root:FindFirstChild("Copy", true)
	t.check(
		where .. " the long wrapped copy grows to its text and is not cut",
		copy ~= nil and copy.TextFits and copy.AbsoluteSize.Y >= copy.TextBounds.Y - 1,
		copy and { copy.TextBounds, copy.AbsoluteSize, copy.TextFits }
	)
end

local function longDialog(UI: any, Host: any, Compose: any, opened: any?): any
	return Host.Frame "Board" {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		UI.Dialog "Long" {
			isPresented = opened or Compose.cell(true),
			onPresentedChange = function() end,
			title = "Leave the race?",
			content = function()
				return longContent(UI, Host)
			end,
			actionLabel = "Leaving now forfeits this heat.",
			actions = {
				{ id = "Stay", label = "Stay", role = "cancel", onActivate = function() end },
				{ id = "Leave", label = "Leave", role = "destructive", onActivate = function() end },
			},
		},
	}
end

add("callout-tour-rich-parts", { "post-overlays-104" }, function(t)
	local stage, built = scenario(t, "overlays", Vector2.new(1280, 720))
	built.steps.tour()
	t.settle(30)
	local panel = visibleNamed(t, stage, "CalloutPanel")
	t.check("the tour coach mark shows", panel ~= nil)
	if not panel then
		return
	end
	t.stable(panel)
	t.inside("the coach mark sits inside the screen", panel, stage, 1)
	local title = t.find(panel, "Title")
	t.check(
		"the title reads Welcome to the garage",
		title and title.ContentText == "Welcome to the garage",
		title and title.ContentText
	)
	t.check("the title fits", title ~= nil and t.fits(title), title and { title.TextBounds, title.AbsoluteSize })
	local media = t.find(panel, "Media")
	t.check("the media shows", media ~= nil and t.visible(media))
	if media then
		local size = media.AbsoluteSize
		t.check("the media has a height", size.Y > 1, size)
		t.near("the media is 2:1", size.X / math.max(1, size.Y), 2, 0.05)
		t.inside("the media inside the coach mark", media, panel, 1)
	end
	local steps = t.find(panel, "Steps")
	t.check("the steps read 1 of 3", steps and steps.ContentText == "1 of 3", steps and steps.ContentText)
	local later, go = t.find(panel, "Later"), t.find(panel, "Go")
	t.check("both actions show", later ~= nil and go ~= nil and t.visible(later) and t.visible(go))
	if later and go then
		t.near("the two actions share one row", later.AbsolutePosition.Y, go.AbsolutePosition.Y, 1)
		t.check("Later sits before Go", later.AbsolutePosition.X < go.AbsolutePosition.X, { t.rect(later), t.rect(go) })
		t.inside("Later inside the coach mark", later, panel, 1)
		t.inside("Go inside the coach mark", go, panel, 1)
		t.check("the Later label fits", t.fits(later), later.TextBounds)
		t.check("the Go label fits", t.fits(go), go.TextBounds)
	end
	t.check("the actions replace the bottom dismiss", t.find(panel, "Dismiss") == nil)
	local close = t.find(panel, "Close")
	t.check("the close control shows", close ~= nil and t.visible(close))
	if close then
		t.check(
			"the close control is at least 44 pixels",
			close.AbsoluteSize.X >= 43.5 and close.AbsoluteSize.Y >= 43.5,
			close.AbsoluteSize
		)
	end
end)

interactive(
	"dialog-body-pad-scrolls-then-moves",
	{ "post-overlays-018" },
	"afterDown: press Down once (arrow keys drive the same native selection as the D-pad); afterDownMany: press Down 15 more times",
	function(t)
		local value = { visits = {} }
		device(t, { device = "xbox" })
		local stage = t.mount(function(UI, Host, Compose)
			return longDialog(UI, Host, Compose)
		end, { frames = 30 })
		local gui = layerOf(stage)
		local modal = visibleNamed(t, gui, "DialogModal")
		value.body = modal and t.find(modal, "Body")
		t.check("the dialog body shows", value.body ~= nil)
		if not value.body then
			return value
		end
		t.stable(value.body)
		local body = value.body
		t.check("the overflowing body is a selection stop", body.Selectable == true, body.Selectable)
		t.check(
			"the body overflows its window",
			body.AbsoluteCanvasSize.Y > body.AbsoluteWindowSize.Y + 1,
			{ body.AbsoluteCanvasSize, body.AbsoluteWindowSize }
		)
		GuiService.SelectedObject = body
		t.settle(4)
		t.check("the selection lands on the body", GuiService.SelectedObject == body, selectedName())
		value.connection = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
			table.insert(value.visits, {
				name = selectedName(),
				canvas = body.CanvasPosition.Y,
				limit = body.AbsoluteCanvasSize.Y - body.AbsoluteWindowSize.Y,
			})
		end)
		t.note("canvas limit", body.AbsoluteCanvasSize.Y - body.AbsoluteWindowSize.Y)
		return value
	end,
	{
		afterDown = function(t, value)
			local body = value.body
			t.check("Down keeps the selection on the body", GuiService.SelectedObject == body, selectedName())
			t.check("Down scrolls the body", body and body.CanvasPosition.Y > 0.5, body and body.CanvasPosition)
		end,
		afterDownMany = function(t, value)
			if value.connection then
				value.connection:Disconnect()
			end
			local body = value.body
			local selected = GuiService.SelectedObject
			t.note("selection visits", value.visits)
			t.check(
				"the selection moves on to an action",
				selected ~= nil and (selected.Name == "Stay" or selected.Name == "Leave"),
				selectedName()
			)
			local left = value.visits[1]
			t.check(
				"the body was scrolled to its end when the selection left it",
				left ~= nil and left.canvas >= left.limit - 1,
				left
			)
			t.check(
				"the body stays at its end",
				body and body.CanvasPosition.Y >= body.AbsoluteCanvasSize.Y - body.AbsoluteWindowSize.Y - 1,
				body and body.CanvasPosition
			)
			GuiService.SelectedObject = nil
		end,
	}
)

add("dialog-room-desktop-short-phone", { "post-overlays-011", "post-overlays-012", "post-overlays-013" }, function(t)
	local viewport = device(t, { device = "xbox", width = 1280, height = 720 })
	t.note("desktop viewport", viewport)
	local stage = t.mount(function(UI, Host, Compose)
		return longDialog(UI, Host, Compose)
	end, { frames = 30 })
	local gui = layerOf(stage)
	local layer = t.rect(gui)
	local modal = visibleNamed(t, gui, "DialogModal")
	local panel = modal and t.find(modal, "Panel")
	t.check("desktop: the dialog shows", panel ~= nil)
	if panel then
		t.stable(panel)
		t.inside("desktop: the dialog inside the window", panel, layer, 1)
		local room, body = t.find(panel, "Room"), t.find(panel, "Body")
		t.check(
			"desktop: the room is pinned, not one scroller",
			room and room.ScrollingEnabled == false,
			room and room.ScrollingEnabled
		)
		t.check(
			"desktop: the body scrolls",
			body and body.ScrollingEnabled == true and body.AbsoluteCanvasSize.Y > body.AbsoluteWindowSize.Y + 1,
			body and { body.AbsoluteCanvasSize, body.AbsoluteWindowSize }
		)
		copyFits(t, "desktop:", body)
		for _, name in { "Header", "ActionLabel", "Actions" } do
			local node = t.find(panel, name)
			t.check(`desktop: {name} shows in full`, node ~= nil and whole(t, node), node and t.rect(node))
			if node then
				t.inside(`desktop: {name} inside the window`, node, layer, 1)
			end
		end
	end
	t.cleanup()
	local short = device(t, { device = "xbox", width = 320, height = 220 })
	t.note("short viewport", short)
	t.note("short window", "320x220 asked so the layer under the 87 px inset keeps a room taller than one 44 px action")
	t.check("the short window applied", short ~= nil and short.Y <= 260, short)
	stage = t.mount(function(UI, Host, Compose)
		return longDialog(UI, Host, Compose)
	end, { frames = 30 })
	gui = layerOf(stage)
	layer = t.rect(gui)
	t.note("short layer", { layer.w, layer.h })
	modal = visibleNamed(t, gui, "DialogModal")
	panel = modal and t.find(modal, "Panel")
	t.check("short: the dialog shows", panel ~= nil)
	if panel then
		t.stable(panel)
		local room, body = t.find(panel, "Room"), t.find(panel, "Body")
		t.check(
			"short: every region moves into one scrolling room",
			room and room.ScrollingEnabled == true,
			room and room.ScrollingEnabled
		)
		t.check(
			"short: the body no longer scrolls on its own",
			body and body.ScrollingEnabled == false,
			body and body.ScrollingEnabled
		)
		t.inside("short: the dialog inside the window", panel, layer, 1)
		if room then
			room.CanvasPosition = Vector2.new(0, math.max(0, room.AbsoluteCanvasSize.Y - room.AbsoluteWindowSize.Y))
			t.settle(6)
			local last
			for _, name in { "Stay", "Leave" } do
				local action = t.find(room, name)
				if action and (last == nil or action.AbsolutePosition.Y > last.AbsolutePosition.Y) then
					last = action
				end
			end
			t.note("short room window", room.AbsoluteWindowSize)
			t.check(
				"short: the last action is reachable at the end of the room",
				last ~= nil and whole(t, last),
				last and { last.Name, t.rect(last), t.clipped(last) }
			)
		end
	end
	t.cleanup()
	local phone = device(t, { device = "iphone_14", orientation = Enum.ScreenOrientation.Portrait })
	t.note("phone viewport", phone)
	local built
	stage, built = scenario(t, "overlays", nil)
	built.steps.openDialog()
	t.settle(30)
	gui = layerOf(stage)
	layer = t.rect(gui)
	modal = visibleNamed(t, gui, "DialogModal")
	panel = modal and t.find(modal, "Panel")
	t.check("phone: the dialog shows", panel ~= nil)
	if panel then
		t.stable(panel)
		t.inside("phone: the dialog inside the window", panel, layer, 1)
		local room, body = t.find(panel, "Room"), t.find(panel, "Body")
		local content = body and body:FindFirstChild("Content")
		t.check(
			"phone: the room is not a scroller",
			room and room.ScrollingEnabled == false,
			room and room.ScrollingEnabled
		)
		if body and content then
			t.near("phone: the body hugs its short copy", body.AbsoluteSize.Y, content.AbsoluteSize.Y, 1.5)
		end
		t.check(
			"phone: the dialog hugs its content",
			panel.AbsoluteSize.Y < layer.h - 64,
			{ panel.AbsoluteSize, layer.h }
		)
		local stay, leave = t.find(panel, "Stay"), t.find(panel, "Leave")
		t.check("phone: both actions show", stay ~= nil and leave ~= nil)
		if stay and leave then
			t.near("phone: two actions that fit share one row", stay.AbsolutePosition.Y, leave.AbsolutePosition.Y, 1)
		end
	end
end)

add("help-plate-edges-and-shrinking-window", { "post-overlays-113", "post-overlays-119" }, function(t)
	local size = t.Facet.Compose.cell(Vector2.new(1280, 720))
	local buttons = {}
	local function spot(UI: any, Host: any, name: string, position: UDim2, anchor: Vector2, help: any): any
		local button = UI.Button(name)({ label = name, help = help })
		buttons[name] = button
		return Host.Frame({
			Name = name .. "Spot",
			BackgroundTransparency = 1,
			AnchorPoint = anchor,
			Position = position,
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			button,
		})
	end
	local function help(edge: string?, align: string?): any
		return {
			title = "Boost",
			body = "Fills the boost meter faster on clean exits.",
			shortcut = { { "Shift", "B" } },
			edge = edge,
			align = align,
		}
	end
	local stage = t.mount(function(UI, Host)
		return Host.Frame "Board" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			spot(UI, Host, "Below", UDim2.fromOffset(200, 200), Vector2.zero, help("bottom")),
			spot(UI, Host, "Beside", UDim2.fromOffset(600, 200), Vector2.zero, help("trailing", "start")),
			spot(UI, Host, "Corner", UDim2.new(1, -4, 1, -4), Vector2.one, help("trailing")),
		}
	end, { size = size, frames = 20 })
	t.note("not checked", "hover with a mouse; the plate is armed through gamepad selection, the same armed path")
	local function plateFor(name: string): any
		GuiService.SelectedObject = buttons[name]
		t.settle(50)
		local plate = visibleNamed(t, stage, "Help")
		if plate then
			t.stable(plate)
		end
		return plate
	end
	local plate = plateFor("Below")
	t.check("Below: the help plate shows", plate ~= nil)
	if plate then
		local title, text, shortcut =
			t.find(plate, "HelpTitle"), t.find(plate, "HelpText"), t.find(plate, "HelpShortcut")
		t.check(
			"the plate shows the title",
			title and title.ContentText == "Boost" and t.fits(title),
			title and title.ContentText
		)
		t.check(
			"the plate shows the body",
			text and t.visible(text) and t.fits(text),
			text and { text.TextBounds, text.AbsoluteSize }
		)
		t.check(
			"the plate shows the shortcut",
			shortcut and shortcut.ContentText == "Shift+B" and t.fits(shortcut),
			shortcut and shortcut.ContentText
		)
		local anchor = t.rect(buttons.Below)
		t.check(
			"bottom: the plate sits below the trigger",
			t.rect(plate).y >= anchor.b + 4.5,
			{ t.rect(plate), anchor }
		)
		t.inside("bottom: the plate inside the window", plate, shrink(t.rect(stage), 8, 8, 8, 8), 1)
	end
	plate = plateFor("Beside")
	t.check("Beside: the help plate shows", plate ~= nil)
	if plate then
		local anchor = t.rect(buttons.Beside)
		local p = t.rect(plate)
		t.check("trailing: the plate sits after the trigger", p.x >= anchor.r + 4.5, { p, anchor })
		t.near("trailing start: the plate top meets the trigger top", p.y, anchor.y, 1)
		size:set(Vector2.new(720, 400))
		t.settle(10)
		t.stable(plate)
		local now = visibleNamed(t, stage, "Help")
		t.check("the plate stays live while the window shrinks", now ~= nil)
		if now then
			t.inside("a shrunken window keeps the plate inside its safe box", now, shrink(t.rect(stage), 8, 8, 8, 8), 1)
			t.check(
				"the plate does not cover its trigger",
				not overlap(t.rect(now), t.rect(buttons.Beside)),
				{ t.rect(now), t.rect(buttons.Beside) }
			)
		end
		size:set(Vector2.new(1280, 720))
		t.settle(10)
	end
	plate = plateFor("Corner")
	t.check("Corner: the help plate shows", plate ~= nil)
	if plate then
		t.inside("corner: the plate stays inside the window", plate, shrink(t.rect(stage), 8, 8, 8, 8), 1)
		size:set(Vector2.new(500, 300))
		t.settle(10)
		local now = visibleNamed(t, stage, "Help")
		if now then
			t.stable(now)
			t.inside("corner: the smaller window keeps the plate inside", now, shrink(t.rect(stage), 8, 8, 8, 8), 1)
		end
	end
	GuiService.SelectedObject = nil
end)

add("navbar-search-wraps-filter", { "post-overlays-093" }, function(t)
	local size = t.Facet.Compose.cell(Vector2.new(1280, 720))
	local stage = scenario(t, "overlays", size)
	local header = visibleNamed(t, stage, "Header")
	t.check("the search bar shows", header ~= nil)
	if not header then
		return
	end
	local primary, trailing = t.find(header, "Primary"), t.find(header, "Trailing")
	local filter = t.find(header, "Filter")
	local input = header:FindFirstChildWhichIsA("TextBox", true)
	t.check("the bar parts are found", primary ~= nil and trailing ~= nil and filter ~= nil and input ~= nil)
	if not (primary and trailing and filter and input) then
		return
	end
	local function beside(): boolean
		local a, b = t.rect(primary), t.rect(trailing)
		return b.x >= a.r - 0.5 and b.y < a.b - 0.5
	end
	t.check("wide: Filter sits on the first row", beside(), { t.rect(primary), t.rect(trailing) })
	input.Text = "Coastal"
	input:CaptureFocus()
	t.settle(6)
	t.check("the search field takes focus", input:IsFocused())
	size:set(Vector2.new(390, 720))
	t.settle(10)
	t.stable(header)
	t.check(
		"narrow: Filter moves to a second row",
		trailing.AbsolutePosition.Y >= t.rect(primary).b - 0.5,
		{ t.rect(primary), t.rect(trailing) }
	)
	t.inside("narrow: Filter inside the window", filter, stage, 1)
	t.check("narrow: the search field is the same instance", input.Parent ~= nil and input:IsDescendantOf(header))
	t.check("narrow: the search text stays", input.Text == "Coastal", input.Text)
	t.check("narrow: the search field keeps focus", input:IsFocused())
	size:set(Vector2.new(1280, 720))
	t.settle(10)
	t.stable(header)
	t.check("wide again: Filter returns to the first row", beside(), { t.rect(primary), t.rect(trailing) })
	t.check("wide again: the search text stays", input.Text == "Coastal", input.Text)
	input:ReleaseFocus()
end)

add("notice-affixed-banner-moves-content", { "post-overlays-090" }, function(t)
	local stage, built = scenario(t, "status_family", Vector2.new(1280, 720))
	local family = t.find(stage, "StatusFamily")
	local content = family and family:FindFirstChild("Content")
	t.check("the Status page is found", content ~= nil)
	if not (family and content) then
		return
	end
	t.stable(content)
	local before = content.AbsolutePosition.Y
	built.notices.banner:set(true)
	t.settle(10)
	local waited = t.stable(content, 6, 120)
	t.check("the page settles with the banner pinned", waited < 120, waited)
	local banner = visibleNamed(t, stage, "Offline")
	t.check("the offline banner shows", banner ~= nil)
	if not banner then
		return
	end
	local layer = family:FindFirstAncestorWhichIsA("LayerCollector")
	local padding = family:FindFirstChildWhichIsA("UIPadding")
	t.note("reservation", {
		layer = layer and { layer:GetFullName(), layer.AbsolutePosition.Y, layer:GetAttribute("FacetInsetTop") },
		family = family.AbsolutePosition.Y,
		banner = { banner.AbsolutePosition.Y, banner.AbsoluteSize.Y, banner:GetFullName() },
		padding = padding and padding.PaddingTop.Offset,
	})
	local top = t.rect(family).y
	local b = t.rect(banner)
	t.check("the banner sits at the top of the Status page", b.y >= top - 0.5 and b.y <= top + 17, { b, top })
	t.near("the content moves down by the banner height", content.AbsolutePosition.Y - before, b.h, 2)
	t.check(
		"the content starts below the banner",
		content.AbsolutePosition.Y >= b.b - 0.5,
		{ content.AbsolutePosition, b }
	)
	built.notices.banner:set(false)
	t.settle(10)
	t.stable(content, 6, 120)
	t.near("the content moves back when the banner closes", content.AbsolutePosition.Y, before, 1)
end)

add("notice-layout-and-emphasis-paint", { "post-overlays-082", "post-overlays-083" }, function(t)
	local colors = {}
	for _, entry in { { "desktop", Vector2.new(1280, 720), "beside" }, { "phone", Vector2.new(390, 844), "below" } } do
		local where, size, expected = entry[1] :: any, entry[2] :: any, entry[3] :: any
		local stage = scenario(t, "notice", size)
		local update = visibleNamed(t, stage, "Update")
		t.check(where .. " the Update notice shows", update ~= nil)
		if update then
			t.stable(update)
			t.check(
				`{where} places the link and actions {expected} the copy`,
				update:GetAttribute("NoticeAccessories") == expected,
				update:GetAttribute("NoticeAccessories")
			)
			local copy, accessories = t.find(update, "Copy"), t.find(update, "Accessories")
			if copy and accessories then
				local c, a = t.rect(copy), t.rect(accessories)
				if expected == "beside" then
					t.check(where .. " accessories sit to the right of the copy", a.x >= c.r - 0.5, { c, a })
				else
					t.check(where .. " accessories sit below the copy", a.y >= c.b - 0.5, { c, a })
				end
			end
			local found = t.offenders(update, stage)
			t.check(where .. " the Update notice inside the screen", #found.lateral == 0, found.lateral)
			t.check(where .. " no Update text is clipped", #found.clipped == 0, found.clipped)
			local fill = styled(update, "BackgroundColor3")
			for _, name in { "Link", "Install" } do
				local button = t.find(update, name)
				if button then
					local own = styled(button, "BackgroundTransparency")
					local behind = if own < 0.5 then styled(button, "BackgroundColor3") else fill
					local ratio = contrast(styled(button, "TextColor3"), behind)
					t.note(`{where} {name} plate`, { transparency = own, tags = button:GetTags() })
					t.check(`{where} the {name} label is readable on the emphasis fill`, ratio >= 4.5, ratio)
				else
					t.check(`{where} {name} found`, false)
				end
			end
		end
		for _, severity in { "info", "success", "warning", "error" } do
			local notice = visibleNamed(t, stage, "Severity-" .. severity)
			local message = notice and t.find(notice, "Message")
			if notice and message then
				local fill = styled(notice, "BackgroundColor3")
				colors[severity] = fill
				local ratio = contrast(styled(message, "TextColor3"), fill)
				t.check(`{where} {severity} emphasis text is readable`, ratio >= 4.5, ratio)
				t.check(
					`{where} {severity} emphasis fill is opaque`,
					styled(notice, "BackgroundTransparency") < 0.5,
					styled(notice, "BackgroundTransparency")
				)
			else
				t.check(`{where} {severity} notice found`, false)
			end
		end
		t.cleanup()
	end
	local distinct = {}
	for _, color in colors do
		distinct[color:ToHex()] = true
	end
	local count = 0
	for _ in distinct do
		count += 1
	end
	t.check("each severity paints its own color", count == 4, colors)
	local stage = t.mount(function(UI)
		return UI.Notice "Plain" {
			severity = "info",
			message = "A new track pack is ready to install.",
			link = { label = "Release notes", onActivate = function() end },
		}
	end, { size = Vector2.new(1280, 720), frames = 12 })
	local link = t.find(stage, "Link")
	t.check(
		"the standard link wears no plate",
		link ~= nil and styled(link, "BackgroundTransparency") >= 0.99,
		link and styled(link, "BackgroundTransparency")
	)
end)

add("popover-caps-and-side-hang", { "post-overlays-033", "post-overlays-166" }, function(t)
	local viewport = device(t, { device = "xbox", width = 1280, height = 720 })
	t.note("viewport", viewport)
	local cells, triggers = {}, {}
	local function pop(
		UI: any,
		Host: any,
		Compose: any,
		name: string,
		anchor: Vector2,
		position: UDim2,
		size: UDim2?,
		long: boolean
	): any
		local opened = Compose.cell(false)
		cells[name] = opened
		local trigger = UI.Button(name .. "Button")({
			label = name,
			Size = if size then UDim2.fromScale(1, 1) else nil,
			AutomaticSize = if size then Enum.AutomaticSize.None else nil,
		})
		triggers[name] = trigger
		return Host.Frame({
			Name = name .. "Spot",
			BackgroundTransparency = 1,
			AnchorPoint = anchor,
			Position = position,
			Size = size or UDim2.fromOffset(0, 0),
			AutomaticSize = if size then Enum.AutomaticSize.None else Enum.AutomaticSize.XY,
			UI.Popover(name)({
				isPresented = opened,
				onPresentedChange = function(nextValue: boolean)
					opened:set(nextValue)
				end,
				trigger = trigger,
				maxWidth = if long then 320 else nil,
				maxHeight = if long then 180 else nil,
				content = function()
					if long then
						return longContent(UI, Host, 296)
					end
					return UI.Label({
						Name = "Words",
						text = "Short note",
						AutomaticSize = Enum.AutomaticSize.XY,
						Size = UDim2.fromOffset(0, 0),
					})
				end,
			}),
		})
	end
	local stage = t.mount(function(UI, Host, Compose)
		return Host.Frame "Board" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			pop(UI, Host, Compose, "TopLeft", Vector2.zero, UDim2.fromOffset(8, 8), nil, true),
			pop(UI, Host, Compose, "TopRight", Vector2.new(1, 0), UDim2.new(1, -8, 0, 8), nil, true),
			pop(UI, Host, Compose, "BottomLeft", Vector2.new(0, 1), UDim2.new(0, 8, 1, -8), nil, true),
			pop(UI, Host, Compose, "BottomRight", Vector2.one, UDim2.new(1, -8, 1, -8), nil, true),
			pop(
				UI,
				Host,
				Compose,
				"Tall",
				Vector2.new(0.5, 0.5),
				UDim2.fromScale(0.5, 0.5),
				UDim2.new(0, 160, 1, -200),
				true
			),
			pop(UI, Host, Compose, "Plain", Vector2.new(0, 0.5), UDim2.new(0, 300, 0.5, 0), nil, false),
		}
	end, { frames = 20 })
	local gui = layerOf(stage)
	local safe = shrink(t.rect(gui), 8, 8, 8, 8)
	for _, name in { "TopLeft", "TopRight", "BottomLeft", "BottomRight", "Tall", "Plain" } do
		cells[name]:set(true)
		t.settle(20)
		local modal = gui:FindFirstChild(name .. "Modal", true)
		local panel = modal and modal:FindFirstChild("Panel", true)
		t.check(name .. " popover shows", panel ~= nil)
		if panel then
			t.stable(panel)
			local body = panel:FindFirstChild("Body")
			local p = t.rect(panel)
			t.inside(name .. " panel inside the safe box", p, safe, 1)
			if name == "Plain" then
				local words = body and body:FindFirstChild("Words", true)
				if words then
					local extra = p.w - (words.AbsoluteSize.X + 16)
					t.check(
						"absent caps keep the plain hug: width, allowing the 4 px scroll bar gutter",
						extra >= -1.5 and extra <= 5.5,
						{ panel = p.w, words = words.AbsoluteSize.X }
					)
					t.near("absent caps keep the plain hug: height", p.h, words.AbsoluteSize.Y + 16, 1.5)
				end
				t.check(
					"the plain body does not scroll",
					body and body.AbsoluteCanvasSize.Y <= body.AbsoluteWindowSize.Y + 1,
					body and { body.AbsoluteCanvasSize, body.AbsoluteWindowSize }
				)
			else
				t.check(name .. " panel width within maxWidth 320 with its chrome", p.w <= 320.5, p.w)
				t.check(name .. " panel height within maxHeight 180 with its chrome", p.h <= 180.5, p.h)
				t.check(
					name .. " body scrolls",
					body and body.ScrollingEnabled and body.AbsoluteCanvasSize.Y > body.AbsoluteWindowSize.Y + 1,
					body and { body.AbsoluteCanvasSize, body.AbsoluteWindowSize }
				)
				copyFits(t, name, body)
				t.check(
					name .. " panel does not cover its trigger",
					not overlap(p, t.rect(triggers[name])),
					{ p, t.rect(triggers[name]) }
				)
			end
			if name == "Tall" then
				local a = t.rect(triggers.Tall)
				t.check(
					"a panel that fits neither above nor below hangs beside the trigger",
					p.x >= a.r - 0.5 or p.r <= a.x + 0.5,
					{ p, a }
				)
			end
		end
		cells[name]:set(false)
		t.settle(12)
	end
end)

add(
	"popover-compact-sheet-then-anchored",
	{ "post-overlays-035", "post-overlays-038", "post-overlays-039" },
	function(t)
		t.note(
			"not checked",
			"the refused drag on the compact sheet (no drag input); the input switch is driven by moving from a touch phone to a desktop gamepad device, which changes the layer width as well as the input class"
		)
		local phone = device(t, { device = "iphone_14", orientation = Enum.ScreenOrientation.Portrait })
		t.note("phone viewport", phone)
		t.note("phone preferred input", tostring(UserInputService.PreferredInput))
		local stage, built = scenario(t, "overlays", nil)
		local gui = layerOf(stage)
		built.steps.openAbout()
		t.settle(30)
		local function route(): (string?, any)
			for _, node in gui:GetDescendants() do
				local value = node:GetAttribute("FacetRoute")
				if value then
					return value, node
				end
			end
			return nil, nil
		end
		local kind = route()
		t.check("a touch phone presents the popover as a sheet", kind == "sheet", kind)
		local status = built.report().status
		local desk = device(t, { device = "xbox", width = 1280, height = 720 })
		t.note("desktop viewport", desk)
		t.note("desktop preferred input", tostring(UserInputService.PreferredInput))
		t.settle(20)
		local now, modal = route()
		t.check("the desktop switches it to the anchored panel", now == "popover", now)
		t.check("the popover stays presented across the switch", built.report().about == true, built.report())
		t.check("the switch is silent", built.report().status == status, built.report().status)
		if modal then
			local panel = modal:FindFirstChild("Panel", true)
			t.check("the anchored panel shows", panel ~= nil and t.visible(panel))
			t.check("the anchored panel has no close", visibleNamed(t, modal, "Close") == nil)
			local words = visibleNamed(t, modal, "Body")
			t.check("the content moved to the anchored panel", words ~= nil)
		end
	end
)

add(
	"sheet-scroll-policy-and-detectors",
	{ "post-overlays-128", "post-overlays-129", "post-overlays-131", "post-overlays-134", "post-overlays-137" },
	function(t)
		t.note(
			"not checked",
			"flick projection, settle speed, drag slop, input-class cancel and the downward pull at the tallest detent all need a drag or touch, which the runner cannot send"
		)
		local detent
		local stage = t.mount(function(UI, Host, Compose)
			detent = Compose.cell("medium")
			return Host.Frame "Board" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				UI.Sheet "Rules" {
					title = "Race rules",
					isPresented = Compose.cell(true),
					detent = detent,
					detents = { "medium", "large" },
					scrollPolicy = "atLargestDetent",
					content = function()
						return longContent(UI, Host)
					end,
				},
			}
		end, { size = Vector2.new(1280, 720), frames = 30 })
		local panel = visibleNamed(t, stage, "SheetPanel")
		t.check("the sheet shows", panel ~= nil)
		if not panel then
			return
		end
		t.stable(panel)
		local detectors = {}
		for _, node in panel:GetDescendants() do
			if node:IsA("UIDragDetector") then
				table.insert(detectors, node.Name)
			end
		end
		t.note("drag detectors", detectors)
		t.check("the panel carries native drag detectors", #detectors >= 1, detectors)
		local body = t.find(panel, "SheetContent")
		t.check(
			"below the tallest detent the body does not scroll",
			body and body.ScrollingEnabled == false,
			body and body.ScrollingEnabled
		)
		detent:set("large")
		t.settle(20)
		t.stable(panel)
		t.check(
			"at the tallest detent the body scrolls",
			body and body.ScrollingEnabled == true,
			body and body.ScrollingEnabled
		)
		t.check(
			"the body overflows at the tallest detent",
			body and body.AbsoluteCanvasSize.Y > body.AbsoluteWindowSize.Y + 1,
			body and { body.AbsoluteCanvasSize, body.AbsoluteWindowSize }
		)
		copyFits(t, "at the tallest detent", body)
	end
)

add(
	"sheet-room-hug-hero-short",
	{ "post-overlays-144", "post-overlays-146", "post-overlays-148", "post-overlays-150" },
	function(t)
		t.note("not checked", "the on-screen keyboard lift (the runner has no on-screen keyboard)")
		for _, entry in { { "desktop", Vector2.new(1280, 720) }, { "phone", Vector2.new(390, 844) } } do
			local where, size = entry[1] :: any, entry[2] :: any
			local stage, built = scenario(t, "sheet", size)
			built.steps.lobby()
			t.settle(30)
			local panel = visibleNamed(t, stage, "SheetPanel")
			t.check(where .. " the lobby sheet shows", panel ~= nil)
			if panel then
				t.stable(panel)
				t.inside(where .. " the sheet inside the screen", panel, stage, 1)
				local room, body = t.find(panel, "Room"), t.find(panel, "SheetContent")
				t.check(
					where .. " the hug sheet keeps its regions pinned",
					room and room.ScrollingEnabled == false,
					room and room.ScrollingEnabled
				)
				t.check(
					where .. " the hug sheet fits its whole body",
					body and body.AbsoluteCanvasSize.Y <= body.AbsoluteWindowSize.Y + 1,
					body and { body.AbsoluteCanvasSize, body.AbsoluteWindowSize }
				)
				local text = t.find(panel, "LobbyBody")
				t.check(
					where .. " the lobby text shows in full",
					text ~= nil and whole(t, text) and t.fits(text),
					text and { t.rect(text), text.TextBounds }
				)
				t.check(
					where .. " the hug sheet is shorter than the large detent",
					panel.AbsoluteSize.Y < size.Y * 0.95 - 1,
					panel.AbsoluteSize
				)
				local strip, banner, utilities =
					t.find(panel, "Strip"), t.find(panel, "Banner"), t.find(panel, "Utilities")
				t.check(
					where .. " the content hero has its close strip",
					strip ~= nil and strip.AbsoluteSize.Y >= 43.5,
					strip and strip.AbsoluteSize
				)
				if strip and banner then
					t.check(
						where .. " the hero content starts below the strip",
						banner.AbsolutePosition.Y >= t.rect(strip).b - 0.5,
						{ t.rect(strip), t.rect(banner) }
					)
				end
				if utilities and banner then
					t.check(
						where .. " the close does not cover the hero content",
						not overlap(t.rect(utilities), t.rect(banner)),
						{ t.rect(utilities), t.rect(banner) }
					)
				end
				for _, name in { "NotNow", "Join" } do
					local action = t.find(panel, name)
					t.check(
						`{where} {name} shows in full`,
						action ~= nil and whole(t, action),
						action and t.rect(action)
					)
				end
			end
			t.cleanup()
		end
		local stage, built = scenario(t, "sheet", Vector2.new(640, 120))
		built.steps.lobby()
		t.settle(30)
		local panel = visibleNamed(t, stage, "SheetPanel")
		t.check("short: the lobby sheet shows", panel ~= nil)
		if panel then
			t.stable(panel)
			local room, body = t.find(panel, "Room"), t.find(panel, "SheetContent")
			t.check(
				"short: the regions unpin into one scroller",
				room and room.ScrollingEnabled == true,
				room and room.ScrollingEnabled
			)
			t.check(
				"short: the body no longer scrolls on its own",
				body and body.ScrollingEnabled == false,
				body and body.ScrollingEnabled
			)
			t.inside("short: the sheet inside the screen", panel, stage, 1)
			if room then
				room.CanvasPosition = Vector2.new(0, math.max(0, room.AbsoluteCanvasSize.Y - room.AbsoluteWindowSize.Y))
				t.settle(6)
				local join = t.find(room, "Join")
				t.check(
					"short: the last action is reachable at the end of the room",
					join ~= nil and whole(t, join),
					join and { t.rect(join), t.clipped(join) }
				)
			end
		end
	end
)

local function themeNamed(t: any, key: string): any
	for _, entry in t.themes do
		local name = string.lower((string.gsub(entry.name, "[%s_]", "")))
		if name == key then
			return entry
		end
	end
	return nil
end

add("snackbar-art-carve", { "post-overlays-070" }, function(t)
	for _, key in { "pixelquest", "fantasyornate" } do
		local theme = themeNamed(t, key)
		if not theme then
			t.note(key, "theme not installed; skipped")
			continue
		end
		local stage = t.mount(function(UI, Host, Compose)
			local shown = Compose.cell(true)
			return Host.Frame "Board" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				UI.Snackbar "Everything" {
					isPresented = shown,
					message = "Offline: your times will upload when you reconnect.",
					icon = "status.warning",
					action = { label = "Undo", onActivate = function() end },
					onPresentedChange = function(nextValue: boolean)
						shown:set(nextValue)
					end,
				},
			}
		end, { theme = theme.package, frames = 20 })
		local gui = layerOf(stage)
		local row = visibleNamed(t, gui, "Snack")
		t.check(theme.name .. " the snackbar shows", row ~= nil)
		if row then
			t.stable(row)
			local chrome = theme.package.chrome
			local insets = chrome and chrome.panel and chrome.panel.contentInsets or {}
			t.note(theme.name .. " panel insets", insets)
			local padding = row:FindFirstChildWhichIsA("UIPadding")
			local left = math.max(8, insets.left or 0)
			local right = math.max(8, insets.right or 0)
			local top = math.max(8, insets.top or 0)
			local bottom = math.max(8, insets.bottom or 0)
			t.check(
				theme.name .. " the row pads by the frame carve",
				padding ~= nil
					and padding.PaddingLeft.Offset == left
					and padding.PaddingRight.Offset == right
					and padding.PaddingTop.Offset == top
					and padding.PaddingBottom.Offset == bottom,
				padding and { padding.PaddingLeft, padding.PaddingRight, padding.PaddingTop, padding.PaddingBottom }
			)
			local inner = shrink(t.rect(row), left, top, right, bottom)
			for _, name in { "Icon", "Message", "Action", "Close" } do
				local node = t.find(row, name)
				t.check(`{theme.name} {name} shows`, node ~= nil and t.visible(node))
				if node then
					t.inside(`{theme.name} {name} inside the frame art`, node, inner, 1)
				end
			end
			local message = t.find(row, "Message")
			t.check(
				theme.name .. " the message fits",
				message ~= nil and t.fits(message),
				message and { message.TextBounds, message.AbsoluteSize }
			)
			t.inside(theme.name .. " the row inside the window", row, t.rect(gui), 1)
		end
		t.cleanup()
	end
end)

add("snackbar-paint-order", { "post-overlays-071" }, function(t)
	local calloutOn, dialogOn
	local trigger
	local stage = t.mount(function(UI, Host, Compose)
		calloutOn, dialogOn = Compose.cell(false), Compose.cell(false)
		trigger = UI.Button "HelpTrigger" {
			label = "Boost",
			help = { title = "Boost", body = "Fills the boost meter faster." },
		}
		local anchor = UI.Button "TourAnchor" { label = "Garage" }
		return Host.Frame "Board" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Host.Frame "Spots" {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -40),
				Size = UDim2.fromOffset(0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				BackgroundTransparency = 1,
				Host.UIListLayout({ FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 24) }),
				trigger,
				anchor,
			},
			UI.Callout {
				anchor = anchor,
				isPresented = calloutOn,
				edge = "bottom",
				title = "Welcome to the garage",
				content = function()
					return UI.Label({ text = "Tune your car here before a race." })
				end,
				onRetire = function() end,
			},
			UI.Snackbar "Snack1" {
				isPresented = Compose.cell(true),
				message = "Kart sold. The garage has room for one more.",
				closeButton = false,
			},
			UI.Dialog "Leave" {
				isPresented = dialogOn,
				closeButton = false,
				title = "Leave the race?",
				content = function()
					return UI.Label({ text = "Your lap will not count." })
				end,
				actions = { { id = "Stay", label = "Stay", role = "cancel", onActivate = function() end } },
			},
		}
	end, { frames = 20 })
	local gui = layerOf(stage)
	t.note("layer z-index behavior", tostring(gui.ZIndexBehavior))
	local row = visibleNamed(t, gui, "Snack")
	t.check("the snackbar row shows", row ~= nil)
	calloutOn:set(true)
	GuiService.SelectedObject = trigger
	t.settle(50)
	local callout = visibleNamed(t, gui, "CalloutPanel")
	local plate = visibleNamed(t, gui, "Help")
	t.check("the callout shows", callout ~= nil)
	t.check("the help plate shows", plate ~= nil)
	if row and callout then
		local above, detail = paintsAbove(callout, row)
		t.check("the callout paints above the snackbar row", above == true, detail)
		t.note("callout overlaps the row", overlap(t.rect(callout), t.rect(row)))
	end
	if row and plate then
		local above, detail = paintsAbove(plate, row)
		t.check("the help plate paints above the snackbar row", above == true, detail)
	end
	dialogOn:set(true)
	t.settle(30)
	local modal = visibleNamed(t, gui, "DialogModal")
	local panel = modal and t.find(modal, "Panel")
	t.check("the dialog shows", panel ~= nil)
	if not panel then
		return
	end
	t.stable(panel)
	if row then
		local above, detail = paintsAbove(panel, row)
		t.check("the dialog paints above the snackbar row", above == true, detail)
	end
	callout = visibleNamed(t, gui, "CalloutPanel")
	plate = visibleNamed(t, gui, "Help")
	t.note("still painted under the dialog", { callout = callout ~= nil, help = plate ~= nil })
	if callout then
		local above, detail = paintsAbove(panel, callout)
		t.check("the dialog paints above the callout", above == true, detail)
	else
		t.check("the callout does not paint over the dialog", true)
	end
	if plate then
		local above, detail = paintsAbove(panel, plate)
		t.check("the dialog paints above the help plate", above == true, detail)
	else
		t.check("the help plate does not paint over the dialog", true)
	end
	GuiService.SelectedObject = nil
end)

add("snackbar-composition-widths", { "post-overlays-048", "post-overlays-049", "post-overlays-050" }, function(t)
	local long =
		"Offline: your lap times will upload when you reconnect to the race servers. Keep driving; nothing is lost."
	for _, entry in
		{
			{ "desktop", { device = "xbox", width = 1280, height = 720 } },
			{ "phone", { device = "iphone_14", orientation = Enum.ScreenOrientation.Portrait } },
		}
	do
		local where = entry[1] :: any
		t.note(where .. " viewport", device(t, entry[2] :: any))
		local cells = {}
		local stage = t.mount(function(UI, Host, Compose)
			local function cell(name: string): any
				local value = Compose.cell(false)
				cells[name] = value
				return value
			end
			local undo = { label = "Undo", onActivate = function() end }
			local close = cell("WithClose")
			return Host.Frame "Board" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				UI.Snackbar "Plain" {
					isPresented = cell("Plain"),
					message = "Saved to your garage.",
					closeButton = false,
				},
				UI.Snackbar "WithAction" {
					isPresented = cell("WithAction"),
					message = "Kart sold.",
					action = undo,
					closeButton = false,
				},
				UI.Snackbar "WithClose" {
					isPresented = close,
					message = "Friend request sent.",
					onPresentedChange = function(nextValue: boolean)
						close:set(nextValue)
					end,
				},
				UI.Snackbar "LongPlain" { isPresented = cell("LongPlain"), message = long, closeButton = false },
				UI.Snackbar "LongAction" {
					isPresented = cell("LongAction"),
					message = long,
					action = undo,
					closeButton = false,
				},
			}
		end, { frames = 12 })
		local gui = layerOf(stage)
		local layer = t.rect(gui)
		local widths = {}
		local function show(name: string): any
			cells[name]:set(true)
			t.settle(14)
			local row = visibleNamed(t, gui, "Snack")
			t.check(`{where} {name} shows`, row ~= nil)
			if row then
				t.stable(row)
				widths[name] = row.AbsoluteSize.X
				t.inside(`{where} {name} inside the window`, row, layer, 1)
			end
			return row
		end
		local function hide(name: string)
			cells[name]:set(false)
			t.settle(10)
		end
		local row = show("Plain")
		if row then
			local message = t.find(row, "Message")
			local padding = row:FindFirstChildWhichIsA("UIPadding")
			local pads = if padding then padding.PaddingLeft.Offset + padding.PaddingRight.Offset else 16
			if message then
				t.near(
					`{where} a message-only row hugs its text`,
					row.AbsoluteSize.X,
					math.ceil(message.TextBounds.X) + pads + 2,
					2
				)
				t.check(
					`{where} the plain message stays on one line`,
					message.TextBounds.Y < styled(message, "TextSize") * 1.6,
					message.TextBounds
				)
			end
		end
		hide("Plain")
		row = show("WithAction")
		if row then
			local message, action = t.find(row, "Message"), t.find(row, "Action")
			if message and action then
				local m, a = t.rect(message), t.rect(action)
				t.check(
					`{where} a short action sits beside the text`,
					a.x >= m.r - 0.5 and a.y < m.b and a.b > m.y,
					{ m, a }
				)
			end
		end
		hide("WithAction")
		show("WithClose")
		hide("WithClose")
		row = show("LongPlain")
		if row then
			local message = t.find(row, "Message")
			t.check(
				`{where} long plain copy wraps`,
				message ~= nil and message.TextBounds.Y > styled(message, "TextSize") * 1.6,
				message and message.TextBounds
			)
		end
		hide("LongPlain")
		row = show("LongAction")
		if row then
			local message, action = t.find(row, "Message"), t.find(row, "Action")
			t.check(
				`{where} long copy wraps`,
				message ~= nil and message.TextBounds.Y > styled(message, "TextSize") * 1.6,
				message and message.TextBounds
			)
			if message and action then
				t.check(
					`{where} the action moves below the long copy`,
					action.AbsolutePosition.Y >= t.rect(message).b - 0.5,
					{ t.rect(message), t.rect(action) }
				)
				t.inside(`{where} the action inside the row`, action, row, 1)
			end
		end
		hide("LongAction")
		t.note(where .. " widths", widths)
		local cap = layer.w - 32
		if widths.WithAction and widths.WithClose then
			t.near(`{where} action and close rows share the constrained width`, widths.WithAction, widths.WithClose, 1)
			t.check(
				`{where} the constrained width stays inside the strip`,
				widths.WithAction <= cap + 0.5,
				{ widths.WithAction, cap }
			)
		end
		if widths.Plain and widths.WithAction then
			t.check(
				`{where} the message-only row is narrower than the constrained row`,
				widths.Plain < widths.WithAction - 1,
				widths
			)
		end
		if widths.LongPlain and widths.WithAction then
			t.near(`{where} a long plain row hugs up to the strip width`, widths.LongPlain, widths.WithAction, 1)
		end
		t.cleanup()
	end
end)

return cases
