# Contributing to Facet

Install the pinned toolchain with `rokit install`. Read [AGENTS.md](AGENTS.md)
and [the architecture](docs/guide/02-architecture.md) before you change the
library.

A change must keep one runtime path:

- Compose owns the native Instances and their lifetime.
- Roblox owns the engine mechanisms.
- Facet owns control behavior.

Do not add a second scheduler, scene representation, renderer, solver, input
transport or application facade. Use native datatypes and native property names
as the ordinary authoring vocabulary.

Work in an isolated checkout. Keep control behavior, public types, examples,
documentation and verification aligned. In source, use `Host` for the native
constructors. Source contains no explanatory comments. Keep the required
directives and notices.

## Verification

1. Use a checkout with Git history. Clone without `--depth`, or run
   `git fetch --unshallow` in a shallow clone. The coverage audit reads the
   pinned pre-cutover commit to account for removed and replaced specs. CI also
   fetches this history.
2. While you edit, run the targeted behavioral specs.
3. Run `lune run tools/lune/verify full` for a completed change. Read its report,
   including the unmapped legacy behavioral coverage. A passing subset from a
   new runner is not full parity.

`tools/lune/gate.luau` declares every producer as one Verify gate. Verify runs
the producers, bounds each process, keeps the logs and writes the outcome. A
complete tier writes the outcome to `artifacts/verify/latest-<tier>.json`. Use
`--explain` to see each selected producer, its tier and the main producer it
replaces. Use `--rerun <producer>` for a focused run. A focused run is not
tier evidence. A studio, device or timing producer that exits 2 is `deferred`:
its evidence is not recorded, or a host timing budget failed. The `full` tier
reports the deferral and continues. The `release` tier is the complete gate and
is not releasable with a deferral. `python3 tools/package.py publish` accepts only a
releasable `artifacts/verify/latest-release.json` whose build binding matches
the clean source.
The [producer comparison](docs/guide/20-verification-parity.md#producers) lists
each main producer and its native status.

Specs return a registration function. The worker supplies a Verify harness. Use `harness:suite`, `harness:case`, and
`Verify.expect(value):toBe(expected)`. Give each case an explicit, stable `id`.
Verify owns assertions, case cleanup, and reports. The consumer gate owns
coverage and release acceptance.

`tests/plan.json` declares the complete executable corpus. Add a new source to
that plan. `tests/case_inventory.json` records the case census. Add its case IDs
when you add behavior. The gate rejects a missing or extra case. The migration
census includes the retained `native_toast` source; its replacement mapping
excludes it from the full plan, as before the migration. You can still run it
with the single-source command.

A slow case can require the `full` or `release` tier. Give the case the tag
`tier:full` or `tier:release`, and record the tier in the case inventory.
Below that tier, Verify records the case as deselected. The 40000-row mount
ramp requires `release`.
`lune run tools/lune/verify spec <spec> ...` runs the named sources below the release
tier. Use `--tier release` to include the release cases. Each source runs in
its own Lune worker through the Verify gate. The full gate runs the committed
plan the same way with four workers. A worker failure, a missing or foreign
receipt, or a census difference fails the producer. Verify stops the worker
process group at its deadline.

Verify is pinned under `tools/vendor/verify`. It is a generated, read-only test
dependency and is not part of the Facet model. Run
`python3 tools/sync_verify.py --check` to check its files. Change shared testing
mechanisms in `voidmeld/verify`, then update the pin. The consumer guide is
[Verify's skill](tools/vendor/verify/.agents/skills/verify/SKILL.md).

The [verification scope audit](docs/guide/18-verification-scope.md) records the
substantial reduction from main and the unresolved coverage work. At this time,
a native `full` run is a complete run of the candidate's checks. It is not
equivalent to the historical coverage.

The `types` producer runs `python3 tools/check_types.py` with the old Luau type
solver at the default analyzer limits. It must report no owned diagnostics and
must reject all negative probes. Run `python3 tools/check_types.py --solver new`
to check the new type solver (`LuauSolverV2`). It is an optional check outside
the required `types` producer. A passing run needs zero owned diagnostics and
all negative probes rejected. Compare its failures with main and report them
separately from the required solver.

Run `lune run tools/lune/bench` when no other verification load runs. Keep the workload
intent and the checked-in baselines. Report changed measurement boundaries and
preexisting threshold failures explicitly. For real layout and input evidence,
exercise the maintained gallery and the virtual monitors in Roblox Studio.

After a source change, run `python3 tools/package.py build` and
`python3 tools/package.py status`. Cloud publication is not part of a code change.

## Versioning

`src/init.luau` is the only version authority. Version 0.12.0 is the native
cutover. It removes the former application, scene, layout and compatibility
APIs in one break. Do not add migration shims or a second supported
architecture. Describe the public effects of each later change in the
changelog.
