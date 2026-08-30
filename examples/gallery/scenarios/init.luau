--!strict
-- Facet Studio verification scenarios (fable-execution-contract §5).
-- A scenario is a NAMED, DETERMINISTIC fixture the Studio MCP can select,
-- drive, observe, and reset without assembling game state. Scenario modules
-- are ENGINE-FREE (like examples/gallery/examples): they build blueprints and
-- pure state against the ctx the runner passes in; only runner.luau touches
-- the engine, and only through the adapter/env seams it is handed.
--
-- Select in Studio: set workspace attribute Facet_Scenario = "<name>" before
-- Play. Drive via _G.FacetScenario (report/step/reset/list) from the MCP.
-- Every scenario export is keyed to acceptance-ledger rows
-- (artifacts/native-substrate/acceptance-ledger.md).
--
-- Registration is explicit and ordered; an unknown name fails loudly in the
-- runner rather than silently mounting nothing.

local ORDER = {
	"probe",
	"safe_area",
	"scroll_host",
	"path_ring",
	"async_images",
	"selection_bridge",
	"preferred_text",
	-- ...and its SIBLING GuiService preference (ADR-0035 / owed row O-26): the
	-- player's BACKGROUND TRANSPARENCY setting, answered by Facet's own painting.
	-- Filed here rather than at the tail because the two are one story — one
	-- accessibility fact each, both pushed from `roblox_env`, neither driveable
	-- from a script. The fixture honours nothing by hand: it moves the environment
	-- fact the adapter publishes and the framework repaints its own backdrop. It
	-- also puts the REFUSALS on screen, because an authored `opacity` holding still
	-- beside a backdrop that moves is the only way to see that the preference is
	-- scoped rather than swept. Also in `demo_picker.DEMOS`.
	"preferred_transparency",
	"drag_session",
	"virtual_list_native",
	"native_style",
	"authoring",
	"adaptive_controls",
	"theme_authoring",
	-- roadmap Step 4: the production-shaped fixture the five-view matrix drives
	-- and the Studio performance capture measures
	"perf_capture",
	-- roadmap Step 5 (sponsor-framework-gaps): the eight Sponsor-shaped fixtures,
	-- one per contract cluster (ui-designer-spec §8). Each is keyed to its SF-*
	-- ledger rows and drives ONLY public Facet.
	"sponsor_motion",
	"sponsor_celebration",
	"sponsor_list",
	"sponsor_drop",
	"sponsor_toast",
	"sponsor_avatars",
	"sponsor_markers",
	"sponsor_billboard",
	-- ADR-0023: declared-content adaptive composition. ONE declaration of twelve
	-- ranked regions driven through the five device offers plus a live axis flip
	"composition",
	-- roadmap Step 8: the desktop keyboard focus chain (form + scrollable list +
	-- modal + TextInput + Slider + Stepper), driven with raw VirtualInput keys
	"keyboard_navigation",
	-- roadmap Step 10: the seven TUTORIAL EXAMPLES, so the five-view device
	-- matrix and the theme-swap capture can hold them by the same handle every
	-- other stage's evidence uses. It owns no UI — it mounts one example
	-- verbatim and adds the select/theme drive surface
	"examples",
	-- row-actions-implementation Task 11: the mail-style gallery fixture for
	-- `newRowActions`/Table `rowActions` — a hand-wrapped ScrollView>VStack
	-- list sharing one coordinator, plus a reorderable/editable Table
	"row_actions",
	-- roadmap Step 11 (reference-app-validation): the clean-room reference
	-- proofs, one scenario per proof, each a thin delegation to its
	-- examples/reference module (see ref_*.luau headers).
	--
	-- FOUR, NOT FIVE, SINCE 2026-08-30. `ref_wardrobe` was deleted with the
	-- Wardrobe retirement (docs/plans/example-games-and-standalones.md, "Retire
	-- Wardrobe; complete Sipworks and Glade"): the app is no longer a player
	-- example, so it has no scenario, no place and no picker entry. It survives
	-- only as test evidence for the closed reference-app-validation gate, at
	-- tests/fixtures/retired/p5_wardrobe (read that directory's README before
	-- re-adding anything here).
	"ref_glade",
	"ref_cartwheel",
	"ref_sipworks",
	"ref_foyer",
	-- parity round 2 (docs/plans/parity-round2.md): the two
	-- surfaces that carry this round's new public API into a place a player can
	-- actually reach. `card_rail` is `newVirtualList`'s horizontal axis (§2.3);
	-- `with_animation` is `presenter.withAnimation` plus the Full/Reduced control
	-- the motion demo owes (§Phase 4). Both are also in `demo_picker.DEMOS`, so
	-- they are pickable in-experience and not only by workspace attribute.
	"card_rail",
	"with_animation",
	-- parity round 3 (docs/plans/parity-round3.md item D2): the
	-- circular progress indicator in BOTH forms — a determinate ring driven by the
	-- steps and an indeterminate one rotating on the surface's own clock — beside
	-- the five-dot spinner it does not replace. Also in `demo_picker.DEMOS`.
	"progress_ring",
	-- ...and item A: FLOW-WRAP. `UI.HStack{ wrap = true }` — the one surface where
	-- turning a single prop off makes fourteen tags walk off the right edge of
	-- their own box, which is the only way to show what wrapping is FOR. Also in
	-- `demo_picker.DEMOS`.
	"flow_wrap",
	-- ...and item D: the two capabilities the completeness audit ranked highest
	-- per line of work. `hidden` is only legible NEXT TO `UI.When` — one switch
	-- drives both panels and only one caption moves — and `onAppear`/
	-- `onDisappear` produce no pixels at all, so the fixture gives them a live
	-- event log and two counters that never reset.
	"lifecycle_hidden",
	-- ...and item C: the PER-ROW CAPABILITY OPT-OUTS (`rowSelectable`,
	-- `rowMovable`, `rowDeletable`). One table, five rows, three of which refuse
	-- exactly one of the three things the other two allow — and because a refusal
	-- is an ABSENCE (the tap does nothing, the row does not move), the fixture
	-- puts the framework's own question on screen: the live line is written from
	-- inside the three predicates, at the instant each is asked. Also in
	-- `demo_picker.DEMOS`.
	"row_capabilities",
	-- ...and rulings 1 and 5 (2026-08-13): THE TEXT DEGRADE CASCADE. Four width
	-- stops on one row, because the feature is not any single frame — it is the
	-- ORDER a label gives things up in (reflow, the compact form, an ellipsis, and
	-- only then a crop), and an order needs a driver. The last stop is the one
	-- state here that files a solver finding, deliberately, exactly as
	-- `flow_wrap`'s "wrapping off" state does. Also in `demo_picker.DEMOS`.
	"text_degrade",
	-- ...and ruling 7 (2026-08-13): VARIABLE ITEM EXTENTS. A feed of 400 posts of
	-- four different heights, with one toggle that makes the list declare a single
	-- number for all of them — the pre-feature contract — so the defect the sweep
	-- measured is visible beside the fix, and the four measured text offsets walk
	-- the whole list without moving the post under the top edge. Also in
	-- `demo_picker.DEMOS`.
	"variable_extents",
	-- ...and STAGE 2 of the same ruling: MEASURED item extents. Read it beside the
	-- one above — that fixture spends thirty lines reproducing the solver's text
	-- arithmetic to declare a correct height (and got it wrong on its first cut,
	-- 372 findings on its own rows); this one contains no height arithmetic at all
	-- and its posts wrap without a `lineLimit`, which is the case a declaration
	-- cannot express. The status line carries the convergence — how much of the
	-- canvas is measurement and how much is still the estimate. Also in
	-- `demo_picker.DEMOS`.
	"measured_extents",
	-- ...and the container §13 said did not exist: `newTable{ virtualized = true }`,
	-- which windows, multi-selects and reorders at the same time on the running-
	-- offset index variable extents shipped. Two thousand rows and a status line
	-- reporting how many are actually in the tree — the only place the feature is
	-- visible, since a windowed table and a fully-mounted one are the same picture.
	-- The three buttons each act on row 1500, which no window has ever held. Also in
	-- `demo_picker.DEMOS`.
	"table_virtualized",
	-- `table_columns` USED TO BE HERE — the half of `newTable` that shipped in
	-- Phase B and had never once been driven on a real adapter: THE HEADER AND ITS
	-- RESIZE DIVIDERS. It was its own fixture because the shipped playlist tutorial
	-- had only two columns, and pinning the sole `fill` one leaves nothing to absorb
	-- the remainder. RETIRED 2026-08-16 (navigation-and-menus D8): the playlist
	-- gained a third `fill` column, so the header, its dividers, the live width
	-- readout and the selected-column hint all live on the tutorial now — the
	-- surface a player reaches rather than one built to be tested.
	-- ...and the director's per-control sensory request (2026-08-13): five
	-- identical-looking buttons that report four different verbs and one nothing
	-- at all, plus one declaration on a panel that all three controls inside it
	-- inherit. The whole capability is a DIFFERENCE in what a press says happened,
	-- which a still screenshot flattens to five chips. Also in
	-- `demo_picker.DEMOS`.
	"sensory_feedback",
	-- ...and ADR-0025: the SCREEN-ANCHORED HUD. Corner clusters, a task panel and
	-- a weapon rail on `composition.HUD`, plus the one switch that takes 200px of
	-- HEIGHT off the box the way a browser URL bar does — so the commissioning
	-- screenshot's exact event can be watched degrading instead of colliding. Also
	-- in `demo_picker.DEMOS`.
	"hud",
	-- ...and `newVirtualGrid`, the lazy grid: five thousand cells with a
	-- live count of the ones the `cell` factory was ever asked for. A lazy grid
	-- and an eager one paint the same first screen, so the demonstration is a
	-- NUMBER — and the lane chips reflow every item onto a different line without
	-- moving the cell under the player's eye, which is the destabilizer only a
	-- grid has. Also in `demo_picker.DEMOS`.
	"virtual_grid",
	-- ...and the SIDEWAYS half, newVirtualGrid on the x axis (sideways grid). It is
	-- its own fixture rather than a step on the one above because the two axes do
	-- not differ in a value: they differ in which axis the LANES divide and which
	-- way the RING walks, and both are things you look at. Down steps a cell here
	-- and Right steps a whole line — the exact transpose, and the OPPOSITE
	-- transposition from a virtual list's. Also in `demo_picker.DEMOS`.
	"virtual_hgrid",
	-- ...and ADR-0028: the CROSS-SURFACE overlap alarm. One probe surface over
	-- one screen, four declarations, and the framework's own sentence about each
	-- — the difference the fixture exists to show is invisible in a screenshot,
	-- because all four states paint identical pixels. Also in
	-- `demo_picker.DEMOS`.
	"surface_overlap",
	-- ...and api.md §When: THE BRANCH SCOPE. `thenView` is
	-- handed the branch's own ownership scope, and a leak paints nothing — the
	-- two panels here are the same panel written the two ways and are identical
	-- while open, so the framework's own scope counter is the surface. Also in
	-- `demo_picker.DEMOS`.
	"branch_scope",
	-- ...and api.md §sortedEntries: `UI.sortedEntries`. The same twelve
	-- scores built three ways, flattened both ways side by side — the raw column
	-- deals itself a new order and the sorted one does not. One frame of a
	-- leaderboard cannot show a bug that only exists BETWEEN two frames. Also in
	-- `demo_picker.DEMOS`.
	"sorted_entries",
	-- ...and ADR-0033: TIME-BASED EASING. The only surface where the thing a
	-- spring cannot do is on screen next to a spring doing it — an informational
	-- `clock:tween` and a `clock:spring` given the same half-second number, racing
	-- with a stopwatch stamping each arrival (the tween at 0.52 s, the spring at
	-- 1.05 s). Beside it, one 400 ms trip under four registered curves that land
	-- on the same frame by travelling differently, and `withAnimation` driven by a
	-- CURVE name rather than a class. The curve registry ships EMPTY, so this
	-- fixture registers its own six curves defensively at build. Also in
	-- `demo_picker.DEMOS`.
	"time_curves",
	-- ...and api.md §Foreign / ADR-0034: UI.FOREIGN. The one
	-- fixture in this list whose panes are NOT drawn by Facet — RichText spans in
	-- one label, an engine-measured UIListLayout with AutomaticCanvasSize, and a
	-- deliberately 2x-oversize Frame that proves the box clips. Each is a
	-- capability the framework declines by design, which is the only way to
	-- demonstrate an escape hatch: a pane Facet could have drawn would show
	-- nothing. A fourth button adopts a `Part` and puts the framework's own
	-- refusal on screen verbatim. Also in `demo_picker.DEMOS`.
	"foreign_content",
	-- ...and the FADE GROUP (ADR-0026/ADR-0029, round-3 O-30). `canvasGroup` and
	-- its reactive twin `opacity` were exercised by six `sponsor_*` fixtures and
	-- `p2_cartwheel` and demonstrated by none of them — nothing in the picker
	-- reached the prop at all, so in the shipped place the capability existed only
	-- behind a workspace attribute. It is the one demonstration here a still
	-- screenshot CAN hold: the same three plates and the same value, faded as one
	-- picture beside faded one plate at a time. Also in `demo_picker.DEMOS`.
	"canvas_group",
	-- ...and `newLevelPicker` (director ruling 2026-08-16): the reference
	-- screenshot's two bar strips — ten segments with two filled, three with none
	-- — each beside the `newStepper` that shares its Signal, because the ± that
	-- looks like part of the control deliberately is not part of it. Plus the
	-- glyph and image segments and a tint override, so all three paint modes and
	-- both tint halves are reachable on a device from one fixture. Also in
	-- `demo_picker.DEMOS`.
	"level_picker",
	-- ...and navigation-and-menus D3: the two plates that look alike in a still
	-- frame and are opposites everywhere else. `help` is PULLED by the player and
	-- shows nothing on touch (so the same sentences are printed on the screen —
	-- the rule `text_audit.helpRoutes` enforces); `newCallout` is PUSHED by the
	-- app, carries the arrow tail, and retires permanently. It reproduces the
	-- reference `f1` plate under a top-right `+`, and the press counter under it
	-- is the NON-BLOCKING claim on screen rather than in a document. The
	-- persistence boundary is a fixture readout: what the framework reported, and
	-- what this app then chose to save. Also in `demo_picker.DEMOS`.
	"callout",
	-- ...and the two constructs of the same round that shipped with spec fixtures
	-- and no surface a person could reach (added 2026-08-16). Both are here for
	-- the same reason `callout` is: what they do is a set of GESTURES and a set
	-- of LIFECYCLES, and a still frame holds neither.
	--
	-- `menu` (D2) splits the five triggers across five cards, because `newMenu`
	-- refuses a `triggers` set that drops `activate` without both chords — so the
	-- smallest set that isolates a gesture is not always one gesture, and the
	-- split IS that rule on screen. It carries the two-level submenu (the depth
	-- >= 2 advice is printed rather than swallowed), an Idiom control that writes
	-- the one live fact the presentation rule reads so panel and sheet are both
	-- reachable on one machine, and a card whose every item is disabled and which
	-- still opens. Also in `demo_picker.DEMOS`.
	"menu",
	-- `tab_view` (D5) is `r2`: a page's own top bar inside a screen that is
	-- itself a tab of the app-level bottom bar, with both levels printing the
	-- placement they resolved and which authority answered. The eviction is a
	-- per-tab BUILD COUNT — a real disposal and a hidden subtree paint the same
	-- picture — beside two counters owned by different scopes, which is the whole
	-- of the documented escape hatch. The page bar overflows on purpose so the
	-- selection can be scrolled into view. Also in `demo_picker.DEMOS`.
	"tab_view",
	-- ADR-0032 (the nested instance tree): the compositing showcase. A registered
	-- host lets the engine compose a term for its WHOLE subtree instead of the
	-- framework computing it per descendant — two plates fading as one group
	-- rather than doubling their overlap, and a container whose authored
	-- rotation/scale carries a plate-plus-marker pair as a rigid unit, beside the
	-- same marker rotated as a bare leaf (no contents to carry, so it detaches
	-- from its own plate — the pre-ADR-0032 defect, reproduced on purpose as the
	-- control). Also in `demo_picker.DEMOS`.
	"nested_compositing",
	--[[ ADR-0063: FLAT FACET ON A WORLD SURFACE — the outpost power terminal. The
		one fixture in this list whose screen is not on a screen: it is painted on a
		`SurfaceGui` over a console part, a player walks up to it through the
		platform's own `ProximityPrompt`, and applying power sends a domain intent
		to the showcase's FIRST server side (`examples/gallery/server`) rather than
		changing the world from here. Its ScreenGui half is the LAB around that —
		the eight exit paths, the face-versus-player assertion, and the five server
		refusals, each driveable once. Deliberately NOT in `demo_picker.DEMOS`, for
		the same reason `sponsor_billboard` is not: a fixture whose demo needs an
		engine fixture built for it is not something the chip strip can mount. ]]
	"outpost_terminal",
	-- scaffold: new control scenarios are appended above this line
}

local scenarios = {}
for _, name in ORDER do
	scenarios[name] = script:WaitForChild(name)
end

return {
	order = ORDER,
	modules = scenarios,
	runner = script:WaitForChild("runner"),
	-- the ENGINE-SIDE sibling `runner` and the shipped showcase host BOTH need
	-- (UI.Foreign, ADR-0034): one materializer for `built.foreignContent`, so the
	-- test rig cannot end up more capable than the surface a player opens
	foreignInstances = script:WaitForChild("foreign_instances"),
}
