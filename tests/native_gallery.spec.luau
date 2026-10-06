--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ExampleContext = typeof(require("@repo/examples/types").Context)
	type MotionLevel = typeof(require("@repo/tools/typecheck/aliases").MotionLevel)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local requireDynamic = require :: (any) -> any
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local catalogue = require("../examples/gallery/client/demo_picker")
	local gallery = require("../examples/gallery/client/screen")
	local Compose: ComposeModule = Facet.Compose

	local function controlsFor(ctx: ExampleContext)
		return Facet.controls(ctx.runtime, {
			types = ctx.types,
			viewport = ctx.viewport,
			guiService = ctx.guiService,
			motionLevel = (Compose.formula(function(use: Use): "normal" | "limited" | "none"
				return if ctx.reducedMotion and use(ctx.reducedMotion) then "none" else "normal"
			end) :: unknown) :: MotionLevel,
		})
	end

	local function nativeContext()
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local viewport = Compose.cell({ width = 1280, height = 720 })
		local target = engine.new("Folder")
		local guiService = engine.new("GuiService")
		local ctx: ExampleContext = {
			UI = nil :: any,
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = (runtime.constructors :: unknown) :: RobloxHost,
			types = engine.types,
			viewport = viewport,
			inputTarget = target,
			worldTarget = engine.new("Folder"),
			guiService = guiService,
			runService = { Heartbeat = engine.heartbeat },
		}
		ctx.UI = controlsFor(ctx)
		return ctx, engine, target
	end

	local function load(kind, name: string)
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

	local function mountExample(name)
		local ctx, engine, target = nativeContext()
		local built
		local stop, node: any = ctx.runtime.mount(function()
			gallery.configure(ctx)
			ctx.UI = controlsFor(ctx)
			built = load("example", name).build(ctx)
			if built.dispose then
				Compose.cleanup(built.dispose)
			end
			return built.screen()
		end, target)
		return built, node, stop, ctx, engine, target
	end

	verifyHarness:suite("native gallery", function()
		verifyHarness:case("switches the entire gallery catalogue through one native root", {
			id = "native_gallery::native gallery::switches the entire gallery catalogue through one native root",
			run = function()
				local ctx, engine, target = nativeContext()
				ctx.selection = Compose.cell("garage")
				ctx.themeMode = Compose.cell("light")
				ctx.theme = Compose.cell(Facet.themes.neutralPackage())
				ctx.packages = { Neutral = ctx.theme:peek() }
				ctx.load = load
				local sheet
				local stop, gui = ctx.runtime.mount(function()
					sheet = Facet.themes.createStyleSheet(
						ctx.runtime,
						ctx.theme,
						{ types = ctx.types, theme = ctx.themeMode }
					)
					return ctx.Host.ScreenGui "FacetGallery" {
						sheet :: unknown,
						ctx.Host.StyleLink({ StyleSheet = Compose.static(sheet) }),
						require("../examples/gallery/client/screen").build(ctx),
					}
				end, target)
				local root = find(gui, "Gallery")
				Verify.expect(sheet.Parent):toBe(gui)
				Verify.expect(find(gui, "StyleLink").StyleSheet):toBe(sheet)
				local navigation = find(root, "Demos")
				Verify.expect(find(navigation, "Tabs").Visible):toBe(false)
				local button = find(find(root, "Toolbar"), "Showcase")
				for _, node in find(root, "Toolbar"):GetDescendants() do
					Verify.expect(node:IsA("TextLabel") and node.Text == "Facet gallery"):toBe(false)
				end
				local function pick(id)
					button.Activated.fire()
					local row = find(gui, "Demo-" .. id)
					if row == nil then
						error("no demo row " .. id)
					end
					row.Activated.fire()
				end
				for _, demo in catalogue.list() do
					pick(demo.id)
					engine.heartbeat.fire(1 / 60)
					Verify.expect((ctx.selection:peek())):toBe(demo.id)
					Verify.expect((ctx.active:peek())):toBe(demo.id)
					Verify.expect((ctx.errorMessage:peek())):toBe(nil)
				end
				pick("garage")
				Verify.expect((ctx.active:peek())):toBe("garage")
				button.Activated.fire()
				Verify.expect(find(gui, "Section") ~= nil):toBe(true)
				Verify.expect(find(gui, "DemoList") ~= nil):toBe(true)
				find(find(gui, "Section"), "settings").Activated.fire()
				Verify.expect(find(gui, "Packages") ~= nil):toBe(true)
				Verify.expect((find(gui, "DemoList"))):toBe(nil)
				find(find(gui, "Section"), "demos").Activated.fire()
				Verify.expect(#find(gui, "DemoList"):GetChildren() > #catalogue.list()):toBe(true)
				Verify.expect(find(gui, "Demo-garage").Parent):toBe(find(gui, "DemoList"))
				Verify.expect((find(gui, "SectionTitle"))):toBe(nil)
				stop()
				Verify.expect(#target:GetChildren()):toBe(0)
				ctx.runtime:dispose()
			end,
		})
		verifyHarness:case("types, submits and restarts the retained word game through native input", {
			id = "native_gallery::native gallery::types, submits and restarts the retained word game through native input",
			run = function()
				local built, node, stop, ctx, _, target = mountExample("05_word_game")
				local answer = built.solution()
				for i = 1, #answer do
					find(target, "Type_" .. answer:sub(i, i)).Pressed.fire()
				end
				find(target, "Submit").Pressed.fire()
				Verify.expect((built.won())):toBe(true)
				Verify.expect((built.resultsOpen())):toBe(true)
				Verify.expect((built.state(1, 1))):toBe("correct")
				Verify.expect((find(find(node, "tile1_1"), "fill"):HasTag("facet-status-success"))):toBe(true)
				built.restart()
				Verify.expect((built.phase())):toBe("playing")
				Verify.expect((built.row(1))):toBe("")
				stop()
				Verify.expect(#target:GetChildren()):toBe(0)
				ctx.runtime:dispose()
			end,
		})
		verifyHarness:case("places and undoes a crossword rack tile without losing the rack", {
			id = "native_gallery::native gallery::places and undoes a crossword rack tile without losing the rack",
			run = function()
				local built, node, stop, ctx = mountExample("06_tile_game")
				local letter = built.rackLetter(1)
				find(node, "rt1").Activated.fire()
				find(find(node, "cell4_4"), "tap").Activated.fire()
				Verify.expect((built.pendingAt(4, 4))):toBe(letter)
				Verify.expect((built.rackCount())):toBe(6)
				built.undo()
				Verify.expect((built.pendingAt(4, 4))):toBe(nil)
				Verify.expect((built.rackCount())):toBe(7)
				stop()
				ctx.runtime:dispose()
			end,
		})
		verifyHarness:case("runs a match-three drag and releases its native frame subscription", {
			id = "native_gallery::native gallery::runs a match-three drag and releases its native frame subscription",
			run = function()
				local built, node, stop, ctx, engine = mountExample("07_match3")
				local tile = find(node, "tile" .. built.tileIdAt(1, 1))
				local drag = find(tile, "SwapDrag")
				drag.DragStart.fire(ctx.types.Vector2.zero)
				drag.DragContinue.fire(ctx.types.Vector2.new(30, 0))
				drag.DragEnd.fire()
				Verify.expect((built.isResolving())):toBe(true)
				for _ = 1, 240 do
					engine.heartbeat.fire(1 / 30)
				end
				Verify.expect((built.isResolving())):toBe(false)
				Verify.expect((built.hasLegalMove())):toBe(true)
				Verify.expect((built.tickHookActive())):toBe(false)
				built.swap(1, 1, 1, 2)
				Verify.expect((built.tickHookActive())):toBe(true)
				stop()
				Verify.expect((built.tickHookActive())):toBe(false)
				ctx.runtime:dispose()
			end,
		})
		verifyHarness:case("retains optimistic settings and rolls back rejected server data", {
			id = "native_gallery::native gallery::retains optimistic settings and rolls back rejected server data",
			run = function()
				local built, node, stop, ctx = mountExample("03_settings_sync")
				find(node, "Music").Activated.fire()
				Verify.expect(built.report().draft.music):toBe(true)
				Verify.expect(built.report().server.music):toBe(false)
				find(node, "Deliver").Activated.fire()
				Verify.expect(built.report().server.music):toBe(true)
				find(node, "Invalid").Activated.fire()
				Verify.expect(built.report().draft.volume):toBe(99)
				find(node, "Deliver").Activated.fire()
				Verify.expect(built.report().status):toBe("rejected")
				Verify.expect(built.report().draft.volume):toBe(10)
				stop()
				ctx.runtime:dispose()
			end,
		})
		verifyHarness:case("keeps playlist ratings when filtering and reordering domain rows", {
			id = "native_gallery::native gallery::keeps playlist ratings when filtering and reordering domain rows",
			run = function()
				local built, _, stop, ctx = mountExample("02_playlist_table")
				built.ratingFor("neon"):set(5)
				built.filterText:set("Drift")
				Verify.expect(#built.from:peek()):toBe(1)
				built.filterText:set("")
				Verify.expect((built.ratingFor("neon"):peek())):toBe(5)
				built.reorder({ "apex" }, 0)
				Verify.expect(built.baseRows:peek()[1].id):toBe("apex")
				built.removeTrack("neon")
				Verify.expect(#built.baseRows:peek()):toBe(5)
				built.restore()
				Verify.expect(#built.baseRows:peek()):toBe(6)
				Verify.expect((built.ratingFor("neon"):peek())):toBe(4)
				stop()
				ctx.runtime:dispose()
			end,
		})
		verifyHarness:case("selects a playlist row on one click and plays it on a double click or Return", {
			id = "native_gallery::native gallery::selects a playlist row on one click and plays it on a double click or Return",
			run = function()
				local built, node, stop, ctx = mountExample("02_playlist_table")
				find(node, "Body").AbsoluteWindowSize = ctx.types.Vector2.new(600, 400)
				local hit = find(node, "RowHit")
				local row = find(hit.Parent, "Row")
				local E = ctx.types.Enum
				local mouse = { UserInputType = E.UserInputType.MouseButton1, KeyCode = E.KeyCode:FromValue(0) }
				hit.Activated.fire(mouse, 0)
				Verify.expect((built.nowPlaying:peek())):toBe(nil)
				Verify.expect((row:GetAttribute("FacetSelected"))):toBe(true)
				hit.Activated.fire(mouse, 0)
				Verify.expect((built.nowPlaying:peek())):toBe(nil)
				hit.Activated.fire(mouse, 1)
				local playing = built.nowPlaying:peek()
				Verify.expect(playing ~= nil):toBe(true)
				built.nowPlaying:set(nil)
				hit.Activated.fire({ UserInputType = E.UserInputType.Keyboard, KeyCode = E.KeyCode.Return }, 1)
				Verify.expect((built.nowPlaying:peek())):toBe(playing)
				built.nowPlaying:set(nil)
				hit.Activated.fire({ UserInputType = E.UserInputType.Touch, KeyCode = E.KeyCode:FromValue(0) }, 1)
				Verify.expect((built.nowPlaying:peek())):toBe(playing)
				stop()
				ctx.runtime:dispose()
			end,
		})
		verifyHarness:case("mounts the additional temperature and confirmation tutorials", {
			id = "native_gallery::native gallery::mounts the additional temperature and confirmation tutorials",
			run = function()
				for _, name in { "01_temperature_converter", "04_confirm_dialog" } do
					local built, _, stop, ctx = mountExample(name)
					if built.clear then
						built.clear()
					else
						built.openDialog()
						built.restore()
					end
					stop()
					ctx.runtime:dispose()
				end
			end,
		})
		verifyHarness:case("updates and removes the standalone consumer through its controls", {
			id = "native_gallery::native gallery::updates and removes the standalone consumer through its controls",
			run = function()
				local ctx, _, target = nativeContext()
				local app =
					Facet.app({ runtime = ctx.runtime, types = ctx.types, parent = target, name = "FacetConsumer" })
				local stop, node: any = app.mount(function()
					return require("../examples/consumer/src/screen").build(Facet, app.UI)
				end)
				Verify.expect(node.Name):toBe("FacetConsumer")
				Verify.expect(assert(node):FindFirstChildWhichIsA("StyleLink").StyleSheet)
					:toBe(node:FindFirstChildWhichIsA("StyleSheet"))
				find(node, "Bump").Activated.fire()
				Verify.expect(find(node, "Count").Text):toBe("1 tap")
				find(node, "Close").Activated.fire()
				Verify.expect((find(node, "Panel"))):toBe(nil)
				stop()
				Verify.expect(#target:GetChildren()):toBe(0)
				app.dispose()
				ctx.runtime:dispose()
			end,
		})
		verifyHarness:case("requests native haptics and releases effects when the screen closes", {
			id = "native_gallery::native gallery::requests native haptics and releases effects when the screen closes",
			run = function()
				local ctx, _, target = nativeContext()
				local built
				local stop, node: any = ctx.runtime.mount(function()
					built = load("fixture", "sensory_feedback").build(ctx)
					return built.screen()
				end, target)
				Verify.expect(find(node, "Press").PressHapticEffect):toBe(built.effects.press)
				find(node, "Release").Activated.fire()
				Verify.expect(built.effects.release.PlayCount):toBe(1)
				Verify.expect((built.requests:peek())):toBe(1)
				find(node, "Selection").Activated.fire()
				Verify.expect(built.effects.selection.PlayCount):toBe(1)
				find(node, "Custom").Activated.fire()
				Verify.expect(built.effects.custom.PlayCount):toBe(1)
				Verify.expect(#built.effects.custom.WaveformKeys):toBe(5)
				Verify.expect((built.requests:peek())):toBe(3)
				built.playHaptics:set(false)
				Verify.expect(find(node, "Press").PressHapticEffect):toBe(nil)
				find(node, "Release").Activated.fire()
				Verify.expect(built.effects.release.PlayCount):toBe(1)
				Verify.expect((built.requests:peek())):toBe(3)
				Verify.expect(built.report().motorConfirmed):toBe(false)
				stop()
				for _, effect in built.effects do
					Verify.expect((effect.isDestroyed())):toBe(true)
				end
				ctx.runtime:dispose()
			end,
		})

		local maintained: { { id: string, kind: "fixture" | "example", module: string, title: string?, blurb: string? } } =
			catalogue.list()
		for _, demo in
			{
				{ id = "all-controls", kind = "fixture" :: "fixture", module = "all_controls" },
				{ id = "collections", kind = "fixture" :: "fixture", module = "collections" },
				{ id = "motion-layout", kind = "fixture" :: "fixture", module = "motion_layout" },
				{ id = "radial-menu", kind = "fixture" :: "fixture", module = "radial_menu" },
				{ id = "ex03", kind = "example" :: "example", module = "03_settings_sync" },
				{ id = "ex05", kind = "example" :: "example", module = "05_word_game" },
				{ id = "ex06", kind = "example" :: "example", module = "06_tile_game" },
				{ id = "ex07", kind = "example" :: "example", module = "07_match3" },
			} :: { { id: string, kind: "fixture" | "example", module: string, title: string?, blurb: string? } }
		do
			table.insert(maintained, demo)
		end
		for _, demo in maintained do
			verifyHarness:case("mounts " .. demo.id .. " with the native runtime", {
				id = "native_gallery::"
					.. "native gallery"
					.. "::"
					.. "mounts "
					.. demo.id
					.. " with the native runtime",
				run = function()
					local ctx, engine, target = nativeContext()
					local stop, node: any = ctx.runtime.mount(function()
						gallery.configure(ctx)
						ctx.UI = controlsFor(ctx)
						local definition = load(demo.kind, demo.module)
						local built = definition.build(ctx)
						if built.dispose then
							Compose.cleanup(built.dispose)
						end
						return built.screen()
					end, target)
					Verify.expect(node.Parent):toBe(target)
					Verify.expect(#engine.made > 1):toBe(true)
					stop()
					Verify.expect((node.isDestroyed())):toBe(true)
					ctx.runtime:dispose()
				end,
			})
		end
		for _, groupName in { "all_controls", "collections", "motion_layout" } do
			local group = load("fixture", groupName)
			for _, section in group.groups do
				for _, tab in section.tabs do
					verifyHarness:case("mounts " .. groupName .. "/" .. tab.id, {
						id = "native_gallery::" .. "native gallery" .. "::" .. "mounts " .. groupName .. "/" .. tab.id,
						run = function()
							local ctx, _, target = nativeContext()
							local stop, node: any = ctx.runtime.mount(function()
								local built = tab.scenario.build(ctx)
								if built.dispose then
									Compose.cleanup(built.dispose)
								end
								return built.screen()
							end, target)
							Verify.expect(node.Parent):toBe(target)
							stop()
							ctx.runtime:dispose()
						end,
					})
				end
			end
		end
		verifyHarness:case("selects a nested all-controls tab by path through the showcase API", {
			id = "native_gallery::native gallery::selects a nested all-controls tab by path through the showcase API",
			run = function()
				local ctx, _, target = nativeContext()
				local built
				local stop = ctx.runtime.mount(function()
					built = load("fixture", "all_controls").build(ctx)
					return built.screen()
				end, target)
				Verify.expect((built.select("actions"))):toBe(true)
				Verify.expect((built.select("actions/menus"))):toBe(true)
				Verify.expect(built.report().active):toBe("menus")
				Verify.expect((built.select("actions/nope"))):toBe(false)
				stop()
				ctx.runtime:dispose()
			end,
		})
		verifyHarness:case("reserves the measured shell toolbar height above the demos", {
			id = "native_gallery::native gallery::reserves the measured shell toolbar height above the demos",
			run = function()
				local ctx, _, target = nativeContext()
				ctx.selection = Compose.cell("garage")
				ctx.themeMode = Compose.cell("light")
				ctx.theme = Compose.cell(Facet.themes.neutralPackage())
				ctx.packages = { Neutral = ctx.theme:peek() }
				ctx.load = load
				local stop, gui = ctx.runtime.mount(function()
					return ctx.Host.ScreenGui "FacetGallery" {
						require("../examples/gallery/client/screen").build(ctx),
					}
				end, target)
				local root = find(gui, "Gallery")
				local toolbar, demos = root:FindFirstChild("Toolbar"), root:FindFirstChild("Demos")
				local row = find(toolbar, "Row")
				Verify.expect(demos.Position.Y.Offset):toBe(56)
				row.AbsoluteSize = ctx.types.Vector2.new(390, 68)
				Verify.expect(demos.Position.Y.Offset):toBe(80)
				Verify.expect(demos.Size.Y.Offset):toBe(-80)
				Verify.expect(toolbar.Size.Y.Offset):toBe(80)
				row.AbsoluteSize = ctx.types.Vector2.new(390, 28)
				Verify.expect(demos.Position.Y.Offset):toBe(56)
				stop()
				ctx.runtime:dispose()
			end,
		})
		verifyHarness:case(
			"keeps action controls ordered responsive and interactive through native layout properties",
			{
				id = "native_gallery::native gallery::keeps action controls ordered responsive and interactive through native layout properties",
				run = function()
					local ctx, engine, target = nativeContext()
					local built
					local stop, root = ctx.runtime.mount(function()
						built = load("fixture", "action_controls").build(ctx)
						return built.screen()
					end, target)
					local toolbar = find(root, "Toolbar")
					Verify.expect(find(root, "Reset").Parent):toBe(toolbar)
					Verify.expect(find(root, "Enable").Parent):toBe(toolbar)
					Verify.expect(toolbar:FindFirstChildWhichIsA("UIListLayout").FillDirection)
						:toBe(ctx.types.Enum.FillDirection.Horizontal)
					local sections = find(root, "Sections")
					local layout = sections:FindFirstChildWhichIsA("UIListLayout")
					Verify.expect(layout.FillDirection):toBe(ctx.types.Enum.FillDirection.Horizontal)
					Verify.expect(find(root, "Showroom").Size.X.Scale):toBe(0.5)
					Verify.expect(find(root, "Showroom").LayoutOrder):toBe(1)
					Verify.expect(find(root, "RaceSetup").LayoutOrder):toBe(2)
					Verify.expect(find(root, "Hero").AutomaticSize):toBe(ctx.types.Enum.AutomaticSize.Y)
					Verify.expect(find(root, "Hero"):FindFirstChildWhichIsA("UISizeConstraint").MinSize.Y):toBe(240)
					Verify.expect(find(root, "Driver1").AutomaticSize):toBe(ctx.types.Enum.AutomaticSize.None)
					Verify.expect(find(root, "Drivers"):FindFirstChildWhichIsA("UIGridLayout").CellSize.Y.Offset)
						:toBe(240)
					Verify.expect(find(root, "Backgrounds"):FindFirstChildWhichIsA("UIGridLayout").CellSize.Y.Offset)
						:toBe(260)
					Verify.expect(
						find(root, "Driver1")
							:FindFirstChild("Content")
							:FindFirstChildWhichIsA("UIListLayout").FillDirection
					):toBe(ctx.types.Enum.FillDirection.Vertical)
					ctx.viewport:set({ width = 600, height = 720 })
					Verify.expect(layout.FillDirection):toBe(ctx.types.Enum.FillDirection.Vertical)
					Verify.expect(find(root, "Showroom").Size.X.Scale):toBe(1)
					Verify.expect(find(root, "Drivers"):FindFirstChildWhichIsA("UIGridLayout").CellSize.X.Scale):toBe(1)
					Verify.expect((find(root, "Driver1"):GetAttribute("selected"))):toBe(false)
					find(root, "Driver1").Activated.fire()
					Verify.expect(built.report().status):toBe("Classic driver selected.")
					Verify.expect((find(root, "Driver1"):GetAttribute("selected"))):toBe(true)
					Verify.expect((find(root, "Driver2"):GetAttribute("selected"))):toBe(false)
					find(root, "Enable").Activated.fire()
					Verify.expect(find(root, "Save").Interactable):toBe(false)
					find(root, "Reset").Activated.fire()
					find(root, "Save").Activated.fire()
					Verify.expect(built.report().busy):toBe(true)
					engine.heartbeat.fire(2)
					Verify.expect(built.report().busy):toBe(false)
					Verify.expect(built.report().status):toBe("Your race is ready.")
					find(root, "OverMediaAction").Activated.fire()
					Verify.expect(built.report().status):toBe("Replay opened.")
					find(root, "RungLarge").Activated.fire()
					Verify.expect(built.report().controlSize):toBe("large")
					stop()
					Verify.expect((built.report())):toBe(nil)
					ctx.runtime:dispose()
				end,
			}
		)
	end)

	verifyHarness:suite("Lab container editing", function()
		verifyHarness:case("changes the model on every container page and restores deleted selections with Undo", {
			id = "native_gallery::Lab container editing::changes the model on every container page and restores deleted selections with Undo",
			run = function()
				local build = require("../examples/facet-lab/src/collection_editing")
				for _, kind in { "Table", "VirtualList", "VirtualGrid" } do
					local ctx, engine, target = nativeContext()
					local values = {}
					local stop, root = ctx.runtime.mount(function()
						return build({
							UI = ctx.UI,
							Compose = Compose,
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
						find(root, name).Activated.fire(nil, 1)
					end
					press("NewItem")
					Verify.expect(#values.editingRows:peek()):toBe(7)
					values.editingSelection:set({ ["1"] = true, ["3"] = true })
					press("DeleteSelected")
					Verify.expect(#values.editingRows:peek()):toBe(5)
					Verify.expect(values.editingSelection:peek()["1"]):toBeNil()
					press("UndoEdit")
					Verify.expect(#values.editingRows:peek()):toBe(7)
					Verify.expect(values.editingSelection:peek()["3"]):toBe(true)
					values.editingEnabled:set(false)
					press("DeleteSelected")
					Verify.expect(#values.editingRows:peek()):toBe(7)
					stop()
					ctx.runtime:dispose()
				end
			end,
		})
	end)
end
