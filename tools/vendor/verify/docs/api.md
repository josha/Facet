# API reference

Verify gives each case an isolated lifecycle and records what happened in a report. Start with
cases and assertions; use sessions, execution plans and host adapters when you need to coordinate
multiple sources or collect observations elsewhere.

| I want to… | Start here |
| --- | --- |
| Write and run a case | [Cases and sessions](#cases-and-sessions) |
| Compare values or record calls | [Assertions and spies](#assertions-and-spies) |
| Read, validate or combine results | [Reports and transport](#reports-and-transport) |
| Schedule work across executors | [Execution plans](#execution-plans) |
| Judge observations collected by a host | [Remote observations](#remote-observations) |
| Capture a scenario, window or place fixture | [Host adapters](#host-adapters) |
| Prove evidence is current, intact, reviewed and covers what you require | [Evidence provenance](#evidence-provenance) |
| Test engine-facing logic without Roblox | [Simulated environment](#simulated-environment) |

Examples use these package names. Replace the paths with your mounted package locations:

```luau
local Core = require(path.to.verify.core)
local Bdd = require(path.to.verify.bdd)
```

Optional packages are [`Lute`](../src/lute/init.luau), [`Roblox`](../src/roblox/init.luau),
[`Gate`](../src/gate/init.luau) and [`Evidence`](../src/evidence/init.luau) (host-side; places mount only core),
[`Host`](../src/host/init.luau) and [`Consumer`](../src/consumer/init.luau).
The entry points export their public functions and types. See the
[working example](../examples/basic.luau) for a directly executable case and report.
The [verification laws](laws.md) define lifecycle and evidence boundaries.

---

## Cases and sessions

### `Core.createHarness`

`createHarness({ now, source?, prefixIds? }) -> Harness`

`Core.createHarness` creates an isolated registry. Register cases. Call `harness:run` to receive their results.
Importing Verify does not create a shared registry.

`harness:run` returns failed and unsupported results in its report; it does not set the process exit code.
The caller must judge the report and make its command fail when the required claim is unmet.
See the [repository runner](../tools/test.luau) for a nonempty, all-passing corpus check.

```luau
local tick = 0
local harness = Core.createHarness {
    now = function()
        tick += 0.001
        return tick
    end,
}

harness:suite("inventory", function()
    harness:case("counts the available slots", function(context)
        local slots = { "first", "second", "third" }
        context:expect(slots):toHaveLength(3)
    end)
end)

local report = harness:run {
    executor = "local",
    environment = { revision = "working-tree" },
}

print(Core.format(report))
```

Supply a monotonic `now` function. This example uses a synthetic clock. `source` associates the
registry with its source. `prefixIds` controls source prefixes in case IDs and defaults to true
when a source is supplied. Prefixing requires a source and does not change selection visibility.

### Registration and execution

| Method | Purpose |
| --- | --- |
| `harness:suite(name, register)` | Group the cases registered by a callback. |
| `harness:case(name, run)` | Register a callback receiving a case context. |
| `harness:case(name, options)` | Supply `run` plus optional `id`, `requires`, `tags`, `limitations`, `timeoutSeconds` and `cleanupTimeoutSeconds`. |
| `harness:skip(name, reason, run?)` | Register a deliberate omission with its reason. |
| `harness:beforeEach(run)` | Register setup for cases in the current suite. |
| `harness:afterEach(run)` | Register teardown for cases in the current suite. |
| `harness:run(options)` | Execute selected cases and return a report. |

Run options name the `executor` and may supply `environment`, `capabilities`, `selection` and
`invoke`, `bind` and `cancelled`. Selection supports IDs, suite prefixes, tags, capabilities and a predicate.
A focused result records that execution; it does not establish a complete gate.

```luau
harness:case("adds two values", {
    requires = { "arithmetic" },
    tags = { "calculation" },
    limitations = { "fixed inputs" },
    run = function(context)
        context:expect(2 + 2):toBe(4)
    end,
})
```

A required capability absent from the run produces `unsupported`, not a pass. A deliberate skip
produces `skipped`. The optional invoker owns actual interruption: it must stop work before
reporting cancellation or timeout. See [execution](execution.md) for host deadlines and policy.

### Case context

The context records assertions, steps and artifact references, and owns case-local cleanup.

| Method | Purpose |
| --- | --- |
| `context:expect(value)` | Create an assertion. |
| `context:step(name, run)` | Record a named step and its outcome. |
| `context:step(name, { run, actor? })` | Associate a step with an actor. |
| `context:artifact(name, reference, mediaType?)` | Attach a reference to evidence. |
| `context:defer(cleanup)` | Register cleanup for the end of the case. |
| `context:own(resource)` | Own a cleanup function or a table with `dispose`/`destroy`. |
| `context:skip(reason)` | Stop the current case with a deliberate skip. |
| `context:perform(actor, operation, input)` | Execute a typed action or query. |
| `context:await(actor, query, input, predicate, pollSeconds)` | Poll a read-only query within the case deadline. |
| `context:checkpoint(actor, name)` | Capture evidence through the bound host. |
| `context:judge(actor, checkpoint, criterion)` | Require an explicit review of captured evidence. |
| `context:measure(actor, name, input, limits)` | Check observed performance against explicit limits. |
| `context:remainingSeconds()` | Read the current body or cleanup budget. |

The [cross-host execution contract](experience.md#one-case-model) owns typed operations, host binding,
deadlines and evidence. `Core.runCase({name, ...caseOptions}, host)` runs one ordinary case and returns
the standard report. Use `Core.observationParity` to compare its action/query observations across hosts.

Declare a disposal callback’s receiver as the complete resource type, including its `dispose` or
`destroy` member. `LifecycleOps<H>` and `ActorOps<H>` preserve the acquired handle type in release
callbacks.

Cleanup runs once, newest first. Setup, case, teardown and cleanup failures remain independently
visible; a later failure does not erase an earlier one. Hooks and cleanup use the same invocation
contract as the case. Artifact references record locations; they do not save or authenticate bytes.

### `Bdd.create`

`create(harness) -> Bdd`

`Bdd.create` provides registration verbs over the same harness and report model.

```luau
local test = Bdd.create(harness)

test.describe("selection", function()
    test.it("starts empty", function(own, context)
        local selection = {}
        own(function()
            table.clear(selection)
        end)
        context:expect(selection):toHaveLength(0)
    end)
end)
```

The surface contains `describe`, `it`, `itSkip`, `beforeEach`, `afterEach`, `expect`, `spy` and
`skip`. Case and hook bodies receive `(own, context)`; `own` registers a cleanup function.
Use `itSkip(name, reason, body?)` during registration and `skip(reason)` during a case or hook.
`it(name, { run, id?, requires?, tags?, limitations? })` passes the same case metadata as
`harness:case`: `id` fixes the case identity, `requires` names capabilities (a missing one is
`unsupported`), `tags` select, and `limitations` appear in the report.

`Bdd.surface({executor, environment, capabilities, ambientSource, now?})` returns one session-backed
surface: the verbs above plus `load(source, register)` (opens the source, registers, and adopts a
registration error as a failed source report), `adoptReport`, `sourceReport`, `run`, `reset` and
`useHarness`. `Bdd.formatResults(report, title?)`, `Bdd.formatFailures` and `Bdd.counts` print a report.
A unit, engine-integration and end-to-end case use this one vocabulary; they differ in the
capabilities they require and the evidence they attach, not in the runner.

### `Core.createSession`

`createSession(options) -> Session`

`Core.createSession` preserves the factory’s surface type in `verbs` and `current()`. It owns one registry per source. Use it when modules register their cases as they load. Options
require `executor` and `environment`; optional fields include `capabilities`, `now`, `surface`,
`runtimeVerbs`, `prefixCaseIds` and `selection`. With solver v2, declare factory options as
`Core.SessionProvidedOptions<YourSurface>` before calling the overloaded constructor.

```luau
local session = Core.createSession {
    executor = "local",
    environment = { revision = "working-tree" },
}

session:open("specs/inventory")
session:harness():case("starts empty", function(context)
    context:expect({}):toHaveLength(0)
end)
session:close()

local report = session:run()
```

| Method or field | Purpose |
| --- | --- |
| `open(source)` / `close()` | Enter and leave a source's registration scope. |
| `harness()` / `current()` | Access the active source's harness or supplied surface. |
| `verbs` | Route calls through the active source's surface. |
| `adoptReport(source, report)` | Include an existing source report. |
| `sourceReport(id, source, status, detail)` | Construct a source-level failed or skipped report. |
| `setSelection(selection?)` | Set which cases to run. |
| `run()` / `reset()` | Execute queued sources or reset session state. |

Call session methods with `:`. A `surface` factory maps registration verbs to each harness;
`runtimeVerbs` routes verbs such as `skip` while cases run. Mid-run reset and reentry fail without
losing queued sources. [Worker examples](execution.md#lute-workers) show module-loading integration.

---

## Assertions and spies

### `Core.expect`

`expect(value) -> Expectation`

Available directly, through a case context, or through the BDD surface. Chain `.never` before a
matcher to negate it.

```luau
Core.expect(4):toBe(4)
Core.expect({ count = 2 }):toEqual({ count = 2 })
Core.expect("ready").never:toBe("waiting")
Core.expect(function()
    error("missing entry", 0)
end):toThrow("missing entry")
```

| Matchers | Compare |
| --- | --- |
| `toBe`, `toEqual` | Equality and deep equality. |
| `toBeNil`, `toBeOk` | Nil and non-nil checks; `false` is non-nil. |
| `toBeTruthy`, `toBeFalsy` | Truthiness checks. |
| `toBeTrueWith(detail)` | A true value, with a supplied failure detail. |
| `toBeCloseTo`, `toBeNear`, `toBeFloat32` | Numeric tolerance or single-precision representation. |
| `toBeLessThan`, `toBeGreaterThan`, `toBeLessThanOrEqual`, `toBeGreaterThanOrEqual` | Numeric ordering. |
| `toContain`, `toContainExactly`, `toHaveLength` | Containment and length. |
| `toThrow(contains?)`, `toThrowMatching(pattern)` | A thrown error, with optional plain text or a Luau pattern. |

`toThrow` uses plain text containment; use `toThrowMatching` for patterns. `Core.float32(value)`
returns the single-precision value. Exact matcher signatures are in
[`matchers.luau`](../src/core/matchers.luau).

### `Core.spy`

`spy(implementation?) -> Spy`

`Core.spy` records calls to its `fn` and optionally delegates to your implementation.

```luau
local callback = Core.spy(function(value)
    return value * 2
end)

Core.expect(callback.fn(3)):toBe(6)
Core.expect(callback.callCount()):toBe(1)
Core.expect(callback.lastArgs()):toEqual({ 3 })
```

Inspect `calls`, `called()`, `lastArgs()` and `lastReturn()`. Use `reset()` to clear recorded calls,
`returnValue(value)` to supply a fixed return, or `implementation(fn)` to replace the callback.

---

## Reports and transport

A schema-v1 report retains executor, environment, capabilities, sources and case results. Each
case retains status, timing, failures, steps, artifacts, limitations and origin. Counts must agree
with the result rows.

| Status | Meaning |
| --- | --- |
| `passed` | The executed case passed. |
| `failed` | An assertion, lifecycle phase or execution failure was recorded. |
| `skipped` | The case was deliberately omitted with a reason. |
| `unsupported` | A required capability was unavailable. |
| `timed_out` | The invoker reported that timed-out work was stopped. |
| `cancelled` | The invoker reported that cancelled work was stopped. |

### Validate and combine

| API | Use it to… |
| --- | --- |
| `Core.decode(value)` | Validate a foreign report and its schema. |
| `Core.merge(reports, executor, environment)` | Combine trusted reports. |
| `Core.compose(payloads, executor, environment)` | Account for every expected shard, including missing, malformed or duplicate outcomes. |
| `Core.syntheticReport(options)` | Record work a host could not reach. |
| `Core.format(report)` | Produce readable output. |
| `Core.canonical(value)` | Produce a deterministic representation. |
| `Core.verdictDigest(report)` / `Core.verdictDifferences(left, right)` | Compare verdicts without treating timings as deterministic. |

```luau
local combined = Core.compose({
    { id = "worker-1", report = report },
    { id = "worker-2", error = "worker exited before returning a report" },
}, "local-workers", { revision = "working-tree" })

print(Core.format(combined))
```

Supply every launched shard, including errors. Omitting an unsuccessful worker from the input
cannot establish that all expected work passed.

### Move reports between hosts

| Surface | Transport |
| --- | --- |
| `Core.frame`, `extract`, `reassemble`, `receipt` | Tagged log lines. |
| `Core.segment`, `reassembleSegments` | Bounded payload arrays. |
| `Lute.encode`, `decode` | JSON values. |
| `Lute.segmentReport`, `reassembleReport` | Reports carried in bounded segments. |

Missing, conflicting or mixed chunks fail. **JSON decoding is not report validation.** Validate
received reports with `Core.decode`; consumers bind executor identity and own authenticity.

## Execution plans

A plan names a finite set of work and its requirements. The consumer supplies discovery,
locator meaning and an authorized host.

| API | Responsibility |
| --- | --- |
| `Core.validateManifest`, `planFromManifest` | Validate a manifest, then derive a plan from it. |
| `Core.validatePlan`, `selectPlan`, `partitionPlan` | Normalize, select and deterministically divide planned work. |
| `Core.planDigest`, `caseId` | Bind plan meaning and compose case identities. |
| `Core.negotiate`, `explainCapabilities` | Determine and explain capability support. |
| `Core.execute(plan, host, options?)` | Execute batches with lifecycle and failure accounting. |

| `Gate.define`, `run`, `format`, `shard`, `testCases` (package `src/gate`); `Lute.gate` and `Lune.gate` (`run`, `writeReport`) | Declare producers and execute them as one accounted plan with an acceptance verdict. See [declarative gates](execution.md#declarative-gates). |
| `Benchmark.case`, `run` (`src/benchmark.luau`) | Warmup, sampling, baseline and stability checks reported as an ordinary case. See [benchmarks](experience.md#benchmarks). |

See [the execution contract](execution.md) for fixtures, deadlines, retries and Lute workers. [`Host.fake`](../src/host/init.luau) injects missing, duplicate, reordered, failed and
cancelled deliveries without external effects.

---

## Host observations

Use typed operations, `context:perform`, `await`, `checkpoint`, `judge` and `measure` in the ordinary
case. Evidence lives in `CaseResult.evidence` and uses standard report transport. See the
[experience contract](experience.md) for binding and the [execution contract](execution.md) for hosts.

## Host adapters

Adapters use injected host operations. Consumers own authorization, actual destinations,
artifact custody and release acceptance. Load only the package needed for the observation.

### Scenarios and journeys

`Roblox.checkpointPlan.order(checkpoints, viewports, rows, collectAll)` orders a declared matrix
with checkpoint first and viewport second. It refuses missing and duplicate checkpoint rows;
non-checkpoint rows remain available for caller-owned capture policy. `Roblox.scenarioStepJournal.create`
retains numbered tool outputs and their request/result digests through injected storage and digest
operations. A binding is copied into call records; the caller owns authorization, tool execution,
paths, and the meaning of each checkpoint.

### Windows, captures and receipts

`Roblox.witnessHost` provides window parsing and selection, viewport capture, checkpoint frames,
and `recordReceipt` / `decodeReceipt` / `checkReceipt`. These functions are also exported at the
Roblox package root.

Captures use injected operations and current window/scale facts. Receipts bind contract, target,
source, console hash, image hash and byte count. Source changes must pass injected ancestry/path
policy; a missing image or red console holds. Duplicate labels cannot overwrite a checkpoint.

`Core.classifyConsoleText`, `classifyConsole` and `splitConsoleLines` preserve narrow caller
exclusions, blocks and line ordering. `Lute.detectViewportCorners` uses the adjacent Swift helper
as an explicitly supplied native inspection capability. It rejects absent or ambiguous marker
rectangles; a missing capability is unsupported. Consumers still own run freshness, image custody
and final clean-image coverage.

### Attached Studio

`Lute.studio.attach({ authorize, studioId?, match?, transport?, ... })` returns `session, refusal` for an
already open Studio chosen through the official Studio MCP. `authorize(request)` sees each request's
exact bytes and digest before it is sent. The session provides `execute`, `play`, `capture`, `report`,
`call` and `close`; responses distinguish `unsent`, `possibly_sent` and `answered`, deadlines are
enforced and `close` restores the declared prior mode without closing Studio. `attach` is also an option of
`Lute.studio.run`, `Lute.studio.host` and `Lute.platform.run`. The caller owns policy. See
[Attached Studio](execution.md#attached-studio).

### Open Cloud

`Lute.openCloud.connect(options)` returns `{ run({ code, runId, requires? }), reconcile(handle) }`;
`Lute.openCloud.host({ connection, codeForBatch, ... })` returns a `Core.Host`; `Lute.platform.run` and
`tools/run.luau` accept `host = "open-cloud"` with `cloud` options. The caller supplies `request` and
`authorize`; outcomes report `passed`, `delivery`, task state, `handle`, logs and `timing`. A complete task
is not a pass without a run-bound all-passed report; a local timeout never cancels. `submit`, `poll`, `logs` and
`binding = "caller"` (script bytes unchanged, raw `results` and `task`, no report claim) serve callers that bind runs
themselves. See
[Open Cloud execution](execution.md#open-cloud-execution).

### Evidence provenance

Evidence rides on the report. An `Artifact` may carry `sha256`, `size` and a typed `provenance`: run, case,
actor, checkpoint, build (`commit`, `tree`, `clean`, `digest`), executing host and capabilities (from the case
origin), caller-declared `device` class and `capturedAt`. A `Review` may carry `kind` (`visual` or `audio`) and
`judged`, the content hashes the reviewer saw. The report decoder keeps both; no second receipt exists.

- `Evidence.seal(report, { runId, build, device, now, hash, read, sink })` reads each artifact, stores its
  bytes in `sink` and returns `{ report, issues }`. An unreadable, unstorable or unconfirmed artifact stays
  unsealed and reported. `Lute.evidenceStore.seal` binds the Lute hash, file reader and clock.
- `Evidence.bindReview(report, { caseId, actor, checkpoint, kind, judged })` binds a recorded review to the content
  hashes the reviewer actually judged. Hash what the reviewer saw, not what is stored later.
- `Evidence.validate(report, policy)` returns `{ ok, issues, verified }` and re-hashes every artifact through
  `policy.store`. The policy declares the expected build (`requireClean` refuses dirty builds), `now`,
  `maxAgeSeconds`, `maxSkewSeconds`, optional `runId`, `hosts` and `capabilities`, and `required` coverage:
  `{ caseId, actors, checkpoints, devices, mediaType?, reviews? }` expanded as a cross product. It rejects
  mismatched builds, stale or future captures, missing coverage, a wrong run, host, actor, checkpoint or device,
  duplicate or conflicting observations, missing identity, changed or unavailable artifacts, and missing,
  unbound, failed or wrong-artifact reviews. An empty policy or invalid clock raises instead of passing.
- A sink is `{ put(content, meta) -> reference, get(reference) -> bytes, stat(reference) -> { size } }`, supplied
  by the caller. `Lute.evidenceStore.localDirectory(path)` is the content-addressed reference sink and
  `Core.memorySink(hash)` a portable one. Validation needs only `get`, `stat`, a hasher and a clock, so it runs
  unchanged under Lute and Lune: `lute run examples/evidence-provenance/lute.luau` and
  `lune run examples/evidence-provenance/lune.luau`.

Metadata or a saved screenshot does not establish visual quality, audio quality or physical-device proof. A
review records that a named reviewer judged specific content; `device` is a claim. The class `physical` is
accepted only when `policy.attest.physical(artifact, provenance)` returns true from the caller's own evidence.

### Observation sinks and place fixtures

`Roblox.observationSink` provides escaped/chunked wire data, bounded values, markers, tallies,
reference pooling, owned observation seams, arming and publication into an injected node tree.
It must not replace or destroy host-owned state. In-engine adapters can import this leaf directly.

### Simulated environment

`Roblox.testEnvironment(options?)` is the optional simulated engine for headless tests. It is host-neutral
Luau: it depends on no consumer, reads no generated paths and ships in no game. `options` are `classes`
(`{super?, creatable?, properties = {name = default}, events = {names}, methods = {name = function | true}}`; the
builtins cover `Instance`, `Folder`, `Model`, parts, `GuiObject` (size, position, color, anchor), `Frame`,
`CanvasGroup`, `ScrollingFrame`, `TextLabel`, `TextBox`, buttons, `UIListLayout`, `UIPadding`, `ScreenGui`,
`Humanoid`, `Animation`, `Animator` and `AnimationTrack`),
`builtins = false` to omit `Roblox.BASIC_ENVIRONMENT_CLASSES`, `fakes` and `limits`
(`attributeNameLength`, default 100; `attributeStringLength`, unbounded unless set). The result has `root`,
`createInstance(className, props?)`, `defineClass`, `newSignal`, `heartbeat`, `task`
(`spawn`, `defer`, `delay`, `wait`, `cancel` on virtual time), `scheduler`, `step(seconds)`, `now`,
inspection (`childrenOf`, `parentOf`, `propertyOf`, `attributeOf`, `isAlive`, `liveObjects`,
`liveConnections`), `poke`/`fire` (engine-side change and event), `failNext(operation)`/`clearFailures`,
`errors` (handler errors the engine would only print), `snapshot(object)` (class, name, set properties,
attributes and children as a table, for debugging) and `fake(member, handler)`. `createInstance` takes
children in the array part: `createInstance("Model", {Name = "m", childA, childB, Parent = root})`.
`Roblox.isInstance(value)` and `Roblox.typeName(value)` identify instances and datatypes.

`Environment`, `EnvironmentOptions`, `EnvironmentDefineOptions`, `EnvironmentSnapshot`, `EnvironmentMethod`, `Signal`,
`Connection`, `VirtualScheduler`, `VirtualTask` and `VirtualCallback` are exported types. Instance
properties and per-class methods are dynamic schema boundaries. Their values still require the
consumer's class contract; assigning a method dictionary does not prove its signatures.

`Roblox.datatypes` holds `Vector2`, `Vector3`, `Color3`, `UDim`, `UDim2` and `CFrame` constructors with
value equality, the other constructor shells and a permissive `Enum`, `typeName(value)` and
`readCFrame(cframe) -> (x, y, z, {nine rotation numbers})`. `Animator:LoadAnimation` returns a track whose
`Play`, `Stop` and `AdjustSpeed` change `IsPlaying` and `Speed` and fire `Stopped` and `Ended`; no frames
are blended. The package exports `DatatypeVector2`, `DatatypeVector3`, `DatatypeCFrame`,
`DatatypeColor3`, `DatatypeUDim`, `DatatypeUDim2` and `DatatypeEnum` for supported values. These types
describe the simulated surface, not every native Roblox member.

Instances support `Parent`, `Name`, children events, `Destroy` (locks the parent, destroys descendants,
disconnects the instance's signals), find/ancestor/`GetFullName`, attributes with change signals, and
property change signals that fire only on change. Signals fire in connect order and skip a connection
disconnected during the fire. Reading a name that is not a property, event or method returns the first
child with that `Name`, as the engine does; a property, event or method of that name wins. Any other
unknown read, and every unknown write, raises the engine's "is not a valid member" error. `defineClass`
refuses an existing class, builtin included, unless called as `defineClass(name, spec, {replace = true})`;
the spec replaces the old one for instances created afterwards and is not merged. A method declared as `true` has no behavior: calling it raises
`unsupported_method: Class.Method ...` unless a function is given in `methods`, in `options.fakes` or
through `fake("Class.Method", handler)`. A schema describing an API is never an implementation, and a
test that needs a result supplies it explicitly. `Roblox.virtualScheduler()` is the same scheduler alone.

### Reflection and behavior adapters

The built-in schemas are a small declared test surface, not a complete Roblox reflection database.
Use the [reflection and UI adapters](#reflection-and-explicit-ui-fakes) for standard integration.
Custom environments may supply `defaultProperty(className, property, fallback)` and
`validateProperty(className, property, value, operation)`. A returned `false` is a real default;
return `fallback` for an unmapped property. Validation runs before mutation. `operation` is `set`
for authored assignments or `poke` for simulated engine changes. Explicit fakes do not establish
native rendering or input fidelity.

Hierarchy notifications include `AncestryChanged`, `DescendantRemoving` and subtree `DescendantAdded`.
Moving a subtree notifies the ancestors it leaves or enters; a common ancestor receives neither event.
Removal runs before detachment, root before descendants. An ancestry callback on the moved instance or
its descendants receives the moved instance and its new parent. Same-parent assignments emit no events.
Reparenting the removing instance from its removal callback fails. The simulator dispatches immediately;
a native deferred signal mode can expose different callback timing and observed state. Cross-event
ordering beyond these guarantees is not a contract.

The simulation proves Luau logic over the declared surface, ordering and disposal. It does not prove
rendering, physics, replication, animation, audio, input devices or player capacity; check a supported
semantic against the real engine before relying on it. `placeBoot`, `bootPlace`, `buildPlaceTree`,
`createPlaceCache` and `createPlaceRuntime` build and run injected place fixtures over an engine the
consumer supplies. Their reports test declared boot phases and ownership; they do not simulate all engine
behavior.

### Consumer diagnostics

`Consumer.scan`, `scanTree` and `scanProductionPaths` inspect portable specifications and
production graphs. See [consumer diagnostics](lint.md) for the rules and their limits.

### Reflection and explicit UI fakes

`Roblox.reflection.create { database, typeName, enumType?, classes?, referenceClass?, validateProperty? }`
builds an environment from a Lune-compatible reflection database. Pass
`roblox.getReflectionDatabase()` and the runtime's `typeof`. `enumType(value)` returns the enum family
name, with or without the `Enum.` prefix. The adapter inherits class defaults, rejects unknown and
read-only writes, and validates native datatypes. `referenceClass(className, property)` can narrow
reference properties: Lune's `Ref` metadata does not include the target class. `classes` overlays
explicit events/methods; `validateProperty` adds fixture restrictions. The portable package imports
no Lune runtime. `lune run tools/check-reflection.luau` checks the real integration.

`Roblox.fixtureBridge { database, typeName, enumType?, library?, classes?, referenceClass?, validateProperty?, ui? }`
composes reflection, the simulator's event metadata, UI fakes and the engine seam over one environment.
UI fake classes the database lacks are listed in `unavailable`, not invented; `ui = false` omits them and
`classes` entries replace the defaults. It returns `{ environment, engine, ui, unavailable, faults, hasClass,
observe, record, instanceHost, accounting, close }`. `faults` wraps `failNext` and `assertConsumed` refuses an
injection that never fired. `observe`/`record` report each create, property, attribute, parent and destroy
operation, marking injected failures. `accounting` and `close` return live objects, connections and pending
faults. `instanceHost(actor)` reuses the same environment. `Lune.fixture(options?)` (`src/lune`) binds
`@lune/roblox`'s real database and datatypes to it; `lune run examples/lune-fixture.luau` shows a consumer.
Application-specific UI expectations stay with the consumer.

Under Lute, a serialized reflection snapshot replaces the Lune database at test time.
`lune run tools/export-reflection.luau <out.json> [--classes=A,B,...]` writes a deterministic, compact snapshot of the named classes
and their superclasses: property types, scriptability, tags and the defaults of Vector3, Vector2, Color3, UDim, UDim2,
CFrame, EnumItem, string, number and boolean values (other default types are omitted). Without `--classes` it exports
every class. `Lute.fixture.bridge(path | snapshot, options?)` builds the same bridge from that file with no Lune runtime;
`Roblox.reflectionSnapshot.database(snapshot)` and `.bridge(snapshot, options?)` are the portable forms. Values are
Verify datatypes, so enum items carry their family (`Enum.Material.Plastic`) and are checked against the property's enum.
A Lune test compares the snapshot path with the native bridge for classes, properties, defaults and accepted and refused
writes. Regenerate a committed snapshot after a Roblox API update; the Lune test fails when a fixture is stale.

This is simulated behavior validated against engine metadata, not engine parity: instances are Luau tables,
defaults and property types come from the database, and events, methods, layout, rendering, input and
physics exist only where declared or injected.

`Roblox.uiFakes.classes` declares optional UI methods. Supply it as a class overlay and pass
`uiFakes.validateProperty` as the property validator to reject selection of hidden or unselectable
controls. `uiFakes.attach(environment, { measureText?, measureBounds?, methods? })` installs focus,
style-map, video-state, path-point storage and instant page-navigation fakes. Measurement providers
are required for measurement claims. Keep its controller and call `close()` to release focus resources.
Curve evaluation, rendered text, animated navigation, playback quality and style rendering are not
simulated. Unsupported declared methods require an explicit injected implementation. `attach` registers
`environment.onClone`, so `Clone()` copies style, transition, derive and path state with in-tree derive
references remapped; focus is never copied. `environment.observe` and `pendingFailures` expose operation
observation and unfired fault injection.

`Roblox.environmentEngine(environment, library?)` exposes the environment as a structural scene engine
with creation, heartbeat, clock, datatype constructors, destruction and property observation.
Objects and signals preserve identity. The default uses Verify datatypes; supply the typed factory
library when using native datatypes. This adapter adds no renderer or native engine claims.

The environment implements `Clone()` with internal instance-reference remapping, attributes and tags.
Nonarchivable descendants are omitted; external references stay external; signals are not copied.
It includes recursive `FindFirstChildWhichIsA`, exact/inherited ancestor lookup and instance tag methods.

## Named case collections

`Core.runCases(cases, options, now, ids?)` executes ordinary named cases with exact selection.
The [run guide](running.md) owns selection, entry modules and host execution.
