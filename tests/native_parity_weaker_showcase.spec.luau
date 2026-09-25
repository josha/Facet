--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local glade = require("../examples/reference/p1_glade")
local sipworks = require("../examples/reference/p3_sipworks")
local foyer = require("../examples/reference/p4_foyer")
local Compose = Facet.Compose

type World = {
	engine: any,
	runtime: any,
	gui: any,
	input: any,
	parent: any,
	screen: any,
	root: any,
	built: any,
	stop: () -> (),
}

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

local function within(node: any, ancestor: any): boolean
	return node ~= nil and (node == ancestor or node:IsDescendantOf(ancestor))
end

local function V2(w: any, x: number, y: number): any
	return w.engine.types.Vector2.new(x, y)
end

local function services(engine: any): (any, any)
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
	input.GetFocusedTextBox = function()
		return nil
	end
	input.IsKeyDown = function()
		return false
	end
	return gui, input
end

local function referenceWorld(module: any, preferred: string): World
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui, input = services(engine)
	input.PreferredInput = (engine.types.Enum.PreferredInput :: any)[preferred]
	local parent = engine.new("Folder")
	local built
	local stop, root = runtime.mount(function()
		built = module.build({
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = runtime.constructors,
			UI = Facet.controls(
				runtime,
				{
					types = engine.types,
					guiService = gui,
					inputParent = parent,
					reducedMotion = Compose.cell(true),
					services = { GuiService = gui, UserInputService = input },
				} :: any
			),
			types = engine.types,
			viewport = Compose.cell({ width = 1000, height = 720 }),
			heartbeat = engine.heartbeat,
		})
		return runtime.constructors.ScreenGui "App" { built.screen() }
	end, parent)
	return {
		engine = engine,
		runtime = runtime,
		gui = gui,
		input = input,
		parent = parent,
		screen = root,
		root = root:GetChildren()[1],
		built = built,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
end

local function tab(w: any)
	local traverse = assert(find(w.parent, "FacetTraversal"), "the traversal context exists")
	traverse:FindFirstChild("Traverse").Pressed.fire()
end

local function pad(w: any, key: string)
	w.input.InputBegan.fire({
		KeyCode = (w.engine.types.Enum.KeyCode :: any)[key],
		UserInputType = w.engine.types.Enum.UserInputType.Gamepad1,
	}, true)
end

local function ring(w: any): { any }
	local seen: { any } = {}
	if w.gui.SelectedObject == nil then
		tab(w)
	end
	local start = w.gui.SelectedObject
	local guard = 0
	repeat
		table.insert(seen, w.gui.SelectedObject)
		tab(w)
		guard += 1
	until w.gui.SelectedObject == start or w.gui.SelectedObject == nil or guard > 400
	t.expect(w.gui.SelectedObject).toBe(start)
	return seen
end

local function galleryWorld(configure: ((any) -> ())?): any
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui, input = services(engine)
	local parent = engine.new("Folder")
	local ctx: any = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
		types = engine.types,
		viewport = Compose.cell({ width = 1280, height = 800 }),
		inputTarget = parent,
		worldTarget = engine.new("Folder"),
		guiService = gui,
		inputService = input,
		runService = { Heartbeat = engine.heartbeat },
		selection = Compose.cell("all-controls"),
		theme = Compose.cell(Facet.themes.neutralPackage()),
		themeMode = Compose.cell("light"),
		demos = { { id = "all-controls", title = "All controls", kind = "fixture", module = "all_controls" } },
		load = function(_, module)
			return (require :: any)("../examples/gallery/scenarios/" .. module)
		end,
	}
	ctx.packages = { Neutral = ctx.theme:peek() }
	if configure then
		configure(ctx)
	end
	local gallery = require("../examples/gallery/client/screen")
	local stop, root = runtime.mount(function()
		gallery.configure(ctx)
		ctx.UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				viewport = ctx.viewport,
				inputParent = parent,
				guiService = gui,
				services = { GuiService = gui, UserInputService = input },
				theme = ctx.theme,
				reducedMotion = ctx.reducedMotion,
			} :: any
		)
		return ctx.Host.ScreenGui "GalleryTest" { gallery.build(ctx) }
	end, parent)
	return {
		engine = engine,
		runtime = runtime,
		gui = gui,
		input = input,
		parent = parent,
		ctx = ctx,
		root = root,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
end

local function tabView(root: any, view: string): any
	for _, node in root:GetDescendants() do
		if node.Name == view and node:FindFirstChild("Tabs") then
			return node
		end
	end
	return nil
end

local function strip(root: any, view: string): { any }
	local bar = tabView(root, view):FindFirstChild("Tabs")
	local buttons = {}
	for _, child in bar:GetChildren() do
		if child:IsA("TextButton") then
			table.insert(buttons, child)
		end
	end
	table.sort(buttons, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	return buttons
end

local function input(w: any, kind: string): any
	local E = w.engine.types.Enum
	if kind == "mouse" then
		return { UserInputType = E.UserInputType.MouseButton1, KeyCode = E.KeyCode.Unknown }
	elseif kind == "touch" then
		return { UserInputType = E.UserInputType.Touch, KeyCode = E.KeyCode.Unknown }
	elseif kind == "gamepad" then
		return { UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.ButtonA }
	end
	return { UserInputType = E.UserInputType.Keyboard, KeyCode = E.KeyCode.Return }
end

local function scenarioWorld(name: string, options: any?): (any, any, any)
	local opts = options or {}
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui, service = services(engine)
	if opts.input then
		service.PreferredInput = (engine.types.Enum.PreferredInput :: any)[opts.input]
	end
	if opts.text then
		gui.PreferredTextSize = (engine.types.Enum.PreferredTextSize :: any)[opts.text]
	end
	local parent = engine.new("Folder")
	local theme = Compose.cell(opts.theme or Facet.themes.neutralPackage())
	local ctx: any = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
		types = engine.types,
		viewport = Compose.cell(opts.viewport or { width = 1280, height = 720 }),
		inputTarget = parent,
		worldTarget = engine.new("Folder"),
		guiService = gui,
		inputService = service,
		runService = { Heartbeat = engine.heartbeat },
		heartbeat = engine.heartbeat,
		theme = theme,
	}
	local world = {
		engine = engine,
		runtime = runtime,
		gui = gui,
		input = service,
		parent = parent,
		ctx = ctx,
	}
	local definition = (require :: any)("../examples/gallery/scenarios/" .. name)
	local built
	local gallery = require("../examples/gallery/client/screen")
	local stop, root = runtime.mount(function()
		gallery.configure(ctx)
		ctx.motionPreference:set(true)
		ctx.UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				viewport = ctx.viewport,
				guiService = gui,
				inputParent = parent,
				services = { GuiService = gui, UserInputService = service },
				theme = theme,
				reducedMotion = true,
			} :: any
		)
		local sheet = Facet.themes.createStyleSheet(runtime, theme, { types = engine.types })
		built = definition.build(ctx)
		if built.dispose then
			Compose.cleanup(built.dispose)
		end
		return ctx.Host.ScreenGui "Screen" {
			sheet,
			ctx.Host.StyleLink({ StyleSheet = Compose.static(sheet) }),
			built.screen(),
		}
	end, parent)
	world.root = root
	world.stop = function()
		stop()
		runtime:dispose()
	end
	return world, built, root
end

local PLACEMENTS = {
	{ name = "sidebar", size = { 1400, 900 }, input = "KeyboardAndMouse" },
	{ name = "bottomBar", size = { 390, 844 }, input = "Touch" },
	{ name = "bottomBarCompact", size = { 700, 360 }, input = "Touch" },
	{ name = "topBar", size = { 1920, 1080 }, input = "Gamepad" },
}

local function walkPlacements(module: any, cellOf: (any) -> any, ids: { string }, open: (any) -> ())
	for _, placement in PLACEMENTS do
		local w = referenceWorld(module, placement.input)
		local E = w.engine.types.Enum
		local view = assert(find(w.root, "Destinations"))
		view.AbsoluteSize = V2(w, placement.size[1], placement.size[2])
		local bar = assert(view:FindFirstChild("Tabs"))
		local pages = assert(find(view, "Content"))
		local layout = bar:FindFirstChildWhichIsA("UIListLayout")
		local label = placement.name
		if label == "sidebar" then
			t.expect(`{label} {layout.FillDirection.Name} {bar.Position.X.Offset}`).toBe(`{label} Vertical 8`)
			t.expect(pages.Position.X.Offset > 0).toBe(true)
		elseif label == "topBar" then
			t.expect(`{label} {layout.FillDirection.Name} {bar.Position.Y.Scale}`).toBe(`{label} Horizontal 0`)
			t.expect(pages.Position.Y.Offset).toBe(52)
		else
			t.expect(`{label} {layout.FillDirection.Name} {bar.Position.Y.Scale} {bar.Position.Y.Offset}`)
				.toBe(`{label} Horizontal 1 -44`)
		end
		t.expect(layout.SortOrder).toBe(E.SortOrder.LayoutOrder)
		local buttons = {}
		for index, id in ids do
			local button = assert(find(bar, id, "TextButton"), `{label}: no {id} tab`)
			t.expect(`{label} {id} {button.Selectable} {button.Visible} {button.Interactable}`)
				.toBe(`{label} {id} true true true`)
			t.expect(button.LayoutOrder).toBe(index)
			buttons[index] = button
		end
		local forward = if label == "sidebar" then "NextSelectionDown" else "NextSelectionRight"
		local backward = if label == "sidebar" then "NextSelectionUp" else "NextSelectionLeft"
		for index, button in buttons do
			t.expect(`{label} {ids[index]} {forward} {(button :: any)[forward] == buttons[index + 1]}`)
				.toBe(`{label} {ids[index]} {forward} true`)
			t.expect(`{label} {ids[index]} {backward} {(button :: any)[backward] == buttons[index - 1]}`)
				.toBe(`{label} {ids[index]} {backward} true`)
		end
		t.expect(w.gui.SelectedObject).toBe(nil)
		pad(w, "DPadDown")
		t.expect(w.gui.SelectedObject).toBe(buttons[1])
		local stops = ring(w)
		for index, button in buttons do
			t.expect(`{label} ring {ids[index]} {table.find(stops, button) ~= nil}`)
				.toBe(`{label} ring {ids[index]} true`)
		end
		local content = 0
		for _, stop in stops do
			if within(stop, pages) then
				content += 1
			end
			t.expect(stop.Selectable and stop.Visible).toBe(true)
		end
		t.expect(`{label} content stops {content > 0}`).toBe(`{label} content stops true`)
		for step = 2, #buttons do
			t.expect(table.find(stops, buttons[step]) > table.find(stops, buttons[step - 1])).toBe(true)
		end
		local cell = cellOf(w.built)
		for index = #ids, 1, -1 do
			local id = ids[index]
			w.gui.SelectedObject = buttons[index]
			t.expect(w.gui.SelectedObject).toBe(buttons[index])
			buttons[index].Activated.fire()
			t.expect(`{label} {cell:peek()}`).toBe(`{label} {id}`)
			local panel = assert(pages:FindFirstChild(id, true), `{label}: no {id} page`)
			t.expect(panel.Visible).toBe(true)
			local selected = w.gui.SelectedObject
			t.expect(`{label} {id} away {within(selected, panel) or selected == buttons[index]}`)
				.toBe(`{label} {id} away true`)
		end
		t.expect(#w.engine.rejectedSelections).toBe(0)
		open(w.built)
		local sheet = assert(find(w.screen, "SheetPanel"), `{label}: no sheet`)
		local inside = ring(w)
		local close
		for _, stop in inside do
			t.expect(`{label} modal stop inside {within(stop, sheet)}`).toBe(`{label} modal stop inside true`)
			if stop.Name == "Close" then
				close = stop
			end
		end
		t.expect(`{label} dismissal reachable {close ~= nil}`).toBe(`{label} dismissal reachable true`)
		close.Activated.fire()
		t.expect(find(w.screen, "SheetPanel")).toBeNil()
		w.stop()
	end
end

t.describe("native parity weaker showcase", function()
	t.it(
		"apps-24 Glade walks every nav placement: entry, the Tab ring, linked tab order, activation away and modal dismissal",
		function()
			walkPlacements(glade, function(built)
				return built.model.section
			end, { "glades", "favorites", "wisps", "flora", "keeper" }, function(built)
				built.steps.open("mossholm")
			end)
		end
	)

	t.it(
		"apps-90 Sipworks walks every nav placement: entry, the Tab ring, linked tab order, activation away and modal dismissal",
		function()
			walkPlacements(sipworks, function(built)
				return built.model.section
			end, { "menu", "favorites", "rewards", "book" }, function(built)
				built.steps.open("lantern-oolong")
			end)
		end
	)

	t.it(
		"apps-102 Foyer walks every nav placement: entry, the Tab ring, linked tab order, activation away and modal dismissal",
		function()
			walkPlacements(foyer, function(built)
				return built.model.destination
			end, { "home", "crews", "forge", "mail", "you" }, function(built)
				built.steps.open("moss-kingdom")
			end)
		end
	)

	t.it(
		"apps2-225 links each showcase strip tab to its declared neighbours at every stage size and preview so DPadRight cannot skip",
		function()
			local sizes = {
				{ "phone", 390, 844 },
				{ "tablet", 1024, 768 },
				{ "desktop", 1440, 900 },
				{ "tv", 1920, 1080 },
			}
			for _, size in sizes do
				local w = galleryWorld(function(ctx)
					ctx.viewport:set({ width = size[2], height = size[3] })
				end)
				local scale = find(w.root, "ViewingDistance", "UIScale")
				for _, distance in { "automatic", "near", "ten-foot" } do
					w.ctx.viewingDistance:set(distance)
					t.expect(scale.Scale).toBe(if distance == "ten-foot" then 1.5 else 1)
					for _, input in { "Gamepad", "KeyboardAndMouse" } do
						w.input.PreferredInput = (w.engine.types.Enum.PreferredInput :: any)[input]
						for _, view in { { "inputs", "basics", "writing" }, { "Categories", "inputs", "actions" } } do
							local buttons = strip(w.root, view[1])
							local label = `{size[1]} {distance} {input} {view[1]}`
							t.expect(`{label} {buttons[1].Name} {buttons[2].Name}`).toBe(`{label} {view[2]} {view[3]}`)
							for index, button in buttons do
								t.expect(
									`{label} {button.Name} right {button.NextSelectionRight == buttons[index + 1]}`
								)
									.toBe(`{label} {button.Name} right true`)
								t.expect(`{label} {button.Name} left {button.NextSelectionLeft == buttons[index - 1]}`)
									.toBe(`{label} {button.Name} left true`)
								t.expect(button.NextSelectionUp == nil and button.NextSelectionDown == nil).toBe(true)
							end
							w.gui.SelectedObject = buttons[1]
							local walked = { buttons[1].Name }
							while w.gui.SelectedObject.NextSelectionRight do
								w.gui.SelectedObject = w.gui.SelectedObject.NextSelectionRight
								table.insert(walked, w.gui.SelectedObject.Name)
							end
							local names = {}
							for _, button in buttons do
								table.insert(names, button.Name)
							end
							t.expect(`{label} {table.concat(walked, ",")}`).toBe(`{label} {table.concat(names, ",")}`)
						end
					end
				end
				t.expect(#w.engine.rejectedSelections).toBe(0)
				w.stop()
			end
		end
	)

	t.it("apps2-225 relinks a strip when a tab is disabled or hidden and in a sidebar links vertically", function()
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local gui, input = services(engine)
		local UI = Facet.controls(
			runtime,
			{ types = engine.types, guiService = gui, services = { GuiService = gui, UserInputService = input } } :: any
		)
		local Host = runtime.constructors
		local selection, enabled = Compose.cell("a"), Compose.cell(true)
		local customization = Compose.cell(nil :: any)
		local stop, root = runtime.mount(function()
			return Host.ScreenGui {
				UI.TabView "Strip" {
					selection = selection,
					customization = customization,
					tabs = {
						{
							id = "a",
							label = "A",
							content = function()
								return Host.Frame "APage" {}
							end,
						},
						{
							id = "b",
							label = "B",
							enabled = enabled,
							content = function()
								return Host.Frame "BPage" {}
							end,
						},
						{
							id = "c",
							label = "C",
							content = function()
								return Host.Frame "CPage" {}
							end,
						},
					},
				},
			}
		end, engine.new("Folder"))
		local view = find(root, "Strip")
		view.AbsoluteSize = engine.types.Vector2.new(390, 844)
		local a, b, c = find(view, "a", "TextButton"), find(view, "b", "TextButton"), find(view, "c", "TextButton")
		t.expect(a.NextSelectionRight).toBe(b)
		t.expect(b.NextSelectionRight).toBe(c)
		t.expect(c.NextSelectionLeft).toBe(b)
		enabled:set(false)
		t.expect(a.NextSelectionRight).toBe(c)
		t.expect(c.NextSelectionLeft).toBe(a)
		t.expect(b.NextSelectionRight).toBe(nil)
		t.expect(b.NextSelectionLeft).toBe(nil)
		enabled:set(true)
		t.expect(a.NextSelectionRight).toBe(b)
		customization:set({ order = { "c", "a", "b" }, hidden = { "a" } })
		t.expect(c.NextSelectionRight).toBe(b)
		t.expect(b.NextSelectionLeft).toBe(c)
		t.expect(b.NextSelectionRight).toBe(nil)
		customization:set(nil)
		a = find(view, "a", "TextButton")
		view.AbsoluteSize = engine.types.Vector2.new(1400, 900)
		t.expect(a.NextSelectionDown).toBe(b)
		t.expect(b.NextSelectionUp).toBe(a)
		t.expect(b.NextSelectionDown).toBe(c)
		t.expect(a.NextSelectionRight).toBe(nil)
		t.expect(b.NextSelectionLeft).toBe(nil)
		stop()
		runtime:dispose()
	end)

	t.it(
		"mech2-25 the Tab walk never stops on or under the powered-off panel, still reaches After and returns when on",
		function()
			for _, package in
				{
					Facet.themes.neutralPackage(),
					((require("../examples/themes/pixel_quest") :: any).build(Facet.themes)),
				}
			do
				local w, built, root = scenarioWorld("inherited_subtree", { theme = package })
				local go, inner, after = find(root, "Go"), find(root, "InnerGo"), find(root, "After")
				local power = find(root, "PowerToggle")
				local function names(): { [string]: boolean }
					local seen = {}
					for _, stop in ring(w) do
						seen[stop.Name] = true
					end
					return seen
				end
				local on = names()
				t.expect(on.Go and on.InnerGo and on.After and on.PowerToggle).toBe(true)
				w.gui.SelectedObject = go
				power.Activated.fire(input(w, "keyboard"))
				t.expect(built.report().enabled).toBe(false)
				t.expect(w.gui.SelectedObject).toBe(after)
				local off = names()
				t.expect(off.Go == nil and off.InnerGo == nil).toBe(true)
				t.expect(off.After and off.PowerToggle).toBe(true)
				w.gui.SelectedObject = power
				tab(w)
				local guard = 0
				while w.gui.SelectedObject ~= after and guard < 40 do
					t.expect(w.gui.SelectedObject ~= go and w.gui.SelectedObject ~= inner).toBe(true)
					tab(w)
					guard += 1
				end
				t.expect(w.gui.SelectedObject).toBe(after)
				power.Activated.fire(input(w, "gamepad"))
				t.expect(built.report().enabled).toBe(true)
				local again = names()
				t.expect(again.Go and again.InnerGo).toBe(true)
				w.stop()
			end
		end
	)

	t.it(
		"inputs-77 every input class requests the completed click once and a disabled demo requests nothing",
		function()
			local w, built, root = scenarioWorld("sensory_feedback")
			local release = find(root, "Release")
			for index, kind in { "mouse", "touch", "gamepad", "keyboard" } do
				release.Activated.fire(input(w, kind))
				t.expect(built.requests:peek()).toBe(index)
				t.expect(built.effects.release.PlayCount).toBe(index)
				t.expect(built.steps.readHistory()[1]).toBe(`{index}. release`)
			end
			t.expect(built.effects.press.PlayCount == nil or built.effects.press.PlayCount == 0).toBe(true)
			t.expect(find(root, "Press").PressHapticEffect).toBe(built.effects.press)
			find(root, "Custom").Activated.fire(input(w, "gamepad"))
			t.expect(built.effects.custom.PlayCount).toBe(1)
			t.expect(built.report().motorConfirmed).toBe(false)
			built.steps.setPlayHaptics(false)
			for _, kind in { "mouse", "touch", "gamepad", "keyboard" } do
				release.Activated.fire(input(w, kind))
			end
			t.expect(built.requests:peek()).toBe(5)
			t.expect(built.effects.release.PlayCount).toBe(4)
			t.expect(find(root, "Press").PressHapticEffect).toBe(nil)
			w.stop()
			for _, effect in built.effects do
				t.expect(effect.isDestroyed()).toBe(true)
			end
		end
	)

	local HUD_VIEWS = {
		{ "compact-phone-portrait", 359, 718, "Touch" },
		{ "compact-phone-landscape", 705, 338, "Touch" },
		{ "tablet-landscape", 1079, 809, "Touch" },
		{ "desktop-standard", 1232, 1067, "KeyboardAndMouse" },
		{ "console-ten-foot", 1920, 1078, "Gamepad" },
		{ "handheld-gamepad", 960, 540, "Gamepad" },
		{ "compact-gamepad", 390, 844, "Gamepad" },
		{ "narrow-portrait", 320, 640, "Touch" },
		{ "narrow-landscape", 640, 320, "Touch" },
		{ "desktop-studio-1320", 1320, 742, "KeyboardAndMouse" },
		{ "phone-390x844", 390, 844, "Touch" },
	}
	local HUD_ZONES = { "Tasks", "Clock", "Rail", "Health", "Actions", "Feed", "Readout", "Weapon" }

	local function hudShown(root: any): number
		local body = find(root.Parent or root, "OverflowBody")
		local count = 0
		for _, child in body:GetChildren() do
			if child:IsA("GuiObject") and child.Name ~= "OverflowNote" and child.Name ~= "OverflowEmpty" then
				count += 1
			end
		end
		return count
	end

	local function same(a: any, b: any): boolean
		for key, value in a do
			if b[key] ~= value then
				return false
			end
		end
		for key in b do
			if a[key] == nil then
				return false
			end
		end
		return true
	end

	t.it(
		"mech2-90 mounts the HUD at main's eleven viewports, recovers every stepped-down zone and settles each rotation like a fresh mount",
		function()
			local fresh = {}
			for _, view in HUD_VIEWS do
				local w, built, root = scenarioWorld("hud", {
					viewport = { width = view[2], height = view[3] },
					input = view[4],
				})
				local forms, unshown = built.report().forms, built.report().unshown
				local label = `{view[1]} {view[2]}x{view[3]}`
				for _, zone in HUD_ZONES do
					local regions = 0
					for _, node in root:GetDescendants() do
						if node.Name == zone and node.Parent and node.Parent.Name == "Content" then
							regions += 1
						end
					end
					t.expect(`{label} {zone} regions {regions}`).toBe(`{label} {zone} regions 1`)
					local expected = forms[zone] ~= "full"
					t.expect(`{label} {zone} unshown {table.find(unshown, zone) ~= nil}`)
						.toBe(`{label} {zone} unshown {expected}`)
				end
				local body = find(root, "HudBody")
				body.AbsoluteSize = V2(w, view[2] - 24, view[3] - 140)
				t.expect(same(built.report().forms, forms)).toBe(true)
				find(root, "Overflow").Activated.fire(input(w, "touch"))
				t.expect(built.report().overflowOpen).toBe(true)
				t.expect(`{label} recovered {hudShown(root)}`).toBe(`{label} recovered {#unshown}`)
				if #unshown == 0 then
					t.expect(find(root.Parent, "OverflowEmpty") ~= nil).toBe(true)
				end
				fresh[view[1]] = forms
				w.stop()
				t.expect(#w.parent:GetChildren()).toBe(0)
			end
			local w, built, root = scenarioWorld("hud", { viewport = { width = 1079, height = 809 } })
			local regions = {}
			for _, zone in HUD_ZONES do
				regions[zone] = find(root, zone)
			end
			local order = table.clone(HUD_VIEWS)
			for index = #HUD_VIEWS, 1, -1 do
				table.insert(order, HUD_VIEWS[index])
			end
			for _, view in order do
				w.ctx.viewport:set({ width = view[2], height = view[3] })
				t.expect(`{view[1]} rotated {same(built.report().forms, fresh[view[1]])}`)
					.toBe(`{view[1]} rotated true`)
				for _, zone in HUD_ZONES do
					t.expect(find(root, zone)).toBe(regions[zone])
				end
			end
			w.stop()
		end
	)

	t.it(
		"apps-208 a theme swap and the largest text re-run the HUD give-way from the new native body like a fresh mount there",
		function()
			local ornate = ((require :: any)("../examples/themes/fantasy_ornate").build(Facet.themes))
			local neutral = Facet.themes.neutralPackage()
			local function decided(theme: any, text: string?, body: { number }): any
				local w, built, root = scenarioWorld("hud", { theme = theme, text = text })
				find(root, "HudBody").AbsoluteSize = V2(w, body[1], body[2])
				local forms = built.report().forms
				w.stop()
				return forms
			end
			for _, step in { { neutral, ornate }, { ornate, neutral } } do
				for _, bodies in { { { 1040, 640 }, { 330, 250 } }, { { 330, 250 }, { 1040, 640 } } } do
					local w, built, root = scenarioWorld("hud", { theme = step[1] })
					local body = find(root, "HudBody")
					body.AbsoluteSize = V2(w, bodies[1][1], bodies[1][2])
					local before = built.report().forms
					w.ctx.theme:set(step[2])
					t.expect(same(built.report().forms, before)).toBe(true)
					body.AbsoluteSize = V2(w, bodies[2][1], bodies[2][2])
					local want = decided(step[2], nil, bodies[2])
					t.expect(same(want, before)).toBe(false)
					t.expect(same(built.report().forms, want)).toBe(true)
					w.gui.PreferredTextSize = w.engine.types.Enum.PreferredTextSize.Largest
					body.AbsoluteSize = V2(w, bodies[1][1], bodies[1][2])
					t.expect(same(built.report().forms, decided(step[2], "Largest", bodies[1]))).toBe(true)
					w.stop()
				end
			end
		end
	)

	t.it(
		"mech3-59 mounts the HUD on a world-fixed SurfaceGui and decides from its canvas like a screen of that size",
		function()
			for _, canvas in { { 1024, 768 }, { 640, 480 }, { 320, 640 } } do
				local engine: any = engineLib.new()
				local runtime = Facet.Roblox.createRuntime(engine)
				local gui, service = services(engine)
				local part, holder = engine.new("Part"), engine.new("Folder")
				local viewport = Compose.cell({ width = canvas[1], height = canvas[2] })
				local ctx: any = {
					Facet = Facet,
					Compose = Compose,
					runtime = runtime,
					Host = runtime.constructors,
					types = engine.types,
					viewport = viewport,
					guiService = gui,
					inputService = service,
				}
				ctx.UI = Facet.controls(
					runtime,
					{
						types = engine.types,
						viewport = viewport,
						guiService = gui,
						services = { GuiService = gui, UserInputService = service },
					} :: any
				)
				local hud = require("../examples/gallery/scenarios/hud") :: any
				local built
				local stop, surface = runtime.mount(function()
					built = hud.build(ctx)
					return ctx.Host.SurfaceGui "HudSurface" {
						Adornee = part,
						Face = engine.types.Enum.NormalId.Front,
						SizingMode = engine.types.Enum.SurfaceGuiSizingMode.FixedSize,
						CanvasSize = engine.types.Vector2.new(canvas[1], canvas[2]),
						built.screen(),
					}
				end, holder)
				t.expect(surface.ClassName).toBe("SurfaceGui")
				t.expect(surface.CanvasSize.X).toBe(canvas[1])
				t.expect(surface.Adornee).toBe(part)
				local body = find(surface, "HudBody")
				t.expect(body ~= nil).toBe(true)
				local screenWorld, screenBuilt =
					scenarioWorld("hud", { viewport = { width = canvas[1], height = canvas[2] } })
				t.expect(same(built.report().forms, screenBuilt.report().forms)).toBe(true)
				body.AbsoluteSize = engine.types.Vector2.new(canvas[1] - 24, canvas[2] - 140)
				find(screenWorld.root, "HudBody").AbsoluteSize = V2(screenWorld, canvas[1] - 24, canvas[2] - 140)
				t.expect(same(built.report().forms, screenBuilt.report().forms)).toBe(true)
				screenWorld.stop()
				find(surface, "Overflow").Activated.fire()
				t.expect(built.report().overflowOpen).toBe(true)
				t.expect(find(surface, "OverflowBody") ~= nil).toBe(true)
				local signal = body:GetPropertyChangedSignal("AbsoluteSize")
				stop()
				runtime:dispose()
				t.expect(surface.isDestroyed()).toBe(true)
				t.expect(#holder:GetChildren()).toBe(0)
				t.expect(signal.count()).toBe(0)
			end
		end
	)
end)
