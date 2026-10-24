--!strict

local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Json = require("../lib/json")
local Core = require("../../vendor/verify/src/core")
local Eval = require("../../vendor/verify/src/agent-eval")
local Lute = require("../../vendor/verify/src/lute")
local Compare = require("../../../eval/compare")
local Submission = require("../../../eval/submission")
local Setup = require("../lib/facetbench_setup")
local Process = require("@std/process")

local function preparePlaces()
	local protocol = Files.text("eval/authoring.md")
	Files.write(
		"artifacts/facetbench/plain-instructions.md",
		protocol .. "\n\n" .. Files.text("eval/arms/plain/AGENTS.md")
	)
	Files.write(
		"artifacts/facetbench/facet-instructions.md",
		protocol
			.. "\n\n"
			.. Files.text("eval/arms/facet/AGENTS.md")
			.. "\n\n"
			.. Files.text("skills/use-facet/SKILL.md")
	)
	local project = Json.decode(Files.read("eval/place.project.json"))
	Files.write("artifacts/facetbench/run-inputs/default.project.json", Json.pretty(project))
	local tree = assert(Json.asObject(Json.field(project, "tree")), "blank place has no DataModel")
	Json.set(tree, "ReplicatedStorage", { Packages = { ["$path"] = "Packages" } })
	Json.set(tree, "ServerStorage", { FacetDocs = { ["$path"] = "StudioDocs" } })
	Files.write("artifacts/facetbench/arm-facet/default.project.json", Json.pretty(project))
end

local function prepareCatalog(path: string, models: { string })
	local prepared = Setup.restrictCatalog(Json.decode(Files.read(path)), models)
	Files.write("artifacts/facetbench/run-inputs/.codex-model-catalog.json", Json.encode(prepared))
end

return {
	name = "facetbench",
	summary = "Prepare the thirty-minute run or compare its recorded evidence with Verify.",
	usage = "usage: lute run tools/facet facetbench prepare|compare|snapshot|check-submission [--suite PATH --model-catalog PATH --place PATH --evidence PATH --report PATH --run ID]",
	values = { "place", "evidence", "report", "run", "model-catalog", "suite" },
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
			local identity: Compare.Identity? = nil
			local suiteEvidence: string? = nil
			local suitePath = Cli.flag(invocation, "suite")
			if suitePath ~= nil then
				local suite =
					Eval.decodeSuite(Json.decode(Files.read(suitePath)), Files.absolute(suitePath), Eval.lute.loader())
				assert(
					#suite.tasks == 1 and #suite.agents == 1 and #suite.seeds == 1,
					"compare requires one task, author and seed"
				)
				identity = {
					suite = suite.id,
					task = suite.tasks[1].id,
					agent = suite.agents[1].id,
					model = assert(suite.agents[1].model, "compare requires an explicit author model"),
					seed = suite.seeds[1],
					judgeModel = assert(
						Json.stringField(suite.judge, "model"),
						"compare requires an explicit judge model"
					),
				}
				suiteEvidence = suite.evidence
			end
			local evidence: string = Cli.flag(invocation, "evidence") or suiteEvidence or "artifacts/facetbench/run"
			local files = Eval.lute.loader().files
			local results = if files.exists(evidence .. "/index.json")
				then Eval.load(evidence, files, Lute.parse)
				else {}
			local judgments = Eval.judge.load(evidence, files, Lute.parse)
			local report = Core.runCases(Compare.cases(results, judgments, identity), {
				executor = "recorded-run-comparison",
				environment = {
					evidence = evidence,
					scope = "one paired game; no population confidence claim",
					expectedIdentity = Json.canonical(identity or Compare.DEFAULT_IDENTITY),
				},
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
		local models = Setup.authorModels(Json.decode(Files.read(Cli.flag(invocation, "suite") or "eval/run.json")))
		prepareCatalog(Cli.flag(invocation, "model-catalog") or Files.join(codexDirectory, "models_cache.json"), models)
		preparePlaces()
		print(
			"facetbench: prepared blank places, author guidance, and restricted tool profiles: "
				.. table.concat(models, ", ")
		)
		return 0
	end,
} :: Cli.Command
