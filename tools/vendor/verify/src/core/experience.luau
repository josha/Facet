--!strict

local Harness = require "./harness"
local Types = require "./types"
local Reports = require "./report"
local Matchers = require "./matchers"
local Performance = require "./performance"

export type Request = {
	kind: "action" | "query",
	actor: string,
	name: string,
	payload: unknown,
	deadline: number,
}
export type JudgmentRequest = {
	actor: string,
	checkpoint: string,
	criterion: string,
	artifacts: { Types.Artifact },
}
export type Judgment = {
	status: "passed" | "failed" | "unreviewed",
	reviewer: string,
	detail: string,
}
export type Host = {
	name: string,
	capabilities: { string },
	environment: { [string]: string },
	now: () -> number,
	invoke: (request: Request) -> unknown,
	capture: ((actor: string, checkpoint: string) -> { Types.Artifact })?,
	judge: ((request: JudgmentRequest) -> Judgment)?,
	close: (() -> ())?,
}
export type Observation = {
	kind: "action" | "query",
	actor: string,
	name: string,
	value: unknown,
}
export type Checkpoint = {
	actor: string,
	name: string,
	artifacts: { Types.Artifact },
}
export type Review = {
	actor: string,
	checkpoint: string,
	criterion: string,
	judgment: Judgment,
}
export type Measurement = {
	actor: string,
	name: string,
	evaluation: Performance.Evaluation,
}
export type Parity = {
	status: "passed" | "failed" | "unsupported",
	differences: { string },
}
export type Evidence = {
	measurements: { Measurement },
	observations: { Observation },
	checkpoints: { Checkpoint },
	reviews: { Review },
}
export type Context = {
	check: Harness.Context,
	measure: (actor: string, name: string, input: Performance.Input, limits: Performance.Limits) -> (),
	action: (actor: string, name: string, payload: unknown) -> (),
	query: (actor: string, name: string, payload: unknown) -> unknown,
	checkpoint: (actor: string, name: string) -> (),
	judge: (actor: string, checkpoint: string, criterion: string) -> (),
}
export type Case = {
	id: string,
	name: string,
	requires: { string },
	timeoutSeconds: number,
	run: (context: Context) -> (),
}
export type Result = {
	report: Types.Report,
	evidence: { [string]: Evidence },
}

local function finite(value: number): boolean
	return value == value and math.abs(value) < math.huge
end

local function snapshot(value: unknown, ancestors: { [unknown]: boolean }?): unknown
	local kind = type(value)
	if kind == "nil" or kind == "string" or kind == "boolean" then
		return value
	elseif kind == "number" then
		assert(finite(value :: number), "observations must be finite")
		return value
	end
	assert(kind == "table", "observations must be portable values")
	local seen: { [unknown]: boolean } = ancestors or {}
	assert(not seen[value], "observations must not contain cycles")
	seen[value] = true
	local copy: { [string | number]: unknown } = {}
	for key, child in value :: { [unknown]: unknown } do
		assert(type(key) == "string" or type(key) == "number", "observation keys must be strings or numbers")
		if type(key) == "number" then
			assert(finite(key), "observation keys must be finite")
		end
		copy[key :: string | number] = snapshot(child, seen)
	end
	seen[value] = nil
	return table.freeze(copy)
end

local function register(harness: Harness.Harness, spec: Case, host: Host, evidence: { [string]: Evidence })
	assert(spec.id ~= "" and spec.name ~= "", "experience case needs an id and name")
	assert(finite(spec.timeoutSeconds) and spec.timeoutSeconds > 0, "experience timeout must be finite and positive")
	assert(evidence[spec.id] == nil, "duplicate experience id")
	local recorded: Evidence = { observations = {}, checkpoints = {}, reviews = {}, measurements = {} }
	evidence[spec.id] = recorded
	harness:case(spec.name, {
		id = spec.id,
		requires = spec.requires,
		run = function(check)
			if host.close ~= nil then
				check:defer(host.close :: () -> ())
			end
			local began = host.now()
			assert(finite(began), "host clock must be finite")
			local deadline = began + spec.timeoutSeconds
			local last = began
			local function withinDeadline()
				local current = host.now()
				assert(finite(current) and current >= last, "host clock must be finite and monotonic")
				last = current
				assert(current < deadline, "experience deadline exceeded")
			end
			local function invoke(kind: "action" | "query", actor: string, name: string, payload: unknown): unknown
				assert(actor ~= "" and name ~= "", "operation actor and name must not be empty")
				local value: unknown = nil
				check:step(kind .. " " .. name, {
					actor = actor,
					run = function()
						withinDeadline()
						assert(
							table.find(host.capabilities, kind .. ":" .. name) ~= nil,
							"unsupported operation: " .. kind .. ":" .. name
						)
						value = snapshot(host.invoke {
							kind = kind,
							actor = actor,
							name = name,
							payload = snapshot(payload),
							deadline = deadline,
						})
						withinDeadline()
						table.insert(recorded.observations, { kind = kind, actor = actor, name = name, value = value })
					end,
				})
				return value
			end
			local context: Context = {
				check = check,
				measure = function(actor, name, input, limits)
					check:step("measure " .. name, {
						actor = actor,
						run = function()
							withinDeadline()
							assert(actor ~= "" and name ~= "", "measurement needs actor and name")
							local evaluation = Performance.evaluate(Performance.summarize(input), limits)
							table.insert(recorded.measurements, { actor = actor, name = name, evaluation = evaluation })
							check:expect(evaluation.status):toBe "passed"
						end,
					})
				end,
				action = function(actor, name, payload)
					invoke("action", actor, name, payload)
				end,
				query = function(actor, name, payload)
					return invoke("query", actor, name, payload)
				end,
				checkpoint = function(actor, name)
					check:step("checkpoint " .. name, {
						actor = actor,
						run = function()
							withinDeadline()
							assert(actor ~= "" and name ~= "", "checkpoint needs actor and name")
							for _, prior in recorded.checkpoints do
								assert(prior.actor ~= actor or prior.name ~= name, "duplicate checkpoint")
							end
							local capture = host.capture
							assert(
								capture ~= nil and table.find(host.capabilities, "capture") ~= nil,
								"capture unavailable"
							)
							local artifacts = capture(actor, name)
							withinDeadline()
							assert(#artifacts > 0, "capture returned no evidence")
							local copies: { Types.Artifact } = {}
							for _, artifact in artifacts do
								assert(
									artifact.name ~= "" and artifact.reference ~= "",
									"artifact needs a name and reference"
								)
								check:artifact(artifact.name, artifact.reference, artifact.mediaType)
								table.insert(copies, table.freeze(table.clone(artifact)))
							end
							table.insert(
								recorded.checkpoints,
								{ actor = actor, name = name, artifacts = table.freeze(copies) }
							)
						end,
					})
				end,
				judge = function(actor, checkpoint, criterion)
					check:step("judge " .. criterion, {
						actor = actor,
						run = function()
							withinDeadline()
							assert(criterion ~= "", "judgment needs a criterion")
							local captured: Checkpoint? = nil
							for _, candidate in recorded.checkpoints do
								if candidate.actor == actor and candidate.name == checkpoint then
									captured = candidate
								end
							end
							assert(captured ~= nil, "judgment requires captured evidence")
							local judge = host.judge
							assert(
								judge ~= nil and table.find(host.capabilities, "judgment") ~= nil,
								"judgment unavailable"
							)
							local result = judge {
								actor = actor,
								checkpoint = checkpoint,
								criterion = criterion,
								artifacts = captured.artifacts,
							}
							withinDeadline()
							assert(
								result.reviewer ~= "" and result.detail ~= "",
								"judgment needs reviewer and reasoning"
							)
							assert(
								result.status == "passed" or result.status == "failed" or result.status == "unreviewed",
								"invalid judgment status"
							)
							table.insert(recorded.reviews, {
								actor = actor,
								checkpoint = checkpoint,
								criterion = criterion,
								judgment = table.freeze(table.clone(result)),
							})
							check:expect(result.status):toBe "passed"
						end,
					})
				end,
			}
			spec.run(context)
			withinDeadline()
		end,
	})
end

local function run(spec: Case, host: Host): Result
	local harness = Harness.createHarness { now = host.now }
	local evidence: { [string]: Evidence } = {}
	register(harness, spec, host, evidence)
	local report =
		harness:run { executor = host.name, capabilities = host.capabilities, environment = host.environment }
	return { report = report, evidence = evidence }
end

local function parity(left: Result, right: Result): Parity
	local differences = Reports.verdictDifferences(left.report, right.report)
	local unsupported = left.report.total == 0 or right.report.total == 0
	for _, result in left.report.results do
		if result.status ~= "passed" then
			unsupported = true
		end
		local a, b = left.evidence[result.id], right.evidence[result.id]
		if a == nil or b == nil then
			table.insert(differences, result.id .. ": missing observations")
		elseif not Matchers.deepEqual(a.observations, b.observations) then
			table.insert(differences, result.id .. ": observations differ")
		end
	end
	for _, result in right.report.results do
		if result.status ~= "passed" then
			unsupported = true
		end
	end
	return {
		status = if #differences > 0 then "failed" elseif unsupported then "unsupported" else "passed",
		differences = differences,
	}
end

return { register = register, run = run, parity = parity, snapshot = snapshot }
