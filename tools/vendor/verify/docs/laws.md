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
| A run's original failure survives cleanup. Log collection, stop and reset run on every exit path; a cleanup failure is reported beside the failure and never replaces it. A held resource is released. | [tests/lifecycle.spec.luau](../tests/lifecycle.spec.luau) |
| A wait names the condition, how long it waited and the last observed state when it times out or is cancelled. Polling repeats no mutation. Only a host that can kill the work enforces a bound. | [tests/wait.spec.luau](../tests/wait.spec.luau), [tests/bounded.spec.luau](../tests/bounded.spec.luau) |
| Actors are joined, readied and left as one unit; a lost actor, a busy shared resource or a failed leave is named and never hidden by the body result. | [tests/actors.spec.luau](../tests/actors.spec.luau) |
| Evidence returned by a step attaches to its case; capture metadata claims no judgment. | [tests/media.spec.luau](../tests/media.spec.luau), [tests/bdd.spec.luau](../tests/bdd.spec.luau) |
| A simulated engine member that is declared but not implemented raises `unsupported_method` unless a function or explicit fake supplies the answer; a schema is never a behavior. Destroyed instances lock, disconnect and are counted; time is virtual. | [tests/environment.spec.luau](../tests/environment.spec.luau) |
| Hierarchy events preserve old state during removal and final ancestry afterwards; reflection validation rejects a write before mutation. Explicit fakes own UI behavior. | [tests/environment.spec.luau](../tests/environment.spec.luau) |
| Sealing freezes observations; only the harness judges them. It does not authenticate the collector. | [tests/foundation.spec.luau](../tests/foundation.spec.luau), [tests/tier-ladder.spec.luau](../tests/tier-ladder.spec.luau) |
| Capture and transcript selection require the intended current source. Stale, absent, ambiguous, wrong-target and repeated evidence cannot silently qualify. | [tests/scenario-runner.spec.luau](../tests/scenario-runner.spec.luau), [tests/witness-host.spec.luau](../tests/witness-host.spec.luau), [tests/viewport-corners.spec.luau](../tests/viewport-corners.spec.luau), [tests/tier-ladder.spec.luau](../tests/tier-ladder.spec.luau) |
| Host operations require caller-supplied capability and authority. A limitation never excuses an observed defect. | [tests/consumer.spec.luau](../tests/consumer.spec.luau), [tests/tier-ladder.spec.luau](../tests/tier-ladder.spec.luau) |

Core has no I/O, engine, ambient scheduler or credential dependency. Inject time when testing it.
Portable module graphs must resolve in the engine tree; [tests/requires.spec.luau](../tests/requires.spec.luau) checks the actual
closure. Fake place/instance hosts test declared behavior and refusal paths, not engine truth.

The gate runs format, lint, types, behavioral tests and source-boundary checks on current bytes.
It does not execute Studio or Player, authenticate an image, establish audio/input quality, measure
production performance, or prove the caller's expected claims are complete. The consumer must bind
its real run, source/tree, destination and artifact bytes. It must retain the current result in its own
operation record. Laws cannot substitute for those observations.
