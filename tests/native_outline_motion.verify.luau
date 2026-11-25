--!strict
local FixtureRoblox = require("@verify/src/roblox")
local Verify = require("@verify/src/core")
local Bdd = require("@verify/src/bdd")
local VerifyRoblox = require("@verify/src/roblox")
local Facet = require("../src")
local StandardIcons = require("../examples/standard_icons")

return function(verifyHarness: Verify.Harness)
	local test = Bdd.create(verifyHarness)
	local describe, it, expect = test.describe, test.it, test.expect
	local nativeDrag = require("./lib/native_drag")
	local cells = require("./lib/cells")

	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	type TextBoxConstructor = typeof(require("@repo/tools/typecheck/aliases").TextBoxConstructor)
	type TextLabelConstructor = typeof(require("@repo/tools/typecheck/aliases").TextLabelConstructor)
	type UIScaleConstructor = typeof(require("@repo/tools/typecheck/aliases").UIScaleConstructor)
	local FixtureComposeTypes = require("../src/vendor/compose/core")
	local FixtureCollectionTypes = require("../src/ui/collection_types")
	local FixtureCollectionProps = require("../src/ui/collection_props")
	local FixtureEnvironmentTypes = require("../src/ui/environment_types")
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	local FixtureEngineTypes = require("../src/ui/engine_types")
	type Use = FixtureComposeTypes.Use
	type Record = { id: number, label: string }
	local SharedTypes = require("../src/ui/control_types")

	local Compose = require("../src/vendor/compose/core")
	local Roblox = require("../src/vendor/compose/roblox")
	local context = require("../src/ui/context")
	local families = require("./lib/control_families")
	local registerCollections = require("../src/ui/collections")
	local registerRowActions = require("../src/ui/collection_row_actions")
	local registerTable = require("../src/ui/collection_table")
	local engineLib = require("./lib/native_engine")
	local function idleInput(engine: engineLib.Engine, input: VerifyRoblox.Instance)
		for _, name in { "GetKeysPressed", "GetMouseButtonsPressed", "GetGamepadState", "GetNavigationGamepads" } do
			engine.environment.fakeOn(VerifyRoblox.assertInstance(input), name, function()
				return {}
			end)
		end
		engine.environment.fakeOn(VerifyRoblox.assertInstance(input), "IsGamepadButtonDown", function()
			return false
		end)
		engine.environment.fakeOn(VerifyRoblox.assertInstance(input), "GetLastInputType", function()
			local E = engine.types.Enum
			return if input.PreferredInput == E.PreferredInput.Touch
				then E.UserInputType.Touch
				elseif input.PreferredInput == E.PreferredInput.Gamepad then E.UserInputType.Gamepad1
				else E.UserInputType.MouseMovement
		end)
	end

	local function setup(options: { [string]: any }?)
		local engine, fixture = engineLib.new(options and options.engine)
		local clock: (() -> number)? = options and options.clock
		if clock then
			engine.clock = clock
		end
		local runtime: ComposeRuntime = Roblox.createRuntime(engine)
		local gui = (engine.new("GuiService") :: unknown) :: GuiService
		gui.TouchControlsEnabled = true
		local root = engine.new("ScreenGui")
		engine.environment.fakeOn(VerifyRoblox.assertInstance(gui), "GetInsetArea", function()
			return engine.types.Rect.new(0, 0, 800, 600)
		end)
		local config: { [string]: any } = {
			types = engine.types,
			guiService = gui,
			services = { GuiService = gui },
			inputParent = root,
			motionLevel = "none",
		}
		for field, value in (options or {}) :: { [string]: any } do
			if field ~= "engine" then
				config[field] = value
			end
		end
		if config.userInputService and config.userInputService.GetPropertyChangedSignal == nil then
			local service: any = (engine.new("UserInputService") :: unknown) :: UserInputService
			engine.environment.fakeOn(service, "IsKeyDown", function()
				return false
			end)
			idleInput(engine, service)
			for key, value in config.userInputService do
				if type(value) == "function" then
					engine.environment.fakeOn(service, key, value)
				else
					engine.environment.poke(service, key, value)
				end
			end
			config.userInputService = service
			config.services.UserInputService = service
		end
		local ctx = context(Compose, runtime, config :: SharedTypes.Config)
		local UI = ({} :: unknown) :: SharedTypes.Controls
		families.inputs(ctx, UI)
		local surfaces = require("../src/ui/nav_modal")(ctx)
		require("../src/ui/nav_menu")(ctx, UI, surfaces)
		families.surfaces(ctx, UI, surfaces)
		require("../src/ui/nav_popover")(ctx, UI, surfaces)
		families.pages(ctx, UI, surfaces)
		require("../src/ui/nav_radial")(ctx, UI, surfaces)
		local buildList = registerCollections(ctx, UI)
		registerRowActions(ctx, UI)
		registerTable(ctx, UI, buildList)
		return engine, runtime, UI, root, gui, ctx, fixture
	end

	type OutlineRecord = { id: string, label: string?, children: { OutlineRecord }? }

	describe("outline motion", function()
		it("collapses a folder's visible rows as one sweep across a collapsed child folder", {
			id = "native_outline_motion::outline motion::collapses a folder's visible rows as one sweep across a collapsed child folder",
			run = function()
				local now = 0
				local engine, runtime, UI, target = setup({
					motionLevel = "normal",
					clock = function()
						return now
					end,
				})
				local expanded = Compose.cell({ folder = true } :: { [string]: boolean })
				local controls: any = {}
				local stop = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedOutlineSpec<OutlineRecord, string> = {
						from = {
							{
								id = "folder",
								children = {
									{ id = "sub", children = { { id = "deep" } } },
									{ id = "a" },
									{ id = "b" },
								},
							},
							{ id = "last" },
						} :: { OutlineRecord },
						key = "id",
						children = "children",
						expanded = expanded,
						mode = "all" :: "all",
						itemSize = 80,
						controls = controls,
						render = function(): GuiObject
							return Facet.host(runtime).Frame {
								Size = engine.types.UDim2.new(1, 0, 0, 40),
							}
						end,
					}
					return UI.Outline(listSpec)
				end, target)
				now += 1
				engine.heartbeat:Fire(1)
				expanded:set({})
				local sampled = 0
				for _ = 1, 40 do
					now += 1 / 60
					engine.heartbeat:Fire(1 / 60)
					local partial, last, total = 0, nil, 0
					for _, key in { "sub", "a", "b" } do
						local index = controls.indexOfKey(key)
						if index then
							local size = controls.placementOf(index).size
							total += size
							if size > 0 and size < 80 then
								partial += 1
							end
						end
					end
					local lastIndex = controls.indexOfKey("last")
					if lastIndex then
						last = controls.placementOf(lastIndex).offset
					end
					expect(partial <= 1):toBe(true)
					expect(last):toBe(80 + total)
					sampled += 1
				end
				expect(sampled):toBe(40)
				expect(controls.placementOf(controls.indexOfKey("last")).offset):toBe(80)
				stop()
				runtime:dispose()
			end,
		})

		it("keeps reorderable rows on their placement while an expansion animates", {
			id = "native_outline_motion::outline motion::keeps reorderable rows on their placement while an expansion animates",
			run = function()
				local now = 0
				local engine, runtime, UI, target = setup({
					motionLevel = "normal",
					clock = function()
						return now
					end,
				})
				local expanded = Compose.cell({ folder = true } :: { [string]: boolean })
				local controls: any = {}
				local stop, node: any = runtime.mount(function()
					local listSpec: FixtureCollectionProps.KeyedOutlineSpec<OutlineRecord, string> = {
						from = {
							{ id = "folder", children = { { id = "a" }, { id = "b" }, { id = "c" } } },
							{ id = "last" },
						} :: { OutlineRecord },
						key = "id",
						children = "children",
						expanded = expanded,
						mode = "all" :: "all",
						itemSize = 80,
						reorderable = true,
						onReorder = function() end,
						controls = controls,
						render = function(): GuiObject
							return Facet.host(runtime).Frame {
								Size = engine.types.UDim2.new(1, 0, 0, 40),
							}
						end,
					}
					return UI.Outline(listSpec)
				end, target)
				now += 1
				engine.heartbeat:Fire(1)
				expanded:set({})
				for _ = 1, 40 do
					now += 1 / 60
					engine.heartbeat:Fire(1 / 60)
					local row = node:FindFirstChild("last", true)
					local placed = controls.placementOf(controls.indexOfKey("last")).offset
					expect(math.abs(row.Position.Y.Offset - placed) < 1):toBe(true)
				end
				stop()
				runtime:dispose()
			end,
		})
	end)
end
