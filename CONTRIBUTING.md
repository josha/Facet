# Contributing to Facet

Install the pinned toolchain with `rokit install`. Read [AGENTS.md](AGENTS.md) and
[the architecture](docs/guide/02-architecture.md) before changing the library.

A change must leave one runtime path: Compose owns native Instances and lifetime;
Roblox owns engine mechanisms; Facet owns control behavior. Do not add a second
scheduler, scene representation, renderer, solver, input transport or application
facade. Native datatypes and property names are the ordinary authoring vocabulary.

Work in an isolated checkout. Keep control behavior, public types, examples,
documentation and verification aligned. Source uses `Host` for native constructors
and contains no explanatory comments; preserve required directives and notices.

## Verification

Use targeted behavioral specs while editing. `tools/verify.sh full` is required
for a completed change. Read its report, including unmapped legacy behavioral
coverage, rather than treating a new runner's passing subset as full parity.

Run `tools/bench.sh` without concurrent verification load. Keep workload intent
and checked-in baselines intact; report changed measurement boundaries and
preexisting threshold failures explicitly. Exercise the maintained gallery and
virtual monitors in Roblox Studio for real layout/input evidence.

Run `tools/package.sh build` and `tools/package.sh status` after source changes.
Cloud publication is not part of a code change.

## Versioning

`src/init.luau` is the sole version authority. This cutover is 0.12.0 and intentionally
removes the former application, scene, layout and compatibility APIs in one break.
Do not introduce migration shims or a second supported architecture. Subsequent
changes must describe their public effects in the changelog.
