--!strict
-- LuauUI test entry point. Run with:  lune run tests/run   (from GameStudio/ui/LuauUI)
-- or ./run-tests.sh. Requires each spec, then runs. Same testkit as the games use.

local process = require("@lune/process")
local testkit = require("./lib/testkit")

-- Register all specs. Add new spec files here.
require("./smoke.spec")
require("./fusion_vendor.spec")
require("./conformance/conformance.spec")
require("./replication.spec")
require("./layout.spec")
require("./focus.spec")
require("./mount.spec")
require("./layout_v1.spec")
require("./renderer.spec")
require("./native_scroll.spec")
require("./path.spec")
require("./async_image.spec")
require("./selection_bridge.spec")
require("./text_calibration.spec")
require("./text_fit.spec")
require("./value_reveal.spec")
require("./text_premeasure.spec")
require("./drag_session.spec")
require("./touch_gestures.spec")
require("./input.spec")
require("./presenter.spec")
require("./controls_conformance.spec")
require("./hint_no_remount.spec")
require("./icon_box.spec")
require("./chrome_inset_yield.spec")
require("./slice_mutation.spec")
require("./focus_structural.spec")
require("./table.spec")
require("./pointer.spec")
require("./preview.spec")
require("./render_target_contract.spec")
-- the per-node presentation channel + the SF-M9 live-adapter fix (ADR-0022 D2)
require("./presentation_channel.spec")
-- the authored paint escapes: tint, scaleMode, UI.stroke, zIndex (ADR-0022 D6)
require("./paint_extensions.spec")
-- fractional Anchor offsets: the marker-overlay shape (ADR-0022 D6, SF-P5)
require("./fractional_offsets.spec")
require("./presenter_drag_integration.spec")
-- quarantine pins from the fresh-context runtime review (RR-1/RR-2/RR-4)
require("./runtime_quarantine.spec")
-- Phase 4 (hardening) specs
require("./fuzz_scheduler.spec")
require("./fuzz_layout.spec")
require("./fuzz_replication.spec")
require("./faults.spec")
require("./virtualization.spec")
require("./navigation_groups.spec")
require("./perf_runner.spec")
-- evidence-class discipline: the rules that stop a headless number becoming a
-- device claim (roadmap Step 4, UI-PERF-002)
require("./perf_evidence.spec")
-- the future spatial seam: contracts only, and the guard against a VR claim
-- appearing in the shipped surface (roadmap Step 4, UI-SPATIAL-001)
require("./spatial.spec")
-- the five-view device-matrix selection policy, fed a recorded live catalog
require("./matrix_rows.spec")
require("./error_boundary.spec")
require("./styling.spec")
require("./sheet_model.spec")
require("./native_style_scenario.spec")
require("./api_surface.spec")
require("./extension_checker.spec")
require("./examples_gallery.spec")
require("./gallery_theme_picker.spec")
-- the showcase demo picker: one published place, switchable in-game
require("./gallery_demo_picker.spec")
require("./examples_games.spec")

require("./popup_button.spec")
require("./text_input.spec")
require("./auto_input.spec")
require("./table_input.spec")
require("./virtual_list_input.spec")
require("./auto_input_screens.spec")
-- device round 1 (RascalRally, 2026-07-31): contributions mounted by a keyed
-- region AFTER present, and the focus-visible rule a finger must obey
require("./late_contributions.spec")
require("./gamepad_contention.spec")
require("./responder.spec")
require("./modal_dismissal.spec")
require("./paradigm_popup.spec")
require("./paradigm_input_axis.spec")
require("./paradigm_table.spec")
require("./paradigm_hover.spec")
require("./paradigm_tenfoot.spec")
require("./paradigm_textinput.spec")
require("./paradigm_carry.spec")
require("./chip.spec")
require("./authoring.spec")
require("./layout_vocabulary.spec")
require("./adaptive.spec")
require("./button_complete.spec")
-- the circle Button (feature round 2026-07-26)
require("./button_shape.spec")
require("./compact_label.spec")
require("./value_controls.spec")
require("./rating.spec")
require("./display_controls.spec")
require("./theme_package.spec")
require("./theme_snapshot.spec")
require("./theme_roles.spec")
require("./theme_drift.spec")
-- theme controller specs (package 2)
require("./theme_controller.spec")
-- theme chrome/reference specs (package 3)
require("./theme_chrome.spec")
-- rich-skinning-v2 schema + model specs (P1)
require("./theme_layers.spec")
require("./theme_variants.spec")
require("./theme_icons.spec")
require("./theme_pixel.spec")
require("./theme_assets.spec")
-- rich-skinning-v2 adapter APPLICATION specs (P2): every P1 emission, proven on
-- the live path (the Step 3.5 lesson — emission is not application)
require("./theme_layer_application.spec")
-- image value displays (P3): the bar family, the stepper plate, the toggle slots
require("./theme_value_displays.spec")
-- icons + pixel mode + content adoption + selectBy (P4), emission AND application
require("./theme_icons_applied.spec")
require("./theme_selectby.spec")
require("./theme_pixel_content.spec")
require("./theme_reference_packages.spec")
require("./theme_authoring_scenario.spec")
-- the headless twin of the five-view device matrix (RS-A16 structural guard)
require("./theme_matrix_audit.spec")
-- when silence from an image is evidence that its asset failed (RS-A16-D5)
require("./theme_asset_judgement.spec")
-- theme docs spec (docs package)
require("./theme_docs.spec")
-- sponsor-framework-gaps P1: the motion authority (ADR-0022 Decision 1) — pure
-- solver, class registry, injectable clock, perceptual arrival, timelines, and
-- the reduced-motion parity rules, all under a scripted clock
require("./motion_spring.spec")
require("./motion_clock.spec")
require("./motion_chase.spec")
require("./motion_timeline.spec")
-- sponsor-framework-gaps P3: structural transitions (the mount-layer retire
-- model, the coordinator over the presentation channel, and the presenter's own
-- surface enter/exit — ADR-0022 Decision 3, row SF-M6)
require("./transitions.spec")
-- the pure toast scheduler and the input-transparent toast surface it drives
-- (ADR-0022 Decision 4, rows SF-T1..T3)
require("./toast_schedule.spec")
require("./toast_presentation.spec")
-- the one semantic feedback seam: closed taxonomy, causal frames, exactness
-- (ADR-0022 Decision 7, row SF-F1)
require("./feedback.spec")
-- bounded retry with a session give-up, the preload seam, and the AsyncImage dim
-- treatment (ADR-0022 Decision 8, rows SF-A1..A3)
require("./async_completeness.spec")
-- sponsor-framework-gaps P4: the shared interaction tokens + the rolling
-- release-velocity tracker (ADR-0022 Decision 5, rows SF-D3 / SF-D2)
require("./interaction_tokens.spec")
-- the pure drag-to-edge autoscroll model under a scripted clock (SF-L2)
require("./autoscroll.spec")
-- the public drag/drop contract, driven through the REAL acquisition paths
-- (SF-D1..SF-D5, findings F5/F7)
require("./drag_public.spec")
-- focus-skip by live predicate + the active-interaction exemption (SF-L3)
require("./focus_skip.spec")
-- the unified collection: one VirtualList that windows, selects, reorders,
-- accepts drops and edge-scrolls at once (SF-L1, SF-L2, SF-L3)
require("./collection_list.spec")
-- the eight Sponsor-shaped gallery fixtures (ui-designer-spec §8): every step
-- drivable by name, every terminal state, 20 mount/reset cycles registry-neutral
-- (SF-C1) and the reduced-motion axis (SF-M5/SF-T3)
require("./sponsor_scenarios.spec")
-- DECLARED-CONTENT ADAPTIVE COMPOSITION (ADR-0023): the pure decision matrix
-- (arrangement choice, step-down/drop order, floors, reserved-at-rest, the
-- one-scroll refusal, the column fallback) plus the mounted re-solve identity
require("./composition.spec")
-- THE CLOSED-KEY SWEEP (ARCH-1): every composite control spec and every
-- service/model opts table refuses an unknown key, naming the boundary, the key
-- and the legal set — and still accepts the legal call it was derived from
require("./spec_guard_sweep.spec")
local ok = testkit.run()
if not ok then
	process.exit(1)
end
