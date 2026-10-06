# Experience verification

Use the same authored case and ordinary Verify harness to check application logic, simulated actors
and native Roblox observations. The caller supplies operations, evidence collectors, reviewers,
capabilities and acceptance criteria.

## One case model

Author every tier with `harness:case(name, options)` and the ordinary `Core.Context`. BDD and sessions
use that same context. `Core.runCase(namedCase, host)` is a one-case convenience over the harness; it
returns the ordinary `Report`. There is no separate experience case, context, runner or evidence map.
Use direct assertions for local functions and typed operations for host interactions in the same case.

`Core.operation({kind, name, input, output})` declares an action or query with input and output decoders.
`context:perform(actor, operation, input)` preserves the declared Luau input/result types. Decoders also
validate both sides of the wire boundary. `Core.bindOperation(operation, handler)` binds a typed handler
to a host endpoint. Actions and queries use finite plain values; unsupported engine values need an
explicit codec. A query must only read. `context:await(actor, query, input, predicate, pollSeconds)` polls
it using the host clock and sleep within the case deadline; it refuses actions.

A host binds through `harness:run({executor, capabilities, environment, bind, cancelled?})`. `bind(context)`
runs in setup only for selected, supported cases. Create a fresh host per case. Register partial resource
cleanup with `context:defer` before a fallible acquisition or readiness operation. The harness owns the
returned host's `close`, then suite setup, body, teardown and cleanup run through one failure classifier.
Sessions, BDD surfaces, injected execution hosts and Lute worker options accept the same `bind` and `cancelled` options. Use the same monotonic clock for the harness and
host. Declare required operation capabilities as `action:<name>` or `query:<name>` and declare `capture`
and `judgment` when needed. Missing preflight capabilities are unsupported; an undeclared unavailable
operation encountered during execution fails.

Case options include `timeoutSeconds` and `cleanupTimeoutSeconds`. A deadline covers setup and body.
Each teardown/cleanup callback gets a separate cleanup budget (default five seconds), including recovery
operations after a failed or cancelled body. Timeout and cancellation keep their own report statuses.
Checks are cooperative: a blocking call must enforce its supplied deadline or the outer worker must
interrupt it. Cleanup is attempted even after failure; its failures remain visible independently.

`context:checkpoint(actor, name)`, `judge(actor, checkpoint, criterion)` and `measure(actor, name, input,
limits)` attach observations to `CaseResult.evidence`, bound to recorded step indices. Evidence survives
standard report decoding, merging and transport. Judgment needs that actor's captured checkpoint and an
explicit reviewer verdict with reasoning. Capturing media alone establishes no quality judgment.
Unreviewed judgments and insufficient measurements are unsupported; observed defects fail.
`context:unsupported(requirement)` records a missing runtime capability and still runs cleanup.
Measurements retain their inputs and limits; report decoding recomputes and checks their evaluation.

`Core.observationParity(leftReport, rightReport)` compares case verdicts and action/query inputs and
observations. Both reports must pass. It does not certify native physics, replication timing, visual
quality, sound or performance. Those require their own observations and assertions.

Start with [typed local operations](../examples/experience.luau), the
[shared instance case](../examples/instance-case.luau) and
[failure/cleanup tests](../tests/semantic-execution.spec.luau).

## Reusable instance adapter

`Roblox.instanceHost` owns instance-operation binding and fixture cleanup. Its `create`, `parent`,
`destroy`, `setProperty`, `setAttribute` and `inspect` operations use stable caller-selected instance ids.
`property(decoder)` and `attribute(decoder)` provide typed reads. The exact same case runs with
`instanceHost.simulated(actor).host` or `instanceHost.native(actor).host`. Native execution requires an
already running authorized Studio or Player context. The [native launcher](execution.md#native-studio-execution)
provides isolated Studio startup and report retrieval.

`simulated(actor, environment?)` accepts a configured `Roblox.testEnvironment()`. Reuse its class,
default/validation, explicit fake, virtual time and hierarchy behavior instead of building a second
engine. `Roblox.reflection.create` supplies class definitions and defaults from an injected database; no reflection database or
unimplemented UI/physics behavior is implied. Supply explicit fakes for unsupported methods.

`registry({actor, createInstance, borrowed?, codec?})` exposes the same endpoints for a custom native or
simulated host, including `experienceHost` remote routing. `native(actor, borrowed?, codec?)` provides the
native factory and clock. A codec translates nonportable property/attribute values; default transport
accepts only finite plain values. Borrowed instances are not destroyed. Borrowed descendants moved under
owned fixtures are restored to their original parent before cleanup; failed restoration prevents their
owner from being destroyed. Other changes to borrowed instances need explicit caller cleanup. Owned
fixtures are released on success and failure. Unknown ids, wrong actors and invalid values fail.

## Native Roblox hosts

`Roblox.experienceHost.nativeEngine()` requires a running Roblox simulation and reads Studio/Player,
server/client, place and engine identity.
`create(options)` binds that engine, a local actor, actor contexts, operation registry and optional
transport, capture and judge. Injected engine records remain fixture evidence. Registered operations
and supplied collectors/reviewers advertise their capabilities automatically; declare extra capabilities
in `options.capabilities`. `endpoint(decode, body, requires?)` validates payloads before the handler.
Local registry operations and remote responses retain actor and operation bindings.

`remoteTransport(context, remote, actors, playerFor?)` wraps a caller-supplied RemoteFunction. Server
routing requires a player resolver. Bind native callbacks with `remoteResponder(registry,
capabilities, now, actor, authorize)`, whose required authorization callback checks the caller before
dispatch. Opt in to these test endpoints in an authorized development or staging session. The caller
owns endpoint installation, actor membership, authorization policy and cleanup. Capability names
and response correlation do not authenticate a remote caller. Wire requests carry `remainingSeconds`;
the receiving actor applies that budget to its own clock. The originating deadline still bounds
returned completion cooperatively.

The [native visibility example](../examples/roblox-experience.luau) binds an injected target and optional
collectors. The [hierarchy conformance example](../examples/hierarchy-experience.luau) accepts either
a native Folder factory or the simulated environment and checks the same authored observations.

## Player actions

`Roblox.playerHost` declares typed `move`, `jump`, `equip` and `inspect` operations. `native(actor)`
binds the live local player's Humanoid, backpack and character. `move` accepts a unit direction,
`equip` requires one uniquely named backpack Tool, and `inspect` returns position, velocity, health
and equipped tool. Cleanup stops movement. These are semantic character controls, not proof of keyboard,
touch, gamepad or UI input behavior. Those need input-specific host operations and tests.

`registry(backend)` binds the same vocabulary to injected functions for deterministic tests. Such a
fixture does not advertise native physics. The [player example](../examples/player-case.luau) requires
`native-physics` and observes an actual jump and landing; it is unsupported on a simulation-only host.

## Simulated networking

`Roblox.network.create({ clients, latency?, environment? })` gives each declared client and the
server a separate simulated environment. `send` queues cloned plain-data messages;
`onMessage` receives them. `advance(seconds)` delivers the ready snapshot in due-time/sequence order.
Messages sent during delivery wait for another advance. Payloads refuse nonfinite numbers, cycles,
metatables, sparse arrays and mixed array/dictionary keys. Outcomes name refusals explicitly.

The network clock advances independently of each environment's scheduler. `disconnect(client)`
drops queued messages in both directions and disconnects its receiving handlers. This tests authored
message handling and isolation; it supplies no native replication, physics or rendering parity.
See [network tests](../tests/network.spec.luau).

## Performance observations

`Verify.performance.summarize({ samples, unit, context, threshold? })` validates finite nonnegative
dense samples, retains environment/signal and `observed` or `simulated` timing labels, and computes
count, mean, extrema and nearest-rank p50/p95/p99 in the supplied unit. Empty observations retain
absent metrics. An optional threshold counts samples strictly above it.

`evaluate(summary, limits)` requires matching units, a positive `minimumSamples` and explicit caller
limits. Ratio limits also require the matching threshold. Exceeded limits fail; missing,
insufficient, simulated or mismatched evidence is unsupported. No game budget or environment
attribution is built in. Caller labels do not authenticate timing: real frame-performance claims
need samples from the actual consumer surface. [Performance tests](../tests/performance.spec.luau)
prove calculations and refusals. `context.measure(actor, name, input, limits)` records the evaluation
in the case evidence and requires a passed result through the shared harness.


`Roblox.performance.collect({ connect, environment, signal, maximumSamples })` bounds collection from
an injected interval signal. Supply the current `environmentLabel` and caller-owned `sampleLimit`:

```luau
local collector = Roblox.performance.collect {
    environment = environmentLabel,
    signal = "RenderStepped",
    maximumSamples = sampleLimit,
    connect = function(sample)
        local connection = game:GetService("RunService").RenderStepped:Connect(sample)
        return function() connection:Disconnect() end
    end,
}
```

Exercise the consumer, then call `collector.finish()` during cleanup. It disconnects once and returns
cloned `Performance.Input` samples in `ms`, labeled `observed`; invalid intervals refuse after
cleanup. The cap stops retaining new samples, while `finish` releases the connection. The caller must
connect the actual signal and bind its run/source identity. Injected callback tests establish fixture
coverage, not an observed native frame-performance result.

## Coordinated native clients

`Roblox.multiplayer.server(context, options)` binds a server and one to eight clients to one ordinary
case. Options supply the `RemoteEvent`, unique `runId`, client count, authorization callback, server
registry, native engine, sleep and readiness deadline. `armed` may announce that the server listener
is connected. Clients wait for that announcement, then call `multiplayer.client` with the same remote
and run ID, their registry, capabilities, clock and spawn function. Optional `capture` and `close`
callbacks collect client evidence and release client resources.

The server assigns `client-1` through `client-N` in join order. These are run-local identities, not
account IDs. Cases use `context:perform`, `await` and `checkpoint` against those actors or `server`.
The coordinator checks actual sender identity, run and request identity, deadlines and disconnects.
Cleanup waits for connected clients to acknowledge release; missing or failed cleanup fails the case.
The [runnable example](../examples/multiplayer.luau) clicks UI in one client and observes the server
and second client's replicated counter. Its native client images are temporary, explicitly limited
evidence. Use a durable capture callback for retained per-client images.

`Roblox.inputHost` declares `key`, `pointer` and `text` operations. `native()` uses
`UserInputService:CreateVirtualInput()` and returns nil when unavailable. Register only the available
capabilities; unavailable input is not a pass. `registry(backend)` binds the operations, and
`backend.close()` releases held keys and mouse buttons. `screenCenter(guiObject)` converts rendered GUI
bounds to screen coordinates including the top-bar inset. Pointer coordinates are screen pixels.
Roblox still rejects reserved keys and interactions with protected CoreGui. This is real virtual
input, distinct from the character motion operations in `playerHost`.

## Benchmarks

`Benchmark.case(spec)` (`src/benchmark.luau`, host-side) is an ordinary case; `Benchmark.run(spec)` returns the raw result. A spec supplies
`name`, `unit` (`seconds`, `milliseconds`, `microseconds`), `workload`, `warmup`, `samples`, `iterations?`, `budget?`
(`p50`, `p95`, `p99`, `maximum`; none means the case passes as measured only, with that limitation and evaluation reason `measured`, and acceptance policy decides), `environment = { observed, accepted? }` and optionally `maxSpread`, `yardstick`,
`baseline` (a `value` or recorded `samples`, and optionally the `yardstick` it was recorded with, which normalizes the comparison across machines) with `acceptedBaselines`, `judge` (a callback over the raw samples and summary returning a refusal message), `setup`/`teardown` (once, untimed), `beforeSample`/`afterSample` (every sample, untimed), `heap` (`{ probe, unit, maximumGrowth? }`), `deadlineSeconds` and an injectable `clock` (default `os.clock`; a gate supplies its own).
The consumer owns identities, budgets and units; no machine is a universal baseline.

`Benchmark.collection({ name, yardstick, benchmarks })` is one case whose members share a yardstick measured before and after the whole collection (`Benchmark.collect` returns the raw result). After the second reading each member's baseline comparison (including `baseline.yardstick` normalization) and `judge` run with the collection's before and after yardstick samples; the judge view carries them raw (`yardstickBefore`, `yardstickAfter`) and summarized (`yardstickBeforeSummary`, `yardstickAfterSummary`) so a caller can apply its own normalization and rules. A drifting yardstick marks the members unsupported and skips their judges. Warmup runs are untimed. Exactly `samples` timed samples follow, each `iterations` runs averaged. The run is never retried.
All raw samples are kept in the case's measurement evidence. Within budget passes; over budget or a baseline
regression beyond `tolerance` fails. Anything that makes the numbers untrustworthy is reported as missing
`measurement:<reason>` (unsupported unless the budget also failed): `environment_mismatch`, `baseline_mismatch`
(identity, environment or unit), `unstable` (`(p95 - p50) / p50 > maxSpread`), `yardstick_unstable`,
`yardstick_drift` (a fixed CPU workload sampled before and after moves more than `maxDrift`), `heap_unsupported` (the probe returned no reading), `deadline_exceeded`.
Environment or baseline mismatch skips the workload. A raising workload or invalid clock fails.

`Benchmark.luauHeap` reads `collectgarbage('count')` where the runtime exposes it (Lune); Lute 1.0 does not, so it reports `heap_unsupported`. It never forces a collection. A summary also carries `total` and `deviation`.
