--!strict
--[[ ── THE ABSORBING-BOUNDARY ANALYSIS ───────────────────────────────────────────

	`controller.analyzeBoundaries()`'s body, lifted out of `render/renderer.luau` on
	2026-09-06 (ruling C-3, fix round 2) for the Source-write headroom that fix
	needed. `tools/lune/verify/data/source-cap-ledger.md` states the rule every
	extraction in this repository is judged by, and the first half of it is that the
	room is taken FIRST, in its own behaviour-neutral commit. This is that commit's
	half.

	IT BELONGS HERE ON ITS MERITS, not only for the room. NOTHING IN IT RENDERS. It is
	a diagnostic: a second solve of a tree the renderer has already solved, with the
	analysis flag on, so a maintainer (or `tests/measure_reuse.spec.luau` and
	`tests/structural_scope.spec.luau`) can read which boxes absorb a change. It
	touches no handle, no adapter, no rect map, no counter and no phase; it runs only
	when a tool or a spec asks, never from a frame. Every other line in the block it
	came from is about painting one.

	ONE-WAY, AND BY CONSTRUCTION rather than by inspection. `lastSolveInputs` is a
	plain record the renderer builds FOR this call and never reads back — its own
	comment says so ("kept so the Stage-1 boundary analysis can re-solve the SAME tree
	with the SAME offers") — so the whole seam is ONE argument, passed straight
	through. There is no Deps record, no upvalue of the host, no module-level state,
	and this file names no renderer symbol. Its one require, `../layout/solver`, is a
	require the renderer already makes and a module that requires nothing under
	`render/`, so the move creates no require BACK.
	`tests/boundary_analysis_seam.spec.luau` is that mechanised.

	THE ANALYSIS IS A FULL SOLVE OR IT IS NOTHING (P1 review, IMPORTANT 2), and that
	argument moved here with the code because it is the only reason the two
	assignments below exist. `inputs.opts` is the LIVE `solveOpts` TABLE, so both
	reuse fields are visible through the clone — `reuse` since Stage 2, `measures`
	since P1. `boundary` is written in `measureUncached`, so a solve served from
	slates records almost nothing, every unrecorded node reads as "does not absorb",
	and the report INVERTS (measured: 6 absorbing against the true 11).
	`reuse.dirtyContains` is also the wrong refresh's set, and passing `measures`
	would let an ANALYSIS write the store the next real solve reads. Pinned in
	`tests/measure_reuse.spec.luau`.

	THE CLONE IS THE OTHER HALF OF THAT, and it is a property of this call rather than
	a convenience: the caller's `solveOpts` is the record the NEXT real solve is going
	to run on, so setting the analysis flag or clearing the reuse fields on it would
	make a diagnostic change what ships. ]]

local solver = require("../layout/solver")

local boundary_analysis = {}

--[[ `inputs` is the renderer's `lastSolveInputs`: `{ layoutRoot, viewport, opts }`,
	or `nil` on a surface that has not solved yet — which answers `nil`, because a
	report about a tree no solve ever built would be a report about nothing. ]]
function boundary_analysis.report(inputs: any): any
	if inputs == nil then
		return nil
	end
	local opts = table.clone(inputs.opts)
	opts.analyzeBoundaries = true
	-- see THE ANALYSIS IS A FULL SOLVE OR IT IS NOTHING, above
	opts.reuse = nil
	opts.measures = nil
	local result = solver.solve(inputs.layoutRoot, inputs.viewport, opts)
	return solver.boundaryReport(inputs.layoutRoot, result)
end

return boundary_analysis
