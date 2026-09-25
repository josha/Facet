--!strict
local cases = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function anchored(UI: any, Host: any, Compose: any, at: UDim2, edge: string?, pivot: Vector2)
	local anchor = UI.Button "Anchor" { label = "Anchor", Position = at, AnchorPoint = pivot }
	return Host.Frame "Surface" {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		anchor,
		UI.Callout({
			anchor = anchor,
			edge = edge,
			isPresented = Compose.cell(true),
			onRetire = function() end,
			content = function()
				return UI.Text({ text = "Start from a prompt, then edit it before you send." })
			end,
		}),
	}
end

local SPOTS = {
	{ name = "centre", at = UDim2.fromScale(0.5, 0.6), edge = "top", pivot = Vector2.new(0.5, 0.5) },
	{ name = "left", at = UDim2.new(0, 8, 0.6, 0), edge = "top", pivot = Vector2.new(0, 0.5) },
	{ name = "right", at = UDim2.new(1, -8, 0.6, 0), edge = "top", pivot = Vector2.new(1, 0.5) },
	{ name = "top-left", at = UDim2.fromOffset(8, 12), edge = "top", pivot = Vector2.zero },
	{ name = "bottom-right", at = UDim2.new(1, -8, 1, -8), edge = nil, pivot = Vector2.one },
}

add("callout-edge-gap-shift-clamp", { "navigation-1-39", "navigation-1-67" }, function(t)
	for _, spot in SPOTS do
		local stage = t.mount(function(UI, Host, Compose)
			return anchored(UI, Host, Compose, spot.at, spot.edge, spot.pivot)
		end)
		local anchor, panel = t.find(stage, "Anchor"), t.find(stage.Parent, "CalloutPanel")
		if not panel then
			t.check(spot.name .. " panel mounted", false)
			t.cleanup()
			continue
		end
		local screen = stage.Parent
		local a, p, s = t.rect(anchor), t.rect(panel), t.rect(screen)
		local above = p.b <= a.y + 0.5
		local gap = if above then a.y - p.b else p.y - a.b
		t.near(spot.name .. " gap off the anchor edge", gap, 8, 1)
		t.check(spot.name .. " panel does not cover the anchor", p.b <= a.y + 0.5 or p.y >= a.b - 0.5, {
			panel = { p.y, p.b },
			anchor = { a.y, a.b },
		})
		if spot.name == "top-left" then
			t.check("top-left flips below when the top edge has no room", p.y >= a.b - 0.5, { panel = p.y })
		end
		t.inside(spot.name .. " panel inside the safe box with 8px gutter", p, {
			x = s.x + 8,
			y = s.y + 8,
			r = s.r - 8,
			b = s.b - 8,
			w = 0,
			h = 0,
		}, 1)
		local centred = a.x + a.w / 2 - p.w / 2
		t.note(spot.name .. " shift", p.x - centred)
		if spot.name == "centre" then
			t.near("centre panel centred on the anchor", p.x + p.w / 2, a.x + a.w / 2, 1)
		end
		t.cleanup()
	end
end)

add("callout-tail-centre-border-corners", { "navigation-1-42" }, function(t)
	for _, spot in SPOTS do
		local stage = t.mount(function(UI, Host, Compose)
			return anchored(UI, Host, Compose, spot.at, spot.edge, spot.pivot)
		end)
		local screen = stage.Parent
		local anchor, panel, arrow = t.find(stage, "Anchor"), t.find(screen, "CalloutPanel"), t.find(screen, "Arrow")
		if not (panel and arrow) then
			t.check(spot.name .. " tail mounted", false)
			t.cleanup()
			continue
		end
		local a, p = t.rect(anchor), t.rect(panel)
		local centreX = arrow.AbsolutePosition.X + arrow.AbsoluteSize.X / 2
		local centreY = arrow.AbsolutePosition.Y + arrow.AbsoluteSize.Y / 2
		local border = if p.b <= a.y + 0.5 then p.b else p.y
		t.near(spot.name .. " tail rides the shared border", centreY, border, 1.5)
		t.check(
			spot.name .. " tail clears the panel corners",
			centreX >= p.x + 12 - 1 and centreX <= p.r - 12 + 1,
			{ centre = centreX, left = p.x, right = p.r }
		)
		local source = a.x + a.w / 2
		if source >= p.x + 12 and source <= p.r - 12 then
			t.near(spot.name .. " tail centres on the source", centreX, source, 1.5)
		end
		t.check(spot.name .. " tail paints behind the panel", arrow.ZIndex < panel.ZIndex, {
			arrow = arrow.ZIndex,
			panel = panel.ZIndex,
		})
		t.cleanup()
	end
end)

add("navigation-stack-root-box-and-back-chrome", { "navigation-3-27" }, function(t)
	local path
	local stage = t.mount(function(UI, _, Compose)
		path = Compose.cell({})
		return UI.NavigationStack({
			path = path,
			root = {
				content = function()
					return UI.Text "RootLabel" { text = "Root" }
				end,
			},
			destinations = {
				detail = {
					title = "Detail",
					content = function()
						return UI.Text "DetailLabel" { text = "Detail" }
					end,
				},
			},
		})
	end, { size = Vector2.new(480, 320) })
	local stack = t.find(stage, "NavigationStack")
	local rootDestination = t.find(t.find(stack, "@root") or stack, "Destination")
	local s, d = t.rect(stack), t.rect(rootDestination)
	t.near("untitled root keeps the full width", d.w, s.w, 0.5)
	t.near("untitled root keeps the full height", d.h, s.h, 0.5)
	t.near("untitled root starts at the top", d.y, s.y, 0.5)
	path:set({ { id = "detail" } })
	t.settle(12)
	local page = t.find(stack, "detail")
	local destination, back, bar = t.find(page, "Destination"), t.find(page, "Back"), t.find(page, "NavigationBar")
	local pd, pb = t.rect(destination), t.rect(back)
	t.near("destination box is reduced by the Back chrome", pd.h, s.h - t.rect(bar).h, 0.5)
	t.check("destination starts below the navigation bar", pd.y >= t.rect(bar).b - 0.5, { destination = pd.y })
	t.near("destination keeps the stack bottom", pd.b, s.b, 0.5)
	t.inside("Back sits inside the navigation bar", pb, bar, 1)
	t.check("Back is visible", t.visible(back))
	t.note("navigation bar height", t.rect(bar).h)
	local title = t.find(bar, "Title")
	t.check("title fits its bar", title.TextFits, { bounds = title.TextBounds, size = title.AbsoluteSize })
end)

add("vertical-segments-stack-share-width-floor", { "navigation-3-59" }, function(t)
	local stage = t.mount(function(UI, _, Compose)
		return UI.Picker "Rail" {
			style = "segmented",
			axis = "y",
			selected = Compose.cell("a"),
			options = {
				{ value = "a", label = "Alpha" },
				{ value = "b", label = "Beta with a longer label" },
				{ value = "c", label = "C" },
			},
		}
	end, { size = Vector2.new(480, 400) })
	local segments = {}
	for _, value in { "a", "b", "c" } do
		local node = t.find(stage, value)
		if node and node:IsA("GuiObject") then
			table.insert(segments, t.rect(node))
		end
	end
	t.check("three segments mounted", #segments == 3, #segments)
	for index, rect in segments do
		t.check(`segment {index} meets the 44px floor on X`, rect.w >= 44 - 0.5, rect.w)
		t.check(`segment {index} meets the 44px floor on Y`, rect.h >= 44 - 0.5, rect.h)
		if index > 1 then
			t.check(`segment {index} stacks below segment {index - 1}`, rect.y >= segments[index - 1].b - 0.5, {
				top = rect.y,
				previousBottom = segments[index - 1].b,
			})
			t.near(`segment {index} shares the rail width`, rect.w, segments[1].w, 0.5)
			t.near(`segment {index} shares the rail x`, rect.x, segments[1].x, 0.5)
		end
	end
end)

add("tab-head-accessory-above-rail", { "navigation-5-34" }, function(t)
	local stage = t.mount(function(UI, Host, Compose)
		return UI.TabView({
			selection = Compose.cell("one"),
			style = "sidebarAdaptable",
			placement = "sidebar",
			tabs = {
				{
					id = "one",
					label = "One",
					content = function()
						return Host.Frame({ BackgroundTransparency = 1 })
					end,
				},
				{
					id = "two",
					label = "Two",
					content = function()
						return Host.Frame({ BackgroundTransparency = 1 })
					end,
				},
			},
			accessories = {
				head = function()
					return UI.Text "HeadLabel" { text = "Profile header" }
				end,
				foot = function()
					return UI.Button "FootButton" { label = "Settings" }
				end,
			},
		})
	end, { size = Vector2.new(1000, 600) })
	local head, tabs = t.find(stage, "Accessory-head"), t.find(stage, "Tabs")
	local foot = t.find(stage, "Accessory-foot")
	if not (head and tabs and foot) then
		t.check("rail slots mounted", false, { head = head ~= nil, tabs = tabs ~= nil, foot = foot ~= nil })
		return
	end
	local h, s, f, root = t.rect(head), t.rect(tabs), t.rect(foot), t.rect(stage)
	t.check("head sits above the strip", h.b <= s.y + 0.5, { head = h.b, strip = s.y })
	t.check("head height is measured", h.h > 0, h.h)
	local railWidth = math.clamp(math.floor(root.w * 0.2), 200, 280)
	t.near("head spans the rail width", h.w, railWidth, 0.5)
	t.near("head starts at the rail edge", h.x, root.x, 0.5)
	t.check(
		"the strip sits inside the rail",
		s.x >= root.x - 0.5 and s.r <= root.x + railWidth + 0.5,
		{ strip = s, railWidth = railWidth }
	)
	t.check("head inside the TabView", h.x >= root.x - 0.5 and h.y >= root.y - 0.5, h)
	t.near("foot is pinned to the rail bottom", f.b, root.b, 0.5)
	t.check("strip ends above the foot", s.b <= f.y + 0.5, { strip = s.b, foot = f.y })
	t.check("rail inside the TabView width", s.r <= root.r + 0.5, { strip = s.r, root = root.r })
end)

add("circle-button-authored-axes", { "paint-14" }, function(t)
	for _, rung in { "compact", "regular", "large" } do
		local stage = t.mount(function(UI)
			return UI.Button "Circle" { label = "Close", icon = "close", shape = "circle", controlSize = rung }
		end, { size = Vector2.new(300, 200) })
		local node = t.find(stage, "Circle")
		local r = t.rect(node)
		t.near(`{rung} circle is round`, r.w, r.h, 0.5)
		t.check(`{rung} circle is not empty`, r.w > 0, r.w)
		t.note(`{rung} diameter`, r.w)
		t.cleanup()
	end
	for _, axis in { "width", "height" } do
		local size = if axis == "width" then UDim2.fromOffset(32, 0) else UDim2.fromOffset(0, 72)
		local stage = t.mount(function(UI)
			return UI.Button "Circle" {
				label = "Close",
				icon = "close",
				shape = "circle",
				controlSize = "compact",
				Size = size,
			}
		end, { size = Vector2.new(300, 200) })
		local r = t.rect(t.find(stage, "Circle"))
		local expected = if axis == "width" then 32 else 72
		t.near(`authored {axis} circle keeps its authored {axis}`, if axis == "width" then r.w else r.h, expected, 0.5)
		t.near(`authored {axis} circle is round`, r.w, r.h, 0.5)
		t.cleanup()
	end
end)

add("circular-progress-stroke-inside-box", { "themes-P1-71" }, function(t)
	for _, theme in t.themes do
		local stage = t.mount(function(UI)
			return UI.ProgressView "Ring" { presentation = "circular", value = 1 }
		end, { theme = theme.package, size = Vector2.new(200, 200) })
		local indicator = t.find(stage, "Indicator")
		local fill = indicator and indicator:FindFirstChild("RingFill")
		if not (indicator and fill) then
			t.check(theme.name .. " ring mounted", false)
			t.cleanup()
			continue
		end
		local box = indicator.AbsoluteSize
		local half = fill.Thickness / 2
		local worst = math.huge
		for _, point in fill:GetControlPoints() do
			local x = point.Position.X.Scale * box.X + point.Position.X.Offset
			local y = point.Position.Y.Scale * box.Y + point.Position.Y.Offset
			worst = math.min(worst, x - half, y - half, box.X - x - half, box.Y - y - half)
		end
		t.check(
			theme.name .. " stroke fits inside its own box",
			worst >= -0.5,
			{ margin = worst, thickness = fill.Thickness, box = box }
		)
		t.near(theme.name .. " ring box is square", box.X, box.Y, 0.5)
		t.cleanup()
	end
end)

local function paddingOf(node: Instance): (number, number, number, number)
	local padding = node:FindFirstChildWhichIsA("UIPadding")
	if not padding then
		return 0, 0, 0, 0
	end
	local size = (node :: any).AbsoluteSize
	local function px(name: string, extent: number): number
		local value = (padding :: any):GetStyled(name)
		return value.Scale * extent + value.Offset
	end
	return px("PaddingLeft", size.X), px("PaddingRight", size.X), px("PaddingTop", size.Y), px("PaddingBottom", size.Y)
end

add("chrome-insets-reserve-native-padding", { "themes-P2-20", "themes-P2-26" }, function(t)
	for _, theme in t.themes do
		local stage = t.mount(function(UI, Host, Compose)
			return Host.Frame "Column" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Host.UIListLayout({ Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
				UI.Button "Plain" { label = "Continue the long journey", LayoutOrder = 1 },
				UI.Toggle "Switch" { label = "Notifications", value = Compose.cell(true), LayoutOrder = 2 },
			}
		end, { theme = theme.package, size = Vector2.new(420, 300) })
		for _, name in { "Plain", "Switch" } do
			local node = t.find(stage, name)
			if not node then
				t.check(`{theme.name} {name} mounted`, false)
				continue
			end
			local left, right, top, bottom = paddingOf(node)
			local r = t.rect(node)
			local content = { x = r.x + left, y = r.y + top, r = r.r - right, b = r.b - bottom, w = 0, h = 0 }
			local label = node:IsA("TextButton") and node or node:FindFirstChildWhichIsA("TextLabel", true)
			local lifted = t.find(node, "LabelBounds")
			if lifted then
				t.inside(`{theme.name} {name} lifted label inside the recipe padding`, lifted, content, 1)
				local lb = t.rect(lifted)
				t.near(`{theme.name} {name} lifted label starts at the left inset`, lb.x, content.x, 1)
				t.near(`{theme.name} {name} lifted label ends at the right inset`, lb.r, content.r, 1)
			elseif label and label:IsA("GuiObject") and (label :: any).TextBounds then
				local bounds = (label :: any).TextBounds
				t.check(
					`{theme.name} {name} text fits inside the padded box`,
					bounds.X <= (content.r - content.x) + 1 and bounds.Y <= (content.b - content.y) + 1,
					{ text = bounds, box = { content.r - content.x, content.b - content.y } }
				)
			end
			t.note(`{theme.name} {name} padding`, { left, right, top, bottom })
			t.check(
				`{theme.name} {name} padded box is not negative`,
				content.r >= content.x and content.b >= content.y,
				{
					left = left,
					right = right,
					width = r.w,
				}
			)
		end
		t.cleanup()
	end
end)

add("layers-hang-outside-layout", { "themes-P4-05" }, function(t)
	for _, theme in t.themes do
		t.mount(function(UI, Host, Compose)
			return UI.Sheet({
				isPresented = Compose.cell(true),
				detent = Compose.cell("medium"),
				title = "Loadout",
				content = function()
					return UI.Text "SheetBody" {
						text = "Choose a loadout for the next round.",
						TextWrapped = true,
						Size = UDim2.fromScale(1, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
					}
				end,
			})
		end, { theme = theme.package })
		local gui = game:GetService("Players").LocalPlayer.PlayerGui
		local panel
		for _, node in gui:GetDescendants() do
			if node.Name == "SheetPanel" and node:IsA("GuiObject") and t.visible(node) then
				panel = node
			end
		end
		local body = panel and t.find(panel, "SheetBody")
		if not (panel and body) then
			t.check(theme.name .. " sheet mounted", false)
			t.cleanup()
			continue
		end
		local p, b = t.rect(panel), t.rect(body)
		local offset = b.y - p.y
		t.inside(theme.name .. " content inside the decorated panel", body, panel, 1)
		local boundary
		for _, node in panel:GetDescendants() do
			if node.Name == "SkinBoundary" and node.Parent and node.Parent.Parent == panel then
				boundary = node
			end
		end
		local skin = boundary and boundary:FindFirstChild("Skin", true)
		if skin then
			local art = t.rect(skin)
			t.near(theme.name .. " art covers the panel width", art.w, p.w, 1.5)
			t.near(theme.name .. " art covers the panel height", art.h, p.h, 1.5)
			t.near(theme.name .. " art starts at the panel origin", art.x, p.x, 1.5)
			t.check(
				theme.name .. " art boundary is not a layout item",
				not boundary.Parent:IsA("GuiObject"),
				boundary.Parent.ClassName
			)
		end
		t.note(theme.name .. " content offset", { offset = offset, skinned = skin ~= nil })
		t.cleanup()
	end
end)

add("grid-cell-width-arithmetic", { "collections-226" }, function(t)
	for _, columns in { 2, 3, 4 } do
		local rows = {}
		for index = 1, 12 do
			rows[index] = { id = tostring(index) }
		end
		local stage = t.mount(function(UI, Host)
			return UI.VirtualGrid "Grid" {
				from = rows,
				key = function(item)
					return item.id
				end,
				columns = columns,
				itemSize = 60,
				gap = 8,
				crossGap = 10,
				Size = UDim2.fromOffset(400, 300),
				render = function(current)
					return Host.Frame({
						Name = "Cell" .. current:peek().id,
						Size = UDim2.fromScale(1, 1),
					})
				end,
			}
		end, { size = Vector2.new(400, 300) })
		local grid = t.find(stage, "Grid")
		local window = grid.AbsoluteWindowSize.X
		local edge = math.ceil(10 / 2)
		local expected = (window - 2 * edge - (columns - 1) * 10) / columns
		local first, second = t.find(grid, "Cell1"), t.find(grid, "Cell2")
		if not (first and second) then
			t.check(`{columns} columns cells mounted`, false)
			t.cleanup()
			continue
		end
		local a, b = t.rect(first), t.rect(second)
		t.near(`{columns} columns cell width`, a.w, expected, 1)
		t.near(`{columns} columns first cell keeps half a gap at the edge`, a.x - grid.AbsolutePosition.X, edge, 1)
		t.near(`{columns} columns cross gap`, b.x - a.r, 10, 1)
		t.near(`{columns} columns cell height`, a.h, 60, 1)
		local below = t.find(grid, "Cell" .. tostring(columns + 1))
		if below then
			t.near(`{columns} columns line gap`, t.rect(below).y - a.b, 8, 1)
			t.near(`{columns} columns next line starts at the first column`, t.rect(below).x, a.x, 1)
		end
		t.cleanup()
	end
end)

add("image-button-caption-clear-of-artwork", { "navigation-1-06" }, function(t)
	for _, theme in t.themes do
		for _, width in { 180, 240, 320 } do
			local stage = t.mount(function(UI)
				return UI.Button "Card" {
					label = "A driver with a descriptive title",
					subtitle = "A longer description that must wrap inside the card.",
					image = "rbxasset://textures/ui/GuiImagePlaceholder.png",
					imageAspectRatio = 2,
					Size = UDim2.fromOffset(width, 300),
				}
			end, { theme = theme.package, size = Vector2.new(400, 400) })
			local card = t.find(stage, "Card")
			local image, title = t.find(card, "Image"), t.find(card, "Title")
			local description = t.find(card, "Description")
			local where = `{theme.name} {width}px`
			if not (image and title) then
				t.check(where .. " card parts mounted", false)
				t.cleanup()
				continue
			end
			local i, ti = t.rect(image), t.rect(title)
			t.check(where .. " title below the artwork", ti.y >= i.b - 0.5, { image = i.b, title = ti.y })
			t.inside(where .. " artwork inside the card", i, card, 1)
			t.inside(where .. " title inside the card", ti, card, 1)
			if description then
				local d = t.rect(description)
				t.check(where .. " description below the title", d.y >= ti.b - 0.5, { title = ti.b, description = d.y })
				t.check(
					where .. " description clear of the artwork",
					d.y >= i.b - 0.5,
					{ image = i.b, description = d.y }
				)
				t.note(where .. " description overflow below the card", math.max(0, d.b - t.rect(card).b))
			end
			local selectable = 0
			for _, node in card:GetDescendants() do
				if node:IsA("GuiObject") and node.Selectable and t.visible(node) then
					selectable += 1
				end
			end
			t.check(where .. " one focus target", card.Selectable and selectable == 0, { descendants = selectable })
			t.cleanup()
		end
	end
end)

return cases
