--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Bdd = require("../tools/vendor/verify/src/bdd")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")
local task = require("@std/task")

return function(verifyHarness: Verify.Harness)
	local test = Bdd.create(verifyHarness)
	local describe, it, expect = test.describe, test.it, test.expect
	local Facet = require("../src")
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ExampleContext = typeof(require("@repo/examples/types").Context)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local requireDynamic = require :: (any) -> any
	type Use = Facet.Use

	local engineLib = require("./lib/native_engine")
	local catalogue = require("../examples/gallery/client/demo_picker")
	local gallery = require("../examples/gallery/client/screen")
	local Compose: ComposeModule = Facet.Compose

	local function configureControls(ctx: ExampleContext): ()
		ctx.UI = Facet.controls(ctx.runtime, {
			types = ctx.types,
			viewport = ctx.viewport,
			guiService = ctx.guiService,
			motionLevel = Compose.formula(function(use: Use): "normal" | "limited" | "none"
				return if ctx.reducedMotion and use(ctx.reducedMotion) then "none" else "normal"
			end),
		})
	end

	local function nativeContext(width: number?, height: number?)
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local viewport = Compose.cell({ width = width or 1280, height = height or 720 })
		local target = engine.new("Folder")
		local guiService = engine.new("GuiService")
		local ctx: any = {
			UI = nil,
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = Facet.host(runtime),
			types = engine.types,
			viewport = viewport,
			inputTarget = target,
			worldTarget = engine.new("Folder"),
			guiService = guiService,
			runService = { Heartbeat = engine.heartbeat },
		}
		local scope: ExampleContext = ctx
		configureControls(scope)
		return ctx, engine, target
	end

	local function load(kind: string, name: string)
		return requireDynamic(
			"../examples/gallery/" .. (if kind == "example" then "examples/" else "scenarios/") .. name
		)
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

	local function capture<G>(build: (ExampleContext) -> G)
		local current: G? = nil
		return function(ctx: ExampleContext): G
			local result = build(ctx)
			current = result
			return result
		end, function(): G
			return assert(current)
		end
	end

	type Screen = { read screen: () -> Instance, read dispose: (() -> ())? }
	local function mountExample<G>(definition: { read build: (ExampleContext) -> G & Screen })
		local ctx, engine, target = nativeContext()
		local built: (G & Screen)? = nil
		local scope: ExampleContext = ctx
		local runtime: Facet.Runtime = ctx.runtime
		local stop, node = runtime.mount(function(): Instance
			gallery.configure(scope)
			configureControls(scope)
			local result = definition.build(scope)
			built = result
			if result.dispose then
				Compose.cleanup(result.dispose)
			end
			return result.screen()
		end, target)
		return assert(built), node, stop, ctx, engine, target
	end

	describe("native gallery", function()
		it("recreates Sipworks ingredients after collapse without losing gathered state", function(own)
			local built, root, stop, ctx, engine = mountExample(require("../examples/gallery/examples/14_sipworks"))
			own(function()
				stop()
				ctx.runtime:dispose()
			end)
			built.open("lantern-oolong")
			for _ = 1, 60 do
				engine.heartbeat:Fire(1 / 60)
			end
			local original = assert(find(root, "Gather_oolong"))
			local header = assert(find(find(root, "Ingredients"), "Header"))
			original.Activated:Fire()
			header.Activated:Fire()
			for _ = 1, 60 do
				engine.heartbeat:Fire(1 / 60)
			end
			header.Activated:Fire()
			for _ = 1, 60 do
				engine.heartbeat:Fire(1 / 60)
			end
			local replacement = assert(find(root, "Gather_oolong"))
			expect(replacement == original):toBe(false)
			expect(find(root, "FacetError")):toBe(nil)
			expect(replacement:GetAttribute("selected")):toBe(true)
		end)
		it("styles a route load failure with the theme text role", {
			id = "native_gallery::native gallery::styles a route load failure with the theme text role",
			run = function()
				local ctx, engine, target = nativeContext()
				ctx.selection = Compose.cell("broken")
				ctx.demos = { { id = "broken", title = "Missing demo", kind = "example", module = "missing" } }
				ctx.theme = Compose.cell(Facet.themes.neutralPackage())
				ctx.themeMode = Compose.cell("dark")
				ctx.packages = { Neutral = ctx.theme:peek() }
				ctx.load = function()
					error("module is not shipped")
				end
				local scope: ExampleContext = ctx
				local runtime: Facet.Runtime = ctx.runtime
				local stop, root: any = runtime.mount(function(): Instance
					return scope.Host.ScreenGui { gallery.build(scope) }
				end, target)
				local failure = assert(find(root, "DemoFailure"))
				expect((failure:HasTag("facet-type-body"))):toBe(true)
				expect(string.find(failure.Text, "could not load", 1, true) ~= nil):toBe(true)
				stop()
				ctx.runtime:dispose()
			end,
		})
		it("numbered places list and load only their own shipped demo", {
			id = "native_gallery::native gallery::numbered places list and load only their own shipped demo",
			run = function()
				for number = 1, 7 do
					local demos = catalogue.list(number)
					expect(#demos):toBe(1)
					local selected = catalogue.boot(nil, nil, number)
					expect(demos[1].id):toBe(selected)
					for _, demo in demos do
						expect(demo.kind):toBe("example")
						local definition: { read build: (ExampleContext) -> Screen } = load("example", demo.module)
						local built, _, stop = mountExample(definition)
						expect(built ~= nil):toBe(true)
						stop()
					end
				end
			end,
		})
		it("switches the entire gallery catalogue through one native root", {
			id = "native_gallery::native gallery::switches the entire gallery catalogue through one native root",
			run = function()
				for _, size in { { 389, 762 }, { 430, 932 }, { 1280, 720 } } do
					local ctx, engine, target = nativeContext(size[1], size[2])
					ctx.selection = Compose.cell("garage")
					ctx.themeMode = Compose.cell("light")
					ctx.theme = Compose.cell(Facet.themes.neutralPackage())
					ctx.packages = { Neutral = ctx.theme:peek() }
					ctx.load = load
					local sheet: StyleSheet? = nil
					local scope: ExampleContext = ctx
					local runtime: Facet.Runtime = ctx.runtime
					local stop, gui = runtime.mount(function(): Instance
						sheet = Facet.themes.createStyleSheet(
							ctx.runtime,
							ctx.theme,
							{ types = ctx.types, theme = ctx.themeMode }
						)
						return scope.Host.ScreenGui "FacetGallery" {
							sheet,
							scope.Host.StyleLink { StyleSheet = Compose.static(sheet) },
							require("../examples/gallery/client/screen").build(scope),
						}
					end, target)
					local root = find(gui, "Gallery")
					expect(assert(sheet).Parent):toBe(gui)
					expect(find(gui, "StyleLink").StyleSheet):toBe(sheet)
					local navigation = find(root, "Demos")
					expect(find(navigation, "Tabs").Visible):toBe(false)
					local button = find(find(root, "Toolbar"), "Showcase")
					for _, node in find(root, "Toolbar"):GetDescendants() do
						expect(node:IsA("TextLabel") and node.Text == "Facet gallery"):toBe(false)
					end
					local function pick(id: string)
						button.Activated:Fire()
						local row = find(gui, "Demo-" .. id)
						if row == nil then
							error("no demo row " .. id)
						end
						row.Activated:Fire()
					end
					for _, demo in catalogue.list() do
						pick(demo.id)
						Verify.awaitValue(
							function()
								return if ctx.active:peek() == demo.id or ctx.errorMessage:peek() ~= nil
									then true
									else nil
							end,
							5,
							0.01,
							{
								now = os.clock,
								sleep = function(seconds)
									task.wait(seconds)
								end,
							}
						)
						engine.heartbeat:Fire(1 / 60)
						expect(`selected {ctx.selection:peek()}`):toBe(`selected {demo.id}`)
						expect(`active {ctx.active:peek()}; error {ctx.errorMessage:peek()}`):toBe(
							`active {demo.id}; error nil`
						)
						expect((ctx.errorMessage:peek())):toBe(nil)
					end
					pick("garage")
					expect((ctx.active:peek())):toBe("garage")
					button.Activated:Fire()
					expect(find(gui, "Section") ~= nil):toBe(true)
					expect(find(gui, "DemoList") ~= nil):toBe(true)
					find(find(gui, "Section"), "settings").Activated:Fire()
					expect(find(gui, "Packages") ~= nil):toBe(true)
					expect((find(gui, "DemoList"))):toBe(nil)
					find(find(gui, "Section"), "demos").Activated:Fire()
					expect(#find(gui, "DemoList"):GetChildren() > #catalogue.list()):toBe(true)
					expect(find(gui, "Demo-garage").Parent):toBe(find(gui, "DemoList"))
					expect((find(gui, "SectionTitle"))):toBe(nil)
					stop()
					expect(#target:GetChildren()):toBe(0)
					ctx.runtime:dispose()
				end
			end,
		})
		it("types, submits and restarts the retained word game through native input", {
			id = "native_gallery::native gallery::types, submits and restarts the retained word game through native input",
			run = function()
				local built, node, stop, ctx, _, target =
					mountExample(require("../examples/gallery/examples/05_word_game"))
				local answer = built.solution()
				for i = 1, #answer do
					find(target, "Type_" .. answer:sub(i, i)).Pressed:Fire()
				end
				find(target, "Submit").Pressed:Fire()
				expect((built.won())):toBe(true)
				expect((built.resultsOpen())):toBe(true)
				expect((built.state(1, 1))):toBe("correct")
				expect((find(find(node, "tile1_1"), "fill"):HasTag("facet-status-success"))):toBe(true)
				built.restart()
				expect((built.phase())):toBe("playing")
				expect((built.row(1))):toBe("")
				stop()
				expect(#target:GetChildren()):toBe(0)
				ctx.runtime:dispose()
			end,
		})
		it("places and undoes a crossword rack tile without losing the rack", {
			id = "native_gallery::native gallery::places and undoes a crossword rack tile without losing the rack",
			run = function()
				local built, node, stop, ctx, engine =
					mountExample(require("../examples/gallery/examples/06_tile_game"))
				local letter = built.rackLetter(1)
				find(node, "rt1").Activated:Fire()
				find(find(node, "cell4_4"), "tap").Activated:Fire()
				expect((built.pendingAt(4, 4))):toBe(letter)
				expect((built.rackCount())):toBe(6)
				built.undo()
				expect((built.pendingAt(4, 4))):toBe(nil)
				expect((built.rackCount())):toBe(7)
				stop()
				ctx.runtime:dispose()
			end,
		})
		it("runs a match-three drag and releases its native frame subscription", {
			id = "native_gallery::native gallery::runs a match-three drag and releases its native frame subscription",
			run = function()
				local built, node, stop, ctx, engine = mountExample(require("../examples/gallery/examples/07_match3"))
				local tile = find(node, "tile" .. assert(built.tileIdAt(1, 1)))
				local drag = find(tile, "SwapDrag")
				drag.DragStart:Fire(ctx.types.Vector2.zero)
				drag.DragContinue:Fire(ctx.types.Vector2.new(30, 0))
				drag.DragEnd:Fire()
				expect((built.isResolving())):toBe(true)
				for _ = 1, 240 do
					engine.heartbeat:Fire(1 / 30)
				end
				expect((built.isResolving())):toBe(false)
				expect((built.hasLegalMove())):toBe(true)
				expect((built.tickHookActive())):toBe(false)
				built.swap(1, 1, 1, 2)
				expect((built.tickHookActive())):toBe(true)
				stop()
				expect((built.tickHookActive())):toBe(false)
				ctx.runtime:dispose()
			end,
		})
		it("retains optimistic settings and rolls back rejected server data", {
			id = "native_gallery::native gallery::retains optimistic settings and rolls back rejected server data",
			run = function()
				local built, node, stop, ctx, engine =
					mountExample(require("../examples/gallery/examples/03_settings_sync"))
				find(node, "Music").Activated:Fire()
				expect(built.report().draft.music):toBe(true)
				expect(built.report().server.music):toBe(false)
				find(node, "Deliver").Activated:Fire()
				expect(built.report().server.music):toBe(true)
				find(node, "Invalid").Activated:Fire()
				expect(built.report().draft.volume):toBe(99)
				find(node, "Deliver").Activated:Fire()
				expect(built.report().status):toBe("rejected")
				expect(built.report().draft.volume):toBe(10)
				stop()
				ctx.runtime:dispose()
			end,
		})

		it("selects a playlist row on one click and plays it on a double click or Return", {
			id = "native_gallery::native gallery::selects a playlist row on one click and plays it on a double click or Return",
			run = function()
				local built, node, stop, ctx, engine =
					mountExample(require("../examples/gallery/examples/02_playlist_table"))
				engine.environment.poke(find(node, "Body"), "AbsoluteWindowSize", ctx.types.Vector2.new(600, 400))
				local hit = find(node, "RowHit")
				local row = find(hit.Parent, "Row")
				local E = ctx.types.Enum
				local mouse = { UserInputType = E.UserInputType.MouseButton1, KeyCode = E.KeyCode:FromValue(0) }
				hit.Activated:Fire(mouse, 1)
				expect((built.nowPlaying:peek())):toBe(nil)
				expect((row:GetAttribute("FacetSelected"))):toBe(true)
				hit.Activated:Fire(mouse, 1)
				expect((built.nowPlaying:peek())):toBe(nil)
				hit.Activated:Fire(mouse, 2)
				local playing = built.nowPlaying:peek()
				expect(playing ~= nil):toBe(true)
				built.nowPlaying:set(nil)
				hit.Activated:Fire({ UserInputType = E.UserInputType.Keyboard, KeyCode = E.KeyCode.Return }, 1)
				expect((built.nowPlaying:peek())):toBe(playing)
				built.nowPlaying:set(nil)
				hit.Activated:Fire({ UserInputType = E.UserInputType.Touch, KeyCode = E.KeyCode:FromValue(0) }, 1)
				expect((built.nowPlaying:peek())):toBe(playing)
				stop()
				ctx.runtime:dispose()
			end,
		})

		it("updates and removes the standalone consumer through its controls", {
			id = "native_gallery::native gallery::updates and removes the standalone consumer through its controls",
			run = function()
				local ctx, engine, target = nativeContext()
				local app =
					Facet.app({ runtime = ctx.runtime, types = ctx.types, parent = target, name = "FacetConsumer" })
				local stop, node: any = app.mount(function()
					return require("../examples/consumer/src/screen").build(Facet, app.UI)
				end)
				expect(node.Name):toBe("FacetConsumer")
				expect(find(node, "Panel").BackgroundTransparency):toBe(0)
				expect((find(node, "Panel"):HasTag("facet-surface"))):toBe(true)
				expect(assert(node):FindFirstChildWhichIsA("StyleLink").StyleSheet):toBe(
					node:FindFirstChildWhichIsA("StyleSheet")
				)
				find(node, "Bump").Activated:Fire()
				expect(find(node, "Count").Text):toBe("1 tap")
				find(node, "Close").Activated:Fire()
				expect((find(node, "Panel"))):toBe(nil)
				stop()
				expect(#target:GetChildren()):toBe(0)
				app.dispose()
				ctx.runtime:dispose()
			end,
		})
		it("requests native haptics and releases effects when the screen closes", {
			id = "native_gallery::native gallery::requests native haptics and releases effects when the screen closes",
			run = function()
				local ctx, engine, target = nativeContext()
				local waveforms: { [unknown]: { FloatCurveKey } } = {}
				engine.environment.onCreate(function(effect)
					if effect:IsA("HapticEffect") then
						engine.environment.fakeOn(
							VerifyRoblox.assertInstance(effect),
							"SetWaveformKeys",
							function(_, keys: { FloatCurveKey })
								waveforms[effect] = keys
							end
						)
					end
				end)
				local build, result = capture(require("../examples/gallery/scenarios/sensory_feedback").build)
				local scope: ExampleContext = ctx
				local runtime: Facet.Runtime = ctx.runtime
				local stop, node: any = runtime.mount(function(): Instance
					local built = build(scope)
					return built.screen()
				end, target)
				local built = result()
				local plays: { [unknown]: number } = {}
				local stops: { [unknown]: number } = {}
				for _, effect in built.effects do
					engine.environment.fakeOn(VerifyRoblox.assertInstance(effect), "Play", function()
						plays[effect] = (plays[effect] or 0) + 1
					end)
					engine.environment.fakeOn(VerifyRoblox.assertInstance(effect), "Stop", function()
						stops[effect] = (stops[effect] or 0) + 1
					end)
				end
				expect(find(node, "Press").PressHapticEffect):toBe(built.effects.press)
				find(node, "Release").Activated:Fire()
				expect(plays[built.effects.release]):toBe(1)
				expect((built.requests:peek())):toBe(1)
				find(node, "Selection").Activated:Fire()
				expect(plays[built.effects.selection]):toBe(1)
				find(node, "Custom").Activated:Fire()
				expect(plays[built.effects.custom]):toBe(1)
				expect(#waveforms[built.effects.custom]):toBe(5)
				expect((built.requests:peek())):toBe(3)
				built.playHaptics:set(false)
				for _, effect in built.effects do
					expect(stops[effect]):toBe(1)
				end
				expect(find(node, "Press").PressHapticEffect):toBe(nil)
				find(node, "Release").Activated:Fire()
				expect(plays[built.effects.release]):toBe(1)
				expect((built.requests:peek())):toBe(3)
				expect(built.report().motorConfirmed):toBe(false)
				stop()
				for _, effect in built.effects do
					expect(stops[effect]):toBe(2)
					expect(engine.environment.isAlive(VerifyRoblox.assertInstance(effect))):toBe(false)
				end
				ctx.runtime:dispose()
			end,
		})

		local maintained: { { read id: string, read kind: string, read module: string, read title: string?, read blurb: string? } } =
			{}
		for _, demo in catalogue.list() do
			table.insert(maintained, demo)
		end
		for _, demo in
			{
				{ id = "all-controls", kind = "fixture", module = "all_controls" },
				{ id = "collections", kind = "fixture", module = "collections" },
				{ id = "motion-layout", kind = "fixture", module = "motion_layout" },
				{ id = "radial-menu", kind = "fixture", module = "radial_menu" },
				{ id = "ex03", kind = "example", module = "03_settings_sync" },
				{ id = "ex05", kind = "example", module = "05_word_game" },
				{ id = "ex06", kind = "example", module = "06_tile_game" },
				{ id = "ex07", kind = "example", module = "07_match3" },
			} :: { { id: string, kind: string, module: string, title: string?, blurb: string? } }
		do
			table.insert(maintained, demo)
		end
		for _, demo in maintained do
		end
		for _, groupName in { "all_controls", "collections", "motion_layout" } do
			local group = load("fixture", groupName)
			for _, section in group.groups do
				for _, tab in section.tabs do
				end
			end
		end
		it("selects a nested all-controls tab by path through the showcase API", {
			id = "native_gallery::native gallery::selects a nested all-controls tab by path through the showcase API",
			run = function()
				local ctx, engine, target = nativeContext()
				local build, result = capture(require("../examples/gallery/scenarios/all_controls").build)
				local scope: ExampleContext = ctx
				local runtime: Facet.Runtime = ctx.runtime
				local stop = runtime.mount(function(): Instance
					local built = build(scope)
					return built.screen()
				end, target)
				local built = result()
				expect((built.select("actions"))):toBe(true)
				expect((built.select("actions/menus"))):toBe(true)
				expect(built.report().active):toBe("menus")
				expect((built.select("actions/nope"))):toBe(false)
				stop()
				ctx.runtime:dispose()
			end,
		})
		it("reserves the measured shell toolbar height above the demos", {
			id = "native_gallery::native gallery::reserves the measured shell toolbar height above the demos",
			run = function()
				local ctx, engine, target = nativeContext()
				ctx.selection = Compose.cell("garage")
				ctx.themeMode = Compose.cell("light")
				ctx.theme = Compose.cell(Facet.themes.neutralPackage())
				ctx.packages = { Neutral = ctx.theme:peek() }
				ctx.load = load
				local scope: ExampleContext = ctx
				local runtime: Facet.Runtime = ctx.runtime
				local stop, gui = runtime.mount(function(): Instance
					return scope.Host.ScreenGui "FacetGallery" {
						require("../examples/gallery/client/screen").build(scope),
					}
				end, target)
				local root = find(gui, "Gallery")
				local toolbar, demos = root:FindFirstChild("Toolbar"), root:FindFirstChild("Demos")
				local row = find(toolbar, "Row")
				expect(demos.Position.Y.Offset):toBe(56)
				engine.environment.poke(row, "AbsoluteSize", ctx.types.Vector2.new(390, 68))
				expect(demos.Position.Y.Offset):toBe(80)
				expect(demos.Size.Y.Offset):toBe(-80)
				expect(toolbar.Size.Y.Offset):toBe(80)
				engine.environment.poke(row, "AbsoluteSize", ctx.types.Vector2.new(390, 28))
				expect(demos.Position.Y.Offset):toBe(56)
				stop()
				ctx.runtime:dispose()
			end,
		})
		it("keeps action controls ordered responsive and interactive through native layout properties", {
			id = "native_gallery::native gallery::keeps action controls ordered responsive and interactive through native layout properties",
			run = function()
				local ctx, engine, target = nativeContext()
				local build, result = capture(require("../examples/gallery/scenarios/action_controls").build)
				local scope: ExampleContext = ctx
				local runtime: Facet.Runtime = ctx.runtime
				local stop, root = runtime.mount(function(): Instance
					local built = build(scope)
					return built.screen()
				end, target)
				local built = result()
				local toolbar = find(root, "Toolbar")
				expect(find(root, "Reset").Parent):toBe(toolbar)
				expect(find(root, "Enable").Parent):toBe(toolbar)
				expect(toolbar:FindFirstChildWhichIsA("UIListLayout").FillDirection):toBe(
					ctx.types.Enum.FillDirection.Horizontal
				)
				local sections = find(root, "Sections")
				local layout = sections:FindFirstChildWhichIsA("UIListLayout")
				expect(layout.FillDirection):toBe(ctx.types.Enum.FillDirection.Horizontal)
				expect(find(root, "Showroom").Size.X.Scale):toBe(0.5)
				expect(find(root, "Showroom").LayoutOrder):toBe(1)
				expect(find(root, "RaceSetup").LayoutOrder):toBe(2)
				expect(find(root, "Hero").AutomaticSize):toBe(ctx.types.Enum.AutomaticSize.Y)
				expect(find(root, "Hero"):FindFirstChildWhichIsA("UISizeConstraint").MinSize.Y):toBe(240)
				expect(find(root, "Driver1").AutomaticSize):toBe(ctx.types.Enum.AutomaticSize.None)
				expect(find(root, "Drivers"):FindFirstChildWhichIsA("UIGridLayout").CellSize.Y.Offset):toBe(240)
				expect(find(root, "Backgrounds"):FindFirstChildWhichIsA("UIGridLayout").CellSize.Y.Offset):toBe(260)
				expect(
					find(root, "Driver1"):FindFirstChild("Content"):FindFirstChildWhichIsA("UIListLayout").FillDirection
				):toBe(ctx.types.Enum.FillDirection.Vertical)
				ctx.viewport:set({ width = 600, height = 720 })
				expect(layout.FillDirection):toBe(ctx.types.Enum.FillDirection.Vertical)
				expect(find(root, "Showroom").Size.X.Scale):toBe(1)
				expect(find(root, "Drivers"):FindFirstChildWhichIsA("UIGridLayout").CellSize.X.Scale):toBe(1)
				expect((find(root, "Driver1"):GetAttribute("selected"))):toBe(false)
				find(root, "Driver1").Activated:Fire()
				expect(assert(built.report()).status):toBe("Classic driver selected.")
				expect((find(root, "Driver1"):GetAttribute("selected"))):toBe(true)
				expect((find(root, "Driver2"):GetAttribute("selected"))):toBe(false)
				find(root, "Enable").Activated:Fire()
				expect(find(root, "Save").Interactable):toBe(false)
				find(root, "Reset").Activated:Fire()
				find(root, "Save").Activated:Fire()
				expect(assert(built.report()).busy):toBe(true)
				engine.heartbeat:Fire(2)
				expect(assert(built.report()).busy):toBe(false)
				expect(assert(built.report()).status):toBe("Your race is ready.")
				find(root, "OverMediaAction").Activated:Fire()
				expect(assert(built.report()).status):toBe("Replay opened.")
				find(root, "RungLarge").Activated:Fire()
				expect(assert(built.report()).controlSize):toBe("large")
				stop()
				expect((built.report())):toBe(nil)
				ctx.runtime:dispose()
			end,
		})
	end)

	describe("Lab container editing", function()
		it("changes the model on every container page and restores deleted selections with Undo", {
			id = "native_gallery::Lab container editing::changes the model on every container page and restores deleted selections with Undo",
			run = function()
				local build = require("../examples/facet-lab/src/collection_editing")
				for _, kind in { "Table", "VirtualList", "VirtualGrid" } do
					local ctx, engine, target = nativeContext()
					local values = {}
					local scope: ExampleContext = ctx
					local runtime: Facet.Runtime = ctx.runtime
					local stop, root = runtime.mount(function(): Instance
						return (build :: any)({
							UI = ctx.UI,
							Compose = Compose,
							Facet = Facet,
							Host = ctx.Host,
							types = ctx.types,
							ctx = ctx,
							cell = function(name, initial)
								values[name] = values[name] or Compose.cell(initial)
								return values[name]
							end,
							log = function()
								return function() end
							end,
						}, kind)
					end, target)
					local function press(name)
						find(root, name).Activated:Fire(nil, 1)
					end
					press("NewItem")
					expect(#values.editingRows:peek()):toBe(7)
					values.editingSelection:set({ ["1"] = true, ["3"] = true })
					press("DeleteSelected")
					expect(#values.editingRows:peek()):toBe(5)
					expect(values.editingSelection:peek()["1"]):toBeNil()
					press("UndoEdit")
					expect(#values.editingRows:peek()):toBe(7)
					expect(values.editingSelection:peek()["3"]):toBe(true)
					values.editingEnabled:set(false)
					press("DeleteSelected")
					expect(#values.editingRows:peek()):toBe(7)
					stop()
					ctx.runtime:dispose()
				end
			end,
		})
	end)
end
