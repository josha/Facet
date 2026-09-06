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
		--[[ ...and the PATHS a text settle pushed as `measure` dirt on the last solve
			(Plan C, T18-A). Zero on every solve that is not a settle, which is what
			makes it readable as a class marker: a tick that moved it learned a word.
			The number is the paths NAMED, not the ancestor closure they expand to, so
			it is the size of the (font,size) key's user set on this surface — the
			quantity the whole narrowing is a function of, and the one a workload whose
			new words land on a 1,000-node key reads very differently from one whose
			land on a 4-node key. Written by `renderer.attach`'s solve rather than by
			`publish`: it belongs to the solve's INPUT, not to its work record. ]]
		lastTextDirtyPaths = 0,
		--[[ ...and how many of those calls a STACK's own measure branch made (Plan C,
			T13). It is the denominator the container memo moves: a hit removes the call
			entirely, so neither counter above can say where a saving came from — one
			does not see it and the other was already answering it cheaply. It counts
			CALLS, not loop iterations; the PASS 1 loop still walks every child. ]]
		lastChildVisits = 0,
		--[[ ...and the ITERATIONS, which are a different fact (Plan C, T13b). This is
			the child-array POSITIONS a stack's measure branch looked at — PASS 1 and the
			fill pass — where the counter above is the `measure` calls it made. T13's memo
			cut the calls and left the loops; T13b enumerates the dirty children from the
			container's own reverse map, so this falls while `lastChildVisits` does NOT
			move. The `crossMax` fold is the named O(n) residual and is not counted here:
			it is measured at 1.9 % of the three passes and a patched argmax would need a
			rescan on up to 14.8 % of folds. ]]
		lastChildIterations = 0,
		--[[ ...and the ARRANGE side of the same distinction (Plan C, T14). This is how
			many times `arrangeBody` was ENTERED, where `lastArranged` is how many bodies
			RAN — a gap that is the whole cost of a stack re-placing children whose
			arrangement did not move, because the early skip sits above every counter
			this record already had. `lastPlaceSkipped` is the per-child census beside
			it: the placement-loop iterations the replay did not spend. Neither may be
			read without the other, because an entry count cannot fall below the
			container count and a skipped-placement count cannot say how many containers
			paid for it. ]]
		lastArrangeEntries = 0,
		lastPlaceSkipped = 0,
		-- ...and how often that aggregate STARTED and refused, on one of its two
		-- performance valves (the probe budget or a `fill` classification change).
		-- A class where this is non-zero is reported, never averaged away.
		lastAggregateFallbacks = 0,
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
		--[[ ...and the PAINT-ORDER WALK's own pair (Plan C, C5), CUMULATIVE where the
			one above is a last capture, because a frame can run TWO z walks: the
			structural sync's bounded one and the commit's hit-lift re-run, which is
			whole-tree and lands after it. A `last` number would report whichever ran
			second and a reader could not tell which. Read as a delta over a drive, with
			`zPasses` in the same string, they say both how many walks a change caused
			and what they cost together — which is also the shape that survives a drive
			that ran no walk at all.

			`zVisits` counts NODES TOUCHED, skips included: the z walk starts at the
			mount root every time and reaches a change by SKIPPING a subtree whose
			numbers cannot have moved, so its cost is the descent plus the changed
			parent's children, and this is the number that says the skip still lands. ]]
		zPasses = 0,
		zVisits = 0,
		--[[ ...and the LIVE size of the walk's own memo — a gauge, not a total, kept on
			the two transitions rather than counted. It exists to pin one rule that no
			differential can see: a LEAF earns no memo entry, because skipping a childless
			node saves nothing while an entry per node cost a measured 16 % on the step
			that allocates the most (`battle_hud setState`). Giving a leaf an entry is
			CORRECT, merely expensive, so the regression would return in silence; this is
			the number that refuses it. It equals the count of mounted nodes that have
			children. ]]
		zMemoEntries = 0,
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
		--[[ ...and how many CHILDREN the commit CONSIDERED (Plan C, C4), which is a
			different number from the one above and the one the commit span is actually
			made of. A walk that prunes a subtree still asks `skip` of every child of
			every node it DID visit, so a one-leaf update on a 1,000-row list visits four
			nodes and asks 1,000 questions — eight times over, once per walk. `visits`
			counts the answers that were "descend"; this counts the questions. It is the
			denominator C4's descend-list cache moves, and the one number that would have
			stayed flat while the span halved. ]]
		lastCommitScans = 0,
		--[[ ...and what those answers were STORED in (Plan C, C4 fix round 1). One per
			array `buildDescend` materialised for a descend list, plus the slots it
			reserved — the list's own header counted as one, so a fork that keeps
			nothing is still visible. It is the counter for the OTHER half of the
			cost: the questions fell 8x and the milliseconds did not follow on a
			commit that prunes nothing, because the answer was being written into
			three worst-case-sized arrays per visited node. `deep_stack_scene` at
			1,000 rows, one leaf's text: 3,004 -> 3. ]]
		lastCommitListCells = 0,
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
		stats.lastChildVisits = work.childVisits or 0
		stats.lastChildIterations = work.childIterations or 0
		stats.lastArrangeEntries = work.arrangeEntries or 0
		stats.lastPlaceSkipped = work.placeSkipped or 0
		stats.lastAggregateFallbacks = work.aggregateFallbacks or 0
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
