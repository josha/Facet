# Facet maintainer map

This page answers one question: **where does a change go, and what proves it?**

It is a map, not a catalog. Every public name, property and default lives in
[`reference/api.md`](reference/api.md), and the guide index carries the
[capability catalog](guide/README.md). Nothing here repeats them. What is here is
the ownership layer that a reference cannot express: which area owns a job, which
seam other code is allowed to reach, which direction a dependency may point, which
specs cover it, which Studio fixture shows it running, which gate row pins it, and
which playbook to follow when you extend it.

Read [`guide/02-architecture.md`](guide/02-architecture.md) first if you have never
seen the codebase. It explains *why* the boundaries below exist. This page assumes
you already believe in them and just need to know where to type.

Every fact in the two tables is checked against the place it came from. See
[section 4](#4-how-this-file-stays-true) for the rules and the command.

## 1. The areas

Nineteen areas cover every top-level entry under `src/`. The **owns** column is the
key: each `src/` entry belongs to exactly one area, and the drift check reads the
tree to prove it.

<!-- maintainer-map:areas -->

| Area | Owns | Responsibility | Public seam | Internal owner modules |
|---|---|---|---|---|
| **core** | `src/core/` | The reactive runtime: signals, memos, observers, effects, transactions and scopes. No engine, no layout. | `Facet.newCore` | `src/core/custom.luau`, `src/core/scope_impl.luau`, `src/core/contract.luau`, `src/core/profile.luau` |
| **blueprint** | `src/blueprint.luau`, `src/blueprint_schema.luau`, `src/class_contract.luau`, `src/spec_guard.luau` | The declarative constructors and the closed key schema every public spec is judged against. Produces frozen data only. | `Facet.UI` | `src/blueprint.luau`, `src/blueprint_schema.luau`, `src/class_contract.luau`, `src/spec_guard.luau` |
| **mount** | `src/mount.luau` | Turns a blueprint into a live mounted node graph, runs each setup once, and records what changed in the dirty queue. | `Facet.mount` | `src/mount.luau` |
| **layout** | `src/layout/`, `src/region_expand.luau`, `src/measure.luau` | Pure two-pass geometry. A tree snapshot and a viewport go in, a rectangle per node comes out. It reads no signal and no instance. | `Facet.adaptive`, `Facet.composition`, `Facet.text` — plus the sibling instance `ReplicatedStorage.Facet.measure` (not a `Facet` table member: framework-gaps-phase2 gap 11's headless entry point, a standalone republish of `text_metrics.luau` reached WITHOUT running `src/init.luau`'s 65 `@self` requires; see [api.md](reference/api.md#measure--the-headless-entry-point-framework-gaps-phase2-gap-11)) | `src/layout/solver.luau`, `src/layout/text_metrics.luau`, `src/layout/text_fit.luau`, `src/layout/composition.luau` |
| **render** | `src/render/` | Walks the mounted graph, runs the solver, drives a render-target adapter, and enforces one property authority per engine property. | `Facet.renderer` | `src/render/renderer.luau`, `src/render/authority.luau`, `src/render/target_contract.luau`, `src/render/layout_node.luau` |
| **controls** | `src/controls/`, `src/row_capability.luau`, `src/virtual_extents.luau` | Composite controls assembled out of the primitive blueprints. Nothing here reaches past the public constructors. | `Facet.Controls` | `src/controls/table.luau`, `src/controls/virtual_list.luau`, `src/controls/row_actions.luau`, `src/controls/menu.luau` |
| **present** | `src/present/` | Whole screens and modals: their lifetimes, focus scopes, input contexts, and the frame the renderer is driven from. | `Facet.newPresenter` | `src/present/presenter.luau`, `src/present/focus_map.luau`, `src/present/toast_schedule.luau`, `src/present/with_animation.luau` |
| **input** | `src/input/` | The engine-free action, binding and context model, plus gestures, drag sessions and edge autoscroll. | `Facet.newActionSystem`, `Facet.newDragSession`, `Facet.touchGestures`, `Facet.spatial` | `src/input/actions.luau`, `src/input/drag_session.luau`, `src/input/touch_gestures.luau`, `src/input/contribution.luau` |
| **focus** | `src/focus/` | Logical focus identity and navigation: flat rings, navigation groups, and document-order traversal. | `Facet.newFocusGraph` | `src/focus/focus_graph.luau` |
| **motion** | `src/motion/` | The motion authority: injectable clocks, springs, curves, timelines, and the reduced-motion rules. | `Facet.motion` | `src/motion/clock.luau`, `src/motion/spring.luau`, `src/motion/curves.luau`, `src/motion/timeline.luau` |
| **tokens** | `src/tokens/` | Design-token compilation, the built-in look, the native style-sheet rule model, and the decoration-slot vocabulary. | `Facet.tokens` | `src/tokens/tokens.luau`, `src/tokens/styling.luau`, `src/tokens/sheet_model.luau`, `src/tokens/chrome_slots.luau` |
| **themes** | `src/themes/` | Theme packages: the pure compiler for the versioned schema, and the frozen snapshot that is the one metric authority. | `Facet.themes` | `src/themes/package.luau`, `src/themes/snapshot.luau`, `src/themes/token_sync.luau`, `src/themes/standard_icons.luau` |
| **env** | `src/env/` | Per-device facts as observable values, plus the derived policy: interaction classes, distance profile, safe insets. | `Facet.newEnvironment` | `src/env/environment.luau`, `src/env/safe_insets.luau`, `src/env/surface_env.luau` |
| **async** | `src/async/` | Bounded, cancellable loading with a cache and stale-response rejection. | `Facet.newResourceProvider` | `src/async/resources.luau` |
| **replication** | `src/replication/` | Receiving server-owned state as snapshots and collections, and sending validated mutations back. | `Facet.replication` | `src/replication/adapters.luau` |
| **client** | `src/client/` | The only code that touches Roblox instances, real input and real device facts. Client-only, and the one place a consumer may require past the root. | The blessed client modules, listed in [api.md](reference/api.md#client-entry-points) | `src/client/host.luau`, `src/client/screen_target.luau`, `src/client/roblox_env.luau`, `src/client/roblox_input.luau`, `src/client/theme_controller.luau` |
| **preview** | `src/preview/` | Device-profile presets and matrix rows, so the real solver renders what a named device class would see. | None: reached through `src/client/edit_preview.luau` | `src/preview/device_profiles.luau`, `src/preview/matrix_rows.luau` |
| **shared helpers** | `src/num.luau`, `src/paths.luau`, `src/rect.luau`, `src/text_distance.luau` | One home each for a predicate that every other area had copied: finiteness, node-path prefixes, rectangle algebra, near-miss suggestions. | None: internal | `src/num.luau`, `src/paths.luau`, `src/rect.luau`, `src/text_distance.luau` |
| **library root** | `src/init.luau` | The one public table. It assembles every export, freezes the control namespace, and publishes the deprecation ledger. | `Facet` itself | `src/init.luau` |

## 2. How each area is held true

Same nineteen areas, same order. The **may depend on** column names the rule that
enforces the direction where one exists; those names are the rules
[`tools/lune/check_boundary.luau`](../tools/lune/check_boundary.luau) reports, and
the drift check refuses a name that module does not use.

The **tests** column names entry-point specs, never the whole set. Coverage is
derived, not listed: a spec covers an area when one of its own `require` calls
names a module of that area. Run
`lune run tools/lune/check_maintainer_map_cli -- --counts` for the live per-area
number. A spec that reaches the library only through `require("../src")` counts
under the library-root row, which is why the reactive-recovery and quarantine
specs appear there rather than under core.

<!-- maintainer-map:proof -->

| Area | May depend on | Tests | Studio scenario | Gate | Extend via |
|---|---|---|---|---|---|
| **core** | Nothing but itself. Engine-free, and the vendored engine modules are refused by `engine-free-zone-requires-engine-vendor`. | `tests/conformance/conformance.spec.luau`, `tests/profile_scopes.spec.luau`, `tests/measure_publish_settle.spec.luau`, `tests/session_lifetime.spec.luau` | `branch_scope` | `phase-0-foundation/conformance-custom-core` | Internal. Change it under [the constitution](reference/constitution.md) and record the decision in [the changelog](../CHANGELOG.md) |
| **blueprint** | core, and the shared helpers. Never render, never client (`non-client-requires-client`). | `tests/api_surface.spec.luau`, `tests/authoring.spec.luau`, `tests/controls_conformance.spec.luau`, `tests/layout_vocabulary.spec.luau` | `authoring` | `authoring-adaptive-ui/strict-authoring`, `authoring-adaptive-ui/one-property-model` | [Adding a blueprint primitive](extending/new-primitive.md) |
| **mount** | core and blueprint. It never reads geometry and never writes an instance. | `tests/mount.spec.luau`, `tests/error_boundary.spec.luau`, `tests/lifecycle_hooks.spec.luau`, `tests/virtualization.spec.luau` | `lifecycle_hidden` | `phase-1-minimal-screen/no-factory-rerun-trace` | Internal. Change it under [the constitution](reference/constitution.md) |
| **layout** | The shared helpers and its own text metrics. It may not require core: a solve runs on a frozen snapshot. | `tests/layout.spec.luau`, `tests/text_fit.spec.luau`, `tests/measure_memo.spec.luau`, `tests/region_expand.spec.luau` | `composition` | `authoring-adaptive-ui/adaptive-layout` | [Adding a blueprint primitive](extending/new-primitive.md) for a new box; otherwise [the constitution](reference/constitution.md) |
| **render** | core, blueprint, mount, layout, tokens, themes. Never client (`non-client-requires-client`): it talks to the screen only through the target contract. | `tests/renderer.spec.luau`, `tests/render_target_contract.spec.luau`, `tests/presentation_channel.spec.luau`, `tests/styling.spec.luau` | `nested_compositing` | `phase-0-foundation/property-authority-spike`, `native-stylesheets/adapter-native-mode` | [Adding a render target](extending/new-render-target.md), or [adopting an engine feature](extending/new-engine-feature.md) |
| **controls** | blueprint, core, input, focus, motion, layout, themes. Only the public constructors, never the renderer's internals. | `tests/table.spec.luau`, `tests/virtual_list_axis.spec.luau`, `tests/controls_conformance.spec.luau`, `tests/row_capability_optouts.spec.luau`, `tests/virtual_extents.spec.luau` | `table_virtualized` | `authoring-adaptive-ui/value-controls`, `navigation-and-menus/d5-tabview` | [Adding a composite control](extending/new-control.md), then `lune run tools/lune/scaffold_cli control <name>` |
| **present** | core, blueprint, mount, render, input, focus, env, motion. Never client. | `tests/presenter.spec.luau`, `tests/toast_schedule.spec.luau`, `tests/help.spec.luau`, `tests/anchored_surface.spec.luau` | `menu` | `phase-1-minimal-screen/modal-context-priority-sink-disposal`, `navigation-and-menus/d1-anchored-surface`, `sponsor-framework-gaps/toast-presentation` | Internal. Change it under [the constitution](reference/constitution.md) |
| **input** | core and the shared helpers. It models input; it never reads a real device. | `tests/input.spec.luau`, `tests/drag_session.spec.luau`, `tests/touch_gestures.spec.luau`, `tests/autoscroll.spec.luau` | `drag_session` | `input-adaptation-audit/per-control-per-input-conformance`, `input-adaptation-audit/first-responder-model`, `sponsor-framework-gaps/drag-public-contract` | [Adding a platform capability or interaction mode](extending/new-platform-mode.md) |
| **focus** | core only. | `tests/focus.spec.luau`, `tests/navigation_groups.spec.luau`, `tests/traversal_order.spec.luau`, `tests/focus_grid_axis.spec.luau` | `keyboard_navigation` | `traversal-document-order/document-order-traversal`, `desktop-keyboard-navigation/traversal-pure` | Internal. Change it under [the constitution](reference/constitution.md) |
| **motion** | core and the shared helpers. Its clock is injected, so nothing here reads real time. | `tests/motion_spring.spec.luau`, `tests/motion_timeline.spec.luau`, `tests/value_reveal.spec.luau` | `with_animation` | `sponsor-framework-gaps/motion-authority` | Internal. Change it under [the constitution](reference/constitution.md) |
| **tokens** | The shared helpers, and the theme snapshot for metrics. Never client. | `tests/styling.spec.luau`, `tests/sheet_model.spec.luau`, `tests/theme_chrome.spec.luau`, `tests/chrome_padding_refit.spec.luau` | `native_style` | `native-stylesheets/sheet-model-headless`, `native-stylesheets/seed-once-materializer`, `rich-skinning-v2/layered-slots-and-posture` | [Adopting an engine feature](extending/new-engine-feature.md) for a new paint property |
| **themes** | tokens, env and the shared helpers. Engine-free on purpose, so it is safe in a shared require graph; the controller that materializes sheets lives in client. | `tests/theme_package.spec.luau`, `tests/theme_snapshot.spec.luau`, `tests/theme_layers.spec.luau`, `tests/theme_icons.spec.luau` | `theme_authoring` | `theme-packages-and-skinning/theme-package-contract`, `rich-skinning-v2/state-variant-assets`, `rich-skinning-v2/semantic-icons` | [Adding or extending a theme](extending/new-theme.md), or [a control that ships its own art](extending/skinned-control.md) |
| **env** | core and the shared helpers. It publishes facts; `src/client/roblox_env.luau` is what reads them off the engine. | `tests/platform_env_binding.spec.luau`, `tests/adaptive.spec.luau`, `tests/ten_foot_metrics.spec.luau`, `tests/paradigm_tenfoot.spec.luau` | `safe_area` | `input-paradigms/affordance-matrix`, `native-substrate/safe-area-adoption`, `cross-platform-proof/console-tenfoot-profile` | [Adding a platform capability or interaction mode](extending/new-platform-mode.md) |
| **async** | core only. Nothing here knows what a request is made of. | `tests/async_completeness.spec.luau`, `tests/async_image.spec.luau`, `tests/session_lifetime.spec.luau` | `async_images` | `native-substrate/resource-transport`, `sponsor-framework-gaps/async-avatars` | Internal. Change it under [the constitution](reference/constitution.md) |
| **replication** | core only, and it is held to the engine-free zone by `engine-free-zone-requires-engine-vendor`. | `tests/replication.spec.luau`, `tests/platform_adapters_recovery.spec.luau` | `examples` | `phase-0-foundation/replication-boundary-spike`, `phase-2-settings-parity/replication-convergence-carryover`, `phase-4-hardening/fuzz-replication` | Internal. Change it under [the constitution](reference/constitution.md) |
| **client** | Every engine-free area. Nothing outside it may require it (`non-client-requires-client`), and a consumer reaching past the blessed list is caught by `consumer-requires-facet-internal`. | `tests/client_host.spec.luau`, `tests/platform_env_binding.spec.luau`, `tests/theme_controller.spec.luau`, `tests/pointer_seam_ownership.spec.luau`, `tests/haptics.spec.luau` | `scroll_host`, `outpost_terminal` | `phase-0-foundation/client-boundary-static`, `native-substrate/scroll-host-adoption`, `part-2-director/ws3-billboard-target` | [Adding a render target](extending/new-render-target.md), or [adopting an engine feature](extending/new-engine-feature.md) |
| **preview** | core and env. Engine-free, so the harness and the durable plugin share one source of profiles. | `tests/preview.spec.luau`, `tests/matrix_rows.spec.luau` | `perf_capture` | `part-2-director/ws2-edit-preview-harness`, `cross-platform-proof/matrix-five-views-driven` | Internal. Change it under [the constitution](reference/constitution.md) |
| **shared helpers** | Nothing. They are pure functions, which is the whole point of extracting them. | `tests/leaf_helpers.spec.luau`, `tests/text_distance.spec.luau` | none — pure arithmetic with no live surface; it is proved headless and read through the areas that call it | `code-simplicity-cleanup/public-surface-unchanged`, `release-candidate-review/reuse-consolidation` | Internal. Change it under [the constitution](reference/constitution.md) |
| **library root** | Everything. Nothing under `src/` may require it back: that is a cycle, and `src-module-requires-library-root` refuses it. | `tests/smoke.spec.luau`, `tests/controls_namespace.spec.luau`, `tests/reactive_recovery.spec.luau`, `tests/runtime_quarantine.spec.luau`, `tests/spec_guard_sweep.spec.luau` | `examples` | `api-architecture-consistency/surface-ledger-complete`, `release-candidate-review/naming-adr-implemented`, `release-candidate-review/guide-catalog-current` | [The constitution](reference/constitution.md) governs the shape of anything added here |

## 3. Where does it belong?

<!-- maintainer-map:quick -->

| I want to add … | It belongs in | Follow |
|---|---|---|
| a **control** | `src/controls/`, composed from public `UI.*` primitives, exported through `src/init.luau` | [new-control.md](extending/new-control.md), then `lune run tools/lune/scaffold_cli control <name>` |
| a **primitive** (a new kind of box the target materializes) | `src/blueprint.luau` plus its schema row, its class contract, and every target | [new-primitive.md](extending/new-primitive.md) |
| a **layout** container or arrangement rule | `src/layout/solver.luau` for the arithmetic, `src/blueprint_schema.luau` for the props that reach it | [new-primitive.md](extending/new-primitive.md) and [guide 02](guide/02-architecture.md#24-why-the-boundaries-exist) |
| a **modifier** | `src/blueprint.luau` for the constructor, `src/blueprint_schema.luau` for the closed key, `src/tokens/styling.luau` for the normalized value | [guide 05](guide/05-styling.md) |
| an **engine property** | `src/render/authority.luau` declares the one owner, `src/client/screen_target.luau` materializes it, `src/render/style_lint.luau` refuses misuse | [new-engine-feature.md](extending/new-engine-feature.md) |
| a **render target** | A new adapter satisfying `src/render/target_contract.luau`; nothing in `src/render/` changes | [new-render-target.md](extending/new-render-target.md), then `lune run tools/lune/scaffold_cli adapter <name>` |
| an **input behavior** | `src/input/` for the model, `src/client/roblox_input.luau` for the real device, never both | [new-platform-mode.md](extending/new-platform-mode.md) and [guide 07](guide/07-input.md) |
| a **theme feature** | `src/themes/package.luau` for the schema and compiler, `src/tokens/` for what it compiles to | [new-theme.md](extending/new-theme.md), or [skinned-control.md](extending/skinned-control.md) for a control with its own art |
| a **device or platform fact** | `src/env/environment.luau` publishes it, `src/client/roblox_env.luau` reads it off the engine | [new-platform-mode.md](extending/new-platform-mode.md) |
| an **example** | `examples/gallery/examples/` for a tutorial, `examples/reference/` for a whole application | [guide 04](guide/04-tutorial-examples.md) |
| a **Studio scenario** | `examples/gallery/scenarios/`, registered in that folder's `init.luau` order | [guide 11](guide/11-device-verification.md) |
| a **test helper** | `tests/lib/` for a shared fake or fixture, `tests/fixtures/` for shared data | [guide 02](guide/02-architecture.md#23-extension-points) |
| a **checker** | `tools/lune/` for a Luau check, `tools/` for a Python check; give it a failing case | [section 4](#4-how-this-file-stays-true) |

## 4. How this file stays true

Three rules keep the map from rotting, and one command proves them.

**Derive, do not duplicate.** Anything the build already knows is read from the
build. The area list is read from `src/`. Coverage is read from the require graph.
Gate rows are read from the manifest. Dependency rules are read from the boundary
checker. Scenario names are read from the scenario index. The map holds the
*mapping*, and nothing else.

**No second catalog.** Public names, properties, defaults and return values belong
to [`reference/api.md`](reference/api.md), and the shipped capability list belongs
to the [guide index](guide/README.md). If you find yourself typing a property name
here, you are writing the wrong document.

**No number you would have to maintain.** Counts drift silently, so this page
carries none of them: not a spec count, not a control count, not the size of the
blessed client list. Ask the tool instead:

```sh
lune run tools/lune/check_maintainer_map_cli -- --counts
```

**The drift check.** One command checks every row against its source:

```sh
lune run tools/lune/check_maintainer_map_cli              # check the live map
lune run tools/lune/check_maintainer_map_cli -- --list    # what it enforces
lune run tools/lune/check_maintainer_map_cli -- --selftest # prove each rule bites
```

It fails when a new `src/` area is unmapped, when a claimed path does not exist,
when the two tables disagree, when a named spec does not require the area it is
filed under, when a scenario is unregistered, when a cited gate row or boundary
rule is gone, when the seam column advertises an export the library table no longer
has, when a link breaks, or when an extension playbook ships that the map never
links. The selftest plants each of those faults into a copy of this file in a
scratch directory and requires each one to be reported, so the check has been
watched failing before it is trusted. The same checker runs inside the suite as
[`tests/maintainer_map.spec.luau`](../tests/maintainer_map.spec.luau), so drift
fails the suite and not only a command someone remembered to type.

## 5. Which verification tier proves it

The **Tests** column above names where a change is covered. This section names
what to run, and it is the same four tiers a contributor uses
([`../CONTRIBUTING.md`](../CONTRIBUTING.md)):

```sh
tools/verify.sh affected     # the smallest safe set for the files you changed
tools/verify.sh fast         # the inner-loop tier
tools/verify.sh full         # every deterministic check, exactly once
tools/verify.sh release      # full, plus the build, package and evidence producers
```

Three rules decide which one a piece of work owes.

**Work in affected or fast; propose on full.** The two working tiers exist to be
fast, and their output says so. A result from either is not evidence that a
change is ready, and the tool refuses to let one read as the other.

**Release belongs to a release.** That tier runs the producers that build
artifacts, verify the distributable package, and gather recorded evidence. It is
run by the person cutting a release, at an exact commit, and not on an ordinary
change.

**The tier is not the whole bar for anything a player can see.** A headless run
cannot see engine frame work, paint, or a real device.
[`guide/11-device-verification.md`](guide/11-device-verification.md) names which
instrument can close which kind of claim, and each extension playbook's §6 names
the live Roblox check its area owes.

Two loops sit underneath the tiers and are worth keeping in the fingers:
`lune run tests/run_one <spec-name>` runs one spec file and is how a new check is
watched failing before it is trusted, and `./run-tests.sh` still runs the
complete suite exactly as it always has.
