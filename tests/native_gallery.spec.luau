--!strict
local t = require("./lib/testkit")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local catalogue = require("../examples/gallery/client/demo_picker")
local gallery = require("../examples/gallery/client/screen")
local Compose = Facet.Compose

local function controlsFor(ctx)
	return Facet.controls(ctx.runtime, {
		types = ctx.types,
		viewport = ctx.viewport,
		guiService = ctx.guiService,
		reducedMotion = ctx.reducedMotion,
	})
end

local function nativeContext()
	local engine = engineLib.new()
	local runtime = Facet.Roblox.createRuntime(engine)
	local viewport = Compose.cell({ width = 1280, height = 720 })
	local target = engine.new("Folder")
	local guiService = engine.new("GuiService")
	local ctx = {
		Facet = Facet,
		Compose = Compose,
		runtime = runtime,
		Host = runtime.constructors,
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

local function load(kind, name)
	return require("../examples/gallery/" .. (if kind == "example" then "examples/" else "scenarios/") .. name)
end

local function find(root, name)
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
	local stop, node = ctx.runtime.mount(function()
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

t.describe("native gallery", function()
	t.it("switches the entire gallery catalogue through one native root", function()
		local ctx, engine, target = nativeContext()
		ctx.selection = Compose.cell("all-controls")
		ctx.themeMode = Compose.cell("light")
		ctx.theme = Compose.cell(Facet.themes.neutralPackage())
		ctx.packages = { Neutral = ctx.theme:peek() }
		ctx.load = load
		local sheet
		local stop, gui = ctx.runtime.mount(function()
			sheet = Facet.themes.createStyleSheet(ctx.runtime, ctx.theme, { types = ctx.types, theme = ctx.themeMode })
			return ctx.Host.ScreenGui "FacetGallery" {
				sheet,
				ctx.Host.StyleLink({ StyleSheet = Compose.static(sheet) }),
				require("../examples/gallery/client/screen").build(ctx),
			}
		end, target)
		local root = find(gui, "Gallery")
		t.expect(sheet.Parent).toBe(gui)
		t.expect(find(gui, "StyleLink").StyleSheet).toBe(sheet)
		local navigation = find(root, "Demos")
		local bar = find(navigation, "Tabs")
		navigation.AbsoluteSize = ctx.types.Vector2.new(1280, 664)
		t.expect(bar.ScrollingDirection).toBe(ctx.types.Enum.ScrollingDirection.Y)
		for _, demo in catalogue.list() do
			find(bar, demo.id).Activated.fire()
			engine.heartbeat.fire(1 / 60)
			t.expect(ctx.selection:peek()).toBe(demo.id)
			t.expect(ctx.active:peek()).toBe(demo.id)
			t.expect(ctx.errorMessage:peek()).toBe(nil)
		end
		navigation.AbsoluteSize = ctx.types.Vector2.new(390, 700)
		t.expect(bar.ScrollingDirection).toBe(ctx.types.Enum.ScrollingDirection.X)
		find(bar, "all-controls").Activated.fire()
		t.expect(ctx.active:peek()).toBe("all-controls")
		find(root, "Settings").Activated.fire()
		t.expect(find(root, "GallerySettings") ~= nil).toBe(true)
		stop()
		t.expect(#target:GetChildren()).toBe(0)
		ctx.runtime:dispose()
	end)
	t.it("types, submits and restarts the retained word game through native input", function()
		local built, node, stop, ctx, _, target = mountExample("05_word_game")
		local answer = built.solution()
		for i = 1, #answer do
			find(target, "Type_" .. answer:sub(i, i)).Pressed.fire()
		end
		find(target, "Submit").Pressed.fire()
		t.expect(built.won()).toBe(true)
		t.expect(built.resultsOpen()).toBe(true)
		t.expect(built.state(1, 1)).toBe("correct")
		t.expect(find(find(node, "tile1_1"), "fill"):HasTag("facet-status-success")).toBe(true)
		built.restart()
		t.expect(built.phase()).toBe("playing")
		t.expect(built.row(1)).toBe("")
		stop()
		t.expect(#target:GetChildren()).toBe(0)
		ctx.runtime:dispose()
	end)
	t.it("places and undoes a crossword rack tile without losing the rack", function()
		local built, node, stop, ctx = mountExample("06_tile_game")
		local letter = built.rackLetter(1)
		find(node, "rt1").Activated.fire()
		find(find(node, "cell4_4"), "tap").Activated.fire()
		t.expect(built.pendingAt(4, 4)).toBe(letter)
		t.expect(built.rackCount()).toBe(6)
		built.undo()
		t.expect(built.pendingAt(4, 4)).toBe(nil)
		t.expect(built.rackCount()).toBe(7)
		stop()
		ctx.runtime:dispose()
	end)
	t.it("runs a match-three drag and releases its native frame subscription", function()
		local built, node, stop, ctx, engine = mountExample("07_match3")
		local tile = find(node, "tile" .. built.tileIdAt(1, 1))
		local drag = find(tile, "SwapDrag")
		drag.DragStart.fire(ctx.types.Vector2.zero)
		drag.DragContinue.fire(ctx.types.Vector2.new(30, 0))
		drag.DragEnd.fire()
		t.expect(built.isResolving()).toBe(true)
		for _ = 1, 240 do
			engine.heartbeat.fire(1 / 30)
		end
		t.expect(built.isResolving()).toBe(false)
		t.expect(built.hasLegalMove()).toBe(true)
		t.expect(built.tickHookActive()).toBe(false)
		built.swap(1, 1, 1, 2)
		t.expect(built.tickHookActive()).toBe(true)
		stop()
		t.expect(built.tickHookActive()).toBe(false)
		ctx.runtime:dispose()
	end)
	t.it("retains optimistic settings and rolls back rejected server data", function()
		local built, node, stop, ctx = mountExample("03_settings_sync")
		find(node, "Music").Activated.fire()
		t.expect(built.report().draft.music).toBe(true)
		t.expect(built.report().server.music).toBe(false)
		find(node, "Deliver").Activated.fire()
		t.expect(built.report().server.music).toBe(true)
		find(node, "Invalid").Activated.fire()
		t.expect(built.report().draft.volume).toBe(99)
		find(node, "Deliver").Activated.fire()
		t.expect(built.report().status).toBe("rejected")
		t.expect(built.report().draft.volume).toBe(10)
		stop()
		ctx.runtime:dispose()
	end)
	t.it("keeps playlist ratings when filtering and reordering domain rows", function()
		local built, _, stop, ctx = mountExample("02_playlist_table")
		built.ratingFor("neon"):set(5)
		built.filterText:set("Drift")
		t.expect(#built.from:peek()).toBe(1)
		built.filterText:set("")
		t.expect(built.ratingFor("neon"):peek()).toBe(5)
		built.reorder({ "apex" }, 0)
		t.expect(built.baseRows:peek()[1].id).toBe("apex")
		built.removeTrack("neon")
		t.expect(#built.baseRows:peek()).toBe(5)
		built.restore()
		t.expect(#built.baseRows:peek()).toBe(6)
		t.expect(built.ratingFor("neon"):peek()).toBe(4)
		stop()
		ctx.runtime:dispose()
	end)
	t.it("selects a playlist row on one click and plays it on a double click or Return", function()
		local built, node, stop, ctx = mountExample("02_playlist_table")
		find(node, "Body").AbsoluteWindowSize = ctx.types.Vector2.new(600, 400)
		local hit = find(node, "RowHit")
		local row = find(hit.Parent, "Row")
		local E = ctx.types.Enum
		local mouse = { UserInputType = E.UserInputType.MouseButton1, KeyCode = E.KeyCode.Unknown }
		hit.Activated.fire(mouse, 1)
		t.expect(built.nowPlaying:peek()).toBe(nil)
		t.expect(row:GetAttribute("FacetSelected")).toBe(true)
		hit.Activated.fire(mouse, 1)
		t.expect(built.nowPlaying:peek()).toBe(nil)
		hit.Activated.fire(mouse, 2)
		local playing = built.nowPlaying:peek()
		t.expect(playing ~= nil).toBe(true)
		built.nowPlaying:set(nil)
		hit.Activated.fire({ UserInputType = E.UserInputType.Keyboard, KeyCode = E.KeyCode.Return }, 1)
		t.expect(built.nowPlaying:peek()).toBe(playing)
		built.nowPlaying:set(nil)
		hit.Activated.fire({ UserInputType = E.UserInputType.Touch, KeyCode = E.KeyCode.Unknown }, 1)
		t.expect(built.nowPlaying:peek()).toBe(playing)
		stop()
		ctx.runtime:dispose()
	end)
	t.it("mounts the additional temperature and confirmation tutorials", function()
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
	end)
	t.it("updates and removes the standalone consumer through its controls", function()
		local ctx, _, target = nativeContext()
		local app = Facet.app({ runtime = ctx.runtime, types = ctx.types, parent = target, name = "FacetConsumer" })
		local stop, node = app.mount(function()
			return require("../examples/consumer/src/screen").build(Facet, app.UI)
		end)
		t.expect(node.Name).toBe("FacetConsumer")
		t.expect(node:FindFirstChildWhichIsA("StyleLink").StyleSheet).toBe(node:FindFirstChildWhichIsA("StyleSheet"))
		find(node, "Bump").Activated.fire()
		t.expect(find(node, "Count").Text).toBe("1 tap")
		find(node, "Close").Activated.fire()
		t.expect(find(node, "Panel")).toBe(nil)
		stop()
		t.expect(#target:GetChildren()).toBe(0)
		app.dispose()
		ctx.runtime:dispose()
	end)
	t.it("requests native haptics and releases effects when the screen closes", function()
		local ctx, _, target = nativeContext()
		local built
		local stop, node = ctx.runtime.mount(function()
			built = load("fixture", "sensory_feedback").build(ctx)
			return built.screen()
		end, target)
		t.expect(find(node, "Press").PressHapticEffect).toBe(built.effects.press)
		find(node, "Release").Activated.fire()
		t.expect(built.effects.release.PlayCount).toBe(1)
		t.expect(built.requests:peek()).toBe(1)
		find(node, "Selection").Activated.fire()
		t.expect(built.effects.selection.PlayCount).toBe(1)
		find(node, "Custom").Activated.fire()
		t.expect(built.effects.custom.PlayCount).toBe(1)
		t.expect(#built.effects.custom.WaveformKeys).toBe(5)
		t.expect(built.requests:peek()).toBe(3)
		built.playHaptics:set(false)
		t.expect(find(node, "Press").PressHapticEffect).toBe(nil)
		find(node, "Release").Activated.fire()
		t.expect(built.effects.release.PlayCount).toBe(1)
		t.expect(built.requests:peek()).toBe(3)
		t.expect(built.report().motorConfirmed).toBe(false)
		stop()
		for _, effect in built.effects do
			t.expect(effect.isDestroyed()).toBe(true)
		end
		ctx.runtime:dispose()
	end)

	for _, demo in catalogue.list() do
		t.it("mounts " .. demo.id .. " with the native runtime", function()
			local ctx, engine, target = nativeContext()
			local stop, node = ctx.runtime.mount(function()
				gallery.configure(ctx)
				ctx.UI = controlsFor(ctx)
				local definition = load(demo.kind, demo.module)
				local built = definition.build(ctx)
				if built.dispose then
					Compose.cleanup(built.dispose)
				end
				return built.screen()
			end, target)
			t.expect(node.Parent).toBe(target)
			t.expect(#engine.made > 1).toBe(true)
			stop()
			t.expect(node.isDestroyed()).toBe(true)
			ctx.runtime:dispose()
		end)
	end
	for _, groupName in { "all_controls", "collections", "motion_layout" } do
		local group = load("fixture", groupName)
		for _, section in group.groups do
			for _, tab in section.tabs do
				t.it("mounts " .. groupName .. "/" .. tab.id, function()
					local ctx, _, target = nativeContext()
					local stop, node = ctx.runtime.mount(function()
						local built = tab.scenario.build(ctx)
						if built.dispose then
							Compose.cleanup(built.dispose)
						end
						return built.screen()
					end, target)
					t.expect(node.Parent).toBe(target)
					stop()
					ctx.runtime:dispose()
				end)
			end
		end
	end
	t.it("reserves the measured shell toolbar height above the demos", function()
		local ctx, _, target = nativeContext()
		ctx.selection = Compose.cell("all-controls")
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
		t.expect(toolbar.AutomaticSize).toBe(ctx.types.Enum.AutomaticSize.Y)
		t.expect(demos.Position.Y.Offset).toBe(56)
		toolbar.AbsoluteSize = ctx.types.Vector2.new(390, 80)
		t.expect(demos.Position.Y.Offset).toBe(80)
		t.expect(demos.Size.Y.Offset).toBe(-80)
		toolbar.AbsoluteSize = ctx.types.Vector2.new(390, 40)
		t.expect(demos.Position.Y.Offset).toBe(56)
		stop()
		ctx.runtime:dispose()
	end)
	t.it("keeps action controls ordered responsive and interactive through native layout properties", function()
		local ctx, engine, target = nativeContext()
		local built
		local stop, root = ctx.runtime.mount(function()
			built = load("fixture", "action_controls").build(ctx)
			return built.screen()
		end, target)
		local toolbar = find(root, "Toolbar")
		t.expect(find(root, "Reset").Parent).toBe(toolbar)
		t.expect(find(root, "Enable").Parent).toBe(toolbar)
		t.expect(toolbar:FindFirstChildWhichIsA("UIListLayout").FillDirection)
			.toBe(ctx.types.Enum.FillDirection.Horizontal)
		local sections = find(root, "Sections")
		local layout = sections:FindFirstChildWhichIsA("UIListLayout")
		t.expect(layout.FillDirection).toBe(ctx.types.Enum.FillDirection.Horizontal)
		t.expect(find(root, "Showroom").Size.X.Scale).toBe(0.5)
		t.expect(find(root, "Showroom").LayoutOrder).toBe(1)
		t.expect(find(root, "RaceSetup").LayoutOrder).toBe(2)
		t.expect(find(root, "Hero").AutomaticSize).toBe(ctx.types.Enum.AutomaticSize.Y)
		t.expect(find(root, "Hero"):FindFirstChildWhichIsA("UISizeConstraint").MinSize.Y).toBe(240)
		t.expect(find(root, "Driver1").AutomaticSize).toBe(ctx.types.Enum.AutomaticSize.None)
		t.expect(find(root, "Drivers"):FindFirstChildWhichIsA("UIGridLayout").CellSize.Y.Offset).toBe(240)
		t.expect(find(root, "Backgrounds"):FindFirstChildWhichIsA("UIGridLayout").CellSize.Y.Offset).toBe(260)
		t.expect(find(root, "Driver1"):FindFirstChild("Content"):FindFirstChildWhichIsA("UIListLayout").FillDirection)
			.toBe(ctx.types.Enum.FillDirection.Vertical)
		ctx.viewport:set({ width = 600, height = 720 })
		t.expect(layout.FillDirection).toBe(ctx.types.Enum.FillDirection.Vertical)
		t.expect(find(root, "Showroom").Size.X.Scale).toBe(1)
		t.expect(find(root, "Drivers"):FindFirstChildWhichIsA("UIGridLayout").CellSize.X.Scale).toBe(1)
		find(root, "Driver1").Activated.fire()
		t.expect(built.report().status).toBe("Classic driver selected.")
		find(root, "Enable").Activated.fire()
		t.expect(find(root, "Save").Interactable).toBe(false)
		find(root, "Reset").Activated.fire()
		find(root, "Save").Activated.fire()
		t.expect(built.report().busy).toBe(true)
		engine.heartbeat.fire(2)
		t.expect(built.report().busy).toBe(false)
		t.expect(built.report().status).toBe("Your race is ready.")
		find(root, "OverMediaAction").Activated.fire()
		t.expect(built.report().status).toBe("Replay opened.")
		find(root, "RungLarge").Activated.fire()
		t.expect(built.report().controlSize).toBe("large")
		stop()
		t.expect(built.report()).toBe(nil)
		ctx.runtime:dispose()
	end)
end)
