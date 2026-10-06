--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local FixtureComposeTypes = require("../src/vendor/compose/core")

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local catalogue = require("../examples/gallery/client/demo_picker")
	local gallery = require("../examples/gallery/client/screen")
	local Compose: ComposeModule = Facet.Compose

	local function context()
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local problems: { string } = {}
		local ctx: any = {
			Facet = Facet,
			Compose = Compose,
			runtime = runtime,
			Host = (runtime.constructors :: unknown) :: RobloxHost,
			types = engine.types,
			viewport = Compose.cell({ width = 1280, height = 720 }),
			inputTarget = engine.new("Folder"),
			worldTarget = engine.new("Folder"),
			guiService = engine.new("GuiService"),
			runService = { Heartbeat = engine.heartbeat },
		}
		ctx.UI = Facet.controls(runtime, {
			types = ctx.types,
			viewport = ctx.viewport,
			guiService = ctx.guiService,
			onError = function(problem: unknown)
				table.insert(problems, tostring(problem))
			end,
		})
		return ctx, engine, problems
	end

	local function load(kind: string, name: string): any
		return require(
				"../examples/gallery/" .. (if kind == "example" then "examples/" else "scenarios/") .. name
			) :: any
	end

	local function settle(engine: any, frames: number)
		for _ = 1, frames do
			engine.heartbeat:Fire(1 / 60)
		end
	end

	local function fallbacks(root: any): { string }
		local found = {}
		for _, node in root:GetDescendants() do
			if
				node.Name == "AppFailure"
				or (node.ClassName == "TextLabel" and string.find(node.Text or "", " stopped$"))
			then
				table.insert(found, tostring(node.Name))
			end
		end
		return found
	end

	local function press(engine: any, root: any, problems: { string }): (number, { string })
		local pressed = 0
		local failures = {}
		local controls: { any } = {}
		for _, node in root:GetDescendants() do
			if node:IsA("GuiButton") or node:IsA("TextBox") then
				table.insert(controls, node)
			end
		end
		for _, node in controls do
			if node.Parent == nil or node:isDestroyed() then
				continue
			end
			local ok, problem = pcall(function()
				if node:IsA("TextBox") then
					node.Text = "Probe"
					node.FocusLost:Fire(true)
				else
					node.Activated:Fire()
				end
				settle(engine, 3)
			end)
			pressed += 1
			if not ok then
				table.insert(failures, tostring(node.Name) .. ": " .. tostring(problem))
			end
		end
		settle(engine, 30)
		for _, problem in problems do
			table.insert(failures, "reported: " .. problem)
		end
		return pressed, failures
	end

	local function sweep(label: string, build: (any) -> any)
		verifyHarness:case("presses every control in " .. label .. " without an error or a failure screen", {
			id = "native_press_sweep::"
				.. "native press sweep: gallery demos"
				.. "::"
				.. "presses every control in "
				.. label
				.. " without an error or a failure screen",
			run = function()
				local ctx, engine, problems = context()
				local target = engine.new("Folder")
				local stop, node: any = ctx.runtime.mount(function()
					gallery.configure(ctx)
					return build(ctx)
				end, target)
				settle(engine, 10)
				local pressed, failures = press(engine, node, problems)
				Verify.expect((table.concat(failures, "\n"))):toBe("")
				Verify.expect((table.concat(fallbacks(node), "\n"))):toBe("")
				Verify.expect(pressed >= 0):toBe(true)
				stop()
				ctx.runtime:dispose()
			end,
		})
	end

	verifyHarness:suite("native press sweep: gallery demos", function()
		for _, demo in catalogue.list() do
			sweep(demo.id, function(ctx)
				local built = load(demo.kind, demo.module).build(ctx)
				if built.dispose then
					Compose.cleanup(built.dispose)
				end
				return built.screen()
			end)
		end
		for _, groupName in { "all_controls", "collections", "motion_layout" } do
			local group = load("fixture", groupName)
			for _, section in group.groups do
				for _, tab in section.tabs do
					sweep(groupName .. "/" .. tab.id, function(ctx)
						local built = tab.scenario.build(ctx)
						if built.dispose then
							Compose.cleanup(built.dispose)
						end
						return built.screen()
					end)
				end
			end
		end
	end)

	verifyHarness:suite("native press sweep: Virtual Monitors", function()
		verifyHarness:case("presses every control on every monitor twice without an error or a failure screen", {
			id = "native_press_sweep::native press sweep: Virtual Monitors::presses every control on every monitor twice without an error or a failure screen",
			run = function()
				local Roblox = require("../src/vendor/compose/roblox")
				local modelModule = require("../examples/virtual_monitors/model") :: any
				local screens = require("../examples/virtual_monitors/screens") :: any
				local engine = engineLib.new()
				local runtime: ComposeRuntime = Roblox.createRuntime(engine)
				local target = engine.new("ScreenGui")
				local gui, input = engine.new("GuiService"), engine.new("UserInputService")
				input.GetFocusedTextBox = function()
					return nil
				end
				input.IsKeyDown = function()
					return false
				end
				local problems: { string } = {}
				local lifetime = Compose.createRootOwner(function()
					local model = modelModule.new(Compose)
					Compose.cleanup(model.dispose)
					local views = screens.create(Facet, runtime, {
						model = model,
						types = engine.types,
						services = { GuiService = gui, UserInputService = input },
						motionLevel = "none",
					})
					local pressedTotal = 0
					for _, name in { "Discover", "Avatar", "Chat" } do
						local _, node: any = runtime.mount(views[name], target)
						settle(engine, 10)
						for _ = 1, 2 do
							local pressed, failures = press(engine, node, problems)
							pressedTotal += pressed
							Verify.expect(name .. ": " .. table.concat(failures, "\n")):toBe(name .. ": ")
							Verify.expect(name .. ": " .. table.concat(fallbacks(node), "\n")):toBe(name .. ": ")
						end
					end
					Verify.expect(pressedTotal > 50):toBe(true)
				end, runtime.reactor)
				lifetime.dispose()
				runtime:dispose()
			end,
		})
	end)

	return nil
end
