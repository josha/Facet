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

local stack_measure = {}

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

		SO THE PARENT KEEPS THE ANSWERS. Five per-child arrays, indexed by child index,
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
	local memoable = cmemo ~= nil and reuse ~= nil and ctx.measureStamp ~= nil and not ctx.analyze
	local mMain, mCross, mMargin, mCuts, mIds
	if memoable then
		if hit then
			mMain, mCross, mMargin, mCuts, mIds = cmemo.mMain, cmemo.mCross, cmemo.mMargin, cmemo.mCuts, cmemo.mIds
		else
			mMain, mCross, mMargin, mCuts, mIds = {}, {}, {}, {}, {}
		end
	end
	-- PASS 1: children with a definite main extent measure against the whole
	-- inner box, and consume it.
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
				subtracts to get a node's `cuts`. ]]
			ctx.offers[child.wKey or (child.id .. "|w")] = innerMaxW
			ctx.offers[child.hKey or (child.id .. "|h")] = innerMaxH
			ctx.fitCuts += mCuts[idx]
			marginMain[idx] = mMargin[idx]
			crossOf[idx] = mCross[idx]
			mainSum += mMain[idx]
			continue
		end
		local mt, mr, mb, ml = sides(child.margin)
		marginMain[idx] = if isH then ml + mr else mt + mb
		if childMainDim.type == "fill" then
			fillWeightSum += childMainDim.weight or 1
		else
			ctx.childVisits += 1
			local cutsBefore = ctx.fitCuts
			local cw, ch = measure(ctx, child, innerMaxW, innerMaxH)
			local mainOf = if isH then cw + ml + mr else ch + mt + mb
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
				compares. Off in production; there is no third behaviour. ]]
			if skippable then
				assert(
					mMain[idx] == mainOf and mCross[idx] == crossOfIdx and mMargin[idx] == marginMain[idx],
					`container memo mismatch at {node.id}[{idx}]`
				)
			end
			--[[ RECORDED, OR NOT RECORDED — never "and the container gives up". A
				`text`/`composition` child is refused PER CHILD: its index is left
				unrecorded, so the skip arm's `mIds[idx] == child.id` term refuses it on
				every later tick and `record` publishes its verdicts exactly as it does
				today. The three subtree booleans are the serve's own, asked of the child
				for the channels no cached number can carry back. ]]
			if
				memoable
				and child.kind ~= "text"
				and child.kind ~= "composition"
				and child.subtreeHasScroll ~= true
				and child.subtreeHasComposition ~= true
				and child.containerRelativeInside ~= true
			then
				mMain[idx], mCross[idx] = mainOf, crossOfIdx
				mMargin[idx], mCuts[idx] = marginMain[idx], ctx.fitCuts - cutsBefore
				mIds[idx] = child.id
			end
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
	for idx, child in children do
		if crossOf[idx] ~= nil then
			continue
		end
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
	if memoable and not hit then
		cmemo.mStamp, cmemo.mScope, cmemo.mOffW, cmemo.mOffH = ctx.measureStamp, ctx.scopeKey, innerMaxW, innerMaxH
		cmemo.mMain, cmemo.mCross, cmemo.mMargin, cmemo.mCuts, cmemo.mIds = mMain, mCross, mMargin, mCuts, mIds
	elseif not memoable and cmemo ~= nil then
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
	local contentMain = mainSum + gaps + (if isH then pl + pr else pt + pb)
	local contentCross = crossMax + (if isH then pt + pb else pl + pr)
	if isH then
		return contentMain, contentCross
	end
	return contentCross, contentMain
end

return stack_measure
