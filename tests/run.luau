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
-- MicroProfiler phase scopes (roadmap Step 9, PL-8): the closed scope set, its
-- cardinality bound, and the balance guarantee proved through a recording hook
-- pair — because Lune has no debug.profilebegin and the instrumented branch is
-- otherwise never executed by this suite at all
require("./profile_scopes.spec")
-- the performance lab's PURE decisions (roadmap Step 9, PL-2..PL-11): the shared
-- deterministic dataset, the bounded-window rule with its negative control, mount
-- exclusivity, the emergency stop, and what makes a capture row inadmissible
require("./perf_lab.spec")
-- the per-solve measure memo's VERDICT contract (Step 9, architecture review
-- BLOCKER-1): a cached measure must replay the compact/textFacts it published, or
-- last-write-wins silently becomes first-measure-wins and a cut label reports
-- truncated = false with its geometry unchanged
require("./measure_memo.spec")
require("./fine_grained_reactivity.spec")
require("./instance_recycling.spec")
require("./mount_unmount_soak.spec")
-- ...and the THEMED half (L-28): park releases the chrome's path keys, adopt
-- re-keys them, and a decoration-hint or package mismatch refuses the adoption
require("./instance_recycling_themed.spec")
require("./instance_park_corpse.spec")
require("./incremental_layout.spec")
require("./diagnostic_replay.spec")
require("./container_relative_incremental.spec")
require("./perf_principles.spec")
require("./layout_v1.spec")
require("./renderer.spec")
require("./native_scroll.spec")
-- O-31: a virtualised collection mirrors its engine CanvasPosition with NO
-- post-`present` consumer call, on the two contribution seams that reach every
-- presenter configuration (`bindController` + `syncGeometry`)
require("./native_scroll_autobind.spec")
-- desktop keyboard focus chain (roadmap Step 8): Tab/Shift+Tab traversal,
-- Space-as-Activate, focused-value arrow Adjust
require("./keyboard_navigation.spec")
require("./traversal_order.spec")
require("./path.spec")
-- UI.Stage (ViewportFrame adoption, 2026-08-08): the engine-content leaf plus
-- its renderer-mediated content seam (camera/lighting/content root)
require("./stage.spec")
-- UI.Foreign (ADR-0034, react-lua-comparison §5 rank 1): the bounded escape
-- hatch to a GuiObject class LuauUI does not wrap — one box, one claim
-- (`Foreign.Parent`, on the reserved `host` authority), everything else the
-- caller's
require("./foreign.spec")
require("./async_image.spec")
require("./selection_bridge.spec")
require("./text_calibration.spec")
require("./text_degrade_cascade.spec")
require("./text_fit.spec")
-- the LINE BOX (ruled 2026-08-15): `text.facts`/`text.lineBox`, the three defects
-- they fixed in the public `composition.floorPx`, and the differential oracle that
-- proves the helper equals what the solver arranges across every shipped theme x
-- both display classes x sub-1..3x preferences x the four measured text offsets
require("./text_line_box.spec")
require("./value_reveal.spec")
require("./text_premeasure.spec")
-- large-text accessibility (LTN-4): the solve's per-text truncation facts, the
-- /2 layout dump, and the five pure authoring-safety checks with their negative
-- controls
require("./text_audit.spec")
-- ...and the presenter-owned STATIC full-value disclosure the `disclose`
-- declaration buys (LTN-2 chose static over a marquee)
require("./text_disclosure.spec")
-- D1, the anchored-surface seam (navigation-and-menus §2 D1): the pure
-- placement solver (preferred edge, safe-area flip, along-edge shift, arrow
-- tail + its suppression), `presenter.presentAnchored` on top of it, and the
-- two hand-rolled precedents it unifies
require("./anchored_surface.spec")
-- ...and the AUTO REVEAL (director 2026-08-04, superseding LTN-2 for declared
-- surfaces): `reveal = "auto"` slides a truncated one-liner's whole value
-- through its box on the presenter's one tick, under the plan's constraint list
require("./text_reveal.spec")
require("./preferred_text_seam.spec")
-- ...and the LARGE-TEXT MATRIX the plan's verification section asks for
-- (acceptance LT-6/LT-8), over the shared tests/lib/large_text harness: every
-- controls_registry row at { 0, 4, 10, 14 } px x both reference themes; the
-- overflow ORDER on four composed screens at two compact viewports, with
-- reduced motion; and the live 0 -> 14 -> 0 swing with focus, an uncommitted
-- edit and a scrolled list on the screen
require("./large_text_matrix.spec")
require("./large_text_layout.spec")
require("./large_text_hot_swap.spec")
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
require("./table_virtualized.spec")
-- the header, its resize dividers and the owner-held sort, on the surface a
-- player reaches them through: the shipped playlist tutorial. Was
-- `table_columns.spec` against a fixture of its own until 2026-08-16, when the
-- playlist gained the third `fill` column that makes a resize non-degenerate and
-- the standalone fixture was retired (navigation-and-menus D8).
require("./playlist_columns.spec")
-- the hit-expander overhang lift (2026-08-15): the z rule that makes a sub-floor
-- control's advertised touch band DELIVERABLE, proved on the table divider that
-- reported it and on a non-table expander that carried it silently
require("./hit_expander_overhang.spec")
-- the header band across all eight shipped packages: the axis every other Table
-- spec is uniform along, and therefore the one that let the sort mark ship
-- outside its themed plate (director, Studio 2026-08-14)
require("./table_themed_header.spec")
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
-- the RUNNING-OFFSET INDEX under variable item extents (2026-08-14): the pure
-- prefix-sum arithmetic `index x pitch` cannot express, proved to contain the
-- uniform rule as its special case and to stay logarithmic on a 10,000-item list
require("./virtual_extents.spec")
-- ...and the CONTROL wired to it: variable item extents (ruling 7, 2026-08-13).
-- Per-item extents, bounded builds on a 10,000-item ragged list, an anchored
-- scroll when the extents re-derive, and the differential against the uniform
-- list it must contain
require("./virtual_list_variable_extents.spec")
-- ...and STAGE 2 on the same index: MEASURED extents (`itemExtent = "measured"`).
-- The row is windowed at what its cell measures rather than at what its consumer
-- predicted, so the prediction — and the whole lying-extent class — goes away.
-- Laziness and the anchored scroll are re-proved on the measured path, because a
-- design that measured every row would look identical in a screenshot
require("./virtual_list_measured_extents.spec")
require("./virtual_list_row_gap.spec")
require("./virtual_list_axis.spec")
require("./virtual_list_focus_policy.spec")
-- the LYING `itemExtent` guard (2026-08-13): a fixed-pitch window is only exact
-- while the declared extent is the true one, and until this nothing checked the
-- consumer's prediction against what its own row actually measures
require("./virtual_list_slot_guard.spec")
require("./virtual_grid.spec")
require("./virtual_grid_input.spec")
-- ...and the SIDEWAYS half, `newVirtualGrid { axis = "x" }` -- SwiftUI's `LazyHGrid`.
-- It exists because `UI.Grid` learned to wrap COLUMN-MAJOR (`grid_column_flow.spec`),
-- so the horizontal band is a real `UI.Grid` with the lane formula EXECUTING, never a
-- second lane arithmetic inside the control. Its ring transposes the OPPOSITE way from
-- a list's: a grid's declared group axis is the LANE axis, perpendicular to the scroll,
-- so Down steps ONE CELL here and Right steps a whole LINE
require("./virtual_hgrid.spec")
require("./navigation_groups.spec")
-- ...and the mechanism BOTH grids stand on since ADR-0030: a NavigationGroup may
-- declare `columns`, and the focus graph then answers the direction perpendicular
-- to the lanes itself, by a whole line. This is what deleted the two intercepts
require("./focus_grid_axis.spec")
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
-- `UI.sortedEntries` (fusion-comparison.md §5 gap G-3): the deterministic
-- dictionary flatten `UI.ForEach` needs, and the negative control that proves
-- Luau's `pairs` order really does move with a table's construction history —
-- twelve keys, because at six the constructions agree and prove nothing
require("./sorted_entries.spec")
require("./styling.spec")
require("./sheet_model.spec")
require("./native_style_scenario.spec")
require("./api_surface.spec")
require("./extension_checker.spec")
require("./examples_gallery.spec")
require("./gallery_theme_picker.spec")
-- the showcase demo picker: one published place, switchable in-game
require("./gallery_demo_picker.spec")
-- ...and the CHROME around it (parity round 3, item E rows 4 and 11): four-input
-- reachability driven through the real key/pad path rather than asserted from
-- source text, the two-chip ViewThatFits ladder, and the persistent
-- Full | Reduced motion setting the reduced-motion axis of a device canary needs
require("./gallery_chrome.spec")
require("./examples_games.spec")
-- the word game's PURE rules and state machine (roadmap Step 10, EQ-9): the
-- two-pass letter budget across every duplicate shape, refusals that do not
-- consume a row, monotonic key state, win/loss, and the deterministic seed
require("./example_word_game.spec")

require("./popup_button.spec")
require("./text_input.spec")
require("./auto_input.spec")
require("./table_input.spec")
require("./virtual_list_input.spec")
require("./virtual_list_row_actions.spec")
-- ...and the SHIPPING DIFFERENTIAL the hosted-mode charter asks for: a plain
-- list and a `rowActions` list built from one builder, diffed node for node
-- (paths, classes, solved rects) and over the whole engage/disengage lifecycle
require("./virtual_list_row_actions_identity.spec")
require("./auto_input_screens.spec")
-- device round 1 (RascalRally, 2026-07-31): contributions mounted by a keyed
-- region AFTER present, and the focus-visible rule a finger must obey
require("./late_contributions.spec")
require("./gamepad_contention.spec")
require("./responder.spec")
require("./modal_dismissal.spec")
require("./paradigm_popup.spec")
require("./popup_catcher_paint.spec")
require("./paradigm_input_axis.spec")
require("./paradigm_table.spec")
require("./paradigm_hover.spec")
require("./paradigm_tenfoot.spec")
require("./paradigm_textinput.spec")
require("./paradigm_carry.spec")
require("./chip.spec")
require("./authoring.spec")
require("./layout_vocabulary.spec")
-- the stack branch's three round-2 parity additions, in one file because they are
-- one change to one branch: `distribute` (§2.6, main-axis distribution), the
-- shrink pass (§2.4, `layoutPriority` tiers x `shrinkWeight` proportions — which
-- runs in the MEASURE branch as well as arrange, so a squeezed label's wraps are
-- reserved) and `lineAlign` (§2.1, per-child cross-axis alignment — the
-- `ItemLineAlignment` gap)
require("./stack_distribution.spec")
-- §2.2 the ROW grid: `UI.GridRow` turns `UI.Grid` into SwiftUI's Grid/GridRow pair
-- (column n is the widest natural cell in column n across every row, `gridSpan`
-- covers several columns and widens none of them), selected by the children — and
-- the flow grid every existing caller has stays byte-identical, pinned first
require("./grid_row.spec")
-- ...and `flow = "column"`, COLUMN-MAJOR wrapping — a MODE of the one flow-grid
-- arithmetic, not a second one. The solver's flow grid is written in LANE/FLOW
-- terms and binds those two words to width/height exactly twice, so a column-flow
-- grid is provably the TRANSPOSE of the row-flow grid it mirrors (this spec's
-- central case). It is what a `LazyHGrid`'s mounted band can be
require("./grid_column_flow.spec")
-- round 3 item A: FLOW-WRAP. `UI.HStack{ wrap = true }` / `UI.VStack{ wrap = true }`
-- — Roblox's `UIListLayout.Wraps`, which LuauUI had no spelling for. One prop, one
-- native arrange branch (never a public `Layout` protocol — see the round-3 design
-- doc's Phase 0 verdict), and NO new alignment vocabulary: the engine's cross-axis
-- rule was measured live and it is `align` for the block of lines and `lineAlign`
-- for an item inside its line. The line partition is a PURE function, cached on
-- the ctx exactly as `gridColumnPlan` is, so the two passes cannot disagree
require("./flow_wrap.spec")
require("./geometry_solve_coalescing.spec")
-- a measure→publish cycle settles inside ONE flush (optimization-log L-31): the
-- general shape behind L-29 residual 1, which the 2026-08-14 device capture
-- priced at ~4 of 7.12 solves per step. Two arms in every case — with the round
-- trip and without — so a change that slows both cannot pass
require("./measure_publish_settle.spec")
-- view lifecycle hooks + the space-reserving hide (round 3, item D): the two
-- capabilities the completeness audit ranked highest per line of work —
-- `onAppear`/`onDisappear` (zero hits in `src/` before this) and `hidden`,
-- which is the one thing neither `UI.When` nor the engine's `Visible` gives
require("./lifecycle_hooks.spec")
-- §2.1 SILENTLY-INERT PLACEMENT PROPS. `anchor`, `offsetX`, `offsetY`, `alignH`,
-- `alignV`, `lineAlign` and `gridSpan` are shared BOX props — legal on every node
-- — but each is an instruction addressed to a particular kind of PARENT, and
-- every arrange branch reads only the ones it knows. Everywhere else the prop was
-- ACCEPTED AND THEN IGNORED, which constitution §4 forbids. The child cannot
-- catch it (it does not know its parent at its own construction), so the parent
-- does: `solver.auditPlacement`, called from `renderer.toLayoutNode` and reported
-- through `controller.diagnostics()`
require("./placement_audit.spec")
-- §2.5 `containerRelativeFrame`: a fraction of the nearest ancestor VIEWPORT
-- rather than of the parent's offer — including the measure memo's cache key,
-- which this is the first input to genuinely widen
require("./container_relative_frame.spec")
-- a Grid must MEASURE the layout it ARRANGES: the reported width has to re-derive
-- its own column count, or a hug parent hands back a width that adds a row
-- (2026-08-08 report, "content overflows this vstack by 200px")
require("./grid_measure_arrange.spec")
-- ...and the same fixed-point rule for a hug ScrollView vs its own bar reserve
require("./scroll_bar_measure.spec")
require("./scroll_indicators.spec")
require("./zstack_fill_diagnostic.spec")
-- THE ALWAYS-ON OVERFLOW SWEEP (device bug round 2026-08-12, Group B). Every
-- showcase surface — 25 gallery scenarios, 7 tutorial examples, 5 reference
-- proofs — mounted at the five recorded device-matrix viewports plus the
-- narrowest supported one in BOTH orientations, under the showcase's own picker
-- reservation, failing on `controller.diagnostics()`' main-axis overflow. The
-- lesson this closes (docs/lessons/the-solver-already-told-you.md) is not "read
-- the diagnostics" — §13 already said that — it is that nothing in the suite
-- FAILED on them, so the answer sat unread through a green suite, a green gate,
-- a five-view matrix and four reviews, twice
require("./overflow_sweep.spec")
-- ...and its twin question at the same viewports: is the content each tutorial
-- example DECLARES actually rendered? The overflow sweep sees content that spills
-- out of its box; it is blind to content that left the tree, or that is arranged
-- to a zero rect because it ended up inside a losing `ViewThatFits` candidate —
-- which is exactly how `06_tile_game`'s score and progress readouts left their
-- published paths for a whole mission under a green suite (2026-08-13)
require("./example_readouts.spec")
-- ...and the paint half of the same round: a padded `UI.Text` is drawn INSIDE its
-- padding. The solver's text measure had always added it to the box; the renderer
-- and both adapters only ever painted a Button's, so a padded label sat flush
-- against its own plate's leading edge (device report IMG_3691, the S1..S12 tiles)
require("./text_padding_paint.spec")
-- ...and the INSTRUMENT the same round found missing: a scroll host's engine
-- WINDOW is narrower than its own frame by the bar thickness even where the
-- layout reserve is zero, so content can be laid out correctly and still be
-- clipped. The fake target models the window now, and the disagreement between
-- the published reserve and the instance thickness is measured and pinned
require("./scroll_window_clip.spec")
-- the namespaced-icon ASCII floor the api contract promised
require("./icon_ns_glyph.spec")
require("./adaptive.spec")
require("./button_complete.spec")
-- the circle Button (feature round 2026-07-26)
require("./button_shape.spec")
require("./compact_label.spec")
require("./value_controls.spec")
require("./rating.spec")
require("./display_controls.spec")
-- parity round 3 D2: the circular progress indicator, both forms — the geometry,
-- the paint-only contract, the zero off-path cost and the per-theme stroke fit
require("./progress_circular.spec")
require("./theme_package.spec")
require("./theme_snapshot.spec")
require("./theme_roles.spec")
require("./theme_drift.spec")
-- roadmap Step 10: the same rule for the TUTORIAL EXAMPLES, and property-aware
-- rather than a number ban — an invented `surface` token is as much a bypass as
-- a px text size, and it is the one that made the word-game board invisible
require("./example_drift.spec")
-- theme controller specs (package 2)
require("./theme_controller.spec")
-- a theme commit repaints what NO rule can express: the tint channel and a
-- UI.Path's stroke role (director report 2026-08-14, "the spinner stayed blue")
require("./theme_paint_repaint.spec")
-- theme chrome/reference specs (package 3)
require("./theme_chrome.spec")
-- a decoration is compensated for the padding its host ACTUALLY has (director
-- device round 2026-08-13, `cutoff.png`: the Compact Pointer tray plate's left
-- border clipped away by the Table body, because its full-bleed was computed
-- from the Button's CREATE-time padding and the authored one arrived after)
require("./chrome_padding_refit.spec")
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
-- ...and G-1, the one capability a Fusion user lost outright (ADR-0033): a
-- DURATION with a CURVE, evaluated by the engine's own `TweenService:GetValue`
-- in production and by a pure twin — pinned to the engine by a differential
-- oracle — under Lune
require("./motion_tween.spec")
require("./motion_timeline.spec")
-- ...and the ACCESSIBILITY half of motion: the player's reduced-motion setting
-- reaching the render target with no consumer wiring (C1, 2026-08-12)
require("./reduced_motion_seam.spec")
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
-- the AUTHORED half of that seam: UI.sensoryFeedback(bp, { trigger, event })
-- (docs/plans/swiftui-parity-round2.md §3.3), and the opt-in, default-off client
-- haptics adapter that is one possible SUBSCRIBER to it — LuauUI still plays
-- nothing
require("./sensory_feedback.spec")
require("./haptics.spec")
-- ...and the PER-CONTROL form of the same modifier — UI.sensoryFeedback(bp,
-- { activation = verb }) — which cascades down the mounted tree and replaces the
-- verb a press emits (director request 2026-08-13; swiftui-parity.md §7.1)
require("./control_feedback.spec")
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
-- row actions: pure swipe state decisions for row-action composites
require("./row_actions_state.spec")
-- row actions: the newRowActions composite skeleton (spec, lazy trays, static reveal)
require("./row_actions.spec")
require("./row_capability_optouts.spec")
-- ...and the SHOWCASE surface for that family (parity round 3 item C, standing
-- rule 4): the fixture a player opens, its three refusals driven through a real
-- tap / a real swipe / the public move funnel, the live line that says WHO
-- refused, and the geometry under every shipped theme and a 1.4x pseudo-locale
require("./row_capabilities_scenario.spec")
-- row actions: the mouse gesture (axis lock, live drag, flick velocity, full-swipe commit)
require("./row_actions_input.spec")
-- row actions: HOSTED mode (perf mission Task 2) — `buildHosted`, the same
-- engine with no blueprint at all: the host owns the hit surface, paints the
-- slide, drives the collapse and builds one shared tray overlay from trayState
require("./row_actions_hosted.spec")
-- row actions: the mail-style gallery scenario (Task 11) — builds/mounts clean,
-- every scripted step drivable, both surfaces' actions proven end to end
require("./row_actions_scenario.spec")
-- row actions: THE FLIGHT (device bug round 2026-08-12, Group C). Six
-- motion-quality findings from a phone that a settled-state assertion structurally
-- cannot see; every check here is a statement about a recorded per-frame trace
require("./row_actions_motion.spec")
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
-- ADR-0025: the SCREEN-ANCHORED HUD — the nine anchors as a partition that cannot
-- overlap, `holdsLane` (rule 9's counterpart), rank degradation under a HEIGHT
-- shrink, and the collision alarm for the one case a partition cannot remove
require("./hud_composition.spec")
-- THE CLOSED-KEY SWEEP (ARCH-1): every composite control spec and every
-- service/model opts table refuses an unknown key, naming the boundary, the key
-- and the legal set — and still accepts the legal call it was derived from
require("./spec_guard_sweep.spec")
-- THE TYPOGRAPHY WEIGHT CHANNEL (F2): `strong`/`numeral` as first-class roles,
-- and the invariant that makes them a role rather than a `weight` prop — the
-- descriptor the solver MEASURES with is the descriptor the adapter PAINTS
require("./typography_weight_roles.spec")
-- swiftui-reference-app-validation: the five clean-room reference proofs
-- swiftui-parity round 2 Phase 1: presenter.withAnimation — the paint layer
-- travels while the solver stays exact and instant
require("./with_animation.spec")
require("./animation_precedence.spec")
-- swiftui-parity round 3, ADR-0026: AUTHORED presentation — opacity/scale/
-- rotation as a second TERM in the presentation channel rather than a second
-- writer, and withAnimation reaching all three
require("./authored_presentation.spec")
-- ADR-0035 / owed row O-26: the player's Background Transparency preference,
-- honoured by the one paint path that has a see-through background to honour it
-- with — and the named refusals that keep it from becoming a blanket multiply
require("./preferred_transparency.spec")
-- ADR-0028: the CROSS-SURFACE overlap alarm — two independently mounted
-- surfaces covering each other with neither declaring that it means to
require("./surface_overlap.spec")
-- director report 2026-08-15: the shipped HUD fixture on the three axes nothing
-- else sweeps — a viewport that changes UNDER a mounted tree (every other sweep
-- mounts fresh per viewport, so none of them could see a rotation defect), the
-- app's own chrome declared through `appChromeRects`, and the drawn URL bar
require("./hud_chrome_rotation.spec")
require("./reference/glade_spec")
require("./reference/cartwheel_spec")
require("./reference/sipworks_spec")
require("./reference/foyer_spec")
require("./reference/wardrobe_spec")
-- swiftui-parity round 2 Phase 6: the fast tier's guards — the tier is derived
-- from THIS file's require list, every exclusion must name a spec this file
-- really runs, and the inner-loop runner has to keep announcing itself
require("./tier.spec")
require("./selection_indicator.spec")
-- navigation-and-menus D6: the segmented Picker's upgrades — icons on `Option`,
-- the vertical rail, and the indicator adopted as the segmented default
require("./picker_segments.spec")
-- D2: the freestanding action menu — verbs not values, the shared row recipe,
-- submenus that nest without a cap, and the five triggers that close `.contextMenu`
require("./menu.spec")
-- D3a: `help` — pointer hover-dwell and keyboard/gamepad focus, NOTHING on
-- touch, and a reachability check that no declaration can waive
require("./help.spec")
-- D3b: `Callout` — the app-pushed coach mark, its eligibility/invalidation
-- contract, the caller-owned persistence boundary, and the non-blocking proof
require("./callout.spec")
require("./tab_view.spec")
local ok = testkit.run()
if not ok then
	process.exit(1)
end
