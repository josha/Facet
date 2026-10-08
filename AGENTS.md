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
- Before you write custom code, check in this order:
  1. The Roblox engine API reference in
     [creator-docs](https://github.com/Roblox/creator-docs/tree/main/content/en-us/reference/engine).
     Use the native API first and extend it when it falls short.
  2. Compose (`src/vendor/compose` and its `references/api.md`). Use what it
     already provides. When Compose is the right home for a missing general
     mechanism, add it upstream in [Compose](https://github.com/voidmeld/compose)
     with a pull request, then re-pin with `tools/sync_compose.py`.
  3. Only when neither fits, write custom code in Facet.
  Name the Roblox and Compose APIs you checked and why they did not fit in the
  commit message or receipt.
- Fix a shared cause in Facet itself, not in an example, the lab or one theme's
  numbers.
- Motion timing belongs to the theme. Durations, easings and springs are theme
  tokens, applied through StyleSheet transitions where the engine supports
  them. Do not hard-code a motion value in a control.
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
  Change Compose upstream and re-pin instead.
  `python3 tools/sync_compose.py --check` verifies the pin and the file hashes.
- `Facet.VERSION` is set only in `src/init.luau`. Package publication is a
  separate maintainer release operation. A local build does not publish.

## Rules for evidence

- Default to [Verify](https://github.com/voidmeld/verify) when adding or changing
  tests. Use its public APIs from `tools/vendor/verify` for registration,
  assertions, fixtures, execution and reports. Do not add a Facet test harness.
- Before writing custom testing infrastructure, check Verify's public API and
  consumer skill. If a capability is missing, add it upstream in Verify and
  re-pin with `tools/sync_verify.py` before using it here. Keep only
  Facet-specific cases and integration policy in this repository.
- Declare each producer in `tools/lune/producers.json`. The Verify gate in
  `tools/lune/gate.luau` runs it. Do not add a Facet runner, receipt or verdict.
- Keep `tests/plan.json` aligned with the spec files. The plan lists the spec
  sources. Each spec file on disk must appear exactly once. The `plan` producer
  checks this rule. There is no committed case list. The full gate uses the
  committed plan. A focused run is not full evidence.
- `tools/vendor/verify` is a generated, read-only test dependency. Change shared
  testing mechanisms upstream in `voidmeld/verify`, then re-pin with
  `tools/sync_verify.py`. Keep Verify out of the consumer model.

- Verify behavior with meaningful tests. Geometry and input also need live
  Studio evidence. A native engine double does not prove engine behavior.
- Before you propose a completed change, run `lune run tools/lune/verify full`,
  `lune run tools/lune/bench`, `python3 tools/package.py build` and `python3 tools/package.py status`.
- Report baseline failures separately from regressions. Do not call a targeted
  run full evidence.
- The current suite is the evidence. It does not claim to equal the tests that
  existed before the native cutover. Read the
  [verification scope](docs/guide/18-verification-scope.md).

## Internal showcase review

Before you add a demo, identify its player task and visible result.
Compare its layout and interaction with the other demos.
If it repeats an existing task, improve the existing demo.
Keep the control catalog in the lab.
Use the showcase to show controls in complete tasks.
Do not add unrelated features only to include more controls.
Keep these instructions in internal Facet development files.
Public documents and the consumer skill explain UI use in games.

Check these interactions:

- Open each contextual menu. Check its text, position, and Close action.
- Open child pages at wide and compact sizes. Check motion and Back.
- Check that the root page has no Back command.
- Enter filter text. Press Clear. Check the full collection and the empty result state.
- For each Sheet, compare DisclosureGroup, Popover, and NavigationStack. Select the control that fits the task.
- Keep theme, input, and device settings available during these checks.

Use Simplified Technical English for new documentation.
Keep API names unchanged. Use one term for each technical concept.

## Where to read next

- [Maintainers](docs/MAINTAINERS.md)
- [Choosing controls](docs/guide/14-choosing-controls.md)
- [Components](docs/guide/15-components.md)
- [Device verification](docs/guide/11-device-verification.md)
