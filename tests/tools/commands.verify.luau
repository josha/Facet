--!strict
local Verify = require("../../tools/vendor/verify/src/core")
local commands = require("../../tools/facet/commands")
local Loader = require("../lib/loader")
local Run = require("../../tools/facet/lib/run")
local Files = require("../../tools/facet/lib/files")
local Json = require("../../tools/facet/lib/json")

return function(harness: Verify.Harness)
	harness:case(
		"first docs call contains bounded recipes, project discovery and recoverable heading suggestions",
		function()
			local first = Run.capture({ Run.lute(), "run", "tools/facet", "docs" })
			Verify.expect(first.ok):toBe(true)
			Verify.expect(#first.stdout < 12000):toBe(true)
			for _, text in
				{
					"Facet.Use",
					"VirtualGrid",
					"KeyedCollectionSpec",
					"--static",
					"rg and Git are optional",
					"[string]: number",
				}
			do
				Verify.expect(string.find(first.stdout, text, 1, true) ~= nil):toBe(true)
			end
			for _, heading in { "Theme packages", "Sizing and layout" } do
				local result = Run.capture({ Run.lute(), "run", "tools/facet", "docs", heading })
				Verify.expect(result.ok):toBe(true)
				Verify.expect(string.find(result.stdout, "Closest sections:", 1, true) ~= nil):toBe(true)
			end
		end
	)
	harness:case(
		"verify accepts BOM and mixed public reactive types and audits saved evidence without Studio",
		function(context)
			local directory = Files.temporaryDirectory("facet-verify-consumer")
			context:defer(function()
				Files.remove(directory)
			end)
			local source = Files.join(directory, "main.client.luau")
			local project = Files.join(directory, "default.project.json")
			local dump = Files.join(directory, "dump.json")
			local text = [[--!strict
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local Compose = Facet.Compose
local app = Facet.app()
local UI = app.UI
type Entry = { id: string, title: string }
local initial: { Entry } = {}
local entries = Compose.cell(initial)
local busy = Compose.cell(false)
local initialBalances: { [string]: number } = { Credits = 0 }
local balances = Compose.cell(initialBalances)
local key = Compose.cell("Credits")
app.mount(function()
    local spec: Facet.KeyedCollectionSpec<Entry, string> = {
        from = entries, key = "id", itemSize = 64,
        render = function(current)
            return UI.Button "Entry" {
                label = function(use: Facet.Use)
                    return use(current).title .. tostring(use(balances)[use(key)] or 0)
                end,
                enabled = function(use: Facet.Use) return not use(busy) end,
            }
        end,
    }
    return UI.Screen "Root" { UI.VirtualList "Entries" (spec) }
end)
]]
			Files.write(source, "\239\187\191" .. text)
			Files.write(
				project,
				Json.encode({
					name = "Consumer",
					tree = {
						["$className"] = "DataModel",
						ReplicatedStorage = {
							Packages = {
								["$className"] = "Folder",
								Facet = { ["$path"] = Files.join(Files.cwd(), "src") },
							},
						},
						StarterPlayer = { StarterPlayerScripts = { Main = { ["$path"] = source } } },
					},
				})
			)
			local Look = require("../../tools/facet/lib/look")
			Files.write(dump, Look.sample(false))
			local command = {
				Run.lute(),
				"run",
				"tools/facet",
				"verify",
				source,
				"--project",
				project,
				"--out",
				Files.join(directory, "out"),
				"--static",
			}
			local static = Run.capture(command)
			Verify.expect(static.ok):toBe(true)
			Verify.expect(Files.read(source)):toBe(text)
			Verify.expect(string.find(static.stdout, "not checked (--static)", 1, true) ~= nil):toBe(true)
			Verify.expect(string.find(static.stdout, "facet lint:", 1, true) == nil):toBe(true)
			table.remove(command)
			for _, argument in { "--dump", dump, "--device", "desktop" } do
				table.insert(command, argument)
			end
			local saved = Run.capture(command)
			Verify.expect(string.find(saved.stdout, "saved evidence only", 1, true) ~= nil):toBe(true)
			Files.write(dump, Look.sample(true))
			local weak = Run.capture(command)
			Verify.expect(weak.ok):toBe(false)
			Verify.expect(string.find(weak.stdout, "[text-truncated]", 1, true) ~= nil):toBe(true)
		end
	)
	harness:case("author docs bound broad reads and print a shared control section once", function()
		local compact = Run.capture({
			Run.lute(),
			"run",
			"tools/facet",
			"docs",
			"Screen",
			"Sheet",
			"VStack",
			"HStack",
			"Text",
			"Button",
			"VirtualGrid",
			"Card",
			"Notice",
			"Sheet and overlay focus",
			"Selection and gamepad focus",
			"Typed collections",
		})
		Verify.expect(compact.ok):toBe(true)
		Verify.expect(#compact.stdout < 12000):toBe(true)
		Verify.expect(string.find(compact.stdout, "--full", 1, true) ~= nil):toBe(true)
		local full = Run.capture({ Run.lute(), "run", "tools/facet", "docs", "VirtualList", "VirtualGrid", "--full" })
		Verify.expect(full.ok):toBe(true)
		local _, headings = string.gsub(full.stdout, "### VirtualList and VirtualGrid", "")
		Verify.expect(headings):toBe(1)
		Verify.expect(string.find(full.stdout, "minColumnWidth", 1, true) ~= nil):toBe(true)
	end)
	harness:case("author setup and task recipes fit a short first read", function()
		local info = Run.capture({ Run.lute(), "run", "tools/facet", "info" })
		Verify.expect(info.ok):toBe(true)
		Verify.expect(#info.stdout < 3200):toBe(true)
		local recipes = Run.capture({ Run.lute(), "run", "tools/facet", "docs", "HUD panels", "Collection screen" })
		Verify.expect(recipes.ok):toBe(true)
		Verify.expect(#recipes.stdout < 4000):toBe(true)
		Verify.expect(string.find(recipes.stdout, "Facet.Use", 1, true) ~= nil):toBe(true)
	end)
	harness:case(
		"lint keeps all error locations and full details when it shortens cyclic type errors",
		function(context)
			local temporary = Files.temporaryDirectory("facet-lint-output")
			local directory = Files.join("artifacts/verify", Files.name(temporary))
			Files.remove(temporary)
			context:defer(function()
				Files.remove(directory)
			end)
			local source = Files.join(directory, "fault.luau")
			local project = Files.join(directory, "default.project.json")
			Files.write(
				source,
				[[--!strict
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local app = Facet.app()
local UI = app.UI
type Entry = { id: string, title: string }
local entries: { Entry } = {}
local initial: { name: string, enabled: boolean }? = nil
local state = Facet.Compose.cell(initial)
local wrong: Facet.Readable<Entry> = state
app.mount(function()
    local spec: Facet.KeyedCollectionSpec<Entry, string> = {
        from = Facet.Compose.cell(entries), key = "id", itemSize = 64,
        render = function(current)
            return UI.Text "Status" {
                text = function(use)
                    local entry, snapshot = use(current), use(state)
                    return if snapshot then snapshot.name .. entry.title else "Waiting"
                end,
            }
        end,
    }
    return UI.VirtualList "Entries" (spec)
end)
]]
			)
			Files.write(
				project,
				Json.encode({
					name = "LintOutput",
					tree = {
						["$className"] = "DataModel",
						ReplicatedStorage = {
							Packages = {
								["$className"] = "Folder",
								Facet = { ["$path"] = Files.join(Files.cwd(), "src") },
							},
						},
						StarterPlayer = {
							StarterPlayerScripts = { Fault = { ["$path"] = Files.join(Files.cwd(), source) } },
						},
					},
				})
			)
			local argv = { Run.lute(), "run", "tools/facet", "lint", source, "--types", "--project", project }
			local compact = Run.capture(argv)
			table.insert(argv, "--verbose")
			local full = Run.capture(argv)
			Verify.expect(compact.ok):toBe(false)
			Verify.expect(full.ok):toBe(false)
			Verify.expect(string.find(compact.stdout, "function(use: Facet.Use)", 1, true) ~= nil):toBe(true)
			Verify.expect(string.find(compact.stdout, "[shortened]", 1, true) ~= nil):toBe(true)
			Verify.expect(#compact.stdout < #full.stdout):toBe(true)
			local _, compactLocations = string.gsub(compact.stdout, ": error %[types%]", "")
			local _, fullLocations = string.gsub(full.stdout, ": error %[types%]", "")
			Verify.expect(compactLocations):toBe(fullLocations)
			Verify.expect(string.find(Files.read("artifacts/facet-lint/types.txt"), "(*CYCLE*)", 1, true) ~= nil)
				:toBe(true)
		end
	)
	harness:case("the public surface checker detects removed, added and changed exports", function()
		local result = Run.capture({ Run.lute(), "run", "tools/engine/check_public_surface.luau", "--selftest" })
		Verify.expect(result.ok):toBe(true)
		Verify.expect(string.find(result.stdout, "SELFTEST PASS", 1, true) ~= nil):toBe(true)
	end)
	harness:case("module loader resolves an explicit Luau file before directory candidates", {
		id = "tools/commands::loader::explicit Luau file",
		run = function()
			local loader = Loader.new()
			local explicit = loader.require("src/ui/rich_text.luau")
			Verify.expect(loader.require("src/ui/rich_text")):toBe(explicit)
			Verify.expect(type(explicit)):toBe("table")
		end,
	})
	harness:case("module loader reports a missing explicit Luau file", {
		id = "tools/commands::loader::missing Luau file",
		run = function()
			local ok, failure = pcall(Loader.new().require, "tests/lib/missing-macos-loader-fixture.luau")
			Verify.expect(ok):toBe(false)
			Verify.expect(string.find(tostring(failure), "no module at ", 1, true) ~= nil):toBe(true)
		end,
	})
	for _, command in commands do
		local build = command.cases
		if build == nil then
			continue
		end
		harness:suite(command.name, function()
			for _, case in build() do
				harness:case(case.name, {
					id = ("tools/commands::%s::%s"):format(command.name, case.name),
					tags = case.tags,
					run = function()
						Verify.expect(case.run()):toBe(nil)
					end,
				})
			end
		end)
	end
end
