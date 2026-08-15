--!strict
-- LuauUI Studio verification scenarios (fable-execution-contract §5).
-- A scenario is a NAMED, DETERMINISTIC fixture the Studio MCP can select,
-- drive, observe, and reset without assembling game state. Scenario modules
-- are ENGINE-FREE (like examples/gallery/examples): they build blueprints and
-- pure state against the ctx the runner passes in; only runner.luau touches
-- the engine, and only through the adapter/env seams it is handed.
--
-- Select in Studio: set workspace attribute LuauUI_Scenario = "<name>" before
-- Play. Drive via _G.LuauUIScenario (report/step/reset/list) from the MCP.
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
	-- ledger rows and drives ONLY public LuauUI.
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
	-- roadmap Step 11 (swiftui-reference-app-validation): the five clean-room
	-- reference proofs, one scenario per proof, each a thin delegation to its
	-- examples/reference module (see ref_*.luau headers)
	"ref_glade",
	"ref_cartwheel",
	"ref_sipworks",
	"ref_foyer",
	"ref_wardrobe",
	-- SwiftUI-parity round 2 (docs/plans/swiftui-parity-round2.md): the two
	-- surfaces that carry this round's new public API into a place a player can
	-- actually reach. `card_rail` is `newVirtualList`'s horizontal axis (§2.3);
	-- `with_animation` is `presenter.withAnimation` plus the Full/Reduced control
	-- the motion demo owes (§Phase 4). Both are also in `demo_picker.DEMOS`, so
	-- they are pickable in-experience and not only by workspace attribute.
	"card_rail",
	"with_animation",
	-- SwiftUI-parity round 3 (docs/plans/swiftui-parity-round3.md item D2): the
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
	-- ...and the container §13 said did not exist: `newTable{ virtualized = true }`,
	-- which windows, multi-selects and reorders at the same time on the running-
	-- offset index variable extents shipped. Two thousand rows and a status line
	-- reporting how many are actually in the tree — the only place the feature is
	-- visible, since a windowed table and a fully-mounted one are the same picture.
	-- The three buttons each act on row 1500, which no window has ever held. Also in
	-- `demo_picker.DEMOS`.
	"table_virtualized",
	-- ...and the half of `newTable` that shipped in Phase B and had never once been
	-- driven on a real adapter: THE HEADER AND ITS RESIZE DIVIDERS. The model, the
	-- pointer drag and the keyboard/gamepad step were all proved headlessly against
	-- a fake target that dispatches a pointer event to the path it is handed —
	-- which is exactly the thing the engine's topmost-only `InputBegan` rule makes
	-- untrue of an 8px divider painted over a full-cell header button. It cannot
	-- live in `table_virtualized` (headerless, deliberately and for a measured
	-- reason) so it is its own surface. Also in `demo_picker.DEMOS`.
	"table_columns",
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
	-- ...and ADR-0028: the CROSS-SURFACE overlap alarm. One probe surface over
	-- one screen, four declarations, and the framework's own sentence about each
	-- — the difference the fixture exists to show is invisible in a screenshot,
	-- because all four states paint identical pixels. Also in
	-- `demo_picker.DEMOS`.
	"surface_overlap",
}

local scenarios = {}
for _, name in ORDER do
	scenarios[name] = script:WaitForChild(name)
end

return {
	order = ORDER,
	modules = scenarios,
	runner = script:WaitForChild("runner"),
}
