# Execution contract

A plan is a finite set of units, declared capabilities and policy. Verify executes that plan.
The consumer defines each locator and supplies the authorized host.

`Core.validatePlan(draft)` normalizes ids, locators, groups, tags, requirements, weights and policy.
Duplicate ids/locators and malformed fields fail. `selectPlan` narrows by ids, tags, capabilities,
groups or a predicate over the same source-bearing subject used by harness/session selection.
`partitionPlan(plan, count, mode?)` assigns every unit once and keeps fixture groups whole.
Count and weighted batching are deterministic functions of authored metadata. `planDigest` binds
meaning, not timing. `caseId` composes stable ids. `planFromManifest` accepts an explicitly validated
manifest. `validateManifest` remains the input boundary. All selection and partitioning use the plan.
Discovery and changed-file reachability belong to consumers, not a second scheduler in Verify.

## Host boundary

`Core.execute(plan, host, options?)` drives capability negotiation, fixture setup/cleanup, batching,
run deadlines, failure accounting and receipt composition. A host supplies `runBatch`; optional
parallel dispatch and artifact routing preserve the same report semantics. A batch outcome is
`completed`, `faulted`, `timed_out`, or `cancelled`; only a completed valid report carries verdicts.
The host must stop timed-out/cancelled work and account for every dispatched batch. A clean exit
without the expected receipt is a fault.

`execute` derives completeness from the original plan. Narrowing, missing results, infrastructure
faults and contradictory retries remain explicit facts. A narrowed pass is not the complete gate.
Retries apply only to declared infrastructure outcomes. The report retains every attempt. Verify never retries ordinary
assertion failures to obtain a pass. Fixture and cleanup failures remain independently
visible. Artifact sinks return references, not proof of durability or authenticity.

The typed `Host`, `BatchOutcome`, `ExecutionOptions`, `PlanPolicy` and returned `ExecutionReport`
are exported by `src/core`. [Behavioral tests](../tests/execution.spec.luau) exercise dropped,
reordered, duplicate, forged and disagreeing deliveries using the injected fake host.

## Run lifecycle

`Core.runLifecycle(spec, ops)` drives one external run through injected host operations: ordered `setup`
steps, a `start` step, a `body`, then cleanup. The body is a list of steps and checkpoints or a function
that receives a handle (`send`, `capture`, `checkpoint`). A checkpoint captures each declared row, then
acknowledges; it counts as reached only after the acknowledgment succeeds. `ops` supplies `now` and
optional `sleep`, `start`, `send`, `capture`, `acknowledge`, `readLog`, `stop`, `reset`, `acquire`,
`release` and `interrupted`. A missing operation that a step needs is a failure, not a pass.

The first failure is the run's `failure`: `failed`, `timeout`, `threw`, `resource` or `interrupted`, with
the step id, phase and reason. Cleanup always runs after it, in order: `readLog` and `stop` once `start`
was attempted (a failed start may be half started), then `reset` once `start` or any step marked
`mutates` was attempted. A cleanup failure goes to `cleanupFailures` and never replaces `failure`; a run
with only cleanup failures is not ok. `Core.lifecycleFailures(result)` returns both in the report
`Failure` shape.

A step may carry its own host operation in `run`; it replaces the shared `send`, `capture` or `acknowledge`
operation for that step. A step's `deadlineSeconds` is passed to the host operation and checked against `now` after it returns, as
is the spec's run deadline before each step. Verify cannot stop work a blocking host call does not end;
the host operation must enforce the bound and may return `timedOut`. A step naming `resource` holds that
exclusive resource only around its own operation. `acquire` is polled with `sleep` within the spec's
`resource` wait budget; the release runs after success or failure and a release failure is a cleanup
failure. Language-level cleanup cannot survive a killed host process; recovering that host belongs to the
consumer.

`Core.runConcurrentLifecycles(runs, parallel?)` begins each run in order, hands the runs' resource-free
single steps of each round to `parallel` as one batch for the host to run together, then finishes every
run. Runs fail and clean up independently. Resource steps and checkpoints run one at a time in the
calling process, so a resource shared by concurrent processes is taken inside each process.
[Behavioral tests](../tests/lifecycle.spec.luau) use fake host operations.

## Waits, actors and evidence

`Core.waitUntil({name, deadlineSeconds, pollSeconds, probe, describe?}, {now, sleep, cancelled?})`
polls `probe(remainingSeconds) -> (done, observed, refusal?)`. It returns `satisfied`, `timeout`,
`cancelled`, `refused` (the probe named a hard failure; no retry) or `probe_threw`, with the waited
seconds, the poll count and the last observed value; the timeout detail names the wait and that value.
A probe must only read. Verify cannot interrupt a blocking probe, so a host call that can hang must
enforce `remainingSeconds` itself; `Lute.runBounded(argv, seconds)` does this by killing the command's
process group at the limit and reporting `timedOut`. `Lute.directoryLock(root)` returns `acquire(name)` and
`release(handle)` for a named exclusive resource shared by processes: it makes a lock directory, and takes
over one whose recorded holder process no longer exists.

`Core.actorNames(count, prefix?)` names actors (`client-1`...). `Core.runActors({name, actors,
resources?, deadlineSeconds, pollSeconds, body}, ops)` runs the lifecycle for several named
participants: it takes each named shared resource, joins every actor, waits until each reports ready
(a ready actor is not probed again, a lost actor fails the run by name), runs the body, then always
leaves the actors in reverse order and releases the resources. Leave and release failures are cleanup
failures and never replace the body failure. The caller supplies `join`, `probe`, `leave`, and the
lifecycle operations the body uses. Actions, predicates and participant counts stay with the consumer.

A host operation may return `artifacts` (still, burst frame, clip, audio sample, metric file). The
lifecycle keeps them per step; `Core.attachLifecycle(context, result)` attaches each to the running
case as `<step>/<name>` and then throws the failure and the cleanup failures as one message, so the
evidence and the verdict live in the same report. `Core.mediaProbeSummary`, `mediaAudioWindow`,
`mediaAudioMeasurement` and `mediaSampleCommands` are the pure parts of decoding a recording; they claim
no visual or audible judgment.

`Core.accountPlan(plan, execution)` lists, for the plan's units, what ran, which capability each
unsupported unit lacked, what was not run, and whether the plan was complete. Select with
`selectPlan` or the `selection` option, run on any host, and account with this one path.

## Lute workers

`Lute.host({worker, command?, directory, capabilities?, ...})` starts one process per batch.
Use a separate directory for each concurrent run; its batch inputs and reports remain available for
failure diagnosis. Consumer output files remain the consumer's isolation responsibility.

`worker` loads a registration function returned by each module. `selfRegisteringWorker` instead calls
`load(locator, harness)`, so an existing BDD surface can register against each unit's private harness.
Both use the same session and failure classifier. No global registry is created on import.
[The self-registering example](../examples/self-registering-worker.luau) shows the caller seam.

`runWorkerBatch` and `runSelfRegisteringWorkerBatch` expose that lifecycle for injected execution.
An explicit `classifyLoadFailure` may name a recognized prerequisite as skipped/unsupported.
Unrecognized or throwing classifiers leave a hard failure. Successful loading followed by broken
registration is a failure. Every missing source remains a named case.

`Lute.corpus` supplies injected discovery rules, require-affinity grouping, literal subset matching,
worker bounds and stable lock text. A query matching nothing selects nothing. The consumer owns
filesystem discovery and the committed complete corpus. A static require scan cannot infer dynamic edges. `encodeBatch`/`decodeBatch` transport the existing plan-batch schema.

## Engine and external execution

Mount the portable core/BDD and needed Roblox adapters. Create a source-bound session or harness.
Transport its report. Engine manifests, live services, driver startup, publication identity,
credentials, scheduling, image capture and durable storage are consumer operations. Verify's
injected observation/capture/tier adapters judge those supplied facts; they do not authenticate a
remote service or authorize an external action.

Use tagged log transport or bounded segments from [the API](api.md#reports-and-transport). Enumerate
all expected responses. Refuse missing, mixed, conflicting and stale evidence before release
acceptance. A saved old report proves no current source, environment, screenshot or runtime result.
