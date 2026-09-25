# Building with Facet

Facet is a library of Roblox UI controls. The controls use Compose and the
Roblox engine. Read [the API reference](docs/reference/api.md) and
[the architecture](docs/guide/02-architecture.md) before you change a public
contract.

## Rules for code

- Get controls with `Facet.controls(runtime)`. Name the runtime's constructor
  table `Host` (`local Host = runtime.constructors`) and use it for Roblox
  objects.
- Use Compose directly to mount, branch, portal, animate and own resources.
  Do not create a Facet application or a second scene graph.
- Use the native engine mechanisms: layout objects, constraints, text editing,
  scrolling, selection, input contexts, drag detectors and StyleSheets. Put only
  control-specific policy in Facet. Do not rebuild a general engine mechanism.
- The consumer game owns game state and server validation. A Compose component
  owns local state. The model owns durable row state and route state.
- Keep existing control behavior and the actual showcase content. Do not remove
  an example or a behavioral test to hide a regression.
- Write self-documenting source. Do not add explanatory code comments or
  docstrings. Keep compiler and tool directives, executable help text and
  legally required notices.
- Current examples, types, snippets and scaffolding must use the current API.
  There are no deprecated aliases and no compatibility runtime.
- `src/vendor/compose` is a generated, read-only snapshot. Do not edit it.
  `python3 tools/sync_compose.py --check` verifies the pin and the file hashes.
- `Facet.VERSION` is set only in `src/init.luau`. Package publication is a
  separate maintainer release operation. A local build does not publish.

## Rules for evidence

- Verify behavior with meaningful tests. Geometry and input also need live
  Studio evidence. A native engine double does not prove engine behavior.
- Before you propose a completed change, run `tools/verify.sh full`,
  `tools/bench.sh`, `tools/package.sh build` and `tools/package.sh status`.
- Report baseline failures separately from regressions. Do not call a targeted
  run full evidence.
- A passing native `full` run is not equivalent to the historical coverage on
  main. Read the [verification scope](docs/guide/18-verification-scope.md).

## Where to read next

- [Maintainers](docs/MAINTAINERS.md)
- [Choosing controls](docs/guide/14-choosing-controls.md)
- [Components](docs/guide/15-components.md)
- [Device verification](docs/guide/11-device-verification.md)
