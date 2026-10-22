# Checkpoint validation

The local full-tier command finished with no failing producers. It is not a
complete release gate and does not establish an eval pass. Final mergeability
also depends on the GitHub checks for the PR head.

## Repository checks

`lute run tools/facet gate full` produced
`gate-1792626881-77900-1`: 37 producers passed, two were deferred, and two
release-only producers were not selected. See the
[command output](repository-validation.txt).

Behavior, maintainer-tool cases, types, formatting, input policy, eval contract,
standalone builds, resource ceilings, and teardown passed. The prior Kart
input-policy and clean-checkout eval failures are fixed. No rule or resource
budget was relaxed. The eval contract case now starts without generated
artifacts and still rejects an unknown overlay path.

The gate began on a dirty worktree based on `a86af51a`, containing the CI
repairs subsequently committed in `30a397a7`. Evidence text and the additional
missing-overlay assertion were finalized during that run. GitHub CI on the
final PR head is the authoritative clean-checkout check; this local receipt
does not attest a clean final commit.

The `bench` and `perf` producers defer reference-host timing evidence. The
full tier excludes `run-comparison` and `prove-perf-gate`. The separately
recorded [eval comparison](comparison.verify.json) fails: two requirements
pass and 16 fail. CI success must not be read as an eval pass.

## Library and package checks

The separate `lute run tools/facet bench` passed after the full-tier process
stopped, with 0.3% yardstick drift. See [benchmark output](library-benchmark.txt).
This native-double benchmark does not establish game frame-time or retained
memory overhead. Its heap readings include allocation churn and collector
phase.

`lute run tools/facet package build` and `lute run tools/facet package status`
completed successfully. The package is unpublished; Studio package verification
remains pending. The source hash is
`5bef441d272872040a0df8596867e1af8f7cc2fd07af73d9f838b2760a51a029`.

The resource census stayed within unchanged ceilings: Card uses 15 instances,
8 connections, and 83 reactive holdings. Teardown counts return to zero.
Collection-churn connection growth remains a reported trend; zero teardown
counts do not prove flat retained memory during play.

## Live engine evidence

Reports in `library-card-lift` cover centered lift, neighboring layout,
resize, content changes, native click, focus cleanup, temporary-layer release,
and grid corners. `shared-feedback.verify.json` covers Button pop, field
rejection, disclosure motion, and idle property writes. The idle window starts
only after the disclosure reaches its resting angle, with a two-second
deadline.

The [Kart input observations](kart-input-observations.md) record a separate
live test of native Back and settings action integration. Physical-controller
verification remains pending. Neither these checks nor the Card receipts
establish the new games' complete five-device player acceptance.

See [latest pair](README.md) for the authored-game verdict and
[next improvements](next-improvements.md) for the remaining work. No additional
author run is part of this checkpoint.
