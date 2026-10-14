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

Facet source must not use the `any` type outside `src/vendor`. Use a concrete
type or check an `unknown` value before you use it.
`lute run tools/facet check type-policy` checks this rule. It reads the syntax
tree of each file and counts each `any` type annotation. The tracked limits in
`tools/typecheck/any_budget.json` cover non-vendored examples, tools, tests and
bench. Counts must not exceed these limits. Limits can only decrease. Run
`lute run tools/facet check type-policy --counts` to print the current counts. Run
`lute run tools/facet check type-policy --lower-budgets` to lower the limits after
you remove uses. This command refuses to raise a limit.

## Verification

1. While you edit, run the targeted behavioral specs.
2. Run `lune run tools/lune/verify full` for a completed change. Read its report,
   including failures and deferrals. A focused run is not full evidence.

`tools/lune/gate.luau` declares every producer as one Verify gate. Verify runs
the producers, bounds each process, keeps the logs and writes the outcome.
Each run writes its outcome to `artifacts/verify/native/gate/latest.json`. Use
`--list` to see each producer, its tier and the main producer it replaces. Use
`--only <producer>` for a focused run, `--rerun` to repeat what the last run
did not pass and `--explain <id>` to see why a producer or a case ran. A
focused run is not tier evidence. A studio, device or timing producer that exits 2 is `deferred`:
its evidence is not recorded, or a host timing budget failed. The `full` tier
reports the deferral and continues. The `release` tier is the complete gate and
is not releasable with a deferral. `lute run tools/facet package publish` accepts only a
releasable `artifacts/verify/native/gate/latest.json` whose build binding matches
the clean source.

Specs return a registration function. The worker supplies a Verify harness. Use `harness:suite`, `harness:case`, and
`Verify.expect(value):toBe(expected)`. Give each case an explicit, stable `id`.
Verify owns assertions, case cleanup, and reports. The consumer gate owns
coverage and release acceptance.

`tests/plan.json` declares the complete executable corpus. It lists the spec
sources. Add a new source to that plan. The `plan` producer checks that each
spec file on disk appears exactly once. There is no committed case list.
The gate runs each case that a planned source registers.

A slow case can require the `full` or `release` tier. Give the case the tag
`tier:full` or `tier:release`.
Below that tier, Verify records the case as deselected. The 40000-row mount
ramp requires `release`.
`lune run tools/lune/verify spec <spec> ...` runs the named sources below the release
tier. Use `--tier release` to include the release cases. Each source runs in
its own Lune worker through the Verify gate. The full gate runs the committed
plan the same way with four workers. A worker failure, a missing or foreign
receipt, or a source that reports no case fails the producer. Verify stops the worker
process group at its deadline.

Verify is pinned under `tools/vendor/verify`. It is a generated, read-only test
dependency and is not part of the Facet model. Run
`lute run tools/facet sync verify --check` to check its files. Change shared testing
mechanisms in `voidmeld/verify`, then update the pin. The consumer guide is
[Verify's skill](tools/vendor/verify/.agents/skills/verify/SKILL.md).

The [verification scope](docs/guide/18-verification-scope.md) describes the
current evidence. The current suite does not claim to equal the tests that
existed before the native cutover.

The `types` producer runs `lute run tools/facet types` with the old Luau type
solver at the default analyzer limits. It must report no owned diagnostics and
must reject all negative probes. Run `lute run tools/facet types --solver new`
to check the new type solver (`LuauSolverV2`). It is an optional check outside
the required `types` producer. A passing run needs zero owned diagnostics and
all negative probes rejected. Compare its failures with main and report them
separately from the required solver.

Run `lune run tools/lune/bench` when no other verification load runs. Keep the workload
intent and the checked-in baselines. Report changed measurement boundaries and
preexisting threshold failures explicitly. For real layout and input evidence,
exercise the maintained gallery and the virtual monitors in Roblox Studio.

After a source change, run `lute run tools/facet package build` and
`lute run tools/facet package status`. Cloud publication is not part of a code change.

## Tooling

The maintainer tools are strict Luau programs that run on Lute. `rokit install`
installs Lute. Run `lute run tools/facet help` to list the commands.

- `lute run tools/facet check --list` lists each repository check. Run
  `lute run tools/facet check <rule>` to run one check. Add `--selftest` to run
  its cases against planted faults. `lute run tools/facet check --all` runs every
  check.
- `tools/facet/checks` holds one module for each check. A check module returns
  its findings and its selftest cases. `tools/facet/commands` holds the other
  commands. `tools/facet/lib` holds the shared modules.
- `tests/tools/rules.spec.luau` and `tests/tools/commands.spec.luau` run each
  selftest case as a Verify case in the Lute worker `tests/tools/worker.luau`.
  The `tool-specs` producer runs each plan unit that requires `lute`. The
  `suite` producer runs the other plan units in the Lune worker.
- Give the tag `tier:full` to a case that runs an external tool or that takes
  more than two seconds.
- `tools/lune` holds only the Verify gate runner and the programs that run
  Facet in the Lune engine double: the benchmarks, the performance workloads,
  the public surface check, the package canary and the theme probes.

Do not add Python programs.

## Versioning

`src/init.luau` is the only version authority. Version 0.12.0 is the native
cutover. It removes the former application, scene, layout and compatibility
APIs in one break. Do not add migration shims or a second supported
architecture. Describe the public effects of each later change in the
changelog.
