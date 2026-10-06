--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local glade = require("../examples/reference/p1_glade")
	local sipworks = require("../examples/reference/p3_sipworks")
	local foyer = require("../examples/reference/p4_foyer")
	local Compose: ComposeModule = Facet.Compose

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

	local measured = require("./lib/hud_measure")

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
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui, input = services(engine)
		input.PreferredInput = (engine.types.Enum.PreferredInput :: any)[preferred]
		local parent = engine.new("Folder")
		local built
		local stop, root: any = runtime.mount(function()
			built = module.build({
				Facet = Facet,
				Compose = Compose,
				runtime = runtime,
				Host = (runtime.constructors :: unknown) :: RobloxHost,
				UI = Facet.controls(
					runtime,
					{
						types = engine.types,
						guiService = gui,
						inputParent = parent,
						motionLevel = "none",
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
		Verify.expect(w.gui.SelectedObject):toBe(start)
		return seen
	end

	local function galleryWorld(configure: ((any) -> ())?): any
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui, input = services(engine)
		local parent = engine.new("Folder")
		local ctx: any = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = (runtime.constructors :: unknown) :: RobloxHost,
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
			demos = {
				{ id = "all-controls", title = "All controls", kind = "fixture" :: "fixture", module = "all_controls" },
			},
			load = function(_, module)
				return (require :: any)("../examples/gallery/scenarios/" .. module)
			end,
		}
		ctx.packages = { Neutral = ctx.theme:peek() }
		if configure then
			configure(ctx)
		end
		local gallery = require("../examples/gallery/client/screen")
		local stop, root: any = runtime.mount(function()
			gallery.configure(ctx)
			ctx.UI = Facet.controls(
				runtime,
				{
					types = engine.types,
					environment = ctx.environment,
					viewport = ctx.viewport,
					inputParent = parent,
					guiService = gui,
					services = { GuiService = gui, UserInputService = input },
					theme = ctx.theme,
					motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
						return if ctx.reducedMotion and use(ctx.reducedMotion) then "none" else "normal"
					end) :: unknown) :: MotionLevel,
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
			return { UserInputType = E.UserInputType.MouseButton1, KeyCode = E.KeyCode:FromValue(0) }
		elseif kind == "touch" then
			return { UserInputType = E.UserInputType.Touch, KeyCode = E.KeyCode:FromValue(0) }
		elseif kind == "gamepad" then
			return { UserInputType = E.UserInputType.Gamepad1, KeyCode = E.KeyCode.ButtonA }
		end
		return { UserInputType = E.UserInputType.Keyboard, KeyCode = E.KeyCode.Return }
	end

	local function scenarioWorld(name: string, options: any?): (any, any, any)
		local opts = options or {}
		local engine: any = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
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
			Host = (runtime.constructors :: unknown) :: RobloxHost,
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
		local stop, root: any = runtime.mount(function()
			gallery.configure(ctx)
			ctx.motionPreference:set("none")
			ctx.UI = Facet.controls(
				runtime,
				{
					types = engine.types,
					environment = ctx.environment,
					viewport = ctx.viewport,
					guiService = gui,
					inputParent = parent,
					services = { GuiService = gui, UserInputService = service },
					theme = theme,
					motionLevel = "none",
				} :: any
			)
			local sheet = Facet.themes.createStyleSheet(runtime, theme, { types = engine.types })
			built = definition.build(ctx)
			if built.dispose then
				Compose.cleanup(built.dispose)
			end
			return ctx.Host.ScreenGui "Screen" {
				sheet :: unknown,
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
				Verify.expect(`{label} {layout.FillDirection.Name} {bar.Position.X.Offset}`):toBe(`{label} Vertical 8`)
				Verify.expect(pages.Position.X.Offset > 0):toBe(true)
			elseif label == "topBar" then
				Verify.expect(`{label} {layout.FillDirection.Name} {bar.Position.Y.Scale}`):toBe(`{label} Horizontal 0`)
				Verify.expect(pages.Position.Y.Offset):toBe(52)
			else
				Verify.expect(`{label} {layout.FillDirection.Name} {bar.Position.Y.Scale} {bar.Position.Y.Offset}`)
					:toBe(`{label} Horizontal 1 -44`)
			end
			Verify.expect(layout.SortOrder):toBe(E.SortOrder.LayoutOrder)
			local buttons = {}
			for index, id in ids do
				local button = assert(find(bar, id, "TextButton"), `{label}: no {id} tab`)
				Verify.expect(`{label} {id} {button.Selectable} {button.Visible} {button.Interactable}`)
					:toBe(`{label} {id} true true true`)
				Verify.expect(button.LayoutOrder):toBe(index)
				buttons[index] = button
			end
			local forward = if label == "sidebar" then "NextSelectionDown" else "NextSelectionRight"
			local backward = if label == "sidebar" then "NextSelectionUp" else "NextSelectionLeft"
			for index, button in buttons do
				Verify.expect(`{label} {ids[index]} {forward} {(button :: any)[forward] == buttons[index + 1]}`)
					:toBe(`{label} {ids[index]} {forward} true`)
				Verify.expect(`{label} {ids[index]} {backward} {(button :: any)[backward] == buttons[index - 1]}`)
					:toBe(`{label} {ids[index]} {backward} true`)
			end
			Verify.expect(w.gui.SelectedObject):toBe(nil)
			pad(w, "DPadDown")
			Verify.expect(w.gui.SelectedObject):toBe(buttons[1])
			local stops = ring(w)
			for index, button in buttons do
				Verify.expect(`{label} ring {ids[index]} {table.find(stops, button) ~= nil}`)
					:toBe(`{label} ring {ids[index]} true`)
			end
			local content = 0
			for _, stop in stops do
				if within(stop, pages) then
					content += 1
				end
				Verify.expect(stop.Selectable and stop.Visible):toBe(true)
			end
			Verify.expect(`{label} content stops {content > 0}`):toBe(`{label} content stops true`)
			for step = 2, #buttons do
				Verify.expect(table.find(stops, buttons[step]) > table.find(stops, buttons[step - 1])):toBe(true)
			end
			local cell = cellOf(w.built)
			for index = #ids, 1, -1 do
				local id = ids[index]
				w.gui.SelectedObject = buttons[index]
				Verify.expect(w.gui.SelectedObject):toBe(buttons[index])
				buttons[index].Activated.fire()
				Verify.expect(`{label} {cell:peek()}`):toBe(`{label} {id}`)
				local panel = assert(pages:FindFirstChild(id, true), `{label}: no {id} page`)
				Verify.expect(panel.Visible):toBe(true)
				local selected = w.gui.SelectedObject
				Verify.expect(`{label} {id} away {within(selected, panel) or selected == buttons[index]}`)
					:toBe(`{label} {id} away true`)
			end
			Verify.expect(#w.engine.rejectedSelections):toBe(0)
			open(w.built)
			local sheet = assert(find(w.screen, "SheetPanel"), `{label}: no sheet`)
			local inside = ring(w)
			local close
			for _, stop in inside do
				Verify.expect(`{label} modal stop inside {within(stop, sheet)}`):toBe(`{label} modal stop inside true`)
				if stop.Name == "Close" or stop.Name == "Grabber" then
					close = stop
				end
			end
			Verify.expect(`{label} dismissal reachable {close ~= nil}`):toBe(`{label} dismissal reachable true`)
			find(w.parent, "ModalBack", "InputAction").Pressed.fire()
			Verify.expect((find(w.screen, "SheetPanel"))):toBeNil()
			w.stop()
		end
	end

	verifyHarness:suite("native parity weaker showcase", function()
		verifyHarness:case(
			"apps-24 Glade walks every nav placement: entry, the Tab ring, linked tab order, activation away and modal dismissal",
			{
				id = "native_parity_weaker_showcase::native parity weaker showcase::apps-24 Glade walks every nav placement: entry, the Tab ring, linked tab order, activation away and modal dismissal",
				run = function()
					walkPlacements(glade, function(built)
						return built.model.section
					end, { "glades", "favorites", "wisps", "flora", "keeper" }, function(built)
						built.steps.open("mossholm")
					end)
				end,
			}
		)

		verifyHarness:case(
			"apps-90 Sipworks walks every nav placement: entry, the Tab ring, linked tab order, activation away and modal dismissal",
			{
				id = "native_parity_weaker_showcase::native parity weaker showcase::apps-90 Sipworks walks every nav placement: entry, the Tab ring, linked tab order, activation away and modal dismissal",
				run = function()
					walkPlacements(sipworks, function(built)
						return built.model.section
					end, { "menu", "favorites", "rewards", "book" }, function(built)
						built.steps.open("lantern-oolong")
					end)
				end,
			}
		)

		verifyHarness:case(
			"apps-102 Foyer walks every nav placement: entry, the Tab ring, linked tab order, activation away and modal dismissal",
			{
				id = "native_parity_weaker_showcase::native parity weaker showcase::apps-102 Foyer walks every nav placement: entry, the Tab ring, linked tab order, activation away and modal dismissal",
				run = function()
					walkPlacements(foyer, function(built)
						return built.model.destination
					end, { "home", "crews", "forge", "mail", "you" }, function(built)
						built.steps.open("moss-kingdom")
					end)
				end,
			}
		)

		verifyHarness:case(
			"apps2-225 links each showcase strip tab to its declared neighbours at every stage size and preview so DPadRight cannot skip",
			{
				id = "native_parity_weaker_showcase::native parity weaker showcase::apps2-225 links each showcase strip tab to its declared neighbours at every stage size and preview so DPadRight cannot skip",
				run = function()
					local sizes = {
						{ device = "phone", width = 390, height = 844 },
						{ device = "tablet", width = 1024, height = 768 },
						{ device = "desktop", width = 1440, height = 900 },
						{ device = "tv", width = 1920, height = 1080 },
					}
					for _, size in sizes do
						local w = galleryWorld(function(ctx)
							ctx.viewport:set({ width = size.width, height = size.height })
						end)
						local scale = find(w.root, "ViewingDistance", "UIScale")
						for _, distance in { "automatic", "near", "ten-foot" } do
							w.ctx.viewingDistance:set(distance)
							Verify.expect(scale.Scale):toBe(1)
							Verify.expect((w.ctx.metricScale:peek():peek()))
								:toBe(if distance == "ten-foot" then 1.5 else 1)
							for _, input in { "Gamepad", "KeyboardAndMouse" } do
								w.input.PreferredInput = (w.engine.types.Enum.PreferredInput :: any)[input]
								for _, view in
									{ { "inputs", "basics", "writing" }, { "Categories", "inputs", "actions" } }
								do
									local buttons = strip(w.root, view[1])
									local label = `{size.device} {distance} {input} {view[1]}`
									Verify.expect(`{label} {buttons[1].Name} {buttons[2].Name}`)
										:toBe(`{label} {view[2]} {view[3]}`)
									for index, button in buttons do
										Verify.expect(
											`{label} {button.Name} right {button.NextSelectionRight == buttons[index + 1]}`
										):toBe(`{label} {button.Name} right true`)
										Verify.expect(
											`{label} {button.Name} left {button.NextSelectionLeft == buttons[index - 1]}`
										)
											:toBe(`{label} {button.Name} left true`)
										Verify.expect(button.NextSelectionUp == nil and button.NextSelectionDown == nil)
											:toBe(true)
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
									Verify.expect(`{label} {table.concat(walked, ",")}`)
										:toBe(`{label} {table.concat(names, ",")}`)
								end
							end
						end
						Verify.expect(#w.engine.rejectedSelections):toBe(0)
						w.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"apps2-225 relinks a strip when a tab is disabled or hidden and in a sidebar links vertically",
			{
				id = "native_parity_weaker_showcase::native parity weaker showcase::apps2-225 relinks a strip when a tab is disabled or hidden and in a sidebar links vertically",
				run = function()
					local engine: any = engineLib.new()
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local gui, input = services(engine)
					local UI = Facet.controls(
						runtime,
						{
							types = engine.types,
							guiService = gui,
							services = { GuiService = gui, UserInputService = input },
						} :: any
					)
					local Host = (runtime.constructors :: unknown) :: RobloxHost
					local selection, enabled = Compose.cell("a"), Compose.cell(true)
					local customization = Compose.cell(nil :: any)
					local stop, root: any = runtime.mount(function()
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
									} :: FixtureNavigationTypes.Tab,
									{
										id = "b",
										label = "B",
										enabled = enabled,
										content = function()
											return Host.Frame "BPage" {}
										end,
									} :: FixtureNavigationTypes.Tab,
									{
										id = "c",
										label = "C",
										content = function()
											return Host.Frame "CPage" {}
										end,
									} :: FixtureNavigationTypes.Tab,
								},
							},
						}
					end, engine.new("Folder"))
					local view = find(root, "Strip")
					view.AbsoluteSize = engine.types.Vector2.new(390, 844)
					local a, b, c =
						find(view, "a", "TextButton"), find(view, "b", "TextButton"), find(view, "c", "TextButton")
					Verify.expect(a.NextSelectionRight):toBe(b)
					Verify.expect(b.NextSelectionRight):toBe(c)
					Verify.expect(c.NextSelectionLeft):toBe(b)
					enabled:set(false)
					Verify.expect(a.NextSelectionRight):toBe(c)
					Verify.expect(c.NextSelectionLeft):toBe(a)
					Verify.expect(b.NextSelectionRight):toBe(nil)
					Verify.expect(b.NextSelectionLeft):toBe(nil)
					enabled:set(true)
					Verify.expect(a.NextSelectionRight):toBe(b)
					customization:set({ order = { "c", "a", "b" }, hidden = { "a" } })
					Verify.expect(c.NextSelectionRight):toBe(b)
					Verify.expect(b.NextSelectionLeft):toBe(c)
					Verify.expect(b.NextSelectionRight):toBe(nil)
					customization:set(nil)
					a = find(view, "a", "TextButton")
					view.AbsoluteSize = engine.types.Vector2.new(1400, 900)
					Verify.expect(a.NextSelectionDown):toBe(b)
					Verify.expect(b.NextSelectionUp):toBe(a)
					Verify.expect(b.NextSelectionDown):toBe(c)
					Verify.expect(a.NextSelectionRight):toBe(nil)
					Verify.expect(b.NextSelectionLeft):toBe(nil)
					stop()
					runtime:dispose()
				end,
			}
		)

		verifyHarness:case(
			"mech2-25 the Tab walk never stops on or under the powered-off panel, still reaches After and returns when on",
			{
				id = "native_parity_weaker_showcase::native parity weaker showcase::mech2-25 the Tab walk never stops on or under the powered-off panel, still reaches After and returns when on",
				run = function()
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
						Verify.expect(on.Go and on.InnerGo and on.After and on.PowerToggle):toBe(true)
						w.gui.SelectedObject = go
						power.Activated.fire(input(w, "keyboard"))
						Verify.expect(built.report().enabled):toBe(false)
						Verify.expect(w.gui.SelectedObject):toBe(after)
						local off = names()
						Verify.expect(off.Go == nil and off.InnerGo == nil):toBe(true)
						Verify.expect(off.After and off.PowerToggle):toBe(true)
						w.gui.SelectedObject = power
						tab(w)
						local guard = 0
						while w.gui.SelectedObject ~= after and guard < 40 do
							Verify.expect(w.gui.SelectedObject ~= go and w.gui.SelectedObject ~= inner):toBe(true)
							tab(w)
							guard += 1
						end
						Verify.expect(w.gui.SelectedObject):toBe(after)
						power.Activated.fire(input(w, "gamepad"))
						Verify.expect(built.report().enabled):toBe(true)
						local again = names()
						Verify.expect(again.Go and again.InnerGo):toBe(true)
						w.stop()
					end
				end,
			}
		)

		verifyHarness:case(
			"inputs-77 every input class requests the completed click once and a disabled demo requests nothing",
			{
				id = "native_parity_weaker_showcase::native parity weaker showcase::inputs-77 every input class requests the completed click once and a disabled demo requests nothing",
				run = function()
					local w, built, root = scenarioWorld("sensory_feedback")
					local release = find(root, "Release")
					for index, kind in
						{ "mouse", "touch", "gamepad", "keyboard" } :: { "gamepad" | "keyboard" | "mouse" | "touch" }
					do
						release.Activated.fire(input(w, kind))
						Verify.expect((built.requests:peek())):toBe(index)
						Verify.expect(built.effects.release.PlayCount):toBe(index)
						Verify.expect(built.steps.readHistory()[1]):toBe(`{index}. release`)
					end
					Verify.expect(built.effects.press.PlayCount == nil or built.effects.press.PlayCount == 0):toBe(true)
					Verify.expect(find(root, "Press").PressHapticEffect):toBe(built.effects.press)
					find(root, "Custom").Activated.fire(input(w, "gamepad"))
					Verify.expect(built.effects.custom.PlayCount):toBe(1)
					Verify.expect(built.report().motorConfirmed):toBe(false)
					built.steps.setPlayHaptics(false)
					for _, kind in
						{ "mouse", "touch", "gamepad", "keyboard" } :: { "gamepad" | "keyboard" | "mouse" | "touch" }
					do
						release.Activated.fire(input(w, kind))
					end
					Verify.expect((built.requests:peek())):toBe(5)
					Verify.expect(built.effects.release.PlayCount):toBe(4)
					Verify.expect(find(root, "Press").PressHapticEffect):toBe(nil)
					w.stop()
					for _, effect in built.effects do
						Verify.expect((effect.isDestroyed())):toBe(true)
					end
				end,
			}
		)

		local HUD_VIEWS = {
			{ device = "compact-phone-portrait", width = 359, height = 718, input = "Touch" },
			{ device = "compact-phone-landscape", width = 705, height = 338, input = "Touch" },
			{ device = "tablet-landscape", width = 1079, height = 809, input = "Touch" },
			{ device = "desktop-standard", width = 1232, height = 1067, input = "KeyboardAndMouse" },
			{ device = "console-ten-foot", width = 1920, height = 1078, input = "Gamepad" },
			{ device = "handheld-gamepad", width = 960, height = 540, input = "Gamepad" },
			{ device = "compact-gamepad", width = 390, height = 844, input = "Gamepad" },
			{ device = "narrow-portrait", width = 320, height = 640, input = "Touch" },
			{ device = "narrow-landscape", width = 640, height = 320, input = "Touch" },
			{ device = "desktop-studio-1320", width = 1320, height = 742, input = "KeyboardAndMouse" },
			{ device = "phone-390x844", width = 390, height = 844, input = "Touch" },
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

		verifyHarness:case(
			"mech2-90 mounts the HUD at main's eleven viewports, recovers every stepped-down zone and settles each rotation like a fresh mount",
			{
				id = "native_parity_weaker_showcase::native parity weaker showcase::mech2-90 mounts the HUD at main's eleven viewports, recovers every stepped-down zone and settles each rotation like a fresh mount",
				run = function()
					local fresh = {}
					local function box(view: any): { number }
						return { view.width - 16, view.height - 150 }
					end
					for _, view in HUD_VIEWS do
						local w, built, root = scenarioWorld("hud", {
							viewport = { width = view.width, height = view.height },
							input = view.input,
						})
						measured.measure(root, w.engine, box(view))
						local forms, unshown = built.report().forms, built.report().unshown
						local label = `{view.device} {view.width}x{view.height}`
						for _, zone in HUD_ZONES do
							local regions = 0
							for _, node in root:GetDescendants() do
								if node.Name == zone and node:GetAttribute("FacetForm") ~= nil then
									regions += 1
								end
							end
							Verify.expect(`{label} {zone} regions {regions}`):toBe(`{label} {zone} regions 1`)
							local expected = forms[zone] ~= "full"
							Verify.expect(`{label} {zone} unshown {table.find(unshown, zone) ~= nil}`)
								:toBe(`{label} {zone} unshown {expected}`)
						end
						built.steps.openOverflow()
						Verify.expect(built.report().overflowOpen):toBe(true)
						Verify.expect(`{label} recovered {hudShown(root)}`):toBe(`{label} recovered {#unshown}`)
						if #unshown == 0 then
							Verify.expect(find(root.Parent, "OverflowEmpty") ~= nil):toBe(true)
						end
						fresh[view.device] = forms
						w.stop()
						Verify.expect(#w.parent:GetChildren()):toBe(0)
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
						w.ctx.viewport:set({ width = view.width, height = view.height })
						measured.measure(root, w.engine, box(view))
						Verify.expect(`{view.device} rotated {same(built.report().forms, fresh[view.device])}`)
							:toBe(`{view.device :: unknown} rotated true`)
						for _, zone in HUD_ZONES do
							Verify.expect((find(root, zone))):toBe(regions[zone])
						end
					end
					w.stop()
				end,
			}
		)

		verifyHarness:case(
			"apps-208 a theme swap and the largest text re-run the HUD give-way from the new native body like a fresh mount there",
			{
				id = "native_parity_weaker_showcase::native parity weaker showcase::apps-208 a theme swap and the largest text re-run the HUD give-way from the new native body like a fresh mount there",
				run = function()
					local ornate = ((require :: any)("../examples/themes/fantasy_ornate").build(Facet.themes))
					local neutral = Facet.themes.neutralPackage()
					local function decided(theme: any, text: string?, body: { number }): any
						local w, built, root = scenarioWorld("hud", { theme = theme, text = text })
						measured.measure(root, w.engine, body)
						local forms = built.report().forms
						w.stop()
						return forms
					end
					for _, step in { { neutral, ornate }, { ornate, neutral } } do
						for _, bodies in { { { 1040, 640 }, { 330, 250 } }, { { 330, 250 }, { 1040, 640 } } } do
							local w, built, root = scenarioWorld("hud", { theme = step[1] })
							measured.measure(root, w.engine, bodies[1])
							local before = built.report().forms
							w.ctx.theme:set(step[2])
							Verify.expect((same(built.report().forms, before))):toBe(true)
							measured.measure(root, w.engine, bodies[2])
							local want = decided(step[2], nil, bodies[2])
							Verify.expect((same(want, before))):toBe(false)
							Verify.expect((same(built.report().forms, want))):toBe(true)
							w.gui.PreferredTextSize = w.engine.types.Enum.PreferredTextSize.Largest
							measured.measure(root, w.engine, bodies[1])
							Verify.expect((same(built.report().forms, decided(step[2], "Largest", bodies[1]))))
								:toBe(true)
							w.stop()
						end
					end
				end,
			}
		)

		verifyHarness:case(
			"mech3-59 mounts the HUD on a world-fixed SurfaceGui and decides from its canvas like a screen of that size",
			{
				id = "native_parity_weaker_showcase::native parity weaker showcase::mech3-59 mounts the HUD on a world-fixed SurfaceGui and decides from its canvas like a screen of that size",
				run = function()
					for _, canvas in { { 1024, 768 }, { 640, 480 }, { 320, 640 } } do
						local engine: any = engineLib.new()
						local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
						local gui, service = services(engine)
						local part, holder = engine.new("Part"), engine.new("Folder")
						local viewport = Compose.cell({ width = canvas[1], height = canvas[2] })
						local ctx: any = {
							Facet = Facet,
							Compose = Compose,
							runtime = runtime,
							Host = (runtime.constructors :: unknown) :: RobloxHost,
							types = engine.types,
							viewport = viewport,
							guiService = gui,
							inputService = service,
						}
						ctx.UI = Facet.controls(
							runtime,
							{
								types = engine.types,
								environment = ctx.environment,
								viewport = viewport,
								guiService = gui,
								services = { GuiService = gui, UserInputService = service },
							} :: any
						)
						local hud = require("../examples/gallery/scenarios/hud") :: any
						local built
						local stop, surface: any = runtime.mount(function()
							built = hud.build(ctx)
							return ctx.Host.SurfaceGui "HudSurface" {
								Adornee = part,
								Face = engine.types.Enum.NormalId.Front,
								SizingMode = engine.types.Enum.SurfaceGuiSizingMode.FixedSize,
								CanvasSize = engine.types.Vector2.new(canvas[1], canvas[2]),
								built.screen(),
							}
						end, holder)
						Verify.expect(surface.ClassName):toBe("SurfaceGui")
						Verify.expect(surface.CanvasSize.X):toBe(canvas[1])
						Verify.expect(surface.Adornee):toBe(part)
						local body = find(surface, "HudBody")
						Verify.expect(body ~= nil):toBe(true)
						local screenWorld, screenBuilt =
							scenarioWorld("hud", { viewport = { width = canvas[1], height = canvas[2] } })
						Verify.expect((same(built.report().forms, screenBuilt.report().forms))):toBe(true)
						body.AbsoluteSize = engine.types.Vector2.new(canvas[1] - 24, canvas[2] - 140)
						find(screenWorld.root, "HudBody").AbsoluteSize =
							V2(screenWorld, canvas[1] - 24, canvas[2] - 140)
						Verify.expect((same(built.report().forms, screenBuilt.report().forms))):toBe(true)
						screenWorld.stop()
						built.steps.openOverflow()
						Verify.expect(built.report().overflowOpen):toBe(true)
						Verify.expect(find(surface, "OverflowBody") ~= nil):toBe(true)
						local signal = body:GetPropertyChangedSignal("AbsoluteSize")
						stop()
						runtime:dispose()
						Verify.expect((surface.isDestroyed())):toBe(true)
						Verify.expect(#holder:GetChildren()):toBe(0)
						Verify.expect((signal.count())):toBe(0)
					end
				end,
			}
		)
	end)
end
