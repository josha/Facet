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
`returned`, `faulted`, `timed_out`, or `cancelled`; only a returned valid report carries verdicts.
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

## Case lifecycle and waits

Every tier uses the [ordinary harness context](experience.md#one-case-model). Acquire actors and
resources in `bind(context)`, registering cleanup with `context:defer` before each fallible acquisition.
Perform readiness queries with `context:await`. Put actions, assertions and checkpoints in the case.
The harness retains body and cleanup failures independently. There is no separate scenario lifecycle,
actor runner or transcript verdict model.

`Core.waitUntil` is the standalone read-only polling primitive. `Lute.runBounded(argv, seconds)`
enforces an external process-group deadline. `Lute.directoryLock(root)` provides cross-process resource
ownership. These are host utilities, not alternative case formats.

`Core.accountPlan(plan, execution)` reports what ran, unsupported units and completeness.
`Core.mediaProbeSummary`, `mediaAudioWindow`, `mediaAudioMeasurement` and `mediaSampleCommands`
decode media measurements. Decoding alone provides no visual or audible judgment.

## Lute workers

`Lute.host({worker, command?, directory, capabilities?, ...})` starts one process per batch.
The worker process group is bounded by the batch deadline or host `deadlineSeconds` (default 60).
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

## Native Studio execution

`Lute.studio.run({place, code, worker, context?, deadlineSeconds?, directory?, studioExecutable?,
mcpExecutable?, players?, finalCapture?})` copies an XML place into an isolated run directory, starts a disposable Studio,
selects its unique document through the official Studio MCP, starts play and executes `code` in
`Server` (default) or `Client`. Use the provided `tools/studio-worker.luau` as `worker`. macOS is the
reference platform; the launcher uses POSIX process groups. It never attaches to an existing place.
Studio must already be installed, authenticated and configured for its MCP tools.

The engine code receives `runId`. Run ordinary cases or a source-bound session and return
`HttpService:JSONEncode(Roblox.reportChannel.envelope(runId, report))`. The launcher validates identity
and the ordinary report schema. Missing, malformed or wrong-run reports fault. Results use the existing
`BatchOutcome`: returned, faulted or timed_out. A returned report can contain failed cases.

`Lute.studio.host({place, worker, codeForBatch, capabilities, ...})` implements the standard `Core.Host`
for `Core.execute`; `codeForBatch(batch)` loads and registers that batch's ordinary cases in the engine.
The consumer owns its mounted test modules and operation bindings. No additional scenario format exists.

The default run limit is 90 seconds. An external watchdog kills the owned worker process group,
including Studio and the MCP process, on timeout. Normal success/failure also terminates those owned
processes. Case budgets remain cooperative inside the engine; the outer run limit is enforced even
when engine code never yields. Temporary run directories retain the input, engine/MCP diagnostics and
one report for diagnosis. They are disposable, not a second receipt ledger.

`lute run tools/native-conformance.luau` builds the reference fixture from current source and tests
simulator/server observation parity, detection of a native mutation defect, a client's actual jump
and landing, and termination of a wedged engine. `lute run tools/gate.luau --native` includes this check.
A missing/unavailable engine fails the native command. The default portable gate does not run it and
cannot establish native parity. Use the native gate when changing engine behavior or its launcher.

Set `players = 1..8` to run a server with that many actual Studio clients through
`StudioTestService:ExecuteMultiplayerTestAsync`. The code runs on the server and ends the test with
its report. See the [multiplayer example](../examples/multiplayer.luau); the native gate runs it.

For single-client runs, `finalCapture = true` saves the final active Studio viewport through the
supported MCP capture tool before closing Studio. The last case retains the image path and media
type. This is a final-state artifact, not an earlier checkpoint or a visual judgment. Captures are
not silently substituted between actors. Multiplayer client capture callbacks need their own
durable sink; `CaptureService` temporary image references expire with the client.

## Published Player execution

Build the authorized test place with `Lute.platform.buildPublished`, then run the same entry through
`--host player`. [Setup and commands](running.md) own this workflow. The builder
supports server execution with client report relay, or client execution after server authorization.
The server checks the actual joined UserId, entry identity and selected case IDs. Launch data is
correlation, not authorization. Each player can execute only one request per join.

The lower-level `Lute.player.run { placeId, runId, entry?, caseIds?, logPath?, deadlineSeconds? }`
opens the documented Roblox deep link with the signed-in account. The macOS reference backend
requires Roblox.app and no existing Player process. It reads the log held open by the new PID,
validates the ordinary framed report and run identity, and stops that owned process. `logPath` saves
the collected raw log before cleanup. The default deadline is 90 seconds. Missing, stale, malformed
or incomplete reports, exits and cleanup failures cannot pass. Ambiguous process ownership faults.
A delayed OS launch can finish after the startup deadline; Verify does not kill an unidentified process.
The launcher neither publishes places nor installs scripts into existing experiences.
After republishing, use a new server running the intended place version. Entry and case selection do
not identify a deployment revision; a valid report from an old server is not proof of the new build.

`backend` can supply another platform's typed `now`, `sleep` and `launch` implementation. Its session
provides `read(remainingSeconds)`, `alive(remainingSeconds)` and `close()`. Respect deadlines and release
partial acquisitions on failure. [Launcher tests](../tests/player-launcher.spec.luau) exercise this
contract. Real published Player validation has exercised native character motion, generated fixture
execution, selected cases, standard report collection and owned-process cleanup. This does not prove
multiple authenticated Players or durable screenshots: the reference launcher drives one authenticated
client per machine and has no durable screenshot export. Studio multiplayer remains separate evidence.

## Report transport

`Roblox.reportChannel.envelope(runId, report)` validates a report and binds its run identity.
`receive(envelope, runId)` rejects other runs. `publish(runId, report, encode, emit)` writes framed
`VERIFY_REPORT` lines; `collect(bytes, runId, decode)` reassembles and validates them. Supply the host's
JSON codec and output sink. This is the same report for unit and end-to-end cases, not a log-derived
verdict. Tagged transport rejects missing, mixed, conflicting or multiple complete reports.
A matching id is correlation, not authentication; callers own channel access and evidence custody.
