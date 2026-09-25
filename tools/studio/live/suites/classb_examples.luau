--!strict
local storage = game:GetService("ReplicatedStorage")

local cases = {}

local function add(id: string, contracts: { string }, run: (any) -> ())
	table.insert(cases, { id = id, contracts = contracts, run = run })
end

local OFFSETS = { 0, 4, 10, 14 }

local function isText(node: Instance): boolean
	return node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox")
end

local function grow(root: Instance, offset: number, base: { [Instance]: number })
	for _, node in root:GetDescendants() do
		if isText(node) and not (node :: any).TextScaled then
			local label = node :: any
			if base[node] == nil then
				base[node] = label:GetStyled("TextSize")
			end
			label.TextSize = base[node] + offset
		end
	end
end

local function example(t: any, name: string, size: Vector2, patch: ((any) -> ())?, theme: any?): (any, any)
	local built
	local stage = t.mount(function(UI, Host, Compose, env)
		local ctx = t.context(UI, Host, Compose, env)
		if patch then
			patch(ctx)
		end
		local module = storage:WaitForChild("FacetExamples"):WaitForChild(name)
		built = (require :: any)(module).build(ctx)
		return if type(built) == "function" then built() else built.screen()
	end, { size = size, frames = 20, theme = theme })
	return stage, built
end

local function scenario(t: any, name: string, size: Vector2, patch: ((any) -> ())?): (any, any)
	local built
	local stage = t.mount(function(UI, Host, Compose, env)
		local ctx = t.context(UI, Host, Compose, env)
		if patch then
			patch(ctx)
		end
		built = t.scenario(name).build(ctx)
		return if type(built) == "function" then built() else built.screen()
	end, { size = size, frames = 20 })
	return stage, built
end

local function visibleNamed(t: any, root: Instance, name: string): any
	for _, node in root:GetDescendants() do
		if node.Name == name and node:IsA("GuiObject") and t.visible(node) then
			return node
		end
	end
	return nil
end

local function pseudo(text: string): string
	local extra = math.ceil(#text * 0.4)
	local pad = string.rep("~", extra)
	return "[" .. text .. pad .. "]"
end

add("consumer-blurb-grows-with-text-size", { "apps2-05" }, function(t)
	local module = storage:WaitForChild("FacetConsumerScreen")
	local screen = (require :: any)(module)
	local stage = t.mount(function(UI)
		return screen.build(t.Facet, UI)
	end, { size = Vector2.new(390, 844), frames = 20 })
	local blurb, count = t.find(stage, "Blurb"), t.find(stage, "Count")
	t.check("the blurb and the count mount", blurb ~= nil and count ~= nil)
	if not (blurb and count) then
		return
	end
	t.check("the blurb declares no text size of its own", blurb.TextSize == 8, blurb.TextSize)
	local base, last = {}, 0
	for _, offset in OFFSETS do
		grow(blurb, 0, base)
		base[blurb] = base[blurb] or blurb:GetStyled("TextSize")
		blurb.TextSize = base[blurb] + offset
		t.settle(6)
		local height = blurb.AbsoluteSize.Y
		t.note(`+{offset} blurb`, { textSize = blurb.TextSize, size = blurb.AbsoluteSize, bounds = blurb.TextBounds })
		if offset > 0 then
			t.check(`+{offset} the blurb is taller than at the smaller size`, height > last + 0.5, { height, last })
		end
		t.check(`+{offset} the blurb text fits its box`, t.fits(blurb), { blurb.TextBounds, blurb.AbsoluteSize })
		t.inside(`+{offset} the blurb stays inside the screen width`, blurb, stage, 1)
		t.check(
			`+{offset} the count moves below the taller blurb`,
			count.AbsolutePosition.Y >= blurb.AbsolutePosition.Y + height - 0.5,
			{ count = count.AbsolutePosition.Y, blurb = blurb.AbsolutePosition.Y + height }
		)
		last = height
	end
end)

local function overlap(a: any, b: any): boolean
	local w = math.min(a.r, b.r) - math.max(a.x, b.x)
	local h = math.min(a.b, b.b) - math.max(a.y, b.y)
	return w > 0.5 and h > 0.5
end

add("word-board-holds-glyphs-at-every-text-size", { "apps2-27" }, function(t)
	local phone = Vector2.new(390, 844)
	for _, theme in t.themes do
		local stage, built = example(t, "05_word_game", phone, nil, theme.package)
		t.settle(4)
		for _, letter in { "R", "U", "L", "E", "S" } do
			built.press(letter)
		end
		built.press("Return")
		for _, letter in { "E", "R", "R" } do
			built.press(letter)
		end
		t.settle(10)
		local board = t.find(stage, "board")
		t.check(`{theme.name} the board mounts`, board ~= nil)
		if not board then
			t.cleanup()
			continue
		end
		local base = {}
		for _, offset in OFFSETS do
			grow(stage, offset, base)
			t.settle(10)
			local where = `{theme.name} +{offset}`
			local bad, seen = {}, 0
			for _, tile in board:GetChildren() do
				if not (tile:IsA("GuiObject") and string.match(tile.Name, "^tile%d+_%d+$")) then
					continue
				end
				local cell = t.rect(tile)
				local ch, mark = t.find(tile, "ch"), t.find(tile, "mark")
				local drawn = {}
				for _, node in { ch, mark } do
					if node and node.ContentText ~= "" then
						seen += 1
						table.insert(drawn, node)
						local box = t.rect(node)
						local inside = box.x >= cell.x - 0.5
							and box.y >= cell.y - 0.5
							and box.r <= cell.r + 0.5
							and box.b <= cell.b + 0.5
						if not inside or not node.TextFits or not t.fits(node) then
							table.insert(bad, {
								tile.Name,
								node.Name,
								node.ContentText,
								node.TextBounds,
								{ box.x - cell.x, box.y - cell.y, box.w, box.h },
								cell.h,
							})
						end
					end
				end
				if #drawn == 2 and overlap(t.rect(drawn[1]), t.rect(drawn[2])) then
					table.insert(bad, { tile.Name, "letter and mark overlap", t.rect(drawn[1]), t.rect(drawn[2]) })
				end
			end
			t.check(`{where} the board draws letters and marks`, seen >= 10, seen)
			t.check(`{where} every letter and mark has a box inside its tile that holds it`, #bad == 0, bad)
			t.inside(`{where} the board fits the phone width`, board, stage, 0.5)
		end
		t.cleanup()
	end
end)

add("settings-sync-compact-phone-every-text-size", { "apps2-43" }, function(t)
	for _, size in { Vector2.new(360, 633), Vector2.new(667, 317) } do
		local stage = example(t, "03_settings_sync", size)
		local base = {}
		for _, offset in OFFSETS do
			grow(stage, offset, base)
			t.settle(10)
			local where = `{size.X}x{size.Y} +{offset}`
			local found = t.offenders(stage, stage)
			t.check(where .. " no text is clipped", #found.clipped == 0, found.clipped)
			t.check(where .. " nothing crosses a lateral edge", #found.lateral == 0, found.lateral)
			local page = t.find(stage, "SettingsSync")
			local history = t.find(stage, "History")
			local volume = t.find(stage, "Volume")
			local value = volume and visibleNamed(t, volume, "Value")
			t.check(
				where .. " the volume value has a box",
				value ~= nil and value.AbsoluteSize.X > 0 and value.AbsoluteSize.Y > 0,
				value and value.AbsoluteSize
			)
			if page and history then
				local bottom = history.AbsolutePosition.Y
					+ history.AbsoluteSize.Y
					- page.AbsolutePosition.Y
					+ page.CanvasPosition.Y
				t.check(
					where .. " the page canvas reaches the last line",
					page.AbsoluteCanvasSize.Y >= bottom - 0.5,
					{ canvas = page.AbsoluteCanvasSize.Y, bottom = bottom }
				)
			else
				t.check(where .. " the page and history mount", false)
			end
			for _, name in { "Music", "Volume", "Invalid", "Deliver", "Reset" } do
				local node = t.find(stage, name)
				t.check(
					where .. ` {name} has a box`,
					node ~= nil and node.AbsoluteSize.X >= 20 and node.AbsoluteSize.Y >= 20,
					node and node.AbsoluteSize
				)
			end
		end
		t.cleanup()
	end
end)

add("confirm-dialog-card-centred", { "apps2-45" }, function(t)
	for _, size in { Vector2.new(390, 844), Vector2.new(1280, 720), Vector2.new(1920, 1080) } do
		local where = `{size.X}x{size.Y}`
		local stage, built = example(t, "04_confirm_dialog", size)
		built.openDialog()
		t.settle(40)
		local gui = stage:FindFirstAncestorWhichIsA("LayerCollector")
		local card = visibleNamed(t, gui, "AlertPanel") or visibleNamed(t, gui, "Card")
		local confirm, cancel = visibleNamed(t, gui, "Confirm"), visibleNamed(t, gui, "Cancel")
		t.check(
			where .. " the dialog shows its card and both actions",
			card ~= nil and confirm ~= nil and cancel ~= nil
		)
		if card and confirm and cancel then
			t.stable(card)
			local c, s = t.rect(card), t.rect(stage)
			t.note(where .. " card", { c.x, c.y, c.w, c.h })
			t.near(where .. " card centred horizontally", c.x + c.w / 2, s.x + s.w / 2, 2)
			t.near(where .. " card centred vertically", c.y + c.h / 2, s.y + s.h / 2, 2)
			t.check(where .. " card is smaller than the screen", c.w < s.w and c.h < s.h, { c.w, c.h })
			t.inside(where .. " confirm inside the card", confirm, card, 0.5)
			t.inside(where .. " cancel inside the card", cancel, card, 0.5)
			t.check(where .. " the actions do not overlap", not overlap(t.rect(confirm), t.rect(cancel)))
			t.check(where .. " both actions have a box", confirm.AbsoluteSize.X > 0 and cancel.AbsoluteSize.X > 0)
			t.note(where .. " actions", { confirm = t.rect(confirm), cancel = t.rect(cancel) })
		end
		t.cleanup()
	end
end)

add("card-rail-height-includes-scrollbar-band", { "apps2-48" }, function(t)
	for _, size in { Vector2.new(320, 640), Vector2.new(1232, 1067) } do
		local where = `{size.X}x{size.Y}`
		local stage = scenario(t, "card_rail", size)
		t.settle(10)
		local rail = t.find(stage, "Rail")
		t.check(where .. " the rail mounts", rail ~= nil and rail:IsA("ScrollingFrame"))
		if rail then
			local card = visibleNamed(t, rail, "Card_c1")
			local inner = card and card:FindFirstChild("Card")
			t.check(where .. " the first card mounts", card ~= nil and inner ~= nil)
			if card and inner then
				local window = rail.AbsolutePosition.Y + rail.AbsoluteWindowSize.Y
				local r = t.rect(rail)
				t.note(where .. " rail", {
					size = rail.AbsoluteSize,
					window = rail.AbsoluteWindowSize,
					bar = rail.ScrollBarThickness,
					card = card.AbsoluteSize,
				})
				t.check(
					where .. " the rail shows a scrollbar band",
					r.h - rail.AbsoluteWindowSize.Y >= rail.ScrollBarThickness - 0.5 and rail.ScrollBarThickness > 0,
					{ r.h, rail.AbsoluteWindowSize.Y, rail.ScrollBarThickness }
				)
				t.check(
					where .. " the card ends above the scrollbar band",
					card.AbsolutePosition.Y + card.AbsoluteSize.Y <= window + 0.5,
					{ card = card.AbsolutePosition.Y + card.AbsoluteSize.Y, window = window }
				)
				t.near(
					where .. " the rail is exactly the card plus the band",
					r.h,
					card.AbsoluteSize.Y + (r.h - rail.AbsoluteWindowSize.Y),
					0.5
				)
				for _, name in { "Name", "Badge" } do
					local label = inner:FindFirstChild(name)
					t.check(
						where .. ` card {name} fits`,
						label ~= nil and t.fits(label),
						label and { label.TextBounds, label.AbsoluteSize }
					)
					if label then
						t.inside(
							where .. ` card {name} inside the rail window`,
							label,
							{ x = r.x, y = r.y, r = r.r, b = window },
							0.5
						)
					end
				end
			end
		end
		t.cleanup()
	end
end)

add("card-rail-pseudo-localized-chrome", { "apps2-48" }, function(t)
	local copy = {}
	for key, value in t.scenario("card_rail").copy do
		copy[key] = pseudo(value)
	end
	for _, size in { Vector2.new(320, 640), Vector2.new(640, 320) } do
		local where = `{size.X}x{size.Y}`
		local stage = scenario(t, "card_rail", size, function(ctx)
			ctx.copy = copy
		end)
		t.settle(10)
		for _, name in { "Title", "Hint", "Selected" } do
			local label = t.find(stage, name)
			t.check(
				where .. ` {name} shows the pseudo-localized copy`,
				label ~= nil and string.find(label.ContentText, "~", 1, true) ~= nil,
				label and label.ContentText
			)
			if label then
				t.check(
					where .. ` {name} fits`,
					t.fits(label) and label.TextFits,
					{ label.TextBounds, label.AbsoluteSize }
				)
				t.inside(
					where .. ` {name} inside the screen width`,
					label,
					{ x = 0, y = -1e6, r = size.X, b = 1e6 },
					0.5
				)
			end
		end
		local found = t.offenders(stage, stage)
		t.check(where .. " no text is clipped", #found.clipped == 0, found.clipped)
		t.check(where .. " nothing crosses a lateral edge", #found.lateral == 0, found.lateral)
		t.cleanup()
	end
end)

add("with-animation-pseudo-localized", { "apps2-52" }, function(t)
	for _, size in { Vector2.new(320, 640), Vector2.new(640, 320) } do
		local where = `{size.X}x{size.Y}`
		local stage, built = scenario(t, "with_animation", size)
		built.steps.run()
		t.settle(90)
		local changed = 0
		for _, node in stage:GetDescendants() do
			if
				isText(node)
				and (node :: any).Text ~= ""
				and not string.find((node :: any).Text, "Animations:", 1, true)
			then
				(node :: any).Text = pseudo((node :: any).Text)
				changed += 1
			end
		end
		t.settle(12)
		t.check(where .. " the copy was expanded", changed >= 8, changed)
		local detail = visibleNamed(t, stage, "DetailPanel")
		t.check(where .. " the detail panel is open", detail ~= nil)
		local found = t.offenders(stage, stage)
		t.check(where .. " no text is clipped", #found.clipped == 0, found.clipped)
		t.check(where .. " nothing crosses a lateral edge", #found.lateral == 0, found.lateral)
		t.cleanup()
	end
end)

add("outpost-terminal-holds-canvas-every-text-size", { "apps2-131" }, function(t)
	for _, offset in OFFSETS do
		local built
		local stage = t.mount(function(UI, Host, Compose, env)
			local ctx = t.context(UI, Host, Compose, env)
			built = ctx.load("example", "outpost_terminal").build(ctx)
			return built.screen()
		end, { size = Vector2.new(640, 480), frames = 20 })
		built.steps.engage(built.steps.snapshot().outpost)
		built.steps.setValue("door", 3)
		built.steps.setValue("beacon", 2)
		built.steps.setValue("workshop", 4)
		t.settle(6)
		grow(stage, offset, {})
		t.settle(10)
		local where = `+{offset}`
		local terminal = t.find(stage, "OutpostTerminal")
		t.note(where .. " message", built.steps.snapshot().message)
		local found = t.offenders(stage, stage)
		t.check(where .. " no text is clipped", #found.clipped == 0, found.clipped)
		t.check(where .. " nothing crosses a lateral edge", #found.lateral == 0, found.lateral)
		t.check(where .. " nothing leaves the 640x480 canvas", #found.vertical == 0, found.vertical)
		local texts = {}
		for _, node in terminal:GetDescendants() do
			if isText(node) and node.ContentText ~= "" and t.visible(node) then
				table.insert(texts, node)
			end
		end
		local collisions = {}
		for i = 1, #texts do
			for j = i + 1, #texts do
				local a, b = texts[i], texts[j]
				if not a:IsDescendantOf(b) and not b:IsDescendantOf(a) and overlap(t.rect(a), t.rect(b)) then
					table.insert(collisions, { a.Name, a.ContentText, b.Name, b.ContentText })
				end
			end
		end
		t.check(where .. " no two lines of text paint over each other", #collisions == 0, collisions)
		local misfit = {}
		for _, node in texts do
			if not node.TextFits then
				table.insert(misfit, { node.Name, node.ContentText, node.TextBounds, node.AbsoluteSize })
			end
		end
		t.check(where .. " every line fits its box", #misfit == 0, misfit)
		t.cleanup()
	end
end)

local function tableHead(t: any, stage: any): any
	local tracks = t.find(stage, "Tracks")
	return tracks and t.find(tracks, "Header")
end

add("playlist-header-titles-and-pinned-column", { "apps2-166" }, function(t)
	local stage, built = example(t, "02_playlist_table", Vector2.new(900, 640))
	t.settle(10)
	local header = tableHead(t, stage)
	t.check("the header mounts", header ~= nil)
	if not header then
		return
	end
	local first = nil
	for _, id in { "name", "artist", "rating" } do
		local cell = header:FindFirstChild(id)
		local sort = cell and cell:FindFirstChild("Sort")
		local title = nil
		if sort then
			for _, node in sort:GetDescendants() do
				if isText(node) and node.ContentText ~= "" then
					title = node
				end
			end
			if title == nil and isText(sort) then
				title = sort
			end
		end
		t.check(
			`{id} title has real area`,
			title ~= nil and title.AbsoluteSize.X > 0 and title.AbsoluteSize.Y > 0 and t.visible(title),
			title and title.AbsoluteSize
		)
		if title then
			t.check(`{id} title text fits`, t.fits(title), { title.TextBounds, title.AbsoluteSize })
		end
	end
	local body = t.find(t.find(stage, "Tracks"), "Body")
	local band = t.rect(header)
	for _, node in body:GetDescendants() do
		if node.Name == "Row" and node:IsA("GuiObject") and t.visible(node) then
			first = node
			break
		end
	end
	t.check(
		"the first row sits below the header band",
		first ~= nil and first.AbsolutePosition.Y >= band.b - 0.5,
		first and { row = first.AbsolutePosition.Y, band = band.b }
	)
	local before = {}
	for _, id in { "name", "artist", "rating" } do
		before[id] = t.rect(header:FindFirstChild(id))
	end
	t.note(
		"widths before",
		{ name = before.name.w, artist = before.artist.w, rating = before.rating.w, header = band.w }
	)
	built.columnWidths:set({ name = 200 })
	t.settle(10)
	local name, rating = t.rect(header:FindFirstChild("name")), t.rect(header:FindFirstChild("rating"))
	local artist = t.rect(header:FindFirstChild("artist"))
	t.note("widths after pinning name", { name = name.w, artist = artist.w, rating = rating.w })
	t.near("the pinned column is 200 wide", name.w, 200, 0.5)
	t.check(
		"the last column still reaches the band's edge",
		rating.r >= band.r - 1,
		{ rating = rating.r, band = band.r }
	)
end)

add("playlist-320x640-edit-mode-cells", { "apps2-180" }, function(t)
	local stage = example(t, "02_playlist_table", Vector2.new(320, 640), function(ctx)
		local base = ctx.UI
		ctx.UI = setmetatable({
			Table = function(name)
				return function(spec)
					local copy = table.clone(spec)
					copy.editing = ctx.Compose.cell(true)
					return base.Table(name)(copy)
				end
			end,
		}, { __index = base })
	end)
	t.settle(20)
	local tracks = t.find(stage, "Tracks")
	local header = tableHead(t, stage)
	local body = tracks and t.find(tracks, "Body")
	t.check("the table mounts", header ~= nil and body ~= nil)
	if not (header and body) then
		return
	end
	local shown = {}
	for _, id in { "name", "artist", "rating" } do
		local cell = header:FindFirstChild(id)
		shown[id] = cell ~= nil and t.visible(cell)
	end
	t.note("visible header columns", shown)
	local row = nil
	for _, node in body:GetDescendants() do
		if node.Name == "Row" and node:IsA("GuiObject") and t.visible(node) then
			row = node
			break
		end
	end
	t.check("a row mounts", row ~= nil)
	if not row then
		return
	end
	local measures = {}
	for _, id in { "name", "artist", "rating" } do
		local cell = row:FindFirstChild(id, true)
		local visible = cell ~= nil and t.visible(cell)
		t.check(
			`{id} shows in the row exactly when it shows in the header`,
			visible == shown[id],
			{ row = visible, header = shown[id] }
		)
		if visible and cell then
			local head = t.rect(header:FindFirstChild(id))
			local box = t.rect(cell)
			t.near(`{id} cell starts under its header`, box.x, head.x, 0.5)
			t.near(`{id} cell is as wide as its header`, box.w, head.w, 0.5)
			local value = cell:FindFirstChild("Value", true)
			if value then
				local seen = t.clipped(value)
				local width = if seen then seen.w else 0
				measures[id] = { cell = box.w, text = width, fits = value.TextFits }
				t.check(`{id} keeps at least 66 px of visible text`, width >= 66, measures[id])
			end
		end
	end
	t.note("320x640 edit mode first row", measures)
	t.near("name cell measures 98 px", measures.name and measures.name.cell or 0, 98, 0.5)
	local collapsed = not shown.artist or not shown.rating
	local more = row.Parent and row.Parent:FindFirstChild("Details")
	t.check(
		"collapsed columns are offered through the row's More control",
		not collapsed or (more ~= nil and t.visible(more) and more.AbsoluteSize.X >= 44),
		more and more.AbsoluteSize
	)
	if more then
		t.inside("the More control stays inside the screen", more, stage, 0.5)
	end
	local found = t.offenders(stage, stage)
	t.check("nothing crosses a lateral edge", #found.lateral == 0, found.lateral)
end)

return cases
