--!strict

local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Json = require("../lib/json")
local Core = require("../../vendor/verify/src/core")
local Eval = require("../../vendor/verify/src/agent-eval")
local Lute = require("../../vendor/verify/src/lute")
local Compare = require("../../../eval/compare")
local Submission = require("../../../eval/submission")
local Process = require("@std/process")

local function preparePlaces()
	Files.write(
		"artifacts/facetbench/facet-instructions.md",
		Files.text("eval/arms/facet/AGENTS.md") .. "\n\n" .. Files.text("skills/use-facet/SKILL.md")
	)
	local project = Json.decode(Files.read("eval/place.project.json"))
	Files.write("artifacts/facetbench/run-inputs/default.project.json", Json.pretty(project))
	local tree = assert(Json.asObject(Json.field(project, "tree")), "blank place has no DataModel")
	Json.set(tree, "ReplicatedStorage", { Packages = { ["$path"] = "Packages" } })
	Json.set(tree, "ServerStorage", { FacetDocs = { ["$path"] = "StudioDocs" } })
	Files.write("artifacts/facetbench/arm-facet/default.project.json", Json.pretty(project))
end

local function prepareCatalog(path: string)
	local catalog = assert(Json.asObject(Json.decode(Files.read(path))), "invalid Codex model catalog")
	local models = assert(Json.asArray(catalog.models), "Codex model catalog has no models")
	local found = false
	for _, value in models do
		local model = assert(Json.asObject(value), "invalid Codex model entry")
		if model.slug == "gpt-6.1-sol" then
			Json.set(model, "apply_patch_tool_type", Json.null)
			Json.set(model, "multi_agent_version", Json.null)
			Json.set(model, "experimental_supported_tools", Json.array())
			found = true
		end
	end
	assert(found, "Codex model catalog does not contain gpt-6.1-sol")
	local prepared = Json.object()
	Json.set(prepared, "models", models)
	Files.write("artifacts/facetbench/run-inputs/.codex-model-catalog.json", Json.encode(prepared))
end

return {
	name = "facetbench",
	summary = "Prepare the thirty-minute run or compare its recorded evidence with Verify.",
	usage = "usage: lute run tools/facet facetbench prepare|compare|snapshot|check-submission [--model-catalog PATH --place PATH --evidence PATH --report PATH --run ID]",
	values = { "place", "evidence", "report", "run", "model-catalog" },
	run = function(invocation: Cli.Invocation): number
		local action = invocation.positional[1]
		if #invocation.positional == 1 and (action == "snapshot" or action == "check-submission") then
			local place = Cli.flag(invocation, "place")
			local evidence = assert(Cli.flag(invocation, "evidence"), "--evidence is required")
			local destination = assert(Cli.flag(invocation, "report"), "--report is required")
			local runId = assert(Cli.flag(invocation, "run"), "--run is required")
			local report = if action == "snapshot"
				then Submission.capture(
					assert(place, "--place must name the saved Studio place"),
					evidence .. "/submission",
					runId
				)
				else Submission.validate(place, evidence .. "/submission")
			Lute.gate.writeReport(destination, runId, report)
			print(Core.format(report))
			return if report.passed == report.total then 0 else 1
		end
		if #invocation.positional == 1 and invocation.positional[1] == "compare" then
			local evidence = Cli.flag(invocation, "evidence") or "artifacts/facetbench/run"
			local files = Eval.lute.loader().files
			local results = if files.exists(evidence .. "/index.json")
				then Eval.load(evidence, files, Lute.parse)
				else {}
			local judgments = Eval.judge.load(evidence, files, Lute.parse)
			local report = Core.runCases(Compare.cases(results, judgments), {
				executor = "recorded-run-comparison",
				environment = { evidence = evidence, scope = "one paired game; no population confidence claim" },
			}, os.clock)
			Files.makeDirectory(evidence)
			Lute.gate.writeReport(evidence .. "/comparison.verify.json", "facetbench-run-comparison", report)
			print(Core.format(report))
			for _, result in report.results do
				if result.status ~= "passed" then
					return 1
				end
			end
			return 0
		end
		assert(#invocation.positional == 1 and invocation.positional[1] == "prepare", "expected prepare")
		local codexDirectory = Process.env.CODEX_HOME
		if codexDirectory == nil then
			local profile = Process.env.USERPROFILE or Process.env.HOME
			assert(profile, "pass --model-catalog PATH when the user profile is unavailable")
			codexDirectory = Files.join(profile, ".codex")
		end
		prepareCatalog(Cli.flag(invocation, "model-catalog") or Files.join(codexDirectory, "models_cache.json"))
		preparePlaces()
		print("facetbench: prepared the blank places, Facet skill, and restricted Sol tool profile")
		return 0
	end,
} :: Cli.Command
