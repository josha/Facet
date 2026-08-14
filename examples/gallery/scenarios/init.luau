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
