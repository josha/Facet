--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)

	local fs, Lute = require("@std/fs"), require("../tools/vendor/verify/src/lute")
	local Facet, engineLib = require("../src"), require("./lib/native_engine")
	local entries = {}
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
				run = function()
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
					local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
					local Compose: ComposeModule, Host = Facet.Compose, runtime.constructors
					local UI = Facet.controls(runtime, { types = engine.types })
					local facade = table.clone(Facet)
					facade.Roblox = table.clone(Facet.Roblox)
					facade.themes = table.clone(Facet.themes)
					facade.Roblox.createRuntime = function()
						return runtime
					end
					facade.controls = function(rt, opt)
						opt = table.clone(opt or {})
						assert(opt).types = engine.types
						return Facet.controls(rt, opt)
					end
					facade.bind = function(core, roblox)
						Facet.bind(core, roblox)
						return facade
					end
					local playerGui = engine.new("PlayerGui")
					facade.app = function(opt)
						opt = table.clone(opt or {})
						assert(opt).runtime = assert(opt).runtime or runtime
						assert(opt).types = engine.types
						assert(opt).parent = assert(opt).parent or playerGui
						return Facet.app(opt)
					end
					local sheets = {}
					facade.themes.createStyleSheet = function(rt, pkg, opt)
						opt = table.clone(opt or {})
						assert(opt).types = engine.types
						local sheet = Facet.themes.createStyleSheet(rt, pkg, opt)
						table.insert(sheets, sheet)
						return sheet
					end
					local env: { [string]: any } = (table.clone(engine.types) :: unknown) :: { [string]: any }
					for key, value in
						{
							Facet = facade,
							Compose = Compose,
							runtime = runtime,
							Host = Host,
							UI = UI,
							themes = facade.themes,
							package = Facet.themes.neutralPackage(),
							ownedPanelAsset = "rbxassetid://123",
							themeModule = "theme",
							terminalPart = engine.new("Part"),
							playerGui = playerGui,
							productId = "test",
						}
					do
						env[tostring(key)] = value
					end
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
							return UI.Text({ text = "Content" })
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
					env.require = function(id)
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
					local bindings = {}
					for key in env do
						table.insert(bindings, `local {key}=env[{string.format("%q", key)}]`)
					end
					local suffix = if entry.file == "docs/guide/06-client-server.md"
						then "\nreturn Purchase()"
						elseif entry.file == "docs/guide/01-concepts.md" then "\nreturn Preferences()"
						elseif
							entry.file == "docs/guide/09-custom-themes.md" and entry.index == 2
						then "\nreturn Screen()"
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
						local stop = runtime.mount(function()
							local node = factory(env)
							return if type(node) == "table" and (node :: { [string]: unknown }).ClassName
								then (node :: unknown) :: Instance
								else Host.Frame({})
						end, engine.new("ScreenGui"))
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
					end
				end,
			})
		end
	end)
end
