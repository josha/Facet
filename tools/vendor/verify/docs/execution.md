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

## Lune workers

`Lune.host({worker, command?, directory?, deadlineSeconds?, ...})` from `src/lune` is the Lute host with a different
runtime binding: one real `lune run` process per batch, the same plan batches, session, load/registration
classification and report schema. `Lune.worker`, `selfRegisteringWorker`, `runWorkerBatch`,
`runSelfRegisteringWorkerBatch`, `runBounded`, `encodeBatch`/`decodeBatch` mirror the Lute names. Run
`lune run examples/lune-run.luau` for a three-batch consumer run with a passing, a failing and a missing unit.

The logic lives once in `src/runtime` over a `Runtime` binding `{ name, defaultCommand, defaultDirectory,
json, fs, process, time, stdio }`; `src/lute/runtime.luau` and `src/lune/runtime.luau` supply the services and
`Binding.validate` refuses an incomplete one. A third runtime needs only a binding. The Lute entry points are
unchanged and keep the plain-report protocol.

A Lune host defaults to `receipts = "bound"`: the host passes a unique run id as the worker's third argument
and the worker writes `{ receiptVersion, runId, batchId, report }` to a per-run file. The host returns a report
only when the receipt parses, belongs to this run and batch, decodes as a valid report and the worker exited
zero. Missing, malformed, stale (other run), foreign (other batch) or invalid receipts, a nonzero exit beside a
receipt, an unstartable or absent worker and every timeout are faults or timeouts, never a pass. Worker
output is kept beside the receipt as `*-worker.log` and named in the fault detail. `receipts = "report"` (the
Lute default) accepts a plain report and ignores the exit status. Load, registration and empty-discovery
outcomes are the ordinary case results and `Core.execute` facts.

The batch deadline kills the worker's POSIX process group, including grandchildren, through `/bin/sh`.
Limits: macOS and Linux only; `lune` must be on `PATH` or named in `command`; each worker resolves its own
`require` paths relative to its script; `@lune/*` services are loaded dynamically, so static analysis does
not type them; a pass proves Luau logic under Lune, not Lute, Studio or Player behavior.
`tools/lune-test.luau` drives real `lune` subprocesses for these claims.

## Declarative gates

`Core.defineGate({ id, producers, policy? })` declares what must be produced. `Lute.gate.run(gate, options?)` and
`Lune.gate.run` execute it through `Core.execute`: one plan, one `Core.Report`, no second scheduler or receipt. Both
are bindings over `src/runtime/gate.luau`; another host calls `Core.runGate(gate, executor, { runId, ... })` with an
injected `{ now, wait, start }`.

| Producer | Fields | Runs |
| --- | --- | --- |
| `tests` | `worker`, `locators` | Ordinary spec modules in one [Lute worker](#lute-workers) process. Every locator must report a case. |
| `command`, `build`, `native` | `argv`, `env?`, `cwd?`, `exit?`, `report?` | An argument vector in a bounded process group, with `env` added to the inherited environment and `cwd` set through the runtime binding (no shell wrapper). `native` must name its host in `requires`. |
| `benchmark` | `benchmark` | A [benchmark](experience.md#benchmarks) in this process, alone by default. |

Every producer has a unique `id` and may set `after`, `tier`, `tags`, `requires`, `deadlineSeconds` (default
`policy.commandDeadlineSeconds`, 300) and `exclusive`. Policy sets `concurrency` (default 1), whole-run
`deadlineSeconds`, `failFast`, `deferrals` and `reuse`.

- **Order and concurrency.** Producers start in declaration order once everything they run `after` has passed, never more than
  `concurrency` at once; an exclusive producer runs alone. A producer after one that did not pass is `blocked`.
- **Deadlines.** Each command is bounded as by `runBounded` and its process group is killed at the limit
  (whole seconds, rounded up). The run deadline clamps each start; producers it prevents from starting
  are `timed_out`.
- **Exit and reports.** Exit zero passes unless `exit` maps the code to `passed`, `failed`, `deferred` or
  `unsupported`. A producer with `report` must also deliver a current-run report: `{report}` and `{run}` in
  `argv` become the report path and run id, and the command writes `Lute.gate.writeReport(path, run, report)`,
  the `{ runId, report }` envelope used by the Roblox report channel. The old file is deleted first; another run id, an undecodable
  report, fewer than `report.minimum` cases or a missing `report.cases` entry fails. Exit and report must agree.
  Adopted cases are named `<producer>:<case>`.
- **Selection.** `{ ids, tiers, tags }` narrows the run (all given kinds must match; any listed value of one kind).
  Dependencies are pulled in and marked. Unknown or empty selections raise. Anything short of every producer yields
  verdict `selected`, never `release`.
- **Acceptance.** `outcome.acceptance.verdict` is `release`, `deferred`, `selected` or `failed`; only `release`
  is `releasable`. A missing host capability is `unsupported` and fails. `policy.deferrals[id] = reason` makes an
  unsupported producer, or an exit code classed `deferred`, `deferred` instead; unnamed ones fail. A deferral is explicit and
  never a release.
- **Reuse.** `options.reuse[id] = { report, reference, validatedBy }` satisfies a producer without running it, only for
  ids in `policy.reuse`. The report is decoded and accounted like any other and the result is marked `reused` with a
  limitation. The caller validates that the receipt matches the current artifact; Verify cannot.
- **Build binding.** `options.build` (an `EvidenceBuild`, see [Evidence provenance](api.md#evidence-provenance)) is recorded in
  the report environment and the outcome. When set, a reused receipt must carry the same build digest or the producer fails.
- **Outcome.** `{ runId, digest, build?, execution, producers, acceptance }`. Every declared producer has a record (status, exit
  code, bounded log tails, case ids, reuse, deferral). `execution.report` is the receipt; `Core.formatGate` renders it.
  Full logs are written under `<directory>/<runId>/`.

Limits: a benchmark runs in the gate's own process and stops only cooperatively between samples; the gate digest
binds the definition but not benchmark closures; output is not streamed (use `observe` for progress).

## Native Studio execution

`Lute.studio.run({place, code, worker, context?, deadlineSeconds?, directory?, studioExecutable?,
mcpExecutable?, players?, finalCapture?})` copies an XML place into an isolated run directory, starts a disposable Studio,
selects its unique document through the official Studio MCP, starts play and executes `code` in
`Server` (default) or `Client`. Use the provided `tools/studio-worker.luau` as `worker`. macOS is the
reference platform; the launcher uses POSIX process groups. `run` never attaches unless given `attach`
(see [Attached Studio](#attached-studio)).
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

## Attached Studio

`Lute.studio.attach(options)` uses a Studio the developer already has open, through the official Studio
MCP. It returns `session, refusal`. `options` is `{ authorize, studioId?, match?, transport?,
mcpExecutable?, directory?, mode?, callSeconds?, runSeconds?, cleanupSeconds? }`.

Discovery lists open Studios (`list_roblox_studios`) and selects the one with `studioId` and/or for
which `match({ id, name })` is true. A missing selector, no match (`absent`) or several matches
(`ambiguous`) is a refusal naming the candidates; Verify never picks implicitly.

`authorize(request)` is required and returns `{ ok, reason? }`. It receives each request before any
bytes leave: `{ tool, argumentsJson, fields, studioId, bytes, digest }`, where `bytes` is
`{"name":...,"arguments":...}` exactly as sent and `digest` its SHA-256 hex. A refusal, a raise or a
request aimed at another Studio sends nothing. Verify defines no policy; the caller owns grants,
which place is open and whether its run may change it.

A session offers `call(tool, argumentsJson)`, `execute(datamodel, code)` for `Edit`, `Server` or
`Client`, `play(start)`, `capture({ argumentsJson?, directory?, stem? })`, `report(datamodel, code,
runId)` for the ordinary run-bound report channel, and `close()`. Each response has `ok`, `delivery`,
`refused`, `expired`, `detail`, `result` and `text`. `delivery` is `unsent` (nothing left; safe to
retry), `possibly_sent` (the call may have taken effect: no answer, lost connection or deadline) or
`answered`. Verify never retries a call; a caller must not blindly repeat a possibly sent mutation.

`callSeconds` (default 60) bounds each call and `runSeconds` (default 300) the whole session. At a
deadline the call is abandoned, the transport is closed and the response is `possibly_sent`; later
calls in an expired run are refused unsent. `close()` gets its own `cleanupSeconds` (default 30), sends the
play toggle that returns the Studio to its declared prior `mode` (`edit` by default; `play` if the
Studio was already playing) when the session changed it or lost track of it, closes the transport and
returns `{ acknowledged, restored, mode, detail? }`. It never closes or kills Studio and sends only
that toggle; an unacknowledged cleanup (for example the consumer refused the stop) is reported, not
hidden. Verify cannot query the Studio's mode, so the declared `mode` is trusted.

`transport` replaces the MCP process with `{ call(tool, argumentsJson, deadline) -> exchange, close() }`,
where an exchange is `answered`, `unsent` or `unanswered`. `close` must abort an in-flight call and a
later `call` must work again. Tests use a fake transport; the default starts the Studio MCP executable
and reconnects after a deadline.

`Lute.studio.run`, `Lute.studio.host` and `Lute.platform.run({ host = "studio", attach = ... })` accept
`attach` and run the same engine code and report path as a launched run: play starts, the code runs in
`context`, the report is validated against the run id, an optional final capture is saved, then
cleanup runs. Faults, timeouts and unacknowledged cleanup are never a pass. The open place must already
contain what the code requires, such as the mounted entry; nothing is built, copied or installed.
Attached runs do not support `players`. They share the developer's Studio with no isolation, so the
work can see and alter the open place's state; use a launched run for isolation.

## Open Cloud execution

`Lute.openCloud.connect({ universeId, placeId, versionId, request, authorize, requestSeconds?,
pollSeconds?, pollIntervalSeconds?, logPages?, logBytes?, now?, sleep? })` runs the ordinary entry as a
Luau execution task on an exact published place version, with no local Studio or Player. It is a
first-class host beside simulator, Studio and Player: `Lute.platform.run({ host = "open-cloud", cloud = ... })`
and `tools/run.luau --host open-cloud` use the same entry, case IDs, selection, lifecycle and
`Core.Report`. `Lute.openCloud.host({ connection, codeForBatch, runId?, capabilities?, onOutcome? })` is the
`Core.Host` for `Core.execute`.

Verify holds no credentials and reads no environment or files for this host. The caller supplies
`request(call, deadline) -> exchange` and `authorize(call) -> { ok, reason? }`. `call` is
`{ purpose = "submit" | "poll" | "logs", method, url, body?, digest, universeId, placeId, versionId, taskPath? }`;
the request function adds authentication and performs the HTTP call; an exchange is `answered`
(`httpStatus`, `body`), `unsent` or `unanswered`. `authorize` sees every call before it is sent.
`deadline` is an absolute time on the host clock; Verify also abandons a call that exceeds
`requestSeconds` (default 30). Caller code that outlives an abandoned call is the caller's to stop.

`session.run({ code, runId, requires? })` submits once and polls to a terminal state until `pollSeconds`
(default 330). The code receives `runId`, runs the case lifecycle in the task and returns
`HttpService:JSONEncode(Roblox.reportChannel.envelope(runId, report))`. The outcome is
`{ status, passed, delivery, state?, handle?, report?, detail?, logs, diagnostics, timing, runId }`.

- `passed` is true only for a `COMPLETE` task whose single run-bound report has every case passed.
  `COMPLETE` alone is not a pass; assertion failures return `status = "returned"` with failed cases.
  `FAILED`, `CANCELLED`, a missing, malformed, duplicated or other-run report fault.
- `delivery` is `unsent`, `possibly_sent` or `answered`, as in [Attached Studio](#attached-studio).
  401, 403, 429 and other client errors, an unsent exchange and a refusing `authorize` are `unsent`.
  A 5xx, 408, an unanswered or malformed 2xx reply and a submit deadline are `possibly_sent`.
  Verify never retries a submit, and the host refuses to resubmit a batch whose earlier submit is unknown.
- A local poll deadline is `timed_out` and does not cancel anything: the task may still run or complete.
  The outcome keeps `handle = { path, runId, universeId, placeId, versionId }`.
  `session.reconcile(handle)` polls that task again without submitting; the host does this
  automatically when a batch it timed out is run again.
- The task path must match the requested universe, place and version exactly. Another path is a fault.
- Task logs are fetched (bounded by `logPages`, `logBytes`) after a terminal state into `logs`;
  fetch problems and transient poll failures are listed in `diagnostics`. `timing` carries measured
  `submitSeconds`, `pollSeconds`, `totalSeconds` and `polls`; the `tools/run.luau` output prints them.

The host declares `open-cloud-server`. It has no physics simulation, no auto-started place scripts,
no joined clients and no input, replication, rendering, audio, capture or judgment. A unit requiring
`native-physics`, `native-multiplayer`, `native-input`, `native-replication`, `native-rendering`,
`native-audio`, `place-scripts`, `joined-clients`, `capture`, `judgment` or `action:input.*` is refused
before anything is sent; declaring one in `capabilities` raises. Operation capabilities for a server
instance host are the caller's to declare.

This proves that the named published version executed that code in a Roblox server task and reported
these results under this run id. It does not prove client, input, replication, rendering, audio or
physics behavior, player-visible quality, that the place version is the one intended for release, or
authenticity (the run id is correlation). The place must already contain the mounted framework and
entry. Caller-facing service limits: a task is capped at five minutes, and a place may have at most ten
incomplete tasks; exceed either and the service rejects or ends the task. Verify enforces neither and does not
cancel tasks. Measured queue and run overhead: not yet measured; run
`examples/open-cloud-transport.luau` live and record the printed `timing` here.

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
