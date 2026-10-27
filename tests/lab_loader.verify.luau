--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")
local engineLib = require("./lib/native_engine")
local fs = require("@std/fs")
local task = require("@std/task")
local Lute = require("../tools/vendor/verify/src/lute")
local gallery = require("../examples/gallery/client/screen")
type Lab = {
	state: { errors: { [string]: { [string]: string } } },
	pageIds: () -> { string },
	open: (string) -> { ok: boolean },
	configure: (string) -> { ok: boolean },
	report: () -> { errors: { [string]: string }, missing: { string }, values: { [string]: string } },
}
type Catalog = { build: (Facet.Controls) -> unknown }
type Settings = { new: (unknown, unknown) -> unknown }
type Browser = { mount: (unknown) -> Lab }
return function(harness: Verify.Harness)
	harness:case("real Lab loader mounts every page and rejects new refusals", function(t)
		local engine = engineLib.new()
		local C = Facet.Compose
		local runtime = Facet.Roblox.createRuntime(engine)
		local Host = (runtime.constructors :: unknown) :: typeof(require("../tools/typecheck/aliases").RobloxHost)
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		local world = engine.new("Workspace")
		local camera = engine.new("Camera")
		engine.environment.poke(camera, "ViewportSize", engine.types.Vector2.new(1440, 900))
		camera.WorldToViewportPoint = function(_self: unknown, point: Vector3): (Vector3, boolean)
			return engine.types.Vector3.new(720 + point.X, 450 - point.Y, 20), true
		end
		world.CurrentCamera = camera
		input.GetFocusedTextBox = function()
			return nil
		end
		local demoTabs = require("../examples/gallery/scenarios/demo_tabs")
		local services: { [string]: unknown } = {
			GuiService = gui,
			RunService = { Heartbeat = engine.heartbeat },
			ReplicatedStorage = {
				WaitForChild = function(_self: unknown, name: string)
					assert(name == "FacetScenarios")
					return {
						WaitForChild = function(_folder: unknown, child: string): string
							assert(child == "demo_tabs")
							return "demo_tabs"
						end,
					}
				end,
			},
		}
		local target = engine.new("PlayerGui")
		local modules: { [string]: unknown } = {}
		local loadLab: (string) -> unknown
		local names = {
			"collection_editing",
			"drag_drop_demo",
			"variant_cell",
			"matrix_row",
			"matrix_width",
			"matrix_limit",
			"render_result",
			"page_key",
		}
		local siblings: { [string]: string } = {}
		for _, name in names do
			siblings[name] = name
		end
		loadLab = function(name: string): unknown
			if modules[name] ~= nil then
				return modules[name]
			end
			local environment = (table.clone(engine.types) :: unknown) :: { [string]: unknown }
			environment.workspace = world
			environment.Instance = { new = engine.new }
			environment.game = {
				GetService = function(_self: unknown, service: string): unknown
					return assert(services[service], service)
				end,
			}
			environment.task = task
			environment.script = { Parent = siblings }
			environment.require = function(path: string): unknown
				if path == "demo_tabs" then
					return demoTabs
				end
				return loadLab((string.gsub(path, "^%./", "")))
			end
			local module = Lute.chunk.load(fs.readFileToString("examples/facet-lab/src/" .. name .. ".luau"), {
				name = "Lab/" .. name,
				environment = environment,
			})()
			modules[name] = module
			return module
		end
		local catalog = loadLab("catalog") :: Catalog
		local browser = loadLab("browser") :: Browser
		local settings = loadLab("lab_settings") :: Settings
		local lab: Lab
		local app: Facet.App
		local stop = runtime.mount(function()
			local theme = Facet.themes.neutralPackage()
			local context: any = {
				Facet = Facet,
				Compose = C,
				runtime = runtime,
				Host = Host,
				types = engine.types,
				viewport = C.cell({ width = 1440, height = 900 }),
				guiService = gui,
				inputTarget = target,
				worldTarget = world,
				runService = { Heartbeat = engine.heartbeat },
				theme = C.cell(theme),
				themeMode = C.cell(theme.style.defaultTheme),
				themeName = C.cell("Neutral"),
				packages = { Neutral = theme },
				sceneVisible = C.cell(false),
				preview = gallery.preview,
			}
			gallery.configure(context)
			app = Facet.app {
				runtime = runtime,
				types = engine.types,
				parent = context.inputTarget,
				theme = context.theme,
				motionLevel = "none",
				guiService = gui,
				userInputService = input,
				services = { Workspace = world, GuiService = gui, UserInputService = input },
			}
			C.cleanup(app.dispose)
			lab = browser.mount {
				Facet = Facet,
				app = app,
				ctx = context,
				settings = settings.new(context, input),
				catalog = catalog.build(app.UI),
			}
			return Host.Folder { Name = "LabLoaderOwner" }
		end, engine.new("Folder"))
		t:defer(function()
			stop()
			runtime:dispose()
		end)
		local pages = lab.pageIds()
		Verify.expect(#pages >= 75):toBe(true)
		Verify.expect(#lab.report().missing):toBe(0)
		local refusals: { [string]: string } = {}
		for _, id in pages do
			Verify.expect(lab.open(id).ok):toBe(true)
			assert(
				target:FindFirstChild("Page_" .. id, true) ~= nil,
				`Page_{id} did not mount: {lab.report().errors.page or "no page error"}`
			)
			for page, errors in lab.state.errors do
				for where, message in errors do
					refusals[page .. "/" .. where] = message
				end
			end
		end
		local failures: { string } = {}
		Verify.expect(lab.open("Button").ok):toBe(true)
		Verify.expect(lab.configure("+reactive width (tap to change)").ok):toBe(true)
		local page = assert(target:FindFirstChild("Page_Button", true))
		local playground = assert(page:FindFirstChild("Playground"))
		local button = assert(playground:FindFirstChild("Live"):FindFirstChildWhichIsA("GuiButton", true))
		local buttonSignal = ((button :: unknown) :: { Activated: engineLib.Signal<> }).Activated
		for _, expected in { "220", "0", "140" } do
			buttonSignal:Fire()
			Verify.expect(lab.report().values.plainWidth):toBe(expected)
		end
		Verify.expect(lab.open("Composition").ok):toBe(true)
		local composition = assert(target:FindFirstChild("Page_Composition", true))
		local strip = assert(composition:FindFirstChild("Playground"):FindFirstChild("StripSettingsButton", true))
		local stripSignal = ((strip :: unknown) :: { Activated: engineLib.Signal<> }).Activated
		stripSignal:Fire()
		Verify.expect(lab.report().values.stripSettingsOpen):toBe("true")
		stripSignal:Fire()
		Verify.expect(lab.report().values.stripSettingsOpen):toBe("false")
		for location, message in refusals do
			if location == "focusSection/helper" and message == "Facet UI.Button: unknown option 'width'." then
				t:attach("baseline-focusSection", "text/plain", location .. ": " .. message)
			else
				table.insert(failures, location .. ": " .. message)
			end
		end
		table.sort(failures)
		assert(#failures == 0, table.concat(failures, "\n"))
	end)
end
