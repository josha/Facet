--!strict

local Verify = require("../../tools/vendor/verify/src/core")
local Eval = require("../../tools/vendor/verify/src/agent-eval")
local Headline = require("../../eval/tools/headline")
local Fixture = require("../fixtures/headline")

return function(harness: Verify.Harness)
	local b = Eval.lute
	local thresholds = Eval.report.decodeThresholds(b.decode(b.files.read("eval/thresholds.json")))
	local overhead = b.decode(b.files.read("eval/overhead.json")) :: Headline.Overhead
	harness:case("spec failures do not gate and missing universal evidence fails closed", function(t)
		local directory = b.absolute("artifacts/facetbench/synthetic-tiers")
		local suite = Fixture.write(directory, "pass")
		local runs = Eval.load(directory, b.files, b.decode)
		local judgments = Eval.judge.load(directory, b.files, b.decode)
		for _, run in runs do
			run.passed = false
			if run.arm == "facet" then
				for _, audit in run.audits do
					audit.rules["instance-count"] = 10000
					audit.rules["type-scale"] = 10000
					audit.rules["spacing-scale"] = 10000
					audit.rules["press-feedback-missing"] = 10000
				end
			end
		end
		t:expect(Headline.build(suite, runs, judgments, thresholds, overhead).passed):toBe(true)
		runs[1].scores["play.universal.desktop.fraction"] = nil
		t:expect(Headline.build(suite, runs, judgments, thresholds, overhead).passed):toBe(false)
	end)
	for _, mode in { "pass", "instances", "fail", "missing" } do
		harness:case("headline report reads " .. mode .. " synthetic run directory", function(t)
			local directory = b.absolute("artifacts/facetbench/synthetic-" .. mode)
			local suite = Fixture.write(directory, mode)
			local output = Headline.write(directory, suite, thresholds, overhead)
			t:expect(output.passed):toBe(mode == "pass" or mode == "instances")
			t:expect(output.quality.verdict):toBe("PASS")
			t:expect(b.files.read(directory .. "/headline.md")):toBe(output.markdown)
			t:expect(
				string.find(
					output.markdown,
					"Headline: **" .. (if output.passed then "PASS" else "FAIL") .. "**.",
					1,
					true
				) ~= nil
			):toBe(true)
			if mode == "instances" then
				t:expect(
					string.find(
						output.markdown,
						"| baseInstances | — | reported, not gated | 100.000 | [100.000, 100.000] | 5 |",
						1,
						true
					) ~= nil
				):toBe(true)
				t:expect(string.find(output.markdown, "10000.000 / 10.000 / 16.000 / 1.000 / 1.000", 1, true) ~= nil)
					:toBe(true)
			end
			if mode == "fail" then
				t:expect(
					string.find(output.markdown, "mountSeconds: FAIL", 1, true)
						< string.find(output.markdown, "Quality rules:", 1, true)
				):toBe(true)
			end
			t:expect(
				string.find(
					output.markdown,
					"| codex-sol | 3 | facet | 1400 | 200 | 0 | 400 | 2000 | 200.000 | missing |",
					1,
					true
				) ~= nil
			):toBe(true)
		end)
	end
	harness:case("each confirmed overhead rule gates every device and requires complete data", function(t)
		local directory = b.absolute("artifacts/facetbench/synthetic-device-fail")
		local suite = Fixture.write(directory, "pass")
		local judgments = Eval.judge.load(directory, b.files, b.decode)
		for _, rule in overhead.rules do
			for _, device in suite.tasks[1].devices do
				local runs = Eval.load(directory, b.files, b.decode)
				for _, run in runs do
					if run.arm == "facet" then
						local key = "play.perf." .. device.id .. "." .. rule.metric
						run.scores[key] *= 1.11
					end
				end
				local output = Headline.build(suite, runs, judgments, thresholds, overhead)
				t:expect(output.passed):toBe(false)
				t:expect(string.find(output.markdown, device.id .. "/" .. rule.metric .. ": FAIL", 1, true) ~= nil)
					:toBe(true)
			end
		end
	end)
	harness:case("quality failures and incomplete seeds cannot support the headline", function(t)
		local directory = b.absolute("artifacts/facetbench/synthetic-quality-fail")
		local suite = Fixture.write(directory, "pass")
		local runs = Eval.load(directory, b.files, b.decode)
		local judgments = Eval.judge.load(directory, b.files, b.decode)
		for _, run in runs do
			if run.arm == "facet" then
				run.metrics.totalTokens = 2000
			end
		end
		local output = Headline.build(suite, runs, judgments, thresholds, overhead)
		t:expect(output.passed):toBe(false)
		t:expect(output.quality.verdict):toBe("FAIL")
		table.remove(runs)
		output = Headline.build(suite, runs, judgments, thresholds, overhead)
		t:expect(#output.problems > 0):toBe(true)
	end)
	harness:case("both arms must retain memory and blind judgments must exist", function(t)
		local directory = b.absolute("artifacts/facetbench/synthetic-retention-fail")
		local suite = Fixture.write(directory, "pass")
		local runs = Eval.load(directory, b.files, b.decode)
		for _, run in runs do
			for _, device in suite.tasks[1].devices do
				run.scores["play.perf." .. device.id .. ".heapReturnRatio"] = 2
			end
		end
		local output = Headline.build(suite, runs, Eval.judge.load(directory, b.files, b.decode), thresholds, overhead)
		t:expect(output.passed):toBe(false)
		t:expect(#output.problems > 0):toBe(true)
		output = Headline.build(suite, runs, {}, thresholds, overhead)
		t:expect(output.passed):toBe(false)
		t:expect(output.quality.verdict):toBe("FAIL")
	end)
	harness:case("quality intervals resample tasks with different costs", function(t)
		local directory = b.absolute("artifacts/facetbench/synthetic-interval")
		local suite = Fixture.write(directory, "pass")
		local runs = Eval.load(directory, b.files, b.decode)
		for _, run in runs do
			if run.arm == "facet" then
				for index, task in suite.tasks do
					if task.id == run.task then
						run.metrics.totalTokens = 100 + index * 100
					end
				end
			end
		end
		local output = Headline.build(suite, runs, Eval.judge.load(directory, b.files, b.decode), thresholds, overhead)
		for _, comparison in output.quality.agents[1].comparisons do
			if comparison.metric == "totalTokens" then
				t:expect(comparison.estimate):toBe(0.4)
				t:expect((comparison.lower :: number) < 0.4):toBe(true)
				t:expect((comparison.upper :: number) > 0.4):toBe(true)
			end
		end
	end)
	harness:case("extra judgments cannot bias a complete suite", function(t)
		local directory = b.absolute("artifacts/facetbench/synthetic-extra-judge")
		local suite = Fixture.write(directory, "pass")
		local runs = Eval.load(directory, b.files, b.decode)
		local judgments = Eval.judge.load(directory, b.files, b.decode)
		local extra = table.clone(judgments[1])
		extra.device = "unexpected-device"
		table.insert(judgments, extra)
		local output = Headline.build(suite, runs, judgments, thresholds, overhead)
		t:expect(output.passed):toBe(false)
		t:expect(#output.problems > 0):toBe(true)
	end)
end
