--!strict

local Eval = require("../../tools/vendor/verify/src/agent-eval")
local fs = require("@std/fs")
local Headline = require("../../eval/tools/headline")

local function write(directory: string, mode: string): Headline.Manifest
	local b = Eval.lute
	local suite = Headline.manifest()
	local index: { { path: string } } = {}
	local judgments: { Eval.Judgment } = {}
	local order = 0
	for _, task in suite.tasks do
		for _, seed in suite.seeds do
			for _, arm in suite.arms do
				order += 1
				local facet = arm.id == "facet"
				local relative = ("runs/%s/%s/codex-sol/%d"):format(task.id, arm.id, seed)
				local runPath = directory .. "/" .. relative
				fs.createDirectory(runPath, { makeParents = true })
				local scores: { [string]: number } = { ["types.passed"] = 1, ["types.errors"] = 0 }
				local audits: { { device: string?, score: number, path: string, rules: { [string]: number } } } = {}
				for _, device in task.devices do
					scores["play.fraction." .. device.id] = if facet then 1 else 0.5
					local measurements: { [string]: number } = {
						baseInstances = if mode == "instances" and facet then 10000 else 100,
						mountSeconds = if mode == "fail" and facet then 12 else 10,
						idleFrameP50Ms = 16,
						idleFrameP95Ms = 17,
						heapReturnRatio = 1,
						guiReturnRatio = 1,
						returned = 1,
					}
					for name, value in measurements do
						scores["play.perf." .. device.id .. "." .. name] = value
					end
					if mode == "missing" and facet and seed == 3 then
						scores["play.perf." .. device.id .. ".mountSeconds"] = nil
					end
				end
				for _, check in task.checks do
					if check.kind ~= "audit" then
						continue
					end
					for _, device in task.devices do
						table.insert(audits, {
							device = device.id,
							score = 80,
							path = check.id .. "/" .. device.id,
							rules = { offscreen = if facet then 1 else 10 },
						})
					end
				end
				local tokens, seconds = if facet then 400 else 1000, if facet then 40 else 100
				local raw = {
					schemaVersion = 1,
					id = relative,
					digest = "synthetic",
					suite = suite.id,
					task = task.id,
					tier = "game",
					arm = arm.id,
					agent = "codex-sol",
					adapter = "codex",
					seed = seed,
					order = order,
					status = "completed",
					passed = facet,
					checksPassed = facet,
					exceeded = {},
					metrics = {
						turns = 2,
						messages = 2,
						subagentMessages = 0,
						inputTokens = tokens * 0.7,
						cacheCreationTokens = 0,
						cacheReadTokens = tokens * 0.1,
						outputTokens = tokens * 0.2,
						totalTokens = tokens,
						wallSeconds = seconds,
						turnLatencies = { seconds / 10, seconds / 5 },
						turnIntervals = {},
						toolCalls = 1,
						toolErrors = 0,
						permissionDenials = 0,
					},
					session = { usageSource = "turn.completed", mcpServers = {}, tools = {} },
					checks = {},
					scores = scores,
					audits = audits,
					captures = {},
					startedAt = 0,
					finishedAt = seconds,
					directory = runPath,
				}
				b.files.write(runPath .. "/result.json", b.encode(raw))
				table.insert(index, { path = relative })
			end
			for _, device in task.devices do
				local verdict: Eval.Verdict = { criteria = {}, overall = "first", confidence = 1, reasons = {} }
				local reverse: Eval.Verdict = { criteria = {}, overall = "second", confidence = 1, reasons = {} }
				local judgment: Eval.Judgment = {
					id = task.id .. "/" .. device.id .. "/" .. seed,
					task = task.id,
					agent = "codex-sol",
					seed = seed,
					device = device.id,
					a = "facet",
					b = "plain",
					status = "judged",
					order = "a-first",
					scoreA = 1,
					criteria = {},
					winner = "facet",
					consistent = true,
					presentations = {
						{ first = "a", attempts = 1, verdict = verdict },
						{ first = "b", attempts = 1, verdict = reverse },
					},
				}
				table.insert(judgments, judgment)
			end
		end
	end
	b.files.write(directory .. "/index.json", b.encode({ schemaVersion = 1, suite = suite.id, runs = index }))
	b.files.write(
		directory .. "/judgments.json",
		b.encode({ schemaVersion = 1, suite = suite.id, judgments = judgments })
	)
	return suite
end

return { write = write }
