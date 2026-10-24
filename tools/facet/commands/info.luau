--!strict
local Verify = require("../../vendor/verify/src/core")

local json = require("@std/json")
local Cli = require("../lib/cli")
local DocsIndex = require("../lib/docs_index")
local Files = require("../lib/files")

local USAGE = [[usage: lute run tools/facet info [--full] [--json]

Prints what an author needs first: the Facet version, how to mount a screen,
which control fits each player task, the starter blocks and the next commands.
It is short. Read the contract of each control that you choose with
lute run tools/facet docs <Control>. Use --full for the complete control map
and starter block list.]]

local MOUNT = [[local Facet = require(game:GetService("ReplicatedStorage").Packages.Facet)
local Compose = Facet.Compose
local app = Facet.app({ name = "Counter", parent = playerGui })
local UI = app.UI
app.mount(function()
	local count = Compose.cell(0)
	return UI.Screen "Counter" {
		UI.Text "Count" { text = function(use) return tostring(use(count)) end },
		UI.Button "Add" { label = "Add one", onActivate = function() count:update(function(n) return n + 1 end) end },
	}
end)]]

local COMPOSE = {
	{ "Compose.cell(value)", "state that the screen owns; cell:set(value), cell:update(fn), cell:peek()" },
	{ "Compose.formula(function(use) ... end)", "a value derived from other cells" },
	{ "function(use) return use(cell) end", "a property that follows a cell" },
	{ "Compose.show(readable, build)", "a branch that mounts and unmounts with a condition" },
	{ "Compose.keyed({ from, key, render })", "a list of children keyed by id" },
	{ "Compose.cleanup(fn)", "release a connection or a timer with its owner" },
	{ "app.runtime.tween, app.runtime.spring", "animation that the owner stops" },
}

local RULES = {
	"Make one runtime and mount one root. Each screen, panel and overlay is a Compose.show branch or a portal of that tree, switched by Compose state.",
	'Write controls in the named form, UI.Button "Buy" { ... }, so that strict mode checks every option without casts.',
	"Native properties keep their Roblox names (Size, LayoutOrder). Control options use lower camel case (label, onActivate).",
	"State is Compose cells. Read a cell inside a property function with use(cell). Change it with cell:set(value).",
	"Put Roblox objects through Host = app.runtime.constructors, for example Host.UIListLayout { ... }.",
	"The theme owns paint, type, spacing and motion. Use textRole, appearance, gap and padding tokens, not literal colors and sizes.",
	"Controls own gamepad selection, touch targets, safe insets and reduced motion. Do not rebuild them.",
}

local COMMANDS = {
	{ "docs <path>", "one task recipe, control card or option node" },
	{ "docs --search TEXT", "node paths and one-line summaries" },
	{ "lint [paths]", "Facet usage problems and strict types in your interface code" },
	{ "preview [--device ID]...", "screenshots and an outline of a screen that you must see; not a flow test" },
	{
		"audit --tap TEXT...",
		"once, when the screens are done, with one --tap for each control that opens a screen, for example --tap Shop; without --tap it checks only the first screen",
	},
}

local function version(): string
	if not Files.isFile("src/init.luau") then
		for _, candidate in { "Packages/Facet/init.luau", "Packages/Facet/src/init.luau" } do
			if Files.isFile(candidate) then
				local found = string.match(Files.read(candidate), 'VERSION%s*=%s*"([^"]+)"')
				if found ~= nil then
					return found
				end
			end
		end
		return "unknown"
	end
	return string.match(Files.read("src/init.luau"), 'VERSION%s*=%s*"([^"]+)"') or "unknown"
end

type Facts = { version: string, tokens: number, hasTasks: boolean }

local function report(full: boolean?): (string, Facts)
	local tasks = Files.read("docs/guide/choosing-controls.md")
	local blocks = Files.read("examples/blocks/README.md")
	if not full then
		local text = table.concat({
			("Facet %s: Roblox UI controls on Compose."):format(version()),
			"",
			"```luau",
			MOUNT,
			"```",
			"",
			"Use one app and one mounted root. Use app.runtime.constructors as Host for native objects.",
			"Use named controls, theme tokens and Compose cells. Read properties with function(use: Facet.Use).",
			"Compose.cleanup releases resources; Compose.show owns branches. Keep durable row state in the model.",
			"",
			"Task -> controls -> short recipe (lute run tools/facet docs NAME):",
			"  Gameplay HUD -> Composition, Region -> Tasks.hud",
			"  Lists, tiles, filters -> VirtualList, VirtualGrid, Table -> Tasks.collection-detail",
			"  Child pages -> NavigationStack; tabs -> TabView; confirmation -> Alert",
			"  Settings -> Toggle, Slider, Picker; text entry -> TextInput",
			"  Text fit -> Text-fit; type errors -> Types",
			"",
			"Start with: lute run tools/facet docs (the task map). Open one recipe, then a node for a missing detail.",
			"Starter components: examples/blocks/. More controls and blocks: info --full.",
			"Check a coherent edit: verify --tap TEXT... runs types, lint, build, audit and screenshots together.",
			"Use verify --static without Studio. File discovery: project [directory]; rg and Git are optional.",
		}, "\n")
		return text, { version = version(), tokens = math.ceil(#text / 4), hasTasks = tasks ~= nil }
	end
	local lines: { string } = {
		("Facet %s: Roblox UI controls on Compose and the native engine."):format(version()),
		"",
		"## Mount a screen",
		"",
		"```luau",
		MOUNT,
		"```",
		"",
		"## Rules",
		"",
	}
	for _, rule in RULES do
		table.insert(lines, "- " .. rule)
	end
	table.insert(lines, "")
	table.insert(lines, "## Compose essentials")
	table.insert(lines, "")
	table.insert(
		lines,
		"Facet includes Compose as Facet.Compose. Use it for state, ownership, branches, lists and motion. Do not build a second state system."
	)
	table.insert(lines, "")
	for _, entry in COMPOSE do
		table.insert(lines, ("- `%s`: %s."):format(entry[1], entry[2]))
	end
	if tasks ~= nil then
		table.insert(lines, "")
		table.insert(lines, (string.gsub(tasks, "^##", "##", 1)))
	end
	if blocks ~= nil then
		table.insert(lines, "")
		table.insert(lines, blocks)
	end
	table.insert(lines, "")
	table.insert(lines, "## Next commands")
	table.insert(lines, "")
	for _, entry in COMMANDS do
		table.insert(lines, ("- `lute run tools/facet %s`: %s."):format(entry[1], entry[2]))
	end
	local text = table.concat(lines, "\n")
	return text, { version = version(), tokens = math.ceil(#text / 4), hasTasks = tasks ~= nil }
end

local function run(invocation: Cli.Invocation): number
	local unknown = Cli.unknownFlags(invocation, { "full" })
	if unknown ~= nil or #invocation.positional > 0 then
		if unknown ~= nil then
			print("facet info: unknown flags " .. unknown)
		end
		print(USAGE)
		return 2
	end
	local text, facts = report(Cli.switch(invocation, "full"))
	local value: json.Value = { version = facts.version, tokens = facts.tokens, text = text }
	Cli.emit(invocation, value, text)
	return 0
end

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "the overview names the version, the mount recipe, the task map and the commands", {
		id = prefix .. "the overview names the version, the mount recipe, the task map and the commands",
		run = function(test: Verify.Context)
			local text, facts = report(true)
			Verify.expect(facts.version ~= "unknown"):toBeTrueWith("the version is unknown")
			Verify.expect(facts.hasTasks == true):toBeTrueWith("the task-to-control map is missing")
			Verify.expect(string.find(text, "Facet.app(", 1, true) ~= nil):toBeTrueWith("the mount recipe is missing")
			Verify.expect(string.find(text, "| Ask for a brief confirmation | Alert. |", 1, true) ~= nil)
				:toBeTrueWith("a task row is missing")
			Verify.expect(string.find(text, "tools/facet docs", 1, true) ~= nil)
				:toBeTrueWith("the docs command is missing")
			Verify.expect(string.find(text, "Compose.cell", 1, true) ~= nil)
				:toBeTrueWith("the Compose essentials are missing")
		end,
	})
	harness:case(prefix .. "the overview stays short", {
		id = prefix .. "the overview stays short",
		run = function(test: Verify.Context)
			local _, facts = report()
			Verify.expect(facts.tokens < 4000):toBeTrueWith(`the overview is {facts.tokens} tokens`)
		end,
	})
	harness:case(prefix .. "every control that the overview recipe uses has a documented section", {
		id = prefix .. "every control that the overview recipe uses has a documented section",
		run = function(test: Verify.Context)
			local sections = DocsIndex.load(".")
			for _, name in { "Screen", "Button", "Sheet", "Text", "Mounting" } do
				if DocsIndex.find(sections, name) == nil then
					error(`{name} has no section`, 0)
				end
			end
		end,
	})
end

local command: Cli.Command = {
	name = "info",
	summary = "Print the Facet overview for an author: mounting, the task-to-control map and the next commands.",
	usage = USAGE,
	register = register,
	run = run,
}

return command
