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
	-- PASS 1: children with a definite main extent measure against the whole
	-- inner box, and consume it.
	for idx, child in children do
		local mt, mr, mb, ml = sides(child.margin)
		marginMain[idx] = if isH then ml + mr else mt + mb
		local childMainDim = dim(child, if isH then "w" else "h")
		if childMainDim.type == "fill" then
			fillWeightSum += childMainDim.weight or 1
		else
			local cw, ch = measure(ctx, child, innerMaxW, innerMaxH)
			mainSum += (if isH then cw + ml + mr else ch + mt + mb)
			crossOf[idx] = if isH then ch + mt + mb else cw + ml + mr
			if child.shrinkWeight ~= nil and child.shrinkWeight > 0 then
				local basis = shrinkBasis or {}
				basis[idx] = if isH then cw else ch
				shrinkBasis = basis
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
