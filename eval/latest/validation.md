# Checkpoint validation

The full repository gate did not pass. This checkpoint is not merge-ready
evidence of a clean full gate or an eval pass.

`lute run tools/facet gate full` produced
`gate-1792619918-149644-1`. Five producers failed:

| Producer | Finding | Checkpoint status |
| --- | --- | --- |
| vendor | Verify notice had the previous pin | Corrected; vendor check passes |
| suite | State documentation sample omitted local definitions | Corrected; focused native documentation spec passes |
| tool-specs | Stage documentation sample needed native value types in its test environment | Corrected; focused documentation examples spec passes |
| screen-key-bindings | 14 input-policy findings in the preserved Kart example | Open |
| standalone-builds | Windows reported a mapped-file lock on the generated Showcase place (OS error 1224) | Blocked by the environment |

The focused spec reports are `gate-1792620607-235139-1` and
`gate-1792620607-234908-1`. They do not replace a full gate. The full gate
was not repeated after these corrections. The Kart findings are preserved
example debt; this report does not claim that the base commit had the same
gate failures.

The final `lute run tools/facet bench` passed with 1.1% yardstick drift.
`lute run tools/facet package build` and `lute run tools/facet package status`
completed successfully. The package is unpublished, and its Studio check is
pending. These commands do not attest a passing full gate on the final tree.

Type policy, eval contract, documentation nodes, and strict documentation
samples also passed. The full gate deferred reference-host performance
evidence. The benchmark does not establish native retained-memory overhead
or the eval's frame-time threshold.

See [the evidence report](README.md) for player and blind-judge results.
