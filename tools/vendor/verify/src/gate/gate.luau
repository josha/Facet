--!strict

local Benchmark = require "../core/benchmark"
local Capability = require "../core/capability"
local Execution = require "../core/execution"
local GateJob = require "./gate-job"
local GateTypes = require "./gate-types"
local Plan = require "../core/plan"
local ReportModel = require "../core/report"
local Types = require "../core/types"

type Producer = GateTypes.Producer
type ProducerRecord = GateTypes.ProducerRecord
type Gate = GateTypes.Gate
type Status = GateTypes.Status
type Report = Types.Report

local SCHEMA_VERSION = 1
local DEFAULT_COMMAND_DEADLINE = 300
local DEFAULT_LOG_BYTES = 65536
local ID_PATTERN = "^[%w][%w%-_%.]*$"

local function positiveWhole(value: number?, fallback: number, label: string): number
	local chosen = if value ~= nil then value else fallback
	if type(chosen) ~= "number" or chosen < 1 or chosen % 1 ~= 0 then
		error(label .. " must be a positive whole number", 3)
	end
	return chosen
end

local function positiveSeconds(value: number?, label: string): number?
	if value == nil then
		return nil
	end
	if type(value) ~= "number" or value <= 0 or value >= math.huge then
		error(label .. " must be a positive finite number of seconds", 3)
	end
	return value
end

local function strings(values: { string }?, label: string): { string }
	return Capability.sorted(values, label)
end

local function ordered(values: { string }?, label: string): { string }
	local source: { string } = if values ~= nil then values else {}
	local result: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, value in source do
		if type(value) ~= "string" or value == "" then
			error(label .. " must contain only non-empty strings", 3)
		end
		if seen[value] then
			error(("%s names %q more than once"):format(label, value), 3)
		end
		seen[value] = true
		table.insert(result, value)
	end
	return result
end

local function arguments(values: { string }?, label: string): { string }
	local result: { string } = {}
	local source: { string } = if values ~= nil then values else {}
	for _, value in source do
		if type(value) ~= "string" then
			error(label .. " must contain only strings", 3)
		end
		table.insert(result, value)
	end
	return result
end

local function normalizeProducer(draft: GateTypes.ProducerDraft, defaultDeadline: number): Producer
	local id = draft.id
	if type(id) ~= "string" or string.match(id, ID_PATTERN) == nil then
		error(
			("producer id %q must start with a letter or digit and use only letters, digits, '-', '_' and '.'"):format(
				tostring(id)
			),
			3
		)
	end
	local label = ("producer %q"):format(id)
	local kind = draft.kind
	if kind ~= "tests" and kind ~= "command" and kind ~= "build" and kind ~= "native" and kind ~= "benchmark" then
		error(label .. " has an unknown kind", 3)
	end
	local argv: { string } = {}
	local locators: { string } = {}
	local silent: { string } = {}
	local exit: { [number]: GateTypes.ExitClass } = {}
	if kind == "tests" then
		if type(draft.worker) ~= "string" or draft.worker == "" then
			error(label .. " needs a worker module", 3)
		end
		locators = ordered(draft.locators, label .. ".locators")
		if #locators == 0 then
			error(label .. " lists no test module", 3)
		end
		silent = ordered(draft.silent, label .. ".silent")
		for _, locator in silent do
			if table.find(locators, locator) == nil then
				error(("%s.silent names %s, which is not one of its locators"):format(label, locator), 3)
			end
		end
		if
			draft.argv ~= nil
			or draft.exit ~= nil
			or draft.report ~= nil
			or draft.benchmark ~= nil
			or draft.env ~= nil
			or draft.cwd ~= nil
		then
			error(label .. " is a tests producer and takes only worker and locators", 3)
		end
	elseif kind == "benchmark" then
		if draft.benchmark == nil then
			error(label .. " needs a benchmark specification", 3)
		end
		Benchmark.check(draft.benchmark)
		if
			draft.argv ~= nil
			or draft.exit ~= nil
			or draft.report ~= nil
			or draft.worker ~= nil
			or draft.locators ~= nil
			or draft.silent ~= nil
			or draft.env ~= nil
			or draft.cwd ~= nil
		then
			error(label .. " is a benchmark producer and takes only a benchmark specification", 3)
		end
	else
		argv = arguments(draft.argv, label .. ".argv")
		if #argv == 0 then
			error(label .. " needs a command", 3)
		end
		if draft.worker ~= nil or draft.locators ~= nil or draft.silent ~= nil or draft.benchmark ~= nil then
			error(label .. " is a command producer and takes argv, env, cwd, exit and report", 3)
		end
		local declaredExit: { [number]: GateTypes.ExitClass } = if draft.exit ~= nil then draft.exit else {}
		local declaredEnv: { [string]: string } = if draft.env ~= nil then draft.env else {}
		for key, value in declaredEnv do
			if type(key) ~= "string" or key == "" or type(value) ~= "string" then
				error(label .. ".env must map non-empty names to strings", 3)
			end
		end
		if draft.cwd ~= nil and draft.cwd == "" then
			error(label .. ".cwd must not be empty", 3)
		end
		for code, class in declaredExit do
			if type(code) ~= "number" or code % 1 ~= 0 then
				error(label .. ".exit must be keyed by whole exit codes", 3)
			end
			if class ~= "passed" and class ~= "failed" and class ~= "deferred" and class ~= "unsupported" then
				error(("%s.exit[%d] must be passed, failed, deferred or unsupported"):format(label, code), 3)
			end
			exit[code] = class
		end
	end
	local expectation = draft.report
	if expectation ~= nil then
		if expectation.minimum ~= nil then
			positiveWhole(expectation.minimum, 1, label .. ".report.minimum")
		end
		if expectation.cases ~= nil then
			ordered(expectation.cases, label .. ".report.cases")
		end
	end
	local requires = strings(draft.requires, label .. ".requires")
	if kind == "native" and #requires == 0 then
		error(label .. " is native and must name the host capability it requires", 3)
	end
	if draft.tier ~= nil and draft.tier == "" then
		error(label .. ".tier must not be empty", 3)
	end
	return {
		id = id,
		kind = kind,
		after = ordered(draft.after, label .. ".after"),
		tier = draft.tier,
		tags = strings(draft.tags, label .. ".tags"),
		requires = requires,
		deadlineSeconds = positiveSeconds(draft.deadlineSeconds, label .. ".deadlineSeconds") or defaultDeadline,
		exclusive = if draft.exclusive ~= nil then draft.exclusive else kind == "benchmark",
		argv = argv,
		exit = exit,
		env = if draft.env ~= nil then table.clone(draft.env) else {},
		cwd = draft.cwd,
		report = expectation,
		worker = draft.worker,
		locators = locators,
		silent = silent,
		benchmark = draft.benchmark,
	}
end

local function checkGraph(producers: { Producer })
	local byId: { [string]: Producer } = {}
	for _, producer in producers do
		if byId[producer.id] ~= nil then
			error("duplicate producer id: " .. producer.id, 3)
		end
		byId[producer.id] = producer
	end
	for _, producer in producers do
		for _, dependency in producer.after do
			if dependency == producer.id then
				error(("producer %q cannot run after itself"):format(producer.id), 3)
			end
			if byId[dependency] == nil then
				error(("producer %q runs after unknown producer %q"):format(producer.id, dependency), 3)
			end
		end
	end
	local visiting: { [string]: boolean } = {}
	local done: { [string]: boolean } = {}
	local function visit(producer: Producer, path: { string })
		if done[producer.id] then
			return
		end
		if visiting[producer.id] then
			error("producer dependencies form a cycle: " .. table.concat(path, " -> ") .. " -> " .. producer.id, 4)
		end
		visiting[producer.id] = true
		table.insert(path, producer.id)
		for _, dependency in producer.after do
			visit(byId[dependency], path)
		end
		table.remove(path)
		visiting[producer.id] = nil
		done[producer.id] = true
	end
	for _, producer in producers do
		visit(producer, {})
	end
end

local function fingerprint(text: string): string
	local hash = 2166136261
	for index = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, index))
		hash = bit32.band(hash * 16777619, 0xFFFFFFFF)
	end
	return ("%08x-%d"):format(hash, #text)
end

local function digestOf(id: string, producers: { Producer }, policy: GateTypes.Policy): string
	local pieces: { string } = {
		("v%d"):format(SCHEMA_VERSION),
		id,
		("concurrency=%d"):format(policy.concurrency),
		("deadline=%s"):format(tostring(policy.deadlineSeconds)),
		("commandDeadline=%d"):format(policy.commandDeadlineSeconds),
		("failFast=%s"):format(tostring(policy.failFast)),
		("reuse=%s"):format(table.concat(policy.reuse, ",")),
		("requires=%s"):format(table.concat(policy.requires, ",")),
	}
	local deferred: { string } = {}
	for key, reason in policy.deferrals do
		table.insert(deferred, key .. "=" .. reason)
	end
	table.sort(deferred)
	table.insert(pieces, "deferrals=" .. table.concat(deferred, ";"))
	for _, producer in producers do
		local codes: { string } = {}
		for code, class in producer.exit do
			table.insert(codes, ("%d=%s"):format(code, class))
		end
		table.sort(codes)
		local report = producer.report
		local spec = producer.benchmark
		table.insert(
			pieces,
			table.concat({
				producer.id,
				producer.kind,
				table.concat(producer.after, ","),
				tostring(producer.tier),
				table.concat(producer.tags, ","),
				table.concat(producer.requires, ","),
				tostring(producer.deadlineSeconds),
				tostring(producer.exclusive),
				table.concat(producer.argv, "\0"),
				(function(): string
					local entries: { string } = {}
					for key, value in producer.env do
						table.insert(entries, key .. "=" .. value)
					end
					table.sort(entries)
					return table.concat(entries, "\0") .. "@" .. tostring(producer.cwd)
				end)(),
				table.concat(codes, ","),
				if report ~= nil
					then ("%s|%s"):format(
						tostring(report.minimum),
						table.concat(if report.cases ~= nil then report.cases else {}, ",")
					)
					else "",
				tostring(producer.worker),
				table.concat(producer.locators, ","),
				table.concat(producer.silent, ","),
				if spec ~= nil
					then ("%s|%s|%d|%d|%s|%s"):format(
						spec.name,
						spec.unit,
						spec.warmup,
						spec.samples,
						tostring(spec.budget.p50)
							.. tostring(spec.budget.p95)
							.. tostring(spec.budget.p99)
							.. tostring(spec.budget.maximum),
						spec.environment.observed
					)
					else "",
			}, "|")
		)
	end
	return fingerprint(table.concat(pieces, "\n"))
end

local function define(draft: GateTypes.GateDraft): Gate
	if type(draft) ~= "table" or type(draft.id) ~= "string" or draft.id == "" then
		error("a gate needs a non-empty id", 2)
	end
	local source: GateTypes.PolicyDraft = if draft.policy ~= nil then draft.policy else {}
	local commandDeadline = positiveSeconds(source.commandDeadlineSeconds, "gate policy commandDeadlineSeconds")
		or DEFAULT_COMMAND_DEADLINE
	local producers: { Producer } = {}
	for index, entry in draft.producers do
		if type(index) ~= "number" or index ~= #producers + 1 then
			error("gate producers must be a dense array", 2)
		end
		table.insert(producers, normalizeProducer(entry, commandDeadline))
	end
	checkGraph(producers)
	local known: { [string]: boolean } = {}
	for _, producer in producers do
		known[producer.id] = true
	end
	local deferrals: { [string]: string } = {}
	local declaredDeferrals: { [string]: string } = if source.deferrals ~= nil then source.deferrals else {}
	for id, reason in declaredDeferrals do
		if not known[id] then
			error(("gate policy defers unknown producer %q"):format(id), 2)
		end
		if type(reason) ~= "string" or string.find(reason, "%S") == nil then
			error(("gate policy deferral for %q needs a reason"):format(id), 2)
		end
		deferrals[id] = reason
	end
	local reuse = strings(source.reuse, "gate policy reuse")
	for _, id in reuse do
		if not known[id] then
			error(("gate policy allows reuse of unknown producer %q"):format(id), 2)
		end
	end
	local policy: GateTypes.Policy = {
		concurrency = positiveWhole(source.concurrency, 1, "gate policy concurrency"),
		deadlineSeconds = positiveSeconds(source.deadlineSeconds, "gate policy deadlineSeconds"),
		commandDeadlineSeconds = commandDeadline,
		failFast = source.failFast == true,
		deferrals = deferrals,
		reuse = reuse,
		requires = strings(source.requires, "gate policy requires"),
	}
	local units: { Types.PlanUnitDraft } = {}
	for _, producer in producers do
		local tags = table.clone(producer.tags)
		table.insert(tags, "kind:" .. producer.kind)
		if producer.tier ~= nil then
			table.insert(tags, "tier:" .. producer.tier)
		end
		table.insert(units, {
			id = producer.id,
			locator = GateJob.locator(producer),
			tags = tags,
			requires = producer.requires,
			deadlineSeconds = producer.deadlineSeconds,
		})
	end
	local plan = Plan.validate {
		id = draft.id,
		requires = policy.requires,
		policy = {
			maxParallelBatches = 1,
			batchCount = 1,
			runDeadlineSeconds = policy.deadlineSeconds,
		},
		units = units,
	}
	return {
		schemaVersion = SCHEMA_VERSION,
		id = draft.id,
		digest = digestOf(draft.id, producers, policy),
		producers = producers,
		policy = policy,
		plan = plan,
	}
end

local function producerOf(gate: Gate, id: string): Producer
	for _, producer in gate.producers do
		if producer.id == id then
			return producer
		end
	end
	error("unknown producer " .. id, 2)
end

local function resolve(gate: Gate, selection: GateTypes.Selection?): ({ string }?, { [string]: boolean })
	local pulled: { [string]: boolean } = {}
	if selection == nil then
		return nil, pulled
	end
	local ids = selection.ids
	local tiers = selection.tiers
	local tags = selection.tags
	if (ids == nil or #ids == 0) and (tiers == nil or #tiers == 0) and (tags == nil or #tags == 0) then
		error("a gate selection must name at least one id, tier or tag", 3)
	end
	local known: { [string]: boolean } = {}
	local present: { [string]: boolean } = {}
	for _, unit in gate.plan.units do
		known[unit.id] = true
		for _, tag in unit.tags do
			present[tag] = true
		end
	end
	local askedIds: { string } = if ids ~= nil then ids else {}
	for _, id in askedIds do
		if not known[id] then
			error(("selection names unknown producer %q"):format(id), 3)
		end
	end
	local wanted: { string } = {}
	local askedTiers: { string } = if tiers ~= nil then tiers else {}
	for _, tier in askedTiers do
		if not present["tier:" .. tier] then
			error(("selection names unknown tier %q"):format(tier), 3)
		end
		table.insert(wanted, "tier:" .. tier)
	end
	local askedTags: { string } = if tags ~= nil then tags else {}
	for _, tag in askedTags do
		if not present[tag] then
			error(("selection names unknown tag %q"):format(tag), 3)
		end
		table.insert(wanted, tag)
	end
	local picked = Plan.select(gate.plan, {
		ids = if ids ~= nil and #ids > 0 then ids else nil,
		tags = if #wanted > 0 then wanted else nil,
	})
	if #picked.units == 0 then
		error("the selection matches no producer", 3)
	end
	local chosen: { [string]: boolean } = {}
	local function include(id: string)
		if chosen[id] then
			return
		end
		chosen[id] = true
		for _, dependency in producerOf(gate, id).after do
			include(dependency)
		end
	end
	local direct: { [string]: boolean } = {}
	for _, unit in picked.units do
		direct[unit.id] = true
		include(unit.id)
	end
	local result: { string } = {}
	for _, producer in gate.producers do
		if chosen[producer.id] then
			table.insert(result, producer.id)
			if not direct[producer.id] then
				pulled[producer.id] = true
			end
		end
	end
	return result, pulled
end

local function micros(seconds: number): number
	return math.max(0, math.floor(seconds * 1e6 + 0.5))
end

type Running = {
	id: string,
	handle: GateTypes.Task,
	startedAt: number,
}

local function schedule(
	gate: Gate,
	executor: GateTypes.Executor,
	options: GateTypes.RunOptions,
	ctx: GateJob.Context,
	units: { Types.PlanUnit },
	records: { [string]: ProducerRecord }
): { Report }
	local policy = gate.policy
	local logBytes = ctx.logBytes
	local pollSeconds = options.pollSeconds or 0.01
	local byId: { [string]: Producer } = {}
	local order: { string } = {}
	local waiting: { [string]: boolean } = {}
	local inBatch: { [string]: boolean } = {}
	for _, unit in units do
		byId[unit.id] = producerOf(gate, unit.id)
		table.insert(order, unit.id)
		waiting[unit.id] = true
		inBatch[unit.id] = true
	end
	local reports: { [string]: Report } = {}
	local finished: { [string]: Status } = {}
	local running: { Running } = {}
	local startedAt = executor.now()
	local stopKind: string? = nil
	local stopReason = ""

	local function record(
		producer: Producer,
		built: GateJob.Built,
		began: number,
		outcome: GateTypes.JobOutcome?,
		reuse: GateTypes.Reuse?
	)
		reports[producer.id] = built.report
		finished[producer.id] = built.status
		local log: GateTypes.Log? = nil
		if outcome ~= nil and (outcome.stdout ~= "" or outcome.stderr ~= "" or outcome.logReference ~= nil) then
			local stdout, cutOut = GateJob.bounded(outcome.stdout, logBytes)
			local stderr, cutErr = GateJob.bounded(outcome.stderr, logBytes)
			log = {
				stdout = stdout,
				stderr = stderr,
				bytes = #outcome.stdout + #outcome.stderr,
				truncated = cutOut or cutErr,
				reference = outcome.logReference,
			}
		end
		records[producer.id] = {
			id = producer.id,
			kind = producer.kind,
			tier = producer.tier,
			status = built.status,
			selected = true,
			pulledByDependency = false,
			exitcode = if outcome ~= nil and outcome.started then outcome.exitcode else nil,
			timedOut = outcome ~= nil and outcome.timedOut,
			durationMicros = micros(executor.now() - began),
			detail = built.detail,
			log = log,
			reportAccounted = built.accounted,
			caseIds = built.caseIds,
			reused = reuse ~= nil and built.status ~= "failed",
			reuseReference = if reuse ~= nil then reuse.reference else nil,
			deferral = built.deferral,
			blockedBy = nil,
		}
		if options.observe ~= nil then
			pcall(options.observe, records[producer.id])
		end
		if
			policy.failFast
			and stopKind == nil
			and built.status ~= "passed"
			and built.status ~= "deferred"
			and built.status ~= "blocked"
		then
			stopKind = "fail-fast"
			stopReason = ("fail-fast stopped the run after %s"):format(producer.id)
		end
	end

	local function readiness(producer: Producer): ("ready" | "waiting" | "blocked", string?, string?)
		local pendingDependency = false
		for _, dependency in producer.after do
			if not inBatch[dependency] then
				return "blocked", dependency, "not run"
			end
			local status = finished[dependency]
			if status == nil then
				pendingDependency = true
			elseif status ~= "passed" then
				return "blocked", dependency, status
			end
		end
		return if pendingDependency then "waiting" else "ready", nil, nil
	end

	local function launch(producer: Producer, remaining: number?)
		local began = executor.now()
		local reuse = if options.reuse ~= nil then options.reuse[producer.id] else nil
		if reuse ~= nil then
			if table.find(policy.reuse, producer.id) == nil then
				record(
					producer,
					GateJob.refusedReuse(producer, ctx, "evidence reuse is not permitted by the gate policy"),
					began,
					nil,
					nil
				)
				return
			end
			if options.build ~= nil and (reuse.build == nil or reuse.build.digest ~= options.build.digest) then
				record(
					producer,
					GateJob.refusedReuse(producer, ctx, "the reused receipt is not bound to the build under test"),
					began,
					nil,
					nil
				)
				return
			end
			local outcome: GateTypes.JobOutcome = {
				started = true,
				exitcode = 0,
				timedOut = false,
				stdout = "",
				stderr = "",
				report = reuse.report,
			}
			record(producer, GateJob.conclude(producer, ctx, outcome, reuse), began, nil, reuse)
			return
		end
		if producer.kind == "benchmark" then
			record(producer, GateJob.benchmark(producer, ctx, remaining), began, nil, nil)
			return
		end
		local deadline = if remaining ~= nil
			then math.min(producer.deadlineSeconds, remaining)
			else producer.deadlineSeconds
		local job: GateTypes.Job = {
			id = producer.id,
			kind = producer.kind :: "tests" | "command" | "build" | "native",
			argv = producer.argv,
			env = producer.env,
			cwd = producer.cwd,
			worker = producer.worker,
			locators = producer.locators,
			runId = options.runId,
			expectsReport = producer.kind == "tests" or producer.report ~= nil,
			deadlineSeconds = deadline,
		}
		local started, handle: unknown = pcall(executor.start, job)
		if not started then
			local outcome: GateTypes.JobOutcome = {
				started = false,
				exitcode = -1,
				timedOut = false,
				stdout = "",
				stderr = "",
				detail = tostring(handle),
			}
			record(producer, GateJob.conclude(producer, ctx, outcome, nil), began, outcome, nil)
			return
		end
		table.insert(running, { id = producer.id, handle = handle :: GateTypes.Task, startedAt = began })
	end

	while true do
		local index = 1
		while index <= #running do
			local entry = running[index]
			local polled, outcome: unknown = pcall(entry.handle.poll)
			local result: GateTypes.JobOutcome? = nil
			if not polled then
				result = {
					started = true,
					exitcode = -1,
					timedOut = false,
					stdout = "",
					stderr = "",
					detail = "the executor raised while polling: " .. tostring(outcome),
				}
			else
				result = outcome :: GateTypes.JobOutcome?
			end
			if result ~= nil then
				table.remove(running, index)
				local producer = byId[entry.id]
				record(producer, GateJob.conclude(producer, ctx, result, nil), entry.startedAt, result, nil)
			else
				index += 1
			end
		end

		local elapsed = executor.now() - startedAt
		local limit = policy.deadlineSeconds
		if stopKind == nil and limit ~= nil and elapsed >= limit then
			stopKind = "deadline"
			stopReason = ("the run deadline of %s second(s) elapsed"):format(tostring(limit))
		end

		local progress = false
		local exclusiveRunning = false
		for _, entry in running do
			if byId[entry.id].exclusive then
				exclusiveRunning = true
			end
		end
		if stopKind == nil and not exclusiveRunning then
			for _, id in order do
				if not waiting[id] then
					continue
				end
				local producer = byId[id]
				local state, culprit, culpritStatus = readiness(producer)
				if state == "blocked" then
					waiting[id] = nil
					record(
						producer,
						GateJob.blocked(producer, ctx, culprit :: string, culpritStatus :: string),
						executor.now(),
						nil,
						nil
					)
					records[id].blockedBy = culprit
					progress = true
				elseif state == "ready" then
					if #running >= policy.concurrency or (producer.exclusive and #running > 0) then
						break
					end
					local remaining: number? = if limit ~= nil then limit - (executor.now() - startedAt) else nil
					waiting[id] = nil
					launch(producer, remaining)
					progress = true
					if producer.exclusive or stopKind ~= nil then
						break
					end
				end
			end
		end

		local remainingWaiting = false
		for _, id in order do
			if waiting[id] then
				remainingWaiting = true
			end
		end
		if #running == 0 and (not remainingWaiting or stopKind ~= nil or not progress) then
			break
		end
		if #running > 0 and not progress then
			executor.wait(pollSeconds)
		end
	end

	for _, id in order do
		if waiting[id] then
			waiting[id] = nil
			local producer = byId[id]
			local built = if stopKind == "deadline"
				then GateJob.notRun(producer, ctx, "timed_out", "not dispatched: " .. stopReason)
				elseif stopKind == "fail-fast" then GateJob.notRun(
					producer,
					ctx,
					"skipped",
					"not dispatched: " .. stopReason
				)
				else GateJob.notRun(
					producer,
					ctx,
					"skipped",
					"no producer could be scheduled; its dependencies never completed"
				)
			record(producer, built, executor.now(), nil, nil)
		end
	end

	local collected: { Report } = {}
	for _, id in order do
		table.insert(collected, reports[id])
	end
	return collected
end

local function placeholder(
	producer: Producer,
	selected: boolean,
	declared: { string },
	gate: Gate,
	execution: Types.ExecutionReport
): ProducerRecord
	local status: Status = "not_selected"
	local detail: string? = nil
	if selected then
		local negotiation = Capability.negotiate(declared, Capability.union(gate.policy.requires, producer.requires))
		if not negotiation.satisfied then
			status = "unsupported"
			detail = Capability.explain(negotiation)
		else
			status = "not_run"
			detail = if execution.batches[1] ~= nil and execution.batches[1].reason ~= nil
				then execution.batches[1].reason
				else "the run ended before this producer was dispatched"
		end
	end
	return {
		id = producer.id,
		kind = producer.kind,
		tier = producer.tier,
		status = status,
		selected = selected,
		pulledByDependency = false,
		exitcode = nil,
		timedOut = false,
		durationMicros = 0,
		detail = detail,
		log = nil,
		reportAccounted = false,
		caseIds = {},
		reused = false,
		reuseReference = nil,
		deferral = nil,
		blockedBy = nil,
	}
end

local function accept(gate: Gate, execution: Types.ExecutionReport, records: { ProducerRecord }): GateTypes.Acceptance
	local passed: { string } = {}
	local failed: { string } = {}
	local deferred: { string } = {}
	local reused: { string } = {}
	local notSelected: { string } = {}
	local reasons: { string } = {}
	for _, record in records do
		if record.reused then
			table.insert(reused, record.id)
		end
		if record.status == "not_selected" then
			table.insert(notSelected, record.id)
		elseif record.status == "passed" then
			table.insert(passed, record.id)
		elseif record.status == "deferred" then
			table.insert(deferred, record.id)
			table.insert(reasons, ("%s deferred: %s"):format(record.id, tostring(record.deferral or record.detail)))
		else
			table.insert(failed, record.id)
			table.insert(
				reasons,
				("%s %s%s"):format(record.id, record.status, if record.detail ~= nil then ": " .. record.detail else "")
			)
		end
	end
	local unaccounted = false
	for _, fact in execution.facts do
		if fact.severity == "failure" then
			unaccounted = true
			table.insert(reasons, ("%s: %s"):format(fact.code, fact.detail))
		end
	end
	local report = execution.report
	if report.total == 0 then
		unaccounted = true
		table.insert(reasons, "the gate ran no case")
	end
	if report.failed + report.timedOut + report.cancelled > 0 and #failed == 0 then
		unaccounted = true
		table.insert(reasons, "the report holds failing cases that no producer record accounts for")
	end
	if #failed == 0 and #deferred == 0 and report.passed ~= report.total then
		unaccounted = true
		table.insert(reasons, "the report holds cases that did not pass although every producer record passed")
	end
	local complete = execution.provenance.complete
	local verdict: GateTypes.Verdict
	if #failed > 0 or unaccounted then
		verdict = "failed"
	elseif not complete then
		verdict = "selected"
		table.insert(
			reasons,
			("%d of %d producer(s) were selected; this is not the complete gate"):format(#passed + #deferred, #records)
		)
	elseif #deferred > 0 then
		verdict = "deferred"
	else
		verdict = "release"
	end
	return {
		verdict = verdict,
		releasable = verdict == "release",
		complete = complete,
		reasons = reasons,
		passed = passed,
		failed = failed,
		deferred = deferred,
		reused = reused,
		notSelected = notSelected,
	}
end

local function run(gate: Gate, executor: GateTypes.Executor, options: GateTypes.RunOptions): GateTypes.Outcome
	if type(options) ~= "table" or type(options.runId) ~= "string" or options.runId == "" then
		error("a gate run needs a run id", 2)
	end
	if
		type(executor) ~= "table"
		or type(executor.now) ~= "function"
		or type(executor.wait) ~= "function"
		or type(executor.start) ~= "function"
	then
		error("a gate run needs an executor with now, wait and start", 2)
	end
	local offered: { [string]: GateTypes.Reuse } = if options.reuse ~= nil then options.reuse else {}
	for id in offered do
		producerOf(gate, id)
	end
	local ids, pulled = resolve(gate, options.selection)
	local declared = Capability.sorted(options.capabilities, "gate capabilities")
	local name = options.name or "verify-gate"
	local environment: { [string]: string } = {}
	local supplied: { [string]: string } = if options.environment ~= nil then options.environment else {}
	for key, value in supplied do
		environment[key] = value
	end
	environment["verify.gate"] = gate.digest
	environment["verify.gateRun"] = options.runId
	if options.build ~= nil then
		environment["verify.build.commit"] = options.build.commit
		environment["verify.build.tree"] = options.build.tree
		environment["verify.build.clean"] = tostring(options.build.clean)
		environment["verify.build.digest"] = options.build.digest
	end
	local ctx: GateJob.Context = {
		runId = options.runId,
		executor = name,
		environment = environment,
		capabilities = declared,
		now = executor.now,
		deferrals = gate.policy.deferrals,
		logBytes = options.logBytes or DEFAULT_LOG_BYTES,
	}
	local records: { [string]: ProducerRecord } = {}
	local host: Execution.Host = {
		name = name,
		capabilities = declared,
		environment = environment,
		now = executor.now,
		runBatch = function(batch: Types.PlanBatch): Types.BatchOutcome
			local reports = schedule(gate, executor, options, ctx, batch.units, records)
			return { status = "returned", report = ReportModel.merge(reports, name, environment) }
		end,
	}
	local execution = Execution.execute(gate.plan, host, {
		selection = if ids ~= nil then { ids = ids } else nil,
		batchCount = 1,
		parallel = 1,
		fixtures = options.fixtures,
	})
	local selectedSet: { [string]: boolean } = {}
	local chosenIds: { string } = if ids ~= nil then ids else {}
	for _, id in chosenIds do
		selectedSet[id] = true
	end
	local list: { ProducerRecord } = {}
	for _, producer in gate.producers do
		local selected = ids == nil or selectedSet[producer.id] == true
		local record = records[producer.id]
		if record == nil then
			record = placeholder(producer, selected, declared, gate, execution)
		end
		record.selected = selected
		record.pulledByDependency = pulled[producer.id] == true
		local reason = gate.policy.deferrals[producer.id]
		if record.status == "unsupported" and reason ~= nil then
			record.status = "deferred"
			record.deferral = reason
		end
		table.insert(list, record)
	end
	return {
		schemaVersion = SCHEMA_VERSION,
		gate = gate.id,
		digest = gate.digest,
		runId = options.runId,
		build = options.build,
		execution = execution,
		producers = list,
		acceptance = accept(gate, execution, list),
	}
end

local function format(outcome: GateTypes.Outcome): string
	local lines: { string } = {
		("gate %s run %s [%s]"):format(outcome.gate, outcome.runId, outcome.digest),
	}
	for _, record in outcome.producers do
		local flags: { string } = {}
		if record.reused then
			table.insert(flags, "reused")
		end
		if record.pulledByDependency then
			table.insert(flags, "dependency")
		end
		table.insert(
			lines,
			("  %-12s %s (%s)%s%s"):format(
				record.status,
				record.id,
				record.kind,
				if #flags > 0 then " [" .. table.concat(flags, ",") .. "]" else "",
				if record.status == "not_selected" then "" else (" %.2fs"):format(record.durationMicros / 1e6)
			)
		)
		if record.status ~= "passed" and record.status ~= "not_selected" and record.detail ~= nil then
			table.insert(lines, "      " .. record.detail)
		end
	end
	local acceptance = outcome.acceptance
	table.insert(
		lines,
		("verdict: %s%s"):format(acceptance.verdict, if acceptance.releasable then " (releasable)" else "")
	)
	if acceptance.verdict ~= "release" then
		for _, reason in acceptance.reasons do
			table.insert(lines, "  " .. reason)
		end
	end
	return table.concat(lines, "\n")
end

export type ShardOptions = {
	prefix: string,
	worker: string,
	count: number,
	mode: Types.BatchingMode?,
	silent: { string }?,
	tier: string?,
	tags: { string }?,
	requires: { string }?,
	deadlineSeconds: number?,
}

local function shard(plan: Types.PlanDraft, options: ShardOptions): { GateTypes.ProducerDraft }
	local silent: { [string]: boolean } = {}
	local declared: { string } = options.silent or {}
	for _, locator in declared do
		silent[locator] = true
	end
	local drafts: { GateTypes.ProducerDraft } = {}
	for _, batch in Plan.partition(plan, options.count, options.mode) do
		local locators: { string } = {}
		local quiet: { string } = {}
		for _, unit in batch.units do
			table.insert(locators, unit.locator)
			if silent[unit.locator] then
				table.insert(quiet, unit.locator)
			end
		end
		if #locators > 0 then
			table.insert(drafts, {
				id = ("%s-%d"):format(options.prefix, batch.index),
				kind = "tests",
				worker = options.worker,
				locators = locators,
				silent = quiet,
				tier = options.tier,
				tags = options.tags,
				requires = options.requires,
				deadlineSeconds = options.deadlineSeconds,
			})
		end
	end
	return drafts
end

local function testCases(outcome: GateTypes.Outcome): Report
	local own: { string } = {}
	for _, record in outcome.producers do
		if record.kind == "tests" then
			table.insert(own, record.id)
		end
	end
	return ReportModel.without(outcome.execution.report, own)
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	shard = shard,
	testCases = testCases,
	DEFAULT_COMMAND_DEADLINE = DEFAULT_COMMAND_DEADLINE,
	define = define,
	run = run,
	format = format,
}
