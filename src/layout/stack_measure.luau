--!strict
--[[ THE VSTACK/HSTACK *MEASURE* BRANCH, lifted out of `layout/solver.luau` on
	2026-09-05 — the measure-side sibling of `./stack`, which took the ARRANGE half of
	the same two kinds on 2026-09-02 for the same reason.

	WHY NOW. Plan C's lever wave gives this branch a per-child memo (T13): a container
	whose children are clean stops re-asking `measure` for each of them. The mechanism
	plus the reasoning it owes is ~5,500 characters and `solver.luau` had 7,388 usable
	below the campaign's 197,500 STOP line for FOUR tasks. `tools/lune/verify/data/source-cap-ledger.md`
	demands the room be taken FIRST, in its own behaviour-neutral commit, before a
	character of the change that needs it — so this commit is the move alone, and the
	memo lands in the next one.

	IT IS ONE-WAY, which is the only test this repository judges a split by: the block
	reads no mutable upvalue of its host. What it needs from the solver is four
	bind-time things — `measure` (a forwarder, because the solver's `measure` is a
	forward local assigned far below the record's line and a by-value capture there
	takes nil), `dim`, `sides`, and the `shrink` record itself, passed rather than
	rebuilt so the two cannot end up reading a different `mainDimOf`. There are no
	call-site arguments: unlike the arrange branch, nothing this block calls is
	declared below the Deps record.

	WHAT IT REQUIRES DIRECTLY: `./shrink`, for the measure-side shrink pass (PASS 1.5)
	this branch and `./stack` are the only two callers of. It is a leaf the solver also
	requires and it requires nothing in this direction, so the graph stays acyclic in
	the shape `./grid`, `./flow`, `./stack` and `./scroll_arrange` have proven four
	times.

	NO BEHAVIOUR CHANGES. `tests/stack_measure_seam.spec.luau` mechanises the emptiness
	above; the behaviour half is the whole suite, which drives a vstack or an hstack on
	very nearly every fixture in the repository. ]]
local shrinkLib = require("./shrink")
local baseline = require("./baseline")
local spacerMinimum = require("./measure_facts").spacerMinimum

local permutation = require("./row_permutation")

local stack_measure = {}

--[[ THE SEVEN SHAPES A CONTAINER'S MEASURE BRANCH CAN NEVER SERVE (owed row A13).
	Five of them are the serve's own refusals asked of a child — the two kinds that
	publish verdicts no cached number can carry (`text`, `composition`), the two
	subtree booleans whose OWNER publishes a channel, and the container-relative mark
	— plus a declared shrink weight, which the skip arm refuses on `== nil` so a
	declared ZERO is unservable too and the two must agree.

	IT IS A MODULE FUNCTION AND NOT AN INLINE PREDICATE because T13b's fix round made
	it have TWO readers: the full pass classifies with it, and the aggregate's pre-pass
	re-asks it of every index it is about to visit. Two copies of a seven-term
	predicate is the copy-goes-stale failure this file's own seam header is about, and
	a module function closes over nothing, so it allocates nothing per call. ]]
local function alwaysVisit(child: any): boolean
	return child.kind == "text"
		or child.kind == "composition"
		or child.subtreeHasScroll == true
		or child.subtreeHasComposition == true
		or child.containerRelativeInside == true
		or child.shrinkWeight ~= nil
end

-- What the branch needs from the solver, passed at every call. Typed `any` for the
-- node/ctx arguments on purpose: the solver requires THIS module, so importing
-- `solver.Node`/`Ctx` back would be a require cycle, and re-declaring either schema
-- here is the copy-goes-stale failure this seam exists to avoid — the same ruling
-- `shrink.Deps`, `grid.Deps` and `stack.Deps` carry.
export type Deps = {
	measure: (ctx: any, node: any, maxW: number, maxH: number) -> (number, number),
	dim: (node: any, axis: string) -> any,
	sides: (margin: any) -> (number, number, number, number),
	-- the record `./shrink` takes, built by the solver and NOT rebuilt here
	shrink: shrinkLib.Deps,
	baseline: any,
}

--[[ THE CONTENT SIZE OF A VSTACK/HSTACK, and the three passes that produce it: the
	definite-main children (PASS 1), the measure-side shrink (PASS 1.5) and the `fill`
	children's weighted share (PASS 2). The caller has already resolved the padding and
	the inner box, so this function is handed them rather than re-deriving them from a
	node it would then have to know the sizing rules of.

	It returns `(w, h)` in the solver's own order, which is why the two `return`s at the
	tail are not one: the branch computes MAIN and CROSS, and which of those is width
	depends on the kind. ]]
function stack_measure.contentSize(
	deps: Deps,
	ctx: any,
	node: any,
	innerMaxW: number,
	innerMaxH: number,
	gap: number,
	pt: number,
	pr: number,
	pb: number,
	pl: number
): (number, number)
	-- the four names this branch spends, bound once at the top so the body below is
	-- the solver's LINE FOR LINE and a reviewer's diff is a move, not a rewrite
	local measure, dim, sides = deps.measure, deps.dim, deps.sides
	local SHRINK_DEPS = deps.shrink
	local isH = node.kind == "hstack"
	local children = node.children or {}
	local n = #children
	local gaps = if n > 1 then gap * (n - 1) else 0
	local mainLimit = if isH then innerMaxW else innerMaxH
	local mainSum, fillWeightSum = 0, 0
	local crossOf: { [number]: number } = {}
	local marginMain: { [number]: number } = {}
	-- lazily created, and only ever by a child that declared a shrinkWeight ABOVE
	-- ZERO: a stack that opted into nothing allocates nothing here and PASS 1.5
	-- below never runs. The one cost on the inert path is the field read in PASS 1.
	--
	-- `> 0`, NOT `~= nil` (Milestone-1 review, C6). `shrinkWeight = 0` is the
	-- documented default AND a legal authored value — "never shrinks", Roblox's
	-- `UIFlexMode.None` — so a caller who writes it explicitly means the inert
	-- behaviour. The `~= nil` form allocated `shrinkBasis`, ran PASS 1.5 and called
	-- `shrinkLib.stack` for it, which then filtered it out one level down on exactly
	-- this test. Same filter, one level earlier.
	local shrinkBasis: { [number]: number }? = nil
	--[[ THE CONTAINER MEMOISES ITS CHILDREN'S ANSWERS (Plan C, T13).

		This branch re-measured every child on every call. On the arena's `battle_hud`
		workload at L a ONE-LEAF write measured 6 nodes and entered `measure` 2,221
		times, 2,206 of which the node-resident serve answered from the child's own
		slots in 0.47 us each. That serve made the ANSWER cheap; it could not make the
		PARENT stop asking, and 1.038 ms of a 1.824 ms class is the asking.

		SO THE PARENT KEEPS THE ANSWERS. Four per-child arrays, indexed by child index,
		on the container's `cmemo` — whose home is the mount-keyed store entry, because
		a container holding one dirty child has its layout node REBUILT and a memo
		living there would be nil on exactly the ticks this is for.

		NOTHING IS AGGREGATED AND NOTHING IS PATCHED. `mainSum` is re-summed from
		`mMain` exactly as it always was, which is an add loop this branch already pays
		and which cannot drift from a base the shrink pass moved. The saving is the
		`measure` CALL, at 0.47 us against three hash reads and a string compare — and
		it is the WHOLE call, not call overhead: the skip returns before `measure` is
		entered, so this branch owes every channel that call would have published, one
		by one. That list is the header of `tests/container_memo.spec.luau`.

		THE KEY IS THE RAW OFFER PAIR PLUS THE SOLVE'S SCOPE AND STAMP: the pair this
		loop actually hands its children, not the reduced height key `measure` uses for
		its own slots, which would be a WIDER key than the answers were recorded under.
		`ctx.scopeKey` already carries the `|fit` segment, so a `ViewThatFits` probe
		cannot collide with the real measure of the same node.

		AND THE GATE IS THE SERVE'S GATE ASKED OF THE CHILDREN, PLUS TWO SHAPES THIS
		BRANCH CANNOT SERVE: a child that publishes verdicts (`text`, `composition` —
		the exact pair `record` branches on), refused PER CHILD and never by taking the
		container down with it, and any container holding a `shrinkWeight > 0` child,
		which sets `memoable` false because PASS 1.5 rebases `mainSum`. The per-child
		form is not a nicety: measured on `battle_hud L`, killing the container at its
		first `text` child serves 1.4 % of this loop's calls where refusing that child
		alone serves 96.8 %, because a real flat list splices labels straight into the
		row it is a list of. ]]
	local cmemo = node.cmemo
	local reuse = ctx.reuse
	local dirty = if reuse ~= nil then reuse.measureContains else nil
	local hit = cmemo ~= nil
		and dirty ~= nil
		and ctx.measureQuiet
		and not ctx.analyze
		and ctx.measureStamp ~= nil
		and cmemo.mStamp == ctx.measureStamp
		and cmemo.mScope == ctx.scopeKey
		and cmemo.mOffW == innerMaxW
		and cmemo.mOffH == innerMaxH
		--[[ ...AND THE AXIS, which was missing and is a wrong pixel (found by T13b while
			proving owed row A2). `mMain[idx]` is the child's contribution on the MAIN
			axis and `mCross[idx]` on the cross one; which of those is width is
			`node.kind`. A `UI.Stack{ axis = signal }` flips `kind` between `vstack` and
			`hstack` through a PROP (`render/layout_node`, the stack literal), and `axis`
			is not a node fact, so the flip is measure-classed dirt on the container
			alone: the carrier keeps the memo (the mount children table is the same
			object), every child stays clean, and a container with a definite box offers
			the identical `innerMaxW`/`innerMaxH` on both sides of the flip. Every other
			term in this key would hold and the memo would serve heights as widths. One
			compare, and `tests/container_aggregate.spec.luau` drives it. ]]
		and cmemo.mKind == node.kind
	-- Structural dirt changes indices. Validate the complete unchanged set before
	-- remapping any answer; deletion may keep a clean subset. A changed survivor
	-- makes this a normal full pass.
	if hit and cmemo.struct == true and not ctx.memoAudit and not ctx.aggregateAudit then
		local order = permutation.order(children, cmemo.mIds, cmemo.mN, dirty, nil, true)
		if order ~= nil then
			cmemo.mMain = permutation.remap(cmemo.mMain, order)
			cmemo.mCross = permutation.remap(cmemo.mCross, order)
			cmemo.mCuts = permutation.remap(cmemo.mCuts, order)
			cmemo.mIds = permutation.remap(cmemo.mIds, order)
		end
	end
	local memoable = cmemo ~= nil and reuse ~= nil and ctx.measureStamp ~= nil and not ctx.analyze
	local mMain, mCross, mCuts, mIds
	if memoable then
		if hit then
			mMain, mCross, mCuts, mIds = cmemo.mMain, cmemo.mCross, cmemo.mCuts, cmemo.mIds
		else
			mMain, mCross, mCuts, mIds = {}, {}, {}, {}
		end
	end
	if cmemo ~= nil and reuse ~= nil then
		-- OWED ROW A1, AND IT IS ONE FIELD: "this container measured on THIS solve".
		-- A child this pass SERVES is never handed to `measure`, so nothing writes
		-- `ctx.offers` for it and the arrange entry literal would file a nil offer,
		-- disarming both anchor arms. The offer it needs is the memo's own key, and
		-- `solver`'s entry literal reads it through `child.oMemo` behind this stamp.
		cmemo.mSolve = ctx.solveToken
	end
	--[[ THE PARENT STOPS LOOKING AT THE CHILDREN IT DID NOT ASK (Plan C, T13b —
		rulings L-7 and L-8). T13 above made the WORK inside these loops O(dirty) and
		left the loops themselves: measured at `66ccc867`, PASS 1's walk is 0.207 ms of
		a 1.802 ms class on the arena's `battle_hud L updateItem-hp`, the fill scan
		0.005 and the `crossMax` fold 0.004 — 12.0 % of the class and the dominant term
		in this branch.

		SO THE DIRTY CHILDREN ARE ENUMERATED INSTEAD OF FOUND. `reuse.measureContains`
		is 5 entries on that class and the container's own reverse map turns them into
		indices; the ALWAYS-VISIT list (a child whose kind or weights this branch can
		never serve) and the FILL list are recorded, ascending, by the full pass.
		Everything else is a number this container already holds.

		AND THE FOLD BELOW STAYS O(n) ON A MEASUREMENT, NOT A HABIT: it is 3.6 ns a
		child, 1.9 % of the three passes, and a patched `crossMax` argmax would need a
		full rescan every time the argmax child shrinks — measured 0.09 % of hit folds
		on `battle_hud`, 6.9 % on `war_room_inventory`, 14.8 % on `killfeed_nameplates`.
		Amendment A-4's third withdrawal reason is answered by not building the thing.

		EVERY REFUSAL IS DECIDED BEFORE A SINGLE WRITE (plan review, M3). The first
		version aliased the arrays and then `break`ed out of the measuring loop on two
		valves, which left HEAD's pass running on a poisoned `crossOf` sentinel, a
		double-counted `mainSum` and a double-counted `ctx.childVisits` — the counter
		the whole acceptance argument rests on. So this is a PRE-PASS that reads
		`dim`/`sides`/the memo and calls no `measure`, and a committed loop that cannot
		bail. ]]
	local agg = hit
		and cmemo.mSum ~= nil
		and cmemo.mN == n
		-- owed row A2: the one tick class on which an index binding can move under an
		-- unchanged mount children table is a STRUCTURAL refresh, and `render/layout_node`
		-- stamps it from the argument the renderer already passes
		and cmemo.struct ~= true
		-- ...and NEITHER audit: T13's forces every child through `measure` so its own
		-- per-index assert has something to compare, and an aggregate that skipped PASS 1
		-- would take that arm away from it (found by the run — `memoChecks` read 0)
		and not ctx.memoAudit
		and not ctx.aggregateAudit
	-- the visit list, ascending and deduplicated, or nil for "this tick walks"
	local visit: { number }? = nil
	local aggFillWeight = 0
	if agg then
		local mIsFill, mFill = cmemo.mIsFill, cmemo.mFill
		--[[ OWED ROW A10: the walk is BOUNDED BY A PROBE BUDGET, not by trust. This
			loop walks the whole measure closure, not this container's share of it, so a
			wide closure could make the aggregate slower than the walk it replaces. The
			floor is `math.max(4, …)` because a bare `n // 4` is 0 below four children
			and 1 below eight — every small container in a real tree would pay a probe
			walk and then fall back, which is cost with no gain (plan review, S3).

			AND THE BUDGET IS SPENT BEFORE THE MAP BELOW IS BUILT, which is why this is a
			bare count rather than the resolve loop under it: a tick that bails here must
			not have paid for anything. ]]
		local budget = math.max(4, n // 4)
		local probes = 0
		for _ in dirty do
			probes += 1
			if probes > budget then
				agg = false
				break
			end
		end
		ctx.childIterations += probes
		local list: { number } = {}
		if agg then
			--[[ THE REVERSE MAP IS BUILT LAZILY, AND THE ARENA IS WHAT DECIDED THAT. The
				first version built `id -> index` inside the full pass, for every child,
				on every full pass — and measured on the arena's `battle_hud L`, that is
				1,100 string-keyed hash inserts riding a walk that already runs, which cost
				**+0.3 ms (+12 %) on `removeItem-damage`**, a STRUCTURAL class the aggregate
				refuses outright. A lever that pays for itself on one class out of another's
				pocket is not a lever, and only the three-arm interleave could see it.

				SO IT IS BUILT ON THE FIRST TICK THAT WOULD SPEND IT, and dropped by every
				completed full pass (the tail below) — which is the only event that can move
				an index binding this pass is allowed to run under, because every OTHER way
				a layout children sequence can change makes the refresh structural and
				`cmemo.struct` refuses those before this line. One O(n) walk per full-pass
				epoch, amortised over every aggregating tick in it, and ZERO on a container
				that never aggregates. ]]
			local mIdx = cmemo.mIdx
			if mIdx == nil then
				local built: { [string]: number } = {}
				for idx, child in children do
					built[child.id] = idx
					--[[ OWED ROW A1 RIDES THE SAME WALK, and the arena is why it rides THIS
						one rather than the full pass. A child this container SERVES is never
						handed to `measure`, so nothing writes `ctx.offers` for it and the
						arrange entry literal files a nil offer — which disarms both anchor
						arms, and on an aggregating surface it disarms them on every tick
						rather than for one. The pointer is to THIS memo, whose key already IS
						the offer (`mOffW`/`mOffH`), and the gate above has just proved that
						key equals this tick's offer.

						WRITTEN ONCE PER EPOCH, NOT ONCE PER PASS. The first version stamped it
						in the record block, per child, on every full pass: measured on the
						arena's `battle_hud L`, that plus one accumulator cost **0.15 ms a full
						pass** — `removeItem-damage` +6.2 % against the counters-only arm, and
						the hp class handed back a third of its own win. Here it rides the walk
						the reverse map already pays for, and a container that never aggregates
						never pays it at all. ]]
					child.oMemo = cmemo
				end
				cmemo.mIdx = built
				mIdx = built
				ctx.childIterations += n
			end
			table.move(cmemo.mAlways, 1, #cmemo.mAlways, 1, list)
			for id in dirty do
				local idx = mIdx[id]
				if idx ~= nil and dirty[id] == true and mIsFill[idx] ~= true then
					table.insert(list, idx)
				end
			end
		end
		local ordered: { number } = {}
		if agg then
			--[[ OWED ROW A9, AND IT IS THE TRAP IN THIS TASK. The dirty set is a HASH and
				iterating it gives an arbitrary order; PASS 1.5's own comment states the
				rule (last-write-wins verdict channels — `compact`, `textFacts` — must
				publish deterministically). k is 1-20 on every class measured here, so the
				sort is free. A child in the always list AND in the dirty set appears
				twice, and measuring it twice would patch `mainSum` twice — hence the
				dedupe, which the sort makes one compare. ]]
			table.sort(list)
			local prev = -1
			local mAlwaysAt = cmemo.mAlwaysAt
			for _, idx in list do
				if idx == prev then
					continue
				end
				prev = idx
				local child = children[idx]
				-- owed row A3, one direction: a recorded non-fill child that became fill
				if dim(child, if isH then "w" else "h").type == "fill" then
					agg = false
					break
				end
				--[[ ...AND OWED ROW A13'S OTHER SIX PREDICATES, RE-ASKED (fix round 1,
					I-1). The row's argument was that a flip cannot reach an UNVISITED
					index, and that is true — but it is only half of what the payload
					needs. The flip tick VISITS the child and measures it correctly, and
					then the classification is thrown away, because `mAlways` is recorded
					only by a completed full pass. From the next tick the child is neither
					in `mAlways` nor dirty, so it is SERVED — a serve HEAD's own PASS 1
					refuses by this very predicate, and `lastChildVisits` falls BELOW the
					walk's, which owed row A11 names as the one thing this task must not do.

					`containerRelativeInside` is the reachable vector and it needs no
					remount and no structural refresh: it is a pure function of a
					DESCENDANT's dim type (`render/layout_node`), and `width`/`height` are
					reactive measure-classed props. Measured on two trees identical at tick
					4 — declared from the start, `visits=3`; ARRIVING at tick 3,
					`visits=2`, the child never measured again.

					SO THE PRE-PASS REFUSES, exactly as the `fill` valve one line up does
					and for the same reason: refusal is free, it is decided before any
					write, and HEAD's pass then re-records `mAlways` correctly. It catches
					BOTH directions — a predicate that arrives, and one that departs and
					would otherwise leave the child over-visited forever. ]]
				if alwaysVisit(child) ~= (mAlwaysAt[idx] == true) then
					agg = false
					break
				end
				table.insert(ordered, idx)
			end
		end
		if agg then
			--[[ OWED ROWS A4 AND A8, AND THE PLAN HAD BOTH BACKWARDS. It said PASS 2
				supplies `marginMain[idx]` and `fillWeightSum`; PASS 2 only READS them,
				and both are written by PASS 1, which this path does not run. Without
				this loop `fillWeightSum` is 0, the share below is `math.huge` and every
				fill child measures at an unbounded main extent — the "painted at a size
				nobody measured" family PASS 1.5 was written for. It is O(#fill), which
				is 1-2 children on the measured classes, and it carries owed row A3's
				OTHER direction: a recorded fill child that stopped being one. ]]
			for _, idx in mFill do
				local child = children[idx]
				local childMainDim = dim(child, if isH then "w" else "h")
				if childMainDim.type ~= "fill" then
					agg = false
					break
				end
				local mt, mr, mb, ml = sides(child.margin)
				marginMain[idx] = if isH then ml + mr else mt + mb
				aggFillWeight += childMainDim.weight or 1
			end
		end
		if agg then
			visit = ordered
			ctx.childIterations += #ordered + #mFill
		else
			-- STARTED and refused, which is the only thing this counter means: a tick
			-- the aggregate never entered is not a fallback (plan review, S2)
			ctx.aggregateFallbacks += 1
		end
	end
	-- the payload the NEXT tick reads, built by the full pass below and recorded at the
	-- tail. The reverse map is NOT among them: it is the only O(n) one, and it is built
	-- lazily above on the first tick that would spend it (measured — see that block).
	local always: { number } = {}
	-- ...and the same list AS A SET, which the aggregate's pre-pass asks per visited
	-- index (fix round 1, I-1). An array cannot answer "was THIS index classified
	-- always-visit" without a scan, and the pre-pass asks it k times a tick.
	local alwaysAt: { [number]: boolean } = {}
	local fills: { number } = {}
	local isFill: { [number]: boolean } = {}
	-- the sum of `mCuts` over the RECORDED indices, which is what an unvisited child's
	-- cuts are patched from (owed row A7)
	local cutsSum = 0
	-- ...and the audit's snapshot of the payload as the aggregate would have found it,
	-- taken BEFORE the pass overwrites the arrays in place (see the oracle below)
	--[[ ...AND THE TWO AUDITS ARE MUTUALLY EXCLUSIVE, which is a property of what each
		one asks. T13's `memoAudit` makes the skip never fire, so PASS 1 measures every
		child; T13b's oracle predicts the set the AGGREGATE would have visited and
		compares it against the set PASS 1 actually measured. With both on, the second
		comparison is "dirty ∪ always" against "everything", which fails on healthy
		input. ]]
	local auditOn = ctx.aggregateAudit
		and not ctx.memoAudit
		and hit
		and cmemo.mSum ~= nil
		and cmemo.mN == n
		and cmemo.struct ~= true
	local aSum, aCutsSum, aMain, aCuts, aIds, aIdx, aAlways, aAlwaysAt, aFill, aIsFill
	local auditMeasured: { number }? = nil
	if auditOn then
		aSum, aCutsSum = cmemo.mSum, cmemo.mCutsSum
		aMain, aCuts, aIds = table.clone(cmemo.mMain), table.clone(cmemo.mCuts), table.clone(cmemo.mIds)
		aAlways, aAlwaysAt = cmemo.mAlways, cmemo.mAlwaysAt
		aFill, aIsFill = cmemo.mFill, cmemo.mIsFill
		-- ...and the map the aggregate would have used, built here when the lazy build
		-- above has not run yet: this arm is test-only, so it pays that walk itself
		aIdx = cmemo.mIdx
		if aIdx == nil then
			local built: { [string]: number } = {}
			for idx, child in children do
				built[child.id] = idx
			end
			aIdx = built
		end
		auditMeasured = {}
	end
	if visit ~= nil then
		--[[ THE COMMITTED LOOP. Nothing above it has written a solve-visible number, and
			nothing in it can refuse. The arrays ARE the memo's on this path (owed row
			A5): the fold at the bottom needs EVERY index, and the indices this pass does
			not touch are exactly the ones it must not re-derive. ]]
		crossOf = cmemo.mCross
		fillWeightSum = aggFillWeight
		mainSum = cmemo.mSum
		cutsSum = cmemo.mCutsSum
		local cutsOwed = cutsSum
		local mMainA, mCutsA, mIdsA = cmemo.mMain, cmemo.mCuts, cmemo.mIds
		for _, idx in visit do
			local child = children[idx]
			local mt, mr, mb, ml = sides(child.margin)
			marginMain[idx] = if isH then ml + mr else mt + mb
			ctx.childVisits += 1
			local cutsBefore = ctx.fitCuts
			local cw, ch = measure(ctx, child, innerMaxW, innerMaxH)
			local mainOf = (if isH then cw + ml + mr else ch + mt + mb) + spacerMinimum(child, isH)
			crossOf[idx] = if isH then ch + mt + mb else cw + ml + mr
			-- OWED ROWS A6 AND A7, the only arithmetic in this task, and both are exact
			-- because a served number IS the number the walk would have produced for
			-- that index. `mMain` is complete for EVERY index (see the full pass), which
			-- the first draft's `or 0` was not: an always-visit child is never RECORDED,
			-- so `or 0` would have added its whole contribution on top of a sum that
			-- already held it.
			mainSum += mainOf - mMainA[idx]
			if mIdsA[idx] ~= nil then
				local now = ctx.fitCuts - cutsBefore
				cutsOwed -= mCutsA[idx]
				cutsSum += now - mCutsA[idx]
				mCutsA[idx] = now
			end
			mMainA[idx] = mainOf
			--[[ OWED ROW A12: A `shrinkWeight` THAT ARRIVES ON AN AGGREGATING CONTAINER.
				`memoable = false` does not clear `hit`, so the key still matches and this
				path can run on the very tick a weight appears. It builds the basis
				exactly as PASS 1 does and drops the key at the tail, so PASS 1.5 runs
				over a `mainSum` that is exact (the capture below is pre-shrink) and the
				next tick is a full pass. Refusing the aggregate instead would also be
				correct, and it is what the plan review proposed — but it would refuse
				forever for any container holding a `shrinkWeight = 0` child, which is
				the documented "never shrinks" value and a legal authored one. ]]
			if child.shrinkWeight ~= nil and child.shrinkWeight > 0 then
				local basis = shrinkBasis or {}
				basis[idx] = if isH then cw else ch
				shrinkBasis = basis
				memoable = false
			end
		end
		ctx.fitCuts += cutsOwed
	end
	-- PASS 1: children with a definite main extent measure against the whole
	-- inner box, and consume it. UNCHANGED by T13b except for what it RECORDS: it is
	-- the arm every refusal above falls back to, and it must behave exactly as it did.
	if visit == nil then
		ctx.childIterations += n
		for idx, child in children do
			local childMainDim = dim(child, if isH then "w" else "h")
			--[[ MAY THIS PARENT SKIP ASKING? The serve's own question was "may this CHILD
			be served"; this is the other one, and it is asked of five things the child
			carries plus the memo's own index binding.

			THE INDEX IS NOT THE IDENTITY. A `UI.ForEach` splice shifts every later
			index while the MOUNT children table the carrier gate compares stays the
			SAME OBJECT — `mount` replaces the REGION's children, never its parent's —
			so an array position alone would serve another node's number. Measured, the
			index-keyed form reads 98 % skippable on a remove where every index moved,
			and every one of those serves would be wrong. `child.id` is the mount PATH
			(`render/layout_node`): stable across a rebuild and unique among siblings,
			but NOT an identity — a region re-creating different content under the same
			path is caught one level up, where a structural solve widens
			`measureContains` to the whole dirty closure, and never here. ]]
			local skippable = hit
				and childMainDim.type ~= "fill"
				and dirty[child.id] ~= true
				and mIds[idx] == child.id
				and mMain[idx] ~= nil
				and child.kind ~= "text"
				and child.kind ~= "composition"
				and child.shrinkWeight == nil
				and child.subtreeHasScroll ~= true
				and child.subtreeHasComposition ~= true
				and child.containerRelativeInside ~= true
			if skippable and not ctx.memoAudit then
				--[[ THE SKIP, AND THE TWO CHANNELS IT OWES. `measure` was not called, so
				nothing it publishes has been published — and the entry literal of a child
				that is ARRANGE-dirty but MEASURE-clean reads `ctx.offers` for its
				`offerW`/`offerH`. A nil there disarms BOTH anchor arms for the life of the
				surface. The RAW offer is the right value, because the serve one level down
				writes the raw pair too. `mCuts[idx]` is the `ctx.fitCuts` delta this
				child's own call produced when it was recorded, which is what `record`
				subtracts to get a node's `cuts`.

				`marginMain[idx]` IS NOT OWED, AND A FIFTH ARRAY FOR IT WAS DELETED (review
				round 1, I-1). It has exactly one reader — the fill pass below — and that
				pass reads it only where `crossOf[idx] == nil`, which a skipped index never
				is: the line under this one writes `crossOf[idx]`, and `mMain`/`mCross` are
				recorded together so neither can exist without the other. Carrying it cost
				an array, a write and a read per child per solve, plus an audit term that
				could never differ, on the branch whose own finding is that the residual is
				now the dominant term. If a later task gives the fill pass a second reader,
				it re-adds the array WITH a case that fails without it. ]]
				ctx.offers[child.wKey or (child.id .. "|w")] = innerMaxW
				ctx.offers[child.hKey or (child.id .. "|h")] = innerMaxH
				ctx.fitCuts += mCuts[idx]
				crossOf[idx] = mCross[idx]
				mainSum += mMain[idx]
				-- ...and T13b's: the recorded cuts total the next tick patches from (owed
				-- row A7). The audit's own half of it is DERIVED in the audit block rather
				-- than accumulated here — an unconditional second `+=` per SKIPPED child is
				-- a thousand adds a pass on the arena's `battle_hud`, for a number no
				-- production solve reads.
				cutsSum += mCuts[idx]
				continue
			end
			local mt, mr, mb, ml = sides(child.margin)
			marginMain[idx] = if isH then ml + mr else mt + mb
			if childMainDim.type == "fill" then
				fillWeightSum += childMainDim.weight or 1
				--[[ ...AND THE FILL LIST, WHICH REPLACES THE FILL PASS'S OWN SCAN (T13b).
				That pass walked every index and skipped the ones `crossOf[idx] ~= nil`
				answered; the set it finds is exactly this one, in exactly this order, so
				the scan is a walk to re-derive a list this loop already knows. It has to
				exist anyway: the sentinel cannot survive the aggregate's PERSISTED
				`crossOf`, where no index is ever nil. ]]
				table.insert(fills, idx)
				isFill[idx] = true
				if mIds ~= nil then
					-- a fill child is never recorded, and a child that BECAME fill must
					-- lose the record it had (fix round 1, I-2)
					mIds[idx], mCuts[idx] = nil, nil
				end
				-- a fill child contributes nothing to `mainSum` in this pass, and owed row
				-- A6 needs `mMain` complete at EVERY index, not only the recorded ones
				if mMain ~= nil then
					mMain[idx] = 0
				end
			else
				ctx.childVisits += 1
				local cutsBefore = ctx.fitCuts
				local cw, ch = measure(ctx, child, innerMaxW, innerMaxH)
				local mainOf = (if isH then cw + ml + mr else ch + mt + mb) + spacerMinimum(child, isH)
				local crossOfIdx = if isH then ch + mt + mb else cw + ml + mr
				mainSum += mainOf
				crossOf[idx] = crossOfIdx
				if child.shrinkWeight ~= nil and child.shrinkWeight > 0 then
					local basis = shrinkBasis or {}
					basis[idx] = if isH then cw else ch
					shrinkBasis = basis
					-- ...AND THE CONTAINER STOPS MEMOISING, because PASS 1.5 below rebases
					-- `mainSum` by what the shrink absorbed and re-measures at the reduced
					-- offer — numbers this memo does not hold. It does not stop the memo
					-- being HIT on this tick: a weight that ARRIVES on a container that
					-- already memoised at this offer leaves the key matching, so PASS 1.5
					-- runs over a partly served `mainSum`. That is exact — a served number
					-- is the number this loop would have produced for that index — and the
					-- tail below drops the key so the next tick starts again.
					memoable = false
				end
				--[[ THE AUDIT ARM (ruling A-12, routed by ruling L-4 through the solver's own
				opts rather than an attach opt). When it is on the skip above never fires
				and the memo's answer is compared against the real one instead, so a
				differential exercises this arithmetic on EVERY container it touches
				without any gate being weakened. It asks `skippable`, which is the SKIP's
				own predicate — comparing against a DIRTY child's fresh answer would be
				asserting the memo is stale, which is what dirt means. And it runs BEFORE
				the record below, because the record overwrites the very numbers it
				compares. Off in production; there is no third behaviour.

				`mCuts` IS IN THE COMPARISON, and it was not (review round 1, I-2). The cuts
				delta is the one recorded number with no geometric shadow: a wrong one moves
				no rect, so the nine-view rect differential cannot see it, and it reaches
				the world only through `chosenCandidate`'s `uncut` test one ladder up —
				where under-counting makes a candidate that WILL paint an ellipsis look
				honest. An audit that compares the numbers a snapshot already compares is
				an audit of the snapshot. ]]
				if skippable then
					ctx.memoChecks += 1
					assert(
						mMain[idx] == mainOf and mCross[idx] == crossOfIdx and mCuts[idx] == ctx.fitCuts - cutsBefore,
						`container memo mismatch at {node.id}[{idx}]`
					)
				end
				--[[ RECORDED, OR NOT RECORDED — never "and the container gives up". A
				`text`/`composition` child is refused PER CHILD: its index is left
				unrecorded, so the skip arm's `mIds[idx] == child.id` term refuses it on
				every later tick and `record` publishes its verdicts exactly as it does
				today. The three subtree booleans are the serve's own, asked of the child
				for the channels no cached number can carry back. ]]
				if auditMeasured ~= nil then
					auditMeasured[#auditMeasured + 1] = idx
				end
				if mMain ~= nil then
					-- COMPLETE AT EVERY INDEX, which the record below is deliberately not
					-- (owed row A6). `mIds` stays the gate that says an index may be SERVED;
					-- `mMain` is what the next tick's aggregate subtracts, and it needs the
					-- previous contribution of every child it visits — including the
					-- always-visit ones, which are never recorded.
					mMain[idx] = mainOf
				end
				--[[ THE ALWAYS-VISIT LIST (owed rows A13 and A3). These are the five shapes
				this branch can never serve plus the declared shrink weight, recorded ONCE
				and never re-checked on an unvisited index — which is sound because a FLIP
				of any of them cannot reach one: `kind` is a class change and therefore a
				remount (structure-class); the three subtree booleans are pure functions
				of the built subtree, so a flip means a descendant changed and a
				descendant's measure dirt puts every ancestor up to this child in
				`measureContains`; `containerRelativeInside` is the same shape; and
				`shrinkWeight` is a prop on the child itself. All four routes make the
				child DIRTY, and a dirty child is visited. Ascending because this loop is.

				`shrinkWeight ~= nil` and not `> 0`: the skip above refuses on `== nil`,
				so a declared zero is unservable too, and the two lists must agree. ]]
				if alwaysVisit(child) then
					table.insert(always, idx)
					alwaysAt[idx] = true
					--[[ ...AND THE RECORD IS RETRACTED, which nothing did (fix round 1,
					I-2). `mIds[idx]` had ONE writer and no eraser, and on a HIT the array
					IS `cmemo.mIds` — so a child that LEAVES the record set on a
					hit-and-full-pass tick (it gained a `ScrollView` on a structural tick,
					say: `hit` is computed before the `struct` term, so `hit` is true and
					the pass runs in place) kept a non-nil `mIds` and a stale `mCuts` while
					`cutsSum` correctly dropped it. The next aggregate tick then read
					`mIdsA[idx] ~= nil` as "this index is RECORDED" and subtracted
					`mCuts[idx]` from a `cutsOwed` seeded by an `mCutsSum` that never held
					it — `ctx.fitCuts` short by that child's cuts on that tick and every
					one after. `ctx.fitCuts` reaches the world through `chosenCandidate`'s
					`uncut` test, where UNDER-counting makes a candidate that will paint an
					ellipsis look honest. One owner of the field, in both directions. ]]
					if mIds ~= nil then
						mIds[idx], mCuts[idx] = nil, nil
					end
				elseif
					memoable
					and child.kind ~= "text"
					and child.kind ~= "composition"
					and child.subtreeHasScroll ~= true
					and child.subtreeHasComposition ~= true
					and child.containerRelativeInside ~= true
				then
					--[[ RECORDED, and `mCross` is no longer recorded HERE (T13b). The fold at
					the bottom needs a complete cross array on the aggregate path, so the
					tail records the pass's OWN `crossOf` — every index, including the ones
					this block refuses — and `mIds` remains the only gate on what may be
					served. `marginMain` is not recorded at all: PASS 2 is the only reader
					and the aggregate rebuilds it for exactly the fill children that read
					it (review round 1, I-1, unchanged).

					THE `elseif` IS NOT A NARROWING. The branch above it is the SUPERSET of
					the five refusals this one asks for — it adds `shrinkWeight ~= nil`,
					which the record has never excluded — so a shrink-weighted child is now
					in `always` and NOT recorded, where before it was recorded and never
					servable. Nothing reads a record it cannot serve; `mMain` above is
					written for it either way, which is what the aggregate needs. ]]
					mCuts[idx], mIds[idx] = ctx.fitCuts - cutsBefore, child.id
					cutsSum += mCuts[idx]
				elseif mIds ~= nil then
					-- ...and the same retraction on the OTHER way out of the record set
					-- (fix round 1, I-2): a child the gate refuses for any reason must not
					-- keep an `mIds` entry that says it was recorded
					mIds[idx], mCuts[idx] = nil, nil
				end
			end
		end
	end
	-- ...AND THE SUM AS PASS 1 LEAVES IT, captured before PASS 1.5 below can rebase it
	-- by what the shrink absorbed. Amendment A-4's first withdrawal reason — "a
	-- post-shrink `aSum` compared against a pre-shrink `aMain`" — is answered by this
	-- local: the number the memo carries is never the shrunk one.
	local sumAfterPass1 = mainSum
	if auditOn and visit == nil then
		--[[ THE FORCED-ON ORACLE (ruling L-4, and the plan review's M5). With
			`containerAggregateAudit` on, `agg` is false and the full pass above ran —
			so there is no aggregate answer to replay, and the plan's "compare the full
			pass against the aggregate's" had nothing on the other side of the equals:
			`cmemo.mSum` is the value the PREVIOUS full pass recorded, which legitimately
			differs from this tick's whenever anything changed. T13's audit worked because
			its memo holds a per-index would-have-served answer; a container-level SUM has
			no such twin.

			SO THE ANSWER IS COMPUTED, NOT REPLAYED. The four channels below are derived
			arithmetically from the payload as it stood BEFORE this pass overwrote it —
			no extra `measure` call, no gate weakened — and asserted against this pass's
			own numbers before the record at the tail replaces them (T13's ordering
			ruling). Non-vacuity is `ctx.aggregateChecks`, which counts the containers
			actually compared and which every case pins a floor on; the plan's proposed
			witness (the two `lastChildIterations` differ) is satisfied by the audit
			flag alone and proves only that the flag works. ]]
		local mainAxis = if isH then "w" else "h"
		local budget = math.max(4, n // 4)
		local probes = 0
		local list = table.clone(aAlways)
		local reached = true
		for id in dirty do
			probes += 1
			if probes > budget then
				reached = false
				break
			end
			local idx = aIdx[id]
			if idx ~= nil and dirty[id] == true and aIsFill[idx] ~= true then
				table.insert(list, idx)
			end
		end
		local ordered: { number } = {}
		if reached then
			table.sort(list)
			local prev = -1
			for _, idx in list do
				if idx ~= prev then
					prev = idx
					local child = children[idx]
					if dim(child, mainAxis).type == "fill" or alwaysVisit(child) ~= (aAlwaysAt[idx] == true) then
						reached = false
						break
					end
					table.insert(ordered, idx)
				end
			end
		end
		local predWeight, predMarginOk = 0, true
		if reached then
			for _, idx in aFill do
				local child = children[idx]
				local childMainDim = dim(child, mainAxis)
				if childMainDim.type ~= "fill" then
					reached = false
					break
				end
				local mt, mr, mb, ml = sides(child.margin)
				if marginMain[idx] ~= (if isH then ml + mr else mt + mb) then
					predMarginOk = false
				end
				predWeight += childMainDim.weight or 1
			end
		end
		if reached then
			ctx.aggregateChecks += 1
			local measured = auditMeasured :: { number }
			-- CHANNEL 1 — THE VISIT SET, which is owed rows A2, A3 and A13 in one
			-- equality: the indices the aggregate would have measured, in the order it
			-- would have measured them, against the ones this walk actually did.
			local same = #ordered == #measured
			if same then
				for i, idx in ordered do
					if measured[i] ~= idx then
						same = false
						break
					end
				end
			end
			assert(same, `container aggregate visit-set mismatch at {node.id}`)
			-- CHANNEL 2 — `mainSum` (owed row A6), and CHANNEL 3 — the cuts an unvisited
			-- child owes (owed row A7), against the total this pass's skip arm served
			local predSum, predOwed = aSum, aCutsSum
			for _, idx in ordered do
				predSum += (mMain :: any)[idx] - aMain[idx]
				if aIds[idx] ~= nil then
					predOwed -= aCuts[idx]
				end
			end
			assert(predSum == sumAfterPass1, `container aggregate mainSum mismatch at {node.id}`)
			--[[ ...and what the walk ACTUALLY served, derived here rather than accumulated
				in the skip arm: a recorded index this pass did not measure is exactly a
				skipped one, so the two sets partition the recorded indices. O(n) inside an
				arm that is off in production. ]]
			local visited: { [number]: boolean } = {}
			for _, idx in ordered do
				visited[idx] = true
			end
			local servedCuts = 0
			for idx = 1, n do
				if aIds[idx] ~= nil and not visited[idx] then
					servedCuts += aCuts[idx]
				end
			end
			assert(predOwed == servedCuts, `container aggregate fitCuts mismatch at {node.id}`)
			-- CHANNEL 4 — `fillWeightSum` and `marginMain` over the fill indices, which
			-- are owed rows A8 and A4 and are the pair PASS 2 READS and never writes
			assert(predWeight == fillWeightSum and predMarginOk, `container aggregate fill-input mismatch at {node.id}`)
		end
	end
	-- PASS 1.5: THE MEASURE-SIDE SHRINK (§2.4, added 2026-08-12 — the mirror that
	-- closes the seam this branch used to merely name).
	--
	-- The claim this replaces was that shrinking is an arrange-time negotiation and
	-- measure only reports what a stack would LIKE, so a deficit cannot exist here.
	-- That is true of a `hug`/`content` parent, which offers back exactly what it
	-- measured. It is false the moment the offer is DEFINITE and smaller than the
	-- content — a `fill`-width toolbar in a fixed screen — which is the canonical
	-- use of the feature. There the squeeze is knowable at measure time, and not
	-- doing it reserved the CROSS extent of a wrap that will not happen: a label
	-- squeezed to its floor wrapped to eight lines inside a row that had reserved
	-- one, and painted the other seven outside. That is the "painted at a size
	-- nobody measured" family,
	-- and shipping a new layout feature with a known instance of it inside is
	-- shipping the next one.
	--
	-- It mirrors PASS 2 below, which exists for the identical reason on the `fill`
	-- child: measure at the extent the child will ACTUALLY get, or under-report its
	-- cross size. Order matches arrange's (shrink, then fill): the freed pixels are
	-- part of what fill children share.
	--
	-- ZERO ADDED WORK WHEN NOTHING OPTED IN, deliberately — this is the hot measure
	-- path and it has a live perf budget. `shrinkBasis` is nil unless a child
	-- declared a weight, so the whole block is skipped by one nil test; the two
	-- tables it needs are allocated on the deficit path only, exactly the discipline
	-- arrange's `shrinkLib.EMPTY` was written for.
	--
	-- ...AND IT DOES NOT RUN INSIDE A `ViewThatFits` FIT PROBE (ruling 2). "Does
	-- this candidate fit?" is asked of the size the candidate would LIKE — its ideal
	-- size, the same sense the declarative-layout literature uses — and a candidate
	-- that only fits after being squeezed does not fit, exactly as a Text that only
	-- fits after truncating does not fit there.
	-- See `chosenCandidate` for the ruling and the measurement; the probe is off
	-- again before the chosen candidate is measured for real, so the winner still
	-- shrinks.
	if shrinkBasis ~= nil and mainLimit ~= math.huge and not ctx.fitProbe then
		local deficit = mainSum + gaps - mainLimit
		if deficit > 0 then
			local shrunk: { [number]: number } = {}
			local absorbed =
				shrinkLib.stack(SHRINK_DEPS, ctx, children, isH, shrinkBasis :: { [number]: number }, deficit, shrunk)
			if absorbed > 0 then
				-- the report shrinks with the children: a stack that can absorb its own
				-- deficit needs the room it is left with, not the room it started from,
				-- and reporting the larger number would make measure a fixed point of
				-- nothing (the parent hands the report back and the same squeeze happens
				-- again at arrange).
				mainSum -= absorbed
				-- RE-MEASURE AT THE REDUCED OFFER, in document order — the same loop, the
				-- same reason and the same ordering rule as arrange's: last-write-wins
				-- verdict channels (`compact`, `textFacts`) must publish deterministically.
				for idx = 1, n do
					local size = shrunk[idx]
					if size ~= nil then
						(shrinkBasis :: { [number]: number })[idx] = size
						local child = children[idx]
						local mt, mr, mb, ml = sides(child.margin)
						local cw, ch =
							measure(ctx, child, if isH then size else innerMaxW, if isH then innerMaxH else size)
						crossOf[idx] = if isH then ch + mt + mb else cw + ml + mr
					end
				end
			end
		end
	end
	-- PASS 2: a FILL child never receives the whole main extent — it receives its
	-- weighted share of what is left, exactly as arrange distributes it.
	--
	-- THIS PASS MIRRORS ARRANGE'S `fill` BLOCK. Arrange's SHRINK pass has its own
	-- mirror at PASS 1.5 above (it used to have none, and the gap between them was
	-- the seam recorded there). Both passes are the same rule applied to the two
	-- ways a child ends up smaller than its natural size — a fill share, or a
	-- squeeze — and both run because the CROSS extent has to be measured at the main
	-- extent the child will actually get.
	--
	-- Measuring
	-- it against the FULL extent under-reports its cross size, because less width
	-- means more wrapped lines and more height. That under-report is what a
	-- ScrollView turns into a canvas that cannot reach its own content: found live
	-- 2026-07-24 on compact-phone-landscape, where the two fill columns measured at
	-- the full 680px reported a 292px canvas for content that actually reached
	-- 443px — the bottom 151px, including the whole tile row, was unreachable by
	-- scrolling. Same root cause as the 27px cross-axis clamp the overflow
	-- diagnostic reports on the wider rows.
	local remaining = if mainLimit == math.huge then math.huge else math.max(0, mainLimit - mainSum - gaps)
	--[[ ...AND IT IS O(#fill) NOW, NOT O(n) (T13b). The old head walked every index and
		skipped the ones a non-nil `crossOf[idx]` answered; the set it found is exactly
		the list PASS 1 records, in exactly the same ascending order. It is not merely
		cheaper — the sentinel CANNOT survive the aggregate's path, where `crossOf` is
		the container's own persisted array and no index is ever nil. The BODY below is
		untouched, so a fill child is still measured on every single tick (T13's owed
		row 5), which is why `lastChildVisits` cannot move. ]]
	local fillList = if visit ~= nil then cmemo.mFill else fills
	ctx.childIterations += #fillList
	for _, idx in fillList do
		local child = children[idx]
		local mt, mr, mb, ml = sides(child.margin)
		local childMainDim = dim(child, if isH then "w" else "h")
		local share = if remaining == math.huge or fillWeightSum <= 0
			then math.huge
			else remaining * (childMainDim.weight or 1) / fillWeightSum
		-- floor is the conservative direction: a slightly narrower measurement
		-- over-reserves height rather than under-reserving it
		local childMain = if share == math.huge then math.huge else math.max(0, math.floor(share) - marginMain[idx])
		local cw, ch = measure(ctx, child, if isH then childMain else innerMaxW, if isH then innerMaxH else childMain)
		crossOf[idx] = if isH then ch + mt + mb else cw + ml + mr
	end
	--[[ THE MEMO IS FILLED HERE, AFTER EVERY PASS THAT COULD HAVE CHANGED A NUMBER,
		and only when this container is still memoable. A hit refilled nothing: the
		arrays it served from are the same tables, and every index it did NOT serve was
		overwritten in place by the loop above.

		AND AN UN-MEMOABLE CONTAINER DROPS ITS KEY rather than keeping a stale one. The
		case is a `shrinkWeight` (or a `text` child) ARRIVING on a container that has
		already memoised at this offer: the key still matches, so this tick was a HIT,
		and without this line the next tick would hit again on numbers PASS 1.5 has
		since rebased. Dropping the stamp costs that container one full pass and buys
		back a memo that cannot be wrong. ]]
	if memoable then
		cmemo.mStamp, cmemo.mScope, cmemo.mOffW, cmemo.mOffH = ctx.measureStamp, ctx.scopeKey, innerMaxW, innerMaxH
		cmemo.mKind = node.kind
		--[[ ...AND THE TWO AGGREGATE TOTALS, WRITTEN BACK ON EVERY TICK (T13b, plan
			review M1(b)). The first draft read them and never wrote them, so the second
			consecutive aggregate tick was exact and the THIRD subtracted a value the
			second had already replaced: `mSum − mMain[idx]_from_tick_2 + new_3` where the
			truth is `mSum − mMain[idx]_original + new_3`, with the error accumulating.
			Same for the cuts. ]]
		cmemo.mSum, cmemo.mCutsSum = sumAfterPass1, cutsSum
		if visit == nil then
			--[[ A COMPLETED FULL PASS RE-RECORDS EVERYTHING, HIT OR MISS (plan review,
				M1(a)). The `and not hit` this condition used to carry was a real defect
				once the payload existed: `agg` is false while `hit` is true on four tick
				classes — a structural refresh, an audited tick, an `mN` mismatch and both
				fallbacks — and on all four the pass repairs the per-index arrays in place
				while leaving `mIdx`/`mAlways`/`mFill` describing the PREVIOUS shape. The
				worked case is a `ForEach` REORDER at an unchanged child count: the
				structural tick repairs the arrays, the next tick is non-structural, and
				the aggregate resolves every dirty id to the wrong index. A wrong pixel
				the splice fixture cannot see, because it stops at the structural tick.

				`mCross` takes the pass's OWN array, which widens the memo to indices the
				record block refuses (text, composition, fill). That is required — owed row
				A5's completeness, the fold needs every index — and safe, because what may
				be SERVED is gated by `mIds` and those indices are all in `mAlways`/`mFill`.
				`mCross` therefore no longer means "recorded"; it means "the cross extent
				this container last computed at this index".

				AND `struct` IS CLEARED HERE, which is what keeps it from being
				sticky-true (plan review, S5). `render/layout_node` sets it on every
				rebuild and a container NOT rebuilt on a later non-structural tick keeps
				the old value — so without this line one structural tick would disable the
				aggregate for that container indefinitely, with no counter showing it.
				Every index in this pass is either id-verified or freshly recorded, which
				is precisely the fact the flag stands in for. ]]
			cmemo.mMain, cmemo.mCross, cmemo.mCuts, cmemo.mIds = mMain, crossOf, mCuts, mIds
			cmemo.mN = n
			-- ...and the reverse map is DROPPED rather than rebuilt: this pass may have
			-- moved every index, and the next tick that wants one pays for one map
			-- instead of this pass paying for a map nothing may ever read
			cmemo.mIdx = nil
			cmemo.mAlways, cmemo.mAlwaysAt, cmemo.mFill, cmemo.mIsFill = always, alwaysAt, fills, isFill
			cmemo.struct = false
		end
	elseif cmemo ~= nil then
		cmemo.mStamp = nil
	end
	--[[ ...AND THE RESIDUAL, BOOKED RATHER THAN HIDDEN. Three passes over the child
		array survive this change — PASS 1, the fill pass's `continue` scan and the
		`crossMax` fold below — because only the WORK INSIDE the loops became O(dirty),
		never the loops themselves. On a 1,000-child container that is ~0.09 ms of
		iteration plus six table operations per skipped child, against the ~0.47 ms this
		removes. `lastChildVisits` counts the CALLS, which is what moved; the iteration
		count is a separate fact and this task does not claim it. Removing it is a
		different lever with a different shape (a per-index dirty list), and it is not
		this one. ]]
	local crossMax = 0
	for idx = 1, n do
		crossMax = math.max(crossMax, crossOf[idx] or 0)
	end
	if isH and baseline.has(node) then
		local sizes = {}
		for i, child in children do
			local mt, mr, mb, ml = sides(child.margin)
			local offer = innerMaxW
			if dim(child, "w").type == "fill" and remaining ~= math.huge and fillWeightSum > 0 then
				offer = math.max(0, math.floor(remaining * (dim(child, "w").weight or 1) / fillWeightSum) - ml - mr)
			elseif shrinkBasis ~= nil and shrinkBasis[i] ~= nil then
				offer = shrinkBasis[i]
			end
			local w, h = measure(ctx, child, offer, innerMaxH)
			if dim(child, "w").type == "fill" and offer ~= math.huge then
				w = offer
			end
			sizes[i] = { w = w, h = h, mt = mt, mb = mb }
		end
		local _, cross = baseline.line(deps.baseline, ctx, node, sizes, 1, n)
		crossMax = math.max(crossMax, cross)
	end
	local contentMain = mainSum + gaps + (if isH then pl + pr else pt + pb)
	local contentCross = crossMax + (if isH then pt + pb else pl + pr)
	if isH then
		return contentMain, contentCross
	end
	return contentCross, contentMain
end

return stack_measure
