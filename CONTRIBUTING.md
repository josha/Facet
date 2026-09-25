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
3. Run `tools/verify.sh full` for a completed change. Read its report,
   including the unmapped legacy behavioral coverage. A passing subset from a
   new runner is not full parity.

Each run writes `artifacts/verify/latest-<tier>.json`. Use `--explain` to see
each selected producer, its tiers and the main producer it replaces. A studio,
device or timing producer that exits 2 reports `FAIL_ENVIRONMENT`: its evidence
is not recorded, or a host timing budget failed. The `full` tier reports it and
continues. The `release` tier stops on it. `tools/package.sh publish` accepts
only a clean, passing `artifacts/verify/latest-release.json` for the same source.
The [producer comparison](docs/guide/20-verification-parity.md#producers) lists
each main producer and its native status.

A spec case can require a higher tier. Give `t.it` the option
`{ tier = "full" }` (or `"release"`) when the case is too slow for the working
tiers, for example a mount ramp to the declared ceiling of 40000 rows. The
`affected` and `fast` tiers record the case as `skip` with its tier, and the
suite check accepts it there. The `full` tier runs a `full` case, and only the `release` tier runs a
`release` case. The mount ramp to 40000 rows is a `release` case. A case that
the run's own tier must run cannot be skipped. `lune run tests/run_one <spec>`
also skips it. Use `lune run tests/run_one <spec> release` to run it.

The [verification scope audit](docs/guide/18-verification-scope.md) records the
substantial reduction from main and the unresolved coverage work. At this time,
a native `full` run is a complete run of the candidate's checks. It is not
equivalent to the historical coverage.

The `types` producer runs `python3 tools/check_types.py` with the old Luau type
solver at the default analyzer limits. It must report no owned diagnostics and
must reject all negative probes. Run `python3 tools/check_types.py --solver new`
to check the new type solver (`LuauSolverV2`). That run must not exceed the
diagnostic budget in `tools/typecheck/solver_v2_budget.json`. When a change
removes new solver diagnostics, lower the budget in the same change. Do not
raise it.

Run `tools/bench.sh` when no other verification load runs. Keep the workload
intent and the checked-in baselines. Report changed measurement boundaries and
preexisting threshold failures explicitly. For real layout and input evidence,
exercise the maintained gallery and the virtual monitors in Roblox Studio.

After a source change, run `tools/package.sh build` and
`tools/package.sh status`. Cloud publication is not part of a code change.

## Versioning

`src/init.luau` is the only version authority. Version 0.12.0 is the native
cutover. It removes the former application, scene, layout and compatibility
APIs in one break. Do not add migration shims or a second supported
architecture. Describe the public effects of each later change in the
changelog.
