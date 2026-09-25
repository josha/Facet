--!strict
local GuiService = game:GetService("GuiService")
local storage = game:GetService("ReplicatedStorage")

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

local function selectedName(): string
	local selected = GuiService.SelectedObject
	return if selected then selected.Name else "nil"
end

local function selectedPath(root: Instance?): string
	local selected = GuiService.SelectedObject
	if not selected then
		return "nil"
	end
	local parts = {}
	local at: Instance? = selected
	while at and at ~= root and not at:IsA("LayerCollector") do
		table.insert(parts, 1, at.Name)
		at = at.Parent
	end
	return table.concat(parts, "/")
end

local function watch(value: any, root: Instance?)
	value.visited = {}
	value.paths = {}
	value.connection = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
		table.insert(value.visited, selectedName())
		table.insert(value.paths, selectedPath(root))
	end)
end

local function stop(value: any)
	if value.connection then
		value.connection:Disconnect()
		value.connection = nil
	end
	GuiService.SelectedObject = nil
end

local function monitors(t: any, size: Vector2, app: string, options: { [string]: any }?): any
	local config = options or {}
	local folder = storage:WaitForChild("VirtualMonitors")
	local screens = (require :: any)(folder:WaitForChild("screens"))
	local theme = (require :: any)(folder:WaitForChild("theme"))
	local desktop = (require :: any)(folder:WaitForChild("desktop"))
	local modelModule = (require :: any)(folder:WaitForChild("model"))
	local package = theme.create(t.Facet, if app == "Desktop" then "Discover" else app)
	local value: any = {}
	value.stage = t.mount(function(_, _, Compose, env)
		local model = modelModule.new(Compose)
		Compose.cleanup(model.dispose)
		value.model = model
		local actions = { model = model, spatial = false, theme = package, reducedMotion = Compose.cell(true) }
		local views = screens.create(t.Facet, env.runtime, actions)
		if app == "Desktop" then
			value.progress = Compose.cell(config.progress or 1)
			model.mode:set("Screen")
			model.selectedTab:set(config.tab or "Discover")
			return desktop.create(
				t.Facet,
				env.runtime,
				views,
				model,
				value.progress,
				{ theme = package, reducedMotion = actions.reducedMotion }
			)()
		end
		model.selectedTab:set(app)
		return views[app]()
	end, { size = size, theme = package, palette = theme.paletteName("sage", true), frames = 30 })
	t.settle(20)
	return value
end

local function endDevice(t: any)
	pcall(function()
		(game:GetService("StudioDeviceSimulatorService") :: any):StopSimulationAsync()
	end)
	t.settle(30)
end

local function selectables(t: any, root: Instance): { any }
	local out = {}
	for _, node in root:GetDescendants() do
		if node:IsA("GuiObject") and node.Selectable and t.visible(node) and t.clipped(node) ~= nil then
			table.insert(out, node)
		end
	end
	return out
end

local function pathOf(node: Instance, root: Instance?): string
	local parts = {}
	local at: Instance? = node
	while at and at ~= root and not at:IsA("LayerCollector") do
		table.insert(parts, 1, at.Name)
		at = at.Parent
	end
	return table.concat(parts, "/")
end

local function firstSelectable(t: any, root: Instance, fragment: string): any
	for _, node in selectables(t, root) do
		if string.find(pathOf(node, root), fragment, 1, true) then
			return node
		end
	end
	return nil
end

local function buttonNamed(root: Instance, name: string): any
	for _, node in root:GetDescendants() do
		if node.Name == name and node:IsA("GuiButton") then
			return node
		end
	end
	return nil
end

local function reached(paths: { string }, fragment: string): boolean
	for _, path in paths do
		if string.find(path, fragment, 1, true) then
			return true
		end
	end
	return false
end

local function scenario(t: any, name: string, size: any, frames: number?): (any, any)
	local built
	local stage = t.mount(function(UI, Host, Compose, env)
		built = t.scenario(name).build(t.context(UI, Host, Compose, env))
		return if type(built) == "function" then built() else built.screen()
	end, { size = size, frames = frames or 20 })
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

local function selectableIn(node: Instance): any
	if node:IsA("GuiObject") and node.Selectable then
		return node
	end
	for _, child in node:GetDescendants() do
		if child:IsA("GuiObject") and child.Selectable then
			return child
		end
	end
	return nil
end

interactive("recipe-rail-tab-scrolls-tail", { "apps2-222" }, function(t)
	local value = {}
	local stage, built = scenario(t, "recipes_common", Vector2.new(320, 700))
	value.stage, value.built = stage, built
	value.rail = t.find(stage, "RailChips")
	local start = value.rail and t.find(value.rail, "Wet Weather")
	value.tail = value.rail and t.find(value.rail, "Ghost Lap")
	t.check("the rail and its two chips mount", value.rail ~= nil and start ~= nil and value.tail ~= nil)
	GuiService.SelectedObject = selectableIn(start)
	t.settle(10)
	value.before = value.rail.CanvasPosition.X
	t.note("rail canvas before", value.before)
	t.check("Wet Weather takes the selection", selectedName() == "Wet Weather", selectedPath(stage))
	watch(value, stage)
	return value
end, {
	afterRight = function(t, value)
		t.settle(10)
		t.note("Right visits", table.clone(value.paths))
		t.check("one Right selects Ghost Lap", selectedName() == "Ghost Lap", selectedPath(value.stage))
		local after = value.rail.CanvasPosition.X
		t.check(
			"the rail scrolls toward its tail",
			after > value.before + 0.5,
			{ before = value.before, after = after }
		)
		t.inside("Ghost Lap is whole inside the rail window", value.tail, value.rail)
		local first
		for _, node in t.find(value.stage, "Page"):GetDescendants() do
			if
				node:IsA("GuiObject")
				and node.Selectable
				and t.visible(node)
				and (first == nil or node.AbsolutePosition.Y < first.AbsolutePosition.Y)
			then
				first = node
			end
		end
		GuiService.SelectedObject = first
		t.settle(6)
		t.note("walk starts at", selectedPath(value.stage))
		table.clear(value.visited)
		table.clear(value.paths)
	end,
	afterWalk = function(t, value)
		t.note("Down walk visits", table.clone(value.paths))
		for _, fragment in { "CheckboxGroup/fuel", "WrapChecks/fuel", "WrapChips/", "RailChips/Row/" } do
			t.check(`the Down walk reaches {fragment}`, reached(value.paths, fragment), fragment)
		end
		t.note("Down walk stops at", selectedPath(value.stage))
		local action = t.find(t.find(value.stage, "EmptyCollection"), "Action")
		GuiService.SelectedObject = action
		t.settle(10)
		table.clear(value.visited)
		table.clear(value.paths)
	end,
	afterAccordion = function(t, value)
		t.note("second Down walk visits", table.clone(value.paths))
		for _, fragment in { "NoResults/Action", "Accordion/Rules", "Accordion/Setup", "Accordion/Rewards" } do
			t.check(`the second Down walk reaches {fragment}`, reached(value.paths, fragment), fragment)
		end
		local content = t.find(value.stage, "Content")
		local selected = GuiService.SelectedObject
		if selected then
			t.note("last header and page scroller", {
				header = t.rect(selected),
				scroller = t.rect(content),
				canvas = content.AbsoluteCanvasSize,
				page = t.find(value.stage, "Page").AbsoluteSize,
				position = content.CanvasPosition,
			})
		end
		stop(value)
	end,
})

add("vm-phone-avatar-and-assistant", { "apps2-279" }, function(t)
	for app, names in { Avatar = { "Palette", "Hat", "MotionRow", "Reset" }, Chat = { "Draft", "Send" } } do
		local value = monitors(t, Vector2.new(393, 740), app)
		local stage = value.stage
		local stops = selectables(t, stage)
		t.note(`{app} selectable stops`, #stops)
		t.check(`{app} offers selectable controls on a phone`, #stops >= 4, #stops)
		for _, name in names do
			local node = t.find(stage, name)
			local stop = node and selectableIn(node)
			t.check(`{app} {name} is selectable`, stop ~= nil and t.visible(stop))
		end
		local found = t.offenders(stage, stage)
		t.check(`{app} nothing crosses a lateral edge`, #found.lateral == 0, found.lateral)
		local cut = {}
		for _, entry in found.clipped do
			local bounds, box = entry[3], entry[4]
			if bounds.X > box.X + 0.5 or bounds.Y > box.Y + 0.5 then
				table.insert(cut, entry)
			end
		end
		t.check(`{app} no text is cut`, #cut == 0, cut)
		t.cleanup()
	end
end)

add("vm-saved-shelf-takes-the-column", { "apps2-283" }, function(t)
	for _, size in { Vector2.new(1920, 1080), Vector2.new(1280, 720), Vector2.new(920, 640) } do
		local where = `{size.X}x{size.Y}`
		local value = monitors(t, size, "Discover")
		local stage, model = value.stage, value.model
		local body = t.find(stage, "DiscoverBody")
		local games = t.find(stage, "Games")
		t.check(`{where} the Discover body and the Games grid mount`, body ~= nil and games ~= nil)
		if not (body and games) then
			t.cleanup()
			continue
		end
		t.stable(games)
		local grid = t.rect(games)
		local items = model.catalog.items:peek()
		model.toggleSaved(items[1].id)
		model.toggleSaved(items[2].id)
		model.shelf:set("saved")
		t.settle(30)
		local saved = t.find(stage, "SavedGames")
		t.check(`{where} the Games grid unmounts on the Saved shelf`, t.find(stage, "Games") == nil)
		t.check(`{where} the Saved table mounts`, saved ~= nil)
		if saved then
			t.stable(saved)
			local r = t.rect(saved)
			t.note(`{where} grid and saved heights`, { grid = grid.h, saved = r.h })
			t.check(
				`{where} the Saved table is at least 0.9 of the Games grid height`,
				r.h >= grid.h * 0.9,
				{ grid = grid.h, saved = r.h }
			)
			t.inside(`{where} the Saved table stays inside the Discover body`, saved, body, 1)
		end
		model.shelf:set("browse")
		t.settle(30)
		t.check(`{where} the Games grid returns on the Browse shelf`, t.find(stage, "Games") ~= nil)
		t.cleanup()
	end
end)

add("vm-detail-information-scrolls", { "apps2-282" }, function(t)
	for _, size in { Vector2.new(920, 640), Vector2.new(393, 852), Vector2.new(1920, 1080) } do
		local where = `{size.X}x{size.Y}`
		local viewport = if size.X == 1920
			then workspace.CurrentCamera.ViewportSize
			else t.device({ device = "generic_handheld_720", width = size.X, height = size.Y })
		t.note(`{where} viewport`, viewport)
		local value = monitors(t, nil :: any, "Discover")
		local item = value.model.catalog.items:peek()[1]
		value.model.selectGame(item)
		t.settle(40)
		local gui = value.stage:FindFirstAncestorWhichIsA("LayerCollector")
		local details = gui and visibleNamed(t, gui, "GameDetails")
		t.check(`{where} the detail opens`, details ~= nil)
		if details then
			local panel = details:FindFirstAncestor("AlertPanel")
			local scroller = details:FindFirstAncestorWhichIsA("ScrollingFrame")
			t.check(`{where} the detail content is in a scroller in the panel`, scroller ~= nil and panel ~= nil)
			if scroller and panel then
				t.inside(`{where} the panel is inside the screen`, panel, gui, 1)
				t.inside(`{where} the scroller is inside the panel`, scroller, panel, 1)
				local window = scroller.AbsoluteWindowSize
				local canvas = scroller.AbsoluteCanvasSize
				t.note(`{where} panel, window and canvas`, { t.rect(panel), window, canvas })
				t.check(
					`{where} the canvas holds the whole detail`,
					canvas.Y + 1 >= details.AbsoluteSize.Y,
					{ canvas = canvas.Y, details = details.AbsoluteSize.Y }
				)
				scroller.CanvasPosition = Vector2.new(0, math.max(0, canvas.Y - window.Y))
				t.settle(10)
				local frame = {
					x = scroller.AbsolutePosition.X,
					y = scroller.AbsolutePosition.Y,
					r = scroller.AbsolutePosition.X + window.X,
					b = scroller.AbsolutePosition.Y + window.Y,
				}
				for _, name in { "Sparkline", "DetailsTabs" } do
					local node = visibleNamed(t, details, name)
					t.check(`{where} {name} exists`, node ~= nil)
					if node then
						t.inside(`{where} {name} is inside the scroller window at the scroll end`, node, frame, 1)
					end
				end
				local found = t.offenders(details, panel)
				t.check(`{where} nothing in the detail crosses the panel sides`, #found.lateral == 0, found.lateral)
			end
		end
		t.cleanup()
		endDevice(t)
	end
end)

local function tabButton(t: any, root: Instance, id: string): any
	for _, node in root:GetDescendants() do
		if node.Name == id and node:IsA("GuiButton") and t.visible(node) and t.clipped(node) ~= nil then
			return node
		end
	end
	return nil
end

local function clipCheck(t: any, name: string, node: any, stage: any): number
	local hosts = 0
	local at = node.Parent
	local seen = t.rect(node)
	while at and at:IsA("GuiObject") do
		if at.ClipsDescendants or at:IsA("ScrollingFrame") then
			if at:IsA("ScrollingFrame") then
				hosts += 1
			end
			t.inside(`{name} inside {at.Name}`, seen, at, 0.5)
		end
		at = at.Parent
	end
	t.inside(`{name} inside the screen`, seen, stage, 0.5)
	return hosts
end

interactive("showcase-rail-tail-inside-clips", { "apps2-228" }, function(t)
	local value = {}
	local stage, built = scenario(t, "all_controls", Vector2.new(390, 700), 30)
	value.stage, value.built = stage, built
	local actions = tabButton(t, stage, "actions")
	t.check("the Actions category is a selection stop", actions ~= nil)
	GuiService.SelectedObject = actions
	t.settle(4)
	return value
end, {
	afterReturnActions = function(t, value)
		t.settle(30)
		t.check(
			"Return opens Actions",
			value.built.report().selected.Categories == "actions",
			value.built.report().selected
		)
		GuiService.SelectedObject = tabButton(t, value.stage, "recipes")
		t.settle(4)
		t.check("the Recipes tab takes the selection", selectedName() == "recipes", selectedName())
	end,
	afterReturnRecipes = function(t, value)
		t.settle(30)
		t.check("Return opens Recipes", value.built.report().active == "recipes", value.built.report().active)
		local rail = visibleNamed(t, value.stage, "RailChips")
		value.rail = rail
		GuiService.SelectedObject = rail and selectableIn(t.find(rail, "Ghost Lap"))
		t.settle(10)
		t.check("Ghost Lap takes the selection", selectedName() == "Ghost Lap", selectedName())
	end,
	afterRight = function(t, value)
		t.settle(10)
		local target = GuiService.SelectedObject
		t.check("Right selects Custom Rules", selectedName() == "Custom Rules", selectedName())
		if target then
			local hosts = clipCheck(t, "Custom Rules", target, value.stage)
			t.note("scroll hosts around Custom Rules", hosts)
			t.check("Custom Rules sits in nested scroll hosts", hosts >= 2, hosts)
			t.note("Custom Rules rect", t.rect(target))
		end
	end,
	afterReturnChip = function(t, value)
		t.settle(6)
		local example = value.built.report().example
		t.check(
			"Return selects Custom Rules",
			example ~= nil and example.railSelected["Custom Rules"] == true,
			example and example.railSelected
		)
		GuiService.SelectedObject = nil
	end,
})

interactive("inner-tabs-widen-to-engine-words", { "post-showcase-04" }, function(t)
	local value = {}
	local stage, built = scenario(t, "all_controls", Vector2.new(1500, 740), 30)
	value.stage, value.built = stage, built
	GuiService.SelectedObject = tabButton(t, stage, "actions")
	t.settle(4)
	t.check("the Actions category takes the selection", selectedName() == "actions", selectedName())
	return value
end, {
	afterReturn = function(t, value)
		t.settle(40)
		t.check(
			"Return opens Actions",
			value.built.report().selected.Categories == "actions",
			value.built.report().selected
		)
		for id, word in { buttons = "Buttons", recipes = "Recipes", menus = "Menus", sheets = "Sheets", help = "Help" } do
			local button = tabButton(t, value.stage, id)
			t.check(`{word} tab shows`, button ~= nil)
			if button then
				local label = button:FindFirstChild("Label", true)
				local text = if label and label:IsA("TextLabel") then label else button
				t.check(
					`{word} shows its whole word`,
					text.ContentText == word and text.TextBounds.X <= text.AbsoluteSize.X + 0.5,
					{ text.ContentText, text.TextBounds, text.AbsoluteSize }
				)
				t.check(
					`{word} tab is wider than its engine words plus padding`,
					button.AbsoluteSize.X >= text.TextBounds.X + 24 - 0.5,
					{ button = button.AbsoluteSize.X, words = text.TextBounds.X }
				)
			end
		end
		GuiService.SelectedObject = nil
	end,
})

return cases
