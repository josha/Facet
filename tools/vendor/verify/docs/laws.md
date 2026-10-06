# Verification laws

A claim consists of a named case, the observations it judges, and a receipt from its executor.
A recorded verdict provides evidence of that execution. It grants no publication authority and proves nothing about another artifact.

| Contract | Tests that can detect a violation |
| --- | --- |
| Each harness/source owns its registry. Reset or reentry cannot erase queued work. | [tests/core.spec.luau](../tests/core.spec.luau), [tests/foundation.spec.luau](../tests/foundation.spec.luau) |
| Setup, case, teardown and cleanup failures remain independently visible. Cleanup runs once, newest first. | [tests/core.spec.luau](../tests/core.spec.luau), [tests/worker.spec.luau](../tests/worker.spec.luau) |
| Missing capability is unsupported; deliberate omission is skipped. Neither passes. Empty, partial and focused runs cannot establish complete acceptance. | [tests/core.spec.luau](../tests/core.spec.luau), [tests/execution.spec.luau](../tests/execution.spec.luau), [tests/foundation.spec.luau](../tests/foundation.spec.luau) |
| A plan accounts for every unit and attempt. Host failures, missing/duplicate results and disagreeing retries cannot become green. | [tests/execution.spec.luau](../tests/execution.spec.luau), [tests/worker.spec.luau](../tests/worker.spec.luau) |
| Receipts retain source, executor, environment, failures and limitations. Malformed counts, schema drift, truncated/mixed/conflicting transport and duplicate cases fail closed. | [tests/core.spec.luau](../tests/core.spec.luau), [tests/foundation.spec.luau](../tests/foundation.spec.luau), [tests/adapters.spec.luau](../tests/adapters.spec.luau) |
| A wait names the condition, how long it waited and the last observed state when it times out or is cancelled. Polling repeats no mutation. Only a host that can kill the work enforces a bound. | [tests/wait.spec.luau](../tests/wait.spec.luau), [tests/bounded.spec.luau](../tests/bounded.spec.luau) |
| Every tier uses the ordinary case context and failure classifier. Typed host observations survive report transport; capture metadata claims no judgment. | [tests/semantic-execution.spec.luau](../tests/semantic-execution.spec.luau), [tests/instance-host.spec.luau](../tests/instance-host.spec.luau) |
| A simulated engine member that is declared but not implemented raises `unsupported_method` unless a function or explicit fake supplies the answer; a schema is never a behavior. Destroyed instances lock, disconnect and are counted; time is virtual. | [tests/environment.spec.luau](../tests/environment.spec.luau) |
| Hierarchy events preserve old state during removal and final ancestry afterwards; reflection validation rejects a write before mutation. Explicit fakes own UI behavior. | [tests/environment.spec.luau](../tests/environment.spec.luau) |

Core has no I/O, engine, ambient scheduler or credential dependency. Inject time when testing it.
Portable module graphs must resolve in the engine tree; [tests/requires.spec.luau](../tests/requires.spec.luau) checks the actual
closure. Fake place/instance hosts test declared behavior and refusal paths, not engine truth.

The gate runs format, lint, types, behavioral tests and source-boundary checks on current bytes.
The optional `--native` gate executes the reference Studio conformance cases. The portable gate does not.
Neither gate authenticates an image, establishes audio/input quality, measures
production performance, or proves the caller's expected claims are complete. The consumer must bind
its real run, source/tree, destination and artifact bytes. It must retain the current result in its own
operation record. Laws cannot substitute for those observations.
