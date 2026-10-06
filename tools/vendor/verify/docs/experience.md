# Experience verification

Use the same authored case and ordinary Verify harness to check application logic, simulated actors
and native Roblox observations. The caller supplies operations, evidence collectors, reviewers,
capabilities and acceptance criteria.

## Cases and evidence

`Verify.experience.register(harness, case, host, evidence)` adds an experience case beside ordinary
cases. Run that harness once with the host's capabilities and environment. `run(case, host)` is the
standalone convenience. Both use the existing harness/report model. `Result` holds `{ report,
evidence }` in memory; evidence is keyed by case id. The caller owns persistence and transport.

A case declares `id`, `name`, `requires`, positive `timeoutSeconds` and `run(context)`. Declare each
required `action:<name>`, `query:<name>`, `capture` and `judgment` capability. Missing declared
capabilities produce an unsupported case without executing it. An unavailable operation discovered
inside a step fails that step.

The context offers `action`, `query`, `checkpoint`, `judge`, `measure` and ordinary `check` assertions.
Operations name their actor. Payloads and returned observations are finite portable values,
snapshotted against later mutation. A checkpoint attaches nonempty artifact references to the case.
Judgment requires that actor's captured checkpoint and a caller-supplied reviewer with a verdict and
reasoning. Capture alone grants no quality verdict; no default judge exists. Entered cases defer host
cleanup through the harness and retain its failures. The caller releases setup skipped by preflight.

Deadlines use the host's monotonic clock and are checked before and after operations. They are
cooperative: they detect late completion but cannot interrupt a hung callback or native remote call.
`parity(left, right)` returns `{ status, differences }` and compares case verdicts and recorded
action/query observations. Passing requires both runs to pass and their observations to agree.
Checkpoint media, judgments and performance measurements remain separate acceptance obligations;
this comparison grants no native event-ordering, physics, rendering or audio parity.

Start with the [in-memory example](../examples/experience.luau). Behavioral evidence lives in
[experience tests](../tests/experience.spec.luau).

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
