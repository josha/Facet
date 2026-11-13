--!strict

local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Json = require("../lib/json")
local Run = require("../lib/run")
local Core = require("../../vendor/verify/src/core")
local Eval = require("../../vendor/verify/src/agent-eval")
local Lute = require("../../vendor/verify/src/lute")
local Compare = require("../../../eval/compare")
local Submission = require("../../../eval/submission")
local Admission = require("../../../eval/admission")
local Preflight = require("../../../eval/preflight")
local Hash = require("../lib/hash")
local Look = require("../lib/look")
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
	local kit =
		Run.capture({ Run.lute(), "run", "tools/facet", "kit", "--out", "artifacts/facetbench/arm-facet", "--force" })
	assert(kit.ok, "facetbench: the Facet author kit did not build: " .. kit.stdout .. kit.stderr)
	local tree = assert(Json.asObject(Json.field(project, "tree")), "blank place has no DataModel")
	Json.set(tree, "ReplicatedStorage", { Packages = { ["$path"] = "Packages" } })
	Json.set(tree, "ServerStorage", { FacetDocs = { ["$path"] = "StudioDocs" } })
	Files.write("artifacts/facetbench/arm-facet/default.project.json", Json.pretty(project))
end

local function prepareCatalog(path: string, models: { string })
	local prepared = Setup.restrictCatalog(Json.decode(Files.read(path)), models)
	Files.write("artifacts/facetbench/run-inputs/.codex-model-catalog.json", Json.encode(prepared))
end

local function candidates(manifest: unknown): ({ Admission.Candidate }, { string })
	local list: { Admission.Candidate } = {}
	local entries: Json.Array = assert(Json.asArray(Json.field(manifest, "captures")), "the manifest has no captures")
	for position, entry in entries do
		local function need(key: string): string
			return assert(Json.stringField(entry, key), ("capture %d has no %s"):format(position, key))
		end
		local expected = Json.field(entry, "expect")
		local expect: Admission.Expectation? = nil
		if expected ~= nil then
			local modal = Json.field(expected, "modal")
			local stated: Admission.Expectation = {
				visible = Json.strings(Json.field(expected, "visible")),
				absent = Json.strings(Json.field(expected, "absent")),
			}
			if type(modal) == "boolean" then
				stated.modal = modal
			elseif modal == "any" then
				stated.modal = "any"
			end
			expect = stated
		end
		local candidate: Admission.Candidate = {
			id = need("id"),
			arm = need("arm"),
			device = need("device"),
			screen = need("screen"),
			image = need("image"),
			dump = Json.stringField(entry, "dump"),
			attempt = Json.numberField(entry, "attempt"),
			expect = expect,
		}
		table.insert(list, candidate)
	end
	local arms = assert(Json.strings(Json.field(manifest, "arms")), "the manifest names no arms")
	return list, arms
end

local function admit(evidence: string): number
	local source = Files.join(evidence, "judge-candidates.json")
	assert(Files.isFile(source), "facetbench admit: " .. source .. " is missing")
	local list, arms = candidates(Json.decode(Files.read(source)))
	local review = Admission.review(list, function(path: string)
		return Look.load(Files.join(evidence, path))
	end, arms)
	local decisions: { Json.Object } = {}
	local admitted, excluded = 0, 0
	local lines: { string } = {}
	for _, decision in review.decisions do
		local image = Files.join(evidence, decision.image)
		local held = Files.isFile(image)
		local reasons = table.clone(decision.reasons)
		if not held then
			table.insert(reasons, "the image file is missing")
		end
		local ok = decision.admitted and held
		admitted += if ok then 1 else 0
		excluded += if ok then 0 else 1
		local entry: Json.Object = {
			id = decision.id,
			arm = decision.arm,
			device = decision.device,
			screen = decision.screen,
			attempt = decision.attempt,
			image = decision.image,
			sha256 = if held then Hash.sha256(Files.read(image)) else Json.null,
			admitted = ok,
			reasons = reasons,
		}
		table.insert(decisions, entry)
		if not ok then
			table.insert(lines, ("  excluded %s: %s"):format(decision.id, table.concat(reasons, "; ")))
		end
	end
	local matched = 0
	local pairs: { Json.Object } = {}
	for _, pair in review.pairs do
		local complete = pair.admitted
		for _, id in pair.captures do
			for _, decision in decisions do
				if Json.stringField(decision, "id") == id and Json.field(decision, "admitted") ~= true then
					complete = false
				end
			end
		end
		matched += if complete then 1 else 0
		local entry: Json.Object = {
			device = pair.device,
			screen = pair.screen,
			admitted = complete,
			captures = pair.captures,
			reason = if complete then Json.null else pair.reason or "a capture of the pair was excluded",
		}
		table.insert(pairs, entry)
		if not complete then
			table.insert(
				lines,
				("  not compared %s/%s: %s"):format(pair.device, pair.screen, pair.reason or "a capture was excluded")
			)
		end
	end
	Files.write(
		Files.join(evidence, "admission.json"),
		Json.pretty({ schema = "facetbench-admission/1", decisions = decisions, pairs = pairs })
	)
	print(
		("facetbench admit: %d capture(s) admitted, %d excluded; %d of %d pair(s) can be compared"):format(
			admitted,
			excluded,
			matched,
			#review.pairs
		)
	)
	if #lines > 0 then
		print(table.concat(lines, "\n"))
	end
	print("Every candidate and each reason is kept in " .. Files.join(evidence, "admission.json"))
	return 0
end

local function preflight(invocation: Cli.Invocation): number
	local evidence = assert(Cli.flag(invocation, "evidence"), "--evidence is required")
	local destination = assert(Cli.flag(invocation, "report"), "--report is required")
	local runId = assert(Cli.flag(invocation, "run"), "--run is required")
	local suitePath = Cli.flag(invocation, "suite") or "eval/run.json"
	local chosen = assert(Cli.flag(invocation, "agent"), "--agent is required")
	local required: { string }? = nil
	for _, agent in Json.asArray(Json.field(Json.decode(Files.read(suitePath)), "agents")) or {} do
		if Json.stringField(agent, "id") == chosen then
			required = Json.strings(Json.field(Json.field(agent, "options"), "preflight")) or {}
		end
	end
	assert(required, "the suite has no author " .. chosen)
	local source = Files.join(evidence, "preflight", "images.json")
	local record: Preflight.Record? = nil
	if Files.isFile(source) then
		local found = Json.decode(Files.read(source))
		local made, sent = Json.field(found, "generation"), Json.field(found, "upload")
		local read: Preflight.Record = {
			agent = Json.stringField(found, "agent") or "",
			tools = Json.strings(Json.field(found, "tools")) or {},
			authorStart = Json.numberField(found, "authorStart"),
		}
		if made ~= nil then
			read.generation = {
				ok = Json.field(made, "ok") == true,
				file = Json.stringField(made, "file"),
				bytes = Json.numberField(made, "bytes"),
				at = Json.numberField(made, "at"),
			}
		end
		if sent ~= nil then
			read.upload = {
				ok = Json.field(sent, "ok") == true,
				tool = Json.stringField(sent, "tool"),
				assetId = Json.stringField(sent, "assetId"),
				loaded = Json.field(sent, "loaded") == true,
				at = Json.numberField(sent, "at"),
			}
		end
		record = read
		assert(read.agent == chosen, "preflight/images.json is for another author: " .. read.agent)
	end
	local report = Core.runCases(Preflight.cases(record, required), { executor = "author-preflight" }, os.clock)
	Lute.gate.writeReport(destination, runId, report)
	print(Core.format(report))
	return if report.passed == report.total then 0 else 1
end

return {
	name = "facetbench",
	summary = "Prepare the thirty-minute run or compare its recorded evidence with Verify.",
	usage = "usage: lute run tools/facet facetbench prepare|preflight|compare|snapshot|seal|check-submission|admit [--suite PATH --agent ID --judge-model ID --model-catalog PATH --place PATH --evidence PATH --report PATH --run ID]",
	values = { "place", "evidence", "report", "run", "model-catalog", "suite", "agent", "judge-model" },
	run = function(invocation: Cli.Invocation): number
		local action = invocation.positional[1]
		if #invocation.positional == 1 and action == "admit" then
			return admit(assert(Cli.flag(invocation, "evidence"), "--evidence is required"))
		end
		if #invocation.positional == 1 and action == "preflight" then
			return preflight(invocation)
		end
		if
			#invocation.positional == 1
			and (action == "snapshot" or action == "seal" or action == "check-submission")
		then
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
				elseif action == "seal" then Submission.seal(evidence, runId)
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
				assert(#suite.tasks == 1 and #suite.seeds == 1, "compare requires one task and seed")
				local chosen = Cli.flag(invocation, "agent")
				local author: Eval.Agent = suite.agents[1]
				if chosen ~= nil then
					local found: Eval.Agent? = nil
					for _, agent in suite.agents do
						if agent.id == chosen then
							found = agent
						end
					end
					if found == nil then
						error("the suite has no author " .. chosen, 0)
					end
					author = found
				else
					assert(#suite.agents == 1, "pass --agent ID to choose one of the suite authors")
				end
				identity = {
					suite = suite.id,
					task = suite.tasks[1].id,
					agent = author.id,
					adapter = author.adapter,
					model = assert(author.model, "compare requires an explicit author model"),
					seed = suite.seeds[1],
					judgeModel = assert(
						Cli.flag(invocation, "judge-model") or Json.stringField(suite.judge, "model"),
						"compare requires an explicit judge model"
					),
				}
				suiteEvidence = suite.evidence
			end
			local evidence: string = Cli.flag(invocation, "evidence") or suiteEvidence or "artifacts/facetbench/run"
			local files = Eval.lute.loader().files
			local results: { Eval.RunResult } = if files.exists(evidence .. "/index.json")
				then Eval.load(evidence, files, Lute.parse)
				else {}
			local judgments = Eval.judge.load(evidence, files, Lute.parse)
			if identity ~= nil then
				local agent = identity.agent
				local chosenResults: { Eval.RunResult } = {}
				for _, result in results do
					if result.agent == agent then
						table.insert(chosenResults, result)
					end
				end
				local chosenJudgments: { Eval.Judgment } = {}
				for _, judgment in judgments do
					if judgment.agent == agent then
						table.insert(chosenJudgments, judgment)
					end
				end
				results, judgments = chosenResults, chosenJudgments
			end
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
		local models = Setup.authorModels(Json.decode(Files.read(Cli.flag(invocation, "suite") or "eval/run.json")))
		if #models > 0 then
			local codexDirectory = Process.env.CODEX_HOME
			if codexDirectory == nil then
				local profile = Process.env.USERPROFILE or Process.env.HOME
				assert(profile, "pass --model-catalog PATH when the user profile is unavailable")
				codexDirectory = Files.join(profile, ".codex")
			end
			prepareCatalog(
				Cli.flag(invocation, "model-catalog") or Files.join(codexDirectory, "models_cache.json"),
				models
			)
		end
		preparePlaces()
		print(
			"facetbench: prepared blank places, the Facet author kit, author guidance, and restricted Codex tool profiles: "
				.. (if #models > 0 then table.concat(models, ", ") else "none")
		)
		return 0
	end,
} :: Cli.Command
