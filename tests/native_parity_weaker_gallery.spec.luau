--!strict
local t = require("./lib/testkit")
local fs = require("@lune/fs")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local catalogue = require("../examples/gallery/client/demo_picker")
local gallery = require("../examples/gallery/client/screen")
local Compose = Facet.Compose

local function find(root: any, name: string, class: string?): any
	if root.Name == name and (class == nil or root:IsA(class)) then
		return root
	end
	for _, child in root:GetChildren() do
		local found = find(child, name, class)
		if found then
			return found
		end
	end
	return nil
end

local function findAll(root: any, name: string, into: { any }?): { any }
	local result = into or {}
	if root.Name == name then
		table.insert(result, root)
	end
	for _, child in root:GetChildren() do
		findAll(child, name, result)
	end
	return result
end

local function load(kind: string, name: string): any
	return require("../examples/gallery/" .. (if kind == "example" then "examples/" else "scenarios/") .. name) :: any
end

local function world(options: any?): any
	local opts = options or {}
	local engine = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local target = engine.new("Folder")
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	input.IsKeyDown = function()
		return false
	end
	local viewport = Compose.cell(opts.viewport or { width = 1280, height = 720 })
	local ctx: any = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
		types = engine.types,
		viewport = viewport,
		inputTarget = target,
		worldTarget = engine.new("Folder"),
		guiService = gui,
		runService = { Heartbeat = engine.heartbeat },
		theme = opts.theme,
		themeMode = opts.themeMode,
	}
	ctx.UI = Facet.controls(
		runtime,
		{
			types = engine.types,
			viewport = viewport,
			guiService = gui,
			services = { GuiService = gui, UserInputService = input },
			inputParent = target,
			theme = opts.theme,
			reducedMotion = if opts.reducedMotion == nil then true else opts.reducedMotion,
		} :: any
	)
	return {
		reducedMotion = if opts.reducedMotion == nil then true else opts.reducedMotion,
		engine = engine,
		runtime = runtime,
		target = target,
		gui = gui,
		input = input,
		ctx = ctx,
		types = engine.types,
	}
end

local function mountBuilt(w: any, definition: any): (any, any, () -> ())
	local built
	local stop, node = w.runtime.mount(function()
		gallery.configure(w.ctx)
		w.ctx.motionPreference:set(w.reducedMotion)
		built = definition.build(w.ctx)
		if built.dispose then
			Compose.cleanup(built.dispose)
		end
		return w.ctx.Host.ScreenGui "Screen" { built.screen() }
	end, w.target)
	return built, node, stop
end

local function galleryWorld(options: any?): any
	local opts = options or {}
	local engine = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local target, gui = engine.new("Folder"), engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	input.IsKeyDown = function()
		return false
	end
	local neutral = Facet.themes.neutralPackage()
	local ctx: any = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
		types = engine.types,
		viewport = Compose.cell(opts.viewport or { width = 1280, height = 720 }),
		inputTarget = target,
		worldTarget = engine.new("Folder"),
		guiService = gui,
		runService = { Heartbeat = engine.heartbeat },
		selection = Compose.cell(opts.initial or "all-controls"),
		theme = Compose.cell(neutral),
		themeMode = Compose.cell(neutral.style.defaultTheme),
		packages = { Neutral = neutral },
		load = opts.load or load,
	}
	local baseline = engine.census()
	local roots = Compose.outstandingMounts()
	local sheet
	local stop, root = runtime.mount(function()
		gallery.configure(ctx)
		ctx.UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				viewport = ctx.viewport,
				guiService = gui,
				inputParent = target,
				services = { GuiService = gui, UserInputService = input },
				theme = ctx.theme,
				reducedMotion = ctx.reducedMotion,
			} :: any
		)
		sheet = Facet.themes.createStyleSheet(runtime, ctx.theme, { types = engine.types, theme = ctx.themeMode })
		return ctx.Host.ScreenGui "FacetGallery" {
			sheet,
			ctx.Host.StyleLink({ StyleSheet = Compose.static(sheet) }),
			gallery.build(ctx),
		}
	end, target)
	return {
		engine = engine,
		runtime = runtime,
		target = target,
		gui = gui,
		ctx = ctx,
		root = root,
		sheet = sheet,
		baseline = baseline,
		roots = roots,
		types = engine.types,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
end

local function demoPanels(g: any): { string }
	local ids: { [string]: boolean } = {}
	for _, demo in catalogue.list() do
		ids[demo.id] = true
	end
	local names = {}
	for _, node in g.root:GetDescendants() do
		if ids[node.Name] and node:IsA("Frame") and node.Parent and node.Parent.Name == "Content" then
			table.insert(names, node.Name)
		end
	end
	table.sort(names)
	return names
end

local function input(w: any, kind: string): any
	local E = w.types.Enum
	if kind == "mouse" then
		return { UserInputType = E.UserInputType.MouseButton1, KeyCode = E.KeyCode.Unknown }
	elseif kind == "touch" then
		return { UserInputType = E.UserInputType.Touch, KeyCode = E.KeyCode.Unknown }
	elseif kind == "gamepad" then
		return { UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.ButtonA }
	end
	return { UserInputType = E.UserInputType.Keyboard, KeyCode = E.KeyCode.Return }
end

local function enabledAction(target: any, context: string, action: string): any
	local live = {}
	for _, node in findAll(target, "Facet" .. context) do
		if node.Enabled then
			table.insert(live, node)
		end
	end
	t.expect(#live).toBe(1)
	return live[1]:FindFirstChild(action)
end

t.describe("native parity weaker gallery", function()
	t.it("apps2-01 consumer mounts every part, repaints its count from the cell and tears down to baseline", function()
		local w = world()
		local baseline = w.engine.census()
		local roots = Compose.outstandingMounts()
		local stop, node = w.runtime.mount(function()
			return require("../examples/consumer/src/screen").build(
				Facet,
				Facet.controls(w.runtime, { types = w.types })
			)
		end, w.target)
		local panel = find(node, "Panel")
		for _, name in { "Title", "Blurb", "Count", "Sound", "Bump", "Close" } do
			local part = find(panel, name)
			t.expect(part ~= nil).toBe(true)
			t.expect(part.Visible).toBe(true)
		end
		local count = find(panel, "Count")
		t.expect(count.Text).toBe("0 taps")
		find(panel, "Bump").Activated.fire(input(w, "mouse"))
		t.expect(count.Text).toBe("1 tap")
		find(panel, "Bump").Activated.fire(input(w, "touch"))
		t.expect(count.Text).toBe("2 taps")
		t.expect(find(node, "Count")).toBe(count)
		find(panel, "Close").Activated.fire(input(w, "mouse"))
		t.expect(find(node, "Panel")).toBe(nil)
		t.expect(count.isDestroyed()).toBe(true)
		stop()
		t.expect(#w.target:GetChildren()).toBe(0)
		t.expect(w.engine.census().live).toBe(baseline.live)
		t.expect(w.engine.census().connections).toBe(baseline.connections)
		t.expect(Compose.outstandingMounts()).toBe(roots)
		w.runtime:dispose()
	end)

	t.it(
		"apps2-17 crossword play then dispose returns instances, connections and reactive roots to baseline",
		function()
			local w = world()
			local baseline = w.engine.census()
			local roots = Compose.outstandingMounts()
			local built, node, stop = mountBuilt(w, load("example", "06_tile_game"))
			t.expect(Compose.outstandingMounts()).toBe(roots + 1)
			find(node, "rt1").Activated.fire(input(w, "mouse"))
			find(find(node, "cell4_4"), "tap").Activated.fire(input(w, "mouse"))
			t.expect(built.pendingAt(4, 4) ~= nil).toBe(true)
			find(node, "Submit").Activated.fire(input(w, "mouse"))
			find(node, "rt2").Activated.fire(input(w, "mouse"))
			find(find(node, "cell1_1"), "tap").Activated.fire(input(w, "mouse"))
			for _ = 1, 30 do
				w.engine.heartbeat.fire(1 / 30)
			end
			stop()
			t.expect(#w.target:GetChildren()).toBe(0)
			t.expect(w.engine.heartbeat.count()).toBe(0)
			t.expect(w.engine.census().live).toBe(baseline.live)
			t.expect(w.engine.census().connections).toBe(baseline.connections)
			t.expect(Compose.outstandingMounts()).toBe(roots)
			w.runtime:dispose()
		end
	)

	t.it("apps2-66 word game types, deletes and wins through pointer and touch key activations", function()
		for _, kind in { "mouse", "touch" } do
			local w = world()
			local built, node, stop = mountBuilt(w, load("example", "05_word_game"))
			local answer = built.solution()
			local wrong = if answer:sub(1, 1) == "Q" then "Z" else "Q"
			find(node, "key_" .. wrong).Activated.fire(input(w, kind))
			t.expect(built.row(1)).toBe(wrong)
			find(node, "key_Back").Activated.fire(input(w, kind))
			t.expect(built.row(1)).toBe("")
			for i = 1, #answer do
				find(node, "key_" .. answer:sub(i, i)).Activated.fire(input(w, kind))
			end
			t.expect(built.row(1)).toBe(answer)
			t.expect(built.resultsOpen()).toBe(false)
			find(node, "key_Enter").Activated.fire(input(w, kind))
			t.expect(built.won()).toBe(true)
			t.expect(built.state(1, 5)).toBe("correct")
			t.expect(built.resultsOpen()).toBe(true)
			t.expect(find(w.target, "AlertPanel") ~= nil).toBe(true)
			stop()
			t.expect(#w.target:GetChildren()).toBe(0)
			w.runtime:dispose()
		end
	end)

	t.it("apps2-66 crossword selects then places, undoes and explains an empty submit through touch", function()
		for _, kind in { "mouse", "touch" } do
			local w = world()
			local built, node, stop = mountBuilt(w, load("example", "06_tile_game"))
			local first, second = built.rackLetter(1), built.rackLetter(3)
			find(node, "rt1").Activated.fire(input(w, kind))
			t.expect(built.selected()).toBe(1)
			find(find(node, "cell4_4"), "tap").Activated.fire(input(w, kind))
			t.expect(built.letterAt(4, 4)).toBe(first)
			t.expect(built.rackLetter(1)).toBe(nil)
			t.expect(built.selected()).toBe(nil)
			find(node, "rt3").Activated.fire(input(w, kind))
			find(find(node, "cell4_5"), "tap").Activated.fire(input(w, kind))
			t.expect(built.letterAt(4, 5)).toBe(second)
			find(node, "Undo").Activated.fire(input(w, kind))
			t.expect(built.rackCount()).toBe(7)
			t.expect(built.letterAt(4, 4)).toBe(nil)
			t.expect(built.letterAt(4, 5)).toBe(nil)
			find(node, "Submit").Activated.fire(input(w, kind))
			t.expect(built.wordText()).toBe("Place at least one tile before you submit.")
			stop()
			w.runtime:dispose()
		end
	end)

	t.it("apps2-66 match-3 touch taps on two adjacent tiles land on the same board as the swap API", function()
		local board = {
			{ "a", "a", "b", "c", "d", "e" },
			{ "c", "d", "a", "e", "b", "c" },
			{ "e", "b", "c", "d", "a", "b" },
			{ "b", "c", "d", "e", "c", "a" },
			{ "d", "e", "b", "a", "e", "d" },
			{ "a", "c", "e", "b", "d", "c" },
		}
		local function settle(w: any, built: any)
			for _ = 1, 2400 do
				if built.phase() == "idle" and not built.isResolving() then
					return
				end
				w.engine.heartbeat.fire(0.01)
			end
			error("match-3 did not settle")
		end
		local reference = world()
		local ref, _, stopRef = mountBuilt(reference, load("example", "07_match3"))
		ref.debugSetBoard(board)
		ref.swap(1, 3, 2, 3)
		settle(reference, ref)
		local expected = ref.boardSnapshot()
		stopRef()
		reference.runtime:dispose()
		for _, kind in { "mouse", "touch" } do
			local w = world()
			local built, node, stop = mountBuilt(w, load("example", "07_match3"))
			built.debugSetBoard(board)
			local origin = w.types.Vector2.new(120, 120)
			for _, cell in { { 1, 3 }, { 2, 3 } } do
				local hit = find(find(node, "tile" .. built.tileIdAt(cell[1], cell[2])), "hit")
				hit.AbsolutePosition = w.types.Vector2.new(100, 100)
				hit.AbsoluteSize = w.types.Vector2.new(44, 44)
				local drag = find(hit, "SwapDrag")
				drag.DragStart.fire(origin)
				drag.DragEnd.fire(origin)
				hit.Activated.fire(input(w, kind))
			end
			settle(w, built)
			t.expect(built.moves()).toBe(1)
			t.expect(table.concat(built.boardSnapshot(), "|")).toBe(table.concat(expected, "|"))
			stop()
			w.runtime:dispose()
		end
	end)

	t.it("apps2-86 first paint selects the first demo under Facet Neutral and the sweep reaches every demo", function()
		local g = galleryWorld()
		local ctx = g.ctx
		t.expect(ctx.themeName:peek()).toBe("Neutral")
		t.expect(ctx.theme:peek()).toBe(ctx.packages.Neutral)
		t.expect(ctx.themeMode:peek()).toBe(ctx.packages.Neutral.style.defaultTheme)
		t.expect(find(g.root, "StyleLink").StyleSheet).toBe(g.sheet)
		t.expect(ctx.selection:peek()).toBe("all-controls")
		t.expect(ctx.active:peek()).toBe("all-controls")
		t.expect(ctx.errorMessage:peek()).toBe(nil)
		local bar = find(find(g.root, "Demos"), "Tabs")
		local first = find(bar, "all-controls", "TextButton")
		t.expect(first:HasTag("facet-tab-current")).toBe(true)
		t.expect(first:HasTag("facet-tab-filled")).toBe(true)
		for _, demo in catalogue.list() do
			if demo.id ~= "all-controls" then
				t.expect(find(bar, demo.id, "TextButton"):HasTag("facet-tab-current")).toBe(false)
			end
		end
		t.expect(table.concat(demoPanels(g), ",")).toBe("all-controls")
		local visited = {}
		for _ = 1, #catalogue.list() do
			local id = ctx.selection:peek()
			table.insert(visited, id)
			t.expect(ctx.active:peek()).toBe(id)
			t.expect(ctx.errorMessage:peek()).toBe(nil)
			t.expect(find(bar, id, "TextButton"):HasTag("facet-tab-current")).toBe(true)
			local answer = gallery.dispatch(ctx, "showNext", 1)
			t.expect(answer.ok).toBe(true)
			g.engine.heartbeat.fire(1 / 60)
		end
		local order = {}
		for _, demo in catalogue.list() do
			table.insert(order, demo.id)
		end
		t.expect(table.concat(visited, ",")).toBe(table.concat(order, ","))
		t.expect(ctx.selection:peek()).toBe("all-controls")
		t.expect(first:HasTag("facet-tab-current")).toBe(true)
		t.expect(first:HasTag("facet-tab-filled")).toBe(true)
		t.expect(ctx.themeName:peek()).toBe("Neutral")
		g.stop()
	end)

	t.it("apps2-102 catalogue offers ten unique demos with real registered modules and one tab each", function()
		local demos = catalogue.list()
		t.expect(#demos).toBe(10)
		t.expect(demos[1].id).toBe("all-controls")
		t.expect(demos[1].module).toBe("all_controls")
		local seen: { [string]: boolean } = {}
		for _, demo in demos do
			t.expect(seen[demo.id]).toBe(nil)
			seen[demo.id] = true
		end
		for _, id in { "collections", "motion-layout", "radial-menu", "ex02", "ex03", "ex05", "ex06", "ex07" } do
			t.expect(seen[id]).toBe(true)
		end
		local registry = fs.readFile("examples/gallery/scenarios/init.luau")
		local registered: { [string]: boolean } = {}
		for name in string.gmatch(registry, '"([%w_]+)"') do
			registered[name] = true
		end
		for _, demo in demos do
			local path = if demo.kind == "fixture"
				then `examples/gallery/scenarios/{demo.module}.luau`
				else `examples/gallery/examples/{demo.module}.luau`
			t.expect(`{demo.id} {fs.isFile(path)}`).toBe(`{demo.id} true`)
			if demo.kind == "fixture" then
				t.expect(`{demo.id} registered {registered[demo.module] == true}`).toBe(`{demo.id} registered true`)
			end
		end
		local g = galleryWorld()
		local bar = find(find(g.root, "Demos"), "Tabs")
		local tabs = {}
		for _, node in bar:GetDescendants() do
			if node:HasTag("facet-tab-item") then
				table.insert(tabs, node.Name)
			end
		end
		t.expect(#tabs).toBe(10)
		for _, id in tabs do
			t.expect(seen[id]).toBe(true)
		end
		g.stop()
	end)

	t.it("apps2-114 advancing the picker leaves exactly the named demo mounted and reports failed builds", function()
		local g = galleryWorld()
		local ctx = g.ctx
		for _ = 1, #catalogue.list() do
			local id = ctx.selection:peek()
			t.expect(table.concat(demoPanels(g), ",")).toBe(id)
			t.expect(ctx.active:peek()).toBe(id)
			local answer = gallery.dispatch(ctx, "showNext", 1)
			t.expect(answer.mounted).toBe(answer.current)
		end
		t.expect(ctx.selection:peek()).toBe("all-controls")
		g.stop()
		t.expect(#g.target:GetChildren()).toBe(0)
		local broken = galleryWorld({
			load = function(kind: string, name: string)
				if name == "collections" then
					error("Unable to require: collections is not a valid member of FacetScenarios")
				end
				return load(kind, name)
			end,
		})
		local answer = gallery.dispatch(broken.ctx, "show", "collections")
		t.expect(answer.current).toBe("collections")
		t.expect(answer.mounted).toBe(nil)
		t.expect(broken.ctx.errorMessage:peek() ~= nil).toBe(true)
		t.expect(find(broken.root, "DemoFailure") ~= nil).toBe(true)
		answer = gallery.dispatch(broken.ctx, "showNext", 1)
		t.expect(answer.mounted).toBe(answer.current)
		t.expect(broken.ctx.errorMessage:peek()).toBe(nil)
		t.expect(table.concat(demoPanels(broken), ",")).toBe(answer.current)
		broken.stop()
	end)

	t.it("apps-193 collections is the next peer tab after all controls in the one demo list", function()
		local g = galleryWorld()
		local bar = find(find(g.root, "Demos"), "Tabs")
		local first, collections = find(bar, "all-controls", "TextButton"), find(bar, "collections", "TextButton")
		t.expect(collections.Parent).toBe(first.Parent)
		t.expect(collections.LayoutOrder).toBe(first.LayoutOrder + 1)
		t.expect(collections.Selectable).toBe(true)
		t.expect(collections.Visible).toBe(true)
		t.expect(first.NextSelectionDown == nil or first.NextSelectionDown == collections).toBe(true)
		g.gui.SelectedObject = first
		collections.Activated.fire(input(g, "gamepad"))
		t.expect(g.ctx.selection:peek()).toBe("collections")
		t.expect(g.ctx.active:peek()).toBe("collections")
		t.expect(table.concat(demoPanels(g), ",")).toBe("collections")
		g.stop()
	end)
	t.it("apps2-195 leaving the world item disposes its scene at once and leaves no frame work behind", function()
		local w = world()
		local built, node, stop = mountBuilt(w, load("fixture", "radial_menu"))
		local cornerHeartbeat = w.engine.heartbeat.count()
		built.steps.world()
		local stage = find(node, "TrailPack", "ViewportFrame")
		t.expect(stage ~= nil).toBe(true)
		local model = find(stage, "TrailPack")
		find(node, "Launcher").Activated.fire(input(w, "mouse"))
		t.expect(built.report().menu.isPresented).toBe(true)
		find(node, "inspect").Activated.fire(input(w, "mouse"))
		t.expect(built.report().world.angle).toBe(45)
		built.steps.corner()
		t.expect(built.report().tab).toBe("corner")
		t.expect(stage.isDestroyed()).toBe(true)
		t.expect(model == nil or model.isDestroyed()).toBe(true)
		t.expect(find(node, "TrailPack")).toBe(nil)
		t.expect(find(node, "inspect")).toBe(nil)
		t.expect(w.engine.heartbeat.count()).toBe(cornerHeartbeat)
		for _ = 1, 30 do
			w.engine.heartbeat.fire(1 / 60)
		end
		t.expect(built.report().world).toBe(nil)
		t.expect(built.report().menu.isPresented).toBe(false)
		stop()
		t.expect(w.engine.heartbeat.count()).toBe(0)
		w.runtime:dispose()
	end)

	t.it("apps2-261 featured carousel opens a game and hides on the Saved shelf and a short viewport", function()
		local engine = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local target = engine.new("ScreenGui")
		local gui, uis = engine.new("GuiService"), engine.new("UserInputService")
		uis.GetFocusedTextBox = function()
			return nil
		end
		uis.IsKeyDown = function()
			return false
		end
		local lifetime = Compose.createRootOwner(function()
			local model = require("../examples/virtual_monitors/model").new(Compose)
			Compose.cleanup(model.dispose)
			local views = require("../examples/virtual_monitors/screens").create(Facet, runtime, {
				model = model,
				types = engine.types,
				services = { GuiService = gui, UserInputService = uis },
				reducedMotion = true,
			})
			local _, discover = runtime.mount(views.Discover, target)
			local body = find(discover, "DiscoverBody")
			body.AbsoluteSize = engine.types.Vector2.new(1000, 800)
			local first = model.catalog.items:peek()[1]
			t.expect(find(discover, "Featured") ~= nil).toBe(true)
			find(discover, "ExploreFeatured_" .. first.id).Activated.fire()
			t.expect(model.selectedGame:peek().id).toBe(first.id)
			find(target, "close").Activated.fire()
			find(discover, "Saved", "TextButton").Activated.fire()
			t.expect(model.shelf:peek()).toBe("saved")
			t.expect(find(discover, "Featured")).toBe(nil)
			find(discover, "Browse", "TextButton").Activated.fire()
			t.expect(model.shelf:peek()).toBe("browse")
			local featured = find(discover, "Featured")
			t.expect(featured ~= nil).toBe(true)
			t.expect(find(featured, "ExploreFeatured_" .. first.id) ~= nil).toBe(true)
			body.AbsoluteSize = engine.types.Vector2.new(920, 260)
			t.expect(find(discover, "Featured")).toBe(nil)
			body.AbsoluteSize = engine.types.Vector2.new(1000, 800)
			t.expect(find(discover, "Featured") ~= nil).toBe(true)
		end, runtime.reactor)
		lifetime.dispose()
		t.expect(#target:GetChildren()).toBe(0)
		runtime:dispose()
	end)

	t.it("apps2-285 every input class moves the objective marker, including after a resize", function()
		for _, kind in { "gamepad", "keyboard", "touch", "mouse" } do
			local w = world()
			local built, node, stop = mountBuilt(w, load("fixture", "world_markers"))
			local map = find(node, "Map")
			map.AbsoluteSize = w.types.Vector2.new(1248, 360)
			local objective, move = find(map, "A"), find(node, "Move")
			local function activate()
				if kind == "gamepad" or kind == "keyboard" then
					w.gui.SelectedObject = move
					t.expect(w.gui.SelectedObject).toBe(move)
				end
				move.Activated.fire(input(w, kind))
			end
			t.expect(built.report().markers[1].edge).toBe(false)
			activate()
			t.expect(built.report().markers[1].edge).toBe(true)
			t.expect(find(objective, "Direction").Visible).toBe(true)
			t.expect(objective.Position.X.Offset + objective.Size.X.Offset <= 1248).toBe(true)
			map.AbsoluteSize = w.types.Vector2.new(812, 360)
			t.expect(built.report().markers[1].edge).toBe(true)
			t.expect(objective.Position.X.Offset + objective.Size.X.Offset <= 812).toBe(true)
			activate()
			t.expect(built.report().markers[1].edge).toBe(false)
			t.expect(find(objective, "Direction").Visible).toBe(false)
			t.expect(find(map, "A")).toBe(objective)
			t.expect(find(node, "Move")).toBe(move)
			stop()
			w.runtime:dispose()
		end
	end)

	t.it(
		"collections-101 gallery mail rows open one at a time, close explicitly and delete from the keyboard",
		function()
			local w = world()
			local built, node, stop = mountBuilt(w, load("fixture", "row_actions"))
			local list = find(node, "Mail_list")
			local function row(key: string): any
				local found = find(list, "Row_" .. key)
				found.AbsoluteSize = w.types.Vector2.new(320, 112)
				return found
			end
			local function swipe(key: string, from: number, to: number)
				local detector = row(key):FindFirstChildWhichIsA("UIDragDetector", true)
				detector.DragStart.fire(w.types.Vector2.new(from, 20))
				detector.DragContinue.fire(w.types.Vector2.new(to, 20))
				detector.DragEnd.fire()
			end
			local function opened(key: string): boolean
				return find(row(key), "trailing").Visible
			end
			local function report(): any
				return built.report().surfaces.list
			end
			swipe("m1", 300, 150)
			t.expect(opened("m1")).toBe(true)
			t.expect(find(find(row("m1"), "trailing"), "delete") ~= nil).toBe(true)
			swipe("m2", 300, 150)
			t.expect(opened("m2")).toBe(true)
			t.expect(opened("m1")).toBe(false)
			w.gui.SelectedObject = find(row("m2"), "Item_m2")
			enabledAction(w.target, "RowActionsClose", "RowActionsClose").Pressed.fire()
			t.expect(opened("m2")).toBe(false)
			t.expect(report().count).toBe(6)
			swipe("m3", 10, 300)
			t.expect(report().read.m3).toBe(true)
			t.expect(report().count).toBe(6)
			t.expect(find(list, "Row_m3") ~= nil).toBe(true)
			t.expect(report().read.m5 == true).toBe(false)
			find(row("m5"), "Item_m5").Activated.fire(input(w, "touch"))
			t.expect(report().read.m5).toBe(true)
			t.expect(find(list, "Row_m5") ~= nil).toBe(true)
			w.gui.SelectedObject = find(row("m4"), "Item_m4")
			enabledAction(w.target, "RowActionsDelete", "RowActionsDelete").Pressed.fire()
			t.expect(report().count).toBe(5)
			t.expect(find(list, "Row_m4")).toBe(nil)
			t.expect(find(list, "Row_m3") ~= nil and find(list, "Row_m5") ~= nil).toBe(true)
			w.gui.SelectedObject = find(row("m6"), "Item_m6")
			enabledAction(w.target, "RowActionsReveal", "RowActionsReveal").Pressed.fire()
			local panel = find(w.target, "MenuPanel")
			t.expect(panel ~= nil).toBe(true)
			t.expect(find(panel, "trailing:delete") ~= nil and find(panel, "leading:read") ~= nil).toBe(true)
			find(w.target, "FacetModalBack"):FindFirstChild("ModalBack").Pressed.fire()
			t.expect(find(w.target, "MenuPanel")).toBe(nil)
			w.input.IsKeyDown = function(_, key)
				return key == w.types.Enum.KeyCode.LeftShift
			end
			w.gui.SelectedObject = nil
			w.gui.SelectedObject = find(row("m5"), "Item_m5")
			enabledAction(w.target, "RowActionsToggle", "RowActionsToggle").Pressed.fire()
			t.expect(find(w.target, "MenuPanel") ~= nil).toBe(true)
			stop()
			t.expect(#w.target:GetChildren()).toBe(0)
			w.runtime:dispose()
		end
	)

	t.it("collections-109 the gallery page context builds, ticks and disposes the mail rows", function()
		local g = galleryWorld()
		gallery.dispatch(g.ctx, "show", "collections")
		t.expect(g.ctx.active:peek()).toBe("collections")
		t.expect(g.ctx.errorMessage:peek()).toBe(nil)
		local list = find(g.root, "Mail_list")
		t.expect(list ~= nil).toBe(true)
		for _ = 1, 5 do
			g.engine.heartbeat.fire(1 / 60)
		end
		local report = g.ctx.currentReport()
		t.expect(report.active).toBe("swipe")
		t.expect(report.example.active).toBe("list")
		t.expect(report.example.surfaces.list.count).toBe(6)
		t.expect(g.ctx.errorMessage:peek()).toBe(nil)
		gallery.dispatch(g.ctx, "show", "all-controls")
		t.expect(list.isDestroyed()).toBe(true)
		t.expect(find(g.root, "Mail_list")).toBe(nil)
		g.stop()
		t.expect(#g.target:GetChildren()).toBe(0)
		t.expect(g.engine.heartbeat.count()).toBe(0)
		t.expect(Compose.outstandingMounts()).toBe(g.roots)
	end)

	t.it(
		"inputs-77 sensory demo requests press before release, toggles off and on, remounts on and tears down",
		function()
			local w = world()
			local baseline = w.engine.census()
			local built, node, stop = mountBuilt(w, load("fixture", "sensory_feedback"))
			local press, release = find(node, "Press"), find(node, "Release")
			t.expect(built.playHaptics:peek()).toBe(true)
			t.expect(press.PressHapticEffect).toBe(built.effects.press)
			press.InputBegan.fire(input(w, "mouse"))
			release.Activated.fire(input(w, "mouse"))
			local history = built.steps.readHistory()
			t.expect(#history).toBe(2)
			t.expect(history[2]).toBe("1. press")
			t.expect(history[1]).toBe("2. release")
			t.expect(built.effects.press.PlayCount == nil or built.effects.press.PlayCount == 0).toBe(true)
			t.expect(built.effects.release.PlayCount).toBe(1)
			release.InputBegan.fire(input(w, "touch"))
			release.InputEnded.fire(input(w, "touch"))
			t.expect(built.requests:peek()).toBe(2)
			find(node, "PlayHaptics").Activated.fire(input(w, "mouse"))
			t.expect(built.playHaptics:peek()).toBe(false)
			t.expect(find(node, "Press").PressHapticEffect).toBe(nil)
			for _, effect in built.effects do
				t.expect((effect.StopCount or 0) >= 1).toBe(true)
			end
			t.expect(built.report().state).toBe("Feedback is off")
			find(node, "Release").Activated.fire(input(w, "mouse"))
			t.expect(built.requests:peek()).toBe(2)
			find(node, "PlayHaptics").Activated.fire(input(w, "mouse"))
			t.expect(built.playHaptics:peek()).toBe(true)
			t.expect(find(node, "Press").PressHapticEffect).toBe(built.effects.press)
			find(node, "Release").Activated.fire(input(w, "mouse"))
			t.expect(built.requests:peek()).toBe(3)
			find(node, "PlayHaptics").Activated.fire(input(w, "mouse"))
			t.expect(built.playHaptics:peek()).toBe(false)
			local previous = built.effects
			stop()
			for _, effect in previous do
				t.expect(effect.isDestroyed()).toBe(true)
			end
			t.expect(w.engine.census().live).toBe(baseline.live)
			local again, node2, stop2 = mountBuilt(w, load("fixture", "sensory_feedback"))
			t.expect(again.playHaptics:peek()).toBe(true)
			t.expect(again.effects.press ~= previous.press).toBe(true)
			t.expect(find(node2, "Press").PressHapticEffect).toBe(again.effects.press)
			t.expect(again.requests:peek()).toBe(0)
			stop2()
			for _, effect in again.effects do
				t.expect(effect.isDestroyed()).toBe(true)
			end
			t.expect(w.engine.census().live).toBe(baseline.live)
			t.expect(w.engine.census().connections).toBe(baseline.connections)
			w.runtime:dispose()
		end
	)
	t.it("mech2-25 nested tint follows the package, disable blocks every input class and moves focus", function()
		local function near(a: any, b: any)
			t.expect(a.R).toBeCloseTo(b.R, 1e-4)
			t.expect(a.G).toBeCloseTo(b.G, 1e-4)
			t.expect(a.B).toBeCloseTo(b.B, 1e-4)
		end
		local packages = {
			Facet.themes.neutralPackage(),
			((require("../examples/themes/pixel_quest") :: any).build(Facet.themes)),
		}
		for _, package in packages do
			local palette = package.style.themes[1]
			for _, candidate in package.style.themes do
				if candidate.name == package.style.defaultTheme then
					palette = candidate
				end
			end
			local function color(role: string): any
				local rgb = palette.colors[role] or (palette.extra or {})[role] or palette.colors.content
				return { R = rgb.r, G = rgb.g, B = rgb.b }
			end
			local w = world({ theme = Compose.cell(package), themeMode = Compose.cell(palette.name) })
			local built, node, stop = mountBuilt(w, load("fixture", "inherited_subtree"))
			local hero, crest, note, sub =
				find(node, "HeroTitle"), find(node, "Crest"), find(node, "Note"), find(node, "Sub")
			t.expect(hero.TextColor3).toBe(crest.ImageColor3)
			near(note.TextColor3, color("danger"))
			near(sub.TextColor3, color("contentSecondary"))
			built.blend:set(0)
			near(hero.TextColor3, color("contentSecondary"))
			built.blend:set(100)
			near(hero.TextColor3, color("accent"))
			t.expect(crest.ImageColor3).toBe(hero.TextColor3)
			near(sub.TextColor3, color("contentSecondary"))
			t.expect(find(node, "HeroTitle")).toBe(hero)
			t.expect(find(node, "Crest")).toBe(crest)
			stop()
			w.runtime:dispose()
		end
		for _, kind in { "mouse", "touch", "gamepad", "keyboard" } do
			local w = world()
			local built, node, stop = mountBuilt(w, load("fixture", "inherited_subtree"))
			local go, nested, after = find(node, "Go"), find(node, "InnerGo"), find(node, "After")
			local caption = go.TextColor3
			go.Activated.fire(input(w, kind))
			nested.Activated.fire(input(w, kind))
			t.expect(built.report().engaged).toBe(2)
			w.gui.SelectedObject = go
			find(node, "PowerToggle").Activated.fire(input(w, kind))
			t.expect(built.report().enabled).toBe(false)
			t.expect(w.gui.SelectedObject).toBe(after)
			for _, control in { go, nested } do
				t.expect(control.Selectable).toBe(false)
				t.expect(control.Interactable).toBe(false)
				t.expect(control:HasTag("facet-disabled")).toBe(true)
				control.Activated.fire(input(w, kind))
			end
			t.expect(go.TextColor3).toBe(caption)
			t.expect(after.Selectable).toBe(true)
			t.expect(after:HasTag("facet-disabled")).toBe(false)
			t.expect(built.report().engaged).toBe(2)
			after.Activated.fire(input(w, kind))
			t.expect(built.report().enabled).toBe(true)
			t.expect(go.Selectable).toBe(true)
			t.expect(go:HasTag("facet-disabled")).toBe(false)
			go.Activated.fire(input(w, kind))
			t.expect(built.report().engaged).toBe(3)
			t.expect(find(node, "Go")).toBe(go)
			stop()
			w.runtime:dispose()
		end
	end)

	t.it("mech2-26 inherited subtree teardown with the panel on or off leaves nothing live", function()
		for _, on in { true, false } do
			local w = world()
			local baseline = w.engine.census()
			local roots = Compose.outstandingMounts()
			local built, node, stop = mountBuilt(w, load("fixture", "inherited_subtree"))
			w.gui.SelectedObject = find(node, "InnerGo")
			if not on then
				find(node, "PowerToggle").Activated.fire(input(w, "mouse"))
				t.expect(built.report().enabled).toBe(false)
			end
			built.blend:set(80)
			stop()
			t.expect(#w.target:GetChildren()).toBe(0)
			t.expect(w.engine.census().live).toBe(baseline.live)
			t.expect(w.engine.census().connections).toBe(baseline.connections)
			t.expect(w.engine.heartbeat.count()).toBe(0)
			t.expect(Compose.outstandingMounts()).toBe(roots)
			w.runtime:dispose()
		end
	end)

	t.it("mech3-20 card shelves are one-up on a phone, several-up on a desktop and made of selectable cards", function()
		local results = {}
		for _, width in { 390, 1920 } do
			local w = world({ viewport = { width = width, height = 844 } })
			local built, node, stop = mountBuilt(w, load("fixture", "card_rail"))
			t.expect(built.report().shelves).toBe(3)
			local rails = {}
			for _, name in { "Rail", "WeekendRail", "RecommendedRail" } do
				local rail = find(node, name)
				local window = width - 24
				rail.AbsoluteSize = w.types.Vector2.new(window, 300)
				rail.AbsoluteWindowSize = w.types.Vector2.new(window, 300)
				local extent = built.report().rails[name].itemExtent
				local perView = math.floor((window + 8) / (extent + 8))
				t.expect(window - perView * extent - (perView - 1) * 8 >= 0).toBe(true)
				local card = find(rail, "Card_c1")
				t.expect(card.Selectable).toBe(true)
				t.expect(card.Visible).toBe(true)
				rails[name] = perView
			end
			t.expect(rails.WeekendRail).toBe(rails.Rail)
			t.expect(rails.RecommendedRail).toBe(rails.Rail)
			table.insert(results, rails.Rail)
			find(find(node, "WeekendRail"), "Card_c2").Activated.fire(input(w, "gamepad"))
			t.expect(built.report().selectedKey).toBe("c2")
			stop()
			w.runtime:dispose()
		end
		t.expect(results[1]).toBe(1)
		t.expect(results[2] > results[1]).toBe(true)
	end)

	t.it("navigation-1-65 callout reset keeps both anchors, replaces the tips and replays the tip", function()
		local w = world()
		local built, node, stop = mountBuilt(w, load("fixture", "callout"))
		local copy = load("fixture", "callout").copy
		local plus, share = find(node, "Plus"), find(node, "Share")
		local tips = { find(node, "AvatarTip"), find(node, "ShareTip") }
		t.expect(tips[1] ~= nil and tips[2] ~= nil).toBe(true)
		find(node, "Show").Activated.fire(input(w, "mouse"))
		t.expect(built.report().tip.state).toBe("showing")
		find(node, "Use").Activated.fire(input(w, "mouse"))
		t.expect(built.report().tip.state).toBe("retired")
		t.expect(built.report().seen).toBe(true)
		t.expect(built.report().saved ~= copy.saveNothing).toBe(true)
		t.expect(built.steps.show().state).toBe("retired")
		find(node, "ShowSecond").Activated.fire(input(w, "mouse"))
		local reset = find(node, "Reset")
		t.expect(reset:IsA("GuiButton")).toBe(true)
		t.expect(reset.Parent).toBe(find(node, "Show").Parent)
		reset.Activated.fire(input(w, "touch"))
		local after = built.report()
		t.expect(after.tip.state).toBe("waiting")
		t.expect(after.second.state).toBe("waiting")
		t.expect(after.seen).toBe(false)
		t.expect(after.saved).toBe(copy.saveNothing)
		t.expect(find(node, "Plus")).toBe(plus)
		t.expect(find(node, "Share")).toBe(share)
		t.expect(plus.isDestroyed() or share.isDestroyed()).toBe(false)
		for _, tip in tips do
			t.expect(tip.isDestroyed()).toBe(true)
		end
		t.expect(#findAll(node, "AvatarTip")).toBe(1)
		t.expect(#findAll(node, "ShareTip")).toBe(1)
		t.expect(find(node, "AvatarTip") ~= tips[1]).toBe(true)
		t.expect(built.steps.show().state).toBe("showing")
		find(node, "Plus").Activated.fire(input(w, "mouse"))
		t.expect(built.report().presses).toBe(1)
		t.expect(built.report().tip.state).toBe("showing")
		stop()
		w.runtime:dispose()
	end)

	t.it("navigation-2-50 the menu scenario is inside All controls and also mounts standalone", function()
		local menu = load("fixture", "menu")
		t.expect(catalogue.list()[1].module).toBe("all_controls")
		local embedded
		for _, group in load("fixture", "all_controls").groups do
			if group.id == "actions" then
				for _, entry in group.tabs do
					if entry.id == "menus" then
						embedded = entry.scenario
					end
				end
			end
		end
		t.expect(embedded).toBe(menu)
		t.expect(string.find(fs.readFile("examples/gallery/scenarios/init.luau"), '"menu"', 1, true) ~= nil).toBe(true)
		local w = world()
		local _, node, stop = mountBuilt(w, menu)
		t.expect(find(node, "MenuDemo") ~= nil).toBe(true)
		stop()
		w.runtime:dispose()
		local g = galleryWorld()
		find(g.root, "actions", "TextButton").Activated.fire(input(g, "mouse"))
		find(g.root, "menus", "TextButton").Activated.fire(input(g, "mouse"))
		t.expect(g.ctx.currentReport().active).toBe("menus")
		t.expect(find(g.root, "MenuDemo") ~= nil).toBe(true)
		t.expect(g.ctx.errorMessage:peek()).toBe(nil)
		g.stop()
	end)

	t.it("navigation-3-32 showroom and race setup reflow across viewports and survive the distant preview", function()
		local g = galleryWorld({ viewport = { width = 1440, height = 900 } })
		find(g.root, "actions", "TextButton").Activated.fire(input(g, "mouse"))
		t.expect(g.ctx.currentReport().active).toBe("buttons")
		local showroom, race = find(g.root, "Showroom"), find(g.root, "RaceSetup")
		local layout = find(g.root, "Sections"):FindFirstChildWhichIsA("UIListLayout")
		t.expect(layout.FillDirection).toBe(g.types.Enum.FillDirection.Horizontal)
		t.expect(showroom.Size.X.Scale).toBe(0.5)
		t.expect(race.Size.X.Scale).toBe(0.5)
		t.expect(showroom.LayoutOrder < race.LayoutOrder).toBe(true)
		local scale = find(find(g.root, "Gallery"), "ViewingDistance", "UIScale")
		g.ctx.viewingDistance:set("ten-foot")
		t.expect(scale.Scale).toBe(1.5)
		t.expect(find(g.root, "Showroom")).toBe(showroom)
		t.expect(find(g.root, "RaceSetup")).toBe(race)
		t.expect(layout.FillDirection).toBe(g.types.Enum.FillDirection.Vertical)
		t.expect(showroom.Size.X.Scale).toBe(1)
		t.expect(race.Size.X.Scale).toBe(1)
		t.expect(showroom.LayoutOrder < race.LayoutOrder).toBe(true)
		g.ctx.viewingDistance:set("automatic")
		t.expect(layout.FillDirection).toBe(g.types.Enum.FillDirection.Horizontal)
		t.expect(showroom.Size.X.Scale).toBe(0.5)
		g.ctx.viewport:set({ width = 600, height = 900 })
		t.expect(layout.FillDirection).toBe(g.types.Enum.FillDirection.Vertical)
		t.expect(showroom.Size.X.Scale).toBe(1)
		t.expect(race.Size.X.Scale).toBe(1)
		t.expect(showroom.LayoutOrder < race.LayoutOrder).toBe(true)
		g.ctx.viewport:set({ width = 1440, height = 900 })
		t.expect(layout.FillDirection).toBe(g.types.Enum.FillDirection.Horizontal)
		t.expect(find(g.root, "Showroom")).toBe(showroom)
		g.stop()
	end)

	t.it(
		"navigation-3-36 action controls report nil unmounted, the displayed rung, taller large controls and reset",
		function()
			local w = world()
			local definition = load("fixture", "action_controls")
			local built
			local stop, node = w.runtime.mount(function()
				built = definition.build(w.ctx)
				t.expect(built.report()).toBe(nil)
				return w.ctx.Host.ScreenGui "Screen" { built.screen() }
			end, w.target)
			t.expect(built.report().controlSize).toBe("compact")
			local look = find(node, "LookStandard")
			local before = look.Size.Y.Offset
			t.expect(before > 0).toBe(true)
			find(node, "RungLarge").Activated.fire(input(w, "mouse"))
			t.expect(built.report().controlSize).toBe("large")
			t.expect(look.Size.Y.Offset > before).toBe(true)
			built.steps.reset()
			t.expect(built.report().controlSize).toBe("compact")
			t.expect(look.Size.Y.Offset).toBe(before)
			built.steps.sizeRegular()
			t.expect(built.report().controlSize).toBe("regular")
			t.expect(look.Size.Y.Offset >= before).toBe(true)
			find(node, "Reset").Activated.fire(input(w, "mouse"))
			t.expect(built.report().controlSize).toBe("compact")
			t.expect(look.Size.Y.Offset).toBe(before)
			stop()
			t.expect(built.report()).toBe(nil)
			w.runtime:dispose()
		end
	)

	t.it("navigation-5-45 all controls nests page tabs inside the adaptable group navigation", function()
		local groups = load("fixture", "all_controls").groups
		t.expect(#groups > 1 and #groups[1].tabs > 1).toBe(true)
		local g = galleryWorld()
		local outer = find(g.root, "Categories")
		t.expect(outer ~= nil).toBe(true)
		for _, group in groups do
			t.expect(find(outer, group.id, "TextButton") ~= nil).toBe(true)
		end
		local inner = find(outer, groups[1].id, "Frame")
		t.expect(inner ~= nil).toBe(true)
		for _, tab in groups[1].tabs do
			local button = find(inner, tab.id, "TextButton")
			t.expect(button ~= nil).toBe(true)
			t.expect(button:HasTag("facet-tab-item")).toBe(true)
		end
		t.expect(find(outer, groups[1].id, "TextButton"):HasTag("facet-tab-current")).toBe(true)
		t.expect(find(inner, groups[1].tabs[1].id, "TextButton"):HasTag("facet-tab-current")).toBe(true)
		t.expect(g.ctx.currentReport().active).toBe(groups[1].tabs[1].id)
		local second = groups[1].tabs[2].id
		find(inner, second, "TextButton").Activated.fire(input(g, "mouse"))
		t.expect(g.ctx.currentReport().active).toBe(second)
		t.expect(find(inner, second, "TextButton"):HasTag("facet-tab-current")).toBe(true)
		t.expect(find(inner, groups[1].tabs[1].id, "TextButton"):HasTag("facet-tab-current")).toBe(false)
		find(outer, groups[2].id, "TextButton").Activated.fire(input(g, "mouse"))
		t.expect(g.ctx.currentReport().active).toBe(groups[2].tabs[1].id)
		find(outer, groups[1].id, "TextButton").Activated.fire(input(g, "mouse"))
		t.expect(g.ctx.currentReport().active).toBe(second)
		g.stop()
	end)

	t.it("paint-47 progress mounts inside all controls and its rung and value controls drive the indicators", function()
		local g = galleryWorld()
		find(g.root, "indicators", "TextButton").Activated.fire(input(g, "mouse"))
		t.expect(g.ctx.currentReport().active).toBe("progress")
		local page = find(g.root, "ProgressRing")
		t.expect(page ~= nil).toBe(true)
		for _, name in { "Bar", "Ring", "Busy", "Dots" } do
			t.expect(find(page, name) ~= nil).toBe(true)
		end
		t.expect(find(find(page, "Ring"), "Indicator").Size.X.Offset).toBe(120)
		local busy, dots = find(find(page, "Busy"), "Indicator"), find(find(page, "Dots"), "Indicator")
		find(page, "Compact").Activated.fire(input(g, "mouse"))
		local compact, compactDots = busy.Size.X.Offset, dots.Size.X.Offset
		t.expect(compact > 0).toBe(true)
		t.expect(busy.Size.Y.Offset).toBe(compact)
		find(page, "Large").Activated.fire(input(g, "mouse"))
		t.expect(busy.Size.X.Offset > compact).toBe(true)
		t.expect(dots.Size.X.Offset > compactDots).toBe(true)
		t.expect(busy.Size.Y.Offset).toBe(busy.Size.X.Offset)
		local example = g.ctx.currentReport().example
		t.expect(example.controlSize).toBe("large")
		local function hasText(root: any, text: string): boolean
			for _, node in root:GetDescendants() do
				if (node:IsA("TextLabel") or node:IsA("TextButton")) and node.Text == text then
					return true
				end
			end
			return false
		end
		t.expect(hasText(find(page, "Bar"), "1 of 5")).toBe(true)
		g.stop()
		local w = world()
		local built, node, stop = mountBuilt(w, load("fixture", "progress_ring"))
		t.expect(built.steps.setProgress65().progress).toBe(0.65)
		t.expect(hasText(find(node, "Bar"), "3 of 5")).toBe(true)
		t.expect(built.steps.sizeLarge().controlSize).toBe("large")
		local large = find(find(node, "Busy"), "Indicator").Size.X.Offset
		t.expect(built.steps.sizeCompact().controlSize).toBe("compact")
		t.expect(find(find(node, "Busy"), "Indicator").Size.X.Offset < large).toBe(true)
		stop()
		w.runtime:dispose()
	end)

	t.it("paint-125 all controls opens on the basics fixture with its settings and actions mounted", function()
		local g = galleryWorld()
		t.expect(g.ctx.active:peek()).toBe("all-controls")
		t.expect(g.ctx.currentReport().active).toBe("basics")
		local screen = find(g.root, "AdaptiveScreen")
		t.expect(screen ~= nil).toBe(true)
		t.expect(find(screen, "Save", "TextButton") ~= nil).toBe(true)
		t.expect(find(screen, "Volume") ~= nil).toBe(true)
		t.expect(g.ctx.errorMessage:peek()).toBe(nil)
		find(g.root, "choices", "TextButton").Activated.fire(input(g, "mouse"))
		t.expect(find(g.root, "SelectionControls") ~= nil).toBe(true)
		t.expect(g.ctx.errorMessage:peek()).toBe(nil)
		g.stop()
		t.expect(#g.target:GetChildren()).toBe(0)
	end)
end)
