--!strict
-- TEST TIERS (parity round 2, Phase 6 step 2).
--
-- There is exactly ONE list of specs in this repository: the `require(...)`
-- calls in `tests/run.luau`. The fast tier is not a second list — it is that
-- list minus the named exclusions below, parsed out of the file itself, so a
-- spec added to `run.luau` joins the fast tier automatically and a spec renamed
-- out from under an exclusion fails `tests/tier.spec.luau` rather than silently
-- shrinking the tier.
--
-- WHAT THE FAST TIER IS FOR: the inner loop. It is NOT the gate. The gate runs
-- `./run-tests.sh` with no arguments, which runs `tests/run.luau` — every file.
-- `tools/test.sh` refuses a fast-tier transcript outright (it greps for the
-- `LUAUUI-FAST-TIER` marker the fast runner prints).
--
-- HOW THE EXCLUSIONS WERE CHOSEN: measured, not guessed, with
-- `lune run tools/lune/time_specs` (three runs, per-spec spread median 2.3 %,
-- against a whole-suite noise floor of 2.3 % over six unchanged runs — see
-- docs/plans/swiftui-parity-round2.md §Phase 6). They are the eleven costliest
-- files and nothing else: together 34.3 s of the 42.7 s suite. Every one of them
-- is either a WORKLOAD (mounts thousands of rows, or one screen at a dozen
-- viewports) or a SOURCE SCANNER (re-reads and re-lints a file tree per case) —
-- both classes are exactly the kind of check you want in the gate and exactly
-- the kind you do not want between two keystrokes.
--
-- Nothing here is deleted, skipped or weakened. Every excluded file runs, in
-- full, on `./run-tests.sh`.

local fs = require("@lune/fs")

local tiers = {}

export type Exclusion = { spec: string, ms: number, why: string }

-- ms = median total (load + cases) of three timed runs at f476b63, 4562 cases.
tiers.SLOW = {
	{
		spec = "perf_lab.spec",
		ms = 16024,
		why = "the performance lab itself: 2 000- and 20 000-row mounts, a nine-workload sweep, and one case that walks a whole collection at every phone width (7.1 s on its own)",
	},
	{
		spec = "example_drift.spec",
		ms = 4182,
		why = "source scanner: re-reads and re-lints the whole tutorial example tree once per case, plus once per injected negative control",
	},
	{
		spec = "reference/sipworks_spec",
		ms = 3222,
		why = "clean-room reference proof: seeded worlds, full loops, replay-determinism dumps",
	},
	{
		spec = "extension_checker.spec",
		ms = 2701,
		why = "source scanner: walks src/ and docs/reference/api.md per case, including the allowlist negative controls",
	},
	{
		spec = "reference/glade_spec",
		ms = 1979,
		why = "clean-room reference proof: whole app mounted across the text range and the viewport set",
	},
	{
		spec = "reference/cartwheel_spec",
		ms = 1874,
		why = "clean-room reference proof: nine sections at every real viewport, in both locales",
	},
	{
		spec = "theme_drift.spec",
		ms = 1356,
		why = "source scanner: hardcoded-constant lint over controls, renderer and presenter",
	},
	{
		spec = "overflow_sweep.spec",
		ms = 1036,
		why = "37 showcase surfaces x six viewports x both orientations, diagnostics-failing",
	},
	{
		spec = "reference/foyer_spec",
		ms = 978,
		why = "clean-room reference proof: the whole representative loop, its rejection paths, reflow survival, locale swap and reset determinism, driven through the presenter/adapter stack",
	},
	{
		spec = "instance_recycling.spec",
		ms = 602,
		why = "long-scroll pool-bound workload (a single case scrolls far enough to prove the pool cannot grow)",
	},
	{
		spec = "reference/wardrobe_spec",
		ms = 326,
		why = "clean-room reference proof: try-on history, the purchase lifecycle, the stage seam and the split-to-stacked Composition flip with state survival",
	},
} :: { Exclusion }

-- Specs the fast tier must ALWAYS carry, named rather than inferred: the smoke
-- check, the core solver/render/mount spine, and every area parity round 2
-- touched. `tests/tier.spec.luau` fails if an exclusion ever swallows one.
tiers.FAST_ANCHORS = {
	-- smoke + spine
	"smoke.spec",
	"layout.spec",
	"mount.spec",
	"renderer.spec",
	"focus.spec",
	"presenter.spec",
	"styling.spec",
	"api_surface.spec",
	"conformance/conformance.spec",
	-- parity round 2, phase by phase
	"with_animation.spec",
	"animation_precedence.spec",
	"stack_distribution.spec",
	"grid_row.spec",
	"grid_measure_arrange.spec",
	"placement_audit.spec",
	"container_relative_frame.spec",
	"virtual_list_axis.spec",
	"sensory_feedback.spec",
	"haptics.spec",
	"reduced_motion_seam.spec",
	"display_controls.spec",
	"table.spec",
	"examples_gallery.spec",
} :: { string }

-- The full order, parsed from tests/run.luau — the single source of truth for
-- which specs exist. Paths are as written there, without the leading "./".
function tiers.fullOrder(): { string }
	local src = fs.readFile("tests/run.luau")
	local order: { string } = {}
	for line in string.gmatch(src, "[^\n]+") do
		local rel = string.match(line, '^%s*require%("%./([%w_/%.]+)"%)')
		if rel then
			table.insert(order, rel)
		end
	end
	assert(#order > 0, "tiers: parsed no require() lines out of tests/run.luau")
	return order
end

function tiers.excluded(): { [string]: Exclusion }
	local set: { [string]: Exclusion } = {}
	for _, entry in tiers.SLOW do
		set[entry.spec] = entry
	end
	return set
end

-- The fast order: fullOrder minus the exclusions, same relative order.
function tiers.fastOrder(): { string }
	local skip = tiers.excluded()
	local out: { string } = {}
	for _, rel in tiers.fullOrder() do
		if skip[rel] == nil then
			table.insert(out, rel)
		end
	end
	return out
end

return tiers
