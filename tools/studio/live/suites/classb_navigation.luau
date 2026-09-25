--!strict
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local cases = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function interactive(
	id: string,
	contracts: { string },
	setup: (any) -> any,
	steps: { [string]: (any, any) -> () }
)
	table.insert(cases, { id = id, contracts = contracts, setup = setup, steps = steps })
end

local function tagged(root: Instance, tag: string): { any }
	local out = {}
	for _, node in root:GetDescendants() do
		if node:HasTag(tag) then
			table.insert(out, node)
		end
	end
	return out
end

local function sheetRule(stage: Instance, selector: string): { [string]: any }?
	local gui = stage:FindFirstAncestorWhichIsA("ScreenGui")
	local sheet = gui and gui:FindFirstChildWhichIsA("StyleSheet")
	if not sheet then
		return nil
	end
	local found
	for _, node in sheet:GetDescendants() do
		if node:IsA("StyleRule") and node.Selector == selector then
			found = node:GetProperties()
		end
	end
	return found
end

local function shown(node: Instance): boolean
	local at: Instance? = node
	while at and at:IsA("GuiObject") do
		if at:GetStyled("Visible") == false then
			return false
		end
		at = at.Parent
	end
	return true
end

local function themed(t: any, name: string): any
	for _, entry in t.themes do
		if entry.name == name then
			return entry.package
		end
	end
	return nil
end

add("billboard-nameplate", { "mech3-08" }, function(t)
	local Facet = t.Facet
	local Compose = Facet.Compose
	local camera = workspace.CurrentCamera
	local part = Instance.new("Part")
	part.Name = "ClassbNameplateAnchor"
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = camera.CFrame * CFrame.new(0, 0, -12)
	part.Parent = workspace
	local runtime = Facet.Roblox.createRuntime()
	local Host = runtime.constructors
	local UI = Facet.controls(runtime)
	local health = Compose.cell("100")
	local billboard
	local stop = runtime.mount(function()
		local sheet = Facet.themes.createStyleSheet(runtime)
		billboard = Host.BillboardGui "Nameplate" {
			Adornee = part,
			AlwaysOnTop = true,
			Size = UDim2.fromOffset(300, 96),
			ResetOnSpawn = false,
			sheet,
			Host.StyleLink({ StyleSheet = Compose.static(sheet) }),
			UI.VStack "Plate" {
				padding = 8,
				gap = 4,
				width = "fill",
				height = "fill",
				UI.Label "Name" { text = "Razz Raccoon", TextSize = 18 },
				UI.Label "Health" { text = health, TextSize = 14 },
			},
		}
		return billboard
	end, Players.LocalPlayer:WaitForChild("PlayerGui"))
	t.settle(10)
	local plate = billboard:FindFirstChild("Plate")
	local name = plate and plate:FindFirstChild("Name")
	local label = plate and plate:FindFirstChild("Health")
	t.check("the nameplate mounts in a BillboardGui", name ~= nil and label ~= nil)
	if name and label then
		local origin = billboard.AbsolutePosition
		t.near("the billboard canvas is 300 wide", billboard.AbsoluteSize.X, 300, 0.5)
		t.near("the billboard canvas is 96 tall", billboard.AbsoluteSize.Y, 96, 0.5)
		t.near("the name sits 8 px from the leading edge", name.AbsolutePosition.X - origin.X, 8, 0.5)
		t.near("the name sits 8 px from the top edge", name.AbsolutePosition.Y - origin.Y, 8, 0.5)
		t.check(
			"the name fits in 300 - 16 px",
			name.AbsoluteSize.X <= 284.5 and t.fits(name),
			{ name.AbsoluteSize, name.TextBounds }
		)
		t.near(
			"the health line follows 4 px below the name",
			label.AbsolutePosition.Y - (name.AbsolutePosition.Y + name.AbsoluteSize.Y),
			4,
			0.5
		)
		local before = #billboard:GetDescendants()
		local created = 0
		local connection = billboard.DescendantAdded:Connect(function()
			created += 1
		end)
		health:set("87")
		t.settle(4)
		connection:Disconnect()
		t.check("the health update writes the text", label.ContentText == "87", label.ContentText)
		t.check("the same label instance shows the new value", plate:FindFirstChild("Health") == label)
		t.check(
			"the update creates no instance",
			created == 0 and #billboard:GetDescendants() == before,
			{ created, before, #billboard:GetDescendants() }
		)
		t.near(
			"the name keeps its place after the update",
			name.AbsolutePosition.X - billboard.AbsolutePosition.X,
			8,
			0.5
		)
	end
	stop()
	runtime:dispose()
	part:Destroy()
end)

local function strip(t: any, control: number, corners: string?): (any, any)
	local Facet = t.Facet
	local package = assert(Facet.themes.define({
		identity = { id = `classb-radius-{control}` },
		metrics = { radii = { control = control, panel = 12, pill = 999 } },
	} :: any))
	local stage = t.mount(function(UI, _, Compose)
		return UI.Picker "View" {
			selected = Compose.cell("a"),
			style = "segmented",
			corners = corners,
			Size = UDim2.fromOffset(360, 44),
			options = {
				{ value = "a", label = "One" },
				{ value = "b", label = "Two" },
				{ value = "c", label = "Tri" },
			},
		}
	end, { size = Vector2.new(600, 300), theme = package, frames = 12 })
	return stage, tagged(stage, "facet-segmented")[1]
end

interactive("segment-fill-follows-track", { "mech3-35" }, function(t)
	local value = {}
	local stage, track = strip(t, 8, "pill")
	value.stage, value.track = stage, track
	t.check("the pill strip mounts", track ~= nil)
	if track then
		t.stable(track)
		local current = tagged(track, "facet-segment-current")[1]
		value.current = current
		t.check("one segment is current", current ~= nil)
		if current then
			local a, b = t.rect(current), t.rect(track)
			t.near("the fill is inset 3 px from the track top", a.y - b.y, 3, 0.5)
			t.near("the fill is inset 3 px from the track bottom", b.b - a.b, 3, 0.5)
			t.near("the fill is inset 3 px from the track leading edge", a.x - b.x, 3, 0.5)
			local corner = track:FindFirstChild("Corners")
			t.check(
				"the track wears the pill corner",
				corner ~= nil and corner.CornerRadius.Scale == 1,
				corner and corner.CornerRadius
			)
			t.check("the strip carries the pill tag", track:HasTag("facet-segmented-pill"), track:GetTags())
			local rule = sheetRule(stage, ".facet-segmented-pill >> .facet-segment::UICorner")
			t.check(
				"the segments inside a pill strip resolve a capsule corner",
				rule ~= nil and rule.CornerRadius == UDim.new(1, 0),
				rule and rule.CornerRadius
			)
			t.note("track rect", { b.x, b.y, b.w, b.h })
			t.note("fill rect", { a.x, a.y, a.w, a.h })
		end
	end
	return value
end, {
	capture = function(t, value)
		t.check("the strip is still mounted for the capture", value.track ~= nil and value.track.Parent ~= nil)
	end,
})

add("segment-corner-concentric", { "mech3-35" }, function(t)
	for _, control in { 0, 8, 999 } do
		local stage, track = strip(t, control, nil)
		local current = track and tagged(track, "facet-segment-current")[1]
		local outer = sheetRule(stage, ".facet-segmented::UICorner")
		local inner = sheetRule(stage, ".facet-segment::UICorner")
		t.check(`control {control}: the strip and its fill mount`, track ~= nil and current ~= nil)
		if track and current and outer and inner then
			local trackRadius = control + 2
			t.check(
				`control {control}: the track keeps the theme's corner`,
				outer.CornerRadius == UDim.new(0, trackRadius),
				outer.CornerRadius
			)
			t.check(
				`control {control}: the fill corner is the track corner less the 3 px inset`,
				inner.CornerRadius == UDim.new(0, math.max(0, trackRadius - 3)),
				inner.CornerRadius
			)
			local a, b = t.rect(current), t.rect(track)
			t.near(`control {control}: the fill floats 3 px inside the track`, a.y - b.y, 3, 0.5)
			if control == 999 then
				t.check(
					"a fully round track keeps a capsule fill",
					inner.CornerRadius.Offset >= a.h / 2,
					{ inner.CornerRadius.Offset, a.h }
				)
			end
			t.check(`control {control}: the strip names no container tag`, not track:HasTag("facet-segmented-pill"))
		end
		t.cleanup()
	end
	local stage, track = strip(t, 8, "square")
	local rule = sheetRule(stage, ".facet-segmented-square >> .facet-segment::UICorner")
	t.check("a square strip carries the square tag", track ~= nil and track:HasTag("facet-segmented-square"))
	t.check(
		"the segments inside a square strip resolve a square corner",
		rule ~= nil and rule.CornerRadius == UDim.new(0, 0),
		rule and rule.CornerRadius
	)
end)

add("collapsible-safe-edges", { "navigation-2-06" }, function(t)
	for _, size in { Vector2.new(320, 300), Vector2.new(390, 844), Vector2.new(1280, 720) } do
		local where = `{size.X}x{size.Y}`
		local expanded
		local stage = t.mount(function(UI, _, Compose)
			expanded = Compose.cell(false)
			return UI.Screen "S" {
				UI.CollapsibleView "View" {
					label = "Settings",
					expanded = expanded,
					Size = UDim2.new(1, 0, 0, 44),
					content = function()
						return UI.Label {
							text = string.rep("Course details ", 30),
							TextWrapped = true,
							Size = UDim2.new(1, 0, 0, 0),
							AutomaticSize = Enum.AutomaticSize.Y,
						}
					end,
				},
			}
		end, { size = size, frames = 10 })
		expanded:set(true)
		t.settle(20)
		local presentation = t.find(stage, "ExpandedPresentation")
		t.check(where .. " the expanded view presents", presentation ~= nil)
		if presentation then
			t.stable(presentation)
			local gui = stage:FindFirstAncestorWhichIsA("ScreenGui")
			t.inside(where .. " the expanded view stays inside the screen", presentation, stage, 1)
			t.inside(where .. " the expanded view stays inside the ScreenGui safe area", presentation, gui, 1)
			local box, screen = t.rect(presentation), t.rect(stage)
			t.check(
				where .. " the expanded view keeps a 16 px side margin or its 640 px cap",
				(box.x - screen.x >= 15.5 and screen.r - box.r >= 15.5) and box.w <= 640.5,
				{ box.x - screen.x, screen.r - box.r, box.w }
			)
			local found = t.offenders(presentation, stage)
			t.check(
				where .. " nothing in the expanded view crosses a screen edge",
				#found.lateral + #found.vertical == 0,
				found
			)
		end
		t.cleanup()
	end
end)

interactive("navigation-back-pointer", { "navigation-3-19" }, function(t)
	local value = {}
	local stage = t.mount(function(UI, _, Compose)
		value.path = Compose.cell({ { id = "step", value = 1 } })
		return UI.NavigationStack "Nav" {
			path = value.path,
			root = {
				title = "Start",
				content = function()
					return UI.Label { text = "Root" }
				end,
			},
			destinations = {
				step = {
					title = "Step",
					content = function()
						return UI.Button "Other" { label = "Other" }
					end,
				},
			},
			backLabel = "Back",
			transition = false,
		}
	end, { size = Vector2.new(800, 600), frames = 20 })
	local back
	for _, node in stage:GetDescendants() do
		if node.Name == "Back" and node:IsA("GuiButton") and t.visible(node) then
			back = node
		end
	end
	value.back = back
	t.check("the Back chrome shows on the pushed page", back ~= nil)
	if back then
		t.check("Back is at least 44 px wide", back.AbsoluteSize.X >= 43.5, back.AbsoluteSize)
		t.check("Back is at least 44 px tall", back.AbsoluteSize.Y >= 43.5, back.AbsoluteSize)
		t.check("Back starts idle", back.GuiState == Enum.GuiState.Idle, back.GuiState)
		t.note("back path", back:GetFullName())
	end
	return value
end, {
	hovered = function(t, value)
		t.check(
			"the pointer over Back puts it in the Hover state",
			value.back.GuiState == Enum.GuiState.Hover,
			value.back.GuiState
		)
	end,
	clicked = function(t, value)
		t.check("a click on Back pops the page", #value.path:peek() == 0, #value.path:peek())
	end,
})

local function pager(t: any, size: any, reduced: boolean): (any, any)
	local value = {}
	local stage = t.mount(function(UI, _, Compose)
		value.selection = Compose.cell("one")
		local pages = {}
		for _, id in { "one", "two", "three" } do
			table.insert(pages, {
				id = id,
				title = id,
				content = function()
					return UI.Button "Play" { label = "Play " .. id }
				end,
			})
		end
		return UI.PageView "Pager" { selection = value.selection, pages = pages }
	end, { size = size, reducedMotion = reduced, frames = 12 })
	return stage, value
end

add("pageview-resize-during-travel", { "navigation-3-44" }, function(t)
	local size = t.Facet.Compose.cell(Vector2.new(600, 400))
	local stage, value = pager(t, size, false)
	local pages = t.find(stage, "Pages")
	local layout = pages:FindFirstChildWhichIsA("UIPageLayout")
	local three = pages:FindFirstChild("three")
	t.check("the pager animates page travel", layout.Animated == true, layout.Animated)
	value.selection:set("three")
	t.settle(2)
	size:set(Vector2.new(400, 600))
	t.settle(90)
	t.check("the requested page survives the resize", value.selection:peek() == "three", value.selection:peek())
	t.check(
		"the layout rests on the requested page",
		layout.CurrentPage == three,
		layout.CurrentPage and layout.CurrentPage.Name
	)
	t.check("the page is the same instance", pages:FindFirstChild("three") == three)
	t.near("the page fills the new width", three.AbsoluteSize.X, 400, 0.5)
	t.near("the requested page is on screen", three.AbsolutePosition.X, pages.AbsolutePosition.X, 0.5)
	size:set(Vector2.new(900, 500))
	value.selection:set("two")
	t.settle(3)
	size:set(Vector2.new(500, 700))
	t.settle(90)
	local two = pages:FindFirstChild("two")
	t.check(
		"a second travel keeps its page through a class flip",
		value.selection:peek() == "two" and layout.CurrentPage == two,
		layout.CurrentPage and layout.CurrentPage.Name
	)
	t.near("the second page is on screen", two.AbsolutePosition.X, pages.AbsolutePosition.X, 0.5)
	t.near("the second page fills the portrait width", two.AbsoluteSize.X, 500, 0.5)
end)

add("pageview-fixed-in-scroller", { "navigation-3-48" }, function(t)
	local stage = t.mount(function(UI, _, Compose)
		return UI.ScrollView "Outer" {
			width = "fill",
			height = "fill",
			UI.PageView "Pager" {
				selection = Compose.cell("one"),
				Size = UDim2.new(1, 0, 0, 360),
				pages = {
					{
						id = "one",
						title = "One",
						content = function()
							return UI.Label { text = "Course details" }
						end,
					},
				},
			},
		}
	end, { size = Vector2.new(600, 400), frames = 12 })
	local outer = t.find(stage, "Outer")
	local pagerNode = t.find(stage, "Pager")
	local pages = t.find(pagerNode, "Pages")
	local one = pages:FindFirstChild("one")
	t.near("the pager keeps its fixed 360 px height", pagerNode.AbsoluteSize.Y, 360, 0.5)
	t.check(
		"the page viewport is bounded and positive",
		pages.AbsoluteSize.Y > 0 and pages.AbsoluteSize.Y <= 360,
		pages.AbsoluteSize
	)
	t.near("the page fills the page viewport", one.AbsoluteSize.Y, pages.AbsoluteSize.Y, 0.5)
	t.inside("the page viewport stays inside the pager", pages, pagerNode, 0.5)
	t.check(
		"the outer canvas holds the pager and no more",
		outer.AbsoluteCanvasSize.Y >= 359.5 and outer.AbsoluteCanvasSize.Y <= 360 + 64,
		outer.AbsoluteCanvasSize
	)
end)

add("segment-accent-plate-image-themes", { "navigation-3-51" }, function(t)
	for _, entry in t.themes do
		local stage = t.mount(function(UI, _, Compose)
			return UI.Picker "Motion" {
				selected = Compose.cell("full"),
				style = "segmented",
				Size = UDim2.fromOffset(360, 44),
				options = { { value = "full", label = "Full" }, { value = "reduced", label = "Reduced" } },
			}
		end, { size = Vector2.new(600, 200), theme = entry.package, frames = 10 })
		local current = tagged(stage, "facet-segment-current")
		local plate = sheetRule(stage, ".facet-segment-current")
		local ink = sheetRule(stage, ".facet-segment-current >> .facet-button-caption")
		t.check(`{entry.name}: one segment is current`, #current == 1, #current)
		if current[1] and plate and ink then
			local segment = current[1]
			t.check(
				`{entry.name}: the current segment paints an opaque plate`,
				segment:GetStyled("BackgroundTransparency") == 0,
				segment:GetStyled("BackgroundTransparency")
			)
			t.check(
				`{entry.name}: the plate is the accent`,
				segment:GetStyled("BackgroundColor3") == plate.BackgroundColor3,
				{ segment:GetStyled("BackgroundColor3"), plate.BackgroundColor3 }
			)
			local caption = tagged(segment, "facet-button-caption")[1]
			local expected = if caption then ink.TextColor3 else plate.TextColor3
			local reader = caption or segment
			t.check(
				`{entry.name}: the label reads onAccent on the plate`,
				reader:GetStyled("TextColor3") == expected,
				{ reader:GetStyled("TextColor3"), expected }
			)
			local covering = {}
			for _, node in segment:GetDescendants() do
				if
					node:IsA("ImageLabel")
					and shown(node)
					and node:GetStyled("ImageTransparency") < 1
					and node.AbsoluteSize.X >= segment.AbsoluteSize.X - 1
				then
					table.insert(covering, node.Name)
				end
			end
			t.check(`{entry.name}: no art covers the plate`, #covering == 0, covering)
			local other = nil
			for _, node in tagged(stage, "facet-segment") do
				if not node:HasTag("facet-segment-current") then
					other = node
				end
			end
			t.check(
				`{entry.name}: the neighbour paints no plate`,
				other ~= nil and other:GetStyled("BackgroundTransparency") == 1,
				other and other:GetStyled("BackgroundTransparency")
			)
		else
			t.check(`{entry.name}: the plate rules compile`, false, { plate ~= nil, ink ~= nil })
		end
		t.cleanup()
	end
end)

add("underline-follows-rehomed-strip", { "navigation-4-26" }, function(t)
	local atTop, selected
	local stage = t.mount(function(UI, _, Compose)
		atTop = Compose.cell(true)
		selected = Compose.cell("a")
		local function strip()
			return UI.Picker "Tabs" {
				selected = selected,
				style = "inline",
				indicator = "underline",
				axis = "x",
				options = { { value = "a", label = "Alpha" }, { value = "b", label = "Beta" } },
			}
		end
		return UI.VStack "Page" {
			gap = 0,
			width = "fill",
			Compose.show(atTop, strip),
			UI.VStack "Body" { Size = UDim2.new(1, 0, 0, 100) },
			Compose.show(function(use)
				return not use(atTop)
			end, strip),
		}
	end, { size = Vector2.new(600, 400), frames = 12 })
	local function bar(): any
		for _, node in stage:GetDescendants() do
			if node.Name == "SelectionIndicator" and t.visible(node) then
				return node
			end
		end
		return nil
	end
	local function check(label: string, id: string)
		local line = bar()
		t.check(label .. ": one underline shows", line ~= nil)
		if line then
			local button = line.Parent
			t.check(label .. ": the underline is inside the chosen option", button.Name == id, button.Name)
			local a, b = t.rect(line), t.rect(button)
			local pad = button:FindFirstChildWhichIsA("UIPadding")
			local left = if pad then pad:GetStyled("PaddingLeft").Offset else 0
			local right = if pad then pad:GetStyled("PaddingRight").Offset else 0
			t.near(label .. ": the underline starts at the option's content edge", a.x, b.x + left, 0.5)
			t.near(label .. ": the underline spans the option's content box", a.w, b.w - left - right, 0.5)
			t.near(label .. ": the underline sits on the option's bottom edge", a.b, b.b, 0.5)
		end
		return line
	end
	local first = check("top home", "a")
	local topY = first and first.AbsolutePosition.Y
	atTop:set(false)
	t.settle(10)
	local moved = check("bottom home", "a")
	t.check(
		"the underline moved down with the strip",
		moved ~= nil and topY ~= nil and moved.AbsolutePosition.Y > topY + 99,
		{ topY, moved and moved.AbsolutePosition.Y }
	)
	selected:set("b")
	t.settle(10)
	check("bottom home after a new selection", "b")
end)

add("tab-reorder-keeps-page-geometry", { "navigation-4-58" }, function(t)
	local order, builds = nil, 0
	local stage = t.mount(function(UI, _, Compose)
		order = Compose.cell({ "home", "feed", "me" })
		return UI.TabView "Tabs" {
			selection = Compose.cell("home"),
			style = "sidebarAdaptable",
			placement = "bottomBar",
			customization = function(use)
				return { order = use(order) }
			end,
			tabs = {
				{
					id = "home",
					label = "Home",
					content = function()
						builds += 1
						return UI.VStack "HomeBody" {
							width = "fill",
							UI.Button "First" { label = "First" },
							UI.Button "Second" { label = "Second" },
						}
					end,
				},
				{
					id = "feed",
					label = "Feed",
					content = function()
						return UI.Label { text = "Feed" }
					end,
				},
				{
					id = "me",
					label = "Me",
					content = function()
						return UI.Label { text = "Me" }
					end,
				},
			},
		}
	end, { size = Vector2.new(390, 700), frames = 15 })
	local strip = t.find(stage, "Tabs"):FindFirstChild("Tabs")
	local body = t.find(stage, "HomeBody")
	local content = t.find(stage, "Content")
	local buttons =
		{ home = strip:FindFirstChild("home"), feed = strip:FindFirstChild("feed"), me = strip:FindFirstChild("me") }
	local function snapshot(): { [string]: any }
		local out = {}
		for _, node in body:GetDescendants() do
			if node:IsA("GuiObject") then
				out[node:GetFullName()] = t.rect(node)
			end
		end
		out.content = t.rect(content)
		out.body = t.rect(body)
		return out
	end
	local before = snapshot()
	local xs = { home = buttons.home.AbsolutePosition.X, me = buttons.me.AbsolutePosition.X }
	order:set({ "me", "feed", "home" })
	t.settle(10)
	t.check(
		"the strip keeps the same tab buttons",
		strip:FindFirstChild("home") == buttons.home and strip:FindFirstChild("me") == buttons.me
	)
	t.check(
		"the reordered strip puts Me first",
		buttons.me.AbsolutePosition.X < buttons.feed.AbsolutePosition.X
			and buttons.feed.AbsolutePosition.X < buttons.home.AbsolutePosition.X,
		{ buttons.me.AbsolutePosition.X, buttons.feed.AbsolutePosition.X, buttons.home.AbsolutePosition.X }
	)
	t.near("Me takes the leading slot", buttons.me.AbsolutePosition.X, xs.home, 0.5)
	t.near("Home takes the trailing slot", buttons.home.AbsolutePosition.X, xs.me, 0.5)
	t.check("the page was built once", builds == 1, builds)
	local after = snapshot()
	local moved = {}
	for key, rect in before do
		local now = after[key]
		if
			not now
			or math.abs(now.x - rect.x) > 0.5
			or math.abs(now.y - rect.y) > 0.5
			or math.abs(now.w - rect.w) > 0.5
			or math.abs(now.h - rect.h) > 0.5
		then
			table.insert(moved, key)
		end
	end
	t.check("no page geometry changes outside the strip", #moved == 0, moved)
	t.inside("the strip stays inside the TabView", strip, t.find(stage, "Tabs"), 0.5)
end)

add("tab-content-stretches-page", { "navigation-5-20" }, function(t)
	for _, size in { Vector2.new(390, 844), Vector2.new(1280, 720) } do
		local where = `{size.X}x{size.Y}`
		local stage = t.mount(function(UI, _, Compose)
			return UI.TabView "Tabs" {
				selection = Compose.cell("home"),
				style = "sidebarAdaptable",
				tabs = {
					{
						id = "home",
						label = "Home",
						content = function()
							return UI.HStack "HomeBody" {
								UI.Label { text = "a considerably wider body than a phone offers" },
								UI.Label { text = "and a second one after it, for good measure" },
							}
						end,
					},
					{
						id = "feed",
						label = "Feed",
						content = function()
							return UI.Label { text = "Feed" }
						end,
					},
				},
			}
		end, { size = size, frames = 15 })
		local root = t.find(stage, "Tabs")
		local content = root:FindFirstChild("Content")
		local layer = content and content:FindFirstChild("home")
		t.check(where .. " the page layer mounts", layer ~= nil)
		if content and layer then
			local c, l = t.rect(content), t.rect(layer)
			t.near(where .. " the page layer is as wide as the content region", l.w, c.w, 0.5)
			t.near(where .. " the page layer is as tall as the content region", l.h, c.h, 0.5)
			t.near(where .. " the page layer starts at the region", l.x, c.x, 0.5)
			t.inside(where .. " the content region stays inside the TabView", content, root, 0.5)
			t.check(where .. " the region clips a wider page", content.ClipsDescendants == true)
			local body = t.find(layer, "HomeBody")
			local seen = t.clipped(body)
			t.check(
				where .. " the visible part of the page stays inside the region",
				seen ~= nil and seen.x >= c.x - 0.5 and seen.r <= c.r + 0.5,
				seen
			)
			local strip = root:FindFirstChild("Tabs")
			t.check(
				where .. " the page does not cover the strip",
				strip ~= nil
					and (
						strip.AbsolutePosition.Y >= c.b - 0.5
						or strip.AbsolutePosition.X + strip.AbsoluteSize.X <= c.x + 0.5
						or strip.AbsolutePosition.Y + strip.AbsoluteSize.Y <= c.y + 0.5
					),
				{ t.rect(strip), c }
			)
		end
		t.cleanup()
	end
end)

add("progress-track-centring", { "paint-35" }, function(t)
	local stage = t.mount(function(UI, _, Compose)
		return UI.VStack "Column" {
			width = "fill",
			gap = 16,
			UI.ProgressView "Down" { label = "Download", value = Compose.cell(0.35), showValue = true },
			UI.Label "Cap" { text = "Save changes" },
		}
	end, { size = Vector2.new(400, 400), frames = 12 })
	local root = t.find(stage, "Down")
	local track = tagged(root, "facet-track")[1]
	local header = t.find(root, "Header")
	local value = t.find(root, "Value")
	t.check("the bar has a track and a header", track ~= nil and header ~= nil and value ~= nil)
	if track and header and value then
		local r, tr = t.rect(root), t.rect(track)
		t.near("the track starts at the row's leading edge", tr.x, r.x, 0.5)
		t.near("the track ends at the row's trailing edge", tr.r, r.r, 0.5)
		t.check("the track lies on whole pixels", tr.y % 1 == 0 and tr.h % 1 == 0, { tr.y, tr.h })
		local title
		for _, node in header:GetChildren() do
			if node:IsA("TextLabel") and node ~= value then
				title = node
			end
		end
		if title then
			local a, b = t.rect(title), t.rect(value)
			t.near("the value centres on the label's midline", b.y + b.h / 2, a.y + a.h / 2, 0.5)
		end
	end
	local cap = t.find(stage, "Cap")
	local box = t.rect(cap)
	local bounds = cap.TextBounds
	t.check("the label title has glyphs", bounds.X > 0)
	local lead = if cap:GetStyled("TextXAlignment") == Enum.TextXAlignment.Center then (box.w - bounds.X) / 2 else 0
	t.near("the title's glyphs are centred in its own box", lead, (box.w - bounds.X) / 2, 0.5)
end)

add("progress-track-beside-trailing-copy", { "paint-43" }, function(t)
	local package = themed(t, "fantasy_ornate") or t.themes[1].package
	for _, width in { 280, 200 } do
		for _, spec in
			{
				{ key = "segmented", value = 0.4, segments = 5, showValue = true, endLabel = "2 of 5" },
				{ key = "ordinary", value = 0.4, showValue = true, endLabel = "Waiting for the next checkpoint" },
				{ key = "busy", endLabel = "Waiting for the next checkpoint" },
				{
					key = "labelled",
					label = "Loading",
					value = 0.4,
					showValue = true,
					endLabel = "Waiting for the next checkpoint",
				},
			}
		do
			if spec.key == "labelled" and width < 280 then
				continue
			end
			local where = `{width} {spec.key}`
			local stage = t.mount(function(UI, _, Compose)
				local props = table.clone(spec)
				props.key = nil
				if props.value ~= nil then
					props.value = Compose.cell(props.value)
				end
				return UI.VStack "Column" { width = "fill", UI.ProgressView "Progress"(props) }
			end, { size = Vector2.new(width, 500), theme = package, frames = 12 })
			local root = t.find(stage, "Progress")
			local track = tagged(root, "facet-track")[1]
			local fill = t.find(root, "Fill1")
			local ending = t.find(root, "EndLabel")
			t.check(
				where .. " the track is visible and at least 4 px wide",
				track ~= nil and t.visible(track) and track.AbsoluteSize.X >= 4,
				track and track.AbsoluteSize
			)
			local samples = if spec.value == nil then 10 else 1
			local blank = {}
			for sample = 1, samples do
				local seen = fill and t.clipped(fill)
				if seen == nil or seen.w <= 0 then
					table.insert(blank, sample)
				end
				if samples > 1 then
					t.settle(8)
				end
			end
			t.check(where .. " the fill shows inside the track at every sample", #blank == 0, blank)
			t.check(
				where .. " the end copy shows its words",
				ending ~= nil and ending.ContentText == spec.endLabel,
				ending and ending.ContentText
			)
			if ending then
				t.inside(where .. " the end copy stays on screen", ending, stage, 0.5)
				t.check(
					where .. " the end copy is not clipped",
					t.fits(ending) or ending:GetStyled("TextTruncate") ~= Enum.TextTruncate.None,
					{ ending.TextBounds, ending.AbsoluteSize }
				)
			end
			if spec.segments then
				local first = t.find(root, "Fill1")
				t.check(
					where .. " the first segment has width",
					first ~= nil and first.AbsoluteSize.X > 0,
					first and first.AbsoluteSize
				)
			end
			t.cleanup()
		end
	end
end)

add("icon-inside-content-box", { "paint-51" }, function(t)
	for _, entry in t.themes do
		for _, case in
			{
				{ key = "tight", size = UDim2.fromOffset(52, 44), label = "Go" },
				{ key = "room", size = UDim2.fromOffset(220, 60), label = "Continue" },
				{ key = "icon-only", size = UDim2.fromOffset(20, 20) },
			}
		do
			local where = `{entry.name} {case.key}`
			local stage = t.mount(function(UI)
				return UI.Button "Back" {
					icon = "chevron.leading",
					label = case.label,
					Size = case.size,
					AutomaticSize = Enum.AutomaticSize.None,
				}
			end, { size = Vector2.new(400, 200), theme = entry.package, frames = 8 })
			local button = t.find(stage, "Back")
			local icon = t.find(button, "LeadingIcon")
			if icon then
				local ib = t.rect(icon)
				t.check(where .. " the picture is never zero", ib.w >= 1 and ib.h >= 1, { ib.w, ib.h })
				if case.key == "icon-only" then
					t.note(where .. " icon in a 20 px button", { ib.x, ib.y, ib.w, ib.h })
				else
					local pad = button:FindFirstChildWhichIsA("UIPadding")
					local box = t.rect(button)
					local left = if pad then pad:GetStyled("PaddingLeft").Offset else 0
					local right = if pad then pad:GetStyled("PaddingRight").Offset else 0
					local top = if pad then pad:GetStyled("PaddingTop").Offset else 0
					local bottom = if pad then pad:GetStyled("PaddingBottom").Offset else 0
					t.inside(where .. " the picture stays inside the button's content box", icon, {
						x = box.x + left,
						y = box.y + top,
						w = box.w - left - right,
						h = box.h - top - bottom,
						r = box.r - right,
						b = box.b - bottom,
					}, 0.5)
				end
				if case.key == "room" then
					local metric = entry.package.metrics.controls
					local rung = metric and metric.regular and metric.regular.iconSize
					t.note(where .. " icon", { ib.w, ib.h, rung })
					if rung then
						t.near(where .. " a button with room draws the rung untouched", ib.w, rung, 0.5)
					end
				end
			else
				t.check(where .. " the icon mounts", false)
			end
			t.cleanup()
		end
	end
end)

interactive("path-clipped-in-scroll", { "paint-86" }, function(t)
	local value = {}
	local stage = t.mount(function(UI, _, Compose)
		local rows = {}
		for index = 1, 6 do
			table.insert(
				rows,
				UI.HStack("Row" .. index) {
					Size = UDim2.new(1, 0, 0, 60),
					UI.ProgressView "Ring" {
						presentation = "circular",
						value = Compose.cell(0.75),
						diameter = 56,
						thickness = 8,
					},
				}
			)
		end
		return UI.ScrollView "List" {
			Size = UDim2.fromOffset(300, 150),
			gap = 0,
			table.unpack(rows),
		}
	end, { size = Vector2.new(600, 400), frames = 15 })
	value.list = t.find(stage, "List")
	local function report(label: string)
		local shown = {}
		for index = 1, 6 do
			local ring = t.find(t.find(value.list, "Row" .. index), "RingFill")
			local seen = ring and t.clipped(ring.Parent)
			shown[index] = if seen == nil
				then "none"
				elseif seen.h >= ring.Parent.AbsoluteSize.Y - 0.5 then "whole"
				else "part"
		end
		t.note(label, shown)
		return shown
	end
	local shown = report("at rest")
	t.check("rows 1 and 2 are whole in the viewport", shown[1] == "whole" and shown[2] == "whole", shown)
	t.check("row 3 crosses the viewport edge", shown[3] == "part", shown)
	t.check("rows 4 to 6 are outside the viewport", shown[4] == "none" and shown[6] == "none", shown)
	t.check("the viewport clips its descendants", value.list:IsA("ScrollingFrame"))
	return value
end, {
	scrolled = function(t, value)
		value.list.CanvasPosition = Vector2.new(0, 120)
		t.settle(4)
		local shown = {}
		for index = 1, 6 do
			local ring = t.find(t.find(value.list, "Row" .. index), "RingFill")
			local seen = ring and t.clipped(ring.Parent)
			shown[index] = if seen == nil
				then "none"
				elseif seen.h >= ring.Parent.AbsoluteSize.Y - 0.5 then "whole"
				else "part"
		end
		t.note("after scroll", shown)
		t.check("after a scroll rows 1 and 2 leave the viewport", shown[1] == "none" and shown[2] == "none", shown)
		t.check("after a scroll rows 3 and 4 are whole", shown[3] == "whole" and shown[4] == "whole", shown)
	end,
})

return cases
