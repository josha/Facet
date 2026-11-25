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

	describe("row action input", function()
		it("listens to the input service only while a row action press is held", {
			id = "native_row_action_input::row action input::listens to the input service only while a row action press is held",
			run = function()
				local engine, runtime, UI, target, _, ctx = setup({ userInputService = {} })
				local Host = Facet.host(runtime)
				local service = VerifyRoblox.assertInstance(ctx.config.userInputService)
				local count = engine.environment.connectionsOfInstance
				local function rows(total: number): (() -> (), { Frame })
					local nodes: { Frame } = {}
					local stop = runtime.mount(function()
						local list = {}
						for index = 1, total do
							local spec: FixtureCollectionProps.RowActionsSpec = {
								content = Host.Frame {} :: GuiObject,
								trailing = { { id = "Delete", label = "Delete", onActivate = function() end } },
							}
							local node = UI.RowActions(spec)
							nodes[index] = node
							list[index] = node
						end
						return Host.Frame(list)
					end, target)
					return stop, nodes
				end
				local stopOne = rows(1)
				local one = count(service)
				stopOne()
				local stopMany, nodes = rows(5)
				expect(count(service)):toBe(one)
				local press = {
					UserInputType = engine.types.Enum.UserInputType.MouseButton1,
					UserInputState = engine.types.Enum.UserInputState.Begin,
					Position = engine.types.Vector3.new(10, 10, 0),
				}
				engine.environment.fire(VerifyRoblox.assertInstance(nodes[1]), "InputBegan", press)
				local held = count(service)
				expect(held > one):toBe(true)
				press.UserInputState = engine.types.Enum.UserInputState.End
				engine.environment.fire(service, "InputEnded", press)
				expect(count(service)):toBe(one)
				stopMany()
				runtime:dispose()
			end,
		})
	end)
end
