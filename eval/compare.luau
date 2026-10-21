--!strict

local Core = require("../tools/vendor/verify/src/core")
local Eval = require("../tools/vendor/verify/src/agent-eval")

local devices = { "desktop", "phone-portrait", "phone-landscape", "tablet", "console" }
local outcomes = {
	"hub",
	"driving",
	"queue",
	"race",
	"scoreboard",
	"results",
	"shop",
	"garage",
	"loadout",
	"drivers",
	"crates",
	"daily-rewards",
	"codes",
	"boosts",
	"quests",
	"offer",
	"mechanic",
	"settings",
	"livery",
	"voting",
	"quick-chat",
	"upgrades",
	"party",
	"tutorial",
	"authority",
	"persistence",
	"adaptation",
	"stability",
	"progression",
}
local screens = { "hub", "shop", "garage", "livery", "race", "results", "tutorial" }

local function positive(value: number?): number
	assert(value ~= nil and value > 0 and value < math.huge, "a finite positive measurement is required")
	return value
end

local function cases(results: { Eval.RunResult }, judgments: { Eval.Judgment }): { Core.NamedCase }
	local collection: { Core.NamedCase } = {}
	local function add(id: string, body: (Core.Context) -> ())
		table.insert(collection, { id = id, name = id, timeoutSeconds = 30, run = body })
	end
	local function arm(id: string): Eval.RunResult
		local found: Eval.RunResult? = nil
		for _, result in results do
			if result.arm == id then
				assert(found == nil, "the comparison requires exactly one " .. id .. " run")
				found = result
			end
		end
		assert(found, "missing " .. id .. " run")
		return found
	end
	add("pair/identity", function(t)
		t:expect(#results):toBe(2)
		for _, id in { "plain", "facet" } do
			local run = arm(id)
			t:expect(run.suite):toBe("facetbench-run")
			t:expect(run.task):toBe("run")
			t:expect(run.agent):toBe("codex-sol")
			t:expect(run.adapter):toBe("codex")
			t:expect(run.model):toBe("gpt-6.1-sol")
			t:expect(run.seed):toBe(1)
			t:expect(run.parent):toBe(nil)
		end
	end)
	add("facet/completion", function(t)
		local run = arm("facet")
		t:expect(run.status):toBe("completed")
		t:expect(run.passed):toBe(true)
		t:expect(run.checksPassed):toBe(true)
		t:expect(#run.exceeded):toBe(0)
		t:expect(positive(run.metrics.wallSeconds) <= 600):toBe(true)
		for _, id in { "submission", "submission-unchanged" } do
			local found: Eval.CheckResult? = nil
			for _, check in run.checks do
				if check.id == id then
					assert(found == nil, "duplicate submission check")
					found = check
				end
			end
			assert(
				found and found.required and found.kind == "verify" and found.passed,
				"missing submission integrity: " .. id
			)
			t:expect(#found.cases):toBe(1)
			t:expect(found.cases[1].id):toBe("submission/unchanged")
			t:expect(found.cases[1].status):toBe("passed")
		end
	end)
	for _, device in devices do
		add("facet/behavior/" .. device, function(t)
			local statuses: { [string]: string } = {}
			local play: Eval.CheckResult? = nil
			for _, check in arm("facet").checks do
				if check.id == "play" then
					assert(play == nil, "duplicate player-outcome check")
					play = check
				end
			end
			assert(play and play.required and play.kind == "verify", "required Verify player-outcome check is missing")
			for _, outcome in play.cases do
				assert(statuses[outcome.id] == nil, "duplicate outcome: " .. outcome.id)
				statuses[outcome.id] = outcome.status
			end
			for _, outcome in outcomes do
				local id = device .. "/play/" .. outcome
				t:expect(statuses[id] == "passed"):toBeTrueWith("required player outcome: " .. id)
			end
		end)
	end
	add("cost/complete-usage", function(t)
		for _, id in { "plain", "facet" } do
			local run = arm(id)
			t:expect(run.status):toBe("completed")
			t:expect(run.session.usageSource ~= "none"):toBe(true)
			t:expect(run.session.malformed):toBe(0)
			local metrics = run.metrics
			positive(metrics.totalTokens)
			t:expect(metrics.totalTokens)
				:toBe(
					metrics.inputTokens + metrics.cacheCreationTokens + metrics.cacheReadTokens + metrics.outputTokens
				)
		end
	end)
	add("cost/tokens", function(t)
		local ratio = positive(arm("facet").metrics.totalTokens) / positive(arm("plain").metrics.totalTokens)
		t:expect(ratio <= 0.5):toBeTrueWith("Facet total tokens / Plain total tokens = " .. tostring(ratio))
	end)
	add("cost/wall", function(t)
		local ratio = positive(arm("facet").metrics.wallSeconds) / positive(arm("plain").metrics.wallSeconds)
		t:expect(ratio <= 0.6):toBeTrueWith("Facet author wall / Plain author wall = " .. tostring(ratio))
	end)
	add("cost/turn-latency", function(t)
		local facet = positive(Eval.stats.median(arm("facet").metrics.turnLatencies))
		local plain = positive(Eval.stats.median(arm("plain").metrics.turnLatencies))
		t:expect(facet < plain):toBeTrueWith("Facet median turn latency / Plain = " .. tostring(facet / plain))
	end)
	for _, device in devices do
		add("runtime/" .. device, function(t)
			local prefix = "play.perf." .. device .. "."
			local plain, facet = arm("plain").scores, arm("facet").scores
			for _, scores in { plain, facet } do
				t:expect(scores[prefix .. "returned"]):toBe(1)
				t:expect(scores[prefix .. "mountTimedOut"]):toBe(0)
				for _, metric in { "heapReturnRatio", "guiReturnRatio" } do
					t:expect(positive(scores[prefix .. metric]) < 1.05):toBeTrueWith(metric .. " retains less than 5%")
				end
			end
			for _, state in { "idle", "shop", "race" } do
				for _, scores in { plain, facet } do
					t:expect(positive(scores[prefix .. state .. ".frames"]) >= 120)
						:toBeTrueWith(state .. " needs 120 frames")
				end
				for _, percentile in { "p50", "p95" } do
					local key = prefix .. state .. "." .. percentile
					local ratio = positive(facet[key]) / positive(plain[key])
					t:expect(ratio < 1.05)
						:toBeTrueWith(state .. " " .. percentile .. " frame ratio = " .. tostring(ratio))
				end
			end
			for _, metric in { "finalHeapKb", "finalGuiMb" } do
				local ratio = positive(facet[prefix .. metric]) / positive(plain[prefix .. metric])
				t:expect(ratio < 1.05):toBeTrueWith(metric .. " ratio = " .. tostring(ratio))
			end
		end)
	end
	add("visual/coverage", function(t)
		for _, id in { "plain", "facet" } do
			local captures: { [string]: boolean } = {}
			for _, capture in arm(id).captures do
				assert(capture.size > 0 and #capture.sha256 == 64, "capture bytes need a content hash")
				captures[capture.device .. "/" .. capture.label] = true
			end
			for _, device in devices do
				for _, screen in screens do
					t:expect(captures[device .. "/" .. screen] == true)
						:toBeTrueWith(id .. "/" .. device .. "/" .. screen)
				end
			end
		end
	end)
	add("visual/preference", function(t)
		local scores: { [string]: number } = {}
		for _, judgment in judgments do
			assert(
				judgment.task == "run" and judgment.agent == "codex-sol" and judgment.seed == 1,
				"wrong judgment identity"
			)
			assert(scores[judgment.device] == nil, "duplicate device judgment")
			assert(judgment.status == "judged", "a skipped, failed, or forfeited comparison is not a visual win")
			assert(#judgment.presentations == 2, "both presentation orders are required")
			assert(
				judgment.presentations[1].first ~= judgment.presentations[2].first,
				"presentation order was not reversed"
			)
			local observed = 0
			for _, presentation in judgment.presentations do
				assert(presentation.model == "gpt-6.1-sol" and presentation.verdict ~= nil, "missing Sol judgment")
				local choice = presentation.verdict.overall
				observed += if choice == "tie"
					then 0.5
					elseif
						choice == "first" and presentation.first == "a"
						or choice == "second" and presentation.first == "b"
					then 1
					else 0
			end
			local score = judgment.scoreA
			assert(score ~= nil and score >= 0 and score <= 1, "missing visual preference score")
			assert(score == observed / 2, "preference score differs from the two recorded judgments")
			assert(
				judgment.a == "facet" and judgment.b == "plain" or judgment.a == "plain" and judgment.b == "facet",
				"wrong compared arms"
			)
			scores[judgment.device] = if judgment.a == "facet" then score else 1 - score
			t:attach(judgment.device .. "-judgment", "application/json", Eval.lute.encode(judgment))
		end
		local total = 0
		for _, device in devices do
			assert(scores[device] ~= nil, "missing judgment for " .. device)
			total += scores[device]
		end
		t:expect(#judgments):toBe(#devices)
		t:expect(total / #devices >= 0.7):toBeTrueWith("Facet blind preference = " .. tostring(total / #devices))
	end)
	return collection
end

return { cases = cases }
