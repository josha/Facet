--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type SheetDetent = typeof(require("@repo/tools/typecheck/aliases").SheetDetent)
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local FixtureCollectionTypes = require("../src/ui/collection_types")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local materialize = require("./lib/materialize")
	local fs = require("@lune/fs")
	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local Compose: ComposeModule = Facet.Compose

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
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
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
		local Host = (runtime.constructors :: unknown) :: RobloxHost
		local stop, screen: any = runtime.mount(function()
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
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui = engine.new("GuiService")
		local UI =
			Facet.controls(runtime, { types = engine.types, guiService = gui, services = { GuiService = gui } } :: any)
		local Host = (runtime.constructors :: unknown) :: RobloxHost
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
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
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
			Host = (runtime.constructors :: unknown) :: RobloxHost,
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
					motionLevel = "none",
				} :: any
			),
		}
		local built
		local stop, screen: any = runtime.mount(function()
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

	local function page(
		Host: any,
		name: string,
		builds: { [string]: number }?,
		cleanups: { [string]: number }?
	): () -> any
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

	verifyHarness:suite("native parity navigation", function()
		verifyHarness:case(
			"pages tabs with the shoulders from the strip, wraps there and clamps when paging from content",
			{
				id = "native_parity_navigation::native parity navigation::pages tabs with the shoulders from the strip, wraps there and clamps when paging from content",
				run = function()
					for _, mode in { "strip", "content" } :: { "content" | "strip" } do
						local selection = Compose.cell("a")
						local world = setup(function(UI: FacetControls, Host: RobloxHost)
							return UI.TabView({
								selection = selection,
								shoulderNavigation = if mode == "content" then "content" :: "content" else nil,
								tabs = {
									{
										id = "a",
										label = "A",
										content = function(): Instance
											return Host.Frame({
												UI.Button("Play")({ label = "Play" }) :: unknown,
												UI.Slider("Volume")({ value = Compose.cell(0.5) }),
											})
										end,
									} :: FixtureNavigationTypes.Tab,
									{ id = "b", label = "B", content = page(Host, "b") } :: FixtureNavigationTypes.Tab,
									{ id = "c", label = "C", content = page(Host, "c") } :: FixtureNavigationTypes.Tab,
								},
							})
						end)
						local tabs = find(world.screen, "Tabs")
						world.gui.SelectedObject = find(world.screen, "Play")
						if mode == "strip" then
							Verify.expect((action(world.screen, "NextTab"))):toBeNil()
							world.gui.SelectedObject = find(tabs, "a")
							local next, previous = action(world.screen, "NextTab"), action(world.screen, "PreviousTab")
							Verify.expect(next:FindFirstChildWhichIsA("InputBinding").KeyCode.Name):toBe("ButtonR1")
							Verify.expect(previous:FindFirstChildWhichIsA("InputBinding").KeyCode.Name):toBe("ButtonL1")
							next.Pressed:Fire()
							next.Pressed:Fire()
							Verify.expect((selection:peek())):toBe("c")
							next.Pressed:Fire()
							Verify.expect((selection:peek())):toBe("a")
							previous.Pressed:Fire()
							Verify.expect((selection:peek())):toBe("c")
						else
							local next = action(world.screen, "NextTab")
							next.Pressed:Fire()
							Verify.expect((selection:peek())):toBe("b")
							next.Pressed:Fire()
							next.Pressed:Fire()
							Verify.expect((selection:peek())):toBe("c")
							action(world.screen, "PreviousTab").Pressed:Fire()
							Verify.expect((selection:peek())):toBe("b")
							selection:set("a")
							world.gui.SelectedObject = find(world.screen, "Volume")
							local increase = action(world.screen, "Increase")
							Verify.expect(increase.Parent.Priority > action(world.screen, "NextTab").Parent.Priority)
								:toBe(true)
						end
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"pages the inner tab view from nested content, clamps at its boundary and leaves the outer tabs",
			{
				id = "native_parity_navigation::native parity navigation::pages the inner tab view from nested content, clamps at its boundary and leaves the outer tabs",
				run = function()
					local outer, inner = Compose.cell("a"), Compose.cell("one")
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return UI.TabView({
							selection = outer,
							shoulderNavigation = "content" :: "content",
							tabs = {
								{
									id = "a",
									label = "A",
									content = function(): Instance
										return UI.TabView("Inner")({
											selection = inner,
											shoulderNavigation = "content" :: "content",
											tabs = {
												{
													id = "one",
													label = "One",
													content = function(): Instance
														return UI.Button("Deep")({ label = "Deep" })
													end,
												} :: FixtureNavigationTypes.Tab,
												{ id = "two", label = "Two", content = page(Host, "two") } :: FixtureNavigationTypes.Tab,
											},
										})
									end,
								} :: FixtureNavigationTypes.Tab,
								{ id = "b", label = "B", content = page(Host, "b") } :: FixtureNavigationTypes.Tab,
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
					Verify.expect(#enabled):toBe(2)
					Verify.expect(enabled[1].Priority > enabled[2].Priority):toBe(true)
					enabled[1]:FindFirstChild("NextTab").Pressed:Fire()
					enabled[1]:FindFirstChild("NextTab").Pressed:Fire()
					Verify.expect((inner:peek())):toBe("two")
					Verify.expect((outer:peek())):toBe("a")
					world.stop()
				end,
			}
		)

		verifyHarness:case("builds only visited tabs and disposes departing pages under top retention", {
			id = "native_parity_navigation::native parity navigation::builds only visited tabs and disposes departing pages under top retention",
			run = function()
				local builds, cleanups = {}, {}
				local selection = Compose.cell("home")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = selection,
						retention = "top" :: "top",
						transition = false :: false,
						tabs = {
							{ id = "home", label = "Home", content = page(Host, "home", builds, cleanups) } :: FixtureNavigationTypes.Tab,
							{ id = "feed", label = "Feed", content = page(Host, "feed", builds, cleanups) } :: FixtureNavigationTypes.Tab,
							{ id = "more", label = "More", content = page(Host, "more", builds, cleanups) } :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				Verify.expect(builds):toEqual({ home = 1 })
				Verify.expect((find(world.screen, "feedBody"))):toBeNil()
				selection:set("feed")
				Verify.expect(builds):toEqual({ home = 1, feed = 1 })
				Verify.expect(cleanups):toEqual({ home = 1 })
				Verify.expect((find(world.screen, "homeBody"))):toBeNil()
				selection:set("home")
				Verify.expect(builds.home):toBe(2)
				Verify.expect(cleanups.feed):toBe(1)
				local baseline = world.engine.census()
				for _ = 1, 20 do
					selection:set("feed")
					selection:set("home")
				end
				local after = world.engine.census()
				Verify.expect(after.live):toBe(baseline.live)
				Verify.expect(after.connections):toBe(baseline.connections)
				Verify.expect(builds.home):toBe(22)
				Verify.expect(builds.more):toBeNil()
				world.stop()
			end,
		})

		verifyHarness:case("resolves a nested tab view to a top band and keeps nesting balanced after a failed page", {
			id = "native_parity_navigation::native parity navigation::resolves a nested tab view to a top band and keeps nesting balanced after a failed page",
			run = function()
				local fresh = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.TabView("Outer")({
							selection = Compose.cell("a"),
							tabs = {
								{
									id = "a",
									label = "A",
									content = function(): Instance
										return UI.TabView("Inner")({
											selection = Compose.cell("x"),
											tabs = {
												{ id = "x", label = "X", content = page(Host, "x") } :: FixtureNavigationTypes.Tab,
												{ id = "y", label = "Y", content = page(Host, "y") } :: FixtureNavigationTypes.Tab,
											},
										})
									end,
								} :: FixtureNavigationTypes.Tab,
							},
						}) :: unknown,
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
									} :: FixtureNavigationTypes.Tab,
								},
							})
						end, function()
							return Host.Folder("Failed")({})
						end),
						Compose.show(fresh, function()
							return UI.TabView("Fresh")({
								selection = Compose.cell("a"),
								tabs = {
									{ id = "a", label = "A", content = page(Host, "fresh") } :: FixtureNavigationTypes.Tab,
								},
							})
						end),
					})
				end)
				local outerView, innerView = find(world.screen, "Outer"), find(world.screen, "Inner")
				outerView.AbsoluteSize = V2(world, 1200, 800)
				innerView.AbsoluteSize = V2(world, 900, 700)
				local Enum = world.engine.types.Enum
				Verify.expect(outerView:FindFirstChild("Tabs"):FindFirstChildWhichIsA("UIListLayout").FillDirection)
					:toBe(Enum.FillDirection.Vertical)
				local innerTabs = innerView:FindFirstChild("Tabs")
				Verify.expect(innerTabs.Position):toBe(world.engine.types.UDim2.fromOffset(0, 0))
				Verify.expect(innerTabs:FindFirstChildWhichIsA("UIListLayout").FillDirection)
					:toBe(Enum.FillDirection.Horizontal)
				Verify.expect(find(world.screen, "Failed") ~= nil):toBe(true)
				fresh:set(true)
				local freshView = find(world.screen, "Fresh")
				freshView.AbsoluteSize = V2(world, 400, 800)
				Verify.expect(freshView:FindFirstChild("Tabs").Position.Y.Scale):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case(
			"places sidebar head and foot accessories around the strip and passes the placement to builders",
			{
				id = "native_parity_navigation::native parity navigation::places sidebar head and foot accessories around the strip and passes the placement to builders",
				run = function()
					local placements: { FixtureNavigationTypes.Placement } = {}
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						local function builder(name: string)
							return function(placement: FixtureNavigationTypes.Placement): Instance
								table.insert(placements, placement)
								return Host.Frame(name)({})
							end
						end
						return UI.TabView({
							selection = Compose.cell("a"),
							placement = "sidebar" :: "sidebar",
							accessories = { head = builder("Head"), foot = builder("Foot") },
							tabs = {
								{ id = "a", label = "A", content = page(Host, "a") } :: FixtureNavigationTypes.Tab,
							},
						})
					end)
					local view = find(world.screen, "TabView")
					view.AbsoluteSize = V2(world, 1200, 800)
					find(world.screen, "Accessory-head").AbsoluteSize = V2(world, 240, 52)
					find(world.screen, "Accessory-foot").AbsoluteSize = V2(world, 240, 60)
					local UDim2 = world.engine.types.UDim2
					local tabs = view:FindFirstChild("Tabs")
					Verify.expect(tabs.Size):toBe(UDim2.new(0, 240 - 16, 1, -112))
					Verify.expect(tabs.Position):toBe(UDim2.fromOffset(8, 52))
					Verify.expect(find(world.screen, "Accessory-head").Position):toBe(UDim2.fromOffset(0, 0))
					Verify.expect(find(world.screen, "Accessory-foot").Position):toBe(UDim2.new(0, 0, 1, -60))
					table.sort(placements)
					Verify.expect(placements):toEqual({ "sidebar", "sidebar" })
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"docks trailing and above-bar accessories against the band and re-homes them with the placement",
			{
				id = "native_parity_navigation::native parity navigation::docks trailing and above-bar accessories against the band and re-homes them with the placement",
				run = function()
					local placement = Compose.cell(
						"topBar" :: "automatic" | "bottomBar" | "bottomBarCompact" | "none" | "sidebar" | "topBar"
					)
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return UI.TabView({
							selection = Compose.cell("a"),
							placement = placement,
							accessories = {
								trailing = function(): Instance?
									return Host.Frame("Search")({})
								end,
							},
							tabs = {
								{ id = "a", label = "A", content = page(Host, "a") } :: FixtureNavigationTypes.Tab,
							},
						})
					end)
					local UDim2 = world.engine.types.UDim2
					local view = find(world.screen, "TabView")
					view.AbsoluteSize = V2(world, 900, 700)
					find(world.screen, "Accessory-trailing").AbsoluteSize = V2(world, 120, 44)
					Verify.expect(view:FindFirstChild("Tabs").Size):toBe(UDim2.new(1, -120, 0, 44))
					Verify.expect(find(world.screen, "Accessory-trailing").Position):toBe(UDim2.new(1, -120, 0, 0))
					placement:set("bottomBar")
					find(world.screen, "Accessory-trailing").AbsoluteSize = V2(world, 120, 44)
					Verify.expect(find(world.screen, "Accessory-trailing").Position):toBe(UDim2.new(1, -120, 1, -44))
					Verify.expect(view:FindFirstChild("Tabs").Position):toBe(UDim2.new(0, 0, 1, -44))
					world.stop()
					local calls = {}
					local docked = setup(function(UI: FacetControls, Host: RobloxHost)
						return UI.TabView({
							selection = Compose.cell("a"),
							accessories = {
								aboveBar = function(where): Instance?
									table.insert(calls, where)
									return if where == "bottomBarCompact" then nil else Host.Frame("NowPlaying")({})
								end,
							},
							tabs = {
								{ id = "a", label = "A", content = page(Host, "a") } :: FixtureNavigationTypes.Tab,
							},
						})
					end)
					local root = find(docked.screen, "TabView")
					root.AbsoluteSize = V2(docked, 400, 800)
					local dock = find(docked.screen, "Accessory-aboveBar")
					dock.AbsoluteSize = V2(docked, 400, 56)
					Verify.expect(dock.Position):toBe(UDim2.new(0, 0, 1, -100))
					Verify.expect(dock.Position.Y.Offset + 56):toBe(root:FindFirstChild("Tabs").Position.Y.Offset)
					Verify.expect(root:FindFirstChild("Content").Size):toBe(UDim2.new(1, 0, 1, -108))
					root.AbsoluteSize = V2(docked, 800, 400)
					Verify.expect((find(docked.screen, "Accessory-aboveBar"))):toBeNil()
					Verify.expect(root:FindFirstChild("Content").Size):toBe(UDim2.new(1, 0, 1, -52))
					Verify.expect(calls):toEqual({ "bottomBar", "bottomBarCompact" })
					docked.stop()
				end,
			}
		)

		verifyHarness:case(
			"refuses unknown accessory slots, non-function builders, unhostable slots and malformed transitions",
			{
				id = "native_parity_navigation::native parity navigation::refuses unknown accessory slots, non-function builders, unhostable slots and malformed transitions",
				run = function()
					local function view(extra)
						return function(UI: FacetControls, Host: RobloxHost)
							local spec: { [any]: any } = {
								selection = Compose.cell("a"),
								tabs = {
									{ id = "a", label = "A", content = page(Host, "a") } :: FixtureNavigationTypes.Tab,
								},
							}
							for field, value in extra do
								spec[field] = value
							end
							return UI.TabView(spec)
						end
					end
					local slots = "TabView accessories require head, foot, trailing or aboveBar builders"
					Verify.expect((refuses(slots, view({ accessories = { leading = function() end } })))):toBe(true)
					Verify.expect((refuses(slots, view({ accessories = { head = {} } })))):toBe(true)
					Verify.expect((refuses(
						"TabView accessory is unavailable in this placement",
						view({
							placement = "bottomBar" :: "bottomBar",
							accessories = { head = function() end },
						})
					))):toBe(true)
					Verify.expect(
						(refuses("Navigation transition uses Compose tween options", view({ transition = "fade" })))
					)
						:toBe(true)
					Verify.expect((refuses("seconds, ease", view({ transition = { seconds = 0.2, fade = true } }))))
						:toBe(true)
					Verify.expect((mountError(view({ transition = { seconds = 0.2 } })))):toBeNil()
				end,
			}
		)

		verifyHarness:case("uses a plain native frame and hides the old page immediately when transition is false", {
			id = "native_parity_navigation::native parity navigation::uses a plain native frame and hides the old page immediately when transition is false",
			run = function()
				for _, declared in { "false" } do
					local selection = Compose.cell("a")
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return UI.TabView({
							selection = selection,
							transition = if declared == "false" then false :: false else nil,
							tabs = {
								{ id = "a", label = "A", content = page(Host, "a") } :: FixtureNavigationTypes.Tab,
								{ id = "b", label = "B", content = page(Host, "b") } :: FixtureNavigationTypes.Tab,
							},
						})
					end)
					local layer = find(world.screen, "aBody").Parent
					Verify.expect(layer.ClassName):toBe("Frame")
					selection:set("b")
					Verify.expect(layer.Visible):toBe(false)
					Verify.expect(find(world.screen, "bBody").Parent.ClassName):toBe("Frame")
					Verify.expect((engineLib.connections(world.engine.heartbeat))):toBe(0)
					world.stop()
				end
			end,
		})

		verifyHarness:case("labels tabs by id, keeps icon-only names accessible and badges unselected tabs in place", {
			id = "native_parity_navigation::native parity navigation::labels tabs by id, keeps icon-only names accessible and badges unselected tabs in place",
			run = function()
				local badge, iconOnly = Compose.cell(nil :: number?), Compose.cell(false)
				local selection = Compose.cell("home")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = selection,
						iconOnly = iconOnly,
						tabs = {
							{ id = "home", content = page(Host, "home") } :: FixtureNavigationTypes.Tab,
							{
								id = "feed",
								label = "Feed",
								icon = "checkmark",
								badge = badge,
								content = page(Host, "feed"),
							} :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				local tabs = find(world.screen, "Tabs")
				local home, feed = find(tabs, "home"), find(tabs, "feed")
				Verify.expect(home.Text):toBe("home")
				Verify.expect((home:GetAttribute("FacetLabel"))):toBe("home")
				badge:set(12)
				Verify.expect((feed:GetAttribute("FacetLabel"))):toBe("Feed")
				local label = feed:FindFirstChild("Title", true)
				local function shown()
					return if label then label.Text else feed.Text
				end
				Verify.expect((shown())):toBe("Feed")
				local seal = feed:FindFirstChild("CornerBadge", true)
				Verify.expect(seal ~= nil and seal.Text == "12"):toBe(true)
				for _ = 1, 3 do
					selection:set("feed")
					selection:set("home")
				end
				Verify.expect((find(tabs, "feed"))):toBe(feed)
				Verify.expect((shown())):toBe("Feed")
				Verify.expect((feed:FindFirstChild("CornerBadge", true))):toBe(seal)
				iconOnly:set(true)
				Verify.expect((shown())):toBe("")
				Verify.expect((feed:GetAttribute("FacetLabel"))):toBe("Feed")
				world.stop()
			end,
		})
		verifyHarness:case("keeps a labelled tab's icon badge clear of its title under any UIScale", {
			id = "native_parity_navigation::native parity navigation::keeps a labelled tab's icon badge clear of its title under any UIScale",
			run = function()
				local badge, iconOnly = Compose.cell(12 :: number?), Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = Compose.cell("home"),
						iconOnly = iconOnly,
						tabs = {
							{ id = "home", content = page(Host, "home") } :: FixtureNavigationTypes.Tab,
							{
								id = "feed",
								label = "Feed",
								icon = "checkmark",
								badge = badge,
								content = page(Host, "feed"),
							} :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				local feed = find(find(world.screen, "Tabs"), "feed")
				local glyph = feed:FindFirstChild("LeadingIcon", true)
				local layout = glyph.Parent:FindFirstChildWhichIsA("UIListLayout")
				local gap = layout.Padding.Offset
				local scale = 1.2047
				glyph.AbsoluteSize =
					world.engine.types.Vector2.new(glyph.Size.X.Offset * scale, glyph.Size.Y.Offset * scale)
				local seal = feed:FindFirstChild("CornerBadge", true)
				seal.AbsoluteSize = world.engine.types.Vector2.new(23.5 * scale, 24 * scale)
				Verify.expect(layout.Padding.Offset >= 23.5 / 2 + 2):toBe(true)
				local wrapper = feed:FindFirstChild("Anchor+badge", true)
				local side = glyph.Size.X.Offset
				Verify.expect(wrapper.Size.X.Offset):toBe(math.round(math.max(0, 23.5 / 2 - side / 4)))
				Verify.expect(wrapper.Position.Y.Offset):toBe(-math.round(math.max(0, 24 / 2 - side / 4)))
				badge:set(nil)
				Verify.expect(layout.Padding.Offset):toBe(gap)
				badge:set(3)
				feed:FindFirstChild("CornerBadge", true).AbsoluteSize = seal.AbsoluteSize
				iconOnly:set(true)
				Verify.expect(layout.Padding.Offset):toBe(gap)
				world.stop()
			end,
		})
		verifyHarness:case(
			"underlines the selected top tab by default, fills bottom and sidebar tabs and follows the indicator",
			{
				id = "native_parity_navigation::native parity navigation::underlines the selected top tab by default, fills bottom and sidebar tabs and follows the indicator",
				run = function()
					local indicator, placement =
						Compose.cell(nil :: FixtureNavigationTypes.Indicator?),
						Compose.cell(
							"topBar" :: "automatic" | "bottomBar" | "bottomBarCompact" | "none" | "sidebar" | "topBar"
						)
					local selection = Compose.cell("a")
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return UI.TabView({
							selection = selection,
							indicator = indicator,
							placement = placement,
							tabs = {
								{ id = "a", label = "A", content = page(Host, "a") } :: FixtureNavigationTypes.Tab,
								{ id = "b", label = "B", content = page(Host, "b") } :: FixtureNavigationTypes.Tab,
							},
						})
					end)
					local tabs = find(world.screen, "Tabs")
					local a, b = find(tabs, "a"), find(tabs, "b")
					Verify.expect(a:FindFirstChild("SelectionIndicator") ~= nil):toBe(true)
					Verify.expect((b:FindFirstChild("SelectionIndicator"))):toBeNil()
					Verify.expect((a:HasTag("facet-tab-current"))):toBe(true)
					Verify.expect((a:HasTag("facet-tab-filled"))):toBe(false)
					selection:set("b")
					Verify.expect((a:FindFirstChild("SelectionIndicator"))):toBeNil()
					Verify.expect(b:FindFirstChild("SelectionIndicator") ~= nil):toBe(true)
					indicator:set("pill")
					Verify.expect((b:FindFirstChild("SelectionIndicator"))):toBeNil()
					Verify.expect((b:HasTag("facet-selected"))):toBe(true)
					Verify.expect((a:HasTag("facet-selected"))):toBe(false)
					indicator:set("none")
					Verify.expect((b:FindFirstChild("SelectionIndicator"))):toBeNil()
					Verify.expect((b:HasTag("facet-selected"))):toBe(false)
					Verify.expect((b:HasTag("facet-tab-current"))):toBe(true)
					indicator:set(nil)
					for _, where in { "bottomBar", "sidebar" } :: { FixtureNavigationTypes.Placement } do
						placement:set(where :: FixtureNavigationTypes.Placement)
						Verify.expect((b:HasTag("facet-tab-filled"))):toBe(true)
						Verify.expect((a:HasTag("facet-tab-filled"))):toBe(false)
						Verify.expect((b:FindFirstChild("SelectionIndicator"))):toBeNil()
					end
					world.stop()
				end,
			}
		)

		verifyHarness:case("keeps every tab at the 44 pixel target floor and reads a bound text size and rail width", {
			id = "native_parity_navigation::native parity navigation::keeps every tab at the 44 pixel target floor and reads a bound text size and rail width",
			run = function()
				local textSize, railWidth, placement =
					Compose.cell(16),
					Compose.cell(nil :: number?),
					Compose.cell(
						"sidebar" :: "automatic" | "bottomBar" | "bottomBarCompact" | "none" | "sidebar" | "topBar"
					)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.TabView({
							selection = Compose.cell("a"),
							placement = placement,
							textSize = textSize,
							railWidth = railWidth,
							tabs = {
								{ id = "a", label = "A", content = page(Host, "a") } :: FixtureNavigationTypes.Tab,
								{ id = "b", label = "B", content = page(Host, "b") } :: FixtureNavigationTypes.Tab,
							},
						}) :: unknown,
						UI.TabView("Plain")({
							selection = Compose.cell("p"),
							tabs = {
								{ id = "p", label = "P", content = page(Host, "p") } :: FixtureNavigationTypes.Tab,
							},
						}),
						UI.Button("Reference")({ label = "Reference" }),
					})
				end)
				local view = find(world.screen, "TabView")
				view.AbsoluteSize = V2(world, 1200, 800)
				local tabs = view:FindFirstChild("Tabs")
				local content = view:FindFirstChild("Content")
				for _, where in { "sidebar", "bottomBar", "topBar" } :: { FixtureNavigationTypes.Placement } do
					placement:set(where :: FixtureNavigationTypes.Placement)
					for _, id in { "a", "b" } do
						local button = find(tabs, id)
						Verify.expect(button:FindFirstChildWhichIsA("UISizeConstraint").MinSize):toBe(V2(world, 44, 44))
						Verify.expect(button.Size.Y.Offset):toBe(44)
					end
				end
				placement:set("sidebar")
				Verify.expect(tabs.Size.X.Offset):toBe(240 - 16)
				Verify.expect(tabs.Position.X.Offset):toBe(8)
				Verify.expect(content.Position.X.Offset):toBe(240)
				railWidth:set(260)
				Verify.expect(tabs.Size.X.Offset):toBe(260 - 16)
				Verify.expect(content.Position.X.Offset):toBe(260)
				view.AbsoluteSize = V2(world, 2000, 800)
				railWidth:set(nil)
				Verify.expect(tabs.Size.X.Offset):toBe(280 - 16)
				Verify.expect(find(tabs, "a").TextSize):toBe(16)
				textSize:set(22)
				Verify.expect(find(tabs, "a").TextSize):toBe(22)
				Verify.expect(find(tabs, "b").TextSize):toBe(22)
				Verify.expect(find(find(find(world.screen, "Plain"), "Tabs"), "p").TextSize)
					:toBe(find(world.screen, "Reference").TextSize)
				world.stop()
			end,
		})

		verifyHarness:case("reveals an offscreen selected tab once and never scrolls for a visible one", {
			id = "native_parity_navigation::native parity navigation::reveals an offscreen selected tab once and never scrolls for a visible one",
			run = function()
				local selection = Compose.cell("a")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local list = {}
					for _, id in { "a", "b", "c", "d", "e" } do
						table.insert(list, { id = id, label = string.upper(id), content = page(Host, id) })
					end
					return UI.TabView({ selection = selection, placement = "topBar" :: "topBar", tabs = list })
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
				Verify.expect(writes):toBe(0)
				Verify.expect(tabs.CanvasPosition.X):toBe(0)
				selection:set("e")
				Verify.expect(writes):toBe(1)
				Verify.expect(tabs.CanvasPosition.X):toBe(100)
				for index, id in { "a", "b", "c", "d", "e" } do
					find(tabs, id).AbsolutePosition = V2(world, (index - 1) * 80 - 100, 0)
				end
				tabs.CanvasPosition = V2(world, 0, 0)
				for index, id in { "a", "b", "c", "d", "e" } do
					find(tabs, id).AbsolutePosition = V2(world, (index - 1) * 80, 0)
				end
				Verify.expect(tabs.CanvasPosition.X):toBe(0)
				Verify.expect(writes):toBe(2)
				find(tabs, "e").AbsoluteSize = V2(world, 120, 44)
				Verify.expect(tabs.CanvasPosition.X):toBe(140)
				world.stop()
			end,
		})

		verifyHarness:case("keeps the strip, the page and its owner across placement changes and round trips", {
			id = "native_parity_navigation::native parity navigation::keeps the strip, the page and its owner across placement changes and round trips",
			run = function()
				local builds, cleanups = {}, {}
				local preference = Compose.cell("sidebar" :: "automatic" | "sidebar" | "topBar")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = Compose.cell("a"),
						style = "sidebarAdaptable" :: "sidebarAdaptable",
						sidebarPreference = preference,
						tabs = {
							{ id = "a", label = "A", content = page(Host, "a", builds, cleanups) } :: FixtureNavigationTypes.Tab,
							{ id = "b", label = "B", content = page(Host, "b", builds, cleanups) } :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				local view = find(world.screen, "TabView")
				view.AbsoluteSize = V2(world, 1200, 800)
				local tabs, body = view:FindFirstChild("Tabs"), find(world.screen, "aBody")
				local layout = tabs:FindFirstChildWhichIsA("UIListLayout")
				Verify.expect(layout.FillDirection):toBe(world.engine.types.Enum.FillDirection.Vertical)

				local track = view:FindFirstChild("Track")
				Verify.expect(track.Visible and track:HasTag("facet-tab-plate")):toBe(true)
				Verify.expect((track:FindFirstChildWhichIsA("UIStroke"))):toBe(nil)
				Verify.expect((track:FindFirstChildWhichIsA("UICorner"))):toBe(nil)
				Verify.expect(track.Position):toBe(tabs.Position)
				preference:set("topBar")
				Verify.expect(layout.FillDirection):toBe(world.engine.types.Enum.FillDirection.Horizontal)
				Verify.expect(track.Visible):toBe(true)
				Verify.expect((find(tabs, "a"):HasTag("facet-tab-filled"))):toBe(true)
				preference:set("sidebar")
				local baseline = world.engine.census()
				for _ = 1, 12 do
					preference:set("topBar")
					preference:set("sidebar")
					view.AbsoluteSize = V2(world, 390, 844)
					view.AbsoluteSize = V2(world, 1200, 800)
				end
				Verify.expect((view:FindFirstChild("Tabs"))):toBe(tabs)
				Verify.expect((find(world.screen, "aBody"))):toBe(body)
				Verify.expect(builds):toEqual({ a = 1 })
				Verify.expect(cleanups):toEqual({})
				local after = world.engine.census()
				Verify.expect(after.live):toBe(baseline.live)
				Verify.expect(after.connections):toBe(baseline.connections)
				world.stop()
				Verify.expect(cleanups):toEqual({ a = 1 })
			end,
		})

		verifyHarness:case("moves adaptable tabs to a top band while a gamepad is the preferred input", {
			id = "native_parity_navigation::native parity navigation::moves adaptable tabs to a top band while a gamepad is the preferred input",
			run = function()
				local selection = Compose.cell("a")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = selection,
						style = "sidebarAdaptable" :: "sidebarAdaptable",
						accessories = {
							head = function(): Instance?
								return Host.Frame("Brand")({})
							end,
							trailing = function(): Instance?
								return Host.Frame("Search")({})
							end,
						},
						tabs = {
							{ id = "a", label = "A", content = page(Host, "a") } :: FixtureNavigationTypes.Tab,
							{ id = "b", label = "B", content = page(Host, "b") } :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				local view = find(world.screen, "TabView")
				view.AbsoluteSize = V2(world, 1280, 800)
				Verify.expect(find(world.screen, "Accessory-head") ~= nil):toBe(true)
				Verify.expect((find(world.screen, "Accessory-trailing"))):toBeNil()
				world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Gamepad
				Verify.expect((find(world.screen, "Accessory-head"))):toBeNil()
				Verify.expect(find(world.screen, "Accessory-trailing") ~= nil):toBe(true)
				local tabs = view:FindFirstChild("Tabs")
				local placed = tabs.Position
				Verify.expect(placed.Y.Offset):toBe(0)
				Verify.expect(view:FindFirstChild("Track").Visible):toBe(true)
				Verify.expect(find(tabs, "b").Visible):toBe(true)
				find(tabs, "b").Activated:Fire()
				Verify.expect((selection:peek())):toBe("b")
				Verify.expect(tabs.Position):toBe(placed)
				world.input.PreferredInput = world.engine.types.Enum.PreferredInput.KeyboardAndMouse
				Verify.expect(find(world.screen, "Accessory-head") ~= nil):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case(
			"orders customized tabs, skips stale ids, protects required tabs and falls back from a hidden selection",
			{
				id = "native_parity_navigation::native parity navigation::orders customized tabs, skips stale ids, protects required tabs and falls back from a hidden selection",
				run = function()
					local builds = {}
					local selection = Compose.cell("home")
					local customization = Compose.cell({
						order = { "gone", "gear", "home", "gear" },
						hidden = { "home", "settings" },
					} :: any)
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return UI.TabView({
							selection = selection,
							customization = customization,
							tabs = {
								{ id = "home", label = "Home", required = true, content = page(Host, "home", builds) } :: FixtureNavigationTypes.Tab,
								{ id = "gear", label = "Gear", content = page(Host, "gear", builds) } :: FixtureNavigationTypes.Tab,
								{ id = "settings", label = "Settings", content = page(Host, "settings", builds) } :: FixtureNavigationTypes.Tab,
							},
						})
					end)
					local tabs = find(world.screen, "Tabs")
					local gear, home = find(tabs, "gear"), find(tabs, "home")
					Verify.expect((find(tabs, "settings"))):toBeNil()
					Verify.expect(gear.LayoutOrder < home.LayoutOrder):toBe(true)
					customization:set({ order = { "home", "gear" } })
					Verify.expect((find(tabs, "home"))):toBe(home)
					Verify.expect((find(tabs, "gear"))):toBe(gear)
					Verify.expect(home.LayoutOrder < gear.LayoutOrder):toBe(true)
					Verify.expect(find(tabs, "settings") ~= nil):toBe(true)
					Verify.expect(builds):toEqual({ home = 1 })
					selection:set("gear")
					customization:set({ order = { "home", "gear" }, hidden = { "gear" } })
					Verify.expect((selection:peek())):toBe("home")
					Verify.expect((find(tabs, "gear"))):toBeNil()
					world.stop()
				end,
			}
		)

		verifyHarness:case("keeps a retained tab's scroll position on return and resets it when restoreScroll is off", {
			id = "native_parity_navigation::native parity navigation::keeps a retained tab's scroll position on return and resets it when restoreScroll is off",
			run = function()
				for _, restore in { true, false } do
					local selection = Compose.cell("a")
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return UI.TabView({
							selection = selection,
							restoreScroll = if restore then nil else false,
							tabs = {
								{
									id = "a",
									label = "A",
									content = function(): Instance
										return Host.ScrollingFrame("Inventory")({})
									end,
								} :: FixtureNavigationTypes.Tab,
								{ id = "b", label = "B", content = page(Host, "b") } :: FixtureNavigationTypes.Tab,
							},
						})
					end)
					local inventory = find(world.screen, "Inventory")
					inventory.CanvasPosition = V2(world, 0, 450)
					selection:set("b")
					selection:set("a")
					Verify.expect((find(world.screen, "Inventory"))):toBe(inventory)
					Verify.expect(inventory.CanvasPosition.Y):toBe(if restore then 450 else 0)
					world.stop()
				end
			end,
		})
		for _, case in
			{
				{ kind = "VirtualGrid", editing = false },
				{ kind = "Table", editing = false },
				{
					kind = "Table",
					editing = true,
				},
			}
		do
			local kind, editing = case.kind, case.editing
			verifyHarness:case(
				"restores " .. kind .. " keys across a retained tab switch with editing=" .. tostring(editing),
				{
					id = "native_parity_navigation::"
						.. "native parity navigation"
						.. "::"
						.. "restores "
						.. kind
						.. " keys across a retained tab switch with editing="
						.. tostring(editing),
					run = function()
						local data = {}
						for index = 1, 100 do
							data[index] = { id = tostring(index), label = "Item " .. index }
						end
						local rows, selection, edit: FixtureComposeTypes.Cell<boolean> =
							Compose.cell(data), Compose.cell("a"), Compose.cell(editing)
						local builds = 0
						local world = setup(function(UI: FacetControls, Host: RobloxHost)
							local function render(current: Readable<{ id: string, label: string }>): GuiObject
								builds += 1
								return Host.TextLabel({
									Name = "Label",
									Text = function(use: Use)
										return use(current).label
									end,
								})
							end
							return UI.TabView({
								selection = selection,
								placement = "topBar" :: "topBar",
								tabs = {
									{
										id = "a",
										label = "A",
										content = function(): Instance
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
													columns = {
														{ id = "label", label = "Item", render = render } :: FixtureCollectionTypes.TableColumn<any, any>,
													},
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
									} :: FixtureNavigationTypes.Tab,
									{ id = "b", label = "B", content = page(Host, "b") } :: FixtureNavigationTypes.Tab,
								},
							})
						end)
						local collection = find(world.screen, "Collection")
						local scroll = if kind == "Table" then collection:FindFirstChild("Body") else collection
						scroll.AbsoluteWindowSize = V2(world, 200, 300)
						scroll.CanvasPosition = V2(world, 0, 2050)
						selection:set("b")
						local shifted = table.clone(data)
						table.insert(shifted, 1, assert(table.remove(shifted)))
						if kind == "VirtualGrid" then
							table.insert(shifted, 1, assert(table.remove(shifted)))
						end
						rows:set(shifted)
						selection:set("a")
						Verify.expect((find(world.screen, "Collection"))):toBe(collection)
						Verify.expect(scroll.CanvasPosition.Y):toBe(2150)
						Verify.expect(builds < 100):toBe(true)
						selection:set("b")
						local shorter = {}
						for index = 1, 8 do
							shorter[index] = { id = "new-" .. index, label = "Replacement " .. index }
						end
						rows:set(shorter)
						selection:set("a")
						Verify.expect(scroll.CanvasPosition.Y):toBe(if kind == "VirtualGrid" then 100 else 500)
						selection:set("b")
						rows:set({})
						selection:set("a")
						Verify.expect(scroll.CanvasPosition.Y):toBe(0)
						edit:set(not editing)
						Verify.expect((find(world.screen, "Collection"))):toBe(collection)
						world.stop()
					end,
				}
			)
		end

		verifyHarness:case(
			"keeps both showcase tab levels at the 44 pixel floor, marks each selection and reveals once",
			{
				id = "native_parity_navigation::native parity navigation::keeps both showcase tab levels at the 44 pixel floor, marks each selection and reveals once",
				run = function()
					local engine, _, screen, built, stop = showcase()
					local Enum = engine.types.Enum
					local catalog = require("../examples/gallery/scenarios/all_controls")
					local categories = tabView(screen, "Categories")
					categories.AbsoluteSize = engine.types.Vector2.new(1280, 800)
					local outer = categories:FindFirstChild("Tabs")
					Verify.expect(outer:FindFirstChildWhichIsA("UIListLayout").FillDirection)
						:toBe(Enum.FillDirection.Vertical)
					local function floor(button: any)
						Verify.expect(button:IsA("TextButton") and button.Selectable and button.Visible):toBe(true)
						Verify.expect(button:FindFirstChildWhichIsA("UISizeConstraint").MinSize)
							:toBe(engine.types.Vector2.new(44, 44))
					end
					for _, group in catalog.groups do
						local button = find(outer, group.id)
						floor(button)
						button.Activated:Fire()
						Verify.expect(built.report().selected.Categories):toBe(group.id)
						for _, other in catalog.groups do
							local tab = find(outer, other.id)
							Verify.expect((tab:HasTag("facet-tab-current"))):toBe(other == group)
							Verify.expect((tab:HasTag("facet-tab-filled"))):toBe(other == group)
						end
						local inner = tabView(screen, group.id)
						local strip = inner:FindFirstChild("Tabs")
						Verify.expect(strip:FindFirstChildWhichIsA("UIListLayout").FillDirection)
							:toBe(Enum.FillDirection.Horizontal)
						for index, tab in group.tabs do
							local innerButton = find(strip, tab.id)
							floor(innerButton)
							Verify.expect(innerButton.Size.Y.Offset):toBe(44)
							Verify.expect(innerButton:FindFirstChild("SelectionIndicator") ~= nil):toBe(index == 1)
						end
					end
					find(outer, "actions").Activated:Fire()
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
					find(strip, "shortcuts").Activated:Fire()
					find(strip, "recipes").Activated:Fire()
					find(strip, "buttons").Activated:Fire()
					Verify.expect(writes):toBe(0)
					find(strip, "help").Activated:Fire()
					Verify.expect(built.report().active):toBe("help")
					Verify.expect(writes):toBe(1)
					Verify.expect(strip.CanvasPosition.X):toBe(500)
					for index, tab in catalog.groups[2].tabs do
						find(strip, tab.id).AbsolutePosition = engine.types.Vector2.new((index - 1) * 100 - 500, 0)
					end
					find(strip, "help").Activated:Fire()
					strip.AbsoluteSize = engine.types.Vector2.new(301, 44)
					Verify.expect(writes):toBe(1)
					stop()
				end,
			}
		)

		verifyHarness:case("climbs a badge on an unselected tab whose content was never built", {
			id = "native_parity_navigation::native parity navigation::climbs a badge on an unselected tab whose content was never built",
			run = function()
				local builds = {}
				local unread = Compose.cell(3)
				local selection = Compose.cell("home")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = selection,
						placement = "bottomBar" :: "bottomBar",
						tabs = {
							{ id = "home", label = "Home", content = page(Host, "home", builds) } :: FixtureNavigationTypes.Tab,
							{ id = "inbox", label = "Inbox", badge = unread, content = page(Host, "inbox", builds) } :: FixtureNavigationTypes.Tab,
							{ id = "me", label = "Me", content = page(Host, "me", builds) } :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				local inbox = find(find(world.screen, "Tabs"), "inbox")
				local function shown()
					local label = inbox:FindFirstChild("Title", true)
					local pill = inbox:FindFirstChild("Count", true)
					return `{if label then label.Text else inbox.Text} {if pill then pill.Text else ""}`
				end
				Verify.expect((shown())):toBe("Inbox 3")
				selection:set("me")
				unread:update(function(value)
					return value + 1
				end)
				unread:update(function(value)
					return value + 1
				end)
				Verify.expect(builds.inbox):toBeNil()
				Verify.expect((shown())):toBe("Inbox 5")
				Verify.expect((find(find(world.screen, "Tabs"), "inbox"))):toBe(inbox)
				selection:set("inbox")
				Verify.expect(builds.inbox):toBe(1)
				world.stop()
			end,
		})

		verifyHarness:case(
			"pages each showcase tab strip by shoulder, traps the alert and restores its launcher on Back",
			{
				id = "native_parity_navigation::native parity navigation::pages each showcase tab strip by shoulder, traps the alert and restores its launcher on Back",
				run = function()
					local _, gui, screen, built, stop = showcase()
					local categories = tabView(screen, "Categories")
					local outer = categories:FindFirstChild("Tabs")
					find(outer, "actions").Activated:Fire()
					local inner = tabView(screen, "actions"):FindFirstChild("Tabs")
					gui.SelectedObject = find(inner, "buttons")
					action(screen, "NextTab").Pressed:Fire()
					Verify.expect(built.report().selected.actions):toBe("shortcuts")
					Verify.expect(built.report().selected.Categories):toBe("actions")
					action(screen, "PreviousTab").Pressed:Fire()
					action(screen, "PreviousTab").Pressed:Fire()
					Verify.expect(built.report().selected.actions):toBe("buttons")
					gui.SelectedObject = find(outer, "actions")
					action(screen, "NextTab").Pressed:Fire()
					Verify.expect(built.report().selected.Categories):toBe("indicators")
					Verify.expect(built.report().selected.actions):toBe("buttons")
					action(screen, "PreviousTab").Pressed:Fire()
					Verify.expect(built.report().selected.Categories):toBe("actions")
					find(inner, "alerts").Activated:Fire()
					Verify.expect(built.report().active):toBe("alerts")
					local launcher = find(tabView(screen, "actions"):FindFirstChild("Content"), "Open")
					gui.SelectedObject = launcher
					launcher.Activated:Fire()
					Verify.expect(built.report().example.alert.presented):toBe(true)
					local modal = find(screen, "AlertModal")
					local panel = find(modal, "AlertPanel")
					Verify.expect(panel.SelectionGroup):toBe(true)
					for _, side in { "Up", "Down", "Left", "Right" } do
						Verify.expect(panel["SelectionBehavior" .. side].Name):toBe("Stop")
					end
					local held = gui.SelectedObject
					Verify.expect(held ~= nil and held:IsDescendantOf(panel)):toBe(true)
					Verify.expect((action(screen, "NextTab"))):toBeNil()
					gui.SelectedObject = find(inner, "alerts")
					Verify.expect((action(screen, "NextTab"))):toBeNil()
					Verify.expect((action(screen, "PreviousTab"))):toBeNil()
					gui.SelectedObject = find(outer, "actions")
					Verify.expect((action(screen, "NextTab"))):toBeNil()
					gui.SelectedObject = held
					local back = action(screen, "ModalBack")
					local keys = {}
					for _, binding in back:GetChildren() do
						if binding:IsA("InputBinding") then
							table.insert(keys, binding.KeyCode.Name)
						end
					end
					Verify.expect(table.find(keys, "ButtonB") ~= nil):toBe(true)
					back.Pressed:Fire()
					Verify.expect(built.report().example.alert.presented):toBe(false)
					Verify.expect(gui.SelectedObject):toBe(launcher)
					Verify.expect(built.report().selected.Categories):toBe("actions")
					Verify.expect(built.report().active):toBe("alerts")
					find(outer, "navigation").Activated:Fire()
					local journey = tabView(screen, "navigation")
					local continue = find(journey:FindFirstChild("Content"), "Continue")
					gui.SelectedObject = continue
					continue.Activated:Fire()
					Verify.expect(built.report().example.navigation.depth):toBe(1)
					Verify.expect(gui.SelectedObject ~= continue and gui.SelectedObject:IsDescendantOf(journey))
						:toBe(true)
					action(screen, "NavigationBack").Pressed:Fire()
					Verify.expect(built.report().example.navigation.depth):toBe(0)
					Verify.expect(gui.SelectedObject):toBe(continue)
					action(screen, "NextTab").Pressed:Fire()
					Verify.expect(built.report().selected.Categories):toBe("navigation")
					Verify.expect(built.report().active):toBe("pages")
					stop()
				end,
			}
		)

		verifyHarness:case(
			"opens a menu only through its declared triggers and binds the keyboard and gamepad chords",
			{
				id = "native_parity_navigation::native parity navigation::opens a menu only through its declared triggers and binds the keyboard and gamepad chords",
				run = function()
					local restricted, activateOnly = Compose.cell(false), Compose.cell(false)
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						local items = { { id = "a", label = "A", onSelect = function() end } }
						return Host.Frame({
							UI.Menu("Restricted")({
								label = "Actions",
								isPresented = restricted,
								items = items,
								triggers = { "secondary", "keyboard", "gamepad" } :: { FixtureNavigationTypes.MenuTrigger },
							}) :: unknown,
							UI.Menu("Tap")({
								label = "Tap",
								isPresented = activateOnly,
								items = items,
								triggers = { "activate" } :: { FixtureNavigationTypes.MenuTrigger },
							}),
						})
					end)
					local Enum = world.engine.types.Enum
					local trigger = find(find(world.screen, "Restricted"), "Trigger")
					trigger.Activated:Fire()
					Verify.expect((restricted:peek())):toBe(false)
					trigger.InputBegan:Fire({
						UserInputType = Enum.UserInputType.MouseButton2,
						Position = world.engine.types.Vector3.new(50, 50, 0),
					})
					Verify.expect((restricted:peek())):toBe(true)
					Verify.expect(find(world.screen, "MenuPanel") ~= nil):toBe(true)
					action(world.screen, "ModalBack").Pressed:Fire()
					Verify.expect((restricted:peek())):toBe(false)
					Verify.expect((action(world.screen, "Menu"))):toBeNil()
					world.gui.SelectedObject = trigger
					local chord = action(world.screen, "Menu")
					local bindings = {}
					for _, binding in chord:GetChildren() do
						local modifier = binding.PrimaryModifier
						local plain = modifier == nil or modifier == Enum.KeyCode:FromValue(0)
						table.insert(bindings, binding.KeyCode.Name .. (if plain then "" else "+" .. modifier.Name))
					end
					table.sort(bindings)
					Verify.expect(bindings):toEqual({ "ButtonY", "F10+LeftShift", "F10+RightShift", "Menu" })
					chord.Pressed:Fire()
					Verify.expect((restricted:peek())):toBe(true)
					action(world.screen, "ModalBack").Pressed:Fire()
					local tap = find(find(world.screen, "Tap"), "Trigger")
					tap.InputBegan:Fire({
						UserInputType = Enum.UserInputType.MouseButton2,
						Position = world.engine.types.Vector3.new(50, 50, 0),
					})
					tap.TouchLongPress:Fire({}, Enum.UserInputState.Begin)
					world.gui.SelectedObject = tap
					Verify.expect((action(world.screen, "Menu"))):toBeNil()
					Verify.expect((activateOnly:peek())):toBe(false)
					tap.Activated:Fire()
					Verify.expect((activateOnly:peek())):toBe(true)
					world.stop()
				end,
			}
		)

		verifyHarness:case("opens a wholly disabled menu and keeps it open when a disabled item is activated", {
			id = "native_parity_navigation::native parity navigation::opens a wholly disabled menu and keeps it open when a disabled item is activated",
			run = function()
				local opened, ran = Compose.cell(false), 0
				local world = setup(function(UI: FacetControls)
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
							} :: FixtureNavigationTypes.MenuItem<any>,
							{
								id = "share",
								label = "Share",
								enabled = false,
								onSelect = function()
									ran += 1
								end,
							} :: FixtureNavigationTypes.MenuItem<any>,
						},
					})
				end)
				find(world.screen, "Trigger").Activated:Fire()
				Verify.expect((opened:peek())):toBe(true)
				local panel = find(world.screen, "MenuPanel")
				for _, id in { "save", "share" } do
					local row = find(panel, id)
					Verify.expect(row.Interactable):toBe(false)
					Verify.expect((row:HasTag("facet-disabled"))):toBe(true)
					row.Activated:Fire()
				end
				Verify.expect(ran):toBe(0)
				Verify.expect((opened:peek())):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("unwinds submenus one level at a time and enters a branch only from a focused branch row", {
			id = "native_parity_navigation::native parity navigation::unwinds submenus one level at a time and enters a branch only from a focused branch row",
			run = function()
				local opened = Compose.cell(false)
				local world = setup(function(UI: FacetControls)
					return UI.Menu({
						isPresented = opened,
						items = {
							{ id = "First", label = "First", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
							{
								id = "Parent",
								label = "Parent",
								children = { { id = "Leaf", label = "Leaf", onSelect = function() end } },
							} :: FixtureNavigationTypes.MenuItem<any>,
						},
					})
				end)
				world.gui.SelectedObject = find(world.screen, "Trigger")
				opened:set(true)
				local modal = find(world.screen, "Modal")
				modal.AbsoluteSize = V2(world, 1000, 720)
				Verify.expect(world.gui.SelectedObject.Name):toBe("First")
				Verify.expect((action(world.screen, "MenuRight"))):toBeNil()
				local keys = {}
				for _, context in contexts(world.screen, "MenuRight") do
					for _, binding in context:FindFirstChild("MenuRight"):GetChildren() do
						table.insert(keys, binding.KeyCode.Name)
					end
				end
				table.sort(keys)
				Verify.expect(keys):toEqual({ "DPadRight", "Right" })
				local panel = find(world.screen, "MenuPanel")
				world.gui.SelectedObject = find(panel, "Parent")
				Verify.expect(find(panel, "Parent"):FindFirstChild("TrailingIcon", true).Image ~= ""):toBe(true)
				Verify.expect((find(panel, "First"):FindFirstChild("TrailingIcon", true))):toBeNil()
				action(world.screen, "MenuRight").Pressed:Fire()
				Verify.expect(find(panel, "Leaf") ~= nil):toBe(true)
				Verify.expect(world.gui.SelectedObject.Name):toBe("Leaf")
				Verify.expect((action(world.screen, "MenuRight"))):toBeNil()
				action(world.screen, "MenuLeft").Pressed:Fire()
				Verify.expect((find(panel, "Leaf"))):toBeNil()
				Verify.expect(world.gui.SelectedObject.Name):toBe("Parent")
				Verify.expect((opened:peek())):toBe(true)
				action(world.screen, "MenuRight").Pressed:Fire()
				action(world.screen, "ModalBack").Pressed:Fire()
				Verify.expect((find(panel, "Leaf"))):toBeNil()
				Verify.expect((opened:peek())):toBe(true)
				Verify.expect(world.gui.SelectedObject.Name):toBe("Parent")
				action(world.screen, "ModalBack").Pressed:Fire()
				Verify.expect((opened:peek())):toBe(false)
				world.stop()
			end,
		})

		verifyHarness:case("follows the presentation option and touch input between the menu and sheet idioms", {
			id = "native_parity_navigation::native parity navigation::follows the presentation option and touch input between the menu and sheet idioms",
			run = function()
				local opened, presentation =
					Compose.cell(false), Compose.cell("sheet" :: "automatic" | "menu" | "sheet")
				local world = setup(function(UI: FacetControls)
					return UI.Menu({
						isPresented = opened,
						presentation = presentation,
						backLabel = "Retour",
						items = {
							{
								id = "Parent",
								label = "Parent",
								children = { { id = "Leaf", label = "Leaf", onSelect = function() end } },
							} :: FixtureNavigationTypes.MenuItem<any>,
						},
					})
				end)
				opened:set(true)
				local modal = find(world.screen, "Modal")
				modal.AbsoluteSize = V2(world, 1000, 720)
				find(world.screen, "Parent").Activated:Fire()
				local back = find(world.screen, "Back")
				Verify.expect(back ~= nil):toBe(true)
				Verify.expect(find(back, "Title").Text):toBe("Retour")
				Verify.expect(find(back, "LeadingIcon") ~= nil):toBe(true)
				Verify.expect((find(world.screen, "AncestorMenu"))):toBeNil()
				presentation:set("menu")
				Verify.expect(find(world.screen, "AncestorMenu") ~= nil):toBe(true)
				Verify.expect(find(world.screen, "Leaf") ~= nil):toBe(true)
				presentation:set("automatic")
				Verify.expect(find(world.screen, "AncestorMenu") ~= nil):toBe(true)
				world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Touch
				Verify.expect((find(world.screen, "AncestorMenu"))):toBeNil()
				Verify.expect(find(world.screen, "Leaf") ~= nil):toBe(true)
				world.input.PreferredInput = world.engine.types.Enum.PreferredInput.KeyboardAndMouse
				Verify.expect(find(world.screen, "AncestorMenu") ~= nil):toBe(true)
				world.input.PreferredInput = world.engine.types.Enum.PreferredInput.Gamepad
				Verify.expect((find(world.screen, "AncestorMenu"))):toBeNil()
				Verify.expect(find(world.screen, "Back") ~= nil):toBe(true)
				world.input.PreferredInput = world.engine.types.Enum.PreferredInput.KeyboardAndMouse
				Verify.expect(find(world.screen, "AncestorMenu") ~= nil):toBe(true)
				modal.AbsoluteSize = V2(world, 360, 720)
				Verify.expect((find(world.screen, "AncestorMenu"))):toBeNil()
				presentation:set("menu")
				Verify.expect(find(world.screen, "AncestorMenu") ~= nil):toBe(true)
				Verify.expect(find(world.screen, "Leaf") ~= nil):toBe(true)
				world.stop()
			end,
		})

		verifyHarness:case("toggles nested checked items in both idioms and releases every level with the trigger", {
			id = "native_parity_navigation::native parity navigation::toggles nested checked items in both idioms and releases every level with the trigger",
			run = function()
				for _, presentation in { "menu", "sheet" } :: { "menu" | "sheet" } do
					local checked = Compose.cell(false)
					local show = Compose.cell(true)
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({
							Compose.show(show, function()
								return UI.Menu({
									presentation = presentation :: "menu" | "sheet",
									items = {
										{
											id = "options",
											label = "Options",
											children = {
												{
													id = "deeper",
													label = "Deeper",
													children = {
														{
															id = "check",
															label = "Check",
															checked = checked,
															dismiss = true,
														},
													},
												},
											},
										} :: FixtureNavigationTypes.MenuItem<any>,
									},
								})
							end),
						})
					end)
					local before = world.engine.census()
					for round = 1, 2 do
						find(world.screen, "Trigger").Activated:Fire()
						find(world.screen, "Modal").AbsoluteSize = V2(world, 1000, 720)
						find(find(world.screen, "MenuPanel"), "options").Activated:Fire()
						find(find(world.screen, "MenuPanel"), "deeper").Activated:Fire()
						find(find(world.screen, "MenuPanel"), "check").Activated:Fire()
						Verify.expect((checked:peek())):toBe(round == 1)
						Verify.expect((find(world.screen, "MenuPanel"))):toBeNil()
					end
					local closed = world.engine.census()
					for _ = 1, 20 do
						find(world.screen, "Trigger").Activated:Fire()
						find(world.screen, "Modal").AbsoluteSize = V2(world, 1000, 720)
						find(find(world.screen, "MenuPanel"), "options").Activated:Fire()
						find(find(world.screen, "MenuPanel"), "deeper").Activated:Fire()
						action(world.screen, "ModalBack").Pressed:Fire()
						action(world.screen, "ModalBack").Pressed:Fire()
						action(world.screen, "ModalBack").Pressed:Fire()
					end
					Verify.expect((find(world.screen, "MenuPanel"))):toBeNil()
					local churned = world.engine.census()
					Verify.expect(churned.live):toBe(closed.live)
					Verify.expect(churned.connections):toBe(closed.connections)
					find(world.screen, "Trigger").Activated:Fire()
					find(find(world.screen, "MenuPanel"), "options").Activated:Fire()
					find(find(world.screen, "MenuPanel"), "deeper").Activated:Fire()
					show:set(false)
					Verify.expect((find(world.screen, "MenuPanel"))):toBeNil()
					Verify.expect((find(world.screen, "AncestorMenu"))):toBeNil()
					Verify.expect((find(world.screen, "DismissOutside"))):toBeNil()
					Verify.expect(#contexts(world.screen, "ModalBack")):toBe(0)
					local after = world.engine.census()
					Verify.expect(after.connections <= before.connections):toBe(true)
					world.stop()
				end
			end,
		})

		verifyHarness:case(
			"anchors the menu panel below its trigger, sizes it from the widest row and keeps it inside the viewport",
			{
				id = "native_parity_navigation::native parity navigation::anchors the menu panel below its trigger, sizes it from the widest row and keeps it inside the viewport",
				run = function()
					local opened = Compose.cell(false)
					local world = setup(function(UI: FacetControls)
						return UI.Menu({
							isPresented = opened,
							items = {
								{ id = "short", label = "Short", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
								{ id = "long", label = "Long", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
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
					Verify.expect(panel.Size.X.Offset):toBe(348)
					Verify.expect(panel.Size.Y.Offset):toBe(104)
					panel.AbsoluteSize = V2(world, 348, 104)
					world.engine.heartbeat:Fire(1)
					world.engine.heartbeat:Fire(1)
					Verify.expect((materialize.position(panel))):toBe(world.engine.types.UDim2.fromOffset(100, 148))
					find(find(panel, "long"), "Content").AbsoluteSize = V2(world, 500, 44)
					Verify.expect(panel.Size.X.Offset):toBe(400)
					find(find(panel, "long"), "Content").AbsoluteSize = V2(world, 50, 44)
					Verify.expect(panel.Size.X.Offset):toBe(220)
					trigger.AbsolutePosition = V2(world, 900, 800)
					panel.AbsoluteSize = V2(world, 220, 104)
					Verify.expect(materialize.position(panel).X.Offset):toBe(1000 - 220 - 8)
					Verify.expect(materialize.position(panel).Y.Offset):toBe(800 - 104 - 4)
					world.stop()
				end,
			}
		)

		verifyHarness:case("keeps a picker and menu tap-away catcher invisible at every background preference", {
			id = "native_parity_navigation::native parity navigation::keeps a picker and menu tap-away catcher invisible at every background preference",
			run = function()
				for _, kind in { "menu", "picker" } :: { "menu" | "picker" } do
					local opened = Compose.cell(true)
					local world = setup(function(UI: FacetControls)
						if kind == "menu" then
							return UI.Menu({
								isPresented = opened,
								items = {
									{ id = "a", label = "A", onSelect = function() end } :: FixtureNavigationTypes.MenuItem<any>,
								},
							})
						end
						return UI.Picker({
							selected = Compose.cell("a"),
							style = "menu" :: "menu",
							isPresented = opened,
							options = {
								{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
								{ value = "b", label = "B" } :: FixtureNavigationTypes.PickerOption<any>,
							},
						})
					end)
					local catcher = find(world.screen, "DismissOutside")
					for _, preference in { 1, 0.5, 0 } do
						world.gui.PreferredTransparency = preference
						Verify.expect(catcher.BackgroundTransparency):toBe(1)
					end
					world.stop()
				end
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.Dialog({
						isPresented = Compose.cell(true),
						onPresentedChange = function() end,
						title = "More",
						content = function(): Instance
							return Host.Frame({})
						end,
					})
				end)
				world.gui.PreferredTransparency = 0
				Verify.expect((find(world.screen, "DismissOutside"):HasTag("facet-scrim"))):toBe(true)
				world.stop()
				local engine: any = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local stop, sheet: any = runtime.mount(function()
					return Facet.themes.createStyleSheet(
						runtime,
						Facet.themes.neutralPackage(),
						{ types = engine.types }
					)
				end, engine.new("Folder"))
				local scrim
				for _, rule in sheet:GetChildren() do
					if rule.Selector == ".facet-scrim" then
						scrim = rule:GetProperties().BackgroundTransparency
					end
				end
				Verify.expect(scrim > 0 and scrim < 1):toBe(true)
				stop()
				runtime:dispose()
			end,
		})
		verifyHarness:case(
			"picks from a vertical radio group and moves the current paint with the selection and indicator",
			{
				id = "native_parity_navigation::native parity navigation::picks from a vertical radio group and moves the current paint with the selection and indicator",
				run = function()
					local selected, indicator = Compose.cell("a"), Compose.cell(nil :: string?)
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						local options = {
							{ value = "a", label = "A" },
							{ value = "b", label = "B" },
							{ value = "c", label = "C" },
						}
						return Host.Frame({
							UI.Picker("Radio")({
								selected = selected,
								style = "radioGroup" :: "radioGroup",
								options = options,
							}) :: unknown,
							UI.Picker("Segments")({
								selected = selected,
								style = "segmented" :: "segmented",
								indicator = indicator,
								options = options,
							}),
							UI.Picker("Inline")({
								selected = selected,
								style = "inline" :: "inline",
								options = options,
							}),
						})
					end)
					local Enum = world.engine.types.Enum
					local radio = find(world.screen, "Radio")
					Verify.expect(radio:FindFirstChildWhichIsA("UIListLayout").FillDirection)
						:toBe(Enum.FillDirection.Vertical)
					for _, id in { "a", "b", "c" } do
						Verify.expect((find(radio, id):HasTag("facet-choice"))):toBe(true)
					end
					find(radio, "b").Activated:Fire()
					Verify.expect((selected:peek())):toBe("b")
					local segments, inline = find(world.screen, "Segments"), find(world.screen, "Inline")
					local a, b = find(segments, "a"), find(segments, "b")
					Verify.expect((b:HasTag("facet-segment-current"))):toBe(true)
					Verify.expect((b:HasTag("facet-selected"))):toBe(true)
					Verify.expect((a:HasTag("facet-segment-current"))):toBe(false)
					Verify.expect((a:HasTag("facet-selected"))):toBe(false)
					Verify.expect((find(inline, "b"):HasTag("facet-choice-current"))):toBe(true)
					Verify.expect((find(radio, "b"):HasTag("facet-choice-current"))):toBe(true)
					selected:set("a")
					Verify.expect((find(segments, "a"))):toBe(a)
					Verify.expect((a:HasTag("facet-segment-current"))):toBe(true)
					Verify.expect((b:HasTag("facet-segment-current"))):toBe(false)
					Verify.expect((find(inline, "a"):HasTag("facet-choice-current"))):toBe(true)
					Verify.expect((find(inline, "b"):HasTag("facet-choice-current"))):toBe(false)
					indicator:set("underline")
					Verify.expect(a:FindFirstChild("SelectionIndicator") ~= nil):toBe(true)
					Verify.expect((a:HasTag("facet-segment-current"))):toBe(false)
					Verify.expect((a:HasTag("facet-selected"))):toBe(false)
					indicator:set("pill")
					Verify.expect((a:FindFirstChild("SelectionIndicator"))):toBeNil()
					Verify.expect((a:HasTag("facet-segment-current"))):toBe(true)
					indicator:set("none")
					Verify.expect((a:FindFirstChild("SelectionIndicator"))):toBeNil()
					Verify.expect((a:HasTag("facet-segment-current"))):toBe(true)
					indicator:set("automatic")
					Verify.expect((a:HasTag("facet-segment-current"))):toBe(true)
					world.stop()
				end,
			}
		)

		verifyHarness:case("sizes segments by fill or hug without replacing them and refuses unknown sizing", {
			id = "native_parity_navigation::native parity navigation::sizes segments by fill or hug without replacing them and refuses unknown sizing",
			run = function()
				local sizing, selected =
					(function(value: "fill" | "hug"): FixtureComposeTypes.Cell<"fill" | "hug">
						return Compose.cell(value)
					end)("fill"), Compose.cell("a")
				local world = setup(function(UI: FacetControls)
					return UI.Picker({
						selected = selected,
						style = "segmented" :: "segmented",
						sizing = sizing,
						options = {
							{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
							{ value = "b", label = "Much longer" } :: FixtureNavigationTypes.PickerOption<any>,
						},
					})
				end)
				local Enum = world.engine.types.Enum
				local picker = find(world.screen, "Picker")
				local layout = picker:FindFirstChildWhichIsA("UIListLayout")
				local a = find(picker, "a")
				Verify.expect(layout.HorizontalFlex):toBe(Enum.UIFlexAlignment.Fill)
				Verify.expect(a.AutomaticSize):toBe(Enum.AutomaticSize.X)
				Verify.expect(a.Size.Y.Scale):toBe(0)
				Verify.expect(a.Size.Y.Offset):toBe(44)
				sizing:set("hug")
				Verify.expect(layout.HorizontalFlex):toBe(Enum.UIFlexAlignment.None)
				Verify.expect((find(picker, "a"))):toBe(a)
				sizing:set("fill")
				Verify.expect(layout.HorizontalFlex):toBe(Enum.UIFlexAlignment.Fill)
				world.stop()
				Verify.expect((refuses("Picker.sizing must be fill or hug", function(UI: FacetControls)
					return UI.Picker({
						selected = Compose.cell("a"),
						style = "segmented",
						sizing = "wide",
						options = { { value = "a", label = "A" } },
					} :: any)
				end))):toBe(true)
			end,
		})

		verifyHarness:case("refuses malformed picker options, labels, icons, indicators, axes and styles", {
			id = "native_parity_navigation::native parity navigation::refuses malformed picker options, labels, icons, indicators, axes and styles",
			run = function()
				local function picker(extra)
					return function(UI: FacetControls)
						local spec: { [any]: any } = {
							selected = Compose.cell("a"),
							style = "segmented" :: "segmented",
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
					{
						"Picker options require nonempty labels",
						{ options = { { value = "a", label = Compose.cell("") } } },
					},
					{
						"Picker.iconOnly requires an icon on each option",
						{ iconOnly = true, options = { { value = "a", label = "A" } } },
					},
					{ "Invalid Picker.indicator", { indicator = "bar" :: "bar" } },
					{ "Picker.axis must be x or y", { axis = "z" :: "z" } },
					{ "Unknown Picker style", { style = "wheel" :: "wheel" } },
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
					table.insert(cases, { entry[1], { style = "menu" :: "menu", options = entry[2] } })
					table.insert(cases, { entry[1], { style = "menu" :: "menu", options = Compose.cell(entry[2]) } })
					table.insert(cases, { entry[1], { style = "inline" :: "inline", options = entry[2] } })
				end
				for _, case in cases do
					local failure = mountError(picker(case[2]))
					Verify.expect(failure ~= nil and string.find(failure, case[1], 1, true) ~= nil):toBe(true)
				end
				Verify.expect((mountError(picker({ indicator = "automatic" :: "automatic" })))):toBeNil()
			end,
		})

		verifyHarness:case("resolves the automatic picker by width, description, count, input and query", {
			id = "native_parity_navigation::native parity navigation::resolves the automatic picker by width, description, count, input and query",
			run = function()
				local options = Compose.cell({
					{ value = "a", label = "A" },
					{ value = "b", label = "B" },
				} :: { any })
				local world = setup(function(UI: FacetControls)
					return UI.Picker({ selected = Compose.cell("a"), options = options })
				end)
				local Enum = world.engine.types.Enum
				local container = find(world.screen, "Picker")
				local function presentation()
					return container:FindFirstChild("Presentation")
				end
				container.AbsoluteSize = V2(world, 400, 44)
				Verify.expect((presentation():HasTag("facet-segmented"))):toBe(true)
				local first = presentation()
				container.AbsoluteSize = V2(world, 300, 44)
				Verify.expect((presentation():HasTag("facet-segmented"))):toBe(true)
				container.AbsoluteSize = V2(world, 50, 44)
				world.input.PreferredInput = Enum.PreferredInput.KeyboardAndMouse
				Verify.expect(find(presentation(), "Trigger") ~= nil):toBe(true)
				world.input.PreferredInput = Enum.PreferredInput.Gamepad
				Verify.expect((presentation():HasTag("facet-segmented"))):toBe(false)
				Verify.expect(find(presentation(), "a") ~= nil):toBe(true)
				Verify.expect((find(presentation(), "Trigger"))):toBeNil()
				container.AbsoluteSize = V2(world, 400, 44)
				options:set({
					{ value = "a", label = "A", description = "First" },
					{ value = "b", label = "B" },
				})
				Verify.expect((presentation():HasTag("facet-segmented"))):toBe(false)
				Verify.expect(find(presentation(), "a") ~= nil):toBe(true)
				local seven = {}
				for index = 1, 7 do
					table.insert(seven, { value = tostring(index), label = `Option {index}` })
				end
				seven[1].value = "a"
				options:set(seven)
				Verify.expect(find(presentation(), "Trigger") ~= nil):toBe(true)
				options:set({ table.unpack(seven, 1, 6) })
				Verify.expect((find(presentation(), "Trigger"))):toBeNil()
				Verify.expect(find(presentation(), "a") ~= nil):toBe(true)
				Verify.expect((find(world.screen, "Picker"))):toBe(container)
				Verify.expect(first ~= presentation()):toBe(true)
				world.stop()
				local query = Compose.cell("")
				local searching = setup(function(UI: FacetControls)
					return UI.Picker({
						selected = Compose.cell("a"),
						query = query,
						options = {
							{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
							{ value = "b", label = "B" } :: FixtureNavigationTypes.PickerOption<any>,
						},
					})
				end)
				local link = find(searching.screen, "Presentation")
				Verify.expect(link.ClassName):toBe("TextButton")
				link.Activated:Fire()
				Verify.expect(find(searching.screen, "PickerSearch") ~= nil):toBe(true)
				searching.stop()
			end,
		})

		verifyHarness:case("never shows a selection redirected inside onChange to observers", {
			id = "native_parity_navigation::native parity navigation::never shows a selection redirected inside onChange to observers",
			run = function()
				local selected = Compose.cell("a")
				local seen = {}
				local world = setup(function(UI: FacetControls)
					Compose.watch(function(use: Use)
						table.insert(seen, use(selected))
					end)
					return UI.Picker({
						selected = selected,
						style = "segmented" :: "segmented",
						options = {
							{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
							{ value = "b", label = "B" } :: FixtureNavigationTypes.PickerOption<any>,
						},
						onChange = function()
							selected:set("a")
						end,
					})
				end)
				find(world.screen, "b").Activated:Fire()
				Verify.expect((selected:peek())):toBe("a")
				Verify.expect((table.find(seen, "b"))):toBeNil()
				world.stop()
			end,
		})

		verifyHarness:case("closes a menu picker by trigger or Back without changing the selection", {
			id = "native_parity_navigation::native parity navigation::closes a menu picker by trigger or Back without changing the selection",
			run = function()
				local selected, opened = Compose.cell("a"), Compose.cell(false)
				local world = setup(function(UI: FacetControls)
					return UI.Picker({
						selected = selected,
						style = "menu" :: "menu",
						isPresented = opened,
						options = {
							{ value = "a", label = "A" } :: FixtureNavigationTypes.PickerOption<any>,
							{ value = "b", label = "B" } :: FixtureNavigationTypes.PickerOption<any>,
						},
					})
				end)
				local trigger = find(world.screen, "Trigger")
				trigger.Activated:Fire()
				Verify.expect((opened:peek())):toBe(true)
				action(world.screen, "ModalBack").Pressed:Fire()
				Verify.expect((opened:peek())):toBe(false)
				Verify.expect((selected:peek())):toBe("a")
				trigger.Activated:Fire()
				find(world.screen, "DismissOutside").Activated:Fire({
					Position = world.engine.types.Vector3.new(0, 0, 0),
				})
				Verify.expect((opened:peek())):toBe(false)
				Verify.expect((selected:peek())):toBe("a")
				trigger.Activated:Fire()
				find(find(world.screen, "MenuPanel"), "b").Activated:Fire()
				Verify.expect((opened:peek())):toBe(false)
				Verify.expect((selected:peek())):toBe("b")
				world.stop()
			end,
		})
		verifyHarness:case("refuses unknown and duplicate sheet detents and a read-only detent source", {
			id = "native_parity_navigation::native parity navigation::refuses unknown and duplicate sheet detents and a read-only detent source",
			run = function()
				local function sheet(extra)
					return function(UI: FacetControls, Host: RobloxHost)
						local spec: { [any]: any } = {
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
				Verify.expect((refuses(
					"Invalid Sheet detent",
					sheet({
						detents = ({ "tiny" } :: unknown) :: { SheetDetent },
					})
				))):toBe(true)
				Verify.expect((refuses(
					"Sheet detents require unique ids",
					sheet({
						detents = { "medium", "medium" } :: { SheetDetent },
					})
				))):toBe(true)
				Verify.expect((refuses(
					"Sheet.detent requires a writable Compose cell",
					sheet({
						detent = Compose.formula(function()
							return "medium"
						end),
					})
				))):toBe(true)
				Verify.expect((mountError(sheet({
					detents = { "medium", { id = "tall", height = 600 } } :: { SheetDetent },
				})))):toBeNil()
			end,
		})

		verifyHarness:case("dismisses a sheet dragged below its smallest detent and keeps a 44 pixel grabber", {
			id = "native_parity_navigation::native parity navigation::dismisses a sheet dragged below its smallest detent and keeps a 44 pixel grabber",
			run = function()
				local opened, detent = Compose.cell(true), Compose.cell("medium")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet({
						isPresented = opened,
						detent = detent,
						title = "Sheet",
						content = page(Host, "sheet"),
					})
				end, { motionLevel = "none" })
				find(world.screen, "Modal").AbsoluteSize = V2(world, 390, 720)
				local panel = find(world.screen, "SheetPanel")
				Verify.expect(panel.Size.Y.Offset):toBe(360)
				local grabber = find(world.screen, "Grabber")
				Verify.expect(grabber.Size.X.Offset >= 44 and grabber.Size.Y.Offset >= 44):toBe(true)
				local drag = find(world.screen, "UIDragDetector")
				drag.DragStart:Fire(V2(world, 0, 0))
				drag.DragContinue:Fire(V2(world, 0, 60))
				drag.DragEnd:Fire()
				Verify.expect((opened:peek())):toBe(true)
				Verify.expect((detent:peek())):toBe("medium")
				drag.DragStart:Fire(V2(world, 0, 0))
				drag.DragContinue:Fire(V2(world, 0, 400))
				drag.DragEnd:Fire()
				Verify.expect((opened:peek())):toBe(false)
				Verify.expect((find(world.screen, "SheetPanel"))):toBeNil()
				world.stop()
			end,
		})

		verifyHarness:case("continues a grab during a detent change from the painted height", {
			id = "native_parity_navigation::native parity navigation::continues a grab during a detent change from the painted height",
			run = function()
				local detent = Compose.cell("medium")
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet({
						isPresented = Compose.cell(true),
						detent = detent,
						title = "Sheet",
						content = page(Host, "sheet"),
					})
				end)
				find(world.screen, "Modal").AbsoluteSize = V2(world, 390, 720)
				world.engine.heartbeat:Fire(1)
				world.engine.heartbeat:Fire(1)
				local panel = find(world.screen, "SheetPanel")
				Verify.expect(panel.Size.Y.Offset):toBeCloseTo(360, 0.5)
				detent:set("large")
				world.engine.heartbeat:Fire(0.05)
				local painted = panel.Size.Y.Offset
				Verify.expect(painted > 360 and painted < 684):toBe(true)
				local drag = find(world.screen, "UIDragDetector")
				drag.DragStart:Fire(V2(world, 0, 0))
				Verify.expect(panel.Size.Y.Offset):toBeCloseTo(painted, 0.5)
				drag.DragContinue:Fire(V2(world, 0, 1))
				Verify.expect(panel.Size.Y.Offset):toBeCloseTo(painted - 1, 0.5)
				world.stop()
			end,
		})

		verifyHarness:case(
			"gates callout eligibility on sessions, seen and feature use and refuses a missing onRetire",
			{
				id = "native_parity_navigation::native parity navigation::gates callout eligibility on sessions, seen and feature use and refuses a missing onRetire",
				run = function()
					local sessions = Compose.cell(1)
					local retired = {}
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						local function anchor(name: string)
							return Host.TextButton(name)({})
						end
						local first, second, third = anchor("First"), anchor("Second"), anchor("Third")
						local function callout(name: string, target, extra)
							local spec: { [any]: any } = {
								anchor = target,
								content = function(): Instance
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
							first :: unknown,
							second,
							third,
							callout("Later", first, { sessions = sessions, afterSessions = 3 }),
							callout("Seen", second, { seen = Compose.cell(true), priority = 5 }),
							callout("Used", third, { featureUsed = Compose.cell(true), priority = 6 }),
						})
					end)
					Verify.expect((find(world.screen, "LaterTip"))):toBeNil()
					Verify.expect((find(world.screen, "SeenTip"))):toBeNil()
					Verify.expect((find(world.screen, "UsedTip"))):toBeNil()
					table.sort(retired)
					Verify.expect(retired):toEqual({ "Seen:seen", "Used:featureUsed" })
					sessions:set(2)
					Verify.expect((find(world.screen, "LaterTip"))):toBeNil()
					sessions:set(3)
					Verify.expect(find(world.screen, "LaterTip") ~= nil):toBe(true)
					world.stop()
					Verify.expect((refuses("Callout requires onRetire", function(UI: FacetControls, Host: RobloxHost)
						return UI.Callout({ anchor = Host.TextButton({}), content = page(Host, "tip") } :: any)
					end))):toBe(true)
					Verify.expect((refuses("unknown option 'persist'", function(UI: FacetControls, Host: RobloxHost)
						return UI.Callout({
							anchor = Host.TextButton({}) :: GuiObject,
							content = page(Host, "tip"),
							onRetire = function() end,
							persist = true,
						})
					end))):toBe(true)
				end,
			}
		)

		verifyHarness:case("frees the callout queue slot when the showing callout is disposed", {
			id = "native_parity_navigation::native parity navigation::frees the callout queue slot when the showing callout is disposed",
			run = function()
				local flag, retired = Compose.cell(true), {}
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					local anchor = Host.TextButton("Anchor")({})
					local function callout(name: string, priority)
						return UI.Callout({
							anchor = anchor :: GuiObject,
							priority = priority,
							content = function(): Instance
								return Host.TextLabel(name .. "Tip")({ Text = name })
							end,
							onRetire = function(reason: "action" | "dismissed" | "featureUsed" | "seen" | "tapAway")
								table.insert(retired, name .. ":" .. reason)
							end,
						})
					end
					return Host.Frame({
						anchor :: unknown,
						Compose.show(flag, function()
							return callout("High", 2)
						end),
						callout("Low", 1),
					})
				end)
				Verify.expect(find(world.screen, "HighTip") ~= nil):toBe(true)
				Verify.expect((find(world.screen, "LowTip"))):toBeNil()
				flag:set(false)
				Verify.expect((find(world.screen, "HighTip"))):toBeNil()
				Verify.expect(find(world.screen, "LowTip") ~= nil):toBe(true)
				Verify.expect(retired):toEqual({})
				world.stop()
			end,
		})

		verifyHarness:case(
			"aligns a callout to the anchor edges, flips it above near the bottom and omits an unrequested tail",
			{
				id = "native_parity_navigation::native parity navigation::aligns a callout to the anchor edges, flips it above near the bottom and omits an unrequested tail",
				run = function()
					local align: FixtureComposeTypes.Cell<"center" | "leading" | "trailing"> =
						Compose.cell("center" :: "center" | "leading" | "trailing")
					local world = setup(function(UI: FacetControls, Host: RobloxHost)
						local anchor = Host.TextButton("Anchor")({})
						local withoutTail = Host.TextButton("Quiet")({})
						return Host.Frame({
							anchor :: unknown,
							withoutTail,
							UI.Callout({
								anchor = anchor :: GuiObject,
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
					world.engine.heartbeat:Fire(1)
					local lift = 8 + 16 * math.sqrt(2) / 2
					local function corner(): (number, number)
						return math.round(panel.Position.X.Offset - panel.AnchorPoint.X * panel.AbsoluteSize.X),
							panel.Position.Y.Offset - panel.AnchorPoint.Y * panel.AbsoluteSize.Y
					end
					Verify.expect(math.abs(select(2, corner()) - (660 - 100 - lift)) <= 1):toBe(true)
					Verify.expect((corner())):toBe(140)
					align:set("leading")
					Verify.expect((corner())):toBe(160)
					align:set("trailing")
					Verify.expect((corner())):toBe(160 + 240 - 280)
					anchor.AbsolutePosition = V2(world, 160, 100)
					Verify.expect(math.abs(select(2, corner()) - (100 + 44 + lift)) <= 1):toBe(true)
					Verify.expect(find(world.screen, "Arrow") ~= nil):toBe(true)
					world.stop()
					for _, tail in { false, "none" } :: { any } do
						local quiet = setup(function(UI: FacetControls, Host: RobloxHost)
							local anchor = Host.TextButton("Anchor")({})
							return Host.Frame({
								anchor :: unknown,
								UI.Callout({
									anchor = anchor :: GuiObject,
									tail = tail,
									content = page(Host, "tip"),
									onRetire = function() end,
								}),
							})
						end)
						Verify.expect(find(quiet.screen, "CalloutPanel") ~= nil):toBe(true)
						Verify.expect((find(quiet.screen, "Arrow"))):toBeNil()
						quiet.stop()
					end
				end,
			}
		)

		verifyHarness:case("keeps device names out of the control sources", {
			id = "native_parity_navigation::native parity navigation::keeps device names out of the control sources",
			run = function()
				for _, file in fs.readDir("src/ui") do
					local source = string.lower(fs.readFile("src/ui/" .. file))
					for _, device in
						{ "iphone", "ipad", "android", "xbox", "playstation", "nintendo", "macos", "windows" }
					do
						Verify.expect(string.find(source, "%f[%a]" .. device .. "%f[%A]") == nil):toBe(true)
					end
				end
			end,
		})
		verifyHarness:case(
			"adds a default OK action and keeps an alert open on outside taps and custom content buttons",
			{
				id = "native_parity_navigation::native parity navigation::adds a default OK action and keeps an alert open on outside taps and custom content buttons",
				run = function()
					for _, surface in { "dialog", "fullScreen" } :: { "dialog" | "fullScreen" } do
						local presented = Compose.cell(true)
						local world = setup(function(UI: FacetControls)
							return UI.Alert({
								isPresented = presented,
								title = "Saved",
								surface = surface :: "dialog" | "fullScreen",
								content = function(): Instance
									return UI.Button("OK")({ label = "Preview" })
								end,
							})
						end)
						local actions = find(world.screen, "Actions")
						local content = find(world.screen, "AlertContent")
						Verify.expect(find(content, "OK").Text):toBe("Preview")
						find(content, "OK").Activated:Fire()
						Verify.expect((presented:peek())):toBe(true)
						find(world.screen, "DismissOutside").Activated:Fire({
							Position = world.engine.types.Vector3.new(0, 0, 0),
						})
						Verify.expect((presented:peek())):toBe(true)
						find(world.screen, "DismissOutside").Activated:Fire()
						Verify.expect((presented:peek())):toBe(true)
						Verify.expect(find(actions, "OK").Text):toBe("OK")
						find(actions, "OK").Activated:Fire()
						Verify.expect((presented:peek())):toBe(false)
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"refuses misspelled alert fields, duplicate action ids, two cancel actions and malformed transitions",
			{
				id = "native_parity_navigation::native parity navigation::refuses misspelled alert fields, duplicate action ids, two cancel actions and malformed transitions",
				run = function()
					Verify.expect((refuses("unknown option 'paddding'", function(UI: FacetControls)
						return UI.Alert({ isPresented = Compose.cell(false), title = "T", paddding = 12 })
					end))):toBe(true)
					Verify.expect(
						(
							refuses("Alert.transition supports source, seconds, ease", function(UI: FacetControls)
								return UI.Alert(
									{ isPresented = Compose.cell(false), title = "T", transition = { enter = "fade" } } :: any
								)
							end)
						)
					)
						:toBe(true)
					for _, transition in { "instant", 7 } :: { any } do
						Verify.expect((refuses("Alert transition must be a table or false", function(UI: FacetControls)
							return UI.Alert({ isPresented = Compose.cell(false), title = "T", transition = transition })
						end))):toBe(true)
					end
					for _, case in
						{
							{
								"Alert actions require unique ids",
								{ { id = "a", label = "A" }, { id = "a", label = "B" } },
							},
							{
								"Alert accepts one cancel action",
								{
									{ id = "a", label = "A", role = "cancel" :: "cancel" },
									{ id = "b", label = "B", role = "cancel" :: "cancel" },
								},
							},
						} :: { { any } }
					do
						local failures = {}
						local presented = Compose.cell(true)
						local world = setup(function(UI: FacetControls)
							return UI.Alert("Broken")({ isPresented = presented, title = "T", actions = case[2] })
						end, {
							onError = function(failure)
								table.insert(failures, tostring(failure))
							end,
						})
						Verify.expect(#failures):toBe(1)
						Verify.expect(string.find(failures[1], case[1], 1, true) ~= nil):toBe(true)
						Verify.expect((presented:peek())):toBe(false)
						Verify.expect((find(world.screen, "AlertPanel"))):toBeNil()
						world.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"lays out alert actions in a row with the cancel action first and stacks them for long labels",
			{
				id = "native_parity_navigation::native parity navigation::lays out alert actions in a row with the cancel action first and stacks them for long labels",
				run = function()
					local presented = Compose.cell(true)
					local world = setup(function(UI: FacetControls)
						return UI.Alert({
							isPresented = presented,
							title = "Leave?",
							message = "Progress is saved.",
							actions = {
								{ id = "Cancel", label = "Cancel", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
								{ id = "Accept", label = "Accept" } :: FixtureNavigationTypes.AlertAction<any>,
							},
						})
					end)
					local Enum = world.engine.types.Enum
					local modal = find(world.screen, "AlertModal")
					local actions = find(world.screen, "Actions")
					local layout = actions:FindFirstChildWhichIsA("UIListLayout")
					local cancel, accept = find(actions, "Cancel"), find(actions, "Accept")
					modal.AbsoluteSize = V2(world, 1280, 800)
					Verify.expect(layout.FillDirection):toBe(Enum.FillDirection.Horizontal)
					Verify.expect(cancel.LayoutOrder < accept.LayoutOrder):toBe(true)
					local constraint = find(world.screen, "AlertPanel"):FindFirstChildWhichIsA("UISizeConstraint")
					Verify.expect(constraint.MaxSize.X):toBe(440)
					world.gui.SelectedObject = cancel
					modal.AbsoluteSize = V2(world, 360, 640)
					Verify.expect(layout.FillDirection):toBe(Enum.FillDirection.Vertical)
					Verify.expect((find(actions, "Cancel"))):toBe(cancel)
					Verify.expect((find(actions, "Accept"))):toBe(accept)
					Verify.expect(world.gui.SelectedObject):toBe(cancel)
					Verify.expect(cancel.LayoutOrder > accept.LayoutOrder):toBe(true)
					Verify.expect(cancel.Size):toBe(world.engine.types.UDim2.new(1, 0, 0, 44))
					modal.AbsoluteSize = V2(world, 900, 700)
					Verify.expect(layout.FillDirection):toBe(Enum.FillDirection.Horizontal)
					Verify.expect(cancel.LayoutOrder):toBe(0)
					for _, button in { cancel, accept } do
						button.TextBounds = V2(world, 220, 20)
					end
					Verify.expect(layout.FillDirection):toBe(Enum.FillDirection.Vertical)
					for _, button in { cancel, accept } do
						button.TextBounds = V2(world, 60, 20)
					end
					Verify.expect(layout.FillDirection):toBe(Enum.FillDirection.Horizontal)
					Verify.expect(world.gui.SelectedObject):toBe(cancel)
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"grows an alert message to its content when the card has room and bounds it when it does not",
			{
				id = "native_parity_navigation::native parity navigation::grows an alert message to its content when the card has room and bounds it when it does not",
				run = function()
					local world = setup(function(UI: FacetControls)
						return UI.Alert({
							isPresented = Compose.cell(true),
							title = "Saved",
							message = "Short",
							actions = { { id = "OK", label = "OK" } :: FixtureNavigationTypes.AlertAction<any> },
						})
					end)
					find(world.screen, "AlertModal").AbsoluteSize = V2(world, 390, 844)
					find(world.screen, "Actions").AbsoluteSize = V2(world, 320, 44)
					local content = find(world.screen, "AlertContent")
					local scroll = find(world.screen, "AlertMessage")
					Verify.expect(find(scroll, "UIListLayout") ~= nil):toBe(true)
					local flow = content.Parent
					flow.AbsoluteSize = V2(world, 320, 120)
					Verify.expect(scroll.Size.Y.Offset):toBe(120)
					for _ = 1, 30 do
						world.engine.heartbeat:Fire(1 / 60)
					end
					flow.AbsoluteSize = V2(world, 320, 2000)
					Verify.expect(scroll.Size.Y.Offset):toBe(844 - 44 - 40 - 40)
					world.stop()
				end,
			}
		)

		verifyHarness:case(
			"mounts an alert title only while it has visible text and wraps a long title across the card",
			{
				id = "native_parity_navigation::native parity navigation::mounts an alert title only while it has visible text and wraps a long title across the card",
				run = function()
					local title = Compose.cell(" ")
					local world = setup(function(UI: FacetControls)
						return UI.Alert({ isPresented = Compose.cell(true), title = title, message = "Body" })
					end)
					Verify.expect((find(world.screen, "Title"))):toBeNil()
					Verify.expect(find(world.screen, "Message") ~= nil):toBe(true)
					title:set("Hi")
					Verify.expect(find(world.screen, "Title").Text):toBe("Hi")
					title:set("")
					Verify.expect((find(world.screen, "Title"))):toBeNil()
					title:set(string.rep("A very long title ", 12))
					local heading = find(world.screen, "Title")
					Verify.expect(heading.TextWrapped):toBe(true)
					Verify.expect(heading.Size.X.Scale):toBe(1)
					Verify.expect((heading:HasTag("facet-type-heading"))):toBe(true)
					world.stop()
				end,
			}
		)

		verifyHarness:case("releases an open alert with its owner and returns selection to the opener", {
			id = "native_parity_navigation::native parity navigation::releases an open alert with its owner and returns selection to the opener",
			run = function()
				local show = Compose.cell(false)
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						UI.Button("Opener")({ label = "Open" }) :: unknown,
						Compose.show(show, function()
							return UI.Alert({
								isPresented = Compose.cell(true),
								title = "Leave?",
								actions = {
									{ id = "Stay", label = "Stay", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
								},
							})
						end),
					})
				end)
				world.gui.SelectedObject = find(world.screen, "Opener")
				local baseline = world.engine.census()
				for _ = 1, 5 do
					show:set(true)
					Verify.expect(world.gui.SelectedObject.Name):toBe("Stay")
					show:set(false)
					Verify.expect(world.gui.SelectedObject.Name):toBe("Opener")
				end
				Verify.expect((find(world.screen, "AlertModal"))):toBeNil()
				Verify.expect(#contexts(world.screen, "ModalBack")):toBe(0)
				local after = world.engine.census()
				Verify.expect(after.live):toBe(baseline.live)
				Verify.expect(after.connections):toBe(baseline.connections)
				world.stop()
			end,
		})
		verifyHarness:case(
			"opens each menu scenario card only through its printed routes and runs nothing from the blocked card",
			{
				id = "native_parity_navigation::native parity navigation::opens each menu scenario card only through its printed routes and runs nothing from the blocked card",
				run = function()
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
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
						Host = (runtime.constructors :: unknown) :: RobloxHost,
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
								motionLevel = "none",
							} :: any
						),
					}
					local scenario = require("../examples/gallery/scenarios/menu")
					local built
					local stop, screen: any = runtime.mount(function()
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
							back.Pressed:Fire()
						end
					end
					for _, card in { "Tap", "Chord", "Secondary", "Hold", "Blocked" } do
						local node = trigger(card)
						Verify.expect(node.ClassName):toBe("TextButton")
						Verify.expect(node.Selectable):toBe(true)
						Verify.expect(node.Size.Y.Offset >= 44):toBe(true)
					end
					trigger("Tap").Activated:Fire()
					Verify.expect(built.report().counts.Tap):toBe(1)
					close()
					trigger("Chord").Activated:Fire()
					Verify.expect((find(screen, "MenuPanel"))):toBeNil()
					trigger("Chord").InputBegan:Fire({
						UserInputType = Enum.UserInputType.MouseButton2,
						Position = engine.types.Vector3.new(50, 50, 0),
					})
					Verify.expect(built.report().counts.Chord):toBeNil()
					gui.SelectedObject = trigger("Chord")
					action(screen, "Menu").Pressed:Fire()
					Verify.expect(built.report().counts.Chord):toBe(1)
					close()
					trigger("Secondary").Activated:Fire()
					Verify.expect(built.report().counts.Secondary):toBeNil()
					trigger("Secondary").InputBegan:Fire({
						UserInputType = Enum.UserInputType.MouseButton2,
						Position = engine.types.Vector3.new(50, 50, 0),
					})
					Verify.expect(built.report().counts.Secondary):toBe(1)
					close()
					trigger("Hold").TouchLongPress:Fire({}, Enum.UserInputState.Begin)
					Verify.expect(built.report().counts.Hold):toBe(1)
					close()
					Verify.expect(built.report().counts.Tap):toBe(1)
					local ran = built.report().ran
					trigger("Blocked").Activated:Fire()
					local panel = find(screen, "MenuPanel")
					Verify.expect(panel ~= nil):toBe(true)
					for _, id in { "save", "share", "delete" } do
						local row = find(panel, id)
						Verify.expect(row.Interactable):toBe(false)
						row.Activated:Fire()
					end
					Verify.expect(built.report().ran):toBe(ran)
					Verify.expect((find(screen, "MenuPanel"))):toBe(panel)
					close()
					local copy: { string } = {}
					for _, value in scenario.copy do
						table.insert(copy, tostring(value))
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
							Verify.expect(covered):toBe(true)
						end
					end
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case(
			"keeps the callout scenario reset chip on screen at the 44 pixel floor and resets the session",
			{
				id = "native_parity_navigation::native parity navigation::keeps the callout scenario reset chip on screen at the 44 pixel floor and resets the session",
				run = function()
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local gui = engine.new("GuiService")
					local target = engine.new("Folder")
					local ctx = {
						Facet = Facet,
						Compose = Compose,
						runtime = runtime,
						Host = (runtime.constructors :: unknown) :: RobloxHost,
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
								motionLevel = "none",
							} :: any
						),
					}
					local built
					local stop, screen: any = runtime.mount(function()
						built = require("../examples/gallery/scenarios/callout").build(ctx)
						return ctx.Host.ScreenGui({ built.screen() })
					end, target)
					local initial = built.report().tip.state
					find(screen, "Show").Activated:Fire()
					Verify.expect(built.report().tip.state ~= initial):toBe(true)
					local reset = find(screen, "Reset")
					Verify.expect(reset.Visible):toBe(true)
					Verify.expect(reset.Size.Y.Offset >= 44):toBe(true)
					reset.Activated:Fire()
					Verify.expect(built.report().tip.state):toBe(initial)
					stop()
					runtime:dispose()
				end,
			}
		)
		verifyHarness:case("scrolls an overflowing top tab strip from its leading edge with no rail scrollbar", {
			id = "native_parity_navigation::native parity navigation::scrolls an overflowing top tab strip from its leading edge with no rail scrollbar",
			run = function()
				local world = setup(function(UI: FacetControls, Host: RobloxHost)
					return UI.TabView({
						selection = Compose.cell("progress"),
						placement = "topBar" :: "topBar",
						tabs = {
							{
								id = "progress",
								label = "Progress",
								content = function(): Instance
									return Host.Frame({})
								end,
							} :: FixtureNavigationTypes.Tab,
							{
								id = "levels",
								label = "Levels",
								content = function(): Instance
									return Host.Frame({})
								end,
							} :: FixtureNavigationTypes.Tab,
						},
					})
				end)
				local V2 = world.engine.types.Vector2
				local bar = find(world.screen, "Tabs")
				local strip = bar:FindFirstChildWhichIsA("UIListLayout")
				Verify.expect(bar.ScrollBarThickness):toBe(0)
				bar.AbsoluteSize = V2.new(389, 44)
				strip.AbsoluteContentSize = V2.new(300, 42)
				Verify.expect(strip.HorizontalAlignment):toBe(world.engine.types.Enum.HorizontalAlignment.Center)
				strip.AbsoluteContentSize = V2.new(468, 42)
				Verify.expect(strip.HorizontalAlignment):toBe(world.engine.types.Enum.HorizontalAlignment.Left)
				world.stop()
			end,
		})
	end)
end
