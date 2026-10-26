# Maintaining Facet

This page tells you where a change goes and what proves it. The
[API reference](reference/api.md) holds each public name, property and default.
The [architecture](guide/architecture.md) tells you why each boundary
exists. This page does not repeat them.

A check compares each table on this page with the tree. See
[How this page stays true](#how-this-page-stays-true).

## Documentation nodes

`facet docs` derives its index from Markdown files in `docs/reference/nodes`.
The file name without `.md` is the query path. `Map` is the map. `Tasks.*`
nodes are recipes. `*.card` nodes are control cards. `Controls`, `Controls.N`,
`Tasks`, `Reference`, `*.index` and `Themes.*.tokens` are indexes. Other names
that start with a letter and contain only letters, digits, dots, underscores
or hyphens are details. Use `<!-- kind: index -->` for an index whose name
does not identify its kind.

Each node needs a title and a short first sentence. The first sentence is its
search summary. Links to nodes supply children in source order. Repeated links
remain in that order. Code examples and external links do not supply children.
Control cards derive their aliases from the control name and `UI.` plus that
name. Keep other search aliases on one line:
`<!-- aliases: first name | second name -->`.
An exact control card or path takes priority over an alias. A shared alias
selects the shortest path.

`docs-nodes` checks titles, kinds, summaries, source byte budgets and
reachability from `Map`. Marker lines count toward the source byte budget.
Queries omit marker lines and keep the response byte limit.
It also compares `docs/reference/nodes/Icons.names.md` with the icon registry
and the glyph uses in `tools/facet/lib/docs_props.luau`. Run
`lute run tools/facet check docs-nodes --write` to write the node again.

`docs <Control>.props` derives option names and types from the public property
types. It works in the repository and in an author kit. Lowercase fields are
Facet options. Native properties keep their engine names. The output marks
required inputs, known defaults and omitted inputs that use control or theme
policy. A control name with an unknown option selects its `.props` list.

`docs-samples` type-checks every Luau fence in task recipes and control cards.
It adds strict mode and the app mount context for a card. It uses the same
consumer analyzer, solver flags and pinned Roblox definitions as `facet verify`.
Failures name the Markdown file and source line.

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
| **spatial presentation** | `src/ui/diegetic_screen.luau`, `src/ui/diegetic_geometry.luau`, `src/ui/diegetic_types.luau` | Reversible presentation of existing application layers on native world surfaces. | `UI.DiegeticScreen` |
| **library root** | `src/init.luau`, `src/ui/init.luau`, `src/ui/app.luau`, `src/ui/adaptive.luau`, `src/ui/gamepad_contention.luau`, `src/ui/freeze.luau`, `src/ui/environment.luau`, `src/ui/environment_types.luau`, `src/ui/layout.luau`, `src/ui/layout_kit.luau`, `src/ui/layout_types.luau`, `src/ui/layout_props.luau`, `src/ui/glass.luau`, `src/ui/composition.luau`, `src/ui/composition_resolve.luau`, `src/ui/region_presence.luau`, `src/ui/extent_match.luau`, `src/ui/size_floor.luau`, `src/ui/measured_scroll.luau`, `src/ui/scroll_lock.luau`, `src/ui/scroll_chain.luau`, `src/ui/scrolling.luau`, `src/ui/scroll_initial.luau` | Exports the public table and the public types. Assembles the control families into one frozen controls table for each runtime. Holds the layout primitives, scrolling, the adaptive facts and the app mount. | `Facet.VERSION`, `Facet.controls`, `Facet.bind` |
| **design library** | `src/design/init.luau`, `src/design/library.luau`, `src/design/types.luau`, `src/design/controls.luau`, `src/design/fields.luau` | The Facet library for Compose Design. It maps each control to a design kind with fields, defaults, children and a build function. `fields.luau` is generated from the control prop types by `lute run tools/facet types props`. | `Facet.design()` |
| **Compose snapshot** | `src/vendor/compose/` | The pinned Compose reactive runtime and its Roblox host. Generated. Do not edit it. | `Facet.Compose`, `Facet.Roblox` |
| **control context** | `src/ui/context.luau`, `src/ui/context_actions.luau`, `src/ui/context_config.luau`, `src/ui/control_environment.luau`, `src/ui/context_construct.luau`, `src/ui/context_content.luau`, `src/ui/context_environment.luau`, `src/ui/context_metrics.luau`, `src/ui/context_native.luau`, `src/ui/context_observe.luau`, `src/ui/types.luau`, `src/ui/engine_types.luau`, `src/ui/control_types.luau`, `src/ui/help.luau`, `src/ui/native_decoration.luau`, `src/ui/arithmetic.luau`, `src/ui/motion.luau`, `src/ui/font_readiness.luau`, `src/ui/presentation_readiness.luau`, `src/ui/text_measure.luau`, `src/ui/settle.luau`, `src/ui/selection.luau`, `src/ui/reserved_keys.luau`, `src/ui/text_press.luau`, `src/ui/segment_metrics.luau`, `src/ui/drag.luau`, `src/ui/drag_types.luau`, `src/ui/drag_pointer.luau`, `src/ui/pointer_drag.luau`, `src/ui/drag_session.luau`, `src/ui/drag_travel.luau`, `src/ui/gesture_arbitration.luau`, `src/ui/gesture_service.luau`, `src/ui/text_reveal.luau`, `src/ui/preferred_input.luau` | The shared context for each runtime and the shared types. It also holds the help text, the text reveal, drag and drop, native decoration, native property observations, the modifier-key hold on `PreferredInput`, the Tab and Escape dispatch shared per `UserInputService` (`reserved_keys.luau`), the velocity-seeded settle (`settle.luau`). | None. The families receive it from the library root. |
| **inputs** | `src/ui/inputs.luau`, `src/ui/input_kit.luau`, `src/ui/input_contacts.luau`, `src/ui/input_adjustment.luau`, `src/ui/input_button.luau`, `src/ui/input_button_content.luau`, `src/ui/input_toggle.luau`, `src/ui/input_stepper.luau`, `src/ui/input_level.luau`, `src/ui/input_chip.luau`, `src/ui/input_shortcut_hint.luau`, `src/ui/input_button_guide.luau`, `src/ui/input_key_glyph.luau`, `src/ui/command_scope.luau`, `src/ui/command_types.luau`, `src/ui/feedback_paint.luau`, `src/ui/input_value.luau`, `src/ui/input_types.luau`, `src/ui/input_props.luau`, `src/ui/slider.luau`, `src/ui/text_field.luau`, `src/ui/field_chrome.luau`, `src/ui/color_picker.luau`, `src/ui/color_picker_kit.luau`, `src/ui/color_picker_state.luau`, `src/ui/color_picker_panel.luau`, `src/ui/color_picker_well.luau`, `src/ui/color_picker_spectrum.luau`, `src/ui/color_picker_sliders.luau`, `src/ui/color_picker_swatches.luau`, `src/ui/color_picker_readout.luau`, `src/ui/color_picker_types.luau`, `src/ui/color_value.luau`, `src/ui/date_time_picker.luau`, `src/ui/date_time_parts.luau`, `src/ui/date_time_options.luau`, `src/ui/date_time_state.luau`, `src/ui/date_time_field.luau`, `src/ui/date_time_panel.luau`, `src/ui/date_time_header.luau`, `src/ui/date_time_calendar.luau`, `src/ui/date_time_time.luau`, `src/ui/date_time_picker_types.luau`, `src/ui/civil_date.luau`, `src/ui/civil_date_types.luau` | Buttons, toggles, text input, steppers, sliders, ratings, level pickers, chips, shortcut hints and button guides. | None. Reach it through `Facet.controls`. |
| **navigation** | `src/ui/nav_modal.luau`, `src/ui/nav_modal_stack.luau`, `src/ui/nav_modal_input.luau`, `src/ui/nav_surface_kit.luau`, `src/ui/nav_overlay_portal.luau`, `src/ui/nav_overlay_presence.luau`, `src/ui/nav_popover_placement.luau`, `src/ui/nav_help.luau`, `src/ui/nav_menu.luau`, `src/ui/nav_menu_items.luau`, `src/ui/nav_menu_panel.luau`, `src/ui/nav_menu_rows.luau`, `src/ui/nav_picker.luau`, `src/ui/nav_picker_parts.luau`, `src/ui/nav_picker_options.luau`, `src/ui/nav_picker_menu.luau`, `src/ui/nav_picker_cards.luau`, `src/ui/nav_split_button.luau`, `src/ui/nav_combo_box.luau`, `src/ui/nav_surfaces.luau`, `src/ui/nav_surface_parts.luau`, `src/ui/nav_alert.luau`, `src/ui/nav_callout.luau`, `src/ui/nav_disclosure.luau`, `src/ui/nav_collapsible.luau`, `src/ui/nav_pages.luau`, `src/ui/nav_page_layers.luau`, `src/ui/transition.luau`, `src/ui/nav_tab_view.luau`, `src/ui/nav_tab_item.luau`, `src/ui/nav_tab_metrics.luau`, `src/ui/nav_tab_accessories.luau`, `src/ui/nav_stack.luau`, `src/ui/gameplay_hold.luau`, `src/ui/entry_upgrade.luau`, `src/ui/nav_page_view.luau`, `src/ui/nav_path_shapes.luau`, `src/ui/navigation_types.luau`, `src/ui/navigation_props.luau`, `src/ui/navigation_split_view.luau` | Menus, pickers, presented surfaces, tab views, navigation stacks and page views. | None. Reach it through `Facet.controls`. |
| **overlays** | `src/ui/keyboard_inset.luau`, `src/ui/nav_dialog.luau`, `src/ui/nav_popover.luau`, `src/ui/nav_sheet.luau`, `src/ui/nav_sheet_content.luau`, `src/ui/nav_sheet_detents.luau`, `src/ui/nav_sheet_gesture.luau`, `src/ui/nav_notice.luau`, `src/ui/overlay_parts.luau`, `src/ui/overlay_arrival.luau`, `src/ui/materialize.luau`, `src/ui/overlay_placement.luau`, `src/ui/overlay_types.luau`, `src/ui/overlay_props.luau`, `src/ui/sheet_release.luau`, `src/ui/reservations.luau`, `src/ui/activation.luau`, `src/ui/nav_toast.luau`, `src/ui/toast_schedule.luau` | Dialogs, popovers, sheets, snackbars, toasts, notices, the navigation bar, the shared placement, the layer insets and the Composition zone claims of one screen. | None. Reach it through `Facet.controls`. |
| **radial** | `src/ui/nav_radial.luau`, `src/ui/nav_radial_menu.luau`, `src/ui/nav_radial_layout.luau`, `src/ui/nav_radial_sectors.luau`, `src/ui/nav_radial_center.luau`, `src/ui/nav_radial_gestures.luau`, `src/ui/nav_radial_geometry.luau`, `src/ui/radial_types.luau`, `src/ui/radial_props.luau` | The radial menu and its geometry. | None. Reach it through `Facet.controls`. |
| **collections** | `src/ui/collections.luau`, `src/ui/spatial_grid.luau`, `src/ui/spatial_grid_geometry.luau`, `src/ui/spatial_grid_types.luau`, `src/ui/spatial_grid_props.luau`, `src/ui/collection_state.luau`, `src/ui/collection_slots.luau`, `src/ui/collection_rows.luau`, `src/ui/collection_focus.luau`, `src/ui/collection_navigation.luau`, `src/ui/collection_fling.luau`, `src/ui/collection_policy.luau`, `src/ui/collection_paint.luau`, `src/ui/collection_tree.luau`, `src/ui/collection_selection.luau`, `src/ui/collection_reorder.luau`, `src/ui/collection_reorder_state.luau`, `src/ui/collection_reorder_row.luau`, `src/ui/collection_reorder_pointer.luau`, `src/ui/collection_reorder_keys.luau`, `src/ui/collection_reorder_drop.luau`, `src/ui/collection_reorder_feedback.luau`, `src/ui/collection_snap.luau`, `src/ui/collection_row_actions.luau`, `src/ui/collection_table.luau`, `src/ui/collection_table_metrics.luau`, `src/ui/collection_table_columns.luau`, `src/ui/collection_table_header.luau`, `src/ui/collection_table_rows.luau`, `src/ui/collection_table_toolbar.luau`, `src/ui/collection_table_editors.luau`, `src/ui/collection_types.luau`, `src/ui/collection_props.luau` | Keyed and virtual collections, animated hierarchies, selection, reorder, snap, row actions, reusable CellEditor drafts and tables. | None. Reach it through `Facet.controls`. |
| **media** | `src/ui/media.luau`, `src/ui/media_shared.luau`, `src/ui/media_text.luau`, `src/ui/media_image.luau`, `src/ui/media_async_image.luau`, `src/ui/media_badge.luau`, `src/ui/media_progress.luau`, `src/ui/media_skeleton.luau`, `src/ui/media_avatar.luau`, `src/ui/media_stage.luau`, `src/ui/media_path.luau`, `src/ui/media_readiness.luau`, `src/ui/media_types.luau`, `src/ui/media_props.luau`, `src/ui/rich_text.luau`, `src/ui/format.luau`, `src/ui/timer.luau`, `src/ui/typewriter.luau`, `src/ui/world_marker.luau`, `src/ui/hud_types.luau`, `src/ui/hud_props.luau` | Labels, badges, status, progress, skeletons, images, avatars, stages, paths, world markers and rich text escaping. | `Facet.format`, `Facet.richText`, `Facet.pathShapes`, or through `Facet.controls`. |
| **content** | `src/ui/pagination.luau`, `src/ui/pagination_window.luau`, `src/ui/step_indicator.luau`, `src/ui/vote.luau`, `src/ui/card.luau`, `src/ui/badge_seal.luau`, `src/ui/content_values.luau`, `src/ui/content_types.luau`, `src/ui/content_props.luau` | Pagination, step indicators, votes, cards, and the checks that keep the last legal value. | None. Reach it through `Facet.controls`. |
| **effects** | `src/ui/effect_types.luau`, `src/ui/effect_props.luau`, `src/ui/effect_sequence.luau`, `src/ui/effect_flash.luau`, `src/ui/effect_shake.luau` | Ordered effect policy, numeric motion, transient GUI paint and restored rotation feedback. | Through `Facet.controls`. |
| **zoom and travel** | `src/ui/zoom_view.luau`, `src/ui/zoom_geometry.luau`, `src/ui/travel.luau`, `src/ui/travel_engine.luau`, `src/ui/travel_geometry.luau`, `src/ui/zoom_travel_types.luau`, `src/ui/zoom_travel_props.luau` | Board zoom, pan, focus limits and travel between native containers. | None. Reach it through `Facet.controls`. |
| **themes** | `src/ui/themes.luau`, `src/ui/theme_support.luau`, `src/ui/theme_define.luau`, `src/ui/theme_rule_kit.luau`, `src/ui/theme_stylesheet.luau`, `src/ui/theme_skin.luau`, `src/ui/theme_icons.luau`, `src/ui/theme_types.luau`, `src/ui/theme_distance.luau`, `src/ui/icons.luau` | Theme packages, their compilation to native StyleSheets, the ten-foot metric ladder, chrome skins and the standard icons. | `Facet.themes` |

## Proof

The same areas, in the same order. The **Tests** column names entry specs. It
does not name each spec. A spec covers an area when one of its own `require`
calls names a module of that area. A spec that requires only `src` or `src/ui`
covers the library root. To see the number of specs for each area, run
`lute run tools/facet check maintainer-map --counts`.

<!-- maintainer-map:proof -->

| Area | Tests | Studio scenario | Extend via |
|---|---|---|---|
| **spatial presentation** | `tests/native_diegetic_screen.verify.luau` | None — native consumer transition review is pending. | [Mounting into native targets](extending/new-render-target.md) |
| **library root** | `tests/blocks.verify.luau`, `tests/lab_loader.verify.luau`, `tests/native_public_surface.verify.luau`, `tests/native_compose_contract.verify.luau`, `tests/native_compose_binding.verify.luau`, `tests/native_navigation.verify.luau`, `tests/native_radial_controls.verify.luau` | `all_controls` | [Adding a control](extending/new-control.md) |
| **design library** | `tests/facet_compose_library.verify.luau` | None — the design editor runs in the Studio plugin, not in a gallery scenario. | [Compose Design](reference/nodes/Design-library.md). Change the design format upstream in Compose. Then run `lute run tools/facet sync compose`. Regenerate the fields with `lute run tools/facet types props`. |
| **Compose snapshot** | `tests/native_themes_media.verify.luau`, `tests/native_perf_runner.verify.luau` | `component_motion` | [Adopting an engine feature](extending/new-engine-feature.md). Change Compose upstream. Then run `lute run tools/facet sync compose`. |
| **control context** | `tests/native_registration.verify.luau`, `tests/native_text_measure.verify.luau`, `tests/native_inputs.verify.luau`, `tests/gesture_arbitration.verify.luau`, `tests/container_transfer.verify.luau` | `all_controls` | [Native primitives](extending/new-primitive.md) |
| **inputs** | `tests/command_scope.verify.luau`, `tests/native_inputs.verify.luau`, `tests/native_collections.verify.luau` | `action_controls`, `text_controls` | [Adding a control](extending/new-control.md) |
| **navigation** | `tests/native_collections.verify.luau` | `menu`, `navigation_stack`, `sheet`, `alert` | [Adapting to another platform context](extending/new-platform-mode.md) |
| **overlays** | `tests/native_dialog.verify.luau`, `tests/native_popover.verify.luau`, `tests/native_sheet_parts.verify.luau`, `tests/native_toast_action.verify.luau`, `tests/native_notice_navbar.verify.luau`, `tests/native_callout_help.verify.luau`, `tests/sheet_release.verify.luau` | `overlays`, `notice`, `sheet` | [Adding a control](extending/new-control.md) |
| **radial** | `tests/radial_geometry.verify.luau`, `tests/native_collections.verify.luau` | `radial_menu` | [Adding a control](extending/new-control.md) |
| **collections** | `tests/native_collections.verify.luau` | `collections`, `table_virtualized`, `row_actions` | [Adding a control](extending/new-control.md) |
| **media** | `tests/native_themes_media.verify.luau`, `tests/hud_format.verify.luau`, `tests/hud_timer.verify.luau`, `tests/hud_typewriter.verify.luau` | `async_images`, `avatar`, `badge` | [Mounting into native targets](extending/new-render-target.md) |
| **content** | `tests/native_pagination.verify.luau` | `paging`, `steps` | [Adding a control](extending/new-control.md) |
| **effects** | `tests/effect_sequence.verify.luau`, `tests/effect_shake.verify.luau` | None — use the reward_sequence and shake live suites and Lab pages. | [Adding a control](extending/new-control.md) |
| **zoom and travel** | `tests/zoom_travel.verify.luau` | None — use the zoom and travel live suite and Lab pages. | [Adding a control](extending/new-control.md) |
| **themes** | `tests/native_themes_media.verify.luau`, `tests/native_themes_media.verify.luau` | `all_controls` | [Adding a theme package](extending/new-theme.md) and [Adding artwork to a control](extending/skinned-control.md) |

## Repository

Each top-level directory has one row. The tree table does not list the
directories that `.gitignore` excludes.

<!-- maintainer-map:tree -->

| Directory | Holds | Check |
|---|---|---|
| `src/` | The library. See [Areas](#areas). | `lute run tools/facet gate full` |
| `tests/` | The behavioral specs, the native engine double and the type witnesses. | `lute run tools/facet gate spec <spec-name>` |
| `examples/` | The starter blocks in `examples/blocks`, the gallery, the Facet Lab, the consumer project, the reference apps, the virtual monitors, the example themes and the performance lab. | `lute run tools/facet check scenario-requires` |
| `bench/` | The benchmark scenes, profiles and baselines. | `lute run tools/facet bench` |
| `tools/` | The Verify gate runner, the Lute maintainer commands and checks, the native engine double programs and the Studio tools. | `lute run tools/facet check --all` |
| `docs/` | The guides, extension playbooks, reference and this map. | `lute run tools/facet check doc-style` |
| `assets/` | The icon images and the theme art. The generators in `tools/facet/art/` make them, and the package build includes them. | `lute run tools/facet art all --check` |
| `package/` | The Roblox Package configuration and the publish receipts. See [the package interface](../package/README.md). | `lute run tools/facet package status` |
| `skills/` | The agent skills for Compose and for Facet. | None. A reviewer reads them with the guide. |
| `eval/` | The thirty-minute blank-project game run, its author setups and acceptance requirements. See [the run](../eval/README.md). | `lute run tools/facet check facetbench` |

## Quick answers

<!-- maintainer-map:quick -->

| Question | Answer | Read |
|---|---|---|
| Where does a new control go? | In the area of its family, under `src/ui/`. | [Adding a control](extending/new-control.md) |
| How do I change the look? | Change or derive a theme package. Do not change a control. | [Custom themes](guide/themes.md) |
| How do I change Compose? | Change Compose upstream. Then update the pinned snapshot. | [Adopting an engine feature](extending/new-engine-feature.md) |
| What does a passing native run prove? | Only that the selected commands passed. | [Verification scope](guide/verification-scope.md) |
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

## Gate producers

The gate declares each producer and tier in
[`tools/facet/producers.json`](../tools/facet/producers.json). `tool-specs`
includes the planted-fault proofs for types, public surface and memory.
`vendor` checks both dependency pins. `standalone-builds` builds the example
and reference places. `theme-artifacts` builds and probes themes.
`package-build` builds and verifies the model and package. `art` also checks
plate samples. `perf` reports budgets and metrics; `perf-scenes` checks both
production and theme scenes. `perf-place` keeps its Studio environment.

`studio-live` uses the committed [live source plan](../tools/studio/live/plan.json).
The `plan` producer checks its source coverage. The [CI guide](../tools/studio/CI.md)
defines complete native runs, hosted CI coverage and the final Verify job.
Hosted CI uses the engine double; native Studio coverage remains deferred.

Hosted CI splits the full tier into four Linux shards with Verify's `--shard`.
[`tools/facet/ci-weights.json`](../tools/facet/ci-weights.json) holds the
measured seconds that balance them. Each shard records fresh weights in its
verification artifact. A release runs the complete full tier on macOS and
Windows before it publishes.

Commands and test workers share a process budget equal to the host CPU count.
Each command and each test worker uses one slot. Tests can use a command's slot
when the command exits. The gate reserves 2 GiB of memory, allows 2 GiB per
worker and caps the test pool at eight workers and the selected source count.
Set `FACET_TEST_WORKERS` to a positive integer for a controlled comparison.
The shared process budget, memory, source and eight-worker limits still apply.
Performance timing remains serial.

The Lab option check reads field origins from the props generator and its
option tables. Run the [Lab coverage tool](../examples/facet-lab/tools/coverage.luau)
with `fields` from `examples/facet-lab` to list each control, field and origin.

## Evidence

Control policy tests use a native engine double. Geometry, hit testing,
Input Method Editor (IME) text, scrolling and input eligibility need live
Studio evidence. The live runner uses Verify to produce case reports.
Hand-written observations do not replace those reports. The `plan` producer
checks that `tests/plan.json` lists each spec file on disk exactly once. When
you retire tests of removed mechanisms, keep the behavior coverage of each control family.
The current suite is the evidence. A passing run proves only the selected cases. The
[verification scope](guide/verification-scope.md) describes the checks and
their limits.

Read the [contributor workflow](../CONTRIBUTING.md), the
[API reference](reference/api.md) and the
[control playbook](extending/new-control.md).

Run `lute run tools/facet perf footprint` for the control resource census.
The report subtracts an empty screen from each mounted control. It records
active and idle instances, connections and Compose holdings, then checks
zero resources after disposal. Menu and VirtualList samples with one and
two rows show the cost of one more row. These fixed headless fixtures use
the native engine double. They do not measure engine layout or device memory.
The `perf-footprint` producer checks `bench/footprint_budgets.json`.

Run `lute run tools/facet perf profile SCENE` for a Lute sampling trace of
the unchanged scene. Profiles include setup and warmup. Use paired runs
for timing claims.

Paired performance also checks retained Luau heap while each scene is mounted
and after teardown. It uses Verify's bounded heap estimator in a separate pass,
with eight collection witness cycles at each endpoint.
The heap comparison requires growth above 5% and 64 KiB in every paired round
and in the median. Run `lute run tools/facet perf prove-retained-memory` to check
unchanged scenes and a retained allocation of 4 MiB. This proof covers every
paired scene and keeps its raw measurements in the output directory.
The `prove-retained-memory` producer belongs to the release tier. CI also runs
the proof when the collector, scene adapter or comparison policy changes.

`lute run tools/facet perf affected BASE` checks paired performance inputs.
It covers code, workload data, fixtures, the toolchain and the CI workflow.
Exit 0 requires paired measurements. Exit 3 means that these inputs did not change.

## How this page stays true

Run `lute run tools/facet check maintainer-map`. It reads the tree and this
page, and it fails when they disagree. Run it with `--rules` to see each rule.
Run it with `--selftest` to see each rule fail on a planted fault.
