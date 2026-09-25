--!strict
local cases = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local ZONES = { "Tasks", "Clock", "Rail", "Health", "Actions", "Feed", "Readout", "Weapon", "Rounds", "HudBody" }
local SIZES = {
	Vector2.new(1079, 809),
	Vector2.new(360, 691),
	Vector2.new(691, 360),
	Vector2.new(320, 240),
}

local function label(size: Vector2): string
	return `{size.X}x{size.Y}`
end

local function hud(t: any, size: any): (any, any)
	local built
	local stage = t.mount(function(UI, Host, Compose, env)
		built = t.scenario("hud").build(t.context(UI, Host, Compose, env))
		return built.screen()
	end, { size = size, frames = 12 })
	return stage, built
end

local function snapshot(t: any, stage: any): { [string]: any }
	local origin = stage.AbsolutePosition
	local result = {}
	for _, name in ZONES do
		local node = t.find(stage, name)
		if node and node:IsA("GuiObject") then
			result[name] = {
				x = node.AbsolutePosition.X - origin.X,
				y = node.AbsolutePosition.Y - origin.Y,
				w = node.AbsoluteSize.X,
				h = node.AbsoluteSize.Y,
				visible = t.visible(node),
			}
		end
	end
	return result
end

local function same(t: any, where: string, actual: { [string]: any }, expected: { [string]: any })
	local worst, missing = 0, {}
	for name, want in expected do
		local got = actual[name]
		if not got then
			table.insert(missing, name)
			continue
		end
		if got.visible ~= want.visible then
			table.insert(missing, name .. " visibility")
		end
		worst = math.max(
			worst,
			math.abs(got.x - want.x),
			math.abs(got.y - want.y),
			math.abs(got.w - want.w),
			math.abs(got.h - want.h)
		)
	end
	t.check(where, worst <= 0.5 and #missing == 0, { worstDelta = worst, missing = missing })
end

local function rects(t: any, stage: any, names: { string }): { [string]: any }
	local out = {}
	for _, name in names do
		local node = t.find(stage, name)
		if
			node
			and node:IsA("GuiObject")
			and t.visible(node)
			and node.AbsoluteSize.X > 0
			and node.AbsoluteSize.Y > 0
		then
			out[name] = t.rect(node)
		end
	end
	return out
end

local function overlap(a: any, b: any): number
	local w = math.min(a.r, b.r) - math.max(a.x, b.x)
	local h = math.min(a.b, b.b) - math.max(a.y, b.y)
	return if w > 0.5 and h > 0.5 then w * h else 0
end

local LEAF_ZONES = { "Tasks", "Clock", "Rail", "Health", "Actions", "Feed", "Readout", "Weapon" }

add("hud-viewport-round-trip", { "apps-206", "apps-218", "apps-234" }, function(t)
	for _, a in SIZES do
		local fresh = select(1, hud(t, a))
		local expected = snapshot(t, fresh)
		t.cleanup()
		for _, b in SIZES do
			if b == a then
				continue
			end
			local size = t.Facet.Compose.cell(a)
			local stage, built = hud(t, size)
			size:set(b)
			t.settle(4)
			built.steps.openUrlBar()
			t.settle(4)
			built.steps.closeUrlBar()
			t.settle(4)
			built.steps.openOverflow()
			t.settle(10)
			built.steps.closeOverflow()
			t.settle(10)
			size:set(a)
			t.settle(10)
			same(t, `{label(a)} -> {label(b)} -> {label(a)} zones match a fresh mount`, snapshot(t, stage), expected)
			t.cleanup()
		end
	end
end)

add("hud-url-bar-reserves-its-height", { "apps-206" }, function(t)
	for _, size in { Vector2.new(1079, 809), Vector2.new(691, 360) } do
		local stage, built = hud(t, size)
		local body = t.find(stage, "HudBody")
		local before = body.AbsoluteSize.Y
		built.steps.openUrlBar()
		t.settle(8)
		local chrome = t.find(stage, "BrowserChrome")
		local after = body.AbsoluteSize.Y
		local where = label(size)
		t.near(
			`{where} body shrinks by the chrome and the list padding`,
			before - after,
			chrome.AbsoluteSize.Y + 8,
			0.5
		)
		t.note(`{where} chrome height`, chrome.AbsoluteSize.Y)
		local zones = rects(t, stage, LEAF_ZONES)
		local c = t.rect(chrome)
		for name, zone in zones do
			t.check(`{where} {name} clear of the browser chrome`, overlap(zone, c) == 0, { zone = zone, chrome = c })
		end
		for first, a in zones do
			for second, b in zones do
				if first < second then
					t.check(`{where} {first} clear of {second}`, overlap(a, b) == 0, { a = a, b = b })
				end
			end
		end
		t.cleanup()
	end
end)

add("hud-orientation-cycles", { "apps-210" }, function(t)
	local landscape, portrait = Vector2.new(691, 360), Vector2.new(360, 691)
	local fresh = hud(t, landscape)
	local expected = snapshot(t, fresh)
	t.cleanup()
	local size = t.Facet.Compose.cell(landscape)
	local stage, built = hud(t, size)
	built.steps.openUrlBar()
	t.settle(4)
	size:set(portrait)
	t.settle(6)
	built.steps.closeUrlBar()
	t.settle(4)
	size:set(landscape)
	t.settle(10)
	same(t, "landscape, URL bar, portrait, no URL bar, landscape matches a fresh mount", snapshot(t, stage), expected)
	for cycle = 1, 4 do
		size:set(portrait)
		t.settle(6)
		size:set(landscape)
		t.settle(10)
		same(t, `orientation cycle {cycle} matches a fresh mount`, snapshot(t, stage), expected)
	end
end)

add("hud-heights-keep-zones-apart", { "apps-214" }, function(t)
	local size = t.Facet.Compose.cell(Vector2.new(1079, 809))
	local stage = hud(t, size)
	local lanes = {
		Left = { "Tasks", "Health", "Feed" },
		Center = { "Clock" },
		Right = { "Rail", "Readout", "Weapon", "Actions" },
	}
	for height = 809, 240, -19 do
		size:set(Vector2.new(1079, height))
		t.settle(4)
		local zones = rects(t, stage, LEAF_ZONES)
		local crossings = {}
		for first, a in zones do
			for second, b in zones do
				if first < second and overlap(a, b) > 0 then
					table.insert(crossings, first .. "/" .. second)
				end
			end
		end
		local outside = {}
		for laneName, members in lanes do
			local lane = t.find(stage, laneName)
			if lane then
				local l = t.rect(lane)
				for _, name in members do
					local zone = zones[name]
					if zone and (zone.x < l.x - 0.5 or zone.r > l.r + 0.5) then
						table.insert(outside, name)
					end
				end
			end
		end
		t.check(`1079x{height} zones do not intersect`, #crossings == 0, crossings)
		t.check(`1079x{height} zones stay inside their lanes`, #outside == 0, outside)
	end
end)

add("hud-notice-clear-of-zones", { "apps-221" }, function(t)
	for _, size in { Vector2.new(1280, 800), Vector2.new(390, 844) } do
		local stage, built = hud(t, size)
		built.steps.notify()
		t.settle(8)
		local notice = t.find(stage, "Notice")
		if not (notice and t.visible(notice)) then
			t.check(label(size) .. " notice shown", false)
			t.cleanup()
			continue
		end
		local n = t.rect(notice)
		for name, zone in rects(t, stage, LEAF_ZONES) do
			t.check(`{label(size)} notice clear of {name}`, overlap(n, zone) == 0, { notice = n, zone = zone })
		end
		t.cleanup()
	end
end)

add("circular-value-inside-gauge", { "themes-P1-11" }, function(t)
	local stage = t.mount(function(UI)
		return UI.ProgressView "Ring" { value = 0.75, presentation = "circular", diameter = 120, showValue = true }
	end, { size = Vector2.new(300, 300) })
	local value, gauge = t.find(stage, "Value"), t.find(stage, "Gauge")
	if not (value and gauge) then
		t.check("circular value mounted", false)
		return
	end
	local v, g = t.rect(value), t.rect(gauge)
	t.note("value text", value.Text)
	t.check("value text is at most 72px wide", value.TextBounds.X <= 72, value.TextBounds)
	t.check("value is centred on its anchor", value.AnchorPoint == Vector2.new(0.5, 0.5), value.AnchorPoint)
	t.check(
		"value inside the gauge width",
		v.x >= g.x - 0.5 and v.r <= g.r + 0.5,
		{ value = { v.x, v.r }, gauge = { g.x, g.r } }
	)
end)

add("large-text-gauge-value-below-ring", { "themes-P1-14" }, function(t)
	t.note("preferred text size", t.environment.preferredTextSize)
	local stage = t.mount(function(UI)
		return UI.ProgressView "Ring" {
			value = 1,
			presentation = "circular",
			diameter = 80,
			showValue = true,
			format = function()
				return "10000 / 10000"
			end,
		}
	end, { size = Vector2.new(400, 300) })
	local value, gauge = t.find(stage, "Value"), t.find(stage, "Gauge")
	local indicator = t.find(stage, "Indicator")
	if not (value and gauge and indicator) then
		t.check("gauge mounted", false)
		return
	end
	local v, g, ring = t.rect(value), t.rect(gauge), t.rect(indicator)
	t.check("value is visible", t.visible(value))
	t.check("value text fits", t.fits(value), { bounds = value.TextBounds, size = value.AbsoluteSize })
	t.check("value is wider than the ring", value.TextBounds.X > 80, value.TextBounds)
	t.check(
		"gauge is at least as wide as the value",
		g.w >= value.TextBounds.X - 0.5,
		{ gauge = g.w, text = value.TextBounds.X }
	)
	t.check("value shows below the ring", v.y >= ring.b - 0.5, { value = v.y, ring = ring.b })
end)

local function columnsMatch(t: any, where: string, grid: any, ids: { string })
	local header = t.find(grid, "Header")
	if not header then
		t.check(where .. " header mounted", false)
		return
	end
	local rows = 0
	for _, row in grid:GetDescendants() do
		if row.Name == "Row" and row:IsA("GuiObject") and t.visible(row) then
			rows += 1
			for _, id in ids do
				local head, cell = header:FindFirstChild(id), row:FindFirstChild(id, true)
				if head and cell and t.visible(head) and t.visible(cell) then
					local h, c = t.rect(head), t.rect(cell)
					t.check(
						`{where} row {rows} {id} x matches the header`,
						math.abs(h.x - c.x) <= 0.5,
						{ header = h.x, cell = c.x }
					)
					t.check(
						`{where} row {rows} {id} width matches the header`,
						math.abs(h.w - c.w) <= 0.5,
						{ header = h.w, cell = c.w }
					)
				end
			end
		end
	end
	t.check(where .. " rows compared", rows > 0, rows)
end

local LAPS = {
	{ id = "1", name = "Ari Foyer", laps = 12 },
	{
		id = "2",
		name = "A driver with a very long name that has to wrap across more than one line in the cell",
		laps = 9,
	},
	{ id = "3", name = "Rally", laps = 4 },
}

add("table-columns-follow-the-header", { "collections-133", "collections-134", "collections-207" }, function(t)
	local shapes = {
		{ name = "viewport", options = {} },
		{ name = "content", options = { scrolls = false } },
		{ name = "reorderable", options = { reorderable = true, editing = true, actions = true } },
		{ name = "collapsed", options = { narrow = true } },
	}
	for _, theme in t.themes do
		for _, shape in shapes do
			local editing, rows
			local stage = t.mount(function(UI, _, Compose)
				editing = Compose.cell(shape.options.editing == true)
				rows = Compose.cell(table.clone(LAPS))
				return UI.Table "Grid" {
					from = rows,
					key = function(item)
						return item.id
					end,
					columns = {
						{
							id = "name",
							label = "Name",
							value = function(item)
								return item.name
							end,
						},
						{
							id = "laps",
							label = "Laps",
							width = 64,
							value = function(item)
								return item.laps
							end,
						},
						if shape.options.narrow
							then {
								id = "team",
								label = "Team",
								width = 150,
								priority = 2,
								value = function()
									return "Glade"
								end,
							}
							else nil,
					},
					scrolls = shape.options.scrolls,
					reorderable = shape.options.reorderable,
					editing = editing,
					rowActions = if shape.options.actions
						then function()
							return {
								trailing = {
									{
										id = "delete",
										label = "Delete",
										role = "destructive",
										onActivate = function() end,
									},
								},
							}
						end
						else nil,
					Size = UDim2.fromScale(1, if shape.options.scrolls == false then 0 else 1),
				}
			end, {
				theme = theme.package,
				size = if shape.options.narrow then Vector2.new(260, 300) else Vector2.new(520, 320),
				frames = 12,
			})
			local grid = t.find(stage, "Grid")
			columnsMatch(t, `{theme.name} {shape.name}`, grid, { "name", "laps", "team" })
			if shape.name == "reorderable" then
				local body = grid:FindFirstChildWhichIsA("ScrollingFrame", true)
				if body then
					body.CanvasPosition = Vector2.new(40, body.CanvasPosition.Y)
					t.settle(6)
					columnsMatch(t, `{theme.name} {shape.name} after a horizontal scroll`, grid, { "name", "laps" })
				end
			end
			if shape.name == "viewport" and theme.name == "Neutral" then
				local grown = table.clone(LAPS)
				grown[1] = { id = "1", name = string.rep("Longer name ", 8), laps = 12 }
				rows:set(grown)
				t.settle(8)
				columnsMatch(t, "Neutral viewport after a row grows", grid, { "name", "laps" })
			end
			t.cleanup()
		end
	end
end)

add("collapsed-column-details-target", { "collections-203" }, function(t)
	local stage = t.mount(function(UI)
		return UI.Table "Grid" {
			from = LAPS,
			key = function(item)
				return item.id
			end,
			columns = {
				{
					id = "a",
					label = "Alpha",
					width = 150,
					value = function(item)
						return item.name
					end,
				},
				{
					id = "b",
					label = "Beta",
					width = 150,
					priority = 2,
					value = function(item)
						return item.laps
					end,
				},
				{
					id = "c",
					label = "Gamma",
					width = 150,
					priority = 1,
					value = function()
						return "Glade"
					end,
				},
			},
			Size = UDim2.fromScale(1, 1),
		}
	end, { size = Vector2.new(240, 320), frames = 12 })
	local found = 0
	for _, node in stage:GetDescendants() do
		if node.Name == "Details" and node:IsA("GuiObject") and t.visible(node) then
			local button = node:FindFirstChildWhichIsA("GuiButton", true) or node
			found += 1
			t.check(`Details {found} meets the 44px touch height`, button.AbsoluteSize.Y >= 43.5, button.AbsoluteSize)
		end
	end
	t.note("touch", t.environment.touch)
	t.check("a collapsed column shows Details", found > 0, found)
end)

add("playlist-resize-grip-touch-target", { "apps2-175" }, function(t)
	local api = workspace:WaitForChild("FacetShowcaseAPI") :: any
	local result = api:Invoke("show", "ex02")
	t.settle(20)
	t.check("gallery shows the playlist", result.ok == true, result)
	local gui = game:GetService("Players").LocalPlayer.PlayerGui:WaitForChild("FacetGallery")
	local header
	for _ = 1, 120 do
		for _, node in gui:GetDescendants() do
			if node.Name == "Header" and node:IsA("GuiObject") and t.visible(node) and node:FindFirstChild("name") then
				header = node
			end
		end
		if header then
			break
		end
		t.settle(1)
	end
	t.settle(6)
	local cell = header and header:FindFirstChild("name")
	local grip = cell and cell:FindFirstChild("Resize", true)
	if not grip then
		t.check("Name column resize grip found", false)
		return
	end
	local g, c = t.rect(grip), t.rect(cell)
	t.note("touch", t.environment.touch)
	t.check("grip is at least 44 wide on touch", g.w >= 43.5, g.w)
	t.check("grip is at least 44 tall on touch", g.h >= 43.5, g.h)
	t.near("grip right edge meets the header cell right edge", g.r, c.r, 0.5)
end)

add("gallery-current-tab-fill-at-first-frame", { "apps2-86" }, function(t)
	local api = workspace:WaitForChild("FacetShowcaseAPI") :: any
	local gui = game:GetService("Players").LocalPlayer.PlayerGui:WaitForChild("FacetGallery")
	local function check(where: string)
		local shell = gui:FindFirstChild("Gallery")
		local demos = shell and shell:FindFirstChild("Demos")
		local tabs = demos and demos:FindFirstChild("Tabs")
		local tab = tabs and tabs:FindFirstChild("all-controls", true)
		if not tab then
			t.check(where .. " all-controls tab visible", false)
			return
		end
		t.check(where .. " tab is tagged current", tab:HasTag("facet-tab-current"), tab:GetTags())
		t.check(where .. " tab is tagged filled", tab:HasTag("facet-tab-filled"), tab:GetTags())
		t.check(
			where .. " tab has a non-empty size",
			tab.AbsoluteSize.X > 0 and tab.AbsoluteSize.Y > 0,
			tab.AbsoluteSize
		)
		local transparency = (tab :: any):GetStyled("BackgroundTransparency")
		t.check(where .. " tab shows its fill", transparency < 1, transparency)
		t.note(where .. " fill", (tab :: any):GetStyled("BackgroundColor3"))
	end
	api:Invoke("show", "all-controls")
	t.settle(10)
	check("first")
	api:Invoke("show", "collections")
	t.settle(10)
	api:Invoke("show", "all-controls")
	t.settle(10)
	check("after a round trip")
end)

add("coach-mark-clear-of-share-and-reset-floor", { "navigation-1-65" }, function(t)
	local built
	local stage = t.mount(function(UI, Host, Compose, env)
		built = t.scenario("callout").build(t.context(UI, Host, Compose, env))
		return built.screen()
	end, { frames = 12 })
	local share = t.find(stage, "Share")
	if not share then
		t.check("Share mounted", false)
		return
	end
	local page = share:FindFirstAncestorWhichIsA("ScrollingFrame")
	if page then
		page.CanvasPosition = Vector2.new(0, math.max(0, share.AbsolutePosition.Y - page.AbsolutePosition.Y - 40))
		t.settle(4)
	end
	game:GetService("GuiService").SelectedObject = share
	local function plates(where: string)
		local s = t.rect(share)
		local count = 0
		for _, node in stage.Parent:GetDescendants() do
			if node.Name == "CalloutPanel" and node:IsA("GuiObject") and t.visible(node) then
				count += 1
				local p = t.rect(node)
				local w = math.min(p.r, s.r) - math.max(p.x, s.x)
				local h = math.min(p.b, s.b) - math.max(p.y, s.y)
				t.check(
					`{where} plate {count} does not cover Share`,
					not (w > 0.5 and h > 0.5),
					{ plate = p, share = s }
				)
			end
		end
		t.note(where .. " plates", count)
	end
	built.steps.show()
	t.settle(10)
	plates("after show")
	built.steps.use()
	t.settle(10)
	plates("after use")
	built.steps.reset()
	t.settle(10)
	built.steps.show()
	t.settle(10)
	plates("after reset and show")
	local reset = t.find(stage, "Reset")
	t.check("Reset meets the 44px floor", reset ~= nil and reset.AbsoluteSize.Y >= 43.5, reset and reset.AbsoluteSize)
	game:GetService("GuiService").SelectedObject = nil
end)

return cases
