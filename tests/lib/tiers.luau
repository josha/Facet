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
-- `FACET-FAST-TIER` marker the fast runner prints).
--
-- THE RULE IS A THRESHOLD, NOT A RANK (2026-08-15, O-17). It used to read "the
-- eleven costliest files and nothing else", which was true when it was written
-- and quietly false a fortnight later: on the 2026-08-15 measurement
-- `virtual_list_row_actions.spec` (1737 ms) and `row_actions_scenario.spec`
-- (1458 ms) both cost MORE than three files this list excludes, and nothing
-- noticed, because a rank is a claim about every OTHER file and this list only
-- names its own. A threshold is a claim this file can be held to:
--
--   * `tiers.THRESHOLD_MS` — anything measured above it MUST be excluded, unless
--     it is a FAST_ANCHOR (an exclusion the fast tier deliberately refuses);
--   * an entry BELOW it is still legal — every one of these is a workload or a
--     source scanner, which is a reason of its own;
--   * `tools/lune/check_tier_costs` enforces both halves against a fresh
--     `time_specs` run, so the next drift reddens a check instead of ageing in a
--     comment.
--
-- HOW THE EXCLUSIONS WERE CHOSEN: measured, not guessed, with
-- `lune run tools/lune/time_specs` (three runs, per-spec spread median 2.3 %,
-- against a whole-suite noise floor of 2.3 % over six unchanged runs — see
-- docs/plans/parity-round2.md §Phase 6). They are the eleven costliest
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

-- Above this measured total, a spec belongs in SLOW or in FAST_ANCHORS, and
-- `tools/lune/check_tier_costs` says so by name. Chosen at the gap in the
-- 2026-08-15 distribution: the cheapest thing above it is 1458 ms, the dearest
-- below it 938.
tiers.THRESHOLD_MS = 1200

-- ms = median total (load + cases) of THREE timed runs on 2026-08-15, at 5561
-- cases / 213 spec files, wall 78.9-79.9 s (`lune run tools/lune/time_specs`,
-- artifacts/swiftui-parity-round3/tier-costs-2026-08-15.md). The previous set was
-- taken at f476b63 / 4562 cases and every number in it had drifted — this file is
-- STALE BY CONSTRUCTION, which is why `tools/lune/check_tier_costs` now exists to
-- catch the next drift rather than the next reader.
tiers.SLOW = {
	{
		spec = "perf_lab.spec",
		ms = 24204,
		why = "the performance lab itself: 2 000- and 20 000-row mounts, a nine-workload sweep, and one case that walks a whole collection at every phone width (7.1 s on its own)",
	},
	{
		spec = "example_drift.spec",
		ms = 4416,
		why = "source scanner: re-reads and re-lints the whole tutorial example tree once per case, plus once per injected negative control",
	},
	{
		spec = "reference/sipworks_spec",
		ms = 3961,
		why = "clean-room reference proof: seeded worlds, full loops, replay-determinism dumps",
	},
	{
		spec = "extension_checker.spec",
		ms = 3795,
		why = "source scanner: walks src/ and docs/reference/api.md per case, including the allowlist negative controls",
	},
	{
		spec = "reference/glade_spec",
		ms = 2471,
		why = "clean-room reference proof: whole app mounted across the text range and the viewport set",
	},
	{
		spec = "reference/cartwheel_spec",
		ms = 1878,
		why = "clean-room reference proof: nine sections at every real viewport, in both locales",
	},
	{
		spec = "theme_drift.spec",
		ms = 2037,
		why = "source scanner: hardcoded-constant lint over controls, renderer and presenter",
	},
	{
		spec = "virtual_list_row_actions.spec",
		ms = 1737,
		why = "workload: the hosted row-actions battery — every tray, flick and irrevocable commit driven through a mounted VirtualList, plus the keyed-overlay perf cases (added to this list 2026-08-15: it was measured costlier than three files already on it)",
	},
	{
		spec = "row_actions_scenario.spec",
		ms = 1458,
		why = "workload: the showcase row-actions surface mounted in all three of its modes at the swept viewports (added to this list 2026-08-15 for the same reason as the row above)",
	},
	{
		spec = "overflow_sweep.spec",
		ms = 16342,
		why = "the always-on cross product, re-measured 2026-08-15: 46 surfaces x 9 viewports x 4 text preferences on the neutral pass, x 8 theme packages over a 10-cell tier, x a 1.4x locale pass over 2 preferences on the 21 surfaces that have a second form — one mount per (surface, viewport) for the first two axes, a second mount for the third",
	},
	{
		spec = "reference/foyer_spec",
		ms = 938,
		why = "clean-room reference proof: the whole representative loop, its rejection paths, reflow survival, locale swap and reset determinism, driven through the presenter/adapter stack",
	},
	{
		spec = "instance_recycling.spec",
		ms = 693,
		why = "long-scroll pool-bound workload (a single case scrolls far enough to prove the pool cannot grow)",
	},
	{
		spec = "reference/wardrobe_spec",
		ms = 497,
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
