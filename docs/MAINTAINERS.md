# Maintaining Facet

This page tells you where a change goes and what proves it. The
[API reference](reference/api.md) holds each public name, property and default.
The [architecture](guide/02-architecture.md) tells you why each boundary
exists. This page does not repeat them.

A check compares each table on this page with the tree. See
[How this page stays true](#how-this-page-stays-true).

## Structure

The public root exports Compose, its Roblox host, the control factory, the
themes and the control types. `src/ui` implements the controls directly over
the supplied runtime. A tool generates `src/vendor/compose`. Do not edit it.

Facet has none of these:

- a client adapter layer,
- a Facet scene,
- a renderer,
- an application,
- a general layout solver,
- a focus graph.

## Areas

Each module under `src/` belongs to one area. The **Owns** column names the
modules. A directory with a trailing slash owns each module in it.

<!-- maintainer-map:areas -->

| Area | Owns | Responsibility | Public seam |
|---|---|---|---|
| **library root** | `src/init.luau`, `src/ui/init.luau`, `src/ui/app.luau`, `src/ui/adaptive.luau`, `src/ui/gamepad_contention.luau`, `src/ui/freeze.luau`, `src/ui/environment.luau`, `src/ui/environment_types.luau`, `src/ui/layout.luau`, `src/ui/layout_kit.luau`, `src/ui/layout_types.luau`, `src/ui/composition.luau`, `src/ui/composition_resolve.luau`, `src/ui/measured_scroll.luau`, `src/ui/scroll_lock.luau`, `src/ui/scroll_chain.luau`, `src/ui/scrolling.luau`, `src/ui/scroll_initial.luau` | Exports the public table and the public types. Assembles the control families into one frozen controls table for each runtime. Holds the layout primitives, scrolling, the adaptive facts and the app mount. | `Facet.VERSION`, `Facet.controls`, `Facet.bind` |
| **Compose snapshot** | `src/vendor/compose/` | The pinned Compose reactive runtime and its Roblox host. Generated. Do not edit it. | `Facet.Compose`, `Facet.Roblox` |
| **control context** | `src/ui/context.luau`, `src/ui/types.luau`, `src/ui/engine_types.luau`, `src/ui/control_types.luau`, `src/ui/help.luau`, `src/ui/native_decoration.luau`, `src/ui/geometry_observation.luau`, `src/ui/arithmetic.luau`, `src/ui/motion.luau`, `src/ui/rest.luau`, `src/ui/font_readiness.luau`, `src/ui/settle.luau`, `src/ui/selection.luau`, `src/ui/reserved_keys.luau`, `src/ui/text_press.luau`, `src/ui/segment_metrics.luau`, `src/ui/drag.luau`, `src/ui/drag_types.luau`, `src/ui/drag_pointer.luau`, `src/ui/drag_session.luau`, `src/ui/drag_travel.luau`, `src/ui/gesture_arbitration.luau`, `src/ui/gesture_service.luau`, `src/ui/text_reveal.luau`, `src/ui/preferred_input.luau` | The shared context for each runtime and the shared types. It also holds the help text, the text reveal, drag and drop, native decoration, batched geometry observations, the modifier-key hold on `PreferredInput`, the Tab and Escape dispatch shared per `UserInputService` (`reserved_keys.luau`), the layout rest tracker (`rest.luau`) and the velocity-seeded settle (`settle.luau`). | None. The families receive it from the library root. |
| **inputs** | `src/ui/inputs.luau`, `src/ui/command_scope.luau`, `src/ui/command_types.luau`, `src/ui/feedback_paint.luau`, `src/ui/input_value.luau`, `src/ui/input_types.luau`, `src/ui/slider.luau`, `src/ui/text_field.luau`, `src/ui/field_chrome.luau`, `src/ui/color_picker.luau`, `src/ui/color_picker_types.luau`, `src/ui/color_value.luau`, `src/ui/date_time_picker.luau`, `src/ui/date_time_picker_types.luau`, `src/ui/civil_date.luau`, `src/ui/civil_date_types.luau` | Buttons, toggles, text input, steppers, sliders, ratings, level pickers, chips and shortcut hints. | None. Reach it through `Facet.controls`. |
| **navigation** | `src/ui/nav_modal.luau`, `src/ui/nav_menu.luau`, `src/ui/nav_surfaces.luau`, `src/ui/nav_pages.luau`, `src/ui/nav_path_shapes.luau`, `src/ui/navigation_types.luau`, `src/ui/navigation_split_view.luau` | Menus, pickers, presented surfaces, tab views, navigation stacks and page views. | None. Reach it through `Facet.controls`. |
| **overlays** | `src/ui/nav_dialog.luau`, `src/ui/nav_popover.luau`, `src/ui/nav_sheet.luau`, `src/ui/nav_notice.luau`, `src/ui/overlay_parts.luau`, `src/ui/materialize.luau`, `src/ui/overlay_placement.luau`, `src/ui/overlay_types.luau`, `src/ui/sheet_release.luau`, `src/ui/reservations.luau`, `src/ui/activation.luau`, `src/ui/nav_toast.luau`, `src/ui/toast_schedule.luau` | Dialogs, popovers, sheets, snackbars, toasts, notices, the navigation bar, the shared placement and the layer insets. | None. Reach it through `Facet.controls`. |
| **radial** | `src/ui/nav_radial.luau`, `src/ui/nav_radial_geometry.luau`, `src/ui/radial_types.luau` | The radial menu and its geometry. | None. Reach it through `Facet.controls`. |
| **collections** | `src/ui/collections.luau`, `src/ui/collection_policy.luau`, `src/ui/collection_paint.luau`, `src/ui/collection_tree.luau`, `src/ui/collection_selection.luau`, `src/ui/collection_reorder.luau`, `src/ui/collection_snap.luau`, `src/ui/collection_row_actions.luau`, `src/ui/collection_table.luau`, `src/ui/collection_table_editors.luau`, `src/ui/collection_types.luau` | Keyed and virtual collections, animated hierarchies, selection, reorder, snap, row actions, reusable CellEditor drafts and tables. | None. Reach it through `Facet.controls`. |
| **media** | `src/ui/media.luau`, `src/ui/media_readiness.luau`, `src/ui/media_types.luau`, `src/ui/rich_text.luau` | Labels, badges, status, progress, skeletons, images, avatars, stages, paths and rich text escaping. | `Facet.richText`, `Facet.pathShapes`, or through `Facet.controls`. |
| **content** | `src/ui/pagination.luau`, `src/ui/pagination_window.luau`, `src/ui/step_indicator.luau`, `src/ui/vote.luau`, `src/ui/card.luau`, `src/ui/badge_seal.luau`, `src/ui/content_values.luau`, `src/ui/content_types.luau` | Pagination, step indicators, votes, cards, and the checks that keep the last legal value. | None. Reach it through `Facet.controls`. |
| **effects** | `src/ui/effect_types.luau`, `src/ui/effect_sequence.luau`, `src/ui/effect_flash.luau` | Ordered effect policy, numeric motion and transient GUI paint. | Through `Facet.controls`. |
| **zoom and travel** | `src/ui/zoom_view.luau`, `src/ui/zoom_geometry.luau`, `src/ui/travel.luau`, `src/ui/travel_engine.luau`, `src/ui/travel_geometry.luau`, `src/ui/zoom_travel_types.luau` | Board zoom, pan, focus limits and travel between native containers. | None. Reach it through `Facet.controls`. |
| **themes** | `src/ui/themes.luau`, `src/ui/theme_types.luau`, `src/ui/theme_distance.luau`, `src/ui/icons.luau` | Theme packages, their compilation to native StyleSheets, the ten-foot metric ladder, chrome skins and the standard icons. | `Facet.themes` |

## Proof

The same areas, in the same order. The **Tests** column names entry specs. It
does not name each spec. A spec covers an area when one of its own `require`
calls names a module of that area. A spec that requires only `src` or `src/ui`
covers the library root. To see the number of specs for each area, run
`lune run tools/lune/check_maintainer_map_cli --counts`.

<!-- maintainer-map:proof -->

| Area | Tests | Studio scenario | Extend via |
|---|---|---|---|
| **library root** | `tests/lab_loader.spec.luau`, `tests/native_public_surface.spec.luau`, `tests/native_compose_contract.spec.luau`, `tests/native_compose_binding.spec.luau`, `tests/native_navigation.spec.luau`, `tests/native_radial_controls.spec.luau` | `all_controls` | [Adding a control](extending/new-control.md) |
| **Compose snapshot** | `tests/native_themes_media.spec.luau`, `tests/native_perf_runner.spec.luau` | `component_motion` | [Adopting an engine feature](extending/new-engine-feature.md). Change Compose upstream. Then run `python3 tools/sync_compose.py`. |
| **control context** | `tests/native_registration.spec.luau`, `tests/native_inputs.spec.luau`, `tests/gesture_arbitration.spec.luau`, `tests/container_transfer.spec.luau` | `all_controls` | [Native primitives](extending/new-primitive.md) |
| **inputs** | `tests/command_scope.spec.luau`, `tests/native_inputs.spec.luau`, `tests/native_collections.spec.luau` | `action_controls`, `text_controls` | [Adding a control](extending/new-control.md) |
| **navigation** | `tests/native_collections.spec.luau` | `menu`, `navigation_stack`, `sheet`, `alert` | [Adapting to another platform context](extending/new-platform-mode.md) |
| **overlays** | `tests/native_dialog.spec.luau`, `tests/native_popover.spec.luau`, `tests/native_sheet_parts.spec.luau`, `tests/native_toast_action.spec.luau`, `tests/native_notice_navbar.spec.luau`, `tests/native_callout_help.spec.luau`, `tests/sheet_release.spec.luau` | `overlays`, `notice`, `sheet` | [Adding a control](extending/new-control.md) |
| **radial** | `tests/radial_geometry.spec.luau`, `tests/native_collections.spec.luau` | `radial_menu` | [Adding a control](extending/new-control.md) |
| **collections** | `tests/native_collections.spec.luau` | `collections`, `table_virtualized`, `row_actions` | [Adding a control](extending/new-control.md) |
| **media** | `tests/native_themes_media.spec.luau` | `async_images`, `avatar`, `badge` | [Mounting into native targets](extending/new-render-target.md) |
| **content** | `tests/native_pagination.spec.luau` | `paging`, `steps` | [Adding a control](extending/new-control.md) |
| **effects** | `tests/effect_sequence.spec.luau` | None — use the reward_sequence live suite and Lab page. | [Adding a control](extending/new-control.md) |
| **zoom and travel** | `tests/zoom_travel.spec.luau` | None — use the zoom and travel live suite and Lab pages. | [Adding a control](extending/new-control.md) |
| **themes** | `tests/native_themes_media.spec.luau`, `tests/native_themes_media.spec.luau` | `all_controls` | [Adding a theme package](extending/new-theme.md) and [Adding artwork to a control](extending/skinned-control.md) |

## Repository

Each top-level directory has one row. The tree table does not list the
directories that `.gitignore` excludes.

<!-- maintainer-map:tree -->

| Directory | Holds | Check |
|---|---|---|
| `src/` | The library. See [Areas](#areas). | `lune run tools/lune/verify full` |
| `tests/` | The behavioral specs, the native engine double and the type witnesses. | `lune run tools/lune/verify spec <spec-name>` |
| `examples/` | The gallery, the Facet Lab, the consumer project, the reference apps, the virtual monitors, the example themes and the performance lab. | `lune run tools/lune/check_scenario_requires_cli` |
| `bench/` | The benchmark scenes, profiles and baselines. | `lune run tools/lune/bench` |
| `tools/` | The verification runner, the checkers, the build scripts and the Studio tools. | `python3 tools/strip_comments.py --check` |
| `docs/` | The guide, the extension playbooks, the reference, this map and the historical plans. | `python3 tools/check_doc_style.py` |
| `assets/` | The icon images and the theme art. The package build includes them. | `python3 tools/package.py build` |
| `package/` | The Roblox Package configuration and the publish receipts. See [the package interface](../package/README.md). | `python3 tools/package.py status` |
| `skills/` | The agent skills for Compose and for Facet. | None. A reviewer reads them with the guide. |

## Quick answers

<!-- maintainer-map:quick -->

| Question | Answer | Read |
|---|---|---|
| Where does a new control go? | In the area of its family, under `src/ui/`. | [Adding a control](extending/new-control.md) |
| How do I change the look? | Change or derive a theme package. Do not change a control. | [Custom themes](guide/09-custom-themes.md) |
| How do I change Compose? | Change Compose upstream. Then update the pinned snapshot. | [Adopting an engine feature](extending/new-engine-feature.md) |
| What does a passing native run prove? | Only that the selected commands passed. | [Verification scope](guide/18-verification-scope.md) |
| How do I release? | The maintainer publishes. A change only builds the package locally. | [The package interface](../package/README.md) |

## Controls

A control implementation consumes its behavioral options. It forwards native
properties, event keys, attributes and children unchanged. The common private
helpers only make native components or observe native properties. They do not
own a runtime, a frame loop or an application lifetime.

## Themes

Theme definitions compile to native StyleSheets. The callers own the
StyleLinks. Do not write explicit default paint properties that hide the
stylesheet rules.

## Evidence

Control policy tests use a native engine double. Geometry, hit testing,
Input Method Editor (IME) text, scrolling and input eligibility need live
Studio evidence. The live runner uses Verify to produce case reports.
Hand-written observations do not replace those reports. The `plan` producer
checks that `tests/plan.json` lists each spec file on disk exactly once. When
you retire tests of removed mechanisms, keep the behavior coverage of each control family.
The current suite is the evidence. It does not claim to equal the tests that
existed before the native cutover. The
[verification scope](guide/18-verification-scope.md) describes the checks and
their limits.

Read the [contributor workflow](../CONTRIBUTING.md), the
[API reference](reference/api.md) and the
[control playbook](extending/new-control.md).

## How this page stays true

Run `lune run tools/lune/check_maintainer_map_cli`. It reads the tree and this
page, and it fails when they disagree. Run it with `--list` to see each rule.
Run it with `--selftest` to see each rule fail on a planted fault.
