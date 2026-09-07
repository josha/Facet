--!strict
--[[ ── THE SETTLE SOLVE'S OWN CLOSURE, SPENT ─────────────────────────────────────

	Plan D, D3c. A SEAM, taken first and on its own, before any mechanism: this is
	the block that used to sit inline in `render/renderer.luau`'s `solveOnce` —
	the `textIndex.apply` call, the push budget it is judged against, and the two
	counters the plan publishes.

	WHY IT LEFT THE RENDERER, and the reason is a measurement rather than a taste.
	`renderer.luau` stands at 197,472 of the campaign's 197,500-character STOP line
	(28 characters), and the 200,000 above that is a HARD engine limit: a module at
	or over it silently stops live-syncing into an open Studio session, so a live
	check against it reads the built place rather than the edits under test
	(`tools/check_source_size.py` owns that argument, measured 2026-08-14). D3c adds
	a probe phase and a second counter to this decision. Neither can be paid for
	there, and a mechanism that cannot carry its own explanation is the shape this
	repository has learned to refuse.

	WHAT IS HERE AND WHAT IS NOT. The DECISION — own the closure, union into the
	caller's, or drop the caller's for the whole-tree solve — stays in
	`render/text_index`, beside the index whose paths it spends and the page of
	measurement that chose it. What is here is the renderer's HALF of the seam: the
	budget the push is judged against, the call, and the counters. The tail clear (a
	closure this solve set, this solve clears) stays at the call site, because it
	has to run after `solveOpts.reuse` has been built from those same two tables.

	THE BUDGET IS A MEASUREMENT (Plan C, §C16; re-swept at Plan D, D3b). A push that
	names a large FRACTION of the tree is not a narrowing — its ancestor closure
	reaches the root, every container refuses its memo, and the solve does the whole
	tree's work PLUS the closure's. The crossover is a BAND (roughly 7-13 % of the
	tree at §C16, unchanged at D3b's re-sweep), and `lastLayoutNodes // 8` is 12.5 %
	— the top of that band, where a refusal costs at worst a wash. The `64` floor is
	for a surface with no previous solve, where `lastLayoutNodes` is 0; benign by
	construction, because such a surface has no `lastResult` either, so `narrow` is
	false and no push is built for the budget to judge.
]]

local text_index = require("./text_index")

local settle_solve = {}

--[[ SPEND THE PENDING TEXT PUSH ON THIS SOLVE'S TWO CLOSURES. Returns the two sets
	the solve should use and whether THIS call created them — a settle solve has no
	tail of its own, and a caller's closure belongs to the caller, so the call site
	clears only what it was told it owns.

	`stats` is written, not read back: `lastTextDirtyPaths` is how many paths the
	push actually named — over the cap, the set the probe found MOVED — and
	`lastTextProbeMeasures` how many leaves that probe re-measured to get there
	(Plan D, D3c; `render/text_index` owns both). ]]
function settle_solve.spend(
	index: text_index.Index,
	stats: any,
	contains: { [string]: boolean }?,
	measures: { [string]: boolean }?,
	narrow: boolean
): ({ [string]: boolean }?, { [string]: boolean }?, boolean)
	local nextContains, nextMeasures, owns, pushed, probed =
		index.apply(contains, measures, narrow, math.max(64, stats.lastLayoutNodes // 8))
	stats.lastTextDirtyPaths = pushed
	stats.lastTextProbeMeasures = probed
	return nextContains, nextMeasures, owns
end

return settle_solve
