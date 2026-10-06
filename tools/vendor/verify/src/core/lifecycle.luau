--!strict

local Types = require "./types"

export type Returned = {
	ok: boolean,
	output: string?,
	detail: string?,
	reason: string?,
	timedOut: boolean?,
	artifacts: { Types.Artifact }?,
}

export type Step = {
	id: string,
	kind: string?,
	payload: unknown?,
	run: ((step: Step) -> Returned)?,
	deadlineSeconds: number?,
	resource: string?,
	mutates: boolean?,
}

export type Checkpoint = {
	id: string,
	captures: { Step },
	acknowledge: Step,
}

export type FailureKind = "failed" | "timeout" | "threw" | "resource" | "interrupted"
export type Phase = "setup" | "start" | "body" | "cleanup"

export type Failure = {
	stage: string,
	phase: Phase,
	kind: FailureKind,
	reason: string,
	detail: string?,
}

export type Outcome = Returned & { failure: Failure? }

export type Record = {
	id: string,
	phase: Phase,
	ok: boolean,
	timedOut: boolean,
	elapsedSeconds: number,
	output: string?,
	detail: string?,
	artifacts: { Types.Artifact }?,
}

export type Ops<H = unknown> = {
	now: () -> number,
	sleep: ((seconds: number) -> ())?,
	start: ((step: Step) -> Returned)?,
	send: ((step: Step) -> Returned)?,
	capture: ((step: Step) -> Returned)?,
	acknowledge: ((step: Step) -> Returned)?,
	readLog: (() -> Returned)?,
	stop: (() -> Returned)?,
	reset: (() -> Returned)?,
	acquire: ((name: string) -> (H?, string?))?,
	release: ((handle: H, name: string) -> Returned?)?,
	interrupted: (() -> boolean)?,
}

export type Handle = {
	send: (self: Handle, step: Step) -> Outcome,
	capture: (self: Handle, step: Step) -> Outcome,
	checkpoint: (self: Handle, checkpoint: Checkpoint) -> Outcome,
}

export type Body = { Step | Checkpoint } | (handle: Handle) -> Failure?

export type ResourcePolicy = { waitSeconds: number, pollSeconds: number }

export type Spec = {
	name: string,
	setup: { Step }?,
	start: Step?,
	body: Body,
	deadlineSeconds: number?,
	resource: ResourcePolicy?,
}

export type Result = {
	name: string,
	ok: boolean,
	status: "passed" | "failed" | "timed_out",
	failure: Failure?,
	cleanupFailures: { Failure },
	records: { Record },
	checkpoints: { string },
	elapsedSeconds: number,
}

export type Run<H = unknown> = { spec: Spec, ops: Ops<H> }
export type Batch = { run: number, step: Step }

type State<H> = {
	spec: Spec,
	ops: Ops<H>,
	began: number,
	records: { Record },
	failure: Failure?,
	cleanupFailures: { Failure },
	checkpoints: { string },
	touched: boolean,
	started: boolean,
}

local DEFAULT_REASONS: { [FailureKind]: string } = {
	failed = "step_failed",
	timeout = "step_timeout",
	threw = "op_threw",
	resource = "resource_unavailable",
	interrupted = "interrupted",
}

local function failureOf(stage: string, phase: Phase, kind: FailureKind, reason: string?, detail: string?): Failure
	return { stage = stage, phase = phase, kind = kind, reason = reason or DEFAULT_REASONS[kind], detail = detail }
end

local function refused(failure: Failure): Outcome
	return {
		ok = false,
		detail = failure.detail,
		reason = failure.reason,
		timedOut = failure.kind == "timeout",
		failure = failure,
	}
end

local function acquire<H>(state: State<H>, name: string): (H?, string?)
	local ops = state.ops
	if ops.acquire == nil then
		return nil, "acquire_unavailable"
	end
	local policy = state.spec.resource
	local waitUntil = ops.now() + (if policy ~= nil then policy.waitSeconds else 0)
	while true do
		local called, handle, why = pcall(ops.acquire :: (string) -> (unknown?, string?), name)
		if not called then
			return nil, tostring(handle)
		end
		if handle ~= nil then
			return handle :: H, nil
		end
		if policy == nil or ops.sleep == nil or ops.now() >= waitUntil then
			return nil, why or "busy"
		end
		(ops.sleep :: (number) -> ())(policy.pollSeconds)
	end
end

local function classify<H>(
	state: State<H>,
	phase: Phase,
	step: Step,
	called: boolean,
	rawReturned: unknown,
	elapsed: number,
	failReason: string?
): Outcome
	local returned = rawReturned :: Returned
	local timeout = step.deadlineSeconds
	local result: Outcome
	if not called then
		result = refused(failureOf(step.id, phase, "threw", nil, tostring(returned)))
	elseif type(returned) ~= "table" or type(returned.ok) ~= "boolean" then
		result = refused(failureOf(step.id, phase, "failed", "op_returned_invalid", nil))
	elseif returned.timedOut == true or (timeout ~= nil and elapsed > timeout) then
		result = refused(failureOf(step.id, phase, "timeout", returned.reason, returned.detail))
		result.output = returned.output
	elseif not returned.ok then
		result = refused(failureOf(step.id, phase, "failed", returned.reason or failReason, returned.detail))
		result.output = returned.output
	else
		result = { ok = true, output = returned.output, detail = returned.detail, reason = returned.reason }
	end
	local failure = result.failure
	table.insert(state.records, {
		id = step.id,
		phase = phase,
		ok = failure == nil,
		timedOut = failure ~= nil and failure.kind == "timeout",
		elapsedSeconds = elapsed,
		output = result.output,
		detail = result.detail,
		artifacts = if type(returned) == "table" then returned.artifacts else nil,
	})
	return result
end

local function callOp<H>(
	state: State<H>,
	phase: Phase,
	step: Step,
	op: ((Step) -> Returned)?,
	name: string,
	failReason: string?
): Outcome
	local ops = state.ops
	if phase ~= "cleanup" then
		if ops.interrupted ~= nil and ops.interrupted() then
			return refused(failureOf(step.id, phase, "interrupted", nil, nil))
		end
		local limit = state.spec.deadlineSeconds
		if limit ~= nil and ops.now() - state.began > limit then
			return refused(failureOf(step.id, phase, "timeout", "run_deadline_exceeded", nil))
		end
	end
	if op == nil and step.run == nil then
		return refused(failureOf(step.id, phase, "failed", "op_missing", name))
	end
	local handle: H? = nil
	if step.resource ~= nil then
		local acquired, why = acquire(state, step.resource)
		if acquired == nil then
			return refused(failureOf(step.id, phase, "resource", nil, ("%s: %s"):format(step.resource, tostring(why))))
		end
		handle = acquired
	end
	local began = ops.now()
	local called, returned = pcall((step.run or op) :: (Step) -> Returned, step)
	local elapsed = ops.now() - began
	if step.resource ~= nil then
		local released, problem = pcall(function(): Returned?
			if ops.release == nil then
				return { ok = false, detail = "release_unavailable" }
			end
			return (ops.release :: (H, string) -> Returned?)(handle :: H, step.resource :: string)
		end)
		if not released or (type(problem) == "table" and problem.ok == false) then
			local detail = if released then (problem :: Returned).detail else tostring(problem)
			table.insert(
				state.cleanupFailures,
				failureOf(step.id .. "/release", "cleanup", "resource", "resource_release_failed", detail)
			)
		end
	end
	return classify(state, phase, step, called, returned, elapsed, failReason)
end

local function sendStep<H>(state: State<H>, phase: Phase, step: Step): Outcome
	return callOp(state, phase, step, state.ops.send, "send", nil)
end

local function checkpoint<H>(state: State<H>, phase: Phase, item: Checkpoint): Outcome
	for _, capture in item.captures do
		local captured = callOp(state, phase, capture, state.ops.capture, "capture", "capture_failed")
		if captured.failure ~= nil then
			return captured
		end
	end
	local acknowledged =
		callOp(state, phase, item.acknowledge, state.ops.acknowledge, "acknowledge", "acknowledge_failed")
	if acknowledged.failure == nil then
		table.insert(state.checkpoints, item.id)
	end
	return acknowledged
end

local function handleFor<H>(state: State<H>): Handle
	return {
		send = function(_self: Handle, step: Step): Outcome
			return sendStep(state, "body", step)
		end,
		capture = function(_self: Handle, step: Step): Outcome
			return callOp(state, "body", step, state.ops.capture, "capture", "capture_failed")
		end,
		checkpoint = function(_self: Handle, item: Checkpoint): Outcome
			return checkpoint(state, "body", item)
		end,
	}
end

local function begin<H>(spec: Spec, ops: Ops<H>): State<H>
	local state: State<H> = {
		spec = spec,
		ops = ops,
		began = ops.now(),
		records = {},
		failure = nil,
		cleanupFailures = {},
		checkpoints = {},
		touched = false,
		started = false,
	}
	local setup: { Step } = spec.setup or {}
	for _, step in setup do
		if step.mutates == true then
			state.touched = true
		end
		local sent = sendStep(state, "setup", step)
		if sent.failure ~= nil then
			state.failure = sent.failure
			return state
		end
	end
	local start = spec.start
	if start ~= nil then
		state.started = true
		state.touched = true
		local opened = callOp(state, "start", start, ops.start, "start", "start_failed")
		state.failure = opened.failure
	end
	return state
end

local function bodyItem<H>(state: State<H>, item: Step | Checkpoint): Failure?
	if (item :: Checkpoint).captures ~= nil then
		return checkpoint(state, "body", item :: Checkpoint).failure
	end
	return sendStep(state, "body", item :: Step).failure
end

local function runBody<H>(state: State<H>)
	if state.failure ~= nil then
		return
	end
	local body = state.spec.body
	if type(body) == "function" then
		local called, failure = pcall(body, handleFor(state))
		if not called then
			state.failure = failureOf("body", "body", "threw", nil, tostring(failure))
		else
			state.failure = failure
		end
		return
	end
	for _, item in body do
		local failure = bodyItem(state, item)
		if failure ~= nil then
			state.failure = failure
			return
		end
	end
end

local function finish<H>(state: State<H>): Result
	local ops = state.ops
	local function cleanup(id: string, op: (() -> Returned)?)
		local called, returned = pcall(function(): Returned
			if op == nil then
				return { ok = true }
			end
			return op()
		end)
		local outcome = classify(state, "cleanup", { id = id }, called, returned, 0, nil)
		if outcome.failure ~= nil then
			table.insert(state.cleanupFailures, outcome.failure)
		end
	end
	if state.started then
		cleanup("readLog", ops.readLog)
		cleanup("stop", ops.stop)
	end
	if state.touched then
		cleanup("reset", ops.reset)
	end
	local failure = state.failure
	local ok = failure == nil and #state.cleanupFailures == 0
	return {
		name = state.spec.name,
		ok = ok,
		status = if ok then "passed" elseif failure ~= nil and failure.kind == "timeout" then "timed_out" else "failed",
		failure = failure,
		cleanupFailures = state.cleanupFailures,
		records = state.records,
		checkpoints = state.checkpoints,
		elapsedSeconds = ops.now() - state.began,
	}
end

local function run<H>(spec: Spec, ops: Ops<H>): Result
	local state = begin(spec, ops)
	runBody(state)
	return finish(state)
end

local function batchable<H>(state: State<H>, item: (Step | Checkpoint)?): boolean
	return state.failure == nil
		and item ~= nil
		and (item :: Checkpoint).captures == nil
		and (item :: Step).resource == nil
end

local function runConcurrent<H>(runs: { Run<H> }, parallel: ((batch: { Batch }) -> { Returned })?): { Result }
	local states: { State<H> } = {}
	local rounds = 0
	for index, entry in runs do
		states[index] = begin(entry.spec, entry.ops)
		local body = entry.spec.body
		if type(body) == "function" then
			runBody(states[index])
		else
			rounds = math.max(rounds, #body)
		end
	end
	for round = 1, rounds do
		local batch: { Batch } = {}
		local began: { [number]: number } = {}
		for index, state in states do
			local body = state.spec.body
			if parallel ~= nil and type(body) == "table" then
				local item = body[round]
				if batchable(state, item) then
					table.insert(batch, { run = index, step = item :: Step })
				end
			end
		end
		local delivered: { [number]: boolean } = {}
		if #batch > 0 then
			for _, entry in batch do
				began[entry.run] = states[entry.run].ops.now()
			end
			local called, returned = pcall(parallel :: (batch: { Batch }) -> { Returned }, batch)
			for position, entry in batch do
				local state = states[entry.run]
				local elapsed = state.ops.now() - began[entry.run]
				local outcome = if called and type(returned) == "table"
					then classify(state, "body", entry.step, true, returned[position], elapsed, nil)
					else classify(state, "body", entry.step, false, returned, elapsed, nil)
				state.failure = outcome.failure
				delivered[entry.run] = true
			end
		end
		for index, state in states do
			local body = state.spec.body
			if type(body) == "table" and not delivered[index] and state.failure == nil and body[round] ~= nil then
				state.failure = bodyItem(state, body[round])
			end
		end
	end
	local results: { Result } = {}
	for index, state in states do
		results[index] = finish(state)
	end
	return results
end

local function failures(result: Result): { Types.Failure }
	local rows: { Types.Failure } = {}
	local function add(failure: Failure)
		local phase: Types.FailurePhase = if failure.phase == "cleanup"
			then "cleanup"
			elseif failure.phase == "body" then "case"
			else "setup"
		local message = ("%s: %s"):format(failure.stage, failure.reason)
		if failure.detail ~= nil and failure.detail ~= "" then
			message ..= ": " .. failure.detail
		end
		table.insert(rows, {
			phase = phase,
			outcome = if failure.kind == "timeout" then "timed_out" else "failed",
			message = message,
		})
	end
	if result.failure ~= nil then
		add(result.failure)
	end
	for _, failure in result.cleanupFailures do
		add(failure)
	end
	return rows
end

export type Context = {
	artifact: (self: Context, name: string, reference: string, mediaType: string?) -> (),
}

local function attach(context: Context, result: Result)
	for _, record in result.records do
		local artifacts: { Types.Artifact } = record.artifacts or {}
		for _, artifact in artifacts do
			context:artifact(record.id .. "/" .. artifact.name, artifact.reference, artifact.mediaType)
		end
	end
	if result.ok then
		return
	end
	local parts: { string } = {}
	for position, row in failures(result) do
		table.insert(parts, if position == 1 and result.failure ~= nil then row.message else "cleanup " .. row.message)
	end
	error(("%s failed: %s"):format(result.name, table.concat(parts, "; ")), 0)
end

return {
	attach = attach,
	run = run,
	runConcurrent = runConcurrent,
	failures = failures,
}
