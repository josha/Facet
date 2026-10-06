# Verify migration receipt

Facet now uses the same testing library as Compose. This reduces the test
machinery that Facet maintains so it can focus on its UI controls.

Facet uses the public API of `voidmeld/verify` for case registration, assertions,
lifecycle, execution plans, results, observations and transport. The old
`tests/lib/testkit.luau` is removed. There is no compatibility harness.

## Source and scope

- Facet baseline: `9ed7e57cec0ca8b21f0e2134de6ddd538adda5b7`.
- Verify pin: `7ee3d2737d74e9283bb1510224ec3f5c7853a1d2`.
- All 151 spec sources were converted by the syntax-aware codemod.
- All 3,765 registered case IDs, names and source identities are unchanged.
- The default plan has the same 150 sources as the baseline: 3,731 cases.
  `native_toast` remains available as a targeted source. Its existing behavior
  replacement mapping excludes it from the default gate.
- The same release-only case is deferred below the release tier.
- The full producer catalogue retains all baseline commands and adds Verify
  pin integrity, host fault tests and the registration census.
- Facet source, public contracts, version, control examples and benchmark
  workloads are unchanged. Verify is outside `src` and the shipped library.

The migration does not establish parity with the earlier 10,848-case historical
suite. Read [verification scope](../docs/guide/18-verification-scope.md).

## Codemod reproduction

Use Python 3.9 or later and the pinned Facet StyLua tool:

```sh
python3 -m venv /tmp/facet-verify-codemod
/tmp/facet-verify-codemod/bin/pip install -r tools/codemods/requirements.txt
/tmp/facet-verify-codemod/bin/python tools/codemods/verify_cutover.py \
  --revision 9ed7e57cec0ca8b21f0e2134de6ddd538adda5b7 --check
/tmp/facet-verify-codemod/bin/python -m unittest discover \
  -s tools/codemods -p 'test_*.py'
```

`--write` regenerates the migrated sources from that revision. Both modes run
StyLua until the output is stable. The transformation changes 501 suite
calls, 3,185 case call sites and 21,700 matcher calls. Runtime-generated cases
account for the difference between call sites and registered cases. It changes
three negations to Verify's property form and preserves the original `1e-4`
tolerance explicitly in 110 comparisons. One helper registers cases outside
the lexical suite; the census checks its generated IDs. The codemod also makes
7,512 function-call arguments yield one assertion value, removes four obsolete
harness returns, and adds one numeric parameter annotation required by the
public Verify types.

The codemod preserves type expressions and string contents. Its parser view
masks unsupported Luau type syntax without changing the source bytes.

## Host boundaries

`tests/runner.luau` loads the committed plan with `Verify.execute`. Each source
returns a registration function. Load, registration, empty-source, case and
cleanup failures produce Verify results. The consumer gate binds those results
to the complete case inventory and rejects missing, extra or duplicate IDs.
It also rejects incomplete execution, malformed results and unapproved skips.

The producer host supplies command execution. Verify supplies dispatch and
result accounting. Facet retains its architecture, historical coverage,
release and environment acceptance policy. Missing Studio, device or reference
performance evidence stays visible and blocks release acceptance.

The worker host supplies isolated processes and deadline termination. Verify
supplies batch selection, dispatch and aggregation. Timed-out workers have their
entire process group killed before a timeout result is returned.

The Studio host retains geometry, input, screenshots and game-specific setup.
Each live assertion is a Verify step. Cleanup errors remain failures. Receipts
contain native Verify reports and sealed observation bundles. The relay uses
Verify segmentation and rejects incomplete or conflicting segments.

The APIs checked were Roblox native layout, selection and input APIs,
[`RemoteEvent:FireServer`](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/RemoteEvent.yaml),
and [`HttpService:PostAsync`](https://github.com/Roblox/creator-docs/blob/main/content/en-us/reference/engine/classes/HttpService.yaml);
Compose mounting and ownership; and Verify's public core, observation and
execution APIs. Roblox and Compose do not supply test registration or result accounting.
Facet's engine fixture simulates native controls for existing behavioral tests.
Verify's optional test environment does not cover all of that fixture's engine behavior.
Real Studio observations remain separate evidence.

`time_specs.luau` now measures case execution from Verify results. Its timing
boundary differs from the previous monkey-patched load and memory sampler.
These timings do not prove a control performance change.

## Validation

The detailed logs and JSON reports are in `artifacts/verify` in the worktree.
The final baseline comparison is recorded below after both gates complete.

- Eight codemod tests passed.
- Registration census: all 3,765 unchanged case IDs passed.
- The retained `native_toast` source passed all 34 cases on both main and Verify.
- Nineteen consumer acceptance self-tests passed.
- Six host boundary tests passed, including load, registration, empty source,
  duplicate IDs, case and cleanup errors, tier deferral, report corruption and
  transport damage.
- Two isolated worker sources passed: 90 cases. A real deadline test produced
  one timeout and killed the worker process group.
- Package build and status completed successfully.
- The default type solver passed with zero owned or dependency diagnostics.
  All 181 public negative probes were rejected.
- Studio grid geometry passed 18 checks; navigation geometry passed nine.
  These are targeted live observations, not full Studio coverage.

The full `layout_geometry` suite ran under both the original main harness and
Verify in the same isolated Studio place. Both had nine passes and four
failures. All 421 named check outcomes matched. The existing failures were
`callout-edge-gap-shift-clamp`, `tab-head-accessory-above-rail`,
`circle-button-authored-axes` and `panel-insets-reserve-native-padding`.

Two interactive cases used real Studio keyboard input. Both harnesses had the
same three check outcomes: held-arrow repeat passed, the final-row check failed,
and Tab traversal failed after visiting B and C. These are baseline failures,
not migration regressions. The viewport was 844 by 369, with touch enabled, in
Studio version `0.741.19.7411056`.

The server relay received the complete 105,725-byte geometry receipt for the
final Verify pin through
four Verify segments. The receipt remained valid JSON and retained all cases,
observations and failure steps. The comparison is recorded in
`artifacts/verify/studio-comparison.json`. The final pin geometry comparison is
in `artifacts/verify/studio-upstream-comparison.json`; all 421 checks still match.

The main baseline full gate passed: 3,730 cases passed and one release-only case
was deferred. Its 74 producer entries had 72 passes and two environment
deferrals: `perf` and `perf-gate-evidence-perf-gate`.

The benchmark inside the final full gate passed with 3.1 percent CPU yardstick
drift. The final standalone benchmark returned `FAIL_ENVIRONMENT` (exit 2)
with 31.9 percent drift. An earlier standalone run also failed with 32.8
percent drift. Those standalone runs do not provide a valid performance
comparison. No benchmark workload or Facet runtime source changed.
The full performance producer reported eight host timing budget violations;
main reported 15. Neither result establishes a control performance change.

Before the final upstream re-pin, the optional new type solver failed on both
trees: 13,028 diagnostics on main and 13,198 on that candidate. The final pin
was not re-tested with this optional solver. The default solver is the required
gate.
The new solver results do not establish parity or a passing migration.

The final candidate full gate passed: 3,730 cases passed, no cases failed and
one release-only case was deferred. Its 77 producer entries had 75 passes and
the same two performance environment deferrals as main: `perf` and
`perf-gate-evidence-perf-gate`. The complete source plan was accounted for.
The final default type solver checked 699 targets with zero owned or dependency
diagnostics and rejected all 181 public negative probes. No library source,
benchmark workload or case ID changed.

## Current Verify main

The final dependency pin includes the session-backed BDD surface, case metadata,
bounded waits, actors, media, lifecycle evidence, plan accounting and the Roblox
test environment. The native suite and producer host use `Core.accountPlan` to
check that every selected unit returned. Both native entry points use the same
Verify worker host, with a fresh Lune process per source and a bounded deadline.

The optional `Roblox.testEnvironment` does not yet cover the native fixture's
`AncestryChanged` and `DescendantRemoving` behavior, reflection-derived default
values, runtime method replacement and geometry measurement callbacks. Facet
keeps this explicit fixture. It owns no case registration, assertions, case scheduling
or result format. Live Studio remains the evidence for actual engine behavior.
The Lute bounded-process API cannot replace the Lune worker deadline host.

Upstream source and guide bytes remain unchanged. The integrity gate checks
every snapshot file. Facet source guards exclude generated upstream guides and
accept only Verify in the tool vendor directory. Verify stays outside the
consumer model.
