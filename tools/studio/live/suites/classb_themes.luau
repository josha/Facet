--!strict
local GuiService = game:GetService("GuiService")

local cases = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function themeNamed(t: any, name: string): any
	for _, entry in t.themes do
		if entry.name == name then
			return entry.package
		end
	end
	error("missing theme " .. name)
end

local function color(value: any): Color3
	return Color3.new(value.r, value.g, value.b)
end

local function sameColor(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 0.002 and math.abs(a.G - b.G) < 0.002 and math.abs(a.B - b.B) < 0.002
end

local function paletteOf(package: any, name: string): any
	for _, entry in package.style.themes do
		if entry.name == name then
			return entry
		end
	end
	error("missing palette " .. name)
end

add("skeleton-circle-round-sweep", { "themes-P1-87" }, function(t)
	local stage = t.mount(function(UI, Host)
		return Host.Frame "Holder" {
			Size = UDim2.fromOffset(300, 300),
			BackgroundTransparency = 1,
			UI.Skeleton "Circle" { form = "circle" },
		}
	end, { size = Vector2.new(400, 400), reducedMotion = false })
	local plate = t.find(stage, "Circle"):FindFirstChild("Placeholder1")
	local size = plate.AbsoluteSize
	t.near("the circle placeholder is square", size.X, size.Y, 0.01)
	t.check("the circle placeholder has a size", size.X >= 20, size)
	local corner = plate:FindFirstChildOfClass("UICorner")
	t.check("the circle owns a full UICorner", corner ~= nil and corner.CornerRadius == UDim.new(1, 0))
	local sweep = plate:FindFirstChildOfClass("UIGradient")
	t.check("the sweep is a gradient on the rounded plate", sweep ~= nil and sweep.Parent == plate)
	t.check("the sweep runs with motion on", sweep ~= nil and sweep.Enabled == true)
	local first = sweep.Offset.X
	t.settle(20)
	t.check("the sweep moves", sweep.Offset.X ~= first, { first, sweep.Offset.X })
	t.note("circle", { size = size })
end)

add("skeleton-band-contained", { "themes-P1-88" }, function(t)
	local width
	local stage = t.mount(function(UI, Host, Compose)
		width = Compose.cell(0.5)
		return Host.Frame "Offer" {
			Size = UDim2.fromOffset(500, 200),
			BackgroundTransparency = 1,
			UI.Skeleton "A" {
				form = "box",
				Size = function(use)
					return UDim2.new(use(width), 0, 0, 0)
				end,
			},
		}
	end, { size = Vector2.new(600, 400), reducedMotion = false })
	local offer = t.find(stage, "Offer")
	local root = t.find(stage, "A")
	local plate = root:FindFirstChild("Placeholder1")
	local sweep = plate:FindFirstChildOfClass("UIGradient")
	for _, px in { 390, 101, 43.5, 0.5 } do
		width:set(px / 500)
		t.settle(4)
		local low, high = math.huge, -math.huge
		local within, filled = true, true
		for _ = 1, 90 do
			t.settle(1)
			local x = sweep.Offset.X
			low, high = math.min(low, x), math.max(high, x)
			within = within and x >= -1 and x <= 1 and sweep.Offset.Y == 0
			filled = filled
				and math.abs(plate.AbsoluteSize.X - root.AbsoluteSize.X) < 0.01
				and math.abs(plate.AbsolutePosition.X - root.AbsolutePosition.X) < 0.01
		end
		t.near(px .. "px root width is the fractional offer", root.AbsoluteSize.X, px, 0.01)
		t.check(px .. "px the band offset stays inside the placeholder span", within, { low, high })
		t.check(px .. "px the band crosses the whole placeholder", low < -0.8 and high > 0.8, { low, high })
		t.check(px .. "px the placeholder fills the root on every frame", filled)
		t.check(px .. "px the sweep is paint on the placeholder, not a moving object", #plate:GetChildren() == 1)
		local found = t.offenders(root, t.rect(offer))
		t.check(px .. "px nothing paints outside the offer", #found.lateral == 0, found.lateral)
	end
end)

add("skeleton-parent-alignment", { "themes-P1-90" }, function(t)
	for _, align in { "center", "end", "start" } do
		local stage = t.mount(function(UI)
			return UI.VStack "Col" {
				width = "fill",
				align = align,
				UI.Skeleton "One" { form = "line", Size = UDim2.fromOffset(120, 0) },
				UI.Skeleton "Many" { form = "line", lines = 3, Size = UDim2.fromOffset(120, 0) },
			}
		end, { size = Vector2.new(500, 400) })
		local col = t.find(stage, "Col")
		local one, many = t.find(stage, "One"), t.find(stage, "Many")
		local left = col.AbsolutePosition.X
		local expected = if align == "center"
			then left + (col.AbsoluteSize.X - 120) / 2
			elseif align == "end" then left + col.AbsoluteSize.X - 120
			else left
		t.near(align .. " one-line skeleton x", one.AbsolutePosition.X, expected, 0.5)
		t.near(align .. " paragraph skeleton x", many.AbsolutePosition.X, expected, 0.5)
		t.near(align .. " both forms share x", one.AbsolutePosition.X, many.AbsolutePosition.X, 0.01)
		t.near(align .. " one-line width", one.AbsoluteSize.X, 120, 0.01)
		local first, last = many:FindFirstChild("Placeholder1"), many:FindFirstChild("Placeholder3")
		t.near(align .. " paragraph first line x", first.AbsolutePosition.X, many.AbsolutePosition.X, 0.01)
		t.near(align .. " paragraph first line width", first.AbsoluteSize.X, 120, 0.01)
		t.near(align .. " paragraph last line width is sixty percent", last.AbsoluteSize.X, 72, 0.5)
		t.inside(align .. " paragraph last line stays in the paragraph", last, many)
		t.cleanup()
	end
end)

add("stage-not-selectable", { "themes-P1-105" }, function(t)
	local stage = t.mount(function(UI, Host)
		return Host.Frame "Form" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Host.UIListLayout { SortOrder = Enum.SortOrder.LayoutOrder },
			Host.Frame "OnlyStage" {
				Size = UDim2.fromOffset(260, 200),
				BackgroundTransparency = 1,
				LayoutOrder = 1,
				UI.Stage "Scene" {},
			},
			UI.Button "After" { label = "After", LayoutOrder = 2 },
		}
	end, { size = Vector2.new(600, 500) })
	local scene = t.find(stage, "Scene")
	t.check("the stage is a ViewportFrame", scene:IsA("ViewportFrame"))
	t.check("the stage is not selectable", scene.Selectable == false)
	t.check("the stage is not active", scene.Active == false)
	GuiService.SelectedObject = nil
	GuiService:Select(t.find(stage, "OnlyStage"))
	t.settle(2)
	t.check(
		"engine selection finds nothing in a container that holds only a stage",
		GuiService.SelectedObject == nil,
		GuiService.SelectedObject
	)
	GuiService:Select(t.find(stage, "Form"))
	t.settle(2)
	local chosen = GuiService.SelectedObject
	t.check(
		"engine selection passes over the stage to the button",
		chosen ~= nil and chosen:IsDescendantOf(t.find(stage, "After")) or chosen == t.find(stage, "After"),
		chosen
	)
	GuiService.SelectedObject = nil
end)

add("stage-panel-paint", { "themes-P1-107" }, function(t)
	local env
	local stage = t.mount(function(UI, _, _, e)
		env = e
		return UI.Stage "Scene" {}
	end, { size = Vector2.new(400, 300) })
	local scene = t.find(stage, "Scene")
	local package = env.theme:peek()
	t.check("the stage carries the panel style tag", scene:HasTag("facet-panel"))
	local seen = {}
	for _, entry in package.style.themes do
		env.palette:set(entry.name)
		t.settle(4)
		local want = color(paletteOf(package, entry.name).colors.surfaceStrong)
		local got = scene:GetStyled("BackgroundColor3")
		t.check(entry.name .. " stage background is the palette panel color", sameColor(got, want), { got, want })
		t.check(entry.name .. " stage background is opaque", scene:GetStyled("BackgroundTransparency") == 0)
		table.insert(seen, got)
	end
	t.check("two palettes paint two stage colors", #seen >= 2 and not sameColor(seen[1], seen[2]))
end)

add("explicit-gradient-wins-across-swap", { "themes-P3-11" }, function(t)
	local glossy, scifi = themeNamed(t, "glossy_mobile"), themeNamed(t, "scifi_hud")
	local env
	local viewColor = ColorSequence.new(Color3.fromRGB(255, 0, 0), Color3.fromRGB(0, 0, 255))
	local viewAlpha = NumberSequence.new(0.1, 0.3)
	local stage = t.mount(function(UI, Host, _, e)
		env = e
		return Host.Frame "Pair" {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Host.UIListLayout { SortOrder = Enum.SortOrder.LayoutOrder },
			UI.Stage "Card" {
				LayoutOrder = 1,
				Host.UIGradient "ViewGradient" { Color = viewColor, Rotation = 45, Transparency = viewAlpha },
			},
			UI.Stage "Plain" { LayoutOrder = 2 },
		}
	end, { size = Vector2.new(600, 500), theme = glossy })
	local card = t.find(stage, "Card")
	local gradient = card:FindFirstChild("ViewGradient")
	local function verify(label: string)
		local count = 0
		for _, child in card:GetChildren() do
			if child:IsA("UIGradient") then
				count += 1
			end
		end
		t.check(label .. " the card has exactly one real gradient child", count == 1, count)
		t.check(label .. " the view gradient is the same instance", card:FindFirstChild("ViewGradient") == gradient)
		t.check(
			label .. " the view rotation wins",
			gradient:GetStyled("Rotation") == 45,
			gradient:GetStyled("Rotation")
		)
		t.check(label .. " the view colors win", gradient:GetStyled("Color") == viewColor, gradient:GetStyled("Color"))
		t.check(
			label .. " the view transparency wins",
			gradient:GetStyled("Transparency") == viewAlpha,
			gradient:GetStyled("Transparency")
		)
		t.check(
			label .. " the plain sibling has no real gradient",
			t.find(stage, "Plain"):FindFirstChildOfClass("UIGradient") == nil
		)
	end
	t.check("glossy declares a panel gradient", glossy.style.themes[1].extra.chromeGradient.panel ~= nil)
	t.check("scifi declares a panel gradient", scifi.style.themes[1].extra.chromeGradient.panel ~= nil)
	verify("glossy")
	env.palette:set(scifi.style.defaultTheme)
	env.theme:set(scifi)
	t.settle(8)
	verify("after swap to scifi")
	env.palette:set(glossy.style.defaultTheme)
	env.theme:set(glossy)
	t.settle(8)
	verify("after swap back to glossy")
end)

add("skinned-selection-hugs-art", { "themes-P4-15" }, function(t)
	local ornate = themeNamed(t, "fantasy_ornate")
	local stage = t.mount(function(UI)
		return UI.VStack "Col" {
			UI.Button "Skinned" { label = "Ornate" },
		}
	end, { size = Vector2.new(500, 400), theme = ornate, frames = 20 })
	local button = t.find(stage, "Skinned")
	local skin = button:FindFirstChild("Skin", true)
	t.check("the skinned button has theme art", skin ~= nil)
	local art = {}
	if skin then
		for _, node in skin:GetDescendants() do
			if node:IsA("ImageLabel") and t.visible(node) then
				table.insert(art, node)
			end
		end
	end
	t.check("the skin paints image layers", #art > 0, #art)
	local plate
	for _, node in art do
		if
			math.abs(node.AbsoluteSize.X - button.AbsoluteSize.X) < 0.5
			and math.abs(node.AbsoluteSize.Y - button.AbsoluteSize.Y) < 0.5
		then
			plate = node
			break
		end
	end
	t.check("a full-bleed art plate exists", plate ~= nil)
	if plate then
		t.near("the plate left edge is the button left edge", plate.AbsolutePosition.X, button.AbsolutePosition.X, 0.5)
		t.near("the plate top edge is the button top edge", plate.AbsolutePosition.Y, button.AbsolutePosition.Y, 0.5)
	end
	local before = #button:GetDescendants()
	local rect = t.rect(button)
	GuiService.SelectedObject = button
	t.settle(4)
	t.check("the engine selects the control itself", GuiService.SelectedObject == button, GuiService.SelectedObject)
	t.check(
		"selection adds no ring or glow instance",
		#button:GetDescendants() == before,
		{ before, #button:GetDescendants() }
	)
	local after = t.rect(button)
	t.check(
		"selection does not move or resize the hit area",
		after.x == rect.x and after.y == rect.y and after.w == rect.w and after.h == rect.h
	)
	local hits = game:GetService("Players").LocalPlayer.PlayerGui
		:GetGuiObjectsAtPosition(rect.x + rect.w / 2, rect.y + rect.h / 2)
	local hitButton = false
	for _, node in hits do
		if node == button then
			hitButton = true
		end
	end
	t.check("the hit area at the art center is the button", hitButton)
	t.note("button", { rect = { rect.x, rect.y, rect.w, rect.h }, art = #art })
	GuiService.SelectedObject = nil
end)

add("selection-corners-follow-control", { "themes-P5-43" }, function(t)
	local env
	local neutral = t.themes[1].package
	local ornate = themeNamed(t, "fantasy_ornate")
	local stage = t.mount(function(UI, _, _, e)
		env = e
		return UI.VStack "Col" {
			UI.Button "Target" { label = "Target" },
		}
	end, { size = Vector2.new(500, 400), theme = neutral, frames = 20 })
	local button = t.find(stage, "Target")
	GuiService.SelectedObject = button
	t.settle(4)
	t.check("the engine highlight targets the control", GuiService.SelectedObject == button)
	t.note("neutral tags", button:GetTags())
	env.palette:set(ornate.style.defaultTheme)
	env.theme:set(ornate)
	t.settle(10)
	t.check("the highlight stays on the control across a theme swap", GuiService.SelectedObject == button)
	t.note("ornate tags", button:GetTags())
	GuiService.SelectedObject = nil
end)

add("status-count-authored-height", { "themes-P1-117" }, function(t)
	for _, cutout in { false, true } do
		for _, height in { UDim.new(0.5, 0), UDim.new(0, 20), UDim.new(0, 30) } do
			local label = `{if cutout then "cutout" else "plain"} {height.Scale}+{height.Offset}`
			local stage = t.mount(function(UI, Host)
				return Host.Frame "Offer" {
					Size = UDim2.fromOffset(100, 100),
					BackgroundTransparency = 1,
					UI.StatusIndicator "Mark" {
						count = 7,
						cutout = cutout,
						Size = UDim2.new(UDim.new(0, 40), height),
					},
				}
			end, { size = Vector2.new(300, 300) })
			local mark = t.find(stage, "Mark")
			local want = if height.Scale > 0 then 50 else height.Offset
			t.near(label .. " height is the authored height", mark.AbsoluteSize.Y, want, 0.01)
			t.check(
				label .. " the pill is never narrower than tall",
				mark.AbsoluteSize.X >= mark.AbsoluteSize.Y - 0.01,
				mark.AbsoluteSize
			)
			local stroke = mark:FindFirstChild("Cutout")
			t.check(label .. " the cutout is present only when asked", (stroke ~= nil) == cutout)
			local inset = if stroke then stroke.Thickness else 0
			if stroke then
				t.check(
					label .. " the cutout draws inside the box",
					stroke.BorderStrokePosition == Enum.BorderStrokePosition.Inner
				)
			end
			local bounds = mark.TextBounds
			t.check(label .. " the count text is 7", mark.ContentText == "7")
			t.check(
				label .. " the count text fits inside the cutout inset",
				bounds.Y <= mark.AbsoluteSize.Y - 2 * inset + 0.5 and bounds.X <= mark.AbsoluteSize.X - 2 * inset + 0.5,
				{ bounds, mark.AbsoluteSize, inset }
			)
			t.cleanup()
		end
	end
end)

local OFFERS = {
	{ 10, 16 },
	{ 16, 10 },
	{ 16.49, 10.49 },
	{ 16.5, 10.5 },
	{ 16.99, 10.99 },
	{ 10.49, 16.49 },
	{ 10.5, 16.5 },
	{ 10.99, 16.99 },
	{ 10.49, 10.99 },
	{ 10.99, 10.49 },
	{ 0.99, 0.49 },
}

add("status-round-containment", { "themes-P1-120" }, function(t)
	for _, cutout in { false, true } do
		for _, offer in OFFERS do
			local label = `{if cutout then "cutout" else "plain"} {offer[1]}x{offer[2]}`
			local stage = t.mount(function(UI, Host)
				return Host.Frame "Box" {
					Size = UDim2.fromOffset(100, 100),
					BackgroundTransparency = 1,
					Host.Frame "Offer" {
						Size = UDim2.fromScale(offer[1] / 100, offer[2] / 100),
						BackgroundTransparency = 1,
						UI.StatusIndicator "Mark" { form = "ring", cutout = cutout, Size = UDim2.fromScale(1, 1) },
					},
				}
			end, { size = Vector2.new(300, 300), frames = 6 })
			local box, mark = t.find(stage, "Offer"), t.find(stage, "Mark")
			local side = math.min(box.AbsoluteSize.X, box.AbsoluteSize.Y)
			t.near(label .. " the mark is square", mark.AbsoluteSize.X, mark.AbsoluteSize.Y, 0.01)
			t.near(label .. " the mark takes the shorter offered axis", mark.AbsoluteSize.X, side, 0.01)
			t.inside(label .. " the mark stays inside the offer", mark, box, 0.01)
			local corner = mark:FindFirstChildOfClass("UICorner")
			t.check(label .. " the mark is round", corner ~= nil and corner.CornerRadius == UDim.new(1, 0))
			t.cleanup()
		end
	end
	local width, height
	local stage = t.mount(function(UI, Host, Compose)
		width, height = Compose.cell(200), Compose.cell(100)
		return Host.Frame "Offer" {
			Size = function(use)
				return UDim2.fromOffset(use(width), use(height))
			end,
			BackgroundTransparency = 1,
			UI.StatusIndicator "Dot" { form = "dot", Size = UDim2.fromScale(0.5, 0.5) },
			UI.StatusIndicator "Dash" {
				form = "dash",
				Size = UDim2.fromScale(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
			},
		}
	end, { size = Vector2.new(400, 400) })
	for _, dims in { { 200, 100 }, { 60, 200 }, { 200, 100 } } do
		width:set(dims[1])
		height:set(dims[2])
		t.settle(4)
		local offer = t.find(stage, "Offer")
		local dot, dash = t.find(stage, "Dot"), t.find(stage, "Dash")
		local label = `{dims[1]}x{dims[2]}`
		local side = math.min(dims[1], dims[2]) / 2
		t.near(label .. " dot width refits", dot.AbsoluteSize.X, side, 0.01)
		t.near(label .. " dot height refits", dot.AbsoluteSize.Y, side, 0.01)
		local dashWidth = math.min(dims[1] / 2, dims[2] / 2 * 3)
		t.near(label .. " dash width refits", dash.AbsoluteSize.X, dashWidth, 0.01)
		t.near(label .. " dash keeps three to one", dash.AbsoluteSize.X, dash.AbsoluteSize.Y * 3, 0.02)
		t.inside(label .. " dot inside the offer", dot, offer, 0.01)
		t.inside(label .. " dash inside the offer", dash, offer, 0.01)
	end
end)

add("status-cutout-hairline", { "themes-P1-121" }, function(t)
	local pixel = themeNamed(t, "pixel_quest")
	local env
	for _, size in { 8, 10, 11, 13, 16, 40 } do
		for _, form in { "dot", "ring", "square", "dash" } do
			local label = `{form} {size}`
			local stage = t.mount(function(UI, Host, _, e)
				env = e
				return Host.Frame "Offer" {
					Size = UDim2.fromOffset(size * 3, size),
					BackgroundTransparency = 1,
					Host.UIListLayout { FillDirection = Enum.FillDirection.Horizontal },
					UI.StatusIndicator "Mark" { form = form, diameter = size, cutout = true },
					UI.StatusIndicator "Bare" { form = form, diameter = size },
				}
			end, { size = Vector2.new(200, 200), theme = pixel, frames = 6 })
			local mark = t.find(stage, "Mark")
			local bare = t.find(stage, "Bare")
			local stroke = mark:FindFirstChild("Cutout")
			local height = mark.AbsoluteSize.Y
			t.near(label .. " the cutout keeps the footprint width", mark.AbsoluteSize.X, bare.AbsoluteSize.X, 0.01)
			t.near(label .. " the cutout keeps the footprint height", mark.AbsoluteSize.Y, bare.AbsoluteSize.Y, 0.01)
			if form ~= "dash" then
				t.near(label .. " the footprint is the diameter", mark.AbsoluteSize.X, size, 0.01)
			end
			t.check(
				label .. " the cutout is an inner stroke",
				stroke ~= nil and stroke.BorderStrokePosition == Enum.BorderStrokePosition.Inner
			)
			t.check(label .. " the cutout is a one pixel hairline", stroke ~= nil and stroke.Thickness == 1)
			local surface = color(paletteOf(pixel, env.palette:peek()).colors.surface)
			t.check(
				label .. " the cutout paints the surface color",
				stroke ~= nil and sameColor(stroke:GetStyled("Color"), surface)
			)
			local ring = mark:FindFirstChild("Ring")
			local used = 1 + (if ring then ring.Thickness else 0)
			t.check(label .. " the mark keeps a visible center", used * 2 < math.min(size, height), { used, size })
			t.cleanup()
		end
	end
end)

return cases
