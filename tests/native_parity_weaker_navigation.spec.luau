--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local Compose = Facet.Compose

type World = {
	engine: any,
	runtime: any,
	gui: any,
	input: any,
	screen: any,
	stop: () -> (),
}

local function setup(build: (any, any, any) -> any, options: { [string]: any }?): World
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.GetFocusedTextBox = function()
		return nil
	end
	input.IsKeyDown = function()
		return false
	end
	local config: { [string]: any } = {
		types = engine.types,
		guiService = gui,
		services = { GuiService = gui, UserInputService = input },
	}
	for key, value in (options or {}) :: { [string]: any } do
		config[key] = value
	end
	local UI = Facet.controls(runtime, config :: any)
	local Host = runtime.constructors
	local stop, screen = runtime.mount(function()
		return Host.ScreenGui({ build(UI, Host, engine) })
	end, engine.new("Folder"))
	return {
		engine = engine,
		runtime = runtime,
		gui = gui,
		input = input,
		screen = screen,
		stop = function()
			stop()
			runtime:dispose()
		end,
	}
end

local function settle(engine: any)
	for _ = 1, 60 do
		engine.heartbeat.fire(1 / 60)
	end
end

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

local function action(root: any, name: string): any
	for _, node in root:GetDescendants() do
		if node:IsA("InputContext") and node.Name == "Facet" .. name and node.Enabled then
			return node:FindFirstChild(name)
		end
	end
	return nil
end

local function V2(world: World, x: number, y: number): any
	return world.engine.types.Vector2.new(x, y)
end

local function page(Host: any, name: string): () -> any
	return function()
		return Host.Frame(name .. "Body")({})
	end
end

local function galleryFixture(build: (any) -> any): (any, any, () -> (), any)
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local target, gui = engine.new("Folder"), engine.new("GuiService")
	local input = engine.new("UserInputService")
	input.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
	input.GetFocusedTextBox = function()
		return nil
	end
	input.IsKeyDown = function()
		return false
	end
	local ctx: any = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
		types = engine.types,
		viewport = Compose.cell({ width = 1280, height = 800 }),
		inputTarget = target,
		worldTarget = engine.new("Folder"),
		guiService = gui,
		inputService = input,
		runService = { Heartbeat = engine.heartbeat },
		selection = Compose.cell("all-controls"),
		theme = Compose.cell(Facet.themes.neutralPackage()),
		themeMode = Compose.cell("light"),
		engine = engine,
	}
	ctx.packages = { Neutral = ctx.theme:peek() }
	local gallery = require("../examples/gallery/client/screen")
	local stop, root = runtime.mount(function()
		gallery.configure(ctx)
		ctx.UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				viewport = ctx.viewport,
				inputParent = target,
				guiService = gui,
				services = { GuiService = gui, UserInputService = input },
				theme = ctx.theme,
				reducedMotion = ctx.reducedMotion,
			} :: any
		)
		return ctx.Host.ScreenGui("GalleryTest")({ build(ctx) })
	end, target)
	return ctx, root, stop, target
end

local function tabView(root: any, view: string): any
	for _, node in root:GetDescendants() do
		if node.Name == view and node:FindFirstChild("Tabs") then
			return node
		end
	end
	return nil
end

local function tabButton(root: any, view: string, id: string): any
	local node = tabView(root, view)
	return if node then find(node:FindFirstChild("Tabs"), id, "TextButton") else nil
end

local function journeyFixture(theme: any, input: string): (any, any, any, () -> ())
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local target, gui = engine.new("Folder"), engine.new("GuiService")
	local service = engine.new("UserInputService")
	service.PreferredInput = (engine.types.Enum.PreferredInput :: any)[input]
	service.GetFocusedTextBox = function()
		return nil
	end
	service.IsKeyDown = function()
		return false
	end
	local ctx: any = {
		Facet = Facet,
		Compose = Compose,
		Host = runtime.constructors,
		runtime = runtime,
		types = engine.types,
		viewport = Compose.cell({ width = 1280, height = 720 }),
		guiService = gui,
		inputService = service,
		inputTarget = target,
		runService = { Heartbeat = engine.heartbeat },
		reducedMotion = Compose.cell(true),
		pageVisible = Compose.cell(true),
		engine = engine,
	}
	ctx.UI = Facet.controls(
		runtime,
		{
			types = engine.types,
			viewport = ctx.viewport,
			guiService = gui,
			services = { GuiService = gui, UserInputService = service },
			inputParent = target,
			reducedMotion = ctx.reducedMotion,
			theme = theme,
		} :: any
	)
	local built
	local stop, node = runtime.mount(function()
		built = require("../examples/gallery/scenarios/navigation_stack").build(ctx)
		return ctx.Host.ScreenGui({ built.screen() })
	end, target)
	ctx.target = target
	return built,
		node,
		ctx,
		function()
			stop()
			t.expect(#target:GetChildren()).toBe(0)
			t.expect(engine.census().live).toBe(3)
			t.expect(engine.census().connections).toBe(0)
			runtime:dispose()
		end
end

t.describe("native parity weaker navigation", function()
	t.it("places the empty-center ring Back in the south-west compass slot and closes from the root", function()
		local opened = Compose.cell(true)
		local world = setup(function(UI)
			return UI.RadialMenu({
				isPresented = opened,
				distribution = "compass",
				center = "empty",
				items = {
					{ id = "N", slot = "N", label = "N" },
					{ id = "E", slot = "E", label = "E" },
					{ id = "S", slot = "S", label = "S" },
					{ id = "W", slot = "W", label = "W" },
				},
			})
		end, { reducedMotion = true })
		t.expect(find(world.screen, "Center")).toBeNil()
		local north, south = find(world.screen, "N", "TextButton"), find(world.screen, "S", "TextButton")
		local cx = north.Position.X.Offset
		local cy = (north.Position.Y.Offset + south.Position.Y.Offset) / 2
		local ring = find(world.screen, "$navigation", "TextButton")
		t.expect(ring.Text).toBe("Close")
		local dx, dy = ring.Position.X.Offset - cx, ring.Position.Y.Offset - cy
		local angle = math.deg(math.atan2(dx, -dy)) % 360
		t.expect(math.abs(angle - 225) < 1).toBe(true)
		t.expect(math.abs(math.sqrt(dx * dx + dy * dy) - (cy - north.Position.Y.Offset)) < 1).toBe(true)
		ring.Activated.fire()
		t.expect(opened:peek()).toBe(false)
		world.stop()
	end)

	t.it("keeps the empty-center Back inside a corner arc and returns one level from a branch", function()
		local opened = Compose.cell(true)
		local world = setup(function(UI)
			return UI.RadialMenu({
				isPresented = opened,
				preset = "bottom-left",
				center = "empty",
				items = {
					{ id = "Gear", label = "Gear", children = { { id = "Use", label = "Use" } } },
					{ id = "Map", label = "Map" },
				},
			})
		end, { reducedMotion = true })
		t.expect(find(world.screen, "Center")).toBeNil()
		local gear, map = find(world.screen, "Gear", "TextButton"), find(world.screen, "Map", "TextButton")
		local ring = find(world.screen, "$navigation", "TextButton")
		t.expect(ring.Text).toBe("Close")
		local xs = { gear.Position.X.Offset, map.Position.X.Offset, ring.Position.X.Offset }
		local ys = { gear.Position.Y.Offset, map.Position.Y.Offset, ring.Position.Y.Offset }
		t.expect(xs[1] < xs[2] and xs[2] < xs[3]).toBe(true)
		t.expect(ys[1] < ys[2] and ys[2] < ys[3]).toBe(true)
		gear.Activated.fire()
		local back = find(world.screen, "$navigation", "TextButton")
		t.expect(back.Text).toBe("Back")
		t.expect(find(world.screen, "Use", "TextButton") ~= nil).toBe(true)
		back.Activated.fire()
		t.expect(opened:peek()).toBe(true)
		t.expect(find(world.screen, "Use", "TextButton")).toBeNil()
		t.expect(find(world.screen, "Gear", "TextButton") ~= nil).toBe(true)
		find(world.screen, "$navigation", "TextButton").Activated.fire()
		t.expect(opened:peek()).toBe(false)
		world.stop()
	end)

	t.it("backs a radial branch out with ButtonB and returns the selection to the parent item", function()
		for _, navigation in { "replace", "expand" } do
			local opened = Compose.cell(true)
			local world = setup(function(UI)
				return UI.RadialMenu({
					isPresented = opened,
					navigation = navigation,
					items = {
						{
							id = "Gear",
							label = "Gear",
							children = {
								{
									id = "Tools",
									label = "Tools",
									navigation = "expand",
									children = { { id = "Use", label = "Use", completion = "stay" } },
								},
							},
						},
						{ id = "Map", label = "Map" },
					},
				})
			end, { reducedMotion = true })
			world.gui.SelectedObject = find(world.screen, "Gear", "TextButton")
			find(world.screen, "Gear", "TextButton").Activated.fire()
			world.gui.SelectedObject = find(world.screen, "Tools", "TextButton")
			find(world.screen, "Tools", "TextButton").Activated.fire()
			world.gui.SelectedObject = find(world.screen, "Use", "TextButton")
			find(world.screen, "Use", "TextButton").Activated.fire()
			t.expect(find(world.screen, "Use", "TextButton") ~= nil).toBe(true)
			action(world.screen, "ModalBack").Pressed.fire()
			t.expect(opened:peek()).toBe(true)
			t.expect(find(world.screen, "Use", "TextButton")).toBeNil()
			t.expect(world.gui.SelectedObject).toBe(find(world.screen, "Tools", "TextButton"))
			action(world.screen, "ModalBack").Pressed.fire()
			t.expect(find(world.screen, "Tools", "TextButton")).toBeNil()
			t.expect(world.gui.SelectedObject).toBe(find(world.screen, "Gear", "TextButton"))
			action(world.screen, "ModalBack").Pressed.fire()
			t.expect(opened:peek()).toBe(false)
			world.stop()
		end
	end)

	t.it("leaves the selection on the disclosure header when the header expands the group", function()
		local expanded = Compose.cell(false)
		local world = setup(function(UI)
			return UI.DisclosureGroup({
				expanded = expanded,
				label = "Advanced",
				content = function()
					return UI.Button("Inner")({ label = "Inner" })
				end,
			})
		end)
		local header = find(world.screen, "Header")
		world.gui.SelectedObject = header
		header.Activated.fire()
		t.expect(expanded:peek()).toBe(true)
		t.expect(find(world.screen, "Inner") ~= nil).toBe(true)
		t.expect(world.gui.SelectedObject).toBe(header)
		header.Activated.fire()
		t.expect(expanded:peek()).toBe(false)
		t.expect(find(world.screen, "Inner")).toBeNil()
		t.expect(world.gui.SelectedObject).toBe(header)
		world.stop()
	end)

	t.it("selects pages from the indicators and summarizes the current page", function()
		local selection = Compose.cell("one")
		local world = setup(function(UI, Host)
			local pages = {}
			for _, id in { "one", "two", "three" } do
				table.insert(pages, { id = id, title = id, content = Host.Frame(id .. "Body")({}) })
			end
			return UI.PageView("Pager")({ selection = selection, pages = pages })
		end)
		local indicators = find(world.screen, "Indicators")
		local summary = find(world.screen, "Summary")
		local layout = find(world.screen, "PagesLayout")
		t.expect(summary.Text).toBe("Page 1 of 3")
		find(indicators, "two", "TextButton").Activated.fire()
		t.expect(selection:peek()).toBe("two")
		t.expect(summary.Text).toBe("Page 2 of 3")
		t.expect(layout.CurrentPage.Name).toBe("two")
		selection:set("three")
		t.expect(summary.Text).toBe("Page 3 of 3")
		t.expect(layout.CurrentPage.Name).toBe("three")
		t.expect(find(world.screen, "Next").Interactable).toBe(false)
		layout:JumpTo(find(find(world.screen, "Pages"), "one"))
		t.expect(selection:peek()).toBe("one")
		t.expect(summary.Text).toBe("Page 1 of 3")
		t.expect(find(world.screen, "Previous").Interactable).toBe(false)
		find(indicators, "three", "TextButton").Activated.fire()
		t.expect(selection:peek()).toBe("three")
		world.stop()
	end)

	t.it("sizes every page to the pager viewport and moves the page with owner-held selection", function()
		local selection = Compose.cell("one")
		local world = setup(function(UI, Host)
			local pages = {}
			for _, id in { "one", "two", "three" } do
				table.insert(pages, { id = id, title = id, content = Host.Frame(id .. "Body")({}) })
			end
			return UI.PageView("Pager")({ selection = selection, pages = pages })
		end)
		local UDim2 = world.engine.types.UDim2
		local viewport = find(world.screen, "Pages")
		t.expect(viewport.ClipsDescendants).toBe(true)
		t.expect(viewport.Size.X).toBe(world.engine.types.UDim.new(1, 0))
		t.expect(viewport.Size.Y.Scale).toBe(1)
		local layout = viewport:FindFirstChildWhichIsA("UIPageLayout")
		t.expect(layout.FillDirection).toBe(world.engine.types.Enum.FillDirection.Horizontal)
		local count = 0
		for _, child in viewport:GetChildren() do
			if child:IsA("GuiObject") then
				count += 1
				t.expect(child.Size).toBe(UDim2.fromScale(1, 1))
			end
		end
		t.expect(count).toBe(3)
		selection:set("three")
		t.expect(layout.CurrentPage).toBe(viewport:FindFirstChild("three"))
		selection:set("two")
		t.expect(layout.CurrentPage).toBe(viewport:FindFirstChild("two"))
		world.stop()
	end)

	t.it("repeats push and Back from page content and releases each popped page", function()
		local path = Compose.cell({})
		local live, built = 0, {}
		local world = setup(function(UI)
			local function content(entry)
				local name = if entry then "detail" else "root"
				live += 1
				built[name] = (built[name] or 0) + 1
				Compose.cleanup(function()
					live -= 1
				end)
				return UI.Button(if entry then "Continue" else "Start")({
					label = if entry then "Continue" else "Start",
					onActivate = function()
						local nextPath = table.clone(path:peek())
						table.insert(nextPath, { id = "detail", value = #nextPath + 1 })
						path:set(nextPath)
					end,
				})
			end
			return UI.NavigationStack("Nav")({
				path = path,
				root = { title = "Home", content = content },
				destinations = { detail = { title = "Detail", content = content } },
				backLabel = "Back",
			})
		end)
		t.expect(live).toBe(1)
		local start = find(world.screen, "Start")
		for cycle = 1, 3 do
			find(world.screen, "Start").Activated.fire()
			t.expect(#path:peek()).toBe(1)
			t.expect(live).toBe(2)
			t.expect(built.detail).toBe(cycle)
			settle(world.engine)
			t.expect(world.engine.heartbeat.count()).toBe(0)
			t.expect(find(world.screen, "@root").Visible).toBe(false)
			t.expect(find(world.screen, "detail").Visible).toBe(true)
			find(find(world.screen, "detail"), "Back").Activated.fire()
			t.expect(#path:peek()).toBe(0)
			settle(world.engine)
			t.expect(world.engine.heartbeat.count()).toBe(0)
			t.expect(live).toBe(1)
			t.expect(find(world.screen, "detail")).toBeNil()
			t.expect(find(world.screen, "@root").Visible).toBe(true)
			t.expect(find(world.screen, "Start")).toBe(start)
		end
		t.expect(built.root).toBe(1)
		world.stop()
		t.expect(live).toBe(0)
	end)

	t.it("keeps the caller path through repeated routes and pop to root and releases every page", function()
		local path = Compose.cell({})
		local live, built, released = 0, 0, 0
		local world = setup(function(UI, Host)
			local function content(entry)
				live += 1
				built += 1
				Compose.cleanup(function()
					live -= 1
					released += 1
				end)
				return Host.Frame("Route" .. (if entry then tostring(entry.value) else "Home"))({})
			end
			return UI.NavigationStack("Nav")({
				path = path,
				root = { content = content },
				destinations = { step = { title = "Step", content = content } },
			})
		end)
		local first = { id = "step", value = 1 }
		local second = { id = "step", value = 2 }
		path:set({ first })
		t.expect(live).toBe(2)
		path:set({ first, second })
		t.expect(live).toBe(3)
		t.expect(find(world.screen, "Route2") ~= nil).toBe(true)
		path:set({ first, second })
		t.expect(built).toBe(3)
		local popped = table.clone(path:peek())
		table.remove(popped)
		path:set(popped)
		t.expect(live).toBe(2)
		t.expect(find(world.screen, "Route2")).toBeNil()
		t.expect(find(world.screen, "Route1") ~= nil).toBe(true)
		path:set({ first, { id = "step", value = 3 }, { id = "step", value = 4 } })
		t.expect(live).toBe(4)
		t.expect(find(world.screen, "Route4") ~= nil).toBe(true)
		action(world.screen, "NavigationBack").Pressed.fire()
		t.expect(#path:peek()).toBe(2)
		t.expect(path:peek()[1]).toBe(first)
		path:set({})
		t.expect(live).toBe(1)
		t.expect(find(world.screen, "RouteHome") ~= nil).toBe(true)
		t.expect(action(world.screen, "NavigationBack")).toBeNil()
		world.stop()
		t.expect(live).toBe(0)
		t.expect(released).toBe(built)
	end)

	t.it("steps the gallery catalogue forward and back with wrapping and full cycles", function()
		local gallery = require("../examples/gallery/client/screen")
		local demos = gallery.list()
		t.expect(#demos > 2).toBe(true)
		local first, last = demos[1].id, demos[#demos].id
		t.expect(gallery.next(first, 1)).toBe(demos[2].id)
		t.expect(gallery.next(last, 1)).toBe(first)
		t.expect(gallery.next(first, -1)).toBe(last)
		t.expect(gallery.next(demos[2].id, -1)).toBe(first)
		local id = first
		for _ = 1, #demos do
			id = gallery.next(id, 1)
		end
		t.expect(id).toBe(first)
		local fallback = gallery.next("not-a-demo", 1)
		local known = false
		for _, demo in demos do
			known = known or demo.id == fallback
		end
		t.expect(known).toBe(true)
		local ctx = {
			demos = demos,
			selection = Compose.cell(first),
			active = Compose.cell(first),
			errorMessage = Compose.cell(nil),
			themeName = Compose.cell("Neutral"),
			themeMode = Compose.cell("light"),
		}
		t.expect(gallery.dispatch(ctx, "next").current).toBe(demos[2].id)
		t.expect(gallery.dispatch(ctx, "showNext").current).toBe(demos[3].id)
		t.expect(gallery.dispatch(ctx, "next", -1).current).toBe(demos[2].id)
		gallery.dispatch(ctx, "next", -1)
		local wrapped = gallery.dispatch(ctx, "next", -1)
		t.expect(wrapped.ok).toBe(true)
		t.expect(wrapped.current).toBe(last)
		t.expect(gallery.dispatch(ctx, "next").current).toBe(first)
		for _ = 1, #demos do
			gallery.dispatch(ctx, "next")
		end
		t.expect(ctx.selection:peek()).toBe(first)
	end)

	t.it("mounts and selects every nested showcase tab at three sizes and releases the whole tree", function()
		for _, name in { "all_controls", "collections", "motion_layout" } do
			local scenario = require("../examples/gallery/scenarios/" .. name) :: any
			for _, size in { { 1280, 800 }, { 390, 844 }, { 844, 390 } } do
				local built
				local ctx, root, stop, target = galleryFixture(function(context)
					context.pageVisible = Compose.cell(true)
					built = scenario.build(context)
					if built.dispose then
						Compose.cleanup(built.dispose)
					end
					return built.screen()
				end)
				local categories = tabView(root, "Categories")
				categories.AbsoluteSize = V2({ engine = ctx.engine } :: any, size[1], size[2])
				for _, group in scenario.groups do
					tabButton(root, "Categories", group.id).Activated.fire()
					t.expect(built.report().selected.Categories).toBe(group.id)
					for _, tab in group.tabs do
						local button = tabButton(root, group.id, tab.id)
						t.expect(button ~= nil).toBe(true)
						button.Activated.fire()
						ctx.engine.heartbeat.fire(1 / 60)
						t.expect(built.report().active).toBe(tab.id)
						t.expect(built.report().selected[group.id]).toBe(tab.id)
					end
				end
				stop()
				t.expect(#target:GetChildren()).toBe(0)
				t.expect(ctx.engine.census().live).toBe(4)
				t.expect(ctx.engine.census().connections).toBe(0)
				ctx.runtime:dispose()
			end
		end
	end)

	t.it("adapts showcase category navigation while keeping the page and its inner top tabs", function()
		for _, name in { "all_controls", "collections", "motion_layout" } do
			local scenario = require("../examples/gallery/scenarios/" .. name) :: any
			local ctx, root, stop = galleryFixture(function(context)
				context.pageVisible = Compose.cell(true)
				return scenario.build(context).screen()
			end)
			local Enum, UDim2 = ctx.types.Enum, ctx.types.UDim2
			local first, tab = scenario.groups[1].id, scenario.groups[1].tabs[1].id
			local categories = tabView(root, "Categories")
			local function direction(view)
				return tabView(root, view):FindFirstChild("Tabs"):FindFirstChildWhichIsA("UIListLayout").FillDirection
			end
			categories.AbsoluteSize = ctx.types.Vector2.new(1280, 800)
			t.expect(direction("Categories")).toBe(Enum.FillDirection.Vertical)
			local inner = tabView(root, first)
			local button = tabButton(root, first, tab)
			local page = inner:FindFirstChild("Content"):FindFirstChild(tab)
			t.expect(page ~= nil).toBe(true)
			local function unchanged()
				t.expect(tabView(root, first)).toBe(inner)
				t.expect(tabButton(root, first, tab)).toBe(button)
				t.expect(inner:FindFirstChild("Content"):FindFirstChild(tab)).toBe(page)
				t.expect(direction(first)).toBe(Enum.FillDirection.Horizontal)
				t.expect(inner:FindFirstChild("Tabs").Position).toBe(UDim2.fromOffset(0, 0))
			end
			find(root, "UseTopTabs", "TextButton").Activated.fire()
			t.expect(direction("Categories")).toBe(Enum.FillDirection.Horizontal)
			unchanged()
			find(root, "UseSidebar", "TextButton").Activated.fire()
			t.expect(direction("Categories")).toBe(Enum.FillDirection.Vertical)
			unchanged()
			for _, input in { "Gamepad", "Touch", "KeyboardAndMouse" } do
				ctx.inputService.PreferredInput = (Enum.PreferredInput :: any)[input]
				t.expect(direction("Categories"))
					.toBe(if input == "Gamepad" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical)
				unchanged()
			end
			categories.AbsoluteSize = ctx.types.Vector2.new(390, 844)
			t.expect(categories:FindFirstChild("Tabs").Position.Y.Scale).toBe(1)
			unchanged()
			stop()
			ctx.runtime:dispose()
		end
	end)

	t.it("switches gallery display previews without remounting the page and keeps its tabs selectable", function()
		local gallery = require("../examples/gallery/client/screen")
		local ctx, root, stop = galleryFixture(function(context)
			context.demos = {
				{ id = "all-controls", title = "All controls", kind = "fixture", module = "all_controls" },
			}
			context.load = function(_, module)
				return require("../examples/gallery/scenarios/" .. module) :: any
			end
			return gallery.build(context)
		end)
		local Enum = ctx.types.Enum
		local categories = tabView(root, "Categories")
		local strip = categories:FindFirstChild("Tabs")
		local inner = tabView(root, "inputs")
		local basics = tabButton(root, "inputs", "basics")
		local writing = tabButton(root, "inputs", "writing")
		local page = inner:FindFirstChild("Content"):FindFirstChild("basics")
		local scale = find(root, "ViewingDistance", "UIScale")
		for _, distance in { "ten-foot", "near", "automatic" } do
			ctx.viewingDistance:set(distance)
			t.expect(scale.Scale).toBe(if distance == "ten-foot" then 1.5 else 1)
			for _, input in { "Gamepad", "Touch", "KeyboardAndMouse" } do
				ctx.inputService.PreferredInput = (Enum.PreferredInput :: any)[input]
				t.expect(tabView(root, "Categories")).toBe(categories)
				t.expect(categories:FindFirstChild("Tabs")).toBe(strip)
				t.expect(tabView(root, "inputs")).toBe(inner)
				t.expect(tabButton(root, "inputs", "basics")).toBe(basics)
				t.expect(inner:FindFirstChild("Content"):FindFirstChild("basics")).toBe(page)
				t.expect(basics.Selectable and writing.Selectable).toBe(true)
				t.expect(tabButton(root, "Categories", "actions").Selectable).toBe(true)
				ctx.guiService.SelectedObject = basics
				t.expect(ctx.guiService.SelectedObject).toBe(basics)
				ctx.guiService.SelectedObject = tabButton(root, "Categories", "inputs")
				t.expect(ctx.guiService.SelectedObject).toBe(tabButton(root, "Categories", "inputs"))
				t.expect(#ctx.engine.rejectedSelections).toBe(0)
			end
		end
		stop()
		ctx.runtime:dispose()
	end)

	t.it("keeps the nested showcase selections in independent cells and shows the inner page", function()
		local scenario = require("../examples/gallery/scenarios/all_controls") :: any
		local built
		local ctx, root, stop = galleryFixture(function(context)
			context.pageVisible = Compose.cell(true)
			built = scenario.build(context)
			return built.screen()
		end)
		tabButton(root, "inputs", "writing").Activated.fire()
		settle(ctx.engine)
		t.expect(built.report().selected.inputs).toBe("writing")
		t.expect(built.report().selected.Categories).toBe("inputs")
		local inner = tabView(root, "inputs")
		local writing = inner:FindFirstChild("Content"):FindFirstChild("writing")
		t.expect(writing.Visible).toBe(true)
		t.expect(inner:FindFirstChild("Content"):FindFirstChild("basics").Visible).toBe(false)
		tabButton(root, "Categories", "actions").Activated.fire()
		t.expect(built.report().selected.Categories).toBe("actions")
		t.expect(built.report().selected.inputs).toBe("writing")
		t.expect(built.report().active).toBe("buttons")
		tabButton(root, "actions", "menus").Activated.fire()
		t.expect(built.report().selected.inputs).toBe("writing")
		t.expect(built.report().selected.Categories).toBe("actions")
		tabButton(root, "Categories", "inputs").Activated.fire()
		settle(ctx.engine)
		t.expect(built.report().active).toBe("writing")
		t.expect(built.report().selected.actions).toBe("menus")
		t.expect(tabView(root, "inputs")).toBe(inner)
		t.expect(inner:FindFirstChild("Content"):FindFirstChild("writing")).toBe(writing)
		t.expect(writing.Visible).toBe(true)
		stop()
	end)

	t.it(
		"resolves every tab home from measured shape and input without author wiring and re-homes one strip",
		function()
			local current, builds = nil, 0
			local selection = Compose.cell("a")
			local world = setup(function(UI, Host)
				local function probe(placement)
					current = placement
					return Host.Frame("Probe")({})
				end
				return UI.TabView({
					selection = selection,
					accessories = { head = probe, trailing = probe },
					tabs = {
						{
							id = "a",
							label = "A",
							content = function()
								builds += 1
								return Host.Frame("aBody")({})
							end,
						},
						{
							id = "b",
							label = "B",
							content = function()
								return Host.Frame("bBody")({})
							end,
						},
					},
				})
			end)
			local Enum, UDim2 = world.engine.types.Enum, world.engine.types.UDim2
			local view = find(world.screen, "TabView")
			local strip = view:FindFirstChild("Tabs")
			local layout = strip:FindFirstChildWhichIsA("UIListLayout")
			local b = find(strip, "b", "TextButton")
			local function home(x, y, expected)
				view.AbsoluteSize = V2(world, x, y)
				t.expect(current).toBe(expected)
				t.expect(view:FindFirstChild("Tabs")).toBe(strip)
				t.expect(find(strip, "b", "TextButton")).toBe(b)
				t.expect(layout.FillDirection)
					.toBe(if expected == "sidebar" then Enum.FillDirection.Vertical else Enum.FillDirection.Horizontal)
				t.expect(strip.ScrollingDirection)
					.toBe(if expected == "sidebar" then Enum.ScrollingDirection.Y else Enum.ScrollingDirection.X)
				if expected == "sidebar" then
					t.expect(strip.Size.Y.Scale).toBe(1)
					t.expect(strip.Size.X.Scale).toBe(0)
				elseif expected == "topBar" then
					t.expect(strip.Position).toBe(UDim2.fromOffset(0, 0))
				else
					t.expect(strip.Position).toBe(UDim2.new(0, 0, 1, -44))
				end
			end
			home(390, 844, "bottomBar")
			home(320, 640, "bottomBar")
			home(800, 400, "bottomBarCompact")
			home(900, 900, "bottomBar")
			home(1200, 900, "sidebar")
			world.input.PreferredInput = Enum.PreferredInput.Gamepad
			t.expect(current).toBe("topBar")
			t.expect(strip.Position).toBe(UDim2.fromOffset(0, 0))
			home(390, 844, "topBar")
			world.input.PreferredInput = Enum.PreferredInput.Touch
			t.expect(current).toBe("bottomBar")
			home(1200, 900, "sidebar")
			b.Activated.fire()
			t.expect(selection:peek()).toBe("b")
			home(800, 400, "bottomBarCompact")
			t.expect(builds).toBe(1)
			world.stop()
			local adaptable, placed = nil, nil
			local wide = setup(function(UI, Host)
				return Host.Frame({
					UI.TabView("Adaptable")({
						selection = Compose.cell("a"),
						style = "sidebarAdaptable",
						accessories = {
							head = function(placement)
								adaptable = placement
								return Host.Frame({})
							end,
							trailing = function(placement)
								adaptable = placement
								return Host.Frame({})
							end,
						},
						tabs = { { id = "a", label = "A", content = page(Host, "a") } },
					}),
					UI.TabView("Declared")({
						selection = Compose.cell("a"),
						placement = "topBar",
						accessories = {
							trailing = function(placement)
								placed = placement
								return Host.Frame({})
							end,
						},
						tabs = { { id = "a", label = "A", content = page(Host, "a") } },
					}),
				})
			end)
			find(wide.screen, "Adaptable").AbsoluteSize = V2(wide, 900, 900)
			t.expect(adaptable).toBe("sidebar")
			find(wide.screen, "Adaptable").AbsoluteSize = V2(wide, 700, 900)
			t.expect(adaptable).toBe("bottomBar")
			local declared = find(wide.screen, "Declared")
			for _, size in { { 320, 640 }, { 1200, 900 }, { 800, 400 } } do
				declared.AbsoluteSize = V2(wide, size[1], size[2])
				t.expect(placed).toBe("topBar")
				t.expect(declared:FindFirstChild("Tabs").Position).toBe(UDim2.fromOffset(0, 0))
			end
			wide.input.PreferredInput = Enum.PreferredInput.Gamepad
			t.expect(placed).toBe("topBar")
			wide.stop()
		end
	)

	t.it("keeps page owners and the strip across every declared home and evicts only on selection", function()
		for _, style in { "automatic", "sidebarAdaptable" } do
			local selected, placement = Compose.cell("games"), Compose.cell("topBar")
			local mounted, released = {}, {}
			local world = setup(function(UI, Host)
				local function content(id)
					return function()
						mounted[id] = (mounted[id] or 0) + 1
						Compose.cleanup(function()
							released[id] = (released[id] or 0) + 1
						end)
						return Host.Frame(id .. "Page")({})
					end
				end
				return UI.TabView({
					selection = selected,
					style = style,
					placement = placement,
					retention = "top",
					transition = false,
					tabs = {
						{ id = "games", label = "Games", content = content("games") },
						{ id = "avatar", label = "Avatar", content = content("avatar") },
					},
				})
			end)
			local view = find(world.screen, "TabView")
			view.AbsoluteSize = V2(world, 1200, 800)
			local strip = view:FindFirstChild("Tabs")
			local avatar = find(strip, "avatar", "TextButton")
			local page = find(world.screen, "gamesPage")
			for _, home in { "sidebar", "bottomBar", "topBar", "bottomBarCompact", "sidebar", "topBar" } do
				placement:set(home)
				t.expect(mounted.games).toBe(1)
				t.expect(released.games).toBeNil()
				t.expect(mounted.avatar).toBeNil()
				t.expect(view:FindFirstChild("Tabs")).toBe(strip)
				t.expect(find(strip, "avatar", "TextButton")).toBe(avatar)
				t.expect(find(world.screen, "gamesPage")).toBe(page)
			end
			avatar.Activated.fire()
			t.expect(selected:peek()).toBe("avatar")
			t.expect(released.games).toBe(1)
			t.expect(mounted.avatar).toBe(1)
			t.expect(find(world.screen, "avatarPage") ~= nil).toBe(true)
			placement:set("bottomBar")
			t.expect(mounted.avatar).toBe(1)
			t.expect(released.avatar).toBeNil()
			selected:set("games")
			t.expect(released.avatar).toBe(1)
			t.expect(mounted.games).toBe(2)
			world.stop()
			t.expect(released.games).toBe(2)
		end
	end)

	t.it("retires tab accessories per home through Compose ownership in every placement", function()
		local placement = Compose.cell("sidebar")
		local live, built, released = {}, 0, 0
		local world = setup(function(UI, Host)
			local function accessory(slot)
				return function(home)
					built += 1
					local key = slot .. ":" .. home
					live[key] = (live[key] or 0) + 1
					Compose.cleanup(function()
						released += 1
						live[key] -= 1
					end)
					return Host.Frame(slot .. "Accessory")({})
				end
			end
			return UI.TabView({
				selection = Compose.cell("home"),
				style = "sidebarAdaptable",
				placement = placement,
				accessories = {
					head = accessory("head"),
					trailing = accessory("trailing"),
					aboveBar = accessory("aboveBar"),
				},
				tabs = { { id = "home", label = "Home", content = page(Host, "home") } },
			})
		end)
		local slots = {
			sidebar = { head = true },
			topBar = { trailing = true },
			bottomBar = { trailing = true, aboveBar = true },
			bottomBarCompact = { trailing = true, aboveBar = true },
		}
		for _, home in { "sidebar", "topBar", "bottomBar", "bottomBarCompact", "sidebar" } do
			placement:set(home)
			for key, count in live do
				local slot, at = string.match(key, "^(%w+):(%w+)$")
				t.expect(count).toBe(if at == home and slots[home][slot :: string] then 1 else 0)
			end
			for slot in slots[home] do
				t.expect(live[slot .. ":" .. home]).toBe(1)
				t.expect(find(world.screen, "Accessory-" .. slot) ~= nil).toBe(true)
			end
		end
		world.stop()
		t.expect(released).toBe(built)
	end)

	t.it("reopens collapsed tabs through their menu and selects each destination in turn", function()
		local selected = Compose.cell("games")
		local world = setup(function(UI, Host)
			return UI.TabView("Collapsed")({
				style = "collapsible",
				selection = selected,
				tabs = {
					{ id = "games", label = "Games", content = page(Host, "games") },
					{ id = "avatar", label = "Avatar", content = page(Host, "avatar") },
				},
			})
		end)
		local collapsed = find(world.screen, "Collapsed")
		t.expect(collapsed:FindFirstChild("Tabs").Visible).toBe(false)
		for _, destination in { "avatar", "games", "avatar" } do
			find(find(collapsed, "TabsMenu"), "Trigger").Activated.fire()
			find(find(world.screen, "MenuPanel"), destination, "TextButton").Activated.fire()
			t.expect(selected:peek()).toBe(destination)
			t.expect(find(world.screen, "MenuPanel")).toBeNil()
			t.expect(find(find(collapsed, "TabsMenu"), "Trigger").Text)
				.toBe(if destination == "avatar" then "Avatar" else "Games")
			t.expect(find(world.screen, destination .. "Body") ~= nil).toBe(true)
		end
		world.stop()
	end)

	t.it("moves selection into the collapsed tab menu and returns it to the trigger after a choice", function()
		for _, variant in { "default", "customized" } do
			local selected = Compose.cell("one")
			local world = setup(function(UI, Host)
				return UI.TabView("Collapsed")({
					style = "collapsible",
					indicator = if variant == "customized" then "none" else nil,
					customization = if variant == "customized" then Compose.cell({ order = {}, hidden = {} }) else nil,
					selection = selected,
					tabs = {
						{ id = "one", label = "First", content = page(Host, "one") },
						{ id = "two", label = "Second", content = page(Host, "two") },
					},
				})
			end)
			local trigger = find(find(world.screen, "TabsMenu"), "Trigger")
			world.gui.SelectedObject = trigger
			trigger.Activated.fire()
			local panel = find(world.screen, "MenuPanel")
			t.expect(world.gui.SelectedObject).toBe(find(panel, "one", "TextButton"))
			find(panel, "two", "TextButton").Activated.fire()
			t.expect(selected:peek()).toBe("two")
			t.expect(find(world.screen, "MenuPanel")).toBeNil()
			t.expect(world.gui.SelectedObject).toBe(trigger)
			trigger.Activated.fire()
			panel = find(world.screen, "MenuPanel")
			local current = world.gui.SelectedObject
			t.expect(current ~= nil and current:IsDescendantOf(panel)).toBe(true)
			find(panel, "two", "TextButton").Activated.fire()
			t.expect(selected:peek()).toBe("two")
			t.expect(world.gui.SelectedObject).toBe(trigger)
			t.expect(#world.engine.rejectedSelections).toBe(0)
			world.stop()
		end
	end)

	t.it("binds the sidebar preference without rebuilding pages or moving focus off page content", function()
		local selection, preference = Compose.cell("garage"), Compose.cell("topBar")
		local builds = 0
		local world = setup(function(UI)
			local function content(id, label)
				return function()
					builds += 1
					return UI.Button(id)({ label = label })
				end
			end
			return UI.TabView({
				style = "sidebarAdaptable",
				sidebarPreference = preference,
				selection = selection,
				tabs = {
					{ id = "garage", label = "Garage", content = content("Tune", "Tune car") },
					{ id = "races", label = "Races", content = content("Race", "Start race") },
				},
			})
		end)
		local Enum = world.engine.types.Enum
		local view = find(world.screen, "TabView")
		local layout = view:FindFirstChild("Tabs"):FindFirstChildWhichIsA("UIListLayout")
		view.AbsoluteSize = V2(world, 1200, 800)
		t.expect(layout.FillDirection).toBe(Enum.FillDirection.Horizontal)
		preference:set("sidebar")
		t.expect(layout.FillDirection).toBe(Enum.FillDirection.Vertical)
		view.AbsoluteSize = V2(world, 390, 844)
		t.expect(view:FindFirstChild("Tabs").Position.Y.Scale).toBe(1)
		local tune = find(world.screen, "Tune")
		world.gui.SelectedObject = tune
		preference:set("topBar")
		t.expect(world.gui.SelectedObject).toBe(tune)
		preference:set("sidebar")
		t.expect(world.gui.SelectedObject).toBe(tune)
		view.AbsoluteSize = V2(world, 1200, 800)
		t.expect(layout.FillDirection).toBe(Enum.FillDirection.Vertical)
		t.expect(world.gui.SelectedObject).toBe(tune)
		preference:set("topBar")
		t.expect(layout.FillDirection).toBe(Enum.FillDirection.Horizontal)
		t.expect(world.gui.SelectedObject).toBe(tune)
		preference:set("automatic")
		t.expect(layout.FillDirection).toBe(Enum.FillDirection.Vertical)
		t.expect(world.gui.SelectedObject).toBe(tune)
		t.expect(find(world.screen, "Tune")).toBe(tune)
		t.expect(builds).toBe(1)
		t.expect(selection:peek()).toBe("garage")
		t.expect(#world.engine.rejectedSelections).toBe(0)
		world.stop()
	end)

	t.it("shows a persistent sidebar by default on a wide pointer viewport without a toggle", function()
		local world = setup(function(UI, Host)
			return UI.TabView({
				style = "sidebarAdaptable",
				selection = Compose.cell("garage"),
				tabs = {
					{ id = "garage", label = "Garage", content = page(Host, "garage") },
					{ id = "races", label = "Races", content = page(Host, "races") },
				},
			})
		end)
		world.input.PreferredInput = world.engine.types.Enum.PreferredInput.KeyboardAndMouse
		local view = find(world.screen, "TabView")
		view.AbsoluteSize = V2(world, 1200, 800)
		local strip = view:FindFirstChild("Tabs")
		t.expect(strip:FindFirstChildWhichIsA("UIListLayout").FillDirection)
			.toBe(world.engine.types.Enum.FillDirection.Vertical)
		t.expect(strip.Visible).toBe(true)
		for _, node in world.screen:GetDescendants() do
			t.expect(string.find(node.Name, "Toggle", 1, true)).toBeNil()
		end
		t.expect(find(view, "TabsMenu")).toBeNil()
		t.expect(strip.Position.X.Offset).toBe(8)
		t.expect(view:FindFirstChild("Content").Position.X.Offset)
			.toBe(strip.Position.X.Offset + strip.Size.X.Offset + 8)
		world.stop()
	end)

	t.it(
		"centres the top bar beside a tall trailing accessory and anchors rail accessories to the rail ends",
		function()
			local placement = Compose.cell("topBar")
			local world = setup(function(UI, Host, engine)
				return UI.TabView({
					selection = Compose.cell("a"),
					style = "sidebarAdaptable",
					placement = placement,
					accessories = {
						trailing = function()
							return Host.Frame("Trailing")({ Size = engine.types.UDim2.fromOffset(80, 120) })
						end,
						head = function()
							return Host.Frame("Head")({})
						end,
						foot = function()
							return Host.Frame("Foot")({})
						end,
					},
					tabs = { { id = "a", label = "A", content = page(Host, "a") } },
				})
			end)
			local UDim2 = world.engine.types.UDim2
			local view = find(world.screen, "TabView")
			view.AbsoluteSize = V2(world, 1000, 600)
			for _ = 1, 2 do
				placement:set("topBar")
				local trailing = find(world.screen, "Accessory-trailing")
				trailing.AbsoluteSize = V2(world, 80, 44)
				local strip = view:FindFirstChild("Tabs")
				t.expect(trailing.ClipsDescendants).toBe(true)
				t.expect(trailing.Size.Y).toBe(world.engine.types.UDim.new(0, 44))
				t.expect(trailing.Position).toBe(UDim2.new(1, -80, 0, 0))
				t.expect(strip.Position).toBe(UDim2.fromOffset(0, 0))
				t.expect(strip.Size).toBe(UDim2.new(1, -80, 0, 44))
				local barCentre = strip.Position.Y.Offset + strip.Size.Y.Offset / 2
				local accessoryCentre = trailing.Position.Y.Offset + trailing.Size.Y.Offset / 2
				t.expect(barCentre).toBe(accessoryCentre)
				t.expect(strip.Size.X.Scale).toBe(trailing.Position.X.Scale)
				t.expect(strip.Size.X.Offset).toBe(trailing.Position.X.Offset)
				placement:set("sidebar")
				local head, foot = find(world.screen, "Accessory-head"), find(world.screen, "Accessory-foot")
				head.AbsoluteSize = V2(world, 240, 80)
				foot.AbsoluteSize = V2(world, 240, 100)
				strip = view:FindFirstChild("Tabs")
				t.expect(head.Position).toBe(UDim2.fromOffset(0, 0))
				t.expect(strip.Position).toBe(UDim2.fromOffset(8, 80))
				t.expect(foot.Position).toBe(UDim2.new(0, 0, 1, -100))
				t.expect(strip.Size.Y).toBe(world.engine.types.UDim.new(1, -180))
				t.expect(strip.Position.Y.Offset + strip.Size.Y.Offset + 100).toBe(0)
				t.expect(head.Size.X.Offset).toBe(strip.Size.X.Offset + 16)
				t.expect(foot.Size.X.Offset).toBe(strip.Size.X.Offset + 16)
			end
			world.stop()
		end
	)

	t.it("remembers a tab's focus after its page is evicted and lets a direct selection override it", function()
		local selected = Compose.cell("gear")
		local builds, released = 0, 0
		local world = setup(function(UI, Host)
			local function content()
				builds += 1
				Compose.cleanup(function()
					released += 1
				end)
				return Host.Frame("Page")({
					Host.UIListLayout({}),
					UI.Button("A")({ label = "A" }),
					UI.Button("B")({ label = "B" }),
				})
			end
			return UI.TabView({
				selection = selected,
				placement = "topBar",
				retention = "top",
				transition = false,
				tabs = {
					{ id = "gear", label = "Gear", content = content },
					{ id = "options", label = "Options", content = content },
				},
			})
		end)
		world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Gamepad
		local function inGear(name)
			local panel = find(find(world.screen, "Content"), "gear")
			return if panel then find(panel, name, "TextButton") else nil
		end
		local oldB = inGear("B")
		world.gui.SelectedObject = oldB
		selected:set("options")
		t.expect(released).toBe(1)
		t.expect(inGear("B")).toBeNil()
		selected:set("gear")
		t.expect(builds).toBe(3)
		local b = inGear("B")
		t.expect(b ~= nil and b ~= oldB).toBe(true)
		t.expect(world.gui.SelectedObject).toBe(b)
		world.gui.SelectedObject = inGear("A")
		selected:set("options")
		selected:set("gear")
		t.expect(world.gui.SelectedObject).toBe(inGear("A"))
		t.expect(#world.engine.rejectedSelections).toBe(0)
		world.stop()
	end)

	t.it("fits nested horizontal tabs at a large text size without mounting section headings", function()
		local textSize = Compose.cell(18)
		local sections = { { id = "game", label = "Game" }, { id = "system", label = "System" } }
		local world = setup(function(UI, Host)
			return UI.TabView("Outer")({
				selection = Compose.cell("pages"),
				placement = "sidebar",
				sections = sections,
				tabs = {
					{
						id = "pages",
						label = "Pages",
						section = "game",
						content = function()
							return UI.TabView("Inner")({
								selection = Compose.cell("avatars"),
								sections = sections,
								textSize = textSize,
								tabs = {
									{
										id = "avatars",
										label = "Avatars",
										section = "game",
										content = page(Host, "avatars"),
									},
									{
										id = "badges",
										label = "Badges",
										section = "game",
										content = page(Host, "badges"),
									},
									{
										id = "privacy",
										label = "Privacy",
										section = "system",
										content = page(Host, "privacy"),
									},
								},
							})
						end,
					},
					{ id = "about", label = "About", section = "system", content = page(Host, "about") },
				},
			})
		end)
		local Enum = world.engine.types.Enum
		local outer, inner = find(world.screen, "Outer"), find(world.screen, "Inner")
		outer.AbsoluteSize = V2(world, 1200, 800)
		inner.AbsoluteSize = V2(world, 705, 600)
		local headings = 0
		for _, node in outer:FindFirstChild("Tabs"):GetDescendants() do
			if node.Name == "Section" and node:IsA("TextLabel") then
				headings += 1
			end
		end
		t.expect(headings).toBe(2)
		local strip = inner:FindFirstChild("Tabs")
		t.expect(strip:FindFirstChildWhichIsA("UIListLayout").FillDirection).toBe(Enum.FillDirection.Horizontal)
		for _, size in { 18, 40 } do
			textSize:set(size)
			for _, node in strip:GetDescendants() do
				t.expect(node.Name ~= "Section").toBe(true)
			end
			for _, id in { "avatars", "badges", "privacy" } do
				local button = find(strip, id, "TextButton")
				t.expect(button.TextSize).toBe(size)
				t.expect(button:FindFirstChildWhichIsA("UISizeConstraint").MinSize).toBe(V2(world, 44, 44))
				t.expect(button.AutomaticSize).toBe(Enum.AutomaticSize.X)
			end
			t.expect(strip.ScrollingDirection).toBe(Enum.ScrollingDirection.X)
			t.expect(strip.AutomaticCanvasSize).toBe(Enum.AutomaticSize.X)
		end
		inner.AbsoluteSize = V2(world, 640, 200)
		t.expect(strip.Visible).toBe(false)
		t.expect(find(inner, "TabsMenu") ~= nil).toBe(true)
		local content = inner:FindFirstChild("Content")
		t.expect(content.Position.Y.Offset).toBe(52)
		t.expect(content.Size.Y.Scale * 200 + content.Size.Y.Offset > 0).toBe(true)
		t.expect(find(content, "avatarsBody") ~= nil).toBe(true)
		world.stop()
	end)

	t.it("adapts one Journey flow across themes sizes and inputs and releases every page", function()
		local packages =
			{
				Facet.themes.neutralPackage(),
				(assert(
					(Facet.themes :: any).define(
						(require("../examples/themes/classic_desktop") :: any).build(Facet.themes)
					)
				)),
				(assert(
					(Facet.themes :: any).define(
						(require("../examples/themes/fantasy_parchment") :: any).build(Facet.themes)
					)
				)),
			}
		local views = {
			{ 390, 844, "Touch" },
			{ 844, 390, "Touch" },
			{ 1024, 768, "Touch" },
			{ 1280, 800, "KeyboardAndMouse" },
			{ 1920, 1080, "Gamepad" },
		}
		for _, package in packages do
			for _, view in views do
				local built, node, ctx, close = journeyFixture(package, view[3])
				find(node, "NavigationFlow").AbsoluteSize = ctx.types.Vector2.new(view[1], view[2])
				t.expect(built.report().axis).toBe(if view[1] < 600 then "y" else "x")
				find(node, "Continue", "TextButton").Activated.fire()
				t.expect(built.report().navigation.depth).toBe(1)
				t.expect(find(node, "Columns"):FindFirstChildWhichIsA("UIListLayout").FillDirection).toBe(
					if view[1] < 600
						then ctx.types.Enum.FillDirection.Vertical
						else ctx.types.Enum.FillDirection.Horizontal
				)
				t.expect(find(node, "FlexibleGap") ~= nil).toBe(true)
				built.steps.baseline()
				built.steps.spacing()
				find(node, "Review", "TextButton").Activated.fire()
				t.expect(built.report().navigation.depth).toBe(2)
				find(node, "StartAgain", "TextButton").Activated.fire()
				t.expect(built.report().navigation.depth).toBe(0)
				t.expect(built.report().notes).toBe("Meet at sunrise.")
				t.expect(built.report().visits - built.report().exits).toBe(1)
				close()
			end
		end
	end)

	t.it("keeps the compact Journey flow through input switches and returns selection on each Back", function()
		local built, node, ctx, close = journeyFixture(nil, "Gamepad")
		find(node, "NavigationFlow").AbsoluteSize = ctx.types.Vector2.new(390, 844)
		t.expect(built.report().axis).toBe("y")
		local launcher = find(node, "Continue", "TextButton")
		ctx.guiService.SelectedObject = launcher
		launcher.Activated.fire()
		t.expect(built.report().navigation.depth).toBe(1)
		local review = find(node, "Review", "TextButton")
		local visits = built.report().visits
		for _, preference in { "Touch", "Gamepad", "Touch" } do
			ctx.inputService.PreferredInput = (ctx.types.Enum.PreferredInput :: any)[preference]
			t.expect(built.report().navigation.depth).toBe(1)
			t.expect(built.report().axis).toBe("y")
			t.expect(built.report().visits).toBe(visits)
			t.expect(find(node, "Review", "TextButton")).toBe(review)
		end
		ctx.guiService.SelectedObject = review
		review.Activated.fire()
		t.expect(built.report().navigation.depth).toBe(2)
		ctx.inputService.PreferredInput = ctx.types.Enum.PreferredInput.Gamepad
		t.expect(built.report().navigation.depth).toBe(2)
		local back = action(ctx.target, "NavigationBack")
		t.expect(back:FindFirstChildWhichIsA("InputBinding") ~= nil).toBe(true)
		back.Pressed.fire()
		t.expect(built.report().navigation.depth).toBe(1)
		t.expect(ctx.guiService.SelectedObject).toBe(review)
		action(ctx.target, "NavigationBack").Pressed.fire()
		t.expect(built.report().navigation.depth).toBe(0)
		t.expect(ctx.guiService.SelectedObject).toBe(launcher)
		t.expect(action(ctx.target, "NavigationBack")).toBeNil()
		t.expect(built.report().notes).toBe("Meet at sunrise.")
		t.expect(#ctx.engine.rejectedSelections).toBe(0)
		t.expect(built.report().visits - built.report().exits).toBe(1)
		close()
	end)

	t.it("keeps Journey search filtering through adaptation and restores the chosen result on Back", function()
		local built, node, ctx, close = journeyFixture(nil, "KeyboardAndMouse")
		local flow = find(node, "NavigationFlow")
		flow.AbsoluteSize = ctx.types.Vector2.new(390, 844)
		local search = find(node, "Search", "TextBox")
		search:CaptureFocus()
		search.Text = "FoReSt"
		search.FocusLost.fire(true)
		t.expect(built.report().query).toBe("FoReSt")
		local function results()
			local count = 0
			for _, item in node:GetDescendants() do
				if string.sub(item.Name, 1, 7) == "Result-" and item:IsA("TextButton") then
					count += 1
				end
			end
			return count
		end
		t.expect(results()).toBe(1)
		local result = find(node, "Result-forest", "TextButton")
		flow.AbsoluteSize = ctx.types.Vector2.new(1280, 800)
		t.expect(built.report().axis).toBe("x")
		t.expect(find(node, "Search", "TextBox")).toBe(search)
		t.expect(find(node, "Result-forest", "TextButton")).toBe(result)
		ctx.guiService.SelectedObject = result
		result.Activated.fire()
		t.expect(built.report().navigation.depth).toBe(1)
		t.expect(built.report().destination).toBe("forest")
		action(ctx.target, "NavigationBack").Pressed.fire()
		t.expect(built.report().navigation.depth).toBe(0)
		t.expect(built.report().query).toBe("FoReSt")
		t.expect(ctx.guiService.SelectedObject).toBe(result)
		search:CaptureFocus()
		search.Text = "zzz"
		search.FocusLost.fire(true)
		t.expect(results()).toBe(0)
		built.steps.clearSearch()
		t.expect(built.report().query).toBe("")
		t.expect(results()).toBe(3)
		t.expect(built.report().visits - built.report().exits).toBe(1)
		close()
	end)

	t.it("lists only same-genre matches under More like this, opens one on its info and toggles Save off", function()
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local target = engine.new("ScreenGui")
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		input.GetFocusedTextBox = function()
			return nil
		end
		input.IsKeyDown = function()
			return false
		end
		local modelModule = require("../examples/virtual_monitors/model") :: any
		local screens = require("../examples/virtual_monitors/screens") :: any
		local lifetime = Compose.createRootOwner(function()
			local model = modelModule.new(Compose)
			Compose.cleanup(model.dispose)
			local views = screens.create(Facet, runtime, {
				model = model,
				types = engine.types,
				services = { GuiService = gui, UserInputService = input },
				reducedMotion = true,
			})
			runtime.mount(views.Discover, target)
			local function rows()
				local found = {}
				for _, node in find(target, "SimilarPage"):GetChildren() do
					local id = string.match(node.Name, "^SimilarRow_(.+)$")
					if id then
						table.insert(found, id)
					end
				end
				return found
			end
			model.catalog.seen(35)
			model.catalog.step()
			local byId = {}
			for _, item in model.catalog.items:peek() do
				byId[item.id] = item
			end
			local first = model.catalog.items:peek()[1]
			model.selectGame(first)
			find(target, "SimilarTab").Activated.fire()
			local picks = rows()
			t.expect(#picks).toBe(6)
			for _, id in picks do
				t.expect(byId[id].genre).toBe(first.genre)
				t.expect(id ~= first.id).toBe(true)
			end
			local match = picks[1]
			local row = find(target, "SimilarRow_" .. match)
			row.TouchLongPress.fire({}, engine.types.Enum.UserInputState.Begin)
			find(target, "trailing:SaveSimilar").Activated.fire()
			t.expect(model.saved:peek()[match]).toBe(true)
			t.expect(table.find(model.savedOrder:peek(), match) ~= nil).toBe(true)
			row = find(target, "SimilarRow_" .. match)
			row.TouchLongPress.fire({}, engine.types.Enum.UserInputState.Begin)
			find(target, "trailing:SaveSimilar").Activated.fire()
			t.expect(model.saved:peek()[match]).toBeNil()
			t.expect(table.find(model.savedOrder:peek(), match)).toBeNil()
			find(target, "Similar_" .. match).Activated.fire()
			t.expect(model.selectedGame:peek().id).toBe(match)
			t.expect(model.selectedGame:peek().genre).toBe(first.genre)
			t.expect(model.detailTab:peek()).toBe("about")
			t.expect(find(target, "SimilarGames")).toBeNil()
			t.expect(find(target, "SimilarTab") ~= nil).toBe(true)
			find(target, "SimilarTab").Activated.fire()
			for _, id in rows() do
				t.expect(byId[id].genre).toBe(first.genre)
				t.expect(id ~= match).toBe(true)
			end
		end, runtime.reactor)
		lifetime.dispose()
		t.expect(#target:GetChildren()).toBe(0)
		runtime:dispose()
	end)
end)
