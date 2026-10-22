--!strict

local Core = require("../../tools/vendor/verify/src/core")
local Eval = require("../../tools/vendor/verify/src/agent-eval")
local Compare = require("../../eval/compare")
local Play = require("../../tools/play/host/play")
local Submission = require("../../eval/submission")
local Files = require("../../tools/facet/lib/files")

local function result(arm: string): Eval.RunResult
	local tokens = if arm == "facet" then 500 else 1000
	return Eval.result.decode({
		schemaVersion = 1,
		id = arm,
		digest = "fixture",
		suite = "facetbench-run",
		task = "run",
		tier = "game",
		arm = arm,
		agent = "codex-sol",
		adapter = "codex",
		model = "gpt-6.1-sol",
		seed = 1,
		order = 1,
		status = "completed",
		passed = true,
		checksPassed = true,
		exceeded = {},
		metrics = {
			turns = 1,
			messages = 1,
			subagentMessages = 0,
			inputTokens = tokens * 0.2,
			cacheCreationTokens = 0,
			cacheReadTokens = tokens * 0.6,
			outputTokens = tokens * 0.2,
			totalTokens = tokens,
			wallSeconds = if arm == "facet" then 300 else 500,
			turnLatencies = { if arm == "facet" then 299 else 499 },
			turnIntervals = {},
			toolCalls = 1,
			toolErrors = 0,
			permissionDenials = 0,
		},
		session = { usageSource = "turn.completed", malformed = 0, tools = {}, mcpServers = {} },
		checks = {},
		scores = {},
		audits = {},
		captures = {},
		startedAt = 1,
		finishedAt = 501,
		directory = "fixture",
	})
end

local function status(runs: { Eval.RunResult }, id: string, judgments: { Eval.Judgment }?): string
	local report = Core.runCases(
		Compare.cases(runs, judgments or {}),
		{ executor = "comparison-regression" },
		os.clock,
		{ id }
	)
	assert(#report.results == 1, "one selected assertion is required")
	return report.results[1].status
end

return function(harness: Core.Harness)
	harness:case("completion accepts the thirty-minute boundary but rejects overruns", function(t)
		local facet = result("facet")
		for _, id in { "submission", "submission-unchanged" } do
			table.insert(facet.checks, {
				id = id,
				check = id,
				kind = "verify",
				required = true,
				status = "passed",
				passed = true,
				cases = { { id = "submission/unchanged", status = "passed" } },
				scores = {},
			})
		end
		facet.metrics.wallSeconds = 1800
		t:expect(status({ facet }, "facet/completion")):toBe("passed")
		facet.metrics.wallSeconds = 1800.01
		t:expect(status({ facet }, "facet/completion")):toBe("failed")
	end)
	harness:case("submission preserves place bytes and refuses changed or corrupt evidence", function(t)
		local root = Files.temporaryDirectory("facet-submission-")
		t:defer(function()
			Files.remove(root)
		end)
		local place, snapshot = root .. "/author.rbxl", root .. "/submission"
		local original = '<roblox version="4"><Item class="Workspace"/></roblox>\r\n'
		Files.write(place, original)
		t:expect(Submission.capture(place, snapshot, "fixture").passed):toBe(1)
		t:expect(Files.read(snapshot .. "/game.rbxl")):toBe(original)
		Files.write(place, original .. "changed")
		t:expect(Submission.capture(place, snapshot, "fixture").passed):toBe(0)
		t:expect(Files.read(snapshot .. "/game.rbxl")):toBe(original)
		Files.write(place, original)
		t:expect(Submission.validate(place, snapshot).passed):toBe(1)
		Files.write(snapshot .. "/game.rbxl", "corrupt")
		t:expect(Submission.validate(nil, snapshot).passed):toBe(0)
		Files.write(snapshot .. "/game.rbxl", original)
		t:expect(Submission.validate(nil, snapshot).passed):toBe(1)
		local objects = Files.walk(snapshot .. "/objects")
		assert(#objects > 0, "capture must seal the place")
		Files.write(snapshot .. "/objects/" .. objects[1], "corrupt")
		t:expect(Submission.validate(place, snapshot).passed):toBe(0)
	end)
	harness:case("missing run evidence cannot pass paired acceptance", function(t)
		local report = Core.runCases(Compare.cases({}, {}), { executor = "comparison-regression" }, os.clock)
		t:expect(#report.results > 0):toBe(true)
		for _, item in report.results do
			t:expect(item.status == "passed"):toBe(false)
		end
	end)
	harness:case("cached tokens count and the author cost boundaries remain inclusive", function(t)
		local plain, facet = result("plain"), result("facet")
		local pair = { plain, facet }
		t:expect(status(pair, "cost/complete-usage")):toBe("passed")
		t:expect(status(pair, "cost/tokens")):toBe("passed")
		t:expect(status(pair, "cost/wall")):toBe("passed")
		facet.metrics.cacheReadTokens += 1
		facet.metrics.totalTokens += 1
		t:expect(status(pair, "cost/tokens")):toBe("failed")
		facet.metrics.wallSeconds += 1
		t:expect(status(pair, "cost/wall")):toBe("failed")
		facet.session.usageSource = "none"
		t:expect(status(pair, "cost/complete-usage")):toBe("failed")
	end)
	harness:case("turn latency uses the median and rejects ties or missing completed turns", function(t)
		local plain, facet = result("plain"), result("facet")
		local pair = { plain, facet }
		plain.metrics.turnLatencies = { 40, 50 }
		facet.metrics.turnLatencies = { 1, 100 }
		t:expect(status(pair, "cost/turn-latency")):toBe("failed")
		facet.metrics.turnLatencies = { 40, 50 }
		t:expect(status(pair, "cost/turn-latency")):toBe("failed")
		facet.metrics.turnLatencies = { 39, 49 }
		t:expect(status(pair, "cost/turn-latency")):toBe("passed")
		facet.metrics.turnLatencies = {}
		t:expect(status(pair, "cost/turn-latency")):toBe("failed")
	end)
	harness:case("a passed result flag cannot replace missing player outcomes", function(t)
		t:expect(status({ result("plain"), result("facet") }, "facet/behavior/desktop")):toBe("failed")
	end)
	harness:case("visual preference requires five devices and both orders and does not accept forfeits", function(t)
		local judgments: { Eval.Judgment } = {}
		local devices = { "desktop", "phone-portrait", "phone-landscape", "tablet", "console" }
		local scores = { 1, 1, 1, 0.5, 0 }
		for index, device in devices do
			local first: Eval.Verdict = {
				overall = if scores[index] == 1 then "first" elseif scores[index] == 0 then "second" else "tie",
				criteria = {},
				confidence = 1,
				reasons = {},
			}
			local second: Eval.Verdict = {
				overall = if scores[index] == 1 then "second" elseif scores[index] == 0 then "first" else "tie",
				criteria = {},
				confidence = 1,
				reasons = {},
			}
			judgments[index] = {
				id = device,
				task = "run",
				agent = "codex-sol",
				seed = 1,
				device = device,
				a = "facet",
				b = "plain",
				status = "judged",
				order = "a-first",
				scoreA = scores[index],
				criteria = {},
				presentations = {
					{ first = "a", attempts = 1, model = "gpt-6.1-sol", verdict = first },
					{ first = "b", attempts = 1, model = "gpt-6.1-sol", verdict = second },
				},
			}
		end
		t:expect(status({}, "visual/preference", judgments)):toBe("passed")
		judgments[4].scoreA = 0
		(judgments[4].presentations[1].verdict :: Eval.Verdict).overall = "second"
		(judgments[4].presentations[2].verdict :: Eval.Verdict).overall = "first"
		t:expect(status({}, "visual/preference", judgments)):toBe("failed")
		judgments[4].scoreA = 0.5
		(judgments[4].presentations[1].verdict :: Eval.Verdict).overall = "tie"
		(judgments[4].presentations[2].verdict :: Eval.Verdict).overall = "tie"
		judgments[5].scoreA = 1
		t:expect(status({}, "visual/preference", judgments)):toBe("failed")
		judgments[5].scoreA = 0
		judgments[1].status = "forfeit"
		t:expect(status({}, "visual/preference", judgments)):toBe("failed")
		judgments[1].status = "judged"
		judgments[1].presentations[2].first = "a"
		t:expect(status({}, "visual/preference", judgments)):toBe("failed")
		judgments[1].presentations[2].first = "b"
		table.remove(judgments)
		t:expect(status({}, "visual/preference", judgments)):toBe("failed")
	end)
	harness:case("state performance preserves race cost and rejects five percent or missing samples", function(t)
		local plain, facet = result("plain"), result("facet")
		local pair = { plain, facet }
		for _, run in pair do
			local scores: { [string]: number } = {}
			local observations: { [string]: Play.DevicePerf } = {}
			local idle: { [string]: unknown } = {
				frames = { frames = 120, p50 = 10, p95 = 20 },
				memory = { luaHeapKb = 100, guiMb = 10 },
			}
			local final: { [string]: unknown } = { memory = { luaHeapKb = 100, guiMb = 10 } }
			observations.desktop = {
				idle = idle,
				screens = {
					shop = { frames = { frames = 120, p50 = 10, p95 = 20 } },
					race = { frames = { frames = 120, p50 = 20, p95 = 30 } },
				},
				final = final,
				returned = true,
			}
			Play.perfScores(observations, scores)
			for key, value in scores do
				run.scores["play." .. key] = value
			end
		end
		t:expect(status(pair, "runtime/desktop")):toBe("passed")
		facet.scores["play.perf.desktop.race.p95"] = 31.5
		t:expect(status(pair, "runtime/desktop")):toBe("failed")
		facet.scores["play.perf.desktop.race.p95"] = 31.4
		t:expect(status(pair, "runtime/desktop")):toBe("passed")
		facet.scores["play.perf.desktop.race.frames"] = nil
		t:expect(status(pair, "runtime/desktop")):toBe("failed")
	end)
end
