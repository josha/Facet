--!strict
local Verify = require("../../vendor/verify/src/core")

local ConsumerTypes = require("../lib/consumer_types")
local Analyzer = require("../lib/analyzer")
local DocsIndex = require("../lib/docs_index")
local Files = require("../lib/files")
local Json = require("../lib/json")
local Rule = require("../lib/rule")

local function check(context: Rule.Context): { string }
	local directory = context.path("artifacts/verify/docs-samples")
	Files.makeDirectory(directory)
	local targets: { string } = {}
	local origins: { [string]: { file: string, line: number, prefix: number } } = {}
	for _, node in DocsIndex.load(context.root) do
		if node.kind ~= "recipe" and node.kind ~= "card" then
			continue
		end
		local source = Files.text(context.path(node.file))
		local index = 0
		for position, matched in string.gmatch(source, "()```luau\n(.-)```") do
			local start = tonumber(position) :: number
			local code = matched :: string
			index += 1
			local target = Files.join(directory, "samples", node.path .. "-" .. index .. ".luau")
			local prefix = "--!strict\n"
			if node.kind == "card" then
				prefix ..= "local Facet = require(game.ReplicatedStorage.Packages.Facet)\nlocal app = Facet.app()\nlocal UI = app.UI\napp.mount(function()\n"
			end
			local _, line = string.gsub(string.sub(source, 1, start), "\n", "")
			local _, count = string.gsub(prefix, "\n", "")
			Files.write(
				target,
				prefix
					.. code
					.. (if node.kind == "card" then "return app.runtime.constructors.Frame({})\nend)\n" else "")
			)
			table.insert(targets, target)
			origins[string.lower(Files.absolute(target))] = { file = node.file, line = line + 2, prefix = count }
		end
		local _, fences = string.gsub(source, "```luau\n", "")
		if fences ~= index then
			return { node.file .. ": unclosed Luau sample" }
		end
	end
	if #targets == 0 then
		return { "no recipe or control card Luau samples found" }
	end
	table.sort(targets)
	local project = Files.join(directory, "default.project.json")
	Files.write(
		project,
		Json.encode({
			name = "Docs",
			tree = {
				["$className"] = "DataModel",
				ReplicatedStorage = {
					Packages = {
						["$className"] = "Folder",
						Facet = { ["$path"] = Files.absolute(context.path("src")) },
					},
				},
				StarterPlayer = {
					StarterPlayerScripts = {
						Samples = { ["$path"] = Files.absolute(Files.join(directory, "samples")) },
					},
				},
			},
		})
	)
	local diagnostics, problem = ConsumerTypes.check(targets, project, "new")
	if problem then
		return { problem }
	end
	local findings: { string } = {}
	local checked: { Analyzer.Diagnostic } = diagnostics or {}
	for _, diagnostic in checked do
		local origin = origins[string.lower(Files.absolute(diagnostic.file))]
		table.insert(
			findings,
			if origin
				then `{origin.file}:{origin.line + diagnostic.line - origin.prefix - 1}: {diagnostic.message}`
				else `{diagnostic.file}:{diagnostic.line}: {diagnostic.message}`
		)
	end
	print(`docs-samples: {#targets} strict Luau samples`)
	return findings
end

return {
	name = "docs-samples",
	summary = "Type-check every recipe and control card sample with the consumer verifier settings.",
	check = check,
	register = function(harness: Verify.Harness, prefix: string): ()
		harness:case(prefix .. "control cards compile inside a mount that returns a host node", {
			id = prefix .. "control cards compile inside a mount that returns a host node",
			run = function(test: Verify.Context): ()
				Rule.within(test, {
					["src/init.luau"] = [[--!strict
return {
	app = function()
		return {
			UI = {},
			runtime = { constructors = { Frame = function(_props: {}): {} return {} end } },
			mount = function(build: () -> {}) build() end,
		}
	end,
}
]],
					["docs/reference/nodes/Value.card.md"] = "# Value\n\n```luau\nlocal value: number = 1\nprint(value)\n```\n",
				}, function(context)
					Verify.expect(check(context)):toEqual({})
				end)
			end,
		})
		harness:case(
			prefix .. "the consumer analyzer accepts a typed sample and rejects a scalar fault at its Markdown line",
			{
				id = prefix
					.. "the consumer analyzer accepts a typed sample and rejects a scalar fault at its Markdown line",
				run = function(test: Verify.Context): ()
					Rule.within(test, {
						["src/init.luau"] = "--!strict\nreturn {}\n",
						["docs/reference/nodes/Tasks.sample.md"] = "# Sample\n\nA typed value.\n\n```luau\nlocal value: number = 1\nprint(value)\n```\n",
					}, function(context)
						local valid = check(context)
						if #valid > 0 then
							Verify.expect(table.concat(valid, "\n")):toBeNil()
							return
						end
						Files.write(
							context.path("docs/reference/nodes/Tasks.sample.md"),
							'# Sample\n\nA typed value.\n\n```luau\nlocal value: number = "wrong"\nprint(value)\n```\n'
						)
						local invalid = check(context)
						Verify.expect(#invalid):toBe(1)
						Verify.expect(string.find(invalid[1] or "", "Tasks.sample.md:6:", 1, true) ~= nil)
							:toBeTrueWith("Markdown source location")
					end)
				end,
			}
		)
	end,
} :: Rule.Rule
