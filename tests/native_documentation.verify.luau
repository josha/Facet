--!strict
local Verify = require("../tools/vendor/verify/src/core")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")

return function(verifyHarness: Verify.Harness)
	local ThemeTypes = require("../src/ui/theme_types")
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)

	local fs, Lute = require("@std/fs"), require("../tools/vendor/verify/src/lute")
	local Facet, engineLib = require("../src"), require("./lib/native_engine")
	local entries: { { file: string, index: number, code: string } } = {}
	local files = { "README.md", "docs/reference/api.md" }
	for _, directory in { "docs/guide", "docs/extending", "docs/reference/nodes" } do
		for _, entry in fs.listDirectory(directory) do
			if string.match(entry.name, "%.md$") then
				table.insert(files, directory .. "/" .. entry.name)
			end
		end
	end
	table.sort(files)
	for _, file in files do
		local index = 0
		local text = string.gsub(fs.readFileToString(file), "\r\n", "\n")
		for code in string.gmatch(text, "```luau\n(.-)```") do
			index += 1
			table.insert(entries, { file = file, index = index, code = code })
		end
	end
	verifyHarness:suite("native documentation", function()
		for _, entry in entries do
			verifyHarness:case(`executes {entry.file} snippet {entry.index}`, {
				id = "native_documentation::"
					.. "native documentation"
					.. "::"
					.. `executes {entry.file} snippet {entry.index}`,
				run = function(t)
					if string.find(entry.code, 'require("./lib/native_engine")', 1, true) then
						local modules: { [string]: unknown } =
							{ ["../src"] = Facet, ["./lib/native_engine"] = engineLib }
						local environment: { [string]: unknown } = {
							require = function(path: string): unknown
								return assert(modules[path], path)
							end,
						}
						Lute.chunk.load(entry.code, { name = entry.file, environment = environment })()
						return
					end
					local engine = engineLib.new()
					local input: UserInputService = engine.new("UserInputService")
					local gui: GuiService = engine.new("GuiService")
					local world: Workspace = engine.new("Workspace")
					engine.environment.fakeOn(input, "GetFocusedTextBox", function(): TextBox?
						return nil
					end)
					local hapticPlays = 0
					local hapticCapture = engine.environment.onCreate(function(effect)
						if effect:IsA("HapticEffect") then
							engine.environment.fakeOn(effect, "Play", function()
								hapticPlays += 1
							end)
						end
					end)
					t:defer(function()
						hapticCapture:Disconnect()
					end)
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local Compose: ComposeModule, Host = Facet.Compose, Facet.host(runtime)
					local UI = Facet.controls(runtime, {
						types = engine.types,
						services = { UserInputService = input, GuiService = gui, Workspace = world },
					})
					local facade = table.clone(Facet)
					facade.Roblox = table.clone(Facet.Roblox)
					facade.themes = table.clone(Facet.themes)
					facade.Roblox.createRuntime = function()
						return runtime
					end
					facade.controls = function(rt: Facet.Runtime, opt: Facet.ControlOptions?)
						local options: Facet.ControlOptions = if opt then table.clone(opt) else {}
						options.types = engine.types
						return Facet.controls(rt, options)
					end
					facade.bind = function(core, roblox)
						Facet.bind(core, roblox)
						return facade
					end
					local playerGui = engine.new("PlayerGui")
					facade.app = function(opt: Facet.AppOptions?)
						local options: Facet.AppOptions = if opt then table.clone(opt) else {}
						options.runtime = options.runtime or runtime
						options.types = engine.types
						options.parent = options.parent or playerGui
						return Facet.app(options)
					end
					local sheets = {}
					facade.themes.createStyleSheet = function(
						rt: Facet.Runtime,
						pkg: Facet.Input<Facet.ReadOnlyThemePackage>?,
						opt: ThemeTypes.ThemeOptions?
					)
						local options: ThemeTypes.ThemeOptions = if opt then table.clone(opt) else {}
						options.types = engine.types
						local sheet = Facet.themes.createStyleSheet(rt, pkg, options)
						table.insert(sheets, sheet)
						return sheet
					end
					local env: { [string]: unknown } = (table.clone(engine.types) :: unknown) :: { [string]: unknown }
					env.Facet = facade
					env.Compose = Compose
					env.runtime = runtime
					env.Host = Host
					env.UI = UI
					env.themes = facade.themes
					env.package = Facet.themes.neutralPackage()
					env.ownedPanelAsset = "rbxassetid://123"
					env.themeModule = "theme"
					env.terminalPart = engine.new("Part")
					env.playerGui = playerGui
					env.productId = "test"
					local noop = function() end
					for _, key in
						{
							"onContinue",
							"openInventory",
							"openManifest",
							"save",
							"preview",
							"deleteDraft",
							"inspect",
							"openItem",
						}
					do
						env[key] = noop
					end
					env.rows = Compose.cell({ { id = "a", title = "Amber" } })
					env.items = env.rows
					for _, key in { "renderCard", "Catalog", "ItemDetails" } do
						env[key] = function()
							return UI.Text { text = "Content" }
						end
					end
					env.script = { Destroying = engine.heartbeat }
					env.request = { FireServer = noop }
					env.reply = { OnClientEvent = engine.heartbeat }
					local purchase = engine.new("RemoteFunction")
					env.game = {
						ReplicatedStorage = {
							Facet = "Facet",
							Packages = { Facet = "Facet", Compose = { core = "ComposeCore", roblox = "ComposeRoblox" } },
							WaitForChild = function()
								return "Facet"
							end,
							FindFirstChild = function(_, name: string)
								return if name == "Purchase" then purchase else nil
							end,
						},
						Players = {
							LocalPlayer = {
								PlayerGui = playerGui,
								WaitForChild = function()
									return playerGui
								end,
							},
						},
					}
					env.require = function(id: unknown): unknown
						return if id == "theme"
							then {
								build = function()
									return Facet.themes.neutralPackage()
								end,
							}
							elseif id == "ComposeCore" then Compose
							elseif id == "ComposeRoblox" then facade.Roblox
							else facade
					end
					if entry.file == "docs/reference/nodes/Composition.examples.md" then
						local app = facade.app({})
						t:defer(app.dispose)
						env.app, env.UI = app, app.UI
						env.beginAction = engine.new("InputAction")
						env.requestDeparture, env.requestRecord = noop, noop
						env.selected = Compose.cell("basalt")
						env.tasks = function()
							return app.UI.Text { text = "Tasks" }
						end
						env.specimenFields = function()
							return app.UI.Text { text = "Volcanic rock" }
						end
						env.specimenModel = function(rt: Facet.Runtime, world: Instance)
							Facet.host(rt).Part {
								Parent = Compose.static(world),
								Anchored = true,
								Size = engine.types.Vector3.new(2, 2, 2),
							}
						end
						for _, name in { "hub", "inspect", "pages" } do
							local body = fs.readFileToString("docs/reference/nodes/Tasks." .. name .. ".md")
							local code = assert(string.match(body, "```luau\n(.-)\n```"))
							env[name] = Lute.chunk.load(
								code .. "\nreturn " .. name,
								{ environment = env, name = "Tasks." .. name }
							)()
						end
					end
					local bindings = {}
					for key in env do
						table.insert(bindings, `local {key}=env[{string.format("%q", key)}]`)
					end
					local suffix = if entry.file == "docs/guide/state.md"
						then "\nreturn Purchase()"
						elseif entry.file == "docs/guide/themes.md" and entry.index == 2 then "\nreturn Screen()"
						else ""
					do
						assert(Lute.chunk.check(entry.code, entry.file))
						local factory = Lute.chunk.load(
							"return function(env)\n"
								.. table.concat(bindings, "\n")
								.. "\n"
								.. entry.code
								.. suffix
								.. "\nend",
							{ name = entry.file }
						)() :: (unknown) -> unknown
						local stop, mounted = runtime.mount(function()
							local node = factory(env)
							return if type(node) == "table" and (node :: { [string]: unknown }).ClassName
								then (node :: unknown) :: Instance
								else Host.Frame {}
						end, engine.new("ScreenGui"))
						if entry.file == "docs/reference/nodes/adjustable.md" then
							local row = (mounted :: unknown) :: Frame
							local readout = row:FindFirstChild("Angle")
							assert(readout and readout:IsA("GuiObject"))
							Verify.expect(readout.Selectable):toBe(true)
							for _, child in readout:GetDescendants() do
								if child:IsA("GuiObject") then
									Verify.expect(child.Selectable):toBe(false)
								end
							end
							local left, right = row:FindFirstChild("Left"), row:FindFirstChild("Right")
							assert(left and left:IsA("GuiButton") and right and right:IsA("GuiButton"))
							local text = readout:FindFirstChildWhichIsA("TextLabel", true)
							assert(text)
							Verify.expect(left.Interactable):toBe(false)
							engine.environment.fire(VerifyRoblox.assertInstance(right), "Activated")
							Verify.expect(text.Text):toBe("Angle 15°")
							engine.environment.fire(VerifyRoblox.assertInstance(left), "Activated")
							Verify.expect(text.Text):toBe("Angle 0°")
							for _ = 1, 6 do
								engine.environment.fire(VerifyRoblox.assertInstance(right), "Activated")
							end
							Verify.expect(text.Text):toBe("Angle 90°")
							Verify.expect(right.Interactable):toBe(false)
						end
						for _, sheet in sheets do
							assert(sheet.Parent ~= nil, "StyleSheet was referenced without parenting")
						end
						if string.find(entry.code, "app.mount(", 1, true) then
							local gui = playerGui:FindFirstChildWhichIsA("ScreenGui")
							assert(gui ~= nil, "app.mount made no ScreenGui")
							local link = gui:FindFirstChildWhichIsA("StyleLink")
							assert(
								link ~= nil and link.StyleSheet == gui:FindFirstChildWhichIsA("StyleSheet"),
								"no linked sheet"
							)
						end
						stop()
						runtime:dispose()
						if entry.file == "docs/reference/nodes/feedback.md" then
							Verify.expect(hapticPlays):toBe(1)
						end
					end
				end,
			})
		end
	end)
end
