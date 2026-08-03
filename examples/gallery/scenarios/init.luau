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
