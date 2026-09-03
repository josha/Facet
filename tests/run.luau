--!strict
-- Facet test entry point. Run with:  lune run tests/run   (from GameStudio/ui/Facet)
-- or ./run-tests.sh. Requires each spec, then runs. Same testkit as the games use.

local process = require("@lune/process")
local testkit = require("./lib/testkit")

-- Register all specs. Add new spec files here.
require("./smoke.spec")
require("./conformance/conformance.spec")
require("./replication.spec")
require("./layout.spec")
require("./transform_footprint.spec")
require("./focus.spec")
require("./mount.spec")
require("./node_facts.spec")
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
-- ...and its CROSS-SOLVE half (perf campaign P1): the demonstrator counter, and the
-- three-arm differential (memo / memo-less incremental / forced full solve) over
-- every axis a solve boundary adds — structure, offer, viewport, theme, text metrics
require("./measure_reuse.spec")
-- ...and P2's half of the same solve: the rect map is the PREVIOUS solve's, so a
-- skipped subtree costs a return instead of N inserts. The insertion counter, the
-- aliasing and canary cases, and the same full-solve differential over the matrix
require("./rect_cow.spec")
-- ...and P3's: the `solver.Node` tree is PATCHED on dirt instead of rebuilt from the
-- mounted tree every solve. The build counter, the zero-build re-solve, the applied-
-- theme case (emission is not application), the structural bound, the three-arm
-- differential over the device matrix, and the four axes driven against
-- `layout_node.build` directly — including the weak-key premise the store's bound rests on
require("./node_reuse.spec")
-- ...and P4's: the COMMIT is driven off the same two signals instead of walking the
-- live tree seven times to make four writes. The visit counter, the ordered
-- adapter-op differential against a full-walk arm over the device matrix, the two
-- axes the other three files do not have (the solve-wide stamp and the scroll
-- canvas), the hide a clean subtree has to inherit, and the census that licenses the
-- predicate
require("./commit_scope.spec")
require("./structural_scope.spec")
-- ...and the audit that relates the two files P1's CRITICAL 1 fell between: every
-- `props.<name>` layout_node reads, walked against that prop's declared dirty classes,
-- because a solver-consumed prop declared paint-only is a geometry change no solve
-- is ever provoked for
require("./layout_prop_dirt.spec")
-- content-terms height (framework-gaps-phase2 gap 3): the closed
-- construction grammar, `of`'s metric resolution, the solver arithmetic for
-- both `lines`/`rows` shapes, the nested-scroll-diagnostic regression fix,
-- the four migrated adaptation-slice sites, and UI.fill/UI.hug (item 14)
require("./content_terms_height.spec")
--[[ the measure helpers' SEAM (2026-08-21, source-cap-ledger): what keeps
	`layout/measure_facts.luau` one-way now that `solver.luau` has stopped being
	one file. There is no parameter object to compare — everything arrives on the
	solve's own `ctx` — so the three sets are the `ctx` fields the module READS,
	the ones its `MeasureCtx` DECLARES and the ones the solver's `Ctx` still
	HOSTS, plus the four-name write surface, the exports against the binding
	block, and that the module holds no module-level mutable state ]]
require("./composition_resolve_seam.spec")
require("./measure_facts_seam.spec")
--[[ ...and the THIRD solver seam (2026-09-02, the RED-TEAM fix wave): the Stage 1
	report left before the wave's own change landed, because the ledger row's trigger
	is a STATE and the two seams it still named had both already been taken. It is
	the cheapest of the three — no `Deps`, no `ctx`, no require at all — so the spec
	pins that emptiness, the one consumer, the one export against the re-export, and
	that nothing stayed behind in the solver ]]
require("./boundary_report_seam.spec")
--[[ ...and the FOURTH solver seam (2026-09-02, the wicked-fast round): the four
	reports a node makes about its OWN resolved box, taken so the translate arm had
	Source-write headroom to land in — and this one left with no `Deps` at all, only
	the values `arrange` already holds on the calling line. The spec pins that
	emptiness, the CLOSED ctx/node/rect field sets, the one consumer, the one export
	against its one call site, that none of the four messages stayed behind, and that
	the module holds no mutable state ]]
require("./arrange_reports_seam.spec")
--[[ ...and the FIFTH solver seam (2026-09-02, the wicked-fast round again): the
	whole vstack/hstack ARRANGE branch — 15,821 characters, the largest block this
	file has ever given up, and the one the source-cap ledger's row has named by name
	since the T4 split. It took the widest `Deps` record in the file plus TWO
	call-site arguments (`arrange`, `noteContainment`), so the spec pins READ ==
	DECLARED == PASSED as three sets, the READ-vs-WRITE free-variable list (it assigns
	no field of ctx/node/child at all and inserts into exactly one list), that the two
	call arguments are not Deps fields, the three leaf requires, the one consumer, the
	one export, that nothing stayed behind, and that the module holds no state ]]
require("./stack_seam.spec")
--[[ ...and the ANCHOR ARRANGE'S THIRD ARM (wicked-fast T6): a non-dirty anchor child
	offered exactly what it was offered last time takes its w/h from its own previous
	rect instead of a `measure` call. The spec pins the two new work counters on an
	hp, an add and a remove, the NEGATIVE CONTROL that a tick (which dirties every
	plate) fires the arm for none of them, that the dirty chain's own arranged/measured
	are untouched, the allocation record — which is NOT the one the task brief
	predicted and says so with the four-arm attribution — and a three-arm oracle over
	nine device views, three fixtures and eight step kinds INCLUDING a viewport change,
	which is the step that makes every recorded offer stop matching ]]
require("./anchor_arrange.spec")
--[[ ...and the renderer's THIRD seam of the same round (2026-09-02): WHICH env facts
	are geometry for a root policy, and WHEN two readings of them are the same. They
	left together because they are one decision — a key added to the list and not
	taught to the comparator is a surface gone deaf to a fact — and the spec pins that
	pairing, the two measured policy narrowings, the caller-owned list, and the memo
	the renderer kept ]]
require("./geometry_facts_seam.spec")
--[[ ...and the RULE THE SAME REVIEW ROUND FOUND MISSING (2026-09-02, finding 9): the
	campaign shipped four attach options and `docs/reference/api.md` documented one, so
	every key `ATTACH_OPTS_KEYS` accepts is now required to be named — with its default,
	its mechanism and what OFF means — in the reference section a reader reaches by
	looking up `attach`, in both directions ]]
require("./attach_opts_documented.spec")
--[[ ...and the ENUMERATION both seam specs asked their one-consumer question over
	(rulings P5 + PRES-X minor): it was a hand-written list of nine directory names
	against a `src/` that has fifteen and thirteen top-level files, so the second
	consumer those rules exist to notice could have appeared in a dozen places and
	still read "exactly one". ]]
require("./src_tree.spec")
--[[ the surface-lifecycle SEAM (2026-08-22, source-cap-ledger): what keeps
	`present/surface_lifecycle.luau` one-way now that `presenter.luau` has stopped
	carrying the focus-visual sync, the refresh body and the dismissal pair. This
	seam DOES have a parameter object, so the three sets are the record's keys as
	the presenter HOSTS them, as the module DECLARES them and as its body READS
	them — plus the one-name write surface, `EXPORTED == BOUND` in both
	directions, no module-level mutable state, and the rule this document's other
	seams did not need: that `displayLayer` stays ONE record with two writers ]]
require("./surface_lifecycle_seam.spec")
require("./fine_grained_reactivity.spec")
--[[ the reactive core's RECOVERY half (release-candidate review RR-1..RR-11):
	whether a memo that failed, an effect that disposed itself, or a settle
	callback that would not converge can ever be well again — plus the two
	diagnostics (cycle path names, a disposal that strands subscribers) that had
	nothing to act on ]]
require("./reactive_recovery.spec")
--[[ the PLATFORM ADAPTER driven by a fake engine (release-candidate platform
	review PLAT-1/RR-6, PLAT-2, PLAT-3): the connections `roblox_env.bind` claims
	to make, and the safe-area arithmetic it publishes ]]
require("./platform_env_binding.spec")
--[[ ...and what the POINTER seam owns vs borrows (PLAT-4/5/6): the adapter-wide
	menu connection a single root teardown used to kill, the host cursor every hint
	clear used to erase, and the second finger that drove another finger's drag ]]
require("./pointer_seam_ownership.spec")
--[[ ...and the ADAPTERS' recovery and honesty contracts (PLAT-7/9/11/21/22/24/
	25/26): the resnapshot gap that could not come back, the remove shape that
	removed nothing, the unbind that claimed a freedom it had not won, the shared
	engine property two binders each thought they owned ]]
require("./platform_adapters_recovery.spec")
--[[ MAINT-5: adding a blueprint PRIMITIVE touches four registries nothing used
	to compare — the schema, class_contract, CLASS_TO_INSTANCE and the create()
	branch on both targets. `tools/lune/check_primitives` compares them, and the
	mutation cases here are what say it can still see each kind of drift ]]
require("./primitive_registration.spec")
--[[ SCREEN-X: a prefix test that compares a different number of characters
	than its own literal is a CONSTANT, so the branch behind it is dead and
	nothing says so. The two renames (`luau-` -> `facet-`, five characters
	to six; `LuauUI` -> `Facet`, six to five) left three of them — the adapter's
	tag-REMOVAL loop among them. Scanned repository-wide, with the scanner's own
	negative control, and the adapter's tag ownership pinned as ONE named fact ]]
require("./prefix_tests.spec")
--[[ ...and the BEHAVIOUR that lint stands in for: mount a Button, change its
	state, and assert the classification tag came OFF. The decision is
	`render/tag_sync`, a pure module both targets call; `fake_target` gained the
	narrow tag mirror it never had, which is why the defect was invisible ]]
require("./tag_sync.spec")
--[[ MAINT-8c: six hand lists of examples/themes/ and nothing enumerated the
	directory. One enumerator with declared roles, two consumers derived from it,
	the rest drift-checked ]]
require("./theme_package_enumeration.spec")
require("./instance_recycling.spec")
require("./mount_unmount_soak.spec")
-- ...and the THEMED half (L-28): park releases the chrome's path keys, adopt
-- re-keys them, and a decoration-hint or package mismatch refuses the adoption
require("./instance_recycling_themed.spec")
require("./instance_park_corpse.spec")
--[[ ...and the recycle-key seam (wicked-fast T8 R2's Phase 0): `recycleKey`,
	`propSignature`, `wornSignature`, the worn-set updater and the parts
	bookkeeping left the renderer for `render/recycle_key.luau` — pure over
	`prop_channels` + `chrome_slots.hintKey`, no Deps record at all, the
	strongest one-way claim any seam here has reached. ]]
require("./recycle_key_seam.spec")
--[[ ...and W1/W1b (wicked-fast T8): `propSigCache` deleted, then the park-time
	key rebuilt from a live worn set instead of a string frozen at create — see
	the header for the full W1 -> W1b -> R2 history and the self-review finding
	each round closed. ]]
require("./recycle_prop_signature.spec")
require("./incremental_layout.spec")
require("./diagnostic_replay.spec")
require("./container_relative_incremental.spec")
require("./perf_principles.spec")
require("./layout_v1.spec")
require("./renderer.spec")
require("./edge_floor.spec")
--[[ the commit walks' SEAM (2026-08-21, source-cap-ledger): what keeps
	`render/commit_walks.luau` one-way now that the six write loops that spend a
	finished solve have left `renderer.luau`. This seam has a parameter object
	with twenty-one fields in it, eight of them mutable records the renderer keeps
	writing to, so the three sets are READ == DECLARED == PASSED plus the
	twelve-name shared write surface, the lifetime owner of each shared record,
	and the mutable-upvalue test applied to the twenty-one names themselves ]]
require("./commit_walks_seam.spec")
require("./native_scroll.spec")
-- O-31: a virtualised collection mirrors its engine CanvasPosition with NO
-- post-`present` consumer call, on the two contribution seams that reach every
-- presenter configuration (`bindController` + `syncGeometry`)
require("./native_scroll_autobind.spec")
-- desktop keyboard focus chain (roadmap Step 8): Tab/Shift+Tab traversal,
-- Space-as-Activate, focused-value arrow Adjust
require("./keyboard_navigation.spec")
require("./traversal_order.spec")
-- ADOPTED CHROME (device review 2026-08-16, F1): the capability that lets a
-- directional press leave the active scope for the app's persistent frame — one
-- composed focus map, opt-in, entry still the active screen's, suspended by a
-- trap, and the press routed to the surface that owns the node
require("./focus_chrome.spec")
require("./path.spec")
-- UI.Stage (ViewportFrame adoption, 2026-08-08): the engine-content leaf plus
-- its renderer-mediated content seam (camera/lighting/content root)
require("./stage.spec")
-- UI.Foreign (docs/reference/api.md §Foreign): the bounded escape
-- hatch to a GuiObject class Facet does not wrap — one box, one claim
-- (`Foreign.Parent`, on the reserved `host` authority), everything else the
-- caller's
require("./foreign.spec")
require("./async_image.spec")
require("./selection_bridge.spec")
require("./text_calibration.spec")
require("./text_degrade_cascade.spec")
require("./text_fit.spec")
-- the headless measurement entry point (framework-gaps-phase2 gap 11):
-- `src/measure` is reachable with none of `src/init.luau`'s 65 `@self`
-- requires, so a pure shared model (RR's HudZoneModel among them) can depend
-- on measurement alone; plus a demonstration for registry item 31
require("./measure_entry_point.spec")
--[[ THE DECLARATIVE FACE OF THE SAME QUESTION (`textSize = "fit"`, audit §10 of
	framework-gaps-phase2 — the one gap in that audit that was shipping wrong pixels).
	The first block MEASURES the class the prop closes: a line box computed at 1.25
	against the library's declared 1.2, and a reserve that ignores
	`max(typographyScale, typographyPaintScale)` and is therefore short by the
	ladder's own factor at ten-foot. The rest drives the whole shipped path, because
	the claim is that four seams cannot disagree about the size. ]]
require("./text_size_fit.spec")
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
-- the presenter-side surface-chrome seam (framework-gaps-phase2 item 13,
-- W3-D): the pure back+title+trailing bar factory
require("./nav_bar.spec")
require("./controls_conformance.spec")
require("./hint_no_remount.spec")
require("./icon_box.spec")
require("./chrome_inset_yield.spec")
require("./slice_mutation.spec")
require("./focus_structural.spec")
require("./table.spec")
require("./table_virtualized.spec")
--[[ the row/cell builder's SEAM (2026-08-18, source-cap-ledger): the parameter
	object that made `controls/table_rows.luau` one-way, pinned as a set
	comparison — every fact READ off `deps` is DECLARED and PASSED, the shared
	write surface is exactly the two mutable containers, and the require does not
	come back. A parameter object rots silently; this is what notices ]]
require("./table_rows_seam.spec")
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
--[[ the WORLD SURFACE target's pure half: the canvas rect the solver
	is handed, every argument it refuses and whether the refusal says WHY, and that
	each capability it deletes is one the contract actually declares. It has a spec
	at all because it resolves `screen_target` inside `new` rather than at module
	scope — `billboard_target` does not, and therefore cannot be loaded headlessly ]]
require("./surface_target.spec")
--[[ ...and the SURFACE the target exists for: the outpost power
	terminal's pure half — every range walked over the whole 4x3x5 product, every
	refusal sentence, the server's five checks through `rules.authorize`, and the
	engage -> adjust -> apply -> success -> reset -> exit machine. The engine half
	(console, prompt, second host, responder handoff) is Studio evidence ]]
require("./outpost_terminal.spec")
-- the per-node presentation channel + the SF-M9 live-adapter fix
require("./presentation_channel.spec")
-- ...and the REAL-PARENT REGISTRY it composes against: one
-- registration function, a longest-path-prefix lookup, and the cost pin that
-- decides whether "register more hosts" is affordable at all
require("./instance_hosts.spec")
-- ...and THE WRITE A HOST MAKES UNNECESSARY (the arrange half): the
-- live `applyRect` driven for real, counting engine Position/Size writes, with
-- the A/A and no-host controls that stop "never write anything" from passing
require("./host_move_write_cost.spec")
-- ...and the INSTRUMENTS the nested-tree migration is measured against (step 2),
-- written while the tree is still flat because they are worth nothing after: the
-- DFS-counter-is-Sibling-order equivalence, tapAt-agrees-with-the-counter, and
-- the two cases step 4 is EXPECTED to turn red
require("./nested_tree_pins.spec")
-- ...and the showcase surface for both capabilities (brief item 7): a real
-- instance host's group opacity beside its rotation/scale carry, registered in
-- scenarios/init.luau ORDER, demo_picker.DEMOS and this file's own SCENARIOS list
require("./nested_compositing_scenario.spec")
-- the authored paint escapes: tint, scaleMode, UI.stroke, zIndex
require("./paint_extensions.spec")
-- fractional Anchor offsets: the marker-overlay shape (SF-P5)
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
require("./collection_gap_tokens.spec")
require("./collection_self_measure.spec")
require("./virtual_list_axis.spec")
require("./virtual_list_focus_policy.spec")
-- the LYING `itemExtent` guard (2026-08-13): a fixed-pitch window is only exact
-- while the declared extent is the true one, and until this nothing checked the
-- consumer's prediction against what its own row actually measures
require("./virtual_list_slot_guard.spec")
require("./virtual_grid.spec")
require("./virtual_grid_input.spec")
-- ...and the SIDEWAYS half, `newVirtualGrid { axis = "x" }`.
-- It exists because `UI.Grid` learned to wrap COLUMN-MAJOR (`grid_column_flow.spec`),
-- so the horizontal band is a real `UI.Grid` with the lane formula EXECUTING, never a
-- second lane arithmetic inside the control. Its ring transposes the OPPOSITE way from
-- a list's: a grid's declared group axis is the LANE axis, perpendicular to the scroll,
-- so Down steps ONE CELL here and Right steps a whole LINE
require("./virtual_hgrid.spec")
require("./navigation_groups.spec")
-- ...and the mechanism BOTH grids stand on: a NavigationGroup may
-- declare `columns`, and the focus graph then answers the direction perpendicular
-- to the lanes itself, by a whole line. This is what deleted the two intercepts
require("./focus_grid_axis.spec")
require("./perf_runner.spec")
-- evidence-class discipline: the rules that stop a headless number becoming a
-- device claim (roadmap Step 4, UI-PERF-002)
require("./perf_evidence.spec")
-- the wicked-fast round's BEFORE numbers, pinned on disk (T2): the arena's
-- workload as a headless fixture, so later commits in this round demonstrate
-- against a "currently N" nobody has to remember from a profiling run
require("./nameplates_baseline.spec")
-- ...and the round's first optimization (T3, O2): `dirtyContains` split into a
-- measure half and an arrange half, so an offset-only step keeps the measure
-- slates it cannot have invalidated. The counter demonstrator with its plan-verdict
-- buckets, the three-arm oracle over every device view and both step kinds, and the
-- opposite direction — a real measure change still refuses a slate
require("./measure_split.spec")
-- ...and the round's second (T4, O3): `arrange` gains a TRANSLATE arm, so a subtree
-- whose size is unchanged and whose origin moved is re-based by one delta instead of
-- being re-entered. The counter demonstrator, the root-rect pin no counter can make,
-- the heap pin that catches a `prev` chain leak, the three self-placement defects the
-- arm had without `selfPlaces`, and the three-arm oracle
require("./translate_arm.spec")
-- ...and the round's third (T5, O4 + N1): the COMMIT under a translate. Six walks
-- whose output cannot read a position ask `skip(node, true)` and prune a moved
-- subtree away; `rect_pass` stops AT each translate root and emits the solver's flat
-- run instead of walking for it. The eight-walk counter demonstrator (ticked twice,
-- so a stale `lastCommitEntry` is visible), the caster column the plan predicted
-- wrong, and the FOUR-arm oracle whose fourth arm turns the commit prune itself off
require("./commit_translate.spec")
-- ...and the round's fourth (T5b): the COMMIT'S DIRTY SET IS NOT THE BUILD'S. A
-- second, narrower set omits the seven props that move a node and change nothing a
-- walk reads, and `skip` picks by the walk's own `arrangeBlind` claim, so four walks
-- leave the dirty closure entirely. The prop -> walk read audit is executable rather
-- than a comment: a driver over all seven props on BOTH the container and the LEAF
-- shape (the classes each walk actually writes for), a scan of every walk body out
-- of the source, a schema round trip on the dropped set, and the T5 oracle plus
-- hide/unhide and a placement prop on a Text leaf
require("./commit_dirt_classes.spec")
-- the future spatial seam: contracts only, and the guard against a VR claim
-- appearing in the shipped surface (roadmap Step 4, UI-SPATIAL-001)
require("./spatial.spec")
-- the five-view device-matrix selection policy, fed a recorded live catalog
require("./matrix_rows.spec")
require("./error_boundary.spec")
-- `UI.sortedEntries` (docs/reference/api.md §sortedEntries): the deterministic
-- dictionary flatten `UI.ForEach` needs, and the negative control that proves
-- Luau's `pairs` order really does move with a table's construction history —
-- twelve keys, because at six the constructions agree and prove nothing
require("./sorted_entries.spec")
require("./styling.spec")
require("./sheet_model.spec")
require("./native_style_scenario.spec")
-- the DEFAULT paint path (director ruling 2026-08-21): sheet
-- paint is what a target with no `nativeStyle` opt takes, the explicit `false`
-- escape hatch survives, and the gallery's A/B precedence survives with it.
require("./native_style_default.spec")
require("./api_surface.spec")
require("./extension_checker.spec")
require("./examples_gallery.spec")
require("./gallery_theme_picker.spec")
-- the showcase demo picker: one published place, switchable in-game
require("./gallery_demo_picker.spec")
-- ...and the showcase HOST PATH the picker feeds (2026-08-20): every demo mounted
-- through the shipped per-demo core proxy, which is where two adaptive controls
-- died live under a green suite because every other spec builds a bare core
require("./gallery_demo_host.spec")
-- ...and the CHROME around it (parity round 3, item E rows 4 and 11): four-input
-- reachability driven through the real key/pad path rather than asserted from
-- source text, the two-chip ViewThatFits ladder, and the persistent
-- Full | Reduced motion setting the reduced-motion axis of a device canary needs
require("./gallery_chrome.spec")
-- THE DIRECTOR'S STANDING RULE (round 3, 2026-08-21): a transient opened from a
-- control appears OVER the live screen and the live screen stays visible behind
-- it — asserted over the whole anchored-surface family, plus the theme's own
-- scrim being translucent by contract
require("./transient_over_live.spec")
-- ...and WHICH of those surfaces a place boots at all (2026-08-20): the §5
-- scenario/example selectors outrank the demo shell, and a selector that cannot
-- be honoured warns instead of booting something that looks like a passing run
require("./gallery_boot_mode.spec")
require("./examples_games.spec")
-- the word game's PURE rules and state machine (roadmap Step 10, EQ-9): the
-- two-pass letter budget across every duplicate shape, refusals that do not
-- consume a row, monotonic key state, win/loss, and the deterministic seed
require("./example_word_game.spec")
-- ...and the DATA both word games now run on (stage example-games-and-standalones):
-- a pinned licensed source, the two sets its filters produce, the per-file hashes
-- that catch a hand-edit, the ascending order the bisection depends on, and the
-- measured lookup cost. The words the old thirty-four-entry list refused are a
-- case of their own, because they were the reason for the replacement
require("./example_word_data.spec")
-- ...and the CROSSWORD's own rules and machine (stage example-games-and-standalones):
-- the bag, the seeded deal and its guaranteed opening, the axis, the unbroken run,
-- the centre and the connection, every word a turn creates and what it scores, the
-- nine refusals as nine exact sentences on screen, both endings, a seeded replay,
-- and the forty-nine board plates measured against the page in every shipped theme
require("./example_tile_game.spec")
-- ...and the MATCH-3 board's MOTION (stage example-games-and-standalones): tile
-- identity across a move, the painted middle of a swap, the removal/gravity/refill
-- ordering, a reset mid-cascade, full/reduced parity with no branch to keep agreeing,
-- a scan for a second animation system, and thirty-six tiles measured against the
-- page in every shipped theme
require("./example_match3_motion.spec")

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
require("./virtual_list_hosted_seam.spec")
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
-- gamepad d-pad auto-repeat (director item 4): holding a direction
-- advances focus repeatedly after the initial delay, gamepad-only, through
-- the same navigate/navigateH functions a fresh press uses
require("./dpad_repeat.spec")
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
-- §2.2 the ROW grid: `UI.GridRow` turns `UI.Grid` into the Grid/GridRow pair
-- (column n is the widest natural cell in column n across every row, `gridSpan`
-- covers several columns and widens none of them), selected by the children — and
-- the flow grid every existing caller has stays byte-identical, pinned first
require("./grid_row.spec")
-- ...and `flow = "column"`, COLUMN-MAJOR wrapping — a MODE of the one flow-grid
-- arithmetic, not a second one. The solver's flow grid is written in LANE/FLOW
-- terms and binds those two words to width/height exactly twice, so a column-flow
-- grid is provably the TRANSPOSE of the row-flow grid it mirrors (this spec's
-- central case). It is what a sideways grid's mounted band can be
require("./grid_column_flow.spec")
-- round 3 item A: FLOW-WRAP. `UI.HStack{ wrap = true }` / `UI.VStack{ wrap = true }`
-- — Roblox's `UIListLayout.Wraps`, which Facet had no spelling for. One prop, one
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
-- lesson this closes is not "read
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
--[[ THE `hug` TRAP INSIDE A `ViewThatFits` CANDIDATE (framework-gaps-phase2 §2a):
	`hug` caps at the offer, so a hug rung could never report "does not fit" and the
	ladder pinned its first rung at every width. The fix is the ladder's own
	doctrine rather than a refusal — `ctx.fitProbe` already makes every squeezing
	mechanism invisible while a candidate is judged, and the cap is one of them —
	and the sweep here is what says `hug` and `content` now agree at every width. ]]
require("./fits_ideal_size.spec")
require("./button_complete.spec")
-- the circle Button (feature round 2026-07-26)
require("./button_shape.spec")
-- the circle shape generalized to ZStack (task PAINT, 2026-08-27, director item 12)
require("./zstack_shape.spec")
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
-- SHOWCASE2 task A: the same "does the tree actually reach what it claims"
-- discipline, aimed at require PATHS rather than property authority — a
-- gallery/scenario/reference module-scope require that resolves under Lune's
-- file-system semantics but not live Studio's instance-tree semantics (the
-- "All controls" empty-mount defect; second occurrence of the class this
-- campaign, after G7+G11's Rojo mount-depth divergence)
require("./scenario_require_paths.spec")
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
-- the setProp seam, mechanised (task EXTRACT, source-cap-ledger):
-- READ == DECLARED == PASSED over src/client/screen_props.luau + screen_target.luau
require("./screen_props_seam.spec")
-- rich-skinning-v2 schema + model specs (P1)
require("./theme_layers.spec")
require("./theme_variants.spec")
require("./theme_icons.spec")
require("./theme_pixel.spec")
require("./theme_assets.spec")
-- rich-skinning-v2 adapter APPLICATION specs (P2): every P1 emission, proven on
-- the live path (the Step 3.5 lesson — emission is not application)
require("./theme_layer_application.spec")
-- the float focus ring's geometry (device fix round, director 2026-08-23): the
-- ten-foot lift ordering and the native-mode phantom-corner fallback
require("./focus_ring_float_geometry.spec")
-- the activate-handler connection leak on a recycled instance (device fix
-- round, director 2026-08-23): nested-tabs hit targets shifting after a round
-- trip through a sibling app tab
require("./activate_handler_reconnect.spec")
-- task CONN (review-fix234 Findings 1 & 4): every SIBLING `handle.*Conn`
-- reconnect site the activate-handler fix above did not sweep, closed through
-- two shared helpers (`src/client/handle_conn.luau`) and a CENSUS_SLOTS
-- completeness sweep over every named site
require("./conn_reconnect_sweep.spec")
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
-- the maintainer map (docs/MAINTAINERS.md): every production area still points at
-- the src tree, the specs, the scenario, the gate row and the playbook it claims
require("./maintainer_map.spec")
-- sponsor-framework-gaps P1: the motion authority — pure
-- solver, class registry, injectable clock, perceptual arrival, timelines, and
-- the reduced-motion parity rules, all under a scripted clock
require("./motion_spring.spec")
require("./motion_clock.spec")
require("./motion_chase.spec")
-- ...and the one thing a spring structurally cannot promise: a
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
-- surface enter/exit — row SF-M6)
require("./transitions.spec")
-- BACKDROP-BEFORE-CONTENT (framework-gaps-phase2-followups task POP, director
-- item 10 + mandate b): the structural gate for the pop class newpop.mov
-- demonstrated — a canvasGroup fade whose OWN direct child paints an opaque
-- surface can never let that backdrop be legible ahead of its content, because
-- GroupTransparency is one engine scalar over the whole subtree. Pure finder +
-- live coordinator + the real Glade modals (wisp/charm/provisions/picker), all
-- clean after `examples/reference/p1_glade/ui/shop.luau`'s restructuring.
require("./backdrop_fade.spec")
-- the pure toast scheduler and the input-transparent toast surface it drives
-- (rows SF-T1..T3)
require("./toast_schedule.spec")
require("./toast_presentation.spec")
-- the one semantic feedback seam: closed taxonomy, causal frames, exactness
-- (row SF-F1)
require("./feedback.spec")
-- the AUTHORED half of that seam: UI.sensoryFeedback(bp, { trigger, event })
-- (docs/plans/parity-round2.md §3.3), and the opt-in, default-off client
-- haptics adapter that is one possible SUBSCRIBER to it — Facet still plays
-- nothing
require("./sensory_feedback.spec")
-- ...the three Facet waveforms themselves (`contact` / `settle` / `tick`), pinned
-- byte-exactly because they ARE the product and no test can feel them, plus the
-- per-phase override/silence rules and the preset fallback's limitation
require("./sensory_profile.spec")
require("./haptics.spec")
-- ...and the PER-CONTROL form of the same modifier — UI.sensoryFeedback(bp,
-- { activation = verb }) — which cascades down the mounted tree and replaces the
-- verb a press emits (director request 2026-08-13; the comparison document §7.1)
require("./control_feedback.spec")
-- bounded retry with a session give-up, the preload seam, and the AsyncImage dim
-- treatment (rows SF-A1..A3)
require("./async_completeness.spec")
-- sponsor-framework-gaps P4: the shared interaction tokens + the rolling
-- release-velocity tracker (rows SF-D3 / SF-D2)
require("./interaction_tokens.spec")
-- the pure drag-to-edge autoscroll model under a scripted clock (SF-L2)
require("./autoscroll.spec")
-- ...and the RENDERER's chain around it (`render/autoscroll_bridge.luau`, extracted
-- 2026-09-01): the mechanised seam — READ == DECLARED == PASSED, the mutable-upvalue
-- test over the nine names that cross, and the claim that the two reassigned scalars
-- left WITH the code — plus the behaviour the split moved, which had no case at all
-- before it: the dwell, the canvas write, the opt-out, the clip-only fallback and the
-- nested chain rule
require("./autoscroll_bridge_seam.spec")
-- scroll SNAPPING (ADAPT-17, audit cell B-7): the pure resolver in numbers, and
-- the wired list/grid driven through the engine mirror on a scripted clock
require("./scroll_snap.spec")
-- ...and the PARADIGM it exists for (ADAPT-17, cells B-1/B-7/B-8): the compact
-- card rail, defaulted from the facts the host already flows, plus the structural
-- check that a future card surface cannot be silent about compact
require("./paradigm_cards.spec")
-- the public drag/drop contract, driven through the REAL acquisition paths
-- (SF-D1..SF-D5, findings F5/F7)
require("./drag_public.spec")
-- ...and the RENDERER's half of the bridge to that model (`render/drag_bridge.luau`,
-- extracted 2026-09-01, the ledger's named REGISTRY half): the mechanised seam plus
-- the rule no previous seam spec has had to state — the reassigned scalar the ledger
-- said needed a record now has exactly one owner, `peek` may never build and the z
-- table crosses by reference
require("./drag_bridge_seam.spec")
require("./tap_arm_seam.spec")
--[[ ...and the TEXT-PREMEASUREMENT ROUND (wicked-fast T7), the seam the renderer's
	source-cap ledger row has named since the geometry-facts split: the collect /
	deliver / `learned` block plus all three records it owned, behind the three-field
	`Deps` that row predicted. `solveAndApply` crosses AT THE CALL because the round
	re-enters it, so the spec pins that it is NOT a Deps field, plus READ == DECLARED
	== PASSED, the single writer of `disposed`, that the renderer kept no copy and no
	second `adapter.measureTextWidths` caller, and the three accessors driven ]]
require("./premeasure_round_seam.spec")
--[[ ...AND THE SCROLL-INTO-VIEW FAMILY (wicked-fast T8's Phase 0), the seam the
	renderer's own ledger row named next once the text-premeasurement round left:
	`scrollToVisible` + `scrollHostFor` and the keep-visible arithmetic between
	them, behind the six-field `Deps` the read-set scan found — TWO more than the
	row's own four-name prediction, and `handles` was not one of the four after
	all. The write set is EMPTY (both functions call one encapsulated write,
	`controller.scrollTo`, and touch nothing else directly), `controller` crosses
	whole for its `scrollPosition`/`scrollTo` pair, and `../layout/solver` is the
	one leaf require, exactly the `premeasure_round.luau` precedent ]]
require("./scroll_into_view_seam.spec")
--[[ O6 (wicked-fast T7): the STRUCTURAL SYNC takes the delta `refresh` already
	holds. `ensureTree`, `livePaths` and the removal sweep stop being whole-tree; the
	five per-path maps go per-subtree with the old membership snapshotted from the
	per-parent index first, `pathNodeCount` is decremented rather than zeroed, and an
	unbounded delta falls back to the whole tree and says so via `ssFullPasses`. The
	oracle is differential against a forced from-scratch sync at all nine device
	views, and two cases exist only to see the facts a rect oracle cannot: an erased
	scroll host and an emptied `pathNodes`/`pathNodeCount` pair ]]
require("./structural_incremental.spec")
-- row actions: pure swipe state decisions for row-action composites
require("./row_actions_state.spec")
-- row actions: the newRowActions composite skeleton (spec, lazy trays, static reveal)
require("./row_actions.spec")
-- row actions: the dump() seam (task EXTRACT2) — one-way, READ==DECLARED==PASSED
require("./row_actions_dump_seam.spec")
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
-- DECLARED-CONTENT ADAPTIVE COMPOSITION: the pure decision matrix
-- (arrangement choice, step-down/drop order, floors, reserved-at-rest, the
-- one-scroll refusal, the column fallback) plus the mounted re-solve identity
require("./band_policy.spec")
require("./composition.spec")
require("./composition_exclusions.spec")
-- WAVE REVEAL: a region standing on a form below its richest EXPANDS to it — the
-- pure facts (activeForm/richestForm/formInteractive/expand), the plate's size and
-- its sheet fallback, the affordance the framework synthesizes, and the plate's
-- own lifetime. The knob is `expand` because `reveal` is UI.Text's, and one key
-- with two meanings on one surface is the collision this rename removed
require("./region_expand.spec")
-- the SCREEN-ANCHORED HUD — the nine anchors as a partition that cannot
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
-- reference-app-validation: the five clean-room reference proofs
-- parity round 2 Phase 1: presenter.withAnimation — the paint layer
-- travels while the solver stays exact and instant
require("./with_animation.spec")
require("./animation_precedence.spec")
-- parity round 3: AUTHORED presentation — opacity/scale/
-- rotation as a second TERM in the presentation channel rather than a second
-- writer, and withAnimation reaching all three
require("./authored_presentation.spec")
-- owed row O-26: the player's Background Transparency preference,
-- honoured by the one paint path that has a see-through background to honour it
-- with — and the named refusals that keep it from becoming a blanket multiply
require("./preferred_transparency.spec")
-- the CROSS-SURFACE overlap alarm — two independently mounted
-- surfaces covering each other with neither declaring that it means to
require("./surface_overlap.spec")
-- director report 2026-08-15: the shipped HUD fixture on the three axes nothing
-- else sweeps — a viewport that changes UNDER a mounted tree (every other sweep
-- mounts fresh per viewport, so none of them could see a rotation defect), the
-- app's own chrome declared through `appChromeRects`, and the drawn URL bar
require("./hud_chrome_rotation.spec")
--[[ D7 — ELISION MUST DISCLOSE, NOT DELETE. The `recover` contract on UI.Region,
	`elided` + `Resolution.unshown` (the seam an overflow surface reads), the
	authoring error for a `self` route whose reduced form holds nothing focusable,
	and the device-matrix sweep that asserts every region the HUD has stopped
	showing has a LIVE route at every viewport in both URL-bar states. ]]
require("./elision_recovery.spec")
--[[ ...and the two holes that sweep left, both named by the 2026-08-16 device
	review: D7.6 mounts a FRESH surface per viewport, so nothing asked whether the
	path BETWEEN viewports is reversible (a one-way ladder passes every row of it);
	and the recovery route was authored as a hand-written transcription beside the
	forms it discloses, so it reached a lesser thing than the form it was for. ]]
require("./adaptation_reversibility.spec")
require("./reference/glade_spec")
require("./reference/cartwheel_spec")
require("./reference/sipworks_spec")
require("./reference/foyer_spec")
require("./reference/wardrobe_spec")
-- parity round 2 Phase 6: the fast tier's guards — the tier is derived
-- from THIS file's require list, every exclusion must name a spec this file
-- really runs, and the inner-loop runner has to keep announcing itself
require("./tier.spec")
require("./selection_indicator.spec")
-- navigation-and-menus D6: the segmented Picker's upgrades — icons on `Option`,
-- the vertical rail, and the indicator adopted as the segmented default
require("./picker_segments.spec")
-- D2: the freestanding action menu — verbs not values, the shared row recipe,
-- submenus that nest without a cap, and the five triggers that close the context-menu construct
require("./menu.spec")
--[[ ...and the two SHOWCASE SURFACES D2 and D5 shipped WITHOUT. Both constructs
	landed with spec fixtures only, so the director could load the showcase on a
	phone and exercise neither — exactly the gap `async-images` and `canvas-group`
	closed one round earlier. These two prove the fixture a player actually opens:
	that each of the five menu triggers reaches its own card through the real seam,
	that both presentation idioms are reachable on one machine, and that the tab
	eviction is a number on the screen rather than a claim in a document. They sit
	with D2's spec rather than at the tail because they are one deliverable and
	belong beside the first construct they exercise. ]]
require("./menu_scenario.spec")
require("./tab_view_scenario.spec")
-- D3a: `help` — pointer hover-dwell and keyboard/gamepad focus, NOTHING on
-- touch, and a reachability check that no declaration can waive
require("./help.spec")
-- D3b: `Callout` — the app-pushed coach mark, its eligibility/invalidation
-- contract, the caller-owned persistence boundary, and the non-blocking proof
require("./callout.spec")
-- ...and the SURFACE those two constructs are shown on, which shipped with no
-- spec at all and took two of the four findings of the 2026-08-16 device review:
-- the session reset that makes the device pass repeatable, and the screen gutter
-- a flush-right plate had been sitting on
require("./callout_scenario.spec")
--[[ NM-H4a: the director's own sequence — the ··· sink opened and CLOSED, then
	two orientation-plus-URL-bar cycles — replayed against the PAINTED tree rather
	than the resolution (which 288 replays already proved innocent), plus the
	on-screen paint probe that ships because that sequence still diverges by zero
	in every instrument this repository has ]]
require("./hud_paint_probe.spec")
--[[ NM-H4a: the hit-expander z reservation read `lastHitRects` — the expanders
	that exist RIGHT NOW — so a first structural sync reserved nothing and every
	expander landed on the previous node's ZIndex. Measured live on the built
	showcase: 73 of 86 nodes diverged from a fresh mount on `zIndex` alone. ]]
require("./hit_expander_z_band.spec")
--[[ A COVER'S TOUCH FLOOR STOPS AT ITS OWN REGION (DIR5 review H1):
	the one hit floor that is BOUNDED, because a cover's rect is a whole region's
	box and inflating it to 44px necessarily leaves the region across its full
	width — measured as 26% of each of two neighbouring Buttons. Beside the two
	cases above because it is the third rule about the same expander, and its
	control case is that an ORDINARY sub-floor control keeps its whole floor ]]
require("./hit_floor_region_clamp.spec")
require("./tab_view.spec")
require("./tab_view_accessories.spec")
require("./level_picker.spec")
--[[ `Facet.Controls.<Name>(core, spec)` — every one of the nineteen
	composites built BOTH ways from the same spec and compared on what it
	publishes, because an entry wired to the wrong builder (or to the right one
	with the wrong library) still returns a perfectly plausible table ]]
require("./controls_namespace.spec")
--[[ the three dependency-free leaves (num/paths/rect) plus the live defect they
	closed: two presented screens named `Menu` and `MenuBar` routed each other's
	taps, because the presenter imported the segment-aligned prefix test at line
	270 and then wrote the raw `string.sub` form at 640 and 3326 ]]
require("./leaf_helpers.spec")
--[[ one bounded-Levenshtein matrix where five modules each had one, with each
	caller's threshold kept explicit at its own boundary — the two policies
	(case-sensitive <= 2; case-folded, length-scaled) disagreed and nobody had
	ever decided that, so both are pinned rather than merged ]]
require("./text_distance.spec")
--[[ the client host's frame contract: one PreRender, `tick(dt)` then
	`refresh()`, consumer work on `presenter.onTick`, and an all-or-nothing
	construction — the half three of the four shipped bootstraps dropped, which no
	dump can see because a frozen motion clock looks exactly like a settled one ]]
require("./client_host.spec")
--[[ the shared headless world, and the guard that keeps the five-tuple at ONE
	order: twelve files returned `core, env, system, adapter, pres` and sixteen
	returned the same five names with positions three and four swapped, which
	Luau binds without a word ]]
require("./world_substrate.spec")
--[[ the two `newX` factories that held session state and could not be put down:
	`newActionSystem`'s contexts and their signals, `newResourceProvider`'s cache,
	in-flight requests, give-up ledger and one signal triple per live key. Both
	teardowns are asserted against the core's COUNTERS, which is the only
	instrument that tells "disposed" from "the reference went out of scope" ]]
require("./session_lifetime.spec")
--[[ the three process-global stores and who owns them: the text-metric caches
	are CONTENT-ADDRESSED so sharing them is a cache hit rather than a coupling,
	and the motion registries are shared ON PURPOSE because a motion name is a
	design-system decision and the registry is the only dial ]]
require("./process_globals.spec")
--[[ one owner for "is this path inside a subtree that does not paint": the
	disclosure walk, the help walk and the reveal walk's two gates all asked it
	themselves, and `presenter.luau` imported the published answer and then
	shadowed it with a nested copy (REUSE-29) ]]
require("./hidden_roots_owner.spec")
--[[ ADAPT-1's standing guard: adaptation arrives by itself (an environment is
	discoverable from the core it was built on, so a control asks instead of being
	told), or the control refuses to construct and names the host that would have
	supplied it. Every adaptive control the audit measured is pinned unwired ]]
require("./adaptive_defaults.spec")
--[[ the director's ten-foot ruling (ADAPT-8): the whole metric ladder scales by
	the TYPE floor's own factor, applied at the same environment seam the type
	floor uses — so a television with no theme package installed measures capped
	lanes and scaled metrics (ADAPT-L1) ]]
require("./ten_foot_metrics.spec")
--[[ the missing spacing step (task G-SPACE; the declarative-purity
	audit's `gap = 6` finding): a seventh, derived space step naming the value
	halfway between `xs` and `s` — resolves to 6 at neutral, authored beats
	derived exactly as `space.gutter` does, and is legal in the same
	gap/rowGap/padding/px= channels its neighbors are ]]
require("./space_tight_step.spec")
--[[ …and the channel that lets an APP put its own structural numbers on that
	same ladder (framework-gaps-phase2 gap 1): a reserved `app.*`
	namespace an app declares once, that `isMetricPath` accepts, a package may
	move, and the distance transform walks — replacing four independently
	rediscovered shims that kept ~100 numbers outside every theme ]]
require("./app_metrics.spec")
--[[ ADAPT-1's shape one layer down (matrix-layout.md, wave LAYOUT-FIX): the
	LAYOUT PRIMITIVES answer for themselves too. A Grid told nothing lanes itself
	from the box it got, an AdaptiveStack told nothing refuses rather than being a
	permanent VStack, a row grid says when it squeezed past a declared width, and a
	ten-foot Composition caps its content measure.

	OVERFLOW'S DEFAULT IS UNCHANGED and this file is where that has to be said,
	because the sentence here used to claim otherwise. ADAPT-L5 is CONTESTED: what
	the spec guards is that the DIAGNOSIS is complete and identical at every combo,
	which is the one property the always-on `overflow_sweep` cannot check because it
	counts findings and never reads one. ]]
require("./layout_defaults.spec")
--[[ THE SETTLE-TIME CONTAINMENT FINDING (2026-08-21): the one overflow the
	solver knew and could not say, because every other finding in that file is
	derived from a MEASURE against an offer and none from the RECT a child was
	finally given. Scoped by measurement to a stack's CROSS axis — the counts
	that rejected the wider rule are in `layout/placement_audit.luau` ]]
require("./containment_diagnostic.spec")
--[[ ...AND THE SAME INVARIANT ASKED UNDER A PACKAGE (task THEME, director items
	6-9). It sits above the guard's own proofs for the same reason everything else
	does — those read process-wide waiver counts — and below the diagnostic because
	it is the applied floor rather than the rule. ]]
require("./themed_containment.spec")
--[[ THE STANDALONE CONSUMER (distribution-readiness D2/D4): `examples/consumer/`
	is the smallest complete Facet project, and this mounts ITS OWN screen module
	— the same file the client script requires through the instance tree — against
	the fake target. Mount, theme, a press through the public input path, a signal
	repaint, a viewport and preferred-text re-solve, and registries back to
	baseline after teardown. It sits ABOVE the overflow guard for the reason the
	next block gives: that one has to be last. ]]
require("./consumer_standalone.spec")
--[[ THE CONTAINMENT INVARIANT'S OWN PROOFS, and it is REQUIRED LAST ON PURPOSE.
	`tests/lib/overflow_guard.luau` runs after every settle in every fixture world
	above, and its waiver registry may not rot — "every waiver still fires" is a
	claim about the WHOLE process, so the case that reads the use counts has to be
	the last one to run. testkit executes suites in registration order, which makes
	the last require and the last case the same thing. ]]
require("./overflow_guard.spec")
--[[ STRUCTURED RESULTS, WHEN ASKED FOR (distribution-readiness D7).
	`FACET_SUITE_JSON=<path> ./run-tests.sh` additionally writes every case as
	`{id, suite, name, status, ms, error}` for tools/verify.sh to query by id.
	Unset, this is exactly the run it always was. `registeredSpecs` is counted
	from THIS file's require list — a spec that registers nothing is then a
	number that disagrees with itself rather than a silent zero. ]]
local ok = testkit.run({
	jsonOut = process.env.FACET_SUITE_JSON,
	tier = "full",
	registeredSpecs = testkit.registeredSpecCount("tests/run.luau"),
})
if not ok then
	process.exit(1)
end
