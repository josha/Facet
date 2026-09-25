# Verification scope during the native cutover

The verification for the native cutover is substantially smaller than the
verification on main. A passing native `full` run is not evidence of equivalent historical
coverage. It means only that the commands that the current runner selects
passed. Do not infer a performance improvement from the shorter verification
time.

## Measured comparison

The baseline is commit `a8c8895673c0745506908b66dc89f8cead6b66f3`. This is the
commit immediately before the native cutover. The audited candidate was
`e12f9d40`.

| Inventory | Baseline | Candidate before restoring checks |
|---|---:|---:|
| Test cases | 10,848 registered | 593 executed |
| Full-tier producers | 130 | 24 |
| Rows in the historical verification graph | 505 | Historical graph not evaluated |

The baseline case count comes from loading `tests/run.luau` with registration
instrumented and execution suppressed. It does not come from a fresh, passing
baseline test run. The candidate count comes from
`artifacts/verify/native/suite.json`. Case counts are not equivalent units of
behavior, but this reduction needs justification.

The baseline producer counts come from `tools/lune/verify/graph.json` at the
baseline commit. They select the producers with `tiers.full == true`. Their
environment classes are:

- 94 deterministic,
- 24 Studio,
- seven device,
- three external,
- two package.

Studio and device producers include validators of recorded evidence. Thus 130
does not mean 130 freshly executed runtime suites. The graph also includes
checks of the old architecture and of historical projects. You cannot simply
run those checks again against the native implementation.

## What the current mapping proves

The candidate coverage inventory classifies 252 historical specs as removed
mechanisms and 249 as behavior replacements. It runs 30 available specs and
tracks 18 gallery parity entries. These are inventory classifications. They are
not a case-by-case proof that all user-facing contracts survived.

At this time, a retirement needs only nonempty rationale text. A replacement
names specs and passing case IDs. But the checker does not require an account
of every original assertion. Thus a broad retirement rationale can hide a
behavior that still exists. In this audit, only 14 replacement entries
contained `caseMappings`.

In the audited candidate, the runner also ignored `pendingLiveRisks` when it
decided its exit code. At commit `254e44d0`, the coverage producer fails when
`pendingLiveRisks` has entries. This does not close any of the risks.

`historicalParity: "not-established"` in the current report is independent of
`ok`. `completeTier` means that all selected commands were attempted. It does
not establish historical parity or fresh Studio or device coverage.

## Restored checks

The follow-up restores these existing checks to native `full`:

- the link checker and its fault-injection self-test,
- the source-size guard,
- the type checker self-test,
- the package checker self-test.

When link validation came back, it found two obsolete API anchors in the
historical changelog. Those references now state explicitly that they describe
the old API. These checks keep their existing implementations and failure
conditions.

## Unresolved coverage work

Before you treat native verification as equivalent protection, account for
each historical producer and each original behavioral assertion. In
particular:

- Port the surviving control contracts, error handling, input and focus
  behavior, collection ownership and teardown assertions. The removal of the
  private solver and renderer alone does not justify the retirement of those
  behaviors.
- Audit the lost fuzz, fault, soak and conformance workloads. The native suite
  has some corresponding cases. But their mappings do not prove equivalent
  workload duration, seed coverage, fault injection or invariant strength.
- Audit the omitted public-surface, boundary, documentation, registration and
  artifact checks. Restore the checks that still apply. Replace architecture
  assumptions where necessary.
- Verify all maintained standalone and reference place bootstraps and theme
  distributions. Building the gallery, the monitors and the performance place
  does not cover all former artifact producers.
- Renew the applicable Studio and device evidence. The outstanding recorded
  risks include compact and largest-text collections and settings, live
  preferred-transparency changes, and retained-page transient, haptic and
  motion lifetime.

The previous Ubuntu CI lane moved to macOS ARM after host-dependent failures of
timing thresholds. That is a change of measurement environment. It does not
prove that the Ubuntu regression was resolved. Keep this distinction when you
compare performance reports and when you decide which platforms CI must cover.
CI runs the full tier on Ubuntu again, beside the ARM runner. On Ubuntu, a
failed timing budget is reported as `FAIL_ENVIRONMENT` and does not stop the
run. Timing budgets stop the run only on the reference host.

See [Contributing](../../CONTRIBUTING.md) to run the current tier, and
[device verification](11-device-verification.md) for the limits of headless
checks. This audit stays open. Restoring a small number of checks does not
close it.
