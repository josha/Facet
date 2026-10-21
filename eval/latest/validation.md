# Checkpoint validation

The full repository gate did not pass. This checkpoint does not establish
a clean full gate or an eval pass.

`lute run tools/facet gate full` produced
`gate-1792622570-311127-1`. One producer failed:

| Producer | Finding | Checkpoint status |
| --- | --- | --- |
| screen-key-bindings | 14 input-policy findings in the preserved Kart example | Open |

The vendor, behavior suite, tooling suite, types, standalone builds, resource
ceilings, and teardown checks passed. The previous mapped-file lock did not
recur. The Kart findings are preserved example debt; this report does not
claim that the base commit had the same gate failures.

The final focus-cleanup correction and regression assertions were completed
while this gate ran. Focused Card, input, and collection specs passed in
`gate-1792622861-947965-1`; the added input focus assertion passed in
`gate-1792622887-503217-1`. Four changed source/test targets passed strict
analysis in `artifacts/verify/types/focused-22eaebdb7d.json`. These checks do
not turn the earlier full gate into final-tree evidence.

Live Studio reports in `library-card-lift` cover centered lift, neighboring
layout, resize, content changes, native click, focus cleanup, temporary-layer
release, and grid corners. `shared-feedback.verify.json` covers Button pop,
field rejection, disclosure motion, and idle property writes. Its idle window
starts only after the disclosure reaches its resting angle, with a two-second
deadline. A fixed-frame wait previously began before that animation ended.

The resource census stayed within unchanged ceilings: Card uses 15 instances,
8 connections, and 83 reactive holdings. Teardown counts return to zero.
The memory check still reports collection-churn connection growth as a trend;
zero teardown counts do not establish flat retained memory during play.

The final `lute run tools/facet bench` passed with 1.9% yardstick drift after
the full gate stopped. An earlier overlapping run was rejected for host drift.
`lute run tools/facet package build` and `lute run tools/facet package status`
completed successfully. The package is unpublished, and its Studio check is
pending. The source hash is
`5bef441d272872040a0df8596867e1af8f7cc2fd07af73d9f838b2760a51a029`.
These commands do not attest a passing full gate on the final tree.

Type policy, eval contract, documentation nodes, and strict documentation
samples also passed. The full gate deferred reference-host performance
evidence. The benchmark does not establish native retained-memory overhead
or the eval's frame-time threshold.

See [the evidence report](README.md) for player and blind-judge results.
