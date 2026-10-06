--!strict

local Benchmark = require "./benchmark"
local Provenance = require "./provenance"
local Types = require "./types"

export type Kind = "tests" | "command" | "build" | "native" | "benchmark"
export type ExitClass = "passed" | "failed" | "deferred" | "unsupported"

export type ReportExpectation = {
	cases: { string }?,
	minimum: number?,
}

export type ProducerDraft = {
	id: string,
	kind: Kind,
	after: { string }?,
	tier: string?,
	tags: { string }?,
	requires: { string }?,
	deadlineSeconds: number?,
	exclusive: boolean?,
	argv: { string }?,
	exit: { [number]: ExitClass }?,
	env: { [string]: string }?,
	cwd: string?,
	report: ReportExpectation?,
	worker: string?,
	locators: { string }?,
	benchmark: Benchmark.Spec?,
}

export type Producer = {
	id: string,
	kind: Kind,
	after: { string },
	tier: string?,
	tags: { string },
	requires: { string },
	deadlineSeconds: number,
	exclusive: boolean,
	argv: { string },
	exit: { [number]: ExitClass },
	env: { [string]: string },
	cwd: string?,
	report: ReportExpectation?,
	worker: string?,
	locators: { string },
	benchmark: Benchmark.Spec?,
}

export type PolicyDraft = {
	concurrency: number?,
	deadlineSeconds: number?,
	commandDeadlineSeconds: number?,
	failFast: boolean?,
	deferrals: { [string]: string }?,
	reuse: { string }?,
	requires: { string }?,
}

export type Policy = {
	concurrency: number,
	deadlineSeconds: number?,
	commandDeadlineSeconds: number,
	failFast: boolean,
	deferrals: { [string]: string },
	reuse: { string },
	requires: { string },
}

export type GateDraft = {
	id: string,
	producers: { ProducerDraft },
	policy: PolicyDraft?,
}

export type Gate = {
	schemaVersion: number,
	id: string,
	digest: string,
	producers: { Producer },
	policy: Policy,
	plan: Types.Plan,
}

export type Selection = {
	ids: { string }?,
	tiers: { string }?,
	tags: { string }?,
}

export type Reuse = {
	report: unknown,
	reference: string,
	validatedBy: string,
	build: Provenance.Build?,
}

export type Job = {
	id: string,
	kind: "tests" | "command" | "build" | "native",
	argv: { string },
	env: { [string]: string },
	cwd: string?,
	worker: string?,
	locators: { string },
	runId: string,
	expectsReport: boolean,
	deadlineSeconds: number,
}

export type JobOutcome = {
	started: boolean,
	exitcode: number,
	timedOut: boolean,
	stdout: string,
	stderr: string,
	report: unknown?,
	detail: string?,
	logReference: string?,
}

export type Task = {
	poll: () -> JobOutcome?,
}

export type Executor = {
	now: () -> number,
	wait: (seconds: number) -> (),
	start: (job: Job) -> Task,
}

export type RunOptions = {
	runId: string,
	build: Provenance.Build?,
	selection: Selection?,
	reuse: { [string]: Reuse }?,
	capabilities: { string }?,
	environment: { [string]: string }?,
	name: string?,
	logBytes: number?,
	pollSeconds: number?,
	observe: ((record: ProducerRecord) -> ())?,
	fixtures: { { name: string, acquire: () -> (), release: (() -> ())? } }?,
}

export type Status =
	"passed"
	| "failed"
	| "timed_out"
	| "unsupported"
	| "deferred"
	| "blocked"
	| "not_run"
	| "not_selected"

export type Log = {
	stdout: string,
	stderr: string,
	bytes: number,
	truncated: boolean,
	reference: string?,
}

export type ProducerRecord = {
	id: string,
	kind: Kind,
	tier: string?,
	status: Status,
	selected: boolean,
	pulledByDependency: boolean,
	exitcode: number?,
	timedOut: boolean,
	durationMicros: number,
	detail: string?,
	log: Log?,
	reportAccounted: boolean,
	caseIds: { string },
	reused: boolean,
	reuseReference: string?,
	deferral: string?,
	blockedBy: string?,
}

export type Verdict = "release" | "deferred" | "selected" | "failed"

export type Acceptance = {
	verdict: Verdict,
	releasable: boolean,
	complete: boolean,
	reasons: { string },
	passed: { string },
	failed: { string },
	deferred: { string },
	reused: { string },
	notSelected: { string },
}

export type Outcome = {
	schemaVersion: number,
	gate: string,
	digest: string,
	runId: string,
	build: Provenance.Build?,
	execution: Types.ExecutionReport,
	producers: { ProducerRecord },
	acceptance: Acceptance,
}

return nil
