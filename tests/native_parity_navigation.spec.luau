--!strict
local t = require("./lib/testkit")
local fs = require("@lune/fs")
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

local function find(root: any, name: string): any
	if root.Name == name then
		return root
	end
	for _, child in root:GetChildren() do
		local found = find(child, name)
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

local function contexts(root: any, name: string): { any }
	local found = {}
	for _, node in root:GetDescendants() do
		if node:IsA("InputContext") and node.Name == "Facet" .. name then
			table.insert(found, node)
		end
	end
	return found
end

local function mountError(build: (any, any) -> any): string?
	local engine: any = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local gui = engine.new("GuiService")
	local UI =
		Facet.controls(runtime, { types = engine.types, guiService = gui, services = { GuiService = gui } } :: any)
	local Host = runtime.constructors
	local ok, message = pcall(function()
		local stop = runtime.mount(function()
			return Host.ScreenGui({ build(UI, Host) })
		end, engine.new("Folder"))
		stop()
	end)
	runtime:dispose()
	return if ok then nil else tostring(message)
end

local function refuses(message: string, build: (any, any) -> any): boolean
	local failure = mountError(build)
	return failure ~= nil and string.find(failure, message, 1, true) ~= nil
end

local function V2(world: World, x: number, y: number): any
	return world.engine.types.Vector2.new(x, y)
end

local function showcase(): (any, any, any, any, () -> ())
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
	input.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
	local target = engine.new("Folder")
	local viewport = Compose.cell({ width = 1280, height = 800 })
	local ctx = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
		types = engine.types,
		viewport = viewport,
		inputTarget = target,
		guiService = gui,
		runService = { Heartbeat = engine.heartbeat },
		UI = Facet.controls(
			runtime,
			{
				types = engine.types,
				viewport = viewport,
				guiService = gui,
				services = { GuiService = gui, UserInputService = input },
				reducedMotion = true,
			} :: any
		),
	}
	local built
	local stop, screen = runtime.mount(function()
		built = require("../examples/gallery/scenarios/all_controls").build(ctx)
		return ctx.Host.ScreenGui({ built.screen() })
	end, target)
	return engine, gui, screen, built, function()
		stop()
		runtime:dispose()
	end
end

local function tabView(root: any, name: string): any
	for _, node in root:GetDescendants() do
		if node.Name == name and node:FindFirstChild("Tabs") and node:FindFirstChild("Content") then
			return node
		end
	end
	return nil
end

local function page(Host: any, name: string, builds: { [string]: number }?, cleanups: { [string]: number }?): () -> any
	return function()
		if builds then
			builds[name] = (builds[name] or 0) + 1
		end
		if cleanups then
			Compose.cleanup(function()
				cleanups[name] = (cleanups[name] or 0) + 1
			end)
		end
		return Host.Frame(name .. "Body")({})
	end
end

t.describe("native parity navigation", function()
	t.it("pages tabs with the shoulders from the strip, wraps there and clamps when paging from content", function()
		for _, mode in { "strip", "content" } do
			local selection = Compose.cell("a")
			local world = setup(function(UI, Host)
				return UI.TabView({
					selection = selection,
					shoulderNavigation = if mode == "content" then "content" else nil,
					tabs = {
						{
							id = "a",
							label = "A",
							content = function()
								return Host.Frame({
									UI.Button("Play")({ label = "Play" }),
									UI.Slider("Volume")({ value = Compose.cell(0.5) }),
								})
							end,
						},
						{ id = "b", label = "B", content = page(Host, "b") },
						{ id = "c", label = "C", content = page(Host, "c") },
					},
				})
			end)
			local tabs = find(world.screen, "Tabs")
			world.gui.SelectedObject = find(world.screen, "Play")
			if mode == "strip" then
				t.expect(action(world.screen, "NextTab")).toBeNil()
				world.gui.SelectedObject = find(tabs, "a")
				local next, previous = action(world.screen, "NextTab"), action(world.screen, "PreviousTab")
				t.expect(next:FindFirstChildWhichIsA("InputBinding").KeyCode.Name).toBe("ButtonR1")
				t.expect(previous:FindFirstChildWhichIsA("InputBinding").KeyCode.Name).toBe("ButtonL1")
				next.Pressed.fire()
				next.Pressed.fire()
				t.expect(selection:peek()).toBe("c")
				next.Pressed.fire()
				t.expect(selection:peek()).toBe("a")
				previous.Pressed.fire()
				t.expect(selection:peek()).toBe("c")
			else
				local next = action(world.screen, "NextTab")
				next.Pressed.fire()
				t.expect(selection:peek()).toBe("b")
				next.Pressed.fire()
				next.Pressed.fire()
				t.expect(selection:peek()).toBe("c")
				action(world.screen, "PreviousTab").Pressed.fire()
				t.expect(selection:peek()).toBe("b")
				selection:set("a")
				world.gui.SelectedObject = find(find(world.screen, "Volume"), "Track")
				local increase = action(world.screen, "Increase")
				t.expect(increase.Parent.Priority > action(world.screen, "NextTab").Parent.Priority).toBe(true)
			end
			world.stop()
		end
	end)

	t.it("pages the inner tab view from nested content, clamps at its boundary and leaves the outer tabs", function()
		local outer, inner = Compose.cell("a"), Compose.cell("one")
		local world = setup(function(UI, Host)
			return UI.TabView({
				selection = outer,
				shoulderNavigation = "content",
				tabs = {
					{
						id = "a",
						label = "A",
						content = function()
							return UI.TabView("Inner")({
								selection = inner,
								shoulderNavigation = "content",
								tabs = {
									{
										id = "one",
										label = "One",
										content = function()
											return UI.Button("Deep")({ label = "Deep" })
										end,
									},
									{ id = "two", label = "Two", content = page(Host, "two") },
								},
							})
						end,
					},
					{ id = "b", label = "B", content = page(Host, "b") },
				},
			})
		end)
		world.gui.SelectedObject = find(world.screen, "Deep")
		local enabled = {}
		for _, context in contexts(world.screen, "NextTab") do
			if context.Enabled then
				table.insert(enabled, context)
			end
		end
		table.sort(enabled, function(first, second)
			return first.Priority > second.Priority
		end)
		t.expect(#enabled).toBe(2)
		t.expect(enabled[1].Priority > enabled[2].Priority).toBe(true)
		enabled[1]:FindFirstChild("NextTab").Pressed.fire()
		enabled[1]:FindFirstChild("NextTab").Pressed.fire()
		t.expect(inner:peek()).toBe("two")
		t.expect(outer:peek()).toBe("a")
		world.stop()
	end)

	t.it("builds only visited tabs and disposes departing pages under top retention", function()
		local builds, cleanups = {}, {}
		local selection = Compose.cell("home")
		local world = setup(function(UI, Host)
			return UI.TabView({
				selection = selection,
				retention = "top",
				transition = false,
				tabs = {
					{ id = "home", label = "Home", content = page(Host, "home", builds, cleanups) },
					{ id = "feed", label = "Feed", content = page(Host, "feed", builds, cleanups) },
					{ id = "more", label = "More", content = page(Host, "more", builds, cleanups) },
				},
			})
		end)
		t.expect(builds).toEqual({ home = 1 })
		t.expect(find(world.screen, "feedBody")).toBeNil()
		selection:set("feed")
		t.expect(builds).toEqual({ home = 1, feed = 1 })
		t.expect(cleanups).toEqual({ home = 1 })
		t.expect(find(world.screen, "homeBody")).toBeNil()
		selection:set("home")
		t.expect(builds.home).toBe(2)
		t.expect(cleanups.feed).toBe(1)
		local baseline = world.engine.census()
		for _ = 1, 20 do
			selection:set("feed")
			selection:set("home")
		end
		local after = world.engine.census()
		t.expect(after.live).toBe(baseline.live)
		t.expect(after.connections).toBe(baseline.connections)
		t.expect(builds.home).toBe(22)
		t.expect(builds.more).toBeNil()
		world.stop()
	end)

	t.it("resolves a nested tab view to a top band and keeps nesting balanced after a failed page", function()
		local fresh = Compose.cell(false)
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.TabView("Outer")({
					selection = Compose.cell("a"),
					tabs = {
						{
							id = "a",
							label = "A",
							content = function()
								return UI.TabView("Inner")({
									selection = Compose.cell("x"),
									tabs = {
										{ id = "x", label = "X", content = page(Host, "x") },
										{ id = "y", label = "Y", content = page(Host, "y") },
									},
								})
							end,
						},
					},
				}),
				Compose.boundary(function()
					return UI.TabView("Broken")({
						selection = Compose.cell("a"),
						tabs = {
							{
								id = "a",
								label = "A",
								content = function(): any
									error("page failed", 0)
								end,
							},
						},
					})
				end, function()
					return Host.Folder("Failed")({})
				end),
				Compose.show(fresh, function()
					return UI.TabView("Fresh")({
						selection = Compose.cell("a"),
						tabs = { { id = "a", label = "A", content = page(Host, "fresh") } },
					})
				end),
			})
		end)
		local outerView, innerView = find(world.screen, "Outer"), find(world.screen, "Inner")
		outerView.AbsoluteSize = V2(world, 1200, 800)
		innerView.AbsoluteSize = V2(world, 900, 700)
		local Enum = world.engine.types.Enum
		t.expect(outerView:FindFirstChild("Tabs"):FindFirstChildWhichIsA("UIListLayout").FillDirection)
			.toBe(Enum.FillDirection.Vertical)
		local innerTabs = innerView:FindFirstChild("Tabs")
		t.expect(innerTabs.Position).toBe(world.engine.types.UDim2.fromOffset(0, 0))
		t.expect(innerTabs:FindFirstChildWhichIsA("UIListLayout").FillDirection).toBe(Enum.FillDirection.Horizontal)
		t.expect(find(world.screen, "Failed") ~= nil).toBe(true)
		fresh:set(true)
		local freshView = find(world.screen, "Fresh")
		freshView.AbsoluteSize = V2(world, 400, 800)
		t.expect(freshView:FindFirstChild("Tabs").Position.Y.Scale).toBe(1)
		world.stop()
	end)

	t.it("places sidebar head and foot accessories around the strip and passes the placement to builders", function()
		local placements = {}
		local world = setup(function(UI, Host)
			local function builder(name)
				return function(placement)
					table.insert(placements, placement)
					return Host.Frame(name)({})
				end
			end
			return UI.TabView({
				selection = Compose.cell("a"),
				placement = "sidebar",
				accessories = { head = builder("Head"), foot = builder("Foot") },
				tabs = { { id = "a", label = "A", content = page(Host, "a") } },
			})
		end)
		local view = find(world.screen, "TabView")
		view.AbsoluteSize = V2(world, 1200, 800)
		find(world.screen, "Accessory-head").AbsoluteSize = V2(world, 240, 52)
		find(world.screen, "Accessory-foot").AbsoluteSize = V2(world, 240, 60)
		local UDim2 = world.engine.types.UDim2
		local tabs = view:FindFirstChild("Tabs")
		t.expect(tabs.Size).toBe(UDim2.new(0, 240 - 16, 1, -112))
		t.expect(tabs.Position).toBe(UDim2.fromOffset(8, 52))
		t.expect(find(world.screen, "Accessory-head").Position).toBe(UDim2.fromOffset(0, 0))
		t.expect(find(world.screen, "Accessory-foot").Position).toBe(UDim2.new(0, 0, 1, -60))
		table.sort(placements)
		t.expect(placements).toEqual({ "sidebar", "sidebar" })
		world.stop()
	end)

	t.it("docks trailing and above-bar accessories against the band and re-homes them with the placement", function()
		local placement = Compose.cell("topBar")
		local world = setup(function(UI, Host)
			return UI.TabView({
				selection = Compose.cell("a"),
				placement = placement,
				accessories = {
					trailing = function()
						return Host.Frame("Search")({})
					end,
				},
				tabs = { { id = "a", label = "A", content = page(Host, "a") } },
			})
		end)
		local UDim2 = world.engine.types.UDim2
		local view = find(world.screen, "TabView")
		view.AbsoluteSize = V2(world, 900, 700)
		find(world.screen, "Accessory-trailing").AbsoluteSize = V2(world, 120, 44)
		t.expect(view:FindFirstChild("Tabs").Size).toBe(UDim2.new(1, -120, 0, 44))
		t.expect(find(world.screen, "Accessory-trailing").Position).toBe(UDim2.new(1, -120, 0, 0))
		placement:set("bottomBar")
		find(world.screen, "Accessory-trailing").AbsoluteSize = V2(world, 120, 44)
		t.expect(find(world.screen, "Accessory-trailing").Position).toBe(UDim2.new(1, -120, 1, -44))
		t.expect(view:FindFirstChild("Tabs").Position).toBe(UDim2.new(0, 0, 1, -44))
		world.stop()
		local calls = {}
		local docked = setup(function(UI, Host)
			return UI.TabView({
				selection = Compose.cell("a"),
				accessories = {
					aboveBar = function(where)
						table.insert(calls, where)
						return if where == "bottomBarCompact" then nil else Host.Frame("NowPlaying")({})
					end,
				},
				tabs = { { id = "a", label = "A", content = page(Host, "a") } },
			})
		end)
		local root = find(docked.screen, "TabView")
		root.AbsoluteSize = V2(docked, 400, 800)
		local dock = find(docked.screen, "Accessory-aboveBar")
		dock.AbsoluteSize = V2(docked, 400, 56)
		t.expect(dock.Position).toBe(UDim2.new(0, 0, 1, -100))
		t.expect(dock.Position.Y.Offset + 56).toBe(root:FindFirstChild("Tabs").Position.Y.Offset)
		t.expect(root:FindFirstChild("Content").Size).toBe(UDim2.new(1, 0, 1, -108))
		root.AbsoluteSize = V2(docked, 800, 400)
		t.expect(find(docked.screen, "Accessory-aboveBar")).toBeNil()
		t.expect(root:FindFirstChild("Content").Size).toBe(UDim2.new(1, 0, 1, -52))
		t.expect(calls).toEqual({ "bottomBar", "bottomBarCompact" })
		docked.stop()
	end)

	t.it(
		"refuses unknown accessory slots, non-function builders, unhostable slots and malformed transitions",
		function()
			local function view(extra)
				return function(UI, Host)
					local spec: { [string]: any } = {
						selection = Compose.cell("a"),
						tabs = { { id = "a", label = "A", content = page(Host, "a") } },
					}
					for field, value in extra do
						spec[field] = value
					end
					return UI.TabView(spec)
				end
			end
			local slots = "TabView accessories require head, foot, trailing or aboveBar builders"
			t.expect(refuses(slots, view({ accessories = { leading = function() end } }))).toBe(true)
			t.expect(refuses(slots, view({ accessories = { head = {} } }))).toBe(true)
			t.expect(refuses(
				"TabView accessory is unavailable in this placement",
				view({
					placement = "bottomBar",
					accessories = { head = function() end },
				})
			)).toBe(true)
			t.expect(refuses("Navigation transition uses Compose tween options", view({ transition = "fade" })))
				.toBe(true)
			t.expect(refuses("seconds, ease", view({ transition = { seconds = 0.2, fade = true } }))).toBe(true)
			t.expect(mountError(view({ transition = { seconds = 0.2 } }))).toBeNil()
		end
	)

	t.it("uses a plain native frame and hides the old page immediately when transition is false", function()
		for _, declared in { "false" } do
			local selection = Compose.cell("a")
			local world = setup(function(UI, Host)
				return UI.TabView({
					selection = selection,
					transition = if declared == "false" then false else nil,
					tabs = {
						{ id = "a", label = "A", content = page(Host, "a") },
						{ id = "b", label = "B", content = page(Host, "b") },
					},
				})
			end)
			local layer = find(world.screen, "aBody").Parent
			t.expect(layer.ClassName).toBe("Frame")
			selection:set("b")
			t.expect(layer.Visible).toBe(false)
			t.expect(find(world.screen, "bBody").Parent.ClassName).toBe("Frame")
			t.expect(world.engine.heartbeat.count()).toBe(0)
			world.stop()
		end
	end)

	t.it("labels tabs by id, keeps icon-only names accessible and badges unselected tabs in place", function()
		local badge, iconOnly = Compose.cell(nil :: number?), Compose.cell(false)
		local selection = Compose.cell("home")
		local world = setup(function(UI, Host)
			return UI.TabView({
				selection = selection,
				iconOnly = iconOnly,
				tabs = {
					{ id = "home", content = page(Host, "home") },
					{ id = "feed", label = "Feed", icon = "checkmark", badge = badge, content = page(Host, "feed") },
				},
			})
		end)
		local tabs = find(world.screen, "Tabs")
		local home, feed = find(tabs, "home"), find(tabs, "feed")
		t.expect(home.Text).toBe("home")
		t.expect(home:GetAttribute("FacetLabel")).toBe("home")
		badge:set(12)
		t.expect(feed:GetAttribute("FacetLabel")).toBe("Feed")
		local label = feed:FindFirstChild("Title", true)
		local function shown()
			return if label then label.Text else feed.Text
		end
		t.expect(shown()).toBe("Feed")
		local seal = feed:FindFirstChild("CornerBadge", true)
		t.expect(seal ~= nil and seal.Text == "12").toBe(true)
		for _ = 1, 3 do
			selection:set("feed")
			selection:set("home")
		end
		t.expect(find(tabs, "feed")).toBe(feed)
		t.expect(shown()).toBe("Feed")
		t.expect(feed:FindFirstChild("CornerBadge", true)).toBe(seal)
		iconOnly:set(true)
		t.expect(shown()).toBe("")
		t.expect(feed:GetAttribute("FacetLabel")).toBe("Feed")
		world.stop()
	end)
	t.it(
		"underlines the selected top tab by default, fills bottom and sidebar tabs and follows the indicator",
		function()
			local indicator, placement = Compose.cell(nil :: string?), Compose.cell("topBar")
			local selection = Compose.cell("a")
			local world = setup(function(UI, Host)
				return UI.TabView({
					selection = selection,
					indicator = indicator,
					placement = placement,
					tabs = {
						{ id = "a", label = "A", content = page(Host, "a") },
						{ id = "b", label = "B", content = page(Host, "b") },
					},
				})
			end)
			local tabs = find(world.screen, "Tabs")
			local a, b = find(tabs, "a"), find(tabs, "b")
			t.expect(a:FindFirstChild("SelectionIndicator") ~= nil).toBe(true)
			t.expect(b:FindFirstChild("SelectionIndicator")).toBeNil()
			t.expect(a:HasTag("facet-tab-current")).toBe(true)
			t.expect(a:HasTag("facet-tab-filled")).toBe(false)
			selection:set("b")
			t.expect(a:FindFirstChild("SelectionIndicator")).toBeNil()
			t.expect(b:FindFirstChild("SelectionIndicator") ~= nil).toBe(true)
			indicator:set("pill")
			t.expect(b:FindFirstChild("SelectionIndicator")).toBeNil()
			t.expect(b:HasTag("facet-selected")).toBe(true)
			t.expect(a:HasTag("facet-selected")).toBe(false)
			indicator:set("none")
			t.expect(b:FindFirstChild("SelectionIndicator")).toBeNil()
			t.expect(b:HasTag("facet-selected")).toBe(false)
			t.expect(b:HasTag("facet-tab-current")).toBe(true)
			indicator:set(nil)
			for _, where in { "bottomBar", "sidebar" } do
				placement:set(where)
				t.expect(b:HasTag("facet-tab-filled")).toBe(true)
				t.expect(a:HasTag("facet-tab-filled")).toBe(false)
				t.expect(b:FindFirstChild("SelectionIndicator")).toBeNil()
			end
			world.stop()
		end
	)

	t.it("keeps every tab at the 44 pixel target floor and reads a bound text size and rail width", function()
		local textSize, railWidth, placement = Compose.cell(16), Compose.cell(nil :: number?), Compose.cell("sidebar")
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.TabView({
					selection = Compose.cell("a"),
					placement = placement,
					textSize = textSize,
					railWidth = railWidth,
					tabs = {
						{ id = "a", label = "A", content = page(Host, "a") },
						{ id = "b", label = "B", content = page(Host, "b") },
					},
				}),
				UI.TabView("Plain")({
					selection = Compose.cell("p"),
					tabs = { { id = "p", label = "P", content = page(Host, "p") } },
				}),
				UI.Button("Reference")({ label = "Reference" }),
			})
		end)
		local view = find(world.screen, "TabView")
		view.AbsoluteSize = V2(world, 1200, 800)
		local tabs = view:FindFirstChild("Tabs")
		local content = view:FindFirstChild("Content")
		for _, where in { "sidebar", "bottomBar", "topBar" } do
			placement:set(where)
			for _, id in { "a", "b" } do
				local button = find(tabs, id)
				t.expect(button:FindFirstChildWhichIsA("UISizeConstraint").MinSize).toBe(V2(world, 44, 44))
				t.expect(button.Size.Y.Offset).toBe(44)
			end
		end
		placement:set("sidebar")
		t.expect(tabs.Size.X.Offset).toBe(240 - 16)
		t.expect(tabs.Position.X.Offset).toBe(8)
		t.expect(content.Position.X.Offset).toBe(240)
		railWidth:set(260)
		t.expect(tabs.Size.X.Offset).toBe(260 - 16)
		t.expect(content.Position.X.Offset).toBe(260)
		view.AbsoluteSize = V2(world, 2000, 800)
		railWidth:set(nil)
		t.expect(tabs.Size.X.Offset).toBe(280 - 16)
		t.expect(find(tabs, "a").TextSize).toBe(16)
		textSize:set(22)
		t.expect(find(tabs, "a").TextSize).toBe(22)
		t.expect(find(tabs, "b").TextSize).toBe(22)
		t.expect(find(find(find(world.screen, "Plain"), "Tabs"), "p").TextSize)
			.toBe(find(world.screen, "Reference").TextSize)
		world.stop()
	end)

	t.it("reveals an offscreen selected tab once and never scrolls for a visible one", function()
		local selection = Compose.cell("a")
		local world = setup(function(UI, Host)
			local list = {}
			for _, id in { "a", "b", "c", "d", "e" } do
				table.insert(list, { id = id, label = string.upper(id), content = page(Host, id) })
			end
			return UI.TabView({ selection = selection, placement = "topBar", tabs = list })
		end)
		local tabs = find(world.screen, "Tabs")
		tabs.AbsoluteSize = V2(world, 300, 44)
		for index, id in { "a", "b", "c", "d", "e" } do
			local button = find(tabs, id)
			button.AbsolutePosition = V2(world, (index - 1) * 80, 0)
			button.AbsoluteSize = V2(world, 80, 44)
		end
		local writes = 0
		tabs:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			writes += 1
		end)
		selection:set("b")
		selection:set("a")
		selection:set("b")
		tabs.AbsoluteSize = V2(world, 301, 44)
		tabs.AbsoluteSize = V2(world, 300, 44)
		t.expect(writes).toBe(0)
		t.expect(tabs.CanvasPosition.X).toBe(0)
		selection:set("e")
		t.expect(writes).toBe(1)
		t.expect(tabs.CanvasPosition.X).toBe(100)
		world.stop()
	end)

	t.it("keeps the strip, the page and its owner across placement changes and round trips", function()
		local builds, cleanups = {}, {}
		local preference = Compose.cell("sidebar")
		local world = setup(function(UI, Host)
			return UI.TabView({
				selection = Compose.cell("a"),
				style = "sidebarAdaptable",
				sidebarPreference = preference,
				tabs = {
					{ id = "a", label = "A", content = page(Host, "a", builds, cleanups) },
					{ id = "b", label = "B", content = page(Host, "b", builds, cleanups) },
				},
			})
		end)
		local view = find(world.screen, "TabView")
		view.AbsoluteSize = V2(world, 1200, 800)
		local tabs, body = view:FindFirstChild("Tabs"), find(world.screen, "aBody")
		local layout = tabs:FindFirstChildWhichIsA("UIListLayout")
		t.expect(layout.FillDirection).toBe(world.engine.types.Enum.FillDirection.Vertical)
		preference:set("topBar")
		t.expect(layout.FillDirection).toBe(world.engine.types.Enum.FillDirection.Horizontal)
		preference:set("sidebar")
		local baseline = world.engine.census()
		for _ = 1, 12 do
			preference:set("topBar")
			preference:set("sidebar")
			view.AbsoluteSize = V2(world, 390, 844)
			view.AbsoluteSize = V2(world, 1200, 800)
		end
		t.expect(view:FindFirstChild("Tabs")).toBe(tabs)
		t.expect(find(world.screen, "aBody")).toBe(body)
		t.expect(builds).toEqual({ a = 1 })
		t.expect(cleanups).toEqual({})
		local after = world.engine.census()
		t.expect(after.live).toBe(baseline.live)
		t.expect(after.connections).toBe(baseline.connections)
		world.stop()
		t.expect(cleanups).toEqual({ a = 1 })
	end)

	t.it("moves adaptable tabs to a top band while a gamepad is the preferred input", function()
		local selection = Compose.cell("a")
		local world = setup(function(UI, Host)
			return UI.TabView({
				selection = selection,
				style = "sidebarAdaptable",
				accessories = {
					head = function()
						return Host.Frame("Brand")({})
					end,
					trailing = function()
						return Host.Frame("Search")({})
					end,
				},
				tabs = {
					{ id = "a", label = "A", content = page(Host, "a") },
					{ id = "b", label = "B", content = page(Host, "b") },
				},
			})
		end)
		local view = find(world.screen, "TabView")
		view.AbsoluteSize = V2(world, 1280, 800)
		t.expect(find(world.screen, "Accessory-head") ~= nil).toBe(true)
		t.expect(find(world.screen, "Accessory-trailing")).toBeNil()
		world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Gamepad
		t.expect(find(world.screen, "Accessory-head")).toBeNil()
		t.expect(find(world.screen, "Accessory-trailing") ~= nil).toBe(true)
		local tabs = view:FindFirstChild("Tabs")
		t.expect(tabs.Position).toBe(world.engine.types.UDim2.fromOffset(0, 0))
		t.expect(find(tabs, "b").Visible).toBe(true)
		find(tabs, "b").Activated.fire()
		t.expect(selection:peek()).toBe("b")
		t.expect(tabs.Position).toBe(world.engine.types.UDim2.fromOffset(0, 0))
		world.input.PreferredInput = world.engine.types.Enum.PreferredInput.KeyboardAndMouse
		t.expect(find(world.screen, "Accessory-head") ~= nil).toBe(true)
		world.stop()
	end)

	t.it(
		"orders customized tabs, skips stale ids, protects required tabs and falls back from a hidden selection",
		function()
			local builds = {}
			local selection = Compose.cell("home")
			local customization = Compose.cell({
				order = { "gone", "gear", "home", "gear" },
				hidden = { "home", "settings" },
			} :: any)
			local world = setup(function(UI, Host)
				return UI.TabView({
					selection = selection,
					customization = customization,
					tabs = {
						{ id = "home", label = "Home", required = true, content = page(Host, "home", builds) },
						{ id = "gear", label = "Gear", content = page(Host, "gear", builds) },
						{ id = "settings", label = "Settings", content = page(Host, "settings", builds) },
					},
				})
			end)
			local tabs = find(world.screen, "Tabs")
			local gear, home = find(tabs, "gear"), find(tabs, "home")
			t.expect(find(tabs, "settings")).toBeNil()
			t.expect(gear.LayoutOrder < home.LayoutOrder).toBe(true)
			customization:set({ order = { "home", "gear" } })
			t.expect(find(tabs, "home")).toBe(home)
			t.expect(find(tabs, "gear")).toBe(gear)
			t.expect(home.LayoutOrder < gear.LayoutOrder).toBe(true)
			t.expect(find(tabs, "settings") ~= nil).toBe(true)
			t.expect(builds).toEqual({ home = 1 })
			selection:set("gear")
			customization:set({ order = { "home", "gear" }, hidden = { "gear" } })
			t.expect(selection:peek()).toBe("home")
			t.expect(find(tabs, "gear")).toBeNil()
			world.stop()
		end
	)

	t.it("keeps a retained tab's scroll position on return and resets it when restoreScroll is off", function()
		for _, restore in { true, false } do
			local selection = Compose.cell("a")
			local world = setup(function(UI, Host)
				return UI.TabView({
					selection = selection,
					restoreScroll = if restore then nil else false,
					tabs = {
						{
							id = "a",
							label = "A",
							content = function()
								return Host.ScrollingFrame("Inventory")({})
							end,
						},
						{ id = "b", label = "B", content = page(Host, "b") },
					},
				})
			end)
			local inventory = find(world.screen, "Inventory")
			inventory.CanvasPosition = V2(world, 0, 450)
			selection:set("b")
			selection:set("a")
			t.expect(find(world.screen, "Inventory")).toBe(inventory)
			t.expect(inventory.CanvasPosition.Y).toBe(if restore then 450 else 0)
			world.stop()
		end
	end)
	for _, case in { { "VirtualGrid", false }, { "Table", false }, { "Table", true } } do
		local kind, editing = case[1], case[2]
		t.it("restores " .. kind .. " keys across a retained tab switch with editing=" .. tostring(editing), function()
			local data = {}
			for index = 1, 100 do
				data[index] = { id = tostring(index), label = "Item " .. index }
			end
			local rows, selection, edit = Compose.cell(data), Compose.cell("a"), Compose.cell(editing)
			local builds = 0
			local world = setup(function(UI, Host)
				local function render(current)
					builds += 1
					return Host.TextLabel({
						Name = "Label",
						Text = function(use)
							return use(current).label
						end,
					})
				end
				return UI.TabView({
					selection = selection,
					placement = "topBar",
					tabs = {
						{
							id = "a",
							label = "A",
							content = function()
								if kind == "Table" then
									return UI.Table("Collection")({
										from = rows,
										key = function(item)
											return item.id
										end,
										itemSize = 100,
										overscan = 0,
										editing = edit,
										reorderable = true,
										onReorder = function() end,
										columns = { { id = "label", label = "Item", render = render } },
									})
								end
								return UI.VirtualGrid("Collection")({
									from = rows,
									key = function(item)
										return item.id
									end,
									columns = 2,
									itemSize = 100,
									gap = 0,
									overscan = 0,
									render = render,
								})
							end,
						},
						{ id = "b", label = "B", content = page(Host, "b") },
					},
				})
			end)
			local collection = find(world.screen, "Collection")
			local scroll = if kind == "Table" then collection:FindFirstChild("Body") else collection
			scroll.AbsoluteWindowSize = V2(world, 200, 300)
			scroll.CanvasPosition = V2(world, 0, 2050)
			selection:set("b")
			local shifted = table.clone(data)
			table.insert(shifted, 1, table.remove(shifted))
			if kind == "VirtualGrid" then
				table.insert(shifted, 1, table.remove(shifted))
			end
			rows:set(shifted)
			selection:set("a")
			t.expect(find(world.screen, "Collection")).toBe(collection)
			t.expect(scroll.CanvasPosition.Y).toBe(2150)
			t.expect(builds < 100).toBe(true)
			selection:set("b")
			local shorter = {}
			for index = 1, 8 do
				shorter[index] = { id = "new-" .. index, label = "Replacement " .. index }
			end
			rows:set(shorter)
			selection:set("a")
			t.expect(scroll.CanvasPosition.Y).toBe(if kind == "VirtualGrid" then 100 else 500)
			selection:set("b")
			rows:set({})
			selection:set("a")
			t.expect(scroll.CanvasPosition.Y).toBe(0)
			edit:set(not editing)
			t.expect(find(world.screen, "Collection")).toBe(collection)
			world.stop()
		end)
	end

	t.it("keeps both showcase tab levels at the 44 pixel floor, marks each selection and reveals once", function()
		local engine, _, screen, built, stop = showcase()
		local Enum = engine.types.Enum
		local catalog = require("../examples/gallery/scenarios/all_controls")
		local categories = tabView(screen, "Categories")
		categories.AbsoluteSize = engine.types.Vector2.new(1280, 800)
		local outer = categories:FindFirstChild("Tabs")
		t.expect(outer:FindFirstChildWhichIsA("UIListLayout").FillDirection).toBe(Enum.FillDirection.Vertical)
		local function floor(button: any)
			t.expect(button:IsA("TextButton") and button.Selectable and button.Visible).toBe(true)
			t.expect(button:FindFirstChildWhichIsA("UISizeConstraint").MinSize).toBe(engine.types.Vector2.new(44, 44))
		end
		for _, group in catalog.groups do
			local button = find(outer, group.id)
			floor(button)
			button.Activated.fire()
			t.expect(built.report().selected.Categories).toBe(group.id)
			for _, other in catalog.groups do
				local tab = find(outer, other.id)
				t.expect(tab:HasTag("facet-tab-current")).toBe(other == group)
				t.expect(tab:HasTag("facet-tab-filled")).toBe(other == group)
			end
			local inner = tabView(screen, group.id)
			local strip = inner:FindFirstChild("Tabs")
			t.expect(strip:FindFirstChildWhichIsA("UIListLayout").FillDirection).toBe(Enum.FillDirection.Horizontal)
			for index, tab in group.tabs do
				local innerButton = find(strip, tab.id)
				floor(innerButton)
				t.expect(innerButton.Size.Y.Offset).toBe(44)
				t.expect(innerButton:FindFirstChild("SelectionIndicator") ~= nil).toBe(index == 1)
			end
		end
		find(outer, "actions").Activated.fire()
		local strip = tabView(screen, "actions"):FindFirstChild("Tabs")
		strip.AbsoluteSize = engine.types.Vector2.new(300, 44)
		strip.AbsolutePosition = engine.types.Vector2.new(0, 0)
		for index, tab in catalog.groups[2].tabs do
			local button = find(strip, tab.id)
			button.AbsolutePosition = engine.types.Vector2.new((index - 1) * 100, 0)
			button.AbsoluteSize = engine.types.Vector2.new(100, 44)
		end
		local writes = 0
		strip:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			writes += 1
		end)
		find(strip, "shortcuts").Activated.fire()
		find(strip, "recipes").Activated.fire()
		find(strip, "buttons").Activated.fire()
		t.expect(writes).toBe(0)
		find(strip, "help").Activated.fire()
		t.expect(built.report().active).toBe("help")
		t.expect(writes).toBe(1)
		t.expect(strip.CanvasPosition.X).toBe(500)
		for index, tab in catalog.groups[2].tabs do
			find(strip, tab.id).AbsolutePosition = engine.types.Vector2.new((index - 1) * 100 - 500, 0)
		end
		find(strip, "help").Activated.fire()
		strip.AbsoluteSize = engine.types.Vector2.new(301, 44)
		t.expect(writes).toBe(1)
		stop()
	end)

	t.it("climbs a badge on an unselected tab whose content was never built", function()
		local builds = {}
		local unread = Compose.cell(3)
		local selection = Compose.cell("home")
		local world = setup(function(UI, Host)
			return UI.TabView({
				selection = selection,
				placement = "bottomBar",
				tabs = {
					{ id = "home", label = "Home", content = page(Host, "home", builds) },
					{ id = "inbox", label = "Inbox", badge = unread, content = page(Host, "inbox", builds) },
					{ id = "me", label = "Me", content = page(Host, "me", builds) },
				},
			})
		end)
		local inbox = find(find(world.screen, "Tabs"), "inbox")
		local function shown()
			local label = inbox:FindFirstChild("Title", true)
			return if label then label.Text else inbox.Text
		end
		t.expect(shown()).toBe("Inbox (3)")
		selection:set("me")
		unread:update(function(value)
			return value + 1
		end)
		unread:update(function(value)
			return value + 1
		end)
		t.expect(builds.inbox).toBeNil()
		t.expect(shown()).toBe("Inbox (5)")
		t.expect(find(find(world.screen, "Tabs"), "inbox")).toBe(inbox)
		selection:set("inbox")
		t.expect(builds.inbox).toBe(1)
		world.stop()
	end)

	t.it("pages each showcase tab strip by shoulder, traps the alert and restores its launcher on Back", function()
		local _, gui, screen, built, stop = showcase()
		local categories = tabView(screen, "Categories")
		local outer = categories:FindFirstChild("Tabs")
		find(outer, "actions").Activated.fire()
		local inner = tabView(screen, "actions"):FindFirstChild("Tabs")
		gui.SelectedObject = find(inner, "buttons")
		action(screen, "NextTab").Pressed.fire()
		t.expect(built.report().selected.actions).toBe("shortcuts")
		t.expect(built.report().selected.Categories).toBe("actions")
		action(screen, "PreviousTab").Pressed.fire()
		action(screen, "PreviousTab").Pressed.fire()
		t.expect(built.report().selected.actions).toBe("buttons")
		gui.SelectedObject = find(outer, "actions")
		action(screen, "NextTab").Pressed.fire()
		t.expect(built.report().selected.Categories).toBe("indicators")
		t.expect(built.report().selected.actions).toBe("buttons")
		action(screen, "PreviousTab").Pressed.fire()
		t.expect(built.report().selected.Categories).toBe("actions")
		find(inner, "alerts").Activated.fire()
		t.expect(built.report().active).toBe("alerts")
		local launcher = find(tabView(screen, "actions"):FindFirstChild("Content"), "Open")
		gui.SelectedObject = launcher
		launcher.Activated.fire()
		t.expect(built.report().example.alert.presented).toBe(true)
		local modal = find(screen, "AlertModal")
		local panel = find(modal, "AlertPanel")
		t.expect(panel.SelectionGroup).toBe(true)
		for _, side in { "Up", "Down", "Left", "Right" } do
			t.expect(panel["SelectionBehavior" .. side].Name).toBe("Stop")
		end
		local held = gui.SelectedObject
		t.expect(held ~= nil and held:IsDescendantOf(panel)).toBe(true)
		t.expect(action(screen, "NextTab")).toBeNil()
		gui.SelectedObject = find(inner, "alerts")
		t.expect(action(screen, "NextTab")).toBeNil()
		t.expect(action(screen, "PreviousTab")).toBeNil()
		gui.SelectedObject = find(outer, "actions")
		t.expect(action(screen, "NextTab")).toBeNil()
		gui.SelectedObject = held
		local back = action(screen, "ModalBack")
		local keys = {}
		for _, binding in back:GetChildren() do
			if binding:IsA("InputBinding") then
				table.insert(keys, binding.KeyCode.Name)
			end
		end
		t.expect(table.find(keys, "ButtonB") ~= nil).toBe(true)
		back.Pressed.fire()
		t.expect(built.report().example.alert.presented).toBe(false)
		t.expect(gui.SelectedObject).toBe(launcher)
		t.expect(built.report().selected.Categories).toBe("actions")
		t.expect(built.report().active).toBe("alerts")
		find(outer, "navigation").Activated.fire()
		local journey = tabView(screen, "navigation")
		local continue = find(journey:FindFirstChild("Content"), "Continue")
		gui.SelectedObject = continue
		continue.Activated.fire()
		t.expect(built.report().example.navigation.depth).toBe(1)
		t.expect(gui.SelectedObject ~= continue and gui.SelectedObject:IsDescendantOf(journey)).toBe(true)
		action(screen, "NavigationBack").Pressed.fire()
		t.expect(built.report().example.navigation.depth).toBe(0)
		t.expect(gui.SelectedObject).toBe(continue)
		action(screen, "NextTab").Pressed.fire()
		t.expect(built.report().selected.Categories).toBe("navigation")
		t.expect(built.report().active).toBe("pages")
		stop()
	end)

	t.it("opens a menu only through its declared triggers and binds the keyboard and gamepad chords", function()
		local restricted, activateOnly = Compose.cell(false), Compose.cell(false)
		local world = setup(function(UI, Host)
			local items = { { id = "a", label = "A", onSelect = function() end } }
			return Host.Frame({
				UI.Menu("Restricted")({
					label = "Actions",
					isPresented = restricted,
					items = items,
					triggers = { "secondary", "keyboard", "gamepad" },
				}),
				UI.Menu("Tap")({ label = "Tap", isPresented = activateOnly, items = items, triggers = { "activate" } }),
			})
		end)
		local Enum = world.engine.types.Enum
		local trigger = find(find(world.screen, "Restricted"), "Trigger")
		trigger.Activated.fire()
		t.expect(restricted:peek()).toBe(false)
		trigger.InputBegan.fire({ UserInputType = Enum.UserInputType.MouseButton2 })
		t.expect(restricted:peek()).toBe(true)
		t.expect(find(world.screen, "MenuPanel") ~= nil).toBe(true)
		action(world.screen, "ModalBack").Pressed.fire()
		t.expect(restricted:peek()).toBe(false)
		t.expect(action(world.screen, "Menu")).toBeNil()
		world.gui.SelectedObject = trigger
		local chord = action(world.screen, "Menu")
		local bindings = {}
		for _, binding in chord:GetChildren() do
			local modifier = binding.PrimaryModifier
			local plain = modifier == nil or modifier == Enum.KeyCode.Unknown
			table.insert(bindings, binding.KeyCode.Name .. (if plain then "" else "+" .. modifier.Name))
		end
		table.sort(bindings)
		t.expect(bindings).toEqual({ "ButtonY", "F10+LeftShift", "F10+RightShift", "Menu" })
		chord.Pressed.fire()
		t.expect(restricted:peek()).toBe(true)
		action(world.screen, "ModalBack").Pressed.fire()
		local tap = find(find(world.screen, "Tap"), "Trigger")
		tap.InputBegan.fire({ UserInputType = Enum.UserInputType.MouseButton2 })
		tap.TouchLongPress.fire({}, Enum.UserInputState.Begin)
		world.gui.SelectedObject = tap
		t.expect(action(world.screen, "Menu")).toBeNil()
		t.expect(activateOnly:peek()).toBe(false)
		tap.Activated.fire()
		t.expect(activateOnly:peek()).toBe(true)
		world.stop()
	end)

	t.it("opens a wholly disabled menu and keeps it open when a disabled item is activated", function()
		local opened, ran = Compose.cell(false), 0
		local world = setup(function(UI)
			return UI.Menu({
				isPresented = opened,
				items = {
					{
						id = "save",
						label = "Save",
						enabled = false,
						onSelect = function()
							ran += 1
						end,
					},
					{
						id = "share",
						label = "Share",
						enabled = false,
						onSelect = function()
							ran += 1
						end,
					},
				},
			})
		end)
		find(world.screen, "Trigger").Activated.fire()
		t.expect(opened:peek()).toBe(true)
		local panel = find(world.screen, "MenuPanel")
		for _, id in { "save", "share" } do
			local row = find(panel, id)
			t.expect(row.Interactable).toBe(false)
			t.expect(row:HasTag("facet-disabled")).toBe(true)
			row.Activated.fire()
		end
		t.expect(ran).toBe(0)
		t.expect(opened:peek()).toBe(true)
		world.stop()
	end)

	t.it("unwinds submenus one level at a time and enters a branch only from a focused branch row", function()
		local opened = Compose.cell(false)
		local world = setup(function(UI)
			return UI.Menu({
				isPresented = opened,
				items = {
					{ id = "First", label = "First", onSelect = function() end },
					{
						id = "Parent",
						label = "Parent",
						children = { { id = "Leaf", label = "Leaf", onSelect = function() end } },
					},
				},
			})
		end)
		world.gui.SelectedObject = find(world.screen, "Trigger")
		opened:set(true)
		local modal = find(world.screen, "Modal")
		modal.AbsoluteSize = V2(world, 1000, 720)
		t.expect(world.gui.SelectedObject.Name).toBe("First")
		t.expect(action(world.screen, "MenuRight")).toBeNil()
		local keys = {}
		for _, context in contexts(world.screen, "MenuRight") do
			for _, binding in context:FindFirstChild("MenuRight"):GetChildren() do
				table.insert(keys, binding.KeyCode.Name)
			end
		end
		table.sort(keys)
		t.expect(keys).toEqual({ "DPadRight", "Right" })
		local panel = find(world.screen, "MenuPanel")
		world.gui.SelectedObject = find(panel, "Parent")
		t.expect(find(panel, "Parent"):FindFirstChild("TrailingIcon", true).Image ~= "").toBe(true)
		t.expect(find(panel, "First"):FindFirstChild("TrailingIcon", true)).toBeNil()
		action(world.screen, "MenuRight").Pressed.fire()
		t.expect(find(panel, "Leaf") ~= nil).toBe(true)
		t.expect(world.gui.SelectedObject.Name).toBe("Leaf")
		t.expect(action(world.screen, "MenuRight")).toBeNil()
		action(world.screen, "MenuLeft").Pressed.fire()
		t.expect(find(panel, "Leaf")).toBeNil()
		t.expect(world.gui.SelectedObject.Name).toBe("Parent")
		t.expect(opened:peek()).toBe(true)
		action(world.screen, "MenuRight").Pressed.fire()
		action(world.screen, "ModalBack").Pressed.fire()
		t.expect(find(panel, "Leaf")).toBeNil()
		t.expect(opened:peek()).toBe(true)
		t.expect(world.gui.SelectedObject.Name).toBe("Parent")
		action(world.screen, "ModalBack").Pressed.fire()
		t.expect(opened:peek()).toBe(false)
		world.stop()
	end)

	t.it("follows the presentation option and touch input between the menu and sheet idioms", function()
		local opened, presentation = Compose.cell(false), Compose.cell("sheet")
		local world = setup(function(UI)
			return UI.Menu({
				isPresented = opened,
				presentation = presentation,
				backLabel = "Retour",
				items = {
					{
						id = "Parent",
						label = "Parent",
						children = { { id = "Leaf", label = "Leaf", onSelect = function() end } },
					},
				},
			})
		end)
		opened:set(true)
		local modal = find(world.screen, "Modal")
		modal.AbsoluteSize = V2(world, 1000, 720)
		find(world.screen, "Parent").Activated.fire()
		local back = find(world.screen, "Back")
		t.expect(back ~= nil).toBe(true)
		t.expect(back.Text).toBe("Retour")
		t.expect(find(world.screen, "AncestorMenu")).toBeNil()
		presentation:set("menu")
		t.expect(find(world.screen, "AncestorMenu") ~= nil).toBe(true)
		t.expect(find(world.screen, "Leaf") ~= nil).toBe(true)
		presentation:set("automatic")
		t.expect(find(world.screen, "AncestorMenu") ~= nil).toBe(true)
		world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Touch
		t.expect(find(world.screen, "AncestorMenu")).toBeNil()
		t.expect(find(world.screen, "Leaf") ~= nil).toBe(true)
		world.input.PreferredInput = world.engine.types.Enum.PreferredInput.KeyboardAndMouse
		t.expect(find(world.screen, "AncestorMenu") ~= nil).toBe(true)
		modal.AbsoluteSize = V2(world, 360, 720)
		t.expect(find(world.screen, "AncestorMenu")).toBeNil()
		presentation:set("menu")
		t.expect(find(world.screen, "AncestorMenu") ~= nil).toBe(true)
		t.expect(find(world.screen, "Leaf") ~= nil).toBe(true)
		world.stop()
	end)

	t.it("toggles nested checked items in both idioms and releases every level with the trigger", function()
		for _, presentation in { "menu", "sheet" } do
			local checked = Compose.cell(false)
			local show = Compose.cell(true)
			local world = setup(function(UI, Host)
				return Host.Frame({
					Compose.show(show, function()
						return UI.Menu({
							presentation = presentation,
							items = {
								{
									id = "options",
									label = "Options",
									children = {
										{
											id = "deeper",
											label = "Deeper",
											children = {
												{ id = "check", label = "Check", checked = checked, dismiss = true },
											},
										},
									},
								},
							},
						})
					end),
				})
			end)
			local before = world.engine.census()
			for round = 1, 2 do
				find(world.screen, "Trigger").Activated.fire()
				find(world.screen, "Modal").AbsoluteSize = V2(world, 1000, 720)
				find(find(world.screen, "MenuPanel"), "options").Activated.fire()
				find(find(world.screen, "MenuPanel"), "deeper").Activated.fire()
				find(find(world.screen, "MenuPanel"), "check").Activated.fire()
				t.expect(checked:peek()).toBe(round == 1)
				t.expect(find(world.screen, "MenuPanel")).toBeNil()
			end
			local closed = world.engine.census()
			for _ = 1, 20 do
				find(world.screen, "Trigger").Activated.fire()
				find(world.screen, "Modal").AbsoluteSize = V2(world, 1000, 720)
				find(find(world.screen, "MenuPanel"), "options").Activated.fire()
				find(find(world.screen, "MenuPanel"), "deeper").Activated.fire()
				action(world.screen, "ModalBack").Pressed.fire()
				action(world.screen, "ModalBack").Pressed.fire()
				action(world.screen, "ModalBack").Pressed.fire()
			end
			t.expect(find(world.screen, "MenuPanel")).toBeNil()
			local churned = world.engine.census()
			t.expect(churned.live).toBe(closed.live)
			t.expect(churned.connections).toBe(closed.connections)
			find(world.screen, "Trigger").Activated.fire()
			find(find(world.screen, "MenuPanel"), "options").Activated.fire()
			find(find(world.screen, "MenuPanel"), "deeper").Activated.fire()
			show:set(false)
			t.expect(find(world.screen, "MenuPanel")).toBeNil()
			t.expect(find(world.screen, "AncestorMenu")).toBeNil()
			t.expect(find(world.screen, "DismissOutside")).toBeNil()
			t.expect(#contexts(world.screen, "ModalBack")).toBe(0)
			local after = world.engine.census()
			t.expect(after.connections <= before.connections).toBe(true)
			world.stop()
		end
	end)

	t.it(
		"anchors the menu panel below its trigger, sizes it from the widest row and keeps it inside the viewport",
		function()
			local opened = Compose.cell(false)
			local world = setup(function(UI)
				return UI.Menu({
					isPresented = opened,
					items = {
						{ id = "short", label = "Short", onSelect = function() end },
						{ id = "long", label = "Long", onSelect = function() end },
					},
				})
			end)
			local trigger = find(world.screen, "Trigger")
			trigger.AbsolutePosition = V2(world, 100, 100)
			trigger.AbsoluteSize = V2(world, 200, 44)
			opened:set(true)
			local modal = find(world.screen, "Modal")
			modal.AbsoluteSize = V2(world, 1000, 844)
			local panel = find(world.screen, "MenuPanel")
			find(find(panel, "short"), "Content").AbsoluteSize = V2(world, 120, 44)
			find(find(panel, "long"), "Content").AbsoluteSize = V2(world, 300, 44)
			find(panel, "MenuRows").AbsoluteSize = V2(world, 348, 104)
			t.expect(panel.Size.X.Offset).toBe(348)
			t.expect(panel.Size.Y.Offset).toBe(104)
			panel.AbsoluteSize = V2(world, 348, 104)
			world.engine.heartbeat.fire(1)
			t.expect(panel.Position).toBe(world.engine.types.UDim2.fromOffset(100, 148))
			find(find(panel, "long"), "Content").AbsoluteSize = V2(world, 500, 44)
			t.expect(panel.Size.X.Offset).toBe(400)
			find(find(panel, "long"), "Content").AbsoluteSize = V2(world, 50, 44)
			t.expect(panel.Size.X.Offset).toBe(220)
			trigger.AbsolutePosition = V2(world, 900, 800)
			panel.AbsoluteSize = V2(world, 220, 104)
			t.expect(panel.Position.X.Offset).toBe(1000 - 220 - 8)
			t.expect(panel.Position.Y.Offset).toBe(800 - 104 - 4)
			world.stop()
		end
	)

	t.it("keeps a picker and menu tap-away catcher invisible at every background preference", function()
		for _, kind in { "menu", "picker" } do
			local opened = Compose.cell(true)
			local world = setup(function(UI)
				if kind == "menu" then
					return UI.Menu({
						isPresented = opened,
						items = { { id = "a", label = "A", onSelect = function() end } },
					})
				end
				return UI.Picker({
					selected = Compose.cell("a"),
					style = "menu",
					isPresented = opened,
					options = { { value = "a", label = "A" }, { value = "b", label = "B" } },
				})
			end)
			local catcher = find(world.screen, "DismissOutside")
			for _, preference in { 1, 0.5, 0 } do
				world.gui.PreferredTransparency = preference
				t.expect(catcher.BackgroundTransparency).toBe(1)
			end
			world.stop()
		end
		local expanded = Compose.cell(true)
		local world = setup(function(UI, Host)
			return UI.CollapsibleView({
				label = "More",
				expanded = expanded,
				content = function()
					return Host.Frame({})
				end,
			})
		end)
		world.gui.PreferredTransparency = 0
		t.expect(find(world.screen, "DismissOutside"):HasTag("facet-scrim")).toBe(true)
		world.stop()
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local stop, sheet: any = runtime.mount(function()
			return Facet.themes.createStyleSheet(runtime, Facet.themes.neutralPackage(), { types = engine.types })
		end, engine.new("Folder"))
		local scrim
		for _, rule in sheet:GetChildren() do
			if rule.Selector == ".facet-scrim" then
				scrim = rule:GetProperties().BackgroundTransparency
			end
		end
		t.expect(scrim > 0 and scrim < 1).toBe(true)
		stop()
		runtime:dispose()
	end)
	t.it("picks from a vertical radio group and moves the current paint with the selection and indicator", function()
		local selected, indicator = Compose.cell("a"), Compose.cell(nil :: string?)
		local world = setup(function(UI, Host)
			local options = {
				{ value = "a", label = "A" },
				{ value = "b", label = "B" },
				{ value = "c", label = "C" },
			}
			return Host.Frame({
				UI.Picker("Radio")({ selected = selected, style = "radioGroup", options = options }),
				UI.Picker("Segments")({
					selected = selected,
					style = "segmented",
					indicator = indicator,
					options = options,
				}),
				UI.Picker("Inline")({ selected = selected, style = "inline", options = options }),
			})
		end)
		local Enum = world.engine.types.Enum
		local radio = find(world.screen, "Radio")
		t.expect(radio:FindFirstChildWhichIsA("UIListLayout").FillDirection).toBe(Enum.FillDirection.Vertical)
		for _, id in { "a", "b", "c" } do
			t.expect(find(radio, id):HasTag("facet-choice")).toBe(true)
		end
		find(radio, "b").Activated.fire()
		t.expect(selected:peek()).toBe("b")
		local segments, inline = find(world.screen, "Segments"), find(world.screen, "Inline")
		local a, b = find(segments, "a"), find(segments, "b")
		t.expect(b:HasTag("facet-segment-current")).toBe(true)
		t.expect(b:HasTag("facet-selected")).toBe(true)
		t.expect(a:HasTag("facet-segment-current")).toBe(false)
		t.expect(a:HasTag("facet-selected")).toBe(false)
		t.expect(find(inline, "b"):HasTag("facet-choice-current")).toBe(true)
		t.expect(find(radio, "b"):HasTag("facet-choice-current")).toBe(true)
		selected:set("a")
		t.expect(find(segments, "a")).toBe(a)
		t.expect(a:HasTag("facet-segment-current")).toBe(true)
		t.expect(b:HasTag("facet-segment-current")).toBe(false)
		t.expect(find(inline, "a"):HasTag("facet-choice-current")).toBe(true)
		t.expect(find(inline, "b"):HasTag("facet-choice-current")).toBe(false)
		indicator:set("underline")
		t.expect(a:FindFirstChild("SelectionIndicator") ~= nil).toBe(true)
		t.expect(a:HasTag("facet-segment-current")).toBe(false)
		t.expect(a:HasTag("facet-selected")).toBe(false)
		indicator:set("pill")
		t.expect(a:FindFirstChild("SelectionIndicator")).toBeNil()
		t.expect(a:HasTag("facet-segment-current")).toBe(true)
		indicator:set("none")
		t.expect(a:FindFirstChild("SelectionIndicator")).toBeNil()
		t.expect(a:HasTag("facet-segment-current")).toBe(true)
		indicator:set("automatic")
		t.expect(a:HasTag("facet-segment-current")).toBe(true)
		world.stop()
	end)

	t.it("sizes segments by fill or hug without replacing them and refuses unknown sizing", function()
		local sizing, selected = Compose.cell("fill"), Compose.cell("a")
		local world = setup(function(UI)
			return UI.Picker({
				selected = selected,
				style = "segmented",
				sizing = sizing,
				options = { { value = "a", label = "A" }, { value = "b", label = "Much longer" } },
			})
		end)
		local Enum = world.engine.types.Enum
		local picker = find(world.screen, "Picker")
		local layout = picker:FindFirstChildWhichIsA("UIListLayout")
		local a = find(picker, "a")
		t.expect(layout.HorizontalFlex).toBe(Enum.UIFlexAlignment.Fill)
		t.expect(a.AutomaticSize).toBe(Enum.AutomaticSize.X)
		t.expect(a.Size.Y.Scale).toBe(1)
		sizing:set("hug")
		t.expect(layout.HorizontalFlex).toBe(Enum.UIFlexAlignment.None)
		t.expect(find(picker, "a")).toBe(a)
		sizing:set("fill")
		t.expect(layout.HorizontalFlex).toBe(Enum.UIFlexAlignment.Fill)
		world.stop()
		t.expect(refuses("Picker.sizing must be fill or hug", function(UI)
			return UI.Picker({
				selected = Compose.cell("a"),
				style = "segmented",
				sizing = "wide",
				options = { { value = "a", label = "A" } },
			})
		end)).toBe(true)
	end)

	t.it("refuses malformed picker options, labels, icons, indicators, axes and styles", function()
		local function picker(extra)
			return function(UI)
				local spec: { [string]: any } = {
					selected = Compose.cell("a"),
					style = "segmented",
					options = { { value = "a", label = "A" } },
				}
				for field, value in extra do
					spec[field] = value
				end
				return UI.Picker(spec)
			end
		end
		local cases: { { any } } = {
			{ "Picker options require nonempty labels", { options = { { value = "a", label = "" } } } },
			{ "Picker options require nonempty labels", { options = { { value = "a", label = Compose.cell("") } } } },
			{
				"Picker.iconOnly requires an icon on each option",
				{ iconOnly = true, options = { { value = "a", label = "A" } } },
			},
			{ "Invalid Picker.indicator", { indicator = "bar" } },
			{ "Picker.axis must be x or y", { axis = "z" } },
			{ "Unknown Picker style", { style = "wheel" } },
		}
		local malformed: { { any } } = {
			{ "Picker options require a dense array", { named = { value = "a", label = "A" } } },
			{
				"Picker options require a dense array",
				{ [1] = { value = "a", label = "A" }, [3] = { value = "b", label = "B" } },
			},
			{ "Picker options require nonempty labels", { { value = "a", label = "" } } },
			{ "Picker description must be text", { { value = "a", label = "A", description = false } } },
			{
				"Picker options require unique values or ids",
				{ { value = "a", label = "A" }, { value = "a", label = "B" } },
			},
			{ "Picker options require unique values or ids", { { label = "Nameless" } } },
		}
		for _, entry in malformed do
			table.insert(cases, { entry[1], { style = "menu", options = entry[2] } })
			table.insert(cases, { entry[1], { style = "menu", options = Compose.cell(entry[2]) } })
			table.insert(cases, { entry[1], { style = "inline", options = entry[2] } })
		end
		for _, case in cases do
			local failure = mountError(picker(case[2]))
			t.expect(failure ~= nil and string.find(failure, case[1], 1, true) ~= nil).toBe(true)
		end
		t.expect(mountError(picker({ indicator = "automatic" }))).toBeNil()
	end)

	t.it("resolves the automatic picker by width, description, count, input and query", function()
		local options = Compose.cell({
			{ value = "a", label = "A" },
			{ value = "b", label = "B" },
		} :: { any })
		local world = setup(function(UI)
			return UI.Picker({ selected = Compose.cell("a"), options = options })
		end)
		local Enum = world.engine.types.Enum
		local container = find(world.screen, "Picker")
		local function presentation()
			return container:FindFirstChild("Presentation")
		end
		container.AbsoluteSize = V2(world, 400, 44)
		t.expect(presentation():HasTag("facet-segmented")).toBe(true)
		local first = presentation()
		container.AbsoluteSize = V2(world, 300, 44)
		world.input.PreferredInput = Enum.PreferredInput.KeyboardAndMouse
		t.expect(find(presentation(), "Trigger") ~= nil).toBe(true)
		world.input.PreferredInput = Enum.PreferredInput.Gamepad
		t.expect(presentation():HasTag("facet-segmented")).toBe(false)
		t.expect(find(presentation(), "a") ~= nil).toBe(true)
		t.expect(find(presentation(), "Trigger")).toBeNil()
		container.AbsoluteSize = V2(world, 400, 44)
		options:set({
			{ value = "a", label = "A", description = "First" },
			{ value = "b", label = "B" },
		})
		t.expect(presentation():HasTag("facet-segmented")).toBe(false)
		t.expect(find(presentation(), "a") ~= nil).toBe(true)
		local seven = {}
		for index = 1, 7 do
			table.insert(seven, { value = tostring(index), label = `Option {index}` })
		end
		seven[1].value = "a"
		options:set(seven)
		t.expect(find(presentation(), "Trigger") ~= nil).toBe(true)
		options:set({ table.unpack(seven, 1, 6) })
		t.expect(find(presentation(), "Trigger")).toBeNil()
		t.expect(find(presentation(), "a") ~= nil).toBe(true)
		t.expect(find(world.screen, "Picker")).toBe(container)
		t.expect(first ~= presentation()).toBe(true)
		world.stop()
		local query = Compose.cell("")
		local searching = setup(function(UI)
			return UI.Picker({
				selected = Compose.cell("a"),
				query = query,
				options = { { value = "a", label = "A" }, { value = "b", label = "B" } },
			})
		end)
		local link = find(searching.screen, "Presentation")
		t.expect(link.ClassName).toBe("TextButton")
		link.Activated.fire()
		t.expect(find(searching.screen, "PickerSearch") ~= nil).toBe(true)
		searching.stop()
	end)

	t.it("never shows a selection redirected inside onChange to observers", function()
		local selected = Compose.cell("a")
		local seen = {}
		local world = setup(function(UI)
			Compose.watch(function(use)
				table.insert(seen, use(selected))
			end)
			return UI.Picker({
				selected = selected,
				style = "segmented",
				options = { { value = "a", label = "A" }, { value = "b", label = "B" } },
				onChange = function()
					selected:set("a")
				end,
			})
		end)
		find(world.screen, "b").Activated.fire()
		t.expect(selected:peek()).toBe("a")
		t.expect(table.find(seen, "b")).toBeNil()
		world.stop()
	end)

	t.it("closes a menu picker by trigger or Back without changing the selection", function()
		local selected, opened = Compose.cell("a"), Compose.cell(false)
		local world = setup(function(UI)
			return UI.Picker({
				selected = selected,
				style = "menu",
				isPresented = opened,
				options = { { value = "a", label = "A" }, { value = "b", label = "B" } },
			})
		end)
		local trigger = find(world.screen, "Trigger")
		trigger.Activated.fire()
		t.expect(opened:peek()).toBe(true)
		action(world.screen, "ModalBack").Pressed.fire()
		t.expect(opened:peek()).toBe(false)
		t.expect(selected:peek()).toBe("a")
		trigger.Activated.fire()
		find(world.screen, "DismissOutside").Activated.fire({ Position = world.engine.types.Vector3.new(0, 0, 0) })
		t.expect(opened:peek()).toBe(false)
		t.expect(selected:peek()).toBe("a")
		trigger.Activated.fire()
		find(find(world.screen, "MenuPanel"), "b").Activated.fire()
		t.expect(opened:peek()).toBe(false)
		t.expect(selected:peek()).toBe("b")
		world.stop()
	end)
	t.it("refuses unknown and duplicate sheet detents and a read-only detent source", function()
		local function sheet(extra)
			return function(UI, Host)
				local spec: { [string]: any } = {
					isPresented = Compose.cell(false),
					detent = Compose.cell("medium"),
					title = "Sheet",
					content = page(Host, "sheet"),
				}
				for field, value in extra do
					spec[field] = value
				end
				return UI.Sheet(spec)
			end
		end
		t.expect(refuses("Invalid Sheet detent", sheet({ detents = { "tiny" } }))).toBe(true)
		t.expect(refuses("Sheet detents require unique ids", sheet({ detents = { "medium", "medium" } }))).toBe(true)
		t.expect(refuses(
			"Sheet.detent requires a writable Compose cell",
			sheet({
				detent = Compose.formula(function()
					return "medium"
				end),
			})
		)).toBe(true)
		t.expect(mountError(sheet({ detents = { "medium", { id = "tall", height = 600 } } }))).toBeNil()
	end)

	t.it("dismisses a sheet dragged below its smallest detent and keeps a 44 pixel grabber", function()
		local opened, detent = Compose.cell(true), Compose.cell("medium")
		local world = setup(function(UI, Host)
			return UI.Sheet({ isPresented = opened, detent = detent, title = "Sheet", content = page(Host, "sheet") })
		end, { reducedMotion = true })
		find(world.screen, "Modal").AbsoluteSize = V2(world, 390, 720)
		local panel = find(world.screen, "SheetPanel")
		t.expect(panel.Size.Y.Offset).toBe(360)
		local grabber = find(world.screen, "Grabber")
		t.expect(grabber.Size.X.Offset >= 44 and grabber.Size.Y.Offset >= 44).toBe(true)
		local drag = find(world.screen, "UIDragDetector")
		drag.DragStart.fire(V2(world, 0, 0))
		drag.DragContinue.fire(V2(world, 0, 60))
		drag.DragEnd.fire()
		t.expect(opened:peek()).toBe(true)
		t.expect(detent:peek()).toBe("medium")
		drag.DragStart.fire(V2(world, 0, 0))
		drag.DragContinue.fire(V2(world, 0, 400))
		drag.DragEnd.fire()
		t.expect(opened:peek()).toBe(false)
		t.expect(find(world.screen, "SheetPanel")).toBeNil()
		world.stop()
	end)

	t.it("continues a grab during a detent change from the painted height", function()
		local detent = Compose.cell("medium")
		local world = setup(function(UI, Host)
			return UI.Sheet({
				isPresented = Compose.cell(true),
				detent = detent,
				title = "Sheet",
				content = page(Host, "sheet"),
			})
		end)
		find(world.screen, "Modal").AbsoluteSize = V2(world, 390, 720)
		world.engine.heartbeat.fire(1)
		world.engine.heartbeat.fire(1)
		local panel = find(world.screen, "SheetPanel")
		t.expect(panel.Size.Y.Offset).toBeCloseTo(360, 0.5)
		detent:set("large")
		world.engine.heartbeat.fire(0.05)
		local painted = panel.Size.Y.Offset
		t.expect(painted > 360 and painted < 684).toBe(true)
		local drag = find(world.screen, "UIDragDetector")
		drag.DragStart.fire(V2(world, 0, 0))
		t.expect(panel.Size.Y.Offset).toBeCloseTo(painted, 0.5)
		drag.DragContinue.fire(V2(world, 0, 1))
		t.expect(panel.Size.Y.Offset).toBeCloseTo(painted - 1, 0.5)
		world.stop()
	end)

	t.it("gates callout eligibility on sessions, seen and feature use and refuses a missing onRetire", function()
		local sessions = Compose.cell(1)
		local retired = {}
		local world = setup(function(UI, Host)
			local function anchor(name)
				return Host.TextButton(name)({})
			end
			local first, second, third = anchor("First"), anchor("Second"), anchor("Third")
			local function callout(name, target, extra)
				local spec: { [string]: any } = {
					anchor = target,
					content = function()
						return Host.TextLabel(name .. "Tip")({ Text = name })
					end,
					onRetire = function(reason)
						table.insert(retired, name .. ":" .. reason)
					end,
				}
				for field, value in extra do
					spec[field] = value
				end
				return UI.Callout(spec)
			end
			return Host.Frame({
				first,
				second,
				third,
				callout("Later", first, { sessions = sessions, afterSessions = 3 }),
				callout("Seen", second, { seen = Compose.cell(true), priority = 5 }),
				callout("Used", third, { featureUsed = Compose.cell(true), priority = 6 }),
			})
		end)
		t.expect(find(world.screen, "LaterTip")).toBeNil()
		t.expect(find(world.screen, "SeenTip")).toBeNil()
		t.expect(find(world.screen, "UsedTip")).toBeNil()
		table.sort(retired)
		t.expect(retired).toEqual({ "Seen:seen", "Used:featureUsed" })
		sessions:set(2)
		t.expect(find(world.screen, "LaterTip")).toBeNil()
		sessions:set(3)
		t.expect(find(world.screen, "LaterTip") ~= nil).toBe(true)
		world.stop()
		t.expect(refuses("Callout requires onRetire", function(UI, Host)
			return UI.Callout({ anchor = Host.TextButton({}), content = page(Host, "tip") })
		end)).toBe(true)
		t.expect(refuses("unknown option 'persist'", function(UI, Host)
			return UI.Callout({
				anchor = Host.TextButton({}),
				content = page(Host, "tip"),
				onRetire = function() end,
				persist = true,
			})
		end)).toBe(true)
	end)

	t.it("frees the callout queue slot when the showing callout is disposed", function()
		local flag, retired = Compose.cell(true), {}
		local world = setup(function(UI, Host)
			local anchor = Host.TextButton("Anchor")({})
			local function callout(name, priority)
				return UI.Callout({
					anchor = anchor,
					priority = priority,
					content = function()
						return Host.TextLabel(name .. "Tip")({ Text = name })
					end,
					onRetire = function(reason)
						table.insert(retired, name .. ":" .. reason)
					end,
				})
			end
			return Host.Frame({
				anchor,
				Compose.show(flag, function()
					return callout("High", 2)
				end),
				callout("Low", 1),
			})
		end)
		t.expect(find(world.screen, "HighTip") ~= nil).toBe(true)
		t.expect(find(world.screen, "LowTip")).toBeNil()
		flag:set(false)
		t.expect(find(world.screen, "HighTip")).toBeNil()
		t.expect(find(world.screen, "LowTip") ~= nil).toBe(true)
		t.expect(retired).toEqual({})
		world.stop()
	end)

	t.it(
		"aligns a callout to the anchor edges, flips it above near the bottom and omits an unrequested tail",
		function()
			local align = Compose.cell("center")
			local world = setup(function(UI, Host)
				local anchor = Host.TextButton("Anchor")({})
				local withoutTail = Host.TextButton("Quiet")({})
				return Host.Frame({
					anchor,
					withoutTail,
					UI.Callout({
						anchor = anchor,
						align = align,
						content = page(Host, "tip"),
						onRetire = function() end,
					}),
				})
			end)
			world.screen.AbsoluteSize = V2(world, 960, 720)
			local anchor = find(world.screen, "Anchor")
			anchor.AbsolutePosition = V2(world, 160, 660)
			anchor.AbsoluteSize = V2(world, 240, 44)
			local panel = find(world.screen, "CalloutPanel")
			panel.AbsoluteSize = V2(world, 280, 100)
			world.engine.heartbeat.fire(1)
			t.expect(panel.Position.Y.Offset).toBe(660 - 100 - 8)
			t.expect(panel.Position.X.Offset).toBe(140)
			align:set("leading")
			t.expect(panel.Position.X.Offset).toBe(160)
			align:set("trailing")
			t.expect(panel.Position.X.Offset).toBe(160 + 240 - 280)
			anchor.AbsolutePosition = V2(world, 160, 100)
			t.expect(panel.Position.Y.Offset).toBe(100 + 44 + 8)
			t.expect(find(world.screen, "Arrow") ~= nil).toBe(true)
			world.stop()
			for _, tail in { false, "none" } :: { any } do
				local quiet = setup(function(UI, Host)
					local anchor = Host.TextButton("Anchor")({})
					return Host.Frame({
						anchor,
						UI.Callout({
							anchor = anchor,
							tail = tail,
							content = page(Host, "tip"),
							onRetire = function() end,
						}),
					})
				end)
				t.expect(find(quiet.screen, "CalloutPanel") ~= nil).toBe(true)
				t.expect(find(quiet.screen, "Arrow")).toBeNil()
				quiet.stop()
			end
		end
	)

	t.it("keeps device names out of the control sources", function()
		for _, file in fs.readDir("src/ui") do
			local source = string.lower(fs.readFile("src/ui/" .. file))
			for _, device in { "iphone", "ipad", "android", "xbox", "playstation", "nintendo", "macos", "windows" } do
				t.expect(string.find(source, "%f[%a]" .. device .. "%f[%A]") == nil).toBe(true)
			end
		end
	end)
	t.it("adds a default OK action and keeps an alert open on outside taps and custom content buttons", function()
		for _, surface in { "dialog", "fullScreen" } do
			local presented = Compose.cell(true)
			local world = setup(function(UI)
				return UI.Alert({
					isPresented = presented,
					title = "Saved",
					surface = surface,
					content = function()
						return UI.Button("OK")({ label = "Preview" })
					end,
				})
			end)
			local actions = find(world.screen, "Actions")
			local content = find(world.screen, "AlertContent")
			t.expect(find(content, "OK").Text).toBe("Preview")
			find(content, "OK").Activated.fire()
			t.expect(presented:peek()).toBe(true)
			find(world.screen, "DismissOutside").Activated.fire({ Position = world.engine.types.Vector3.new(0, 0, 0) })
			t.expect(presented:peek()).toBe(true)
			find(world.screen, "DismissOutside").Activated.fire()
			t.expect(presented:peek()).toBe(true)
			t.expect(find(actions, "OK").Text).toBe("OK")
			find(actions, "OK").Activated.fire()
			t.expect(presented:peek()).toBe(false)
			world.stop()
		end
	end)

	t.it(
		"refuses misspelled alert fields, duplicate action ids, two cancel actions and malformed transitions",
		function()
			t.expect(refuses("unknown option 'paddding'", function(UI)
				return UI.Alert({ isPresented = Compose.cell(false), title = "T", paddding = 12 })
			end)).toBe(true)
			t.expect(refuses("Alert.transition supports source, seconds, ease", function(UI)
				return UI.Alert({ isPresented = Compose.cell(false), title = "T", transition = { enter = "fade" } })
			end)).toBe(true)
			for _, transition in { "instant", 7 } :: { any } do
				t.expect(refuses("Alert transition must be a table or false", function(UI)
					return UI.Alert({ isPresented = Compose.cell(false), title = "T", transition = transition })
				end)).toBe(true)
			end
			for _, case in
				{
					{
						"Alert actions require unique ids",
						{ { id = "a", label = "A" }, { id = "a", label = "B" } },
					},
					{
						"Alert accepts one cancel action",
						{ { id = "a", label = "A", role = "cancel" }, { id = "b", label = "B", role = "cancel" } },
					},
				} :: { { any } }
			do
				local failures = {}
				local presented = Compose.cell(true)
				local world = setup(function(UI)
					return UI.Alert("Broken")({ isPresented = presented, title = "T", actions = case[2] })
				end, {
					onError = function(failure)
						table.insert(failures, tostring(failure))
					end,
				})
				t.expect(#failures).toBe(1)
				t.expect(string.find(failures[1], case[1], 1, true) ~= nil).toBe(true)
				t.expect(presented:peek()).toBe(false)
				t.expect(find(world.screen, "AlertPanel")).toBeNil()
				world.stop()
			end
		end
	)

	t.it("lays out alert actions in a row with the cancel action first and stacks them for long labels", function()
		local presented = Compose.cell(true)
		local world = setup(function(UI)
			return UI.Alert({
				isPresented = presented,
				title = "Leave?",
				message = "Progress is saved.",
				actions = {
					{ id = "Cancel", label = "Cancel", role = "cancel" },
					{ id = "Accept", label = "Accept" },
				},
			})
		end)
		local Enum = world.engine.types.Enum
		local modal = find(world.screen, "AlertModal")
		local actions = find(world.screen, "Actions")
		local layout = actions:FindFirstChildWhichIsA("UIListLayout")
		local cancel, accept = find(actions, "Cancel"), find(actions, "Accept")
		modal.AbsoluteSize = V2(world, 1280, 800)
		t.expect(layout.FillDirection).toBe(Enum.FillDirection.Horizontal)
		t.expect(cancel.LayoutOrder < accept.LayoutOrder).toBe(true)
		local constraint = find(world.screen, "AlertPanel"):FindFirstChildWhichIsA("UISizeConstraint")
		t.expect(constraint.MaxSize.X).toBe(440)
		world.gui.SelectedObject = cancel
		modal.AbsoluteSize = V2(world, 360, 640)
		t.expect(layout.FillDirection).toBe(Enum.FillDirection.Vertical)
		t.expect(find(actions, "Cancel")).toBe(cancel)
		t.expect(find(actions, "Accept")).toBe(accept)
		t.expect(world.gui.SelectedObject).toBe(cancel)
		t.expect(cancel.LayoutOrder > accept.LayoutOrder).toBe(true)
		t.expect(cancel.Size).toBe(world.engine.types.UDim2.new(1, 0, 0, 44))
		modal.AbsoluteSize = V2(world, 900, 700)
		t.expect(layout.FillDirection).toBe(Enum.FillDirection.Horizontal)
		t.expect(cancel.LayoutOrder).toBe(0)
		for _, button in { cancel, accept } do
			button.TextBounds = V2(world, 220, 20)
		end
		t.expect(layout.FillDirection).toBe(Enum.FillDirection.Vertical)
		for _, button in { cancel, accept } do
			button.TextBounds = V2(world, 60, 20)
		end
		t.expect(layout.FillDirection).toBe(Enum.FillDirection.Horizontal)
		t.expect(world.gui.SelectedObject).toBe(cancel)
		world.stop()
	end)

	t.it("grows an alert message to its content when the card has room and bounds it when it does not", function()
		local world = setup(function(UI)
			return UI.Alert({
				isPresented = Compose.cell(true),
				title = "Saved",
				message = "Short",
				actions = { { id = "OK", label = "OK" } },
			})
		end)
		find(world.screen, "AlertModal").AbsoluteSize = V2(world, 390, 844)
		find(world.screen, "Actions").AbsoluteSize = V2(world, 320, 44)
		local content = find(world.screen, "AlertContent")
		local scroll = find(world.screen, "AlertMessage")
		t.expect(find(scroll, "UIListLayout") ~= nil).toBe(true)
		content.AbsoluteSize = V2(world, 320, 120)
		t.expect(scroll.Size.Y.Offset).toBe(120)
		content.AbsoluteSize = V2(world, 320, 2000)
		t.expect(scroll.Size.Y.Offset).toBe(844 - 44 - 40 - 40)
		world.stop()
	end)

	t.it("mounts an alert title only while it has visible text and wraps a long title across the card", function()
		local title = Compose.cell(" ")
		local world = setup(function(UI)
			return UI.Alert({ isPresented = Compose.cell(true), title = title, message = "Body" })
		end)
		t.expect(find(world.screen, "Title")).toBeNil()
		t.expect(find(world.screen, "Message") ~= nil).toBe(true)
		title:set("Hi")
		t.expect(find(world.screen, "Title").Text).toBe("Hi")
		title:set("")
		t.expect(find(world.screen, "Title")).toBeNil()
		title:set(string.rep("A very long title ", 12))
		local heading = find(world.screen, "Title")
		t.expect(heading.TextWrapped).toBe(true)
		t.expect(heading.Size.X.Scale).toBe(1)
		t.expect(heading:HasTag("facet-type-heading")).toBe(true)
		world.stop()
	end)

	t.it("releases an open alert with its owner and returns selection to the opener", function()
		local show = Compose.cell(false)
		local world = setup(function(UI, Host)
			return Host.Frame({
				UI.Button("Opener")({ label = "Open" }),
				Compose.show(show, function()
					return UI.Alert({
						isPresented = Compose.cell(true),
						title = "Leave?",
						actions = { { id = "Stay", label = "Stay", role = "cancel" } },
					})
				end),
			})
		end)
		world.gui.SelectedObject = find(world.screen, "Opener")
		local baseline = world.engine.census()
		for _ = 1, 5 do
			show:set(true)
			t.expect(world.gui.SelectedObject.Name).toBe("Stay")
			show:set(false)
			t.expect(world.gui.SelectedObject.Name).toBe("Opener")
		end
		t.expect(find(world.screen, "AlertModal")).toBeNil()
		t.expect(#contexts(world.screen, "ModalBack")).toBe(0)
		local after = world.engine.census()
		t.expect(after.live).toBe(baseline.live)
		t.expect(after.connections).toBe(baseline.connections)
		world.stop()
	end)
	t.it(
		"opens each menu scenario card only through its printed routes and runs nothing from the blocked card",
		function()
			local engine: any = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local gui = engine.new("GuiService")
			local input = engine.new("UserInputService")
			input.GetFocusedTextBox = function()
				return nil
			end
			local target = engine.new("Folder")
			local ctx = {
				Facet = Facet,
				Compose = Compose,
				runtime = runtime,
				Host = runtime.constructors,
				types = engine.types,
				viewport = Compose.cell({ width = 1280, height = 720 }),
				inputTarget = target,
				guiService = gui,
				runService = { Heartbeat = engine.heartbeat },
				UI = Facet.controls(
					runtime,
					{
						types = engine.types,
						guiService = gui,
						services = { GuiService = gui, UserInputService = input },
						reducedMotion = true,
					} :: any
				),
			}
			local scenario = require("../examples/gallery/scenarios/menu")
			local built
			local stop, screen = runtime.mount(function()
				built = scenario.build(ctx)
				return ctx.Host.ScreenGui({ built.screen() })
			end, target)
			local Enum = engine.types.Enum
			local function trigger(card: string): any
				return find(find(screen, "Card" .. card), "Trigger")
			end
			local function close()
				local back = action(screen, "ModalBack")
				if back then
					back.Pressed.fire()
				end
			end
			for _, card in { "Tap", "Chord", "Secondary", "Hold", "Blocked" } do
				local node = trigger(card)
				t.expect(node.ClassName).toBe("TextButton")
				t.expect(node.Selectable).toBe(true)
				t.expect(node.Size.Y.Offset >= 44).toBe(true)
			end
			trigger("Tap").Activated.fire()
			t.expect(built.report().counts.Tap).toBe(1)
			close()
			trigger("Chord").Activated.fire()
			t.expect(find(screen, "MenuPanel")).toBeNil()
			trigger("Chord").InputBegan.fire({ UserInputType = Enum.UserInputType.MouseButton2 })
			t.expect(built.report().counts.Chord).toBeNil()
			gui.SelectedObject = trigger("Chord")
			action(screen, "Menu").Pressed.fire()
			t.expect(built.report().counts.Chord).toBe(1)
			close()
			trigger("Secondary").Activated.fire()
			t.expect(built.report().counts.Secondary).toBeNil()
			trigger("Secondary").InputBegan.fire({ UserInputType = Enum.UserInputType.MouseButton2 })
			t.expect(built.report().counts.Secondary).toBe(1)
			close()
			trigger("Hold").TouchLongPress.fire({}, Enum.UserInputState.Begin)
			t.expect(built.report().counts.Hold).toBe(1)
			close()
			t.expect(built.report().counts.Tap).toBe(1)
			local ran = built.report().ran
			trigger("Blocked").Activated.fire()
			local panel = find(screen, "MenuPanel")
			t.expect(panel ~= nil).toBe(true)
			for _, id in { "save", "share", "delete" } do
				local row = find(panel, id)
				t.expect(row.Interactable).toBe(false)
				row.Activated.fire()
			end
			t.expect(built.report().ran).toBe(ran)
			t.expect(find(screen, "MenuPanel")).toBe(panel)
			close()
			local copy = {}
			for _, value in scenario.copy do
				table.insert(copy, value)
			end
			for _, node in screen:GetDescendants() do
				if (node:IsA("TextLabel") or node:IsA("TextButton")) and node.Text ~= "" then
					local covered = false
					for _, value in copy do
						if string.find(node.Text, value, 1, true) then
							covered = true
							break
						end
					end
					t.expect(covered).toBe(true)
				end
			end
			stop()
			runtime:dispose()
		end
	)

	t.it("keeps the callout scenario reset chip on screen at the 44 pixel floor and resets the session", function()
		local engine: any = engineLib.new()
		local runtime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local target = engine.new("Folder")
		local ctx = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = runtime.constructors,
			types = engine.types,
			viewport = Compose.cell({ width = 1280, height = 720 }),
			inputTarget = target,
			guiService = gui,
			runService = { Heartbeat = engine.heartbeat },
			UI = Facet.controls(
				runtime,
				{
					types = engine.types,
					guiService = gui,
					services = { GuiService = gui },
					reducedMotion = true,
				} :: any
			),
		}
		local built
		local stop, screen = runtime.mount(function()
			built = require("../examples/gallery/scenarios/callout").build(ctx)
			return ctx.Host.ScreenGui({ built.screen() })
		end, target)
		local initial = built.report().tip.state
		find(screen, "Show").Activated.fire()
		t.expect(built.report().tip.state ~= initial).toBe(true)
		local reset = find(screen, "Reset")
		t.expect(reset.Visible).toBe(true)
		t.expect(reset.Size.Y.Offset >= 44).toBe(true)
		reset.Activated.fire()
		t.expect(built.report().tip.state).toBe(initial)
		stop()
		runtime:dispose()
	end)
end)
