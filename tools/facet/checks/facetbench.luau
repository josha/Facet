--!strict
local Verify = require("../../vendor/verify/src/core")

local Eval = require("../../vendor/verify/src/agent-eval")
local Files = require("../lib/files")
local Json = require("../lib/json")
local Rule = require("../lib/rule")

local function check(context: Rule.Context): { string }
	local findings: { string } = {}
	local function need(condition: boolean, message: string)
		if not condition then
			table.insert(findings, message)
		end
	end
	local source = context.path("eval/run.json")
	local loaded, value = pcall(function()
		local loader = Eval.lute.loader()
		local files = loader.files
		local generated = {
			[Files.absolute(context.path("artifacts/facetbench/run-inputs"))] = true,
			[Files.absolute(context.path("artifacts/facetbench/arm-facet"))] = true,
		}
		local protocol = Files.read(context.path("eval/authoring.md"))
		local instructions = {
			[Files.absolute(context.path("artifacts/facetbench/plain-instructions.md"))] = protocol
				.. "\n\n"
				.. Files.read(context.path("eval/arms/plain/AGENTS.md")),
			[Files.absolute(context.path("artifacts/facetbench/facet-instructions.md"))] = protocol
				.. "\n\n"
				.. Files.read(context.path("eval/arms/facet/AGENTS.md"))
				.. "\n\n"
				.. Files.read(context.path("skills/use-facet/SKILL.md")),
		}
		local contractFiles = table.clone(files)
		contractFiles.exists = function(path: string): boolean
			local absolute = Files.absolute(path)
			return generated[absolute] == true or instructions[absolute] ~= nil or files.exists(path)
		end
		contractFiles.read = function(path: string): string
			local prepared = instructions[Files.absolute(path)]
			if prepared ~= nil then
				return prepared
			end
			return files.read(path)
		end
		loader.files = contractFiles
		return Eval.decodeSuite(Json.decode(Files.read(source)), Files.absolute(source), loader)
	end)
	if not loaded then
		return { "run does not load: " .. tostring(value) }
	end
	local suite = value :: Eval.Suite
	need(#suite.tasks == 1, "the run needs exactly one game task")
	need(#suite.arms == 2 and suite.arms[1].id == "plain" and suite.arms[2].id == "facet", "compare Plain and Facet")
	need(#suite.agents > 0, "the run needs an author model")
	local claude = false
	for _, agent in suite.agents do
		need(agent.options.effort == "medium", "use Medium author reasoning")
		local arguments: Json.Array = Json.asArray(agent.options.arguments) or {}
		if agent.adapter == "claude-code" then
			claude = true
			need(agent.model == "claude-opus-5-5", "use the Opus 5.5 Claude author")
			need(agent.options.settingSources == "project", "the author must not inherit user settings")
			need(table.find(arguments, "--tools=") ~= nil, "Studio-only author must disable every built-in tool")
			continue
		end
		need(agent.adapter == "codex" and agent.model == "gpt-6.1-sol", "use the Sol 6.1 Codex author")
		need(agent.options.sandbox == "read-only", "the author filesystem must be read-only")
		local disabled: { [string]: boolean } = {}
		local isolated = false
		for index, argument in arguments do
			isolated = isolated or argument == "--ignore-user-config"
			if argument == "--disable" then
				local feature = arguments[index + 1]
				if type(feature) == "string" then
					disabled[feature] = true
				end
			end
		end
		need(isolated, "the author must not inherit unrelated user tools")
		for _, feature in
			{ "shell_tool", "view_image", "apps", "multi_agent", "computer_use", "browser_use", "plugins" }
		do
			need(disabled[feature] == true, "Studio-only author must disable " .. feature)
		end
	end
	for _, arm in suite.arms do
		need(arm.setup.studio ~= nil and arm.setup.studio.keep == true, "preserve the authored Studio place")
		if claude then
			need(arm.setup.env.CLAUDE_CODE_DISABLE_CLAUDE_MDS == "1", "the author must not read user instructions")
			need(arm.setup.env.CLAUDE_CODE_DISABLE_AUTO_MEMORY == "1", "the author must not read user memory")
			need(arm.setup.env.ENABLE_TOOL_SEARCH == "false", "the author must see every Studio tool")
		end
	end
	for _, game in suite.tasks do
		need(game.id == "run" and game.from == nil, "the game must start from blank without follow-up turns")
		need(game.budgets.wallSeconds == 1800, "the author deadline must be 1800 seconds")
		local devices: { [string]: boolean } = {}
		for _, device in game.devices do
			devices[device.id] = true
		end
		for _, id in { "desktop", "phone-portrait", "phone-landscape", "tablet", "console" } do
			need(devices[id] == true, "missing device: " .. id)
		end
		local play = false
		local capture = false
		local unchanged = false
		for _, item in game.checks do
			if item.id == "play" and item.kind == "verify" and item.required then
				play = true
			end
			if item.id == "submission" and item.kind == "verify" and item.required then
				capture = true
			end
			if item.id == "submission-unchanged" and item.kind == "verify" and item.required then
				unchanged = table.find(item.after, "play") ~= nil
			end
			if item.id == "build" or item.id == "navigation" or item.id == "play" or item.id == "types" then
				local usesFrozen = false
				for _, argument in item.argv do
					need(
						not string.find(argument, "{workspace}", 1, true),
						item.id .. " evaluates mutable author files"
					)
					usesFrozen = usesFrozen or string.find(argument, "{evidence}/submission/game.rbxl", 1, true) ~= nil
				end
				need(usesFrozen, item.id .. " must evaluate the frozen submission")
			end
		end
		need(play, "independent player-outcome evaluation is not connected; build and types cannot establish a pass")
		need(
			capture and unchanged,
			"capture the submission before evaluation and check integrity after player outcomes"
		)
	end
	local starter = context.path("eval/tasks/run/starter")
	for _, relative in Files.walk(starter) do
		need(relative == ".gitkeep", "the blank starter contains an author asset: " .. relative)
	end
	for _, retired in { "games.json", "slice.json", "extended.json", "extended-spec.json" } do
		need(not Files.isFile(context.path("eval/" .. retired)), "retired authoring mode remains: " .. retired)
	end
	return findings
end

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "rejects mutable evaluation paths and an extended author deadline", {
		id = prefix .. "rejects mutable evaluation paths and an extended author deadline",
		run = function(test: Verify.Context)
			local files: { [string]: string } = {}
			for _, relative in
				{
					"eval/run.json",
					"eval/authoring.md",
					"eval/tasks/run/task.json",
					"eval/tasks/run/brief.md",
					"eval/arms/plain/AGENTS.md",
					"eval/arms/facet/AGENTS.md",
					"skills/use-facet/SKILL.md",
				}
			do
				files[relative] = Files.read(relative)
			end
			files["eval/tasks/run/starter/.gitkeep"] = ""
			Rule.within(test, files, function(context)
				local initial = check(context)
				if #initial ~= 0 then
					Verify.expect(Rule.describe(initial)):toBeNil()
					return
				end
				local suitePath = context.path("eval/run.json")
				local suiteSource = Files.read(suitePath)
				Files.write(
					suitePath,
					(
						string.gsub(
							suiteSource,
							"artifacts/facetbench/run%-inputs",
							"artifacts/facetbench/missing-inputs"
						)
					)
				)
				if not Rule.contains(check(context), "names a missing path") then
					error("an unknown generated input path was accepted", 0)
				end
				Files.write(suitePath, (string.gsub(suiteSource, '"shell_tool"', '"unused_feature"')))
				if not Rule.contains(check(context), "must disable shell_tool") then
					error("filesystem tools were accepted", 0)
				end
				Files.write(suitePath, suiteSource)
				Files.write(context.path("eval/tasks/run/starter/solution.rbxlx"), "asset")
				if not Rule.contains(check(context), "contains an author asset") then
					error("a prebuilt starter asset was accepted", 0)
				end
				Files.remove(context.path("eval/tasks/run/starter/solution.rbxlx"))
				local path = context.path("eval/tasks/run/task.json")
				local original = Files.read(path)
				Files.write(path, (string.gsub(original, "{evidence}/submission/game.rbxl", "{workspace}")))
				if not Rule.contains(check(context), "evaluates mutable author files") then
					error("mutable author files were accepted", 0)
				end
				Files.write(path, (string.gsub(original, '"wallSeconds": 1800', '"wallSeconds": 1801')))
				Verify.expect(Rule.contains(check(context), "deadline must be 1800"))
					:toBeTrueWith("an extended deadline was accepted")
			end)
		end,
	})
end

local rule: Rule.Rule = {
	name = "facetbench",
	summary = "Check the single blank-project run and its required independent evaluation.",
	check = check,
	register = register,
}

return rule
