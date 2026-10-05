--!strict

type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type Case = {
	id: string,
	contracts: { string },
	run: ((any) -> ())?,
	setup: ((any) -> any)?,
	steps: { [string]: (any, any) -> () }?,
	keepGallery: boolean?,
}
local cases: { Case } = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local function cell(Host: any, name: string, size: UDim2): any
	return Host.Frame(name)({ Size = size, BackgroundTransparency = 0.5 })
end

add("scroll-view-canvas-covers-rows-and-gaps", { "apps-224" }, function(t: any)
	local stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
		return UI.ScrollView "List" {
			gap = 10,
			Size = UDim2.fromOffset(300, 100),
			cell(Host, "A", UDim2.fromOffset(300, 40)) :: unknown,
			cell(Host, "B", UDim2.fromOffset(300, 40)),
			cell(Host, "C", UDim2.fromOffset(300, 40)),
		}
	end, { size = Vector2.new(400, 400) })
	t.settle(10)
	local list = t.find(stage, "List")
	local a, c = t.find(list, "A"), t.find(list, "C")
	local padding = list:FindFirstChildWhichIsA("UIPadding")
	local vertical = if padding
		then padding:GetStyled("PaddingTop").Offset + padding:GetStyled("PaddingBottom").Offset
		else 0
	t.near("the canvas holds three rows and two gaps", list.AbsoluteCanvasSize.Y, 140 + vertical, 1)
	t.near("rows advance by their height plus the gap", c.AbsolutePosition.Y - a.AbsolutePosition.Y, 100, 1)
	t.check("the overflowing list scrolls", list.AbsoluteCanvasSize.Y > list.AbsoluteWindowSize.Y)
end)

add("horizontal-scroll-view-steps-along-x", { "apps-226" }, function(t: any)
	local stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
		local cells = {}
		for index = 1, 5 do
			table.insert(cells, cell(Host, "Cell" .. index, UDim2.new(0, 60, 1, 0)))
		end
		return UI.ScrollView "Rail" {
			axis = "x" :: "x",
			gap = 10,
			Size = UDim2.fromOffset(200, 120),
			table.unpack((cells :: unknown) :: { unknown }),
		}
	end, { size = Vector2.new(400, 400) })
	t.settle(10)
	local rail = t.find(stage, "Rail")
	local first, second = t.find(rail, "Cell1"), t.find(rail, "Cell2")
	local padding = rail:FindFirstChildWhichIsA("UIPadding")
	local horizontal = if padding
		then padding:GetStyled("PaddingLeft").Offset + padding:GetStyled("PaddingRight").Offset
		else 0
	t.near("cells advance along x by width plus gap", second.AbsolutePosition.X - first.AbsolutePosition.X, 70, 1)
	t.near("the canvas extent is horizontal", rail.AbsoluteCanvasSize.X, 340 + horizontal, 1)
	t.near("a full-height cell fills the window height", first.AbsoluteSize.Y, rail.AbsoluteWindowSize.Y, 1)
	t.check("the rail scrolls sideways, not down", rail.AbsoluteCanvasSize.Y <= rail.AbsoluteWindowSize.Y + 1, {
		canvas = rail.AbsoluteCanvasSize,
		window = rail.AbsoluteWindowSize,
	})
end)

add("fill-stack-preserves-overflow-and-recovers", {}, function(t: any)
	for _, theme in t.themes do
		local C = t.Facet.Compose
		local size = C.cell(Vector2.new(390, 600))
		local stage = t.mount(function(UI: FacetControls, Host: RobloxHost)
			return UI.ScrollView "Viewport" {
				UI.VStack "Page" {
					width = "fill" :: "fill",
					height = "fill" :: "fill",
					gap = 0,
					UI.fill() :: unknown,
					Host.Frame { Name = "Header", Size = UDim2.new(1, 0, 0, 500) },
					UI.VStack "Pane" {
						width = "fill" :: "fill",
						height = "fill" :: "fill",
						UI.fill() :: unknown,
						Host.UISizeConstraint { MinSize = Vector2.new(0, 320) },
						UI.Button { Name = "Last", label = "Last item" },
					},
				},
			}
		end, { theme = theme.package, size = size })
		local viewport, page, pane = t.find(stage, "Viewport"), t.find(stage, "Page"), t.find(stage, "Pane")
		for _, height in { 600, 1000, 400, 600 } do
			size:set(Vector2.new(390, height))
			t.settle(30)
			local label = theme.name .. " height " .. height
			t.check(label .. " pane minimum", pane.AbsoluteSize.Y >= 320)
			t.check(label .. " page covers content", page.AbsoluteSize.Y >= 820)
			t.check(label .. " canvas covers page", viewport.AbsoluteCanvasSize.Y >= page.AbsoluteSize.Y - 1)
			local before = page.AbsoluteSize.Y
			t.settle(30)
			t.near(label .. " size settles", page.AbsoluteSize.Y, before)
			viewport.CanvasPosition = Vector2.new(0, 10000)
			t.settle()
			t.check(
				label .. " pane bottom reachable",
				pane.AbsolutePosition.Y + pane.AbsoluteSize.Y
					<= viewport.AbsolutePosition.Y + viewport.AbsoluteWindowSize.Y + 1
			)
		end
	end
end)

add("sheet-content-clears-theme-frame", {}, function(t: any)
	for _, theme in t.themes do
		if theme.name ~= "Neutral" and theme.name ~= "fantasy_parchment" and theme.name ~= "fantasy_ornate" then
			continue
		end
		for _, placement in { "bottom", "side" } do
			local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, C: any)
				return UI.Sheet {
					title = "Search & options with a title that wraps",
					placement = placement :: any,
					isPresented = C.cell(true),
					detent = C.cell("large"),
					detents = { "large" :: "large" },
					contentInset = "none" :: "none",
					content = function(): Instance
						return Host.Frame { Size = UDim2.new(1, 0, 0, 1000) }
					end,
					actions = { { id = "Done", label = "Done", onActivate = function() end } },
				}
			end, { theme = theme.package, size = Vector2.new(390, 640) })
			t.settle(20)
			local panel = t.find(stage.Parent, "SheetPanel")
			local title = t.find(panel, "Title")
			title.TextSize = 32
			t.settle(12)
			t.inside(theme.name .. placement .. " enlarged title", title, title.Parent)
			local carve = ((theme.package.chrome or {}).panel or {}).contentInsets or {}
			for _, name in { "Header", "SheetContent", "Actions" } do
				local node = t.find(panel, name)
				local label = theme.name .. " " .. placement .. " " .. name
				t.check(
					label .. " clears left art and spacing",
					node.AbsolutePosition.X - panel.AbsolutePosition.X >= (carve.left or 0) + 16 - 1
				)
				t.check(
					label .. " clears right art and spacing",
					node.AbsolutePosition.X + node.AbsoluteSize.X
						<= panel.AbsolutePosition.X + panel.AbsoluteSize.X - (carve.right or 0) - 16 + 1
				)
				t.inside(label .. " stays in panel", node, panel)
			end
		end
	end
end)

return cases
