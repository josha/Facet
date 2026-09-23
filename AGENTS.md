# Building with Facet

Facet is controls over Compose and Roblox. Read [the API](docs/reference/api.md)
and [architecture](docs/guide/02-architecture.md) before changing a public contract.

- Use `Facet.controls(runtime)` for controls and `runtime.constructors` named
  `Host` for Roblox objects. Mount, branch, portal, animate and own resources using
  Compose directly. Never create a Facet application or a second scene graph.
- Use native layout objects, constraints, text editing, scrolling, selection,
  input contexts, drag detectors and StyleSheets. Keep necessary control-specific
  policy in Facet, without rebuilding a general engine mechanism.
- Game state and server validation belong to the consumer. Local state belongs
  to a Compose component; durable row/route state belongs in the model.
- Maintain existing control behavior and actual showcase content. Do not make
  a regression disappear by deleting its example or behavioral test.
- Source must be self-documenting. No explanatory code comments or docstrings;
  preserve compiler/tool directives, executable help and legally required notices.
  Use `Host` for the Roblox constructor table.
- Current examples, types, snippets and scaffolding must use the current API.
  There are no deprecated aliases or compatibility runtime.
- Verify behavior with meaningful tests and live Studio evidence for geometry
  and input. A native engine double does not prove those engine behaviors.
- Run `tools/verify.sh full`, `tools/bench.sh`, `tools/package.sh build` and
  `tools/package.sh status` before proposing the completed change. Report baseline
  failures separately from regressions. Never label a targeted run full evidence.
- `src/vendor/compose` is a generated, read-only snapshot. Never edit it.
  `python3 tools/sync_compose.py --check` verifies the pin and file hashes.
- `Facet.VERSION` lives only in `src/init.luau`. Package publication is a separate
  maintainer release operation; local builds do not publish.

See [maintainers](docs/MAINTAINERS.md), [controls](docs/guide/14-choosing-controls.md),
[components](docs/guide/15-components.md) and [verification](docs/guide/11-device-verification.md).
