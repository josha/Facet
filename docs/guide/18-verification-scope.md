# Verification scope

The current suite is the evidence. It does not claim to equal the tests that
existed before the native cutover. A passing run covers the cases and producers
that the runner selected. A focused run is not full evidence. Do not infer a
performance improvement from a shorter verification time.

## Headless evidence

`tests/plan.json` lists the executable spec sources. The Verify gate runs the
cases that these sources register. Reports record each case result and the
selected tier. A native engine double checks control policy, state and resource
ownership. It does not prove engine layout, paint or real input behavior.

`tools/check_plan.py` checks that the plan lists every spec file on disk
exactly once. It rejects missing files, duplicate IDs and incorrect source
paths. The `plan` producer runs this check. The `suite` producer runs the
registered cases and records their results.

## Live evidence

Geometry, hit testing, text editing, scrolling, selection and real input need
live Studio evidence. The live runner uses Verify to produce case reports.
Use the report for the build, device and case that ran. A source file or a
hand-written observation does not replace a run result.

Studio device simulation does not prove physical haptic output, device memory
pressure, thermals or battery use. See
[device verification](11-device-verification.md) for the commands and device
checks.

## Gate evidence

The gate records the selected producers, case results, failures and deferrals.
A complete tier means that all selected commands were attempted. It does not
prove fresh Studio evidence for every control or physical device behavior.
The `release` tier requires the complete gate with no deferrals.

Timing budgets stop the run on the reference host. On other hosts, a failed
timing budget is reported as `deferred`. A deferral is not a passing measurement.
Compare performance reports only with their workload and host limits in view.
See [paired performance](19-paired-performance.md) for the comparison method.

Use [Contributing](../../CONTRIBUTING.md) to run the current tier. Read the
Verify reports to determine what passed, failed, was unsupported or was not
selected.
