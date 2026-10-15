--!strict

local process = require("@std/process")
local Files = require("../lib/files")
local Rule = require("../lib/rule")
local Case = require("../lib/case")
local Bench = require("../lib/facetbench")

local TURNS = Bench.turns

local function overlay(source: string, destination: string)
	for _, relative in Files.walk(source) do
		local path = Files.join(source, relative)
		if Files.isFile(path) then
			Files.write(Files.join(destination, relative), Files.read(path))
		end
	end
end

local function check(context: Rule.Context): { string }
	Bench.prepare(context.root)
	local findings: { string } = {}
	for index, id in TURNS do
		for _, arm in { "strong", "weak" } do
			local relative = "artifacts/facetbench/reference-headless/" .. id .. "/" .. arm
			local workspace = context.path(relative)
			Files.remove(workspace)
			overlay(context.path("eval/tasks/racing-hub/starter"), workspace)
			overlay(context.path("eval/validation/racing-hub/strong/src"), Files.join(workspace, "src"))
			overlay(context.path("eval/validation/followups/strong"), workspace)
			overlay(context.path(Bench.starter), workspace)
			for earlier = 1, index do
				overlay(context.path("eval/validation/" .. TURNS[earlier] .. "/strong"), workspace)
			end
			if arm == "weak" then
				overlay(context.path("eval/validation/" .. id .. "/weak"), workspace)
			end
			local commands = {
				{ "lute", "run", "tools/play/host/contract.luau", Bench.starter, relative },
				{
					"lute",
					"run",
					"eval/arms/shared/tools/typecheck/check.luau",
					"--workspace",
					relative,
					"--definitions",
					"artifacts/facetbench/arm-shared/tools/typecheck/roblox.d.luau",
					"src/client",
					"src/server",
					"src/shared",
				},
				{ "lute", "run", "tools/facet", "lint", relative .. "/src/client" },
				{ "rojo", "build", relative .. "/default.project.json", "-o", relative .. "/reference.rbxlx" },
			}
			for commandIndex, argv in commands do
				local result = process.run(argv, { cwd = context.root, timeout = 600 })
				Files.write(
					Files.join(workspace, "check-" .. tostring(commandIndex) .. ".log"),
					result.stdout .. result.stderr
				)
				if not result.ok then
					table.insert(
						findings,
						id .. "/" .. arm .. ": " .. table.concat(argv, " ") .. "\n" .. result.stdout .. result.stderr
					)
				end
			end
			print("reference headless: " .. id .. "/" .. arm)
		end
	end
	return findings
end

return {
	name = "facetbench-references",
	summary = "Build and type-check the extended hub references without Studio.",
	check = check,
	cases = function(): { Rule.Case }
		return {
			{
				name = "a turn overlay preserves prior files and replaces changed files",
				run = function()
					return Rule.within({
						["source/changed.luau"] = "new",
						["target/changed.luau"] = "old",
						["target/prior.luau"] = "keep",
					}, function(context)
						overlay(context.path("source"), context.path("target"))
						return Case.same({
							Files.read(context.path("target/changed.luau")),
							Files.read(context.path("target/prior.luau")),
						}, { "new", "keep" })
					end)
				end,
			},
		}
	end,
} :: Rule.Rule
