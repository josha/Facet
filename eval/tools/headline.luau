--!strict

local Eval = require("../../tools/vendor/verify/src/agent-eval")
local Universal = require("../tasks/racing-hub/hidden/universal")

type Run = Eval.RunResult
export type Manifest = {
	id: string,
	tasks: {
		{
			id: string,
			universalCases: number?,
			devices: { { id: string } },
			checks: { { id: string, kind: string, perDevice: boolean? } },
		}
	},
	arms: { { id: string } },
	agents: { { id: string } },
	seeds: { number },
}
export type Rule = { metric: string, limit: number?, perArmLimit: number? }
export type Overhead = { status: string, rules: { Rule } }
export type Output = { markdown: string, quality: Eval.EvalReport, passed: boolean, problems: { string } }

local stats = Eval.stats
local UNIVERSAL_AUDIT: { [string]: boolean } = {
	["text-truncated"] = true,
	["text-clipped"] = true,
	["contrast-low"] = true,
	["offscreen"] = true,
	["outside-safe-area"] = true,
	["touch-target-small"] = true,
	["interactive-overlap"] = true,
	["gamepad-unreachable"] = true,
	["focus-hidden"] = true,
	["selection-link-broken"] = true,
}

local function show(value: number?): string
	return if value == nil then "missing" else ("%.3f"):format(value)
end

local function identity(task: string, arm: string, agent: string, seed: number): string
	return ("%s/%s/%s/%d"):format(task, arm, agent, seed)
end

local function metric(run: Run, device: string, name: string): number?
	local value = run.scores[("play.perf.%s.%s"):format(device, name)]
	return if value ~= nil and value == value and math.abs(value) < math.huge and value >= 0 then value else nil
end

local function audit(run: Run): number?
	if #run.audits == 0 then
		return nil
	end
	local total = 0
	for _, item in run.audits do
		for _, count in item.rules do
			total += count
		end
	end
	return total / #run.audits
end

local function build(
	suite: Manifest,
	runs: { Run },
	judgments: { Eval.Judgment },
	thresholds: Eval.Thresholds,
	overhead: Overhead,
	calibration: Eval.Calibration?
): Output
	local problems: { string } = {}
	local measured: { Run } = {}
	for _, original in runs do
		local run = table.clone(original)
		local complete = run.status == "completed" and #run.exceeded == 0
		local contract = false
		local play = false
		for _, check in run.checks do
			if check.required and not check.passed then
				complete = false
			end
			if check.check == "contract" then
				contract = check.passed
			end
			if check.check == "play" then
				play = check.passed
			end
		end
		for _, task in suite.tasks do
			if task.id == run.task then
				for _, device in task.devices do
					local key = "play.universal." .. device.id
					local total = run.scores[key .. ".total"]
					local fraction = run.scores[key .. ".fraction"]
					local recorded, passed = 0, 0
					local seen: { [string]: boolean } = {}
					for _, check in run.checks do
						if check.check ~= "play" then
							continue
						end
						for _, case in check.cases do
							local prefix = device.id .. "/universal/"
							if string.sub(case.id, 1, #prefix) == prefix and not seen[case.id] then
								seen[case.id] = true
								recorded += 1
								passed += if case.status == "passed" then 1 else 0
							end
						end
					end
					if recorded == 0 or recorded ~= total or fraction ~= passed / recorded then
						table.insert(
							problems,
							"harness error: universal case records disagree with scores: "
								.. run.task
								.. "/"
								.. run.arm
								.. "/"
								.. device.id
						)
						complete = false
					end
					if
						total == nil
						or total <= 0
						or fraction == nil
						or (task.universalCases ~= nil and total ~= task.universalCases)
					then
						table.insert(
							problems,
							"missing universal tier: " .. run.task .. "/" .. run.arm .. "/" .. device.id
						)
					end
					complete = complete and total ~= nil and total > 0 and fraction == 1
				end
			end
		end
		run.passed = complete and contract and play
		run.checksPassed = run.passed
		local audits = {}
		for _, item in run.audits do
			if string.find(item.path, "audit-universal-", 1, true) ~= nil then
				local measured = table.clone(item)
				measured.rules = {}
				for rule, count in item.rules do
					if UNIVERSAL_AUDIT[rule] then
						measured.rules[rule] = count
					end
				end
				table.insert(audits, measured)
			end
		end
		run.audits = audits
		table.insert(measured, run)
	end
	runs = measured
	local byId: { [string]: Run } = {}
	local expected: { [string]: boolean } = {}
	local expectedJudgments: { [string]: boolean } = {}
	for _, task in suite.tasks do
		for _, arm in suite.arms do
			for _, agent in suite.agents do
				for _, seed in suite.seeds do
					expected[identity(task.id, arm.id, agent.id, seed)] = true
					for _, device in task.devices do
						expectedJudgments[identity(task.id, "judge", agent.id, seed) .. "/" .. device.id] = true
					end
				end
			end
		end
	end
	for _, run in runs do
		local key = identity(run.task, run.arm, run.agent, run.seed)
		if byId[key] ~= nil or not expected[key] or run.suite ~= suite.id then
			table.insert(problems, "duplicate or unexpected run: " .. key)
		end
		byId[key] = run
		if run.session.usageSource == "none" or #run.metrics.turnLatencies == 0 then
			table.insert(problems, "missing token or latency evidence: " .. key)
		end
	end
	for key in expected do
		if byId[key] == nil then
			table.insert(problems, "missing run: " .. key)
		end
	end
	local quality = Eval.report.build(suite.id, runs, judgments, thresholds, calibration)
	local passed = quality.verdict == "PASS"
	local failures: { string } = {}
	local measurements = table.clone(overhead.rules)
	table.insert(measurements, { metric = "baseInstances" })
	local lines = {
		"# FacetBench headline",
		"",
		"",
		"",
		"Quality rules: **"
			.. quality.verdict
			.. "**. Intervals: paired task bootstrap, 95%, 4000 resamples, seed 20261014. Follow-up tasks share workspace history and are not independent games.",
		"",
		"| Agent | Rule | Result | Bound | Limit | Value | Estimate | 95% interval | Paired tasks |",
		"| --- | --- | --- | --- | ---: | ---: | ---: | --- | ---: |",
	}
	for _, section in quality.agents do
		for _, rule in section.rules do
			if not rule.passed then
				table.insert(failures, section.agent .. "/" .. rule.id .. ": FAIL")
			end
			for _, comparison in section.comparisons do
				if comparison.metric == rule.metric then
					table.insert(
						lines,
						("| %s | %s | %s | %s | %s | %s | %s | [%s, %s] | %d |"):format(
							section.agent,
							rule.id,
							if rule.passed then "PASS" else "FAIL",
							rule.bound,
							show(rule.threshold),
							show(rule.value),
							show(comparison.estimate),
							show(comparison.lower),
							show(comparison.upper),
							comparison.tasks
						)
					)
				end
			end
		end
	end
	local judgeKeys: { [string]: boolean } = {}
	for _, judgment in judgments do
		local key = identity(judgment.task, "judge", judgment.agent, judgment.seed) .. "/" .. judgment.device
		if
			judgeKeys[key]
			or not expectedJudgments[key]
			or judgment.status ~= "judged"
			or #judgment.presentations ~= 2
			or judgment.presentations[1].verdict == nil
			or judgment.presentations[2].verdict == nil
			or judgment.presentations[1].first == judgment.presentations[2].first
			or not (
				(judgment.a == thresholds.baseline and judgment.b == thresholds.treatment)
				or (judgment.b == thresholds.baseline and judgment.a == thresholds.treatment)
			)
		then
			table.insert(problems, "missing blind two-order judgment or duplicate: " .. key)
		end
		judgeKeys[key] = true
	end
	for _, task in suite.tasks do
		local auditCount = 0
		for _, check in task.checks do
			if check.kind == "audit" and string.find(check.id, "audit-universal-", 1, true) == 1 then
				auditCount += if check.perDevice then #task.devices else 1
			end
		end
		for _, agent in suite.agents do
			for _, seed in suite.seeds do
				for _, device in task.devices do
					local key = identity(task.id, "judge", agent.id, seed) .. "/" .. device.id
					if not judgeKeys[key] then
						table.insert(problems, "missing judgment: " .. key)
					end
				end
				for _, arm in suite.arms do
					local key = identity(task.id, arm.id, agent.id, seed)
					local run = byId[key]
					if run == nil then
						continue
					end
					if #run.audits ~= auditCount then
						table.insert(problems, "incomplete audits: " .. key)
					end
					for _, device in task.devices do
						if run.scores["play.universal." .. device.id .. ".fraction"] == nil then
							table.insert(problems, "missing hidden-check fraction: " .. key .. "/" .. device.id)
						end
					end
				end
			end
		end
	end

	table.insert(lines, "")
	table.insert(
		lines,
		"> Limits come from eval/overhead.json. Each overhead rule requires the upper 95% bound of Facet/plain to be at most its limit on every device. Memory also requires every seed in both arms to return within 5% of its own mounted baseline. Instances are reported, not gated. No unmount or forced garbage collection is claimed."
	)
	table.insert(lines, "")
	table.insert(lines, "| Agent | Device | Metric | Limit | Result | Ratio | 95% interval | Tasks |")
	table.insert(lines, "| --- | --- | --- | ---: | --- | ---: | --- | ---: |")
	for _, agent in suite.agents do
		local devices: { string } = {}
		for _, task in suite.tasks do
			for _, device in task.devices do
				if table.find(devices, device.id) == nil then
					table.insert(devices, device.id)
				end
			end
		end
		for _, device in devices do
			for _, rule in measurements do
				local units: { { base: number, treated: number } } = {}
				local complete, retained = true, true
				for _, task in suite.tasks do
					local arms: { { number } } = { {}, {} }
					for index, arm in { thresholds.baseline, thresholds.treatment } do
						for _, seed in suite.seeds do
							local run = byId[identity(task.id, arm, agent.id, seed)]
							local value = if run then metric(run, device, rule.metric) else nil
							if value == nil or value <= 0 then
								complete = false
							else
								table.insert(arms[index], value)
								if
									rule.perArmLimit ~= nil
									and (value > rule.perArmLimit or metric(run :: Run, device, "returned") ~= 1)
								then
									retained = false
								end
							end
						end
					end
					if #arms[1] == #suite.seeds and #arms[2] == #suite.seeds then
						table.insert(
							units,
							{ base = stats.mean(arms[1]) :: number, treated = stats.mean(arms[2]) :: number }
						)
					end
				end
				local interval = stats.bootstrap({
					units = units,
					resamples = thresholds.resamples,
					confidence = thresholds.confidence,
					seed = Eval.random.derive(thresholds.seed, agent.id .. "/" .. device .. "/" .. rule.metric),
					statistic = function(sample: { { base: number, treated: number } }): number?
						local base, treated = 0, 0
						for _, pair in sample do
							base += pair.base
							treated += pair.treated
						end
						return if base > 0 then treated / base else nil
					end,
				})
				local ok = complete
					and retained
					and #units >= thresholds.minimumTasks
					and interval.upper ~= nil
					and (rule.limit == nil or interval.upper <= rule.limit)
				passed = passed and ok
				if not ok then
					table.insert(failures, agent.id .. "/" .. device .. "/" .. rule.metric .. ": FAIL")
				end
				table.insert(
					lines,
					("| %s | %s | %s | %s | %s | %s | [%s, %s] | %d |"):format(
						agent.id,
						device,
						rule.metric,
						if rule.limit then show(rule.limit) else "—",
						if rule.limit == nil then "reported, not gated" elseif ok then "PASS" else "FAIL",
						show(interval.estimate),
						show(interval.lower),
						show(interval.upper),
						#units
					)
				)
				if not complete or not retained then
					table.insert(
						problems,
						agent.id
							.. "/"
							.. device
							.. "/"
							.. rule.metric
							.. ": missing data or memory did not return to baseline"
					)
				end
			end
		end
	end

	table.insert(lines, "")
	table.insert(
		lines,
		"Per-task values are medians over seeds. Pass is the run pass rate; audit is violations per audited screen. Overhead cells show arm medians and arm/plain ratios across all devices and seeds: instances / mount seconds / idle p50 ms / heap return / GUI return. The device rules above prevent a device regression from being hidden by these medians."
	)
	table.insert(lines, "")
	table.insert(lines, "| Agent | Task | Arm | Pass | Audit | Tokens | Wall s | Overhead values | Overhead ratios |")
	table.insert(lines, "| --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- |")
	for _, agent in suite.agents do
		local armValues: { [string]: { { number } } } = {}
		local armOverheads: { [string]: { [string]: { number } } } = {}
		local armRatios: { [string]: { [string]: { number } } } = {}
		for _, arm in { thresholds.baseline, thresholds.treatment } do
			armValues[arm] = { {}, {}, {}, {} }
			armOverheads[arm] = {}
			armRatios[arm] = {}
		end
		for _, task in suite.tasks do
			local baselines: { [string]: number } = {}
			for _, arm in { thresholds.baseline, thresholds.treatment } do
				local passes, audits, tokens, walls = {}, {}, {}, {}
				local overhead: { [string]: { number } } = {}
				for _, seed in suite.seeds do
					local run = byId[identity(task.id, arm, agent.id, seed)]
					if run == nil then
						continue
					end
					table.insert(passes, if run.passed then 1 else 0)
					local violations = audit(run)
					if violations then
						table.insert(audits, violations)
					end
					table.insert(tokens, run.metrics.totalTokens)
					table.insert(walls, run.metrics.wallSeconds)
					for _, rule in measurements do
						overhead[rule.metric] = overhead[rule.metric] or {}
						for _, device in task.devices do
							local value = metric(run, device.id, rule.metric)
							if value then
								table.insert(overhead[rule.metric], value)
							end
						end
					end
				end
				local values, ratios = {}, {}
				for _, name in
					{ "baseInstances", "mountSeconds", "idleFrameP50Ms", "heapReturnRatio", "guiReturnRatio" }
				do
					local value = stats.median(overhead[name] or {})
					if arm == thresholds.baseline and value ~= nil then
						baselines[name] = value
					end
					local base = baselines[name]
					local ratio = if value and base and base > 0 then value / base else nil
					armOverheads[arm][name] = armOverheads[arm][name] or {}
					armRatios[arm][name] = armRatios[arm][name] or {}
					if value then
						table.insert(armOverheads[arm][name], value)
					end
					if ratio then
						table.insert(armRatios[arm][name], ratio)
					end
					table.insert(values, show(value))
					table.insert(ratios, show(ratio))
				end
				local summary = { stats.mean(passes), stats.median(audits), stats.median(tokens), stats.median(walls) }
				for index = 1, 4 do
					if summary[index] ~= nil then
						table.insert(armValues[arm][index], summary[index] :: number)
					end
				end
				table.insert(
					lines,
					("| %s | %s | %s | %s | %s | %s | %s | %s | %s |"):format(
						agent.id,
						task.id,
						arm,
						show(summary[1]),
						show(summary[2]),
						show(summary[3]),
						show(summary[4]),
						table.concat(values, " / "),
						table.concat(ratios, " / ")
					)
				)
			end
		end
		for _, arm in { thresholds.baseline, thresholds.treatment } do
			local v = armValues[arm]
			local values, ratios = {}, {}
			for _, name in { "baseInstances", "mountSeconds", "idleFrameP50Ms", "heapReturnRatio", "guiReturnRatio" } do
				table.insert(values, show(stats.median(armOverheads[arm][name] or {})))
				table.insert(ratios, show(stats.median(armRatios[arm][name] or {})))
			end
			table.insert(
				lines,
				("| %s | Median of tasks | %s | %s | %s | %s | %s | %s | %s |"):format(
					agent.id,
					arm,
					show(stats.median(v[1])),
					show(stats.median(v[2])),
					show(stats.median(v[3])),
					show(stats.median(v[4])),
					table.concat(values, " / "),
					table.concat(ratios, " / ")
				)
			)
		end
	end
	table.insert(lines, "")
	table.insert(
		lines,
		"| Agent | Seed | Arm | Input tokens | Cache read | Cache write | Output tokens | Total tokens | Wall s | USD |"
	)
	table.insert(lines, "| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
	for _, agent in suite.agents do
		for _, seed in suite.seeds do
			for _, arm in { thresholds.baseline, thresholds.treatment } do
				local input, read, write, output, total, wall, usd, priced, count = 0, 0, 0, 0, 0, 0, 0, true, 0
				for _, run in runs do
					if run.agent == agent.id and run.seed == seed and run.arm == arm then
						local m = run.metrics
						input += m.inputTokens
						read += m.cacheReadTokens
						write += m.cacheCreationTokens
						output += m.outputTokens
						total += m.totalTokens
						wall += m.wallSeconds
						count += 1
						if m.costUsd == nil then
							priced = false
						else
							usd += m.costUsd
						end
					end
				end
				table.insert(
					lines,
					("| %s | %d | %s | %d | %d | %d | %d | %d | %.3f | %s |"):format(
						agent.id,
						seed,
						arm,
						input,
						read,
						write,
						output,
						total,
						wall,
						show(if priced and count == #suite.tasks then usd else nil)
					)
				)
			end
		end
	end
	table.sort(problems)
	table.insert(lines, "")
	table.insert(lines, "Universal checks gate run pass rate. Spec checks are diagnostic and do not enter the verdict.")
	table.insert(lines, "")
	table.insert(lines, "| Task | Arm | Seed | Device | Universal fraction | Spec fraction (diagnostic) |")
	table.insert(lines, "| --- | --- | ---: | --- | ---: | ---: |")
	for _, run in runs do
		for _, item in suite.tasks do
			if item.id == run.task then
				for _, device in item.devices do
					table.insert(
						lines,
						("| %s | %s | %d | %s | %s | %s |"):format(
							run.task,
							run.arm,
							run.seed,
							device.id,
							show(run.scores["play.universal." .. device.id .. ".fraction"]),
							show(run.scores["spec.fraction." .. device.id])
						)
					)
				end
			end
		end
	end
	passed = passed and #problems == 0
	table.insert(lines, "")
	lines[3] = "Headline: **" .. (if passed then "PASS" else "FAIL") .. "**."
	local first = 4
	for _, messages in { failures, problems } do
		for _, message in messages do
			table.insert(lines, first, "\n- " .. message)
			first += 1
		end
	end
	table.insert(lines, "")
	table.insert(
		lines,
		"Codex does not report USD cost. Missing USD is unpriced, never zero. Input excludes cached input; total includes cache reads and writes. Frame time is the whole Studio client, not isolated UI CPU time. Mount includes joining, probe readiness and host waits. Memory compares the returned hub after five idle seconds with the mounted hub; it does not prove unmount cleanup. Confirm the return state in Studio."
	)
	table.insert(lines, "")
	for _, limitation in quality.limitations do
		table.insert(lines, "- " .. limitation)
	end
	return { markdown = table.concat(lines, "\n") .. "\n", quality = quality, passed = passed, problems = problems }
end

local function write(evidence: string, suite: Manifest, thresholds: Eval.Thresholds, overhead: Overhead): Output
	local binding = Eval.lute
	local runs = Eval.load(evidence, binding.files, binding.decode)
	local judgments = Eval.judge.load(evidence, binding.files, binding.decode)
	local calibration: Eval.Calibration? = nil
	if binding.files.exists(evidence .. "/labels.json") then
		calibration = Eval.judge.calibrate(
			judgments,
			Eval.judge.decodeLabels(binding.decode(binding.files.read(evidence .. "/labels.json")))
		)
	end
	local output = build(suite, runs, judgments, thresholds, overhead, calibration)
	binding.files.write(evidence .. "/headline.md", output.markdown)
	binding.files.write(evidence .. "/quality.json", binding.encode(output.quality))
	return output
end

local function manifest(source: string?): Manifest
	local b = Eval.lute
	local raw = b.decode(b.files.read(source or "eval/extended.json")) :: {
		id: string,
		tasks: { string },
		devices: { { id: string } },
		arms: { { id: string } },
		agents: { { id: string } },
		seeds: { number },
	}
	local tasks: {
		{
			id: string,
			universalCases: number?,
			devices: { { id: string } },
			checks: { { id: string, kind: string, perDevice: boolean? } },
		}
	} =
		{}
	for _, path in raw.tasks do
		local task = b.decode(b.files.read("eval/" .. path .. "/task.json")) :: {
			id: string,
			devices: { { id: string } }?,
			checks: { { id: string, kind: string, perDevice: boolean? } },
		}
		table.insert(tasks, {
			id = task.id,
			universalCases = #Universal.scenario(task.id).sessions[1].cases,
			devices = task.devices or raw.devices,
			checks = task.checks,
		})
	end
	return { id = raw.id, tasks = tasks, arms = raw.arms, agents = raw.agents, seeds = raw.seeds }
end

return { build = build, write = write, manifest = manifest }
