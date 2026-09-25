--!strict
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local storage = game:GetService("ReplicatedStorage")

local cases = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function visibleNamed(t: any, root: Instance, name: string): any
	for _, node in root:GetDescendants() do
		if node.Name == name and node:IsA("GuiObject") and t.visible(node) then
			return node
		end
	end
	return nil
end

local function box(Host: any, name: string, w: number, h: number, extra: { [string]: any }?): Frame
	local props: { [string]: any } = { Name = name, Size = UDim2.fromOffset(w, h) }
	for key, value in extra or {} do
		props[key] = value
	end
	return Host.Frame(props)
end

local function mountModule(t: any, kind: string, name: string, size: Vector2, theme: any?): (any, any, string?)
	local built, problem
	local ok, stage = pcall(t.mount, function(UI, Host, Compose, env)
		local context = t.context(UI, Host, Compose, env)
		local module = context.load(kind, name)
		local result = module.build(context)
		built = result
		if type(result) == "function" then
			return result()
		end
		return result.screen()
	end, { size = size, theme = theme, frames = 16 })
	if not ok then
		problem = tostring(stage)
		return nil, nil, problem
	end
	return stage, built, nil
end

local FIT_SIZES = {
	Vector2.new(390, 844),
	Vector2.new(844, 390),
	Vector2.new(1280, 720),
	Vector2.new(1920, 1080),
}

local EXAMPLES = {
	"01_temperature_converter",
	"02_playlist_table",
	"03_settings_sync",
	"04_confirm_dialog",
	"05_word_game",
	"06_tile_game",
	"07_match3",
}

local OFF_SCREEN_BY_DESIGN = {
	world_markers = true,
	hud = true,
	outpost_terminal = true,
}

local function fitRun(t: any, kind: string, name: string, size: Vector2, theme: any, label: string)
	local where = `{label} {kind}/{name} {size.X}x{size.Y}`
	local stage, _, problem = mountModule(t, kind, name, size, theme)
	t.check(where .. " mounts", stage ~= nil, problem and string.sub(problem, 1, 300))
	if not stage then
		t.cleanup()
		return
	end
	t.settle(10)
	local found = t.offenders(stage, stage)
	if #found.lateral + #found.clipped > 0 then
		t.settle(30)
		found = t.offenders(stage, stage)
	end
	local zero = {}
	for _, node in stage:GetDescendants() do
		if node:IsA("GuiButton") and t.visible(node) and node.Active and node.Selectable then
			if node.AbsoluteSize.X < 1 or node.AbsoluteSize.Y < 1 then
				table.insert(zero, node.Name)
			end
		end
	end
	if not OFF_SCREEN_BY_DESIGN[name] then
		t.check(where .. " nothing crosses a lateral edge", #found.lateral == 0, found.lateral)
	else
		t.note(where .. " lateral", #found.lateral)
	end
	t.check(where .. " no undisclosed text clip", #found.clipped == 0, found.clipped)
	t.check(where .. " no visible selectable control has a zero rectangle", #zero == 0, zero)
	t.cleanup()
end

add("every-scenario-and-example-fits", {
	"mech2-89",
	"apps-251",
	"apps2-16",
	"apps2-123",
	"apps-248",
	"themes-P5-39",
	"navigation-2-56",
	"navigation-3-30",
	"apps2-60",
	"apps2-64",
	"apps2-70",
	"apps2-58",
	"apps2-54",
	"navigation-3-57",
	"themes-P1-73",
	"apps2-98",
	"apps-63",
	"apps-88",
	"apps-30",
}, function(t)
	local registry = (require :: any)(storage:WaitForChild("FacetScenarios"))
	local neutral = t.themes[1]
	for _, size in FIT_SIZES do
		for _, name in registry.order do
			fitRun(t, "scenario", name, size, neutral.package, neutral.name)
		end
		for _, name in EXAMPLES do
			fitRun(t, "example", name, size, neutral.package, neutral.name)
		end
	end
	for index = 2, #t.themes do
		local theme = t.themes[index]
		for _, name in registry.order do
			fitRun(t, "scenario", name, Vector2.new(1280, 720), theme.package, theme.name)
		end
		for _, name in EXAMPLES do
			fitRun(t, "example", name, Vector2.new(1280, 720), theme.package, theme.name)
		end
	end
	t.note("preferred text size", t.environment.preferredTextSize)
end)

add("scroll-gutter-and-window", { "mech3-29", "mech3-32", "apps2-109", "apps-230", "mech3-21" }, function(t)
	local count
	local stage = t.mount(function(UI, _, Compose)
		count = Compose.cell(20)
		return UI.ScrollView "Scroll" {
			width = 240,
			height = 200,
			align = "stretch",
			Compose.keyed({
				from = function(use)
					local list = {}
					for index = 1, use(count) do
						list[index] = { id = tostring(index) }
					end
					return list
				end,
				key = function(item)
					return item.id
				end,
				render = function(item, index)
					return UI.Button({
						Name = "Row" .. item:peek().id,
						label = "Row " .. item:peek().id,
						LayoutOrder = index,
					})
				end,
			}),
		}
	end, { size = Vector2.new(400, 400), frames = 16 })
	local scroll = t.find(stage, "Scroll")
	t.stable(scroll)
	local thickness = scroll:GetStyled("ScrollBarThickness")
	t.check("overflowing content scrolls", scroll.AbsoluteCanvasSize.Y > scroll.AbsoluteWindowSize.Y, {
		canvas = scroll.AbsoluteCanvasSize,
		window = scroll.AbsoluteWindowSize,
	})
	t.near("the bar reserves its gutter", scroll.AbsoluteWindowSize.X, 240 - thickness, 0.5)
	local row = t.find(scroll, "Row1")
	t.check(
		"rows stay out of the gutter",
		row ~= nil and row.AbsoluteSize.X <= scroll.AbsoluteWindowSize.X + 0.5,
		row and row.AbsoluteSize
	)
	t.near("stretched rows fill the window", row and row.AbsoluteSize.X or 0, scroll.AbsoluteWindowSize.X, 1)
	t.near(
		"the canvas never exceeds the window across the axis",
		scroll.AbsoluteCanvasSize.X,
		scroll.AbsoluteWindowSize.X,
		0.5
	)
	count:set(2)
	t.stable(scroll)
	t.near("without overflow the gutter is released", scroll.AbsoluteWindowSize.X, 240, 0.5)
	row = t.find(scroll, "Row1")
	t.near("rows take the released gutter", row and row.AbsoluteSize.X or 0, 240, 1)
	t.check(
		"a short list does not scroll",
		scroll.AbsoluteCanvasSize.Y <= scroll.AbsoluteWindowSize.Y + 0.5,
		scroll.AbsoluteCanvasSize
	)
	t.near("the height stays fixed across the flip", scroll.AbsoluteSize.Y, 200, 0.5)
	local clip = t.rect(scroll)
	local outside = 0
	count:set(20)
	t.stable(scroll)
	for _, node in scroll:GetDescendants() do
		if node:IsA("GuiObject") and t.visible(node) then
			local seen = t.clipped(node)
			if seen and (seen.y < clip.y - 0.5 or seen.b > clip.b + 0.5) then
				outside += 1
			end
		end
	end
	t.check("the scroll window clips partial rows", outside == 0, outside)
end)

add("grid-hugs-its-lines", { "mech2-03" }, function(t)
	for _, count in { 1, 3, 4, 7, 9 } do
		local stage = t.mount(function(UI, Host)
			local cells = {}
			for index = 1, count do
				table.insert(cells, box(Host, "Cell" .. index, 0, 0))
			end
			return UI.Grid "Grid" {
				columns = 3,
				gap = 8,
				cellHeight = 40,
				Size = UDim2.fromOffset(316, 0),
				table.unpack(cells),
			}
		end, { size = Vector2.new(400, 600) })
		local grid = t.find(stage, "Grid")
		t.stable(grid)
		local lines = math.ceil(count / 3)
		t.near(`{count} cells hug {lines} lines`, grid.AbsoluteSize.Y, lines * 40 + (lines - 1) * 8, 1)
		local last = t.find(stage, "Cell" .. count)
		t.inside(`{count} cells: the last cell inside the grid`, last, grid, 0.5)
		t.near(`{count} cells: cell width fills a third`, last.AbsoluteSize.X, (316 - 16) / 3, 1)
		t.cleanup()
	end
end)

add(
	"text-degrade-cascade",
	{ "mech3-66", "inputs-64", "inputs-208", "paint-149", "themes-P5-06", "mech2-45", "paint-134" },
	function(t)
		local width
		local stage = t.mount(function(UI, Host, Compose)
			width = Compose.cell(360)
			return Host.Frame "Column" {
				Size = function(use)
					return UDim2.fromOffset(use(width), 400)
				end,
				BackgroundTransparency = 1,
				Host.UIListLayout({
					SortOrder = Enum.SortOrder.LayoutOrder,
					HorizontalFlex = Enum.UIFlexAlignment.Fill,
				}),
				UI.Text({
					Name = "Wrap",
					text = string.rep("Wrap this sentence. ", 6),
					TextWrapped = true,
					LayoutOrder = 1,
				}),
				UI.Text({
					Name = "Cut",
					text = string.rep("Truncate this sentence. ", 6),
					TextWrapped = false,
					TextTruncate = Enum.TextTruncate.AtEnd,
					AutomaticSize = Enum.AutomaticSize.Y,
					Size = UDim2.new(1, 0, 0, 0),
					LayoutOrder = 2,
				}),
				UI.Text({
					Name = "Unknown",
					text = "Unknown family text",
					FontFace = Font.new("rbxasset://fonts/families/DoesNotExist.json"),
					LayoutOrder = 3,
				}),
				UI.Text({
					Name = "Rtl",
					text = "مرحبا بالعالم",
					TextDirection = Enum.TextDirection.RightToLeft,
					LayoutOrder = 4,
				}),
			}
		end, { size = Vector2.new(600, 500), frames = 16 })
		local wrap, cut, unknown, rtl =
			t.find(stage, "Wrap"), t.find(stage, "Cut"), t.find(stage, "Unknown"), t.find(stage, "Rtl")
		t.stable(wrap)
		local lineHeight = wrap:GetStyled("TextSize")
		local tall = wrap.AbsoluteSize.Y
		t.check(
			"a wrapping label wraps before it clips",
			wrap.TextFits and tall > lineHeight * 1.5,
			{ size = wrap.AbsoluteSize, bounds = wrap.TextBounds }
		)
		t.inside("the wrapped label stays inside its column", wrap, t.find(stage, "Column"), 0.5)
		t.check(
			"a truncating label discloses the cut",
			cut:GetStyled("TextTruncate") == Enum.TextTruncate.AtEnd,
			cut:GetStyled("TextTruncate")
		)
		t.check("a truncating label stays one line", cut.AbsoluteSize.Y < lineHeight * 2, cut.AbsoluteSize)
		t.check(
			"an unknown font family still fits",
			unknown.TextFits and unknown.AbsoluteSize.X > 0,
			unknown.TextBounds
		)
		t.check(
			"right-to-left text keeps its direction",
			rtl.TextDirection == Enum.TextDirection.RightToLeft and rtl.TextFits,
			rtl.TextBounds
		)
		t.near("measured bounds match the painted size", wrap.TextBounds.Y, wrap.AbsoluteSize.Y, 1)
		width:set(200)
		t.stable(wrap)
		t.check(
			"the wrapped label follows a narrower width",
			wrap.AbsoluteSize.Y > tall and wrap.AbsoluteSize.X <= 200.5,
			wrap.AbsoluteSize
		)
		t.check("the wrapped label still fits", wrap.TextFits, wrap.TextBounds)
	end
)

add(
	"safe-area-and-topbar",
	{ "mech1-09", "inputs-142", "mech3-16", "apps2-96", "apps-216", "apps-207", "navigation-1-68" },
	function(t)
		local gui = Players.LocalPlayer.PlayerGui:FindFirstChild("FacetGallery") :: ScreenGui?
		t.check("the gallery ScreenGui is live", gui ~= nil)
		if not gui then
			return
		end
		local api = workspace:FindFirstChild("FacetShowcaseAPI") :: any
		local inset = GuiService:GetGuiInset()
		local topbar = GuiService.TopbarInset
		t.note("gui inset", inset)
		t.note("topbar inset", { topbar.Min, topbar.Max })
		t.note("screen insets", tostring(gui.ScreenInsets))
		t.check(
			"the gallery keeps the core safe insets",
			gui.ScreenInsets == Enum.ScreenInsets.CoreUISafeInsets,
			tostring(gui.ScreenInsets)
		)
		for _, demo in { "all-controls", "hud", "radial-menu" } do
			if api then
				api:Invoke("show", demo)
			end
			t.settle(30)
			local layer = t.rect(gui)
			t.check(
				`{demo} layer starts below the topbar band`,
				layer.y >= topbar.Max.Y - 0.5 or inset.Y > 0,
				{ layer = layer.y, topbar = topbar.Max.Y }
			)
			local found = t.offenders(gui, layer)
			t.check(`{demo} nothing leaves the safe layer sideways`, #found.lateral == 0, found.lateral)
			t.check(`{demo} nothing leaves the safe layer vertically`, #found.vertical == 0, found.vertical)
		end
		if api then
			api:Invoke("show", "all-controls")
		end
	end
)

add(
	"sibling-order-and-hit-testing",
	{ "paint-81", "mech2-83", "navigation-2-64", "themes-P4-04", "themes-P4-17", "paint-124" },
	function(t)
		local playerGui = Players.LocalPlayer.PlayerGui
		local inset = GuiService:GetGuiInset()
		local function top(at: Vector2): { string }
			local names = {}
			for _, node in playerGui:GetGuiObjectsAtPosition(at.X, at.Y) do
				table.insert(names, node.Name)
			end
			return names
		end
		local stage = t.mount(function(UI, Host)
			return Host.Frame "Pair" {
				Size = UDim2.fromOffset(400, 300),
				BackgroundTransparency = 1,
				UI.Button "Low" {
					label = "Low",
					Position = UDim2.fromOffset(20, 20),
					Size = UDim2.fromOffset(160, 60),
					ZIndex = 1,
				},
				UI.Button "High" {
					label = "High",
					Position = UDim2.fromOffset(80, 40),
					Size = UDim2.fromOffset(160, 60),
					ZIndex = 2,
				},
			}
		end, { size = Vector2.new(800, 600), frames = 12 })
		local high = t.find(stage, "High")
		local hits = top(Vector2.new(high.AbsolutePosition.X + 20, high.AbsolutePosition.Y + 10))
		local highAt, lowAt = table.find(hits, "High"), table.find(hits, "Low")
		t.check(
			"the higher ZIndex sibling is hit first where siblings overlap",
			highAt ~= nil and (lowAt == nil or highAt < lowAt),
			hits
		)
		t.cleanup()
		stage = t.mount(function(UI, Host, Compose)
			return Host.Frame "Base" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				UI.Button "Behind" { label = "Behind", Size = UDim2.fromOffset(200, 60) },
				UI.Alert({
					isPresented = Compose.cell(true),
					title = "On top",
					actions = { { id = "ok", label = "OK" } },
				}),
			}
		end, { size = Vector2.new(800, 600), frames = 20 })
		local panel = visibleNamed(t, stage, "AlertPanel")
		if panel then
			t.stable(panel)
			local behind = t.find(stage, "Behind")
			local b = t.rect(behind)
			hits = top(Vector2.new(b.x + b.w / 2, b.y + b.h / 2))
			local scrimAt, behindAt = table.find(hits, "DismissOutside"), table.find(hits, "Behind")
			t.check(
				"the scrim is hit before the covered background",
				scrimAt ~= nil and (behindAt == nil or scrimAt < behindAt),
				hits
			)
			local scrim = visibleNamed(t, stage, "DismissOutside")
			t.check(
				"the panel paints above its scrim",
				scrim ~= nil and panel.ZIndex > scrim.ZIndex,
				{ panel = panel.ZIndex, scrim = scrim and scrim.ZIndex }
			)
		else
			t.check("the alert shows", false)
		end
		t.cleanup()
		local skinned
		for _, theme in t.themes do
			if theme.name == "fantasy_ornate" then
				skinned = theme
			end
		end
		if skinned then
			stage = t.mount(function(UI)
				return UI.Button "Art" { label = "Art", Size = UDim2.fromOffset(200, 60) }
			end, { size = Vector2.new(800, 600), theme = skinned.package, frames = 12 })
			local art = t.find(stage, "Art")
			local r = t.rect(art)
			hits = top(Vector2.new(r.x + r.w / 2, r.y + r.h / 2))
			local artAt = table.find(hits, "Art")
			t.note("hits over a skinned button", hits)
			local stealing = {}
			for _, node in playerGui:GetGuiObjectsAtPosition(r.x + r.w / 2, r.y + r.h / 2) do
				if node == art then
					break
				end
				if node:IsA("GuiButton") or node.Active or node.Selectable then
					table.insert(stealing, node.Name)
				end
			end
			t.check("the skinned control is under the point", artAt ~= nil, hits)
			t.check("no art layer above the control takes input", #stealing == 0, stealing)
			t.cleanup()
		end
		local sizes = {}
		for _, shadow in { false, true } do
			stage = t.mount(function(_, Host)
				return Host.Frame "Row" {
					Size = UDim2.fromOffset(400, 100),
					BackgroundTransparency = 1,
					Host.UIListLayout({ FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }),
					Host.Frame "Plate" {
						Size = UDim2.fromOffset(120, 60),
						table.unpack(if shadow then { Host.UIShadow({}) } else {}),
					},
					box(Host, "Next", 40, 40),
				}
			end, { size = Vector2.new(500, 200), frames = 8 })
			sizes[shadow] = t.find(stage, "Next").AbsolutePosition.X
			t.cleanup()
		end
		t.near("a shadow does not enter layout", sizes[true], sizes[false], 0.01)
	end
)

return cases
