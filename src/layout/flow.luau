--!strict
--[[ flow — FLOW-WRAP's LINE PARTITION AND THE PLAN BOTH PASSES SHARE.

	Public interface, two entry points and one record:

	  `flow.partition(mains, innerMain, gap) -> lines`
	      the greedy line break, a pure function on three numbers.
	  `flow.plan(deps, ctx, node, isH, innerMain, innerCross, gap) -> plan`
	      the partition PLUS the child measurements it was derived from, cached on
	      `ctx.flowLines` and keyed by the box.

	`flow.Deps` is what it needs from the solver — `measure`, `dim`, `sides`,
	the same three `./grid` takes and for the same reason. It depends on nothing
	else: no require of its own, no state, no module-level mutable local at all.

	WHY IT IS ITS OWN FILE. `docs/handoff/SOURCE_CAP_LEDGER.md`'s solver row names
	this block by name as the next seam, and its trigger is a STATE rather than a
	number: "the next round that opens this file takes `flowPartition` + `flowPlan`
	FIRST". The one-way test that decides every split in this library is whether
	the block reads or WRITES a mutable upvalue of the file it is leaving, and this
	one reads three module-level functions and writes none — `flowPartition` was
	ALREADY exported as `solver.flowPartition` precisely because it reads no node
	and no `ctx`, which is the whole test written down before the split.

	THE TWO HALVES TRAVEL TOGETHER, and that is the constraint on touching this
	file. `flow.plan` owns the MEASUREMENT as well as the partition: the child
	extents ARE the partition's input, so deriving them in one pass and the lines
	in the other is the disagreement this shape exists to make impossible — this
	library's recurring defect, fixed four separate times, is a container that
	measured one shape and arranged another. Both solver passes call `flow.plan`
	and read its answer; there is no second copy and no per-pass branch. The
	`ctx.flowLines` cache is determinism and cost, NOT the guarantee: the single
	OWNER is.

	`ctx` AND `node` ARE TYPED `any` ON PURPOSE, the way `./shrink`, `./grid` and
	`./measure_facts` type them: the solver requires THIS module, so importing
	`solver.Ctx`/`solver.Node` back would be the require cycle the split exists to
	avoid, and re-declaring either schema here is the copy-goes-stale failure the
	seam is for.

	===== FLOW-WRAP (docs/plans/parity-round3.md, item A) =====================

	`UI.HStack{ wrap = true }` / `UI.VStack{ wrap = true }` reach the solver as the
	kinds `hwrap` / `vwrap`: Roblox's `UIListLayout.Wraps`, which Facet had no
	spelling for at all. It is a NATIVE branch and deliberately not a public
	`Layout` protocol — the round-3 Phase 0 verdict, whose one carrying reason is
	that the solver's three newest correctness mechanisms (the measure memo's cache
	key, the incremental-arrange reuse skip, the placement-prop audit) are each
	sound only as an ENUMERATION over a closed file, and consumer code inside the
	solve makes all three unenumerable at once.

	IT ADDS ONE PROP AND NO ALIGNMENT VOCABULARY, and that is a measurement rather
	than a preference. Probed live in Studio on 2026-08-13 (300x400 box, six 100x40
	items, so 80px of lines in 400px of container): wrapped lines are packed with
	NO extra space between them, and the whole BLOCK is placed on the cross axis by
	the container's existing alignment property — `Top` 0, `Center` 160, `Bottom`
	320, exactly. A ragged line put line 2 at y=90, its tallest item, not at 40. So

	    the block of lines  -> `align`      (Roblox VerticalAlignment/Horizontal…)
	    an item in its line -> `lineAlign`  (Roblox ItemLineAlignment)
	    along the main axis -> `distribute` (Roblox HorizontalFlex/VerticalFlex)

	map one-to-one onto words that already ship, and CSS's `align-content` (space
	between LINES) has no native counterpart to be parity with.

	ONE `gap`, BOTH AXES, for the same reason: `UIListLayout` has a single
	`Padding`, and a `rowGap` on `UI.HStack`/`UI.VStack` would be accepted and
	ignored on every stack that does not wrap — the §4 violation the placement
	audit exists to end. (`UI.Grid` has `rowGap` because its two pitches are
	genuinely different arithmetic; here they are the same number.)
]]

local flow = {}

-- What the plan needs from the solver, passed at every call. Typed `any` for the
-- node/ctx arguments for the reason the header states: importing the solver's
-- schemas back would be a require cycle.
--
-- `measure` arrives through a FORWARDER rather than by value, exactly as it does
-- in `./grid`'s `Deps`: it is one of the solver's forward declarations, assigned
-- ~1,500 lines below where the record is built, so a load-time record would
-- capture nil.
export type Deps = {
	measure: (ctx: any, node: any, maxW: number, maxH: number) -> (number, number),
	dim: (node: any, axis: string) -> any,
	sides: (margin: any) -> (number, number, number, number),
}

export type Line = { first: number, last: number, main: number, cross: number }

-- THE LINE PARTITION, AND IT IS A PURE FUNCTION ON PURPOSE.
--
-- `(childMainExtents, innerMain, gap) -> lines`, reading nothing else — no node,
-- no ctx, no clock. Two properties fall out of that and both are load-bearing:
-- measure and arrange cannot derive different partitions for the same numbers
-- (this library's four-times-fixed defect class, see `gridColumnPlan` in
-- `src/layout/grid.luau`), and the
-- partition is drivable by a headless fuzz with no tree at all
-- (`tests/flow_wrap.spec.luau`).
--
-- GREEDY, which is what the engine does and what CSS does: an item joins the
-- current line if it still fits with a gap in front of it, and starts a new one if
-- it does not. An item that fits on NO line still gets a line — of its own —
-- because the alternative is dropping it; `arrange` clamps it to the line and
-- files the diagnostic. An UNBOUNDED offer (`math.huge`, reachable from measure
-- and from a sideways scroller) yields exactly one line, which is the honest
-- answer: infinity cannot be wrapped.
function flow.partition(mains: { number }, innerMain: number, gap: number): { Line }
	local lines: { Line } = {}
	local first, used = 1, 0
	for i = 1, #mains do
		local m = mains[i]
		if i == first then
			used = m
		elseif used + gap + m <= innerMain then
			used += gap + m
		else
			table.insert(lines, { first = first, last = i - 1, main = used, cross = 0 })
			first = i
			used = m
		end
	end
	if #mains > 0 then
		table.insert(lines, { first = first, last = #mains, main = used, cross = 0 })
	end
	return lines
end

-- ...AND THE PLAN THE TWO PASSES SHARE, cached on the context and keyed by the
-- box, exactly as `src/layout/grid.luau`'s `gridColumnPlan` is and for the
-- identical reason.
--
-- It owns the measurement as well as the partition: the child extents ARE the
-- partition's input, so deriving them in one pass and the lines in the other is
-- the disagreement this shape exists to make impossible. Every extent here
-- INCLUDES the child's margins, because a margin occupies line space.
function flow.plan(
	deps: Deps,
	ctx: any,
	node: any,
	isH: boolean,
	innerMain: number,
	innerCross: number,
	gap: number
): any
	local key = `{innerMain}|{innerCross}|{gap}`
	local cached = ctx.flowLines[node.id]
	if cached ~= nil and cached.key == key then
		return cached.value
	end
	local children = node.children or {}
	local mains: { number } = {}
	local crosses: { number } = {}
	local sizes: { any } = {}
	for idx, child in children do
		local mt, mr, mb, ml = deps.sides(child.margin)
		local w, h =
			deps.measure(ctx, child, if isH then innerMain else innerCross, if isH then innerCross else innerMain)
		sizes[idx] = { w = w, h = h, mt = mt, mr = mr, mb = mb, ml = ml }
		-- A `fill` MAIN DIMENSION TAKES THE WHOLE LINE, and it has to be said here
		-- rather than left to `measure`. `resolveAxis` can only report CONTENT for a
		-- `fill` axis (the same fact the aspect-with-fill repair above `measure`
		-- documents), so a `fill`-width Box would enter the partition at ZERO and
		-- three of them would share one line at zero pixels each — a row of invisible
		-- children with nothing to say. "Fill" means "take the extent the parent
		-- offers", and on a wrapping stack the extent it offers IS the line, so it
		-- takes the line. `arrange` files the diagnostic that says so.
		local mainDim = deps.dim(child, if isH then "w" else "h")
		local ownMain = if isH then w + ml + mr else h + mt + mb
		mains[idx] = if mainDim.type == "fill" and innerMain ~= math.huge then innerMain else ownMain
		crosses[idx] = if isH then h + mt + mb else w + ml + mr
	end
	local lines = flow.partition(mains, innerMain, gap)
	local totalCross, maxMain = 0, 0
	for li, line in lines do
		local lineCross = 0
		for i = line.first, line.last do
			lineCross = math.max(lineCross, crosses[i])
		end
		line.cross = lineCross
		-- the lines are PACKED (the probe): one gap between them and nothing else
		totalCross += lineCross + (if li > 1 then gap else 0)
		maxMain = math.max(maxMain, line.main)
	end
	local value = { lines = lines, sizes = sizes, mains = mains, totalCross = totalCross, maxMain = maxMain }
	ctx.flowLines[node.id] = { key = key, value = value }
	return value
end

return flow
