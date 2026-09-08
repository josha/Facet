--!strict
--[[ THE VSTACK/HSTACK ARRANGE BRANCH, lifted out of `layout/solver.luau` on
	2026-09-02 because the wicked-fast round's anchor-arrange task needs Source-write
	headroom the solver did not have — 2,603 characters — and because this is the
	block `tools/lune/verify/data/source-cap-ledger.md`'s solver row has named as its
	next extraction since the T4 split: *"the next round that opens this file for
	anything larger than a comment takes THE STACK BRANCH (`local isH = node.kind ==
	"hstack"` through the `distribute`/`shrunk` tail)"*. That document's head demands
	the room be taken FIRST, in its own behaviour-neutral commit, before a character
	of the change that needs it.

	IT IS THE LARGEST BLOCK THIS FILE HAS EVER GIVEN UP — 15,821 characters, the
	whole of the main-axis pass (hug, shrink, fill, distribute) and the per-child
	placement loop that spends it.

	IT IS ONE-WAY, WHICH IS THE ONLY TEST THIS REPOSITORY JUDGES A SPLIT BY: the
	block reads no mutable upvalue of its host. What it needed from the solver is
	exactly five bind-time functions (`measure`, `dim`, `mainDimOf`, `sides` and the
	`shrink` record) — handed over as a `Deps` record built once at module scope,
	exactly as `GRID_DEPS` / `FLOW_DEPS` / `COMPOSITION_DEPS` / `CANDIDATE_DEPS`
	already are — plus TWO CALL-SITE ARGUMENTS, `place` and `noteContainment`, for
	the reason `grid.luau`'s header states about its own pair: `place` is declared
	BELOW the line the Deps record is built on, so a by-value capture there would
	take the nil global, and forward-declaring it to avoid that would add a mutable
	module local, which is the opposite of what a split is for. (`noteContainment`
	moved to `layout/arrange_reports` on 2026-09-04 and no longer has that
	constraint; it stays a call-site argument because the two are one pair.)

	`place` IS THE SOLVER'S RECURSIVE `arrange`, AND THAT IS NOT A CYCLE. The name is
	passed down the call, never required back: this module names no solver symbol and
	imports no solver type, so the require graph stays acyclic in the same shape
	`./grid` and `./flow` have proven twice.

	WHAT IT REQUIRES DIRECTLY, and why that is not the same thing as reaching back:
	`../num` for `roundPx` (grid's own precedent — a per-call binding on the arrange
	hot loop is a bench regression this repository has already paid for), `./shrink`
	for the pass this branch is the only caller of, and `./placement` for
	`alignOffset` / `distributionOf`. All three are leaves the solver also requires;
	none of them requires anything in this direction. The `shrink` DEPS record is
	NOT rebuilt here — it travels in the `Deps` above, because two copies of a
	forwarder is how the two ends up reading a different `measure` after an edit
	(`solver.luau`'s own note beside `FLOW_DEPS`).

	NO BEHAVIOUR CHANGES. `tests/stack_seam.spec.luau` mechanises the emptiness
	above; the behaviour half is the whole suite, which drives this branch on nearly
	every fixture in the repository. ]]
local num = require("../num")
local shrinkLib = require("./shrink")
local baseline = require("./baseline")
local spacerMinimum = require("./measure_facts").spacerMinimum
local placementLib = require("./placement")
-- bound at module scope for the reason `grid.luau` records: a per-call lookup on
-- the arrange hot loop is a bench regression this repository has already paid for
local roundPx = num.roundPx
local alignOffset = placementLib.alignOffset
local distributionOf = placementLib.distributionOf

local permutation = require("./row_permutation")

local stack = {}

-- What the branch needs from the solver, passed at every call. Typed `any` for the
-- node/ctx arguments on purpose: the solver requires THIS module, so importing
-- `solver.Node`/`Ctx` back would be a require cycle, and re-declaring either
-- schema here is the copy-goes-stale failure this seam exists to avoid — the same
-- ruling `shrink.Deps` and `grid.Deps` carry.
export type Deps = {
	measure: (ctx: any, node: any, maxW: number, maxH: number) -> (number, number),
	dim: (node: any, axis: string) -> any,
	mainDimOf: (node: any, isH: boolean) -> any,
	sides: (margin: any) -> (number, number, number, number),
	-- the record `./shrink` takes, built by the solver and NOT rebuilt here
	shrink: shrinkLib.Deps,
	baseline: any,
}

-- the solver's recursive `arrange`, and its parent-side containment finding. See
-- the header for why these two are arguments and not `Deps` fields.
export type Place = (ctx: any, node: any, rect: any, out: { [string]: any }) -> ()
export type NoteContainment = (
	ctx: any,
	node: any,
	child: any,
	rect: any,
	innerX: number,
	innerY: number,
	innerW: number,
	innerH: number,
	axisIsX: boolean
	-- ...and it REPORTS WHETHER IT FILED (T14). The replay below must re-file a
	-- containment finding about a CLEAN child — the finding carries `filedBy =
	-- parentId` and the solver drops any previous copy whose filer was walked, which
	-- a replaying container always is — and this is how the placement loop knows
	-- whether that re-file is owed at all.
) -> boolean

-- a solved box, declared here rather than imported for the reason the `Deps` note
-- above gives: `./anchor_placement`, `./composition` and `./text_audit` each
-- declare the same four numbers for the same reason.
export type Rect = { x: number, y: number, w: number, h: number }

-- vstack / hstack. Main axis, in order: fixed/content children keep their
-- desired size unless they declared a `shrinkWeight` and the axis is SHORT (the
-- shrink pass, §2.4); `fill` children then share any surplus by weight
-- (largest-remainder rounding); and `distribute` spreads what fill did not take
-- (§2.6). Cross axis honours `child.lineAlign`, else `child.align`, else this
-- container's `align` (`stretch` fills the line). Text-baseline groups reserve
-- their common ascent/descent and use the same nested geometry probe as measure.
--[[ ── THE CANDIDATE INDICES, WITHOUT THE SIBLING SCAN (Plan D, D2c) ─────────────

	The replay below walks EVERY sibling twice for a one-child payload —
	`ctx.placeSkipped` is literally the census of those iterations, 1,124 of them on
	`battle_hud L updateItem-hp`. The first walk is there for one reason its own header
	states: `render/layout_node` splices a `UI.ForEach` REGION's children into this flat
	list, so an insert into a spliced sibling shifts every later index while the mount
	children table the carrier gate compares is untouched — and a container that reaches
	the arm with ZERO dirty children would otherwise return having placed NOTHING.

	`node.kidToken` is what answers that WITHOUT the scan. `render/layout_node` hands a
	container a fresh token whenever it rebuilt the children array and the SAME token
	whenever it kept or patched one, and both of those preserve every id at every index
	(the patch validates it in three layers). So a payload recorded under a token that
	is still the node's own describes exactly the sequence standing here, and the ids
	need no re-reading. The token is compared against a recorded NON-NIL value, so a
	store-less build — where the token is nil on both sides — takes the scan.

	The inverse map is built once per token and dropped with it. The budget is the same
	one `render/layout_node`'s patch uses and for the same reason: the DIRTY SET is what
	is walked here, so a dirt set wider than a quarter of the children costs a scan the
	full pass does not pay, on a tick that is going to re-place most of them anyway. The
	refusal is a pure function of the MATCH COUNT, never of the hash order the set
	happens to enumerate in.

	── AND THE WALK ITSELF IS BOUNDED (Plan D, D3b) ─────────────────────────────────
	That budget bounds what this RETURNS and not what it READS, and `dirtyContains` is
	the whole solve's dirt rather than this container's share of it. On a WIDE push —
	1,000 settled text leaves delivered at once, ~2,000 dirty ids — each of the 1,000
	two-child rows walked all 2,000 to find its own one, and the D3b cutoff sweep priced
	that at +29.5 ms on the 1,000-leaf point alone, the largest single term in a
	regression that took the push route from 24.2 ms to 62.6. So a bare probe COUNT runs
	first, `stack_measure`'s shape and for its reason (a tick that bails must not have
	paid for anything — here the inverse map is not built either), with the same
	`DIRT_PROBE_FLOOR` floor `render/layout_node` states the depth argument for. Past it
	`order` is nil and the loop below takes the SCAN, which is the arm HEAD has always
	run and the exact one D2c replaced.

	AND, AS THERE, THE COUNT IS PAID ONCE PER SOLVE. `reuse.dirtyContains` is one fixed
	table for the length of a solve, so a walk that stopped at `budget + 1` proved the
	set is wider than that and a walk that finished measured it exactly; `ctx.dirtySeen`
	carries the larger of the two and the arrange descends outermost-first, so the
	widest budget goes first and every container under it refuses on a comparison. ]]
local DIRT_PROBE_FLOOR = 64

local function candidateIndices(ctx: any, cmemo: any, dirty: any, n: number): { number }?
	local probeBudget = math.max(DIRT_PROBE_FLOOR, n)
	if ctx.dirtySeen > probeBudget then
		return nil
	end
	local probes = 0
	for _ in dirty do
		probes += 1
		if probes > probeBudget then
			ctx.replayProbes += probes
			ctx.dirtySeen = probes
			return nil
		end
	end
	ctx.replayProbes += probes
	if probes > ctx.dirtySeen then
		ctx.dirtySeen = probes
	end
	local map = cmemo.pIdx
	if map == nil or cmemo.pIdxToken ~= cmemo.pToken then
		map = {}
		local pIds = cmemo.pIds
		for i = 1, n do
			map[pIds[i]] = i
		end
		cmemo.pIdx = map
		cmemo.pIdxToken = cmemo.pToken
	end
	local out: { number } = {}
	local budget = math.max(4, n // 4)
	--[[ ...AND THE SAME BELT THE SCAN ARM WEARS (RED-TEAM C-11). The scan refuses on
		`pIds[idx] ~= child.id or pRect[idx] == nil`; the indexed arm skips both, and
		then reads `local prev = pRect[idx]` followed by `prev.x`. Every path traced
		makes a nil unreachable — `pIds`/`pMain`/`pCross` are filled for all indices
		before the placement loop, `pRect[idx]` in it with no `continue`, and `pN` is
		written LAST so a throw leaves a payload no gate matches — but "unreachable"
		is the argument, not the code, and the failure if it is ever wrong is
		"attempt to index nil" INSIDE a solve rather than a refusal. Refusing the short
		list is free and restores the belt: the caller falls back to the scan, which
		refuses on the same term and takes the full pass. ]]
	local pRect = cmemo.pRect
	for id in dirty do
		local idx = map[id]
		if idx ~= nil then
			if #out >= budget or pRect[idx] == nil then
				return nil
			end
			out[#out + 1] = idx
		end
	end
	--[[ ASCENDING, WHICH IS THE ORDER THE SCAN VISITS THEM IN. It matters on the
		REFUSING path, not the succeeding one: the loop calls `deps.measure` for each
		dirty child before a later one can refuse, so a different order would measure a
		different subset before the same refusal and move `lastMeasured` for no reason. ]]
	table.sort(out)
	return out
end

function stack.arrange(
	deps: Deps,
	ctx: any,
	node: any,
	innerX: number,
	innerY: number,
	innerW: number,
	innerH: number,
	gap: number,
	place: Place,
	noteContainment: NoteContainment,
	out: { [string]: any }
)
	local isH = node.kind == "hstack"
	local children = node.children or {}
	local hasBaseline = isH and baseline.has(node)
	if not isH and baseline.has(node) and ctx.hiddenDepth == 0 then
		table.insert(ctx.diagnostics, {
			node = node.id,
			issue = "text baseline alignment requires a horizontal stack; vertical stacks use start alignment",
		})
	end
	--[[ ── THE STACK RE-PLACES ONLY THE CHILDREN THAT MOVED (Plan C, T14) ──────────
		A one-leaf write on a 1,000-row list entered `arrangeBody` 1,109 times to run
		FIVE bodies: the passes below measured every child, the placement loop built a
		`childRect` for every child, and 1,104 of them reached `arrangeBody` only to
		take its early skip. THE SKIP WAS ALREADY FREE; GETTING THERE WAS THE BILL.

		THE CONDITION IS THAT NO MAIN EXTENT MOVED, AND IT IS WHY EVERY OTHER TERM
		COMES FREE. If the inner box, the gap, the axis and the container's
		`align`/`distribute` are the same, and every dirty child re-measures to the
		MAIN contribution it already had with the same resolved align and the same
		margins, then `fixedMain`, `gaps`, `availMain`, `remaining`, `fillPx`,
		`shrunk`, `clipMain`, `lead`/`step` and every cursor position are the values
		they were. So no child's main-axis placement changes, including the dirty
		ones, and the only work left is to re-enter the dirty subtrees.

		...AND A CROSS EXTENT THAT MOVED COSTS ONE CHILD, NOT THE STACK. A stack's
		cross axis has no cursor: `desired[idx]`'s cross extent is read at exactly one
		place (`crossSize`, below) and no sibling reads it. So a dirty child whose
		main extent stood still and whose CROSS extent moved is re-placed HERE, with
		the same two lines the loop below spends on it, and every other child still
		keeps its rect. That is the case the arena's `updateItem-hp` class is made of —
		a value-driven bar inside a row makes the ROW's measured width follow it, and
		the enclosing thousand-row VStack sees a pure cross-extent change on one child.

		THE COMPARISON IS MEASURED-TO-MEASURED. `pMain`/`pCross` are recorded WHERE
		THE MEASUREMENT HAPPENS — immediately after the hug pass, from `desired` plus
		`margins`, before the shrink and fill passes overwrite `desired` — so they are
		margin-INCLUSIVE and they are measurements, not `mainSize`/`crossSize`, which
		are margin-exclusive, clamped, and for a `fill` or `shrunk` child are the
		placement's answer rather than the measure's. That is the same offer
		`(innerW, innerH)` this arm re-measures at, so the two numbers answer the same
		question. T13's `mMain` is recorded at the MEASURE offer `(innerMaxW,
		innerMaxH)` and is never read here (ruling A-9).

		THE FOUR PLACEMENT INPUTS NO MEASUREMENT CAN SEE are asked of DIRTY children
		only, because a clean child's props cannot have moved — a prop write is what
		makes a node dirty. They are the resolved `child.lineAlign or child.align or
		node.align` (`pAl`), the four margin sides (`pMarg` — a margin-inclusive pair
		alone would let `ml+1, w-1` through, which moves the child and no total),
		`child.shrinkWeight`/`child.layoutPriority` on a stack that was SHORT last
		pass (`pShort`), and the four dimension SHAPES that make a recorded pair mean
		something other than "the extent this child was placed at" (`pFlag`).

		`pFlag` IS THE ONE TERM THAT IS NOT ABOUT CHANGE. A `fill` or `hug` main
		child, a `fill` cross child, an `aspect` child and a member of `shrunk` were
		each measured a SECOND time at an offer this arm does not reproduce (the hug
		pass's `left`, the shrink pass's reduced size, the fill pass's share), or take
		their extent from the placement rather than from a measurement. A dirty child
		that is — or was — any of those refuses outright, in both directions, which is
		what catches a dim flipping type at an unchanged content size.

		THE PREFIX REBASE IS BOOKED, NOT BUILT. Shifting the suffix by a main-axis
		delta is a second lever with its own gate terms (`gap`, align, `shrunk`,
		`clipMain`, aspect, and every `fill` sibling that must be RESIZED rather than
		moved) and it is the one thing this arm refuses that a real workload asks for.
		See `tests/stack_replay.spec.luau`'s header for the measured booking. ]]
	local cmemo = node.cmemo
	local reuse = ctx.reuse
	local dirty = if reuse ~= nil then reuse.dirtyContains else nil
	--[[ THE GATE, CHEAPEST TERM FIRST, AND NOT ONE OF THEM WRITES ANYTHING. A refusal
		here is free of side effects, which is the property the arm's first prototype
		did not have.

		`pKind` IS THE AXIS AND IT IS A WRONG PIXEL WITHOUT IT (the defect T13b found in
		T13's own key). `UI.AdaptiveStack` is ONE class whose reactive `axis` prop maps
		to two solver KINDS with the documented guarantee that the flip is a re-solve
		and never a remount, so every child keeps its identity and stays clean while
		`pMain` stops meaning the axis it was recorded on.

		`pStamp`/`pScope` ARE THE SOLVE-WIDE INPUTS NO PER-CHILD FACT CAN SEE (review
		round 3, MUST-FIX 1) — the viewport, the safe insets, the theme snapshot, the
		two text scales and the text-metrics CALIBRATION generation. The per-WORD half
		of that generation left the stamp in T18-A and arrives as DIRT on the label
		instead, which this arm re-measures and compares like any other dirty child.

		`ctx.measureQuiet` IS THE FOURTH GATE, the anchor arm's and T13's, here for the
		identical reason: a measure-time finding is filed about a node in the subtree
		this arm does not re-measure, and no rect can carry it back. `ctx.analyze` is
		NOT a term because it cannot reach here — an analysing solve is run without
		`reuse` precisely so its result outlives the next solve. ]]
	local replayable = cmemo ~= nil
		and dirty ~= nil
		and ctx.noSkipDepth == 0
		and ctx.measureQuiet
		and ctx.measureStamp ~= nil
		and not hasBaseline
		and cmemo.pRect ~= nil
		-- the child LIST, not just the box: a `ForEach` splice changes the length while
		-- the mount children table the carrier gate compares is untouched
		and cmemo.pN == #children
		and cmemo.pKind == node.kind
		and cmemo.pStamp == ctx.measureStamp
		and cmemo.pScope == ctx.scopeKey
		and cmemo.pHidden == ctx.hiddenDepth
		and cmemo.pDistribute == node.distribute
		and cmemo.pAlign == node.align
		and cmemo.pGap == gap
		and cmemo.pInnerX == innerX
		and cmemo.pInnerY == innerY
		and cmemo.pInnerW == innerW
		and cmemo.pInnerH == innerH
	-- the children this arm must re-place, by index, with the rect to place them at.
	-- `nil` on a stack where nothing is dirty, which is a real and common shape.
	local hot: { [number]: Rect }? = nil
	--[[ ...and the MARGIN-INCLUSIVE CROSS EXTENT of a child the arm re-placed on the
		cross axis, carried to the commit loop rather than written where it is computed
		(fix round 1, I-1). A per-child term that refuses AFTER an earlier child has been
		recorded would leave `cmemo` half-describing a pass that never ran, and "a refusal
		writes nothing" is the property the first prototype of this arm did not have. ]]
	local hotCross: { [number]: number }? = nil
	local hotCount = 0
	--[[ THE INDICES THIS ARM WILL VISIT, or `nil` for "visit every sibling" (Plan D,
		D2c). See `candidateIndices` above for what licenses the short list and what
		refuses it. `pNoted` is a term because the commit walk below has to visit every
		CLEAN child when this container filed a containment finding last pass — the
		indexed arm serves the shape where it filed none, which is the shape a settled
		surface is in. ]]
	local order: { number }? = nil
	if replayable and cmemo.pToken ~= nil and cmemo.pToken == node.kidToken and cmemo.pNoted ~= true then
		order = candidateIndices(ctx, cmemo, dirty, #children)
	end
	if replayable then
		local pIds, pRect = cmemo.pIds, cmemo.pRect
		local pMain, pCross, pAl, pFlag, pMarg = cmemo.pMain, cmemo.pCross, cmemo.pAl, cmemo.pFlag, cmemo.pMarg
		local short = cmemo.pShort
		local crossRoom = if isH then innerH else innerW
		--[[ ONE BODY, TWO ENUMERATIONS. `order == nil` is the scan HEAD has always run —
			every sibling checked for identity, only the dirty ones measured; otherwise
			the short list, whose members are exactly the dirty children in the same
			ascending order the scan would have reached them in. ]]
		local visits = if order ~= nil then #order else #children
		local at = 0
		while at < visits do
			at += 1
			local idx = if order ~= nil then (order :: { number })[at] else at
			local child = children[idx]
			if order == nil then
				--[[ EVERY CHILD IS CHECKED FOR IDENTITY; only the DIRTY ones are re-measured.
				The id scan is not optional: `render/layout_node` splices a `UI.ForEach`
				REGION's children into this flat list while `mount` replaces the REGION's
				children and never the enclosing panel's, so the carrier's `prior.kids ==
				node.children` term HOLDS across an insert into a spliced sibling while
				every later index shifts. Measured on the arena, `battle_hud L
				removeItem-damage` reaches this arm with `dirty ~= nil`, ZERO dirty
				children and an unmoved box over 1,123 children — so without the scan the
				arm returns having placed NOTHING while the splice moved every surviving
				row. One interned-string compare and one hash probe per clean child, in a
				loop the full pass below already runs. ]]
				if pIds[idx] ~= child.id or pRect[idx] == nil then
					replayable = false
					break
				end
				if dirty[child.id] ~= true then
					continue
				end
			end
			local mainDim = deps.mainDimOf(child, isH)
			local wD, hD = deps.dim(child, "w"), deps.dim(child, "h")
			local mainType = mainDim.type
			local crossType = (if isH then hD else wD).type
			if
				pFlag[idx] ~= 0
				or mainType == "fill"
				or mainType == "hug"
				or crossType == "fill"
				or wD.type == "aspect"
				or hD.type == "aspect"
				or (child.lineAlign or child.align or node.align) ~= pAl[idx]
				or (short and (child.shrinkWeight ~= nil or child.layoutPriority ~= nil))
			then
				replayable = false
				break
			end
			local mt, mr, mb, ml = deps.sides(child.margin)
			local pm = pMarg[idx]
			local sameMargin = if pm == false
				then mt == 0 and mr == 0 and mb == 0 and ml == 0
				else pm.t == mt and pm.r == mr and pm.b == mb and pm.l == ml
			if not sameMargin then
				replayable = false
				break
			end
			local w, h = deps.measure(ctx, child, innerW, innerH)
			if (if isH then w + ml + mr else h + mt + mb) ~= pMain[idx] then
				replayable = false
				break
			end
			local prev = pRect[idx]
			local crossOf = if isH then h + mt + mb else w + ml + mr
			local r: Rect
			if crossOf == pCross[idx] then
				-- NOTHING MOVED: a fresh table because `arrangeBody` freezes what it is
				-- handed and the frozen one is already the entry in `out`
				r = { x = prev.x, y = prev.y, w = prev.w, h = prev.h }
			else
				--[[ THE CROSS-ONLY RE-PLACE, and it is the SAME two lines the placement
					loop below spends. `crossAvail` is this child's own margins against the
					box; `crossSize` is the clamp, with the `fill`/`aspect` arms refused
					above so `stretch` is the only spelling left that ignores the measured
					extent; the main-axis half comes from the rect this child already has,
					because no cursor moved. ]]
				local crossAvail = math.max(0, crossRoom - (if isH then mt + mb else ml + mr))
				local childAlign = pAl[idx]
				local crossSize = if childAlign == "stretch"
					then crossAvail
					else math.min(if isH then h else w, crossAvail)
				r = if isH
					then {
						x = prev.x,
						y = innerY + mt + alignOffset(childAlign, crossAvail, crossSize),
						w = prev.w,
						h = crossSize,
					}
					else {
						x = innerX + ml + alignOffset(childAlign, crossAvail, crossSize),
						y = prev.y,
						w = crossSize,
						h = prev.h,
					}
				if hotCross == nil then
					hotCross = {}
				end
				(hotCross :: { [number]: number })[idx] = crossOf
			end
			if hot == nil then
				hot = {}
			end
			(hot :: { [number]: Rect })[idx] = r
			hotCount += 1
		end
		ctx.placeScanned += at
	end
	if replayable and not ctx.replayAudit then
		--[[ NOTHING ON THE MAIN AXIS MOVED: every child keeps the main half of the rect
			it has, and only the dirty subtrees are re-entered. The clean ones are not
			`place`d at all, which is what removes the 1,104 `arrangeBody` entries — and
			they were already costing `ctx.arranged` nothing, because that bump sits
			BELOW `arrangeBody`'s own skip.

			IN DOCUMENT ORDER, INTERLEAVED EXACTLY AS THE LOOP BELOW IS, so the
			diagnostics list and the rect map are written in the order HEAD writes them.

			`noteContainment` FOR EVERY CHILD, not only the re-placed ones (review round
			3, MUST-FIX 2): its findings carry `filedBy = parentId` and the solver's
			diagnostic replay drops any previous finding whose filer was walked — a
			replaying container always is. `pNoted` is what makes the common case free:
			if this container filed no containment finding on the pass that recorded, a
			re-file is provably a no-op, because every rect and the box are unchanged. ]]
		-- Replay can change cut verdicts without a full measurement recording.
		if hotCount > 0 then
			cmemo.pCuts = nil
		end
		local noted, pRect, pCross = cmemo.pNoted, cmemo.pRect, cmemo.pCross
		local axisIsX = not isH
		--[[ ...AND WHAT THIS PASS FILED, which is the value the NEXT replay reads (fix
			round 1, I-1). `noted` above is the RECORDING pass's answer and decides whether
			a clean child is re-noted at all; this is THIS pass's, and it has to replace it
			or a finding the cross re-place just created is dropped on the very next tick —
			`pNoted` would still say this container filed nothing, no clean child would be
			re-noted, and `solve`'s diagnostic replay drops the previous copy because the
			container was walked. That is the "silently, and forever" class one lane over.

			A CLEAN CHILD CANNOT HAVE STARTED OVERHANGING while `noted` is false: its rect
			is the one the recording pass placed it at (the arm only ever re-places `hot`
			children, and it now records what it re-places), and the box is a gate term. ]]
		local filed = false
		--[[ ...AND THE SECOND SIBLING WALK GOES WITH THE FIRST (Plan D, D2c). When the
			indexed arm ran, `noted` is false by its own gate, so a clean child's branch
			below is a lookup that finds nothing and a test that does nothing — and every
			index in `order` carries a rect, because a dirty child that failed any term
			refused the whole arm. So the walk is the short list, in the same ascending
			document order, and `placeSkipped` counts the iterations that did not happen:
			zero, where the scan counted 1,124. ]]
		if order ~= nil then
			for _, idx in order :: { number } do
				local child = children[idx]
				local r = (hot :: { [number]: Rect })[idx]
				filed = noteContainment(ctx, node, child, r, innerX, innerY, innerW, innerH, axisIsX) or filed
				pRect[idx] = r
				local cross = if hotCross ~= nil then hotCross[idx] else nil
				if cross ~= nil then
					pCross[idx] = cross
				end
				place(ctx, child, r, out)
			end
			cmemo.pNoted = filed
			local issues = cmemo.pIssues
			if issues ~= nil then
				for _, finding in issues do
					table.insert(ctx.diagnostics, finding)
				end
			end
			--[[ `placeSkipped` KEEPS ITS MEANING, which is a statement about
				`arrangeBody` and not about this loop: the children this stack did not
				re-place are the same children whatever enumeration found them. What the
				indexed arm moves is `placeScanned`, added above. ]]
			ctx.placeSkipped += #children - hotCount
			ctx.placeScanned += #(order :: { number })
			return
		end
		for idx, child in children do
			local r = if hot ~= nil then hot[idx] else nil
			if r ~= nil then
				filed = noteContainment(ctx, node, child, r, innerX, innerY, innerW, innerH, axisIsX) or filed
				--[[ THE ARM RECORDS WHAT IT COMMITS (fix round 1, I-1). Without these two
					writes the payload keeps describing the last FULL pass while the rect map
					holds this one's, so the next replay re-notes a CLEAN child from the rect
					it had two ticks ago — the reviewer's witness reported a 100px overhang
					where the truth was 160px. The RECTS survived it, because `pRect` and
					`pCross` went stale together and the "nothing moved" copy is only taken
					when the fresh measurement matches the rect it was recorded with; the
					diagnostics did not. `r` is the SAME TABLE `place` freezes into `out`,
					so this array still holds references and never copies. ]]
				pRect[idx] = r
				local cross = if hotCross ~= nil then hotCross[idx] else nil
				if cross ~= nil then
					pCross[idx] = cross
				end
				place(ctx, child, r, out)
			elseif noted then
				filed = noteContainment(ctx, node, child, pRect[idx], innerX, innerY, innerW, innerH, axisIsX) or filed
			end
		end
		cmemo.pNoted = filed
		--[[ ...AND THE CONTAINER'S OWN FINDINGS ARE RE-FILED (review round 3, MUST-FIX
			3). Neither the overflow diagnostic nor the `distribute`-has-nothing conflict
			carries a `filedBy`, so the solver's replay keys them on `d.node` — the
			container, which is walked — and drops the previous copy, while this arm
			returns long before `availMain` exists. An overflowing stack that stopped
			reporting its overflow from its first replay onward, silently and forever, is
			the worst outcome this task could have had. `ctx.hiddenDepth` is a gate term,
			so the decision to file cannot have flipped under us. ]]
		local issues = cmemo.pIssues
		if issues ~= nil then
			for _, finding in issues do
				table.insert(ctx.diagnostics, finding)
			end
		end
		ctx.placeSkipped += #children - hotCount
		ctx.placeScanned += #children
		return
	end
	--[[ REFUSED, or the audit is on: fall through to the full pass. Nothing above wrote a
		rect, wrote to `cmemo` or touched T13's arrays — every write this arm makes is
		inside the commit loop, which runs only once the whole scan has passed.

		THAT IS FREE OF *RECT* SIDE EFFECTS, NOT OF ALL OF THEM (fix round 1, minor 7).
		The scan calls `deps.measure` for each DIRTY child before a later child can
		refuse, so a refusing replay measures those children once more than HEAD did. It
		is idempotent — the same node at the same offer, answered by the per-solve memo or
		by C2's node-resident serve — and it is why the `calls`/`served` pins in
		`container_memo`, `container_aggregate` and `measure_serve` were re-recorded with
		their reason. The order is cheapest-term-first precisely so the common refusals
		(a changed id, a changed gap, a changed box) cost no measure at all. ]]
	-- Arrange's offer differs from measure's (inventory: 598 vs 1280 pixels).
	-- Reuse only this pass's own saved answers and republish its cuts and offers.
	local permuted = nil
	if
		cmemo ~= nil
		and reuse ~= nil
		and ctx.measureQuiet
		and ctx.measureStamp ~= nil
		and ctx.noSkipDepth == 0
		and not ctx.replayAudit
		and not hasBaseline
		and cmemo.pStamp == ctx.measureStamp
		and cmemo.pScope == ctx.scopeKey
		and cmemo.pKind == node.kind
		and cmemo.pHidden == ctx.hiddenDepth
		and cmemo.pInnerW == innerW
		and cmemo.pInnerH == innerH
		and cmemo.pCuts ~= nil
	then
		permuted = permutation.order(children, cmemo.pIds, cmemo.pN, reuse.measureContains)
		if permuted ~= nil then
			for _, child in children do
				local mainType = deps.mainDimOf(child, isH).type
				if
					mainType == "hug"
					or mainType == "fill"
					or child.kind == "text"
					or child.kind == "composition"
					or child.shrinkWeight ~= nil
					or child.subtreeHasScroll
					or child.subtreeHasComposition
					or child.containerRelativeInside
				then
					permuted = nil
					break
				end
			end
		end
	end
	local previousCuts = if cmemo ~= nil then cmemo.pCuts else nil
	local measuredCuts = if cmemo ~= nil then {} else nil
	-- A throw during a full pass must not leave old cut data paired with new extents.
	if cmemo ~= nil then
		cmemo.pCuts = nil
	end
	local desired = {}
	local margins = {}
	local fillWeightSum = 0
	local fixedMain = 0
	local gaps = if #children > 1 then gap * (#children - 1) else 0
	-- A `hug` CHILD'S CEILING IS WHAT ITS SIBLINGS LEFT IT, not the whole stack
	-- (director round 11, reproduced 2026-07-27 against the showcase's own chrome
	-- column). Every child used to be measured against the stack's FULL inner
	-- extent, which is right for the dims that ignore the limit — `fixed`,
	-- `content`, `minMax` — and wrong for the one that clamps to it. The gallery's
	-- theme card is the case: a `hug` ScrollView sitting under a row of chips was
	-- handed the column's entire height as its cap, so it reported its full
	-- natural content height, the cursor placed it after the chips, and it ran off
	-- the bottom of the phone by exactly what the chips had already spent — while
	-- never discovering it should have been scrolling.
	--
	-- So `hug` children are measured in a SECOND pass, in document order, each
	-- against the room actually left. `fill` is deliberately not part of that sum
	-- yet: `hug` means "what I need", `fill` means "whatever is over", so hug
	-- resolves first and fill shares the remainder — which is the order the rest of
	-- this branch assumes. The full order is hug -> SHRINK (only if the axis came out
	-- short) -> fill -> distribute.
	local hugLater: { number } = {}
	for idx, child in children do
		local mt, mr, mb, ml = deps.sides(child.margin)
		margins[idx] = { t = mt, r = mr, b = mb, l = ml }
		local mainDim = deps.mainDimOf(child, isH)
		if mainDim.type == "hug" then
			table.insert(hugLater, idx)
			continue
		end
		local w, h
		local cutsBefore = ctx.fitCuts
		if permuted ~= nil then
			local old = permuted[idx]
			w = (if isH then cmemo.pMain[old] else cmemo.pCross[old]) - ml - mr
			h = (if isH then cmemo.pCross[old] else cmemo.pMain[old]) - mt - mb
			ctx.fitCuts += previousCuts[old] or 0
			ctx.offers[child.wKey or (child.id .. "|w")] = innerW
			ctx.offers[child.hKey or (child.id .. "|h")] = innerH
		else
			w, h = deps.measure(ctx, child, innerW, innerH)
		end
		if measuredCuts ~= nil then
			measuredCuts[idx] = ctx.fitCuts - cutsBefore
		end
		desired[idx] = { w = w, h = h }
		if mainDim.type == "fill" then
			fillWeightSum += mainDim.weight or 1
			fixedMain += spacerMinimum(child, isH)
		else
			fixedMain += (if isH then w + ml + mr else h + mt + mb)
		end
	end
	for _, idx in hugLater do
		local child = children[idx]
		local m = margins[idx]
		local ownMargin = if isH then m.l + m.r else m.t + m.b
		local left = math.max(0, (if isH then innerW else innerH) - fixedMain - gaps - ownMargin)
		local w, h = deps.measure(ctx, child, if isH then left else innerW, if isH then innerH else left)
		desired[idx] = { w = w, h = h }
		fixedMain += (if isH then w + m.l + m.r else h + m.t + m.b)
	end
	--[[ WHAT THE NEXT ARRANGE INTO THIS BOX WILL RE-ASK (T14). `desired` holds the pass-1
		measurement at `(innerW, innerH)` and the hug pass's at `left`; `margins` holds the
		four sides. The pair recorded here is therefore MARGIN-INCLUSIVE and is a
		MEASUREMENT — not `mainSize`/`crossSize`, which are margin-exclusive, clamped, and
		for a `fill` or `shrunk` child are the placement's answer rather than the measure's.
		It is taken BEFORE the shrink and fill passes overwrite `desired`.

		THE ARRAYS ARE ALLOCATED ONCE AND OVERWRITTEN IN PLACE. Seven fresh tables per
		container per solve is the allocation on the arrange hot path this branch has
		already paid for twice; a stale entry past `#children` is unreachable because
		`pN` bounds every read.

		`pMarg` IS `false` WHEN EVERY SIDE IS ZERO, which is nearly every child: the
		common case stores no table and retains nothing, and a margined child stores the
		table `margins` already built. ]]
	local pMain, pCross, pIds, pMarg, pRect, pAl, pFlag
	if cmemo ~= nil then
		pMain, pCross, pIds = cmemo.pMain, cmemo.pCross, cmemo.pIds
		pMarg, pRect, pAl, pFlag = cmemo.pMarg, cmemo.pRect, cmemo.pAl, cmemo.pFlag
		if pMain == nil then
			pMain, pCross, pIds, pMarg, pRect, pAl, pFlag = {}, {}, {}, {}, {}, {}, {}
			cmemo.pMain, cmemo.pCross, cmemo.pIds = pMain, pCross, pIds
			cmemo.pMarg, cmemo.pRect, cmemo.pAl, cmemo.pFlag = pMarg, pRect, pAl, pFlag
		end
		for idx, child in children do
			local m, d = margins[idx], desired[idx]
			if d ~= nil then
				pMain[idx] = if isH then d.w + m.l + m.r else d.h + m.t + m.b
				pCross[idx] = if isH then d.h + m.t + m.b else d.w + m.l + m.r
			end
			pIds[idx] = child.id
			pMarg[idx] = if m.t == 0 and m.r == 0 and m.b == 0 and m.l == 0 then false else m
		end
	end
	local availMain = (if isH then innerW else innerH) - fixedMain - gaps
	-- THE SHRINK PASS (§2.4; the algorithm and its two rulings are documented in
	-- `src/layout/shrink.luau`). It runs ONLY on the overflow path and only over
	-- children that declared a `shrinkWeight`, so a stack that opted into nothing
	-- reaches the diagnostic below with `availMain` untouched — which is what makes
	-- "additive and inert" a fact rather than an intention.
	--
	-- IT ALLOCATES NOTHING UNTIL IT HAS SOMETHING TO SAY. `shrunk` starts as the
	-- shared frozen empty table and is only replaced by a real one on the deficit
	-- path: a per-stack table here would be an allocation on the arrange hot loop,
	-- which is a bench regression this branch has already paid for once.
	--
	-- ...AND OVERFLOW IS NOT RARE, which is why the membership test is hoisted in
	-- front of both tables (Milestone-1 review, C5). The comment above was true of
	-- the pass and false of its setup: on ANY `availMain < 0` this block used to
	-- allocate `shrunk` AND `basisMain` and walk every child, only for the pass
	-- to find zero members and return. The overflow diagnostic below exists because
	-- shipped screens reach this branch at rest, and before §2.4 that path allocated
	-- nothing at all. The scan itself is on the overflow path only — a fitting stack
	-- pays nothing for it — and it stops at the first member.
	local shrunk: { [number]: number } = shrinkLib.EMPTY
	local shrinkOrder: string? = nil
	local hasShrink = false
	if availMain < 0 then
		for _, child in children do
			-- the same `> 0` filter `shrinkLib.stack` applies: `shrinkWeight = 0` is the
			-- default AND a legal authored value meaning "never"
			if child.shrinkWeight ~= nil and child.shrinkWeight > 0 then
				hasShrink = true
				break
			end
		end
	end
	if hasShrink then
		local absorbed
		shrunk = {}
		-- the basis map the pass takes is the MAIN extent of what was measured above,
		-- built here rather than carried through the loops: a per-child main-extent
		-- table maintained unconditionally would be an allocation on the arrange hot
		-- path, and this one only exists once a deficit does
		local basisMain: { [number]: number } = {}
		for idx = 1, #children do
			local d = desired[idx]
			if d ~= nil then
				basisMain[idx] = if isH then d.w else d.h
			end
		end
		absorbed, shrinkOrder = shrinkLib.stack(deps.shrink, ctx, children, isH, basisMain, -availMain, shrunk)
		if absorbed > 0 then
			fixedMain -= absorbed
			availMain += absorbed
			-- RE-MEASURE AT THE REDUCED OFFER, in document order. Same reason the
			-- `fill` block below re-measures: the cross extent was measured against a
			-- width this child no longer has, so a squeezed label would keep the box
			-- of the wrap it is not going to get. Document order, never `pairs`, so
			-- the last-write-wins verdict channels (`compact`, `textFacts`) publish
			-- deterministically.
			for idx = 1, #children do
				local size = shrunk[idx]
				if size ~= nil then
					local w, h =
						deps.measure(ctx, children[idx], if isH then size else innerW, if isH then innerH else size)
					desired[idx] = { w = w, h = h }
				end
			end
		end
	end
	-- OVERFLOW DIAGNOSTIC (preferred-text sweep, 2026-07-24). Content-sized
	-- children always keep their full desired extent and the flow cursor keeps
	-- advancing, so a stack whose content exceeds its own box silently paints
	-- past its parent and off the viewport — no clip, no compression, no scroll.
	-- Found live: on compact-phone-portrait the adaptive_controls Hud column ran
	-- 185px past its own box, drawing the action row INSIDE the media box and
	-- pushing the stat grid and tile row off an 800px screen — at rest, with the
	-- default text size. This does not change layout for a stack that declared no
	-- `shrinkWeight` (that would be a silent re-flow of shipped screens); it makes
	-- the condition detectable, which is the whole difference between a bug you can
	-- catch and one you cannot.
	--
	-- It fires on what is left AFTER the shrink pass, and when that pass tried and
	-- still could not fit the row it appends the priority order it worked through —
	-- because "everything is already at its floor" is a different repair from
	-- "nothing was allowed to shrink".
	--
	-- CLIP IS THE CASCADE'S FLOOR (director ruling 1, 2026-08-13). A stack that ran
	-- the degrade cascade (compact -> truncate, `shrinkFloorOf` above) and STILL
	-- cannot fit crops what is left at its own edge, so nothing ever paints outside
	-- its parent — the failure class this framework has now fixed five times. The
	-- crop is on the RECT, not on an engine `ClipsDescendants`: a cropped rect is
	-- what every headless sweep, dump and audit in this repo actually reads, and a
	-- clip host would have left them all reporting the same out-of-bounds geometry
	-- while hiding it from the only eyes that can see a device.
	--
	-- SCOPED TO THE CASCADE, deliberately. A stack that declared no `shrinkWeight`
	-- opted into nothing and is untouched — cropping every overflowing stack in the
	-- library would be the silent re-flow of shipped screens the diagnostic below
	-- has always refused to be.
	local clipMain = shrinkOrder ~= nil and availMain < 0
	--[[ THE FINDINGS THIS CONTAINER FILES ABOUT ITSELF (T14). Neither carries a
		`filedBy`, so the solver's diagnostic replay keys them on `d.node` — this
		container, which is walked on every solve that reaches here — and drops the
		previous copy. The replay above returns before either condition is computed, so
		the finding TABLES are recorded and re-inserted verbatim; a slice of
		`ctx.diagnostics` would sweep in the measure-time findings the passes between
		these two sites file about DESCENDANTS. `nil` on every well-formed stack, which
		is nearly all of them. ]]
	local ownIssues: { any }? = nil
	if availMain < 0 and ctx.hiddenDepth == 0 then
		local issue = string.format(
			"content overflows this %s by %dpx on the main axis; it will paint outside its box "
				.. "(wrap it in a ScrollView, or give it room)",
			node.kind,
			-availMain
		)
		if shrinkOrder ~= nil then
			issue ..= string.format(
				" — every shrinkable child is already at its floor (layoutPriority order tried: %s), "
					.. "so the box CLIPPED the remaining %dpx",
				shrinkOrder,
				-availMain
			)
		end
		local finding = { node = node.id, issue = issue }
		table.insert(ctx.diagnostics, finding)
		ownIssues = { finding }
	end
	local remaining = math.max(0, availMain)
	local fillPx: { [number]: number } = {}
	if fillWeightSum > 0 then
		local acc = 0
		local shares = {}
		for idx, child in children do
			local mainDim = deps.mainDimOf(child, isH)
			if mainDim.type == "fill" then
				local exact = remaining * (mainDim.weight or 1) / fillWeightSum
				table.insert(shares, { i = idx, floor = math.floor(exact), rem = exact - math.floor(exact) })
				acc += math.floor(exact)
			end
		end
		table.sort(shares, function(a, b)
			return if a.rem ~= b.rem then a.rem > b.rem else a.i < b.i
		end)
		local leftover = remaining - acc
		for rank, share in shares do
			fillPx[share.i] = share.floor + (if rank <= leftover then 1 else 0) + spacerMinimum(children[share.i], isH)
		end
	end
	-- A FILL child's CROSS size was measured above against the whole inner extent,
	-- but the loop above just decided the much smaller main extent it actually
	-- gets. Re-measure it at that real size, or its box under-covers its own
	-- content: found live 2026-07-24, a fill column reported 39px of height while
	-- holding 77px of wrapped text, because it was measured at 400px wide and
	-- arranged at 196px. That gap is what the overflow diagnostic was reporting on
	-- the Hud column, and what left a scroll canvas unable to reach its own tail.
	if fillWeightSum > 0 then
		for idx, child in children do
			if deps.mainDimOf(child, isH).type ~= "fill" then
				continue
			end
			local m = margins[idx]
			local mainMargin = if isH then m.l + m.r else m.t + m.b
			local actualMain = math.max(0, (fillPx[idx] or 0) - mainMargin)
			local w, h =
				deps.measure(ctx, child, if isH then actualMain else innerW, if isH then innerH else actualMain)
			desired[idx] = { w = w, h = h }
		end
	end
	local baselineGroups = nil
	if hasBaseline then
		local sizes = {}
		for i, child in children do
			local m, d = margins[i], desired[i]
			local h = math.min(d.h, math.max(0, innerH - m.t - m.b))
			local align = baseline.alignment(node, child)
			if deps.dim(child, "h").type == "fill" or align == "stretch" then
				h = math.max(0, innerH - m.t - m.b)
			end
			sizes[i] = {
				w = if deps.mainDimOf(child, isH).type == "fill"
					then math.max(0, (fillPx[i] or 0) - m.l - m.r)
					else d.w,
				h = h,
				mt = m.t,
				mb = m.b,
			}
		end
		baselineGroups = baseline.line(deps.baseline, ctx, node, sizes, 1, #children)
	end
	-- MAIN-AXIS DISTRIBUTION (§2.6). The cursor used to be hard-anchored here —
	-- `local cursor = if isH then innerX else innerY` — so SpaceBetween/Around/
	-- Evenly could only be faked with hand-placed `Spacer`s between children, which
	-- a `UI.ForEach` list cannot do at all (its `row` returns exactly ONE
	-- blueprint). A tab bar whose tab count varies was inexpressible.
	--
	-- IT ACTS ON WHAT `fill` DID NOT TAKE. `remaining` is the leftover after the
	-- fill block above, so when `fillWeightSum > 0` there is nothing left and a
	-- non-"start" `distribute` is an authoring conflict — named, not ignored.
	local childCount = #children
	local lead, step = 0, 0
	local mode = node.distribute
	if mode ~= nil and mode ~= "start" then
		if fillWeightSum > 0 then
			if ctx.hiddenDepth == 0 then
				local finding = {
					node = node.id,
					issue = string.format(
						'distribute = "%s" has nothing to distribute on this %s: a `fill` child already takes '
							.. 'the whole leftover (drop the fill dimension, or leave distribute at "start")',
						mode,
						node.kind
					),
				}
				table.insert(ctx.diagnostics, finding)
				if ownIssues == nil then
					ownIssues = { finding }
				else
					table.insert(ownIssues :: { any }, finding)
				end
			end
		else
			lead, step = distributionOf(mode, remaining, childCount)
		end
	end
	-- the fractional part of `lead`/`step` is carried, never dropped per gap: the
	-- k-th gap's extra is `floor(k x step)`, so the whole leftover lands as whole
	-- pixels and the arrangement stays symmetric instead of drifting left
	local cursor = (if isH then innerX else innerY) + math.floor(lead)
	local gapsPlaced, gapExtraApplied = 0, 0
	-- did any child overhang its box (T14)? See the replay's `pNoted`.
	local noted = false
	--[[ THE AUDIT (ruling A-12), AND WHAT IT CAN AND CANNOT SEE. With `ctx.replayAudit`
		on, the arm above evaluated its gate and placed nothing, and this loop asserts
		every rect it WOULD have served against the one it just computed.

		IT DOES NOT RE-RECORD (fix round 1, I-2). The first version let the audited pass
		write `cmemo` at the tail, so the audited arm always held a payload one full pass
		old and could never be handed a payload a REPLAY had left — which is exactly the
		state Important 1's defect lived in. Skipping the record makes this arm a
		comparison of the payload AS THE LAST REPLAY LEFT IT against a fresh computation,
		which is the only shape that can catch a payload that drifted from the rect map.

		IT STILL PRICES ONE TICK. It says "the rects this payload would serve are the
		rects a full pass computes, right now"; it cannot say "and they will still be
		after two more replays". That class belongs to the differential's chained-replay
		drives (`tests/stack_replay.spec.luau`, the rotating-rows case and the oracle's
		consecutive cross drives), and the two are stated as a pair rather than one being
		read as covering the other. ]]
	local audit = ctx.replayAudit and replayable
	for idx, child in children do
		local m = margins[idx]
		local mainDim = deps.mainDimOf(child, isH)
		local crossDim = deps.dim(child, if isH then "h" else "w")
		local mainMargin = if isH then m.l + m.r else m.t + m.b
		local mainSize = if mainDim.type == "fill"
			then math.max(0, (fillPx[idx] or 0) - mainMargin)
			elseif shrunk[idx] ~= nil then shrunk[idx]
			else (if isH then desired[idx].w else desired[idx].h)
		-- clamp: margins taller/wider than the stack must not produce negative
		-- cross space (phase-4 layout fuzz, seed 2532671254)
		local crossAvail = math.max(0, (if isH then innerH else innerW) - (if isH then m.t + m.b else m.l + m.r))
		-- THE CROSS-AXIS ALIGNMENT LADDER, AND WHICH WORD DOES WHICH JOB.
		--
		-- `node.align` is CONTAINER-LEVEL (director review 2026-07-24). HStack/VStack
		-- have always accepted an `align` prop, but the solver only ever read
		-- `child.align` — so `UI.HStack({ align = "center" })` was ACCEPTED AND
		-- IGNORED, exactly what Milestone 0's strict authoring exists to prevent.
		-- There was no way to centre a row's children at all: every control row
		-- pinned its short children (a label, a value readout) to the TOP against its
		-- tall ones, which is why the Volume label and its "6" sat 13px above the
		-- midline of the -/+ buttons, and why the Brightness label and value sat
		-- above the slider track.
		--
		-- `child.align` — a stack child that is ITSELF a stack — is the historic
		-- per-child override, and it is where one word came to mean two things at
		-- once (§2.1): a nested `VStack{ align = "center" }` both centres its own
		-- children AND centres itself in this line. It still wins over the
		-- container's word, so nothing shipped moves.
		--
		-- `child.lineAlign` is the word for the SECOND job alone, and it outranks
		-- both. It is a shared BOX prop, so it is the only spelling that works on a
		-- LEAF — `align` is container-only and is refused on `UI.Text`/`Box`/
		-- `Spacer`/`Image`, which is why Facet had no leaf-level route to Roblox's
		-- `ItemLineAlignment` at all until this.
		local childAlign = child.lineAlign or child.align or node.align
		local crossSize = if crossDim.type == "fill" or childAlign == "stretch"
			then crossAvail
			else math.min(if isH then desired[idx].h else desired[idx].w, crossAvail)
		-- ASPECT against a FILL sibling (found live: a 16:9 media box resolved to
		-- ZERO height). `fill` has no measure-time size, so measure could only
		-- compute `0 / ratio`. Here both extents are finally known, so the aspect
		-- axis is derived from the other one — whichever of main/cross it lands on
		-- for this stack's orientation.
		local wDimC, hDimC = deps.dim(child, "w"), deps.dim(child, "h")
		if hDimC.type == "aspect" then
			local ratio = hDimC.ratio :: number
			if isH then -- width is the MAIN axis here
				crossSize = roundPx(mainSize / ratio)
			else
				mainSize = roundPx(crossSize / ratio)
			end
		elseif wDimC.type == "aspect" then
			local ratio = wDimC.ratio :: number
			if isH then
				mainSize = roundPx(crossSize * ratio)
			else
				crossSize = roundPx(mainSize * ratio)
			end
		end
		-- THE CROP (see `clipMain` above). The PAINTED extent stops at the box edge;
		-- the CURSOR still advances by the full one, because cropping is not
		-- re-flowing — pulling the later children back inside would move content the
		-- author placed, which is a different (and silent) change.
		local paintedMain = mainSize
		if clipMain then
			local start = cursor + (if isH then m.l else m.t)
			local edge = if isH then innerX + innerW else innerY + innerH
			paintedMain = math.clamp(edge - start, 0, mainSize)
		end
		local childRect: Rect
		if isH then
			local y = if baselineGroups and baseline.is(childAlign)
				then innerY + baselineGroups[childAlign].above - deps.baseline(
					ctx,
					child,
					paintedMain,
					crossSize,
					childAlign
				)
				else innerY + m.t + alignOffset(childAlign, crossAvail, crossSize)
			childRect = { x = cursor + m.l, y = y, w = paintedMain, h = crossSize }
			cursor += m.l + mainSize + m.r + gap
		else
			local x = innerX + m.l + alignOffset(childAlign, crossAvail, crossSize)
			childRect = { x = x, y = cursor + m.t, w = crossSize, h = paintedMain }
			cursor += m.t + mainSize + m.b + gap
		end
		if step > 0 and idx < childCount then
			gapsPlaced += 1
			local extra = math.floor(gapsPlaced * step)
			cursor += extra - gapExtraApplied
			gapExtraApplied = extra
		end
		if audit then
			local served = (if hot ~= nil then hot[idx] else nil) or pRect[idx]
			if
				served.x ~= childRect.x
				or served.y ~= childRect.y
				or served.w ~= childRect.w
				or served.h ~= childRect.h
			then
				error(
					`stack replay mismatch at {child.id}: served {served.x},{served.y},{served.w},{served.h} `
						.. `vs placed {childRect.x},{childRect.y},{childRect.w},{childRect.h}`
				)
			end
			ctx.replayChecks += 1
		end
		--[[ THE RECT THIS LOOP DECIDED, and the two facts about the child that decide it
			and that no measurement can see (T14). `childRect` is the SAME TABLE that
			reaches `out` and is frozen there, so this array holds references and never
			copies. `pFlag` marks the four shapes whose recorded pair is not the
			measurement that decided the rect: a `fill` or `hug` main child (measured
			again at its share, or at `left`), a `fill` cross child (which takes the line
			rather than its extent), an `aspect` child (whose axes derive from each other
			at placement) and a member of `shrunk` (measured again at the reduced offer). ]]
		if cmemo ~= nil then
			pRect[idx] = childRect
			pAl[idx] = childAlign
			local flag = 0
			if mainDim.type == "fill" or mainDim.type == "hug" then
				flag = 1
			end
			if crossDim.type == "fill" then
				flag += 2
			end
			if wDimC.type == "aspect" or hDimC.type == "aspect" then
				flag += 4
			end
			if shrunk[idx] ~= nil then
				flag += 8
			end
			pFlag[idx] = flag
		end
		if noteContainment(ctx, node, child, childRect, innerX, innerY, innerW, innerH, not isH) then
			noted = true
		end
		place(ctx, child, childRect, out)
	end
	--[[ THE KEY, WRITTEN LAST (T14) — after the loop that filled the arrays, so a throw
		inside it leaves a payload no gate can match rather than one that half-describes
		this pass. When `cmemo == nil` (a store-less or reuse-off build) nothing above
		was written and nothing here is: today's code exactly. Under `ctx.replayAudit`
		nothing here runs either, so the audited pass leaves the payload the last REPLAY
		left — see the audit block above for why that is the whole point. ]]
	if cmemo ~= nil and not ctx.replayAudit then
		cmemo.pCuts = measuredCuts
		cmemo.pN, cmemo.pKind = #children, node.kind
		cmemo.pStamp, cmemo.pScope, cmemo.pHidden = ctx.measureStamp, ctx.scopeKey, ctx.hiddenDepth
		cmemo.pInnerX, cmemo.pInnerY, cmemo.pInnerW, cmemo.pInnerH = innerX, innerY, innerW, innerH
		cmemo.pGap, cmemo.pAlign, cmemo.pDistribute = gap, node.align, node.distribute
		-- ...and the two container-level facts the arm cannot re-derive: whether the
		-- axis came out SHORT (which is when a `shrinkWeight` arriving on a dirty child
		-- would change every rect) and whether any child overhung its box.
		cmemo.pShort, cmemo.pNoted, cmemo.pIssues = availMain < 0, noted, ownIssues
		--[[ ...AND THE SEQUENCE THIS PAYLOAD'S INDICES DESCRIBE (Plan D, D2c).
			`render/layout_node` hands a container a fresh `kidToken` whenever it rebuilt
			the children array and the same one whenever it kept or patched it, so a later
			replay holding this token may trust `pIds`' indices without re-reading them.
			Recorded HERE, with the rest of the key, so a pass that never completed leaves
			a token no replay can match. It is `nil` on a store-less build, and the
			replay's gate requires a NON-NIL match for exactly that reason. ]]
		cmemo.pToken = node.kidToken
	end
end

return stack
