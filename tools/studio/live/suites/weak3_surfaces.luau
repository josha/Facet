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

local function partOf(root: any, name: string): any
	if root == nil then
		return nil
	end
	return root:FindFirstChild(name) or root:FindFirstChild(name, true)
end

local function found(t: any, label: string, names: { string }, nodes: { [string]: any }): boolean
	local missing = {}
	for _, key in names do
		if nodes[key] == nil then
			table.insert(missing, key)
		end
	end
	t.check(label, #missing == 0, missing)
	return #missing == 0
end

local function overlap(a: any, b: any): boolean
	local w = math.min(a.r, b.r) - math.max(a.x, b.x)
	local h = math.min(a.b, b.b) - math.max(a.y, b.y)
	return w > 0.5 and h > 0.5
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

local function click(node: any): { number }
	local at, size = node.AbsolutePosition, node.AbsoluteSize
	return { math.floor(at.X + size.X / 2 + 0.5), math.floor(at.Y + size.Y / 2 + 0.5) }
end

local function midline(rect: any): number
	return rect.y + rect.h / 2
end

local function host(t: any): { [string]: any }
	return {
		viewport = workspace.CurrentCamera.ViewportSize,
		preferred = tostring(UserInputService.PreferredInput),
		touch = UserInputService.TouchEnabled,
		mouse = UserInputService.MouseEnabled,
		gamepad = UserInputService.GamepadEnabled,
		tenFoot = GuiService:IsTenFootInterface(),
		textSize = tostring(GuiService.PreferredTextSize),
	}
end

local function unemulated(t: any)
	pcall(function()
		(game:GetService("StudioDeviceSimulatorService") :: any):StopSimulationAsync()
	end)
	t.settle(30)
end

local function emulate(t: any, device: string, input: any?, orientation: any?): { [string]: any }
	local ok, problem = pcall(t.device, { device = device, input = input, orientation = orientation })
	if not ok then
		t.note(`device {device} failed`, tostring(problem))
	end
	return host(t)
end

local function dense(t: any): any
	local themes = t.Facet.themes
	local package, report = themes.define({
		base = themes.neutralPackage(),
		identity = { id = "dense", displayName = "Dense", schemaVersion = themes.SCHEMA, version = "1.0.0" },
		metrics = { targetSizes = { minimum = 44, pointer = 28 } },
	})
	assert(package, report and report.errors and report.errors[1] and report.errors[1].message)
	return package
end

local function rowsOf(t: any, panel: any, ids: { string }): ({ any }, { any })
	local rows, rects = {}, {}
	for _, id in ids do
		local row = partOf(panel, id)
		table.insert(rows, row)
		table.insert(rects, if row then t.rect(row) else nil)
	end
	return rows, rects
end

local function pitch(t: any, where: string, panel: any, ids: { string }, want: number?, atLeast: number?)
	local rows, rects = rowsOf(t, panel, ids)
	local heights, collide, missing = {}, false, {}
	for index, rect in rects do
		if rect == nil then
			table.insert(missing, ids[index])
			continue
		end
		table.insert(heights, math.round(rect.h))
		local previous = rects[index - 1]
		if previous and overlap(previous, rect) then
			collide = true
		end
		local row = rows[index]
		t.check(
			`{where}: the {ids[index]} row is its own hit target`,
			row:IsA("GuiButton") and row.Active ~= false,
			{ row.ClassName, row.Active }
		)
	end
	t.check(`{where}: every row was found`, #missing == 0, missing)
	local text = table.concat(heights, ",")
	if want then
		t.check(`{where}: rows are {want} px`, text == `{want},{want},{want}`, text)
	end
	if atLeast then
		local ok = #heights == #ids
		for _, h in heights do
			ok = ok and h >= atLeast
		end
		t.check(`{where}: rows are at least {atLeast} px`, ok, text)
	end
	t.check(`{where}: neighbouring rows do not overlap`, not collide, rects)
end

add("dialog-actions-stack-and-row", { "post-overlays-015" }, function(t)
	local noop = function() end
	local long = string.rep("Withdraw from the championship ", 3)
	local forms = {
		{
			name = "three automatic",
			spec = {
				actions = {
					{ id = "A", label = "One", onActivate = noop },
					{ id = "B", label = "Two", onActivate = noop },
					{ id = "C", label = "Three", onActivate = noop },
				},
			},
			stacks = true,
		},
		{
			name = "narrow explicit row of long labels",
			spec = {
				width = "narrow",
				actionLayout = "row",
				actions = {
					{ id = "A", label = long, onActivate = noop },
					{ id = "B", label = long, onActivate = noop },
				},
			},
			stacks = true,
		},
		{
			name = "explicit row of Yes and No",
			spec = {
				actionLayout = "row",
				actions = {
					{ id = "A", label = "Yes", onActivate = noop },
					{ id = "B", label = "No", onActivate = noop },
				},
			},
			stacks = false,
		},
	}
	t.note("host", host(t))
	for _, form in forms do
		local stage = t.mount(function(UI, Host, Compose)
			local spec: { [string]: any } = {
				isPresented = Compose.cell(true),
				onPresentedChange = noop,
				title = "Leave the race?",
				content = function()
					return UI.Text({
						Name = "Line",
						text = "Your lap will not count.",
						TextWrapped = true,
						Size = UDim2.new(1, 0, 0, 0),
						AutomaticSize = Enum.AutomaticSize.Y,
					})
				end,
			}
			for key, value in form.spec do
				spec[key] = value
			end
			return Host.Frame "Board" {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				UI.Dialog("Confirm")(spec),
			}
		end, { size = Vector2.new(1280, 720), frames = 30 })
		local panel = visibleNamed(t, stage, "Panel")
		local actions = panel and partOf(panel, "Actions")
		local a = actions and partOf(actions, "A")
		local b = actions and partOf(actions, "B")
		if found(t, `{form.name}: the dialog, A and B were found`, { "a", "b" }, { a = a, b = b }) then
			t.stable(panel)
			local ra, rb = t.rect(a), t.rect(b)
			t.note(`{form.name} rects`, { A = ra, B = rb, panel = t.rect(panel) })
			if form.stacks then
				t.check(`{form.name}: B stacks below A`, rb.y >= ra.b - 0.5, { a = ra, b = rb })
			else
				t.near(`{form.name}: A and B share one row`, rb.y, ra.y, 0.5)
				t.check(`{form.name}: A and B sit side by side`, not overlap(ra, rb), { a = ra, b = rb })
			end
			for _, node in { a, b } do
				local words = nil
				for _, item in node:GetDescendants() do
					if item:IsA("TextLabel") and item.ContentText ~= "" then
						words = item
					end
				end
				if node:IsA("TextButton") and node.ContentText ~= "" then
					words = node
				end
				if form.stacks and form.spec.width == "narrow" then
					t.note(`{form.name}: {node.Name} label bounds`, words and { words.TextBounds, words.AbsoluteSize })
				else
					t.check(
						`{form.name}: the {node.Name} label is measured by the engine and fits its button`,
						words ~= nil and t.fits(words),
						words and { words.TextBounds, words.AbsoluteSize }
					)
				end
				t.inside(`{form.name}: {node.Name} inside the panel`, node, panel, 1)
			end
		end
		t.cleanup()
	end
end)

add("picker-panel-widest-row", { "post-pickers-054" }, function(t)
	t.note("host", host(t))
	local open
	local stage = t.mount(function(UI, _, Compose)
		open = Compose.cell(false)
		return UI.Picker "P" {
			Position = UDim2.fromOffset(40, 40),
			Size = UDim2.fromOffset(160, 0),
			style = "menu",
			label = "Driver",
			selected = Compose.cell("a"),
			isPresented = open,
			options = {
				{ value = "a", label = "Ada", avatar = { name = "Ada" }, badge = 3, icon = "settings" },
				{ value = "b", label = "Bo", avatar = { name = "Bo" }, meta = "Crew", icon = "settings" },
				{ value = "c", label = "Cy", avatar = { name = "Cy" }, icon = "settings" },
			},
		}
	end, { size = Vector2.new(1280, 720), frames = 20 })
	open:set(true)
	t.settle(20)
	local panel = visibleNamed(t, stage, "MenuPanel")
	if found(t, "desktop: the menu panel opened", { "panel" }, { panel = panel }) then
		t.stable(panel)
		local p = t.rect(panel)
		local labels = 0
		for _, id in { "a", "b", "c" } do
			local row = partOf(panel, id)
			if not row then
				t.check(`desktop: row {id} exists`, false)
				continue
			end
			local r = t.rect(row)
			t.check(`desktop: row {id} is inside the panel across`, r.x >= p.x - 0.5 and r.r <= p.r + 0.5, {
				row = { r.x, r.r },
				panel = { p.x, p.r },
			})
			local cut = {}
			for _, node in row:GetDescendants() do
				if node:IsA("GuiObject") and t.visible(node) and node.AbsoluteSize.X > 0.5 then
					local n = t.rect(node)
					if n.x < p.x - 0.5 or n.r > p.r + 0.5 then
						table.insert(cut, { node.Name, n.x, n.r })
					end
					if node:IsA("TextLabel") and node.ContentText ~= "" then
						if node.ContentText == ({ a = "Ada", b = "Bo", c = "Cy" })[id] then
							labels += 1
						end
						if not t.fits(node) then
							table.insert(cut, { node.Name, node.ContentText, node.TextBounds, node.AbsoluteSize })
						end
					end
				end
			end
			t.check(`desktop: avatar, icon, meta and badge of row {id} fit inside the panel`, #cut == 0, cut)
		end
		t.check("desktop: three option labels are drawn", labels == 3, labels)
	end
	open:set(false)
end)

add("navigation-link-one-line", { "post-pickers-083" }, function(t)
	t.note("host", host(t))
	local stage = t.mount(function(UI, _, Compose)
		return UI.Picker "P" {
			Position = UDim2.fromOffset(40, 40),
			Size = UDim2.fromOffset(480, 0),
			label = "Track",
			style = "navigationLink",
			selected = Compose.cell("normal"),
			options = {
				{ value = "easy", label = "Easy" },
				{ value = "normal", label = "Normal" },
				{ value = "hard", label = "Hard" },
			},
		}
	end, { size = Vector2.new(1400, 700), frames = 20 })
	local root = t.find(stage, "P")
	local trailing = partOf(root, "Trailing")
	local title = nil
	if root then
		for _, node in root:GetDescendants() do
			if node:IsA("TextLabel") and node.ContentText == "Track" then
				title = node
			end
		end
		if root:IsA("TextButton") and root.ContentText == "Track" then
			title = root
		end
	end
	if
		found(t, "the title and the value were found", { "title", "trailing" }, { title = title, trailing = trailing })
	then
		t.stable(trailing)
		local l, v = t.rect(title), t.rect(trailing)
		t.note("rects", { title = l, value = v, row = t.rect(root) })
		t.check("the title and the value share one line", v.y < l.b and l.y < v.b, { title = l, value = v })
		t.check("the value sits after the title", v.x >= l.x + 0.5, { title = l.x, value = v.x })
		t.check("the value reads Normal", trailing.ContentText == "Normal", trailing.ContentText)
		t.check("both words fit their boxes", t.fits(trailing) and (title == root or t.fits(title)), {
			trailing.TextBounds,
			trailing.AbsoluteSize,
		})
	end
end)

add("slider-custom-knob-footprint", { "post-pickers-118" }, function(t)
	t.note("host", host(t))
	local builds, value = 0, nil
	local stage = t.mount(function(UI, Host, Compose)
		value = Compose.cell(50)
		return UI.Slider "Vol" {
			Position = UDim2.fromOffset(40, 40),
			Size = UDim2.fromOffset(320, 0),
			value = value,
			onChange = function(next: number)
				value:set(next)
			end,
			min = 0,
			max = 100,
			step = 10,
			thumbContent = function()
				builds += 1
				return Host.TextLabel "Pip" {
					BackgroundTransparency = 1,
					Text = "x",
					TextSize = 12,
					Size = UDim2.fromOffset(0, 0),
					AutomaticSize = Enum.AutomaticSize.XY,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
				}
			end,
		}
	end, { size = Vector2.new(600, 300), frames = 20 })
	local knob = partOf(stage, "Thumb")
	local mark = knob and partOf(knob, "Pip")
	t.check("the custom knob is built once", builds == 1, builds)
	if found(t, "the Thumb and the caller's Pip were found", { "knob", "mark" }, { knob = knob, mark = mark }) then
		t.stable(knob)
		local k, m = t.rect(knob), t.rect(mark)
		local floor = knob:FindFirstChildWhichIsA("UISizeConstraint")
		t.note("rects", { knob = k, mark = m, floor = floor and floor.MinSize })
		t.check("the handle is at least as large as the mark", k.w >= m.w - 0.5 and k.h >= m.h - 0.5, { k, m })
		if floor then
			t.near("the handle solves at the control's own floor, not the mark's size", k.w, floor.MinSize.X, 0.5)
		end
		t.inside("the mark is drawn inside the handle", m, k, 0.5)
		value:set(100)
		t.settle(10)
		t.stable(knob)
		t.check("the handle rides the value to the right", knob.AbsolutePosition.X > k.x + 1, {
			before = k.x,
			after = knob.AbsolutePosition.X,
		})
		t.check("setting the value does not rebuild the knob", builds == 1, builds)
	end
end)

add("slider-rung-thin-rail-whole-target", { "post-pickers-120" }, function(t)
	t.note("host", host(t))
	local stage = t.mount(function(UI, Host, Compose)
		return Host.Frame "Column" {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Host.UIListLayout({ Padding = UDim.new(0, 24), SortOrder = Enum.SortOrder.LayoutOrder }),
			UI.Slider "Regular" { LayoutOrder = 1, Size = UDim2.fromOffset(320, 0), value = Compose.cell(50) },
			UI.Slider "Compact" {
				LayoutOrder = 2,
				Size = UDim2.fromOffset(320, 0),
				value = Compose.cell(50),
				controlSize = "compact",
			},
		}
	end, { size = Vector2.new(600, 300), frames = 20 })
	local regular, compact = t.find(stage, "Regular"), t.find(stage, "Compact")
	local nodes = {
		thin = partOf(compact, "Rail"),
		normal = partOf(regular, "Rail"),
		track = partOf(compact, "Track"),
		fill = partOf(compact, "Fill"),
	}
	if found(t, "both rails, the compact Track and Fill were found", { "thin", "normal", "track", "fill" }, nodes) then
		t.stable(nodes.track)
		local thin, normal, track = t.rect(nodes.thin), t.rect(nodes.normal), t.rect(nodes.track)
		t.note("rects", { thin = thin, normal = normal, track = track, fill = t.rect(nodes.fill) })
		t.check("the compact rail paints thinner than the regular one", thin.h < normal.h - 0.5, { thin.h, normal.h })
		t.check("the compact hit track keeps a whole 44 px target", track.h >= 43.5, track.h)
		t.check(
			"the hit track carries the drag detector",
			nodes.track:FindFirstChildWhichIsA("UIDragDetector") ~= nil,
			nodes.track.ClassName
		)
		t.inside("the thin rail sits inside the whole target", thin, track, 0.5)
		t.near("the thin rail is centred in the target", midline(thin), midline(track), 1)
		t.near("the fill paints at the thin rail height", t.rect(nodes.fill).h, thin.h, 0.5)
	end
end)

add("dtp-draft-footer-rects", { "post-pickers-150" }, function(t)
	t.note("host", host(t))
	local civil = t.Facet.civilDate
	local open
	local stage = t.mount(function(UI, Host, Compose)
		open = Compose.cell(false)
		local range =
			Compose.cell({ start = { year = 2026, month = 9, day = 1 }, finish = { year = 2026, month = 9, day = 3 } })
		return Host.Frame "Holder" {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(40, 40),
			Size = UDim2.fromOffset(360, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			UI.DateTimePicker "Window" {
				label = "Season window",
				selection = "range",
				range = range,
				onRangeChange = function(next: any)
					range:set(next)
				end,
				clock = function()
					return { year = 2026, month = 9, day = 23 }
				end,
				draft = true,
				isPresented = open,
				presets = {
					{
						id = "week",
						label = "This week",
						range = function(today: any)
							local start = civil.addDays(today, -(civil.weekday(today) - 1))
							return { start = start, finish = civil.addDays(start, 6) }
						end,
					},
					{
						id = "lastYear",
						label = "Last year",
						range = function(today: any)
							return {
								start = { year = today.year - 1, month = 1, day = 1 },
								finish = { year = today.year - 1, month = 12, day = 31 },
							}
						end,
					},
				},
			},
		}
	end, { size = Vector2.new(1280, 720), frames = 20 })
	open:set(true)
	t.settle(20)
	local layer = layerOf(stage)
	local surface = visibleNamed(t, layer, "CalendarSurface")
	local actions = surface and partOf(surface, "Actions")
	local nodes = {
		surface = surface,
		actions = actions,
		reset = actions and partOf(actions, "ResetAll"),
		cancel = actions and partOf(actions, "Cancel"),
		apply = actions and partOf(actions, "Apply"),
		preset = surface and partOf(surface, "Preset-week"),
	}
	if
		found(
			t,
			"the draft calendar, its footer and a preset chip were found",
			{ "surface", "actions", "reset", "cancel", "apply", "preset" },
			nodes
		)
	then
		t.stable(nodes.surface)
		local row, reset, cancel, apply =
			t.rect(actions), t.rect(nodes.reset), t.rect(nodes.cancel), t.rect(nodes.apply)
		local chip = t.rect(nodes.preset)
		t.note("rects", { row = row, reset = reset, cancel = cancel, apply = apply, chip = chip })
		t.check("Reset all, then Cancel, then Apply from the leading edge", reset.x < cancel.x and cancel.x < apply.x, {
			reset.x,
			cancel.x,
			apply.x,
		})
		t.near("Reset all starts at the footer's leading edge", reset.x, row.x, 1)
		t.near("Apply ends at the footer's trailing edge", apply.r, row.r, 1)
		t.check("the footer buttons share one line", math.abs(midline(reset) - midline(apply)) <= 1, {
			midline(reset),
			midline(apply),
		})
		t.check("the compact preset chip is shorter than Apply", chip.h < apply.h - 0.5, { chip.h, apply.h })
		t.inside("the footer stays inside the calendar", actions, nodes.surface, 1)
		local rules = { header = partOf(nodes.surface, "HeaderRule"), footer = partOf(nodes.surface, "FooterRule") }
		if found(t, "both rules were found", { "header", "footer" }, rules) then
			t.check("the footer rule is above the footer", t.rect(rules.footer).b <= row.y + 0.5, {
				rule = t.rect(rules.footer).b,
				footer = row.y,
			})
		end
	end
	open:set(false)
end)

add("color-swatch-square-cells", { "post-pickers-174" }, function(t)
	t.note("host", host(t))
	local open
	local stage = t.mount(function(UI, _, Compose)
		open = Compose.cell(false)
		local value = Compose.cell(Color3.fromRGB(255, 196, 0))
		return UI.ColorPicker "Trim" {
			Position = UDim2.fromOffset(40, 40),
			value = value,
			onChange = function(next: any)
				value:set(next)
			end,
			isPresented = open,
			swatches = { { color = Color3.fromRGB(255, 196, 0) }, { color = Color3.fromRGB(20, 20, 24) } },
		}
	end, { size = Vector2.new(1280, 720), frames = 20 })
	open:set(true)
	t.settle(20)
	local layer = layerOf(stage)
	local grid = visibleNamed(t, layer, "Swatches")
	if found(t, "the swatch grid was found", { "grid" }, { grid = grid }) then
		t.stable(grid)
		local cells = {}
		for _, child in grid:GetChildren() do
			if child:IsA("GuiObject") then
				table.insert(cells, child)
			end
		end
		t.check("two swatch cells", #cells == 2, #cells)
		for _, cell in cells do
			local r = t.rect(cell)
			t.check(`{cell.Name} solves square at 44x44`, math.abs(r.w - 44) <= 0.5 and math.abs(r.h - 44) <= 0.5, {
				r.w,
				r.h,
			})
		end
		if #cells == 2 then
			t.check("the two cells do not overlap", not overlap(t.rect(cells[1]), t.rect(cells[2])))
		end
		t.near("the short grid is two cells and one gap wide", grid.AbsoluteSize.X, 2 * 44 + 4, 0.5)
	end
	open:set(false)
end)

add("color-brick-field-above-grid", { "post-pickers-187" }, function(t)
	t.note("host", host(t))
	local stage = t.mount(function(UI, _, Compose)
		local value = Compose.cell(Color3.fromRGB(255, 0, 0))
		return UI.ColorPicker "Brick" {
			Position = UDim2.fromOffset(40, 40),
			Size = UDim2.fromOffset(420, 0),
			value = value,
			onChange = function(next: any)
				value:set(next)
			end,
			style = "inline",
			modes = { "brick" },
		}
	end, { size = Vector2.new(1280, 900), frames = 20 })
	local field, grid = partOf(stage, "NameField"), partOf(stage, "BrickGrid")
	local name = field and partOf(field, "BrickName")
	if
		found(
			t,
			"the brick name field and grid were found",
			{ "field", "grid", "name" },
			{ field = field, grid = grid, name = name }
		)
	then
		t.stable(grid)
		local f, g = t.rect(field), t.rect(grid)
		t.note("rects", { field = f, grid = g })
		t.check("the brick name field is above its grid", f.b <= g.y + 0.5, { field = f.b, grid = g.y })
		t.check("the field and the grid do not overlap", not overlap(f, g))
		t.check("the field is visible", t.visible(field) and f.h > 0.5, f)
	end
end)

local MENU_IDS = { "a", "b", "c" }

local function denseMenu(t: any, theme: any): (any, any)
	local open
	local stage = t.mount(function(UI, _, Compose)
		open = Compose.cell(false)
		return UI.Menu "M" {
			Position = UDim2.fromOffset(40, 40),
			label = "Options",
			isPresented = open,
			items = {
				{ id = "a", label = "Alpha", onSelect = function() end },
				{ id = "b", label = "Beta", onSelect = function() end },
				{ id = "c", label = "Gamma", onSelect = function() end },
			},
		}
	end, { size = Vector2.new(800, 600), theme = theme, frames = 20 })
	open:set(true)
	t.settle(20)
	return stage, visibleNamed(t, stage, "MenuPanel")
end

add("menu-dense-pointer-rows-live", {
	"post-port26-009",
	"post-port26-010",
	"post-port26-011",
	"post-port26-017",
}, function(t)
	unemulated(t)
	local pointer = host(t)
	t.note("pointer host", pointer)
	t.check("the Studio window is pointer-only", pointer.mouse and not pointer.touch and not pointer.gamepad, pointer)
	local stage, panel = denseMenu(t, dense(t))
	if not found(t, "the dense menu opened", { "panel" }, { panel = panel }) then
		return
	end
	t.stable(panel)
	pitch(t, "pointer-only", panel, MENU_IDS, 28)
	emulate(t, "iphone_14", Enum.PreferredInput.Touch, Enum.ScreenOrientation.Portrait)
	t.note("touch host", host(t))
	t.settle(10)
	panel = visibleNamed(t, stage, "MenuPanel") or panel
	pitch(t, "touch arrives", panel, MENU_IDS, 44)
	unemulated(t)
	t.note("pointer again host", host(t))
	panel = visibleNamed(t, stage, "MenuPanel") or panel
	pitch(t, "back to pointer-only", panel, MENU_IDS, 28)
	emulate(t, "xbox", Enum.PreferredInput.Gamepad)
	t.note("gamepad host", host(t))
	t.settle(10)
	panel = visibleNamed(t, stage, "MenuPanel") or panel
	pitch(t, "a gamepad arrives", panel, MENU_IDS, 44)
	unemulated(t)
	panel = visibleNamed(t, stage, "MenuPanel") or panel
	pitch(t, "the gamepad leaves", panel, MENU_IDS, 28)
	t.cleanup()
	unemulated(t)
	local _, neutral = denseMenu(t, t.themes[1].package)
	if found(t, "the Neutral menu opened", { "panel" }, { panel = neutral }) then
		t.stable(neutral)
		pitch(t, "Neutral under pointer-only", neutral, MENU_IDS, 44)
	end
end)

add("picker-dense-pointer-rows-live", { "post-port26-020" }, function(t)
	unemulated(t)
	t.note("pointer host", host(t))
	local open
	local stage = t.mount(function(UI, _, Compose)
		open = Compose.cell(false)
		return UI.Picker "P" {
			Position = UDim2.fromOffset(40, 40),
			Size = UDim2.fromOffset(240, 0),
			style = "menu",
			selected = Compose.cell("normal"),
			isPresented = open,
			options = {
				{ value = "slow", label = "Slow" },
				{ value = "normal", label = "Normal" },
				{ value = "fast", label = "Fast" },
			},
		}
	end, { size = Vector2.new(800, 600), theme = dense(t), frames = 20 })
	open:set(true)
	t.settle(20)
	local ids = { "slow", "normal", "fast" }
	local panel = visibleNamed(t, stage, "MenuPanel")
	if not found(t, "the dense picker menu opened", { "panel" }, { panel = panel }) then
		return
	end
	t.stable(panel)
	pitch(t, "pointer-only", panel, ids, 28)
	emulate(t, "iphone_14", Enum.PreferredInput.Touch, Enum.ScreenOrientation.Portrait)
	t.note("touch host", host(t))
	t.settle(10)
	panel = visibleNamed(t, stage, "MenuPanel") or panel
	pitch(t, "touch arrives", panel, ids, nil, 44)
	unemulated(t)
	panel = visibleNamed(t, stage, "MenuPanel") or panel
	pitch(t, "back to pointer-only", panel, ids, 28)
	open:set(false)
end)

add("outline-disclosure-indent", { "post-port26-014" }, function(t)
	t.note("host", host(t))
	local stage = t.mount(function(UI, Host, Compose)
		return Host.Frame "Tree" {
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(390, 400),
			Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }),
			UI.DisclosureGroup "G" {
				label = "Inputs",
				appearance = "outline",
				textSize = "label",
				indent = "m",
				expanded = Compose.cell(true),
				content = function()
					return UI.Text({ Name = "Row", text = "Button", AutomaticSize = Enum.AutomaticSize.XY })
				end,
			},
		}
	end, { size = Vector2.new(390, 400), frames = 20 })
	local group = t.find(stage, "G")
	local header = partOf(group, "Header")
	local row = partOf(group, "Row")
	local title = header and (partOf(header, "Title") or partOf(header, "Label"))
	if
		found(t, "the group, header, title and row were found", { "group", "header", "title", "row" }, {
			group = group,
			header = header,
			title = title,
			row = row,
		})
	then
		t.stable(row)
		t.note("rects", { group = t.rect(group), header = t.rect(header), row = t.rect(row) })
		t.near(
			"the body row solves 16 px (space m) in from the group",
			row.AbsolutePosition.X - group.AbsolutePosition.X,
			16,
			0.5
		)
		t.check("the expanded header wears no selected wash", not header:HasTag("facet-selected"), header:GetTags())
		t.check("the group is an outline", group:HasTag("facet-disclosure-outline"), group:GetTags())
		t.near("the title draws at the label role (14 px)", styled(title, "TextSize"), 14, 0.01)
		t.check("the row is below the header", row.AbsolutePosition.Y >= t.rect(header).b - 0.5)
	end
end)

add("picker-start-inline-hug", { "post-port26-018" }, function(t)
	t.note("host", host(t))
	local function build(theme: any): any
		return t.mount(function(UI, Host, Compose)
			return Host.Frame "Strip" {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(40, 40),
				Size = UDim2.fromOffset(0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				Host.UIListLayout({ FillDirection = Enum.FillDirection.Horizontal }),
				UI.Picker "P" {
					label = "Motion",
					style = "menu",
					valueAlignment = "start",
					sizing = "hug",
					controlSize = "compact",
					selected = Compose.cell("normal"),
					options = {
						{ value = "slow", label = "Slow" },
						{ value = "normal", label = "Normal" },
						{ value = "fast", label = "Fast" },
					},
				},
			}
		end, { size = Vector2.new(1280, 700), theme = theme, frames = 20 })
	end
	local function parts(stage: any): (any, any, any)
		local root = t.find(stage, "P")
		local label = root and root:FindFirstChild("Label")
		local trigger = root and partOf(root, "Trigger")
		return root, label, trigger
	end
	local stage = build(nil)
	local root, label, trigger = parts(stage)
	if
		found(t, "the picker row, label and trigger were found", { "root", "label", "trigger" }, {
			root = root,
			label = label,
			trigger = trigger,
		})
	then
		t.stable(trigger)
		local l, g = t.rect(label), t.rect(trigger)
		t.note("rects", { label = l, trigger = g, root = t.rect(root) })
		t.near("the title and trigger midlines meet", midline(l), midline(g), 1)
		t.check("the trigger follows the title within 32 px", g.x >= l.r - 0.5 and g.x - l.r < 32, { l.r, g.x })
		t.check("the hugging pair is narrower than 400 px", root.AbsoluteSize.X < 400, root.AbsoluteSize.X)
		t.check("the title fits on its line", t.fits(label), { label.TextBounds, label.AbsoluteSize })
	end
end)

add("picker-touch-inline-hug", { "post-port26-019" }, function(t)
	local phone = emulate(t, "iphone_14", Enum.PreferredInput.Touch, Enum.ScreenOrientation.LandscapeRight)
	t.note("host", phone)
	t.check("the preferred input is touch", phone.preferred == tostring(Enum.PreferredInput.Touch), phone.preferred)
	local stage = t.mount(function(UI, Host, Compose)
		return Host.Frame "Strip" {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(40, 40),
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			Host.UIListLayout({ FillDirection = Enum.FillDirection.Horizontal }),
			UI.Picker "P" {
				label = "Motion",
				style = "menu",
				valueAlignment = "start",
				sizing = "hug",
				controlSize = "compact",
				selected = Compose.cell("normal"),
				options = {
					{ value = "slow", label = "Slow" },
					{ value = "normal", label = "Normal" },
					{ value = "fast", label = "Fast" },
				},
			},
		}
	end, { frames = 20 })
	local root = t.find(stage, "P")
	local trigger = root and partOf(root, "Trigger")
	local label = root and root:FindFirstChild("Label")
	if
		found(t, "the row, label and trigger were found", { "trigger", "label" }, { trigger = trigger, label = label })
	then
		t.stable(trigger)
		local g, l = t.rect(trigger), t.rect(label)
		t.note("rects", { trigger = g, label = l, root = t.rect(root) })
		t.check("under touch the trigger hugs its value wider than 48 px", g.w > 48, g.w)
		t.check("the title keeps its line beside the trigger", g.x >= l.r - 0.5, { l.r, g.x })
		local value = if trigger:IsA("TextButton") and trigger.ContentText == "Normal" then trigger else nil
		for _, node in trigger:GetDescendants() do
			if (node:IsA("TextLabel") or node:IsA("TextButton")) and node.ContentText == "Normal" then
				value = node
			end
		end
		t.note(
			"trigger texts",
			(function()
				local out = {}
				for _, node in trigger:GetDescendants() do
					if node:IsA("TextLabel") or node:IsA("TextButton") then
						table.insert(out, { node.Name, node.ContentText })
					end
				end
				return out
			end)()
		)
		t.check("the value word is drawn whole", value ~= nil and t.fits(value), value and {
			value.TextBounds,
			value.AbsoluteSize,
		})
	end
end)

add("sheet-adaptive-side-edge", { "post-port26-024" }, function(t)
	unemulated(t)
	t.note("pointer host", host(t))
	local function sheet(size: Vector2, reduced: boolean): (any, any)
		local stage = t.mount(function(UI, Host, Compose)
			return Host.Frame "Room" {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				UI.Sheet "Inspector" {
					isPresented = Compose.cell(true),
					detent = Compose.cell("medium"),
					placement = "adaptive",
					title = "Inspector",
					content = function()
						return UI.Text({ Name = "Copy", text = "Details", AutomaticSize = Enum.AutomaticSize.XY })
					end,
				},
			}
		end, { size = size, reducedMotion = reduced, frames = 2 })
		return stage, nil
	end
	local stage = sheet(Vector2.new(1200, 800), false)
	local samples = {}
	local panel = nil
	for _ = 1, 90 do
		t.settle(1)
		panel = panel or visibleNamed(t, stage, "SheetPanel")
		if panel then
			table.insert(samples, math.round(panel.AbsolutePosition.X - stage.AbsolutePosition.X))
		end
	end
	if found(t, "desktop: the sheet panel was found", { "panel" }, { panel = panel }) then
		t.stable(panel)
		local p, room = t.rect(panel), t.rect(stage)
		t.note("desktop rects", { panel = p, room = room, samples = samples })
		t.check(
			"desktop: the placement is side",
			panel:GetAttribute("FacetPlacement") == "side",
			panel:GetAttribute("FacetPlacement")
		)
		t.near("desktop: the sheet's right edge is the room's right edge", p.r, room.r, 1)
		t.check("desktop: the sheet is narrower than the room", p.w < room.w - 100, { p.w, room.w })
		local first, last = samples[1], samples[#samples]
		t.check(
			"desktop: the sheet slides in from the right edge",
			first ~= nil and last ~= nil and first > last + 8,
			{ first = first, last = last, count = #samples }
		)
	end
	t.cleanup()
	stage = sheet(Vector2.new(390, 800), true)
	panel = visibleNamed(t, stage, "SheetPanel")
	if found(t, "compact: the sheet panel was found", { "panel" }, { panel = panel }) then
		t.stable(panel)
		t.check(
			"compact width keeps the bottom",
			panel:GetAttribute("FacetPlacement") == "bottom",
			panel:GetAttribute("FacetPlacement")
		)
		t.near("compact: the sheet sits on the bottom edge", t.rect(panel).b, t.rect(stage).b, 1)
	end
	t.cleanup()
	local phone = emulate(t, "iphone_14", Enum.PreferredInput.Touch, Enum.ScreenOrientation.LandscapeRight)
	t.note("touch host", phone)
	stage = sheet(Vector2.new(1200, 800), true)
	panel = visibleNamed(t, stage, "SheetPanel")
	if found(t, "touch: the sheet panel was found", { "panel" }, { panel = panel }) then
		t.stable(panel)
		t.check(
			"touch keeps the bottom",
			panel:GetAttribute("FacetPlacement") == "bottom",
			panel:GetAttribute("FacetPlacement")
		)
		t.near("touch: the sheet sits on the bottom edge", t.rect(panel).b, t.rect(stage).b, 1)
	end
end)

add("tabview-rung-centred", { "post-port26-025" }, function(t)
	t.note("host", host(t))
	local stage = t.mount(function(UI, Host, Compose)
		return UI.TabView "Pages" {
			Size = UDim2.fromOffset(600, 400),
			placement = "topBar",
			controlSize = "compact",
			selection = Compose.cell("a"),
			tabs = {
				{
					id = "a",
					label = "Alpha",
					content = function()
						return Host.Frame({ Name = "PA", BackgroundTransparency = 1 })
					end,
				},
				{
					id = "b",
					label = "Beta",
					content = function()
						return Host.Frame({ Name = "PB", BackgroundTransparency = 1 })
					end,
				},
			},
		}
	end, { size = Vector2.new(600, 400), frames = 20 })
	local root = t.find(stage, "Pages")
	local strip = partOf(root, "Tabs")
	local nodes = { strip = strip, a = strip and partOf(strip, "a"), b = strip and partOf(strip, "b") }
	if found(t, "the strip and both tabs were found", { "strip", "a", "b" }, nodes) then
		t.stable(nodes.a)
		local s = t.rect(strip)
		t.note("rects", { strip = s, a = t.rect(nodes.a), b = t.rect(nodes.b) })
		t.near("the strip reserves the 44 px floor", s.h, 44, 0.5)
		for _, id in { "a", "b" } do
			local r = t.rect(nodes[id])
			t.near(`tab {id} paints at the compact 36 px rung`, r.h, 36, 0.5)
			t.near(`tab {id} is centred in the strip`, midline(r), midline(s), 1)
			t.inside(`tab {id} sits inside the strip`, r, s, 0.5)
		end
	end
end)

interactive(
	"plain-checkbox-row-tap",
	{ "post-port26-037" },
	"click: left-click at the point noted as click (the middle of the Box row)",
	function(t)
		unemulated(t)
		local value: { [string]: any } = {}
		local stage = t.mount(function(UI, Host, Compose)
			value.cell = Compose.cell(false)
			return Host.Frame "Col" {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(40, 40),
				Size = UDim2.fromOffset(320, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Host.UIListLayout({ SortOrder = Enum.SortOrder.LayoutOrder }),
				UI.Toggle "Box" {
					label = "Reduced motion",
					presentation = "checkbox",
					appearance = "plain",
					controlSize = "compact",
					textSize = "label",
					value = value.cell,
				},
			}
		end, { size = Vector2.new(400, 300), frames = 20 })
		t.note("host", host(t))
		local row = t.find(stage, "Box")
		value.row = row
		local words = if row and row:IsA("TextButton") and row.ContentText == "Reduced motion" then row else nil
		if row then
			for _, node in row:GetDescendants() do
				if (node:IsA("TextLabel") or node:IsA("TextButton")) and node.ContentText == "Reduced motion" then
					words = node
				end
			end
		end
		if found(t, "the Box row and its label were found", { "row", "words" }, { row = row, words = words }) then
			t.stable(row)
			t.near("the plain compact row solves at 36 px", row.AbsoluteSize.Y, 36, 0.5)
			t.near("the label draws at the label role (14 px)", styled(words, "TextSize"), 14, 0.01)
			t.check("the label fits its row", t.fits(words) and words.AbsoluteSize.Y <= row.AbsoluteSize.Y + 0.5)
			t.check("the row is plain", row:HasTag("facet-toggle-plain"), row:GetTags())
			t.note("click", click(row))
		end
		return value
	end,
	{
		click = function(t, value)
			t.settle(6)
			t.check("a press on the row toggles the value", value.cell:peek() == true, value.cell:peek())
			local row = value.row
			t.check(
				"the checked row wears no selected wash",
				row ~= nil and not row:HasTag("facet-selected"),
				row and row:GetTags()
			)
			local indicator = row and row:FindFirstChild("Indicator", true)
			t.check(
				"the indicator shows on",
				indicator ~= nil and indicator:HasTag("facet-toggle-on"),
				indicator and indicator:GetTags()
			)
		end,
	}
)

return cases
