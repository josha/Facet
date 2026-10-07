--!strict

type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
local Players = game:GetService("Players")
local storage = game:GetService("ReplicatedStorage")

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

local function api(command: string, argument: any): any
	return (workspace:WaitForChild("FacetShowcaseAPI") :: any):Invoke(command, argument)
end

local function gallery(): ScreenGui
	return (Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui):WaitForChild("FacetGallery") :: ScreenGui
end

local function screenRect(t: any): any
	local layer = gallery()
	return t.rect(layer)
end

local function visibleNamed(t: any, root: Instance, name: string): any
	for _, node in root:GetDescendants() do
		if node.Name == name and node:IsA("GuiObject") and t.visible(node) then
			return node
		end
	end
	return nil
end

local function showing(t: any, id: string)
	local result = api("show", id)
	t.check(`gallery shows {id}`, result.ok == true and result.current == id, result)
	t.settle(20)
end

local function toolbarChecks(t: any, where: string, page: any)
	local scroll = t.find(page, "ToolbarScroll")
	local collection = t.find(page, "Collection")
	if not (scroll and collection) then
		t.check(where .. " toolbar and collection mounted", false)
		return
	end
	local p, s, c = t.rect(page), t.rect(scroll), t.rect(collection)
	local side = c.x >= s.r - 0.5
	t.note(where .. " arrangement", {
		side = side,
		page = { p.w, p.h },
		toolbar = { s.w, s.h },
		canvas = scroll.AbsoluteCanvasSize,
		collection = { c.w, c.h },
	})
	t.inside(where .. " toolbar inside the page", s, p, 1)
	t.inside(where .. " collection inside the page", c, p, 1)
	local usable = math.min(120, p.h * 0.5)
	t.check(where .. " collection keeps a usable height", c.h >= usable - 0.5, { height = c.h, floor = usable })
	t.check(where .. " collection keeps a usable width", c.w >= math.min(200, p.w * 0.5) - 0.5, c.w)
	local canvas = scroll.AbsoluteCanvasSize
	for _, button in scroll:GetDescendants() do
		if button:IsA("GuiButton") and t.visible(button) then
			local b = t.rect(button)
			local top = b.y - s.y + scroll.CanvasPosition.Y
			t.check(
				`{where} {button.Name} inside the toolbar width`,
				b.x >= s.x - 0.5 and b.r <= s.r + 0.5,
				{ button = { b.x, b.r }, toolbar = { s.x, s.r } }
			)
			t.check(
				`{where} {button.Name} reachable in the toolbar canvas`,
				top >= -0.5 and top + b.h <= math.max(canvas.Y, s.h) + 0.5,
				{ top = top, height = b.h, canvas = canvas.Y }
			)
			t.check(`{where} {button.Name} meets the 44px height floor`, b.h >= 43.5, b.h)
			local label = if button:IsA("TextButton") then button else button:FindFirstChildWhichIsA("TextLabel", true)
			if label and (label :: any).Text ~= "" then
				t.check(`{where} {button.Name} label fits`, (label :: any).TextFits, {
					bounds = (label :: any).TextBounds,
					size = (label :: any).AbsoluteSize,
				})
			end
		end
	end
	if collection:IsA("ScrollingFrame") then
		local before = collection.CanvasPosition
		collection.CanvasPosition = Vector2.new(0, 200)
		t.settle(10)
		local moved = collection.CanvasPosition
		t.check(
			where .. " collection scrolls",
			moved.Y > before.Y or moved.X > before.X or collection.AbsoluteCanvasSize.Y <= c.h,
			{
				before = before,
				after = moved,
				canvas = collection.AbsoluteCanvasSize,
			}
		)
		collection.CanvasPosition = before
	end
end

add("collection-toolbar-in-gallery", { "risk:collection-toolbar" }, function(t)
	showing(t, "collections")
	local scroll = visibleNamed(t, gallery(), "ToolbarScroll")
	if not scroll then
		t.check("collection toolbar visible in the gallery", false)
		return
	end
	toolbarChecks(t, "gallery Mail list", scroll.Parent)
	t.note("gallery page size", scroll.Parent.AbsoluteSize)
end)

add("collection-toolbar-variants", { "risk:collection-toolbar" }, function(t)
	showing(t, "collections")
	local reference = visibleNamed(t, gallery(), "ToolbarScroll")
	local size = if reference then reference.Parent.AbsoluteSize else Vector2.new(644, 213)
	local folder = storage:WaitForChild("FacetScenarios")
	local demo = (require :: any)(folder:WaitForChild("collection_demo"))
	local variants: { { name: string, module: string?, build: ((any) -> any)? } } = {
		{
			name = "Mail table",
			build = function(ctx)
				return demo(ctx, {
					name = "Mail_table",
					title = "Mail",
					rows = {
						{
							id = "m1",
							from = "Ari",
							subject = "Kickoff",
							preview = "Recap",
							read = false,
							flagged = false,
						},
					},
					count = 1,
					actions = true,
					mail = true,
					table = true,
				})
			end,
		},
		{ name = "Measured heights", module = "measured_extents" },
		{ name = "Declared heights", module = "variable_extents" },
		{ name = "Grid", module = "virtual_grid" },
		{ name = "Sideways grid", module = "virtual_hgrid" },
		{ name = "Large table", module = "table_virtualized" },
	}
	for _, variant in variants do
		local stage = t.mount(function(UI: FacetControls, Host: RobloxHost, Compose: ComposeModule, env)
			local ctx = {
				Facet = t.Facet,
				Compose = Compose,
				runtime = env.runtime,
				Host = Host,
				UI = UI,
				viewport = env.viewport,
				types = env.types,
				guiService = game:GetService("GuiService"),
				runService = game:GetService("RunService"),
			}
			local built = if variant.module
				then (require :: any)(folder:WaitForChild(variant.module)).build(ctx)
				else assert(variant.build)(ctx)
			return built.screen()
		end, { size = size, frames = 20 })
		local scroll = t.find(stage, "ToolbarScroll")
		if scroll then
			toolbarChecks(t, variant.name, scroll.Parent)
		else
			t.check(variant.name .. " toolbar mounted", false)
		end
		t.cleanup()
	end
end)

add("shell-reservation-and-settings", { "risk:shell-reservation" }, function(t)
	showing(t, "all-controls")
	local names = {}
	for _, theme in t.themes do
		table.insert(names, theme.name)
	end
	for _, name in names do
		local result = api("theme", name)
		if not result.ok then
			t.note(name .. " theme", "not offered by the gallery")
			continue
		end
		t.settle(20)
		local shell = gallery():FindFirstChild("Gallery", true)
		local toolbar = shell and shell:FindFirstChild("Toolbar")
		local screen = screenRect(t)
		local trigger = if toolbar and t.visible(toolbar) then visibleNamed(t, toolbar, "Showcase") else nil
		if not (shell and toolbar and trigger) then
			t.check(name .. " Showcase control visible", false, { shell = shell ~= nil, toolbar = toolbar ~= nil })
			continue
		end
		local s = t.rect(trigger)
		t.inside(name .. " Showcase control inside the screen", s, screen, 1)
		t.check(name .. " Showcase control is selectable", trigger.Selectable and trigger.Active, {
			selectable = trigger.Selectable,
			active = trigger.Active,
		})
		t.note(name .. " Showcase control height", s.h)
		local label = trigger:IsA("TextButton") and trigger or trigger:FindFirstChildWhichIsA("TextLabel", true)
		if label then
			t.check(name .. " Showcase control label fits", (label :: any).TextFits, (label :: any).TextBounds)
		end
		local bar = t.rect(toolbar)
		t.inside(name .. " Showcase control inside the reserved toolbar", s, bar, 1)
		local demos = shell:FindFirstChild("Demos")
		t.check(name .. " content mounted under the toolbar", demos ~= nil)
		if demos then
			t.check(name .. " content starts below the toolbar", t.rect(demos).y >= bar.b - 0.5, {
				content = t.rect(demos).y,
				toolbar = bar.b,
			})
		end
		t.note(name .. " toolbar", { height = bar.h, control = { s.w, s.h } })
		local opened = api("panel", "settings")
		t.check(name .. " Settings section opens", opened.ok == true and opened.panel == "settings", opened)
		t.settle(20)
		local card = visibleNamed(t, gallery(), "ShowcasePanel")
		local settings = card and visibleNamed(t, card, "Settings")
		t.check(name .. " Settings content visible", settings ~= nil, { panel = card ~= nil })
		if card then
			local surface = card:FindFirstAncestor("Expanded")
			local scroll = card:FindFirstAncestor("ExpandedScroll")
			t.check(name .. " Settings uses the collapsible scroll form", surface ~= nil and scroll ~= nil)
			if surface and scroll and scroll:IsA("ScrollingFrame") then
				t.inside(name .. " Settings surface inside the screen", surface, screen, 1)
				t.inside(
					name .. " Settings surface includes the Showcase anchor",
					{ x = s.x + s.w / 2, y = s.y + s.h / 2, w = 0, h = 0, r = s.x + s.w / 2, b = s.y + s.h / 2 },
					surface,
					1
				)
				t.inside(name .. " Settings scroll window inside the surface", scroll, surface, 1)
				local content = t.rect(card)
				local window = t.rect(scroll)
				local bottom = content.b - window.y + scroll.CanvasPosition.Y
				t.check(
					name .. " Settings content reachable in the scroll canvas",
					bottom <= math.max(scroll.AbsoluteCanvasSize.Y, window.h) + 1,
					{ bottom = bottom, canvas = scroll.AbsoluteCanvasSize.Y }
				)
			end
		end
		if api("report", nil).panel ~= nil then
			api("panel", nil)
		end
		t.settle(40)
		t.check(name .. " Settings panel closes", visibleNamed(t, gallery(), "ShowcasePanel") == nil)
	end
	api("theme", "Neutral")
	t.settle(10)
end)

add("word-game-fits-the-phone", { "apps2-24" }, function(t)
	showing(t, "ex05")
	local root = gallery()
	local board = visibleNamed(t, root, "board")
	local page = board and board:FindFirstAncestor("page")
	if not (board and page) then
		t.check("word game board mounted", false)
		return
	end
	t.check("word game page is a native ScrollingFrame", page:IsA("ScrollingFrame"), page.ClassName)
	local p, b = t.rect(page), t.rect(board)
	t.check(
		"board inside the page width",
		b.x >= p.x - 0.5 and b.r <= p.r + 0.5,
		{ board = { b.x, b.r }, page = { p.x, p.r } }
	)
	local count, rows, columns = 0, {}, {}
	for _, tile in board:GetChildren() do
		local r, c = string.match(tile.Name, "^tile(%d+)_(%d+)$")
		if r and tile:IsA("GuiObject") then
			count += 1
			rows[r] = true
			columns[c] = true
			local x = t.rect(tile)
			t.near(`tile {r},{c} is square`, x.w, x.h, 1)
			t.check(`tile {r},{c} inside the board`, x.x >= b.x - 0.5 and x.r <= b.r + 0.5, { tile = { x.x, x.r } })
		end
	end
	local rowCount, columnCount = 0, 0
	for _ in rows do
		rowCount += 1
	end
	for _ in columns do
		columnCount += 1
	end
	t.check("board is 7 rows by 6 columns", count == 42 and rowCount == 7 and columnCount == 6, {
		tiles = count,
		rows = rowCount,
		columns = columnCount,
	})
	for row = 1, 3 do
		local keys = visibleNamed(t, root, "kbrow" .. row)
		if keys then
			local k = t.rect(keys)
			t.check(`keyboard row {row} inside the page width`, k.x >= p.x - 0.5 and k.r <= p.r + 0.5, {
				row = { k.x, k.r },
				page = { p.x, p.r },
			})
			for _, key in keys:GetChildren() do
				if key:IsA("GuiButton") then
					local x = t.rect(key)
					t.check(
						`key {key.Name} inside its row`,
						x.x >= k.x - 0.5 and x.r <= k.r + 0.5,
						{ key = { x.x, x.r } }
					)
				end
			end
		end
	end
	local canvas = page.AbsoluteCanvasSize
	t.check("page scrolls to its last content", canvas.Y >= p.h - 0.5, { canvas = canvas.Y, window = p.h })
end)

return cases
