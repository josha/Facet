--!strict
local t = require("./lib/testkit")
local fs, luau = require("@lune/fs"), require("@lune/luau")
local Facet, engineLib = require("../src"), require("./lib/native_engine")
local entries = {}
local files = { "README.md", "docs/reference/api.md" }
for _, directory in { "docs/guide", "docs/extending" } do
	for _, name in fs.readDir(directory) do
		if string.match(name, "%.md$") then
			table.insert(files, directory .. "/" .. name)
		end
	end
end
table.sort(files)
for _, file in files do
	local index = 0
	for code in string.gmatch(fs.readFile(file), "```luau\n(.-)```") do
		index += 1
		table.insert(entries, { file = file, index = index, code = code })
	end
end
t.describe("native documentation", function()
	for _, entry in entries do
		t.it(`executes {entry.file} snippet {entry.index}`, function()
			if string.find(entry.code, 'require("./lib/native_engine")', 1, true) then
				local modules = { ["../src"] = Facet, ["./lib/native_engine"] = engineLib }
				luau.load(entry.code, {
					debugName = entry.file,
					environment = {
						require = function(path: string)
							return assert(modules[path], path)
						end,
					},
				})()
				return
			end
			local engine = engineLib.new()
			local runtime = Facet.Roblox.createRuntime(engine)
			local Compose, Host = Facet.Compose, runtime.constructors
			local UI = Facet.controls(runtime, { types = engine.types })
			local facade = table.clone(Facet)
			facade.Roblox = table.clone(Facet.Roblox)
			facade.themes = table.clone(Facet.themes)
			facade.Roblox.createRuntime = function()
				return runtime
			end
			facade.controls = function(rt, opt)
				opt = table.clone(opt or {})
				opt.types = engine.types
				return Facet.controls(rt, opt)
			end
			facade.bind = function(core, roblox)
				Facet.bind(core, roblox)
				return facade
			end
			local playerGui = engine.new("PlayerGui")
			facade.app = function(opt)
				opt = table.clone(opt or {})
				opt.runtime = opt.runtime or runtime
				opt.types = engine.types
				opt.parent = opt.parent or playerGui
				return Facet.app(opt)
			end
			local sheets = {}
			facade.themes.createStyleSheet = function(rt, pkg, opt)
				opt = table.clone(opt or {})
				opt.types = engine.types
				local sheet = Facet.themes.createStyleSheet(rt, pkg, opt)
				table.insert(sheets, sheet)
				return sheet
			end
			local env = table.clone(engine.types)
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
				env[key] = value
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
			env.game = {
				ReplicatedStorage = {
					Facet = "Facet",
					Packages = { Facet = "Facet", Compose = { core = "ComposeCore", roblox = "ComposeRoblox" } },
					WaitForChild = function()
						return "Facet"
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
				elseif entry.file == "docs/guide/09-custom-themes.md" and entry.index == 2 then "\nreturn Screen()"
				else ""
			do
				luau.compile(entry.code)
				local factory = luau.load(
					"return function(env)\n" .. table.concat(bindings, "\n") .. "\n" .. entry.code .. suffix .. "\nend"
				)()
				local stop = runtime.mount(function()
					local node = factory(env)
					return if type(node) == "table" and node.ClassName then node else Host.Frame({})
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
		end)
	end
end)
