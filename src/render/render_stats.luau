--!strict
--[[ THE RENDERER'S COUNTERS — the record and the one function that publishes a
	solve's work into it, lifted out of `render/renderer.luau` on 2026-09-04 (Plan
	C, T5) for the Source-write headroom the translate lane needed. The renderer
	stood 3,575 characters from the size line its own ledger row names and the
	lane's hook is +4,272; the campaign's rule is that the room is taken FIRST, in
	its own behaviour-neutral commit, and this is it.

	IT BELONGS HERE ON ITS MERITS, not only for the room. Every field below is a
	NUMBER the renderer writes and `controller.stats()` reads, and the whole block
	is documentation about what each number means and which of them are stale by
	design — the largest single run of prose in that file that says nothing about
	rendering. `publish` is the other half of the same subject: the four lines that
	turn a finished solve's `work` record into those fields.

	ONE-WAY, AND BY CONSTRUCTION rather than by inspection. `new()` returns a fresh
	table and keeps no reference to it; `publish` is a pure function of its four
	arguments that writes only into the table it is handed. There is no Deps
	record, no upvalue of the host, no state at module level, and nothing here
	requires anything at all. `tests/render_stats_seam.spec.luau` is that property
	mechanised.

	`lastResult = result` did NOT come with it: that is the renderer's own solve
	state, not a counter, and moving it would have made this module hold something
	the renderer reads back. ]]
local render_stats = {}

-- A FRESH TABLE PER SURFACE. `renderer.attach` builds one per controller and
-- mutates it in place for the surface's life; `controller.stats()` hands out a
-- shallow clone, which is why several fields below document themselves as "a
-- FRESH table per commit" rather than being cleared.
function render_stats.new(): any
	return {
		creates = 0,
		removes = 0,
		rectWrites = 0,
		propWrites = 0,
		solves = 0,
		textMeasureBatches = 0,
		-- recycling: `parked` counts nodes taken out of the tree intact rather than
		-- destroyed; `recycled` counts creates served from the pool instead of the
		-- engine. Both stay 0 unless the feature is on, which makes "is it actually
		-- doing anything" a readable number rather than an inference.
		parked = 0,
		recycled = 0,
		-- diagnostics for "why is recycling doing nothing": whether the feature is
		-- armed at all, and how many park attempts the ADAPTER refused
		recycleArmed = false,
		parkRefused = 0,
		-- nodes the MOST RECENT solve arranged / measured
		lastArranged = 0,
		lastMeasured = 0,
		-- ...and how many times that solve ENTERED `measure`, against how many of
		-- those entries it answered from the node's own last answer (C2). Neither is
		-- `lastMeasured`: that counts UNCACHED measures, which a memo hit never moved
		-- either, so it cannot say what a cheaper lookup path is worth.
		lastMeasureCalls = 0,
		lastMeasureServed = 0,
		-- ...and the anchor branch's third arm (C3): children of an anchor the solve
		-- did not place at all, because the anchor's box stood still and they were
		-- clean at the identical offer. It is on the PUBLIC surface where the two
		-- older anchor counters are not, because a consumer's own contract test is
		-- the only instrument that can say the arm still reaches a real game screen.
		lastAnchorSkipped = 0,
		-- re-solves earned by a consumer publishing a layout prop back from this
		-- surface's own geometry (see THE SOLVE'S OWN FEEDBACK). The stated cost of
		-- closing that frame: one extra solve on the frame the number moves, which
		-- is the solve the NEXT frame used to pay.
		feedbackSolves = 0,
		-- solves served by re-solving one absorbing box instead of the whole tree
		partialSolves = 0,
		elided = 0,
		ssPasses = 0,
		ssEnsureTree = 0,
		ssRetire = 0,
		ssLivePaths = 0,
		ssSweep = 0,
		ssZOrder = 0,
		-- structuralSync phase timings, ms accumulated. MEASURED rather than assumed:
		-- the pass was believed to be O(all live nodes), and it is not — the no-op walk
		-- is ~6% of it and the rest is per-NEW-NODE setup. Kept so that stays visible.
		ssTotal = 0,
		-- ...and the syncs that could NOT be bounded and took the whole tree (O6),
		-- cumulative like the ms above, so a fixture that always falls back says so.
		ssFullPasses = 0,
		-- ...and the NODES the last sync touched. `last*` not `ss*`: the whole `ss`
		-- family is cumulative ms, same rule as `lastCommitVisits`.
		lastSsVisited = 0,
		lastSkipped = 0,
		-- ...and the SAME number published UNCONDITIONALLY (wicked-fast O3), because
		-- `lastSkipped` above is written only when it is > 0 and is therefore stale by
		-- design on any step that skipped nothing — an invariant reading it would pass
		-- or fail on history. Every new invariant reads this one.
		lastSolveSkipped = 0,
		-- ...and the O3 class: nodes an ancestor re-based by a delta instead of
		-- walking. `arranged + translated + skipped == lastLayoutNodes`.
		lastTranslated = 0,
		--[[ ...and the C6 class: hosts `render/translate_lane` MOVED with no solve.
			Cumulative, then the per-refresh count — written on EVERY refresh, 0 included,
			so an invariant reading it never reads history the way `lastSkipped` above
			deliberately does.

			"MOVED", NOT "CONSIDERED", and the distinction is pinned rather than assumed:
			the lane validates a candidate and then re-places it, and a placement prop
			written back to the value it already had produces no rect and is not counted.
			So `lastLaneTranslates` is a number every engine write corresponds to. The
			lane's REMAINDER is keyed on validation instead — a consumed candidate does
			not reach the solve whether or not its rect moved, because its layout node
			was re-placed either way. ]]
		laneTranslates = 0,
		lastLaneTranslates = 0,
		lastRectInserts = 0,
		-- ...and how many NODES the COMMIT's walks visited (P4): one per walk per node
		-- before the prune, O(touched) after it (`tests/commit_scope.spec.luau`).
		lastCommitVisits = 0,
		-- ...and the same number split by walk (wicked-fast T2). A FRESH table per
		-- commit: `controller.stats()` is a shallow clone, so a shared table would
		-- let the next commit rewrite a snapshot the caller already took. A walk
		-- the adapter cannot run (`visible`/`hitRects`/`scrollRegions` feature-
		-- detect `setVisible`/`setHitRect`/`setScrollRegion` and return before
		-- ever counting a visit) publishes NO key for itself — absent, not 0
		-- (Fix round 2 correction).
		lastCommitVisitsByWalk = {} :: { [string]: number },
		-- ...and how many LAYOUT NODES the last solve had (wicked-fast T2):
		-- `nodeStore.nodes`, the count the `work.skipped` repair below already
		-- computes and used to throw away. The only honest denominator for
		-- `arranged + translated + skipped` (`lastSkipped` is written only when
		-- skipped > 0, so it is stale by design).
		lastLayoutNodes = 0,
		-- ...and what the solve had to BUILD (P3): `solver.Node`s constructed by the
		-- last `layout_node.build`. 0 on a re-solve nothing dirtied, where it was N.
		lastNodeBuilds = 0,
		-- ...and the STRUCTURAL half (P5): add/remove/reorder solves that were
		-- boundary-rooted rather than full, and the PATH the last one was rooted at
		-- (nil = refused, or none yet).
		structuralPartialSolves = 0,
		lastStructuralBoundary = nil :: string?,
	}
end

--[[ WHAT A FINISHED SOLVE ANSWERED FOR, published into the record above.

	`work.skipped` IS REPAIRED HERE rather than taken from the solver: a full solve
	used to re-base that induction at every structural change and no longer does
	(P5 — `render/structural_scope`'s "WHAT `work.skipped` MEANS NOW" carries the
	argument and what it leaves alone). The repair is a WRITE BACK INTO
	`result.work`, deliberately: `rect_pass.apply` is handed the same record and
	reads the same field.

	`layoutNodes` is `nodeStore.nodes` — the count the repair already needs, and the
	only honest denominator for `arranged + translated + skipped`, since
	`lastSkipped` is written ONLY when skipped > 0 and is therefore stale by design.
	`structuralPartial` is held by the caller across the solve rather than counted
	here, because it is a fact about how the solve was SET UP.

	A SOLVE WITH NO `work` RECORD publishes nothing and counts nothing, exactly as
	the four separate blocks this replaces did. ]]
function render_stats.publish(stats: any, result: any, layoutNodes: number, structuralPartial: boolean)
	local work = result.work
	if work ~= nil then
		stats.lastLayoutNodes = layoutNodes
		work.skipped = math.max(0, layoutNodes - (work.arranged or 0) - (work.translated or 0))
		if (work.skipped or 0) > 0 then
			stats.partialSolves += 1
			stats.lastSkipped = work.skipped
		end
		-- the last solve's work, surfaced through `controller.stats()`. This is what
		-- makes "one changed value re-laid-out the whole tree" a testable claim rather
		-- than something you have to instrument the solver to see.
		stats.lastArranged = work.arranged
		stats.lastMeasured = work.measured
		stats.lastMeasureCalls = work.measureCalls or 0
		stats.lastMeasureServed = work.measureServed or 0
		stats.lastAnchorSkipped = work.anchorSkipped or 0
		-- ...and what the solve wrote into the RECT MAP (P2). It is not `lastArranged`
		-- by definition — before the copy-on-write map a skipped subtree inserted
		-- every descendant, so this is the number that says the skip is O(touched).
		stats.lastRectInserts = work.rectInserts
		-- ...and the O3 translate class, beside the UNCONDITIONAL skip count the
		-- invariants read (`lastSkipped` above is stale by design)
		stats.lastTranslated = work.translated or 0
		stats.lastSolveSkipped = work.skipped or 0
	end
	-- ...and the structural half, counted from the same side of the solve
	if structuralPartial then
		stats.structuralPartialSolves += 1
	end
end

return render_stats
