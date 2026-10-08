--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Facet = require("../src")
	local engineLib = require("./lib/native_engine")
	local glade = require("../examples/reference/p1_glade")
	local cartwheel = require("../examples/reference/p2_cartwheel")
	local sipworks = require("../examples/reference/p3_sipworks")
	local foyer = require("../examples/reference/p4_foyer")
	local function world(module)
		local engine = engineLib.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local built
		local stop, node: any = runtime.mount(function()
			built = module.build({
				Facet = Facet,
				Compose = Facet.Compose,
				runtime = runtime,
				Host = (runtime.constructors :: unknown) :: RobloxHost,
				UI = Facet.controls(runtime, { types = engine.types }),
				types = engine.types,
				viewport = Facet.Compose.cell({ width = 1000, height = 720 }),
			})
			return built.screen()
		end, engine.new("ScreenGui"))
		return built, node, function()
			stop()
			runtime:dispose()
		end
	end
	local function find(node: any, name: string): any
		if node.Name == name then
			return node
		end
		for _, child in node:GetChildren() do
			local found = find(child, name)
			if found then
				return found
			end
		end
		return nil
	end
	verifyHarness:suite("native reference applications", function()
		verifyHarness:case("keeps Glade care, inventory consumption and task completion", {
			id = "native_reference_apps::native reference applications::keeps Glade care, inventory consumption and task completion",
			run = function()
				local built, root, stop = world(glade)
				Verify.expect(root.ClassName):toBe("Frame")
				built.steps.open("mossholm")
				built.steps.refill("mossholm")
				Verify.expect((built.steps.choose("mossholm", "bramble"))):toBe(true)
				Verify.expect((built.model.complete:peek())):toBe(true)
				local before = built.model.commerce.satchelOf("starlight"):peek()
				built.steps.choose("mossholm", "starlight")
				Verify.expect((built.model.commerce.satchelOf("starlight"):peek())):toBe(before - 1)
				for _, id in { "favorites", "wisps", "flora", "keeper" } do
					built.model.section:set(id)
				end
				stop()
				Verify.expect((root:isDestroyed())):toBe(true)
			end,
		})
	end);
	(function(verifyHarness: Verify.Harness)
		type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)
		type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
		type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

		local Facet = require("../src")
		local engineLib = require("./lib/native_engine")
		local glade = require("../examples/reference/p1_glade")
		local cartwheel = require("../examples/reference/p2_cartwheel")
		local sipworks = require("../examples/reference/p3_sipworks")
		local foyer = require("../examples/reference/p4_foyer")
		local luau = require("@lune/luau")
		local Compose: ComposeModule = Facet.Compose

		type World = {
			built: any,
			root: any,
			screen: any,
			engine: any,
			input: any,
			baseline: any,
			stop: () -> (),
		}

		local function world(module: any): World
			local engine: any = engineLib.new()
			local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
			local gui = engine.new("GuiService")
			local input = engine.new("UserInputService")
			input.GetFocusedTextBox = function()
				return nil
			end
			local screen = engine.new("ScreenGui")
			local baseline = engine.census()
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
							services = { GuiService = gui, UserInputService = input },
						} :: any
					),
					types = engine.types,
					viewport = Compose.cell({ width = 1000, height = 720 }),
					heartbeat = engine.heartbeat,
				})
				return built.screen()
			end, screen)
			return {
				built = built,
				root = root,
				screen = screen,
				engine = engine,
				input = input,
				baseline = baseline,
				stop = function()
					stop()
					runtime:dispose()
				end,
			}
		end

		local function find(node: any, name: string): any
			if node.Name == name then
				return node
			end
			for _, child in node:GetChildren() do
				local found = find(child, name)
				if found then
					return found
				end
			end
			return nil
		end

		local function within(node: any, ...: string): any
			local at = node
			for _, name in { ... } do
				at = find(at, name)
				if at == nil then
					return nil
				end
			end
			return at
		end

		local function press(node: any, ...: string)
			local target = assert(within(node, ...), `no {table.concat({ ... }, "/")}`)
			target.Activated:Fire()
		end

		local function pages(w: World): any
			return assert(within(w.root, "Destinations", "Content"))
		end

		verifyHarness:suite("Foyer", function()
			verifyHarness:case("section cards fit the local window and grow to their content", {
				id = "native_reference_apps::Foyer::section cards fit the local window and grow to their content",
				run = function()
					local w = world(foyer)
					press(pages(w), "home", "Sections", "picked", "SeeAll")
					local grid = assert(find(w.screen, "Worlds"))
					grid.AbsoluteWindowSize = w.engine.types.Vector2.new(500, 400)
					local items = assert(find(grid, "Items"))
					local row
					for _, child in items:GetChildren() do
						if child:IsA("Frame") and child.Name ~= "LayoutUnit" then
							row = child
							break
						end
					end
					Verify.expect(row ~= nil):toBe(true)
					Verify.expect(row.Size.X.Offset >= 232):toBe(true)
					local card = assert(row:FindFirstChild(row.Name, true))
					card.AbsoluteSize = w.engine.types.Vector2.new(row.Size.X.Offset, 360)
					Verify.expect(row.Size.Y.Offset):toBe(360)
					grid.AbsoluteWindowSize = w.engine.types.Vector2.new(340, 400)
					Verify.expect(row.Size.X.Offset >= 232 and row.Size.X.Offset <= 340):toBe(true)
					w.stop()
				end,
			})
			verifyHarness:case("reference columns keep dynamic content after their commands", {
				id = "native_reference_apps::Foyer::reference columns keep dynamic content after their commands",
				run = function()
					local shown = Compose.cell(true)
					local w = world({
						build = function(ctx)
							local view = require("../examples/reference/view")(ctx)
							return {
								screen = function()
									return view.column("Commands", {
										ctx.Host.TextLabel "Title" {},
										ctx.Host.TextButton "Search" {},
										Compose.show(shown, function()
											return ctx.Host.Frame "Collection" {}
										end),
									})
								end,
							}
						end,
					})
					local title, search = find(w.root, "Title"), find(w.root, "Search")
					Verify.expect(title.LayoutOrder < search.LayoutOrder):toBe(true)
					Verify.expect(search.LayoutOrder < find(w.root, "Collection").LayoutOrder):toBe(true)
					shown:set(false)
					shown:set(true)
					Verify.expect(search.LayoutOrder < find(w.root, "Collection").LayoutOrder):toBe(true)
					w.stop()
				end,
			})
		end)

		verifyHarness:suite("Documentation and tooling", function()
			local function run(code: string, suffix: string): (any, any, any, any, any)
				local engine: any = engineLib.new()
				local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
				local facade = table.clone(Facet) :: any
				facade.Roblox = table.clone(Facet.Roblox)
				facade.themes = table.clone(Facet.themes)
				facade.Roblox.createRuntime = function()
					return runtime
				end
				facade.controls = function(rt, options)
					local settings = table.clone(options or {})
					settings.types = engine.types
					return Facet.controls(rt, settings)
				end
				local sheets = {}
				facade.themes.createStyleSheet = function(rt, package, options)
					local settings = table.clone(options or {})
					settings.types = engine.types
					local sheet = Facet.themes.createStyleSheet(rt, package, settings)
					table.insert(sheets, sheet)
					return sheet
				end
				local playerGui = engine.new("PlayerGui")
				facade.app = function(options)
					local settings = table.clone(options or {})
					settings.types = engine.types
					settings.parent = settings.parent or playerGui
					return Facet.bind(Facet.Compose, facade.Roblox).app(settings)
				end
				local host = engine.new("ScreenGui")
				local scripts = engineLib.new()
				local destroying = scripts.heartbeat
				local env = table.clone(engine.types) :: any
				env.Facet = facade
				env.Compose = Compose
				env.Host = runtime.constructors
				env.UI = facade.controls(runtime)
				env.script = { Destroying = destroying, engine = scripts }
				env.require = function()
					return facade
				end
				env.game = {
					ReplicatedStorage = {
						WaitForChild = function()
							return "Facet"
						end,
					},
					Players = {
						LocalPlayer = {
							WaitForChild = function()
								return playerGui
							end,
						},
					},
				}
				local bindings = {}
				for key in env do
					table.insert(bindings, `local {key}=env[{string.format("%q", key)}]`)
				end
				local baseline = engine.census()
				local factory = luau.load(
					"return function(env)\n" .. table.concat(bindings, "\n") .. "\n" .. code .. suffix .. "\nend"
				)()
				return factory,
					env,
					engine,
					runtime,
					{ baseline = baseline, playerGui = playerGui, host = host, sheets = sheets }
			end
		end)
	end)(verifyHarness)
end
